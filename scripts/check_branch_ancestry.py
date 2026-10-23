#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_branch_ancestry.py — PR 分支「失基」检测（R66 / TASK-BRANCH-ANCESTRY-201）。

## 为什么需要它（2026-10-23 实测，代价是 2 小时）
主线被重写（`92d0edba` → `788c5823`，`memory/2026-10-22.md` 那 613MB 事故的收口）之后，
**早先开出的 PR 分支基点成了孤儿**：`git merge` 直接

    fatal: refusing to merge unrelated histories

于是「分支绿、尺全过、merge-tree 报无冲突」的一个 PR，**物理上合并不了**，合并机器人只能空转。
更坑的是 `git merge-tree --write-tree` 不校验历史相关性——它给"无冲突"，让人以为随时能合。

## 判据
对每个候选分支（默认 = 远端分支里「有 main 之外提交」的那些）：

| 分类 | 判据 | 含义 |
|---|---|---|
| `merged` | 分支 tip 是 main 祖先 | 已并入，无需动作 |
| `mergeable` | `git merge-base main branch` 非空 | 有共同祖先 ⇒ 能三方合并 |
| `orphan` | merge-base 为空 | **失基**：`git merge` 会报 unrelated histories ⇒ 必须按当前 main 重开分支 |

rc 契约：`0` 无 orphan / `1` 检出 orphan（逐支点名并给重开命令）/ `2` 无法测量（取不到 main 或分支集为空）。

## 用法
  python scripts/check_branch_ancestry.py                       # 默认主线 gitcode/main，扫全部远端分支
  python scripts/check_branch_ancestry.py --main origin/master
  python scripts/check_branch_ancestry.py --branches a,b,c       # 只查指定分支
  python scripts/check_branch_ancestry.py --selftest
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DEFAULT_MAINS = ("gitcode/main", "origin/master", "main", "master")


def git(args, cwd):
    p = subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()


def classify(cwd, main, branch):
    """返回 (kind, detail)。kind ∈ {merged, mergeable, orphan, missing}。"""
    rc, _o, _e = git(["rev-parse", "--verify", "--quiet", branch], cwd)
    if rc != 0:
        return "missing", "分支不存在"
    rc, _o, _e = git(["merge-base", "--is-ancestor", branch, main], cwd)
    if rc == 0:
        return "merged", "tip 已是主线祖先"
    rc, out, _e = git(["merge-base", main, branch], cwd)
    if rc != 0 or not out:
        return "orphan", "无共同祖先（git merge 会拒绝 unrelated histories）"
    ahead = int(git(["rev-list", "--count", "%s..%s" % (main, branch)], cwd)[1] or "0" or 0)
    return "mergeable", "共同祖先 %s，领先 %d 个提交" % (out[:8], ahead)


def pick_main(cwd, want=None):
    for cand in ([want] if want else []) + list(DEFAULT_MAINS):
        if not cand:
            continue
        if git(["rev-parse", "--verify", "--quiet", cand], cwd)[0] == 0:
            return cand
    return None


def list_candidates(cwd, main):
    """候选分支：远端 + 本地里「有 main 之外提交」的那些（已并入的不必体检）。

    第一版只扫 refs/remotes，自检仓没配 remote 便一格不取（假阴性），真仓里用 worktree 开的本地分支也漏。
    现在两类都扫：远端用全名（`origin/x`），本地分支用短名。
    """
    cands = []
    for ns in ("refs/remotes", "refs/heads"):
        rc, out, _e = git(["for-each-ref", "--format=%(refname:short)", ns], cwd)
        if rc != 0:
            continue
        for ref in out.splitlines():
            ref = ref.strip()
            if not ref or ref.endswith("/HEAD"):
                continue
            if ref in DEFAULT_MAINS:
                continue
            n = git(["rev-list", "--count", "%s..%s" % (main, ref)], cwd)[1]
            if n.isdigit() and int(n) > 0 and ref not in cands:
                cands.append(ref)
    return cands


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    d = tempfile.mkdtemp(prefix="ancestry-")

    def g(*a):
        return subprocess.run(["git"] + list(a), cwd=d, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")

    def w(p, s):
        full = os.path.join(d, p)
        os.makedirs(os.path.dirname(full) or d, exist_ok=True)
        open(full, "w", encoding="utf-8", newline="\n").write(s)

    try:
        g("init", "-q", "-b", "main", ".")
        g("config", "user.email", "t@t")
        g("config", "user.name", "t")
        w("a.txt", "1\n")
        g("add", "-A"); g("commit", "-qm", "c1")

        # ① mergeable：从 main 开一支并加提交
        g("checkout", "-q", "-b", "feat/ok")
        w("b.txt", "2\n"); g("add", "-A"); g("commit", "-qm", "b")
        cell("classify-mergeable", classify(d, "main", "feat/ok")[0], "mergeable")
        cell("candidates-include-ok", "feat/ok" in list_candidates(d, "main"), True)

        # ② merged：把该分支合进 main
        g("checkout", "-q", "main"); g("merge", "-q", "--no-ff", "-m", "m", "feat/ok")
        cell("classify-merged", classify(d, "main", "feat/ok")[0], "merged")

        # ③ orphan：另起一个**无共同祖先**的根（--orphan + 独立提交）
        g("checkout", "-q", "--orphan", "feat/orphan")
        g("rm", "-rq", "--cached", ".")
        w("z.txt", "z\n"); g("add", "-A"); g("commit", "-qm", "orphan-root")
        cell("classify-orphan", classify(d, "main", "feat/orphan")[0], "orphan")

        # ④ 不存在的分支
        cell("classify-missing", classify(d, "main", "feat/nope")[0], "missing")

        # ⑤ 候选枚举：orphan 有 main 之外的提交 ⇒ 必须被列为候选
        cell("candidates-include-orphan", "feat/orphan" in list_candidates(d, "main"), True)
    finally:
        shutil.rmtree(d, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：mergeable / merged / orphan / missing 四分类 + 候选枚举含 orphan）"
          % len(cells))
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--main", default="")
    ap.add_argument("--branches", default="")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    main_ref = pick_main(ROOT, args.main or None)
    if not main_ref:
        print("  判据无法自证：取不到任何主线 ref（试过 %s）" % ", ".join(DEFAULT_MAINS))
        return 2
    if args.branches.strip():
        cands = [b.strip() for b in args.branches.split(",") if b.strip()]
    else:
        cands = list_candidates(ROOT, main_ref)
    if not cands:
        print("  判据无法自证：没有候选分支（main=%s）——空扫描不算绿" % main_ref)
        return 2

    orphans = []
    for b in cands:
        kind, detail = classify(ROOT, main_ref, b)
        tag = {"merged": "已并入", "mergeable": "可合并", "orphan": "**失基**", "missing": "缺失"}[kind]
        print("  %-44s %-8s %s" % (b, tag, detail))
        if kind == "orphan":
            orphans.append(b)

    if orphans:
        print("\nFAIL %d 支分支**失基**（main 被重写后基点成了孤儿）——`git merge` 会报 unrelated histories：" % len(orphans))
        for b in orphans:
            print("  - %s" % b)
        print("  处置：按当前 %s 重开分支，把该分支的提交重放上去（cherry-pick 或按文件取版本），"
              "别等合并机器人——它合不动。" % main_ref)
        return 1
    print("\nPASS %d 支分支全部可合并或已并入（main=%s）" % (len(cands), main_ref))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
