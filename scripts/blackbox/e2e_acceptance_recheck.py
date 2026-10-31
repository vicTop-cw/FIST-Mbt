#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/blackbox/e2e_acceptance_recheck.py — 九月黑客松拒收六项的一键复验探针。

组委会回执点名的六项（原文摘录）：
  A1 物理多租户隔离   —— 「实际 alpha/beta 库零任务，任务写同一主库」
  A2 自动修复三轮     —— 「错误指纹修复返回零修复」
  A3 可替换 Executor  —— 「外部实现 Executor 报 readonly」
  A4 Native serve/demo—— 「Native 的 serve/demo 正常参数仅输出帮助」
  A5 DAG 成环依赖     —— 「DAG 接受成环依赖」
  A6 Omega 验收门     —— 「Omega 验收门可由 archive 绕过」

本脚本把六项**逐条打到调用面**：真起一个 server 进程、真发 MCP 工具调用、真读 sqlite，
每格给 PASS/FAIL/SKIP 与理由，六格全绿才回 rc=0。

为什么不用文档读数说话（AGENTS 判例-37「文本命中 ≠ 行为覆盖」）：
  六项里有五项曾被「已修复 + 有测试」的叙述盖过，而调用面照样漏。这里只认盘上事实。

隔离纪律（check_demo_isolation 硬门）：
  · 子进程一律带 `FIST_DB_PATH=<沙箱>/main.db` ⇒ **绝不**往仓库根 `fist-mbt.db` 写演示行；
  · ns 物理库落 `<沙箱>/.fist-mbt/data/<ns>.db`（MultiStore 默认 data_dir 相对 server cwd）；
  · 沙箱目录每次新建、带 RUN_ID，不复用上一轮残留（残留会把上一轮的绿读到这一轮）。

用法：
    python scripts/blackbox/e2e_acceptance_recheck.py            # 六格
    python scripts/blackbox/e2e_acceptance_recheck.py --selftest  # 再加一格合成违例
    python scripts/blackbox/e2e_acceptance_recheck.py --json      # 另存机器可读证据
环境变量：
    FIST_ACCEPT_JS  指定要验的 server 产物（默认按 _build → dist → LOCALAPPDATA 顺序找）。
                  相对路径按**调用方 cwd**归一；指不到文件即 rc=2 自拒，不静默回落默认候选。
    NODE            指定 node 可执行文件（默认 `node`）
退出码（契约，勿改档）：
    0 = 六格全部 PASS（SKIP 不算 PASS，也不阻塞）
    1 = 任一 FAIL
    2 = 探针自身不可用（找不到 server 产物 / node 起不来）—— 绝不冒用 1
    3 = --selftest 的合成违例没被抓到 ⇒ **尺子坏了**，六格的绿不可信

已知边界（不遮）：A4 的 native 臂只能校「资产平台与文件名是否自洽」+「有本平台产物时真跑一次」；
  Windows 上若本地没有 Windows native 产物，该格回 SKIP 并写明缺什么，不拿 WSL 读数冒充。
