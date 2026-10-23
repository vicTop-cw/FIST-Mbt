#!/usr/bin/env python3
"""FIST-Mbt pre-push guard: block direct push to gitcode/main.

Reads the pre-push hook stdin format:
    <local-ref> <local-sha> <remote-ref> <remote-sha> [remote-url]

Block condition: remote-ref == refs/heads/main AND remote-url contains "gitcode".
Anything else exits 0 (silent pass).

Standard library only (sys, re). No third-party dependencies.
"""

import re
import sys

# BUG-138（BUG-58 同族）：本脚本往 stderr 打中文结论（❌ 那两行）——Windows 默认 cp936
# 控制台下 print 会当场 UnicodeEncodeError，拿到 traceback 而不是 verdict，而且崩在结论行
# 之前留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。
# CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

MAIN_REFS = {"refs/heads/main"}
BLOCK_MSG = (
    "❌ 主仓只允许指挥官 merge 合入，禁止直 push gitcode/main"
    "（违反 AGENTS.md 红线）。请 push 到功能分支 feat/xxx 后通知 lead。"
)


def main() -> int:
    blocked = False
    for line in sys.stdin:
        parts = line.strip().split()
        if len(parts) < 4:
            # Malformed pre-push line: never fail closed on parse errors.
            continue
        remote_ref = parts[2]
        remote_url = parts[4] if len(parts) > 4 else ""
        if remote_ref in MAIN_REFS and re.search(r"gitcode", remote_url, re.IGNORECASE):
            blocked = True
            print(BLOCK_MSG, file=sys.stderr)
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main())
