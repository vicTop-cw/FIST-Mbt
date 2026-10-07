#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""BUG-136 常驻判据：作用域预订的**跨进程互斥**必须打到两个真进程才观测得到。

为什么它是黑盒脚本而不是单元测试：
  - 缺陷本体是「先读后写」的竞态窗口，只在「进程 A 的读 与 进程 B 的读 都早于彼此的写」
    这一形状下现形；单进程（哪怕用真 SQLite）结构上造不出这个窗口；
  - `src/store/store_rsv_test.mbt` 的两后端一致性锁判的是**语义**，判不到**并发**；
  - 另一半崩因（`Error: database is locked` 打死 server）同理：只有一个连接时永不撞锁。

六格硬门（缺一即 FAIL，且格子集合必须与声明逐字相等——判据自己坏了不许冒充产品绿）：
  1 并发双绑 20 轮：0 轮双成功（互斥由数据库裁决，不由调用侧旧读裁决）
  2 每次拒绝都带 held_by，且无进程死、无 25s 不回执、无双双被拒
  3 每个 scope 库里恰 1 行（不许 last-write-wins 之外再多写）
  4 同 agent 续期成功且报 renewed（修复不许把正常路径改松）
  5 活体持有者不被串行夺走（同上，反向对照）
  6 过期绑定可让渡，报 taken_over 并点名 prev_agent（TTL 语义不许被修掉）

用法（与 ci.yml 的 "Reserve cross-process guard" 一步同形）：
  moon build --target js cmd/cli
  python scripts/patch_esm_main.py <该产物>
  python scripts/blackbox/e2e_reserve_xproc.py
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
    """仓库根按 moon.mod 定位，不按「向上几层」的层数猜——
    这份脚本从 temp/ 跑和将来从 scripts/blackbox/ 跑，深度差一层，写死层数会一路指向 E:\\IDEProjects\\AI。"""
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
DB = os.path.join(ROOT, "temp", "rsv-xproc.db")
BOX = os.path.join(ROOT, "temp", "rsv-xproc-box")
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "rsv-xproc-guard", "version": "1"},
}
ROUNDS = 20  # 样本量写死，不接环境变量：能一键降到 1 的压测门不是门
RESULTS = []


def say(k, v):
    print("%-32s %s" % (k, v), flush=True)


def arm(name, ok, detail):
    RESULTS.append((name, bool(ok)))
    say("  " + name, "%s | %s" % ("PASS" if ok else "FAIL", detail))


def die(msg, hint=""):
    print("RSV-XPROC REFUSED: %s" % msg, flush=True)
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
        """崩溃首行的根因，不是 Node 版本尾行——`Node.js v25.2.1` 只是退出横幅，
        真正的话头在它上面几行（BUG-94 的教训：崩因写在 stderr 中段，不在末尾）。"""
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


def db_rows(sql):
    con = sqlite3.connect(DB)
    try:
        return list(con.execute(sql))
    finally:
        con.close()


def ensure_patched_esm():
    r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "patch_esm_main.py"), CLI],
                       capture_output=True, text=True)
    if r.returncode != 0:
        die("patch_esm_main.py 补产物失败 rc=%s: %s"
            % (r.returncode, (r.stderr or r.stdout)[-200:]))


def concurrent_bind(a, b, scope, ttl):
    """两进程在同一道闸上同时下手：返回 (A 回执, B 回执)。"""
    gate = threading.Barrier(2)
    out = {}

    def go(sess, agent):
        gate.wait()
        out[agent] = sess.call("reserve_scope", {
            "scope": scope, "agent": agent, "ttl_until": ttl})

    t1 = threading.Thread(target=go, args=(a, "xA"))
    t2 = threading.Thread(target=go, args=(b, "xB"))
    t1.start(), t2.start()
    t1.join(timeout=40), t2.join(timeout=40)
    return out.get("xA", {}), out.get("xB", {})


def future(steady_secs=3600):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + steady_secs))


def past():
    return "2020-01-01T00:00:00Z"


