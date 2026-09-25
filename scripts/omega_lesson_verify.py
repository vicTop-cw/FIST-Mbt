#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/omega_lesson_verify.py — 端到端验证「Omega 打回自动落 [lesson] 教训」。

驱动真实 MCP server：发布 Omega 强验证任务 → 递归拆解 → 语料被验证者打回 →
成果复验打回 → 断言每次打回都自动把失败原因沉淀进 evolve_artifacts（[lesson] 资产），
并经 SQLite 直接读回证明落库（供 plan/claim 的 inject 与 dead_ends 后续检索）。
用 scratch 命名空间（temp/）隔离证据库，结束后清理，不污染仓库根。
"""
import json, os, sqlite3, subprocess, sys
from datetime import datetime, timezone
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "omega-lesson-verify"
NOW = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
META = {"io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "omega-lesson-verify", "version": "1.0"}}
DB = os.path.join(ROOT, "fist-mbt.db")          # 根库（evolve_artifacts 可能落此）
TMP_NS_DB = os.path.join(ROOT, "temp", NS + ".db")  # scratch 命名空间库
CAND_DBS = [DB, TMP_NS_DB]
# 本脚本唯一写入的教训原因（用于结束时精确清理，避免误删其它自驱证据）
SCRIPT_REASONS = ("验收标准不量化", "成果未达标")

def _lessons_of(db):
    """读单库的 omega-lesson 教训行列表。"""
    if not os.path.exists(db):
        return []
    con = sqlite3.connect(db); con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(
            "SELECT id, goal, note, code FROM evolve_artifacts WHERE id LIKE 'omega-lesson%' ORDER BY created_at")]
    finally:
        con.close()

def lessons_in_db(_prefix):
    """跨候选库（根库 + scratch 库）聚合 omega-lesson 教训。"""
    out = []
    for db in CAND_DBS:
        out.extend(_lessons_of(db))
    return out

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
    try:
        return json.loads(r["result"]["content"][0]["text"])
    except (KeyError, IndexError, TypeError):
        return r["result"]["content"][0]["text"]

def lessons_in_db(prefix):
    """从根库读回已沉淀的教训（id 前缀匹配）。"""
    if not os.path.exists(DB):
        return []
    con = sqlite3.connect(DB); con.row_factory = sqlite3.Row
    try:
        rows = con.execute(
            "SELECT id, goal, note, code FROM evolve_artifacts WHERE id LIKE ? ORDER BY created_at",
            (prefix + "%",)).fetchall()
        return [dict(r) for r in rows]
    finally:
        con.close()

def cleanup_root_lessons():
    """剔除本脚本写入的教训（跨候选库、仅按本脚本原因精确匹配），保证根库整洁。"""
    total = 0
    for db in CAND_DBS:
        if not os.path.exists(db):
            continue
        try:
            con = sqlite3.connect(db)
            try:
                marks = ",".join("'" + r + "'" for r in SCRIPT_REASONS)
                cur = con.execute(
                    "DELETE FROM evolve_artifacts WHERE id LIKE 'omega-lesson%' AND note IN (" +
                    marks + ")")
                con.commit()
                total += cur.rowcount
            finally:
                con.close()
        except Exception:
            pass
    return total

def main():
    import importlib.util
    spec = importlib.util.spec_from_file_location("patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); mod.patch(MAIN)
    p = subprocess.Popen([NODE, MAIN], cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(p, "tools/list").get("result", {}).get("tools", [])]
        for t in ("omega_spec_review", "omega_result_verify"):
            assert t in tools, f"{t} 未注册（tools/list → {len(tools)}）"
        print(f"PASS tools/list → {len(tools)} 个工具")

        # 隔离到 scratch 命名空间（temp/），不污染仓库根
        call(p, "store_open", namespace=NS, scratch=True, now=NOW)
        root = call(p, "publish", project_dir="/proj/omega-e2e",
                    description="Omega 打回自动落教训 E2E", namespace=NS,
                    created_by="human_steward", now=NOW)
        root_id = root["task_id"]
        call(p, "claim", task_id=root_id, assignee="leader_a", now=NOW)
        call(p, "task_plan_deep", task_id=root_id, split_n=1, by="leader_a",
             omega_strong_verify=True, now=NOW)
        tasks = call(p, "list", namespace=NS)
        if isinstance(tasks, dict): tasks = tasks.get("tasks", tasks)
        child = next(
            t for t in tasks
            if t.get("status") == "待领取" and "omega:required" in t.get("description", "")
        )
        cid = child["id"]
        print(f"PASS 发布+递归拆解 → root={root_id} omega 叶={cid}")

        # ① 语料被打回 → 自动落 [lesson] omega.spec_rejected
        call(p, "omega_spec_create", task_id=cid, author="spec_author",
             content="验收标准 v1", now=NOW)
        r1 = call(p, "omega_spec_review", task_id=cid, reviewer="verifier",
                  verdict="reject", reason="验收标准不量化", now=NOW)
        assert r1.get("learned_lesson") is True, f"spec 打回未自动学习: {r1}"
        print(f"PASS 语料打回 → learned_lesson={r1.get('learned_lesson')}")

        # ② 语料重做通过 + 执行 + 提交 → 成果复验打回 → 自动落 [lesson] omega.result_rejected
        call(p, "omega_spec_create", task_id=cid, author="spec_author",
             content="验收标准 v2（可量化）", now=NOW)
        call(p, "omega_spec_review", task_id=cid, reviewer="verifier", verdict="approve", now=NOW)
        call(p, "claim", task_id=cid, assignee="exec_1", now=NOW)
        call(p, "execute", task_id=cid, deliverable="成果 v1", now=NOW)
        call(p, "submit", task_id=cid, now=NOW)
        r2 = call(p, "omega_result_verify", task_id=cid, reviewer="verifier",
                  verdict="fail", reason="成果未达标", now=NOW)
        assert r2.get("learned_lesson") is True, f"复验打回未自动学习: {r2}"
        print(f"PASS 成果复验打回 → learned_lesson={r2.get('learned_lesson')}")

        # ③ 直接读 SQLite 证明两类教训已落库（下一步 inject/dead_ends 可检索）
        lessons = lessons_in_db("omega-lesson-")
        goals = [l["goal"] for l in lessons]
        notes = [l["note"] for l in lessons]
        assert any("omega.spec_rejected" in g for g in goals), f"缺少 spec_rejected 教训: {goals}"
        assert any("验收标准不量化" in n for n in notes), f"spec 教训未记原因: {notes}"
        assert any("omega.result_rejected" in g for g in goals), f"缺少 result_rejected 教训: {goals}"
        assert any("成果未达标" in n for n in notes), f"复验教训未记原因: {notes}"
        print(f"PASS 库内 [lesson] 教训 {len(lessons)} 条 → " + "; ".join(goals))
        print("MCP-OMEGA-LESSON-VERIFY PASS")
    finally:
        try:
            p.stdin.close(); p.terminate(); p.wait(timeout=5)
        except Exception:
            pass
        # 整洁：剔除本脚本写入根库的教训 + 清理 scratch 临时库，不残留
        removed = cleanup_root_lessons()
        if removed:
            print(f"(cleanup 根库教训 {removed} 条)")
        for suffix in ("", "-wal", "-shm"):
            fp = TMP_NS_DB + suffix
            if os.path.exists(fp):
                try: os.remove(fp)
                except OSError: pass

if __name__ == "__main__":
    main()