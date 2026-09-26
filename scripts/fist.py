#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/fist.py — FIST-Mbt 统一 CLI 网关（一源三态 · CLI 形态）

所有 105 个 MCP 工具通过 `fist.py` 子命令路由调用。

用法：
    python scripts/fist.py list-tools                          # 列出所有工具名
    python scripts/fist.py call <tool_name> --arg val ...      # 通用调用
    python scripts/fist.py call publish --ns scratch --title "测试" --desc "..."
    python scripts/fist.py call store_open --ns scratch --scratch true
    python scripts/fist.py call task_plan_deep --ns scratch --gradient true --max_depth 3
    python scripts/fist.py call output_validate --project-dir . --artifacts '[{"path":"moon.mod"}]'

参数格式（--arg 值）：
    - 纯数字 → float/int 自动转换
    - true/false → bool
    - {...} / [...] → 内联 JSON 对象/数组
    - 普通字符串 → string
    - @file.json → 读文件内容（数组/对象推荐放文件里）

退出码：verdict=pass / result.ok=true → 0；fail / error → 1

设计：与 issue_scan.py / output_validate.py 同款薄封装模式，单真源在 MoonBit。
"""
import json
import os
import re
import subprocess
import sys

NODE = os.environ.get("FIST_NODE", "node")
MAIN_CANDIDATES = [
    "_build/js/debug/build/cmd/main/main.js",
    "target/js/release/build/cmd/main/main.js",
]
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "fist-cli", "version": "1.0"},
}


def find_main():
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


def auto_convert(v: str):
    """把字符串参数自动转成合适的 JSON 类型。"""
    if isinstance(v, str):
        stripped = v.strip()
        # @file.json → 读文件
        if stripped.startswith("@") and os.path.isfile(stripped[1:]):
            with open(stripped[1:], encoding="utf-8") as f:
                return json.load(f)
        # 内联 JSON 对象/数组
        if stripped.startswith("{") or stripped.startswith("["):
            try:
                return json.loads(stripped)
            except json.JSONDecodeError:
                pass
        # 布尔
        if stripped.lower() == "true":
            return True
        if stripped.lower() == "false":
            return False
        # 数字
        try:
            if "." in stripped:
                return float(stripped)
            return int(stripped)
        except ValueError:
            pass
    return v


def parse_args(argv):
    """把 ['--ns', 'scratch', '--title', 'hi'] 转成 {'ns': 'scratch', 'title': 'hi'}。"""
    out = {}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            key = a[2:].replace("-", "_")
            if i + 1 < len(argv):
                out[key] = auto_convert(argv[i + 1])
                i += 2
            else:
                out[key] = True
                i += 1
        else:
            i += 1  # 忽略位置参数（保留给 list-tools 等子命令）
    return out


def run_server():
    main_js = find_main()
    if not main_js:
        print("FAIL main.js 未找到；请先执行 `moon build --target js cmd/main`")
        sys.exit(1)
    import importlib.util
    _spec = importlib.util.spec_from_file_location(
        "patch_esm_main", os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch_esm_main.py"),
    )
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    _mod.patch(main_js)
    proc = subprocess.Popen(
        [NODE, main_js],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
    )
    return proc


def cmd_list_tools(proc):
    """列出所有 MCP 工具名（从 server.mbt 解析）。"""
    server_mbt = os.path.join(os.path.dirname(__file__), "..", "src", "server", "server.mbt")
    if os.path.isfile(server_mbt):
        content = open(server_mbt, encoding="utf-8").read()
        names = re.findall(r'instrumented_tool\(\s*\w+,\s*"([a-z_]+)"', content)
        names = sorted(set(names))
        for n in names:
            print(n)
        print(f"\n共 {len(names)} 个工具")
    else:
        # fallback: 用 list 工具看 store_open 后能否拿到工具列表
        print("无法解析 src/server/server.mbt（不在项目根？）")
        sys.exit(1)


def cmd_call(proc, tool_name, kwargs):
    """通用 MCP 工具调用。"""
    try:
        r = rpc(proc, "tools/call", name=tool_name, arguments=kwargs)
    except Exception as e:
        print(f"FAIL {e}")
        sys.exit(1)
    content = r["result"]["content"]
    text_parts = [c["text"] for c in content if c.get("type") == "text"]
    text = text_parts[0] if text_parts else json.dumps(r["result"], ensure_ascii=False, indent=2)
    print(text)
    # 判退出码：找 verdict / ok 字段
    exit_code = 0
    try:
        payload = json.loads(text)
        verdict = payload.get("verdict", "")
        ok = payload.get("ok")
        if verdict in ("fail", "rejected") or ok is False:
            exit_code = 1
    except json.JSONDecodeError:
        pass
    sys.exit(exit_code)


def main():
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        print("用法: python scripts/fist.py <subcommand> [args...]")
        print("  list-tools          列出所有 MCP 工具名")
        print("  call <tool> --k v   通用 MCP 工具调用")
        print("示例:")
        print("  python scripts/fist.py call store_open --ns scratch --scratch true")
        print("  python scripts/fist.py call publish --ns scratch --title '测试'")
        print("  python scripts/fist.py call task_plan_deep --ns scratch --gradient true --max_depth 3")
        sys.exit(0)

    sub = argv[0]
    rest = argv[1:]

    if sub == "list-tools":
        cmd_list_tools(None)
        return

    if sub == "call":
        if not rest:
            print("用法: fist.py call <tool_name> [--arg val ...]")
            sys.exit(1)
        tool_name = rest[0]
        kwargs = parse_args(rest[1:])
        proc = run_server()
        try:
            cmd_call(proc, tool_name, kwargs)
        finally:
            try:
                proc.stdin.close(); proc.terminate(); proc.wait(timeout=5)
            except Exception:
                pass

    print(f"未知子命令: {sub}")
    sys.exit(1)


if __name__ == "__main__":
    main()
