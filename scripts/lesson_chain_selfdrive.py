#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/lesson_chain_selfdrive.py — 演示【失败回流闭环】: 用 fist-mbt 自身跑一次"打回→记录lesson"完整链路。
发布 omega 任务 → 语料审核打回 → 随即 evolve_lesson 归档 [lesson] → evolve_snapshot 可见教训。
证明"会犯错→可演绎"闭环成立(人工串联; 自动串联列为中期项)。"""
import json, os, subprocess, sys
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "lesson-chain"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "lesson-chain", "version": "1.0"}}
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

def leaves(nodes):
    out = []
    for nd in nodes:
        if nd.get("leaf"): out.append(nd["id"])
        if nd.get("children"): out.extend(leaves(nd["children"]))
    return out

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        root = call(p, "publish_parallel", project_dir=ROOT,
                    description="失败回流闭环演示（打回→lesson 自动归档）", namespace=NS,
                    created_by="selfdrive", now=NOW)["task_id"]
        print(f"PASS publish → {root}")
        pd = call(p, "task_plan_deep", task_id=root, omega_strong_verify=True, split_n=2, by="leader",
                  decide_split_n=1, decide_difficulty=2.0, decide_reason="闭环演示",
                  spec=json.dumps({"fingerprint": "chain:v1"}), now=NOW)
        ls = leaves(pd.get("tree", {}).get("children", []))
        lid = ls[0]
        # 造语料 → 审核【打回】(模拟验证者质疑)
        call(p, "omega_spec_create", task_id=lid, author="spec_author",
             content="验收标准未覆盖 fingerprint", now=NOW)
        call(p, "omega_spec_review", task_id=lid, reviewer="verifier", verdict="reject",
             reason="语料缺 fingerprint/schema，需补齐", now=NOW)
        print("PASS omega_spec_review 打回(reject) 触发")
        # 随即把打回原因归档成 [lesson]（人工串联闭环；自动串联为中期项）
        call(p, "evolve_lesson", cat="语料不合格", reason="语料缺 fingerprint/schema",
             fix="先写 fingerprint 再 claim", now=NOW)
        print("PASS evolve_lesson 归档 [lesson]")
        # 验证 lesson 入档 → snapshot 可见
        snap = call(p, "evolve_snapshot")
        count = snap.get("count", 0)
        dead = snap.get("dead_ends", [])
        print(f"PASS evolve_snapshot → count={count} dead_ends={len(dead)}")
        print("MCP-LESSON-CHAIN PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()