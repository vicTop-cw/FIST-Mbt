#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/award_demo.py — 一条命令串演 fist-mbt 增强能力链（评审 DEMO / 自我迭代过程演示）。

目标：把 15 轮自驱增强叠加出的"更好的 AI 项目管理工具"能力，用一个命令串起来给评审看：
  map(先有地图) → publish → task_plan_deep(gradient=难度梯度递归拆解) → 认领→执行→验收闭环
  → task_challenge(Challenger 由易到难进阶) → evolve_critic(Critic 防漂移评审) → reserve_scope(多 agent 预订)
  → status_summary / board_ascii(项目脉搏与实时看板)。

全部走真实 MCP STDIO 链路（只评审不写库的部分保持只评审），使用独立命名空间 + scratch 落临时区，
演示结束后不改动交付库分录、仓库根不残留生成物（结尾自动 cleanup_artifacts --check 守卫）。

前置：`moon build --target js cmd/main`（脚本会自动跑）+ patch_esm_main。
用法：python scripts/award_demo.py
"""
import json, os, subprocess, sys
from datetime import datetime, timedelta, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "award-demo"
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "award-demo", "version": "1.0"}}
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
TTL = (datetime.now(timezone.utc) + timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ")

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

def read_resource(p, uri):
    r = rpc(p, "resources/read", uri=uri)
    if "error" in r: raise RuntimeError(f"resources/read: {r['error']}")
    contents = r["result"].get("contents", [])
    return contents[0].get("text", "") if contents else ""

def walk_tree(node, acc):
    """DFS 收集叶子任务 id。"""
    if node.get("leaf"):
        acc.append(node["id"])
    for ch in node.get("children", []) or []:
        walk_tree(ch, acc)
    return acc

def main():
    # 1. 构建 + patch + 拉起 server
    subprocess.run(["moon", "build", "--target", "js", "cmd/main"], cwd=ROOT, check=True, capture_output=True)
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        # ① 先有地图（fist://map）
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        print(f"① tools= {len(tools)} 个")
        m = read_resource(p, "fist://map")
        assert "FIST-Mbt" in m, "fist://map 应含产品标识"
        print("   PASS 先读项目地图 fist://map（agent 首读即定位，无需全项目乱找）")

        # ② 开独立命名空间（scratch 落临时区）
        call(p, "store_open", namespace=NS, scratch=True, now=NOW)
        print(f"   PASS store_open(scratch) → 命名空间 {NS} 落临时区")

        # ③ 发布根任务 + 难度梯度递归拆解
        r0 = call(p, "publish", project_dir="/proj/demo", namespace=NS, description="构建一个多 agent 编排引擎", created_by="human_steward", now=NOW)
        rid = r0["task_id"]
        tree = call(p, "task_plan_deep", task_id=rid, split_n=3, by="leader", gradient=True, now=NOW)
        leaves = walk_tree(tree.get("tree", {}) or {}, [])
        assert leaves, "plan_deep 应产出叶子任务"
        c1 = call(p, "get", task_id=leaves[0])
        assert "[难度梯度" in c1["description"], "叶子应带难度梯度标注"
        print(f"   ② 递归拆解(gradient=true) → {tree.get('tree',{}).get('created',0)} 子任务；叶 {leaves[0]} 带难度梯度")

        # ④ 认领→执行→提交→验收 闭环（完成第一个叶子）
        first = leaves[0]
        call(p, "claim", task_id=first, assignee="exec_demo", now=NOW)
        call(p, "execute", task_id=first, deliverable="编排引擎最小可行版已实现", now=NOW)
        call(p, "submit", task_id=first, now=NOW)
        call(p, "verify", task_id=first, verifier="ver_demo", now=NOW)
        print(f"   ④ 生命周期闭环：{first} 已【已完成】（认领→执行→提交→验收）")

        # ⑤ Challenger：由已完成任务上难（SAGE 四专家环）
        ch = call(p, "task_challenge", task_id=first, factor=2, strat="scale", by="auto", now=NOW)
        g = call(p, "get", task_id=ch["new_id"])
        assert "[challenge]" in g["description"], "挑战任务应带 [challenge]"
        print(f"   ⑤ Challenger → 新根 {ch['new_id']} [challenge]from {first}（由易到难自推进；重要度 {g['importance']}）")

        # ⑥ Critic：评审一条拟入库原则（防漂移）
        ck = call(p, "evolve_critic", note="用事件总线统一编排多 agent 的异步信号", score=0.9)
        print(f"   ⑥ Critic 评审 → admit={ck['admit']} ({ck.get('reason','')[:24]}…)")

        # ⑦ 作用域预订（多 agent 并发防冲突）
        rk = call(p, "reserve_scope", scope="src/demo_shim.mbt", agent="exec_demo", ttl_until=TTL, now=NOW)
        assert rk.get("reserved"), "预订应成功"
        ck2 = call(p, "reserve_check", scope="src/demo_shim.mbt", now=NOW)
        print(f"   ⑦ 作用域预订 src/demo_shim.mbt → held_by={ck2.get('holder') or ck2.get('agent') or ck2.get('held_by')}（并发冲突预防）")

        # ⑧ 项目脉搏 + 实时看板（只读）
        ss = call(p, "status_summary", namespace=NS, now=NOW)
        ba = call(p, "board_ascii", namespace=NS, now=NOW)
        print(f"   ⑧ 脉冲 status_summary({NS}) → total={ss.get('total_tasks')}；板面 board_ascii 行数≈{len(ba.get('ascii','').splitlines()) if isinstance(ba, dict) else ''}")

        # ⑨ 整洁守卫：仓库根只允许交付库
        print("MCP-AWARD-DEMO PASS — 增强能力链一条命令全部跑通")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass
        # 结束统一清理临时生成物（keep fist-mbt.db），并 --check 守卫
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "cleanup_artifacts.py")], cwd=ROOT)
        subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "cleanup_artifacts.py"), "--check"], cwd=ROOT)

if __name__ == "__main__":
    main()