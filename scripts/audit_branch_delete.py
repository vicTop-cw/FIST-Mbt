#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/audit_branch_delete.py — 通道分支删除前的**硬门 + 审计**（R50）。

**为什么需要它**（2026-10-22 实测）：`slave-branch-merge.ps1` 的清理段曾经
① 用本地 `HEAD` 当基线、② 用 commit message 撞车判"已合并"，于是把**未交付**的分支
`git push --delete` 掉（实测 4 支：dist-snapshot-guard / orphan-rhop-test-compile-red /
battery-readonly / task-004-…，内容一行也没进远端）。判据已在 R45/R46 修成
"远端基线 + 内容等价"，但仍然**没有留痕**：删掉的到底合没合，事后无法复盘。

本脚本把"删之前必须能证明它已合并"做成一道门，并留审计：
  - 判据（与 ps1 清理段同口径，单一真源）：`merge-base <base> <branch> == <branch tip>`
    或 `git cherry <base> <branch>` 无 `+` 行且 `git diff --name-only` 为空；
  - 通过 ⇒ 追加一行 JSON 到 `<git-dir>/fist/delete-audit.jsonl`，rc=0（允许删）；
  - 不通过 ⇒ **也追加一行**（verdict=keep）并打印未合读数，rc=1（**不许删**）；
  - rc=2 = 判据无法自证（base 取不到、branch 不存在）。

用法（ps1 清理段在 delete 前调用它）：
  python scripts/audit_branch_delete.py <branch> [--base origin/master] [--git-dir <dir>]
  python scripts/audit_branch_delete.py --selftest
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def git(*args, cwd=None):
    r = subprocess.run(["git"] + list(args), cwd=cwd or ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def audit(base, branch, cwd=None):
    """返回 (verdict, payload)。verdict ∈ {"delete","keep","unknown"}。纯读 git，不删任何东西。"""
    rc, tip = git("rev-parse", "--verify", "--quiet", branch, cwd=cwd)
    if rc != 0:
        return "unknown", {"branch": branch, "reason": "branch 不存在"}
    tip = tip.strip()
    rc, mb = git("merge-base", base, branch, cwd=cwd)
    if rc != 0:
        return "unknown", {"branch": branch, "reason": "base 取不到或不可比较：%s" % base}
    contained = mb.strip() == tip
    _, cherry = git("cherry", base, branch, cwd=cwd)
    cherry_plus = sum(1 for l in cherry.splitlines() if l.startswith("+"))
    _, diff = git("diff", "--name-only", base, branch, cwd=cwd)
    diff_files = [f for f in diff.splitlines() if f.strip()]
    payload = {"branch": branch, "base": base, "tip": tip[:12],
               "contained": contained, "cherry_plus": cherry_plus,
               "diff_files": len(diff_files), "diff_sample": diff_files[:5]}
    if contained or (cherry_plus == 0 and not diff_files):
        payload["verdict"] = "delete"
        return "delete", payload
    payload["verdict"] = "keep"
    return "keep", payload


def append_audit(payload, git_dir=None):
    """追加一行 JSON 到 <git-dir>/fist/delete-audit.jsonl；返回落点路径。"""
    if git_dir is None:
        rc, out = git("rev-parse", "--absolute-git-dir")
        if rc != 0:
            raise SystemExit("FATAL 取不到 git-dir，拒绝写审计")
        git_dir = out.strip()
    d = os.path.join(git_dir, "fist")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "delete-audit.jsonl")
    with io.open(p, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")
    return p


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    d = tempfile.mkdtemp(prefix="audit-del-")

    def g(*a, cwd=d):
        return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
    try:
        g("init", "-q", "-b", "master", ".")
        g("config", "user.email", "t@t")
        g("config", "user.name", "t")
        io.open(os.path.join(d, "a.txt"), "w", encoding="utf-8").write("1\n")
        g("add", "-A"); g("commit", "-qm", "base")
        base = g("rev-parse", "HEAD").stdout.strip()
        # 已合并（master 上做同样改动 ⇒ cherry 无 +，diff 空）
        g("checkout", "-q", "-b", "merged")
        io.open(os.path.join(d, "b.txt"), "w", encoding="utf-8").write("2\n")
        g("add", "-A"); g("commit", "-qm", "feat-b")
        g("checkout", "-q", "master")
        io.open(os.path.join(d, "b.txt"), "w", encoding="utf-8").write("2\n")
        g("add", "-A"); g("commit", "-qm", "feat-b")
        base2 = g("rev-parse", "HEAD").stdout.strip()
        # 未合并
        g("checkout", "-q", "-b", "unmerged")
        io.open(os.path.join(d, "c.txt"), "w", encoding="utf-8").write("3\n")
        g("add", "-A"); g("commit", "-qm", "feat-c")
        g("checkout", "-q", "master")

        v1, p1 = audit(base2, "merged", cwd=d)
        cell("merged-deletable", v1, "delete")
        v2, p2 = audit(base2, "unmerged", cwd=d)
        cell("unmerged-keep", v2, "keep")
        cell("unmerged-cherry-plus", p2["cherry_plus"] >= 1, True)
        v3, p3 = audit(base2, "no-such-branch", cwd=d)
        cell("missing-unknown", v3, "unknown")
        gd = os.path.join(d, ".git")
        p = append_audit(p1, git_dir=gd)
        append_audit(p2, git_dir=gd)
        lines = io.open(p, encoding="utf-8").read().strip().splitlines()
        cell("audit-two-lines", len(lines), 2)
        rec = json.loads(lines[0])
        cell("audit-has-verdict", rec.get("verdict"), "delete")
        cell("audit-has-readings", all(k in rec for k in ("contained", "cherry_plus", "diff_files")), True)
    finally:
        shutil.rmtree(d, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：已合可删/未合拒删/缺失不可判 + 审计两行与字段齐备）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("branch", nargs="?")
    ap.add_argument("--base", default="origin/master")
    ap.add_argument("--git-dir", default=None)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--no-audit", action="store_true", help="只判定不留审计（调试用）")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.branch:
        print("用法：audit_branch_delete.py <branch> [--base origin/master]")
        return 2
    verdict, payload = audit(args.base, args.branch)
    if verdict == "unknown":
        print("UNKNOWN %s：%s —— 判据无法自证，**拒绝删除**" % (args.branch, payload.get("reason")))
        if not args.no_audit:
            append_audit(payload, args.git_dir)
        return 2
    if not args.no_audit:
        p = append_audit(payload, args.git_dir)
        payload["_audit_path"] = os.path.basename(p)
    if verdict == "delete":
        print("ALLOW-DELETE %s（contained=%s cherry+=%d diff=%d）"
              % (args.branch, payload["contained"], payload["cherry_plus"], payload["diff_files"]))
        return 0
    print("REFUSE-DELETE %s（未合：cherry+=%d diff=%d 样例=%s）"
          % (args.branch, payload["cherry_plus"], payload["diff_files"], ",".join(payload["diff_sample"])))
    return 1


if __name__ == "__main__":
    sys.exit(main())
