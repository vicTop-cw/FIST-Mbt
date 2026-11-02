#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_precedents_doc.py —— 判例库（docs/AGENTS-precedents.md）的形态尺（R121 立）。

为什么需要（R120 终审缺口）：判例-32~38 于 R119 搬出 AGENTS.md 后，那份文档的**内容**
没有任何尺在看——被写坏（跳号、丢日期戳、指针句滞后）无人知。指针句滞后已实发生过一次：
R120 内容到判例-42 时 AGENTS.md 指针仍写「判例-32~38」（BUG-514 同族「自述滞后于现状」）。

三判（全部从正文反解，不硬编码终点数）：
  R1 编号连续无跳号：`^### 判例-(\\d+)` 从 32 起连续递增；
  R2 指针对表：AGENTS.md 的「判例-32~N 已搬出」的 N == 新文档实测最大编号；
  R3 日期戳：每条判例标题含 `（20xx-` 日期（判例都要「立」在某个实测日期上）。

自拒契约（rc=2，与 J15 同族）：判例库读不到 / 一条判例都解析不到 / AGENTS.md 指针句缺失
——「权威被删空必红」，绝不因读不到而出绿灯。
"""
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC_PATH = os.path.join(ROOT, "docs", "AGENTS-precedents.md")
AGENTS_PATH = os.path.join(ROOT, "AGENTS.md")

RE_HEADING = re.compile(r"^### 判例-(\d+)：.*$", re.M)
RE_DATE = re.compile(r"（20\d{2}-")
RE_POINTER = re.compile(r"判例-(\d+)~(\d+) 已搬出")
_FIRST = 32

_KNOWN_FLAGS = ("--selftest",)


def precedents_problems(doc_text, agents_text):
    """纯函数判核：返回 (parseable, problems)。selftest 直接喂合成文本。"""
    problems = []
    heads = [(int(m.group(1)), m.group(0)) for m in RE_HEADING.finditer(doc_text)]
    if not heads:
        return False, ["判例库一条 `### 判例-N：` 都解析不到（读的是 %d 字节）" % len(doc_text)]
    nums = [n for n, _ in heads]
    # R1：从 32 起连续无跳号
    if nums[0] != _FIRST:
        problems.append("R1 首条判例编号是 %d，不是起点 %d（32~31 仍在 AGENTS.md，搬出必须从 32 起）" % (nums[0], _FIRST))
    gaps = [n for n in range(nums[0], nums[-1] + 1) if n not in set(nums)]
    for g in gaps:
        problems.append("R1 判例-%d 缺号（编号序列不连续：%s…%s）" % (g, nums[0], nums[-1]))
    # R3：每条标题带日期戳
    for n, head in heads:
        if not RE_DATE.search(head):
            problems.append("R3 判例-%d 标题缺日期戳（`（20xx-xx-xx`）：%s" % (n, head.strip()[:60]))
    # R2：AGENTS.md 指针句的终点 == 实测最大编号
    p = RE_POINTER.search(agents_text)
    if p is None:
        problems.append("R2 AGENTS.md 找不到「判例-32~N 已搬出」指针句——指针被删 = agent 读不到判例库在哪")
    else:
        lo, hi = int(p.group(1)), int(p.group(2))
        if lo != _FIRST:
            problems.append("R2 指针句起点是 %d，应为 %d" % (lo, _FIRST))
        if hi != nums[-1]:
            problems.append("R2 指针句写「判例-%d~%d 已搬出」但判例库实测到 %d —— 自述滞后于现状（BUG-514 同族）" % (lo, hi, nums[-1]))
    return True, problems


def _read(path):
    with open(path, "rb") as f:
        return f.read().decode("utf-8", errors="replace")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--selftest" in argv:
        return selftest()
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知旗标：%s（rc=2）" % (" ".join(unknown), " / ".join(_KNOWN_FLAGS)))
        return 2
    if argv:
        print("[FATAL] 不接受位置参数 %s（rc=2；路径由仓库根反解）" % " ".join(argv))
        return 2
    missing = [p for p in (DOC_PATH, AGENTS_PATH) if not os.path.isfile(p)]
    if missing:
        print("REJECT 判据输入面缺失：%s（判据无法自证，拒绝出结论）" % " / ".join(missing))
        return 2
    parseable, problems = precedents_problems(_read(DOC_PATH), _read(AGENTS_PATH))
    if not parseable:
        print("REJECT %s（rc=2：权威面为空 = 判据无法自证）" % problems[0])
        return 2
    if problems:
        print("FAIL 判例库形态 %d 处违例：" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    heads = [int(m.group(1)) for m in RE_HEADING.finditer(_read(DOC_PATH))]
    print("PASS 判例库形态：判例-%d..%d 连续 %d 条、日期戳齐、AGENTS.md 指针对表一致（rc=0）"
          % (heads[0], heads[-1], len(heads)))
    return 0


def selftest():
    doc_ok = (
        "# 判例库\n\n"
        "### 判例-32：探针标定（2026-10-27 立）\n正文。\n\n"
        "### 判例-33：配置这根线（2026-10-27 立）\n正文。\n"
    )
    agents_ok = "> **判例-32~33 已搬出（R119 起）**：整篇搬到判例库。"
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, got, want))

    # ① 干净样例不误红（反向对照）
    p, probs = precedents_problems(doc_ok, agents_ok)
    cell("clean-doc-zero-problems", (p, probs), (True, []))
    # ② 跳号必红
    doc_gap = doc_ok.replace("### 判例-33：配置这根线（2026-10-27 立）", "### 判例-34：配置这根线（2026-10-27 立）")
    _, probs = precedents_problems(doc_gap, "> **判例-32~34 已搬出**：x")
    cell("gap-33-reds", any("R1 判例-33 缺号" in x for x in probs), True)
    # ③ 指针滞后必红（BUG-514 同族本体）
    _, probs = precedents_problems(doc_ok, "> **判例-32~31 已搬出**：x")
    cell("pointer-lag-reds", any("R2 指针句写「判例-32~31 已搬出」但判例库实测到 33" in x for x in probs), True)
    # ④ 指针被删必红
    _, probs = precedents_problems(doc_ok, "没有任何指针句。")
    cell("pointer-missing-reds", any("找不到「判例-32~N 已搬出」指针句" in x for x in probs), True)
    # ⑤ 日期戳缺失必红
    doc_nodate = doc_ok.replace("### 判例-33：配置这根线（2026-10-27 立）", "### 判例-33：配置这根线")
    _, probs = precedents_problems(doc_nodate, agents_ok)
    cell("missing-date-reds", any("R3 判例-33 标题缺日期戳" in x for x in probs), True)
    # ⑥ 空库自拒
    p, _ = precedents_problems("# 没有判例\n", agents_ok)
    cell("empty-doc-self-reject", p, False)
    # ⑦ 未知旗标硬拒（R207 本体：拼错自检开关 = 静默失去自检）
    cell("misspelled-selftest-rejected", main(["--self-test"]), 2)
    cell("unknown-flag-rejected", main(["--definitely-not-real"]), 2)
    # ⑧ 位置参数整体拒绝
    cell("positional-args-rejected", main(["some/path"]), 2)

    bad = [c for c in cells if not c[1]]
    for name, ok, got, want in bad:
        print("SELFTEST FAIL [%s] got=%r want=%r" % (name, got, want))
    print("SELFTEST %s（%d 格：形态 6 + 旗标面 3，全部合成入参不读真仓）"
          % ("OK" if not bad else "FAIL", len(cells)))
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # BUG-369：尺子自己坏了走 4 号档，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
