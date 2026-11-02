#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_doc_dup.py — 文档「同名登记块」重复尺 + 机械修复（R48 立，R136 硬化）。

**为什么需要它**：`scripts/README.md` 在多次 `slave/` 合并后会整段回退成旧快照——
2026-10-22 实测同一份索引里同一段说明被反复拼进来，`run_guards.py` 曾同时挂 4 条自述互不相同的条目；
R136 重建当天实测：1144 行 / 247KB 里 **341 个登记块中 232 块是重复（528 行 / 66,168 字节）**，
`fist_gate.py` 名下并存 11 块说明；旧尺对同一文件回「无重复长条目」rc=0。靠人工偶尔清理治不住，必须有一把尺每轮盯着。

判据（不猜、纯文本；R136 起按**块**判，不按行判）：
- 登记块 = 行首 `- ` + 反引号脚本名（可多枚：`- `a.py` / `b.py` —` 或 `- `a.py` + `b.md` —`），
  紧跟 `—` 或 `（`；**续行（缩进两格）属于同一块**，块到第一个非缩进行或空行为止。
- **不再有长度门槛**：R48 的 `len > 150` 让「短条目重复」整类从尺子底下漏过去（实测：
  重建前 38 个重名名字下 263 块里 254 块首行 ≤150 字——旧尺对同一文件照报「无重复」）。
- 散文引子 `- `check_plugin_sync.py` 的索引缺口补齐登记（…）：` 不是登记块——
  反引号名后面不是 `—`/`（` 的直接形态，按内容跳过（R48 记过的假阳形状，不许回潮）。
- 表格行、`**` 段落、`##` 标题都不参与判定（合法的表头/说明不该被当重复）。
- 同一脚本名被 **> 1 个块**登记 ⇒ 计为重复；rc：0 = 干净；1 = 有重复或断头孤行（逐条点名行号）；
  2 = 扫描面为空（没有文件、或所有文件里一个登记块都没有——判据无法自证）。

