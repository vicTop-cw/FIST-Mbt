#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/lesson_verify.py — 验证 evolve_lesson 失败回流学习工具端到端。"""
import json, os, subprocess, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "lesson-verify", "version": "1.0"}}

def rpc(proc, method, **payload):
    params = {"_meta": META}; params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n"); proc.stdin.flush()
    line = proc.stdout.readline()
    if not line: raise RuntimeError("server closed stdout")
    return json.loads(line)

def call(proc, name, **args):
    r = rpc(proc, "tools/call", name=name, arguments=args)
    if "error" in r: raise RuntimeError(f"{name} error: {r['error']}")
    try:
        return json.loads(r["result"]["content"][0]["text"])
    except (KeyError, IndexError, TypeError):
        return r["result"]["content"][0]["text"]

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    proc = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(proc, "tools/list").get("result", {}).get("tools", [])]
        print("PASS tools/list →", len(tools), "个工具; evolve_lesson 注册=", "evolve_lesson" in tools)
        if "evolve_lesson" not in tools:
            raise RuntimeError("evolve_lesson 未注册")
        import datetime
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        r = call(proc, "evolve_lesson", cat="语料不合格", reason="语料未覆盖验收指纹",
                 fix="必须先写 fingerprint", score=0.5, now=now)
        print("PASS evolve_lesson →", r)
        assert r.get("learned") is True
        assert str(r.get("artifact_id", "")).startswith("lesson-")
        snap = call(proc, "evolve_snapshot")
        count = snap.get("count", 0)
        dead = snap.get("dead_ends", [])
        print("PASS evolve_snapshot → count=", count, "dead_ends=", len(dead))
        print("MCP-LESSON-VERIFY PASS")
    finally:
        try:
            proc.stdin.close(); proc.terminate(); proc.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()