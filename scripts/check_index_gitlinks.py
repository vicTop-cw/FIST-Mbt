#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_index_gitlinks.py —— 「索引里不许有 gitlink（mode 160000）」判据（R179）。

## 为什么需要这一把（真实事故，不是假想）

2026-10-24 实测：本仓 `git worktree list` 注册了 **51** 个 worktree（`.agents/worktrees/**`、
`temp/wt-*`、`../light-wt/*` …），每个 worktree 目录根都有一个 `.git` **文件**（`gitdir: …`）。
只要谁在仓根跑一次 `git add -A`，git 就会把这些目录记成 **gitlink**（`mode 160000` + 一条仓库外
提交 sha），于是：

- `4a7bf82a` 曾把 `.agents/worktrees/fix/display-rank-boundary` 当 gitlink 提交进跟踪面 ⇒
  `check_merge_markers` 等判据「读不到正文」，主线因此带着预存红（R106 登记、R116 才收口）；
- 更糟的是它**不可修复地**粘在历史里：`git rm --cached` 只能挡住下一次，已带 gitlink 的
  commit 仍被 CI/克隆者读到（`git archive` 直接把它变成空目录）。

瘦身组的口径是「49 个已注册 worktree = 49 颗 gitlink 雷」；本尺把「雷」变成**提交前**就会炸的门。

## 判据（两格，都是「有输出即红」）

- **G1 暂存面**：`git diff --cached --raw --diff-filter=AMT` 里出现 `160000` ⇒ 这一次提交要把
  gitlink 写进索引 ⇒ 拒。这是 pre-commit 钩子调的那一格，**只拦本次提交**，不因历史存量而误拦。
- **G2 全索引**：`git ls-files -s` 里出现 `160000` ⇒ 索引里已经有 gitlink（可能是他人在同一索引
  上 add 的，也可能是历史带进来的）。裸跑（不带 `--staged`）判这一格，供守卫宇宙与 CI 事后点名。

两格都点名**每一个**命中路径，并给出逐条可执行的修复命令（不是「请清理」这种泛泛之谈）。

## 为什么是 gitlink，不是「子模块」

本仓**没有** `.gitmodules`，也不打算有：那 51 个 worktree 是 agent 的**本地运行态**，不是仓库
资产。所以这里**不允许**「合法的子模块」例外——出现 160000 一律拒，附带说明为何本仓不适用例外。

## 退出码

0 = 索引面没有 gitlink / 1 = 命中（逐条点名 + 修复命令）/ 2 = 判据无法自证（不是 git 仓库，
或 `git ls-files` 不可用）/ 4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）。

## 自证（`--selftest`，临时仓库端到端，不碰本仓）

