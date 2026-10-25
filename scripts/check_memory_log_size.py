#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_memory_log_size.py — `memory/*.md` 失控追加的**闸**（R59）。

## 为什么必须有一把尺（2026-10-23 实测的仓级事故）
`memory/2026-10-22.md` 在 `gitcode/main` 上长到 **613.31 MB / 3,698,202 行**：
同一段叙述被**追加了成千上万次**（`## R70 …` 这个标题出现 **180,386 次**，不同章节只有 **51 个**），
历史里每提交增长约 **87 MB**（87 → 174 → 261 → 348 → 435 → 522 → 610）。

后果（全部实测）：
1. **GitHub 拒收**：`origin` 的 pre-receive 钩子报
   `File memory/2026-10-22.md is 609.79 MB; this exceeds GitHub's file size limit of 100.00 MB`
   ⇒ **整条 origin 交付线被冻死**（`origin/master` 因此落后 `gitcode/main` 18 个提交）；
2. **本地 git 操作 OOM**：`git worktree add` 直接 `fatal: Out of memory, malloc failed
   (tried to allocate 639407675 bytes)`——那个数字正好是这份文件的 blob 大小；
3. 克隆/落盘/每次 `git show` 都被它拖慢。

## 判据（两条，独立可读）
- **体积**：任一 `memory/*.md` > `MAX_MB`（默认 2 MB）⇒ 红；
- **重复度**：按"空行分段"统计**完全重复的段块**，重复块占段块总数 > `MAX_DUP_RATIO`（默认 0.5）⇒ 红
  （这条专抓"把旧内容再拼一遍"的失控追加：正常日志重复率接近 0，而事故现场是 99.9%）。

rc 契约：`0` 干净 / `1` 检出（逐文件打印读数与成因）/ `2` 扫描面为空（判据无法自证，拒绝报绿）。

## 用法
  python scripts/check_memory_log_size.py            # 默认扫 memory/*.md
  python scripts/check_memory_log_size.py --max-mb 4
  python scripts/check_memory_log_size.py --selftest # 合成样本真断言
