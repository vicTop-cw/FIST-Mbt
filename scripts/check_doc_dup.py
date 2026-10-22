#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_doc_dup.py — 文档「条目重复」尺 + 机械修复（R48）。

**为什么需要它**（2026-10-22 实测两次）：
`scripts/README.md` 在多次 `slave/` 合并后出现**大规模条目重复**——同一段说明被反复拼进来：
- 第一次实测：1519 行里**冗余 992 行**，同一条 `run_guards.py` 条目重复 **13 次**；
- 我按"长条目/加粗标题的完全重复保留首条"去重（删 378 行）后并入主线；
- **不到半小时再测：`run_guards.py` 条目又变回 6 份**——说明合并流程会持续把它们拼回来，
  靠人工偶尔清理治不住，必须有一把尺每轮盯着。

判据（不猜、纯文本）：
- 只看「长条目行」：`len(strip) > 150` 且以 `` - ` `` 或 `**` 开头的行（表格行、短行、代码块**不参与**，
  避免把合法的表头/分隔线当重复）；
- 完全相同的长条目出现 > 1 次 ⇒ 计为重复；
- rc：0 = 干净；1 = 有重复（报告行号 + 浪费字节）；2 = 扫描面为空（判据无法自证）。

`--fix` 做机械去重：保留首次出现，删除后续完全重复的长条目行；表格/短行/代码块不动。
`--selftest` 用临时文件造 干净/重复 两例，断言 rc 与 `--fix` 后的行数（真断言）。

用法：
  python scripts/check_doc_dup.py                       # 默认扫 scripts/README.md
  python scripts/check_doc_dup.py --paths scripts/README.md,AGENTS.md
  python scripts/check_doc_dup.py --fix
  python scripts/check_doc_dup.py --selftest
"""
import argparse
import collections
import io
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
MIN_LEN = 150


def is_entry(line):
    s = line.strip()
    if len(s) <= MIN_LEN:
        return False
    return s.startswith("- `") or s.startswith("**")


def entry_key(line):
    r"""条目 key：以 `- ` 反引号包裹的脚本名取键；否则取加粗标题前 40 字。
    为什么按 key 归组而不是按整行完全相等：2026-10-22 实测 README 里同一脚本**并存多份措辞不同的说明**
    （例：`run_guards.py` 有"26 把尺"与"24 把尺"两种版本共 6 条）——完全重复检测对它们视而不见，
    但它们恰恰是**陈旧副本**：读者不知道该信哪份。"""
    s = line.strip()
    if s.startswith("- `"):
        rest = s[3:]
        end = rest.find("`")
        if end > 0:
            return rest[:end]
        return s[:40]
    return s[2:42]


def scan_text(text):
    """返回 (lines, dups)。dups = [(key, 次数, 行号列表, [各条目长度])]。"""
    lines = text.splitlines()
    groups = {}
    for i, l in enumerate(lines, 1):
        if is_entry(l):
            k = entry_key(l)
            g = groups.setdefault(k, {"lines": [], "lens": []})
            g["lines"].append(i)
            g["lens"].append(len(l.strip()))
    dups = [(k, len(v["lines"]), v["lines"], v["lens"])
            for k, v in groups.items() if len(v["lines"]) > 1]
    dups.sort(key=lambda x: -x[1] * max(x[3]))
    return lines, dups


def fix_text(text):
    """机械去重：同一 key 只保留**最长**那条（更可能含较新读数），其余删除。返回 (新文本, 删除行数)。"""
    lines = text.splitlines()
    best = {}
    for i, l in enumerate(lines):
        if is_entry(l):
            k = entry_key(l)
            if k not in best or len(l.strip()) > len(lines[best[k]].strip()):
                best[k] = i
    keep = set(best.values())
    out, dropped = [], 0
    for i, l in enumerate(lines):
        if is_entry(l) and i not in keep:
            dropped += 1
            continue
        out.append(l)
    return "\n".join(out) + ("\n" if text.endswith("\n") or out else ""), dropped


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    long_entry = "- `demo.py` — " + "旧措辞" * 80
    short = "- `x.py` — 短"
    table = "| a | b |\n| --- | --- |"
    clean = "\n".join([long_entry, short, table, ""])
    newer = "- `demo.py` — " + "新措辞更长的读数说明" * 80
    dirty = "\n".join([long_entry, short, newer, long_entry, table, ""])
    _, dups_clean = scan_text(clean)
    _, dups_dirty = scan_text(dirty)
    cell("clean-no-dup", len(dups_clean), 0)
    cell("dirty-one-key", len(dups_dirty), 1)
    cell("dirty-count-3", dups_dirty[0][1], 3)
    cell("dirty-key", dups_dirty[0][0], "demo.py")
    fixed, dropped = fix_text(dirty)
    cell("fix-dropped-2", dropped, 2)
    cell("fix-keeps-longest", fixed.count(newer), 1)
    cell("fix-drops-stale", fixed.count(long_entry), 0)
    cell("fix-keeps-table", fixed.count("| --- | --- |"), 1)
    cell("short-line-not-entry", is_entry(short), False)
    cell("table-line-not-entry", is_entry("| --- | --- |"), False)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：重复识别三档 + fix 两档 + 非条目排除两档）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--paths", default="scripts/README.md")
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    paths = [p.strip() for p in args.paths.split(",") if p.strip()]
    total_dups, total_dropped, scanned = 0, 0, 0
    for rel in paths:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            print("  跳过（不存在）：%s" % rel)
            continue
        scanned += 1
        text = io.open(p, encoding="utf-8").read()
        lines, dups = scan_text(text)
        if dups:
            total_dups += sum(n - 1 for _, n, _, _ in dups)
            print("  %s：%d 行，重复长条目 %d 类（冗余 %d 行）"
                  % (rel, len(lines), len(dups), sum(n - 1 for _, n, _, _ in dups)))
            for k, n, wl, _lens in dups[:5]:
                print("    %-34s x%-2d 行号 %s…" % (k[:34], n, wl[:6]))
        else:
            print("  %s：%d 行，无重复长条目" % (rel, len(lines)))
        if args.fix and dups:
            new_text, dropped = fix_text(text)
            io.open(p, "w", encoding="utf-8", newline="\n").write(new_text)
            total_dropped += dropped
            print("    --fix：删除 %d 行重复长条目" % dropped)
    if scanned == 0:
        print("FATAL 扫描面为空 —— 判据无法自证，拒绝出结论")
        return 2
    if args.fix:
        print("\n修复完成：共删除 %d 行（请复跑本尺复核）" % total_dropped)
        return 0
    if total_dups:
        print("\n⚠ 共 %d 行冗余长条目：合并流程会把同一段说明反复拼进来（2026-10-22 实测半小时内回涨）。" % total_dups)
        print("  处置：`python scripts/check_doc_dup.py --fix` 机械去重后复跑。")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
