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
import signal
import io
import re
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


def dup_symbols(added, base_symbols):
    """纯函数：分支新增的符号名里，**base 已经有的**那些（R131）。

    R131 实测事故：`gitcode/slave/fix/store-open-preflight` 判 `ok`，真 cherry-pick 后
    **往 master 里插入了第二份同签名函数**（`SqliteStore::open_preflight_ok` 在 master 已存在 1 份，
    该支的 wbtest 文件也已逐字存在）—— 3-way 合并把"已存在"的内容又插了一遍，合进去**编译不过**。
    这是 `ok` 最危险的假阳形态：贴得上、树也变了，但变的是**重复**。
    判法：分支新增的 `pub fn X` 若 base 已有 X ⇒ 记 `duplicate`，不按 `ok` 放行。
    """
    return sorted({s for s in added if s in base_symbols})


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


def verdict(ahead, pick_rc, conflicts, has_merge, changed, added, base_symbols):
    """纯函数：**把三面判定合成一次结论**（R132）。

    为什么要有它：`ok` 的判定先后有三道工序 —— ① `classify`（贴得上否）→
    ② `adjust_kind`（贴完树有没有变）→ ③ `dup_symbols`（变的是不是**重复**）。
    原先这三道散在 `scan` 的循环体里，而 `--selftest` 只测 ①②③ 各自的纯函数
    ⇒ **"合起来是否按这个顺序生效"没人验**（判例-29：机制格 ≠ 实现路径格）。
    抽成一个纯函数后：接线只剩一行，自证可直接断言**组合结果**。
    """
    kind = adjust_kind(classify(ahead, pick_rc, conflicts, has_merge), changed)
    if kind == "ok":
        dups = dup_symbols(added, base_symbols)
        if dups:
            return "duplicate", ["重复符号: " + ", ".join(dups[:3])]
    return kind, conflicts


PROBE_FILE_CAP = 8

COUNT_RE = re.compile(r"([A-Za-z][A-Za-z0-9 _\-]{1,24}?|\u4e00-\u9fff{1,8})\s*(\d{1,6})")
# R164：「数字在前」形态（`(177 MCP tools)` / `共 26 格`）—— 反向一条。
# 为什么要两条：help_topics 的工具总数是 `(177 MCP tools)`，只有反向正则抓得到；
# 少了它，R163 那支只能靠分组计数（`[Board-DAG 27]`）判出来，**主计数反而看不见**。
COUNT_REV_RE = re.compile(r"(\d{1,6})\s+([A-Za-z][A-Za-z0-9_\-]*(?: [A-Za-z][A-Za-z0-9_\-]*)*)")


def count_marks(text):
    """从文本里抽「标签 → 数字」记号（`177 MCP tools` / `[Board-DAG 30]` / `共 26 格`）。

    为什么需要：判 `contained` 只比**行数**，而"支更新的那一行恰好是旧计数"这种情形
    行数比较看不出来（R161 实测：base=140 / 支=141，支多一行却是**旧版 174 工具**）。
    """
    out = {}
    for m in COUNT_RE.finditer(text):
        label = m.group(1).strip()
        try:
            out[label] = int(m.group(2))
        except ValueError:
            continue
    # R164：反向形态（数字在前）。**同 label 只认第一次出现**，避免后出现的噪声覆盖主计数。
    for m in COUNT_REV_RE.finditer(text):
        label = m.group(2).strip()
        try:
            n = int(m.group(1))
        except ValueError:
            continue
        if label and label not in out:
            out[label] = n
    return out


def count_regressions(branch_text, base_text, min_delta=1):
    """纯函数：**支相对 base 的计数倒退**（合并会造成数字变小 ⇒ 多半是旧版覆盖新版）。

    返回 [(label, sub_n, base_n)]，按标签序。`min_delta` 默认 1（任何变小都算）。
    ⚠️ 只报"同一标签下 支 < base"；标签集合不同不算（可能是新增段落）。
    """
    sub = count_marks(branch_text)
    basem = count_marks(base_text)
    bad = []
    for label in sorted(set(sub) & set(basem)):
        if sub[label] + min_delta <= basem[label]:
            bad.append((label, sub[label], basem[label]))
    return bad


