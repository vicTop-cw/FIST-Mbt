# -*- coding: utf-8 -*-
"""多租户库级物理隔离闭环探针（stage1：claim/execute/submit 带 namespace 路由）。
验证：
  C1 业务工具带 namespace 路由到独立库（probe-a.db），不在默认库落行
  C2 默认库（fist-mbt.db）无该任务行（物理隔离）
  C3 任务全流程 publish->claim->execute->submit 在 ns 库内正常流转
  C4 负例：不存在任务在 ns 库报 not found（证明路由真实生效）
"""
import sys, os, json, shutil, tempfile as tf

# BUG-381：与 fist_mbt_mcp_client 同款——本机 cp936 下结论行的中文/符号不得崩。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import fist_mbt_mcp_client as fist_client
# 默认用发布版；本地验证时改指 _build 产物（先 moon build --target js cmd/cli && python scripts/patch_esm_main.py）
fist_client.JS = os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js")
from fist_mbt_mcp_client import FistClient

BASE = os.path.join(ROOT, "temp", "ns-route-probe")
if os.path.isdir(BASE):
    shutil.rmtree(BASE, ignore_errors=True)
os.makedirs(os.path.join(BASE, "box"))

GREEN = "\033[92m"; RED = "\033[91m"; RESET = "\033[0m"
results = []

def check(name, ok, detail=""):
    color = GREEN if ok else RED
    results.append(ok)
    print(f"{color}{name:<42}{'GREEN' if ok else 'RED'}{RESET}  {detail}"[:300])

def q(sqlite_path, sql):
    import sqlite3
    con = sqlite3.connect(sqlite_path)
    try:
        cur = con.execute(sql)
        rows = cur.fetchall()
        return rows
    finally:
        con.close()

fc = FistClient(cwd=os.path.join(BASE, "box"))
try:
    r = fc.call("store_open", {"namespace": "probe-a"})
    check("store_open(probe-a)", not r.get("error"), str(r.get("text", ""))[:120])

    r = fc.call("publish", {
        "project_dir": ".",
        "description": "ns-probe-a-task stage1",
        "created_by": "human_steward",
        "namespace": "probe-a",
    })
    txt = r.get("text", "")
    try:
        tid = json.loads(txt)["task_id"]
    except Exception:
        tid = txt.strip().strip('"')
    check("publish(ns=probe-a)", (not r.get("error")) and bool(tid), str(txt)[:120])

    r = fc.call("claim", {"task_id": tid, "assignee": "marvis-main", "namespace": "probe-a"})
    check("claim(ns=probe-a)", not r.get("error"), str(r.get("text", ""))[:120])

    r = fc.call("execute", {"task_id": tid, "deliverable": "stage1 probe", "namespace": "probe-a"})
    check("execute(ns=probe-a)", not r.get("error"), str(r.get("text", ""))[:120])

    r = fc.call("submit", {"task_id": tid, "namespace": "probe-a"})
    check("submit(ns=probe-a)", not r.get("error"), str(r.get("text", ""))[:120])

    # C1: ns 库文件存在
    ns_db = os.path.join(BASE, "box", "probe-a.db")
    check("C1 ns库文件存在", os.path.isfile(ns_db), ns_db)

    # C2: 默认库无该任务行
    default_db = os.path.join(BASE, "box", "fist-mbt.db")
    if os.path.isfile(default_db):
        rows = q(default_db, f"SELECT id, ns, status FROM tasks WHERE id='{tid}'")
        check("C2 默认库无该任务行", len(rows) == 0, f"default rows={rows}")
    else:
        check("C2 默认库无该任务行", True, "默认库未创建（未污染）")

    # C1b: ns 库有该任务行且 ns 正确、状态已流转到待验收
    rows = q(ns_db, f"SELECT id, ns, status FROM tasks WHERE id='{tid}'")
    ok = len(rows) == 1 and rows[0][1] == "probe-a" and rows[0][2] == "待验收"
    check("C3 ns库任务行存在且状态待验收", ok, f"rows={rows}")

    # C4: 负例 - 不存在的任务报 not found（证明路由到 ns 库而非默认库）
    r = fc.call("claim", {"task_id": "T-no-such-task", "assignee": "marvis-main", "namespace": "probe-a"})
    txt = str(r.get("text", ""))
    ok = r.get("error") or ("not found" in txt.lower() or "不存在" in txt or "未找到" in txt)
    check("C4 负例not found", ok, txt[:120])
finally:
    fc.close()

ok_count = sum(1 for x in results if x is True)
print("\n" + ("ALL GREEN" if ok_count == len(results) and results else f"{ok_count}/{len(results)} GREEN"))
sys.exit(0 if ok_count == len(results) and results else 1)
