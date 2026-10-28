#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_doc_paths.py —— 文档里引用的**文件路径必须真实存在**。

## 为什么有这把尺（R135）

R134 的连带发现：AGENTS 一直承诺「白盒锁 `src/server/server_bug430_s3_revoke_wbtest.mbt`(4 格)」，
而该文件**从未存在过**（`git ls-files` 无、`--diff-filter=D` 也查不到删除记录）。
那不是"文档写错了名字"，是**一份声称存在的锁根本没人写过**。

文档里的路径是**承诺**：读者照着去找，找不到就是文档说谎；而"找不到"这件事**可以机器判**。

## 判据

扫 canonical 文档里反引号包住的 `src|scripts|docs|templates|patches/…` 路径，逐个查磁盘。

**占位符豁免**（明列、非启发式）：路径段含 `xxx` / `<…>` / `*` 视为示例，不判缺失。
这一条必须写死并各有理由 —— 否则"豁免口"会把真缺失也洗成绿的（本仓判例-30 的老坑）。

## 退出码

- `0` = 全部存在
- `1` = 有引用不存在（**文档说谎**，要么补文件要么改文档）
- `2` = 判据无法自证（一份 canonical 文档都读不到 / 一个路径都解析不到）
"""
import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

RC_OK, RC_MISSING, RC_BROKEN = 0, 1, 2

# canonical 文档面（相对 ROOT）。历史/归档面（CHANGELOG/BACKLOG/reports/memory）**不扫**：
# 定律-3 —— 归档面不改，扫它只会产生无法修的债。
DOCS = [
    "AGENTS.md",
    "README.md",
    "README_EN.md",
    "ARCHITECTURE.md",
    "README.mbt.md",
    "docs/agent-map.md",
    "docs/deliverable.md",
    "docs/SOP.md",
]

PATH_RE = re.compile(
    r"`((?:src|scripts|docs|templates|patches)/[A-Za-z0-9_./-]+"
    r"\.(?:mbt|mbti|py|md|json|ps1|sh|yaml|yml))`")

# 占位符豁免：示例路径，不是承诺。**明列**而非启发式。
PLACEHOLDER_MARKS = ("xxx", "<", ">", "*")


def parse_paths(text):
    """纯函数：从一段文档正文反解 [(path, lineno)]（去重保序）。"""
    out, seen = [], set()
    for ln, line in enumerate(text.splitlines(), 1):
        for m in PATH_RE.finditer(line):
            p = m.group(1)
            if any(k in p for k in PLACEHOLDER_MARKS):
                continue
            if p in seen:
                continue
            seen.add(p)
            out.append((p, ln))
    return out


def check_paths(docs, exists_fn):
    """纯函数：docs = [(name, text)]，exists_fn(path) -> bool。返回违例列表。"""
    problems = []
    total = 0
    for name, text in docs:
        for p, ln in parse_paths(text):
            total += 1
            if not exists_fn(p):
                problems.append("%s:%d 引用 `%s` —— **不存在**（要么补文件，要么改文档）"
                                % (name, ln, p))
    return total, problems


def selftest():
    """合成夹具自证（**不读仓库**）：含一格变异对照（判例-29/30）。"""
    fails, cells = [], []

    def cell(name, ok):
        cells.append(name)
        if not ok:
            fails.append(name)

    good = [("A.md", "真源 `src/diff/diff.mbt` + 测试 `src/diff/diff_test.mbt`")]
    has = {"src/diff/diff.mbt", "src/diff/diff_test.mbt"}
    tot, probs = check_paths(good, lambda p: p in has)
    cell("all-paths-exist-passes", tot == 2 and probs == [])

    # 变异对照：把一个路径从"存在集"里拿掉 ⇒ 必须被抓到
    tot2, probs2 = check_paths(good, lambda p: p == "src/diff/diff.mbt")
    cell("missing-path-is-caught", tot2 == 2 and len(probs2) == 1 and "diff_test.mbt" in probs2[0])

    # 占位符必须豁免（否则示例写法会被判成撒谎）
    ph = [("B.md", "放 `docs/xxx-skill.md` 或 `scripts/xxx.py`")]
    cell("placeholder-is-exempt", check_paths(ph, lambda p: False)[1] == [])

    # 非路径文本不误报
    cell("prose-not-parsed", parse_paths("这段没有路径") == [])

    # 去重：同一路径出现两次只查一次（否则违例刷屏）
    cell("dedupe-same-path", len(parse_paths("`src/a.mbt` 与 `src/a.mbt`")) == 1)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL",
                                       len(cells), " ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return RC_OK if not fails else RC_MISSING


def main(argv):
    if "--selftest" in argv:
        return selftest()
    unknown = [a for a in argv if a.startswith("--") and a != "--selftest"]
    if unknown:
        print("FATAL 未知参数：%s（只接受 --selftest）" % " ".join(unknown))
        return RC_BROKEN

    docs = []
    for rel in DOCS:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            continue
        docs.append((rel, io.open(p, encoding="utf-8", errors="replace").read()))
    if not docs:
        print("FATAL 一份 canonical 文档都读不到 ⇒ 判据无法自证")
        return RC_BROKEN

    def exists(rel):
        return os.path.exists(os.path.join(ROOT, rel))

    total, problems = check_paths(docs, exists)
    if total == 0:
        print("FATAL 解析不到任何路径引用 ⇒ 判据脱锚（先确认 PATH_RE 还认得文档里的写法）")
        return RC_BROKEN
    if problems:
        print("FAIL 文档引用了不存在的路径（%d 处）：" % len(problems))
        for p in problems:
            print("  - " + p)
        return RC_MISSING
    print("PASS 文档路径引用全部存在（%d 份文档 / %d 处引用）" % (len(docs), total))
    return RC_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
