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
from git_env import isolated_git_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def git(*args, cwd=None):
    r = subprocess.run(["git"] + list(args), cwd=cwd or ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=isolated_git_env())
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def verdict_of(ahead, pushed):
    """纯函数：领先且未推送 ⇒ gap（交付幻觉）；否则 ok。"""
    if ahead <= 0:
        return "ok"
    return "ok" if pushed else "gap"


def classify_divergence(a_only, b_only):
    """纯函数：两条线互相领先的提交数 ⇒ 形态。

    - 都为 0 ⇒ "same"（同一提交）；
    - 只有一侧领先 ⇒ "ff"（可快进追上；`a_only=0` 表示 b 领先 a，反之亦然）；
    - 两侧都领先 ⇒ "diverged"（真分叉：需要有人手工合）。
    为什么单列这一格：本仓**两条远端线**（`origin/master` 面向 GitHub，`gitcode/main` 是合并机器人的真实整合线）
    会周期性错位；R46 我就因为拿 `origin` 当基准核对，得出过"修的全丢了"的错误结论——实际内容都在 `gitcode` 上。
    把错位量出来（而不是靠记忆里"哪条是主line"），这类误判就不会再发生。
    """
    a_only, b_only = int(a_only), int(b_only)
    if a_only == 0 and b_only == 0:
        return "same"
    if a_only == 0 or b_only == 0:
        return "ff"
    return "diverged"


def inspect_cross(a, b):
    """比较两个远端 ref：返回 {a, b, a_only, b_only, files, verdict}。"""
    rc_a, _ = git("rev-parse", "--verify", "--quiet", a)
    rc_b, _ = git("rev-parse", "--verify", "--quiet", b)
    if rc_a != 0 or rc_b != 0:
        return None
    rc1, s1 = git("rev-list", "--count", "%s..%s" % (b, a))
    rc2, s2 = git("rev-list", "--count", "%s..%s" % (a, b))
    if rc1 != 0 or rc2 != 0:
        return None
    a_only = int(s1.strip() or 0) if s1.strip().isdigit() else 0
    b_only = int(s2.strip() or 0) if s2.strip().isdigit() else 0
    files = 0
    if a_only or b_only:
        # 用**两点**语法：三点 `A...B` 只算 merge-base→B，反向调用会得 0 个文件
        # （实测反向 `gitcode/main...origin/master` = 0，而两点 = 27）⇒ 判据会随入参顺序变，不能用。
        rc, d = git("diff", "--name-only", a, b)
        if rc == 0:
            files = len([f for f in d.splitlines() if f.strip()])
    return {"a": a, "b": b, "a_only": a_only, "b_only": b_only, "files": files,
            "verdict": classify_divergence(a_only, b_only)}


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
    _entry_probe()
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    cell("no-ahead", verdict_of(0, False), "ok")
    cell("ahead-pushed", verdict_of(3, True), "ok")
    cell("ahead-unpushed", verdict_of(3, False), "gap")
    cell("div-same", classify_divergence(0, 0), "same")
    cell("div-ff", classify_divergence(0, 18), "ff")
    cell("div-diverged", classify_divergence(2, 3), "diverged")

    import io
    d = tempfile.mkdtemp(prefix="gap-")

    def g(*a, cwd=d):
        return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", env=isolated_git_env())
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


def main_compare(a, b):
    got = inspect_cross(a, b)
    if got is None:
        print("  判据无法自证：取不到 %s 或 %s（rc=2，拒绝判绿也拒绝判红）" % (a, b))
        return 2
    print("  跨远端断层：%s → %s" % (a, b))
    print("    %-24s 独有 %d 个提交" % (a, got["a_only"]))
    print("    %-24s 独有 %d 个提交" % (b, got["b_only"]))
    print("    形态：%s（差异文件 %d 个）" % (got["verdict"], got["files"]))
    if got["verdict"] == "same":
        print("PASS 两条线同一提交")
        return 0
    if got["verdict"] == "ff":
        lag = a if got["b_only"] else b
        lead = b if got["b_only"] else a
        print("FAIL 单向落后：`%s` 落后 `%s`（可快进；若这条线对外可见，用户/CI 读到的是旧内容）"
              % (lag, lead))
        return 1
    print("FAIL 真分叉：两条线各有独有提交，需要有人手工合并")
    return 1



def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "--compare":
        return main_compare(sys.argv[2], sys.argv[3])
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
