#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_badge.py — README 测试徽章一致性守卫（R34）。

读取 `moon test --target js` 的输出文件，解析实际 "Total tests: N, passed: N"，
再解析 README 的 shields 徽章 `tests-N%2FN`；若徽章与实际测试数不一致则退出码 1，
在 CI 上把"徽章数字过时/手改漏同步"变成硬门禁，杜绝文档即实现倒退。

用法：
    python scripts/check_badge.py <moon_test_log> <README.md>
    python scripts/check_badge.py --selftest

退出码契约（R178，对齐本仓 0/1/2/4 分档）：
    0 = 徽章与实测一致（且快照的源码面锚点与现在同源）
    1 = 违例在场（徽章数字与实测不符 / README 缺徽章或缺自检注释 / 测试有失败）
    2 = **判据无法自证**（实参个数不对、被检文件读不到、日志里没有 `Total tests:` 汇总行、
        **或快照的源码面锚点与现在不同源 —— SNAPSHOT-STALE，见下**）
    4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）

为什么要把 2 从 1 里拆出来：R175 实测踩过——漏传 `<moon_test_log>` 时旧实现回 rc=1 并只打一行
usage，消费者唯一的读法就是"徽章守卫判红"，于是把一次**调用形状错**写进了交付报告的预存红清��。
「尺子没跑到被检面」和「被检面有缺陷」必须是两个数字。

## 判例-25：真源是「可过期快照」时的两面（2026-10-24）

**病灶实测**：`temp/pt27.log` 停在 `Total tests: 1455`（2026-10-24 19:54 手跑一次，之后没人再跑），
而真实现状是 1457。按旧实现：**README 的 1455 == 快照的 1455 ⇒ PASS 绿**。
—— 两个都停在同一个旧值，于是「一致」被读成「正确」。这不是判据不准，**是判据在说谎**。

两条路都不许说谎：

- **B'（默认，裸跑）**：快照必须**自带源码面锚点**，且锚点必须等于现在。
  锚点 = `<snapshot>.src`，内容两行：`head=<sha>` 与 `code=<porcelain 摘要>`，只覆盖
  **源码语义面**（`*.mbt` / `*.pkg` / `*.mod` / `moon.mod`）。缺失或不等 ⇒
  `rc=2 SNAPSHOT-STALE`（**诚实沉默**，不是 PASS、也不是违例红）。
  看的是**代码变没变**，不是 mtime 变没变（判据的真源若是文件系统事实，必须验证它是否代表语义事实）。
  文档（`*.md` 等）改动**不**让锚点失效——改文档不会改测试数。
- **A（`--fresh`）**：判前真跑一次全仓 `moon_test_env.py --raw-log <snapshot>`，
  跑完**重写快照与锚点**，于是「文档 == 现实」被真正证明。成本实测约 7~8 分钟，
  `run_guards` 的格子用它（一次跑覆盖整轮电池）。

