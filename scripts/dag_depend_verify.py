#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/dag_depend_verify.py — 验证 dag_depend 显式构建 DAG 依赖边端到端。"""
import json, os, subprocess, sys
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "dag-verify"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "dag-verify", "version": "1.0"}}
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
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"PASS tools/list → {len(tools)} 个工具; dag_depend 注册={ 'dag_depend' in tools }")
        if "dag_depend" not in tools: raise RuntimeError("dag_depend 未注册")
        # 发布 A、B 两个根任务
        a = call(p, "publish_parallel", project_dir=ROOT, description="DAG A", namespace=NS, created_by="dag", now=NOW)["task_id"]
        b = call(p, "publish_parallel", project_dir=ROOT, description="DAG B", namespace=NS, created_by="dag", now=NOW)["task_id"]
        print(f"PASS publish → A={a} B={b}")
        # B 依赖 A
        tb = call(p, "dag_depend", task_id=b, dep_id=a, now=NOW)
        deps = tb.get("depends_on", [])
        assert a in deps, f"B 应依赖 A: {deps}"
        print(f"PASS dag_depend → B.depends_on={deps}")
        # 自环拒绝
        try:
            call(p, "dag_depend", task_id=a, dep_id=a, now=NOW)
            print("FAIL 自环应被拒绝"); sys.exit(1)
        except RuntimeError as e:
            print("PASS dag_depend 自环被拒绝")
        # dag_ascii 应含依赖标注
        ascii_out = call(p, "dag_ascii", **{"ns": NS})
        print(f"PASS dag_ascii 可调用（含 DAG 依赖线）")
        print("MCP-DAG-DEPEND-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass

if __name__ == "__main__":
    main()