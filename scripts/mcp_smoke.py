#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/mcp_smoke.py — FIST-Mbt 一键自检（评审/自驱 10 秒验证 MCP server 可用）

用法（项目根）：
    python scripts/mcp_smoke.py            # 需先 moon build --target js cmd/main

行为：
    1) 拉起 `node _build/js/.../cmd/main/main.js`（MCP server, STDIO）
    2) tools/list            → 断言含 publish 等 79 个工具
    3) publish_parallel      → 发布一个任务，断言拿到 task_id
    4) get                   → 按 task_id 查回，断言命中且状态为待领取
    全部通过打印 `MCP-SMOKE PASS`，退出码 0；任一步失败打印 FAIL，退出码 1。
"""
import json
import os
import subprocess
import sys

NODE = os.environ.get("FIST_NODE", "node")
MAIN_CANDIDATES = [
    "_build/js/debug/build/cmd/main/main.js",
    "target/js/release/build/cmd/main/main.js",
]
NS = "mcp-smoke"

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "mcp-smoke", "version": "1.0"},
}


def find_main() -> str:
    for p in MAIN_CANDIDATES:
        if os.path.exists(p):
            return p
    return ""


def rpc(proc, method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("MCP server closed stdout (did it crash?)")
    try:
        resp = json.loads(line)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"malformed JSON-RPC response: {line!r}") from e
    if "error" in resp:
        raise RuntimeError(f"JSON-RPC error: {resp['error']}")
    return resp


def fail(msg):
    print("FAIL " + msg)
    sys.exit(1)


def main():
    main_js = find_main()
    if not main_js:
        fail("main.js 未找到；请先执行 `moon build --target js cmd/main`")
    # moonc ≥0.10.14 对可执行目标输出 ESM，mizchi/sqlite 用 CJS require → 注入 require shim（幂等）
    import importlib.util
    _spec = importlib.util.spec_from_file_location(
        "patch_esm_main", os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch_esm_main.py"),
    )
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    _mod.patch(main_js)
    proc = subprocess.Popen(
        [NODE, main_js],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    try:
        # Step 1 · tools/list
        r = rpc(proc, "tools/list")
        tools = [t["name"] for t in r.get("result", {}).get("tools", [])]
        expected = 96
        if len(tools) != expected or "publish" not in tools:
            fail(f"tools/list 异常（共 {len(tools)} 个工具，期望 {expected}，缺 publish）")
        print(f"PASS tools/list → {len(tools)} 个工具（含 publish/selfdrive_publish_next 等）")

        # Step 2 · publish
        r = rpc(
            proc,
            "tools/call",
            name="publish_parallel",
            arguments={
                "project_dir": "/proj/demo",
                "description": "一键自检任务",
                "namespace": NS,
                "created_by": "selfdrive",
            },
        )
        try:
            text = r["result"]["content"][0]["text"]
        except (KeyError, IndexError, TypeError):
            fail(f"publish 返回异常响应: {r}")
        payload = json.loads(text)
        task_id = payload.get("task_id")
        if not task_id:
            fail("publish 未返回 task_id: " + text)
        print(f"PASS publish → {task_id}")

        # Step 3 · get
        r = rpc(proc, "tools/call", name="get", arguments={"task_id": task_id})
        got = json.loads(r["result"]["content"][0]["text"])
        if got.get("id") != task_id or got.get("status") != "待领取":
            fail(f"get 未命中或状态异常: {got}")
        print(f"PASS get → {got.get('id')} [{got.get('status')}]")

        print("MCP-SMOKE PASS")
    finally:
        try:
            proc.stdin.close()
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        except Exception:
            pass


if __name__ == "__main__":
    main()