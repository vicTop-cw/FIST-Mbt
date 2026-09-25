#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/dispatch_verify.py — 验证 `selfdrive_dispatch` 能力路由自动派单（R32）E2E。

流程：登记执行者 exec-DP([编排]) → 发布一条「编排」任务 → `selfdrive_dispatch(want=编排)`
→ 应自动把该任务**认领给 exec-DP**（routed=true，而非常规回退自领）。验证 myself 状态迁移（待领取→已领取）。

⚠ 本脚本为验证派单会向交付库写一条任务；运行后主代理会以 `git checkout -- fist-mbt.db` 恢复，
  并执行 cleanup 保持整洁（仅本仓库独立验证，不并入交付自检链）。
用法：moon build --target js cmd/main && python scripts/dispatch_verify.py
"""
import json, os, subprocess
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "dispatch-verify"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "dispatch-verify", "version": "1.0"}}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

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

def main():
    p = start()
    try:
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具")
        assert "selfdrive_dispatch" in tools, "缺少 selfdrive_dispatch"

        # ① 登记一个「编排」能力执行者
        call(p, "executor_register", name="exec-DP", abilities=["编排"])
        # ② 发布一条「编排」任务（待领取）
        r = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="构建一个编排引擎 MVP", created_by="human", now=NOW)
        tid = r["task_id"]

        # ③ 能力路由自动派单：应派给 exec-DP
        d = call(p, "selfdrive_dispatch", namespace=NS, agent="self", want="编排", now=NOW)
        assert d.get("dispatched"), f"应能派单: {d}"
        assert d.get("routed"), f"应路由到注册执行者而非自领: {d}"
        assert d["assignee"] == "exec-DP", f"应派给 exec-DP: {d}"
        assert d["task_id"] == tid, f"应派单给发布的任务 {tid}: {d}"
        print(f"PASS selfdrive_dispatch(want=编排) → 派单 {tid} 给 exec-DP（routed=true, coverage={d['route']['coverage']}）")

        # ④ 状态迁移验证：该任务已认领给 exec-DP
        g = call(p, "get", task_id=tid)
        assert g.get("assignee") == "exec-DP", f"任务 assignee 应为 exec-DP: {g}"
        assert g.get("status") in ("已领取",), f"任务应已领取: {g.get('status')}"
        print(f"PASS 任务状态 → {g.get('status')}，assignee=exec-DP（0 迁移 待领取→已领取 经能力路由）")

        # ⑤ 清理能力注册（防存留）
        call(p, "executor_clear")
        print("PASS executor_clear 已复位能力注册")
        print("MCP-DISPATCH-VERIFY PASS")
    finally:
        stop(p)

if __name__ == "__main__":
    main()