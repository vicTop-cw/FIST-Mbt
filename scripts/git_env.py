#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/git_env.py —— 夹具跑 git 时的**环境隔离**（R45/R46，事故驱动）。

## 为什么需要这个模块（不是洁癖，是两次真事故）

git 执行钩子（`pre-commit` / `pre-push`）时会向钩子进程注入 `GIT_DIR` / `GIT_WORK_TREE` /
`GIT_INDEX_FILE` 等"仓库定位变量"，它们指向**外层真仓**。判据夹具里常见写法是
`subprocess.run(["git", …], cwd=tempdir)` ——`cwd` 只决定**起点目录**，而上面这些变量**优先级更高**，
于是 git 完全忽略夹具目录、直接操作真仓：

- `git config user.*` 写进**真仓 config**（实测：本仓身份被改成夹具的 `t / t@t`，还原后又被改回）；
- `git add -A` 把夹具文件塞进**真仓索引**；
- `git commit -qm fixture` 在**用户分支**上落提交。

R44 实测后果：某工作树被连写 9 个 `fixture` 提交、整棵树被换成夹具文件。
R45 拿到 A/B 对照：main 版夹具 `--selftest` 在模拟钩子环境下 HEAD 从 `3a715a4c` 变成
`4f4140fe "fixture"`；加了环境隔离后 HEAD 不动。

## 用法

    from git_env import isolated_git_env          # 同目录脚本
    subprocess.run(["git", *args], cwd=d, env=isolated_git_env(), …)

`isolated_git_env()` 返回当前环境的副本并**剥掉** `GIT_ENV_SCRUB` 列出的变量。注意它**不改**
`os.environ`（只返回副本），所以对同一进程里的其它调用零影响。

## 退出码

    python scripts/git_env.py --selftest   # 纯函数自证：设了 GIT_DIR 的环境副本被剥干净
"""
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# git 在钩子/子命令里会注入的仓库定位变量。夹具里出现其中任何一个，都可能让 git 越过 cwd 去操作真仓。
GIT_ENV_SCRUB = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_NAMESPACE",
    "GIT_CEILING_DIRECTORIES",
)


def isolated_git_env(base=None):
    """返回一份剥掉 `GIT_ENV_SCRUB` 的环境副本（默认基于 `os.environ`，不改原环境）。"""
    env = dict(os.environ if base is None else base)
    for k in GIT_ENV_SCRUB:
        env.pop(k, None)
    return env


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    dirty = {
        "GIT_DIR": "/x/.git",
        "GIT_WORK_TREE": "/x",
        "GIT_INDEX_FILE": "/x/.git/index",
        "GIT_PREFIX": "sub/",
        "PATH": "/usr/bin",
        "HOME": "/home/u",
    }
    cleaned = isolated_git_env(dirty)
    cell("scrub-git-dir", "GIT_DIR" in cleaned, False)
    cell("scrub-work-tree", "GIT_WORK_TREE" in cleaned, False)
    cell("scrub-index", "GIT_INDEX_FILE" in cleaned, False)
    cell("scrub-prefix", "GIT_PREFIX" in cleaned, False)
    cell("keep-path", cleaned.get("PATH"), "/usr/bin")
    cell("keep-home", cleaned.get("HOME"), "/home/u")
    # 不改原字典（避免"顺手把别人环境也剥了"这种隐蔽副作用）
    cell("no-mutation-of-input", "GIT_DIR" in dirty, True)
    # 空白环境不炸
    cell("empty-base-ok", isinstance(isolated_git_env({}), dict), True)
    print("SELFTEST %s (%d cells: %s)" % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    if "--selftest" in argv:
        return selftest()
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
