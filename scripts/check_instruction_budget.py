#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_instruction_budget.py —— **指令文件超出 harness 预算**的诊断尺（R211）。

## 为什么要有它

AGENTS.md 是本仓的**规则书**，但 harness 对"工作区指令"有**字节预算**（本机实测 65,536，
实际注入时截断到 **65,244**）。R211 实测本仓 AGENTS.md = **101,115 字节 / 730 行** ——
⇒ **第 ~591 行之后的整段规则，任何 agent 都读不到**（包括 `## 路径约定`、
`### 一源四态 · 插件态`、`### 嵌入式 MCPCf 内部工具`）。

**这条的危险不在于"文件太长"，而在于"它看起来是权威的、完整的"。**
一个 agent 会说"AGENTS.md 里写了"，而那段话在截断点之后 —— 它其实从没读到过。

## 判据

- 计算 `AGENTS.md` 的字节数，与预算（默认 65536）比较；
- 若超出：**逐条列出被截掉的 `##` / `###` 章节标题**（= 谁都读不到的规则）；
- rc 契约：`0` 在预算内 / `1` 超出（**默认不判红**，见下）/ `2` 无法自证；
- `--strict` 才把"超出"当失败（未来把 AGENTS.md 拆瘦后可在 CI 启用）；
  默认模式只**报告**（本仓电池里登记为 `diag`），因为"文件超预算"不是某一次提交引入的，
  让它常红只会训练大家忽略红。

用法：
    python scripts/check_instruction_budget.py
    python scripts/check_instruction_budget.py --strict --budget 65536
    python scripts/check_instruction_budget.py --selftest
"""
from __future__ import annotations

import io
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET = os.path.join(ROOT, "AGENTS.md")
# 本机 harness 实测：预算 65536，实际注入 65244（留 292 字节给包裹文本）。
DEFAULT_BUDGET = 65536
INJECT_MARGIN = 292
KNOWN_FLAGS = ("--strict", "--budget", "--selftest")


def analyse(text, budget=DEFAULT_BUDGET):
    """纯函数：返回 (total_bytes, visible_bytes, cut_sections)。"""
    raw = text.encode("utf-8")
    total = len(raw)
    visible = min(total, budget - INJECT_MARGIN)
    # 逐行累计字节，找出「起笔时已经越过可见线」的 ## / ### 章节
    cut = []
    acc = 0
    for line in text.split("\n"):
        acc += len(line.encode("utf-8")) + 1  # +1 = 换行
        s = line.strip()
        if acc > visible and (s.startswith("## ") or s.startswith("### ")):
            cut.append(s.lstrip("#").strip())
    return total, visible, cut


def selftest():
    ok = True

    def cell(name, cond, detail=""):
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name + ("" if cond else " :: " + str(detail)))
        ok = ok and cond

    small = "## A\n正文\n### B\n正文\n"
    total, visible, cut = analyse(small, budget=100000)
    cell("预算内：不报被截章节", cut == [], cut)
    cell("预算内：total 是字节数", total == len(small.encode("utf-8")), total)

    big = "## 前面的规则\n" + ("填充\n" * 2000) + "## 被截掉的规则\n正文\n"
    total2, visible2, cut2 = analyse(big, budget=1000)
    cell("超预算：报出被截章节", cut2 == ["被截掉的规则"], cut2)
    cell("超预算：total > visible", total2 > visible2, (total2, visible2))

    # 变异对照：把"被截"的那节挪到最前面 ⇒ **它自己**不再被报（但**末尾那节**仍在截断线后，
    # 所以不能断言列表为空 —— 这正是我第一次写错的地方：变异格的断言必须只针对**被移动的那一节**）。
    moved = "## 被截掉的规则\n" + "正文\n" + ("填充\n" * 2000) + "## 前面的规则\n"
    _, _, cut3 = analyse(moved, budget=1000)
    cell("变异对照：前移的那节不再被报", "被截掉的规则" not in cut3, cut3)
    cell("变异对照：末尾那节仍被报（证明尺还在看）", "前面的规则" in cut3, cut3)
    print("=== selftest %d/5 ===" % (5 if ok else 0))
    return 0 if ok else 1


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    unknown = [a for a in argv if a.startswith("-") and a.split("=")[0] not in KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）" % (" ".join(unknown), " / ".join(KNOWN_FLAGS)))
        return 2
    if "--selftest" in argv:
        return selftest()
    budget = DEFAULT_BUDGET
    for i, a in enumerate(argv):
        if a == "--budget" and i + 1 < len(argv):
            budget = int(argv[i + 1])
        elif a.startswith("--budget="):
            budget = int(a.split("=", 1)[1])
    try:
        text = io.open(TARGET, encoding="utf-8").read()
    except OSError as e:
        print("[FATAL] 读不到 AGENTS.md：%s ⇒ rc=2" % e)
        return 2
    total, visible, cut = analyse(text, budget)
    print("AGENTS.md = %d 字节 / 预算 %d（实际注入上限 %d）" % (total, budget, visible))
    if total <= visible:
        print("PASS 指令文件在预算内（全部章节可见）")
        return 0
    print("WARN 超出预算 %d 字节 ⇒ 以下 **%d 个章节任何 agent 都读不到**：" % (total - visible, len(cut)))
    for s in cut:
        print("  - " + s)
    print("  修法二选一：① 把这些章节移到文件前部；② 把它们拆到独立文件并在前部留一行指引。")
    return 1 if "--strict" in argv else 0


if __name__ == "__main__":
    sys.exit(main())
