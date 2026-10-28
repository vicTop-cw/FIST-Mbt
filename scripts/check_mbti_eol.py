#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_mbti_eol.py — `.mbti` 行尾闸（2026-10-23 实测踩坑后落）。

## 为什么要它
`moon info` 生成的 `.mbti` 字节本来就是 **LF**，但 Windows 侧 `core.autocrlf=true` 会在
checkout 时把它转成 **CRLF**——于是"没改任何语义、只跑了一次 `moon info`"就让
core/engine/server 三份 `.mbti` 变 dirty，`git status` 恒有 CRLF 噪声，提交时还得手动
`git add` 排除、极易误提交格式噪声。

修复：`.gitattributes` 钉 `*.mbti text eol=lf`（git blob 存 LF、checkout 也一律 LF）。

## 这个尺子怎么判（三档）
- **rc=0 PASS**：`.gitattributes` 规则在 + **跟踪面全部 `.mbti`** 的 HEAD blob 纯 LF（加规则不会触发
  renormalize 把已在跟踪的文件刷脏）+ 工作树 3 个 `.mbti` 不 dirty（eol 真正生效）。
- **rc=1 FAIL**：规则缺失 / HEAD blob 有 CR / 工作树 `.mbti` 有未提交改动。
- **rc=3 SKIP**：不是 git 仓库（读不到 HEAD），诚实跳过不误红。

纯函数 `rules_cover_mbti` / `blob_has_cr` 可单测；`--selftest` 只验纯函数（合成样本）。

用法：
  python scripts/check_mbti_eol.py            # 复跑校验并判 PASS/FAIL
  python scripts/check_mbti_eol.py --selftest # 只验纯函数（合成样本）