def superseded_decision(regressions):
    """纯函数：出现**任何**计数倒退即判 `superseded`（空列表 ⇒ False）。

    刻意用"任一即真"而不是"多数"：一个数字倒退就足以说明这段文本是旧版，
    合并它会让用户看到更少的功能数（本仓 help_topics 正是这种）。
    """
    return bool(regressions)


def contained_decision(rows):
    """纯函数（R161）：冲突支的**内容是否已在 base**。

    `rows` = [(path, branch_lines, base_lines, missing_syms)]，逐文件一行：
      · `base_lines == -1` ⇒ base **没有**这个文件（不满足包含）；
      · `base_lines < branch_lines` ⇒ base 更短（不满足）；
      · `missing_syms` 非空 ⇒ 支里出现的顶层符号在 base 同名文件里找不到（不满足）。

    判定（**全满足**才算 contained）：
      1. 至少 1 个产品文件被触碰（空列表不算 —— 不能因为"没比较过"就给绿灯）；
      2. 每行都满足上面三条。

    ⚠️ 为什么单列成纯函数：本尺的老问题就是"机制能跑 ≠ 判定被正确接入"（判例-29）。
    纯函数让 `--selftest` 能直接喂数、并且能造**变异对照**（把某行改坏 ⇒ 结论翻面）。
    """
    if not rows:
        return False
    for _path, bl, basel, missing in rows:
        if basel < 0 or basel < bl or missing:
            return False
    return True


def superseded_probe(base, branch, prefixes=("src/", "scripts/", "cmd/", "plugins/")):
    """R162：对**冲突支**取"计数倒退"读数（只读 git）。返回 (bool, [(path, label, sub, base)])。"""
    rc, out = git("log", "--name-only", "--format=", "%s..%s" % (base, branch))
    if rc != 0:
        return False, []
    touched = sorted({ln.strip() for ln in out.splitlines() if ln.strip()})
    # R170b：**限量取样** —— 探针每文件要跑 2 次 `git show`（Windows 每次 50–100ms），
    # 大支动辄 30+ 文件 ⇒ 单支 70s。判"内容是否已在/是否被取代"**不需要看完全部文件**，
    # 扫前 PROBE_FILE_CAP 个就足够触发；未命中的支仍会落到昂贵路径（真 cherry-pick）拿最终结论。
    product = [p for p in touched if p.startswith(prefixes)][:PROBE_FILE_CAP]
    hits = []
    for p in product:
        rc_b, bt = git("show", "%s:%s" % (branch, p))
        rc_a, at = git("show", "%s:%s" % (base, p))
        if rc_b != 0 or rc_a != 0:
            continue
        for label, sub_n, base_n in count_regressions(bt, at):
            hits.append((p, label, sub_n, base_n))
    return superseded_decision(hits), hits


