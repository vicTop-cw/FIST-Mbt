#!/usr/bin/env python3
"""MCP closed-loop for 5 bug fixes — publish→claim→execute→submit→verify per bug"""
import subprocess, json, sys

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "bug-mcp-loop", "version": "1.0"},
}

proc = subprocess.Popen(
    ["node", "_build/js/debug/build/cmd/cli/cli.js", "serve"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    text=True, bufsize=1,
)

def rpc(method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    return json.loads(line)

def tool_result(name, arguments):
    r = rpc("tools/call", name=name, arguments=arguments)
    if "error" in r:
        return {"__error__": r["error"]}
    content = r.get("result", {}).get("content", [])
    if content:
        try:
            return json.loads(content[0]["text"])
        except:
            return {"raw": content[0]["text"]}
    return r.get("result", {})

def loop(namespace, bug_id, title):
    print(f"\n[{bug_id}] {title}")
    # 1. publish
    r = tool_result("publish", {
        "project_dir": ".", "description": f"{bug_id}: {title}",
        "namespace": namespace, "created_by": "human_steward",
    })
    tid = r.get("task_id", "")
    if not tid:
        print(f"  FAIL publish: {r}")
        return False
    print(f"  publish → {tid}")

    # 2. claim
    r = tool_result("claim", {"task_id": tid, "assignee": "agentX"})
    print(f"  claim → {r.get('status', '?')}")

    # 3. execute
    r = tool_result("execute", {"task_id": tid})
    print(f"  execute → {r.get('status', r.get('__error__', r))}")

    # 4. submit
    r = tool_result("submit", {"task_id": tid, "deliverable": f"{bug_id} 修复完成。测试 366/366 通过。"})
    print(f"  submit → {r.get('status', r.get('__error__', r))}")

    # 5. verify (needs completed_by)
    r = tool_result("verify", {"task_id": tid, "verifier": "human_steward"})
    verify_ok = "__error__" not in r
    print(f"  verify → {r.get('status', r.get('__error__', r))} → {'PASS' if verify_ok else 'FAIL'}")
    return verify_ok

try:
    ns = "fist-fix-mcp"
    results = []

    results.append(loop(ns, "BUG-2", "retry后execute不应失败"))
    results.append(loop(ns, "BUG-1", "时间戳服务端盖章"))

    # BUG-5: report_bug → resolved_path
    r = tool_result("report_bug", {"project_dir": ".", "summary": "BUG-5 resolved_path check", "severity": "medium"})
    ok = "resolved_path" in r
    print(f"\n[BUG-5] report_bug → resolved_path {'PASS' if ok else 'FAIL'} (keys={list(r.keys())}, resolved_path={r.get('resolved_path', 'MISSING')})")
    results.append(ok)

    # BUG-3: audit_log → scope
    r = tool_result("audit_log", {"limit": 5})
    ok = "scope" in r
    print(f"\n[BUG-3] audit_log → scope field {'PASS' if ok else 'FAIL'} (scope={r.get('scope', 'MISSING')})")
    results.append(ok)

    # BUG-4: run_check malicious workdir → rejected
    r = tool_result("run_check", {"task_id": "T-test", "workdir": "../etc", "cmd": "echo test"})
    # Either server rejects with error, or the workdir validation kicks in
    has_error = "__error__" in r
    print(f"\n[BUG-4] run_check malicious workdir {'PASS (rejected)' if has_error else 'FAIL (no error)'} (err={r.get('__error__', r.get('msg', 'OK'))})")
    results.append(has_error)

    print(f"\n{'='*40}")
    print(f"SUMMARY: {sum(results)}/{len(results)} PASSED")
    for i, r in enumerate(results):
        print(f"  {'OK' if r else 'XX'} [{i+1}]")
    print(f"{'='*40}")

finally:
    proc.terminate()
    sys.exit(0 if all(results) else 1)

