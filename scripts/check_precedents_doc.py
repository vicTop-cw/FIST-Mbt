#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_precedents_doc.py —— 判例库（docs/AGENTS-precedents.md）的形态尺（R121 立）。

为什么需要（R120 终审缺口）：判例-32~38 于 R119 搬出 AGENTS.md 后，那份文档的**内容**
没有任何尺在看——被写坏（跳号、丢日期戳、指针句滞后）无人知。指针句滞后已实发生过一次：
R120 内容到判例-42 时 AGENTS.md 指针仍写「判例-32~38」（BUG-514 同族「自述滞后于现状」）。

三判（全部从正文反解，不硬编码终点数）：
  R1 编号连续无跳号、且不重号：从 32 起连续递增；
  R2 指针对表：AGENTS.md 的「判例-32~N 已搬出」的 N == 新文档实测最大编号；
  R3 日期戳：每条判例标题含 `（20xx-` 日期（判例都要「立」在某个实测日期上）。

自拒契约（rc=2，与 J15 同族）：判例库读不到 / 一条判例都解析不到 / AGENTS.md 指针句缺失
——「权威被删空必红」，绝不因读不到而出绿灯。

判据①（R213 修尺 · 2026-11-07 · 判例-45「形态尺面如实登记」段现读登记的缺陷）：**抬头按语义取数，
不按排版**。本尺第一版写死 `^### 判例-(\\d+)：`（三条 `#` + 中文冒号），而判例-44/45 两条最新记的是
`## 判例-N ·`（两条 `#` + 间隔号）⇒ 两条**根本不进 R1/R2 取数面**，实测尺绿 `判例-32..43 连续 12 条`
而库里到 45 ——「尺绿而它管的对象已经漂移」是最坏的失效形态（AGENTS.md 指针句滞后就是它的直接后果）。
现在一条抬头 = 行首 ATX 标记（**1~6 个 `#`**）+ 可选空白 + `判例-<编号>`；编号之后的分隔符
（`：` `:` `·` `—` `-` 或直接换行）**一律不算身份**。
未来新形要不要收：**凡「行首 ATX 抬头 + 判例-<数字>」即收**（井号数与分隔符是风格，编号才是身份）；
**散文行里的提及不算**（如「同族口径：判例-44 第 2 条…」没有行首 `#`）——这一条与旧式一致，不是放宽。

判据②（为什么不走「改文档迁就尺」那条路）：判例是**登记面**，44/45 的抬头形正是这条缺陷的证据本身
（45 末尾「形态尺面如实登记」段逐字写着它用的是 `## 判例-N ·` 形）⇒ 改史迁就尺 = 毁掉刚登记的实证，
且尺依旧只会认一种形，下一个 `## 判例-46 ·` 照样漏（判例-39「改名不是接线」同族：认格式不认语义）。

判据③（围栏内的伪抬头不算）：正文里 ``` / ~~~ 围栏中的示例行（如教学片段里的 `### 判例-N：`）
不是条目，`_heading_lines()` 按围栏开闭状态过滤，与判据①的「行首 ATX」共同构成取数面边界。
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

# 语义式抬头（判据①）：井号 1~6 个都认，编号之后的分隔符不参与判定。
# ⚠️ `_MUT_NEEDLE` 必须**只出现在这一行**——变异对照按行首锚定取这一行、并在行内数针的命中次数。
RE_HEADING = re.compile(r"^#{1,6}[ \t]*判例-(\d+)(?!\d).*$", re.M)
_MUT_TARGET = "RE_HEADING = re.compile("
_MUT_NEEDLE = "#{1,6}"
RE_DATE = re.compile(r"（20\d{2}-")
RE_POINTER = re.compile(r"判例-(\d+)~(\d+) 已搬出")
_FIRST = 32

_KNOWN_FLAGS = ("--selftest",)


def _heading_lines(doc_text):
    """取数面：返回 [(编号, 抬头原文)]，按行首语义式匹配，并剔除代码围栏内的伪抬头（判据③）。"""
    out = []
    in_fence = False
    for line in doc_text.splitlines():
        probe = line.lstrip()
        if probe.startswith("```") or probe.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = RE_HEADING.match(line)
        if m:
            out.append((int(m.group(1)), line))
    return out


