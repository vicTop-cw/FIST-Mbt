#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/install_git_hooks.py — 安装/核对本仓 git 钩子（TASK-001② 的"装上"这一半）。

**为什么需要它**：`.githooks/pre-commit` 早在仓里，但 `core.hooksPath` 从未被设置 ⇒ **钩子默认不生效**，
TASK-001 里"每个 commit 合入前自动跑 check_merge_markers"这条其实一直没落到本地提交面
（CI 那步只管推送后）。实测：`git config --get core.hooksPath` 为空。
本脚本把"装钩子"变成一条可复现命令，并提供 `--check` 供守卫/CI 核对，避免"文件在、没生效"。

用法：
  python scripts/install_git_hooks.py --check     # 只核对（0=已生效 / 1=未生效且可安装 / 2=环境不完整）
  python scripts/install_git_hooks.py --install   # 设置 core.hooksPath=.githooks 并校验可执行位
退出码：0 已就绪 / 1 未就绪（--install 时失败也算）/ 2 判据无法自证（缺 .githooks 或缺 git）
"""
import os
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HOOKS_REL = ".githooks"
REQUIRED = ("pre-commit",)


def git(*args):
    return subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def state():
    """返回 (ok, lines)。ok=True 仅当 hooksPath 指向 .githooks 且必需钩子都在。"""
    lines = []
    hooks_dir = os.path.join(ROOT, HOOKS_REL)
    if not os.path.isdir(hooks_dir):
        return False, ["FATAL：缺少 %s/ —— 判据无法自证，拒绝报'已就绪'" % HOOKS_REL]
    missing = [h for h in REQUIRED if not os.path.isfile(os.path.join(hooks_dir, h))]
    if missing:
        return False, ["缺少钩子文件：%s" % ", ".join(missing)]
    r = git("config", "--get", "core.hooksPath")
    if r.returncode != 0:
        return False, ["core.hooksPath 未设置 ⇒ 钩子存在但**不生效**（这正是 TASK-001② 的缺口）"]
    val = (r.stdout or "").strip()
    if val.replace("\\", "/").rstrip("/") != HOOKS_REL:
        return False, ["core.hooksPath=%r 未指向 %s" % (val, HOOKS_REL)]
    lines.append("core.hooksPath=%s，钩子齐全：%s" % (val, ", ".join(REQUIRED)))
    return True, lines


def install():
    r = git("config", "core.hooksPath", HOOKS_REL)
    if r.returncode != 0:
        print("FAIL：设置 core.hooksPath 失败：%s" % (r.stderr or r.stdout).strip()[:200])
        return 1
    print("OK：已设置 core.hooksPath=%s" % HOOKS_REL)
    # 可执行位：Git for Windows 会忽略，POSIX 上必须有
    for h in REQUIRED:
        p = os.path.join(ROOT, HOOKS_REL, h)
        try:
            mode = os.stat(p).st_mode
            os.chmod(p, mode | 0o111)
        except OSError as e:
            print("WARN：无法设置可执行位 %s：%s（Windows 上无妨；POSIX 上需手动 chmod +x）" % (h, e))
    ok, lines = state()
    for l in lines:
        print(("PASS " if ok else "FAIL ") + l)
    return 0 if ok else 1


def main():
    args = sys.argv[1:]
    if "--install" in args:
        return install()
    ok, lines = state()
    for l in lines:
        print(("PASS " if ok else "FAIL ") + l)
    if ok:
        return 0
    print("提示：跑 `python scripts/install_git_hooks.py --install` 装上（幂等）")
    return 2 if any(l.startswith("FATAL") for l in lines) else 1


if __name__ == "__main__":
    sys.exit(main())
