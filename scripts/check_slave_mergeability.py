#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_slave_mergeability.py — 通道可合并性巡检（合并 agent 的前置检查尺）。

**为什么需要它**：`slave/` 通道是合并 agent 的取件面，但通道里常驻 30+ 支分支，其中不少会在
cherry-pick 时撞冲突（append-only 日志、`scripts/README.md` 追加重叠、同一文件被多方演进）。
合并 agent 只能逐支试，冲突一支就打断一次循环；而**能不能合这件事本身是可提前量化的**——
把每支分支的独有提交在一棵**临时 worktree** 里真跑一遍 `cherry-pick --no-commit`，
给出 OK / CONFLICT(文件) / CONTAINED（已含于 base）/ EMPTY（无独有提交）四档。

设计纪律：
- **只读主仓**：所有尝试都在 `git worktree` 临时目录里做，结束时强制清理（`--keep` 可留现场）。
- **不猜**：判据是真实 `git` 退出码与 `git diff --diff-filter=U`，不是文件名启发式。
- 默认 rc=0（只报告）；`--strict` 时有冲突 ⇒ rc=1（供 CI/合并 agent 当门用）。
- `--selftest`：在临时仓库造 clean/conflict/contained 三支，断言四档分类（真断言，不是打印）。

用法：
  python scripts/check_slave_mergeability.py                # 巡检 <remote>/slave/*（默认 gitcode, origin）
  python scripts/check_slave_mergeability.py --remote gitcode --strict
  python scripts/check_slave_mergeability.py --selftest
