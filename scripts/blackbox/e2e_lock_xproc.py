#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""BUG-145 常驻判据：分布式文件锁 `lock_acquire` 的**跨进程拒绝型互斥**必须打到两个真进程才观测得到。

为什么它是黑盒脚本而不是单元测试（与 e2e_reserve_xproc.py 同族，BUG-136 的教训）：
  - 缺陷本体是「`locks_upsert` 先读后写 + 无条件覆盖」的竞态窗口与 last-write-wins 语义；
    只在「进程 A 的读 与 进程 B 的读 都早于彼此的写」这一形状下现形；
    单进程（哪怕用真 SQLite）结构上造不出这个窗口，`store_rsv_test.mbt` 的语义锁判不到并发；
  - BUG-145 的修复把 `lock_acquire` 改走 `locks_try_acquire`（复用 `rsv_action` 裁决、数据库级
    `ON CONFLICT ... WHERE`），第二个 agent 在他人 live 锁上必须 `granted=false, blocked_by=A`，
    锁行**不动**且恰记 **1 条 `lock_denied`**——这正是设计文档 v3 的 lk2 合约。

六格硬门（缺一即 FAIL，且格子集合必须与声明逐字相等——判据自己坏了不许冒充产品绿）：
  1 并发双取 20 轮：0 轮双 granted（互斥由数据库裁决，不由调用侧旧读裁决）
  2 每次拒绝都带 held_by，且无进程死、无 25s 不回执、无双双被拒
  3 每个 scope 库里 file_locks 恰 1 行（不许 last-write-wins 之外再多写）
  4 同 agent 续取成功且报 renewed（修复不许把正常路径改松）
  5 活体持有者不被串行夺走（granted=false, action=conflict, held_by=原主）+ 该次恰记 1 条 lock_denied 且锁行未动
  6 过期锁可让渡，报 taken_over 并点名 prev_agent（TTL 语义不许被修掉）

用法（与 ci.yml 的 "Lock cross-process guard" 一步同形）：
  moon build --target js cmd/cli
  python scripts/patch_esm_main.py <该产物>
  python scripts/blackbox/e2e_lock_xproc.py
