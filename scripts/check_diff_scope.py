#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_diff_scope.py — 分支作用域 / 契约 / 落后 / 先后写覆盖 四件一门的 CI 守卫（R158，主机任务 WT-05）。

## 为什么需要它（一句话说清"谁在替我挨打"）
本仓是多 agent 并行通道：同一基点上常同时有十几支 `slave/*` 在飞，而**合入时没有任何机器面知道
两支改过同一个文件**。R147 实测的机理就是这一条的空位：批处理合并脚本在冲突分支执行
`git checkout --ours .`（整树取我方），三次手工合并各吃掉一份登记面（`scripts/README.md` 索引行 /
`run_guards.py` 的电池格），**两侧改的是不同位置时连冲突提示都不产生**。
`check_slave_mergeability.py` 已经做了 merge-predict（在临时 worktree 里真跑 `cherry-pick --no-commit`
读**逐 hunk** 冲突），但它看不见两件事：① 一支分支动了它**不该动**的文件（越界 / 撞契约），
② 两支在**不同位置**改同一文件（git 能自动并，于是"没有冲突"被读成"没有风险"——而覆盖式合并正是
在这种形状上把别人的行吃掉）。本尺补的正是这两件，加上「落后主线超阈值」这一件（旧 base 直接 push
是②的前置条件）。

## 四条判据（全部离线只读 git，不 fetch、不写库、不动工作树）
- **D1 越界 `SCOPE_OUT`**：分支在 `docs/tasks/diff-scope-claims.txt` 有声明 ⇒ `merge-base..head` 的每个
  改动文件必须命中声明的 glob；越界逐文件点名。**缺声明也是违例**（`NOCLAIM`）——「先写边界再动手」
  是本项目任务包的既有要求（AGENTS.md 任务包格式：目标 / **边界** / 回传格式 / 验收标准），
  此前只在人话里，没有机器面认它。主线分支（`master` / `main`）内置豁免，增豁免是人的决定。
- **D2 契约 `CONTRACT_TOUCH`**：改动命中契约集（见 `is_contract`）而声明未带保留字 `contract` ⇒ 违例。
  契约集按**形状**判而不是抄一份清单：`moon.mod` 整串 / 任意层级的 `moon.pkg` / `src/core/*.mbt` /
  任意 `*.mbti`（生成接口=对外承诺面）。这四形每形一格钉住，改形状必须同批改格。
- **D3 落后 `DRIFT`**：`rev-list --count head..base` > 阈值（`--threshold`，默认 `DRIFT_THRESHOLD_DEFAULT`）
  ⇒ 违例。这是②的**前置条件**：基点越旧，同文件交错面越大。
- **D4 先后写覆盖 `OVERLAP`**：`merge-base(base, head)` 之后 **base 侧**改过的文件集合 ∩ **head 侧**改过的
  文件集合 ≠ ∅ ⇒ 违例，逐文件点名"base 已合入他人改动，请先 rebase/叠线再合"。
  与 `check_slave_mergeability` 的分工：那一把判**合不上**（hunk 冲突），本尺判**合得上去但会互相看不见**
  （同文件不同位置）——后者才是静默丢行的那一半。

## 声明文件文法（`docs/tasks/diff-scope-claims.txt`）
每行 `分支模式 <TAB 或空格> 路径模式 …〔 contract〕`；`#` 起注释、空行跳过。
匹配语义**刻意只有两形**（不引入 fnmatch，`*` 跨不跨 `/` 这种歧义不能留给读者猜）：
- 以 `*` 结尾 ⇒ 去掉 `*` 之后**整串前缀**匹配。写成 `scripts/*` 就是「整个 scripts 目录、含任意深度」，
  写成 `a*` 就只是「根层名字以 a 开头」——前缀里带不带 `/` 由书写者自己负责，没有隐藏规则。
- 其余 ⇒ **整串精确**匹配（`src/core/core_task.mbt`、`slave/feat/diff-scope-guard-r158`）。
分支模式与路径模式共用这一套语义，所以给一族分支（`slave/feat/*`）声明同一份边界也是同一把尺。
保留字 `contract` 单独占一个 token，出现即放行 D2。

