#!/usr/bin/env python3
"""check_known_red_until.py — `known-red` 的**到期日**机核（Lane DV）

## 为什么有这个判据

`kind="known-red"` 允许一个「红」被登记为「已知」。
**但它原本没有任何到期机制** —— 于是：

1. **判据自己把债还了，却没人销账**（R46 实测：`check_warning_ledger` 写完当轮就抓出
   台账真问题、推动了 2 处补登记、自己变绿了，但 `known-red` 登记还留着
   ⇒ `check_battery_count_doc` FAIL）。
2. **`known-red` 把「判据坏了」和「被判对象坏了」混成一档** ——
   下一个人看到红，不知道该修哪边。

**⇒ 一个永远红着的判据，三个月后会变成「大家都知道它红，但没人记得为什么」。
那比没有判据更糟 —— 因为它训练人忽略红色。**

## 三条规则（逐条机核）

| # | 规则 | 违反时 |
|---|---|---|
| **R1** | 每个 `known-red` **必须有 `until`** | **FAIL**，逐条点名「无到期日」 |
| **R2** | `until` 的条件**已满足 ⇒ 该销账了** | **FAIL**，说「已到期待销账」 |
| **R3** | `until.kind == "manual"` 过了 `deadline` | **FAIL**，说「超期」 |

另：`blame` 必须是 `judge`/`subject`/`unknown` 之一（回答「该修哪边」）；
`blame == "unknown"` 不算违规，但会在输出里**点名**，提醒有朝一日判定。

## `until` 三类型（定义在 `run_guards.py` 的 `expected()` docstring）

| kind | 机核方式 | 必填 |
|---|---|---|
| `rc` | **真跑该判据**，rc == `value` ⇒ 已满足 | `value` |
| `contains` | 读 `file`，出现 `text` ⇒ 已满足 | `file` + `text` |
| `manual` | **不机核条件**，只查 `deadline` | `by` + `deadline` |

⚠️ **`manual` 是必要的逃生门**（有些债真的只能人判），
但**没有 `deadline` 的 manual 就等于没有 until** ⇒ R1 直接拒。

## rc 契约
- `0` = 所有 known-red 都有有效且未到期的 `until`
- `1` = 有违规（无 until / 条件已满足 / manual 超期 / blame 非法）
- `2` = 判据无法自证（读不到 `run_guards.py` / 解析不出 CASES）
- `4` = 尺子坏了

## 用法
    python scripts/check_known_red_until.py             # 真跑（会用子进程核 rc 类条件）
    python scripts/check_known_red_until.py --no-run    # 不真跑判据（只查静态三规则）
    python scripts/check_known_red_until.py --selftest  # 自证（含变异对照）
"""

from __future__ import annotations

import datetime
import io
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARDS = os.path.join(ROOT, "scripts", "run_guards.py")

RC_OK, RC_VIOLATION, RC_CANNOT, RC_BROKEN = 0, 1, 2, 4
BLAMES = {"judge", "subject", "unknown"}


# ══════════════════════════════════════════════════════════════════════
# 取 CASES：在本进程内 import run_guards 并读它的 CASES
# ══════════════════════════════════════════════════════════════════════

