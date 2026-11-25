#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_msg_archive.py — 消息池「归档动作」（T0r69）。

> **为什么文件名带 `_` 前缀**（不是 `check_*` 门禁尺，也非纯私有件）：
> `run_guards.py` 的宇宙排除族 `UNIVERSE_EXCLUDE_RE = (^_|...)` 让 `_` 开头脚本
> **不进电池宇宙**（2026-11-25 实测：改回 `msg_archive.py` 时 `--list` 立刻把它
> 列进「非判据」待加格清单），而本件是**离线可用的独立工具**、不是被判据面普查的尺
> ⇒ 走既有 `_` 前缀豁免，无需新加 `EXEMPT_RULES` 条目（AGENTS.md 判例-5 的既定出路）。
> 正确性由自身 `--selftest` 覆盖；人工跑法见 `scripts/README.md` 同名条目。

**这个脚本是什么**：把 `.fist-mbt/msg/inbox/` 里的一条消息**转发**出去，并按结果归档：

    转发成功            → 移入 `.fist-mbt/msg/processed/`（防重触发）
    重试耗尽仍失败      → 移入 `.fist-mbt/msg/.failed/`

它是设计真源 `fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md:50` 那条待办
（「归档动作：转发成功后消息移 processed/；失败重试 3 次后移 .failed/」）的落地件。

**为什么落在 fist-mbt 而不是 mcp-watcher**：真源 §分工判定（`:44`）称 mcp-watcher
「无需加核心功能，只加规则配置」，依据是「fs watch + webhook action（带 backoff）+
归档移动全部现成」。**该依据经实测不成立**（见本报告 §二）：

  1. `action/webhook.mbt` v1 **明确无重试循环**（红线注释：单发，重试留给上层）；
  2. `trash_file` 是 **native 专属**，而守护进程跑的是 **js 目标**
     （`scripts/daemon/watch_daemon.ps1` 启 `_build/js/debug/build/cmd/main/main.js`）
     ⇒ 运行态下 trash 恒返 `Err`（`trash_stub.mbt`）；
  3. 动作分发表的 kind 只有 `command`/`mcp_tool_call`/`webhook`/`internal`，
     **没有 archive/move 类**；`internal` 注册表只有 reload_config/pause_watch/
     resume_watch/log_event 四个 op。

⇒ 「归档动作」在当前树上是**不存在的一条可执行路径**。而 mcp-watcher 的 `command`
动作可以跑任意 argv ⇒ **本脚本就是那条路径**：watcher 侧只需一条规则配置
（真源 `:49`），**零源码改动**。

**复用口径**（不新造第二套词表/算法）：
  - 退避阶梯**逐字镜像** `mcp-watcher/action/webhook.mbt:21-23,65-80`：
    base=500ms、cap=8000ms、每重试翻倍、封顶、负 attempt 归零；
  - 移动语义**镜像** `action/trash_native.mbt` 的 `mkdir(recursive, allow_exist)`
    + `rename(replace)`：先建目录再原子改名；跨卷时 `os.replace` 抛错即退化为
    `shutil.move`（copy+unlink，**不原子**，与 T0r88 裁决一致）；
  - 同名冲突按内容 sha256 前 8 位去重，**不覆盖**（对齐 trash 分桶「可按桶还原」
    的可恢复精神，代价是去重而非时间戳桶）。

**消息格式**（真源 `:33-38`）：
    {"task_id":"T0r66","action":"execute","target":"svc-codearts",
     "endpoint":"http://127.0.0.1:18641/mcp","payload":{...}}
`endpoint` 缺失时用 `--endpoint` 兜底；两者都缺 ⇒ 拒绝出数（rc=1，不猜）。

子命令（全部离线可用，`--selftest` 全程 tempfile 沙箱、零网络零真仓读写）：
    run      处理 inbox（默认全部；--file 指定单条）
    --selftest  自证（含两处变异对照，见文末）

退出码：0=正常 / 1=操作失败或判据无法自证 / 2=argparse 拒绝（未知旗标、缺参数）/
        4=脚本自身异常（**绝不冒用 1**）。
