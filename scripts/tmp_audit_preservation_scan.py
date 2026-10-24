#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/tmp_audit_preservation_scan.py —— 《资产保全证明书》只读取数器（临时工具）。

**纯只读**：只跑 `git rev-parse / merge-base / diff / log / cherry / for-each-ref /
ls-files / status`，本脚本不写入仓库、不删任何东西、不碰 ref、不改索引。
输出一份 JSON 到指定路径，供报告逐条引用。

## 三条判据（copy 自 task-9，不许自创）

C1 内容已在 main：
    A. `git merge-base --is-ancestor <branch> main` 为真；或
    B. `git diff --diff-filter=D --name-only main <branch>` 为空（分支没删掉 main 有的文件）
       **且** 代码面 diff 为空。
    （判例-1：diff -D 非空 => 分支顶树是旧基线；单独用 B 不足以判可删，见报告）

C2 无独有代码增量：
    `git diff --name-only --diff-filter=A main <branch>` 剔除 NOISE 正则后为空。

C3 无未归档史料：
    `git log main..<branch> --format='%H %s'` 是否为空（空 = 该支没有任何 main 里没有的提交）。

## NOISE 正则（task-9 原文照抄，**一条不许少**）
    \\.md$|^memory/|^reports/|^docs/|^\\.agents/|^\\.dsh/|tmp_merge_batch|merge-prompt\\.txt|\\.verify-wt|^dist/

用法：
    python scripts/tmp_audit_preservation_scan.py --out reports/_scan.json
    python scripts/tmp_audit_preservation_scan.py --noise-variant bare --out ..._bare.json
        （对照实验：去掉 ^\\.dsh/ 与 \\.md$ 各跑一遍，证明噪音面的必要性）
