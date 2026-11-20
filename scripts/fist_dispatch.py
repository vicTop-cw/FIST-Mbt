#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""EP-03 fist_dispatch.py -- 任务域写事件 -> 自动派发驱动（watcher command 动作调用）

触发模型（零引擎改动）：fist-mbt 每次任务域写（publish/claim/verify/...）
都会 touch SQLite db 文件 mtime -> watcher 监听 db 文件变更 -> 本脚本做
幂等派发判定。规则模式精确钉到单一 ns 库（如 .fist-mbt/data/fist-self-tidy.db*，
WAL 模式下写落在 -wal，故带 * 通配 -wal/-shm）。

两种模式：
  stale: task_stats 检测超龄任务（updated_at 距今 > stale_days 天）
         -> 逐模板 dup-check（task_query 同描述且待领取数=0 才发）-> publish 补发
  chain: task_events 轮询被监视任务的 verified 事件（cursor 文件去重）
         -> publish 下一单（同描述任意状态已存在则跳过）

幂等保证：dup-check 是真正的收敛闸（cursor 文件丢失最坏导致一次重查，
不会重发）；cursor 只是降噪。重复触发必然收敛，不产生任务风暴。

输出：stdout 单行 JSON（ensure_ascii），形如
  {"mode":"stale","ns":"x","stale":2,"dispatched":["..."],"skipped":1,"checked":3}
供 acceptance 门断言（stdout_contains: ["dispatched"]）。

退出码：0 = 正常（含"无派发"）；1 = 工具调用失败；2 = 参数/配置错误。
"""

import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIST = os.path.join(HERE, "fist.py")
CALL_TIMEOUT_SECS = 120


def call_tool(tool, flags):
    """调 fist.py call <tool>；stdout 可能混入 [fist.py] 构建日志行
    （BUG-32 自动构建），取最后一个非空行解析 JSON。"""
    argv = [sys.executable, FIST, "call", tool] + list(flags)
    try:
        r = subprocess.run(
            argv, capture_output=True, text=True, timeout=CALL_TIMEOUT_SECS
        )
    except subprocess.TimeoutExpired:
        print("fist_dispatch: tool timeout: %s" % tool, file=sys.stderr)
        sys.exit(1)
    lines = [ln.strip() for ln in (r.stdout or "").splitlines() if ln.strip()]
    if r.returncode != 0 or not lines:
        print(
            "fist_dispatch: tool failed rc=%s out=%r err=%r"
            % (r.returncode, (r.stdout or "")[-200:], (r.stderr or "")[-200:]),
            file=sys.stderr,
        )
        sys.exit(1)
    payload = lines[-1]
    try:
        return json.loads(payload)
    except ValueError:
        print("fist_dispatch: bad json from %s: %r" % (tool, payload[:200]),
              file=sys.stderr)
        sys.exit(1)


def publish(ns, tpl):
    """发布一单。publish 工具仅收 project_dir/namespace/description
    （0.3.15 实测定论：--priority 不在其 schema）。"""
    flags = [
        "--project-dir", tpl.get("project_dir", "."),
        "--namespace", ns,
        "--description", tpl["description"],
    ]
    return call_tool("publish", flags)


def dup_count(ns, description, only_pending):
    """同描述任务计数。stale 补发只看待领取（防止已领取的补发单重复补）；
    chain 派发看全部状态（每步只发一次，归档后也不重发）。"""
    flags = ["--namespace", ns, "--keyword", description]
    if only_pending:
        flags += ["--status", "待领取"]
    return call_tool("task_query", flags).get("filtered", 0)


def run_stale(ns, stale_days, templates):
    stats = call_tool(
        "task_stats", ["--namespace", ns, "--stale-days", str(stale_days)]
    )
    stale = stats.get("stale", {})
    count = stale.get("count", 0) if isinstance(stale, dict) else 0
    dispatched, skipped = [], 0
    if count > 0:
        for tpl in templates:
            desc = tpl.get("description", "")
            if not desc:
                skipped += 1
                continue
            if dup_count(ns, desc, only_pending=True) > 0:
                skipped += 1
                continue
            publish(ns, tpl)
            dispatched.append(desc)
    print(json.dumps({
        "mode": "stale", "ns": ns, "stale": count,
        "dispatched": dispatched, "skipped": skipped,
    }))
    return 0


def _verified_newer(events, cursor_ts):
    """返回 (有新 verified 事件, 事件流里最新 ts)。ISO 同构串字典序=时间序。"""
    newest_ts = cursor_ts
    hit = False
    for ev in events or []:
        ts = ev.get("ts", "")
        if ts and ts > newest_ts:
            newest_ts = ts
        if ev.get("event") == "verified" and ts and ts > cursor_ts:
            hit = True
    return hit, newest_ts


def run_chain(ns, chains, cursor_dir):
    os.makedirs(cursor_dir, exist_ok=True)
    dispatched, skipped = [], 0
    for chain in chains:
        watch_id = chain.get("watch", "")
        tpl = chain.get("publish", {})
        desc = tpl.get("description", "")
        if not watch_id or not desc:
            skipped += 1
            continue
        ev = call_tool(
            "task_events",
            ["--namespace", ns, "--task-id", watch_id, "--limit", "5"],
        )
        cursor_file = os.path.join(
            cursor_dir, "%s_%s.json" % (ns.replace("/", "_"), watch_id)
        )
        cursor_ts = ""
        if os.path.exists(cursor_file):
            try:
                with open(cursor_file, "r", encoding="utf-8") as f:
                    cursor_ts = json.load(f).get("last_ts", "")
            except (ValueError, OSError):
                cursor_ts = ""
        hit, newest_ts = _verified_newer(ev.get("events"), cursor_ts)
        if not hit:
            continue
        if dup_count(ns, desc, only_pending=False) > 0:
            skipped += 1
        else:
            publish(ns, tpl)
            dispatched.append(desc)
        with open(cursor_file, "w", encoding="utf-8") as f:
            json.dump({"last_ts": newest_ts}, f)
    print(json.dumps({
        "mode": "chain", "ns": ns,
        "dispatched": dispatched, "skipped": skipped,
    }))
    return 0


def main():
    ap = argparse.ArgumentParser(description="fist task-domain auto dispatch")
    ap.add_argument("--ns", default="fist-self-tidy")
    ap.add_argument("--mode", choices=["stale", "chain"], default="stale")
    ap.add_argument("--stale-days", type=int, default=7)
    ap.add_argument(
        "--tasks", required=True,
        help='JSON array: stale=[{description,project_dir?}]; '
             'chain=[{watch,publish:{description,project_dir?}}]',
    )
    ap.add_argument(
        "--cursor-dir",
        default=os.path.join(HERE, "..", "temp", "fist_dispatch"),
    )
    a = ap.parse_args()
    try:
        tasks = json.loads(a.tasks)
    except ValueError:
        print("fist_dispatch: --tasks is not valid JSON", file=sys.stderr)
        sys.exit(2)
    if not isinstance(tasks, list):
        print("fist_dispatch: --tasks must be a JSON array", file=sys.stderr)
        sys.exit(2)
    if a.mode == "stale":
        sys.exit(run_stale(a.ns, a.stale_days, tasks))
    sys.exit(run_chain(a.ns, tasks, a.cursor_dir))


if __name__ == "__main__":
    main()
