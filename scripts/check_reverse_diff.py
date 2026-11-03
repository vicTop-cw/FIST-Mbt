#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_reverse_diff.py — 反向 diff 检测（TASK-004 / T0r7 · ns=iterate-1102）。

**管什么**：一次提交里「删的行数远多于增的行数」的形状——典型事故是 agent 的 git
误操作把别车道/自己车的 WIP 大段抹掉后又只补了极少内容，`commit_scoped.sh` 现有的
两半法只拒 `0 0` numstat（真源：docs/tasks/backlog/TASK-004-revert-diff-detector.yaml
+ reports/2026-11-02-backlog-queue-audit.md 第三节），比例判定这一格没人认领。

**⚠️ 本判据不改 commit_scoped.sh**：是否接入由统帅终审后另决（任务包边界）。

## 阈值基线——先实测，不拍脑袋（判例：判据基线必须先实测）

对本仓 `git log -300`（2026-11-02 实测，SHA 无关的分布口径：per-commit 聚合）：

  · 原始口径（含纯文件删除）：del/add 比中位数 0.10，p75=0.33，p90=1.00，p95=1.00，
    p99=1.54，max=47.0。两个超 5 的长尾**均为合法提交**：
      - 98d3220e5（47 删 0 增）：整文件删除一份过期 report；
      - 4ecb9d3d2（202 删 16 增）：RX-MBT 升级清理，删除质量全在**整文件删除**
        （patches/reapply.sh 156 行 + workflow 收缩）。
    ⇒ 整文件删除（status D）在本仓是常见合法形状，不能按比例判。
  · **排除纯文件删除后**（只看被修改文件的行数）：max=2.88（即上例排除 D 后剩余），
    p99=1.32，p90=1.00。长尾极短。
  · 事故样本「删 100 增 1」的比 = 100 ⇒ 与实测 max(2.88) 之间有 35 倍空隙。

**默认阈值取分布长尾之外**：`--ratio-threshold 10.0`（≈3.5× 实测 max）、
`--min-del 100`（低于 100 行的删除量不构成"抹掉 WIP"的规模；小修小删不误伤）。
两个数都不是均值——均值 0.10 会把一切正常重构误判。

**已知边界（如实写）**：默认把 status=D 的纯文件删除**排除**在比例质量之外——
因为合法的整文件清理（见 98d3220e5 / 4ecb9d3d2）与恶意的整树抹除在 numstat 上同形，
而前者远常见。代价：一次"删掉整个源文件"式的事故本判据默认不红（`--include-deletions`
可把 D 文件计入质量后再判；回执始终把删除面单独列行，人眼可见）。
这不是漏报的辩护，是刻意的覆盖面取舍，入档时据此裁决。

## 误伤豁免口（带理由；`--no-default-exempts` 可整体关闭，`--exempt` 可追加）

  · `memory/`   —— FIST 账本/日志追加型文件：按纪律每任务追加，历史大量增删混排；
  · `*.mbti`    —— moon info 生成的接口投影：API 收缩时合法地整段重写；
  · `*.lock`    —— 锁/依赖锁文件：机械生成，整段重排与人工意图无关。

豁免语义：命中文件**整体**退出质量统计；**全部**变更文件都命中豁免时判据按 0 处理
（回执逐条列出豁免命中）。与「空扫描必自拒」的分歧及理由：这里输入面（diff）非空、
豁免是**申报过的策略**而非「没读到数据」，静默风险由回执的豁免清单可见性兜住；
真正的"无法自证"档（非 git 仓 / git 命令失败 / 输出不可解析）仍走 2。

## rc 契约

  0 = 通过（含：质量全在豁免文件 / 全在纯删除且未开 --include-deletions）
  1 = 检出反向 diff（删 ≥ min-del 且 删/增比 ≥ ratio-threshold，逐文件清单在回执）
  2 = 判据无法自证（不是 git 仓 / git 调用失败 / numstat 不可解析）——绝不拿"没量到"报绿

