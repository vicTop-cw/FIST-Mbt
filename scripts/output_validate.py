#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/output_validate.py — 产出物验证 CLI（output_validate 三形态之一：MCP / CLI / skill）

用法（项目根）：
    python scripts/output_validate.py <project_dir> \
        --artifacts '[{"path":"README.md","contains":"FIST"}]' \
        [--external-results external.json] \
        [--evidence "agent 报告摘录"] \
        [--require-evidence]

    --artifacts 也支持文件路径：
        --artifacts artifacts.json

行为：
    1) 拉起 `node _build/js/.../cmd/main/main.js`（MCP server, STDIO）
    2) tools/call output_validate {project_dir, artifacts, external_results, evidence, require_evidence}
    3) 打印 JSON 结果；verdict=pass → 退出 0，fail 或 error → 退出 1

设计：
    - 薄封装：验证逻辑单真源在 MoonBit 端（src/server/output_validate.mbt），
      CLI 只负责拉起 server + 调用工具，避免重复造轮子。
    - 与 issue_scan.py 同款 ESM shim 注入（moonc ≥0.10.14 输出 ESM，mizchi/sqlite 用 CJS）。
    - 三形态对齐：同一 output_validate 工具可通过 MCP 协议、本 CLI 脚本、或 skill 调用，
      三者共享相同的 MoonBit 实现与 JSON schema。
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
    "io.modelcontextprotocol/clientInfo": {"name": "output-validate-cli", "version": "1.0"},
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


def _parse_json_arg(raw, label):
    """解析 --artifacts / --external-results：先当文件路径试，失败则当内联 JSON。"""
    if raw is None:
        return None
    # 1) 视作文件路径
    if os.path.isfile(raw):
        try:
            with open(raw, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            raise RuntimeError(
                f"{label}: 文件存在但读取/解析失败 ({e})，请检查 JSON 格式或权限"
            )
    # 2) 视作内联 JSON 字符串
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"{label}: 既不是有效文件也不是合法 JSON 字符串 ({e})"
        )


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(
            "用法: python scripts/output_validate.py <project_dir> "
            "--artifacts <json_or_file> "
            "[--external-results <json_or_file>] "
            "[--evidence <string>] "
            "[--require-evidence]"
        )
        sys.exit(0 if args else 1)

    # 1) 位置参数：project_dir
    project_dir = args[0]

    # 2) 解析具名参数（手动 parse，避免 argparse 额外依赖）
    artifacts_raw = None
    external_results_raw = None
    evidence = ""
    require_evidence = False

    i = 1
    while i < len(args):
        a = args[i]
        if a == "--artifacts":
            if i + 1 >= len(args):
                print("FAIL --artifacts 需要值")
                sys.exit(1)
            artifacts_raw = args[i + 1]
            i += 2
        elif a == "--external-results":
            if i + 1 >= len(args):
                print("FAIL --external-results 需要值")
                sys.exit(1)
            external_results_raw = args[i + 1]
            i += 2
        elif a == "--evidence":
            if i + 1 >= len(args):
                print("FAIL --evidence 需要值")
                sys.exit(1)
            evidence = args[i + 1]
            i += 2
        elif a == "--require-evidence":
            require_evidence = True
            i += 1
        else:
            print(f"FAIL 未知参数: {a}")
            sys.exit(1)

    if artifacts_raw is None:
        print("FAIL 必须提供 --artifacts")
        sys.exit(1)

    try:
        artifacts = _parse_json_arg(artifacts_raw, "--artifacts")
        if not isinstance(artifacts, list):
            print("FAIL --artifacts 解析结果必须是数组")
            sys.exit(1)
        external_results = _parse_json_arg(external_results_raw, "--external-results") \
            if external_results_raw is not None else {}
        if not isinstance(external_results, dict):
            print("FAIL --external-results 解析结果必须是对象(dict)")
            sys.exit(1)
    except RuntimeError as e:
        print("FAIL " + str(e))
        sys.exit(1)

    main_js = find_main()
    if not main_js:
        print("FAIL main.js 未找到；请先执行 `moon build --target js cmd/main`")
        sys.exit(1)

    import importlib.util
    _spec = importlib.util.spec_from_file_location(
        "patch_esm_main",
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch_esm_main.py"),
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
            name="output_validate",
            arguments={
                "project_dir": project_dir,
                "artifacts": artifacts,
                "external_results": external_results,
                "evidence": evidence,
                "require_evidence": require_evidence,
            },
        )
        text = r["result"]["content"][0]["text"]
        print(text)
        try:
            payload = json.loads(text)
            verdict = payload.get("verdict", "")
            sys.exit(0 if verdict == "pass" else 1)
        except json.JSONDecodeError:
            # 无法解析结果 JSON：视作 fail
            sys.exit(1)
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
