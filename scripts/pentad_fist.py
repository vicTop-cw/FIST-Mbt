#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/pentad_fist.py — FIST-Mbt 驱动 Pentad 开发的 MCP 客户端
基于 mcp_smoke.py 的 rpc 模式，注册 Pentad 项目并启用 omega_strong_verify + call_log。
"""
import json
import os
# BUG-122 同型收口：不带 FIST_DB_PATH 裸跑会把演示数据写进仓库根的自举台账 fist-mbt.db。
# 默认改道 temp/ 下的隔离库；调用方显式设过 FIST_DB_PATH 就照它的（store_isolation_probe 那类必须自己控制）。
_FIST_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not (os.environ.get("FIST_DB_PATH") or "").strip():
    os.environ["FIST_DB_PATH"] = os.path.join(_FIST_ROOT, "temp", "pentad_fist.db")
import subprocess
import sys
import time

NS = "pentad-dev"
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "pentad-fist-driver", "version": "0.1"},
}
MAIN_JS = "_build/js/debug/build/cmd/cli/cli.js"


def rpc(proc, method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("MCP server closed stdout")
    resp = json.loads(line)
    if "error" in resp:
        raise RuntimeError(f"JSON-RPC error: {resp['error']}")
    return resp


def call(proc, name, **arguments):
    r = rpc(proc, "tools/call", name=name, arguments=arguments)
    text = r["result"]["content"][0]["text"]
    return json.loads(text)


def main():
    if not os.path.exists(MAIN_JS):
        print(f"FAIL main.js not found at {MAIN_JS}")
        sys.exit(1)

    # patch ESM shim
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import importlib.util
    _spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch_esm_main.py"))
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    _mod.patch(MAIN_JS)

    proc = subprocess.Popen(
        ["node", MAIN_JS, "serve"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )

    try:
        # 1. 验证 tools/list
        r = rpc(proc, "tools/list")
        tools = [t["name"] for t in r.get("result", {}).get("tools", [])]
        print(f"[OK] FIST-Mbt ready: {len(tools)} tools")
        for required in ["publish_parallel", "task_plan_deep", "omega_spec_create", "omega_spec_review", "omega_result_verify", "call_log"]:
            if required not in tools:
                print(f"[FAIL] missing tool: {required}")
                sys.exit(1)
        print("[OK] omega_strong + call_log tools present")

        # 2. 发布 Pentad 开发根任务
        root = call(proc, "publish_parallel",
                     project_dir="/proj/pentad",
                     description="[Pentad] 自驱式递归开发：宏系统修复 + DEMO 全覆盖",
                     namespace=NS,
                     created_by="pentad-fist-driver")
        root_id = root.get("task_id")
        print(f"[OK] root task published: {root_id}")

        # 3. 启用 omega_strong_verify 递归拆解
        plan = call(proc, "task_plan_deep",
                     task_id=root_id,
                     omega_strong_verify=True,
                     split_n=4,
                     by="pentad-fist-driver")
        print(f"[OK] plan_deep: {json.dumps(plan, ensure_ascii=False)[:200]}")

        # 4. 验证 call_log 已写入
        logs = call(proc, "call_log", limit=5)
        print(f"[OK] call_log recent entries: {len(logs.get('logs', []))}")

        print("PENTAD-FIST-READY")
        print(f"  ns={NS}")
        print(f"  root={root_id}")
        print(f"  omega_strong_verify=true")
        print(f"  call_log=true")
    finally:
        try:
            proc.stdin.close()
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    main()
