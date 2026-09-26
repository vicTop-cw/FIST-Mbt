#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_test_sync.py — 测试总数单一真源一致守卫（CI JS 轨）。
唯一真源 = moon test 的实测通过总数（从测试日志或直接参数传入）。
校验 README/AGENTS/deliverable/scoring_rubric 四处的测试总数表述都与实测一致；
与 check_badge（只核 README 徽章）互补，堵住"改测试数只同步了一个文档"的漂移。

用法：
  python scripts/check_test_sync.py <moon_test_log>          # 从日志提取 "Total tests: N"
  python scripts/check_test_sync.py --total 233              # 直接给总数

任一文档漂移即 FAIL（退出码非 0）。
"""
import re
import sys
from pathlib import Path

# BUG-58：守卫的“红”必须是判据红。Windows 默认 GBK 控制台下，中文结论里的 ↔ 等字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
DOCS = [
    ROOT / "README.md",
    ROOT / "AGENTS.md",
    ROOT / "docs" / "deliverable.md",
    ROOT / "scripts" / "scoring_rubric.md",
]


def main():
    args = sys.argv[1:]
    total = None
    if args and args[0] == "--total" and len(args) >= 2:
        total = int(args[1])
    elif args:
        log = Path(args[0]).read_text(encoding="utf-8", errors="replace")
        m = re.search(r"Total tests:?\s*(\d+)\s*,\s*passed:\s*\d+", log)
        m2 = re.search(r"total=(\d+) passed=(\d+)", log)
        if m:
            total = int(m.group(1))
        elif m2:
            total = int(m2.group(1))
    if total is None:
        print("FAIL 无法从参数/日志解析测试总数")
        return 1

    re_total = re.compile(rf"(?<!\d){total}(?!\d)")
    problems = []
    for path in DOCS:
        txt = path.read_text(encoding="utf-8")
        # 用"╱"或"/"连接的 N/N 或独立的 N 均可
        ok = bool(re.search(rf"{total}\s*[\\/╱]\s*{total}", txt)) \
            or bool(re.search(rf"{total}\s*全绿", txt)) or bool(re.search(rf"全绿\s*{total}", txt)) \
            or bool(re_total.search(txt))
        if not ok:
            problems.append(path.name)
    if problems:
        print(f"FAIL 测试总数 {total} 未在所有文档一致表述：缺 {" ".join(problems)}")
        return 1
    print(f"PASS 测试总数单一真源一致：实测 {total}，README/AGENTS/deliverable/scoring_rubric 对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())