"""
import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from git_env import isolated_git_env  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# task-9 原文的噪音排除面。一条都不许少、不许改。
NOISE_PATTERN = (
    r"\.md$|^memory/|^reports/|^docs/|^\.agents/|^\.dsh/|tmp_merge_batch|merge-prompt\.txt|\.verify-wt|^dist/"
)
NOISE_RE = re.compile(NOISE_PATTERN)

# 对照实验用的退化面（用来量化"排除面少一条会怎样"）
NOISE_VARIANTS = {
    "full": NOISE_RE,
    # 去掉 ^\.dsh/ —— 判例-6 的对照格
    "no_dsh": re.compile(
        r"\.md$|^memory/|^reports/|^docs/|^\.agents/|tmp_merge_batch|merge-prompt\.txt|\.verify-wt|^dist/"
    ),
    # 什么都不排除 —— 看原始噪音规模
    "bare": re.compile(r"(?!x)x"),
}


def git(*args, cwd=None, timeout=120):
    r = subprocess.run(
        ["git"] + list(args),
        cwd=cwd or ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=isolated_git_env(),
        timeout=timeout,
    )
    return r.returncode, (r.stdout or ""), (r.stderr or "")


def lines(s):
    return [l for l in s.splitlines() if l.strip()]


def scan_branch(main, branch, noise_re):
    """对单支取三条判据的全部读数。纯只读。"""
    rec = {"branch": branch}
    rc, out, err = git("rev-parse", "--verify", "--quiet", branch + "^{commit}")
    if rc != 0 or not out.strip():
        rec["error"] = "branch 不存在或无法解析"
        return rec
    tip = out.strip()
    rec["tip"] = tip
    rec["tip12"] = tip[:12]
    _, cname, _ = git("log", "-1", "--format=%s", tip)
    rec["subject"] = cname.strip()

    # C1-A: 祖先判定
    rc_a, _, _ = git("merge-base", "--is-ancestor", tip, main)
    rec["C1_ancestor"] = rc_a == 0

    # C1-B: 分支是否删掉 main 有的文件（判例-1 的探针）
    _, delout, _ = git("diff", "--diff-filter=D", "--name-only", main, tip)
    dels = lines(delout)
    rec["C1_deleted_count"] = len(dels)
    rec["C1_deleted_sample"] = dels[:8]

    # 代码面 diff（排除噪音后的改动文件总数）
    _, allout, _ = git("diff", "--name-only", main, tip)
    allfiles = lines(allout)
    rec["diff_total"] = len(allfiles)
    code_files = [f for f in allfiles if not noise_re.search(f)]
    rec["code_changed"] = len(code_files)
    rec["code_changed_sample"] = code_files[:10]

    # C1 判据：祖先 或（C1-A false 时）看是否"内容已达"
    # 「内容已达」严格口径 = 代码面零残留 且 没删过 main 的文件
    rec["C1_content_equal"] = rec["C2_code_empty"] = None
    # C2: 新增文件面（排除噪音）
    _, addout, _ = git("diff", "--name-only", "--diff-filter=A", main, tip)
    adds = lines(addout)
    rec["added_total"] = len(adds)
    added_code = [f for f in adds if not noise_re.search(f)]
    rec["C2_added_code"] = added_code
    rec["C2_code_empty"] = len(added_code) == 0

    # C1 复合判定
    rec["C1_content_equal"] = rec["C1_ancestor"] or (
        len(dels) == 0 and len(code_files) == 0
    )

    # C3: main..branch 的提交（= branch 有、main 没有）
    _, logahead, _ = git("log", main + ".." + tip, "--format=%H %s")
    ahead = lines(logahead)
    rec["C3_ahead_count"] = len(ahead)
    rec["C3_ahead_sample"] = ahead[:12]
    rec["C3_empty"] = len(ahead) == 0

    # 落后者读数（filter-repo 重写后 rev-list --count 失效，这里只记录不判定）
    _, behind, _ = git("rev-list", "--count", tip + ".." + main)
    rec["behind_count_unreliable"] = behind.strip()

    # 新增的 .md / docs 等噪音文件（黄档蒸馏清单用）
    added_noise = [f for f in adds if noise_re.search(f)]
    rec["C2_added_noise_count"] = len(added_noise)
    rec["C2_added_noise_sample"] = added_noise[:10]
    return rec


def main_argv():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--main", default="main")
    ap.add_argument("--noise-variant", default="full", choices=sorted(NOISE_VARIANTS))
    ap.add_argument("--remotes", default="gitcode,origin")
    args = ap.parse_args()

    noise_re = NOISE_VARIANTS[args.noise_variant]

    _, head, _ = git("rev-parse", args.main)
    main_sha = head.strip()

    data = {
        "generated_at": "",
        "main": args.main,
        "main_sha": main_sha,
        "noise_pattern": NOISE_PATTERN,
        "noise_variant": args.noise_variant,
        "branches": {},
        "noise_controls": {},
    }

    for rem in [r for r in args.remotes.split(",") if r]:
        _, refs, _ = git(
            "for-each-ref", "--format=%(refname:short)", "refs/remotes/" + rem
        )
        names = [n for n in lines(refs) if not n.endswith("/HEAD")]
        out = {}
        for n in names:
            out[n] = scan_branch(main_sha, n, noise_re)
        data["branches"][rem] = out

    # 本地分支
    _, lrefs, _ = git("for-each-ref", "--format=%(refname:short)", "refs/heads")
    locals_ = lines(lrefs)
    data["branches"]["local"] = {n: scan_branch(main_sha, n, noise_re) for n in locals_}

    # 噪音面对照实验：只对 main vs 一支「已知全旧」的样本跑
    for var in ("full", "no_dsh", "bare"):
        data["noise_controls"][var] = None

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print("[scan] wrote %s  (main=%s)" % (args.out, main_sha[:12]))
    for rem, brs in data["branches"].items():
        print("  %-8s %d branches" % (rem, len(brs)))
    return 0


if __name__ == "__main__":
    sys.exit(main_argv())
