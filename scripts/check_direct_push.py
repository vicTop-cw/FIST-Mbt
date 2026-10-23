#!/usr/bin/env python3
"""FIST-Mbt pre-push guard: block direct push to gitcode/main.

Reads the pre-push hook stdin format:
    <local-ref> <local-sha> <remote-ref> <remote-oid> [remote-url]

Block condition: remote-ref == refs/heads/main AND remote-url contains "gitcode".
Anything else exits 0 (silent pass).

Standard library only (sys, re). No third-party dependencies.

`--selftest` runs the decision matrix in-process (no git, no network): the block
rule itself is asserted, so the hook's behaviour can be checked without pushing.
This is the cell run_guards' battery executes.
"""

import re
import sys

# BUG-58：守卫的“红”必须是判据红。BLOCK_MSG 含 ❌ 与中文，Windows 默认 GBK 控制台下
# print 会直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。stderr 由调用方钩子转发，
# 此处一并钉住以免 hook stderr 路径在 GBK 下炸（BUG-138 同源）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

MAIN_REFS = {"refs/heads/main"}
BLOCK_MSG = (
    "❌ 主仓只允许指挥官 merge 合入，禁止直 push gitcode/main"
    "（违反 AGENTS.md 红线）。请 push 到功能分支 feat/xxx 后通知 lead。"
)


def decide(lines) -> bool:
    """Pure rule: True = the push must be blocked.

    Malformed lines (<4 fields) are skipped — never fail closed on parse noise.
    """
    blocked = False
    for line in lines:
        parts = line.strip().split()
        if len(parts) < 4:
            continue
        remote_ref = parts[2]
        remote_url = parts[4] if len(parts) > 4 else ""
        if remote_ref in MAIN_REFS and re.search(r"gitcode", remote_url, re.IGNORECASE):
            blocked = True
    return blocked


def selftest() -> int:
    # pre-push stdin 行形状：<local-ref> <local-oid> <remote-ref> <remote-oid> <remote-url>
    # （5 字段；判定读 parts[2]=remote-ref 与 parts[4]=remote-url。上一版 fixture 多写一个
    # 字段 ⇒ remote-ref 落在 oid 上，两格必假红——selftest 自己就是把它抓出来的那只眼。）
    cases = [
        ("refs/heads/main o1 refs/heads/main o2 gitcode.com:V/F.git", True, "直推 gitcode/main 必须拦"),
        ("refs/heads/main o1 refs/heads/main o2 github.com:V/F.git", False, "推 github main 不拦"),
        ("refs/heads/feat/x o1 refs/heads/feat/x o2 gitcode.com:V/F.git", False, "推 feature 分支不拦"),
        ("", False, "空输入 fail-open"),
        ("garbage", False, "畸形行 fail-open"),
        ("refs/heads/main o1 refs/heads/main o2", False, "缺 remote-url 不拦（无从判定）"),
        ("refs/heads/master o1 refs/heads/main o2 GITCODE.com:V/F.git", True, "大小写不敏感"),
    ]
    fails = []
    for line, want, why in cases:
        got = decide([line])
        if got != want:
            fails.append("%s：期望 %s 实回 %s" % (why, want, got))
    if fails:
        print("SELFTEST FAIL：直推拦截语义漂移")
        for f in fails:
            print("  - " + f)
        return 1
    print("SELFTEST OK 直推拦截语义 %d 格全中（拦 gitcode/main / 不拦 github·feature·畸形·空）" % len(cases))
    return 0


def main(argv) -> int:
    if "--selftest" in argv:
        return selftest()
    blocked = decide(sys.stdin)
    if blocked:
        print(BLOCK_MSG, file=sys.stderr)
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
