#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/mcp_tool_tour.py — 全工具调用面巡回（129/129 至少打一次，参数从 schema 反解）。

为什么要有这条（`mcp_smoke.py` 顶不了）：
  · `mcp_smoke.py` 的候选入口是 `_build/js/debug/build/cmd/cli/cli.js`，而发布产物是
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
import re
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
    def __init__(self, js, cwd, env, log_dir=None):
        # stderr 日志落在 log_dir（默认 cwd）；读面 cwd=仓库根 ⇒ 必须引到 temp/，
        # 否则巡回探针自己往仓库根吐文件（BUG-100 的外溢面之一）。
        self.errlog = os.path.join(log_dir or cwd, "tour-%s.stderr.log" % RUN_ID)
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

    def raw(self, method, params):
        """非 tools/call 的方法面（resources/* prompts/*）也按同一份 _meta 打。"""
        self.mid += 1
        w = self.mid
        self._send({"jsonrpc": "2.0", "id": w, "method": method,
                    "params": dict(params, _meta=META)})
        return self._recv(w)

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
    # store_open 的 data_dir 缺省落在 server cwd（读面＝仓库根）⇒ 命名空间库会直接在
    # 被测项目里长出来。外溢判据第一次跑就抓到 tour-read-*.db，故一律指向草稿项目。
    if "data_dir" in props:
        args["data_dir"] = ctx["data_dir"]
    if "scratch" in props:
        args["scratch"] = True
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


def surface_probe(srv, root=None):
    """自述面巡回：文档写着「3 resources + 2 prompts」，这里就把这两面打到调用面并双向对表。

    为什么不只数工具：`check_doc_surface`/`check_tools_sync` 钉的是 tools 面，resources/prompts
    两个面此前没有任何判据认领——文档说 3+2，服务端实际给几个、能不能读、读回来是不是空，
    全靠人偶尔试一次（J10 型缺口：自述有人写、判据没人认领）。
    期望值从 AGENTS.md 的 `Resources:` / `Prompts:` 两行反解，不在此处手抄常量。
    """
    problems = []
    root = root or ROOT
    agents = io.open(os.path.join(root, "AGENTS.md"), encoding="utf-8", errors="replace").read()
    m_res = re.search(r"^Resources:(.*)$", agents, re.M)
    m_pr = re.search("^Prompts:(.*)$", agents, re.M)
    want_res = set(re.findall(r"`(fist://[\w./-]+)`", m_res.group(1))) if m_res else set()
    want_pr = set(re.findall(r"`(fist:[\w./-]+)`", m_pr.group(1))) if m_pr else set()
    if not want_res or not want_pr:
        return ["自述面反解失败：AGENTS.md 的 Resources:/Prompts: 行里没解析出条目"
                "（判据无法自证，绝不报绿）"], ""
    rr = srv.raw("resources/list", {})
    if "error" in rr:
        problems.append("resources/list 被拒：%s" % json.dumps(rr["error"], ensure_ascii=False)[:120])
        res_list = []
    else:
        res_list = rr.get("result", {}).get("resources", []) or []
    got_res = set(x.get("uri", "") for x in res_list)
    for miss in sorted(want_res - got_res):
        problems.append("文档声明的 resource 服务端没有：%s" % miss)
    for extra in sorted(got_res - want_res):
        problems.append("服务端有但文档没声明的 resource：%s" % extra)
    res_chars = []
    for uri in sorted(got_res & want_res):
        rd = srv.raw("resources/read", {"uri": uri})
        if "error" in rd:
            problems.append("resources/read %s 被拒：%s" % (uri, json.dumps(rd["error"], ensure_ascii=False)[:110]))
            continue
        cont = (rd.get("result", {}).get("contents") or [{}])
        txt = cont[0].get("text", "") if cont else ""
        if not txt.strip():
            problems.append("resources/read %s 回的是空文本（读通了但没内容）" % uri)
            continue
        # 逐条把"读到的字节量"打进自述：账本里"非空"这种话要能被下一轮逐字复核，
        # 只写"非空"就等于把一次性观测重新变成叙述。
        res_chars.append("%s=%d" % (uri.replace("fist://", ""), len(txt)))
    pp = srv.raw("prompts/list", {})
    if "error" in pp:
        problems.append("prompts/list 被拒：%s" % json.dumps(pp["error"], ensure_ascii=False)[:120])
        pr_list = []
    else:
        pr_list = pp.get("result", {}).get("prompts", []) or []
    got_pr = set(x.get("name", "") for x in pr_list)
    for miss in sorted(want_pr - got_pr):
        problems.append("文档声明的 prompt 服务端没有：%s" % miss)
    for extra in sorted(got_pr - want_pr):
        problems.append("服务端有但文档没声明的 prompt：%s" % extra)
    pr_msgs = []
    for name in sorted(got_pr & want_pr):
        g = srv.raw("prompts/get", {"name": name, "arguments": {}})
        if "error" in g:
            problems.append("prompts/get %s 被拒：%s" % (name, json.dumps(g["error"], ensure_ascii=False)[:110]))
            continue
        msgs = g.get("result", {}).get("messages") or []
        if not msgs:
            problems.append("prompts/get %s 返回零条消息" % name)
            continue
        pr_msgs.append("%s=%d消息" % (name.replace("fist:", ""), len(msgs)))
    mm = io.open(os.path.join(root, "moon.mod"), encoding="utf-8", errors="replace").read()
    m_ver = re.search(r'version\s*=\s*"([^"]+)"', mm)
    want_ver = m_ver.group(1) if m_ver else ""
    tt = srv.raw("tools/list", {})
    srv_ver = ((tt.get("result", {}) or {}).get("_meta", {})
               .get("io.modelcontextprotocol/serverInfo", {}) or {}).get("version", "")
    if not want_ver:
        problems.append("moon.mod 里没解析出版本号（版本对表无法自证）")
    elif not srv_ver:
        problems.append("tools/list 的 result._meta 里没有 serverInfo（BUG-21 的验收位置空了）")
    elif srv_ver != want_ver:
        problems.append("serverInfo 版本 %s ≠ moon.mod %s" % (srv_ver, want_ver))
    summary = "resources=%d(声明 %d)[%s] prompts=%d(声明 %d)[%s] serverInfo=%s moon.mod=%s" % (
        len(res_list), len(want_res), " ".join(res_chars),
        len(pr_list), len(want_pr), " ".join(pr_msgs), srv_ver or "?", want_ver or "?")
    return problems, summary