def content_contained_probe(base, branch,
                            prefixes=("src/", "scripts/", "cmd/", "docs/", "reports/")):
    # R181：**把 docs/ 与 reports/ 也纳入包含面**。实测动机：`docs/fist-gate-degraded-analysis-r41`
    # 的全部改动都是 docs（一份新报告 + 账本 3 行），R171 已把内容手工合入 ⇒ 内容确实"已含"，
    # 但旧探针只看产品面 ⇒ 返回"支未触碰产品文件" ⇒ 仍判 conflict（**已合过的支永远红着**）。
    # 对 append-only/只增不减的文档，行数比较依然成立。
    """R161：对**冲突支**取数，交给 `contained_decision` 裁。

    取数口径（全部只读 git，不碰工作树）：
      · 支触碰的文件 = 它自己那几笔提交的 `--name-only` 并集；
      · 只看**产品面**（`src/` `scripts/` `cmd/`）—— 文档/插件面不参与"内容是否已在"；
      · 逐文件比行数 + 比顶层符号（`fn/struct/enum/trait`）。
    返回 `(bool, 说明行列表)`。
    """
    rc, out = git("log", "--name-only", "--format=", "%s..%s" % (base, branch))
    if rc != 0:
        return False, []
    touched = sorted({ln.strip() for ln in out.splitlines() if ln.strip()})
    # R170b：**限量取样** —— 探针每文件要跑 2 次 `git show`（Windows 每次 50–100ms），
    # 大支动辄 30+ 文件 ⇒ 单支 70s。判"内容是否已在/是否被取代"**不需要看完全部文件**，
    # 扫前 PROBE_FILE_CAP 个就足够触发；未命中的支仍会落到昂贵路径（真 cherry-pick）拿最终结论。
    product = [p for p in touched if p.startswith(prefixes)][:PROBE_FILE_CAP]
    if not product:
        return False, ["支未触碰产品文件"]
    rows = []
    for p in product:
        rc_b, bt = git("show", "%s:%s" % (branch, p))
        rc_a, at = git("show", "%s:%s" % (base, p))
        bl = len(bt.splitlines()) if rc_b == 0 else 0
        basel = len(at.splitlines()) if rc_a == 0 else -1
        missing = []
        if rc_b == 0 and rc_a == 0:
            syms = set(re.findall(r"^\s*(?:pub )?(?:fn|struct|enum|trait) ([A-Za-z_][A-Za-z0-9_]*)",
                                  bt, re.M))
            have = set(re.findall(r"^\s*(?:pub )?(?:fn|struct|enum|trait) ([A-Za-z_][A-Za-z0-9_]*)",
                                  at, re.M))
            missing = sorted(syms - have)[:3]
        rows.append((p, bl, basel, missing))
    ok = contained_decision(rows)
    detail = []
    for p, bl, basel, missing in rows:
        detail.append("%s: base=%s/sub=%s%s" % (
            p, "缺" if basel < 0 else basel, bl,
            "" if not missing else " 符号缺:" + ",".join(missing)))
    return ok, detail


def branches(remotes, include="/slave/"):
    """列出候选分支。`include` 是**子串过滤**（默认 `/slave/`，R130 起可配）。

    R130 立据：`gitcode/*` 通道有 95 支未并入分支，但本尺只扫 `*/slave/*` ⇒ **那个面没有权威读数**。
    而三种"看起来能判待合并"的现成指标在本仓**全都不可信**（实测同一支：`git cherry` +0 /
    两点 diff 223842 行 / 三点 diff 13 行，逐行比对却证明内容已在 master）—— 唯一可信的判定是
    **真跑 cherry-pick**，也就是本尺在做的事。⇒ 把扫描面做成可配，而不是另造一个指标。
    """
    rc, out = git("for-each-ref", "--format=%(refname:short)", "refs/remotes")
    if rc != 0:
        return []
    names = []
    for line in out.splitlines():
        b = line.strip()
        if not b or b.endswith("/HEAD"):
            continue
        if include in b and any(b.startswith(r + "/") for r in remotes):
            names.append(b)
    return sorted(names)


def simulate(base, wt, commits):
    """在临时 worktree 里真跑 cherry-pick；返回 (rc, conflict_files, changed)。

    `changed`（R130）：全部 `--no-commit` 贴完之后，**树相对 base 是否真的有变化**。
    实测动机：`gitcode/fix/e2e-upgrade-mirror-escape-r2` 判 `ok`（补丁能干净贴上），
    但逐行比对证明该内容**已在 master** ⇒ 合它只会产生一个**空效果提交**。
    "能贴上" 与 "有内容" 不是一回事（判例-32/33 同族：工具给的是形状，不是状态）。
    """
    git("checkout", "-q", "--detach", base, cwd=wt)
    git("reset", "-q", "--hard", base, cwd=wt)
    for c in commits:
        rc, _ = git("cherry-pick", "--no-commit", c, cwd=wt)
        if rc != 0:
            _, conf = git("diff", "--name-only", "--diff-filter=U", cwd=wt)
            files = [f.strip() for f in conf.splitlines() if f.strip()]
            git("cherry-pick", "--abort", cwd=wt)
            return 1, files, False
    _, diff = git("diff", "--name-only", base, cwd=wt)
    changed = bool([f for f in diff.splitlines() if f.strip()])
    return 0, [], changed


