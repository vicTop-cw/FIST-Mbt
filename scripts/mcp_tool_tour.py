#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/mcp_tool_tour.py — 全工具调用面巡回（129/129 至少打一次，参数从 schema 反解）。

为什么要有这条（`mcp_smoke.py` 顶不了）：
  · `mcp_smoke.py` 的候选入口是 `_build/js/debug/build/cmd/main/main.js`，而发布产物是
    `cmd/cli/cli.js`（`scripts/blackbox/build_release.ps1:38`）⇒ 冒烟跑的是**不发布的那棵入口**，
    并且从不带 `serve` 子命令。装好的 `fist-mbt` 全局命令能不能用，它一次都没证明过。
  · 手工写死 129 条参数也不可信（本仓踩过：`laya_decide` 参数收窄后旧键被静默丢弃、
    `report_bug` 必填是 `summary` 不是 `title`）。⇒ 参数一律从 `tools/list` 的
    `inputSchema.required ∩ properties` 反解，测的是**调用面能不能接通**。

三面分开记账（混在一起必然说谎）：
  ok            服务端接受并返回结果
  refused       服务端按设计拒绝（角色闭集 / 状态机 / 白名单 / 缺 [omega:required]）——这是"功能可用"的证据
  skipped       本驱动按授权边界主动不打（真发网络包、真起执行器、全库 heal、删除）
  broken        连接层失败（进程没起 / 超时）⇒ 才算红

安全边界（血债换来的规矩，全部可审）：
  · 写面跑在 `--plane write`：cwd=临时 box + `FIST_DB_PATH` 指到 box 外的独立库
    ⇒ 仓库根 `fist-mbt.db`（多轮共用的共享面）一行都不动；
  · 读面 `--plane read`：cwd=仓库根，只打不改源码的工具（issue_scan / project_standards /
    mode_* / 分析类 dag_*/成本类），库照样隔离；
  · `github_flush_execute` / `github_issue_close` / `github_issue_comment` 不跑（真发 issue）；
  · `executor_run` 只 `dry_run=true`；`heal`/`watchdog_tick` 不带 ns 的全库形态不跑；`delete` 不跑。

用法：
    python scripts/mcp_tool_tour.py --plane write --json
    python scripts/mcp_tool_tour.py --plane read  --json
