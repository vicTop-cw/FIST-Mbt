#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/plan_gradient_verify.py — 验证 task_plan_deep gradient=true 难度梯度标注端到端；scratch 隔离不污染根库。"""
import json, os, subprocess, sys
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "gradient-verify"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "plan-gradient-verify", "version": "1.0"}}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def rpc(p, m, **kw):
    kw["_meta"] = META
    req = {"jsonrpc": "2.0", "id": "1", "method": m, "params": kw}
    p.stdin.write(json.dumps(req, ensure_ascii=False) + "\n"); p.stdin.flush()
    line = p.stdout.readline()
    if not line: raise RuntimeError("server closed stdout")
    return json.loads(line)

def call(p, name, **args):
    r = rpc(p, "tools/call", name=name, arguments=args)
    if "error" in r: raise RuntimeError(f"{name}: {r['error']}")
    return json.loads(r["result"]["content"][0]["text"])

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        # 默认不传 gradient：子任务描述不含难度梯度（零回归）
        r = call(p, "store_open", namespace=NS, scratch=True, now=NOW)
        r0 = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="G 根任务", created_by="human_steward", now=NOW)
        rid = r0["task_id"]
        ignore0 = call(p, "task_plan_deep", task_id=rid, split_n=3, by="leader", now=NOW)
        got = call(p, "get", task_id=f"{rid}.1")
        assert "难度梯度" not in got["description"], f"默认应无难度梯度: {got['description']}"
        print("PASS 默认 gradient 关闭 → 子任务描述无难度梯度（零回归）")
        # 开启 gradient：子任务带难度梯度 + 更简单变体
        r2 = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="G 挑战根任务", created_by="human_steward", now=NOW)
        rid2 = r2["task_id"]
        ignore2 = call(p, "task_plan_deep", task_id=rid2, split_n=3, by="leader", gradient=True, now=NOW)
        c1 = call(p, "get", task_id=f"{rid2}.1")
        c3 = call(p, "get", task_id=f"{rid2}.3")
        assert "[难度梯度 1/3:易]" in c1["description"], f"首片应为易: {c1['description']}"
        assert "更简单变体" in c1["description"], f"应含更简单变体提示: {c1['description']}"
        assert "[难度梯度 3/3:难]" in c3["description"], f"末片应为难: {c3['description']}"
        print("PASS gradient=true → 难度梯度标注（1/3:易、3/3:难）+ 更简单变体提示")
        # 难度校准：gradient + calibrate 用真实难度覆盖位置档
        r3 = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="G 校准根任务", created_by="human_steward", now=NOW)
        rid3 = r3["task_id"]
        ignore3 = call(p, "task_plan_deep", task_id=rid3, split_n=3, by="leader", gradient=True, calibrate=[1, 3, 5], now=NOW)
        ck1 = call(p, "get", task_id=f"{rid3}.1")
        ck3 = call(p, "get", task_id=f"{rid3}.3")
        assert "[难度梯度 1/3:易" in ck1["description"] and "d=1" in ck1["description"], f"首片应校准 d=1: {ck1['description']}"
        assert "[难度梯度 3/3:难" in ck3["description"] and "d=5" in ck3["description"], f"末片应校准 d=5: {ck3['description']}"
        print("PASS 难度校准 calibrate=[1,3,5] → 真实难度覆盖位置档（d=1 易 / d=5 难）")
        # 整洁：scratch 库落 temp/，仓库根无残留 {NS}.db
        root_db = os.path.join(ROOT, NS + ".db")
        if os.path.exists(root_db):
            raise RuntimeError(f"仓库根出现临时库: {root_db}")
        print(f"PASS 仓库根无 {NS}.db（scratch 已隔离）")
        print("MCP-PLAN-GRADIENT-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()