"""
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

GITATTR = ".gitattributes"
MBTI_GLOB = "*.mbti"
# 覆盖面真源 = **git 跟踪面里的全部 `.mbti`**，不是一份手抄清单（判例-16 / R43）。
#
# **为什么改**：早先这里是 3 份硬编码（core/engine/server 的 pkg.generated.mbti），
# 而全仓跟踪着 24 份 `.mbti`。⇒ 另外 21 份谁被 autocrlf 刷成 CRLF，本尺**照样报绿**。
# 这正是判例-16「判据覆盖必须 ≥ 主张的覆盖」的形状：尺说自己管「`.mbti` 行尾」，
# 实际只看了其中 1/8。
#
# 兜底：取不到 git 跟踪面（非仓库/裸仓库）时退回下面这 3 份，
# 让「无 git 环境」仍能覆盖最关键的产物，且 SKIP(3) 分支会如实说明无法验 blob。
MBTI_FILES_FALLBACK = (
    "src/core/pkg.generated.mbti",
    "src/engine/pkg.generated.mbti",
    "src/server/pkg.generated.mbti",
)


def tracked_mbti_files():
    """git 跟踪面里的全部 `.mbti`（排序）。取不到 ⇒ 返回兜底 3 份。"""
    try:
        r = subprocess.run(["git", "ls-files", "--", MBTI_GLOB],
                           cwd=ROOT, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=60)
    except Exception:
        return list(MBTI_FILES_FALLBACK)
    if r.returncode != 0:
        return list(MBTI_FILES_FALLBACK)
    files = [ln.strip() for ln in (r.stdout or "").splitlines() if ln.strip()]
    return sorted(files) if files else list(MBTI_FILES_FALLBACK)


def rules_cover_mbti(gitattributes_content):
    """纯函数：`.gitattributes` 内容里是否有钉住 `*.mbti` 且 `eol=lf` 的规则。

    - 要求 glob `*.mbti` 出现在某一行；
    - 同一行（或该行之后续行——gitattributes 不支持续行，故只算同一行）带 `eol=lf`。
    - 属性名 **大小写敏感**（gitattributes 只认小写 `eol`；`EOL=LF` 不生效，故按 False 判，
      selftest 有反例格钉住）。
    - 忽略 `#` 开头的注释行（避免注释里的"*.mbti text eol=lf"被误当规则，沿用
      BUG-112 的"去掉注释再判"口径）。
    """
    if not gitattributes_content:
        return False
    pat = re.compile(r"^\s*\*\.[mM][bB][tT][iI]\s+.*\beol\s*=\s*[lL][fF]\b")
    for line in gitattributes_content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if pat.match(line):
            return True
    return False


def blob_has_cr(blob_bytes):
    """纯函数：git blob 字节里是否含 `\\r`（CRLF 说明 blob 存的就是 CRLF，钉 eol=lf 会 renormalize）。"""
    return b"\r" in (blob_bytes or b"")


def git(*args):
    p = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or ""), (p.stderr or "")


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    # rules_cover_mbti
    cell("rule-present",
         rules_cover_mbti("# 钩子必须 LF\n.githooks/* text eol=lf\n*.mbti   text eol=lf\n"),
         True)
    cell("rule-present-nocomment",
         rules_cover_mbti("*.mbti text eol=lf\n"), True)
    cell("rule-present-upper-eol-invalid",
         rules_cover_mbti("*.mbti text EOL=LF\n"), False)
    cell("rule-missing-eol",
         rules_cover_mbti("*.mbti text\n"), False)
    cell("rule-missing-glob",
         rules_cover_mbti("*.sh text eol=lf\n"), False)
    cell("rule-in-comment-only",
         rules_cover_mbti("# *.mbti text eol=lf\n*.sh text eol=lf\n"), False)
    cell("rule-empty",
         rules_cover_mbti(""), False)
    cell("rule-none",
         rules_cover_mbti(None), False)

    # blob_has_cr
    cell("blob-lf", blob_has_cr(b"a\nb\n"), False)
    cell("blob-crlf", blob_has_cr(b"a\r\nb\r\n"), True)
    cell("blob-empty", blob_has_cr(b""), False)
    cell("blob-none", blob_has_cr(None), False)

    # ── 判例-16 结构性护栏：覆盖面必须来自**跟踪面**，不是手抄清单 ──────────
    # 早先 MBTI_FILES 硬编码 3 份（core/engine/server），而跟踪面有 24 份 ⇒ 另外 21 份
    # 谁被 autocrlf 刷成 CRLF，本尺照样报绿。这条格钉住「扩面真的生效」。
    cov_ok = True
    _files = tracked_mbti_files()
    if not _files:
        print("SELFTEST FAIL：tracked_mbti_files() 返回空 ⇒ 覆盖面为空，判据会静默全绿")
        cov_ok = False
    if not set(MBTI_FILES_FALLBACK).issubset(set(_files)):
        _miss = sorted(set(MBTI_FILES_FALLBACK) - set(_files))
        print("SELFTEST FAIL：动态覆盖面漏了兜底清单里的 %s" % (_miss,))
        cov_ok = False
    _r = subprocess.run(["git", "ls-files", "--", MBTI_GLOB], cwd=ROOT,
                        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if _r.returncode == 0:
        _truth = len([x for x in _r.stdout.splitlines() if x.strip()])
        if _truth and _truth != len(_files):
            print("SELFTEST FAIL：覆盖面 %d 份 != 跟踪面 %d 份 ⇒ 判据面窄于追踪面"
                  % (len(_files), _truth))
            cov_ok = False
    cells.append(("coverage-from-tracked-surface", cov_ok, ""))

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        sys.exit(1)  # NO_CALL_FACE J2
    n_rule = len([n for n, _, _ in cells if n.startswith("rule")])
    n_blob = len([n for n, _, _ in cells if n.startswith("blob")])
    n_cov = len([n for n, _, _ in cells if n.startswith("coverage")])
    print("SELFTEST OK（%d 格：规则 %d / blob %d / 覆盖面 %d）"
          % (len(cells), n_rule, n_blob, n_cov))
    sys.exit(0)  # NO_CALL_FACE J2


def main(argv):
    if "--selftest" in argv:
        return selftest()

    # 1) 规则在
    attr_path = os.path.join(ROOT, GITATTR)
    if not os.path.isfile(attr_path):
        print("FAIL `.gitattributes` 不存在——`*.mbti` 行尾规则无处可钉")
        return 1
    with open(attr_path, "r", encoding="utf-8") as f:
        attr_content = f.read()
    if not rules_cover_mbti(attr_content):
        print("FAIL `.gitattributes` 缺 `*.mbti text eol=lf` 规则——`moon info` 后 `.mbti` 会继续被 "
              "autocrlf 转 CRLF 变 dirty")
        return 1

    # 2) HEAD blob 纯 LF（加规则不触发 renormalize）
    rc, _, _ = git("rev-parse", "--git-dir")
    if rc != 0:
        print("SKIP(3) 不是 git 仓库（读不到 HEAD），无法验 blob/工作树——诚实跳过不误红")
        return 3
    mbti_files = tracked_mbti_files()
    cr_files = []
    for rel in mbti_files:
        cr, blob, _ = git("cat-file", "blob", "HEAD:" + rel)
        if cr != 0:
            print("SKIP(3) HEAD 无 `%s`——无法验 blob" % rel)
            return 3
        if blob_has_cr(blob.encode("utf-8", errors="replace")):
            cr_files.append(rel)
    if cr_files:
        print("FAIL HEAD blob 含 CR（存的就是 CRLF）：%s——钉 `eol=lf` 会触发 renormalize 把已跟踪文件刷脏，"
              "先 `git add --renormalize` 归一再落规则" % ", ".join(cr_files))
        return 1

    # 3) 工作树不 dirty（eol 生效）
    cr, status, _ = git("status", "--porcelain", "--", *mbti_files)
    dirty = [l for l in (status or "").splitlines() if l.strip()]
    if dirty:
        print("FAIL 工作树 `.mbti` 有未提交改动（dirty），eol=lf 未生效：")
        for l in dirty:
            print("  | " + l[:160])
        print("  提示：`git checkout -- <mbti>` 重新 checkout 为 LF；若 `moon info` 后立刻变脏，"
              "说明规则没被 git 采纳（检查 `.gitattributes` 语法 / `core.autocrlf`）")
        return 1

    print("PASS `.mbti` 行尾闸：规则在 / HEAD blob 纯 LF / 工作树干净（`moon info` 后不再脏）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))