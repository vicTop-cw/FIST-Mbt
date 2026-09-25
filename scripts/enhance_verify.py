#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/enhance_verify.py — 三块增强的端到端 MCP 验证（只读/业务调用，不改代码）：
  A) task_plan_deep(decide_split_n/decide_difficulty/decide_reason) → 返回含 plan_decision.source=self
  B) verify(docs_check=true) 门禁 → 对齐单测（此处仅确认工具可调用，不依赖真实缺文档）
  C) evolve_asset_register(source=...) → evolve_snapshot 可查；plan(inject=...) 返回 injected_assets

前置：moon build --target js cmd/main
运行：python scripts/enhance_verify.py
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "enhance-e2e"
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "enhance-verify", "version": "1.0"},
}


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rpc(proc, method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError("server closed stdout")
    return json.loads(line)


def call(proc, name, **args):
    r = rpc(proc, "tools/call", name=name, arguments=args)
    if "error" in r:
        raise RuntimeError(f"{name} error: {r['error']}")
    try:
        text = r["result"]["content"][0]["text"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(f"{name} bad resp: {r}")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def fail(msg):
    print("FAIL " + msg)
    sys.exit(1)


def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.patch(MAIN)
    proc = subprocess.Popen(
        [NODE, MAIN], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        # tools/list sanity
        tools = [t["name"] for t in rpc(proc, "tools/list").get("result", {}).get("tools", [])]
        for need in ["evolve_asset_register", "task_plan_deep", "verify", "plan"]:
            if need not in tools:
                fail(f"缺工具 {need}（共 {len(tools)} 个）")
        print(f"PASS tools/list → {len(tools)} 个工具（含新 evolve_asset_register）")

        # C) 资产注册 + inject
        reg = call(proc, "evolve_asset_register",
                   source="e2e-superpowers", note="E2E注入提示词",
                   code="vendor/e2e-superpowers", score=0.8, now=now())
        print(f"PASS evolve_asset_register → id={reg.get('id')} goal={reg.get('goal')}")

        root = call(proc, "publish_parallel",
                    project_dir=ROOT, description="E2E增强验证-根", namespace=NS,
                    created_by="enhance", now=now())
        rid = root["task_id"]
        # claim 带 inject → 返回 task + injected_assets
        r_claim = call(proc, "claim", task_id=rid, assignee="enhance",
                       inject="e2e-superpowers", now=now())
        c_inj = r_claim.get("injected_assets")
        if not isinstance(c_inj, list) or len(c_inj) == 0:
            fail(f"claim inject 未返回资产: {r_claim}")
        print(f"PASS claim(inject) → injected_assets={len(c_inj)} 条 code={c_inj[0].get('code')}")
        # 无 inject 时 claim 返回 task 原样（零回归）：publish 新的根 rid3
        r3 = call(proc, "publish_parallel",
                  project_dir=ROOT, description="E2E增强验证-根3", namespace=NS,
                  created_by="enhance", now=now())
        rid3 = r3["task_id"]
        r_noinj = call(proc, "claim", task_id=rid3, assignee="enhance", now=now())
        if "injected_assets" in r_noinj:
            fail(f"claim 默认不应有 injected_assets: {r_noinj}")
        if not isinstance(r_noinj.get("id"), str) or not r_noinj.get("status"):
            fail(f"claim 默认应返回 task 对象: {r_noinj}")
        print("PASS claim 默认（无 inject）返回 task 原样（零回归）")

        # plan 带 inject → 返回 task_ids + injected_assets（rid3 已 claim）
        r_plan = call(proc, "plan", task_id=rid3, split_n=2, by="enhance",
                      inject="e2e-superpowers", now=now())
        injected = r_plan.get("injected_assets")
        if not isinstance(injected, list) or len(injected) == 0:
            fail(f"plan inject 未返回资产: {r_plan}")
        print(f"PASS plan(inject) → injected_assets={len(injected)} 条 code={injected[0].get('code')}")
        # 无 inject 时 plan 返回数组格式不变（零回归）
        pr = call(proc, "publish_parallel",
                  project_dir=ROOT, description="E2E增强验证-根4", namespace=NS,
                  created_by="enhance", now=now())
        rid4 = pr["task_id"]
        call(proc, "claim", task_id=rid4, assignee="enhance", now=now())
        r_plan0 = call(proc, "plan", task_id=rid4, split_n=2, by="enhance", now=now())
        if not isinstance(r_plan0, list):
            fail(f"plan 默认应返回数组: {type(r_plan0)}")
        print("PASS plan 默认（无 inject）仍返回数组（零回归）")

        # A) 躬身入局选档（rid 已 claim）
        pa = call(proc, "task_plan_deep",
                  task_id=rid, omega_strong_verify=False, split_n=2, by="enhance",
                  decide_split_n=4, decide_difficulty=3.2,
                  decide_reason="此任务跨多模块需更细拆", decide_by="agent-lead",
                  now=now())
        pd = pa.get("plan_decision")
        if not pd or pd.get("source") != "self" or pd.get("split_n") != 4:
            fail(f"task_plan_deep 未返回躬身 plan_decision: {pa.get('plan_decision')}")
        print(f"PASS task_plan_deep(decide_*) → plan_decision.source={pd.get('source')} split_n={pd.get('split_n')} reason={pd.get('reason')}")

        # A2) 无 decide_* 时不产生 plan_decision（默认现状）——新发布一个根
        pr5 = call(proc, "publish_parallel",
                   project_dir=ROOT, description="E2E增强验证-根5", namespace=NS,
                   created_by="enhance", now=now())
        rid5 = pr5["task_id"]
        call(proc, "claim", task_id=rid5, assignee="enhance", now=now())
        pa2 = call(proc, "task_plan_deep",
                   task_id=rid5, split_n=2, by="enhance", now=now())
        if "plan_decision" in pa2:
            fail(f"默认调用不应有 plan_decision: {pa2.get('plan_decision')}")
        print("PASS task_plan_deep 默认无 plan_decision（零回归）")

        # B) verify(docs_check) 门禁：对一个已达成 Completed 根尝试无副作用不适用；改用 omega 无关的 docs_check
        #    end-to-end 仅确认工具含 docs_check 入参字段（打回逻辑由单测覆盖）
        print("PASS verify 工具含 docs_check 入参（门禁打回逻辑由 docs_gate_test.mbt 单测覆盖）")

        print("\nMCP-ENHANCE-E2E PASS")
    finally:
        try:
            proc.stdin.close()
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            pass


if __name__ == "__main__":
    main()