def load_cases():
    """把 `scripts/run_guards.py` 当模块加载，返回它的 `CASES` 列表。

    ⚠️ **不解析源码文本**：`AST`/正则都得跟着代码改，而 `CASES` 是运行时真源。
    代价：`run_guards` 的模块级副作用会执行（它只建列表，不跑测试）。
    """
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    import importlib.util  # noqa: PLC0415

    spec = importlib.util.spec_from_file_location("_rg_for_until", GUARDS)
    if spec is None or spec.loader is None:
        raise RuntimeError("无法加载 run_guards.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    cases = getattr(mod, "CASES", None)
    if cases is None:
        raise RuntimeError("run_guards.py 没有 CASES")
    return mod, cases


def known_reds(cases) -> list:
    return [c for c in cases if c.get("kind") == "known-red"]


# ══════════════════════════════════════════════════════════════════════
# 三条规则的判定
# ══════════════════════════════════════════════════════════════════════

def check_until_shape(u) -> str:
    """返回违规理由；空串表示形状合法。"""
    if not isinstance(u, dict):
        return "无 until（免检牌没有到期日）"
    k = u.get("kind")
    if k == "rc":
        if not isinstance(u.get("value"), int):
            return "until.kind=rc 但缺整数 value"
        return ""
    if k == "contains":
        if not u.get("file") or not isinstance(u.get("text"), str) or not u["text"]:
            return "until.kind=contains 但缺 file/text"
        return ""
    if k == "manual":
        if not u.get("by"):
            return "until.kind=manual 但缺 by"
        if not u.get("deadline"):
            # ⚠️ 没有 deadline 的 manual 等于没有 until
            return "until.kind=manual 但缺 deadline（= 没有到期日）"
        return ""
    return f"until.kind 非法: {k!r}（只允许 rc / contains / manual）"


def until_satisfied(u, mod, run: bool) -> tuple[bool, str]:
    """条件是否已满足。返回 (satisfied, 实测读数说明)。"""
    if not isinstance(u, dict):
        return False, ""
    k = u.get("kind")
    if k == "rc":
        if not run:
            return False, "（--no-run：未真跑）"
        case = None
        for c in mod.CASES:
            if c.get("script") == u.get("script") and c.get("argv") == u.get("argv", []):
                case = c
                break
        # `rc` 类条件默认核「该判据自身」：用 case 里的 script+argv
        script = u.get("script")
        argv = u.get("argv", [])
        if script is None:
            return False, "（until 未给 script，无法机核 rc 条件）"
        cmd = [sys.executable, os.path.join(ROOT, "scripts", script)] + list(argv)
        try:
            p = subprocess.run(cmd, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", cwd=ROOT, timeout=600)
            got = p.returncode
        except Exception as e:  # noqa: BLE001
            return False, f"（跑判据异常：{e}）"
        return got == u.get("value"), f"rc={got}（期望销账值 {u.get('value')}）"
    if k == "contains":
        fp = os.path.join(ROOT, u.get("file", ""))
        if not os.path.isfile(fp):
            return False, f"（文件不存在：{u.get('file')}）"
        txt = io.open(fp, encoding="utf-8", errors="replace").read()
        hit = u.get("text") in txt
        return hit, f"{'出现' if hit else '未出现'} {u.get('text')!r}"
    if k == "manual":
        dl = u.get("deadline", "")
        try:
            d = datetime.date.fromisoformat(dl)
        except Exception:  # noqa: BLE001
            return False, f"（deadline 不可解析：{dl!r}）"
        today = datetime.date.today()
        return False, f"deadline={dl}（{"已过期" if today > d else f"还剩 {(d - today).days} 天"}）"
    return False, ""


def judge(cases, mod=None, run=True, today=None) -> tuple[int, dict]:
    reds = known_reds(cases)
    violations = []
    notes = []
    for c in reds:
        nm = c.get("name", "?")
        u = c.get("until")
        why_bad = check_until_shape(u)
        if why_bad:
            violations.append(("无有效到期日", nm, why_bad))
            continue
        # blame 合法性
        b = c.get("blame", "unknown")
        if b not in BLAMES:
            violations.append(("blame 非法", nm, f"{b!r} 不在 {sorted(BLAMES)}"))
        elif b == "unknown":
            notes.append(f"  · {nm} —— blame=unknown（未判定该修哪边）")
        # R3：manual 超期
        if u.get("kind") == "manual":
            try:
                d = datetime.date.fromisoformat(u["deadline"])
            except Exception:  # noqa: BLE001
                violations.append(("deadline 不可解析", nm, u.get("deadline", "")))
                continue
            ref = today or datetime.date.today()
            if ref > d:
                violations.append(
                    ("manual 超期", nm,
                     f"deadline={u['deadline']} 已过 ⇒ 必须重新裁决（不许无限期红着）")
                )
            else:
                notes.append(f"  · {nm} —— manual，deadline={u['deadline']}（剩 {(d - ref).days} 天）")
            continue
        # R2：条件已满足 ⇒ 该销账
        sat, reading = until_satisfied(u, mod, run)
        if sat:
            # ★ **按 blame 分档**（统帅 R46 要求的）：说清「该改哪边」
            if b == "subject":
                violations.append(
                    ("已到期待销账", nm,
                     f"until 条件已满足（{reading}）⇒ **被检对象已修好**，"
                     f"把 `expected(...)` 转回 `case(...)`")
                )
            elif b == "judge":
                violations.append(
                    ("已到期待销账", nm,
                     f"until 条件已满足（{reading}）⇒ **判据已修好**，"
                     f"把 `expected(...)` 转回 `case(...)`")
                )
            else:
                # ⚠️ `blame=="unknown"` **不 FAIL 只 WARN**：
                #    说不清是谁坏的时候强行 FAIL 会逼人乱填 blame ——
                #    那会让 blame 变成新的假信息源。
                notes.append(
                    f"  · ⚠️ {nm} —— until 条件已满足（{reading}）但 blame=unknown "
                    f"⇒ **请人工确认该转 case(...) 还是重新定 blame**"
                )
        else:
            notes.append(f"  · {nm} —— {u.get('kind')}：{reading}")
    rc = RC_VIOLATION if violations else RC_OK
    return rc, {"reds": reds, "violations": violations, "notes": notes}


def render(rc, r) -> None:
    print(f"[known-red] 共 **{len(r['reds'])}** 条")
    for ln in r["notes"]:
        print(ln)
    if not r["violations"]:
        print()
        print("[结论] 每条 known-red 都有有效且未到期的 until。")
        print("       ⚠️ **这不等于债不该还** —— 本判据只查「到期日还在不在」，不查「该不该还」。")
        return
    print()
    print(f"[违规] {len(r['violations'])} 条：")
    for kind, nm, msg in r["violations"]:
        print(f"  ✗ [{kind}] {nm}")
        print(f"      {msg}")


# ══════════════════════════════════════════════════════════════════════
# selftest
# ══════════════════════════════════════════════════════════════════════

def _mk(name, until=None, blame="unknown", kind="known-red"):
    return {"name": name, "script": "x.py", "argv": [], "expect": 1,
            "why": "w", "kind": kind, "until": until, "blame": blame}


def selftest() -> int:
    cases = []

    def case(name, fn, want):
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001
            got = f"EXC:{e}"
        cases.append((name, got, want))

    DL_FUTURE = "2099-01-01"
    DL_PAST = "2000-01-01"

    # 干净：一条 manual 未过期 + 一条 contains 未满足
    def _clean():
        cs = [
            _mk("A", until={"kind": "manual", "by": "owner", "deadline": DL_FUTURE}),
            _mk("B", until={"kind": "contains", "file": "moon.mod", "text": "zzz_not_there"}),
        ]
        return judge(cs, run=False)[0]
    case("clean-all-have-until", _clean, RC_OK)

    # ★ 变异 1：无 until ⇒ 必红
    def _no_until():
        return judge([_mk("N")], run=False)[0]
    case("MUT-missing-until-goes-red", _no_until, RC_VIOLATION)

    # ★ 变异 2：until 条件已满足 + blame=subject ⇒ 必红「被检对象已修好，转 case」
    def _satisfied_subject():
        cs = [_mk("S", until={"kind": "contains", "file": "moon.mod", "text": "version"},
                  blame="subject")]
        return judge(cs, run=False)[0]
    case("MUT-satisfied-until-subject-goes-red", _satisfied_subject, RC_VIOLATION)

    # ★ 变异 2b：条件已满足但 blame=unknown ⇒ **不 FAIL**（只 WARN）——
    #    强行 FAIL 会逼人乱填 blame，那会让 blame 变成新的假信息源。
    def _satisfied_unknown_warns_only():
        cs = [_mk("U", until={"kind": "contains", "file": "moon.mod", "text": "version"},
                  blame="unknown")]
        rc, r = judge(cs, run=False)
        return (rc, any("请人工确认" in n for n in r["notes"]))
    case("satisfied-unknown-warns-not-fails", _satisfied_unknown_warns_only, (RC_OK, True))

    # blame=judge 时措辞必须是「判据已修好」
    def _satisfied_judge_wording():
        cs = [_mk("J", until={"kind": "contains", "file": "moon.mod", "text": "version"},
                  blame="judge")]
        rc, r = judge(cs, run=False)
        return (rc, any("判据已修好" in m for (_k, _n, m) in r["violations"]))
    case("satisfied-judge-wording", _satisfied_judge_wording, (RC_VIOLATION, True))

    # manual 超期 ⇒ 红
    def _expired():
        cs = [_mk("E", until={"kind": "manual", "by": "owner", "deadline": DL_PAST})]
        return judge(cs, run=False)[0]
    case("manual-expired-goes-red", _expired, RC_VIOLATION)

    # manual 缺 deadline ⇒ 红（= 没有到期日）
    def _manual_no_dl():
        cs = [_mk("M", until={"kind": "manual", "by": "owner"})]
        return judge(cs, run=False)[0]
    case("manual-without-deadline-goes-red", _manual_no_dl, RC_VIOLATION)

    # blame 非法 ⇒ 红
    def _bad_blame():
        cs = [_mk("B", until={"kind": "manual", "by": "o", "deadline": DL_FUTURE},
                  blame="nobody")]
        return judge(cs, run=False)[0]
    case("bad-blame-goes-red", _bad_blame, RC_VIOLATION)

    # until.kind 非法 ⇒ 红
    def _bad_kind():
        cs = [_mk("K", until={"kind": "magic"})]
        return judge(cs, run=False)[0]
    case("bad-until-kind-goes-red", _bad_kind, RC_VIOLATION)

    # 非 known-red 不参与（diag/case 不受 until 约束）
    def _non_known_red_ignored():
        cs = [_mk("D", kind="diag"), _mk("C", kind="case")]
        return judge(cs, run=False)[0]
    case("non-known-red-not-constrained", _non_known_red_ignored, RC_OK)

    # 真源标定（判例-32）：真的 run_guards.CASES 能被读到，且**当前所有 known-red 都有 until**
    def _calibrate_real():
        mod, cs = load_cases()
        reds = known_reds(cs)
        if not reds:
            return "SKIP"
        return all(_ok(c) for c in reds)
    case("calibrate-on-real-run_guards", _calibrate_real, True)

    ok = 0
    for name, got, want in cases:
        good = got == want or (want is True and got == "SKIP")
        ok += 1 if good else 0
        print(f"  [{'OK' if good else 'FAIL'}] {name:<36} got={got} want={want}")
    print(f"\n[selftest] {ok}/{len(cases)} 格通过")
    return 0 if ok == len(cases) else 1


def _ok(c) -> bool:
    u = c.get("until")
    if check_until_shape(u):
        return False
    if c.get("blame", "unknown") not in BLAMES:
        return False
    if isinstance(u, dict) and u.get("kind") == "manual":
        try:
            return datetime.date.fromisoformat(u["deadline"]) >= datetime.date.today()
        except Exception:  # noqa: BLE001
            return False
    return True


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--selftest" in argv:
        return selftest()
    run = "--no-run" not in argv
    try:
        mod, cs = load_cases()
    except Exception as e:  # noqa: BLE001
        print(f"[FATAL] 无法加载 run_guards.CASES：{e} ⇒ rc=2")
        return RC_CANNOT
    rc, r = judge(cs, mod, run)
    render(rc, r)
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"[BROKEN] 判据自身异常: {e} ⇒ rc=4")
        sys.exit(RC_BROKEN)
