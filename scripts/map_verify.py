#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/map_verify.py — 验证 fist://map 项目地图 resource 端到端可用。"""
import json, os, subprocess, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "map-verify", "version": "1.0"}}

def rpc(proc, method, **payload):
    params = {"_meta": META}; params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n"); proc.stdin.flush()
    line = proc.stdout.readline()
    if not line: raise RuntimeError("server closed stdout")
    return json.loads(line)

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    proc = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        r = rpc(proc, "resources/list")
        res = r.get("result", {}).get("resources", [])
        names = [x.get("uri") for x in res]
        print("PASS resources/list →", names)
        if "fist://map" not in names:
            raise RuntimeError("fist://map 未注册")
        r = rpc(proc, "resources/read", uri="fist://map")
        content = r.get("result", {}).get("contents", [])
        if not content:
            raise RuntimeError("fist://map 读为空")
        text = content[0].get("text", "")
        payload = json.loads(text)
        assert payload.get("product") == "FIST-Mbt"
        assert "engine" in payload.get("packages", {})
        assert "生命周期" in payload.get("tool_groups", {})
        # R36：地图须含最新分组（Marketplace·能力路由 / 看板·脉冲·预订·推荐+DAG / 自驱含 pick_next）
        assert "Marketplace·能力路由" in payload.get("tool_groups", {}), "地图缺 Marketplace 分组"
        assert "看板/脉冲/预订/推荐+DAG" in payload.get("tool_groups", {}), "地图缺看板/脉冲分组"
        assert "executor_register" in payload.get("tool_groups", {}).get("Marketplace·能力路由", "")
        print("PASS resources/read fist://map → product=", payload.get("product"),
              "packages=", list(payload.get("packages", {})), "tool_groups=", list(payload.get("tool_groups", {})))
        print("MCP-MAP-VERIFY PASS")
    finally:
        try:
            proc.stdin.close(); proc.terminate(); proc.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()