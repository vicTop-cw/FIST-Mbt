#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/executor_route_verify.py — 验证 执行者能力路由（Marketplace 雏形，R30/R31）E2E。

跨进程持久化（R31）：进程 A `executor_register` 登记能力 → 进程 B（全新、内存注册表为空）
`executor_route` 仍能按能力路由到该执行者（证明 store executors 表持久化达到跨进程可复现）；
进程 B `executor_clear` 清空 → 进程 C `executor_route` 不再见该执行者（证明可重置）。

不创建任务（保持交付库干净，负载均衡行为由单元测试 `route_pick` 覆盖）。
用法：moon build --target js cmd/main && python scripts/executor_route_verify.py
"""
import json, os, subprocess
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "executor-route-verify", "version": "1.0"}}

def start(argv_mod=None):
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    return subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)

def rpc(p, m, **kw):
    kw["_meta"] = META
    req = {"jsonrpc": "2.0", "id": "1", "method": m, "params": kw}
    p.stdin.write(json.dumps(req, ensure_ascii=False) + "\n"); p.stdin.flush()
    line = p.stdout.readline()
    if not line: raise RuntimeError("server closed stdout")
    return json.loads(line)

def call(p, tool, **args):
    r = rpc(p, "tools/call", name=tool, arguments=args)
    if "error" in r: raise RuntimeError(f"{tool}: {r['error']}")
    return json.loads(r["result"]["content"][0]["text"])

def stop(p):
    try:
        p.stdin.close(); p.terminate(); p.wait(timeout=5)
    except Exception:
        pass

def names(route):
    return [c["name"] for c in route.get("candidates", [])]

def main():
    # ① 进程 A：登记一个执行者（持久化）
    pa = start()
    try:
        tools = [t["name"] for t in rpc(pa, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具")
        assert "executor_register" in tools and "executor_route" in tools and "executor_clear" in tools
        a = call(pa, "executor_register", name="exec-RJX", abilities=["json", "编排"])
        assert a.get("persisted", False), f"应持久化: {a}"
        assert "exec-RJX" in a["name"], a
        print(f"PASS 进程A executor_register(exec-RJX:[json,编排]) → persisted=true")
    finally:
        stop(pa)

    # ② 进程 B（全新进程，内存注册表为空）：跨进程应能按能力路由到 exec-RJX
    pb = start()
    try:
        rt = call(pb, "executor_route", need="json")
        assert "exec-RJX" in names(rt), f"跨进程应读到持久化的 exec-RJX: {rt}"
        assert rt["best"]["name"] == "exec-RJX", f"json 专长应路由到 exec-RJX: {rt}"
        print(f"PASS 进程B executor_route(json) → 跨进程读到持久化 exec-RJX，best=exec-RJX（跨进程可复现）")
        # ③ 进程 B：清空（Marketplace 重置）
        cl = call(pb, "executor_clear")
        assert cl.get("persisted"), f"清空应落库: {cl}"
        print(f"PASS 进程B executor_clear → persisted=true（已清空 store executors 表）")
    finally:
        stop(pb)

    # ④ 进程 C：清空后不应再见 exec-RJX（可重置）
    pc = start()
    try:
        rt2 = call(pc, "executor_route", need="json")
        assert "exec-RJX" not in names(rt2), f"executor_clear 后不应再见 exec-RJX: {rt2}"
        print(f"PASS 进程C executor_route(json) → exec-RJX 已消失（Marketplace 可重置/整洁）")
    finally:
        stop(pc)

    print("MCP-EXECUTOR-ROUTE-VERIFY PASS")

if __name__ == "__main__":
    main()