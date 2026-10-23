#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_repo_shape.py — 仓库形态守卫：`core.bare` 等会让整类判据一起崩的设置。

## 为什么要有它（2026-10-24 实测两次）

`.git/config` 的 `[core] bare = true` 被写入后，整仓**工作树语义失效**：

    git rev-parse --is-bare-repository   → true     （应为 false）
    git rev-parse --is-inside-work-tree  → false    （应为 true）
    git ls-files --others                → fatal: this operation must be run in a work tree

后果不是「一个判据红」而是**一整类 git 系判据同时红**，且各自报的文案五花八门
（`operation must be run in a work tree` / `无法判定` / `取不到 git dir` …）
⇒ 最容易被误读成「判据自己坏了」，于是没人去查仓的形态。

本仓是**非 bare 工作仓**（有工作树、有索引、判据要靠它读文件）。所以 `core.bare=true`
不是一种可选配置，而是**故障态**，必须有一把尺专门钉它。

## 判据

- **R1** `core.bare` 必须是 `false`（或未设）。`true` ⇒ 红，并给出修复命令。
- **R2** `git rev-parse --is-inside-work-tree` 必须是 `true`。这是 R1 的独立复算
  （不依赖 `core.bare` 的读法，防「配置读到了但 git 另有判法」）。
- **R3** 判据根（本脚本所在仓）必须**不是 bare 仓库**：`--is-bare-repository` == false。
- **R4** 三面任一读不到（git 缺席 / 非仓 / 命令失败）⇒ **rc=2 自拒**，绝不拿「没读到」当绿。

退出码：0 = 形态正常 / 1 = 形态故障（bare 化等）/ 2 = 判据无法自证。

用法：
    python scripts/check_repo_shape.py [--selftest]
