#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/mcp_smoke.py — FIST-Mbt 一键自检（评审/自驱 10 秒验证 MCP server 可用）

用法（项目根）：
    python scripts/mcp_smoke.py            # 需先 moon build --target js cmd/cli

行为：
    1) 拉起 `node _build/js/.../cmd/cli/cli.js`（MCP server, STDIO）
    2) tools/list            → 断言含 publish 等 79 个工具
    3) publish_parallel      → 发布一个任务，断言拿到 task_id
    4) get                   → 按 task_id 查回，断言命中且状态为待领取
    全部通过打印 `MCP-SMOKE PASS`，退出码 0；任一步失败打印 FAIL，退出码 1。
"""

# BUG-138 残余面：Windows 默认 cp936 控制台下，中文结论一红就崩在 print 里，
# traceback + rc=1 会被读成「缺陷在场」那一档——那是尺子自己坏了。先把两条流钉 UTF-8。
import sys as _sys
if hasattr(_sys.stdout, "reconfigure"):
    _sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(_sys.stderr, "reconfigure"):
    _sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import json
import os
import re
from pathlib import Path
import subprocess
import sys

# 工具注册真源的单一实现（此前 5 处复制；漏改即假绿/互掐）。
import importlib.util as _ilu

_ir_spec = _ilu.spec_from_file_location(
    "_tool_registry", Path(__file__).resolve().parent / "_tool_registry.py")
_tool_registry = _ilu.module_from_spec(_ir_spec)
_ir_spec.loader.exec_module(_tool_registry)

NODE = os.environ.get("FIST_NODE", "node")
# BUG-122：README/USAGE/agent-map/deliverable 四处都教人**裸跑**这份自检或 demo，而不带 FIST_DB_PATH 时
# 服务端会把演示数据写进仓库根的自举台账 fist-mbt.db（每裸跑一次多一条任务与若干调用行）。
# 默认改道 temp/ 下的隔离库；调用方显式给了 FIST_DB_PATH 就照它的（demo.ps1 那类已经自己设过）。
_FIST_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not (os.environ.get("FIST_DB_PATH") or "").strip():
    os.environ["FIST_DB_PATH"] = os.path.join(_FIST_ROOT, "temp", "mcp_smoke.db")
MAIN_CANDIDATES = [
    "_build/js/debug/build/cmd/cli/cli.js",
    "target/js/release/build/cmd/cli/cli.js",
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


RE_TOOL = re.compile(r'instrumented_tool\(\s*\w+\s*,\s*"([^"]+)"')
# mcpcf_embed.mbt 走链式 `s.tool("mcpcf.xxx", …)`（不是 instrumented_tool）⇒ 单扫 instrumented_tool 会漏这 7 个。
RE_TOOL_CHAIN = re.compile(r'\b\w+\.tool\(\s*"([^"]+)"')
SERVER_DIR = Path(__file__).resolve().parent.parent / "src" / "server"


def registry_tool_names():
    """工具名真源 —— **委托给单一实现** `scripts/_tool_registry.py`（2026-10-14 收口）。

    本函数曾在 5 个消费者里各写一份；工具注册一搬家（从 server.mbt 拆到 supervisor_tools/
    hat_hexa/mcpcf_embed），漏改处会假绿或互掐。本冒烟只管"运行态 ↔ 源码真源"对表，不碰文档数字。
    返回 set（调用方用集合差算 missing/extra）。"""
    return set(_tool_registry.real_tools())


def registry_tool_count():
    return len(registry_tool_names())


def main():
    main_js = find_main()
    if not main_js:
        fail("main.js 未找到；请先执行 `moon build --target js cmd/cli`")
    # moonc ≥0.10.14 对可执行目标输出 ESM，mizchi/sqlite 用 CJS require → 注入 require shim（幂等）
    import importlib.util
    _spec = importlib.util.spec_from_file_location(
        "patch_esm_main", os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch_esm_main.py"),
    )
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    _mod.patch(main_js)
    proc = subprocess.Popen(
        [NODE, main_js, "serve"],
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
        # BUG-67 同族（第三处）：这里曾硬写 104/120 —— 注册表涨了它就过期，
        # 而且过期方式是"自检通过/自检失败"这种假信号。改成直接读真源同一口径。
        expected = registry_tool_count()
        if expected < 100:
            fail(f"src/server/*.mbt 只解析到 {expected} 个工具（<100 视为解析失效，不出假绿）")
        # 两件事必须分开判：数量不等是"注册表漂移"，缺 publish 是"入口工具丢失"。
        # 2026-10-14 实测过一次混判的代价：运行态 166 vs 只扫 server.mbt 得 148（18 个工具已拆到
        # supervisor_tools/hat_hexa/mcpcf_embed 等文件）⇒ 报出"缺 publish"，而 publish 明明在场，
        # 读的人被文案带去查一个不存在的问题。混判=误导，宁可多打一行。
        if len(tools) != expected:
            missing = sorted(set(registry_tool_names()) - set(tools))
            extra = sorted(set(tools) - set(registry_tool_names()))
            detail = []
            if missing:
                detail.append(f"真源有、运行态缺（{len(missing)}）：{', '.join(missing[:8])}")
            if extra:
                detail.append(f"运行态有、真源无（{len(extra)}）：{', '.join(extra[:8])}")
            fail(f"tools/list 数量与真源不一致：运行态 {len(tools)} vs 真源 {expected}；"
                 + "；".join(detail))
        if "publish" not in tools:
            fail("tools/list 缺 publish（入口工具丢失，与数量无关）")
        print(f"PASS tools/list → {len(tools)} 个工具（含 publish/selfdrive_publish_next 等）")

        # Step 1b · issue_scan（打磨收尾新增：找目标项目潜问题）
        if "issue_scan" not in tools:
            fail("tools/list 缺 issue_scan（找目标项目潜问题扫描）")
        scan_dir = "temp/mcp-smoke-scan"
        os.makedirs(scan_dir, exist_ok=True)
        with open(os.path.join(scan_dir, "d.mbt"), "w", encoding="utf-8") as f:
            f.write("fn f() -> Int {\n  let rows : Array[Int] = []\n  rows[0]\n}\n")
        r = rpc(
            proc,
            "tools/call",
            name="issue_scan",
            arguments={"dir": scan_dir, "max_findings": 20},
        )
        scan = json.loads(r["result"]["content"][0]["text"])
        if scan.get("total_findings", 0) < 1:
            fail(f"issue_scan 未命中注入的高危模式: {scan}")
        print(
            f"PASS issue_scan → 扫描 {scan.get('scanned_files')} 文件，命中 {scan.get('total_findings')} 条"
        )

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