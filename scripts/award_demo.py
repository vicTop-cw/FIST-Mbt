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

        # ③b 真实 DAG 前驱链 + 执行计划视图（R39/R40/R44 纵向串联：先易后逆推 → 计划 → 难度分布）
        r1 = call(p, "publish", project_dir="/proj/demo", namespace=NS,
                  description="搭建可插拔的父层调度（拆解演练）", created_by="human_steward", now=NOW)
        rid1 = r1["task_id"]
        t1 = call(p, "task_plan_deep", task_id=rid1, split_n=3, by="leader",
                  gradient=True, gradient_dag=True, reinject_context=True, now=NOW)
        eo = t1.get("exec_order") or {}
        assert "order" in eo, "gradient_dag 拆解应返回 exec_order 执行计划"
        order_ids = [s.get("id") for s in (eo.get("order") or [])]
        assert order_ids, "exec_order 应有非空执行计划"
        step_str = " → ".join(
            f"{s.get('id')}[{s.get('difficulty','')}]" for s in (eo.get("order") or [])[:4]
        )
        print(f"   ③b 真实DAG+执行计划：gradient_dag=true → 兄弟切片由易到难连 depends_on；"
              f"exec_order {eo.get('count')} 步执行计划：{step_str}"
              f"{'…' if len(order_ids) > 4 else ''}（每步附难度档，照单执行）")
        # R63 父计划回注：开启 reinject_context 后子任务描述带【父计划】让原子片知其所以然
        ctx_pick = call(p, "get", task_id=f"{rid1}.1") or {}
        ctx_desc = ctx_pick.get("description") or ""
        assert "[父计划:" in ctx_desc, "reinject_context 应让子任务描述携带父计划（R63）"
        print(f"      ↳ R63 父计划回注：{rid1}.1 描述含【{ctx_desc[ctx_desc.find('[父计划:'):][:40]}…】"
              f"（原子片知其所归属，防上下文漂移）")
        ss1 = call(p, "status_summary", namespace=NS, now=NOW)
        bd = (ss1.get("by_difficulty") or {})
        print(f"   ③c 项目脉冲 status_summary → 待办难度分布 by_difficulty："
              f"易={bd.get('易', 0)}/中={bd.get('中', 0)}/难={bd.get('难', 0)}/无={bd.get('无', 0)}"
              f"（难度结构一目了然，R44 复用单一抽取来源）")
        print("   PASS 拆解即给一张按依赖可安全执行的计划，agent 照单执行")

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

        # ⑧ 项目脉搏 + 实时看板 + 健康卡 + 下一步推荐（只读）
        ss = call(p, "status_summary", namespace=NS, now=NOW)
        ba = call(p, "board_ascii", namespace=NS, now=NOW)
        print(f"   ⑧ 脉冲 status_summary({NS}) → total={ss.get('total_tasks')}；板面 board_ascii 行数≈{len(ba.get('ascii','').splitlines()) if isinstance(ba, dict) else ''}")
        # R68 项目健康卡：单次调用看全项目健康（一条命令给出等级+阻塞详情）
        ph = call(p, "project_health", namespace=NS, now=NOW)
        assert ph.get("grade") in ("empty", "attention", "stalled", "healthy"), "health 应给出合法等级"
        print(f"      ↳ R68 项目健康卡 project_health({NS}) → grade={ph.get('grade')}；"
              f"in_flight={ph.get('in_flight')} ready={ph.get('ready')} done={ph.get('done')} "
              f"blocked={ph.get('blocked')}（一眼看全项目健康，不逐条 list）")
        # R77 依赖图成本路由：排程优化闭环最终形态（STAR 式蒸馏，纯读不 claim）
        rpc(p, "tools/call", name="executor_register", arguments={
            "name": "exec_demo", "abilities": ["编排"], "now": NOW,
        })
        cr = call(p, "dag_cost_route", now=NOW)
        assert "cost_route" in cr and "total_est_cost" in cr, "cost_route 应返回 cost_route/total_est_cost"
        print(f"      ↳ R77 依赖图成本路由 dag_cost_route → {len(cr.get('cost_route', []))} 条建议，"
              f"total_est_cost={cr.get('total_est_cost')}（执行成本难度档+切换税+能力约束，"
              f"critical_path→slack→schedule→cost_route 闭环）")
        # R80 历史信任轴：executor_route 按 能力覆盖→信任→负载 排序（防只认领不交付）
        er2 = call(p, "executor_route", need="编排")
        best = er2.get("best", {}) or {}
        assert "candidates" in er2, "executor_route 应返回 candidates"
        print(f"      ↳ R80 历史信任轴 executor_route(need=编排) → best={best.get('name')} "
              f"trust={best.get('trust')} load={best.get('load')}（能力覆盖→信任→负载，防只认领不交付）")
        # R81 预算阶段切分：预算在依赖图上按阶段切分，瓶颈阶段占额可见
        bs = call(p, "cost_budget_split", budget=100, now=NOW)
        assert "stages" in bs and "total_budget" in bs, "cost_budget_split 应返回 stages/total_budget"
        print(f"      ↳ R81 预算阶段切分 cost_budget_split(100) → {len(bs.get('stages', []))} 阶段，"
              f"makespan={bs.get('makespan')}（预算按 DAG 阶段切分：瓶颈阶段占额可见，超支先预警）")
        # R87 置信度校准拍卖：按出价竞拍（校准系数 1-|出价-兑现率| 防胜者诅咒，Agora 蒸馏）
        au = call(p, "executor_auction", need="编排", bid={"exec_demo": 0.9, "manual": 0.6})
        aw = au.get("winner", {}) or {}
        assert "bids" in au and "winner" in au, "executor_auction 应返回 bids/winner"
        print(f"      ↳ R87 置信度校准拍卖 executor_auction(need=编排) → 竞拍 {au.get('count')} 家，"
              f"winner={aw.get('name')} calibration={aw.get('calibration')} score={aw.get('score')} "
              f"（Agora 蒸馏：出价×校准×负载折扣，过度自信者被惩罚）")
        # R88 进度预算路由门控：预算×进度双路径预测 + 元门控决策（PROGROUTER 蒸馏）
        pg = call(p, "progress_gate", task_id=rid, budget=20, now=NOW)
        assert pg.get("ok") and "verdict" in pg, "progress_gate 应返回 ok/verdict"
        print(f"      ↳ R88 进度预算门控 progress_gate({rid}, budget=20) → progress={pg.get('progress')} "
              f"spent={pg.get('spent')} verdict={pg.get('verdict')} "
              f"（PROGROUTER 蒸馏：线性/保守双路径预测，预算×进度在线体检）")
        # R89 Phi Accrual 概率式故障检测：按心跳间隔分布算怀疑度 φ（替代固定 timeout）
        ph = call(p, "phi_accrual", intervals=[5, 10, 15, 10, 10], elapsed=60)
        assert ph.get("verdict") in ("healthy", "suspect", "insufficient"), "phi_accrual 应返回 verdict"
        print(f"      ↳ R89 概率式故障检测 phi_accrual(μ=10s σ≈3.5, elapsed=60s) → φ={ph.get('phi')} "
              f"verdict={ph.get('verdict')} （Phi Accrual：φ=-log10(P 心跳晚到)，越久越怀疑，替代固定 timeout）")
        # R96 Saga 局部补偿控级联：失败步骤 → 最小补偿切片（演示无 task_id，走注册序 basis=order）
        for stp in ("step1", "step2", "step3"):
            call(p, "saga_register", root_task_id="demo-root", step=stp,
                 compensation="undo " + stp, now=NOW)
        rep = call(p, "saga_repair", root_task_id="demo-root", failed_step="step2", mark=True)
        assert rep.get("basis") in ("depends_on", "order"), "saga_repair 应返回 basis"
        assert len(rep.get("compensate", [])) == 2 and len(rep.get("keep", [])) == 1, \
            "应只补偿失败步骤+其下游、保留先前承诺"
        print(f"      ↳ R96 局部补偿 saga_repair(demo-root, step2 失败) → basis={rep.get('basis')} "
              f"compensate={[s['step'] for s in rep.get('compensate', [])]} "
              f"keep={[s['step'] for s in rep.get('keep', [])]} "
              f"（最小切片补偿控级联，保留未受影响承诺；depends_on 闭包版见单测）")
        # R98 反馈驱动的计划修订：对 ③b 拆解的根任务做执行反馈修订（读真实状态 basis=status）
        rv = call(p, "plan_revise", root_task_id=rid1)
        assert rv.get("ok") is True, "plan_revise 应 ok"
        assert len(rv.get("ready", [])) >= 1, "plan_revise 应给出下一步 ready"
        print(f"      ↳ R98 计划修订 plan_revise({rid1}) → basis={rv.get('basis')} "
              f"keep={rv.get('keep_count')} rework={rv.get('rework_count')} "
              f"ready={rv.get('ready_count')} "
              f"（ReAct/CoPAL：执行反馈 → keep/rework/ready 三分修订，下一步可做 "
              f"{len(rv.get('ready', []))} 条，控级联不涟漪）")
        # R100 全局目标校验：对 ③b 拆解的根任务校验 drift/冗余（读真实描述，纯计算）
        gd = call(p, "goal_drift_check", root_task_id=rid1)
        assert gd.get("ok") is True, "goal_drift_check 应 ok"
        cnt = gd.get("counts", {})
        print(f"      ↳ R100 目标校验 goal_drift_check({rid1}) → aligned={cnt.get('aligned')} "
              f"drift_suspect={cnt.get('drift_suspect')} redundant_suspect={cnt.get('redundant_suspect')} "
              f"（goal drift 防偏离根目标 + non-redundancy 防重复子目标，词法 Jaccard 纯计算零 LLM）")
        # R102 四金信号健康巡检：SRE Book 2016 latency/traffic/errors/saturation
        hc = call(p, "health_check", namespace=NS)
        assert hc.get("grade") in ("healthy", "attention", "idle"), "health_check 应返回 grade"
        sig = hc.get("signals", {})
        print(f"      ↳ R102 四金信号巡检 health_check({NS}) → grade={hc.get('grade')} "
              f"latency={sig.get('latency', {}).get('verdict')} traffic={sig.get('traffic', {}).get('verdict')} "
              f"errors={sig.get('errors', {}).get('verdict')} saturation={sig.get('saturation', {}).get('verdict')} "
              f"（SRE Book 2016：积压饱和为先行指标，先积压后坏 >0.5 预警）")
        tr = call(p, "task_triage", namespace=NS, agent="exec_demo", want="编排")
        assert tr.get("count", 0) >= 1, "triage 应至少 1 条可领取"
        assert tr.get("suggestion"), "triage 应有 suggestion"
        print(f"   ⑨ 下一步推荐 task_triage({NS}) → 可领取 {tr.get('count')} 条，suggestion 指向 {tr.get('suggestion',{}).get('task_id')}（want={tr.get('want','')} 能力路由）")
        pk = call(p, "selfdrive_pick_next", namespace=NS, agent="exec_demo", want="编排", now=NOW)
        assert pk.get("claimed"), "应按推荐自动取单认领"
        print(f"   ⑩ 自驱取单 selfdrive_pick_next({NS}) → 认领 {pk.get('picked')}（remaining={pk.get('remaining')}，按能力推荐自动推进）")
        # ⑪ 自推进闭环：对该取中的任务 执行→提交→验收，再重推荐，证明"推荐→取单→执行→验收→再推荐"整圈通
        picked = pk.get("picked")
        call(p, "execute", task_id=picked, deliverable="已按推荐取单并完成", now=NOW)
        call(p, "submit", task_id=picked, now=NOW)
        call(p, "verify", task_id=picked, verifier="ver_demo", now=NOW)
        tr2 = call(p, "task_triage", namespace=NS, agent="exec_demo", want="编排")
        print(f"   ⑪ 推荐→取单→执行→验收→再推荐：{picked} 已完成；重推荐可领取 {tr2.get('count')} 条、suggestion 指向 {tr2.get('suggestion',{}).get('task_id')}")

        # ⑫ 整洁守卫：仓库根只允许交付库
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