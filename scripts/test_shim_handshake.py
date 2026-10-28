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
9. 畸形输入健壮性：缺 protocolVersion / 缺 params / 非 JSON / 空行 / 通知

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


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

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


def start_shim(dist: Path, shim: Path, server_cmd=None) -> subprocess.Popen:
    """启动 shim（内部 spawn server）。

    R90：`server_cmd` 非空时**覆盖**内建启动命令 —— 这正是 `--server` 的 help 承诺
    （「覆盖 shim 内建的 server 启动命令（默认 dist serve）」），但旧实现**从未读取**它
    ⇒ 旗标是空开关（文档第 24 行还宣传了用法）。"""
    """启动 shim（内部 spawn 发布版 dist serve）。"""
    if not dist.exists():
        print(f"  [SKIP] dist 不存在：{dist}", file=sys.stderr)
        return None
    db = os.path.join(tempfile.gettempdir(), "fist-shim-test.db")
    env = dict(os.environ)
    env["FIST_DB_PATH"] = db
    return subprocess.Popen(
        ["node", str(shim), "--server"]
        + (list(server_cmd) if server_cmd else ["node", str(dist), "serve"]),
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

    def send_raw(self, line):
        """发原始字符串（测试非 JSON 输入用）。"""
        self.proc.stdin.write(line + "\n")
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
    if resources:
        uri = resources[0].get("uri", "fist://map")
        client.send({
            "jsonrpc": "2.0", "id": 31, "method": "resources/read",
            "params": {"uri": uri},
        })
        r = client.recv()
        contents = (r or {}).get("result", {}).get("contents", [])
        check("resources/read",
              len(contents) > 0 and len(str(contents[0])) > 50,
              f"{uri} → {len(str(contents[0])) if contents else 0} 字符")

    # 5b. prompts/list
    client.send({"jsonrpc": "2.0", "id": 41, "method": "prompts/list"})
    r = client.recv()
    prompts = (r or {}).get("result", {}).get("prompts", [])
    check("prompts/list", len(prompts) > 0, f"{len(prompts)} 个 prompt")
    if prompts:
        name = prompts[0].get("name", "fist:verify")
        client.send({
            "jsonrpc": "2.0", "id": 42, "method": "prompts/get",
            "params": {"name": name},
        })
        r = client.recv()
        msgs = (r or {}).get("result", {}).get("messages", [])
        check("prompts/get",
              len(msgs) > 0 and bool(msgs[0].get("role")),
              f"{name} → {len(msgs)} messages")

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


def run_robustness(client):
    """畸形输入健壮性：缺 protocolVersion / 缺 params / 非 JSON / 空行 / 通知。

    server 侧返回的 -32700 之类标准 JSON-RPC 错误视为"不崩"即 PASS；
    只有 shim 进程死掉、或响应结构完全异常才算 FAIL。
    """
    results = []
    def check(name, ok, detail=""):
        results.append((name, bool(ok), detail))
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {detail}")

    # 1. initialize 缺 protocolVersion（shim 应默认 MCP_PROTOCOL_VERSION 回写）
    client.send({
        "jsonrpc": "2.0", "id": 10, "method": "initialize",
        "params": {"capabilities": {}, "clientInfo": {"name": "no-pv", "version": "1"}},
    })
    r = client.recv()
    pv = (r or {}).get("result", {}).get("protocolVersion", "")
    check("initialize 缺 protocolVersion", bool(pv), f"回写 protocolVersion={pv}")

    # 2. 有 id 的请求缺 params（shim 应补 _meta）
    client.send({"jsonrpc": "2.0", "id": 11, "method": "tools/list"})
    r = client.recv()
    n = len((r or {}).get("result", {}).get("tools", []))
    check("请求缺 params（补 _meta）", n > 0, f"{n} 个工具")

    # 3. 非 JSON（server 应回 -32700，shim 不崩）
    client.send_raw("not-json-at-all")
    r = client.recv()
    code = (r or {}).get("error", {}).get("code", "")
    check("非 JSON（server -32700）", code == -32700, f"error.code={code}")

    # 4. 空行（shim 应忽略）
    client.send_raw("")
    check("空行（忽略）", True, "无响应")

    # 5. notifications/initialized（无 id，应透传/丢弃，无响应）
    client.send({
        "jsonrpc": "2.0", "method": "notifications/initialized",
    })
    check("notifications/initialized", True, "无响应")

    return results


def run_boundary(client):
    """边界输入健壮性（boundary_probe 建议）：元字符/引号/Unicode 注入。

    server 侧返回标准 JSON-RPC 错误（-32600 等）视为"正确拒绝"即 PASS；
    只有 shim 进程死掉或返回异常才算 FAIL。
    """
    results = []
    def check(name, ok, detail=""):
        results.append((name, bool(ok), detail))
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {detail}")

    # 1. 元字符注入：capabilities.experimental 含引号/反斜杠/换行
    client.send({
        "jsonrpc": "2.0", "id": 51, "method": "initialize",
        "params": {
            "capabilities": {"experimental": {"note": 'a"b\\c\nd\te'}},
            "clientInfo": {"name": "inj", "version": "1"},
        },
    })
    r = client.recv()
    name = (r or {}).get("result", {}).get("serverInfo", {}).get("name", "")
    check("元字符注入 capabilities",
          name == "fist-mbt" or (r or {}).get("error") is not None,
          f"serverInfo={name or (r or {}).get('error',{}).get('code','?')}")

    # 2. 未转义引号（原始字符串，shim 透传 → server 解析失败）
    client.send_raw('{"jsonrpc":"2.0","id":52,"method":"initialize",'
                    '"params":{"capabilities":{},"clientInfo":{"name":"bad"quote","version":"1"}}}')
    r = client.recv()
    code = (r or {}).get("error", {}).get("code", "")
    check("未转义引号（server -32600）", code in (-32600, -32700), f"error.code={code}")

    # 3. Unicode 控制字符
    client.send({
        "jsonrpc": "2.0", "id": 53, "method": "initialize",
        "params": {"capabilities": {}, "clientInfo": {"name": "\u0000\u001f\ufffd", "version": "1"}},
    })
    r = client.recv()
    name = (r or {}).get("result", {}).get("serverInfo", {}).get("name", "")
    check("Unicode 控制字符 clientInfo.name",
          name == "fist-mbt" or (r or {}).get("error") is not None,
          f"serverInfo={name or (r or {}).get('error',{}).get('code','?')}")

    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--server", nargs="+", default=None,
                    help="覆盖 shim 内建的 server 启动命令（默认 dist serve）")
    args = ap.parse_args()

    dist = DEFAULT_DIST
    # R90：给了 --server 就按调用方指定的命令跑 ⇒ 不再要求默认 dist 存在
    if args.server is None and not dist.exists():
        print("FATAL: dist/fist-mbt.js 不存在——请先 moon build + patch_esm_main.py", file=sys.stderr)
        return 2

    print(f"=== 发布版协议兼容 shim 回归测试 ===")
    print(f"shim : {DEFAULT_SHIM}")
    print(f"dist : {dist} ({dist.stat().st_size} bytes)")
    print()

    proc = start_shim(dist, DEFAULT_SHIM, args.server)
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

    print("--- 畸形输入健壮性 ---")
    robust_results = run_robustness(client)
    ok_robust = all(r[1] for r in robust_results)
    all_ok = all_ok and ok_robust
    print()

    print("--- 边界输入（boundary_probe 建议）---")
    boundary_results = run_boundary(client)
    ok_boundary = all(r[1] for r in boundary_results)
    all_ok = all_ok and ok_boundary
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