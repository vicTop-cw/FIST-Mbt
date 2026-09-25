#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/executor_route_verify.py — 验证 executor_register / executor_route（Marketplace 能力路由雏形，R30）E2E。

在前置 store_open(scratch) 的命名空间里：发布并完成一条任务 → 登记两个执行者能力标签 →
executor_route 按「能力覆盖率 desc → 负载 asc」推荐最佳执行者；再验证"能力路由到专长执行者 +
负载均衡（同覆盖时负载小的优先）"。scratch 隔离，仓库根不留 {NS}.db。
用法：moon build --target js cmd/main && python scripts/executor_route_verify.py
"""
import json, os, subprocess
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "executor-verify"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "executor-route-verify", "version": "1.0"}}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

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

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具")
        assert "executor_register" in tools and "executor_route" in tools, "缺少 executor_register/executor_route"

        # ① 登记两个执行者能力
        a = call(p, "executor_register", name="exec-A", abilities=["编排", "json"])
        assert a.get("ok") and a["name"] == "exec-A", f"登记失败: {a}"
        b = call(p, "executor_register", name="exec-B", abilities=["编排"])
        assert b.get("ok"), "exec-B 登记失败"
        print(f"PASS executor_register → exec-A(编排,json) / exec-B(编排)，已注册 {a['executors']}")

        # ② 路由"编排"：exec-A 与 exec-B 覆盖率都 1.0；给 exec-A 加一点负载后，应路由到 exec-B（负载均衡）
        # 造 exec-A 一条活跃负载：发布→认领 一条任务给 exec-A
        call(p, "store_open", namespace=NS, scratch=True, now=NOW)
        r = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="给 exec-A 的负载任务", created_by="human_steward", now=NOW)
        call(p, "claim", task_id=r["task_id"], assignee="exec-A", now=NOW)
        rt = call(p, "executor_route", need="编排")
        assert rt.get("count", 0) >= 2, f"应有 ≥2 候选: {rt}"
        best = rt["best"]["name"]
        assert best == "exec-B", f"同覆盖下应负载均衡到 exec-B(负载0)而非 exec-A(负载1): {rt}"
        print(f"PASS executor_route(need=编排) → 最佳 {best}（同覆盖 1.0，exec-A 负载1 被压后，负载均衡到 exec-B）")

        # ③ 路由到专长：need=json 只有 exec-A 覆盖 1.0 → best=exec-A
        rt2 = call(p, "executor_route", need="json")
        assert rt2["best"]["name"] == "exec-A", f"json 专长应路由到 exec-A: {rt2}"
        print(f"PASS executor_route(need=json) → 最佳 exec-A（专长路由）")

        # 整洁：scratch 隔离
        assert not os.path.exists(os.path.join(ROOT, NS + ".db")), f"仓库根不应出现 {NS}.db"
        print("PASS 仓库根无 executor-verify.db（scratch 已隔离）")
        print("MCP-EXECUTOR-ROUTE-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()