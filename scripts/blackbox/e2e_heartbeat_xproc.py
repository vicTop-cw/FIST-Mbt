#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""BUG-119 常驻判据：看护语义必须打到**跨进程调用面**才能观测到。

为什么它是黑盒脚本而不是单元测试（终审 2026-09-29 记）：
  - `src/ops/ops_test.mbt` 的夹具是 MemoryStore + **同进程** Heartbeat 对象，
    结构上看不见"另一个进程上报的心跳读不到"这一格；
  - `src/ops/ops_watchdog_test.mbt` 虽然用真 SQLite，但只有一个进程；
  - 缺陷本体（heal 读进程内内存心跳表 + `None => true`）只有在
    "进程 A 写心跳 / 进程 B 判活" 的形状下才现形——所以判据必须起两个真进程。

四臂（缺一即 FAIL，结论行带基数门，不许"跑了 3 臂算绿"）：
  A 无心跳行 + 刚刚活动过  -> 不回滚（BUG-119 的"首拍即死"；旧码在此必红）
  B 进程 A 心跳 -> 进程 B   -> 跨进程可见（last_seen 非空）且 heal 不误杀
  C 已暂停任务 + 心跳早已过期 -> 不回滚（看护范围只含活跃态）
  D 无心跳行 + 活动时钟超过 timeout -> 仍回滚（no_signal 语义没有被削弱）

用法（与 .github/workflows/ci.yml 的 "Heartbeat cross-process guard" 一步同形）：
  moon build --target js cmd/cli
  python scripts/patch_esm_main.py
  python scripts/blackbox/e2e_heartbeat_xproc.py