def adjust_kind(kind, changed):
    """纯函数：`ok` 但树无变化 ⇒ `contained`（补丁贴上了，却没有任何内容）。

    R130 立据：`ok` 原先只表示"cherry-pick 不冲突"，不是"有内容可合"。
    """
    if kind == "ok" and not changed:
        return "contained"
    return kind


def scan(base, remotes, keep=False, limit=0, include="/slave/"):
    sweep_stale_worktrees()
    bs = branches(remotes, include)
    if limit:
        bs = bs[:limit]
    if not bs:
        print("scan: 通道里没有匹配 %r 的分支" % include)
        return [], 0
    tmp = tempfile.mkdtemp(prefix="mergeability-")
    wt = os.path.join(tmp, "wt")
    # R165：**`scan` 也必须 atexit 兜底** —— 本轮实测：多次普查被 `timeout` / 父 shell 退出杀掉后，
    # `finally` 没机会跑 ⇒ `%TEMP%` 里堆了 **27 个完整 checkout 的 worktree**，
    # 最终把系统吃到 `OSError [WinError 1455] 页面文件太小`（连 spawn 子进程都失败）。
    # `selftest` 从 BUG-409 起就有这层保护，`scan` 一直漏着（判例-33 同族：保护只加在一条路径上）。
    register_cleanup(tmp, wt)
    rc, out = git("worktree", "add", "--detach", wt, base)
    if rc != 0:
        print("FATAL 建临时 worktree 失败：%s" % out.strip()[:200])
        shutil.rmtree(tmp, ignore_errors=True)
        return [], 2
    rows = []
    # R131：base 侧既有的 `pub fn` 名集合（只算一次）
    _, sym_out = git("grep", "-h", "-E", "pub fn ", base, "--", "*.mbt")
    base_syms = set(re.findall(r"pub fn ([A-Za-z0-9_:]+)", sym_out))
    try:
        for b in bs:
            rc, out = git("rev-list", "--reverse", "%s..%s" % (base, b))
            commits = [c for c in out.split() if c] if rc == 0 else []
            # R170：**探针优先**。`contained` / `superseded` 两个结论只读 git 就能定
            # （实测 78s/支 的成本几乎全在"建 worktree + 真 cherry-pick"上），
            # 而通道里绝大多数支就是这两类 ⇒ 先跑探针，命中即短路。
            if commits:
                _c_ok, _c_detail = content_contained_probe(base, b)
                if _c_ok:
                    rows.append({"branch": b, "ahead": len(commits), "kind": "contained",
                                 "files": _c_detail})
                    print("  %s %-52s ahead=%-3d contained%s" % (
                        "=", b, len(commits),
                        ("  内容已含: " + _c_detail[0]) if _c_detail else ""))
                    continue
                _s_hit, _s_detail = superseded_probe(base, b)
                if _s_hit:
                    _d = ["%s: %s %s→%s" % (p, lab, s_n, b_n) for p, lab, s_n, b_n in _s_detail[:4]]
                    rows.append({"branch": b, "ahead": len(commits), "kind": "superseded",
                                 "files": _d})
                    print("  %s %-52s ahead=%-3d superseded  冲突 %d 个: %s" % (
                        "↓", b, len(commits), len(_d), ", ".join(_d[:2])))
                    continue
            pick_rc, files, changed = simulate(base, wt, commits) if commits else (0, [], False)
            _, mout = git("rev-list", "--merges", "%s..%s" % (base, b))
            has_merge = bool([m for m in mout.split() if m]) if commits else False
            _, adiff = git("diff", "%s...%s" % (base, b))
            added = re.findall(r"^\+\s*pub fn ([A-Za-z0-9_:]+)", adiff, re.M)
            # R132：三面合成收进纯函数 `verdict` —— 接线只剩这一行，自证可断言组合结果
            kind, files = verdict(len(commits), pick_rc, files, has_merge, changed, added, base_syms)
            rows.append({"branch": b, "ahead": len(commits), "kind": kind, "files": files})
            mark = {"ok": "✓", "contained": "=", "conflict": "✗", "merge": "M", "error": "!",
                    "duplicate": "⚠", "superseded": "↓"}[kind]
            # R133：`…` 会掩盖规模（4 个还是 40 个完全不同）——显式打**冲突文件总数**。
            # 实测依据：67 支同时列 `.githooks/pre-commit / .githooks/README.md / .gitattributes`
            # 曾让人以为"冲突高度集中、可批量解决"，其实是**字母序前三个**，真实冲突面很宽。
            if files:
                extra = "  冲突 %d 个: %s%s" % (len(files), ", ".join(files[:3]),
                                               " …" if len(files) > 3 else "")
            else:
                extra = ""
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