"""
import argparse
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

PROG = "msg_archive.py"

# ---- 复用面：逐字镜像 mcp-watcher action/webhook.mbt -------------------------
BACKOFF_BASE_MS = 500          # WEBHOOK_BACKOFF_BASE_MS
BACKOFF_CAP_MS = 8000          # WEBHOOK_BACKOFF_CAP_MS
DEFAULT_RETRIES = 3            # 任务口径「重试 3 次」（首次之后的额外尝试次数）

# ---- 池分区：真源 draft:26 + scripts/git_pool_bridge.py:38 -------------------
MSG_DIR_DEFAULT = os.path.join(".fist-mbt", "msg")
INBOX_SUBDIR = "inbox"
PROCESSED_SUBDIR = "processed"
FAILED_SUBDIR = ".failed"       # 注意：active 计划写的是 `failed`（无点号），口径分裂见报告

MSG_SUFFIX = ".json"


class ToolError(Exception):
    """脚本自身故障（对应 rc=4，与操作失败 rc=1 分开）。"""


# --------------------------------------------------------------------------
# 纯函数（自检与复用面都吃这两个）
# --------------------------------------------------------------------------

def backoff_delay_ms(attempt):
    """重试第 `attempt` 次前应等待的毫秒数（镜像 webhook_backoff_delay_ms）。

    语义逐字对齐：base 起、每次翻倍、封顶 cap、attempt<0 归零、超上限按上限算。
    """
    n = attempt
    if n > DEFAULT_RETRIES + 1:
        n = DEFAULT_RETRIES + 1
    if n < 0:
        n = 0
    d = BACKOFF_BASE_MS
    for _ in range(n):
        d *= 2
    return min(d, BACKOFF_CAP_MS)


def unique_dst(dst, content_bytes):
    """同名已存在时不覆盖：插 `.<sha8>` 再试；仍撞则继续加长到唯一。"""
    if not os.path.exists(dst):
        return dst
    digest = hashlib.sha256(content_bytes).hexdigest()[:8]
    root, ext = os.path.splitext(dst)
    candidate = "%s.%s%s" % (root, digest, ext)
    if not os.path.exists(candidate):
        return candidate
    i = 1
    while True:
        candidate = "%s.%s-%d%s" % (root, digest, i, ext)
        if not os.path.exists(candidate):
            return candidate
        i += 1


def move_file(src, dst_dir, content_bytes=None):
    """把 `src` 移入 `dst_dir/`（镜像 trash 的 mkdir+rename 语义）。

    同卷 `os.replace` 原子；跨卷（Windows 不同盘符 / POSIX EXDEV）退化为
    `shutil.move`（copy+unlink，**不原子**）——这是 T0r88 已裁决的边界，不假装原子。
    """
    if content_bytes is None:
        with open(src, "rb") as f:
            content_bytes = f.read()
    os.makedirs(dst_dir, exist_ok=True)
    dst = unique_dst(os.path.join(dst_dir, os.path.basename(src)), content_bytes)
    try:
        os.replace(src, dst)
    except OSError:
        shutil.move(src, dst)
    return dst


# --------------------------------------------------------------------------
# 转发（可被注入 transport，自检才不必联网）
# --------------------------------------------------------------------------

def http_post_json(url, payload, timeout_s):
    """真转发：POST 一段 JSON。返回 (ok, status_or_None, detail)。"""
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            status = getattr(resp, "status", 200)
            body = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return False, e.code, "HTTP %s" % e.code
    except Exception as e:                       # 连接层/超时/DNS —— 可重试
        return False, None, "%s: %s" % (type(e).__name__, e)
    if not (200 <= status < 300):
        return False, status, "HTTP %s" % status
    try:
        doc = json.loads(body)
    except ValueError:
        return True, status, "非 JSON 响应按 2xx 计成功"
    if isinstance(doc, dict) and isinstance(doc.get("error"), dict):
        return False, status, "JSON-RPC error: %s" % json.dumps(doc["error"], ensure_ascii=False)[:200]
    return True, status, "ok"


def rpc_payload(msg):
    """把消息 JSON 包成 MCP `tools/call execute` 载荷（真源拓扑 `:14-15`）。"""
    name = msg.get("action") or "execute"
    args = msg.get("payload")
    if args is None:
        args = {k: v for k, v in msg.items() if k not in ("action", "endpoint", "target")}
    return {"jsonrpc": "2.0", "id": "1", "method": "tools/call",
            "params": {"name": name, "arguments": args}}


def process_message(path, msg_dir, transport=None, retries=DEFAULT_RETRIES,
                    timeout_s=10.0, dry_run=False, sleeper=None):
    """处理一条消息并归档。返回回执 dict（不落盘、由调用方打印）。"""
    transport = transport or http_post_json
    sleeper = sleeper or (lambda ms: None)

    with io.open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    try:
        msg = json.loads(raw)
    except ValueError as e:
        raise ToolError("消息不是合法 JSON: %s (%s)" % (path, e))
    if not isinstance(msg, dict):
        raise ToolError("消息顶层不是对象: %s" % path)

    endpoint = msg.get("endpoint") or None
    if not endpoint:
        return {"file": os.path.basename(path), "archived": None,
                "attempts": 0, "verdict": "no_endpoint",
                "detail": "消息无 endpoint 且未给 --endpoint ⇒ 拒绝出数"}

    payload = rpc_payload(msg)
    attempts = 0
    last_detail = ""
    max_attempts = 1 + max(0, retries)
    for attempt in range(max_attempts):
        if attempt > 0:
            sleeper(backoff_delay_ms(attempt))
        attempts += 1
        ok, status, detail = transport(endpoint, payload, timeout_s)
        last_detail = detail
        if ok:
            break

    inbox_path = path
    if dry_run:
        return {"file": os.path.basename(path), "archived": None, "attempts": attempts,
                "verdict": "dry_run", "detail": last_detail, "endpoint": endpoint}

    if ok:
        dst = move_file(inbox_path, os.path.join(msg_dir, PROCESSED_SUBDIR),
                        raw.encode("utf-8"))
        verdict = "processed"
    else:
        dst = move_file(inbox_path, os.path.join(msg_dir, FAILED_SUBDIR),
                        raw.encode("utf-8"))
        verdict = "failed"
    return {"file": os.path.basename(path), "archived": os.path.basename(dst),
            "attempts": attempts, "verdict": verdict, "detail": last_detail,
            "endpoint": endpoint}


def list_inbox(msg_dir):
    d = os.path.join(msg_dir, INBOX_SUBDIR)
    if not os.path.isdir(d):
        return []
    return sorted(n for n in os.listdir(d) if n.endswith(MSG_SUFFIX))


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog=PROG, description="消息池归档动作（T0r69）")
    p.add_argument("--msg-dir", default=MSG_DIR_DEFAULT,
                   help="消息池根（默认 %s）" % MSG_DIR_DEFAULT)
    p.add_argument("--file", default=None, help="只处理 inbox 下的这一条（basename）")
    p.add_argument("--endpoint", default=None, help="消息未带 endpoint 时的兜底 URL")
    p.add_argument("--retries", type=int, default=DEFAULT_RETRIES,
                   help="首次之后的额外重试次数（默认 %d）" % DEFAULT_RETRIES)
    p.add_argument("--timeout", type=float, default=10.0, help="单次 HTTP 超时秒")
    p.add_argument("--dry-run", action="store_true", help="照读照算但不移动文件")
    p.add_argument("--selftest", action="store_true", help="离线自证（tempfile 沙箱）")
    return p


def cmd_run(args):
    msg_dir = args.msg_dir
    if not os.path.isdir(os.path.join(msg_dir, INBOX_SUBDIR)):
        print("[msg_archive] inbox 不存在，跳过：%s" % os.path.join(msg_dir, INBOX_SUBDIR))
        return 0
    names = [args.file] if args.file else list_inbox(msg_dir)
    if args.file and args.file not in list_inbox(msg_dir):
        print("[FATAL] inbox 里没有 %s" % args.file, file=sys.stderr)
        return 1
    if not names:
        print("[msg_archive] inbox 空")
        return 0

    rc = 0
    for name in names:
        path = os.path.join(msg_dir, INBOX_SUBDIR, name)
        try:
            receipt = process_message(path, msg_dir, retries=args.retries,
                                      timeout_s=args.timeout, dry_run=args.dry_run)
        except ToolError as e:
            print("[FATAL] %s" % e, file=sys.stderr)
            return 4
        if args.endpoint and not receipt.get("endpoint"):
            # endpoint 兜底：消息自带优先，缺失时才用 --endpoint 重跑一次判定
            with io.open(path, "r", encoding="utf-8") as f:
                msg = json.load(f)
            msg.setdefault("endpoint", args.endpoint)
            try:
                receipt = process_message(path, msg_dir, retries=args.retries,
                                          timeout_s=args.timeout, dry_run=args.dry_run)
            except ToolError as e:
                print("[FATAL] %s" % e, file=sys.stderr)
                return 4
        print(json.dumps(receipt, ensure_ascii=False, sort_keys=True))
        if receipt.get("verdict") == "failed":
            rc = 1
    return rc


# --------------------------------------------------------------------------
# 自检（tempfile 沙箱；两处变异对照）
# --------------------------------------------------------------------------

def _selftest():
    ok = True

    def cell(name, cond, detail=""):
        nonlocal ok
        print("%s %s%s" % ("PASS" if cond else "FAIL", name,
                           "" if cond else "  << %s" % detail))
        if not cond:
            ok = False

    def make_pool(root):
        for sub in (INBOX_SUBDIR, PROCESSED_SUBDIR, FAILED_SUBDIR):
            os.makedirs(os.path.join(root, sub), exist_ok=True)

    def write_msg(root, name, obj):
        p = os.path.join(root, INBOX_SUBDIR, name)
        with io.open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(obj, ensure_ascii=False))
        return p

    def always_ok(url, payload, timeout):
        return True, 200, "ok"

    def always_fail(url, payload, timeout):
        return False, 500, "boom"

    # ---- 纯函数格：退避阶梯 -------------------------------------------------
    cell("backoff-attempt0-is-base", backoff_delay_ms(0) == 500, backoff_delay_ms(0))
    cell("backoff-attempt1-doubles", backoff_delay_ms(1) == 1000, backoff_delay_ms(1))
    cell("backoff-attempt3", backoff_delay_ms(3) == 4000, backoff_delay_ms(3))
    cell("backoff-cap-8000", backoff_delay_ms(9) == 8000, backoff_delay_ms(9))
    cell("backoff-negative-zero", backoff_delay_ms(-1) == 500, backoff_delay_ms(-1))

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        p = write_msg(root, "a.json", {"task_id": "T1", "endpoint": "http://x/mcp"})
        r = process_message(p, root, transport=always_ok)
        cell("success-moves-to-processed", r["verdict"] == "processed", r)
        cell("success-not-left-in-inbox", not os.path.exists(p))
        cell("success-target-exists",
             os.path.isfile(os.path.join(root, PROCESSED_SUBDIR, "a.json")))

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        p = write_msg(root, "b.json", {"task_id": "T2", "endpoint": "http://x/mcp"})
        seen = []

        def counting_fail(url, payload, timeout):
            seen.append(1)
            return False, 503, "down"

        r = process_message(p, root, transport=counting_fail, retries=3)
        cell("retries3-gives-4-attempts", r["attempts"] == 4, r["attempts"])
        cell("fail-moves-to-dot-failed", r["verdict"] == "failed", r)
        cell("failed-target-exists",
             os.path.isfile(os.path.join(root, FAILED_SUBDIR, "b.json")))
        cell("failed-name-kept", r["archived"] == "b.json", r["archived"])

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        p = write_msg(root, "c.json", {"task_id": "T3", "endpoint": "http://x/mcp"})
        r = process_message(p, root, transport=always_fail, dry_run=True)
        cell("dry-run-moves-nothing", os.path.isfile(p) and r["verdict"] == "dry_run", r)

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        p = write_msg(root, "d.json", {"task_id": "T4", "endpoint": "http://x/mcp"})
        r = process_message(p, root, transport=always_ok)
        # 造「processed/ 里已有同名件」的既成事实（现实来源：另一条同 task_id 的重复消息）
        dup = write_msg(root, "d.json", {"task_id": "T4dup", "endpoint": "http://x/mcp"})
        r2 = process_message(dup, root, transport=always_ok)
        cell("reprocess-target-collision-deduped",
             os.path.isfile(os.path.join(root, PROCESSED_SUBDIR, "d.json"))
             and r["archived"] == "d.json"
             and r2["archived"].startswith("d.") and r2["archived"] != r["archived"],
             (r["archived"], r2["archived"]))

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        p = write_msg(root, "e.json", {"task_id": "T5"})
        r = process_message(p, root, transport=always_ok)
        cell("no-endpoint-refuses", r["verdict"] == "no_endpoint" and r["attempts"] == 0, r)
        cell("no-endpoint-leaves-file", os.path.isfile(p))

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        bad = os.path.join(root, INBOX_SUBDIR, "bad.json")
        with io.open(bad, "w", encoding="utf-8") as f:
            f.write("{not json")
        try:
            process_message(bad, root, transport=always_ok)
            cell("bad-json-raises", False, "未抛错")
        except ToolError:
            cell("bad-json-raises", True)

    # ---- 变异对照①：把翻倍去掉（退回「固定基数」旧形状），锁必须翻红 --------
    def buggy_delay(attempt):
        return BACKOFF_BASE_MS

    cell("M1-doubling-lock-sensitive",
         buggy_delay(1) != backoff_delay_ms(1) and backoff_delay_ms(1) == 1000,
         (buggy_delay(1), backoff_delay_ms(1)))

    # ---- 变异对照②：把「重试 3 次」写成「总共 1 次尝试」，锁必须翻红 --------
    def buggy_attempts(retries):
        return 1

    with tempfile.TemporaryDirectory() as root:
        make_pool(root)
        p = write_msg(root, "f.json", {"task_id": "T6", "endpoint": "http://x/mcp"})
        n = [0]

        def cnt(url, payload, timeout):
            n[0] += 1
            return False, 500, "x"

        r = process_message(p, root, transport=cnt, retries=3)
        cell("M2-retry-count-lock-sensitive",
             buggy_attempts(3) != r["attempts"] and r["attempts"] == 4,
             (buggy_attempts(3), r["attempts"]))

    # ---- 参数面：未知旗标必拒（rc=2） --------------------------------------
    rc_unknown = 1
    try:
        build_parser().parse_args(["--definitely-not-real"])
    except SystemExit as e:
        rc_unknown = e.code
    cell("unknown-flag-rc2", rc_unknown == 2, rc_unknown)

    print("SELFTEST %s" % ("OK" if ok else "FAILED"))
    return 0 if ok else 1


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.selftest:
        return _selftest()
    return cmd_run(args)


if __name__ == "__main__":
    sys.exit(main())