def main():
    # 刻意不做 --mode=measure 那种「只读数不出门」的档位：一份能自选「这次不判」的判据
    # 不是判据。修前的读数由台账逐字引用运行日志，不靠脚本放水。
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
    warm = a.call("reserve_scope", {"scope": "warmup", "agent": "w", "ttl_until": past()})
    if warm.get("action") not in ("reserved", "renewed"):
        die("预热都没跑通：%s" % json.dumps(warm, ensure_ascii=False)[:200])
    b = Sess("B")
    if b.p.poll() is not None:
        die("进程 B 起不来：%s" % " | ".join(b.err[-3:])[:220])

    # ---- 1) 并发双绑：同一 scope，两 agent ----
    both_ok = refused_with_holder = loser_no_holder = both_refused = proc_dead = 0
    for i in range(ROUNDS):
        scope = "temp/f094/probe%02d.mbt" % i
        ra, rb = concurrent_bind(a, b, scope, future())
        if ra.get("_dead") or rb.get("_dead"):
            proc_dead += 1
            say("  进程被打死", json.dumps((ra, rb), ensure_ascii=False)[:300])
            for s in (a, b):
                if s.p.poll() is not None:
                    p = os.path.join(ROOT, "temp", "rsv_xproc_crash_%s.txt" % s.tag)
                    with open(p, "w", encoding="utf-8") as f:
                        f.write("rc=%s\n" % s.p.returncode + "\n".join(s.err))
                    say("  完整 stderr", "%s（%d 行）" % (os.path.relpath(p, ROOT), len(s.err)))
            break
        ok_a = ra.get("reserved") is True
        ok_b = rb.get("reserved") is True
        if ok_a and ok_b:
            both_ok += 1
        elif ok_a != ok_b:
            loser = rb if ok_a else ra
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
    say("并发双绑 %d 轮" % ROUNDS,
        "双成功=%d，一成一拒且带持锁者=%d，拒方无持锁者=%d，双方被拒=%d，进程死=%d"
        % (both_ok, refused_with_holder, loser_no_holder, both_refused, proc_dead))

    arm("1 并发双绑恰好一成一拒（0 轮双成功）",
        both_ok == 0, "双成功=%d/%d；一成一拒=%d" % (both_ok, ROUNDS, refused_with_holder))
    arm("2 被拒方拿到持锁者信息，且无一轮异形",
        loser_no_holder == 0 and both_refused == 0 and proc_dead == 0,
        "拒方无持锁者=%d，双方被拒=%d，进程死=%d" % (loser_no_holder, both_refused, proc_dead))
    n_rows = len(db_rows("select scope from reservations where scope like 'temp/f094/%'"))
    arm("3 每个 scope 库里恰 1 行", n_rows == ROUNDS, "行数=%d 期望=%d" % (n_rows, ROUNDS))

    # ---- 4) 同 agent 续期不许误拒 ----
    s4 = "temp/f094/renew.mbt"
    a.call("reserve_scope", {"scope": s4, "agent": "xA", "ttl_until": future()})
    r4 = a.call("reserve_scope", {"scope": s4, "agent": "xA", "ttl_until": future()})
    arm("4 同 agent 续期成功且报 renewed",
        r4.get("reserved") is True and r4.get("action") == "renewed",
        json.dumps(r4, ensure_ascii=False)[:180])

    # ---- 5) 活体持有者不许被他人夺走（这一格在现状码上是绿的，防修复把它改松）----
    s5 = "temp/f094/live.mbt"
    a.call("reserve_scope", {"scope": s5, "agent": "xA", "ttl_until": future()})
    r5 = b.call("reserve_scope", {"scope": s5, "agent": "xB", "ttl_until": future()})
    arm("5 活体持有者不被串行夺走",
        r5.get("reserved") is not True and r5.get("held_by") == "xA",
        json.dumps(r5, ensure_ascii=False)[:180])

    # ---- 6) TTL 过期后允许让渡（现语义不许被修复改掉）----
    s6 = "temp/f094/expired.mbt"
    a.call("reserve_scope", {"scope": s6, "agent": "xA", "ttl_until": past()})
    r6 = b.call("reserve_scope", {"scope": s6, "agent": "xB", "ttl_until": future()})
    arm("6 过期绑定可让渡（taken_over + prev_agent）",
        r6.get("reserved") is True and r6.get("action") == "taken_over"
        and r6.get("prev_agent") == "xA",
        json.dumps(r6, ensure_ascii=False)[:180])

    a.kill(), b.kill()
    EXPECTED = [
        "1 并发双绑恰好一成一拒（0 轮双成功）",
        "2 被拒方拿到持锁者信息，且无一轮异形",
        "3 每个 scope 库里恰 1 行",
        "4 同 agent 续期成功且报 renewed",
        "5 活体持有者不被串行夺走",
        "6 过期绑定可让渡（taken_over + prev_agent）",
    ]
    got = [n for n, _ in RESULTS]
    if sorted(got) != sorted(EXPECTED):
        print("RSV-XPROC FAIL: 判据格子集合与声明不符 got=%s ——判据坏了，不是产品坏了" % got,
              flush=True)
        return 1
    n_pass = sum(1 for _, ok in RESULTS if ok)
    if n_pass != len(RESULTS):
        print("=== RSV-XPROC: FAIL（%d/%d）===" % (n_pass, len(RESULTS)), flush=True)
        return 1
    print("=== RSV-XPROC PASS：%d 格全绿（预订的跨进程互斥已锁）===" % len(RESULTS), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
