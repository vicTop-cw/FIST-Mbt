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


def main():
    if len(sys.argv) != 3:
        raise SystemExit("用法: python scripts/check_badge.py <moon_test_log> <README.md>")
    log_path, readme_path = sys.argv[1], sys.argv[2]

    with open(log_path, encoding="utf-8", errors="replace") as f:
        log_text = f.read()
    with open(readme_path, encoding="utf-8") as f:
        readme_text = f.read()

    total, passed, failed = parse_test_count(log_text)
    if failed != 0:
        raise SystemExit(f"FATAL: 测试有失败 failed={failed}（徽章守卫前置失败）")

    badge = parse_readme_badge(readme_text)
    if badge is None:
        raise SystemExit("FATAL: README 未找到 tests-N%2FN 徽章")

    n, d = badge
    if n != total or d != total:
        raise SystemExit(
            f"BADGE-STALE: README 徽章 {n}/{d} ≠ 实际测试数 {total}/{total}。"
            f"请用 `moon test --target js -j 1` 实测后同步（工具数/测试数/徽章全量对齐）。"
        )
    print(f"PASS 徽章一致：README tests-{n}%2F{d} == 实测 {total}/{total}")

    # R50/R52：README「一键完整自检（评审用）」注释里的 Total tests 也须与实测一致，
    # 否则评审照命令运行时"注释写 N/实测 M"矛盾。
    sc = parse_readme_selfcheck_count(readme_text)
    if sc is None:
        raise SystemExit("FATAL: README 未找到『一键完整自检』里的 'Total tests: N, passed: N' 注释")
    sn, sp = sc
    if sn != total or sp != total:
        raise SystemExit(
            f"SELFCHECK-STALE: README 自检注释 Total tests {sn}/{sp} ≠ 实测 {total}/{total}。请同步。"
        )
    print(f"PASS 自检注释一致：README 『→ Total tests: {sn}, passed: {sp}』 == 实测 {total}")


if __name__ == "__main__":
    main()