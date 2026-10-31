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

⚠️ 格 1~3 用未登记的 `temp/f094/*`（要的就是并发裁决本身，与角色无关）；
   格 4~6 用**权限表里登记的 scope**（`moon.mod`，allowed_roles=["HumanSteward"]，
   身份取 `human_steward` / `human` 两个不同字符串都推断成 HumanSteward）——
   因为未登记分支会把成功获取的 action 一律标成 `unregistered`（`engine_rsv.mbt:826-837`，
   前导词逐字不变是刻意的，上游有精确相等断言），`renewed`/`taken_over` 在那条分支上根本不出现。
   锚点格 `p_anchor_first_bind` 钉住这件事：锚点一旦退化 ⇒ **rc=3 自拒**（尺子坏了），不报「产品没续期」。

用法（与 ci.yml 的 "Reserve cross-process guard" 一步同形）：
  moon build --target js cmd/cli
  python scripts/patch_esm_main.py <该产物>
  python scripts/blackbox/e2e_reserve_xproc.py

退出码（契约，勿改档；三档互斥，绝不互相冒用）：
  0 = 六格全 PASS 且格子集合与声明逐字相等
  1 = 任一格 FAIL —— **被测对象**的结论
  3 = 探针不可用（产物缺失 / 进程 B 起不来 / 预热没跑通 / 回执读不到字段）
      ⇒ 「接入没通」不冒充「缺陷在场」；BUG-520 正是预热被判成 rc=3 的那一条。