# R169：**信号路径也要清理**。`timeout` 发的是 SIGTERM，Python 默认**不跑 atexit** 就退出
# ⇒ R165 的 atexit 兜底在这条路径上等于没有（实测：被 timeout 杀掉后仍留 2 个 worktree）。
_CLEANUP_TARGETS = []


def sweep_stale_worktrees(verbose=True):
    """R169：**启动自愈** —— 清扫上次被硬杀遗留的临时 worktree。

    为什么必须这样做（实测）：Windows + Git-Bash 的 `timeout` 通过 TerminateProcess 终止进程，
    **`atexit` 与 `signal` 处理器都不会跑**（R169 kill-test：`timeout 45` 后仍留 2 个 worktree）。
    ⇒ 光靠"优雅退出的清理"在这平台上是**无效承诺**；唯一可靠的是**下次启动先扫**。

    只清**本脚本自己前缀**的路径（`mergeability-*`），不碰任何别人的 worktree；
    清理失败只告警不中断（清理是帮助，不是前置条件）。
    """
    rc, out = git("worktree", "list", "--porcelain")
    if rc != 0:
        return 0
    removed = 0
    tmp_root = tempfile.gettempdir()
    for block in out.split("\n\n"):
        path = ""
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line[len("worktree "):].strip()
        if not path:
            continue
        base = os.path.basename(os.path.dirname(path))
        if not base.startswith("mergeability-"):
            continue
        if not os.path.abspath(path).startswith(os.path.abspath(tmp_root)):
            continue  # 路径不在 temp 下 ⇒ 不是我们建的，绝不删
        git("worktree", "remove", "--force", path)
        parent = os.path.dirname(path)
        if os.path.isdir(parent):
            shutil.rmtree(parent, ignore_errors=True)
        removed += 1
    if removed:
        git("worktree", "prune")
        if verbose:
            print("  [自愈] 清扫上次遗留的临时 worktree：%d 个" % removed)
    return removed


def register_cleanup(tmp, wt):
    """登记一处临时 worktree：atexit（正常退出）+ 信号（被 kill）双路清理。"""
    _CLEANUP_TARGETS.append((tmp, wt))
    atexit.register(_cleanup_paths, tmp, wt)


def _on_signal(signum, _frame):
    for tmp, wt in list(_CLEANUP_TARGETS):
        try:
            _cleanup_paths(tmp, wt)
        except Exception:
            pass
    # 退出码沿用 shell 约定：SIGTERM ⇒ 143，SIGINT ⇒ 0（用户主动中断不算失败）
    sys.exit(0 if signum == signal.SIGINT else 143)


