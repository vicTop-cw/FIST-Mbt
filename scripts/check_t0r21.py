#!/usr/bin/env python3
r"""T0r2.1 run_check 判据：`moon test --target js src/engine` 全绿即通过（BUG-253 修复回归）。

**本件是 T0r2.1 当轮的验收判据，不是日常工具** —— 保留作活证据（BUG-325 裁决：
「删除=丢当轮证据，登记=保留作活证据，非日常工具」同型入账）。

2026-10-31 R115 打磨（两处都是「改名后失去豁免」逼出来的，判例-39）：
1. **去掉本机绝对路径** —— 原第 13/15 行内嵌「某台机器的家目录 + moon.exe」与
   「某台机器的工程绝对路径」两个字面量，换机不可复跑；`check_hardcoded_paths` 的豁免
   只认 `scripts/_*.py` 前缀（本件已按 NAMING.md 债表的「改名 `check_*.py`」建议改名，
   豁免随之消失）⇒ 改为**从 `__file__` 反推仓根** + 走常驻入口 `moon_test_env.py`
   （后者负责剔 PATH 上的 `node.cmd` 垫片与 `MOONC_OVERRIDE`，见 BUG-380/BUG-125）。
   ⚠️ 本 docstring **故意不写出那两个 token**（家目录名与工程目录名）——判据扫的是
   token 不是意图，写出来就等于自己把自己判红。
2. **去掉写死的 `passed: 162`** —— 该数是 2026-10-16 的读数，现在 `src/engine` 是
   **382/382**；写死一个旧数 = 判据恒红的哑雷（比没有判据更坏）。改为**从输出里解析
   `Total tests: N, passed: M, failed: K`**，只判 `K == 0 且 N == M`。

3. **2026-11-02 R118 补 `--selftest` + 未知旗标硬拒** —— 本件此前是**无参脚本**：
   `run_guards.py` 的 `auto_cases()` 按 `check_` 前缀给它补一格 `--selftest`，而本件
   **不解析 argv** ⇒ `--selftest` 被**静默忽略**、直接跑真 `moon test`（4 分钟）。
   这正是 AGENTS.md「新判据必须拒绝未知旗标」要防的形状：自检开关拼错 = 静默失去自检，
   而且**看着绿得很像那么回事**（它真跑、真全绿、真回 rc=0）。修法是把「取数」与
   「打法」拆开（同 `check_test_sync.py` 的 `report()` 缝）：`main(argv, out_text=None)`
   —— `out_text` 给了就**不 spawn**，直接判那段合成输出。自检格子因此**不读真仓库、
   不起子进程**，而它测的是**实现路径本身**（旗标分流 + 汇总行判定），不是别的函数。

4. **2026-11-02 R118 子进程 cwd 隔离** —— 首次进电池后 `check_selftest_hermetic`
   报 G 档越线（selftest→main→_run_check 的**静态链**够得着 `cwd=ROOT`，哪怕自检
   格子实际全走 `out_text` 合成缝）。cwd 改取系统临时目录 ⇒ S 档；真检查行为不变
   （`moon_test_env.py` 的 ROOT 与进程 cwd 无关）。

rc 契约（与 `moon_test_env.py` 同源）：`0` 全绿 / `1` 有失败 / `2` 判据无法自证
（没有汇总行 —— BUG-142：不许只凭 `moon` 的退出码判绿）。
"""
import os
import re
import subprocess
import sys
import tempfile


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SCOPE = "src/engine"
# 入口**必须绝对路径**（2026-11-02 R118）：cwd 已隔离到系统临时目录（见下），相对路径
# `scripts/moon_test_env.py` 只在 cwd=仓根时能解析——第一版隔离后真跑当场
# `can't open file 'C:\…\Temp\scripts\moon_test_env.py'`（rc=2）。绝对化后子进程从任何
# cwd 都能找到入口，而 `moon_test_env.py` 的 ROOT 从它自己的 `__file__` 反推（:141，
# 明写「与本进程 cwd 无关」）⇒ 真检查行为不变。
ENTRY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "moon_test_env.py")
# 子进程 cwd 隔离（2026-11-02 R118）：`check_selftest_hermetic` 的 G 档 = 「subprocess
# 的 cwd/env 值里带仓库锚点（或干脆没给）」⇒ selftest→main→_run_check 的**静态链**会把
# `cwd=ROOT` 记成 G（哪怕自检格子实际全走 out_text 合成缝、_run_check 一次都不执行）。
# cwd 改取系统临时目录 ⇒ S 档（「跑真尺子、打合成输入」的认可形状，记账不判红、不进棘轮）。
# 真检查行为不变：`moon_test_env.py` 的 ROOT 从它自己的 `__file__` 反推（:141，明写
# 「与本进程 cwd 无关」）。
_SPAWN_CWD = tempfile.gettempdir()

SUMMARY_RE = re.compile(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)")

# R207：未知旗标必须硬拒，否则拼错自检开关 = 静默跑真检查。本件无位置参数。
_KNOWN_FLAGS = ("--selftest",)


