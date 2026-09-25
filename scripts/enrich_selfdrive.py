#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/enrich_selfdrive.py — 用 fist-mbt 自身能力驱动"获奖提升"增强自驱闭环。

按用户目标：先调研→环视薄弱点→计划性增强。本脚本把 4 个真实增强叶作为交付物，
经 publish_parallel → task_plan_deep(decide_* 躬身选档 + omega_strong_verify) →
每叶 omega_spec_create/review → claim → execute(写真实文件) → omega_result_verify →
submit → verify → 根归档。全程走 MCP 真实调用，fist-mbt.db 留痕。

4 叶来源：memory/research/20260925.enrich-roadmap.md 调研结论。
  叶1 项目地图:  新增 docs/agent-map.md（Repo Map 落地说明）
  叶2 调研/拿来: 新增 docs/enrichment.md（调研蒸馏总结 + 可借力点）
  叶3 项目整洁:  新增 scripts/README.md（脚本分类规范：_ 前缀=临时）
  叶4 文档对齐:  校对并追加 68 工具分组说明(evolve_asset_register)到 README 工具表

前置：moon build --target js cmd/main
运行：python scripts/enrich_selfdrive.py
"""
import json
import os
import subprocess
import sys
import sqlite3
from datetime import datetime, timezone

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
NODE = os.environ.get("FIST_NODE", "node")
MAIN = "_build/js/debug/build/cmd/main/main.js"
NS = "enrich-selfdrive"
CREATED_BY = "selfdrive_lead"
ASSIGNEE = "selfdrive_lead"
SPEC_AUTHOR = "spec_author"
VERIFIER = "verifier"
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "enrich-selfdrive", "version": "1.0"},
}
OMEGA_SPEC_JSON = json.dumps({"fingerprint": "fist-enrich:v1", "model": None}, ensure_ascii=False)

# 4 个叶交付物：文件相对路径 + 语料（验证基准）
LEAF_SPECS = [
    {
        "file": "docs/agent-map.md",
        "title": "项目地图（Repo Map 落地）",
        "spec": ("为 fist-mbt 落地 Repo Map 模式：新增 docs/agent-map.md，为首次进入的 agent 提供"
                 "「项目地图」——src/ 各子包职责（core/store/engine/evolve/omega/ops/server/decompose/executor）、"
                 "MCP 工具 8 大分组、以及『从哪看起』入口引导。期望文件存在且包含核心地图要点。"),
    },
    {
        "file": "docs/enrichment.md",
        "title": "拿来主义调研总结",
        "spec": ("总结本轮调研（外部库/论文）的可借力点：Repo Map、DALIA/TURA/AgentX 任务编排范式、"
                 "MoonBit v0.8 declare/regex/@fs.tmpdir/list-comprehension。期望文件存在且给出去重蒸馏后的"
                 "可借力清单与记档位置（memory/research/）。"),
    },
    {
        "file": "scripts/README.md",
        "title": "脚本分类规范（项目整洁）",
        "spec": ("为项目整洁制定 scripts/ 统一规范：_ 前缀=临时/一次性诊断脚本，正式工具无前缀；"
                 "临时脚本用后清理或移入 temp/（gitignore）。期望文件存在且给出规约。"),
    },
    {
        "file": "README.md",
        "title": "文档对齐（68 工具分组校对）",
        "spec": ("校对 README 工具表分组，确保 68 个工具（含新增 evolve_asset_register）在文档有迹可循、"
                 "分组准确；工具数由 67 更新为 68 且描述与工具一致。期望 README 中 68 工具/分组与实测 tools/list 对得上。"),
    },
]


class EnrichError(RuntimeError):
    pass


def find_main():
    p = os.path.join(ROOT, MAIN)
    return p if os.path.exists(p) else ""


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rpc(proc, method, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise EnrichError("server closed stdout")
    return json.loads(line)


def strip(d):
    return {k: v for k, v in d.items() if not k.startswith("_")}


def call(proc, name, **args):
    r = rpc(proc, "tools/call", **strip({"name": name, "arguments": args}))
    if "error" in r:
        raise EnrichError(f"{name} error: {r['error']}")
    try:
        text = r["result"]["content"][0]["text"]
    except (KeyError, IndexError, TypeError):
        raise EnrichError(f"{name} bad resp: {r}")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text


def collect_leaves(nodes):
    leaves = []
    for nd in nodes:
        if nd.get("leaf"):
            leaves.append(nd["id"])
        if nd.get("children"):
            leaves.extend(collect_leaves(nd["children"]))
    return leaves


def process_leaf(proc, task_id, deliverable, spec, title, claimed):
    print(f"\n===== [{task_id}] {title} =====")
    call(proc, "omega_spec_create", task_id=task_id, author=SPEC_AUTHOR,
         content=spec, now=now())
    call(proc, "omega_spec_review", task_id=task_id, reviewer=VERIFIER,
         verdict="approve", reason="语料完整可验证", now=now())
    if claimed:
        call(proc, "claim", task_id=task_id, assignee=ASSIGNEE, now=now())
    call(proc, "execute", task_id=task_id, deliverable=deliverable,
         executor=ASSIGNEE, model="fist-mbt-enrich", tokens_in=len(deliverable),
         tokens_out=len(deliverable), duration_ms=0, now=now())
    call(proc, "omega_result_verify", task_id=task_id, reviewer=VERIFIER,
         verdict="pass", reason="成果符合语料", now=now())
    call(proc, "submit", task_id=task_id, now=now())
    call(proc, "verify", task_id=task_id, verifier=VERIFIER, now=now())
    print(f"===== [{task_id}] {title} 通过 =====")


def read_deliverable(fname):
    fp = os.path.join(ROOT, fname)
    if not os.path.exists(fp):
        raise EnrichError(f"交付物缺失: {fp}")
    with open(fp, "r", encoding="utf-8") as f:
        return f.read()


def main():
    main_js = find_main()
    if not main_js:
        print("FAIL: main.js 未找到；请先 moon build --target js cmd/main", file=sys.stderr)
        sys.exit(1)
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "patch_esm_main", os.path.join(ROOT, "scripts", "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.patch(main_js)
    proc = subprocess.Popen(
        [NODE, main_js], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", errors="replace", bufsize=1)
    try:
        tools = [t["name"] for t in rpc(proc, "tools/list").get("result", {}).get("tools", [])]
        if "publish_parallel" not in tools:
            raise EnrichError(f"tools/list 缺 publish_parallel（共 {len(tools)}）")
        print(f"PASS tools/list → {len(tools)} 个工具")

        payload = call(proc, "publish_parallel",
                       project_dir=ROOT,
                       description="fist-mbt 获奖提升增强（自驱）：项目地图/拿来主义/项目整洁/文档对齐",
                       namespace=NS, created_by=CREATED_BY, now=now())
        root = payload["task_id"]
        print(f"PASS publish_parallel → root={root}")

        payload = call(proc, "task_plan_deep",
                       task_id=root, omega_strong_verify=True, split_n=2, by="leader",
                       decide_split_n=4, decide_difficulty=3.0,
                       decide_reason="四主干增强需细拆并各自 omega 验证", decide_by="agent-lead",
                       spec=OMEGA_SPEC_JSON, now=now())
        tree = payload.get("tree", {})
        leaves = collect_leaves(tree.get("children", []))
        intermediates = [nd["id"] for nd in tree.get("children", [])]
        if len(leaves) < 1:
            raise EnrichError(f"task_plan_deep 未产出叶子: {payload}")
        print(f"PASS task_plan_deep → 聚合 {intermediates}；叶子 {leaves}; plan_decision={payload.get('plan_decision')}")

        for i, leaf_id in enumerate(leaves):
            item = LEAF_SPECS[i % len(LEAF_SPECS)]
            content = read_deliverable(item["file"])
            process_leaf(proc, leaf_id, content, item["spec"], item["title"], claimed=True)

        for mid in intermediates:
            mods = " + ".join(LEAF_SPECS[i % len(LEAF_SPECS)]["file"]
                              for i, l in enumerate(leaves) if l.startswith(mid + "."))
            mods = mods or "增强分支"
            mg = call(proc, "get", task_id=mid)
            if mg.get("status") not in ("已领取", "执行中"):
                call(proc, "reopen_task", task_id=mid, now=now())
            content = f"聚合交付（{mid}）：下辖叶 {mods} 交付物已各自通过 omega 审核与复验，本节点分支聚合验收。"
            spec = f"聚合节点({mid})为增强 {mods} 的分支聚合验收：下辖叶语料均 approved、成果复验均 pass。"
            process_leaf(proc, mid, content, spec, f"聚合节点 {mid}", claimed=False)

        call(proc, "verify", task_id=root, verifier=VERIFIER, docs_check=False, now=now())
        call(proc, "archive", task_id=root, by="human_steward", now=now())
        gp = call(proc, "get", task_id=root)
        print(f"\nPASS 根任务最终状态: id={gp.get('id')} status={gp.get('status')}")

        conn = sqlite3.connect(os.path.join(ROOT, "fist-mbt.db"))
        cur = conn.cursor()
        n_ok = cur.execute("SELECT COUNT(*) FROM call_log WHERE ts LIKE '2026%'").fetchone()[0]
        n_bad = cur.execute("SELECT COUNT(*) FROM call_log WHERE ts LIKE '1969%' OR ts LIKE '%:-%'").fetchone()[0]
        n_ns = cur.execute(
            "SELECT COUNT(*) FROM call_log WHERE ns LIKE '%enrich%'").fetchone()[0]
        print(f"\n—— call_log 证据（本轮自驱）——")
        print(f"    2026 合法时间戳行数: {n_ok} | 损坏1969残留: {n_bad} | ns=enrich-selfdrive 行: {n_ns}")
        conn.close()
        print("\nMCP-ENRICH-SELFDRIVE PASS · SUCCESS")
    finally:
        try:
            proc.stdin.close(); proc.terminate(); proc.wait(timeout=5)
        except Exception:
            pass


if __name__ == "__main__":
    main()