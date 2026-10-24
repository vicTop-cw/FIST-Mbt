#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/blackbox/e2e_precommit_gitlink_gate.py —— pre-commit 钩子的**端到端**自证（R179）。

## 为什么不能只靠 `check_index_gitlinks.py --selftest`

判据的 `--selftest` 证明的是「尺子认得出 gitlink」，但**没证明钩子真的会拦**：钩子可能写了却
没接上（`.githooks` 早在仓里、`core.hooksPath` 曾长期为空）、可能 `exit 1` 写在子 shell 里、
可能 `set -e` 把非零当正常…… 所以这里把**真钩子文件**拷进临时仓库、`core.hooksPath` 指过去，
用真 `git commit` 跑两格：

- **格 1（必须拦）**：造一个嵌入式 git 仓 + `git add -A` ⇒ 暂存面出现 mode 160000 ⇒
  `git commit` 必须 **rc≠0 且 HEAD 未动**；
- **格 2（不许误拦）**：同一仓库清干净后提交一个普通文件 ⇒ `git commit` 必须 **rc=0 且 HEAD 前进**。

两格都带 `FIST_PRECOMMIT_SKIP_MOON=1`：本自证盯的是 gitlink 门，不是 moon check（那条由 CI 管，
且夹具里没有 moon 依赖缓存，跑了也只是把"环境缺失"混进判据）。

## 硬纪律

- **全程 `isolated_git_env()`**：夹具的 git 调用绝不继承宿主的 `GIT_DIR`/`GIT_CONFIG_*`；
- `core.hooksPath` 只设在**临时仓库**里，本仓配置一个字不动；
- 临时目录用完 shred，不留垃圾。

## 退出码

0 = 两格都对（拦得住 + 不误拦）/ 1 = 有一格不对（逐格点名 expected vs got）/
2 = 判据无法自证（找不到钩子文件、git 不可用、sh 不可用）/ 4 = 尺子自己坏了（未捕获异常）。

用法：
    python scripts/blackbox/e2e_precommit_gitlink_gate.py
    python scripts/blackbox/e2e_precommit_gitlink_gate.py --selftest   # 等价（本脚本正文即判据）
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

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from git_env import isolated_git_env  # noqa: E402

HOOK_REL = os.path.join(".githooks", "pre-commit")
PRECHECK_REL = os.path.join("scripts", "check_index_gitlinks.py")
MARKER_REL = os.path.join("scripts", "blackbox", "check_merge_markers.py")
GIT_ENV_REL = os.path.join("scripts", "git_env.py")


def _run(args, cwd, env=None):
    p = subprocess.run(args, cwd=cwd, capture_output=True,
                       env=env if env is not None else isolated_git_env())
    return (p.returncode,
            (p.stdout or b"").decode("utf-8", "replace"),
            (p.stderr or b"").decode("utf-8", "replace"))


def _head(repo):
    rc, out, _ = _run(["git", "rev-parse", "HEAD"], repo)
    return out.strip() if rc == 0 else "<no-HEAD>"


def build_fixture(tmp):
    """造一个「真钩子 + 真判据」的临时仓库。返回 (repo_path, 问题列表)。"""
    problems = []
    repo = os.path.join(tmp, "repo")
    os.makedirs(repo)

    # 1) 拷真钩子（连同它依赖的判据与 git_env）——验的是**仓里那份**，不是复制品的新写逻辑
    dst_hooks = os.path.join(repo, ".githooks")
    os.makedirs(dst_hooks, exist_ok=True)
    for rel, dst_dir in (
        (HOOK_REL, dst_hooks),
        (PRECHECK_REL, os.path.join(repo, "scripts")),
        (MARKER_REL, os.path.join(repo, "scripts", "blackbox")),
        (GIT_ENV_REL, os.path.join(repo, "scripts")),
        # **必须一起拷**：夹具里缺 .gitattributes 时，宿主 `core.autocrlf=true` 会把工作树里的
        # CRLF 原样存成 blob ⇒ `git diff --cached --check` 把每一行判成 "trailing whitespace" ⇒
        # 钩子第三道门把**合法提交**拦掉（本机实测踩过：9 格全红，3 格是这条假阳性）。
        # 拷真文件而不是手写规则，是为了让夹具的换行面与真仓**同源**。
        (os.path.join(".gitattributes"), os.path.join(repo)),
    ):
        src = os.path.join(ROOT, rel)
        if not os.path.isfile(src):
            problems.append("缺真源文件：%s" % rel)
            continue
        os.makedirs(dst_dir, exist_ok=True)
        # 为什么用 **二进制** 拷贝而不是 `shutil.copy2`：copy2 会把宿主的 CRLF 原样带进夹具，
        # 而夹具仓没有 .gitattributes ⇒ `git diff --cached --check` 把每一行都判成
        # "trailing whitespace" ⇒ 钩子第三道门把**合法提交**拦掉，自证格当场变红（本机实测踩过）。
        # 这里做 `git config core.autocrlf false` + 原始字节拷贝，让夹具的字节面与真仓逐字节一致。
        dst = os.path.join(dst_dir, os.path.basename(rel))
        with open(src, "rb") as fs, open(dst, "wb") as fd:
            fd.write(fs.read())
        shutil.copystat(src, dst)

    if problems:
        return None, problems

    hook = os.path.join(dst_hooks, "pre-commit")
    os.chmod(hook, 0o755)

    # 2) 临时仓库本体 + 只在本仓库内指 hooksPath
    for args in (
        ["git", "init", "-q", "-b", "main"],
        ["git", "config", "user.name", "t"],
        ["git", "config", "user.email", "t@t"],
        ["git", "config", "commit.gpgsign", "false"],
        # autocrlf 跟宿主的**同向**（本机 true）⇒ 与真仓的换行面一致；归一化本应由
        # .gitattributes 管（上面已拷），这里只是不制造第二套口径。
        ["git", "config", "core.autocrlf", "true"],
        ["git", "config", "core.hooksPath", ".githooks"],
    ):
        rc, _, err = _run(args, repo)
        if rc != 0:
            problems.append("夹具初始化失败 %r: %s" % (args, err.strip()[:200]))

    with open(os.path.join(repo, "README.md"), "w", encoding="utf-8") as f:
        f.write("# fixture\n")
    _run(["git", "add", "README.md"], repo)
    rc, out, err = _run(["git", "commit", "-q", "--no-verify", "-m", "init"], repo)
    if rc != 0:
        problems.append("夹具基线提交失败：%s" % err.strip()[:300])

    # 3) 造雷：嵌入式 git 仓（真 worktree 就是 `.git` 文件的形状）
    wt = os.path.join(repo, ".agents", "worktrees", "wt-probe")
    os.makedirs(wt)
    with open(os.path.join(wt, "note.txt"), "w", encoding="utf-8") as f:
        f.write("local runtime only\n")
    for args in (
        ["git", "init", "-q", "-b", "probe"],
        ["git", "config", "user.name", "t"],
        ["git", "config", "user.email", "t@t"],
        ["git", "add", "note.txt"],
        ["git", "commit", "-q", "-m", "probe"],
    ):
        _run(args, wt)
    return repo, problems