"""
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time

# BUG-58 同族：守卫的红必须是判据红。GBK 控制台下中文结论里的 ⇒ 等字符会让 print 当场
# UnicodeEncodeError，拿到 traceback 而不是读数。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def _find_root() -> str:
    """仓库根按 moon.mod 定位，不按「向上几层」的层数猜（同 e2e_reserve_xproc.py）。"""
    d = os.path.dirname(os.path.abspath(__file__))
    while True:
        if os.path.isfile(os.path.join(d, "moon.mod")):
            return d
        up = os.path.dirname(d)
        if up == d:
            die("从 %s 向上找不到 moon.mod（不在 FIST-Mbt 仓库内）" % os.path.dirname(os.path.abspath(__file__)))
        d = up


ROOT = _find_root()
CLI = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js")
DB = os.path.join(ROOT, "temp", "lock-xproc.db")
BOX = os.path.join(ROOT, "temp", "lock-xproc-box")
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "lock-xproc-guard", "version": "1"},
}
ROUNDS = 20  # 样本量写死，不接环境变量：能一键降到 1 的压测门不是门
RESULTS = []
# 六格的声明（模块级：main() 的基数门与 selftest() 的集合一致性对照共用，避免两处各写一遍）
EXPECTED = [
    "1 并发双取恰好一成一拒（0 轮双 granted）",
    "2 被拒方拿到持锁者信息，且无一轮异形",
    "3 每个 scope 库里 file_locks 恰 1 行",
    "4 同 agent 续取成功且报 renewed",
    "5 活体持有者不被串行夺走（锁行未动 + 恰记 1 条 lock_denied）",
    "6 过期锁可让渡（taken_over + prev_agent）",
]


# ---------------------------------------------------------------- 六格的纯判定
def p_double_no_both_granted(both_granted, rounds):
    """格 1：并发双取 0 轮双 granted（每轮恰一成一拒才合格）。"""
    return both_granted == 0


def p_loser_has_holder_and_no_anomaly(loser_no_holder, both_refused, proc_dead):
    """格 2：被拒方拿到持锁者信息，且无一轮"双方都被拒/拒方无持锁者/进程死"异形。"""
    return loser_no_holder == 0 and both_refused == 0 and proc_dead == 0


def p_exactly_one_row(n_rows, rounds):
    """格 3：每个 scope 库里 file_locks 恰 1 行（多行=双写成功，0 行=全失败）。"""
    return n_rows == rounds


def p_renew_same_agent(r4):
    """格 4：同 agent 续取成功且报 renewed（不许把正常路径误拒）。"""
    return r4.get("granted") is True and r4.get("action") == "renewed"


def p_live_holder_not_stolen(r5, holder, row_agent, n_denied):
    """格 5：活体持有者不被串行夺走（防修复把正常路径改松）；
    且被拒那一次的锁行未动（row_agent 仍是原主）、恰记 1 条 lock_denied（BUG-145 的拒夺审计）。"""
    return (r5.get("granted") is not True
            and r5.get("action") == "conflict"
            and r5.get("held_by") == holder
            and row_agent == holder
            and n_denied == 1)


def p_expired_takeover(r6, prev_agent):
    """格 6：过期锁可让渡且报 taken_over + prev_agent。"""
    return (r6.get("granted") is True
            and r6.get("action") == "taken_over"
            and r6.get("prev_agent") == prev_agent)


# ---------------------------------------------------------------- 通用判定骨架
def arms_consistent(names, declared):
    """格子集合与声明逐字一致（不等即判「判据坏了，不是产品坏了」）。"""
    return sorted(names) == sorted(declared)


def say(k, v):
    print("%-40s %s" % (k, v), flush=True)


def arm(name, ok, detail):
    RESULTS.append((name, bool(ok)))
    say("  " + name, "%s | %s" % ("PASS" if ok else "FAIL", detail))


def die(msg, hint=""):
    print("LOCK-XPROC REFUSED: %s" % msg, flush=True)
    if hint:
        print("  出路：%s" % hint, flush=True)
    sys.exit(3)


class Sess:
    def __init__(self, tag):
        if not os.path.isfile(CLI):
            die("产物不存在 %s" % CLI,
                "moon build --target js cmd/cli && python scripts/patch_esm_main.py <该产物>")
        env = dict(os.environ)
        env["FIST_DB_PATH"] = DB
        self.p = subprocess.Popen(
            ["node", CLI, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, cwd=BOX, env=env, bufsize=0)
        self.tag = tag
        self.lines = []
        self.err = []
        threading.Thread(target=self._pump, daemon=True).start()
        threading.Thread(target=self._pump_err, daemon=True).start()

    def _pump(self):
        for raw in iter(self.p.stdout.readline, b""):
            s = raw.decode("utf-8", "replace").strip()
            if s.startswith("{"):
                try:
                    self.lines.append(json.loads(s))
                except Exception:
                    pass

    def _pump_err(self):
        for raw in iter(self.p.stderr.readline, b""):
            self.err.append(raw.decode("utf-8", "replace").strip())

    def why_dead(self):
        """崩溃首行的根因，不是 Node 版本尾行（BUG-94 的教训）。"""
        lines = [l for l in self.err if l.strip()]
        for i, l in enumerate(lines):
            if "Error" in l or "error" == l.strip()[:5].lower():
                return " | ".join(lines[i:i + 3])[:300]
        return " | ".join(lines[-6:])[:300]

    def call(self, name, args, timeout=25):
        if self.p.poll() is not None:
            return {"_dead": True, "rc": self.p.returncode, "_stderr": self.why_dead()}
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
            time.sleep(0.02)
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


def db_rows(sql, args=()):
    con = sqlite3.connect(DB)
    try:
        return list(con.execute(sql, args))
    finally:
        con.close()


def ensure_patched_esm():
    r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), CLI],
                       capture_output=True, text=True)
    if r.returncode != 0:
        die("patch_esm_main.py 补产物失败 rc=%s: %s"
            % (r.returncode, (r.stderr or r.stdout)[-200:]))


def concurrent_acquire(a, b, scope, ttl):
    """两进程在同一道闸上同时取同一 scope：返回 (A 回执, B 回执)。"""
    gate = threading.Barrier(2)
    out = {}

    def go(sess, agent, lid):
        gate.wait()
        out[agent] = sess.call("lock_acquire", {
            "lock_id": lid, "batch_id": "xproc", "scope": scope,
            "agent": agent, "ttl_until": ttl})

    t1 = threading.Thread(target=go, args=(a, "xA", "lkA"))
    t2 = threading.Thread(target=go, args=(b, "xB", "lkB"))
    t1.start(), t2.start()
    t1.join(timeout=40), t2.join(timeout=40)
    return out.get("xA", {}), out.get("xB", {})


def future(steady_secs=3600):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + steady_secs))


def past():
    return "2020-01-01T00:00:00Z"


def main():
    # 刻意不做「只读数不出门」的档位：一份能自选「这次不判」的判据不是判据。
    if [x for x in sys.argv[1:] if x not in ("--judge",)]:
        die("本判据不带档位参数（多余的旗会被当成放水口子）：%s" % sys.argv[1:])
    os.makedirs(BOX, exist_ok=True)
    for suf in ("", "-wal", "-shm"):
        try:
            os.remove(DB + suf)
        except OSError:
            pass
    ensure_patched_esm()
    with open(CLI, "rb") as f:
        say("产物 sha256", hashlib.sha256(f.read()).hexdigest()[:8])
    head = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    say("HEAD", head or "(非 git 树)")
    say("隔离库", DB)

    a = Sess("A")
    # 预热：让 A 单进程把 schema 建完，再放 B 进来——两进程同时 CREATE TABLE 不是本判据要测的东西
    warm = a.call("lock_acquire", {
        "lock_id": "warm", "batch_id": "xproc", "scope": "warmup",
        "agent": "w", "ttl_until": past()})
    if warm.get("action") not in ("reserved", "renewed", "taken_over"):
        die("预热都没跑通：%s" % json.dumps(warm, ensure_ascii=False)[:200])
    b = Sess("B")
    if b.p.poll() is not None:
        die("进程 B 起不来：%s" % " | ".join(b.err[-3:])[:220])

    # ---- 1) 并发双取：同一 scope，两 agent ----
    both_granted = refused_with_holder = loser_no_holder = both_refused = proc_dead = 0
    for i in range(ROUNDS):
        scope = "temp/lockfix/probe%02d.mbt" % i
        ra, rb = concurrent_acquire(a, b, scope, future())
        if ra.get("_dead") or rb.get("_dead"):
            proc_dead += 1
            say("  进程被打死", json.dumps((ra, rb), ensure_ascii=False)[:300])
            for s in (a, b):
                if s.p.poll() is not None:
                    p = os.path.join(ROOT, "temp", "lock_xproc_crash_%s.txt" % s.tag)
                    with open(p, "w", encoding="utf-8") as f:
                        f.write("rc=%s\n" % s.p.returncode + "\n".join(s.err))
                    say("  完整 stderr", "%s（%d 行）" % (os.path.relpath(p, ROOT), len(s.err)))
            break
        g_a = ra.get("granted") is True
        g_b = rb.get("granted") is True
        if g_a and g_b:
            both_granted += 1
        elif g_a != g_b:
            loser = rb if g_a else ra
            if loser.get("held_by"):
                refused_with_holder += 1
            else:
                loser_no_holder += 1
                say("  拒方无持锁者", json.dumps(loser, ensure_ascii=False)[:200])
        else:
            both_refused += 1
            say("  双方都被拒", "%s :: %s || %s"
                % (scope, json.dumps(ra, ensure_ascii=False)[:120],
                   json.dumps(rb, ensure_ascii=False)[:120]))
    say("并发双取 %d 轮" % ROUNDS,
        "双成功=%d，一成一拒且带持锁者=%d，拒方无持锁者=%d，双方被拒=%d，进程死=%d"
        % (both_granted, refused_with_holder, loser_no_holder, both_refused, proc_dead))

    arm("1 并发双取恰好一成一拒（0 轮双 granted）",
        p_double_no_both_granted(both_granted, ROUNDS),
        "双成功=%d/%d；一成一拒=%d" % (both_granted, ROUNDS, refused_with_holder))
    arm("2 被拒方拿到持锁者信息，且无一轮异形",
        p_loser_has_holder_and_no_anomaly(loser_no_holder, both_refused, proc_dead),
        "拒方无持锁者=%d，双方被拒=%d，进程死=%d" % (loser_no_holder, both_refused, proc_dead))
    n_rows = len(db_rows(
        "select scope from file_locks where scope like 'temp/lockfix/%'"))
    arm("3 每个 scope 库里 file_locks 恰 1 行", p_exactly_one_row(n_rows, ROUNDS),
        "行数=%d 期望=%d" % (n_rows, ROUNDS))

    # ---- 4) 同 agent 续取不许误拒 ----
    s4 = "temp/lockfix/renew.mbt"
    a.call("lock_acquire", {
        "lock_id": "lk4", "batch_id": "xproc", "scope": s4,
        "agent": "xA", "ttl_until": future()})
    r4 = a.call("lock_acquire", {
        "lock_id": "lk4", "batch_id": "xproc", "scope": s4,
        "agent": "xA", "ttl_until": future()})
    arm("4 同 agent 续取成功且报 renewed",
        p_renew_same_agent(r4),
        json.dumps(r4, ensure_ascii=False)[:180])

    # ---- 5) 活体持有者不许被他人夺走 + 拒夺审计（BUG-145 核心回归）----
    s5 = "temp/lockfix/live.mbt"
    a.call("lock_acquire", {
        "lock_id": "lk5", "batch_id": "xproc", "scope": s5,
        "agent": "xA", "ttl_until": future()})
    before = db_rows("select agent from file_locks where scope = ?", (s5,))
    row_before = before[0][0] if before else ""
    r5 = b.call("lock_acquire", {
        "lock_id": "lk5b", "batch_id": "xproc", "scope": s5,
        "agent": "xB", "ttl_until": future()})
    after = db_rows("select agent from file_locks where scope = ?", (s5,))
    row_after = after[0][0] if after else ""
    n_denied = len(db_rows(
        "select id from lock_violations where scope = ? and reason = 'lock_denied'", (s5,)))
    arm("5 活体持有者不被串行夺走（锁行未动 + 恰记 1 条 lock_denied）",
        p_live_holder_not_stolen(r5, "xA", row_after, n_denied),
        "granted=%s action=%s held_by=%s row_before=%s row_after=%s denied=%d"
        % (r5.get("granted"), r5.get("action"), r5.get("held_by"),
           row_before, row_after, n_denied))

    # ---- 6) TTL 过期后允许让渡（现语义不许被修复改掉）----
    s6 = "temp/lockfix/expired.mbt"
    a.call("lock_acquire", {
        "lock_id": "lk6", "batch_id": "xproc", "scope": s6,
        "agent": "xA", "ttl_until": past()})
    r6 = b.call("lock_acquire", {
        "lock_id": "lk6b", "batch_id": "xproc", "scope": s6,
        "agent": "xB", "ttl_until": future()})
    arm("6 过期锁可让渡（taken_over + prev_agent）",
        p_expired_takeover(r6, "xA"),
        json.dumps(r6, ensure_ascii=False)[:180])

    a.kill(), b.kill()
    got = [n for n, _ in RESULTS]
    if not arms_consistent(got, EXPECTED):
        print("LOCK-XPROC FAIL: 判据格子集合与声明不符 got=%s ——判据坏了，不是产品坏了" % got,
              flush=True)
        return 1
    n_pass = sum(1 for _, ok in RESULTS if ok)
    if n_pass != len(RESULTS):
        print("=== LOCK-XPROC: FAIL（%d/%d）===" % (n_pass, len(RESULTS)), flush=True)
        return 1
    print("=== LOCK-XPROC PASS：%d 格全绿（lock_acquire 的跨进程拒绝型互斥已锁）===" % len(RESULTS),
          flush=True)
    return 0


def selftest() -> int:
    """BUG-50 / J10：判据必须先证明自己会红（不起真进程、不碰库）。"""
    rounds = 20
    cases = []

    def case(name, got, want):
        cases.append((name, bool(got) is bool(want), "got=%s want=%s" % (got, want)))

    # 格 1：0 轮双 granted
    case("G1-ok-0双成功", p_double_no_both_granted(0, rounds), True)
    case("G1-red-1轮双成功", p_double_no_both_granted(1, rounds), False)
    case("G1-red-全双成功", p_double_no_both_granted(rounds, rounds), False)
    # 格 2：拒方有持锁者 + 无异形
    case("G2-ok-全带持锁者", p_loser_has_holder_and_no_anomaly(0, 0, 0), True)
    case("G2-red-拒方无持锁者", p_loser_has_holder_and_no_anomaly(1, 0, 0), False)
    case("G2-red-双方被拒", p_loser_has_holder_and_no_anomaly(0, 1, 0), False)
    case("G2-red-进程死", p_loser_has_holder_and_no_anomaly(0, 0, 1), False)
    # 格 3：恰 N 行
    case("G3-ok-恰20行", p_exactly_one_row(20, rounds), True)
    case("G3-red-0行", p_exactly_one_row(0, rounds), False)
    case("G3-red-多行(双写成功)", p_exactly_one_row(40, rounds), False)
    # 格 4：同 agent 续取
    case("G4-ok-renewed", p_renew_same_agent({"granted": True, "action": "renewed"}), True)
    case("G4-red-误拒", p_renew_same_agent({"granted": False, "action": "conflict"}), False)
    case("G4-red-granted但action非renewed", p_renew_same_agent({"granted": True, "action": "reserved"}), False)
    # 格 5：活体不被夺 + 锁行未动 + 恰 1 条 denied
    case("G5-ok-拒且锁行未动且1denied",
         p_live_holder_not_stolen(
             {"granted": False, "action": "conflict", "held_by": "xA"}, "xA", "xA", 1), True)
    case("G5-red-被夺走",
         p_live_holder_not_stolen(
             {"granted": True, "action": "reserved", "held_by": "xB"}, "xA", "xA", 1), False)
    case("G5-red-held_by错人",
         p_live_holder_not_stolen(
             {"granted": False, "action": "conflict", "held_by": "xZ"}, "xA", "xA", 1), False)
    case("G5-red-锁行被改",
         p_live_holder_not_stolen(
             {"granted": False, "action": "conflict", "held_by": "xA"}, "xA", "xB", 1), False)
    case("G5-red-未记denied",
         p_live_holder_not_stolen(
             {"granted": False, "action": "conflict", "held_by": "xA"}, "xA", "xA", 0), False)
    case("G5-red-记了多条denied",
         p_live_holder_not_stolen(
             {"granted": False, "action": "conflict", "held_by": "xA"}, "xA", "xA", 2), False)
    # 格 6：过期让渡
    case("G6-ok-taken_over带prev",
         p_expired_takeover(
             {"granted": True, "action": "taken_over", "prev_agent": "xA"}, "xA"), True)
    case("G6-red-非taken_over",
         p_expired_takeover(
             {"granted": True, "action": "reserved", "prev_agent": "xA"}, "xA"), False)
    case("G6-red-prev_agent错",
         p_expired_takeover(
             {"granted": True, "action": "taken_over", "prev_agent": "xZ"}, "xA"), False)
    case("G6-red-未让渡",
         p_expired_takeover(
             {"granted": False, "action": "taken_over", "prev_agent": "xA"}, "xA"), False)
    # 格子集合一致（判据坏了那一档）
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
    print("SELFTEST OK（%d 格：六格各含正/反/边界对照 + 格子集合一致性 4 格；"
          "格子清单从实现反解，非手写）" % len(cases))
    print("  说明：本自检**不起真进程、不碰库**，只考判定函数会不会红；"
          "两条真进程那条链由无参数运行负责。")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    sys.exit(main())