for _sig in (signal.SIGTERM, signal.SIGINT):
    try:
        signal.signal(_sig, _on_signal)
    except (ValueError, OSError):
        pass  # 非主线程/平台不支持 ⇒ 只剩 atexit 兜底（诚实降级，不静默冒充已接线）


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
    # R130：**"能贴上" ≠ "有内容"** —— 贴完树没变化 ⇒ contained（合了只是空提交）。
    # 变异对照（判例-29）：把 adjust_kind 的 `not changed` 去掉，本格立刻红。
    cell("adjust-ok-but-no-content-is-contained", adjust_kind("ok", False), "contained")
    cell("adjust-ok-with-content-stays-ok", adjust_kind("ok", True), "ok")
    cell("adjust-other-kinds-untouched", adjust_kind("conflict", False), "conflict")
    # R131：新增符号与 base 撞名 ⇒ 必须点名（否则合进去是重复定义，编译不过）
    cell("dup-symbols-detected", dup_symbols(["A", "B"], {"B", "C"}) == ["B"], True)
    cell("dup-symbols-clean", dup_symbols(["A"], {"C"}) == [], True)
    # R132：**三面合成**的组合结果（判例-29 补位：此前只测各工序，没测"合起来按序生效"）
    cell("verdict-ok-clean", verdict(1, 0, [], False, True, ["New"], {"Old"})[0], "ok")
    cell("verdict-ok-no-content-is-contained",
         verdict(1, 0, [], False, False, [], set())[0], "contained")
    v_dup = verdict(1, 0, [], False, True, ["SqliteStore::open_preflight_ok"],
                    {"SqliteStore::open_preflight_ok"})
    cell("verdict-ok-but-dup-symbol-is-duplicate", v_dup[0], "duplicate")
    cell("verdict-dup-lists-symbol", "open_preflight_ok" in v_dup[1][0], True)
    cell("verdict-conflict-untouched", verdict(1, 1, ["a.txt"], False, True, [], set())[0], "conflict")

    # R161：**冲突支的内容包含探针**（纯判据部分）。
    # 动机（实测）：`gitcode/slave/feat/wt-lifecycle-tools` 判 conflict（28 个），
    # 而逐层核实是"master 早已包含、且更演进"⇒ 需要一道"内容是否已在 base"的判据，
    # 否则 104 支里大部分 `conflict` 都无法分辨"真有待合内容"与"早就落地了"。
    cell("contained-decision-empty-is-false", contained_decision([]), False)
    cell("contained-decision-base-longer-true",
         contained_decision([("src/a.mbt", 100, 120, [])]), True)
    cell("contained-decision-equal-length-true",
         contained_decision([("src/a.mbt", 100, 100, [])]), True)
    # 变异对照（判例-29）：base 更短 ⇒ 支里有 base 没有的行 ⇒ **不是** contained
    cell("contained-decision-base-shorter-false",
         contained_decision([("src/a.mbt", 101, 100, [])]), False)
    cell("contained-decision-missing-file-false",
         contained_decision([("src/a.mbt", 10, -1, [])]), False)
    cell("contained-decision-missing-symbol-false",
         contained_decision([("src/a.mbt", 10, 20, ["wt_new_thing"])]), False)
    # R162：**`superseded`（被取代）** —— 支把计数改小 ⇒ 合它会让用户看到更少功能数。
    # 实测动机：`help_topics.mbt` 支从 `[Board-DAG 30]/[Other 12]` 改回 `27/9`（174 工具）。
    cell("count-marks-extract", count_marks("[Board-DAG 30] x [Other 12] y"),
         {"Board-DAG": 30, "Other": 12})
    cell("count-regression-detected",
         [x[:1] for x in count_regressions("[Board-DAG 27]", "[Board-DAG 30]")], [("Board-DAG",)])
    cell("count-regression-none-when-bigger",
         count_regressions("[Board-DAG 31]", "[Board-DAG 30]"), [])
    cell("count-regression-none-when-equal",
         count_regressions("[Board-DAG 30]", "[Board-DAG 30]"), [])
    cell("superseded-decision-empty-false", superseded_decision([]), False)
    # 变异对照（判例-29）：把 `count_regressions` 的方向反过来 ⇒ 本格立刻红
    cell("superseded-decision-any-regression-true",
         superseded_decision(count_regressions("[Other 9]", "[Other 12]")), True)
    # 标签只在单侧出现 ⇒ 不算倒退（可能是新增段落）
    # R165：**接线格**（判例-29 正身）—— `scan` 必须注册 atexit 清理。
    # 实测动机：`finally` 在 SIGKILL/超时/父 shell 退出时不跑 ⇒ %TEMP% 堆了 27 个 worktree
    # ⇒ 系统资源耗尽（WinError 1455）。只断言"有 atexit 机制"不够，必须断言**它在 scan 里**。
    import inspect as _inspect
    _scan_src = _inspect.getsource(scan)
    # R169：改成 register_cleanup（atexit + 信号双路）；同时断言信号处理器真的装了 ——
    # 只断言"有清理"不够，`timeout` 杀的那条路径上必须也有（实测泄漏 2 个）。
    cell("scan-registers-cleanup", "register_cleanup(tmp, wt)" in _scan_src, True)
    cell("signal-handler-installed",
         "_on_signal" in _inspect.getsource(_on_signal), True)
    cell("signal-handler-cleans-targets",
         "_cleanup_paths(tmp, wt)" in _inspect.getsource(_on_signal), True)
    # R169：**平台事实** —— Windows 的 TerminateProcess 让 atexit/signal 都跑不到，
    # 所以清理必须有"启动自愈"这条路径（只断言 atexit 存在会给出安全的错觉）。
    # R170：**探针优先**接线 —— 两个只读探针必须在 `simulate(` 之前出现，否则省不下成本。
    _probe_pos = _scan_src.find("content_contained_probe(base, b)")
    _sim_pos = _scan_src.find("simulate(base, wt, commits)")
    cell("probe-first-before-simulate",
         0 <= _probe_pos < _sim_pos, True)
    cell("superseded-probe-also-before",
         0 <= _scan_src.find("superseded_probe(base, b)") < _sim_pos, True)
    cell("scan-sweeps-stale-worktrees-first",
         "sweep_stale_worktrees()" in _scan_src, True)
    _sweep_src = _inspect.getsource(sweep_stale_worktrees)
    cell("sweep-only-touches-own-prefix",
         "mergeability-" in _sweep_src, True)
    cell("sweep-refuses-outside-temp",
         "startswith(os.path.abspath(tmp_root))" in _sweep_src, True)
    cell("scan-still-has-finally-cleanup",
         "git(\"worktree\", \"remove\"" in _scan_src, True)

    # R164：**数字在前**形态（`(177 MCP tools)`）必须抓到 —— R163 的已知局限
    cell("count-marks-reverse-form-label-whole",
         count_marks("(177 MCP tools)") == {"MCP tools": 177}, True)
    cell("count-marks-reverse-form-catches-label",
         count_marks("(177 MCP tools)").get("MCP tools"), 177)
    cell("count-regression-reverse-form",
         [x[:1] for x in count_regressions("(174 MCP tools)", "(177 MCP tools)")],
         [("MCP tools",)])
    cell("count-regression-ignores-new-label",
         count_regressions("[NewGroup 3]", "[Old 5]"), [])
    # 一行不满足就整体否定（不能因为有 3 个文件已包含就放行第 4 个缺口）
    cell("contained-decision-one-bad-vetoes-all",
         contained_decision([("src/a.mbt", 10, 20, []), ("src/b.mbt", 11, 10, [])]), False)

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
            pick_rc, files, _changed = simulate(base2, wt, commits) if commits else (0, [], False)
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
    ap.add_argument("--include", default="/slave/",
                    help="分支名**子串过滤**（默认 /slave/；R130：可传 gitcode/ 之类"
                         "扫整条通道 —— 本尺靠真跑 cherry-pick 判定，是唯一可信的\"可否合并\"读数）")
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
    rows, rc = scan(args.base, remotes, args.keep, args.limit, args.include)
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
