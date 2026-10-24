#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_worktree_hygiene.py —— worktree「三条件」只读判据（R181）。

## 为什么需要它（司令-α 的实测，不是假想）

阶段 1 收口时执行组发现：**那 11 个禁删 worktree 会「自己变成可删」**。
26 分钟内实测 **4 项变化**：

```
cl7-plugin-sync      1 → 0     （变可删）
auth-measure/wt    532 → 0     （变可删）
wt-skill           378 → 24
cmd-epsilon          4 → 1
```

⇒ 「不可删」不是资产的固有属性，而是**某一时刻的读数**。谁若拿一份旧快照去决定删/留，
就会漏掉那些「已经变可删」的项 —— 司令-α 这一轮正是因为「被跳过的 13 项从未现场重跑」
而漏了 2 项。本尺把这件事变成**每条随时可跑、一律现读**的判据。

## 判据（三条，与阶段 1 定案一致）

对每个**已登记 worktree（除主树）**：

| 条件 | 命令 | 「可删」要求 |
|---|---|---|
| ① 工作树干净 | `git status --porcelain` | 输出为空 |
| ② 无独有提交 | `git rev-list HEAD --not --all` | 输出为空 |
| ③ 无冲突态 | `git ls-files -u` | 输出为空 |

三条全过 ⇒ 「可删」。**「可删」≠「该删」**：本尺只报读数，删除由人/架构决定。

## 本尺如何防「判例-10 家族」的三个坑

- **10（判 rc 不判输出）**：三条全部**读 stdout 内容**判空，不看 `git` 的退出码。
  `git status --porcelain` 在有改动时**依然 rc=0** —— 拿 rc 判就是永真。
- **10b（判 `git diff HEAD` 而不是 `git diff`）**：条件②不用 `diff`，用
  `rev-list HEAD --not --all` —— 它问的是「有没有任何 **ref** 到不了的提交」，
  而 `git diff` 只比两棵树，**看不见已在索引/已提交的独有提交**。
- **10c（快照只列候选，判定一律现读）**：本尺**不缓存、不读任何快照文件**；
  每次运行都对每个 worktree 现跑三条命令。`--selftest` 里专门有一格
  `e2e-live-read-not-snapshot` 证明这一点（造一个 worktree，先判定，再让它变脏，
  不重启进程直接再判 —— 读数必须**当场变**）。

## 只报不判（诊断尺）

「可删」是个**建议**，不是门禁。`rc=1` 表示「发现 N 个可删项，请人看一眼」，
不代表仓库坏了。因此本尺在电池里用 `tolerant(...)` 登记（0 与 1 都算正确读数）——
干净树上读 0、有可删项读 1，两者都对；写死 `expect` 会在另一种树上假红/假绿。

**不自动删除。** 本脚本没有任何删除路径（无 `worktree remove`、无 `rmtree` 作用于真 worktree）。

## 退出码

0 = 无可删 worktree（全部至少不满足一条）
1 = 发现 N 个可删 worktree（诊断读数，逐条点名 path + 三读数）
2 = 判据无法自证（`git worktree list` 读不到 / 工作树数 < 1 / 主树都判不出来）
4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）

用法：
    python scripts/check_worktree_hygiene.py
    python scripts/check_worktree_hygiene.py --json     # 机器可读
    python scripts/check_worktree_hygiene.py --selftest