def _run_check():
    """取数侧：起常驻入口跑 `src/engine`，返回拼接后的输出；起不来返回 None。"""
    cmd = [sys.executable, ENTRY, "--target", "js", SCOPE]
    try:
        # encoding 必须显式给 UTF-8：`text=True` 不带 `encoding=` 时 Python 用**本机 locale**
        # （本机 GBK）解码，moon 的输出是 UTF-8 ⇒ 读侧线程 UnicodeDecodeError ⇒
        # **stdout/stderr 双双返回空、而 returncode 照常是 0**（2026-10-31 实测）——
        # 父进程拿到「rc=0 + 空输出」，比直接崩更难判。与 BUG-58/138 同族，只是这一处
        # 在**取数的这一侧**，不在被取的那一侧。
        p = subprocess.run(cmd, cwd=_SPAWN_CWD, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=900)
    except Exception as e:
        print("ERR spawn: %s" % e)
        return None
    out = (p.stdout or "") + (p.stderr or "")
    print("CMD:", " ".join(cmd))
    print("EXIT:", p.returncode)
    print(out[-2000:])
    return out


def main(argv=None, out_text=None):
    """打法侧。`out_text` 给了就不 spawn（自检用合成夹具走这条缝）。"""
    argv = sys.argv[1:] if argv is None else list(argv)

    if "--selftest" in argv:
        return selftest()

    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知旗标：%s（rc=2；本件无位置参数）"
              % (" ".join(unknown), " / ".join(_KNOWN_FLAGS)))
        return 2

    out = out_text if out_text is not None else _run_check()
    if out is None:
        return 2

    m = None
    for line in out.splitlines():
        m = SUMMARY_RE.search(line)
        if m:
            break
    if m is None:
        print("ERR 判据无法自证：输出里没有 `Total tests: N, passed: M, failed: K` 汇总行")
        return 2

    total, passed, failed = int(m.group(1)), int(m.group(2)), int(m.group(3))
    print("SUMMARY: total=%d passed=%d failed=%d" % (total, passed, failed))
    if failed != 0:
        print("FAIL 有失败：failed=%d" % failed)
        return 1
    if total != passed:
        print("FAIL 总数与通过数不等：total=%d passed=%d" % (total, passed))
        return 1
    print("PASS %s 全绿：%d/%d" % (SCOPE, passed, total))
    return 0


def selftest():
    """合成夹具格：全部走 `main()` 本体（实现路径格），不读真仓库、不起子进程。

    ⚠️ **不给 `--selftest` 本身立「路由格」**：把那个分支摘掉之后 selftest 根本
    不会被调起（`--selftest` 落进取数侧跑真检查），任何写在 selftest **内部**的
    断言都测不到「分支没了」。这层防线由 `check_arg_face_strict` 承担——它从
    **外面**喂 `--definitely-not-real`，分支没了 ⇒ 静默跑真检查 ⇒ 超时/不定 ⇒ 当场点名。
    本件第一版曾写「换分发目标 + 必炸桩」的机制格，变异对照**照样绿**（锁是装饰），
    已删——判例-30 第四形态：看着在测，测的是一条变异够不着的路。
    """
    cells = []

    def cell(name, argv, out_text, want):
        got = main(argv, out_text=out_text)
        cells.append((name, got == want, got, want))
        return got == want

    ok = True

    clean = (
        "----- BEGIN MOON TEST RESULT -----\n"
        "[engine] 382 tests\n"
        "Total tests: 382, passed: 382, failed: 0\n"
        "----- END MOON TEST RESULT -----\n"
    )
    # 汇总行故意不在首行：若判定退化成「只看第一行」，这一格必红 ⇒ 它是逐行扫描的变异对照。
    ok &= cell("summary-not-first-line-is-found", [], clean, 0)

    ok &= cell("failed-nonzero-is-red", [], clean.replace("failed: 0", "failed: 3"), 1)

    mismatch = clean.replace("Total tests: 382, passed: 382",
                             "Total tests: 10, passed: 8")
    ok &= cell("total-passed-mismatch-is-red", [], mismatch, 1)

    ok &= cell("no-summary-line-is-unprovable", [],
               "----- BEGIN MOON TEST RESULT -----\n[engine] all good\n", 2)

    # 旗标面：拼错 / 未知必须硬拒，否则静默跑真检查（R207 失效形态本体）。
    ok &= cell("misspelled-selftest-rejected", ["--self-test"], clean, 2)
    ok &= cell("unknown-flag-rejected", ["--definitely-not-real"], clean, 2)

    bad = [c for c in cells if not c[1]]
    if bad:
        for name, _, got, want in bad:
            print("SELFTEST FAIL [%s] 期望 rc=%s，实际 rc=%s" % (name, want, got))
        print("SELFTEST FAIL %d/%d 格" % (len(bad), len(cells)))
        return 1
    print("SELFTEST OK（%d 格：汇总行判定 4 + 旗标面 2）" % len(cells))
    return 0


if __name__ == "__main__":
    sys.exit(main())
