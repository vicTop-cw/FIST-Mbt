#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_master_mirror.py —— `master` 镜像落后的判据/对齐器（R180）。

## 为什么需要它（同一个动作做了 4 次，第 5 次还是落后）

`gitcode/master` 是个**历史基线镜像**，`gitcode` 的默认分支是它（服务端拒绝删除），
所以**任何只看默认分支的人/工具读到的都是旧基线**。而 main 一直由统帅 cherry-pick 推进，
**没有任何自动化在维护 master**（实测：`.github/workflows/` 里 `refs/heads/master` 零命中）。

于是每轮 main 一推进，master 就落后，人工再补一次：

```
54094672 → 落后 → 对齐
b2dccccb → 落后 → 对齐
3897d378 → 落后 → 对齐
95d71100 → 落后 → 对齐
ffee8d52 → 落后 → 对齐    ← 本脚本诞生的那一次
```

这不是"某次忘了推"，是**缺少一个把这件事变成可执行命令的入口**。本脚本补这个入口。

## 两个模式

- **默认（判据模式）**：只读。报告每个远端的 `master` 是否 == `main`，落后多少笔，
  **以及能不能快进**。`rc=0` 一致 / `rc=1` 落后（逐条点名）/ `rc=2` 判据无法自证
  （git 不可用、读不到远端 ref）。
- **`--apply`（对齐模式）**：把 `master` 推到 `main` 的位置。**只有验证过快进才推**。

## 安全契约（这是本脚本存在的全部理由）

**绝不 force。** 推之前必须满足三条，任一条不满足就**拒绝并给出读数**：

1. `<master-sha>` 是 `<main-sha>` 的**祖先**（`git merge-base --is-ancestor` = 真）
   ⇒ 快进，不丢任何提交；
2. 远端 `master` 仍是**我们刚读到的那一个** sha（推送前复读，防他人并发推）；
3. `--apply` 必须**显式给出**，且不接受 `--force` 这个旗标（给了就是参数错误）。

为什么第 2 条要有：`--force-with-lease` 的理念，但这里**连 lease 都不用**——真正的快进 push
本来就不需要 force，git 自己会拒非快进。第 2 条的用处是**在推之前把并发说清楚**，而不是
靠 git 的报错事后才知道。

## `--dry-run`

只报读数不推送（`--apply --dry-run` 时把「会推什么」打出来但不执行）。
默认模式本身就已经是只读的，`--dry-run` 让它显式化，便于在 CI/巡检脚本里写意图。

## 为什么没接 CI（诚实标注）

`ci.yml` 的 `permissions: contents: read` —— **CI 没有写权限**，接进去只能 dry-run，
那和本脚本手跑没区别。真要自动化，需要 owner 决定是否给 `contents: write` 并加一个
`if: github.ref == 'refs/heads/main'` 的推送 job —— 那是**权限决策**，不在本单元。
所以本脚本当前是「人/巡检用的一条命令」，不是 CI 步骤，也就**不会**碰
`check_ci_step_position` 的 `POSITION_WHY_CEILING`。

## 退出码

0 = 所有远端 master 已与 main 一致（或 `--apply` 后已对齐）
1 = 有远端 master 落后（判据模式）/ 快进验证失败而拒绝（`--apply` 模式）
2 = 判据无法自证（git 不可用、远端 ref 读不到、远端集合为空）
4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）

用法：
    python scripts/check_master_mirror.py                    # 只读判据
    python scripts/check_master_mirror.py --dry-run          # 同上，显式只读
    python scripts/check_master_mirror.py --apply --dry-run  # 报「会推什么」，不推
    python scripts/check_master_mirror.py --apply            # 真对齐（只快进）
    python scripts/check_master_mirror.py --selftest
