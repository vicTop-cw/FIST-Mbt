#!/usr/bin/env python3
"""autoplan —— 计划投递 / 裁决清单 / 裁决反馈（协议 v1）

协议：docs/plans/2026-11-22-autoplan.md。全部经常驻服务 HTTP 面操作，
零核心改动（P0 红线）。

用法（cwd 须为 FIST-Mbt 仓根，服务默认 svc-atomcode @18640）：
  python scripts/autoplan.py drop <计划.md>     # 计划拆解入池（工作项+裁决项）
  python scripts/autoplan.py decisions          # 列出未闭环的 [裁决] 清单
  python scripts/autoplan.py resolve <task_id> "<所选选项与反馈>"
                                                 # verify 闭环 + 裁决落 laya-inbox
"""

import argparse
import json
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NS = "autoplan"
MANIFEST = ROOT / ".fist-mbt" / "data" / "autoplan-manifest.jsonl"
TERMINAL = ("已完成", "已归档", "已暂停")


def load_key() -> str:
    return (ROOT / ".fist-mbt" / "data" / "svc-atomcode.apikey").read_text(encoding="utf-8").strip()


def call(base: str, key: str, name: str, arguments: dict) -> dict:
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": name, "arguments": arguments}}
    req = urllib.request.Request(f"{base}/mcp", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "X-API-Key": key})
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.loads(r.read().decode())
    if "error" in resp:
        raise RuntimeError(resp["error"].get("message", "")[:200])
    return json.loads(resp["result"]["content"][0]["text"])


def parse_plan(path: str):
    """协议 §2：'- [ ] ' = 工作项；'? ' = 裁决项（问题 | 选项：A / B | 建议：C）。"""
    items = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("- [ ] "):
            items.append({"kind": "work", "text": line[len("- [ ] "):].strip()})
        elif line.startswith("? "):
            items.append({"kind": "decision", "text": line[len("? "):].strip()})
    return items


def cmd_drop(base, key, plan_path: str) -> None:
    items = parse_plan(plan_path)
    if not items:
        raise SystemExit("计划文件没有可执行项（- [ ] 工作项 / ? 裁决项）")
    seen = MANIFEST.read_text(encoding="utf-8").splitlines() if MANIFEST.exists() else []
    seen_ids = {json.loads(l).get("task_id") for l in seen if l.strip()}
    for it in items:
        desc = it["text"]
        if it["kind"] == "decision":
            desc = "[裁决] " + desc
        inner = call(base, key, "publish", {
            "project_dir": ".", "namespace": NS,
            "description": desc, "created_by": "human_steward"})
        tid = inner.get("task_id") or inner.get("id") or ""
        print(f"published: {tid} [{it['kind']}] {it['text'][:60]}")
        with MANIFEST.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"task_id": tid, "kind": it["kind"],
                                "title": it["text"][:120]}, ensure_ascii=False) + "\n")
    print(f"drop 完成：{len(items)} 项（清单 {MANIFEST.name}）")


def cmd_decisions(base, key) -> None:
    if not MANIFEST.exists():
        raise SystemExit("清单为空：先 drop 一份计划")
    open_n = 0
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        e = json.loads(line)
        if e.get("kind") != "decision":
            continue
        inner = call(base, key, "get", {"task_id": e["task_id"], "namespace": NS})
        status = inner.get("status", "")
        if status in TERMINAL:
            continue
        open_n += 1
        print(f"[待裁决] {e['task_id']} {e['title']}\n    当前状态：{status}")
    print(f"裁决清单：{open_n} 项未闭环（resolve <task_id> \"<选项与反馈>\" 落定）")


def cmd_resolve(base, key, task_id: str, choice: str) -> None:
    # 裁决 = 任务闭环：按九态机宽容推进（已过的态跳过，其它错误如实抛出）
    steps = [
        ("claim", {"task_id": task_id, "assignee": "atomcode", "namespace": NS}),
        ("execute", {"task_id": task_id, "namespace": NS, "deliverable": choice}),
        ("submit", {"task_id": task_id, "deliverable": choice, "namespace": NS}),
    ]
    for name, args in steps:
        try:
            call(base, key, name, args)
        except RuntimeError as e:
            msg = str(e)
            if "非法迁移" in msg or "已在运行" in msg:
                continue  # 状态机兼容推进：该步已发生过
            raise
    r = call(base, key, "verify", {"task_id": task_id, "verifier": "human_steward",
                                   "namespace": NS})
    inbox = ROOT / ".fist-mbt" / "data" / "laya-inbox.jsonl"
    with inbox.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"type": "autoplan_decision", "task_id": task_id,
                            "choice": choice, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ",
                                                                  time.gmtime())},
                           ensure_ascii=False) + "\n")
    print(f"resolve: {task_id} -> {r.get('status', 'ok')}｜裁决已记 laya-inbox：{choice[:80]}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--service", default="http://127.0.0.1:18640")
    sub = ap.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("drop")
    d.add_argument("plan")
    sub.add_parser("decisions")
    r = sub.add_parser("resolve")
    r.add_argument("task_id")
    r.add_argument("choice")
    a = ap.parse_args()
    base, key = a.service, load_key()
    if a.cmd == "drop":
        cmd_drop(base, key, a.plan)
    elif a.cmd == "decisions":
        cmd_decisions(base, key)
    else:
        cmd_resolve(base, key, a.task_id, a.choice)


if __name__ == "__main__":
    main()