"""
import os
import subprocess
import sys

# BUG-138（BUG-58 同族）：本脚本会打中文结论——Windows cp936 控制台下 print 会当场
# UnicodeEncodeError，拿到 traceback 而不是 verdict。CI 的 UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(args, cwd=None):
    """跑 git，返回 (rc, stdout)。不抛——读不到由调用方按「无法自证」处置。"""
    try:
        p = subprocess.run(
            ["git"] + list(args),
            cwd=cwd or ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.SubprocessError):
        return 1, ""
    return p.returncode, p.stdout.decode("utf-8", "replace").strip()


def judge(cwd):
    """返回 (verdict, problems)。verdict ∈ "ok" / "broken" / "unverifiable"。

    **必须先确认 cwd 就是它自己的工作树根**：git 在子目录里会自动向上找仓，
    非仓目录也可能命中某个祖先仓（本机实测：temp 目录会命中 `C:/Users/<user>`）⇒
    不先钉这一点，「非仓」就会被读成「形态正常」（本节自检抓到过一次）。
    """
    problems = []

    # R1 必须**最先**判：`core.bare=true` 时连 `--show-toplevel` / `--is-inside-work-tree`
    # 都会失败（git 不认这是工作树）⇒ 若先跑形态探测，故障会被读成「无法自证」而不是「形态故障」。
    # 实测：先做 R0 时，人为设 core.bare=true 得到的是 `unverifiable`，R1 永远够不着。
    rc_cfg, bare_cfg = git(["config", "--get", "core.bare"], cwd)
    if rc_cfg not in (0, 1):
        return "unverifiable", ["R4 读不到 core.bare（git config 失败）⇒ 判据无法自证"]
    if rc_cfg == 0 and bare_cfg.strip().lower() == "true":
        return "broken", [
            "R1 `core.bare = true` ⇒ **整仓工作树语义失效**：所有 `git ls-files --others` / "
            "`status` / `worktree` 类判据会以五花八门的文案同时红，最容易被误读成「判据坏了」。"
            "修复：`git config core.bare false`"
        ]

    # R0: 判据根必须是它自己的工作树根（防「向上命中祖先仓」把非仓读成正常）
    rc_top, top = git(["rev-parse", "--show-toplevel"], cwd)
    if rc_top != 0 or not top:
        return "unverifiable", ["R4 读不到 `--show-toplevel`（非仓 / git 不可用）⇒ 判据无法自证"]
    try:
        same = os.path.normcase(os.path.realpath(top)) == os.path.normcase(
            os.path.realpath(cwd)
        )
    except OSError:
        same = False
    if not same:
        return "unverifiable", [
            "R4 %s 不是它自己的工作树根（git 向上命中了 %s）⇒ 判据无法自证" % (cwd, top)
        ]

    # R2: is-inside-work-tree 必须是 true（独立复算，不依赖 R1 的读法）
    rc_ins, inside = git(["rev-parse", "--is-inside-work-tree"], cwd)
    if rc_ins != 0:
        return "unverifiable", [
            "R4 读不到 `--is-inside-work-tree`（git rev-parse 失败）⇒ 判据无法自证"
        ]
    if inside.strip().lower() != "true":
        problems.append(
            "R2 `--is-inside-work-tree` = %r（应为 true）⇒ 当前目录不被 git 当工作树；"
            "与 R1 同源但独立复算" % inside
        )

    # R3: 判据根必须不是 bare 仓库
    rc_bare, is_bare = git(["rev-parse", "--is-bare-repository"], cwd)
    if rc_bare != 0:
        return "unverifiable", [
            "R4 读不到 `--is-bare-repository`（git rev-parse 失败）⇒ 判据无法自证"
        ]
    if is_bare.strip().lower() == "true":
        problems.append(
            "R3 `--is-bare-repository` = true ⇒ 判据根是 bare 仓库，本仓应是非 bare 工作仓"
        )

    return ("broken" if problems else "ok"), problems


def run(_argv):
    verdict, problems = judge(ROOT)
    if verdict == "unverifiable":
        print("FATAL 判据无法自证：%s" % problems[0])
        return 2
    if verdict == "broken":
        print("FAIL 仓库形态异常（会让整类 git 判据一起红，先修形态再谈其它）：")
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS 仓库形态正常：core.bare=false / is-inside-work-tree=true / 非 bare 仓库")
    return 0


def selftest():
    """合成对照：R1/R2/R3 各自能红、干净不误红、读不到自拒。"""
    fails = []
    import tempfile

    def box(bare_cfg=None, init=False):
        d = tempfile.mkdtemp(prefix="reposhape-")
        if init:
            subprocess.run(["git", "init", "-q"], cwd=d, capture_output=True)
        if bare_cfg is not None:
            subprocess.run(
                ["git", "config", "core.bare", bare_cfg], cwd=d, capture_output=True
            )
        return d

    # 干净不误红（真 init 仓，core.bare 未设 = false）
    d_ok = box(init=True)
    v, ps = judge(d_ok)
    if v != "ok":
        fails.append("干净 init 仓被误判：%s %s" % (v, ps))

    # R1 必红：显式 core.bare=true（注：真 bare 化后 git 多数命令会拒，故用 config 造态）
    d_bad = box(bare_cfg="true", init=True)
    v2, ps2 = judge(d_bad)
    if not any("R1" in p for p in ps2):
        fails.append("core.bare=true 却没报 R1：%s / %s" % (v2, ps2))

    # 非仓目录 ⇒ 无法自证
    d_none = box()
    v3, _ = judge(d_none)
    if v3 != "unverifiable":
        fails.append("非仓目录应 unverifiable，实得 %s" % v3)

    # git 缺席模拟：不真造（环境不可控），改判「judge 不抛异常」
    try:
        judge(ROOT)
    except Exception as e:  # noqa: BLE001
        fails.append("judge 在真仓上抛异常：%r" % e)

    # 清理
    import shutil

    for d in (d_ok, d_bad, d_none):
        shutil.rmtree(d, ignore_errors=True)

    if fails:
        print("SELFTEST FAIL：")
        for f in fails:
            print("  - " + f)
        return 1
    print("SELFTEST OK：R1 bare 必红 / 干净 init 仓不误红 / 非仓自拒 / 真仓不抛")
    return 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    return run(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