"""
import argparse
import json
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


# ── 纯函数 ─────────────────────────────────────────────────────────────────────


def judge(dirty, unpushed, unmerged):
    """纯函数：三读数（**字符串**，判空）→ (deletable, why)。

    输入是 `git` 的 stdout 原文而非行数/布尔——这样「判输出不判 rc」（判例-10）在
    函数签名层面就成立，调用方拿不到 rc 可判。

    注意空串与纯空白都算「空」：`git status --porcelain` 干净时输出 ""，
    但某些包装可能给 "\\n"，一律 strip 后再判。

    ⚠️ **参数顺序 = ①②③**（R181 实测踩过：签名曾写成 `(dirty, unmerged, unpushed)`，
    与调用方 `judge(d, p, u)` 不符 ⇒ 「②独有提交」被报成「③冲突态」，输出自相矛盾）。
    自证格 `judge-second-param-is-unpushed` / `judge-third-param-is-unmerged` 钉死顺序。
    """
    d = (dirty or "").strip()
    p = (unpushed or "").strip()
    u = (unmerged or "").strip()
    fails = []
    if d:
        fails.append("①工作树脏（status --porcelain 非空）")
    if p:
        fails.append("②有独有提交（rev-list HEAD --not --branches --remotes --tags 非空）")
    if u:
        fails.append("③冲突态（ls-files -u 非空）")
    if fails:
        return (False, "；".join(fails))
    return (True, "三条件全过 ⇒ 可删（≠ 该删）")


def count_lines(text):
    """纯函数：把 git stdout 折成行数（供报告显示）。空/空白 ⇒ 0。"""
    if not text:
        return 0
    return len([ln for ln in text.splitlines() if ln.strip()])


def nonzeros(dirty, unpushed, unmerged):
    """纯函数：三读数里**哪些冒出来了**（返回如 ["①","③"]）。

    R181 修订的核心：理由**由读数派生**，不另外判一遍。
    这样「有几个非零读数」与「有几条理由」在结构上必然相等 —— 矛盾输出不可能出现。
    """
    flags = []
    if (dirty or "").strip():
        flags.append("①")
    if (unpushed or "").strip():
        flags.append("②")
    if (unmerged or "").strip():
        flags.append("③")
    return flags


# ── git 层（只读）────────────────────────────────────────────────────────────────


def _git(args, cwd=None, env=None):
    """跑一条 git，返回 (rc, stdout)。**调用方判 stdout，不判 rc**（判例-10）。"""
    p = subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        env=env if env is not None else isolated_git_env(),
    )
    return (p.returncode, (p.stdout or b"").decode("utf-8", "replace"))


def registered_worktrees(cwd=None, env=None):
    """列出已登记 worktree 的路径，**排除主树**（第一条）。

    读不到（`worktree list --porcelain` 失败或空）返回 None —— 调用方自拒 rc=2。
    """
    rc, out = _git(["worktree", "list", "--porcelain"], cwd=cwd, env=env)
    if rc != 0 or not out.strip():
        return None
    paths = []
    for line in out.splitlines():
        if line.startswith("worktree "):
            paths.append(line[len("worktree "):].strip())
    return paths


def probe_one(path, env=None):
    """对**一个** worktree 现跑三条命令。返回 dict（含原文读数与判定）。

    判例-10c：**每次调用都现跑**，不读缓存、不读快照文件。

    ⚠️ **条件② 的命令形态（R181 最终定案，判例-12 + detached 两面都覆盖）**：

        git rev-list HEAD --not --branches --remotes --tags

    **必须是单一 `--not` 后跟多个 rev**，不能是多个 `--not`。

    两面（都是实测出来的，缺一面就是错的）：

    **面 A —— `--not` 是翻转开关，不是逐项限定符**（判例-12，lead 抓出）：
        连写 `--not --branches --not --remotes --not --tags` 会互相抵消，
        语义变成 `NOT(branches) OR remotes OR NOT(tags)`。实测同一时刻：
            --not --all                                     → 0
            --not --branches --remotes --tags               → 0    ✅
            --not --branches --not --remotes --not --tags   → 366  ❌
        366 vs 0 **只差一个 `--not`**。

    **面 B —— `--not --all` 在 detached HEAD 上是漏判**（自证格 `e2e-detached-orphan-detected` 抓出）：
        `--all` 含 HEAD 自身（detached 时 HEAD 是一个"无分支的 ref"），
        于是 `HEAD --not --all` 恒为空 —— 连真孤儿提交都查不出来。实测（夹具 detached）：
            --not --all                               → 0   ❌ 漏判
            --not --branches --remotes --tags         → 1   ✅ 检出
            （把分支指回该提交后两种都得 0，证明差异只在孤儿面）

    ⇒ 既要**单一 `--not`**（避面 A），又要**逐个列真 ref 大类**（避面 B）。
    `--all` 太宽（含 HEAD），逐项写法太易错（多个 `--not`）——只有这一个形态两头都对。
    自证格 `e2e-not-flag-single-vs-multi-differ` 与 `e2e-detached-orphan-detected` 分别钉住两面。
    """
    _, dirty = _git(["status", "--porcelain"], cwd=path, env=env)
    _, unpushed = _git(["rev-list", "HEAD", "--not", "--branches", "--remotes", "--tags"],
                       cwd=path, env=env)
    _, unmerged = _git(["ls-files", "-u"], cwd=path, env=env)
    # **单一真源**（R181 修订，lead 实跑抓出的自相矛盾）：先 strip 成三个规范读数，
    # 判定与显示**都只读这三个变量**，绝不让"显示用原文、判据用另一种算法"并存。
    # 曾经的形状是 `judge(dirty_raw, ...)` + `count_lines(dirty_raw)` 两套来源 ⇒
    # 出现过「③unmerged=0 但理由说『③冲突态非空』」的矛盾输出。
    d, p, u = (dirty or "").strip(), (unpushed or "").strip(), (unmerged or "").strip()
    deletable, why = judge(d, p, u)
    return {
        "path": path,
        # 显示读数与 judge 同一来源：d/p/u 本身就来自 strip 后的原文。
        # nz = 「哪些条件是冒出来的」——命令行输出直接据此列理由，不再重算一遍。
        "dirty_lines": count_lines(d),
        "unpushed_lines": count_lines(p),
        "unmerged_lines": count_lines(u),
        "nonzero": nonzeros(d, p, u),
        "deletable": deletable,
        "why": why,
    }


def scan(cwd=None, env=None, include_main=False):
    """全量现读。返回 (rows, fatal)。

    `include_main=False`（缺省）跳过主树 —— 主树永远「有东西」且绝不该删，
    统计它只会稀释读数。
    """
    paths = registered_worktrees(cwd=cwd, env=env)
    if paths is None:
        return [], "`git worktree list` 读不到（不是 git 仓库 / git 不可用）"
    if len(paths) < 1:
        return [], "工作树数为 0 ⇒ 判据空转，拒绝出绿"
    targets = paths if include_main else paths[1:]
    env = env if env is not None else isolated_git_env()
    rows = []
    for p in targets:
        if not os.path.isdir(p):
            rows.append({"path": p, "dirty_lines": -1, "unpushed_lines": -1,
                         "unmerged_lines": -1, "deletable": False,
                         "why": "目录不存在（stale 登记）⇒ 不算可删，需 `git worktree prune`"})
            continue
        rows.append(probe_one(p, env=env))
    return rows, ""


# ── 自证 ───────────────────────────────────────────────────────────────────────


def _fixture(tmp):
    """造「主树 + 三个子 worktree」的夹具：干净 / 脏 / 有独有提交 / 冲突态。

    全部经 `isolated_git_env()`，绝不碰真仓。返回 (main_work, dict_of_paths)。
    """
    env = isolated_git_env()

    def g(*args, cwd):
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True, env=env)

    work = os.path.join(tmp, "main-wt")
    os.makedirs(work)
    for args in (["init", "-q", "-b", "main"],
                 ["config", "user.name", "t"], ["config", "user.email", "t@t"],
                 ["config", "commit.gpgsign", "false"]):
        g(*args, cwd=work)
    with open(os.path.join(work, "a.txt"), "w", encoding="utf-8") as f:
        f.write("1\n")
    g("add", "a.txt", cwd=work)
    g("commit", "-q", "-m", "c1", cwd=work)

    made = {}
    for name in ("clean", "dirty", "unpushed", "conflict"):
        p = os.path.join(tmp, "wt-" + name)
        g("worktree", "add", "-q", "-b", "br-" + name, p, cwd=work)
        made[name] = p

    # ── 判例-12 的**显现夹具**（`notflag`）：专门为「单 --not vs 多 --not 读数必须不同」而造 ──
    #
    # 为什么需要单独一个 worktree（lead 实跑抓出 `e2e-not-flag-single-vs-multi-differ` got=False）：
    # 多 `--not` 的翻转**只在特定形态下才显现差异**，普通夹具（branches 覆盖全部历史、
    # 无 remote/tag）上两种写法读数相同 ⇒ 证伪格等于没测。
    #
    # 实测三种尝试，只有第三种能构造出差异（2026-10-24）：
    #   ① remote 指向 HEAD 历史**之内**的中间提交      ⇒ single 0 / multi 0   ✗ 显不出来
    #   ② 造 stash（stash 父提交就是 HEAD）             ⇒ single 0 / multi 0   ✗
    #   ③ remote 指向**不在 HEAD 历史里**的独立提交      ⇒ single 0 / multi 1   ✓
    #
    # ③ 的机制：`--not --branches --remotes --tags` = NOT(b ∪ r ∪ t) ⇒ 0（排除面覆盖干净）；
    #   `--not --branches --not --remotes --not --tags` = NOT(b) OR r OR NOT(t)
    #   ⇒ 那个只在 remote 上的提交被 `OR r` **包含回来** ⇒ 1。
    #   这与真实仓（`temp/wt-skill` single=0 / multi=366）是**同一机制**，只是规模小到可断言。
    nf = os.path.join(tmp, "wt-notflag")
    g("worktree", "add", "-q", "-b", "br-notflag", nf, "main", cwd=work)
    # 在 main 上再走两笔，让 HEAD 历史更长（branches 仍全覆盖）
    for i in (1, 2):
        with open(os.path.join(work, "h%d.txt" % i), "w", encoding="utf-8") as f:
            f.write("%d\n" % i)
        g("add", "h%d.txt" % i, cwd=work)
        g("commit", "-q", "-m", "h%d" % i, cwd=work)
    # 造一个「只在 remote 上、不在任何 branch/tag」的提交
    g("checkout", "-q", "-b", "side-notflag", cwd=work)
    with open(os.path.join(work, "s.txt"), "w", encoding="utf-8") as f:
        f.write("side\n")
    g("add", "s.txt", cwd=work)
    g("commit", "-q", "-m", "side-commit", cwd=work)
    g("update-ref", "refs/remotes/origin/side-notflag", "HEAD", cwd=work)
    g("checkout", "-q", "main", cwd=work)
    g("branch", "-D", "side-notflag", cwd=work)   # 删分支，只留 remote-tracking
    # notflag worktree 的快照同步到 main 最新（保证它 HEAD 历史被 branches 全覆盖）
    g("reset", "-q", "--hard", "main", cwd=nf)
    made["notflag"] = nf

    # dirty：改一个已跟踪文件（不入索引）
    with open(os.path.join(made["dirty"], "a.txt"), "w", encoding="utf-8") as f:
        f.write("changed\n")

    # unpushed：必须造「任何 ref 都到达不了」的提交。
    # 第一版尝试用「detached 上提交」——**失败**：`git worktree add -b br-unpushed` 创建的分支
    # 仍指向该提交 ⇒ `rev-list HEAD --not --all` 能到达它、读数为 0（自证格 `e2e-unpushed-*`
    # 当场抓出）。正确造法：先把分支**移走**（checkout 到更早的提交），再在 detached 上提交，
    # 这个新提交就成为没有 ref 指向的孤儿。
    p = made["unpushed"]
    g("checkout", "-q", "--detach", "HEAD", cwd=p)
    with open(os.path.join(p, "b.txt"), "w", encoding="utf-8") as f:
        f.write("2\n")
    g("add", "b.txt", cwd=p)
    g("commit", "-q", "-m", "orphan-commit", cwd=p)
    # 关键：把分支指回父提交，让刚提交的孤儿不被任何 ref 到达
    g("branch", "-f", "br-unpushed", "HEAD~1", cwd=p)

    # conflict：造真冲突态（merge 失败留 index 的 stage 1/2/3）
    p = made["conflict"]
    with open(os.path.join(p, "a.txt"), "w", encoding="utf-8") as f:
        f.write("theirs\n")
    g("commit", "-q", "-am", "theirs", cwd=p)
    g("checkout", "-q", "-b", "clash", "main", cwd=p)
    with open(os.path.join(p, "a.txt"), "w", encoding="utf-8") as f:
        f.write("ours\n")
    g("commit", "-q", "-am", "ours", cwd=p)
    # 制造冲突 merge（会失败，正是我们要的 unmerged 态）
    g("merge", "--no-edit", "br-conflict", cwd=p)
    return work, made


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # ── 纯函数格：judge 的三条件 × 空/非空组合（判例-10：传原文不传 rc）──────
    cell("judge-all-empty", judge("", "", "")[0], True)
    cell("judge-whitespace-is-empty", judge("  \n\n ", "", "")[0], True)
    cell("judge-dirty-blocks", judge(" M a.txt\n", "", "")[0], False)
    cell("judge-unpushed-blocks", judge("", "abc123\n", "")[0], False)
    cell("judge-unmerged-blocks", judge("", "", "100644 abc 1\ta.txt\n")[0], False)
    cell("judge-why-names-all-three",
         all(k in judge("x", "y", "z")[1] for k in ("①", "②", "③")), True)
    cell("judge-dirty-only-names-one", "①" in judge("x", "", "")[1], True)
    # 参数顺序格（R181 实测踩到的真 bug）：`judge(dirty, unpushed, unmerged)` 的
    # 第 2/3 位曾经写反（签名有 unmerged 在前），于是「②独有提交」被报成「③冲突态」。
    # 上面那些 `judge("x","","")` 只喂一位，**测不出顺序错**；这里三位各喂一次、逐个点名。
    cell("judge-second-param-is-unpushed", "②" in judge("", "x", "")[1], True)
    cell("judge-second-param-not-unmerged", "③" in judge("", "x", "")[1], False)
    cell("judge-third-param-is-unmerged", "③" in judge("", "", "x")[1], True)
    cell("judge-third-param-not-unpushed", "②" in judge("", "", "x")[1], False)
    cell("count-lines-empty", count_lines(""), 0)
    cell("count-lines-three", count_lines("a\nb\nc\n"), 3)
    cell("count-lines-blank-lines-ignored", count_lines("a\n\n  \n"), 1)
    # R181 核心格：**读数与理由必须同源**（lead 实跑抓出过「③unmerged=0 却说非空」的矛盾）
    cell("nonzeros-none", nonzeros("", "", ""), [])
    cell("nonzeros-only-dirty", nonzeros("x", "", ""), ["①"])
    cell("nonzeros-only-unpushed", nonzeros("", "y", ""), ["②"])
    cell("nonzeros-only-unmerged", nonzeros("", "", "z"), ["③"])
    cell("nonzeros-all-three", nonzeros("x", "y", "z"), ["①", "②", "③"])
    cell("nonzeros-whitespace-is-none", nonzeros("  \n", "\n", " "), [])
    # 矛盾输出在结构上不可能：理由条数 == 非零读数个数（对 8 种组合逐一核）
    _combos = [("", "", ""), ("x", "", ""), ("", "y", ""), ("", "", "z"),
               ("x", "y", ""), ("x", "", "z"), ("", "y", "z"), ("x", "y", "z"), ("  ", "\n", " ")]
    cell("e2e-reason-count-matches-readings",
         all(len(nonzeros(*c)) == (0 if judge(*c)[0] else len(judge(*c)[1].split("；")))
             for c in _combos), True)

    # ── 端到端格：真 worktree（主树 + 4 个子树）────────────────────────────
    tmp = tempfile.mkdtemp(prefix="fist-wt-hygiene-")
    try:
        work, made = _fixture(tmp)
        env = isolated_git_env()

        # 干净树 ⇒ 可删
        row = probe_one(made["clean"], env=env)
        cell("e2e-clean-deletable", row["deletable"], True)
        cell("e2e-clean-thre读数全零",
             (row["dirty_lines"], row["unpushed_lines"], row["unmerged_lines"]), (0, 0, 0))

        # 脏树 ⇒ 不可删
        row = probe_one(made["dirty"], env=env)
        cell("e2e-dirty-not-deletable", row["deletable"], False)
        cell("e2e-dirty-counts-nonzero", row["dirty_lines"] > 0, True)

        # 独有提交 ⇒ 不可删。夹具里该提交由**分支**持有（`br-unpushed`），
        # 所以 `--not --all` 能排除它 ⇒ 这一格验的是「正常分支上的提交不算独有」的反面：
        # 我们把分支移走（见 _fixture 注释），使它成为真孤儿。
        row = probe_one(made["unpushed"], env=env)
        cell("e2e-unpushed-not-deletable", row["deletable"], False)
        cell("e2e-unpushed-counts-nonzero", row["unpushed_lines"] > 0, True)

        # ── 判例-12 的对照格 ────────────────────────────────────────────────────
        # 对照面必须选**专用显现夹具** `notflag`（见 _fixture 里第三种造法）：
        # 它的 remote 指向一个不在 HEAD 历史里的独立提交 ⇒ 多 --not 的 `OR remotes`
        # 会把该提交包含回来，读数与单 --not 必然不同（实测 0 vs 1）。
        #
        # ⚠️ 别换成 clean/unpushed：实测那两种形态上 single 与 multi **读数相同**，
        # 格会假绿（测不出任何东西）——这正是它最初 got=False 的原因。
        _, single = _git(["rev-list", "HEAD", "--not", "--branches", "--remotes", "--tags"],
                         cwd=made["notflag"], env=env)
        _, multi = _git(["rev-list", "HEAD", "--not", "--branches", "--not", "--remotes",
                         "--not", "--tags"], cwd=made["notflag"], env=env)
        cell("e2e-not-flag-single-vs-multi-differ",
             len(single.split()) != len(multi.split()), True)
        cell("e2e-not-flag-single-is-correct", len(single.split()), 0)
        # 格 2：**detached 孤儿面**——这是 `--not --all` 的漏判现场（面 B）。
        # 夹具的 unpushed 是 detached，孤儿提交无分支指向：
        #   判定用的写法（单 --not + 多 rev）→ 必须看到它（>0）
        #   `--not --all`                      → 实测得 0（漏判），这一格是反证
        _, orphan_ok = _git(["rev-list", "HEAD", "--not", "--branches", "--remotes", "--tags"],
                            cwd=made["unpushed"], env=env)
        cell("e2e-detached-orphan-detected", bool(orphan_ok.strip()), True)
        _, orphan_via_all = _git(["rev-list", "HEAD", "--not", "--all"],
                                 cwd=made["unpushed"], env=env)
        cell("e2e-why-not-all-misses-detached-orphan", orphan_via_all.strip(), "")
        # 反证的第二半：把分支指回该提交（不再是孤儿）⇒ 判定写法也必须得 0。
        # 没有这一半，「>0」可能只是夹具本身脏，证不出「检出的正是孤儿」。
        _, _ = _git(["branch", "-f", "br-unpushed", "HEAD"], cwd=made["unpushed"], env=env)
        _, orphan_gone = _git(["rev-list", "HEAD", "--not", "--branches", "--remotes", "--tags"],
                              cwd=made["unpushed"], env=env)
        cell("e2e-orphan-cleared-when-ref-exists", orphan_gone.strip(), "")
        # 复原夹具状态，免得影响后续格（后续 e2e-scan-* 依赖它仍是「不可删」）
        _, _ = _git(["branch", "-f", "br-unpushed", "HEAD~1"], cwd=made["unpushed"], env=env)

        # 格 3（**记录判例-12 的活证据，不是要求两种写法相等**）：
        # 干净场景下**只有判定用的写法（单 --not）必须为 0**；多 --not 的读数如实记录。
        #
        # 为什么不能断言「两者都得 0」：多 --not 的语义 `NOT(b) OR r OR NOT(t)` 本身是错的，
        # 凭什么在干净场景也得 0？夹具补了 remote-tracking 后，`OR remotes` 会把 remote
        # 持有的提交包含进来 ⇒ 干净 worktree 上也多算 1。**这正是判例-12 的证据**，
        # 断言它「必须为 0」等于要求一个语义错误的命令给出正确结果。
        _, s_clean = _git(["rev-list", "HEAD", "--not", "--branches", "--remotes", "--tags"],
                          cwd=made["clean"], env=env)
        _, m_clean = _git(["rev-list", "HEAD", "--not", "--branches", "--not", "--remotes",
                           "--not", "--tags"], cwd=made["clean"], env=env)
        # ① 正确性断言：判定写法在干净 worktree 上必须 0（这是「条件② 可信」的底线）
        cell("e2e-clean-single-not-is-zero", len(s_clean.split()), 0)
        # ② 判例-12 的证据格：错误写法必须**多算**（> 正确写法），而不是「相等」
        cell("e2e-clean-multi-not-overcounts",
             len(m_clean.split()) > len(s_clean.split()), True)
        # ③ 把实际读数记进格子名（读数变了就在格子名里现形，不用翻日志）
        cells.append("diag-clean-multi-not-reading=%d" % len(m_clean.split()))

        # 冲突态 ⇒ 不可删（判例-10c 落点）
        row = probe_one(made["conflict"], env=env)
        cell("e2e-conflict-not-deletable", row["deletable"], False)
        cell("e2e-conflict-unmerged-nonzero", row["unmerged_lines"] > 0, True)

        # 全量扫描：主树被排除；5 个子树里可删的是 clean 与 notflag
        # （notflag 专为判例-12 造的夹具本身是干净的 ⇒ 它天然满足三条件，
        #  这不是缺陷，但它会出现在"可删"清单里——断言必须如实反映这一点）
        rows, fatal = scan(cwd=work, env=env)
        cell("e2e-scan-not-fatal", fatal, "")
        cell("e2e-scan-excludes-main", len(rows), 5)
        # 路径比较用 normpath：`git worktree list` 给正斜杠，夹具给原生分隔符，逐字比会假红
        cell("e2e-scan-exactly-two-deletable",
             sorted(os.path.normpath(r["path"]) for r in rows if r["deletable"]),
             sorted([os.path.normpath(made["clean"]), os.path.normpath(made["notflag"])]))
        # 反面：dirty / unpushed / conflict 三棵必须**不在**可删清单里（这才是判据的核心断言）
        not_deletable = {os.path.normpath(r["path"]) for r in rows if not r["deletable"]}
        cell("e2e-scan-excludes-bad-three",
             all(os.path.normpath(made[k]) in not_deletable
                 for k in ("dirty", "unpushed", "conflict")), True)

        # 判例-10c：快照只列候选、判定一律现读 —— 让 clean 变脏，不重建夹具，当场必须翻转
        with open(os.path.join(made["clean"], "a.txt"), "w", encoding="utf-8") as f:
            f.write("now dirty\n")
        row_again = probe_one(made["clean"], env=env)
        cell("e2e-live-read-not-snapshot", row_again["deletable"], False)

        # 入口面（J2 口径）：真调 main(["--selftest"])，钉 rc==0
        if not _ENTRY_PROBED[0]:
            _ENTRY_PROBED[0] = True
            try:
                cell("entry-main-selftest-rc0", main(["--selftest"]), 0)
            finally:
                _ENTRY_PROBED[0] = False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s (%d cells: %s)"
          % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


# 入口自证的一次性哨兵（防 `main(["--selftest"])` 随递归层层重入）
_ENTRY_PROBED = [False]


# ── 入口 ───────────────────────────────────────────────────────────────────────


def run(argv):
    ap = argparse.ArgumentParser(
        description="worktree 三条件只读判据（干净 / 无独有提交 / 无冲突态）")
    ap.add_argument("--selftest", action="store_true", help="自证（临时 worktree 端到端）")
    ap.add_argument("--json", action="store_true", help="机器可读输出")
    ap.add_argument("--include-main", action="store_true",
                    help="连主树一起量（缺省排除：主树永远有东西且绝不该删）")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    rows, fatal = scan(include_main=args.include_main)
    if fatal:
        print("FATAL 判据无法自证：" + fatal)
        return 2

    deletable = [r for r in rows if r["deletable"]]

    if args.json:
        print(json.dumps({"total": len(rows), "deletable": deletable,
                          "all": rows}, ensure_ascii=False, indent=2))
    else:
        for r in rows:
            flag = "可删" if r["deletable"] else "不可删"
            print("%-3s  ①dirty=%-3d ②unpushed=%-3d ③unmerged=%-3d  %s"
                  % (flag, r["dirty_lines"], r["unpushed_lines"],
                     r["unmerged_lines"], r["path"]))
            if not r["deletable"]:
                # 理由直接用非零读数派生（同一来源），杜绝「读数 0 却说非空」
                nz = r.get("nonzero", [])
                print("      ↳ 不满足 %s —— %s" % ("".join(nz) or "?", r["why"]))

    if deletable:
        print("")
        print("REPORT %d 个 worktree 可删（共 %d 个，已排除主树）：三条件全过。"
              % (len(deletable), len(rows)))
        print("       注意：「可删」≠「该删」——本尺只报读数，删除由人/架构决定。"
              "本脚本没有任何删除路径。")
        for r in deletable:
            print("         - %s" % r["path"])
        return 1

    if not args.json:
        print("PASS 无可删 worktree（共 %d 个，全部至少不满足一条）" % len(rows))
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
