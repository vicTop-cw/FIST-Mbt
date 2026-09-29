#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/scratch_verify.py — 验证 store_open scratch=true 临时命名空间落 temp/ 不污染仓库根。"""
import json, os, subprocess, sys
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
# BUG-122 同型收口：不带 FIST_DB_PATH 裸跑会把演示数据写进仓库根的自举台账 fist-mbt.db。
# 默认改道 temp/ 下的隔离库；调用方显式设过 FIST_DB_PATH 就照它的（store_isolation_probe 那类必须自己控制）。
_FIST_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if not (os.environ.get("FIST_DB_PATH") or "").strip():
    os.environ["FIST_DB_PATH"] = os.path.join(_FIST_ROOT, "temp", "scratch_verify.db")
MAIN = "_build/js/debug/build/cmd/cli/cli.js"
NS = "scratch-verify"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "scratch-verify", "version": "1.0"}}
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
    p = subprocess.Popen([NODE, MAIN, "serve"], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具")
        r = call(p, "store_open", namespace=NS, scratch=True, now=NOW)
        print(f"PASS store_open scratch → data_dir={r.get('data_dir')} scratch={r.get('scratch')} opened={r.get('opened')}")
        assert r.get("data_dir") == "temp", f"scratch 应落 temp/: {r}"
        # 仓库根不应产生 {NS}.db（应落 temp/{NS}.db）
        root_db = os.path.join(ROOT, NS + ".db")
        if os.path.exists(root_db):
            raise RuntimeError(f"仓库根出现临时库: {root_db}")
        temp_db = os.path.join(ROOT, "temp", NS + ".db")
        print(f"PASS 仓库根无 {NS}.db；temp/ 有库: {os.path.exists(temp_db)}")
        print("MCP-SCRATCH-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()