#!/usr/bin/env python3
"""
scripts/test_shim_handshake.py — 发布版协议兼容 shim（mcp_compat_shim.js）回归测试。

背景：fist-mbt server 讲非标协议 `2026-07-28`（BUG-161/163），标准 MCP 客户端
（Claude Desktop / VS Code / cursor，讲 `2024-11-05` 或 `2025-06-18`）直连
`fist serve` 会吃 `-32022 Unsupported protocol version`。本测试通过
`scripts/mcp_compat_shim.js` 代理发布版 `dist/fist-mbt.js`，验证标准握手序列
全部通过。

覆盖场景：
1. initialize（2025-06-18 与 2024-11-05 两档）
2. notifications/initialized（无 id 通知，透传）
3. tools/list
4. tools/call（真实调用 status_summary——验证能列**且**能调）
5. resources/list
6. ping（shim stub）
7. logging/setLevel（shim stub，Round 124 A1）
8. completion/complete（shim stub，Round 124 A1）

用法：
    python scripts/test_shim_handshake.py
    python scripts/test_shim_handshake.py --server node <dist> serve

退出码：0=全过，1=有失败，2=前置不满足（dist 不存在）。

依赖：node + dist/fist-mbt.js（发布版产物）。
"""

import argparse
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_DIST = REPO / "dist" / "fist-mbt.js"
DEFAULT_SHIM = REPO / "scripts" / "mcp_compat_shim.js"

# 标准 MCP 客户端实际使用的协议版本
STANDARD_VERSIONS = ["2025-06-18", "2024-11-05"]

# MCP 可选方法（shim A1 stub）
OPTIONAL_METHODS = [
    ("ping", {}),
    ("logging/setLevel", {"level": "info"}),
    ("completion/complete", {
        "ref": {"type": "ref/prompt", "name": "x"},
        "argument": {"name": "y", "value": ""},
    }),
]


def start_shim(dist: Path, shim: Path) -> subprocess.Popen:
    """启动 shim（内部 spawn 发布版 dist serve）。"""
    if not dist.exists():
        print(f"  [SKIP] dist 不存在：{dist}", file=sys.stderr)
        return None
    db = os.path.join(tempfile.gettempdir(), "fist-shim-test.db")
    env = dict(os.environ)
    env["FIST_DB_PATH"] = db
    return subprocess.Popen(
        ["node", str(shim), "--server", "node", str(dist), "serve"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        bufsize=1,
        env=env,
    )


class Client:
    """极简 JSON-RPC 客户端：读写一行、阻塞等待指定 id 响应。"""

    def __init__(self, proc: subprocess.Popen):
        self.proc = proc
        self.q = queue.Queue()
        self._tid = threading.Thread(
            target=self._reader, daemon=True
        )
        self._tid.start()

    def _reader(self):
        try:
            for line in self.proc.stdout:
                line = line.strip()
                if line:
                    self.q.put(line)
        except Exception:
            pass

    def send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def recv(self, timeout=10):
        try:
            line = self.q.get(timeout=timeout)
            return json.loads(line)
        except queue.Empty:
            return None


def run_handshake(client, version: str) -> list:
    """跑一次完整握手，返回 (步骤, 是否通过, 备注) 列表。"""
    results = []

    def check(name, ok, note=""):
        results.append((name, ok, note))
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {note[:80]}")

    # 1. initialize
    client.send({
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": version,
            "capabilities": {},
            "clientInfo": {"name": "test-shim", "version": "1.0"},
        },
    })
    r = client.recv()
    ok = r and "result" in r and r["result"].get("protocolVersion") == version
    check(f"initialize ({version})", bool(ok),
          (r or {}).get("result", {}).get("serverInfo", {}).get("name", "?"))
    if not ok:
        return results

    # 2. notifications/initialized（无 id，应被透传，无响应）
    client.send({
        "jsonrpc": "2.0", "method": "notifications/initialized",
    })
    # 不应收到任何响应（通知无 id），这里不做断言

    # 3. tools/list
    client.send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    r = client.recv()
    tools = (r or {}).get("result", {}).get("tools", [])
    check("tools/list", len(tools) > 0, f"{len(tools)} 个工具")

    # 4. tools/call（真实调用——只列不调等于没用）
    client.send({
        "jsonrpc": "2.0", "id": 21, "method": "tools/call",
        "params": {"name": "status_summary", "arguments": {}},
    })
    r = client.recv()
    call_result = (r or {}).get("result", {})
    call_text = ""
    content = call_result.get("content", [])
    if isinstance(content, list) and content:
        call_text = str(content[0].get("text", ""))[:80]
    check("tools/call (status_summary)",
          bool(call_result) and "content" in call_result
          and call_result.get("isError") is not True,
          call_text)

    # 5. resources/list
    client.send({"jsonrpc": "2.0", "id": 3, "method": "resources/list"})
    r = client.recv()
    resources = (r or {}).get("result", {}).get("resources", [])
    check("resources/list", len(resources) > 0, f"{len(resources)} 个资源")

    # 6. 可选方法（shim stub）
    for i, (method, params) in enumerate(OPTIONAL_METHODS, start=10):
        client.send({
            "jsonrpc": "2.0", "id": i, "method": method, "params": params,
        })
        r = client.recv()
        # stub 返回 result（非 error）；error.code=-32601 视为 FAIL
        ok = bool(r) and "result" in r
        check(method, ok, str((r or {}).get("result", r or {}))[:60])

    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--server", nargs="+", default=None,
                    help="覆盖 shim 内建的 server 启动命令（默认 dist serve）")
    args = ap.parse_args()

    dist = DEFAULT_DIST
    if not dist.exists():
        print("FATAL: dist/fist-mbt.js 不存在——请先 moon build + patch_esm_main.py", file=sys.stderr)
        return 2

    print(f"=== 发布版协议兼容 shim 回归测试 ===")
    print(f"shim : {DEFAULT_SHIM}")
    print(f"dist : {dist} ({dist.stat().st_size} bytes)")
    print()

    proc = start_shim(dist, DEFAULT_SHIM)
    if proc is None:
        return 2

    time.sleep(1.5)  # 等 server 起来

    # 单个 Client 复用——重建会导致多个 reader 线程抢同一 proc.stdout
    client = Client(proc)

    all_ok = True
    for version in STANDARD_VERSIONS:
        print(f"--- protocolVersion = {version} ---")
        results = run_handshake(client, version)
        ok_this = all(r[1] for r in results)
        all_ok = all_ok and ok_this
        print()

    proc.kill()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.terminate()

    print(f"=== 结果：{'PASS' if all_ok else 'FAIL'} ===")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())