## 用法

  python scripts/check_reverse_diff.py                     # 待提交面：git diff HEAD（暂存+未暂存）
  python scripts/check_reverse_diff.py --staged            # 只看暂存区
  python scripts/check_reverse_diff.py --commit HEAD       # 看某个提交（对 parent 的 diff）
  python scripts/check_reverse_diff.py --selftest          # 自检（合成 git 仓，含变异对照）

只读：对真实仓只发 `git diff*` 读命令，不写任何 git 状态；selftest 全程在临时目录。
"""
import argparse
import fnmatch
import os
import subprocess
import sys
import tempfile

from git_env import isolated_git_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 默认豁免：每条必须带理由（判例-5 同族纪律：豁免无理由 = 免检牌）
DEFAULT_EXEMPTS = (
    ("memory/", "FIST 账本/日志追加型文件，每任务按纪律追加，增删混排是常态"),
    ("*.mbti", "moon info 生成的接口投影，API 收缩时合法整段重写"),
    ("*.lock", "锁/依赖锁文件，机械生成，整段重排与人工意图无关"),
)

DEFAULT_RATIO = 10.0   # 实测基线 max=2.88（排除纯删除）的 ~3.5 倍；事故样本(100/1)=100
DEFAULT_MIN_DEL = 100  # 判例-31 同族口径：低于此删除量不构成"抹掉 WIP"的规模


def run_git(args, cwd):
    """只读 git 调用。失败返回 None（由调用方走自拒档，绝不静默当空）。"""
    try:
        p = subprocess.run(["git"] + args, cwd=cwd, capture_output=True,
                           text=True, encoding="utf-8", errors="replace",
                           env=isolated_git_env(), timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    return p.stdout


def parse_numstat(text):
    """numstat → [(add, del, path)]；二进制行（'-'）跳过并计数（binary 质量不可比，如实回执）。"""
    rows, binary = [], 0
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 3 or not (parts[0].isdigit() and parts[1].isdigit()):
            binary += 1
            continue
        rows.append((int(parts[0]), int(parts[1]), parts[2]))
    return rows, binary


def parse_name_status(text):
    """name-status → {path: status}；R/C 同时记旧路径（rename 来源按 D 面排除同口径处理）。"""
    st = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        code = parts[0][0]
        if code in "RC" and len(parts) >= 3:
            st[parts[2]] = code
            st[parts[1]] = code
        elif len(parts) >= 2:
            st[parts[1]] = code
    return st


def path_exempt(path, patterns):
    """前缀或 fnmatch 命中任一豁免模式（patterns 为 [(pattern, reason)]）。"""
    for pat, _reason in patterns:
        if path.startswith(pat) or fnmatch.fnmatch(path, pat):
            return True
    return False


def diff_ranges(mode, commit):
    """(mode, commit) → git numstat / name-status 的参数组。"""
    if mode == "commit":
        return (["diff-tree", "-r", "-M", "--no-commit-id", "--numstat", commit],
                ["diff-tree", "-r", "-M", "--no-commit-id", "--name-status", commit])
    if mode == "staged":
        return (["diff", "--cached", "HEAD", "-M", "--numstat"],
                ["diff", "--cached", "HEAD", "-M", "--name-status"])
    return (["diff", "HEAD", "-M", "--numstat"],
            ["diff", "HEAD", "-M", "--name-status"])


def check_repo(cwd, mode, commit, ratio_threshold, min_del,
               exempt_patterns, include_deletions, out):
    """主检查。返回 rc（0/1/2）。out 是打印函数（selftest 可换成收集器）。"""
    if not os.path.isdir(os.path.join(cwd, ".git")) and run_git(["rev-parse", "--git-dir"], cwd) is None:
        out("[FATAL] %s 不是 git 仓（无法自证，rc=2）" % cwd)
        return 2
    ns_args, status_args = diff_ranges(mode, commit)
    ns_raw = run_git(ns_args, cwd)
    st_raw = run_git(status_args, cwd)
    if ns_raw is None or st_raw is None:
        out("[FATAL] git 读取失败（mode=%s commit=%s）——无法自证，rc=2" % (mode, commit))
        return 2
    rows, binary = parse_numstat(ns_raw)
    if binary:
        out("[note] 跳过 %d 个二进制/不可解析 numstat 行（质量不可比）" % binary)
    stmap = parse_name_status(st_raw)

    counted_add = counted_del = 0
    del_only_mass = 0          # status=D 文件的删除量（默认不计入比例）
    exempt_hits = []           # (path, add, del, reason)
    faces = []                 # (path, add, del, status)
    for add, dele, path in rows:
        reason = None
        for pat, r in exempt_patterns:
            if path.startswith(pat) or fnmatch.fnmatch(path, pat):
                reason = r
                break
        if reason is not None:
            exempt_hits.append((path, add, dele, reason))
            continue
        status = stmap.get(path, "M")
        if status == "D":
            del_only_mass += dele
            faces.append((path, add, dele, "D"))
            if not include_deletions:
                continue
        counted_add += add
        counted_del += dele
        faces.append((path, add, dele, status))

    for path, add, dele, status in faces:
        out("  %-3s add=%-5d del=%-5d %s" % (status, add, dele, path))
    for path, add, dele, reason in exempt_hits:
        out("  [exempt] add=%-5d del=%-5d %s —— %s" % (add, dele, path, reason))
    if del_only_mass and not include_deletions:
        out("[note] 纯文件删除质量 del=%d 未计入比例（--include-deletions 可计入；"
            "基线证明整文件清理在本仓合法常见，见 docstring 已知边界）" % del_only_mass)

    if not faces and not exempt_hits:
        out("[PASS] 扫描面为空（无 diff）rc=0")
        return 0
    if counted_add + counted_del == 0 and del_only_mass == 0 and not exempt_hits:
        out("[FATAL] diff 非空但解析不到任何可计质量——输出不可解析，无法自证 rc=2")
        return 2

    ratio = counted_del / max(counted_add, 1)
    out("[meter] 计入面：add=%d del=%d 删/增比=%.2f（阈值：del>=%d 且 ratio>=%.1f）"
        % (counted_add, counted_del, ratio, min_del, ratio_threshold))
    if counted_del >= min_del and ratio >= ratio_threshold:
        out("[RED] 反向 diff：删 %d 行 / 增 %d 行（比 %.1f ≥ 阈值 %.1f）——"
            "疑似抹掉 WIP，逐文件清单见上，rc=1" % (counted_del, counted_add, ratio, ratio_threshold))
        return 1
    out("[PASS] rc=0")
    return 0


# ───────────────────────────────── selftest ─────────────────────────────────
# 每格都是真跑：临时 git 仓 + subprocess 调本脚本（判例-29：跑的就是实现路径）。
# 变异对照（判例-30）：S2 把 S1 的「删多」样本改成「删少」，必须由红变绿。


def _git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True,
                       text=True, encoding="utf-8", errors="replace",
                       env=isolated_git_env())
    assert p.returncode == 0, "selftest git 失败: %s\n%s" % (args, p.stderr)
    return p


def _init_repo():
    d = tempfile.mkdtemp(prefix="revdiff_st_")
    _git(d, "init", "-q")
    _git(d, "config", "user.email", "t@example.test")
    _git(d, "config", "user.name", "selftest")
    return d


def _commit_file(d, path, content, msg):
    full = os.path.join(d, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    _git(d, "add", path)
    _git(d, "commit", "-q", "-m", msg)


def _run_judge(d, *extra):
    script = os.path.abspath(__file__)
    p = subprocess.run([sys.executable, script] + list(extra), cwd=d,
                       capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=120)
    return p.returncode, p.stdout + p.stderr


def selftest(out):
    cells = []

    def cell(name, ok, detail):
        cells.append((name, ok, detail))
        out("  [%s] %s %s" % ("PASS" if ok else "FAIL", name, detail))

    # S1 违例红：删 149 增 1（pending diff，比=149）
    d = _init_repo()
    _commit_file(d, "src/a.mbt", "".join("line%d\n" % i for i in range(150)), "base")
    with open(os.path.join(d, "src/a.mbt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("line0\nnewonly\n")  # del 149 add 1 → ratio 149
    rc, o = _run_judge(d)
    cell("S1 违例红(删149增1)", rc == 1 and "RED" in o, "rc=%d" % rc)

    # S2 变异对照：同夹具改成「删少增多」必须变绿（判例-30：改样本数据，非注释）
    with open(os.path.join(d, "src/a.mbt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("".join("line%d\n" % i for i in range(150)) + "appended\n")  # del 0 add 1
    rc, o = _run_judge(d)
    cell("S2 变异对照(删0增1→绿)", rc == 0 and "PASS" in o, "rc=%d" % rc)

    # S3 低于 min-del：删 99 增 0（modified）→ 绿
    with open(os.path.join(d, "src/a.mbt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("".join("line%d\n" % i for i in range(51)))  # del 99
    rc, o = _run_judge(d)
    cell("S3 低于min-del(删99)→绿", rc == 0, "rc=%d" % rc)

    # S4 比例低于阈值：删 100 增 20（比 5 < 10）→ 绿
    with open(os.path.join(d, "src/a.mbt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("".join("line%d\n" % i for i in range(50))
                + "".join("x%d\n" % i for i in range(20)))  # del 100 add 20
    rc, o = _run_judge(d)
    cell("S4 比例5<阈值10→绿", rc == 0, "rc=%d" % rc)

    # S5 豁免命中：违例落在 memory/ → 绿且回执列豁免
    _git(d, "checkout", "-q", "--", "src/a.mbt")
    _commit_file(d, "memory/log.md", "".join("m%d\n" % i for i in range(150)), "ledger")
    with open(os.path.join(d, "memory/log.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("m0\nrewritten\n")
    rc, o = _run_judge(d)
    cell("S5 memory/豁免→绿", rc == 0 and "[exempt]" in o, "rc=%d" % rc)

    # S6 关豁免旗标：同一夹具 --no-default-exempts 必须翻红（豁免口可关）
    rc, o = _run_judge(d, "--no-default-exempts")
    cell("S6 --no-default-exempts→红", rc == 1, "rc=%d" % rc)

    # S7 追加豁免：--exempt 覆盖同夹具 → 绿
    rc, o = _run_judge(d, "--exempt", "memory/")
    cell("S7 --exempt 追加→绿", rc == 0 and "[exempt]" in o, "rc=%d" % rc)

    # S8 纯删除不计：整文件删除 500 行 + 小改 5/4 → 绿；--include-deletions → 红
    d2 = _init_repo()
    _commit_file(d2, "src/big.mbt", "".join("b%d\n" % i for i in range(500)), "big")
    _commit_file(d2, "src/small.mbt", "s0\n", "small")
    _git(d2, "rm", "-q", "src/big.mbt")
    with open(os.path.join(d2, "src/small.mbt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("s0\nn1\nn2\nn3\nn4\n")  # add 4
    rc, o = _run_judge(d2)
    cell("S8a 纯删除默认不计→绿", rc == 0 and "纯文件删除质量" in o, "rc=%d" % rc)
    rc, o = _run_judge(d2, "--include-deletions")
    cell("S8b --include-deletions→红", rc == 1, "rc=%d" % rc)

    # S9 --commit 模式：提交一笔违例后对 HEAD 判红
    d3 = _init_repo()
    _commit_file(d3, "src/x.mbt", "".join("v%d\n" % i for i in range(120)), "base")
    with open(os.path.join(d3, "src/x.mbt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("v0\nonly\n")
    _git(d3, "add", "src/x.mbt")
    _git(d3, "commit", "-q", "-m", "gutted")
    rc, o = _run_judge(d3, "--commit", "HEAD")
    cell("S9 --commit HEAD 违例→红", rc == 1, "rc=%d" % rc)
    rc, o = _run_judge(d3, "--commit", "HEAD~1")  # 基线提交无删除 → 绿
    cell("S9b --commit HEAD~1→绿", rc == 0, "rc=%d" % rc)

    # S10 无 diff → 绿
    d4 = _init_repo()
    _commit_file(d4, "f.txt", "hello\n", "base")
    rc, o = _run_judge(d4)
    cell("S10 无diff→绿", rc == 0 and "扫描面为空" in o, "rc=%d" % rc)

    # S11 非 git 目录 → 自拒 rc=2
    d5 = tempfile.mkdtemp(prefix="revdiff_nongit_")
    rc, o = _run_judge(d5)
    cell("S11 非git自拒rc=2", rc == 2, "rc=%d" % rc)

    # S12 未知旗标必拒（行为级：真跑 argparse）
    rc, o = _run_judge(d4, "--definitely-not-real")
    cell("S12 未知旗标rc≠0", rc != 0, "rc=%d" % rc)

    # S13 低于阈值且全豁免回执可见（防豁免把判据静默化）：全豁免时回执必须点名豁免清单
    rc, o = _run_judge(d)
    ok13 = rc == 0 and "[exempt]" in o and "memory/log.md" in o
    cell("S13 全豁免回执点名", ok13, "rc=%d rc=0且回执含豁免清单" % rc)

    bad = [c for c in cells if not c[1]]
    out("SELFTEST %s（%d 格，FAIL=%d）" % ("OK" if not bad else "FAILED",
                                          len(cells), len(bad)))
    return 0 if not bad else 1


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="check_reverse_diff.py",
        description="反向 diff 检测：删远多于增的提交自动拒绝（TASK-004）")
    ap.add_argument("--commit", metavar="SHA", default=None,
                    help="检查某个提交对其 parent 的 diff（默认检查待提交面 git diff HEAD）")
    ap.add_argument("--staged", action="store_true",
                    help="只检查暂存区（git diff --cached HEAD）")
    ap.add_argument("--ratio-threshold", type=float, default=DEFAULT_RATIO,
                    metavar="R", help="删/增比阈值（默认 %.1f，基线见 docstring）" % DEFAULT_RATIO)
    ap.add_argument("--min-del", type=int, default=DEFAULT_MIN_DEL, metavar="N",
                    help="触发判定的最小删除行数（默认 %d）" % DEFAULT_MIN_DEL)
    ap.add_argument("--exempt", action="append", default=[], metavar="PATTERN",
                    help="追加豁免模式（前缀或 glob；可多次）")
    ap.add_argument("--no-default-exempts", action="store_true",
                    help="关闭内置豁免表（memory/ *.mbti *.lock）")
    ap.add_argument("--include-deletions", action="store_true",
                    help="把 status=D 的纯文件删除量也计入比例质量（默认排除，见 docstring 已知边界）")
    ap.add_argument("--selftest", action="store_true",
                    help="自检：合成 git 仓逐格真跑（含变异对照），不碰真实仓")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest(print)

    if args.commit and args.staged:
        print("[FATAL] --commit 与 --staged 互斥")
        return 2
    patterns = [] if args.no_default_exempts else list(DEFAULT_EXEMPTS)
    for p in args.exempt:
        if not p.strip():
            print("[FATAL] --exempt 不接受空模式（那等于把判据静默化）")
            return 2
        patterns.append((p, "调用方 --exempt 申报"))
    cwd = os.getcwd()
    mode = "commit" if args.commit else ("staged" if args.staged else "pending")
    return check_repo(cwd, mode, args.commit, args.ratio_threshold,
                      args.min_del, patterns, args.include_deletions, print)


if __name__ == "__main__":
    sys.exit(main())
