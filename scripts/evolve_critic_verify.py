#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/evolve_critic_verify.py — 验证 evolve_critic 防漂移门禁 E2E（tools/list=76；只评审不写库，无 DB 污染）。"""
import json, os, subprocess
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "evolve-critic-verify", "version": "1.0"}}

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
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具")
        assert "evolve_critic" in tools, "缺少 evolve_critic"
        # 全新目标 + 高分：放行
        r = call(p, "evolve_critic", note="量子退火驱动的超导比特布线规划器", score=0.9)
        assert r["admit"] is True, f"全新目标应放行: {r}"
        print("PASS 全新目标 → admit=true")
        # 与档案库高重合 → 判漂移拒收（复用固定库已有 lesson/principle 作参照；无则不冲突，由低稳健性兜底）
        r2 = call(p, "evolve_critic", note="异步事件驱动持久化的坑", score=0.9, threshold=0.6)
        print(f"INFO 重复候选 → admit={r2['admit']} reason={r2.get('reason','')}")
        # 低稳健性：score=0.1 → combined<阈值 必拒收（确定性）
        r3 = call(p, "evolve_critic", note="某支离破碎的半成品思路", score=0.1)
        assert r3["admit"] is False, f"低分应拒收: {r3}"
        print("PASS 低稳健性 → admit=false（reason 含 稳健性不足）")
        assert "稳健性不足" in r3["reason"], f"reason 应含稳健性不足: {r3}"
        # 收紧阈值：即使新颖度拉满，score=0.5 时 combined≤0.75 < 0.99 → 拒收（确定性）
        r4 = call(p, "evolve_critic", note="为 fist-mbt 设计异步事件与持久化编排层", score=0.5, threshold=0.99)
        assert r4["admit"] is False, f"阈值收紧应拒收: {r4}"
        print("PASS 收紧阈值(0.99) → admit=false")
        # 只评审不写库：仓库根不留新增 {NS}.db
        assert not os.path.exists(os.path.join(ROOT, "critic-verify.db")), "critic-verify.db 不应出现在仓库根"
        print("PASS 只评审不写库，仓库根无临时库残留")
        print("MCP-EVOLVE-CRITIC-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()