#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_delivery_gap.py — "本地领先 = 已交付？" 的尺（R46）。

**为什么需要它**（2026-10-22 实测两次踩坑）：
1. 共享检出的本地 `main` 一度领先 `origin/master` **207 个提交**，而我 10 项修复里的 9 项
   其实已在本地 main 里 —— 但 `origin/master` 与 `origin/main` 都还停在 12:17 的同一提交。
   只看 origin 会把"已集成"误读成"全丢"。
2. 换 `gitcode/main` 看才发现：**真正的整合线是 gitcode**（推送都去 gitcode），
   9/10 项修复确实已在该线上。⇒ 判断"交付"，必须指定**正确的远端线**，不能想当然。

所以这条尺不假设哪条线是真线，而是**对给定 base 逐分支量**：
  - `rev-list --count <base>..<ref>`：本地领先多少提交；
  - 这些提交动多少文件；
  - `git branch -r --contains <tip>`：这个 tip 是否已经出现在**任何**远端分支上；
  - 退出码：0 = 无断层；1 = 存在未推送提交（交付幻觉）；2 = base 取不到（判据无法自证）。

用法：
  python scripts/check_delivery_gap.py                      # base=origin/master（默认）
  python scripts/check_delivery_gap.py --base gitcode/main  # 换整合线
  python scripts/check_delivery_gap.py --base gitcode/master --refs main,HEAD
  python scripts/check_delivery_gap.py --selftest
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


def git(*args, cwd=None):
    r = subprocess.run(["git"] + list(args), cwd=cwd or ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def verdict_of(ahead, pushed):
    """纯函数：领先且未推送 ⇒ gap（交付幻觉）；否则 ok。"""
    if ahead <= 0:
        return "ok"
    return "ok" if pushed else "gap"


def inspect(base, ref):
    rc, tip = git("rev-parse", "--verify", "--quiet", ref)
    if rc != 0:
        return None
    tip = tip.strip()
    rc, ahead_s = git("rev-list", "--count", "%s..%s" % (base, ref))
    ahead = int(ahead_s.strip()) if rc == 0 and ahead_s.strip().isdigit() else 0
    pushed = True
    if ahead > 0:
        rc, out = git("branch", "-r", "--contains", tip)
        pushed = rc == 0 and bool([l for l in out.splitlines() if l.strip()])
    files = 0
    if ahead:
        rc, d = git("diff", "--name-only", "%s..%s" % (base, ref))
        files = len([f for f in d.splitlines() if f.strip()])
    return {"ref": ref, "tip": tip[:8], "ahead": ahead, "files": files,
            "pushed": pushed, "verdict": verdict_of(ahead, pushed)}


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    cell("no-ahead", verdict_of(0, False), "ok")
    cell("ahead-pushed", verdict_of(3, True), "ok")
    cell("ahead-unpushed", verdict_of(3, False), "gap")

    import io
    d = tempfile.mkdtemp(prefix="gap-")

    def g(*a, cwd=d):
        return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace")
    try:
        remote = os.path.join(d, "remote.git")
        g("init", "--bare", "-q", remote)
        work = os.path.join(d, "work")
        g("init", "-q", "-b", "master", work)
        g("config", "user.email", "t@t", cwd=work)
        g("config", "user.name", "t", cwd=work)
        io.open(os.path.join(work, "a.txt"), "w", encoding="utf-8").write("1\n")
        g("add", "-A", cwd=work)
        g("commit", "-qm", "c1", cwd=work)
        g("remote", "add", "origin", remote, cwd=work)
        g("push", "-q", "origin", "master", cwd=work)
        g("fetch", "-q", "origin", cwd=work)
        io.open(os.path.join(work, "b.txt"), "w", encoding="utf-8").write("2\n")
        g("add", "-A", cwd=work)
        g("commit", "-qm", "c2", cwd=work)
        cnt = g("rev-list", "--count", "origin/master..master", cwd=work).stdout
        cell("e2e-gap", verdict_of(int(cnt.strip() or 0), False), "gap")
        g("push", "-q", "origin", "master", cwd=work)
        g("fetch", "-q", "origin", cwd=work)
        cnt = g("rev-list", "--count", "origin/master..master", cwd=work).stdout
        cell("e2e-after-push", verdict_of(int(cnt.strip() or 0), True), "ok")
    finally:
        shutil.rmtree(d, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：纯函数三档 + 真仓库 提交未推/推送后 两例）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--base", default="origin/master")
    ap.add_argument("--refs", default="main,master,HEAD")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    rc, _ = git("rev-parse", "--verify", "--quiet", args.base + "^{commit}")
    if rc != 0:
        print("FATAL base 不存在：%s —— 判据无法自证，拒绝出结论" % args.base)
        return 2
    print("交付断层巡检：base=%s" % args.base)
    rows = []
    for ref in [r.strip() for r in args.refs.split(",") if r.strip()]:
        info = inspect(args.base, ref)
        if not info:
            continue
        rows.append(info)
        mark = "✓" if info["verdict"] == "ok" else "✗ 未交付"
        print("  %-10s %-10s ahead=%-4d files=%-4d pushed=%-5s %s"
              % (info["ref"], info["tip"], info["ahead"], info["files"], info["pushed"], mark))
    if not rows:
        print("巡检：没有可比较的本地分支")
        return 0
    gaps = [r for r in rows if r["verdict"] == "gap"]
    print("\n汇总：%d 个分支，其中 **%d 个存在未推送提交**" % (len(rows), len(gaps)))
    if gaps:
        print("⚠ 这些提交没有到达远端 base：")
        for r in gaps:
            print("    %s 领先 %d 个提交、动 %d 个文件，tip=%s" % (r["ref"], r["ahead"], r["files"], r["tip"]))
        print('  含义："本地已合" != "已交付"。清理/合并流程若用本地 HEAD 判"已包含"，')
        print("  会删掉尚未交付的通道分支（R46 已把 slave-branch-merge.ps1 的判据改成远端基线 + 内容等价）。")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