"""
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CLI = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js")
BOX = os.path.join(ROOT, "temp", "hb-xproc-box")
DB = os.path.join(ROOT, "temp", "hb-xproc.db")
NS = "hb-xproc"
# 协议注记：2026-07-28 版无 initialize 握手，_meta 必须逐条请求带（否则 -32602）
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "hb-xproc-guard", "version": "1"},
}

RESULTS = []
# 八格的声明（模块级：main() 的基数门与 selftest() 的集合一致性对照共用，避免两处各写一遍）
EXPECTED = [
    "A0 heartbeat 自述已落库(persisted)",
    "A 无心跳+刚活动 -> 不回滚",
    "B1 heal 自述读的是持久化表",
    "B 跨进程心跳可见（last_seen 非空）",
    "C 已暂停任务不被回滚",
    "D 无心跳+活动时钟超 timeout -> 仍回滚",
    "D2 回滚后状态是可重派的「已领取」",
    "E 判死却回滚不了的条目必须走 skipped（本夹具应全可回滚）",
]


# ---------------------------------------------------------------- 八格的纯判定
# 抽成纯函数的理由（BUG-50 / J10：「判据必须先证明自己会红」）：判定若埋在 main() 的实时
# 回执里，`--selftest` 就只能靠"起两个真进程"来验 —— 真进程一起不来判据自己先崩，自检就
# 退化成"链通不通"，**验不出"某支判据会不会红"**。纯函数让每格都能喂合成回执。
def p_hb_persisted(hb1):
    """A0：heartbeat 自述已落库（persisted=true 且 backend=sqlite）——内存后端不许冒充 durable。"""
    return hb1.get("persisted") is True and hb1.get("backend") == "sqlite"


def p_no_heartbeat_recent_not_healed(h_a):
    """A：无心跳行 + 刚刚活动过 ⇒ 不回滚（BUG-119 的"首拍即死"；旧码在此必红）。"""
    return (h_a.get("healed") or []) == []


def p_heal_reads_durable(h_a):
    """B1：heal 自述读的是持久化心跳表（backend=sqlite 且 heartbeat_source=sqlite-heartbeats）。"""
    return h_a.get("backend") == "sqlite" and h_a.get("heartbeat_source") == "sqlite-heartbeats"


def p_xproc_heartbeat_visible(act, tid):
    """B：进程 A 上报的心跳在进程 B 可见（该任务在 active_tasks 且 last_seen 非空）。"""
    return tid in act and str(act.get(tid) or "") != ""


def p_paused_not_rolled_back(wt, h_a, tid):
    """C：已暂停任务不被回滚（看护范围只含活跃态）。"""
    return tid not in (wt.get("healed_tasks") or []) and tid not in (h_a.get("healed") or [])


def p_over_timeout_still_healed(h_d, tids):
    """D：无心跳 + 活动时钟超 timeout ⇒ 仍回滚（no_signal 语义没有被削弱）。"""
    healed = h_d.get("healed") or []
    return all(t in healed for t in tids)


def p_skipped_disclosed(h_d):
    """E：判死却回滚不了的条目必须走 skipped 披露（旧实现把 reopen 失败静默吞掉）。"""
    return h_d.get("skipped") is not None and h_d.get("skipped") == []


def p_rolled_back_status_claimable(st, tid):
    """D2：回滚后状态是可重派的「已领取」（别拿状态字面判 heal）。"""
    return st.get(tid) == "已领取"


def arms_consistent(names, declared):
    """格子集合与声明逐字一致（不等即判「判据坏了，不是产品坏了」）。"""
    return sorted(names) == sorted(declared)


def say(k, v):
    print("%-34s %s" % (k, v), flush=True)


def arm(name, ok, detail):
    RESULTS.append((name, bool(ok)))
    say(("  %s " % name), "%s | %s" % ("PASS" if ok else "FAIL", detail))


def die(msg, hint=""):
    print("E2E-HEARTBEAT-XPROC REFUSED: %s" % msg, flush=True)
    if hint:
        print("  出路：%s" % hint, flush=True)
    sys.exit(2)


class Sess:
    """一个真 `node cli.js serve` 进程：FIST_DB_PATH 指到隔离库，绝不碰仓库根台账。"""

    def __init__(self, tag):
        if not os.path.isfile(CLI):
            die("产物不存在 %s" % CLI, "moon build --target js cmd/cli && python scripts/patch_esm_main.py")
        env = dict(os.environ)
        env["FIST_DB_PATH"] = DB
        self.p = subprocess.Popen(
            ["node", CLI, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, cwd=BOX, env=env, bufsize=0)
        self.tag = tag
        self.lines = []
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for raw in iter(self.p.stdout.readline, b""):
            s = raw.decode("utf-8", "replace").strip()
            # BUG-101/R12：stdout 只许走 JSON-RPC；横幅类杂质若回到 stdout，这一格自己就会红
            if s.startswith("{"):
                try:
                    self.lines.append(json.loads(s))
                except Exception:
                    pass

    def call(self, name, args, timeout=30):
        self.n = getattr(self, "n", 0) + 1
        my = self.n
        req = {"jsonrpc": "2.0", "id": my, "method": "tools/call",
               "params": {"name": name, "arguments": args, "_meta": META}}
        self.p.stdin.write((json.dumps(req) + "\n").encode())
        self.p.stdin.flush()
        t0 = time.time()
        while time.time() - t0 < timeout:
            hit = [m for m in self.lines if m.get("id") == my]
            if hit:
                r = hit[0]
                if "error" in r:
                    return {"_error": r["error"].get("message")}
                c = r.get("result") or {}
                txt = (c.get("content") or [{}])[0].get("text", "")
                try:
                    return json.loads(txt)
                except Exception:
                    return {"_raw": txt}
            time.sleep(0.05)
        return {"_timeout": True}

    def kill(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        try:
            self.p.kill()
            self.p.wait(timeout=5)
        except Exception:
            pass


def db_rows(sql):
    con = sqlite3.connect(DB)
    try:
        return list(con.execute(sql))
    finally:
        con.close()


def ensure_patched_esm():
    """`moon build --target js cmd/cli` 每次重新生成的产物都没有 CJS require shim（mizchi/sqlite 的
    JS 桩用 require），而 `python scripts/patch_esm_main.py` **不带参数时补的是已退役的那个入口**
    ——本判据必须点名补自己要用那份，否则第一笔 publish 就让 server 进程死在
    `ReferenceError: require is not defined in ES module scope`（2026-09-29 实测）。"""
    r = subprocess.run(
        [sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), CLI],
        capture_output=True, text=True)
    if r.returncode != 0:
        die("patch_esm_main.py 补产物失败 rc=%s: %s" % (r.returncode, (r.stderr or r.stdout)[-200:]))
    say("ESM shim 已点名补齐", "%s | %s" % (os.path.relpath(CLI, ROOT), (r.stdout or "").strip()[-90:]))


def main():
    if not os.path.isdir(ROOT):
        die("仓库根解析失败")
    os.makedirs(BOX, exist_ok=True)
    # 沙箱每次清场（BUG-117 的教训：否则判据红在"上一轮的旧状态"上）
    for suf in ("", "-wal", "-shm"):
        try:
            os.remove(DB + suf)
        except OSError:
            pass
    ensure_patched_esm()
    with open(CLI, "rb") as f:
        blob = f.read()
    say("被检面（树身份）", os.path.abspath(CLI))
    say("产物 sha256", hashlib.sha256(blob).hexdigest()[:8])
    try:
        head = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        say("HEAD", head or "(非 git 树)")
    except Exception:
        say("HEAD", "(取不到)")
    say("隔离库", DB)

    # ---- 建两条在途任务 + 一条已暂停：全部由进程 A 落库后杀掉进程 ----
    a = Sess("A")
    r1 = a.call("publish_parallel", {"project_dir": ".",
                                     "namespace": NS, "description": "臂A/B：心跳跨进程"})
    t1 = r1.get("task_id", "")
    r2 = a.call("publish_parallel", {"project_dir": ".",
                                     "namespace": NS, "description": "臂D：无心跳超 timeout"})
    t2 = r2.get("task_id", "")
    r3 = a.call("publish_parallel", {"project_dir": ".",
                                     "namespace": NS, "description": "臂C：已暂停不回滚"})
    t3 = r3.get("task_id", "")
    r4 = a.call("publish_parallel", {"project_dir": ".",
                                     "namespace": NS, "description": "臂E：判死但回滚不了要披露"})
    t4 = r4.get("task_id", "")
    for tid in (t1, t2, t3, t4):
        if not tid:
            die("publish_parallel 未回 task_id：%s" % str(r1)[:200])
        a.call("claim", {"task_id": tid, "assignee": "hb-agent"})
    a.call("execute", {"task_id": t2, "deliverable": "d-xproc"})
    hb1 = a.call("heartbeat", {"task_id": t1, "signal": "active"})
    a.call("pause", {"task_id": t3})
    say("A heartbeat 回执", json.dumps(hb1, ensure_ascii=False)[:220])
    arm("A0 heartbeat 自述已落库(persisted)",
        p_hb_persisted(hb1),
        "persisted=%s backend=%s（BUG-119：内存后端不许冒充 durable）" % (hb1.get("persisted"), hb1.get("backend")))
    a.kill()

    rows_before = db_rows("select task_id,last_seen from heartbeats")
    say("A 之后 库中心跳", str(rows_before))

    # ---- 进程 B：全新的内存心跳表，只能靠持久化表判活 ----
    b = Sess("B")
    # timeout_sec=30：两条在途任务此刻都只有几秒大（进程 B 刚起）——
    # 旧码在这里因为 `None => true` 会把它们一律回滚，这一格因此是 BUG-119 的**承重对照**
    h_a = b.call("heal", {"namespace": NS, "timeout_sec": 30})
    arm("A 无心跳+刚活动 -> 不回滚",
        p_no_heartbeat_recent_not_healed(h_a),
        "heal(timeout_sec=30) -> healed=%s（旧码在此必回滚：None=>true 首拍即死）" % h_a.get("healed"))
    say("B heal 回执", json.dumps({k: h_a.get(k) for k in ("count", "scope", "namespace", "backend", "heartbeat_source")}, ensure_ascii=False))
    arm("B1 heal 自述读的是持久化表",
        p_heal_reads_durable(h_a),
        "backend=%s heartbeat_source=%s" % (h_a.get("backend"), h_a.get("heartbeat_source")))

    wt = b.call("watchdog_tick", {"namespace": NS, "timeout_sec": 3600})
    act = (wt.get("detail") or {}).get("active_tasks") or {}
    say("B watchdog active_tasks", str(act))
    arm("B 跨进程心跳可见（last_seen 非空）",
        p_xproc_heartbeat_visible(act, t1),
        "active_tasks=%s（旧码：进程 B 的内存表为空 -> 该格空串或缺项）" % act)
    arm("C 已暂停任务不被回滚",
        p_paused_not_rolled_back(wt, h_a, t3),
        "healed_tasks=%s 且 heal 的 healed=%s" % (wt.get("healed_tasks"), h_a.get("healed")))

    # 臂 D：把 t2 的活动时钟推到 timeout 之外（不改判据、只等真实时钟走完）
    time.sleep(1.2)
    # timeout_sec=0 + 上面 1.2s 的真实等待：整秒粒度下 elapsed 必 >0，判据不靠运气
    h_d = b.call("heal", {"namespace": NS, "timeout_sec": 0})
    arm("D 无心跳+活动时钟超 timeout -> 仍回滚",
        p_over_timeout_still_healed(h_d, (t2, t4)),
        "heal(timeout_sec=1) -> healed=%s（no_signal 语义未被削弱）" % h_d.get("healed"))
    arm("E 判死却回滚不了的条目必须走 skipped（本夹具应全可回滚）",
        p_skipped_disclosed(h_d),
        "heal -> healed=%s skipped=%s（旧实现把 reopen 失败静默吞掉）" % (h_d.get("healed"), h_d.get("skipped")))
    st = dict(db_rows("select id,status from tasks"))
    arm("D2 回滚后状态是可重派的「已领取」",
        p_rolled_back_status_claimable(st, t2), "%s -> %s（别拿状态字面判 heal：reopen 目标态与 claim 同名）" % (t2, st.get(t2)))
    b.kill()

    got = [n for n, _ in RESULTS]
    n_pass = sum(1 for _, ok in RESULTS if ok)
    n_all = len(RESULTS)
    say("基数门（臂集合==声明的 8 格）", "%d/%d 通过" % (n_pass, n_all))
    if not arms_consistent(got, EXPECTED):
        print(
            "E2E-HEARTBEAT-XPROC FAIL: 判据少了/多了格子 %s（应为 %s）——判据坏了，不是产品坏了"
            % (got, EXPECTED), flush=True)
        sys.exit(1)
    if n_pass != n_all:
        print("=== E2E-HEARTBEAT-XPROC: FAIL ===", flush=True)
        sys.exit(1)
    print("=== E2E-HEARTBEAT-XPROC PASS：%d 格全绿（跨进程看护语义已锁） ===" % n_all, flush=True)


def selftest() -> int:
    """BUG-50 / J10：判据必须先证明自己会红。

    每格都是"合成回执喂进纯判定函数 → 要求它给对答案"，**不起真进程、不碰库**。
    格子的清单与 PASS 行的判据范围一律从实现反解（不手写计数）。
    """
    cases = []

    def case(name, got, want):
        cases.append((name, bool(got) is bool(want), "got=%s want=%s" % (got, want)))

    # A0：persisted + backend
    case("A0-ok-sqlite+persisted", p_hb_persisted({"persisted": True, "backend": "sqlite"}), True)
    case("A0-red-内存后端冒充", p_hb_persisted({"persisted": True, "backend": "memory"}), False)
    case("A0-red-未落库", p_hb_persisted({"persisted": False, "backend": "sqlite"}), False)
    # A：无心跳+刚活动不回滚
    case("A-ok-healed为空", p_no_heartbeat_recent_not_healed({"healed": []}), True)
    case("A-red-首拍即死", p_no_heartbeat_recent_not_healed({"healed": ["t1"]}), False)
    # 边界：healed 缺键 ⇒ 视作空（不误红）。这不是"红"，是判据对缺键形状的**容忍**对照。
    case("A-edge-healed缺键视作空", p_no_heartbeat_recent_not_healed({}), True)
    # B1：heal 读持久化表
    case("B1-ok-sqlite-heartbeats", p_heal_reads_durable(
        {"backend": "sqlite", "heartbeat_source": "sqlite-heartbeats"}), True)
    case("B1-red-读内存表", p_heal_reads_durable(
        {"backend": "sqlite", "heartbeat_source": "memory"}), False)
    case("B1-red-backend错", p_heal_reads_durable(
        {"backend": "memory", "heartbeat_source": "sqlite-heartbeats"}), False)
    # B：跨进程可见
    case("B-ok-在表且last_seen非空", p_xproc_heartbeat_visible({"t1": "2026-10-13T00:00:00Z"}, "t1"), True)
    case("B-red-不在表", p_xproc_heartbeat_visible({}, "t1"), False)
    case("B-red-last_seen空串", p_xproc_heartbeat_visible({"t1": ""}, "t1"), False)
    # C：已暂停不被回滚
    case("C-ok-两处都不含", p_paused_not_rolled_back(
        {"healed_tasks": ["x"]}, {"healed": []}, "t3"), True)
    case("C-red-watchdog回滚了", p_paused_not_rolled_back(
        {"healed_tasks": ["t3"]}, {"healed": []}, "t3"), False)
    case("C-red-heal回滚了", p_paused_not_rolled_back(
        {"healed_tasks": []}, {"healed": ["t3"]}, "t3"), False)
    # D：超 timeout 仍回滚
    case("D-ok-两条都回滚", p_over_timeout_still_healed({"healed": ["t2", "t4"]}, ("t2", "t4")), True)
    case("D-red-只回滚一条", p_over_timeout_still_healed({"healed": ["t2"]}, ("t2", "t4")), False)
    case("D-red-一条没回滚", p_over_timeout_still_healed({"healed": []}, ("t2", "t4")), False)
    # E：skipped 披露
    case("E-ok-skipped为空数组", p_skipped_disclosed({"skipped": []}), True)
    case("E-red-skipped缺键(静默吞)", p_skipped_disclosed({"healed": ["t2"]}), False)
    case("E-red-skipped非空(本夹具不该有)", p_skipped_disclosed({"skipped": ["t3"]}), False)
    # D2：回滚后状态
    case("D2-ok-已领取", p_rolled_back_status_claimable({"t2": "已领取"}, "t2"), True)
    case("D2-red-仍执行中", p_rolled_back_status_claimable({"t2": "执行中"}, "t2"), False)
    case("D2-red-缺该任务", p_rolled_back_status_claimable({}, "t2"), False)
    # 集合一致（判据坏了那一档）
    case("ARM-ok-逐字一致", arms_consistent(list(EXPECTED), EXPECTED), True)
    case("ARM-red-少一格", arms_consistent(EXPECTED[:-1], EXPECTED), False)
    case("ARM-red-多一格", arms_consistent(EXPECTED + ["X"], EXPECTED), False)
    case("ARM-red-改名", arms_consistent([x + "!" for x in EXPECTED], EXPECTED), False)

    bad = [(n, why) for n, ok, why in cases if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, why in bad:
            print("  - %s：%s" % (n, why))
        return 1
    print("SELFTEST OK（%d 格：八格各含正/反/边界对照 + 格子集合一致性 4 格；"
          "格子清单从实现反解，非手写）" % len(cases))
    print("  说明：本自检**不起真进程、不碰库**，只考判定函数会不会红；"
          "两条真进程那条链由无参数运行负责。")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    main()