**文案纪律**：证明不了现实时**不许用「实测」这个词**。旧文案
`PASS … == 实测 1455/1455` 里的「实测」指的不是现实，是快照 —— 那本身就在放大假绿。
新文案把快照路径、mtime、源码面 sha 一起打出来。
"""
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# 判例-25：锚点口径只有一份真源（scripts/badge_anchor.py），本尺只**调用**不复制。
# 两把吃同一类快照的尺（本尺 / check_test_sync）各写一份锚点 = 两份口径必然漂。
import _badge_anchor as badge_anchor  # noqa: E402  (判例-25：锚点单一真源，_ 前缀=内部共享模块)


REJECT = "reject"    # 判据无法自证：被检面/调用形状不可用
VIOLATE = "violate"  # 违例在场

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOON_TEST_ENV = os.path.join(ROOT, "scripts", "moon_test_env.py")
# 单测要把锚点逻辑换成桩（证明本尺**真的**调了共用模块，而不是自己又写了一份）
_anchor = badge_anchor


# BUG-58：守卫的“红”必须是判据红。Windows 默认 GBK 控制台下，中文结论里的 ↔ 等字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def parse_test_count(log_text):
    """取最后一个 `Total tests: N, passed: N, failed: F` 行。"""
    total = passed = failed = None
    for line in log_text.splitlines():
        m = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)", line)
        if m:
            total, passed, failed = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    if total is None:
        raise SystemExit("FATAL: 未在日志中找到 'Total tests:' 行")
    return total, passed, failed


def parse_readme_badge(readme_text):
    """解析 `tests-N%2FN` 徽章 -> (N, N)；找不到返回 None。"""
    m = re.search(r"tests-(\d+)%2F(\d+)", readme_text)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def parse_readme_selfcheck_count(readme_text):
    """解析 README「一键完整自检」块注释里的 `Total tests: N, passed: N`（R50 校准项）-> N；找不到返回 None。"""
    m = re.search(r"#\s*→\s*Total tests:\s*(\d+),\s*passed:\s*(\d+)", readme_text)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def judge(log_text, readme_text):
    """纯判定：返回 (problems, info)。problems 空 == 绿。
    （不含快照新鲜度——那是文件系统面，见 `snapshot_anchor` / `anchor_problems`。）

    BUG-360：判据从 main() 抽出成可单测的纯函数——selftest 直接喂合成串，
    `or`→`and` 变异（分子/分母任一错被短路放行）必被 V1/V2/V3 抓到。
    main() 只负责读文件 + 打印 PASS + 把 problems 映射到退出码。

    R178：problems 每项是 (kind, text)，kind ∈ {REJECT, VIOLATE}——退出码分档必须由
    判据自己给出，不能靠调用方嗅探消息前缀（那等于把契约写进散文）。
    """
    problems = []
    info = {"total": None, "badge": None, "sc": None}

    total = None
    failed = None
    for line in log_text.splitlines():
        m = re.search(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)", line)
        if m:
            total, failed = int(m.group(1)), int(m.group(3))
    if total is None:
        return [(REJECT, "REJECT: 日志里没有 'Total tests:' 行（被检面给不出实测数 ⇒ rc=2，不是违例）")], info
    info["total"] = total
    if failed != 0:
        problems.append((VIOLATE, f"FATAL: 测试有失败 failed={failed}（徽章守卫前置失败）"))

    bm = re.search(r"tests-(\d+)%2F(\d+)", readme_text)
    if not bm:
        problems.append((VIOLATE, "FATAL: README 未找到 tests-N%2FN 徽章（徽章被删同样是文档面违例）"))
        return problems, info
    n, d = int(bm.group(1)), int(bm.group(2))
    info["badge"] = (n, d)
    if n != total or d != total:
        problems.append(
            (VIOLATE,
             f"BADGE-STALE: README 徽章 {n}/{d} ≠ 实际测试数 {total}/{total}。"
             f"请用 `moon test --target js -j 1` 实测后同步（工具数/测试数/徽章全量对齐）。")
        )

    # R50/R52：README「一键完整自检（评审用）」注释里的 Total tests 也须与实测一致，
    # 否则评审照命令运行时"注释写 N/实测 M"矛盾。
    scm = re.search(r"#\s*→\s*Total tests:\s*(\d+),\s*passed:\s*(\d+)", readme_text)
    if not scm:
        problems.append((VIOLATE, "FATAL: README 未找到『一键完整自检』里的 'Total tests: N, passed: N' 注释"))
        return problems, info
    sn, sp = int(scm.group(1)), int(scm.group(2))
    info["sc"] = (sn, sp)
    if sn != total or sp != total:
        problems.append(
            (VIOLATE,
             f"SELFCHECK-STALE: README 自检注释 Total tests {sn}/{sp} ≠ 实测 {total}/{total}。请同步。")
        )
    return problems, info


def selftest():
    """判据必须先证明自己会红：违例必红 + 干净必绿。格子计数从 cases 反解，不手写。

    BUG-360：这是本守卫此前完全缺失的自检面——旧实现连 `--selftest` 都当位置参数
    吃掉、报 usage exit 1，所以「改坏判据会不会红」从没人锁过。
    V1/V2 分别把徽章分子/分母单独改错，钉死 L71 `or` 的两条腿各自独立生效：
    若 `or`→`and`，单腿错会被短路放行 → 该格由红转绿 → SELFTEST FAIL。V3 同钉 L84。

    A1~A5（判例-25）：快照锚点面。A2 是病灶本体——旧实现里「快照过期」= PASS 绿。
    """
    _entry_probe()
    total = 1347
    good_log = f"Total tests: {total}, passed: {total}, failed: 0\n"
    good_readme = (
        f"[![tests](https://img.shields.io/badge/tests-{total}%2F{total}-green)] "
        f"# → Total tests: {total}, passed: {total}\n"
    )
    cases = [
        ("G1 干净全对（必须绿）", good_log, good_readme, False),
        ("V1 徽章分子错", good_log, good_readme.replace(f"tests-{total}%2F", "tests-9999%2F"), True),
        ("V2 徽章分母错", good_log, good_readme.replace(f"%2F{total}-green", f"%2F{total - 1}-green"), True),
        ("V3 自检注释分子错", good_log, good_readme.replace(f"→ Total tests: {total}", "→ Total tests: 9999"), True),
        ("V4 测试有失败", f"Total tests: {total}, passed: {total - 5}, failed: 5\n", good_readme, True),
        ("V5 无徽章", good_log, f"# → Total tests: {total}, passed: {total}\n", True),
        ("V6 无自检注释", good_log, f"tests-{total}%2F{total}-green\n", True),
        ("V7 日志无 Total 行", "moon test 跑完了\n", good_readme, True),
    ]
    bad = 0
    for name, lg, rm, should_red in cases:
        probs, _ = judge(lg, rm)
        is_red = bool(probs)
        ok = (is_red == should_red)
        if not ok:
            bad += 1
        print(f"  {name:<26} {'红' if is_red else '绿'}  {'符合预期' if ok else '**不符预期**'}")
        if is_red and not ok:
            print(f"      └ 期望红却绿（判据被短路放行）")
    reds = sum(1 for c in cases if c[3])
    # R178 分类锁：分档判错比不分档更坏——真违例被降级成 reject 会让 CI 丢掉红门，
    # 而调用形状错被判成 violate 会让消费者把「没喂参数」读成「徽章过时」。
    want_kind = {"G1": set(), "V7": {REJECT}}
    for name, lg, rm, should_red in cases:
        got = {k for k, _ in judge(lg, rm)[0]}
        want = want_kind.get(name.split()[0], {VIOLATE})
        if got != want:
            bad += 1
            print(f"  **不符预期** {name} 分类 {sorted(got) or '空'} 期望 {sorted(want) or '空'}")

    # 入口级锁（R178）：纯函数会分档不等于 main() 接了这条判据——在真子进程上考四个档。
    entry_cases = []
    with tempfile.TemporaryDirectory() as td:
        p_log = os.path.join(td, "ok.log")
        with open(p_log, "w", encoding="utf-8") as f:
            f.write(good_log)
        p_rm = os.path.join(td, "README.md")
        with open(p_rm, "w", encoding="utf-8") as f:
            f.write(good_readme)
        # 锚点面的「现在」指纹：先算出来，后面各夹具都要用它写锚点（顺序有讲究——
        # 先写 p_notal 的锚点再算 now_line 会 UnboundLocalError，实测踩过）
        now_line = badge_anchor.current_anchor(cwd=ROOT)
        p_notal = os.path.join(td, "no-total.log")
        with open(p_notal, "w", encoding="utf-8") as f:
            f.write("moon test 跑完了\n")
        # E3 要考的是「日志无汇总行」，必须先过锚点面这一关，否则考到的是 A2
        with open(badge_anchor.anchor_path(p_notal), "w", encoding="utf-8") as f:
            f.write(now_line + "\n")
        p_stale = os.path.join(td, "stale-README.md")
        with open(p_stale, "w", encoding="utf-8") as f:
            f.write(good_readme.replace(f"tests-{total}%2F", "tests-9999%2F"))
        me = os.path.abspath(__file__)
        missing = os.path.join(td, "does-not-exist.log")

        # A 面（判例-25）：快照新鲜度。纯文件面夹具，不跑全仓、不碰网络。
        # A2 是病灶本体：旧实现里「快照过期」= PASS 绿；现在必须是 rc=2（诚实沉默）。
        p_anch = os.path.join(td, "anchored.log")
        with open(p_anch, "w", encoding="utf-8") as f:
            f.write(good_log)
        # A1 场景：锚点 == 现在（直接写当前指纹，模拟「刚刚跑过」）
        with open(badge_anchor.anchor_path(p_anch), "w", encoding="utf-8") as f:
            f.write(now_line + "\n")
        p_noanch = os.path.join(td, "noanchor.log")
        with open(p_noanch, "w", encoding="utf-8") as f:
            f.write(good_log)
        p_oldanch = os.path.join(td, "oldanchor.log")
        with open(p_oldanch, "w", encoding="utf-8") as f:
            f.write(good_log)
        with open(badge_anchor.anchor_path(p_oldanch), "w", encoding="utf-8") as f:
            f.write(badge_anchor.ANCHOR_PREFIX + "deadbeef" + "@0123456789abcdef\n")

        entry_cases = [
            ("E1 无实参 rc=2", [me], 2),
            ("E2 被检文件读不到 rc=2", [me, missing, p_rm], 2),
            ("E3 日志无汇总行 rc=2", [me, p_notal, p_rm], 2),
            ("E4 徽章过期 rc=1", [me, p_anch, p_stale], 1),
            ("E5 干净 rc=0", [me, p_anch, p_rm], 0),
            ("A2 快照锚点缺失 rc=2", [me, p_noanch, p_rm], 2),
            ("A3 快照锚点过期 rc=2", [me, p_oldanch, p_rm], 2),
        ]
        for name, tail, want_rc in entry_cases:
            r = subprocess.run([sys.executable] + tail, capture_output=True,
                               text=True, encoding="utf-8", errors="replace")
            out = (r.stdout or "") + (r.stderr or "")
            ok = (r.returncode == want_rc) and ("Traceback" not in out)
            if not ok:
                bad += 1
            print(f"  {name:<22} rc={r.returncode} 期望 {want_rc} "
                  f"{'符合预期' if ok else '**不符预期**（traceback 同判不符）'}")

    # 调用面锁（判例-29：机制格 ≠ 实现路径格）：把共用模块换成**桩**，
    # 若本尺仍然自己算锚点（复制过一份），这一格必绿 ⇒ 立刻现形。
    calls = {"n": 0}

    class _StubAnchor:
        ANCHOR_PREFIX = badge_anchor.ANCHOR_PREFIX

        @staticmethod
        def anchor_problems(snapshot_path, cwd=None):
            calls["n"] += 1
            return [("reject", "STUB: 共用模块被调用")], {"anchor": "", "now": ""}

    global _anchor
    saved = _anchor
    try:
        _anchor = _StubAnchor
        stub_probs, _ = anchor_problems("anything.log")
    finally:
        _anchor = saved
    ok_call = (calls["n"] == 1) and bool(stub_probs) and "STUB" in stub_probs[0][1]
    if not ok_call:
        bad += 1
    print(f"  {'C1 真的调了共用模块':<22} {'是' if ok_call else '否'}  "
          f"{'符合预期' if ok_call else '**不符预期**（自己算了一份锚点？判例-29）'}")

    if bad:
        print(f"SELFTEST FAIL：{bad} 项不符预期"
              f"（判据 {len(cases)} 支 + 入口 {len(entry_cases)} 支 + 调用面 1 支）")
        return 1
    print(f"SELFTEST OK：{len(cases) + len(entry_cases) + 1} 支对照全按预期"
          f"（判据违例必红 {reds} / 干净必绿 {len(cases) - reds} / 入口分档 {len(entry_cases)} + "
          f"调用面 1，含判例-25 A2/A3 快照锚点面与 C1 共用模块调用面；"
          f"计数从 cases 与 entry_cases 反解，不手写）")
    return 0



# ── 判例-25：快照的源码面锚点 ────────────────────────────────────────────────
#
# 锚点的**唯一真源**是 `scripts/badge_anchor.py`（两把吃同类快照的尺共用）。
# 这里只留一层薄代理：目的不是再实现一次，而是让 selftest 能把 `_anchor` 换成桩，
# 断言「本尺确实走了共用模块」——判例-29：机制格 ≠ 实现路径格。


def anchor_problems(snapshot_path, cwd=None):
    """透传到共用模块（`_anchor` 可被单测替换成桩）。"""
    return _anchor.anchor_problems(snapshot_path, cwd=cwd)


def write_anchor(snapshot_path, cwd=None):
    """透传到共用模块。"""
    return _anchor.write_anchor(snapshot_path, cwd=cwd)


def run_fresh(snapshot_path, cwd=None):
    """A 方案：判前真跑一次全仓 `moon test --target js`，落快照 + 锚点。返回 (ok, tail)。

    为什么放在判据里而不是让人记得手跑：`temp/pt27.log` 的 mtime 停在 19:54，
    之后全仓多了 2 个测试没人再跑过 —— 「记得手跑」不是机制。
    跑不出真值 ⇒ 调用方走 rc=2（诚实沉默），不拿旧快照冒充现实。
    """
    if not os.path.isfile(MOON_TEST_ENV):
        return False, "moon_test_env.py 不在：%s" % MOON_TEST_ENV
    p = subprocess.run([sys.executable, MOON_TEST_ENV, "--target", "js", "--raw-log", snapshot_path],
                       cwd=cwd or ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    tail = "\n".join([x for x in out.strip().splitlines() if "Total tests" in x] or
                     out.strip().splitlines()[-3:])
    if p.returncode != 0:
        return False, tail or ("moon_test_env rc=%d（无输出）" % p.returncode)
    write_anchor(snapshot_path, cwd=cwd)
    return True, tail


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
    argv = sys.argv[1:]
    if len(argv) == 1 and argv[0] == "--selftest":
        return selftest()
    # A 方案（判例-25）：--fresh 判前真跑一次全仓，跑完重写快照 + 源码面锚点。
    fresh = "--fresh" in argv
    if fresh:
        argv = [a for a in argv if a != "--fresh"]
    if len(argv) != 2:
        print("用法: python scripts/check_badge.py [--fresh] <moon_test_log> <README.md> | --selftest")
        print(f"REJECT 调用形状错：需要 2 个实参，收到 {len(argv)} 个"
              f"（判据没跑到被检面 ⇒ rc=2，不冒用违例红 rc=1）")
        return 2
    log_path, readme_path = argv
    if not os.path.isfile(readme_path):
        print(f"REJECT README读不到：{readme_path}（被检面缺失，判据拒绝出结论 ⇒ rc=2）")
        return 2

    if fresh:
        ok, tail = run_fresh(log_path)
        print("FRESH 真跑全仓：%s" % ("成功" if ok else "失败"))
        for ln in tail.splitlines():
            print("  " + ln)
        if not ok:
            print("REJECT --fresh 跑不出真值（rc≠0）⇒ rc=2，不拿旧快照冒充现实")
            return 2

    if not os.path.isfile(log_path):
        print(f"REJECT 测试日志读不到：{log_path}（被检面缺失，判据拒绝出结论 ⇒ rc=2）")
        return 2

    # 判例-25 B'：先验「快照是不是现在的代码跑出来的」——过期就诚实沉默，不许 PASS。
    # --fresh 跑完已重写锚点，这里必然通过；裸跑则这一格是唯一的防线。
    aprobs, ainfo = anchor_problems(log_path)
    for _, t in aprobs:
        print(t)
    if aprobs:
        return 2

    with open(log_path, encoding="utf-8", errors="replace") as f:
        log_text = f.read()
    with open(readme_path, encoding="utf-8") as f:
        readme_text = f.read()

    problems, info = judge(log_text, readme_text)
    if any(k == REJECT for k, _ in problems):
        for _, t in problems:
            print(t)
        return 2
    if problems:
        raise SystemExit(problems[0][1])

    total = info["total"]
    n, d = info["badge"]
    sn, sp = info["sc"]
    # 文案纪律（判例-25）：「实测」只配指现实。这里能证明的是
    # 「README == 快照（且快照的源码面 == 现在）」，所以逐项把证据打出来。
    try:
        mtime = os.path.getmtime(log_path)
        import datetime
        stamp = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
    except (OSError, ValueError):
        stamp = "?"
    head = ainfo["now"].split("@")[0].replace("code=", "")[:12]
    print(f"PASS 徽章一致：README tests-{n}%2F{d} == 快照 {log_path} @ {stamp}"
          f"（源码面 {head}）")
    print(f"PASS 自检注释一致：README 『→ Total tests: {sn}, passed: {sp}』 == 快照 {log_path}")
    print(f"PASS 快照同源：源码面 {ainfo['now']} == 现在（文档改动不影响该锚点）")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise  # 违例档由 main() 自己定，不许被「尺子坏了」那一档吃掉
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了 ⇒ 真给 4，绝不冒用 1（R178）
        sys.stderr.write("BADGE RULER BROKEN: %r\n" % e)
        sys.exit(4)