class FakeSrv(object):
    """自述面判据的桩 server：按夹具表回放 RPC 回执，缺项＝被拒。"""

    def __init__(self, spec):
        self.spec = spec

    def raw(self, method, params):
        v = self.spec.get(method)
        if v is None:
            return {"error": {"code": -32000, "message": "refused by fixture"}}
        return {"result": v}


def surface_fixture():
    """与 AGENTS.md 当前声明同集的干净回执（干净支的"零 problem"因此不是自证）。"""
    res = re.search(r"^Resources:(.*)$", io.open(os.path.join(ROOT, "AGENTS.md"),
                                                 encoding="utf-8").read(), re.M)
    pr = re.search(r"^Prompts:(.*)$", io.open(os.path.join(ROOT, "AGENTS.md"),
                                               encoding="utf-8").read(), re.M)
    return {
        "resources/list": {"resources": [{"uri": u} for u in re.findall(r"`(fist://[\w./-]+)`", res.group(1))]},
        "resources/read": {"contents": [{"text": "夹具正文，非空"}]},
        "prompts/list": {"prompts": [{"name": n} for n in re.findall(r"`(fist:[\w./-]+)`", pr.group(1))]},
        "prompts/get": {"messages": [{"role": "user", "content": "x"}]},
        "tools/list": {"_meta": {"io.modelcontextprotocol/serverInfo": {
            "name": "fist-mbt", "version": version_from_moon_mod()}}},
    }


def version_from_moon_mod():
    mm = io.open(os.path.join(ROOT, "moon.mod"), encoding="utf-8", errors="replace").read()
    m = re.search(r'version\s*=\s*"([^"]+)"', mm)
    return m.group(1) if m else ""


