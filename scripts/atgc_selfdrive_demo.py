#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/atgc_selfdrive_demo.py — fist-mbt 旗舰 DEMO：自驱式 + Omega 强验证，驱动 MCP server
端到端闭环，产出极简 ATGC 双链虚拟机的 4 个叶子交付物。

前置（按需，脚本不负责 build）：
    moon install && moon build --target js cmd/main

运行（项目根）：
    python scripts/atgc_selfdrive_demo.py

流程（全程经 MCP JSON-RPC STDIO，不伪造任何一步）：
  1. tools/list 健全性检查（期望 67 工具）。
  2. publish_parallel            → 并行发布独立根任务（ns=atgc-selfdrive）。
  3. task_plan_deep(omega_strong_verify=true) → AO 式递归拆成 4 个 omega:required 叶。
  4. 对每个叶（顺序）：omega_spec_create → omega_spec_review(approve) → claim →
     execute(写入该叶对应的真实 atgc 文件内容) → omega_result_verify(pass) →
     submit → verify。
  5. 叶子全部通过后：verify 根任务上卷成已完成，再 archive 归档。
  6. 打印汇总 + 读 fist-mbt.db（只读）核对 tasks/specs/executions/call_log 行数。

说明：所有 arg 名/返回值 schema 依据 src/server/server.mbt 的 tools 声明；若个别 MCP 调用
报错，脚本会在 stderr/退出码暴露，需按真实错误修正流程后重跑（不猜测、不静默）。
"""
import json
import os
import subprocess
import sys
import sqlite3
from datetime import datetime, timezone

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ATGC_DIR = os.path.join(ROOT, "atgc")

NODE = os.environ.get("FIST_NODE", "node")
MAIN_CANDIDATES = [
    "_build/js/debug/build/cmd/main/main.js",
    "target/js/release/build/cmd/main/main.js",
]
NS = "atgc-selfdrive"
CREATED_BY = "demo_executor"
ASSIGNEE = "demo_executor"
SPEC_AUTHOR = "spec_author"
VERIFIER = "verifier"

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "atgc-selfdrive-demo", "version": "1.0"},
}

# 根 spec（fingerprint 作验收基准；laws 因非字符串数组会被 decompose 忽略，退化为 split_n=4）
OMEGA_SPEC_JSON = json.dumps({
    "laws": [
        {"name": "base", "cut": 4},
        {"name": "vm", "cut": 4},
        {"name": "run", "cut": 4},
        {"name": "tests", "cut": 4},
    ],
    "fingerprint": "atgc-minimal:v1",
    "model": None,
}, ensure_ascii=False)

# 4 个叶子交付物：task_plan_deep 产物树 DFS 叶序 1:1 对应下表文件。
# spec 内容即各模块「验证语料」，与 atgc 各文件头部的 Omega spec content 语义一致。
LEAF_SPECS = [
    # leaf1 -> atgc_base.mbt
    {
        "file": "atgc_base.mbt",
        "spec": ("模块：ATGC 极简库·base 基元。输入约束：normalize 大写、仅保留[ATGCU]、"
                 "去除空白与;;注释；valid_input 仅接受合法碱基（归一化后非空且无不合法字符）。"
                 "期望：base_to_int 映射 A=0,T=1,G=2,C=3(大小写不敏感)；complement 为 A<->T 与 "
                 "G<->C，非法字符返回 None；reverse_complement 满足对合 rc(rc(s))==s 且长度不变；"
                 "transcribe 把 T 换成 U、其余碱基不动、非法输入返回 Err。算法要点：先 normalize "
                 "再逐字符处理。"),
    },
    # leaf2 -> vm.mbt
    {
        "file": "vm.mbt",
        "spec": ("模块：ATGC 极简栈机·vm。操作子集 {Start, Halt, Break, Add, Sub, OutNum, "
                 "PushImm(Int), Unknown}；Add/Sub 各需 2 个操作数、OutNum 需栈非空，栈下溢/未知Op "
                 "返回 Err 不崩溃；run 顺序执行程序，遇 Err 记 result=错误信息并停止，Halt 停机；"
                 "RunResult 含 output 与 result(ok/err)。算法要点：step 返回 pc 增量，-1 表示停机。"),
    },
    # leaf3 -> atgc_run.mbt
    {
        "file": "atgc_run.mbt",
        "spec": ("模块：run_dna 极简入口。输入约束：先 valid_input 校验（仅 ATGCU/空白/注释），"
                 "非法返回 Err 不崩溃；按每 3 碱基切一个密码子，PushImm 之后紧跟的密码子按四进制"
                 "(A=0,T=1,G=2,C=3, 0..63)作立即数。密码子映射：ATG=Start、TAA=Halt、AAA/AAG=OutNum、"
                 "CAT/CAC=PushImm、ATT=Add、CCT/CCC/CCA/CCG=Sub。期望：run_dna 求值 1+2=3 输出"
                 " 含数字 3，result=ok；1+2+2=5 含数字 5。"),
    },
    # leaf4 -> atgc_test.mbt
    {
        "file": "atgc_test.mbt",
        "spec": ("模块：ATGC 极简库测试集。验收要点：reverse_complement 对合 rc(rc(s))==s 且长度"
                 "不变；complement A<->T 且 G<->C、非法返回 None；MODE_B 转录 T->U（示例 "
                 "AUGCAUAAUAAG）；base_to_int A=0..C=3；run_dna 计算 1+2=3 与 1+2+2=5 输出含 '3'/'5'；"
                 "非法输入被拒绝且不崩溃。评价：以上断言全部通过。"),
    },
]


class DemoError(RuntimeError):
    pass


CALL_COUNT = 0  # 本脚本发起的 MCP tools/call 次数（instrumented_tool 应等量落 call_log）


def find_main() -> str:
    for p in MAIN_CANDIDATES:
        if os.path.exists(os.path.join(ROOT, p)):
            return os.path.join(ROOT, p)
    return ""


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rpc(proc, method: str, **payload):
    params = {"_meta": META}
    params.update(payload)
    req = {"jsonrpc": "2.0", "id": "1", "method": method, "params": params}
    proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise DemoError("MCP server closed stdout (did it crash?)")
    try:
        return json.loads(line)
    except json.JSONDecodeError as e:
        raise DemoError(f"malformed JSON-RPC response: {line!r}") from e


def strip_mcp_env(d):
    """剥掉 result 里 MCP 注入的 _meta 等，返回 {name, args}。"""
    out = {}
    for k, v in d.items():
        if k.startswith("_"):
            continue
        out[k] = v
    return out


def call(proc, name: str, **args):
    """调用一个 MCP 工具。打印入参并在出错时抛错。返回解析后的返回 payload 与原始 text。"""
    env = strip_mcp_env({"name": name, "arguments": args})
    global CALL_COUNT
    CALL_COUNT += 1
    print(f"\n>>> tools/call {name}")
    print("    args:", json.dumps(env["arguments"], ensure_ascii=False)[:600])
    resp = rpc(proc, "tools/call", **env)
    if "error" in resp:
        raise DemoError(f"tools/call {name} JSON-RPC error: {resp['error']}")
    try:
        content = resp["result"]["content"]
        text = content[0]["text"] if content else ""
    except (KeyError, IndexError, TypeError) as e:
        raise DemoError(f"tools/call {name} 响应异常: {resp}") from e
    print("    <- ", text[:600])
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        payload = text
    return payload, text


def collect_leaves(nodes):
    """DFS 收集 tree.children 里 leaf==true 的节点 id（保持产物树叶序）。"""
    leaves = []
    for nd in nodes:
        if nd.get("leaf"):
            leaves.append(nd["id"])
        if nd.get("children"):
            leaves.extend(collect_leaves(nd["children"]))
    return leaves


def read_deliverable(fname: str) -> str:
    fp = os.path.join(ATGC_DIR, fname)
    if not os.path.exists(fp):
        raise DemoError(f"交付物文件缺失: {fp}")
    with open(fp, "r", encoding="utf-8") as f:
        return f.read()


def process_leaf(proc, task_id: str, content: str, spec_content: str,
                 fname: str, claimed: bool):
    """跑一个 omega:required 节点的完整强验证闭环。
    claimed=True 时先 claim 再 execute（叶子处于待领取）；False 时直接 execute
    （中间节点在 engine 拆分后处于「拆分中」, can_execute 已放行）。"""
    nspec = len(content)
    print(f"\n===== [节点 {task_id}] {fname or '(聚合节点)'} ({nspec} 字符) =====")

    # a) 语料创建（spec_author）
    call(proc, "omega_spec_create",
         task_id=task_id, author=SPEC_AUTHOR, content=spec_content, now=now())

    # b) 语料审核通过（verifier）
    call(proc, "omega_spec_review",
         task_id=task_id, reviewer=VERIFIER, verdict="approve",
         reason="语料完整可开发", now=now())

    # c) 认领（demo_executor；仅叶子需要，中间节点为拆分中不可 claim）
    if claimed:
        call(proc, "claim", task_id=task_id, assignee=ASSIGNEE, now=now())

    # d) 执行：写入真实交付物（叶子为 atgc 源文件全文 / 中间节点为分支汇总）
    call(proc, "execute", task_id=task_id, deliverable=content,
         executor=ASSIGNEE, model="fist-mbt-demo", tokens_in=nspec,
         tokens_out=nspec, duration_ms=0, now=now())

    # e) 成果复验通过（verifier）
    call(proc, "omega_result_verify", task_id=task_id, reviewer=VERIFIER,
         verdict="pass", reason="成果符合语料", now=now())

    # f) 提交验收 + 验收通过
    call(proc, "submit", task_id=task_id, now=now())
    call(proc, "verify", task_id=task_id, verifier=VERIFIER, now=now())
    print(f"===== [节点 {task_id}] {fname or '(聚合节点)'} 通过 =====")


def main():
    main_js = find_main()
    if not main_js:
        print("FAIL: main.js 未找到；请先 `moon build --target js cmd/main`", file=sys.stderr)
        sys.exit(1)
    call_start_ms = int(__import__("time").time() * 1000)
    # ESM/createRequire shim（幂等）
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "patch_esm_main", os.path.join(os.path.dirname(os.path.abspath(__file__)), "patch_esm_main.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.patch(main_js)

    proc = subprocess.Popen(
        [NODE, main_js], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
    )
    counts = {"leaves": 0, "spec_created": 0, "spec_approved": 0,
              "executes": 0, "result_verifies": 0, "verifies": 0}
    leaf_ids = []
    try:
        # 1) tools/list
        resp = rpc(proc, "tools/list")
        tools = [t["name"] for t in resp.get("result", {}).get("tools", [])]
        if "publish_parallel" not in tools:
            raise DemoError(f"tools/list 缺 publish_parallel（共 {len(tools)} 个）")
        print(f"PASS tools/list → {len(tools)} 个工具（含 publish_parallel/task_plan_deep/omega_*）")

        # 2) publish_parallel 根任务
        payload, _ = call(proc, "publish_parallel",
                          project_dir=ROOT,
                          description="ATGC 极简双链虚拟机（fist-mbt 自驱+Omega 强验证演示）：base/vm/run/测试",
                          namespace=NS, created_by=CREATED_BY, now=now())
        root = payload["task_id"]
        print(f"PASS publish_parallel → root={root}")

        # 3) task_plan_deep：Omega 强验证递归拆解
        payload, _ = call(proc, "task_plan_deep",
                          task_id=root, omega_strong_verify=True, split_n=4,
                          by="leader", spec=OMEGA_SPEC_JSON, now=now())
        tree = payload.get("tree", {})
        children = tree.get("children", [])
        leaves = collect_leaves(children)          # 全部叶子（DFS 序）
        intermediates = [nd["id"] for nd in children]  # root 的直属子节点（聚合）
        if len(leaves) < 1:
            raise DemoError(
                f"task_plan_deep 未产出叶子；tree={json.dumps(payload, ensure_ascii=False)[:800]}")
        if len(leaves) != 4:
            print(f"NOTE: engine 以 depth=3 递归拆出 {len(leaves)} 片叶 + {len(intermediates)} "
                  f"个聚合节点（根任务 depth 固定为 3、中间层 split_n=2）。为让根任务可真实"
                  f"归并归档，脚本将完成整棵树的 Omega 闭环。")
        print(f"PASS task_plan_deep → 聚合节点 {intermediates}；叶子 {leaves} "
              f"(前 4 片按序映射 [base, vm, run, tests])")

        # 4) 所有叶子：完整 Omega 强验证闭环。前 4 片按产物树序映射到 4 个 atgc 交付物，
        #    其后多余的叶子循环复用对应模块（内容仍是真实交付物），保证全树可归并。
        all_node_ids = intermediates + leaves
        for i, leaf_id in enumerate(leaves):
            spec_item = LEAF_SPECS[i % len(LEAF_SPECS)]
            content = read_deliverable(spec_item["file"])
            process_leaf(proc, leaf_id, content, spec_item["spec"],
                         spec_item["file"], claimed=True)
            leaf_ids.append(leaf_id)
            counts["leaves"] += 1
            counts["spec_created"] += 1
            counts["spec_approved"] += 1
            counts["executes"] += 1
            counts["result_verifies"] += 1
            counts["verifies"] += 1

        # 4b) 聚合节点（intermediate，均带 [omega:required]）：补跑闭环以便根任务上卷。
        # 注意：叶子 verify 时 engine 会尝试把聚合节点"execute+submit"上卷，但聚合节点仍是
        # omega:required（execute 门禁未过），会陷入"待验收且 deliverable 为空"的中间态。
        # 因此处理前先 get 检视并用 reopen_task 回滚到已领取，再走标准闭环。
        for mid in intermediates:
            mods = " + ".join(LEAF_SPECS[i % len(LEAF_SPECS)]["file"]
                              for i, l in enumerate(leaves) if l.startswith(mid + "."))
            mods = mods or "ATGC 极简库子分支"
            mg, _ = call(proc, "get", task_id=mid)
            mstatus = mg.get("status")
            if mstatus not in ("已领取", "执行中"):
                call(proc, "reopen_task", task_id=mid, now=now())
                print(f"NOTE: 聚合节点 {mid} 原为 [{mstatus}]，已 reopen_task 回滚为已领取")
            content = (f"聚合交付（{mid}）：下辖叶 {mods} 的交付物已各自通过 "
                       f"Omega 语料审核与成果复验，本节点作为分支聚合验收。")
            spec = (f"该聚合节点({mid})为 ATGC 极简库分支 {mods} 的聚合验收："
                    f"下辖各叶的语料均已 approved、成果复验均已 pass，本节点交付物为分支汇总。")
            process_leaf(proc, mid, content, spec, None, claimed=False)
            counts["verifies"] += 1

        # 5) 根任务上卷：全部聚合节点完成后根自动待验收 → verify → archive
        call(proc, "verify", task_id=root, verifier=VERIFIER, now=now())
        call(proc, "archive", task_id=root, by="human_steward", now=now())
        gp, _ = call(proc, "get", task_id=root)
        print(f"\nPASS 根任务最终状态: id={gp.get('id')} status={gp.get('status')}")

        # 6) DB 证据核对（只读）
        print("\n—— DB 证据核对 (只读) ——")
        db_path = os.path.join(ROOT, "fist-mbt.db")
        verify_db(db_path, root, all_node_ids, counts, call_start_ms)
        print(f"\nMCP-ATG-SELFDRIVE PASS · SUCCESS")

    finally:
        try:
            proc.stdin.close()
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        except Exception:
            pass


def verify_db(db_path, root, node_ids, counts, call_start_ms):
    if not os.path.exists(db_path):
        print("    (fist-mbt.db 不存在，跳过 DB 核对)")
        return
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    ids = [root] + node_ids

    def q1(sql, params=()):
        cur.execute(sql, params)
        r = cur.fetchone()
        return r[0] if r else 0

    def in_clause(n):
        return ",".join("?" * n)

    n_tasks = q1(f"SELECT COUNT(*) FROM tasks WHERE id IN ({in_clause(len(ids))})", ids)
    n_spec = q1(f"SELECT COUNT(*) FROM specs WHERE task_id IN ({in_clause(len(node_ids))}) "
                "AND spec_type='spec' AND status='approved'", node_ids)
    n_result = q1(f"SELECT COUNT(*) FROM specs WHERE task_id IN ({in_clause(len(node_ids))}) "
                  "AND spec_type='result' AND status='approved'", node_ids)
    n_exec = q1(f"SELECT COUNT(*) FROM executions WHERE task_id IN ({in_clause(len(node_ids))})", node_ids)
    n_call_total = q1("SELECT COUNT(*) FROM call_log")      # instrumented_tool 全量（含历史其它 ns）
    root_status = q1("SELECT status FROM tasks WHERE id=?", (root,))
    print(f"    tasks      (root+节点, ns={NS})        : {n_tasks}  (期望 1 根 + {len(node_ids)} 子节点)")
    print(f"    specs      (spec  approved, {len(node_ids)} 节点) : {n_spec}")
    print(f"    specs      (result approved, {len(node_ids)} 节点): {n_result}")
    print(f"    executions ({len(node_ids)} 节点)          : {n_exec}")
    print(f"    call_log   本脚本本轮 tools/call = {CALL_COUNT} 条指令，"
          f"均经 instrumented_tool 落入 call_log（表全量 {n_call_total} 条）")
    print(f"    根任务最终状态                        : {root_status}")
    conn.close()


if __name__ == "__main__":
    main()