退出码：0 = 无 broken；1 = 有 broken；2 = 找不到 server 产物 / 工具数自证失败（≤100）。
"""
import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import time
import uuid

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN_ID = time.strftime("%Y%m%d%H%M%S", time.gmtime()) + "-" + uuid.uuid4().hex[:6]
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "mcp-tool-tour", "version": "1"},
}
# 授权边界：这些一律不打真动作（不是产品坏了，是本驱动的纪律）
SKIPPED = {
    "github_flush_execute": "真发 GitHub issue（未授权出网）",
    "github_issue_close": "真关 issue（未授权）",
    "github_issue_comment": "真评论（未授权）",
    "heal": "无 ns 全库回滚——历史事故（396 单/23 ns）后禁止",
    "delete": "不可逆删除",
    "watchdog_tick": "无人值守编排会真派单，交定时任务面",
}
# 读面禁打的"会写项目文件"的工具（BUG-98）：读面的 project_dir="." 就是仓库根，
# report_bug 一类会直接往真账本 memory/bugs.md 追加条目——实测同一天内写过两次，
# 其中一次还和手写台账的编号相撞。读面只做读，写面才在临时 box 里写真东西。
READ_PLANE_SKIP = {
    "report_bug": "读面 project_dir=. 即仓库根，会写真账本 memory/bugs.md",
    "bug_fix": "同上：会改真账本抬头",
    "bug_mark_status": "同上：会改真账本抬头",
    "memory_consolidate": "会写 memory/{kind}.md 真记忆面",
    "memory_gc": "会归档/移动 memory/ 真条目",
    "memory_link": "会追加 memory/links.md 真关联面",
}

SERVER_JS = [
    os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js"),
    os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js"),
]


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def sha8(path):
    h = hashlib.sha256()
    with io.open(path, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()[:8]


class Serve:
    def __init__(self, js, cwd, env):
        self.errlog = os.path.join(cwd, "tour-%s.stderr.log" % RUN_ID)
        self.p = subprocess.Popen(
            [os.environ.get("NODE", "node"), js, "serve"], cwd=cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=io.open(self.errlog, "wb"), bufsize=0, env=env)
        self.mid = 0

    def _send(self, o):
        self.p.stdin.write((json.dumps(o) + "\n").encode("utf-8"))
        self.p.stdin.flush()

    def _recv(self, want, timeout=120):
        t0 = time.time()
        while time.time() - t0 < timeout:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("server closed stdout; stderr tail=%s" %
                                   io.open(self.errlog, "rb").read()[-300:].decode("utf-8", "replace"))
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("{"):
                continue
            try:
                m = json.loads(s)
            except Exception:
                continue
            if m.get("id") == want:
                return m
        raise RuntimeError("timeout id=%s" % want)

    def call(self, tool, args, timeout=120):
        self.mid += 1
        w = self.mid
        self._send({"jsonrpc": "2.0", "id": w, "method": "tools/call",
                    "params": {"_meta": META, "name": tool, "arguments": args}})
        return self._recv(w, timeout)

    def list_tools(self):
        self.mid += 1
        w = self.mid
        self._send({"jsonrpc": "2.0", "id": w, "method": "tools/list",
                    "params": {"_meta": META}})
        m = self._recv(w)
        return m["result"]["tools"]

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=10)
        except Exception:
            self.p.kill()


def text_of(resp):
    """把 MCP result.content[*].text 拼回来；error 分支逐字保留，不截断拒绝文案。"""
    if "error" in resp:
        return json.dumps(resp["error"], ensure_ascii=False)
    parts = resp.get("result", {}).get("content", []) or []
    return " ".join(p.get("text", "") for p in parts)


def jload(s):
    try:
        return json.loads(s)
    except Exception:
        return None


def value_for(name, prop, ctx, depth=0):
    """按"名字优先、类型兜底"给值；ctx 里是本轮真实产生的 id，绝不造假对象。"""
    if name in ctx:
        return ctx[name]
    t = prop.get("type", "")
    if t == "string":
        return ""            # 可选字符串一律留空 = 走服务端默认分支
    if t == "boolean":
        return False
    if t == "integer":
        return 1
    if t == "array":
        return []
    if t == "object":
        return {}
    return ""


# 必填参数的名字优先表（键 = schema 属性名）。取值都有实测依据：
# 这些名字在 tools/list 描述里点名了自己的合法闭集，表里给的是其中"最小副作用"那一档。
NAME_HINTS = {
    "cmd": "python",
    "severity": "low",
    "summary": "巡回探针：调用面可用性核验",
    "detail": "scripts/mcp_tool_tour.py 自动巡回产生，只验调用面",
    "description": "巡回探针任务（不落交付物）",
    "created_by": "human_steward",     # publish 的角色闭集：人类指挥官
    "reported_by": "mcp_tool_tour",
    "author": "spec_author",
    "reviewer": "verifier",
    "agent_id": "tour-agent",
    "executor": "aider",
    "prompt": "只回一行 ok，不要改任何文件",
    "verdict": "approve",
    "content": "巡回探针语料",
    "step": "tour-step",
    "compensation": "无实际动作（巡回）",
    "preset": "build-verify",
    "goal": "巡回探针目标",
    "note": "巡回探针备注",
    "code": "pub fn probe() -> Int { 1 }",
    "dna": "ATG CCA",
    "sequence": "ATGCCA",
    "path": "memory/bugs.md",
    "check_key": "gate",
    "scope": "src/probe.mbt",
    "agent": "tour-agent",
    "name": "tour-loop",
    "kind": "checkpoint",
    "link_a": "memory/log.md",
    "link_b": "memory/bugs.md",
    "asset_id": "tour-asset",
    "task_ids": [],
    "bug_ids": [],
    "steps_required": [],
    "project_dir": None,     # 走 ctx
    "plan": "1. 探 2. 记 3. 收",
    "result": "巡回结果",
    "feedback": [],
    "artifacts": None,       # 特判，见下
    "external_results": None,
    "abilities": ["probe"],
    "need": ["probe"],
    "tags": ["tour"],
    "modes": ["advance"],
    "timeout_ms": 20000,
    "max_rounds": 3,
    "split_n": 2,
    "now": None,             # 走 ctx
}


def build_args(tool, schema, ctx, read_only):
    props = (schema or {}).get("properties", {}) or {}
    required = (schema or {}).get("required", []) or []
    args = {}
    for k in required:
        prop = props.get(k, {})
        if k == "artifacts":
            args[k] = [{"path": ctx["project_dir"] + "/memory/bugs.md",
                        "min_chars": 1}]
            continue
        if k == "external_results":
            args[k] = {"gate": {"ok": True, "code": 0}}
            continue
        if k in ctx:
            args[k] = ctx[k]
            continue
        if k == "name" and tool.startswith("loop_"):
            args[k] = ctx["loop_name"]     # 组合环工具要认本轮真建的那个环，不是随便一个名
            continue
        if k in NAME_HINTS and NAME_HINTS[k] is not None:
            args[k] = NAME_HINTS[k]
            continue
        args[k] = value_for(k, prop, ctx)
    # 通用可选件：只补 project_dir / namespace / now（服务端默认值一律留空）
    for k in ("project_dir", "namespace", "now"):
        if k in props:
            args[k] = ctx[k]
    if "timeout_ms" in props:
        # 巡回不能把 120s 默认超时用在每个工具上：整张表要跑得完，
        # 而且上一版 run_check 撞默认超时时，客户端先超时 ⇒ 记成 broken，冤枉了产品。
        args["timeout_ms"] = 15000
    if "dry_run" in props:
        args["dry_run"] = True          # executor_run：只回显 argv，不起进程
    if "force" in props:
        args["force"] = False           # 出网类：即便被调用也停在门后
    return args


def find_child(srv, ctx, exclude=frozenset()):
    """从 list 回读里挑一个"不是根、不是已用过"的任务 id。

    为什么靠回读而不是靠 plan 的返回值形状：上一版按 children/task_ids 猜键名，
    结果 plan 被状态机拒绝后静默拿到 T0，一整条生命周期在假对象上跑，
    报出来的"拒绝"全都不是被测工具的拒绝。
    """
    try:
        r = srv.call("list", {"project_dir": ctx["project_dir"],
                              "namespace": ctx["namespace"]})
        j = jload(text_of(r))
    except Exception:
        return ""
    rows = []
    if isinstance(j, list):
        rows = j
    elif isinstance(j, dict):
        for key in ("tasks", "items", "list", "data"):
            if isinstance(j.get(key), list):
                rows = j[key]
                break
    for row in rows:
        if not isinstance(row, dict):
            continue
        tid = row.get("id") or row.get("task_id") or ""
        if tid and tid not in exclude:
            return tid
    return ""


def seed(srv, ctx):
    """建一棵真树：后面的 task_id/root_task_id/bug_id 全是这里产生的，不造假对象。"""
    out = []
    def do(label, tool, args):
        r = srv.call(tool, args)
        t = text_of(r)
        out.append((label, "ok" if "error" not in r else "refused", t[:200]))
        return t if "error" not in r else None

    t = do("publish root", "publish", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "description": "巡回探针根任务（普通链）",
        "created_by": "human_steward", "now": ctx["now"]})
    if t:
        ctx["task_id"] = (jload(t) or {}).get("task_id", ctx["task_id"])
        ctx["root_task_id"] = ctx["task_id"]
    do("claim root", "claim", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "task_id": ctx["task_id"], "assignee": "tour-agent", "now": now_iso()})
    t = do("plan 2 children", "plan", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "task_id": ctx["task_id"], "split_n": 2, "now": now_iso()})
    leaf = find_child(srv, ctx, exclude={ctx["task_id"]})
    if leaf:
        ctx["task_id_leaf"] = leaf
    do("claim leaf", "claim", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "task_id": ctx.get("task_id_leaf", ""), "assignee": "tour-agent", "now": now_iso()})
    do("execute leaf", "execute", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "task_id": ctx.get("task_id_leaf", ""), "assignee": "tour-agent",
        "deliverable": "巡回交付物：一段说明 + 一行结论", "now": now_iso()})
    do("submit leaf", "submit", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "task_id": ctx.get("task_id_leaf", ""), "assignee": "tour-agent", "now": now_iso()})
    # Omega 链单独一棵树（标记只能在 publish 期写进 description，事后无工具可改）
    t = do("publish omega root", "publish", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "description": "巡回探针 Omega 根任务 [omega:required]",
        "created_by": "human_steward", "now": now_iso()})
    omega_root = (jload(t) or {}).get("task_id", "") if t else ""
    if omega_root:
        do("claim omega root", "claim", {
            "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
            "task_id": omega_root, "assignee": "tour-agent", "now": now_iso()})
        do("plan omega children", "plan", {
            "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
            "task_id": omega_root, "split_n": 2, "now": now_iso()})
        olea = find_child(srv, ctx, exclude={omega_root, ctx["task_id"],
                                             ctx.get("task_id_leaf", "")})
        if olea:
            ctx["omega_task_id"] = olea
            do("omega_spec_create", "omega_spec_create", {
                "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
                "task_id": olea, "author": "spec_author",
                "content": "巡回语料：给定输入域与判据", "now": now_iso()})
            do("omega_spec_review", "omega_spec_review", {
                "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
                "task_id": olea, "reviewer": "verifier", "verdict": "approve",
                "now": now_iso()})
            do("claim omega leaf", "claim", {
                "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
                "task_id": olea, "assignee": "tour-agent", "now": now_iso()})
            do("execute omega leaf", "execute", {
                "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
                "task_id": olea, "assignee": "tour-agent",
                "deliverable": "巡回 Omega 交付物", "now": now_iso()})
            do("omega_result_verify", "omega_result_verify", {
                "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
                "task_id": olea, "reviewer": "verifier", "verdict": "approve",
                "now": now_iso()})
            do("submit omega leaf", "submit", {
                "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
                "task_id": olea, "assignee": "tour-agent", "now": now_iso()})
    t = do("report_bug", "report_bug", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "summary": "巡回探针：调用面核验", "detail": "由 mcp_tool_tour 产生",
        "severity": "low", "reported_by": "mcp_tool_tour", "publish_task": False,
        "now": now_iso()})
    if t:
        ctx["bug_id"] = (jload(t) or {}).get("bug_id", "")
    do("loop_create", "loop_create", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "name": ctx["loop_name"], "preset": "build-verify", "now": now_iso()})
    do("saga_register", "saga_register", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "root_task_id": ctx.get("root_task_id", ""), "step": "tour-step-1",
        "task_id": ctx.get("task_id_leaf", ""), "compensation": "无实际动作",
        "now": now_iso()})
    do("heartbeat", "heartbeat", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "agent_id": "tour-agent", "task_id": ctx.get("task_id_leaf", ""),
        "now": now_iso()})
    do("executor_register", "executor_register", {
        "project_dir": ctx["project_dir"], "namespace": ctx["namespace"],
        "name": "tour-executor", "abilities": ["probe"], "now": now_iso()})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plane", choices=["write", "read"], default="write")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--js", default="")
    a = ap.parse_args()

    cands = ([a.js] if a.js else []) + SERVER_JS
    js = next((p for p in cands if os.path.isfile(p)), None)
    if not js:
        print("TOUR: UNUSABLE —— 找不到 server 产物，候选=%s" % ", ".join(cands))
        return 2

    if a.plane == "write":
        box = os.path.join(ROOT, "temp", "tool-tour-" + RUN_ID)
        os.makedirs(box, exist_ok=True)
        cwd = box
        iso_db = os.path.join(box, "tour.db")
        proj = "."
    else:
        cwd = ROOT                      # 读面：真源码树
        iso_db = os.path.join(ROOT, "temp", "tool-tour-%s.db" % RUN_ID)
        proj = "."                      # 相对 server cwd
    env = dict(os.environ)
    env["FIST_DB_PATH"] = iso_db        # 两面都隔离：共享根库一行不动
    ns = "tour-%s-%s" % (a.plane, RUN_ID[-6:])

    print("server = %s (sha256:%s)" % (js, sha8(js)))
    print("plane  = %s  cwd=%s  isolated_db=%s  ns=%s" % (
        a.plane, os.path.relpath(cwd, ROOT).replace("\\", "/"),
        os.path.relpath(iso_db, ROOT).replace("\\", "/"), ns))

    srv = Serve(js, cwd, env)
    rows, seedlog = [], []
    try:
        tools = srv.list_tools()
        if len(tools) <= 100:
            print("TOUR: UNUSABLE —— tools/list 只回 %d 个（判据无法自证绝不报绿）" % len(tools))
            return 2
        ctx = {"project_dir": proj, "namespace": ns, "now": now_iso(),
               "task_id": "T0", "root_task_id": "T0", "loop_name": "tour-loop-" + RUN_ID[-6:],
               "bug_id": "BUG-1"}
        if a.plane == "write":
            os.makedirs(os.path.join(cwd, "memory"), exist_ok=True)
            ctx["name"] = ctx["loop_name"]
            seedlog = seed(srv, ctx)
        kinds = {}
        restarts = 0
        for tl in tools:
            name = tl["name"]
            if name in SKIPPED:
                rows.append({"tool": name, "kind": "skipped", "why": SKIPPED[name], "excerpt": ""})
                kinds["skipped"] = kinds.get("skipped", 0) + 1
                continue
            if a.plane == "read" and name in READ_PLANE_SKIP:
                rows.append({"tool": name, "kind": "skipped",
                             "why": "读面禁写件（BUG-98）：" + READ_PLANE_SKIP[name],
                             "excerpt": ""})
                kinds["skipped"] = kinds.get("skipped", 0) + 1
                continue
            args = build_args(name, tl.get("inputSchema"), ctx, a.plane == "read")
            try:
                r = srv.call(name, args)
                t = text_of(r)
                kind = "refused" if "error" in r else "ok"
            except Exception as e:
                # 进程死了 ≠ 后面 94 个工具都坏了：先分诊，再复活继续数。
                # 上一版直接把后续全记 broken，等于用一次崩溃把整张表涂黑，
                # 既夸大了失效面，也永远测不到崩溃点之后的工具。
                rows.append({"tool": name, "kind": "crashed", "args": args,
                             "excerpt": str(e)[:400]})
                kinds["crashed"] = kinds.get("crashed", 0) + 1
                try:
                    srv.close()
                except Exception:
                    pass
                try:
                    srv = Serve(js, cwd, env)
                    srv.list_tools()
                    restarts += 1
                except Exception as e2:
                    print("!! server 复活失败：%s" % e2)
                    for rest in tools[tools.index(tl) + 1:]:
                        rn = rest["name"]
                        if rn in SKIPPED:
                            continue
                        rows.append({"tool": rn, "kind": "not_tested",
                                     "why": "复活失败，未打到调用面", "excerpt": ""})
                        kinds["not_tested"] = kinds.get("not_tested", 0) + 1
                    break
                continue
            rows.append({"tool": name, "kind": kind, "args": args, "excerpt": t[:400]})
            kinds[kind] = kinds.get(kind, 0) + 1
        # 基数自证（本判据自己踩过的坑：kinds 从计数累加、rows 却漏 append，
        # 于是"合计 6 / tools/list 129"配上 TOUR GREEN——明细丢了，拒绝文案就再也举不出来）
        if len(rows) != len(tools):
            print("  !! 基数不符：明细 %d 条 vs 工具 %d 个 ⇒ 判据自己坏了，结论不作数" % (
                len(rows), len(tools)))
            return 2
        # 逐字打印每类计数与全部非 ok 明细（拒绝文案不许被截断成"看着完整"）
        for k in ("ok", "refused", "skipped", "crashed", "not_tested", "broken"):
            print("  %-11s %d" % (k, kinds.get(k, 0)))
        print("  合计         %d（tools/list 自证=%d，复活次数=%d）" % (len(rows), len(tools), restarts))
        print("=== 非 ok 明细（逐字）===")
        for r in rows:
            if r["kind"] == "ok":
                continue
            print("%-22s %-11s %s" % (r["tool"], r["kind"], (r.get("why") or r.get("excerpt", ""))[:300]))
        print("=== 播种链（逐字）===")
        for lbl, k, t in seedlog:
            print("  %-22s %-8s %s" % (lbl, k, t[:200]))
        if a.json:
            jp = os.path.join(ROOT, "temp", "mcp_tool_tour_%s_%s.json" % (a.plane, RUN_ID))
            io.open(jp, "w", encoding="utf-8").write(json.dumps(
                {"started": now_iso(), "server_js": js, "server_sha8": sha8(js),
                 "plane": a.plane, "tools_listed": len(tools), "ns": ns,
                 "seed": seedlog, "rows": rows, "kinds": kinds},
                ensure_ascii=False, indent=2))
            print("JSON 证据 = %s" % os.path.relpath(jp, ROOT).replace("\\", "/"))
        # 红面 = 崩溃 + 未打到调用面 + 复活失败；refused 不算红（那是产品的自述拒绝）
        red = kinds.get("crashed", 0) + kinds.get("not_tested", 0) + kinds.get("broken", 0)
        print("TOUR: %s —— %d 工具 ok=%d refused=%d skipped=%d crashed=%d not_tested=%d 复活=%d" % (
            "GREEN" if red == 0 else "RED", len(rows), kinds.get("ok", 0),
            kinds.get("refused", 0), kinds.get("skipped", 0),
            kinds.get("crashed", 0), kinds.get("not_tested", 0), restarts))
        return 0 if red == 0 else 1
    finally:
        srv.close()


if __name__ == "__main__":
    sys.exit(main())
