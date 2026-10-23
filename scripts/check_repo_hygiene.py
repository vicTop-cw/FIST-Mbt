#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_repo_hygiene.py —— 「仓库自身卫生」判据（R45）。

## 为什么需要这一把（两次真事故，都发生在同一家族）

1. 2026-10-24（R44）：某判据夹具的 `git config user.*` / `git add -A` / `git commit` 没落在夹具目录里，
   git 按常规**向上找到外层仓库** ⇒ 真工作树被连写 9 个 `fixture` 提交、整棵树被换成夹具文件，
   且**本仓 repo config 的 user.name/email 被改成夹具身份 `t / t@t`**。
2. 同期主干事故：`3a715a4c fix(git): core.bare 被误设为 true ⇒ 主仓库退化成 bare，所有 worktree 操作全挂`。

这两件事的共同点是：**判据/夹具脚本会写 git 配置**，而当时没有任何一把尺盯「真仓自己的配置对不对」。
于是坏掉的是"整个仓库的可用性"，报错却很晚（等到某次 worktree 操作才炸）。本尺补这一面。

## 判据（三格，全部只看本仓 config / 仓库形态，零网络、零写盘）

- **H1 不是 bare**：`git rev-parse --is-bare-repository` 必须是 `false`。
  bare 形态下 `git worktree` 全线不可用（主干那次事故就是它）。
- **H2 本仓身份不是夹具身份**：repo-local `user.name` / `user.email` 不得是 `t` / `t@t`。
  这对身份是判据夹具自己用的；出现在**本仓**配置里，就是"某个夹具的 git config 落到了这里"的物证。
- **H3 hooksPath 指向跟踪面（只报不判）**：`core.hooksPath` 应等于 `.githooks`（pre-commit 拦冲突标记、
  pre-push 拦直推 main）。**但不能判红**：repo-local 配置**不随 clone 走**，干净克隆天然没有它——
  判红就等于"每个新克隆刚拉下来就是红的"。所以这格只打 `WARN` 并给出装法，不计入失败。

## 退出码

0 = H1/H2 通过（H3 可带 WARN）/ 1 = H1 或 H2 违例（逐格点名）/ 2 = 判据无法自证（不是 git 仓库）。

用法：
    python scripts/check_repo_hygiene.py
    python scripts/check_repo_hygiene.py --selftest
"""
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

FIXTURE_IDENTITIES = ("t", "t@t")
EXPECTED_HOOKS_PATH = ".githooks"


def is_fixture_identity(value):
    """纯函数：给定 user.name 或 user.email，是否是判据夹具的身份（不区分大小写、去空白）。"""
    return (value or "").strip().lower() in FIXTURE_IDENTITIES


def hooks_path_ok(value):
    """纯函数：core.hooksPath 是否指向跟踪面 `.githooks`（允许前导 `./`）。"""
    v = (value or "").strip().replace("\\", "/")
    while v.startswith("./"):
        v = v[2:]
    return v.rstrip("/") == EXPECTED_HOOKS_PATH


def git(*args):
    p = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # H2 纯函数：夹具身份识别（正例三格 + 反例三格，防"宽到把真人身份也判红"）
    cell("fixture-identity-t-name", is_fixture_identity("t"), True)
    cell("fixture-identity-t-email", is_fixture_identity("t@t"), True)
    cell("fixture-identity-upper", is_fixture_identity(" T "), True)
    cell("fixture-identity-real-ok", is_fixture_identity("fist-bot"), False)
    cell("fixture-identity-email-real", is_fixture_identity("fist-bot@local"), False)
    cell("fixture-identity-empty", is_fixture_identity(""), False)
    # H3 纯函数：hooksPath 三形（正例 / 前导 ./ / 反例）
    cell("hooks-path-plain", hooks_path_ok(".githooks"), True)
    cell("hooks-path-dot-slash", hooks_path_ok("./.githooks"), True)
    cell("hooks-path-backslash", hooks_path_ok(".githooks/"), True)
    cell("hooks-path-wrong", hooks_path_ok("githooks"), False)
    cell("hooks-path-empty", hooks_path_ok(""), False)
    print("SELFTEST %s (%d cells: %s)" % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    rc, bare, _ = git("rev-parse", "--is-bare-repository")
    if rc != 0:
        print("FATAL 判据无法自证：这里不是 git 工作树（`rev-parse` 失败）⇒ 拒绝出绿灯")
        return 2
    problems = []
    # H1 非 bare
    if bare.lower() != "false":
        problems.append(
            "H1 本仓处于 bare 形态（core.bare=%s）⇒ `git worktree` 全线不可用。"
            "修法：`git config core.bare false`（主干 3a715a4c 就是这么救回来的）" % (bare or "空")
        )
    # H2 本仓身份不是夹具身份
    _, uname, _ = git("config", "--local", "user.name")
    _, uemail, _ = git("config", "--local", "user.email")
    for label, val in (("user.name", uname), ("user.email", uemail)):
        if is_fixture_identity(val):
            problems.append(
                "H2 本仓 repo config 的 %s=%r 是**判据夹具的身份** ⇒ 说明某个夹具的 `git config` 落到了真仓"
                "（R44 实测事故：工作树被连写 9 个 fixture 提交）。修法：`git config %s <本项目身份>`，"
                "并把该夹具的 cwd 钉死在自己的临时目录" % (label, val, label)
            )
    # H3 hooksPath 指向跟踪面（只报不判：clone 不继承 repo-local 配置，干净克隆天然没有）
    _, hp, _ = git("config", "--local", "core.hooksPath")
    if not hooks_path_ok(hp):
        print("WARN H3 core.hooksPath=%r 未指向跟踪面 `%s` —— pre-commit/pre-push 钩子当前不生效。"
              "修法：`python scripts/install_git_hooks.py`（或 `git config core.hooksPath %s`）。"
              "本格只报不判：新建克隆本来就没有 repo-local 配置。"
              % (hp, EXPECTED_HOOKS_PATH, EXPECTED_HOOKS_PATH))
    if problems:
        print("FAIL 仓库自身卫生不合格（判据面：bare / 夹具身份 / hooksPath）：")
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS 仓库卫生：非 bare / 本仓身份不是夹具身份 / hooksPath=%(h)s（WARN 档，见上）"
          % {"u": uname or "(未设，用全局)", "h": hp})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