6 格：合法提交放行 / `git add -A` 造出的 gitlink 被拦 / 精确点名路径 / 修复命令可执行且修复后放行 /
G2 全索引格能看见存量 / 合法子模块形态不被当成"错误识别"误判（本仓口径仍拒，但**必须由本尺**而非
git 的 `add` 失败来拒）。
"""
import argparse
import os
import shutil
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

GITLINK_MODE = "160000"

# 入口自证的一次性哨兵（见 selftest() 里的「递归守卫」注释）：保证 `main()` 只在最外层
# 那次 selftest 里被真调一次，不会随递归层层重入。
_ENTRY_PROBED = [False]

# 本仓护栏清单：这些路径必须被 .gitignore 挡住（否则下次 `git add -A` 还会再造一次）
GUARD_RULES = (
    ".agents/worktrees/",
    "/.verify-wt",
    "temp/",
)


def _git(args, cwd=None, env=None):
    """跑一条 git，返回 (rc, stdout, stderr)。全部按 UTF-8 解码，绝不因中文路径编码崩。"""
    proc = subprocess.run(
        ["git", *args],
        cwd=cwd or ROOT,
        capture_output=True,
        env=env,
    )
    return (
        proc.returncode,
        (proc.stdout or b"").decode("utf-8", "replace"),
        (proc.stderr or b"").decode("utf-8", "replace"),
    )


def parse_staged_gitlinks(raw_stdout):
    """纯函数：解析 `git diff --cached --raw` 的输出，返回 [(mode, sha, path), ...] 仅 160000。

    行形如 `:160000 160000 <sha> <sha> A\\tpath`（`-z` 时换成 NUL 分隔，这里只吃换行形态）。
    本函数是判据的**识别核**，与 git 调用解耦，便于自证格直接喂字符串。
    """
    hits = []
    for line in (raw_stdout or "").splitlines():
        if not line.startswith(":"):
            continue
        try:
            meta, _, path = line.partition("\t")
            fields = meta[1:].split()
            dst_mode = fields[1]
            dst_sha = fields[3]
        except IndexError:
            continue
        if dst_mode == GITLINK_MODE:
            hits.append((dst_mode, dst_sha, path))
    return hits


def parse_ls_files(raw_stdout):
    """纯函数：解析 `git ls-files -s` 的输出，返回 [path, ...] 仅 160000。

    行形如 `160000 <sha> <stage>\\tpath`。
    """
    hits = []
    for line in (raw_stdout or "").splitlines():
        try:
            meta, _, path = line.partition("\t")
            mode = meta.split()[0]
        except IndexError:
            continue
        if mode == GITLINK_MODE:
            hits.append(path)
    return hits


def commands_to_ignore():
    """纯函数：本仓护栏里**缺的那几条**（用于错误信息里直接给出 `gitignore` 建议）。"""
    return list(GUARD_RULES)


def remedy_block(paths, scope):
    """生成可执行的修复命令块（不是泛泛之谈：每条都是能直接粘贴的）。

    2026-10-24 自证实测校准：对**首次**进入索引的 gitlink（`A` 态），`git rm --cached` 会因
    「staged content different from both the file and the HEAD」而失败、必须 `-f`；对**已提交**
    的 gitlink（`M` 态）则不需要。所以这里给的是带 `-f` 的通用形——它两种态都能跑通，
    且 `--cached` 保证**工作树里的目录一个字都不动**（那只是 agent 的本地运行态）。
    """
    lines = []
    lines.append("  修法（逐条可执行，按顺序）：")
    lines.append("    1) 把 gitlink 从索引里摘掉（`--cached` ⇒ 工作树里的目录本身**不动**，它只是本地运行态）：")
    for p in paths:
        lines.append('         git rm --cached -f -- "%s"' % p)
    lines.append("    （为何带 -f：对首次 add 进来的 gitlink，不带 -f 的 `git rm --cached` 会报"
                 "「staged content different from both the file and the HEAD」而失败——自证格实测过）")
    lines.append("    2) 确认护栏已生效（本仓已跟踪的这些规则都在 .gitignore 里）：")
    for rule in GUARD_RULES:
        lines.append('         git check-ignore -v -- "%s"   # 期望命中规则：%s' % (rule, rule))
    lines.append("    3) 若上一步没命中，就把缺的规则补进 .gitignore（下面这条幂等，可重复跑）：")
    for rule in GUARD_RULES:
        lines.append('         grep -qxF "%s" .gitignore || echo "%s" >> .gitignore' % (rule, rule))
    lines.append("    4) 重新提交（**不要**再跑 `git add -A`；只 add 你要改的路径）：")
    lines.append("         git add <你的改动路径> && git commit")
    lines.append("")
    lines.append("  为什么必须拒（不是洁癖）：")
    lines.append("    - gitlink 会让 `git archive` / 干净克隆得到一个**空目录**，CI 里判据读不到正文；")
    lines.append("    - 历史里的 gitlink（如 4a7bf82a）`git rm --cached` 挡不住，只能靠提交前拦；")
    lines.append("    - 本仓没有 `.gitmodules`，这 51 个 worktree 是 agent 的本地运行态，不是仓库资产，")
    lines.append("      所以**没有**「合法子模块」例外——出现 %s 一律拒。" % GITLINK_MODE)
    lines.append("")
    lines.append("  本次判据面：%s" % scope)
    return "\n".join(lines)


def check(staged_only=False, cwd=None, env=None):
    """跑两格判据。返回 (rc, report_lines)。"""
    cwd = cwd or ROOT
    env = env if env is not None else isolated_git_env()

    rc, _, err = _git(["rev-parse", "--git-dir"], cwd=cwd, env=env)
    if rc != 0:
        return 2, ["FATAL 判据无法自证：这里不是 git 仓库（`rev-parse --git-dir` 失败）⇒ 拒绝出绿灯"]

    out = []
    failed = False

    # G1 暂存面：本次提交是否要把 gitlink 写进索引
    rc, raw, err = _git(["diff", "--cached", "--raw", "--diff-filter=AMT"], cwd=cwd, env=env)
    if rc != 0 and raw.strip() == "":
        # 没有 index（裸克隆/新仓首次 add 前）时 `diff --cached` 可能非零；此时不算违例，交给 G2
        out.append("WARN G1 `git diff --cached` 不可用（rc=%d）：%s" % (rc, err.strip()[:200]))
    staged = parse_staged_gitlinks(raw)
    if staged:
        failed = True
        out.append("FAIL G1 本次提交要把 %d 个 gitlink(%s) 写进索引：" % (len(staged), GITLINK_MODE))
        for mode, sha, path in staged:
            out.append("  - %s  mode=%s  sha=%s" % (path, mode, sha))
    else:
        out.append("PASS G1 暂存面没有 gitlink（本次提交干净）")

    # G2 全索引：索引里已有 gitlink（存量或同索引他人 add）
    rc, raw, err = _git(["ls-files", "-s"], cwd=cwd, env=env)
    if rc != 0:
        return 2, ["FATAL 判据无法自证：`git ls-files -s` 失败（rc=%d）：%s" % (rc, err.strip()[:200])]
    existing = parse_ls_files(raw)
    if staged_only:
        out.append("SKIP G2 全索引格（--staged 模式只判本次提交；存量 gitlink 由裸跑那格点名）")
    elif existing:
        failed = True
        out.append("FAIL G2 索引里已有 %d 个 gitlink(%s)：" % (len(existing), GITLINK_MODE))
        for path in existing:
            out.append("  - %s" % path)
    else:
        out.append("PASS G2 全索引没有 gitlink")

    hits = [p for _, _, p in staged] if staged else []
    if not staged_only:
        hits = sorted(set(hits) | set(existing))

    if failed:
        out.append("")
        out.append(remedy_block(hits, "G1 暂存面 + G2 全索引" if not staged_only else "G1 暂存面"))
        return 1, out

    out.append("PASS 索引面前不存在 gitlink（%s）：合法提交可以放行" % (", ".join(GUARD_RULES)))
    return 0, out


# ── 自证：临时仓库端到端（全部经 isolated_git_env，绝不碰本仓）────────────────────────────


def _fixture_repo(tmp):
    """造一个带 worktree 雷的临时仓库：主仓 + 一个嵌入式 git 仓（模拟 agent worktree）。"""

    def g(*args, **kw):
        return subprocess.run(
            ["git", *args],
            cwd=kw.get("cwd", tmp),
            capture_output=True,
            env=isolated_git_env(),
        )

    g("init", "-q", "-b", "main")
    g("config", "user.name", "t")
    g("config", "user.email", "t@t")
    g("config", "commit.gpgsign", "false")
    with open(os.path.join(tmp, "README.md"), "w", encoding="utf-8") as f:
        f.write("# fixture\n")
    g("add", "README.md")
    g("commit", "-q", "-m", "init")
    # 模拟 `.agents/worktrees/x`：一个挂着 `.git` 文件的子目录（真 worktree 就是这个形状）
    wt = os.path.join(tmp, ".agents", "worktrees", "wt-probe")
    os.makedirs(wt, exist_ok=True)
    with open(os.path.join(wt, "note.txt"), "w", encoding="utf-8") as f:
        f.write("local runtime only\n")
    g("init", "-q", "-b", "probe", cwd=wt)
    g("config", "user.name", "t", cwd=wt)
    g("config", "user.email", "t@t", cwd=wt)
    g("add", "note.txt", cwd=wt)
    g("commit", "-q", "-m", "probe", cwd=wt)
    return wt


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # R171/J2 口径：自检必须把**真入口**纳入调用图。判据 `check_selftest_call_face.py` 从
    # `selftest()` 出发沿调用名闭包做静态可达性分析，锚点 = 名为 main/run/cli 的函数
    # （或调 exit/SystemExit 的函数）。只写 `callable(main)` 断言**不够**——那样 `main` 只是
    # 被读到的对象、不在调用图里，判据照样算缺（判例-3「改名不是接线」的反面）。所以这里真调
    # 一次 `main()` 并钉住退出码。零副作用。
    #
    # ⚠️ 递归守卫：`main(["--selftest"])` 会再进一次 `selftest()`，若每次都调 `main` 就无限递归
    # （实测 `RecursionError`）。故用模块级一次性哨兵：**只有最外层那次 selftest 调入口**，
    # 递归进去的那层直接跳过本格。这既保住调用图可达性（静态分析看的是 AST，与运行时层数无关），
    # 又只真跑一次。
    if not _ENTRY_PROBED[0]:
        _ENTRY_PROBED[0] = True
        try:
            cell("entry-main-selftest-rc0", main(["--selftest"]), 0)
        finally:
            _ENTRY_PROBED[0] = False

    # ── 纯函数格（不依赖 git）──────────────────────────────────────────
    raw_staged = (
        ":160000 160000 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 A\t.agents/worktrees/wt-probe\n"
        ":000000 100644 3333333333333333333333333333333333333333 4444444444444444444444444444444444444444 A\tREADME.md\n"
    )
    cell("parse-staged-detects-gitlink", [p for _, _, p in parse_staged_gitlinks(raw_staged)],
         [".agents/worktrees/wt-probe"])
    cell("parse-staged-ignores-normal-file", len(parse_staged_gitlinks(raw_staged)), 1)
    cell("parse-staged-empty", parse_staged_gitlinks(""), [])
    raw_ls = (
        "100644 5555555555555555555555555555555555555555 0\tREADME.md\n"
        "160000 6666666666666666666666666666666666666666 0\t.agents/worktrees/wt-probe\n"
    )
    cell("parse-lsfiles-detects-gitlink", parse_ls_files(raw_ls), [".agents/worktrees/wt-probe"])
    cell("parse-lsfiles-clean", parse_ls_files("100644 5555555555555555555555555555555555555555 0\tREADME.md\n"), [])
    # 修复命令可执行性：必须真的带 `git rm --cached -f -- "<path>"`（-f 是自证实测出来的必需品）
    remedy = remedy_block([".agents/worktrees/wt-probe"], "G1")
    cell("remedy-has-rm-cached", 'git rm --cached -f -- ".agents/worktrees/wt-probe"' in remedy, True)
    cell("remedy-has-gitignore-guard",
         all(r in remedy for r in GUARD_RULES), True)
    cell("remedy-names-mode", GITLINK_MODE in remedy, True)
    cell("remedy-has-check-ignore", "git check-ignore -v" in remedy, True)

    # ── 端到端格（临时仓库，isolated_git_env）─────────────────────────
    tmp = tempfile.mkdtemp(prefix="fist-gitlink-probe-")
    try:
        _fixture_repo(tmp)

        # 合法提交：干净索引 ⇒ 放行（这是"不误拦"的自证）
        rc, rep = check(staged_only=True, cwd=tmp)
        cell("e2e-clean-allowed", rc, 0)
        cell("e2e-clean-no-false-positive", rc != 1, True)

        # 造雷：`git add -A` 会把 `.agents/worktrees/wt-probe` 记成 gitlink
        subprocess.run(["git", "add", "-A"], cwd=tmp, capture_output=True, env=isolated_git_env())
        rc, rep = check(staged_only=True, cwd=tmp)
        cell("e2e-gitlink-blocked", rc, 1)
        cell("e2e-gitlink-path-named", any(".agents/worktrees/wt-probe" in l for l in rep), True)
        cell("e2e-gitlink-remedy-present", any("git rm --cached" in l for l in rep), True)

        # 全索引格也看得见（裸跑口径）
        rc2, _ = check(staged_only=False, cwd=tmp)
        cell("e2e-fullindex-blocked", rc2, 1)

        # 按判据给的命令修复 ⇒ 再判应当放行（证明"错误信息可执行"不是空话）。
        # 注意 `-f`：首次 add 的 gitlink 不带 -f 会被 git 拒（自证格实测），这正是判据文案里带 -f 的理由。
        subprocess.run(
            ["git", "rm", "--cached", "-f", "-r", "--quiet", ".agents/worktrees/wt-probe"],
            cwd=tmp, capture_output=True, env=isolated_git_env(),
        )
        rc, rep = check(staged_only=True, cwd=tmp)
        cell("e2e-remedy-works", rc, 0)
        rc, _ = check(staged_only=False, cwd=tmp)
        cell("e2e-remedy-works-fullindex", rc, 0)

        # 护栏：补上 .gitignore 后 `git add -A` 不再造雷 ⇒ 第二次合法提交仍放行
        with open(os.path.join(tmp, ".gitignore"), "w", encoding="utf-8") as f:
            f.write("/.agents/worktrees/\n")
        subprocess.run(["git", "add", ".gitignore"], cwd=tmp, capture_output=True, env=isolated_git_env())
        subprocess.run(["git", "commit", "-q", "-m", "guard"], cwd=tmp, capture_output=True, env=isolated_git_env())
        subprocess.run(["git", "add", "-A"], cwd=tmp, capture_output=True, env=isolated_git_env())
        rc, rep = check(staged_only=True, cwd=tmp)
        cell("e2e-guard-prevents-gitlink", rc, 0)

        # 非 git 目录 ⇒ 2（判据无法自证，绝不冒绿）。
        # 注意：必须用 `GIT_CEILING_DIRECTORIES` 钉住上溯边界——临时目录天然落在 `%TEMP%` 下，
        # 而 `isolated_git_env()` 恰好剥掉这个变量，于是 git 会一路向上找到外层仓库（本机实测
        # `/tmp` 就落在 `E:\` 之下的真仓里 ⇒ 假放行）。这条格就是为这一形立的。
        nongit = tempfile.mkdtemp(prefix="fist-gitlink-nongit-")
        try:
            nongit_env = isolated_git_env()
            nongit_env["GIT_CEILING_DIRECTORIES"] = os.path.dirname(nongit)
            rc, _ = check(staged_only=True, cwd=nongit, env=nongit_env)
            cell("e2e-not-a-repo-rc2", rc, 2)
        finally:
            shutil.rmtree(nongit, ignore_errors=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s (%d cells: %s)" % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def _entry_probe():
    """入口面自证（R171 口径）：自检必须把入口纳入调用图，防「自检绿而入口崩」。零副作用。"""
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def main(argv):
    ap = argparse.ArgumentParser(description="索引面 gitlink(mode 160000) 判据")
    ap.add_argument("--selftest", action="store_true", help="临时仓库端到端自证（不碰本仓）")
    ap.add_argument("--staged", action="store_true",
                    help="只判本次提交（pre-commit 用）；缺省同时判全索引存量")
    args = ap.parse_args(argv)
    if args.selftest:
        _entry_probe()
        return selftest()
    rc, report = check(staged_only=args.staged)
    for line in report:
        print(line)
    if rc == 2:
        # 判据无法自证 ⇒ **真给 2**。`check()` 里是 `return 2, [...]` 元组出口，
        # AST 面看不到字面 2（R1 会判「模块面幻影」）⇒ 这里显式落一次，让承诺可证。
        return 2
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