def surface_selftest():
    """`--surface-selftest`：自述面判据的 12 支对照（10 支违例必红 + 1 支干净必绿 + 1 支自拒）。

    为什么单独跑：判据只在巡回里跑，而巡回要 node + 产物 + 数分钟——CI 轨执行不了；
    没有可独立执行的对照，它就只是一段"本轮绿过一次"的叙述（本仓踩过的同型坑：
    `--selftest` 没被 CI 那一步执行，自检本身崩了也报绿）。这里用桩 server 把每类违例
    都造一遍，不起 node、不碰库，CI 可直接跑。
    """
    cases = []
    cases.append(("干净：夹具与 AGENTS.md 同集 ⇒ 零 problem", lambda s: None, False))

    def drop_res(s):
        s["resources/list"]["resources"].pop(0)

    def ghost_res(s):
        s["resources/list"]["resources"].append({"uri": "fist://ghost"})

    def blank_res(s):
        s["resources/read"]["contents"][0]["text"] = "   "

    def drop_pr(s):
        s["prompts/list"]["prompts"] = s["prompts/list"]["prompts"][1:]

    def ghost_pr(s):
        s["prompts/list"]["prompts"].append({"name": "fist:ghost"})

    def empty_msg(s):
        s["prompts/get"]["messages"] = []

    def bad_ver(s):
        s["tools/list"]["_meta"]["io.modelcontextprotocol/serverInfo"]["version"] = "9.9.9"

    def no_ver(s):
        s["tools/list"]["_meta"] = {}

    def deny_res(s):
        s["resources/list"] = None

    def deny_pr(s):
        s["prompts/list"] = None

    cases += [
        ("声明的 resource 服务端没有", drop_res, True),
        ("服务端多出的 resource 文档没声明", ghost_res, True),
        ("resource 读回来是空文本", blank_res, True),
        ("声明的 prompt 服务端没有", drop_pr, True),
        ("服务端多出的 prompt 文档没声明", ghost_pr, True),
        ("prompt get 返回零条消息", empty_msg, True),
        ("serverInfo 版本 ≠ moon.mod", bad_ver, True),
        ("serverInfo 验收位为空", no_ver, True),
        ("resources/list 被拒", deny_res, True),
        ("prompts/list 被拒", deny_pr, True),
    ]
    fails = []
    for name, mutate, expect_red in cases:
        spec = surface_fixture()
        mutate(spec)
        probs, summ = surface_probe(FakeSrv(spec))
        print("  %-38s problems=%d %s" % (name, len(probs),
                                          (probs[0][:78] if probs else summ[:78])))
        if bool(probs) != expect_red:
            fails.append(name + ("（该红没红）" if expect_red else "（该绿没绿）"))
    # 第 12 支：文档没有声明行 ⇒ 判据必须自拒，不能静默零 problem
    box = os.path.join(ROOT, "temp", "surf-selftest-%s" % RUN_ID)
    os.makedirs(box, exist_ok=True)
    io.open(os.path.join(box, "AGENTS.md"), "w", encoding="utf-8", newline="\n").write(
        "# 假文档：没有 Resources:/Prompts: 两行\n")
    io.open(os.path.join(box, "moon.mod"), "w", encoding="utf-8", newline="\n").write(
        'version = "0.0.0"\n')
    probs, summ = surface_probe(FakeSrv(surface_fixture()), root=box)
    print("  %-38s problems=%d %s" % ("文档无声明行 ⇒ 判据自拒", len(probs),
                                      (probs[0][:78] if probs else "(空)")))
    if not (len(probs) == 1 and "反解失败" in probs[0]):
        fails.append("反解失败支未自拒")
    print("SURFACE-SELFTEST: %s —— %d 支（%d 违例 + 1 干净 + 1 自拒），不符 %d 支" % (
        "OK" if not fails else "FAIL", len(cases) + 1, len(cases) - 1, len(fails)))
    for f in fails:
        print("  FAIL " + f)
    return 0 if not fails else 2


