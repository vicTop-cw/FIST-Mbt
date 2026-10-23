#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/git_sandbox.py — 判据沙箱 git 调用的「宿主隔离」单一真源（R4）。

**为什么要有它**（2026-10-24 实踩 + 主线 `a28be4e1` 同族第二实现坐实的雷类）：本仓多把
`check_*.py` 在 `--selftest` 里用 `tempfile.mkdtemp()`/`TemporaryDirectory` 造合成 git 仓当注入面
（`git init/add/commit`）。当这些尺**被 git 钩子调用**（如 `.githooks/pre-commit` 第 1 步跑
`check_merge_markers --selftest`）时，钩子进程的环境里导出了 `GIT_DIR`/`GIT_INDEX_FILE`/
`GIT_CONFIG_*`（指向宿主仓）。这些是**环境变量级、优先于 `git -C <临时目录>`** 的控制变量 ⇒
沙箱里的 `git add/commit` 会把合成提交 / 暂存内容**写进宿主的 HEAD 与 index**（实测：一次本地
提交被打进三发 `"fixture"` 提交 + 篡改宿主 config `user.*`；`core.bare` 也被同形机制写成 true
导致整类判据崩）。判据必须对环境**无副作用**——所有沙箱 git 调用统一走 `sandbox_env()`。

用法（顶层 `scripts/*.py`）：
    from git_sandbox import sandbox_env
    subprocess.run(["git", "init", "-q"], cwd=d, env=sandbox_env())

`scripts/blackbox/*.py` 引本件需先 `sys.path.insert(0, <scripts 目录>)`（blackbox 的 sys.path[0] 不含顶层）。

普查锁 `check_git_sandbox_hygiene.py` 钉住这个形状：凡「建 git 沙箱（mkdtemp+init/add/commit）却没引
sandbox_env / git_sandbox」的尺发红（存量按棘轮只许降）。

纯 stdlib，零依赖，只定义函数不执行任何 git。
"""
import os

# 会被 git 当作「环境级仓库指针」的控制变量——沙箱必须剥掉，否则 `git -C <临时目录>` 压不过它们。
# 单一真源取**最防御并集**：主线 merge_markers 自带词表（GIT_ENV_SCRUB，含 GIT_CEILING_DIRECTORIES）
# 必须 ⊆ 本表（C8 格对表钉住方向）。本件另在函数体内剥 GIT_CONFIG_*/AUTHOR/COMMITTER 前缀
# + 设 NOSYSTEM，比主线更防御——别的尺按本件接线即可，主线按自己词表剥仓库指针也是根因面。
GIT_CONTROL_VARS = (
    "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX",
    "GIT_NAMESPACE", "GIT_SSH", "GIT_CEILING_DIRECTORIES",
)


def sandbox_env(base=None):
    """造一个「与宿主 git 状态隔离」的 env：剥掉 GIT_* 控制变量、GIT_CONFIG_*、
    GIT_AUTHOR/COMMITTER_*，并设 GIT_CONFIG_NOSYSTEM=1（CI runner 系统级 gitconfig 可能配了
    hooksPath/模板，同样会污染沙箱）。base 可注入（自检造对照用）。返回新 dict，不改传入。"""
    env = dict(base if base is not None else os.environ)
    for k in list(env):
        if (k in GIT_CONTROL_VARS or k.startswith("GIT_CONFIG_")
                or k.startswith("GIT_AUTHOR_") or k.startswith("GIT_COMMITTER_")):
            env.pop(k, None)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    return env
