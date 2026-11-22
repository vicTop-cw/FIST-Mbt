#!/usr/bin/env python3
"""butler_patrol —— 超级管家巡检只读盘点工具（无凭据、无写入）

一次性汇总巡检前三步的读数：
  1) 四常驻服务健康面（/health，公开端点）
  2) laya-inbox.jsonl 尾部（服务上线通知）
  3) svc-atomcode 任务池状态分布 + 超 24h 未动项（本地 sqlite 直读）

纯读：不发任何写请求、不读任何凭据文件、不改任何状态。
退出码：任一服务不活体 ⇒ 1，其余（含卡项/待领取）只报告不失败。

用法：
  python scripts/butler_patrol.py                 # 标准四服务
  python scripts/butler_patrol.py 18645:svc-webai # 追加清单外服务（端口:id）
"""

import json
import sqlite3
import sys
import urllib.request
from pathlib import Path
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent          # scripts/ → 仓根
DATA = ROOT / ".fist-mbt" / "data"
INBOX = DATA / "laya-inbox.jsonl"
DB = DATA / "svc-atomcode.db"

SERVICES = [("18640", "svc-atomcode"), ("18641", "svc-codearts"),
            ("18643", "svc-freebuff"), ("18644", "svc-marvis")]


def health(port: str, service_id: str) -> bool:
    try:
        with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/health", timeout=5) as r:
            info = json.loads(r.read().decode())
        alive = info.get("alive") is True
        print(f"  [{'OK ' if alive else 'DEAD'}] {info.get('service_id', service_id)}"
              f":{port} pid={info.get('pid')}")
        return alive
    except Exception as e:
        print(f"  [DEAD] {service_id}:{port}（{e}）")
        return False


def inbox_tail(n: int = 3) -> int:
    if not INBOX.is_file():
        print("  laya-inbox.jsonl 不存在")
        return 0
    lines = INBOX.read_text(encoding="utf-8", errors="replace").splitlines()
    print(f"  共 {len(lines)} 行，尾部 {min(n, len(lines))} 行：")
    for line in lines[-n:]:
        try:
            ev = json.loads(line)
            # autoplan_decision 等事件无 service_id，补决策摘要（截 60 字）
            detail = str(ev.get("choice") or ev.get("note") or "")[:60]
            print(f"    {ev.get('at', '?')} {ev.get('type', '?')} "
                  f"{ev.get('service_id', '')} {detail}")
        except json.JSONDecodeError:
            print(f"    <非 JSON 行> {line[:80]}")
    return len(lines)


def pool_summary() -> None:
    con = sqlite3.connect(str(DB))
    try:
        rows = con.execute("select status, count(*) from tasks group by status")
        dist = ", ".join(f"{s}={c}" for s, c in rows)
        total = con.execute("select count(*) from tasks").fetchone()[0]
        stale = con.execute(
            "select id, status from tasks "
            "where status in ('执行中','待验收') "
            "and updated_at < datetime('now','-24 hours')").fetchall()
    finally:
        con.close()
    print(f"  总数={total}（{dist}）")
    if stale:
        print(f"  [!]{len(stale)} 项超 24h 未动：{stale}")
    else:
        print("  无执行中/待验收超 24h 卡项")


def selftest() -> None:
    """判据自证：缺失收件箱/死端口两格不崩、给读数（零网络依赖）。"""
    global INBOX
    saved = INBOX
    INBOX = DATA / "__no_such_inbox__.jsonl"
    try:
        n = inbox_tail()
        assert n == 0, f"缺失收件箱应计 0 行，实得 {n}"
        assert health("1", "svc-selftest-deadport") is False, "死端口应判 DEAD"
    finally:
        INBOX = saved
    print("selftest OK：缺失收件箱/死端口两格自证成立")


def main() -> None:
    if "--selftest" in sys.argv:
        selftest()
        return
    extra = [a.split(":") for a in sys.argv[1:] if ":" in a]
    print("== 1) 服务健康 ==")
    # 逐个必查：all() 生成器短路会漏检首个挂掉之后的成员（首轮实证）
    results = [health(p, s) for p, s in SERVICES + extra]
    ok = all(results)
    print("== 2) laya-inbox ==")
    inbox_tail()
    print("== 3) 任务池 svc-atomcode ==")
    pool_summary()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