**D2 断头孤行检测（BUG-539，2026-11-02 立）**：合并机器人把条目**抬头行**整行吃掉后，残留的
后续行成为无头孤行——它既不构成重复块（D1 判定面要求「带抬头完整条目 ≥2 份」），也不触发自拒
⇒ 脏面在绿灯位静默存活（实证：scripts/README 曾有 6 条 `ist-mbt-js-v0.3.4.zip` 落在 R1… 孤行，
清理前后本尺同 rc=0；残留由 commit 9b1e3fafd 手工修掉）。D2 判定面（纯文本形状，不做内容判断）：
- 形状A（**缩进外孤行**）：顶格非空行，非条目头、非覆盖正文、非合法结构行
  （标题 `#` / 表格 `|` / 围栏 ` ``` ` / 引用 `>` / 加粗段 `**` / 列表项 `- * +` / 编号项 `N.`），
  且**上方最近非空行是条目块行**（头或其覆盖正文），向下越过未覆盖内容（孤行自己的续行 /
  连续孤行）后**能到达条目块行**——两头钉在条目列表 fabric 里 ⇒ 违例。
- 形状B（**断头续行**）：缩进非空行不在覆盖面内，且其上方最近非空行**不存在或是标题行**
  ——缩进正文失去了唯一可能的宿主（条目头或散文锚点都没有）⇒ 违例（含链式传播：已判孤行
  之下连续的缩进行一并点名）。
- 形状C（**断头码 span 残段**）：顶格非空行（非头/覆盖/合法结构行），本行反引号数为**奇数**
  （行内有一段 code span 没闭合），且**紧邻上一非空行**反引号成对（偶数——没有跨行开 span
  能认领这个闭引号）⇒ 闭引号的开头在被吃掉的那一行里 ⇒ 违例。合法的跨行懒续行是
  「奇承奇」（上一行行尾开着 span，实证 README 末行），不落进这一格。
- 刻意不判（fail-open，防误伤实证形状）：覆盖面内的缩进正文（含被吃头后并入前一条目的残段
  ——形状上与合法长正文不可区分，留给人工）；EOF 单侧懒续行（实证 712 行形状）；bullet /
  编号锚定的缩进散文（实证 226/421-425 行形状）；条目之间的合法列表项（实证 85 行形状）；
  撞上合法结构行（标题/表格等）边界的单侧可疑行；三行及以上的跨行 code span（中段为
  偶数反引号顶格行时，末行会被形状C 误点名——现状面零实证，出现即人工复核）。孤行
  **不自动修**（`--fix` 只做机械去重，删孤行属内容裁决），但孤儿在场时 rc=1 不放行。

`--fix` 做机械去重：每个名字保留**最长**那块（同长取靠前者——更可能含较新读数），
**整块删除**其余（含续行；R48 只删首行会把续行留成孤儿，2026-10-22 实测出现过
「条目头被吃掉、只剩半句」的残骸）。表格/短行/散文一律不动；修完自检残留重复，
残留 ≠ 0 时打印告警（多名字块与单名字块交叉时才会发生，需人工裁决）。

用法：
  python scripts/check_doc_dup.py                       # 默认扫 scripts/README.md
  python scripts/check_doc_dup.py --paths scripts/README.md,AGENTS.md
  python scripts/check_doc_dup.py --fix
  python scripts/check_doc_dup.py --selftest
退出码：0 = 干净 / 1 = 有重复或断头孤行 / 2 = 判据无法自证 / 4 = 尺子自己坏了（未捕获异常）。
"""
import argparse
import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# `- `a.py` — …` / `- `a.py`（…` / `- `a.py` / `b.py` — …` / `- `a.py` + `b.md` — …`
HEAD_RE = re.compile(r"^- (`[^`]+`(?:\s*[/+]\s*`[^`]+`)*)\s*(?:—|（)")
NAME_RE = re.compile(r"`([^`]+)`")
# 合法结构行（D2 不判）：标题 / 表格 / 围栏 / 引用 / 加粗段 / 列表项 / 编号项
STRUCT_LEGAL_RE = re.compile(r"^(?:#{1,6}\s|\||```|>|\*\*|[-*+]\s|\d+[.、)])")


def parse_blocks(lines):
    """返回 [{start, end, names, text, bytes}]；start/end 是 0-based 半开区间。"""
    blocks, i = [], 0
    while i < len(lines):
        m = HEAD_RE.match(lines[i])
        if not m:
            i += 1
            continue
        names = NAME_RE.findall(m.group(1))
        j = i + 1
        while j < len(lines) and lines[j].strip() and lines[j][:1] in (" ", "\t"):
            j += 1
        text = "\n".join(lines[i:j])
        blocks.append({"start": i, "end": j, "names": names,
                       "text": text, "bytes": len(text.encode("utf-8"))})
        i = j
    return blocks


def scan_text(text):
    """返回 (lines, blocks, dups)。dups = [(name, 块数, [行号…], 浪费字节)]，按浪费降序。"""
    lines = text.splitlines()
    blocks = parse_blocks(lines)
    by_name = {}
    for b in blocks:
        for n in b["names"]:
            by_name.setdefault(n, []).append(b)
    dups = []
    for name, group in by_name.items():
        if len(group) < 2:
            continue
        waste = sum(b["bytes"] for b in group) - max(b["bytes"] for b in group)
        dups.append((name, len(group), [b["start"] + 1 for b in group], waste))
    dups.sort(key=lambda d: (-d[3], d[0]))
    return lines, blocks, dups


def scan_orphans(lines, blocks):
    """D2（BUG-539）断头孤行/断头续行。返回 [(行号(1-based), 行文本)]，按文件顺序。

    文法口径见模块 docstring「D2 断头孤行检测」。纯文本形状判定：
    覆盖面 = 条目头 + 其连续缩进正文（与 parse_blocks 同一口径）。
    """
    covered = [False] * len(lines)
    for b in blocks:
        for k in range(b["start"], b["end"]):
            covered[k] = True
    nbs = [k for k, ln in enumerate(lines) if ln.strip()]
    at = {k: i for i, k in enumerate(nbs)}

    def nb(k, step):
        i = at[k] + step
        return nbs[i] if 0 <= i < len(nbs) else None

    flagged, out = set(), []
    for k, ln in enumerate(lines):
        if not ln.strip() or covered[k]:
            continue
        if ln[:1] in (" ", "\t"):
            # 形状B：缩进正文失去宿主（上方最近非空行不存在/是标题/是已判孤行）
            p = nb(k, -1)
            if p is None or p in flagged or lines[p][:1] == "#":
                flagged.add(k)
                out.append((k + 1, ln))
            continue
        if STRUCT_LEGAL_RE.match(ln):
            continue
        # 形状A：顶格可疑行。上方必须钉在条目块行上；向下越过未覆盖内容
        # （孤行自己的缩进续行 / 连续孤行）后必须到达条目块行，撞上合法结构
        # 行或 EOF 即不判（fail-open）。
        p = nb(k, -1)
        if p is not None and p in flagged:
            flagged.add(k)
            out.append((k + 1, ln))
            continue
        # 形状C：断头码 span 残段——本行反引号奇数（行内有一段 span 没闭合），
        # 而紧邻上一非空行反引号成对（没有跨行开 span 能认领这个闭引号）
        # ⇒ 闭引号的开头在被吃掉的那一行里。实证：7 条 wild 孤行里 5 条落在
        # 散文 bullet 之后，形状A 的覆盖面三明治够不着它们；合法的跨行懒续行
        # 是「奇承奇」（实证 712 行，上一行行尾开着 code span），不落进这一格。
        if (k > 0 and lines[k - 1].strip() and ln.count("`") % 2 == 1
                and lines[k - 1].count("`") % 2 == 0):
            flagged.add(k)
            out.append((k + 1, ln))
            continue
        if p is None or not covered[p]:
            continue
        n = nb(k, +1)
        while n is not None:
            if covered[n]:
                break
            if STRUCT_LEGAL_RE.match(lines[n]):
                n = None
                break
            n = nb(n, +1)
        if n is not None and covered[n]:
            flagged.add(k)
            out.append((k + 1, ln))
    return out


def fix_text(text):
    """每名保留最长块（同长取靠前者），整块删除其余。返回 (新文本, 删除行数, 残留重复数)。"""
    lines, blocks, dups = scan_text(text)
    if not dups:
        return text, 0, 0
    by_name = {}
    for b in blocks:
        for n in b["names"]:
            by_name.setdefault(n, []).append(b)
    keep = set()
    for name, group in by_name.items():
        if len(group) < 2:
            continue
        best = max(group, key=lambda b: (b["bytes"], -b["start"]))
        keep.add(best["start"])
    drop = {}
    for b in blocks:
        if b["start"] in keep:
            continue
        # 只删「名下每条都另有保留块」的块：多名字块的某个名字若只在这里登记过，
        # 删掉就是静默丢登记（宁可留残留重复交给人工，也不替人做丢数据的决定）。
        if all(len(by_name[n]) > 1 for n in b["names"]):
            drop[b["start"]] = b
    out, dropped, i = [], 0, 0
    while i < len(lines):
        b = drop.get(i)
        if b is not None:
            dropped += b["end"] - b["start"]
            i = b["end"]
            continue
        out.append(lines[i])
        i += 1
    new_text = "\n".join(out) + ("\n" if text.endswith("\n") or out else "")
    residual = len(scan_text(new_text)[2])
    return new_text, dropped, residual


def selftest():
    _entry_probe()
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    clean = "- `a.py` — 短条目\n- `b.py` — 另一条\n| t | u |\n| --- | --- |\n"
    _, blocks, dups = scan_text(clean)
    cell("clean-no-dup", len(dups), 0)
    cell("clean-block-count", len(blocks), 2)

    short_dup = "- `a.py` — 短\n- `a.py` — 也短\n"
    _, _, dups = scan_text(short_dup)
    cell("short-dup-detected", len(dups), 1)
    cell("short-dup-count", dups[0][1], 2)

    multi = "- `a.py` — 头\n  续行一\n  续行二\n- `b.py` — 另一条\n"
    _, blocks, dups = scan_text(multi)
    cell("continuations-one-block", len(blocks), 2)
    cell("continuation-span", blocks[0]["end"] - blocks[0]["start"], 3)
    cell("continuations-no-dup", len(dups), 0)

    dup_block = "- `a.py` — 旧头\n  旧续行\n- `a.py` — 新头\n  新续行\n"
    _, _, dups = scan_text(dup_block)
    cell("block-dup-detected", len(dups), 1)
    cell("block-dup-count", dups[0][1], 2)
    cell("block-dup-waste-positive", dups[0][3] > 0, True)

    cell("prose-bullet-not-entry",
         len(scan_text("- `a.py` 的索引缺口补齐登记（历史欠账）：说明\n")[1]), 0)
    cell("table-row-not-entry", len(scan_text("| `a.py` | — |\n")[1]), 0)

    multi_name = "- `a.py` / `b.py` — 共用\n- `b.py` — 单独\n"
    _, _, dups = scan_text(multi_name)
    cell("multi-name-registers-both", [d[0] for d in dups], ["b.py"])

    fixed, dropped, residual = fix_text(dup_block)
    cell("fix-dropped-lines", dropped, 2)
    cell("fix-keeps-one-head", fixed.count("- `a.py` —"), 1)
    cell("fix-drops-continuation", fixed.count("  新续行"), 0)
    cell("fix-residual-zero", residual, 0)

    longer = "- `a.py` — 短\n- `a.py` — " + "长" * 80 + "\n"
    cell("fix-keeps-longest", fix_text(longer)[0].count("长" * 80), 1)

    fixed_table = fix_text(dup_block + "| x | y |\n")[0]
    cell("fix-keeps-table", fixed_table.count("| x | y |"), 1)
    cell("fix-idempotent", len(scan_text(fixed)[2]), 0)

    shared = "- `a.py` / `c.py` — 共用\n- `a.py` — " + "长" * 40 + "\n"
    cell("fix-keeps-unique-multi-name", "c.py" in fix_text(shared)[0], True)

    # ---- D2 断头孤行（BUG-539）----
    orphan_fx = "- `a.py` — 头\nist-mbt 孤行尾巴落在 R1\n- `b.py` — 另一条\n"
    _, oblocks, odups = scan_text(orphan_fx)
    # 实证形状：D1（重复门）对孤行盲——同款清理前后同 rc=0 的根因
    cell("orphan-dup-blind", len(odups), 0)
    # 变异对照（必红面）：合成孤行夹具必须被点名
    cell("orphan-column0-detected", [n for n, _ in scan_orphans(orphan_fx.splitlines(), oblocks)], [2])
    # 变异对照（必绿面）：修复后（缩进进块 / 删除）必须不红
    fixed_ind = "- `a.py` — 头\n  ist-mbt 孤行尾巴落在 R1\n- `b.py` — 另一条\n"
    _, fb, _ = scan_text(fixed_ind)
    cell("orphan-fixed-by-indent", scan_orphans(fixed_ind.splitlines(), fb), [])
    fixed_rm = "- `a.py` — 头\n- `b.py` — 另一条\n"
    _, rb, _ = scan_text(fixed_rm)
    cell("orphan-fixed-by-removal", scan_orphans(fixed_rm.splitlines(), rb), [])
    # 孤行带自己的缩进续行：整段一起点名
    orphan_run = "- `a.py` — 头\n孤行尾巴\n  孤行续行\n- `b.py` — 另一条\n"
    _, ob2, _ = scan_text(orphan_run)
    cell("orphan-run-detected",
         [n for n, _ in scan_orphans(orphan_run.splitlines(), ob2)], [2, 3])
    # 合法结构行不误伤（标题/表格/引用/编号/bullet/加粗段夹在条目之间）
    legal_fx = ("- `a.py` — 头\n\n## 小节\n\n| t | u |\n| --- | --- |\n"
                "> 引用行\n1. 编号项\n- 普通 bullet\n**加粗段落**\n- `b.py` — 另一条\n")
    _, lb, _ = scan_text(legal_fx)
    cell("orphan-legal-structure-pass", scan_orphans(legal_fx.splitlines(), lb), [])
    # EOF 单侧懒续行不误伤（实证：真 README 末行，顶格续上文）
    lazy_fx = "- `a.py` — 头：正文…\n懒继续行（顶格）\n"
    _, zlb, _ = scan_text(lazy_fx)
    cell("orphan-eof-lazy-cont-pass", scan_orphans(lazy_fx.splitlines(), zlb), [])
    # 形状B：缩进断头续行（宿主被吃后前面只剩标题）+ 链式传播
    ind_fx = "## 小节\n  断头续行A\n  断头续行B\n- `b.py` — 头\n"
    _, ib, _ = scan_text(ind_fx)
    cell("orphan-indented-beheaded-detected",
         [n for n, _ in scan_orphans(ind_fx.splitlines(), ib)], [2, 3])
    # 形状B 变异对照（必绿面）：宿主恢复后必绿
    ind_ok = "- `a.py` — 头\n  断头续行A\n  断头续行B\n- `b.py` — 头\n"
    _, iob, _ = scan_text(ind_ok)
    cell("orphan-indented-host-restored-pass", scan_orphans(ind_ok.splitlines(), iob), [])
    # 形状B 反向对照（不误伤）：bullet 锚定的缩进散文（实证 226/421-425 行形状）
    prose_anchor = "- whisperer.py — 巡检自动化（TASK-009）：步骤…\n  issue 扫描）；旗标 --scan-only。\n"
    _, pab, _ = scan_text(prose_anchor)
    cell("orphan-indented-prose-anchor-pass", scan_orphans(prose_anchor.splitlines(), pab), [])
    # 形状C：断头码 span 残段（实证：wild 孤行 5/7 落在散文 bullet 之后，覆盖面三明治够不着）
    span_fx = "- `check_x.py` 的索引缺口补齐登记（历史欠账）：\n" + \
              "ist-mbt-js-v0.3.4.zip` 落在 R1 与 J4 之间，照抄离线线就 404\n- `b.py` — 另一条\n"
    _, sb, _ = scan_text(span_fx)
    cell("orphan-span-fragment-after-bullet-detected",
         [n for n, _ in scan_orphans(span_fx.splitlines(), sb)], [2])
    # 形状C 变异对照（必绿面）：跨行懒续行「奇承奇」（实证 712 行形状）不误伤
    lazy_span = "- `a.py` — 回执 `malformed JSON-RPC response: '[fist-mbt] auth_mode = off\n" + \
                "'` ⇒ 整个 server 不可用，而测试全绿。\n"
    _, lsb, _ = scan_text(lazy_span)
    cell("orphan-span-lazy-cont-pass", scan_orphans(lazy_span.splitlines(), lsb), [])

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK: %d 格（短条目/整块/散文排除/多名字/--fix 整块删与幂等/"
          "D2 断头孤行双向对照，全部真断言）"
          % len(cells))
    return 0



def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    为什么要有这一格：R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。自检只考纯函数、
    不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：只验证入口存在且可调用，
    不起服务、不碰网络、不跑真桥。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", "--self-test", dest="selftest", action="store_true")
    ap.add_argument("--paths", default="scripts/README.md")
    ap.add_argument("--fix", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    paths = [p.strip() for p in args.paths.split(",") if p.strip()]
    total_dups, total_dropped, scanned, blocks_seen = 0, 0, 0, 0
    total_orphans = 0
    for rel in paths:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            print("  跳过（不存在）：%s" % rel)
            continue
        scanned += 1
        with io.open(p, encoding="utf-8-sig", errors="replace") as f:
            text = f.read()
        lines, blocks, dups = scan_text(text)
        blocks_seen += len(blocks)
        if dups:
            total_dups += sum(n - 1 for _, n, _, _ in dups)
            print("  %s：%d 行，登记块 %d，重复名字 %d 个（冗余 %d 块 / 浪费 %d 字节）"
                  % (rel, len(lines), len(blocks), len(dups),
                     sum(n - 1 for _, n, _, _ in dups), sum(w for _, _, _, w in dups)))
            for name, n, wl, waste in dups[:8]:
                print("    %-34s x%-2d 行号 %s…  浪费 %d 字节" % (name[:34], n, wl[:6], waste))
        else:
            print("  %s：%d 行，登记块 %d，无重复登记" % (rel, len(lines), len(blocks)))
        orphans = scan_orphans(lines, blocks)
        if args.fix and dups:
            new_text, dropped, residual = fix_text(text)
            with io.open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(new_text)
            total_dropped += dropped
            print("    --fix：整块删除 %d 行（每名保留最长块）" % dropped)
            if residual:
                print("    ⚠ --fix 后仍有 %d 个名字重复（多名字块交叉，需人工裁决）" % residual)
            # 修后重算（行号按修后文件），孤儿不自动修但要如实重报
            lines, blocks = scan_text(new_text)[:2]
            orphans = scan_orphans(lines, blocks)
        if orphans:
            total_orphans += len(orphans)
            print("  %s：%d 行断头孤行/断头续行（BUG-539 D2：条目文法外且不隶属任何条目块）"
                  % (rel, len(orphans)))
            for ln_no, txt in orphans[:8]:
                print("    行 %d：%s" % (ln_no, txt.strip()[:60]))
            if len(orphans) > 8:
                print("    …其余 %d 行省略" % (len(orphans) - 8))
    if scanned == 0 or blocks_seen == 0:
        print("FATAL 扫描面为空 —— 判据无法自证，拒绝出结论")
        return 2
    if args.fix:
        print("\n修复完成：共删除 %d 行（请复跑本尺复核）" % total_dropped)
        if total_orphans:
            print("⚠ --fix 只做机械去重，不删孤行（内容裁决）——仍有 %d 行断头孤行需人工处置"
                  % total_orphans)
            return 1
        return 0
    verdict = 0
    if total_dups:
        print("\n⚠ 共 %d 块冗余登记：合并流程会把旧快照整段拼回来（2026-10-22 实测半小时内回涨）。"
              % total_dups)
        print("  处置：`python scripts/check_doc_dup.py --fix` 机械去重后复跑。")
        verdict = 1
    if total_orphans:
        print("\n⚠ 共 %d 行断头孤行（BUG-539 D2）：条目抬头行被合并吃掉后的残留，"
              "既不构成重复块也无人认领。" % total_orphans)
        print("  处置：人工核对后并入宿主条目（缩进进块）或删除；--fix 不代做这一步。")
        verdict = 1
    return verdict


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了走 4 号档，不冒用 1
        sys.stderr.write("FATAL(4): 尺子自己坏了：%r\n" % (e,))
        sys.exit(4)
