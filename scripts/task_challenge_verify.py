#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/task_challenge_verify.py — 验证 task_challenge Challenger 进阶变体 E2E（tools/list=77；scratch 隔离）。"""
import json, os, subprocess
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "challenge-verify"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "task-challenge-verify", "version": "1.0"}}
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

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具")
        assert "task_challenge" in tools, "缺少 task_challenge"
        call(p, "store_open", namespace=NS, scratch=True, now=NOW)
        # 完成一条任务后发起挑战
        r = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="实现一个基础计算器", created_by="human_steward", now=NOW)
        tid = r["task_id"]
        call(p, "claim", task_id=tid, assignee="exec_1", now=NOW)
        call(p, "execute", task_id=tid, deliverable="done", now=NOW)
        call(p, "submit", task_id=tid, now=NOW)
        call(p, "verify", task_id=tid, verifier="ver_1", now=NOW)
        c = call(p, "task_challenge", task_id=tid, factor=3, strat="scale", by="auto", now=NOW)
        new_id = c["new_id"]
        g = call(p, "get", task_id=new_id)
        assert "[challenge]" in g["description"], f"应带 [challenge]: {g['description']}"
        assert f"from {tid}" in g["description"], f"应溯源 from {tid}"
        assert "3 倍" in g["description"], f"scale 应写入 factor=3: {g['description']}"
        print(f"PASS task_challenge → new_id={new_id} 带 [challenge]/溯源/3倍")
        # 未完成任务应拒绝
        r2 = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="待挑战任务", created_by="human_steward", now=NOW)
        try:
            call(p, "task_challenge", task_id=r2["task_id"], by="auto", now=NOW)
            raise RuntimeError("未完成任务不应通过 challenge")
        except RuntimeError as e:
            assert "已完成/已归档" in str(e), f"应提示需已完成/已归档: {e}"
        print("PASS 未完成任务 → 拒绝（提示 已完成/已归档）")
        # 整洁：scratch 隔离，仓库根无 {NS}.db
        assert not os.path.exists(os.path.join(ROOT, NS + ".db")), f"仓库根不应出现 {NS}.db"
        print("PASS 仓库根无 challenge-verify.db（scratch 已隔离）")
        print("MCP-TASK-CHALLENGE-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()