"""
import argparse
import atexit
import io
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

from moon_env_probe import moon_env
from git_env import isolated_git_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def git(*args, cwd=None):
    r = subprocess.run(["git"] + list(args), cwd=cwd or ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=isolated_git_env())
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def classify(ahead, pick_rc, conflicts, has_merge=False):
    """四档分类（纯函数，selftest 直接喂数）：
    contained = 无独有提交；
    ok        = 全部 cherry-pick 成功；
    conflict  = 有冲突（带文件清单）；
    error     = 非冲突性失败（git 报错，无法判定）。
    """
    if ahead == 0:
        return "contained"
    if pick_rc == 0:
        return "ok"
    if conflicts:
        return "conflict"
    if has_merge:
        # 通道里确实有这种支（实测 gitcode/slave/guard/backlog-status-staleness-r102，ahead=15 含 merge）：
        # cherry-pick 遇到 merge commit 必须给 -m，否则报 "is a merge but no -m option was given"。
        # 这是**待人工指定主线**，不是"判据坏了"，必须与 error 分开报。
        return "merge"
    return "error"


def branches(remotes):
    rc, out = git("for-each-ref", "--format=%(refname:short)", "refs/remotes")
    if rc != 0:
        return []
    names = []
    for line in out.splitlines():
        b = line.strip()
        if not b or b.endswith("/HEAD"):
            continue
        if "/slave/" in b and any(b.startswith(r + "/") for r in remotes):
            names.append(b)
    return sorted(names)


def simulate(base, wt, commits):
    """在临时 worktree 里真跑 cherry-pick；返回 (rc, conflict_files)。"""
    git("checkout", "-q", "--detach", base, cwd=wt)
    git("reset", "-q", "--hard", base, cwd=wt)
    for c in commits:
        rc, _ = git("cherry-pick", "--no-commit", c, cwd=wt)
        if rc != 0:
            _, conf = git("diff", "--name-only", "--diff-filter=U", cwd=wt)
            files = [f.strip() for f in conf.splitlines() if f.strip()]
            git("cherry-pick", "--abort", cwd=wt)
            return 1, files
    return 0, []


def scan(base, remotes, keep=False, limit=0):
    bs = branches(remotes)
    if limit:
        bs = bs[:limit]
    if not bs:
        print("scan: 通道里没有 <remote>/slave/* 分支")
        return [], 0
    tmp = tempfile.mkdtemp(prefix="mergeability-")
    wt = os.path.join(tmp, "wt")
    rc, out = git("worktree", "add", "--detach", wt, base)
    if rc != 0:
        print("FATAL 建临时 worktree 失败：%s" % out.strip()[:200])
        shutil.rmtree(tmp, ignore_errors=True)
        return [], 2
    rows = []
    try:
        for b in bs:
            rc, out = git("rev-list", "--reverse", "%s..%s" % (base, b))
            commits = [c for c in out.split() if c] if rc == 0 else []
            pick_rc, files = simulate(base, wt, commits) if commits else (0, [])
            _, mout = git("rev-list", "--merges", "%s..%s" % (base, b))
            has_merge = bool([m for m in mout.split() if m]) if commits else False
            kind = classify(len(commits), pick_rc, files, has_merge)
            rows.append({"branch": b, "ahead": len(commits), "kind": kind, "files": files})
            mark = {"ok": "✓", "contained": "=", "conflict": "✗", "merge": "M", "error": "!"}[kind]
            extra = ("  冲突: " + ", ".join(files[:3]) + (" …" if len(files) > 3 else "")) if files else ""
            print("  %s %-52s ahead=%-3d %s%s" % (mark, b, len(commits), kind, extra))
    finally:
        if not keep:
            git("worktree", "remove", "--force", wt)
            git("worktree", "prune")
            shutil.rmtree(tmp, ignore_errors=True)
        else:
            print("  [--keep] 现场保留在 %s" % wt)
    return rows, 0


def apply_merges(base, rows, execute=False):
    """把 ok 分支的独有提交 cherry-pick 到 base（默认只打印命令，不执行）。

    纪律（与 slave-branch-merge.ps1 / whisperer.auto_merge 同一条底线）：
      - **绝不 force-push**，只做 `git push origin HEAD:master`（快进或普通推送，被拒就报错让人看）；
      - 工作树必须干净，否则一件都不动；
      - 每支落完跑两道门（冲突标记判据 + moon build），红就 `reset --hard` 回滚该支；
      - 冲突不猜：`cherry-pick --abort` + `reset --hard`，整支跳过。
    返回 (merged, skipped, dry_run)。
    """
    oks = [r for r in rows if r["kind"] == "ok"]
    if not oks:
        print("apply: 没有可合分支（ok=0）")
        return 0, 0, not execute
    if not execute:
        print("\n[DRY-RUN] 将执行（加 --yes 真跑）：")
        for r in oks:
            print("  git cherry-pick $(git rev-list --reverse %s..%s)" % (base, r["branch"]))
        print("  然后：python scripts/blackbox/check_merge_markers.py && moon build --target js <5 pkgs>")
        print("  最后：git push origin HEAD:master（不 force）")
        return 0, len(oks), True
    if sh("git", "status", "--porcelain", cwd=ROOT)[1].strip():
        print("apply: 工作树不干净 → 拒绝执行（宁可不合，不可猜）")
        return 0, len(oks), False
    merged, skipped = 0, 0
    for r in oks:
        ref = r["branch"]
        rc, out = git("rev-list", "--reverse", "%s..%s" % (base, ref))
        commits = [c for c in out.split() if c] if rc == 0 else []
        if not commits:
            skipped += 1
            continue
        ok_all = True
        for c in commits:
            if git("cherry-pick", c, cwd=ROOT)[0] != 0:
                git("cherry-pick", "--abort", cwd=ROOT)
                git("reset", "--hard", "HEAD", cwd=ROOT)
                print("  ✗ %s 冲突于 %s → 整支跳过" % (ref, c[:7]))
                ok_all = False
                break
        if not ok_all:
            skipped += 1
            continue
        # 门①：冲突标记
        if subprocess.run([sys.executable, "scripts/blackbox/check_merge_markers.py"], cwd=ROOT,
                          capture_output=True).returncode != 0:
            git("reset", "--hard", "HEAD~%d" % len(commits), cwd=ROOT)
            print("  ✗ %s markers 红 → 回滚" % ref)
            skipped += 1
            continue
        # 门②：构建
        b = subprocess.run(["moon", "build", "--target", "js", "src/server", "src/engine",
                            "src/store", "src/router", "src/ops"], cwd=ROOT,
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           env=moon_env())
        if (b.stdout or "").count("Error:") > 0:
            git("reset", "--hard", "HEAD~%d" % len(commits), cwd=ROOT)
            print("  ✗ %s build 有 Error → 回滚" % ref)
            skipped += 1
            continue
        merged += 1
        print("  ✓ %s 合入 %d 个提交" % (ref, len(commits)))
    if merged:
        rc, out = git("push", "origin", "HEAD:master", cwd=ROOT)
        print("  push origin HEAD:master → rc=%d %s" % (rc, out.strip()[:120]))
    return merged, skipped, False


def _force_rm(func, path, exc_info):
    """Windows 上的 rmtree 单点补救：`.git/objects` 里的文件是只读的，直接删 PermissionError。

    先把目标改成可写再重试一次本点；仍失败则抛回给 rmtree 走 _cleanup_paths 的 WARN 路径。
    """
    try:
        os.chmod(path, stat.S_IWRITE)
        func(path)
    except Exception:
        raise


def _cleanup_paths(*paths):
    """清理 selftest 临时现场（BUG-409）。

    两个缺陷各自对应一行：
    1. **`finally` 不保证执行** —— 进程被杀/超时/Ctrl-C 时 finally 不跑，现场永久留在系统
       Temp。缓解：调用方在 mkdtemp 后立刻 `atexit.register(_cleanup_paths, ...)`，正常路径
       在 finally 里 unregister；被 SIGKILL 时仍会残留，但已是能做的最大值。
    2. **`ignore_errors=True` 静默吞掉清理失败** —— 清理失败必须出声并点名路径，
       否则「泄漏」既不被发现也不被报告（与本仓「绝不静默」口径相反）。

    另加一层 Windows 现实补救：`.git` 里的对象文件带只读属性，`rmtree` 会 PermissionError；
    先等 0.3s 让 git 子进程释放句柄，再用 `onerror=_force_rm` 逐点改权限重试。
    """
    for p in paths:
        if not p or not os.path.exists(p):
            continue
        try:
            shutil.rmtree(p)
            continue
        except Exception:
            pass
        time.sleep(0.3)  # 给 git 子进程一点时间释放句柄
        try:
            shutil.rmtree(p, onerror=_force_rm)
        except Exception as exc:  # 清理失败必须点名，不许静默
            print(
                "WARN 清理失败，临时现场残留：%s（%r）—— 请手工删除" % (p, exc),
                file=sys.stderr,
            )


def selftest():
    """临时仓库造 clean / conflict / contained 三支，断言分类与真实 cherry-pick 行为。"""
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    # 纯函数格
    cell("classify-contained", classify(0, 0, []), "contained")
    cell("classify-ok", classify(2, 0, []), "ok")
    cell("classify-conflict", classify(1, 1, ["a.txt"]), "conflict")
    cell("classify-error", classify(1, 1, []), "error")
    cell("classify-merge", classify(3, 1, [], True), "merge")
    cell("classify-merge-but-ok", classify(3, 0, [], True), "ok")

    # 端到端格：造真仓库
    d = tempfile.mkdtemp(prefix="mergeability-st-")
    wt = os.path.abspath(os.path.join(d, "..", "wt-" + os.path.basename(d)))
    # BUG-409：finally 在进程被 SIGKILL / 硬超时时不跑 —— 先注册 atexit 兜一手，
    # 正常路径在 finally 里 unregister（避免重复清理刷 WARN）。
    atexit.register(_cleanup_paths, d, wt)
    def g(*a, cwd=d):
        return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", env=isolated_git_env())
    try:
        g("init", "-q", "-b", "master", ".")
        g("config", "user.email", "t@t")
        g("config", "user.name", "t")
        io.open(os.path.join(d, "a.txt"), "w", encoding="utf-8").write("base\n")
        g("add", "-A"); g("commit", "-qm", "base")
        base = g("rev-parse", "HEAD").stdout.strip()
        # clean 分支：只加新文件
        g("checkout", "-q", "-b", "clean")
        io.open(os.path.join(d, "b.txt"), "w", encoding="utf-8").write("new\n")
        g("add", "-A"); g("commit", "-qm", "clean-commit")
        # conflict 分支：改 base 的同一行
        g("checkout", "-q", "-b", "conflict", base)
        io.open(os.path.join(d, "a.txt"), "w", encoding="utf-8").write("branch-change\n")
        g("commit", "-qam", "conflict-commit")
        # contained：不前进（停在 base）
        g("checkout", "-q", "-b", "contained", base)
        # ★ base 自己也要在同一点演进，否则"分支改了 a.txt"根本不可能冲突
        #   （第一版夹具漏了这一步，自检当场报 e2e-conflict got='ok' —— 判据自己抓到了夹具的假绿）
        g("checkout", "-q", "master")
        io.open(os.path.join(d, "a.txt"), "w", encoding="utf-8").write("master-change\n")
        g("commit", "-qam", "master-advance")
        base2 = g("rev-parse", "HEAD").stdout.strip()
        g("worktree", "add", "--detach", wt, base2)
        # 让 clean 与 conflict 都能被 cherry-pick 到 base 上
        for name, want in (("clean", "ok"), ("conflict", "conflict"), ("contained", "contained")):
            out = g("rev-list", "--reverse", "%s..%s" % (base, name)).stdout
            commits = [c for c in out.split() if c]
            pick_rc, files = simulate(base2, wt, commits) if commits else (0, [])
            cell("e2e-" + name, classify(len(commits), pick_rc, files), want)
    finally:
        # BUG-409：清理失败必须出声（原实现 ignore_errors=True 静默吞掉，泄漏既不被发现也不被报告）
        # Windows 上 git 会持有 worktree 目录句柄，直接 rmtree 必 PermissionError ——
        # 先解注册（worktree remove --force）、再 prune 残注册、最后才删目录。
        for cleanup_argv in (
            ["worktree", "remove", "--force", wt],
            ["worktree", "prune"],
        ):
            try:
                subprocess.run(
                    ["git"] + cleanup_argv, cwd=d, capture_output=True, text=True,
                    encoding="utf-8", errors="replace", env=isolated_git_env(), timeout=30,
                )
            except Exception:
                pass  # 解注册失败不阻断清理，最终 _cleanup_paths 会出声点名
        _cleanup_paths(d, wt)
        try:
            atexit.unregister(_cleanup_paths)
        except Exception:
            pass

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：分类纯函数 6 档 + 真仓库端到端 3 支 clean/conflict/contained）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--base", default="origin/master")
    ap.add_argument("--remote", action="append", default=None,
                    help="只看这些 remote 的 slave/ 分支（可多次；默认 gitcode + origin）")
    ap.add_argument("--strict", action="store_true", help="有冲突 ⇒ rc=1")
    ap.add_argument("--keep", action="store_true", help="保留临时 worktree 现场")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--apply", action="store_true",
                    help="把判定为 ok 的分支真跑 cherry-pick（默认 dry-run 只打印将执行的命令）")
    ap.add_argument("--yes", action="store_true", help="与 --apply 同用：确认真的执行（防手滑）")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    rc, _ = git("rev-parse", "--verify", "--quiet", args.base + "^{commit}")
    if rc != 0:
        print("FATAL base 不存在：%s —— 判据无法自证，拒绝出结论" % args.base)
        return 2
    remotes = args.remote or ["gitcode", "origin"]
    print("通道可合并性巡检：base=%s，remotes=%s" % (args.base, ",".join(remotes)))
    rows, rc = scan(args.base, remotes, args.keep, args.limit)
    if rc != 0:
        return rc
    if not rows:
        return 0
    ok = sum(1 for r in rows if r["kind"] == "ok")
    contained = sum(1 for r in rows if r["kind"] == "contained")
    conflict = sum(1 for r in rows if r["kind"] == "conflict")
    merge = sum(1 for r in rows if r["kind"] == "merge")
    error = sum(1 for r in rows if r["kind"] == "error")
    print("\n汇总：共 %d 支 | 可合 %d | 已含于 base %d | 冲突 %d | 含 merge commit（需 -m 人工指定主线）%d | 无法判定 %d"
          % (len(rows), ok, contained, conflict, merge, error))
    if args.apply:
        m, s, dry = apply_merges(args.base, rows, execute=args.yes)
        print("apply: merged=%d skipped=%d %s" % (m, s, "(dry-run)" if dry else ""))
    if conflict or merge or error:
        print("提示：冲突支需先 rebase/自解（append-only 日志可用 union，README 可'theirs+补回我方段'）")
        return 1 if args.strict else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