"""
import hashlib
import io
import json
import os
import sqlite3
import subprocess
import sys
import time
import uuid

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUN_ID = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + uuid.uuid4().hex[:6]
SANDBOX = os.path.join(ROOT, "temp", "acceptance-recheck", RUN_ID, "box")
ERRLOG = os.path.join(ROOT, "temp", "acceptance-recheck", RUN_ID + ".err")

KNOWN_FLAGS = ("--selftest", "--json", "--help", "-h")
unknown = [a for a in sys.argv[1:] if a.startswith("-") and a not in KNOWN_FLAGS]
if unknown:
    # 判例/R207：自检开关拼错 = 静默失去自检。未知旗标一律拒，不落进真检查分支。
    print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）"
          % (" ".join(unknown), " / ".join(KNOWN_FLAGS)))
    sys.exit(2)

if "--help" in sys.argv[1:] or "-h" in sys.argv[1:]:
    # BUG-524②（R207 的另一半）：旗标**在白名单里但没有处理分支**，比未知旗标更阴——
    # `--help` 会被收下、然后落进真检查分支，把「起 server 跑全量」那 40 秒当帮助跑了。
    # 顺序也是承重的：必须排在 `os.makedirs(SANDBOX)` 之前，否则每问一次帮助留一个空沙箱。
    print(__doc__.strip())
    sys.exit(0)

os.makedirs(SANDBOX, exist_ok=True)

META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "acceptance-recheck", "version": "1"},
}

def resolve_env_js(raw):
    """把 `FIST_ACCEPT_JS` 归一成绝对路径（BUG-524①）。

    存在性判在脚本 cwd、spawn 跑在沙箱 cwd —— 相对路径在这两副面罩下结论相反，
    失效形态是「明明存在的产品报 Cannot find module」，而报错指向 server 起不来。
    """
    raw = (raw or "").strip()
    if not raw:
        return ""
    return raw if os.path.isabs(raw) else os.path.abspath(raw)


JS_PIN = resolve_env_js(os.environ.get("FIST_ACCEPT_JS", ""))
if JS_PIN and not os.path.isfile(JS_PIN):
    # 显式指名却不落空到默认候选：那等于「旗标被承认但不生效」（R207 同族）。
    print("[FATAL] FIST_ACCEPT_JS 指向的文件不存在：%s（已按调用方 cwd 归一，不回落默认候选，rc=2）" % JS_PIN)
    sys.exit(2)

JS_CANDIDATES = [
    JS_PIN,
    os.path.join(ROOT, "_build", "js", "release", "build", "cmd", "cli", "cli.js"),
    os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js"),
    os.path.join(ROOT, "target", "js", "release", "build", "cmd", "cli", "cli.js"),
    os.path.join(ROOT, "dist", "fist-mbt.js"),
    os.path.expandvars(r"%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js"),
]


def find_js():
    for c in JS_CANDIDATES:
        if c and os.path.isfile(c):
            return c
    return ""


def sha8(path):
    h = hashlib.sha256()
    with io.open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()[:8]


class Server:
    """node <js> serve —— 带 FIST_DB_PATH 改道，协议行只认 { 开头（serve 先打横幅）。

    stderr 收进文件而不是 DEVNULL：坏在启动里的形状（require is not defined / 缺 node 版本）
    只有 stderr 看得见；吞掉它等于把可诊断的失败写成不可诊断的红。
    """

    def __init__(self, js, cwd, db):
        env = dict(os.environ)
        env["FIST_DB_PATH"] = db
        self.p = subprocess.Popen(
            [os.environ.get("NODE", "node"), js, "serve"], cwd=cwd,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=io.open(os.path.join(ROOT, "temp", "acceptance-recheck",
                                        RUN_ID + ".err"), "ab"),
            bufsize=0, env=env)
        self.mid = 0

    def _read(self, want, timeout=90):
        t0 = time.time()
        while time.time() - t0 < timeout:
            line = self.p.stdout.readline()
            if not line:
                raise RuntimeError("server closed stdout（见 %s）" % ERRLOG)
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("{"):
                continue
            try:
                m = json.loads(s)
            except Exception:
                continue
            if m.get("id") == want:
                return m
        raise RuntimeError("timeout waiting id=%s" % want)

    def call(self, tool, args, timeout=90):
        self.mid += 1
        w = self.mid
        self.p.stdin.write((json.dumps(
            {"jsonrpc": "2.0", "id": w, "method": "tools/call",
             "params": {"_meta": META, "name": tool, "arguments": args}}) + "\n").encode("utf-8"))
        self.p.stdin.flush()
        m = self._read(w, timeout)
        r = m.get("result") or m.get("error") or {}
        txt = ""
        if isinstance(r, dict):
            c = r.get("content")
            if isinstance(c, list) and c:
                txt = c[0].get("text", "")
            else:
                txt = "ERR:" + str(r.get("message", "unknown"))
        failed = txt.startswith("ERR:") or (isinstance(r, dict) and bool(r.get("isError")))
        try:
            parsed = json.loads(txt)
        except Exception:
            parsed = {}
        return {"rejected": failed, "raw": txt, "json": parsed}

    def tools_count(self, timeout=120):
        self.mid += 1
        w = self.mid
        self.p.stdin.write((json.dumps({"jsonrpc": "2.0", "id": w, "method": "tools/list",
                                        "params": {"_meta": META}}) + "\n").encode("utf-8"))
        self.p.stdin.flush()
        return len((self._read(w, timeout).get("result") or {}).get("tools", []))

    def close(self):
        try:
            self.p.stdin.close()
            self.p.wait(timeout=8)
        except Exception:
            self.p.kill()


def sql1(db, q, a=()):
    """只读取一个标量；库不存在回 None（≠ 0 —— 空库与无库是两种结论，判例-35）。"""
    if not os.path.isfile(db):
        return None
    c = sqlite3.connect("file:%s?mode=ro" % db.replace("\\", "/"), uri=True)
    try:
        row = c.execute(q, a).fetchone()
        return row[0] if row else None
    except Exception:
        return None
    finally:
        c.close()


CELLS = {}


def record(key, verdict, why, evidence):
    CELLS[key] = {"verdict": verdict, "why": why, "evidence": evidence}


def tid_of(res):
    j = res["json"]
    if isinstance(j, dict):
        for k in ("task_id", "id", "bug_id"):
            v = j.get(k)
            if isinstance(v, str) and v:
                return v
    return ""


# ═══════════════════════════════════════════════════════════════════ 起跑
JS = find_js()
if not JS:
    print("[FATAL] 找不到 server 产物。先跑 `moon build --target js --release` "
          "+ `python scripts/patch_esm_main.py`，或用 FIST_ACCEPT_JS 指名。")
    sys.exit(2)

MAIN_DB = os.path.join(SANDBOX, "main.db")
NS_ROOT = os.path.join(SANDBOX, ".fist-mbt", "data")
srv = Server(JS, SANDBOX, MAIN_DB)
try:
    n_tools = srv.tools_count()
except Exception as e:
    print("[FATAL] server 起不来：%s" % e)
    sys.exit(2)
if n_tools < 100:
    # 反幻影：工具面没起来 ⇒ 后面每一格的「没报错」都没有意义
    print("[FATAL] tools/list 只回 %d 个工具（<100）⇒ 产物不可用，六格拒绝出数" % n_tools)
    sys.exit(2)
print("server = %s (sha8=%s) tools=%d sandbox=%s"
      % (os.path.relpath(JS, ROOT).replace("\\", "/"), sha8(JS), n_tools,
         os.path.relpath(SANDBOX, ROOT).replace("\\", "/")))

NS = "alpha"
NS_DB = os.path.join(NS_ROOT, NS + ".db")
srv.call("store_open", {"namespace": NS})
for a in ("human_steward", "exec-1"):
    srv.call("agent_acl_grant", {"agent_id": a, "namespace": NS, "can_write": True})


def main_rows(tag):
    return sql1(MAIN_DB, "select count(*) from tasks where ns=?", (tag,)) or 0


def ns_rows():
    return sql1(NS_DB, "select count(*) from tasks") or 0


# ───────────────────────────────────────────────── A1 物理多租户隔离 ──
A1_PATHS = [
    ("publish", lambda: srv.call("publish", {
        "project_dir": ".", "description": "A1 隔离复验-publish",
        "namespace": NS, "created_by": "human_steward"})),
    ("report_bug", lambda: srv.call("report_bug", {
        "project_dir": ".", "summary": "A1 隔离复验-bug", "detail": "d",
        "publish_task": True, "task_ns": NS, "reported_by": "acceptance"})),
    ("supervisor_task_upsert", lambda: srv.call("supervisor_task_upsert", {
        "project_dir": ".", "by": "human_steward", "namespace": NS,
        "items": [{"description": "A1 隔离复验-supervisor"}]})),
    ("dag_publish", lambda: srv.call("dag_publish", {
        "project_dir": ".", "description": "A1 隔离复验-dag",
        "namespace": NS, "created_by": "human_steward", "depends_on": "[]"})),
    ("watchdog_tick(cold_start)", lambda: srv.call("watchdog_tick", {
        "namespace": NS, "cold_start": True, "project_dir": ".",
        "next_description": "A1 隔离复验-watchdog 冷启动"})),
    ("pipeline_tick", lambda: srv.call("pipeline_tick", {
        "project_dir": ".", "namespace": NS, "phase": "plan"})),
    ("selfdrive_publish_next", lambda: srv.call("selfdrive_publish_next", {
        "project_dir": ".", "namespace": NS, "max_tasks": 1})),
    ("heal", lambda: srv.call("heal", {"namespace": NS, "timeout_sec": 1})),
]
a1_bad, a1_detail = [], []
for name, fire in A1_PATHS:
    before_ns, before_main = ns_rows(), main_rows(NS)
    r = fire()
    after_ns, after_main = ns_rows(), main_rows(NS)
    grew_main = after_main - before_main
    line = "%s: ns_db %+d, main_db(ns=%s) %+d%s" % (
        name, after_ns - before_ns, NS, grew_main,
        "" if not r["rejected"] else " [工具拒了: " + r["raw"][:70] + "]")
    a1_detail.append(line)
    if grew_main > 0:
        a1_bad.append(name)
# 反向的另一半：ns 库里的行必须**也**带着 ns=<该库名> 的列标签。
# 只查「行没落进主库」不够 —— 落进 alpha.db 却盖章 ns=default 同样是脑裂
# （库寻址与列值分家，BUG-420/R114 实测过的那个形状），按 ns 过滤的读侧会两头看不见。
mism = sql1(NS_DB, "select count(*) from tasks where ns<>?", (NS,)) or 0
if mism > 0:
    a1_bad.append("ns 库里有 %d 行列标签不等于库名 %s（库寻址与列值分家）" % (mism, NS))
a1_detail.append("ns 库列标签核对：ns<>%s 的行数=%s" % (NS, mism))
a1_total = ns_rows()
why = ("主库长出 %d 条 ns=%s 的行 ⇒ 隔离未闭环（漏点：%s）"
       % (sum(1 for _ in a1_bad), NS, ", ".join(a1_bad))) if a1_bad else \
      ("八条写路径逐条过：主库 ns=%s 行数恒 0，行全部落 %s.db" % (NS, NS))
verdict = "FAIL" if a1_bad else ("PASS" if a1_total > 0 else "FAIL")
if not a1_bad and a1_total == 0:
    verdict = "FAIL"
    why = "ns 库一条都没有 ⇒ 探针看不见样本（判例-35：全 0 的分布先怀疑尺子）"
record("A1_多租户物理隔离", verdict, why, a1_detail)

# ───────────────────────────────────────────────── A5 DAG 成环依赖 ──
ids = {}
for name, deps in (("A", []), ("B", ["A"]), ("C", ["B"])):
    r = srv.call("dag_publish", {
        "project_dir": ".", "description": "A5 节点 " + name, "namespace": NS,
        "created_by": "human_steward",
        "depends_on": json.dumps([ids.get(d, "?") for d in deps])})
    ids[name] = tid_of(r)
    if not ids[name]:
        break
a5_detail, a5_bad = [], []
if len(ids) == 3 and all(ids.values()):
    before = sql1(NS_DB, "select depends_on from tasks where id=?", (ids["A"],))
    r = srv.call("dag_depend", {"task_id": ids["A"], "dep_id": ids["C"], "namespace": NS})
    a5_detail.append("dag_depend 关环(A←C)：%s" % ("拒" if r["rejected"] else "放行!!"))
    if not r["rejected"]:
        a5_bad.append("dag_depend 关环")
    r = srv.call("supervisor_task_upsert", {
        "project_dir": ".", "by": "human_steward", "namespace": NS,
        "items": [{"task_id": ids["A"], "depends_on": [ids["C"]]}]})
    closed = (not r["rejected"]) and r["json"].get("ok_count", 0) > 0
    a5_detail.append("supervisor_task_upsert 关环(A←C)：%s" % ("拒" if not closed else "放行!!"))
    if closed:
        a5_bad.append("supervisor_task_upsert 关环")
    r = srv.call("supervisor_task_upsert", {
        "project_dir": ".", "by": "human_steward", "namespace": NS,
        "items": [{"task_id": ids["B"], "depends_on": [ids["B"]]}]})
    looped = (not r["rejected"]) and r["json"].get("ok_count", 0) > 0
    a5_detail.append("supervisor_task_upsert 自环(B←B)：%s" % ("拒" if not looped else "放行!!"))
    if looped:
        a5_bad.append("supervisor_task_upsert 自环")
    after = sql1(NS_DB, "select depends_on from tasks where id=?", (ids["A"],))
    a5_detail.append("盘上 A.depends_on：改前=%s 改后=%s" % (before, after))
    if after != before:
        a5_bad.append("落库被写脏")
    # 反向对照：合法边必须放行（否则这格是被恒红刷绿的）
    r = srv.call("dag_depend", {"task_id": ids["C"], "dep_id": ids["A"], "namespace": NS})
    a5_detail.append("对照：合法边 C←A（幂等）%s" % ("拒!!" if r["rejected"] else "放行"))
    if r["rejected"]:
        a5_bad.append("合法边被误杀")
else:
    a5_bad.append("夹具没建起来（A/B/C  ids=%s）" % ids)
record("A5_DAG 成环依赖", "FAIL" if a5_bad else "PASS",
       "拒环漏点：%s" % (", ".join(a5_bad) if a5_bad else "无 —— 三条写边入口同过一道环闸"),
       a5_detail)

# ───────────────────────────────────────────────── A6 Omega 验收门 ──
a6_detail, a6_bad = [], []
r = srv.call("publish", {"project_dir": ".", "description": "A6 验收门 [omega:required]",
                         "namespace": NS, "created_by": "human_steward"})
T = tid_of(r)
if not T:
    a6_bad.append("omega 任务没建出来: " + r["raw"][:80])
else:
    srv.call("claim", {"task_id": T, "assignee": "exec-1", "namespace": NS})
    e = srv.call("execute", {"task_id": T, "namespace": NS,
                            "deliverable": "交付物 src/demo.mbt:1 已落地并通过自测"})
    a6_detail.append("execute：%s" % ("拒: " + e["raw"][:60] if e["rejected"] else "放行"))
    st0 = sql1(NS_DB, "select status from tasks where id=?", (T,))
    a6_detail.append("当前状态=%s" % st0)
    r = srv.call("verify", {"task_id": T, "verifier": "human_steward", "namespace": NS})
    a6_detail.append("verify（未做成果复验）：%s" % ("拒" if r["rejected"] else "放行!!"))
    if not r["rejected"]:
        a6_bad.append("verify 未拦")
    # 归档面：把任务挪到「已暂停」再 force 归档 —— 这是评委说的「用 archive 绕过验收门」那条道
    # 「已暂停/已打回」是 force 唯一能碰到的非完成态，而 Omega 任务走不到「已完成」
    # （verify 先把住），所以这一格测的正是「force 归档能不能顶掉验收门」。
    p = srv.call("pause", {"task_id": T, "namespace": NS, "agent": "exec-1"})
    st1 = sql1(NS_DB, "select status from tasks where id=?", (T,))
    a6_detail.append("pause(agent=exec-1)：%s ⇒ 状态=%s"
                     % ("拒: " + p["raw"][:70] if p["rejected"] else "放行", st1))
    if st1 != "已暂停":
        a6_bad.append("夹具到不了「已暂停」，force 归档这一格无从验起（status=%s）" % st1)
    r = srv.call("archive", {"task_id": T, "by": "human_steward", "force": True, "namespace": NS})
    a6_detail.append("archive(force=true)：%s ⇒ %s"
                     % ("拒" if r["rejected"] else "放行!!", r["raw"][:90]))
    if not r["rejected"]:
        a6_bad.append("archive force=true 绕过验收门")
    elif "Omega" not in r["raw"]:
        a6_bad.append("archive 是被别的原因拒的（状态机/ACL），门本身没被验到：" + r["raw"][:80])
    st_after = sql1(NS_DB, "select status from tasks where id=?", (T,))
    a6_detail.append("归档尝试后状态=%s（不得为 已归档）" % st_after)
    if st_after == "已归档":
        a6_bad.append("任务被静默了账")
    # 反向对照：一条**不带** Omega 标记的任务走完整闭环必须能归档，
    # 否则上面两条红可能只是「谁都归档不了」，而不是「门在拦未验收的」。
    r2 = srv.call("publish", {"project_dir": ".", "description": "A6 对照无标记",
                              "namespace": NS, "created_by": "human_steward"})
    T2 = tid_of(r2)
    if not T2:
        a6_bad.append("对照任务没建出来")
    else:
        srv.call("claim", {"task_id": T2, "assignee": "exec-1", "namespace": NS})
        srv.call("execute", {"task_id": T2, "namespace": NS, "agent": "exec-1",
                             "deliverable": "对照交付物 src/demo2.mbt:1 已落地并通过自测"})
        srv.call("submit", {"task_id": T2, "namespace": NS, "agent": "exec-1"})
        v2 = srv.call("verify", {"task_id": T2, "verifier": "human_steward", "namespace": NS})
        a6_detail.append("对照 verify（无标记，门不该拦）：%s"
                         % ("拒!! 门在错杀: " + v2["raw"][:70] if v2["rejected"] else "放行"))
        c = srv.call("archive", {"task_id": T2, "by": "human_steward", "namespace": NS})
        a6_detail.append("对照 archive：%s"
                         % ("放行" if not c["rejected"] else "拒!! 门在错杀: " + c["raw"][:70]))
        if c["rejected"]:
            a6_bad.append("对照被误杀（合法任务也归不了档 ⇒ 这不是门的功劳）")
record("A6_Omega 验收门", "FAIL" if a6_bad else "PASS",
       "绕过点：%s" % (", ".join(a6_bad) if a6_bad else "verify 与 archive(force) 双向都拦得住"),
       a6_detail)

# ───────────────────────────────────────────────── A2 自动修复三轮 ──
broken = {"file_name": "s1.json",
          "content": json.dumps({"objective": "把 x 改成 y", "acceptance": ["x==y"],
                                 "fingerprint": "0000000000000000"}, ensure_ascii=False)}
r = srv.call("omega_verify_fix", {"specs": [broken], "max_rounds": 3})
j = r["json"] if isinstance(r["json"], dict) else {}
fixes = j.get("fixes_applied") or []
rounds = j.get("rounds") or []
a2_detail = ["回执 fixes_applied=%d 条 / total_rounds=%s" % (len(fixes), j.get("total_rounds"))]
if rounds:
    a2_detail.append("第 1 轮 note=%s" % str(rounds[0].get("note", ""))[:120])
a2_bad = []
if r["rejected"]:
    a2_bad.append("工具直接报错: " + r["raw"][:90])
if not fixes:
    a2_bad.append("fixes_applied 为空（=评委读到的「零修复」）")
if j.get("veto"):
    a2_bad.append("veto=true（一票否决 ⇒ 修复未成立）")
record("A2_自动修复三轮", "FAIL" if a2_bad else "PASS", "; ".join(a2_bad) if a2_bad else
       "坏指纹被真修掉并复验通过，回执给出修复条目", a2_detail)

# ───────────────────────────────────────────────── A3 可替换 Executor ──
# 评委原话是「外部实现 Executor 报 readonly」。这一格打的是**调用面**的三件事：
#   ① 注册一个自定义执行器 ⇒ 必须可用（不是只登记个名字随后被拒）；
#   ② 派发真的按注册名推导 binary，提示词只作为 argv 字面量（不经 shell）；
#   ③ 未注册的执行器必须被拒 —— 这条安全线不能被"可替换"顶掉。
# trait 本身在**包外**可实现（那句 4145 readonly 报错的正身）由
# tests/external_executor/ 这个独立 MoonBit 包编译期自证，不在本探针里（Python 探不到编译面）。
a3_detail, a3_bad = [], []
reg = srv.call("executor_register", {"name": "acc-ext", "abilities": ["编排"]})
a3_detail.append("executor_register(acc-ext)：%s" % reg["raw"][:150])
if reg["rejected"]:
    a3_bad.append("注册被拒: " + reg["raw"][:90])
run = srv.call("executor_run", {"project_dir": ".", "executor": "acc-ext",
                                "prompt": "写一个 hello", "dry_run": True})
a3_detail.append("executor_run(dry_run)：%s" % run["raw"][:200])
if run["rejected"]:
    a3_bad.append("已注册的外部执行器仍跑不了: " + run["raw"][:90])
else:
    rj = run["json"] if isinstance(run["json"], dict) else {}
    if rj.get("binary") != "acc-ext":
        a3_bad.append("binary 不是注册名（实得 %s）⇒ 登记表没有决定可执行文件" % rj.get("binary"))
    if rj.get("argv") != ["写一个 hello"]:
        a3_bad.append("argv 形状不符（实得 %s）" % rj.get("argv"))
    if rj.get("dry_run") is not True or rj.get("executed") is not False:
        a3_bad.append("dry_run 语义破了（executed/dry_run 字段与声明不一致）")
ghost = srv.call("executor_run", {"project_dir": ".", "executor": "没注册过的那个",
                                  "prompt": "hi", "dry_run": True})
a3_detail.append("未注册执行器：%s" % ("拒（安全线在）" if ghost["rejected"] else "放行!! 白名单被绕过"))
if not ghost["rejected"]:
    a3_bad.append("未注册执行器被放行 ⇒ 「可替换」把把关的那道门换掉了")
record("A3_可替换 Executor", "FAIL" if a3_bad else "PASS",
       "; ".join(a3_bad) if a3_bad else
       "注册即可派发（binary=注册名、argv=[prompt] 不经 shell），未注册一律拒；"
       "trait 的包外可实现面由 tests/external_executor 独立编译自证",
       a3_detail)

# ───────────────────────────────────────────────── A4 native serve/demo ──
# 评委原话：「Native 的 serve/demo 正常参数仅输出帮助」。这一格打三层，逐层如实：
#   ① 发布资产（_release/*.zip）内部文件的**实际平台魔数**必须与资产名声明的平台一致
#      —— 名字说 linux 而里面是 PE（或反过来），用户在 Windows 上装到的就是「跑不了/只会打印帮助」；
#   ② 本机有可执行的 native 产物时，**真跑** serve/demo/version，断言不是帮助页；
#   ③ 未知子命令的退出码必须非 0（与 js 轨同档）。
# 本机没有本平台 native 产物时，②③ 记 SKIP 并写明缺什么 —— 拿 WSL 读数冒充 Windows 交付物，
# 与拿「服务本体能跑」冒充「服务被正确接入」（判例-33）是同一个错。
a4_detail, a4_bad, a4_skip = [], [], []
REL = os.path.join(ROOT, "_release")
MAGIC = {b"\x7fELF": "linux-elf", b"MZ": "windows-pe"}
HOST = "windows-pe" if os.name == "nt" else "linux-elf"


def magic_of(path):
    try:
        head = io.open(path, "rb").read(4)
    except Exception:
        return "读不到"
    for k, v in MAGIC.items():
        if head.startswith(k):
            return v
    return "unknown(%s)" % head.hex()


def declared_platform(fname):
    n = fname.lower()
    if "linux" in n:
        return "linux-elf"
    if "windows" in n or "win" in n:
        return "windows-pe"
    if "native-darwin" in n or "macos" in n:
        return None            # 本表没登记的平台：不误判，只如实说没口径
    return None


if os.path.isdir(REL):
    zips = [f for f in sorted(os.listdir(REL)) if f.lower().endswith(".zip")]
    if not zips:
        a4_skip.append("_release/ 下没有 zip 资产（未构建发布包）")
    import zipfile
    for z in zips:
        zp = os.path.join(REL, z)
        want = declared_platform(z)
        try:
            zf = zipfile.ZipFile(zp)
            names = zf.namelist()
        except Exception as ex:
            a4_bad.append("%s 打不开：%s" % (z, ex))
            continue
        for n in names:
            base = os.path.basename(n)
            if base.lower().endswith((".js", ".py", ".md", ".json", ".txt")) or base == "":
                continue          # 文本资产没有平台形状，比魔数没有意义
            try:
                head = zf.read(n)[:4]
            except Exception:
                continue
            got = "unknown"
            for k, v in MAGIC.items():
                if head.startswith(k):
                    got = v
            a4_detail.append("%s :: %s ⇒ 声明平台=%s 实际=%s" % (z, base, want or "-", got))
            if want and got != want:
                a4_bad.append("%s 里 %s 是 %s 而资产名声明 %s ⇒ 装到目标平台跑不了"
                              % (z, base, got, want))
            # 名字与内容两条线都要自洽：linux 资产里的可执行文件不该叫 .exe
            if want == "linux-elf" and base.lower().endswith(".exe"):
                a4_bad.append("%s 里的 linux 产物叫 %s（Windows 侧按 PATHEXT 会优先挑它）"
                              % (z, base))
    # 本地构建目录里的散落产物：只报「名字/内容不自洽」这一条形状，不当交付物判
    for d in sorted(os.listdir(REL)):
        dd = os.path.join(REL, d)
        if not os.path.isdir(dd):
            continue
        for f in sorted(os.listdir(dd)):
            fp = os.path.join(dd, f)
            if not os.path.isfile(fp) or os.path.getsize(fp) < 100000:
                continue
            real = magic_of(fp)
            if real in ("linux-elf", "windows-pe"):
                if f.lower().endswith(".exe") and real != "windows-pe":
                    # _release/ 是 gitignored 的本机构建目录，里面躺着什么**不代表交付物**
                    # （交付物是上面逐只核对过魔数的 zip）。所以这一条只登记、不判红：
                    # 拿本地残留判 FAIL，等于让探针看的是上一位构建者留在盘上的影子。
                    a4_detail.append(
                        "本机残留 %s/%s 是 %s 却叫 .exe（非交付物，仅提示；"
                        "CI 的 windows 臂见 release.yml:185，产物名 fist-mbt-native-win-x64-*.zip）"
                        % (d, f, real))
else:
    a4_skip.append("_release/ 不在（未构建发布包）")

native_bin = ""
for cand in (os.path.join(REL, "native", "fist-mbt.exe" if os.name == "nt" else "fist-mbt"),
             os.path.join(REL, "native", "fist-mbt"),
             os.path.join(REL, "native-linux", "fist-mbt"),
             os.path.join(REL, "native-windows", "fist-mbt.exe")):
    if os.path.isfile(cand) and magic_of(cand) == HOST:
        native_bin = cand
        break
if native_bin:
    a4_detail.append("本平台 native 产物 = %s" % os.path.relpath(native_bin, ROOT).replace("\\", "/"))
    for arg, must in (("version", "FIST-Mbt v"), ("demo", "七态闭环"), ("serve", "serve")):
        try:
            pr = subprocess.run([native_bin, arg], capture_output=True, timeout=30,
                                cwd=os.path.dirname(native_bin), stdin=subprocess.DEVNULL)
            out = pr.stdout.decode("utf-8", "replace") + pr.stderr.decode("utf-8", "replace")
            a4_detail.append("native %s ⇒ rc=%s 命中「%s」=%s"
                             % (arg, pr.returncode, must, must in out))
            if must not in out:
                a4_detail.append("   首行=%s" % out.splitlines()[0] if out.splitlines() else ""[:120])
                if "Usage" in out or "用法" in out:
                    a4_bad.append("native %s 只回帮助页（=评委读到的形状）" % arg)
                else:
                    a4_bad.append("native %s 输出里没有 %s" % (arg, must))
        except Exception as ex:
            a4_bad.append("native %s 跑不起来：%s" % (arg, ex))
    try:
        pr = subprocess.run([native_bin, "definitely-not-a-subcmd"], capture_output=True,
                            timeout=30, cwd=os.path.dirname(native_bin),
                            stdin=subprocess.DEVNULL)
        a4_detail.append("native 未知子命令 ⇒ rc=%s（js 轨是 rc=2）" % pr.returncode)
        if pr.returncode == 0:
            a4_bad.append("native 未知子命令 rc=0 ⇒ cli_exit 的退出码在 native 轨没生效"
                          "（js 轨同参数 rc=2；账本 BUG-501）")
    except Exception as ex:
        a4_bad.append("native rc 探针跑不起来：%s" % ex)
else:
    a4_skip.append("本机(%s)没有可执行的 native 产物 ⇒ serve/demo/rc 两格只能 SKIP；"
                   "已发布 native 资产仅 linux-x64" % HOST)
verdict = "FAIL" if a4_bad else ("PASS" if not a4_skip else "SKIP")
record("A4_native serve/demo", verdict,
       ("绕过点：" + "; ".join(a4_bad)) if a4_bad else
       ("PASS+披露：" + "; ".join(a4_skip)) if a4_skip else
       "; ".join(a4_skip),
       a4_detail)

# ───────────────────────────────────────────────── ST 合成违例 ──
if "--selftest" in sys.argv[1:]:
    # 把探针的判据挪到一个「必然违例」的样本上：手工往主库塞一行 ns=<合成标签>，
    # 让 A1 那套读数逻辑再跑一遍 ⇒ 必须报出漏点。抓不到 = 尺子坏了，六格的绿不可信。
    synth = "synthetic-leak-" + RUN_ID[-6:]
    c = sqlite3.connect(MAIN_DB)
    try:
        c.execute("insert into tasks (id,parent_id,project_dir,ns,priority,importance,depth,"
                  "split_n,level,status,assignee,description,deliverable,created_at,updated_at,"
                  "completed_by,cleanup_mode,depends_on,omega_required,created_by) "
                  "values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  ("ZZ-synth", "", ".", synth, "中", "中", 3, 3, 6, "待领取", "",
                   "合成违例", "", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z",
                   "", "deferred", "[]", 0, "acceptance-selftest"))
        c.commit()
    finally:
        c.close()
    caught = (sql1(MAIN_DB, "select count(*) from tasks where ns=?", (synth,)) or 0) > 0
    record("ST1_合成违例(尺子自检)", "PASS" if caught else "FAIL",
           "往主库注入 ns=%s 的行后，读数逻辑必须看得见（看不见=恒绿探针）" % synth,
           ["main_db(synthetic ns)=%s" % sql1(MAIN_DB,
                                              "select count(*) from tasks where ns=?", (synth,))])
    if not caught:
        print("[FATAL] 合成违例没被抓到 ⇒ 探针恒绿")
        for k, v in CELLS.items():
            print("%-30s %s  why=%s" % (k, v["verdict"], v["why"]))
        sys.exit(3)

    # ── ST2 `FIST_ACCEPT_JS` 相对路径归一（BUG-524①，变异对照内建）──────────
    # 真跑一次 spawn 用的那副面罩：把 cwd 切到沙箱再判存在性。不做归一 ⇒ 这一格必红
    # （naive 形态是「原样交给 os.path.isfile」，在沙箱 cwd 下就是 False）。
    rel_target = os.path.join("temp", "acceptance-recheck", RUN_ID, "b524_probe.js")
    abs_target = os.path.join(ROOT, rel_target)
    io.open(abs_target, "w", encoding="utf-8").write("// 合成产物，只用于路径归一自检\n")
    _cwd0 = os.getcwd()
    try:
        os.chdir(SANDBOX)                      # 与 Server(...) 的 cwd 同一副面罩
        naive_ok = os.path.isfile(rel_target)  # 不归一的读法
        os.chdir(_cwd0)                        # 归一发生在调用方 cwd
        resolved = resolve_env_js(rel_target)
        resolved_ok = os.path.isfile(resolved)
    finally:
        os.chdir(_cwd0)
    st2_ok = resolved_ok and os.path.isabs(resolved) and resolved == abs_target
    record("ST2_相对路径归一(BUG-524)", "PASS" if st2_ok else "FAIL",
           "FIST_ACCEPT_JS 给相对路径时必须按**调用方 cwd**归一；不归一则沙箱 cwd 下读成不存在"
           "（naive 读数=%s ⇒ 未归一会在这里红）" % naive_ok,
           ["raw=%s" % rel_target,
            "resolved=%s isfile=%s" % (resolved, resolved_ok),
            "naive_isfile_in_sandbox=%s" % naive_ok])
    if not st2_ok:
        print("[FATAL] ST2：路径归一失灵 ⇒ FIST_ACCEPT_JS 是个被承认但不生效的旗标")
        sys.exit(3)

    # ── ST3 `--help` 必须真的只出帮助（BUG-524②）──────────────────────────
    # 行为级：起子进程跑 `--help`，要求 rc=0、回了用法段、**且没进真检查分支**
    # （真检查会打 `server = ` 那行横幅）。摘掉处理分支 ⇒ 落进真检查 ⇒ 这一格红。
    hp = subprocess.run([sys.executable, os.path.abspath(__file__), "--help"],
                        capture_output=True, timeout=120)
    htxt = hp.stdout.decode("utf-8", "replace")
    st3_ok = (hp.returncode == 0 and "用法：" in htxt and "server = " not in htxt)
    record("ST3_帮助旗标(BUG-524)", "PASS" if st3_ok else "FAIL",
           "--help/-h 在白名单里就必须有处理分支；否则 40 秒全量复验会被当帮助跑掉",
           ["rc=%d 有用法=%s 落了真检查=%s" % (hp.returncode, "用法：" in htxt,
                                               "server = " in htxt)])
    if not st3_ok:
        print("[FATAL] ST3：--help 没被处理（rc=%d）⇒ 白名单里有旗标没人认领"
              % hp.returncode)
        sys.exit(3)

srv.close()

# ═══════════════════════════════════════════════════════════════════ 结论
fails = [k for k, v in CELLS.items() if v["verdict"] == "FAIL"]
skips = [k for k, v in CELLS.items() if v["verdict"] == "SKIP"]
if "--json" in sys.argv[1:]:
    jp = os.path.join(ROOT, "temp", "acceptance_recheck_%s.json" % RUN_ID)
    io.open(jp, "w", encoding="utf-8").write(json.dumps(
        {"started_utc": RUN_ID, "server_js": JS, "server_sha8": sha8(JS),
         "tools": n_tools, "cells": CELLS}, ensure_ascii=False, indent=2))
    print("JSON 证据 = %s" % os.path.relpath(jp, ROOT).replace("\\", "/"))
for k in sorted(CELLS):
    v = CELLS[k]
    print("%-34s %-5s  %s" % (k, v["verdict"], v["why"]))
    for line in (v["evidence"] or [])[:8]:
        print("      · %s" % line)
n_pass = len([1 for v in CELLS.values() if v["verdict"] == "PASS"])
n_self = len([k for k in CELLS if k.startswith("ST")])
print("结论：%d 格（拒收项 %d + 尺子自检 %d）= %d PASS / %d FAIL / %d SKIP"
      "（格数与分类均从 CELLS 反解，不手写）"
      % (len(CELLS), len(CELLS) - n_self, n_self, n_pass, len(fails), len(skips)))
if fails:
    sys.exit(1)
sys.exit(0)