def surface_snapshot():
    """读面外溢判据的取证面：仓库根一层文件 + memory/ 递归（moon 构建临时件 *.tmp 除外）。"""
    snap = {}
    for name in os.listdir(ROOT):
        p = os.path.join(ROOT, name)
        if os.path.isfile(p) and not name.endswith(".tmp"):
            st = os.stat(p)
            snap[name] = (st.st_size, st.st_mtime_ns)
    mem = os.path.join(ROOT, "memory")
    for dirpath, _dirnames, filenames in os.walk(mem):
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            st = os.stat(p)
            snap[os.path.relpath(p, ROOT).replace("\\", "/")] = (st.st_size, st.st_mtime_ns)
    return snap


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plane", choices=["write", "read"], default="write")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--js", default="")
    ap.add_argument("--surface-selftest", action="store_true",
                    help="只跑自述面判据的对照（桩 server，不起 node、不碰库）")
    a = ap.parse_args()
    if a.surface_selftest:
        return surface_selftest()

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
        log_dir = box
    else:
        cwd = ROOT                      # 读面：真源码树（issue_scan/project_standards 要读到真源码）
        # BUG-100：project_dir 不再是仓库根。带 project_dir 的工具（model_route / pipeline_tick /
        # selfdrive_* / memory_*）会把状态文件写进"被巡回路过"的仓库——上一轮读面就在仓库根长出
        # currentState.txt、memory/_review.count、memory/model-router-tour-read-*.json。
        # 读面照样打到调用面，只是落点改到 temp/ 下的草稿项目。
        proj_box = os.path.join(ROOT, "temp", "tool-tour-proj-" + RUN_ID)
        os.makedirs(proj_box, exist_ok=True)
        iso_db = os.path.join(ROOT, "temp", "tool-tour-%s.db" % RUN_ID)
        proj = os.path.relpath(proj_box, ROOT).replace("\\", "/")
        log_dir = os.path.join(ROOT, "temp")
    env = dict(os.environ)
    env["FIST_DB_PATH"] = iso_db        # 两面都隔离：共享根库一行不动
    before_snap = surface_snapshot() if a.plane == "read" else {}
    ns = "tour-%s-%s" % (a.plane, RUN_ID[-6:])

    print("server = %s (sha256:%s)" % (js, sha8(js)))
    print("plane  = %s  cwd=%s  isolated_db=%s  ns=%s" % (
        a.plane, os.path.relpath(cwd, ROOT).replace("\\", "/"),
        os.path.relpath(iso_db, ROOT).replace("\\", "/"), ns))

    srv = Serve(js, cwd, env, log_dir)
    rows, seedlog = [], []
    try:
        tools = srv.list_tools()
        if len(tools) <= 100:
            print("TOUR: UNUSABLE —— tools/list 只回 %d 个（判据无法自证绝不报绿）" % len(tools))
            return 2
        surf_problems, surf_summary = surface_probe(srv)
        print("自述面（resources/prompts/版本）= %s" % surf_summary)
        for sp in surf_problems:
            print("  !! 自述面 %s" % sp)
        ctx = {"project_dir": proj, "data_dir": proj, "namespace": ns, "now": now_iso(),
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
                    srv = Serve(js, cwd, env, log_dir)
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
                 "surface": {"summary": surf_summary, "problems": surf_problems},
                 "seed": seedlog, "rows": rows, "kinds": kinds},
                ensure_ascii=False, indent=2))
            print("JSON 证据 = %s" % os.path.relpath(jp, ROOT).replace("\\", "/"))
        # 读面外溢判据（BUG-100）：读面只许读——仓库根/memory/ 长出任何新文件即判红。
        # 新建一律致命（读面没有创建仓库文件的正当理由）；memory/ 内被改动同样致命
        # （真账本/真记忆面）；仓库根其它文件被改只列不发红，因为同一时刻可能有并行改动面。
        if a.plane == "read":
            after = surface_snapshot()
            newf = sorted(set(after) - set(before_snap))
            mod = sorted(k for k in set(after) & set(before_snap) if after[k] != before_snap[k])
            mod_mem = [k for k in mod if k.startswith("memory/")]
            mod_root = [k for k in mod if not k.startswith("memory/")]
            print("  读面外溢判据：取证面 %d 项 / 新建 %d / memory 改动 %d / 根改动 %d" % (
                len(before_snap), len(newf), len(mod_mem), len(mod_root)))
            for k in newf:
                print("   NEW       %s" % k)
            for k in mod_mem:
                print("   MOD-MEM   %s" % k)
            for k in mod_root:
                print("   MOD-ROOT  %s（只列不发红：并行改动面）" % k)
            if newf or mod_mem:
                print("!! 读面外溢 ⇒ 判红（巡回探针不该在被测项目里留下任何文件）")
                return 2
        # 红面 = 崩溃 + 未打到调用面 + 复活失败 + 自述面漂移；refused 不算红（那是产品的自述拒绝）
        red = (kinds.get("crashed", 0) + kinds.get("not_tested", 0)
               + kinds.get("broken", 0) + len(surf_problems))
        print("TOUR: %s —— %d 工具 ok=%d refused=%d skipped=%d crashed=%d not_tested=%d 复活=%d 自述面红=%d" % (
            "GREEN" if red == 0 else "RED", len(rows), kinds.get("ok", 0),
            kinds.get("refused", 0), kinds.get("skipped", 0),
            kinds.get("crashed", 0), kinds.get("not_tested", 0), restarts,
            len(surf_problems)))
        return 0 if red == 0 else 1
    finally:
        srv.close()


if __name__ == "__main__":
    sys.exit(main())
