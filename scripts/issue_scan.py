#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/issue_scan.py — 规则驱动源码扫描 CLI（一源四态 · CLI 形态；插件态由 gen_plugins.py 投影）

用法（项目根）：
    python scripts/issue_scan.py <dir> [--max-findings N] [--include-tests]

行为：
    1) 拉起 `node _build/js/.../cmd/main/main.js`（MCP server, STDIO）
    2) tools/call issue_scan {dir, max_findings} → 打印 JSON 结果
    3) 退出码 0（扫描成功）/ 1（失败或命中非法目录）

设计：
    - 薄封装：扫描逻辑单真源在 MoonBit 端（src/server/issue_scan.mbt），
      CLI 只负责拉起 server + 调用工具，避免重复造轮子。
    - 与 mcp_smoke.py 同款 ESM shim 注入（moonc ≥0.10.14 输出 ESM，mizchi/sqlite 用 CJS）。
    - 无绝对路径硬编码：dir 为相对路径参数；main.js 用候选探测。
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
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "issue-scan-cli", "version": "1.0"},
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


def main():
    if len(sys.argv) < 2:
        print("用法: python scripts/issue_scan.py <dir> [--max-findings N] "
              "[--include-tests [true|false]]")
        sys.exit(1)
    argv = sys.argv[1:]
    scan_dir = None
    max_findings = 100
    # BUG-57：以前写 `"--include-tests" in sys.argv`，于是 `--include-tests false`
    # 会**反过来**开启扫描（MCP 形态该参数是 bool，调用方照习惯写值就拿到相反结果且无提示）。
    include_tests = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--max-findings":
            if i + 1 >= len(argv):
                print("FAIL --max-findings 缺值（不猜默认）")
                sys.exit(2)
            try:
                max_findings = int(argv[i + 1])
            except ValueError:
                print("FAIL --max-findings 需要整数，收到 %r" % argv[i + 1])
                sys.exit(2)
            i += 2
            continue
        if a == "--include-tests":
            nxt = argv[i + 1] if i + 1 < len(argv) else None
            if nxt in ("true", "false"):
                include_tests = nxt == "true"
                i += 2
            else:
                include_tests = True
                i += 1
            continue
        if a.startswith("-"):
            print("FAIL 未知参数 %r：本脚本只认 --max-findings / --include-tests" % a)
            sys.exit(2)
        if scan_dir is not None:
            print("FAIL 多余的位置参数 %r：扫描目录只有一个（拼错的开关不静默改语义）" % a)
            sys.exit(2)
        scan_dir = a
        i += 1
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
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    try:
        r = rpc(
            proc,
            "tools/call",
            name="issue_scan",
            arguments={
                "dir": scan_dir,
                "max_findings": max_findings,
                "include_tests": include_tests,
            },
        )
        text = r["result"]["content"][0]["text"]
        print(text)
        payload = json.loads(text)
        # 0 = 扫描成功（无论是否命中）；1 = 非法目录等 Err
        sys.exit(0 if payload.get("scanned_files", -1) >= 0 else 1)
    except Exception as e:
        print("FAIL " + str(e))
        sys.exit(1)
    finally:
        try:
            proc.stdin.close()
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            pass


if __name__ == "__main__":
    main()
