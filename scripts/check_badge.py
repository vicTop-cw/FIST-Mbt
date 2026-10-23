#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_badge.py — README 测试徽章一致性守卫（R34）。

读取 `moon test --target js` 的输出文件，解析实际 "Total tests: N, passed: N"，
再解析 README 的 shields 徽章 `tests-N%2FN`；若徽章与实际测试数不一致则退出码 1，
在 CI 上把"徽章数字过时/手改漏同步"变成硬门禁，杜绝文档即实现倒退。

用法：
    python scripts/check_badge.py <moon_test_log> <README.md>
"""
import re
import sys


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

    BUG-360：判据从 main() 抽出成可单测的纯函数——selftest 直接喂合成串，
    `or`→`and` 变异（分子/分母任一错被短路放行）必被 V1/V2/V3 抓到。
    main() 只负责读文件 + 打印 PASS + 把 problems[0] 转成 SystemExit。
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
        return ["FATAL: 未在日志中找到 'Total tests:' 行"], info
    info["total"] = total
    if failed != 0:
        problems.append(f"FATAL: 测试有失败 failed={failed}（徽章守卫前置失败）")

    bm = re.search(r"tests-(\d+)%2F(\d+)", readme_text)
    if not bm:
        problems.append("FATAL: README 未找到 tests-N%2FN 徽章")
        return problems, info
    n, d = int(bm.group(1)), int(bm.group(2))
    info["badge"] = (n, d)
    if n != total or d != total:
        problems.append(
            f"BADGE-STALE: README 徽章 {n}/{d} ≠ 实际测试数 {total}/{total}。"
            f"请用 `moon test --target js -j 1` 实测后同步（工具数/测试数/徽章全量对齐）。"
        )

    # R50/R52：README「一键完整自检（评审用）」注释里的 Total tests 也须与实测一致，
    # 否则评审照命令运行时"注释写 N/实测 M"矛盾。
    scm = re.search(r"#\s*→\s*Total tests:\s*(\d+),\s*passed:\s*(\d+)", readme_text)
    if not scm:
        problems.append("FATAL: README 未找到『一键完整自检』里的 'Total tests: N, passed: N' 注释")
        return problems, info
    sn, sp = int(scm.group(1)), int(scm.group(2))
    info["sc"] = (sn, sp)
    if sn != total or sp != total:
        problems.append(
            f"SELFCHECK-STALE: README 自检注释 Total tests {sn}/{sp} ≠ 实测 {total}/{total}。请同步。"
        )
    return problems, info


def selftest():
    """判据必须先证明自己会红：违例必红 + 干净必绿。格子计数从 cases 反解，不手写。

    BUG-360：这是本守卫此前完全缺失的自检面——旧实现连 `--selftest` 都当位置参数
    吃掉、报 usage exit 1，所以「改坏判据会不会红」从没人锁过。
    V1/V2 分别把徽章分子/分母单独改错，钉死 L71 `or` 的两条腿各自独立生效：
    若 `or`→`and`，单腿错会被短路放行 → 该格由红转绿 → SELFTEST FAIL。V3 同钉 L84。
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
    if bad:
        print(f"SELFTEST FAIL：{bad}/{len(cases)} 支不符预期")
        return 1
    print(f"SELFTEST OK：{len(cases)} 支对照全按预期（违例必红 {reds} / 干净必绿 {len(cases) - reds}）")
    return 0



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
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        return selftest()
    if len(sys.argv) != 3:
        raise SystemExit("用法: python scripts/check_badge.py <moon_test_log> <README.md> | --selftest")
    log_path, readme_path = sys.argv[1], sys.argv[2]

    with open(log_path, encoding="utf-8", errors="replace") as f:
        log_text = f.read()
    with open(readme_path, encoding="utf-8") as f:
        readme_text = f.read()

    problems, info = judge(log_text, readme_text)
    if problems:
        raise SystemExit(problems[0])

    total = info["total"]
    n, d = info["badge"]
    sn, sp = info["sc"]
    print(f"PASS 徽章一致：README tests-{n}%2F{d} == 实测 {total}/{total}")
    print(f"PASS 自检注释一致：README 『→ Total tests: {sn}, passed: {sp}』 == 实测 {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())