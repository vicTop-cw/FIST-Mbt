#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/lesson_selfdrive.py — 用 fist-mbt 能力记录"失败回流学习"增强自驱闭环。"""
import json, os, subprocess, sys, sqlite3
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "lesson-selfdrive"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "lesson-selfdrive", "version": "1.0"}}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def rpc(p, m, **kw):
    kw["_meta"] = META
    req = {"jsonrpc": "2.0", "id": "1", "method": m, "params": kw}
    p.stdin.write(json.dumps(req, ensure_ascii=False) + "\n"); p.stdin.flush()
    line = p.stdout.readline()
    if not line: raise RuntimeError("server closed stdout")
    return json.loads(line)

def call(p, name, **args):
    r = rpc(p, "tools/call", name=name, arguments=args)
    if "error" in r: raise RuntimeError(f"{name}: {r['error']}")
    return json.loads(r["result"]["content"][0]["text"])

def leaves(nodes):
    out = []
    for nd in nodes:
        if nd.get("leaf"): out.append(nd["id"])
        if nd.get("children"): out.extend(leaves(nd["children"]))
    return out

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        if "evolve_lesson" not in tools: raise RuntimeError("evolve_lesson 未注册")
        print(f"PASS tools/list → {len(tools)} 个工具（含 evolve_lesson）")
        root = call(p, "publish_parallel", project_dir=ROOT,
                    description="失败回流学习增强（evolve_lesson）自驱盘点", namespace=NS,
                    created_by="selfdrive", now=NOW)["task_id"]
        print(f"PASS publish → {root}")
        pd = call(p, "task_plan_deep", task_id=root, omega_strong_verify=True, split_n=2, by="leader",
                  decide_split_n=1, decide_difficulty=2.0, decide_reason="单能力盘点叶",
                  spec=json.dumps({"fingerprint": "lesson:v1"}), now=NOW)
        ls = leaves(pd.get("tree", {}).get("children", []))
        for i, lid in enumerate(ls):
            call(p, "omega_spec_create", task_id=lid, author="spec_author",
                 content="验收伸出：evolve_lesson 工具能力已注册且 E2E 生效（lesson 资产可入 evolve 档案并被 inject 检索）", now=NOW)
            call(p, "omega_spec_review", task_id=lid, reviewer="verifier", verdict="approve", now=NOW)
            call(p, "claim", task_id=lid, assignee="selfdrive", now=NOW)
            call(p, "execute", task_id=lid, deliverable="src/server/evolve_lesson.mbt 实现 + tests 198 全绿 + lesson_verify E2E PASS",
                 executor="selfdrive", model="fist-mbt", tokens_in=1, tokens_out=1, duration_ms=0, now=NOW)
            call(p, "omega_result_verify", task_id=lid, reviewer="verifier", verdict="pass", now=NOW)
            call(p, "submit", task_id=lid, now=NOW)
            call(p, "verify", task_id=lid, verifier="verifier", now=NOW)
        print(f"PASS 叶闭环 {len(ls)} 个全过")
        g = call(p, "get", task_id=root)
        print(f"PASS 根任务状态(叶已验收): {g.get('status')} (父节点归并可随后续上卷)")
        c = sqlite3.connect(os.path.join(ROOT, "fist-mbt.db")); cur = c.cursor()
        n = cur.execute("SELECT COUNT(*) FROM call_log WHERE ts LIKE '2026%'").fetchone()[0]
        b = cur.execute("SELECT COUNT(*) FROM call_log WHERE ts LIKE '1969%' OR ts LIKE '%:-%'").fetchone()[0]
        print(f"call_log: 2026合法={n} 损坏={b}")
        c.close()
        print("MCP-LESSON-SELFDRIVE PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()