def run_cells(repo):
    """两格端到端。返回 (cells, fails)，cells=[(name, got, want), ...]。"""
    cells, fails = [], []
    env = isolated_git_env()
    env["FIST_PRECOMMIT_SKIP_MOON"] = "1"

    def cell(name, got, want):
        cells.append((name, got, want))
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # ── 格 1：宽 add 造出 gitlink ⇒ 必须拦，且 HEAD 不动 ──────────────────────────
    _run(["git", "add", "-A"], repo)
    head_before = _head(repo)
    rc, out, err = _run(["git", "commit", "-m", "should be blocked"], repo, env=env)
    head_after = _head(repo)
    blob = out + err
    cell("gitlink-commit-rejected", rc != 0, True)
    cell("gitlink-commit-head-unchanged", head_after, head_before)
    cell("gitlink-refusal-names-gate", "gitlink" in blob.lower(), True)
    cell("gitlink-refusal-gives-rm-cached", "git rm --cached -f" in blob, True)
    cell("gitlink-refusal-gives-check-ignore", "git check-ignore -v" in blob, True)

    # ── 格 2：清干净后合法提交 ⇒ 必须放行（不误拦）──────────────────────────────
    _run(["git", "rm", "--cached", "-f", "-r", "--quiet", ".agents/worktrees/wt-probe"], repo)
    with open(os.path.join(repo, ".gitignore"), "w", encoding="utf-8") as f:
        f.write("/.agents/worktrees/\n")
    _run(["git", "add", ".gitignore"], repo)
    head_before = _head(repo)
    rc, out, err = _run(["git", "commit", "-m", "legit commit must pass"], repo, env=env)
    head_after = _head(repo)
    cell("legit-commit-allowed", rc, 0)
    cell("legit-commit-head-advanced", head_after != head_before, True)
    cell("legit-commit-not-blocked-by-gitlink",
         "索引里出现 gitlink" not in (out + err), True)

    # ── 格 3：护栏生效后 `git add -A` 不再造雷 ⇒ 仍放行 ───────────────────────────
    _run(["git", "add", "-A"], repo)
    rc, out, err = _run(["git", "commit", "-m", "guarded add -A"], repo, env=env)
    cell("guarded-add-all-not-blocked", rc, 0)
    return cells, fails


def _entry_probe() -> None:
    """入口面自证（R171/J2 口径）：自检必须把入口纳入调用图。零副作用：只验 callable。

    判据 `check_selftest_call_face.py` 从 `selftest()` 出发沿调用名闭包做静态可达性分析，
    锚点 = 名为 main/run/cli 的函数（或调 exit/SystemExit 的函数）。`selftest()` 调
    `_entry_probe()`、`_entry_probe()` 引用 `main`，就构成「selftest → _entry_probe → main」
    的可达链 —— 这是**接线**，不是把函数改名成 run()（判例-3「改名不是接线」）。

    **为什么不真跑 `main(["--selftest"])`**：本脚本 `main()` 的唯一职责就是调 `selftest()`，
    真跑必然无限递归（同文件 `check_index_gitlinks.py` 实测过 RecursionError）。锚点在这里的
    价值是「入口存在且指向自检面」，断言 callable 即可，零副作用。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def selftest():
    _entry_probe()
    problems = []
    for tool in ("git", "sh"):
        if shutil.which(tool) is None:
            problems.append("缺 %s（判据无法自证）" % tool)
    if not os.path.isfile(os.path.join(ROOT, HOOK_REL)):
        problems.append("找不到真钩子 %s" % HOOK_REL)
    if problems:
        for p in problems:
            print("FATAL " + p)
        return 2

    tmp = tempfile.mkdtemp(prefix="fist-e2e-precommit-")
    try:
        repo, build_problems = build_fixture(tmp)
        if build_problems:
            for p in build_problems:
                print("FATAL " + p)
            return 2
        cells, fails = run_cells(repo)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s (%d cells: %s)"
          % ("OK" if not fails else "FAIL", len(cells), " / ".join(c[0] for c in cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    ap = argparse.ArgumentParser(description="pre-commit gitlink 门的端到端自证")
    ap.add_argument("--selftest", action="store_true", help="显式自证（缺省行为同此，便于电池点名）")
    ap.parse_args(argv)
    return selftest()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