def precedents_problems(doc_text, agents_text):
    """纯函数判核：返回 (parseable, problems)。selftest 直接喂合成文本。"""
    problems = []
    heads = _heading_lines(doc_text)
    if not heads:
        return False, ["判例库一条判例抬头都解析不到（语义式：行首 ATX 抬头 + `判例-<编号>`，读的是 %d 字节）" % len(doc_text)]
    nums = [n for n, _ in heads]
    # R1：从 32 起连续无跳号
    if nums[0] != _FIRST:
        problems.append("R1 首条判例编号是 %d，不是起点 %d（32~31 仍在 AGENTS.md，搬出必须从 32 起）" % (nums[0], _FIRST))
    gaps = [n for n in range(nums[0], nums[-1] + 1) if n not in set(nums)]
    for g in gaps:
        problems.append("R1 判例-%d 缺号（编号序列不连续：%s…%s）" % (g, nums[0], nums[-1]))
    # R1b（R213 同批）：同一编号出现两次 = 两条判例抢一个号，连续性判不到这一档
    seen = {}
    for n, head in heads:
        seen[n] = seen.get(n, 0) + 1
    for n in sorted(k for k, v in seen.items() if v > 1):
        problems.append("R1 判例-%d 重号（该编号出现 %d 次，判例编号必须唯一）" % (n, seen[n]))
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
    # R207 的完整形状：**先**做白名单/位置参数核，**再**分派自检——
    # 顺序反过来会让 `--selftest --拼错的旗标` 静默跑自检并报绿（派单点名的同族缺口，R213 本批顺手关掉）。
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知旗标：%s（rc=2）" % (" ".join(unknown), " / ".join(_KNOWN_FLAGS)))
        return 2
    positional = [a for a in argv if not a.startswith("-")]
    if positional:
        print("[FATAL] 不接受位置参数 %s（rc=2；路径由仓库根反解）" % " ".join(positional))
        return 2
    if "--selftest" in argv:
        return selftest()
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
    heads = _heading_lines(_read(DOC_PATH))
    print("PASS 判例库形态：判例-%d..%d 连续 %d 条（抬头按语义取数，两种排版形都进 R1/R2）、"
          "日期戳齐、AGENTS.md 指针对表一致（rc=0）" % (heads[0][0], heads[-1][0], len(heads)))
    return 0


def _mutation_narrow_heading_class(doc_two, agents_34):
    """变异对照（判例-29/30 的硬要求）：**改坏真代码行**，不是改注释、也不是改夹具。

    做法：按行首锚定 `_MUT_TARGET` 取到 RE_HEADING 那一行赋值语句，把行内的井号类
    `_MUT_NEEDLE`（`#{1,6}`）收窄成 `###`（= 本尺修前的旧形，只认三条井号），
    再用变异后的模式跑同一份**双形合成样例** ⇒ 形②（`## 判例-N ·`）必须**当场退出取数面**，
    R2 的最大编号读数必须从 34 退回 32。
    三道自保，任一不成立就判「尺子坏了」而不是判绿：
      ① 锚定行必须恰好 1 行（改名/复制 = 反脱锚，判例-32）；
      ② 针在**该行内**恰好命中 1 次（命中 0 次或多次都可能把变异打到注释上）；
      ③ 变异后的模式与原模式必须真的不同串。
    返回 (anchor_hits, needle_hits, changed, mutant_max_read, clean_with_real_regex)。
    """
    src = _read(os.path.abspath(__file__))
    hit_lines = [ln for ln in src.splitlines() if ln.startswith(_MUT_TARGET)]
    if len(hit_lines) != 1:
        return len(hit_lines), 0, False, None, None
    line = hit_lines[0]
    needle_hits = line.count(_MUT_NEEDLE)
    if needle_hits != 1:
        return len(hit_lines), needle_hits, False, None, None
    head, rest = line.split('re.compile(r"', 1)
    pat_src = rest.rsplit('"', 1)[0]
    mutated_src = pat_src.replace(_MUT_NEEDLE, "###", 1)
    changed = mutated_src != pat_src
    saved = RE_HEADING
    try:
        globals()["RE_HEADING"] = re.compile(mutated_src, re.M)
        _, probs_mut = precedents_problems(doc_two, agents_34)
    finally:
        globals()["RE_HEADING"] = saved
    _, probs_real = precedents_problems(doc_two, agents_34)
    mutant_max = None
    for x in probs_mut:
        m = re.search(r"但判例库实测到 (\d+)", x)
        if m:
            mutant_max = int(m.group(1))
    return len(hit_lines), needle_hits, changed, mutant_max, (probs_real == [])


