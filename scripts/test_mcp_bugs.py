#!/usr/bin/env python3
"""Test MCP server with bug-related tools"""
import subprocess, json, sys, time
import os
# BUG-122 同型收口：裸跑会把演示数据写进仓库根的自举台账 fist-mbt.db ⇒ 默认改道 temp/ 隔离库。
_FIST_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not (os.environ.get("FIST_DB_PATH") or "").strip():
    os.environ["FIST_DB_PATH"] = os.path.join(_FIST_ROOT, "temp", "test_mcp_bugs.db")

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "test", "version": "1.0"},
}

proc = subprocess.Popen(
    ["node", "_build/js/debug/build/cmd/cli/cli.js", "serve"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    bufsize=1,
)

def rpc(method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    return json.loads(line)

try:
    # Test 1: tools/list
    r = rpc("tools/list")
    tools = [t["name"] for t in r["result"]["tools"]]
    print(f"Total tools: {len(tools)}")
    
    # Find publish and bug tools
    key_tools = ["publish", "publish_parallel", "report_bug", "bug_list", 
                 "run_check", "audit_log", "heartbeat", "claim", "execute",
                 "submit", "verify", "reject", "retry", "plan"]
    for t in key_tools:
        print(f"  {'YES' if t in tools else 'MISS'}: {t}")
    
    # Test 2: publish a task for BUG-2
    r = rpc("publish", 
            project_dir=".",
            description="BUG-2 fix verify: retry后execute不应失败",
            namespace="fist-fix-mcp",
            created_by="fix-merge")
    if "result" in r:
        tid = r["result"].get("task_id", "")
        print(f"\nBUG-2 task_id: {tid}")
        
        # Test 3: claim
        r2 = rpc("claim", task_id=tid, assignee="agentX")
        print(f"claim: {r2.get('result', {}).get('status', r2.get('error'))}")
        
        # Test 4: execute
        r3 = rpc("execute", task_id=tid)
        print(f"execute: {r3.get('result', {}).get('status', r3.get('error'))}")
        
        # Test 5: report_bug (BUG-5 - should return resolved_path)
        r4 = rpc("report_bug", 
                 project_dir=".",
                 title="BUG-5 test",
                 description="path resolve test",
                 severity="medium")
        print(f"report_bug: keys={list(r4.get('result', {}).keys())}")
        if "result" in r4:
            print(f"  resolved_path={r4['result'].get('resolved_path', 'MISSING')}")
    else:
        print(f"publish error: {r.get('error')}")
        
finally:
    proc.terminate()