"""
import argparse
import os
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from git_env import isolated_git_env  # noqa: E402

DEFAULT_REMOTES = ("gitcode", "origin")
MIRROR_REF = "refs/heads/master"
SOURCE_REF = "refs/heads/main"


# ── 纯函数（可单测，不依赖 git）─────────────────────────────────────────────────────


def classify(master_sha, main_sha, is_ancestor):
    """纯函数：给一个远端镜像的三种状态。

    - `same`       : master == main               （rc 视角：健康）
    - `fast_forward`: master 是 main 祖先 ⇒ 可安全快进（落后 N 笔）
    - `diverged`   : 不是祖先 ⇒ **拒绝**，绝不 force（这是本脚本的硬线）

    Args:
        master_sha: 远端 master 当前 sha（空串 = 读不到）
        main_sha:   远端 main 当前 sha（空串 = 读不到）
        is_ancestor: `git merge-base --is-ancestor master main` 的布尔结果

    Returns:
        (state, reason) —— state ∈ {"unverifiable","same","fast_forward","diverged"}
    """
    if not master_sha or not main_sha:
        return ("unverifiable", "远端 ref 读不到")
    if master_sha == main_sha:
        return ("same", "master 与 main 同 sha")
    if is_ancestor:
        return ("fast_forward", "master 是 main 的祖先")
    return ("diverged", "master 不是 main 的祖先（非快进）⇒ 拒绝推送，绝不 force")


def plan_action(state):
    """纯函数：给定状态，决定动作。`push` 只在 fast_forward 时成立。

    这条是**安全契约的代码化**：`diverged` 永远拿不到 `push`。
    """
    if state == "fast_forward":
        return "push"
    if state == "same":
        return "noop"
    return "refuse"


# ── git 层 ─────────────────────────────────────────────────────────────────────


def _git(args, cwd=None, env=None):
    p = subprocess.run(
        ["git", *args],
        cwd=cwd or ROOT,
        capture_output=True,
        env=env if env is not None else isolated_git_env(),
    )
    return (p.returncode,
            (p.stdout or b"").decode("utf-8", "replace").strip(),
            (p.stderr or b"").decode("utf-8", "replace").strip())


def remote_sha(remote, ref, cwd=None, env=None):
    """读远端某个 ref 的 sha。读不到返回空串（调用方按 unverifiable 处理，绝不猜）。"""
    rc, out, _ = _git(["ls-remote", remote, ref], cwd=cwd, env=env)
    if rc != 0 or not out:
        return ""
    return out.split()[0]


def is_ancestor(anc, desc, cwd=None, env=None):
    """`anc` 是否是 `desc` 的祖先。非零 rc **不等于** False——但这里两者都按保守处理。

    注意：`merge-base --is-ancestor` 的 rc 语义是 0=是 / 1=不是 / 其它=错误。
    错误时我们**不能**说"是祖先"（那会导致误推），但也**不能**说"不是祖先"就够——
    调用方看到 False 会走 diverged 分支 ⇒ refuse。保守方向正确。
    """
    rc, _, _ = _git(["merge-base", "--is-ancestor", anc, desc], cwd=cwd, env=env)
    return rc == 0


def inspect(remotes=DEFAULT_REMOTES, cwd=None, env=None):
    """对每个远端算一张表。返回 (rows, fatal_reason)。

    rows 每项：{remote, master, main, state, why, action}
    """
    rows, unreadable = [], []
    for r in remotes:
        m = remote_sha(r, MIRROR_REF, cwd=cwd, env=env)
        n = remote_sha(r, SOURCE_REF, cwd=cwd, env=env)
        if not m or not n:
            unreadable.append(r)
            rows.append({"remote": r, "master": m or "?", "main": n or "?",
                         "state": "unverifiable", "why": "远端 ref 读不到",
                         "action": "refuse"})
            continue
        anc = is_ancestor(m, n, cwd=cwd, env=env)
        state, why = classify(m, n, anc)
        rows.append({"remote": r, "master": m, "main": n,
                     "state": state, "why": why, "action": plan_action(state)})
    if unreadable and len(unreadable) == len(remotes):
        return rows, "全部远端都读不到（网络/权限）⇒ 判据无法自证"
    return rows, ""


def apply_ff(rows, dry_run=False, cwd=None, env=None):
    """对 `action == push` 的行执行快进推送。返回 (done, failed) 两个列表。

    推之前**复读一次**远端 master，确认还是我们刚看到的那一个（并发防护）。
    """
    done, failed = [], []
    for row in rows:
        if row["action"] != "push":
            continue
        r = row["remote"]
        if dry_run:
            done.append("%s: (dry-run) 将推 %s -> refs/heads/master" % (r, row["main"][:12]))
            continue
        now = remote_sha(r, MIRROR_REF, cwd=cwd, env=env)
        if now != row["master"]:
            failed.append("%s: 远端 master 在判据与推送之间变了（%s -> %s）⇒ 拒绝，请重跑"
                          % (r, row["master"][:12], (now or "?")[:12]))
            continue
        rc, out, err = _git(["push", r, "%s:refs/heads/master" % row["main"]],
                            cwd=cwd, env=env)
        if rc == 0:
            done.append("%s: %s" % (r, (out or "").splitlines()[-1] if out else "ok"))
        else:
            failed.append("%s: push 失败 rc=%d %s" % (r, rc, (err or "")[:200]))
    return done, failed


# ── 自证 ───────────────────────────────────────────────────────────────────────


def _fixture_repo(tmp):
    """造一个「本地仓 + 两个裸远端」的夹具，模拟 master 落后 main 的真实形态。

    全部经 `isolated_git_env()`，绝不碰真仓。返回 (work, bare_gitcode, bare_origin)。
    """
    env = isolated_git_env()

    def g(*args, cwd=tmp):
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True, env=env)

    work = os.path.join(tmp, "work")
    bare1 = os.path.join(tmp, "gitcode.git")
    bare2 = os.path.join(tmp, "origin.git")
    os.makedirs(work)
    for b in (bare1, bare2):
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", b], capture_output=True, env=env)

    for args in (["init", "-q", "-b", "main"],
                 ["config", "user.name", "t"], ["config", "user.email", "t@t"],
                 ["config", "commit.gpgsign", "false"]):
        g(*args, cwd=work)
    with open(os.path.join(work, "a.txt"), "w", encoding="utf-8") as f:
        f.write("1\n")
    g("add", "a.txt", cwd=work)
    g("commit", "-q", "-m", "c1", cwd=work)
    first = subprocess.run(["git", "rev-parse", "HEAD"], cwd=work,
                           capture_output=True, env=env).stdout.decode().strip()
    # 两个远端都有 main 与 master，且都停在 c1（一致起点）
    for b in (bare1, bare2):
        g("push", "-q", b, "HEAD:refs/heads/main", cwd=work)
        g("push", "-q", b, "HEAD:refs/heads/master", cwd=work)
    # 再推进一笔 ⇒ main 前进，master 留在 c1（= 落后 1 笔的真实形态）
    with open(os.path.join(work, "b.txt"), "w", encoding="utf-8") as f:
        f.write("2\n")
    g("add", "b.txt", cwd=work)
    g("commit", "-q", "-m", "c2", cwd=work)
    second = subprocess.run(["git", "rev-parse", "HEAD"], cwd=work,
                            capture_output=True, env=env).stdout.decode().strip()
    for b in (bare1, bare2):
        g("push", "-q", b, "HEAD:refs/heads/main", cwd=work)
    return work, bare1, bare2, first, second


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # ── 纯函数格：classify 四态 + plan_action 的硬线 ──────────────────────────
    cell("classify-same", classify("abc", "abc", True)[0], "same")
    cell("classify-same-even-if-ancestor-flag-false", classify("abc", "abc", False)[0], "same")
    cell("classify-fast-forward", classify("old", "new", True)[0], "fast_forward")
    cell("classify-diverged", classify("old", "new", False)[0], "diverged")
    cell("classify-unverifiable-empty-master", classify("", "new", False)[0], "unverifiable")
    cell("classify-unverifiable-empty-main", classify("old", "", True)[0], "unverifiable")
    # 安全硬线：diverged 永远拿不到 push
    cell("plan-same-noop", plan_action("same"), "noop")
    cell("plan-ff-push", plan_action("fast_forward"), "push")
    cell("plan-diverged-refuse", plan_action("diverged"), "refuse")
    cell("plan-unverifiable-refuse", plan_action("unverifiable"), "refuse")

    # ── 端到端格：真裸远端，真 git 调用（全部 isolated_git_env）──────────────
    tmp = tempfile.mkdtemp(prefix="fist-master-mirror-")
    try:
        work, bare1, bare2, first, second = _fixture_repo(tmp)
        remotes = (bare1, bare2)

        # 落后态：master=c1, main=c2, c1 是 c2 祖先 ⇒ fast_forward
        rows, fatal = inspect(remotes, cwd=work)
        cell("e2e-inspect-not-fatal", fatal, "")
        cell("e2e-lag-detected-fast-forward", rows[0]["state"], "fast_forward")
        cell("e2e-lag-action-is-push", rows[0]["action"], "push")
        cell("e2e-lag-counted-two-remotes", len(rows), 2)

        # dry-run：只报不推 ⇒ 远端 master 不动
        done, failed = apply_ff(rows, dry_run=True, cwd=work)
        cell("e2e-dry-run-reports-both", len(done), 2)
        cell("e2e-dry-run-pushes-nothing", remote_sha(bare1, MIRROR_REF, cwd=work), first)

        # 真推：master 应变成 c2
        rows, _ = inspect(remotes, cwd=work)
        done, failed = apply_ff(rows, dry_run=False, cwd=work)
        cell("e2e-apply-no-failures", failed, [])
        cell("e2e-apply-moved-master", remote_sha(bare1, MIRROR_REF, cwd=work), second)
        cell("e2e-apply-moved-master-2", remote_sha(bare2, MIRROR_REF, cwd=work), second)

        # 推完再判：应当全部 same，且没有 push 动作
        rows, _ = inspect(remotes, cwd=work)
        cell("e2e-after-apply-same", [r["state"] for r in rows], ["same", "same"])
        cell("e2e-after-apply-no-push", [r["action"] for r in rows], ["noop", "noop"])

        # 分叉态：让 master 有一个 main 里没有的提交 ⇒ 必须 refuse，且推送不生效
        env = isolated_git_env()
        subprocess.run(["git", "checkout", "-q", "-b", "side", first], cwd=work, capture_output=True, env=env)
        with open(os.path.join(work, "side.txt"), "w", encoding="utf-8") as f:
            f.write("x\n")
        subprocess.run(["git", "add", "side.txt"], cwd=work, capture_output=True, env=env)
        subprocess.run(["git", "commit", "-q", "-m", "diverge"], cwd=work, capture_output=True, env=env)
        side = subprocess.run(["git", "rev-parse", "HEAD"], cwd=work,
                              capture_output=True, env=env).stdout.decode().strip()
        subprocess.run(["git", "push", "-q", "-f", bare1, "%s:refs/heads/master" % side],
                       cwd=work, capture_output=True, env=env)  # 夹具造分叉，仅对临时裸库

        rows, _ = inspect((bare1,), cwd=work)
        cell("e2e-diverged-detected", rows[0]["state"], "diverged")
        cell("e2e-diverged-refuses", rows[0]["action"], "refuse")
        done, failed = apply_ff(rows, dry_run=False, cwd=work)
        cell("e2e-diverged-pushes-nothing", (done, failed), ([], []))
        cell("e2e-diverged-master-unchanged", remote_sha(bare1, MIRROR_REF, cwd=work), side)

        # 入口面（J2 口径）：真调 main(["--selftest"])，钉住 rc==0。
        if not _ENTRY_PROBED[0]:
            _ENTRY_PROBED[0] = True
            try:
                cell("entry-main-selftest-rc0", main(["--selftest"]), 0)
            finally:
                _ENTRY_PROBED[0] = False
    finally:
        import shutil as _sh
        _sh.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s (%d cells: %s)"
          % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


# 入口自证的一次性哨兵（防止 `main(["--selftest"])` 随递归层层重入）
_ENTRY_PROBED = [False]


# ── 入口 ───────────────────────────────────────────────────────────────────────


def run(argv):
    if "--force" in argv or "--force-with-lease" in argv:
        print("REFUSED 本脚本**不支持** force：master 镜像只允许快进。"
              "若已分叉，请人工判断后手动处理（非快进对齐意味着丢提交）")
        return 1

    ap = argparse.ArgumentParser(
        description="master 镜像是否落后 main（判据 + 只快进对齐器）")
    ap.add_argument("--selftest", action="store_true", help="自证（临时裸远端端到端）")
    ap.add_argument("--apply", action="store_true", help="真对齐（只快进，绝不 force）")
    ap.add_argument("--dry-run", action="store_true", help="只报读数不推送")
    ap.add_argument("--remote", action="append", default=None,
                    help="限定远端（可重复）；缺省 gitcode + origin")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    remotes = tuple(args.remote) if args.remote else DEFAULT_REMOTES
    rows, fatal = inspect(remotes)
    if fatal:
        print("FATAL " + fatal)
        return 2

    for r in rows:
        print("REMOTE %-8s master=%s main=%s  state=%-13s  %s"
              % (r["remote"], r["master"][:12], r["main"][:12], r["state"], r["why"]))

    pushing = [r for r in rows if r["action"] == "push"]
    refused = [r for r in rows if r["action"] == "refuse"]

    if args.apply:
        done, failed = apply_ff(rows, dry_run=args.dry_run)
        for d in done:
            print("APPLY " + d)
        for f in failed:
            print("APPLY-FAIL " + f)
        if failed:
            return 1
        if args.dry_run:
            print("DRY-RUN 未推送任何东西")
            return 0 if not refused else 1
        return 0 if not refused else 1

    if refused:
        for r in refused:
            print("FAIL %s 的 master 不能自动对齐（%s）⇒ 拒绝推送、绝不 force；请人工判断"
                  % (r["remote"], r["why"]))
        return 1
    if pushing:
        print("FAIL master 落后 main：%d 个远端待对齐。修法：`python scripts/check_master_mirror.py --apply`"
              "（先 --dry-run 看动作）" % len(pushing))
        return 1
    print("PASS 所有远端 master 均与 main 一致（%s）" % ", ".join(remotes))
    return 0


def main(argv):
    return run(argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