def selftest():
    doc_ok = (
        "# 判例库\n\n"
        "### 判例-32：探针标定（2026-10-27 立）\n正文。\n\n"
        "### 判例-33：配置这根线（2026-10-27 立）\n正文。\n"
    )
    agents_ok = "> **判例-32~33 已搬出（R119 起）**：整篇搬到判例库。"
    # 双形样例：形① `### 判例-N：`（判例-32~43 的写法）+ 形② `## 判例-N ·`（判例-44/45 的写法）
    doc_two_forms = (
        "# 判例库\n\n"
        "### 判例-32：探针标定（2026-10-27 立）\n正文。\n\n"
        "## 判例-33 · 基线新鲜度（2026-11-06 立 · 第四次同型）\n正文。\n\n"
        "## 判例-34 · 幻影提交号（2026-11-07 立 · BUG-578 追记现读抓出）\n正文。\n"
    )
    agents_34 = "> **判例-32~34 已搬出（R119 起 · 字节预算）**：整篇搬到判例库。"
    cells = []

    def cell(name, got, want, bucket):
        cells.append((name, got == want, got, want, bucket))

    # ── 形（形态判据本体）─────────────────────────────────────────
    # ① 干净样例不误红（反向对照）
    p, probs = precedents_problems(doc_ok, agents_ok)
    cell("clean-doc-zero-problems", (p, probs), (True, []), "形")
    # ② 跳号必红
    doc_gap = doc_ok.replace("### 判例-33：配置这根线（2026-10-27 立）", "### 判例-34：配置这根线（2026-10-27 立）")
    _, probs = precedents_problems(doc_gap, "> **判例-32~34 已搬出**：x")
    cell("gap-33-reds", any("R1 判例-33 缺号" in x for x in probs), True, "形")
    # ③ 指针滞后必红（BUG-514 同族本体）
    _, probs = precedents_problems(doc_ok, "> **判例-32~31 已搬出**：x")
    cell("pointer-lag-reds", any("R2 指针句写「判例-32~31 已搬出」但判例库实测到 33" in x for x in probs), True, "形")
    # ④ 指针被删必红
    _, probs = precedents_problems(doc_ok, "没有任何指针句。")
    cell("pointer-missing-reds", any("找不到「判例-32~N 已搬出」指针句" in x for x in probs), True, "形")
    # ⑤ 日期戳缺失必红
    doc_nodate = doc_ok.replace("### 判例-33：配置这根线（2026-10-27 立）", "### 判例-33：配置这根线")
    _, probs = precedents_problems(doc_nodate, agents_ok)
    cell("missing-date-reds", any("R3 判例-33 标题缺日期戳" in x for x in probs), True, "形")
    # ⑥ 空库自拒
    p, _ = precedents_problems("# 没有判例\n", agents_ok)
    cell("empty-doc-self-reject", p, False, "形")
    # ── 双形（R213 本笔：形② 必须与形① 同进取数面）────────────────
    # ⑦ 双形连续 + 指针对表 ⇒ 不误红（反向对照：证明 `## 判例-N ·` 真被数进来了）
    p, probs = precedents_problems(doc_two_forms, agents_34)
    cell("dual-form-in-scope-clean", (p, probs), (True, []), "双形")
    # ⑧ 本笔缺陷本体合成化：库里最新两条是形②、指针仍写旧终点 ⇒ R2 必须红
    _, probs = precedents_problems(doc_two_forms, "> **判例-32~33 已搬出**：x")
    cell("dual-form-pointer-lag-reds",
         any("R2 指针句写「判例-32~33 已搬出」但判例库实测到 34" in x for x in probs), True, "双形")
    # ⑨ 形② 之间的跳号必进 R1（下一批人新增判例-46 时漏号就靠这一格）
    doc_dgap = doc_two_forms.replace(
        "## 判例-34 · 幻影提交号（2026-11-07 立 · BUG-578 追记现读抓出）",
        "## 判例-35 · 幻影提交号（2026-11-07 立 · BUG-578 追记现读抓出）")
    _, probs = precedents_problems(doc_dgap, "> **判例-32~35 已搬出**：x")
    cell("dual-form-gap-reds", any("R1 判例-34 缺号" in x for x in probs), True, "双形")
    # ⑩ 形② 的日期戳也归 R3 管
    doc_dnodate = doc_two_forms.replace(
        "## 判例-34 · 幻影提交号（2026-11-07 立 · BUG-578 追记现读抓出）",
        "## 判例-34 · 幻影提交号")
    _, probs = precedents_problems(doc_dnodate, agents_34)
    cell("dual-form-date-stamp-reds", any("R3 判例-34 标题缺日期戳" in x for x in probs), True, "双形")
    # ⑪ 重号（连续性只判跳号判不到这一档，R213 同批补上）
    doc_dup = doc_two_forms.replace("## 判例-34 · ", "## 判例-33 · ")
    _, probs = precedents_problems(doc_dup, agents_ok)
    cell("duplicate-number-reds", any("R1 判例-33 重号" in x for x in probs), True, "双形")
    # ⑫ 围栏内的伪抬头不算条目（判据③）：否则示例片段里的 `### 判例-99：` 会把最大编号顶到 99
    doc_fenced = (doc_ok + "\n```text\n### 判例-99：围栏里的伪抬头（2026-01-01 立）\n```\n\n正文。\n")
    p, probs = precedents_problems(doc_fenced, agents_ok)
    cell("fenced-pseudo-heading-ignored", (p, probs), (True, []), "双形")
    # ── 变异（打在真代码行上，判例-30）───────────────────────────
    anchor_hits, needle_hits, changed, mutant_max, clean_real = _mutation_narrow_heading_class(
        doc_two_forms, agents_34)
    cell("mutation-anchor-line-unique", anchor_hits, 1, "变异")
    cell("mutation-needle-unique", needle_hits, 1, "变异")
    cell("mutation-pattern-actually-changed", changed, True, "变异")
    cell("mutation-narrow-heading-class-reds", (mutant_max, clean_real), (32, True), "变异")
    # ── 旗标面（R207：拼错自检开关 = 静默失去自检）────────────────
    cell("misspelled-selftest-rejected", main(["--self-test"]), 2, "旗标")
    cell("unknown-flag-rejected", main(["--definitely-not-real"]), 2, "旗标")
    # 带值/附加旗标混在 `--selftest` 后面也必须拒（旧顺序：先分派自检 ⇒ 这一形静默跑全量自检报绿）
    cell("selftest-plus-unknown-flag-rejected", main(["--selftest", "--definitely-not-real"]), 2, "旗标")
    # ── 参数面 ───────────────────────────────────────────────────
    cell("positional-args-rejected", main(["some/path"]), 2, "旗标")

    bad = [c for c in cells if not c[1]]
    for name, ok, got, want, _b in bad:
        print("SELFTEST FAIL [%s] got=%r want=%r" % (name, got, want))
    order, tally = [], {}
    for _n, _o, _g, _w, b in cells:
        if b not in tally:
            order.append(b)
            tally[b] = 0
        tally[b] += 1
    face = " + ".join("%s %d" % (b, tally[b]) for b in order)
    print("SELFTEST %s（%d 格：%s，格数由格子清单算出、不手写计数；"
          "全部合成入参不读真仓，变异 4 格只读本尺自身源码的 RE_HEADING 真代码行）"
          % ("OK" if not bad else "FAIL", len(cells), face))
    return 1 if bad else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # BUG-369：尺子自己坏了走 4 号档，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