"""
import argparse
import collections
import io
import os
import shutil
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def block_stats(text):
    """返回 (段块总数, 去重后块数, 重复块数)。空行分隔视为一个段块。"""
    blocks = [b.strip() for b in text.split("\n\n") if b.strip()]
    uniq = len(set(blocks))
    return len(blocks), uniq, len(blocks) - uniq


def judge(size_bytes, total_blocks, dup_blocks, max_mb=2.0, max_dup_ratio=0.5):
    """纯函数：给出 (verdict, reasons)。verdict ∈ {"ok","big","dup"}。"""
    reasons = []
    if size_bytes > max_mb * 1048576:
        reasons.append("big")
    if total_blocks > 0 and (dup_blocks / float(total_blocks)) > max_dup_ratio:
        reasons.append("dup")
    if not reasons:
        return "ok", []
    return ("big" if "big" in reasons else "dup"), reasons


def scan(path, max_mb, max_dup_ratio):
    size = os.path.getsize(path)
    with io.open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    total, uniq, dup = block_stats(text)
    verdict, reasons = judge(size, total, dup, max_mb, max_dup_ratio)
    return {"path": path, "size": size, "blocks": total, "uniq": uniq, "dup": dup,
            "ratio": (dup / float(total)) if total else 0.0, "verdict": verdict, "reasons": reasons}


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    cell("ok-small-unique", judge(1024, 10, 0)[0], "ok")
    cell("big-file", judge(3 * 1048576, 10, 0)[0], "big")
    cell("dup-heavy", judge(1024, 100, 90)[0], "dup")
    cell("both", judge(3 * 1048576, 100, 90)[1], ["big", "dup"])
    cell("boundary-2mb", judge(2 * 1048576, 10, 0)[0], "ok")
    cell("empty-no-false-positive", judge(0, 0, 0)[0], "ok")

    # 真样本：重复段块与唯一段块的统计必须一致
    d = tempfile.mkdtemp(prefix="memlog-")
    try:
        p = os.path.join(d, "m.md")
        # 夹具：A/B/A/A/A ⇒ 段块 5、重复 3、重复率 0.6 > 0.5 ⇒ dup
        # （第一版写 "A\n\nB\n\nA\n\nA\n" 期望 3 块，但尾部换行后是 4 块、重复率正好 0.5 不越线，
        #  自检当场抓出——夹具算术必须自己也算一遍）
        io.open(p, "w", encoding="utf-8").write("A\n\nB\n\nA\n\nA\n\nA\n")
        st = scan(p, 2.0, 0.5)
        cell("scan-blocks-5", st["blocks"], 5)
        cell("scan-dup-3", st["dup"], 3)
        cell("scan-verdict-dup", st["verdict"], "dup")
    finally:
        shutil.rmtree(d, ignore_errors=True)

    # 调用面锁（BUG-405）：selftest 必须能从调用图到达 main/run 面——否则
    # 「--selftest 绿」与「真跑判据」是两条脱钩的路（BUG-366 一族）。喂 temp root，
    # run 的 IO 走 temp 夹具，不触仓库现状面（hermetic H1 不红）。
    d2 = tempfile.mkdtemp(prefix="memlog-callface-")
    try:
        os.makedirs(os.path.join(d2, "memory"), exist_ok=True)
        io.open(os.path.join(d2, "memory", "empty.md"), "w", encoding="utf-8").close()
        rc = run(d2, 2.0, 0.5)
        cell("callface-run-rc-0", rc, 0)
    finally:
        shutil.rmtree(d2, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：体积三档 + 重复度两档 + 边界/空样本 + 真样本扫描三格）" % len(cells))
    return 0


def run(root, max_mb, max_dup_ratio):
    d = os.path.join(root, "memory")
    if not os.path.isdir(d):
        print("FATAL 扫描面为空（%s 不存在）—— 判据无法自证，拒绝报绿" % d)
        return 2
    files = sorted(f for f in os.listdir(d) if f.endswith(".md"))
    if not files:
        print("FATAL 扫描面为空（memory/ 下没有 .md）—— 拒绝报绿")
        return 2
    reds = []
    for f in files:
        p = os.path.join(d, f)
        try:
            st = scan(p, max_mb, max_dup_ratio)
        except OSError as e:
            print("  %-26s 读不动: %s" % (f, e))
            reds.append((f, "unreadable"))
            continue
        tag = "OK  " if st["verdict"] == "ok" else "RED "
        print("  %s %-26s %8.2f MB  段块 %6d / 唯一 %6d / 重复率 %5.1f%%%s"
              % (tag, f, st["size"] / 1048576.0, st["blocks"], st["uniq"], st["ratio"] * 100,
                 ("  ← " + ",".join(st["reasons"])) if st["reasons"] else ""))
        if st["verdict"] != "ok":
            reds.append((f, st["verdict"]))
    if reds:
        print("\nFAIL %d 个日志文件失控（体积 > %.1f MB 或重复率 > %.0f%%）："
              % (len(reds), max_mb, max_dup_ratio * 100))
        print("  失控追加会让 `git push` 被 GitHub 100MB 限制直接拒收（R59 实测：整条 origin 线冻结），")
        print("  也会让 `git worktree add` OOM。处置：按空行分段去重（保留首次出现的段块）后提交，")
        print("  历史面的大 blob 只能靠 filter-repo 重写（**不可逆，须 owner 裁决**）。")
        return 1
    print("\nPASS 全部 %d 个日志文件在体积与重复度上限内" % len(files))
    return 0


def main(argv):
    """CLI 入口：解析 argv 后把判据逻辑交给 run(root, …)。selftest 走 run 的 temp 夹具。"""
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-mb", type=float, default=2.0)
    ap.add_argument("--max-dup-ratio", type=float, default=0.5)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default="")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    return run(args.root or ROOT, args.max_mb, args.max_dup_ratio)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