## 用法
  python scripts/check_diff_scope.py                          # base 自动探测（gitcode/master→origin/master→master），head=HEAD
  python scripts/check_diff_scope.py --base <ref> --head <ref>
  python scripts/check_diff_scope.py --scopes docs/tasks/diff-scope-claims.txt --threshold 30
  python scripts/check_diff_scope.py --selftest               # 合成仓库自证（每条判据都有"必红"与"不误红"两格，
                                                              # 并把 0/1/2/4 四档退出码与折叠行从调用面真跑一遍）

## 退出码（承诺与实现同批核过，见 check_exit_code_contract.py）
0=无违例（含主线豁免、无独有改动） / 1=有违例（逐条点名 kind 与文件） /
2=判据无法自证（base 或 head 读不到、声明文件缺失或解析后一条都没有、仓库不是 git） /
4=尺子自己坏了（未捕获异常，BUG-369 契约）。
"""
import argparse
import io
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SCOPES_REL = os.path.join("docs", "tasks", "diff-scope-claims.txt")

# base 自动探测顺序：副机远程叫 gitcode、主机镜像叫 origin，最后退到本地主线名。
BASE_CANDIDATES = ("gitcode/master", "origin/master", "master", "main")
# 内置主线豁免：worker 分支才需要声明边界，主线自己就是边界。加名字进来是人的决定。
TRUNK_SHORT_NAMES = ("master", "main")
DRIFT_THRESHOLD_DEFAULT = 30
# 违例逐条打印的上限（条数不缩，只把超出部分按 kind 归并成一行；见 main 里的注释）。
PRINT_CAP = 30

CONTRACT_NOTE = ("moon.mod / 任意层级 moon.pkg / src/core/*.mbt / 任意 *.mbti")


def git(args, cwd):
    p = subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def resolve(cwd, ref):
    rc, out = git(["rev-parse", "--verify", "%s^{commit}" % ref], cwd)
    return out.strip().splitlines()[0] if rc == 0 and out.strip() else None


def short_name(cwd, ref):
    """refs/heads/x → x；能解析成分支就取分支短名，否则原样返回（供主线豁免比对）。"""
    rc, out = git(["rev-parse", "--abbrev-ref", ref], cwd)
    return out.strip() if rc == 0 and out.strip() else ref


def pick_base(cwd, head="HEAD"):
    """在 BASE_CANDIDATES 里挑**离 head 最近的一支**当 base（读不到任何候选 ⇒ 返回 ""）。

    2026-10-24（R35）：原实现「第一个能解析的候选就赢」= `gitcode/master` 常赢，而本仓两个镜像
    常年落后本地 `main` 数十笔（实测 59 笔）⇒ 任何 worker 分支相对它都像"动了全仓"：
    实测 D1/D2 判定面 110 条，其中 CONTRACT_TOUCH 11 条**全是主线自己的改动**。
    假违例一多，这条治理面就没人看了——所以按「最新已知干线」取 base；
    距离相同或都读不到距离时，退回 BASE_CANDIDATES 的书写顺序（与原行为同底，不新增自拒面）。
    """
    best = None
    for cand in BASE_CANDIDATES:
        if not resolve(cwd, cand):
            continue
        rc, out = git(["rev-list", "--count", "%s..%s" % (cand, head)], cwd)
        dist = int(out.strip()) if rc == 0 and (out or "").strip().isdigit() else None
        if dist is None:
            continue
        if best is None or dist < best[0]:
            best = (dist, cand)
    if best:
        return best[1]
    for cand in BASE_CANDIDATES:
        if resolve(cwd, cand):
            return cand
    return ""


def name_of_pattern(pat):
    """声明里的分支模式：允许 `remotes/<r>/` 与 `refs/heads/` 前缀噪音，只留最后两段可比的形。"""
    p = pat.strip()
    for pre in ("refs/heads/", "remotes/", "origin/", "gitcode/"):
        if p.startswith(pre):
            p = p[len(pre):]
    return p


def match_one(path, pat):
    """两形匹配（见模块 docstring「声明文件文法」），无第三形。"""
    if pat.endswith("*"):
        return path.startswith(pat[:-1])
    return path == pat


def match_any(path, pats):
    return any(match_one(path, p) for p in pats)


def is_contract(path):
    """契约面按形状判：这四形各有一格 selftest 钉住，改形状必须同批改格。"""
    if path == "moon.mod":
        return True
    if path == "moon.pkg" or path.endswith("/moon.pkg"):
        return True
    if path.startswith("src/core/") and path.endswith(".mbt"):
        return True
    return path.endswith(".mbti")


def parse_claims(text):
    """声明文本 → [(分支模式, [路径模式], 保留字集合)]。语法坏的行不静默丢：原样进 errors。"""
    claims, errors = [], []
    for i, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            errors.append("第 %d 行只有分支名、没有路径声明：%r" % (i, line))
            continue
        branch = name_of_pattern(parts[0])
        tokens = parts[1:]
        flags = {t for t in tokens if t == "contract"}
        pats = [t for t in tokens if t != "contract"]
        if not pats:
            errors.append("第 %d 行声明只剩保留字、没有任何路径模式：%r" % (i, line))
            continue
        claims.append((branch, pats, flags))
    return claims, errors


def find_claim(claims, head_short):
    target = name_of_pattern(head_short)
    for branch, pats, flags in claims:
        if match_one(target, branch):
            return branch, pats, flags
    return None


def changed_files(cwd, from_rev, to_rev):
    rc, out = git(["diff", "--name-only", "%s..%s" % (from_rev, to_rev)], cwd)
    if rc != 0:
        return None
    return [l.strip() for l in out.splitlines() if l.strip()]


def judge(cwd, base_ref, head_ref, scopes_text, threshold=DRIFT_THRESHOLD_DEFAULT):
    """返回 (verdict, detail)。verdict ∈ {"clean","violation","unknown"}。"""
    base = resolve(cwd, base_ref)
    head = resolve(cwd, head_ref)
    if not base or not head:
        return "unknown", {"reason": "base=%r / head=%r 至少一个读不到提交（浅克隆或名字错）"
                                     % (base_ref, head_ref)}
    rc, out = git(["merge-base", base, head], cwd)
    mb = out.strip() if rc == 0 and out.strip() else None
    if not mb:
        return "unknown", {"reason": "git 读不到 %s 与 %s 的共同祖先" % (base_ref, head_ref)}
    if base == head:
        return "clean", {"reason": "base 与 head 同一提交，无独有改动", "violations": [], "diag": []}
    if name_of_pattern(short_name(cwd, head_ref)) in TRUNK_SHORT_NAMES:
        return "clean", {"reason": "主线豁免（%s 是边界本身，不需要声明）"
                                   % short_name(cwd, head_ref),
                         "violations": [], "diag": ["TRUNK-EXEMPT"]}
    head_short = short_name(cwd, head_ref)
    if head_short == "HEAD":
        # D1 的声明对表需要一个**分支名**；detached checkout（CI 的 PR ref、archive 快照）没有。
        # 此时既不能报 clean（没对表）也不能报 NOCLAIM（分支没机会声明）——拒绝出数。
        return "unknown", {"reason": "读不到分支名（detached HEAD）：请用 --head refs/heads/<分支> "
                                     "或先 checkout 分支再判；本尺拒绝在此情形下出 clean 或 NOCLAIM"}
    claims, errors = parse_claims(scopes_text)
    if not claims:
        # 空扫描拒绝出数：判据「什么都没读到」时不许冒充绿。分两种成因说清楚，
        # 因为处置相反——原文就没条目 vs 有条目但全写坏了。
        return "unknown", {"reason": "声明面没有任何可用条目（D1 无从对表）：原文 %d 行、其中语法坏 %d 行%s"
                                % (len(scopes_text.splitlines()), len(errors),
                                   ("；坏的行：" + "；".join(errors[:3])) if errors else "")}

    changed = changed_files(cwd, mb, head)
    if changed is None:
        return "unknown", {"reason": "git diff 读不到 %s..%s" % (mb[:12], head[:12])}
    if not changed:
        return "clean", {"reason": "head 相对 merge-base 无文件改动（空支/已全合入）",
                         "violations": [], "diag": ["NO-CHANGES"]}

    v, diag = [], [{"kind": "CLAIM-SYNTAX", "note": e} for e in errors]
    claim = find_claim(claims, head_short)
    if claim is None:
        v.append({"kind": "NOCLAIM", "file": "(分支)",
                  "why": "分支 %s 在声明面没有任何条目 ⇒ 边界未声明即动文件（D1）" % head_short})
        flags = set()
    else:
        branch, pats, flags = claim
        for f in changed:
            if not match_any(f, pats):
                v.append({"kind": "SCOPE_OUT", "file": f,
                          "why": "不在 %r 的声明 %s 之内（D1）" % (branch, " ".join(pats))})
    # 契约面与"有没有声明"无关：一支没声明的分支撞了 moon.mod，也要看见 CONTRACT_TOUCH
    if "contract" not in flags:
        for f in changed:
            if is_contract(f):
                v.append({"kind": "CONTRACT_TOUCH", "file": f,
                          "why": "命中契约集（%s）而声明未带保留字 contract（D2）" % CONTRACT_NOTE})
    diag.append("声明条目=%d 条 / 改动文件=%d 个" % (len(claims), len(changed)))

    behind = 0
    rc, out = git(["rev-list", "--count", "%s..%s" % (head, base)], cwd)
    if rc == 0 and out.strip().isdigit():
        behind = int(out.strip())
    else:
        diag.append("D3 落后数读不到，只作诊断不判红")
    if behind > int(threshold):
        v.append({"kind": "DRIFT", "file": "(分支)",
                  "why": "落后 %s 共 %d 个提交 > 阈值 %d（D3：旧 base 直接合是覆盖事故的前置条件）"
                            % (base_ref, behind, int(threshold))})

    base_changed = changed_files(cwd, mb, base) or []
    overlap = sorted(set(changed) & set(base_changed))
    for f in overlap:
        v.append({"kind": "OVERLAP", "file": f,
                  "why": "merge-base 之后 base 侧也改过它 ⇒ 先 rebase/叠线再合（D4）。"
                         "git 可能能自动并，但自动并 ≠ 没人被覆盖（R147 的丢行就发生在这形状上）"})
    detail = {"violations": v, "diag": diag, "changed": len(changed),
              "behind": behind, "overlap": len(overlap), "merge_base": mb[:12]}
    return ("violation" if v else "clean"), detail


# ---------------------------------------------------------------------------
# selftest：合成仓库里逐条判据各配「必红」与「不误红」两格
# ---------------------------------------------------------------------------
def selftest():
    cells = []
    notes = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    def kinds(detail):
        return sorted({x["kind"] for x in detail.get("violations", [])})

    d = tempfile.mkdtemp(prefix="diffscope-")
    cwd = d

    def g(*a):
        return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True,
                              text=True, encoding="utf-8", errors="replace")

    def w(p, s):
        full = os.path.join(cwd, p)
        os.makedirs(os.path.dirname(full) or cwd, exist_ok=True)
        open(full, "w", encoding="utf-8", newline="\n").write(s)

    try:
        g("init", "-q", "-b", "master", ".")
        g("config", "user.email", "t@t")
        g("config", "user.name", "t")
        w("scripts/a.py", "print(1)\n")
        w("docs/x.md", "doc\n")
        w("moon.mod", "version = \"0.0.1\"\n")
        g("add", "-A"); g("commit", "-qm", "base")
        g("branch", "oldmaster")          # 主线豁免格要有「旧主线提交」当 base，见下面那格注释

        # 一支点 scripts/*，且 base 侧在她之后没动同文件 ⇒ D1/D2/D3/D4 全不该红
        scopes_ok = ("worker-a\tscripts/*\n"
                     "worker-b\tscripts/*\n"
                     "worker-c\tscripts/* contract\n"
                     "worker-d\tdocs/*\n"
                     "worker-e\tscripts/*\n")

        g("checkout", "-q", "-b", "worker-a")
        w("scripts/new.py", "print(2)\n")
        g("add", "-A"); g("commit", "-qm", "a in scope")
        v, det = judge(cwd, "master", "worker-a", scopes_ok, threshold=1000)
        cell("in-scope-clean", v, "clean")

        # D1 越界必红：同一支改了 docs/
        w("docs/out.md", "越界\n")
        g("add", "-A"); g("commit", "-qm", "a out of scope")
        v, det = judge(cwd, "master", "worker-a", scopes_ok, threshold=1000)
        cell("scope-out-red", v, "violation")
        cell("scope-out-kind", "SCOPE_OUT" in kinds(det), True)
        cell("scope-out-names-file", "docs/out.md" in
             [x["file"] for x in det["violations"] if x["kind"] == "SCOPE_OUT"], True)

        # D1 缺声明必红（分支名不在声明面里）
        g("checkout", "-q", "-b", "worker-undeclared", "worker-a")
        w("scripts/und.py", "print(3)\n")
        g("add", "-A"); g("commit", "-qm", "undeclared branch changes file")
        v, det = judge(cwd, "master", "worker-undeclared", scopes_ok, threshold=1000)
        cell("noclaim-red", "NOCLAIM" in kinds(det), True)

        # 主线豁免不误红 + **真的走到那条分支**：base 用旧主线提交（否则 base==head 会先短路，
        # 上一版就是这样——它测到的是「同一提交无改动」那条短路，TRUNK-EXEMPT 一行从未被执行，
        # 而格子照样绿。豁免面要正面断言 diag 标记，不能只断言 clean。）
        g("checkout", "-q", "master")
        w("scripts/trunk.py", "print(9)\n")
        g("add", "-A"); g("commit", "-qm", "trunk change")
        v, det = judge(cwd, "oldmaster", "master", scopes_ok, threshold=1000)
        cell("trunk-exempt", v, "clean")
        cell("trunk-exempt-marks-diag", "TRUNK-EXEMPT" in det.get("diag", []), True)
        cell("trunk-exempt-has-changes", det.get("reason", "").startswith("主线豁免"), True)
        # base==head 那条短路单独钉（上一格改用它自己的 reason 断言，两形不再互相顶包：
        # 顶包的坏法是「短路把豁免遮住、豁免代码坏了也照样绿」）
        v, det = judge(cwd, "master", "master", scopes_ok, threshold=1000)
        cell("same-commit-shortcut", det.get("reason", ""), "base 与 head 同一提交，无独有改动")

        # detached HEAD（CI 的 PR ref / archive 快照那一形）⇒ 拒绝出数：既不报 clean 也不报 NOCLAIM
        g("checkout", "-q", "--detach", "worker-a")
        v, det = judge(cwd, "master", "HEAD", scopes_ok, threshold=1000)
        cell("detached-selfrefuse", v, "unknown")
        cell("detached-not-noclaim", "NOCLAIM" in kinds(det), False)
        g("checkout", "-q", "master")

        # D2 契约四形各钉一格；未带 contract ⇒ 红，带了 ⇒ 放行
        g("checkout", "-q", "-b", "worker-b", "master")
        w("moon.mod", "version = \"0.0.2\"\n")
        w("src/core/core_task.mbt", "fn task() {}\n")
        w("src/server/moon.pkg", "deps: {}\n")
        w("src/server/server.mbti", "pub fn x()\n")
        w("src/core/not_a_contract.md", "契约面只认 .mbt\n")
        g("add", "-A"); g("commit", "-qm", "b touches contracts")
        v, det = judge(cwd, "master", "worker-b", scopes_ok, threshold=1000)
        touched = sorted(x["file"] for x in det["violations"] if x["kind"] == "CONTRACT_TOUCH")
        cell("contract-moon-mod", "moon.mod" in touched, True)
        cell("contract-src-core-mbt", "src/core/core_task.mbt" in touched, True)
        cell("contract-any-moon-pkg", "src/server/moon.pkg" in touched, True)
        cell("contract-mbti", "src/server/server.mbti" in touched, True)
        cell("contract-src-core-non-mbt-not-flagged",
             "src/core/not_a_contract.md" in touched, False)
        # 同改动 + 声明带 contract ⇒ 契约面必须放行（D1 那侧仍越界，正好证明放行只来自保留字）
        g("checkout", "-q", "-b", "worker-c", "master")
        for p, s in (("moon.mod", "version = \"0.0.2\"\n"),
                     ("src/core/core_task.mbt", "fn task() {}\n"),
                     ("src/server/moon.pkg", "deps: {}\n"),
                     ("src/server/server.mbti", "pub fn x()\n")):
            w(p, s)
        g("add", "-A"); g("commit", "-qm", "c declares contract")
        v, det = judge(cwd, "master", "worker-c", scopes_ok, threshold=1000)
        cell("contract-keyword-releases-d2",
             "CONTRACT_TOUCH" in kinds(det), False)

        # D3 落后必红 / 阈值抬高不误红：worker-d 从旧点切出，master 之后前进
        g("checkout", "-q", "-b", "worker-d", "worker-a")
        w("docs/late.md", "旧 base 上的一支\n")
        g("add", "-A"); g("commit", "-qm", "d change")
        g("checkout", "-q", "master")
        for i in range(3):
            w("scripts/lead%d.py" % i, "print(%d)\n" % i)
            g("add", "-A"); g("commit", "-qm", "master leads %d" % i)
        v, det = judge(cwd, "master", "worker-d", scopes_ok, threshold=2)
        cell("drift-red", "DRIFT" in kinds(det), True)
        cell("drift-count", det.get("behind"), 4)
        v, det = judge(cwd, "master", "worker-d", scopes_ok, threshold=1000)
        cell("drift-under-threshold-clean", "DRIFT" in kinds(det), False)

        # D4 先后写覆盖必红：base 合了 X 对 scripts/a.py 的改动，worker-e 也改同一文件但不同位置
        g("checkout", "-q", "-b", "side-x", "master")
        w("scripts/a.py", "print(1)\nprint(11)\n")
        g("add", "-A"); g("commit", "-qm", "X edits a.py tail")
        g("checkout", "-q", "master")
        g("merge", "-q", "--no-ff", "-m", "merge X into master", "side-x")
        g("checkout", "-q", "-b", "worker-e", "worker-d")
        w("scripts/a.py", "print(1)\n# 只改注释行，git 能自动并\n")
        g("add", "-A"); g("commit", "-qm", "E edits a.py head")
        v, det = judge(cwd, "master", "worker-e", scopes_ok, threshold=1000)
        cell("overlap-red", "OVERLAP" in kinds(det), True)
        cell("overlap-names-file", "scripts/a.py" in
             [x["file"] for x in det["violations"] if x["kind"] == "OVERLAP"], True)
        # 反向对照：同支但只改别的文件 ⇒ 不该有 OVERLAP（否则 D4 只是"分支落后"的换皮）。
        # 声明给 `docs/* scripts/*`：worker-f 从 worker-d 切出，而 worker-a 那一支**没并进主线**，
        # 所以 merge-base 是最初的 base 提交 —— 它带着 worker-a 的 scripts/new.py（第一版只声明
        # `docs/*` 时被这一点判成 SCOPE_OUT，格子红的是 fixture 而不是判据，正是本尺要防的形态）。
        g("checkout", "-q", "-b", "worker-f", "worker-d")
        w("docs/only.md", "只碰自己的新文件\n")
        g("add", "-A"); g("commit", "-qm", "F touches untouched file")
        v, det = judge(cwd, "master", "worker-f",
                       scopes_ok + "worker-f\tdocs/* scripts/*\n", threshold=1000)
        cell("no-overlap-clean", "OVERLAP" in kinds(det), False)
        cell("different-file-clean", v, "clean")

        # 匹配语义三形钉住：/* 含任意深度、裸* 整串前缀、其余精确
        cell("glob-dir-star-deep", match_one("scripts/blackbox/deep/x.py", "scripts/*"), True)
        cell("glob-bare-star-prefix", match_one("moon.mod", "moon*"), True)
        cell("glob-plain-not-prefix", match_one("moon.mod", "moon"), False)
        cell("glob-star-does-not-leak-up", match_one("src/a.py", "a*"), False)

        # 空扫描 / 读不到 ⇒ 必须自拒（拒绝判绿也拒绝判红）
        v, det = judge(cwd, "master", "worker-a", "  \n# 只有注释\n", threshold=1000)
        cell("empty-claims-selfrefuse", v, "unknown")
        v, det = judge(cwd, "no-such-ref", "worker-a", scopes_ok, threshold=1000)
        cell("bad-base-selfrefuse", v, "unknown")
        v, det = judge(cwd, "master", "worker-a", scopes_ok + "broken-line-no-patterns\n",
                       threshold=1000)
        cell("claim-syntax-diag-not-fatal",
             any(isinstance(x, dict) and x.get("kind") == "CLAIM-SYNTAX"
                 for x in det.get("diag", [])), True)

        # 调用面（rc 契约）：`run()`/`main()` 的打印与退出码必须被真跑一遍。上一版就是漏了这层——
        # judge() 全绿，而 `DIFFSCOPE=clean` 那行少一个实参抛 TypeError、rc=1 冒充「有违例」，
        # 全靠我在提交后手跑现状面才发现。格子把 0/1/2/4 四档和折叠行都钉住。
        w("claims.txt", scopes_ok + "worker-f\tdocs/* scripts/*\nworker-g\tscripts/*\n")
        claims = os.path.join(cwd, "claims.txt")

        def cap(argv):
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = run(argv, cwd)
            return rc, buf.getvalue()

        rc, out = cap(["--base", "master", "--head", "worker-f", "--scopes", claims,
                       "--threshold", "1000"])
        cell("argv-clean-rc0", rc, 0)
        cell("argv-clean-prints-threshold", "<= 阈值 1000" in out, True)
        rc, out = cap(["--base", "master", "--head", "worker-a", "--scopes", claims])
        cell("argv-violation-rc1", rc, 1)
        cell("argv-violation-prints-verdict", "DIFFSCOPE=red" in out, True)
        rc, out = cap(["--base", "master", "--head", "worker-f", "--scopes",
                       os.path.join(cwd, "no-such-claims.txt")])
        cell("argv-missing-scopes-rc2", rc, 2)
        rc, out = cap(["--base", "no-such-ref", "--head", "worker-f", "--scopes", claims])
        cell("argv-bad-base-rc2", rc, 2)
        # 声明文件位置是个目录：open() 必抛 ⇒ 只有 main() 的收口能给出 4（run 不吞异常）
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = main(["--base", "master", "--scopes", cwd])
        cell("argv-ruler-broken-rc4", rc, 4)
        cell("argv-ruler-broken-says-fatal", buf.getvalue().startswith("FATAL 尺子自己坏了"), True)

        # 折叠行：越界文件数 > PRINT_CAP 时，逐条点名止于上限、其余归并成一行计数
        # 只 `add docs`：claims.txt 在仓库根，`add -A` 会把它一起提交进来，那条就成了第 36 个
        # 越界文件——格子红的是 fixture 的计数，不是判据（第一版就这样：%d 5 对不上 6）。
        g("checkout", "-q", "-b", "worker-g", "master")
        for i in range(PRINT_CAP + 5):
            w("docs/fold%02d.md" % i, "x\n")
        g("add", "-A", "--", "docs"); g("commit", "-qm", "g 越界条数多于打印上限")
        rc, out = cap(["--base", "master", "--head", "worker-g", "--scopes", claims])
        cell("argv-fold-print-cap-lines", out.count("违例 [SCOPE_OUT]") == PRINT_CAP, True)
        cell("argv-fold-note", ("另有 %d 条未逐条打印" % 5) in out, True)

        # 真源现状面：只在「本支在声明面有条目」时断言。为什么不加「无条目⇒红」那一档：
        # 声明由各支 owner 自己追加（见 diff-scope-claims.txt 抬头），别人/主机的支还没写自己那行，
        # 本格若把它判成 violation 就会**永久弄红别人的电池**——那是「把自己的纪律硬塞给别人、
        # 却把别人按在地上」的坏形状。无条目只记诊断，判据本身仍然会在那个支被单独跑时发红。
        branch = short_name(ROOT, "HEAD")
        scopes_path = os.path.join(ROOT, SCOPES_REL)
        text = open(scopes_path, encoding="utf-8").read() if os.path.exists(scopes_path) else ""
        base_ref = pick_base(ROOT) or None  # 与生产路径同源：取离 HEAD 最近的候选（见 pick_base 注释）
        on_claims, _errs = parse_claims(text)
        on_claim = find_claim(on_claims, branch) if branch != "HEAD" else None
        if base_ref and on_claim:
            v, det = judge(ROOT, base_ref, "HEAD", text)
            cell("onsite-not-violation", v != "violation", True)
        else:
            notes.append("现状面未测（%s）：只作诊断、不充数"
                         % ("游离头" if branch == "HEAD" else
                            ("本支 %s 在声明面还没有条目" % branch if not on_claim
                             else "主线 ref 读不到")))

        shutil.rmtree(d, ignore_errors=True)
        bad = [c for c in cells if not c[1]]
        if bad:
            for name, ok, msg in bad:
                print("  SELFTEST FAIL %s :: %s" % (name, msg))
            return 1
        # 计数自述从已执行格子反解，不手写族数/格数（J10：少写=声明滞后、多写=幻影判据）
        print("SELFTEST OK（%d 格，数从已执行格子反解；未测面 %d 条记为诊断，不充数）"
              % (len(cells), len(notes)))
        return 0
    except Exception as e:                          # 尺子自己坏了不许冒用 1 那一档（BUG-369）
        print("FATAL 尺子自己坏了：%r" % e)
        shutil.rmtree(d, ignore_errors=True)
        return 4


def run(argv, root):
    """一次调用的实体。rc 只从这里出；任何异常由 `main()` 收成 4——尺子坏了不许冒用 1。"""
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--base", default="", help="主线 ref（缺省按 %s 顺序探测）" % " / ".join(BASE_CANDIDATES))
    ap.add_argument("--head", default="HEAD", help="被检分支 ref（缺省 HEAD）")
    ap.add_argument("--scopes", default="", help="声明文件（缺省 %s）" % SCOPES_REL)
    ap.add_argument("--threshold", type=int, default=DRIFT_THRESHOLD_DEFAULT,
                    help="D3 落后阈值（默认 %d）" % DRIFT_THRESHOLD_DEFAULT)
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()

    base = a.base
    if not base:
        base = pick_base(root)
    if not base:
        print("FATAL 判据无法自证：base 一个都探测不到（试过的名字：%s）" % " ".join(BASE_CANDIDATES))
        return 2
    scopes_file = a.scopes or os.path.join(root, SCOPES_REL)
    if not os.path.exists(scopes_file):
        print("FATAL 判据无法自证：声明文件不存在（%s）——没有边界面就没有「越界」这个概念"
              % os.path.relpath(scopes_file, root))
        return 2
    text = open(scopes_file, encoding="utf-8").read()

    verdict, det = judge(root, base, a.head, text, a.threshold)
    if verdict == "unknown":
        print("FATAL 判据无法自证：%s" % det.get("reason", "未给出原因"))
        return 2
    vs = det.get("violations", [])
    # 打印上限：实测一支 2026-10-15 前后的陈旧分支一次就回 120 条（每个目录的 moon.pkg/*.mbti 都在
    # 契约集里）。条数本身是读数、不许缩，但 CI 日志不能靠翻页找重点 ⇒ 前 30 条逐条点名，
    # 其余按 kind 归并成一行计数。
    for x in vs[:PRINT_CAP]:
        print("  违例 [%s] %s :: %s" % (x["kind"], x["file"], x["why"]))
    if len(vs) > PRINT_CAP:
        rest = {}
        for x in vs[PRINT_CAP:]:
            rest[x["kind"]] = rest.get(x["kind"], 0) + 1
        print("  …另有 %d 条未逐条打印（按 kind 归并：%s；判定面总数见下行）"
              % (len(vs) - PRINT_CAP,
                 "、".join("%s=%d" % kv for kv in sorted(rest.items()))))
    for x in det.get("diag", []):
        if isinstance(x, dict):
            print("  诊断 [%s] %s" % (x.get("kind"), x.get("note")))
        else:
            print("  诊断 %s" % x)
    if verdict == "violation":
        print("DIFFSCOPE=red 判定面 %d 条（base=%s head=%s 改动=%d 落后=%d 同文件交错=%d）"
              % (len(det["violations"]), base, a.head, det.get("changed", 0),
                 det.get("behind", 0), det.get("overlap", 0)))
        return 1
    print("DIFFSCOPE=clean base=%s head=%s：%s（改动 %d 个 / 落后 %d <= 阈值 %d / 同文件交错 %d 个）"
          % (base, a.head, det.get("reason") or "改动逐条落在声明内、无契约命中",
             det.get("changed", 0), det.get("behind", 0), a.threshold, det.get("overlap", 0)))
    return 0


def main(argv=None):
    try:
        return run(list(sys.argv[1:] if argv is None else argv), ROOT)
    except Exception as e:                          # 未捕获异常=尺子坏了，走 4，不冒充 1（BUG-369）
        print("FATAL 尺子自己坏了：%r" % e)
        return 4


if __name__ == "__main__":
    sys.exit(main())