自检面（`--selftest`）另给 0/1：不起真进程、不碰库，只考纯判定函数会不会红。
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
    这份脚本从 temp/ 跑和将来从 scripts/blackbox/ 跑，深度差一层，写死层数会一路指向 E:\\proj\\AI。"""
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
# 六格的声明（模块级：main() 的基数门与 selftest() 的集合一致性对照共用，避免两处各写一遍）
EXPECTED = [
    "1 并发双绑恰好一成一拒（0 轮双成功）",
    "2 被拒方拿到持锁者信息，且无一轮异形",
    "3 每个 scope 库里恰 1 行",
    "4 同 agent 续期成功且报 renewed",
    "5 活体持有者不被串行夺走",
    "6 过期绑定可让渡（taken_over + prev_agent）",
]


# ---------------------------------------------------------------- 六格的纯判定
# 抽成纯函数的理由（BUG-50 / J10：「判据必须先证明自己会红」）：判定若埋在 main() 的实时
# 回执里，`--selftest` 就只能靠"起两个真进程跑 20 轮"来验 —— 真进程一起不来判据自己先崩，
# 自检就退化成"链通不通"，**验不出"某支判据会不会红"**。纯函数让每格都能喂合成回执。
def action_base(action):
    """`action` 的合法形状是 `<base>[+role_inferred][+agent_self_reported][+challenge_verified]`
    （真源 `src/engine/engine_rsv.mbt` 的 BUG-430 那一段注释）。
    判 base，**不许判整串**（BUG-520：本探针原先用整串相等，产品把 provenance 后缀加上之后
    预热与格 4/6 集体误判，CI 直接 rc=3「探针不可用」）。
    """
    return str(action or "").split("+")[0]


def p_warmup_ok(rsv):
    """预热格（夹具面）：A 单进程要真拿到一次预订，schema 才算建完。
     outcome 只看 `reserved` 布尔——`action=unregistered+…` 带后缀时同样算拿到（advisory 不参与裁决）。
    """
    return rsv.get("reserved") is True


def p_anchor_first_bind(rsv):
    """锚点格（尺子自己的前置）：登记的 scope 首绑必须报 base=`reserved`。
    报出 `unregistered` ⇒ 该 scope 已不在权限表里 ⇒ 格 4/5/6 的字面锁集体失效，
    那是**尺子坏了**（rc=3 自拒），不是「产品没续期/没让渡」（判例-32）。
    """
    return rsv.get("reserved") is True and action_base(rsv.get("action")) == "reserved"


def p_rounds_no_double_success(both_ok, rounds):
    """格 1：并发双绑 0 轮双成功（每轮恰一成一拒才合格）。"""
    return both_ok == 0


def p_loser_has_holder_and_no_anomaly(loser_no_holder, both_refused, proc_dead):
    """格 2：被拒方拿到持锁者信息，且无一轮"双方都被拒/拒方无持锁者/进程死"异形。"""
    return loser_no_holder == 0 and both_refused == 0 and proc_dead == 0


def p_exactly_one_row(n_rows, rounds):
    """格 3：每个 scope 库里恰 1 行（多行=双写成功，0 行=全失败）。"""
    return n_rows == rounds


def p_renew_same_agent(r4):
    """格 4：同 agent 续期成功且报 renewed（不许把正常路径误拒）。判 base，见 `action_base`。"""
    return r4.get("reserved") is True and action_base(r4.get("action")) == "renewed"


def p_live_holder_not_stolen(r5, holder):
    """格 5：活体持有者不被串行夺走（防修复把正常路径改松）。"""
    return r5.get("reserved") is not True and r5.get("held_by") == holder


def p_expired_takeover(r6, prev_agent):
    """格 6：过期绑定可让渡且报 taken_over + prev_agent。判 base，见 `action_base`。"""
    return (r6.get("reserved") is True
            and action_base(r6.get("action")) == "taken_over"
            and r6.get("prev_agent") == prev_agent)


def arms_consistent(names, declared):
    """格子集合与声明逐字一致（不等即判「判据坏了，不是产品坏了」）。"""
    return sorted(names) == sorted(declared)


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



def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


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
    if not p_warmup_ok(warm):
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
        p_rounds_no_double_success(both_ok, ROUNDS),
        "双成功=%d/%d；一成一拒=%d" % (both_ok, ROUNDS, refused_with_holder))
    arm("2 被拒方拿到持锁者信息，且无一轮异形",
        p_loser_has_holder_and_no_anomaly(loser_no_holder, both_refused, proc_dead),
        "拒方无持锁者=%d，双方被拒=%d，进程死=%d" % (loser_no_holder, both_refused, proc_dead))
    n_rows = len(db_rows("select scope from reservations where scope like 'temp/f094/%'"))
    arm("3 每个 scope 库里恰 1 行", p_exactly_one_row(n_rows, ROUNDS), "行数=%d 期望=%d" % (n_rows, ROUNDS))

    # ---- 4~6 打在**权限表里登记过的 scope** 上（BUG-521）----
    # 未登记的 scope 走 advisory 分支：产品把「成功获取」的 action 一律标成 `unregistered`
    # （`engine_rsv.mbt:826-837` 明写：前导词逐字不变，因为上游有精确相等断言）⇒
    # `renewed` / `taken_over` 这两个字面在 unregistered 分支上**根本不出现**。
    # 这三格要锁的正是「续期 / 夺回」的自述面 ⇒ 必须打在 Allowed 分支上：
    # `moon.mod` 的 allowed_roles=["HumanSteward"]，而 `human_steward` 与 `human` 是两个**不同字符串**
    # 却都推断成 HumanSteward（2026-10-31 用 release 产物实测：首绑 `reserved+…`、续期 `renewed+…`、
    # 过期让渡 `taken_over+…` 且 `prev_agent` 点名）。
    REG_SCOPE, HOLDER, CHALLENGER = "moon.mod", "human_steward", "human"
    # 反脱锚格（判例-32：尺子的腐烂与对象的陈旧是两种结论）：锚点 scope 一旦不再被权限表命中，
    # 这三格会集体退化成 `unregistered` —— 那是**尺子坏了**，必须 rc=3 自拒，不许报「产品没续期」。
    anchor = a.call("reserve_scope", {"scope": REG_SCOPE, "agent": HOLDER, "ttl_until": future()})
    if not p_anchor_first_bind(anchor):
        die("锚点 scope 失效：%s 的 action=%s（期望 base=reserved） ⇒ 权限表里这一条不在了"
            % (REG_SCOPE, anchor.get("action")),
            "换用 `src/engine/engine_scope_perm.mbt` 的 scope_permissions 里仍存在的 scope，"
            "并把本探针的 REG_SCOPE 同批改指——**别改判定式去迁就**（那是把尺子锯短）")
    r4 = a.call("reserve_scope", {"scope": REG_SCOPE, "agent": HOLDER, "ttl_until": future()})
    arm("4 同 agent 续期成功且报 renewed",
        p_renew_same_agent(r4),
        json.dumps(r4, ensure_ascii=False)[:180])

    # ---- 5) 活体持有者不许被他人夺走（这一格在现状码上是绿的，防修复把它改松）----
    r5 = b.call("reserve_scope", {"scope": REG_SCOPE, "agent": CHALLENGER, "ttl_until": future()})
    arm("5 活体持有者不被串行夺走",
        p_live_holder_not_stolen(r5, HOLDER),
        json.dumps(r5, ensure_ascii=False)[:180])

    # ---- 6) TTL 过期后允许让渡（现语义不许被修复改掉）----
    a.call("reserve_scope", {"scope": REG_SCOPE, "agent": HOLDER, "ttl_until": past()})
    r6 = b.call("reserve_scope", {"scope": REG_SCOPE, "agent": CHALLENGER, "ttl_until": future()})
    arm("6 过期绑定可让渡（taken_over + prev_agent）",
        p_expired_takeover(r6, HOLDER),
        json.dumps(r6, ensure_ascii=False)[:180])

    a.kill(), b.kill()
    got = [n for n, _ in RESULTS]
    if not arms_consistent(got, EXPECTED):
        print("RSV-XPROC FAIL: 判据格子集合与声明不符 got=%s ——判据坏了，不是产品坏了" % got,
              flush=True)
        return 1
    n_pass = sum(1 for _, ok in RESULTS if ok)
    if n_pass != len(RESULTS):
        print("=== RSV-XPROC: FAIL（%d/%d）===" % (n_pass, len(RESULTS)), flush=True)
        return 1
    print("=== RSV-XPROC PASS：%d 格全绿（预订的跨进程互斥已锁）===" % len(RESULTS), flush=True)
    return 0


def selftest() -> int:
    """BUG-50 / J10：判据必须先证明自己会红。

    每格都是"合成回执喂进纯判定函数 → 要求它给对答案"，**不起真进程、不碰库/库文件**。
    格子的清单与 PASS 行的判据范围一律从实现反解（不手写计数）。
    """
    _entry_probe()
    rounds = 20
    cases = []

    def case(name, got, want):
        cases.append((name, bool(got) is bool(want), "got=%s want=%s" % (got, want)))

    # 格 1：0 轮双成功
    case("G1-ok-0双成功", p_rounds_no_double_success(0, rounds), True)
    case("G1-red-1轮双成功", p_rounds_no_double_success(1, rounds), False)
    case("G1-red-全双成功", p_rounds_no_double_success(rounds, rounds), False)
    # 格 2：拒方有持锁者 + 无异形
    case("G2-ok-全带持锁者", p_loser_has_holder_and_no_anomaly(0, 0, 0), True)
    case("G2-red-拒方无持锁者", p_loser_has_holder_and_no_anomaly(1, 0, 0), False)
    case("G2-red-双方被拒", p_loser_has_holder_and_no_anomaly(0, 1, 0), False)
    case("G2-red-进程死", p_loser_has_holder_and_no_anomaly(0, 0, 1), False)
    # 格 3：恰 N 行
    case("G3-ok-恰20行", p_exactly_one_row(20, rounds), True)
    case("G3-red-0行", p_exactly_one_row(0, rounds), False)
    case("G3-red-多行(双写成功)", p_exactly_one_row(40, rounds), False)
    # 格 4：同 agent 续期
    case("G4-ok-renewed", p_renew_same_agent({"reserved": True, "action": "renewed"}), True)
    case("G4-red-误拒", p_renew_same_agent({"reserved": False, "action": "conflict"}), False)
    case("G4-red-reserved真但action非renewed", p_renew_same_agent({"reserved": True, "action": "reserved"}), False)
    # 格 5：活体不被夺
    case("G5-ok-held_by他方且未reserved", p_live_holder_not_stolen({"reserved": False, "held_by": "xA"}, "xA"), True)
    case("G5-red-被夺走", p_live_holder_not_stolen({"reserved": True, "held_by": "xB"}, "xA"), False)
    case("G5-red-held_by错人", p_live_holder_not_stolen({"reserved": False, "held_by": "xZ"}, "xA"), False)
    # 格 6：过期让渡
    case("G6-ok-taken_over带prev", p_expired_takeover(
        {"reserved": True, "action": "taken_over", "prev_agent": "xA"}, "xA"), True)
    case("G6-red-非taken_over", p_expired_takeover(
        {"reserved": True, "action": "reserved", "prev_agent": "xA"}, "xA"), False)
    case("G6-red-prev_agent错", p_expired_takeover(
        {"reserved": True, "action": "taken_over", "prev_agent": "xZ"}, "xA"), False)
    case("G6-red-未让渡", p_expired_takeover(
        {"reserved": False, "action": "taken_over", "prev_agent": "xA"}, "xA"), False)
    # ---- BUG-520：预热与 action 的**复合形状**（真源 `engine_rsv.mbt`：`<base>[+role_inferred]`
    #      `[+agent_self_reported][+challenge_verified]`）。旧判据拿整串相等 ⇒ 产品加上后缀后
    #      预热先自拒（rc=3），格 4/6 也在同一条路上——这三格是这把尺子的锁。
    case("WARM-ok-reserved真+带后缀action",
         p_warmup_ok({"reserved": True,
                      "action": "unregistered+role_inferred+agent_self_reported"}), True)
    case("WARM-red-conflict", p_warmup_ok({"reserved": False, "action": "conflict"}), False)
    case("WARM-red-回执缺 reserved 字段（不许把缺字段当成功）",
         p_warmup_ok({"action": "reserved"}), False)
    case("ABASE-ok-拆掉 provenance 后缀",
         action_base("renewed+role_inferred+agent_self_reported") == "renewed", True)
    case("ABASE-ok-旧整串形状照样认", action_base("taken_over") == "taken_over", True)
    case("ABASE-red-空串不得等于任何 base", action_base("") == "reserved", False)
    case("G4-ok-renewed带后缀",
         p_renew_same_agent({"reserved": True, "action": "renewed+agent_self_reported"}), True)
    # 锚点格（BUG-521）：登记的 scope 首绑必须是 reserved；退化成 unregistered ⇒ 尺子坏了（rc=3 自拒）
    case("ANCHOR-ok-登记scope首绑reserved带后缀",
         p_anchor_first_bind({"reserved": True,
                              "action": "reserved+role_inferred+agent_self_reported"}), True)
    case("ANCHOR-red-退化成unregistered（权限表不再命中）",
         p_anchor_first_bind({"reserved": True,
                              "action": "unregistered+role_inferred+agent_self_reported"}), False)
    case("ANCHOR-red-conflict不算锚点通过",
         p_anchor_first_bind({"reserved": False, "action": "conflict"}), False)
    case("G6-ok-taken_over带后缀",
         p_expired_takeover({"reserved": True, "action": "taken_over+role_inferred",
                             "prev_agent": "xA"}, "xA"), True)
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
