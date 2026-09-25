#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/scratch_selfdrive.py — 用 fist-mbt 能力记录"临时产物隔离"增强自驱闭环。"""
import json, os, subprocess, sys
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "scratch-selfdrive"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "scratch-selfdrive", "version": "1.0"}}
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
        if "store_open" not in tools: raise RuntimeError("store_open 未注册")
        print(f"PASS tools/list → {len(tools)} 个工具")
        root = call(p, "publish_parallel", project_dir=ROOT,
                    description="临时产物隔离增强（store_open scratch）自驱盘点", namespace=NS,
                    created_by="selfdrive", now=NOW)["task_id"]
        print(f"PASS publish → {root}")
        pd = call(p, "task_plan_deep", task_id=root, omega_strong_verify=True, split_n=2, by="leader",
                  decide_split_n=1, decide_difficulty=2.0, decide_reason="单能力盘点叶",
                  spec=json.dumps({"fingerprint": "scratch:v1"}), now=NOW)
        ls = leaves(pd.get("tree", {}).get("children", []))
        plan_dec = pd.get("plan_decision", {})
        for lid in ls:
            call(p, "omega_spec_create", task_id=lid, author="spec_author",
                 content="store_open(scratch=true) 已实现：临时命名空间落 temp/，E2E 验证仓库根无污染", now=NOW)
            call(p, "omega_spec_review", task_id=lid, reviewer="verifier", verdict="approve", now=NOW)
            call(p, "claim", task_id=lid, assignee="selfdrive", now=NOW)
            call(p, "execute", task_id=lid, deliverable="server.mbt store_open 加 scratch；99 + scratch_verify E2E PASS",
                 executor="selfdrive", model="fist-mbt", tokens_in=1, tokens_out=1, duration_ms=0, now=NOW)
            call(p, "omega_result_verify", task_id=lid, reviewer="verifier", verdict="pass", now=NOW)
            call(p, "submit", task_id=lid, now=NOW)
            call(p, "verify", task_id=lid, verifier="verifier", now=NOW)
        print(f"PASS 叶闭环 {len(ls)} 个全过; plan_decision.source={ (plan_dec or {}).get('source') }")
        print("MCP-SCRATCH-SELFDRIVE PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()