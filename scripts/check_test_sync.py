#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_test_sync.py — 测试总数单一真源一致守卫（CI JS 轨）。

唯一真源 = moon test 的实测通过总数（从测试日志或直接参数传入）。

**BUG-50 收口：判据从「白名单存在性」升级为「全量一致性」**
旧版只核对"实测数出现在指定 4 份文档里"，这个形状天然测不到
"第 5 份文档写着别的数"（docs/agent-map.md 曾写着 316 而实测 406 却长绿）。
现在双向判：
  R1 反向扫**全部现状面文档**，凡"测试总数声明"（窄口径，见下）必须 == 实测数，
     否则红；合法的历史数/别的 target 必须在 EXEMPT 表里逐条点名（file, 数, 理由）。
  R2 正向要求 must-carry 文档必须携带实测数（防止有人把声明整段删掉来"消解"违例）。
  R3 防空转：扫描面里必须至少命中 1 条与实测数一致的声明，否则判红
     （文档改写法把正则饿死 = 判据失效，不是"没问题"）。

窄口径（宁少不误，避免把引文/年份/编号当声明）：
  A) 等值对 N/N（`/`、`／`、`╱` 三种分隔符）且同行出现测试语义关键词
  B) `N 项|个|条 [测试|用例] 全绿|通过|passed`
  C) `total=N`
  D) 日志回显 `Total tests: N, passed: N`（两个数各算一条声明，缺一即红）
不等值对（如 105/104、1986/1997、22/30）一律**不算**声明。

历史记录豁免（按路径类别，不逐条点名）：`memory/`、`reports/`、`CHANGELOG.md`、
`docs/superpowers/plans/`，以及文件名以 `YYYY-MM-DD` 开头的文件 —— 这些是按日期
追加的既成记录，改写它们等于伪造历史。

用法：
  python scripts/check_test_sync.py <moon_test_log>          # 从日志提取 "Total tests: N, passed: N"
  python scripts/check_test_sync.py --total 439              # 直接给总数
  python scripts/check_test_sync.py --selftest               # 违例对照：证明本判据会红（含"自洽的谎"型）

任一违例即 FAIL（退出码非 0）。R1 的豁免表条目若已失效（不再命中任何声明）同样 FAIL。
"""
import re
import sys
from pathlib import Path

# BUG-58：守卫的“红”必须是判据红。Windows 默认 GBK 控制台下，中文结论里的 ↔ 等字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# R2 必须携带实测数的文档（口径来源：本轮实测它们确实携带，不是许愿清单）
MUST_CARRY = [
    "README.md",
    "AGENTS.md",
    "docs/deliverable.md",
    "docs/agent-map.md",
    "scripts/scoring_rubric.md",
]

# R1 豁免表：(相对路径用 / 分隔, 被豁免的数字, 理由)。条目失效即红。
EXEMPT = [
    ("README.md", "317", "native 轨上一轮实测，本轮未复跑（见该句原文与「已知边界」）"),
    ("AGENTS.md", "317", "同上：native 轨旧数，作者已声明不据旧数宣称双端同版全绿"),
    ("docs/deliverable.md", "233", "R43 交付行的当轮实测数（交付清单逐行是各轮记录）"),
    ("docs/polish-plan.md", "148", "标题自述「初稿」的规划快照，描述的是当时的底子"),
    ("docs/features/F008-evolve.md", "148", "已勾 `- [x] AC-2` 是该特性轮的验收记录，非现状断言"),
    ("README_EN.md", "317", "native 轨旧数（该句已同时声明本轮未复跑，不许读成双端同版全绿）"),
    ("BACKLOG.md", "295", "done 行的 R107 当轮实测数（待办队列的历史列，不是现状断言）"),
]

# 历史记录类别：整路径豁免（按日期追加，改写即伪造历史）
HISTORY_DIR_PREFIXES = ("memory/", "reports/", "docs/superpowers/plans/")
HISTORY_FILES = ("CHANGELOG.md",)
HISTORY_DATED_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}")

SEP = r"[/／╱]"
RX_PAIR = re.compile(rf"(?<!\d)(\d{{2,5}})\s*{SEP}\s*(\d{{2,5}})(?!\d)")
RX_ITEMS = re.compile(
    r"(?<!\d)(\d{2,5})\s*(?:项|个|条)?\s*(?:测试|用例|测试项)?\s*(?:全绿|已通过|全部通过|通过|passed)",
    re.I,
)
RX_TOTAL = re.compile(r"total\s*=\s*(\d{2,5})", re.I)
# D) 日志回显形状 `Total tests: N, passed: N`（README 的自检示例行就是这个形状；
#    只认 A~C 会漏掉它，本轮实测靠 check_badge 才抓到 ⇒ 补进同一判据口径）
RX_LOG = re.compile(r"Total tests:?\s*(\d{2,5})\s*[,,]\s*passed:?\s*(\d{2,5})", re.I)
RX_KEY = re.compile(r"(测试|用例|全绿|passed|test)", re.I)


def is_history(rel: str) -> bool:
    """按日期追加的历史记录面：不参与一致性判定。"""
    if rel in HISTORY_FILES:
        return True
    if rel.replace("\\", "/").startswith(HISTORY_DIR_PREFIXES):
        return True
    return bool(HISTORY_DATED_NAME.match(Path(rel).name))


def current_docs():
    """现状面文档集合（实测：README/AGENTS/USAGE/SKILL/规范 + docs/** + scripts/*.md
    + templates/*.md + plugins/**，全部 .md）。"""
    out = []
    for top in ("README.md", "README_EN.md", "AGENTS.md", "USAGE.md", "BACKLOG.md",
                "FIST-SKILL.md", "AI-DEVELOPMENT-STANDARD.md"):
        out.append(top)
    for sub in ("docs", "scripts", "templates", "plugins"):
        d = ROOT / sub
        if not d.is_dir():
            continue
        pattern = "**/*.md" if sub in ("docs", "plugins") else "*.md"
        for p in d.glob(pattern):
            if p.is_file():
                out.append(str(p.relative_to(ROOT)).replace("\\", "/"))
    return sorted(set(out))


def collect_claims(text: str):
    """从一份文档正文里抽出"测试总数声明"（窄口径）。返回 [(数字, 形状, 行号)]。"""
    hits = []
    for ln, line in enumerate(text.splitlines(), 1):
        if not RX_KEY.search(line):
            continue
        for m in RX_PAIR.finditer(line):
            if m.group(1) == m.group(2):
                hits.append((m.group(1), "N/N", ln))
        for m in RX_ITEMS.finditer(line):
            hits.append((m.group(1), "N 全绿/通过", ln))
        for m in RX_TOTAL.finditer(line):
            hits.append((m.group(1), "total=N", ln))
        for m in RX_LOG.finditer(line):
            hits.append((m.group(1), "日志回显 tests", ln))
            hits.append((m.group(2), "日志回显 passed", ln))
    return hits


def judge(total: str, docs: dict, sweep: list, must_carry: list, exempt: list):
    """纯判定：docs = {相对路径: 正文}。返回 (问题列表, 命中数, 使用掉的豁免条目集合)。"""
    problems = []
    used = set()
    agree = 0
    for rel in sweep:
        text = docs.get(rel)
        if text is None or is_history(rel):
            continue
        for num, shape, ln in collect_claims(text):
            if num == total:
                agree += 1
                continue
            hit = [i for i, (f, n, _) in enumerate(exempt) if f == rel and n == num]
            if hit:
                used.update(hit)
                continue
            problems.append(
                f"R1 {rel}:{ln} 声明测试总数 {num}（{shape}）≠ 实测 {total}"
                f"；要么改文档，要么在 EXEMPT 里点名理由"
            )
    for rel in must_carry:
        text = docs.get(rel)
        if text is None:
            problems.append(f"R2 必须携带实测数的文档不存在：{rel}")
            continue
        nums = {n for n, _, _ in collect_claims(text)}
        if total not in nums:
            problems.append(f"R2 {rel} 未出现实测总数 {total} 的声明")
    if agree == 0:
        problems.append(
            f"R3 防空转：现状面里没有任何一条声明等于实测 {total}"
            "（正则饿死或文档改写≠没有问题）"
        )
    for i, (f, n, why) in enumerate(exempt):
        if i not in used:
            problems.append(f"R4 豁免条目已失效（{f} 里不再有 {n} 的声明）：{why}")
    return problems, agree, used


def run(total: str) -> int:
    sweep = current_docs()
    docs = {}
    for rel in sweep:
        p = ROOT / rel
        if p.is_file():
            docs[rel] = p.read_text(encoding="utf-8", errors="replace")
    problems, agree, _ = judge(total, docs, sweep, MUST_CARRY, EXEMPT)
    live = [r for r in sweep if not is_history(r)]
    if problems:
        print(f"FAIL 测试总数一致性守卫（实测 {total}，扫描 {len(live)} 份现状文档，"
              f"{agree} 条声明一致）：")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"PASS 测试总数单一真源一致：实测 {total}；扫描现状面 {len(live)} 份文档，"
          f"{agree} 条声明全部等于实测；must-carry {len(MUST_CARRY)} 份齐全；"
          f"豁免 {len(EXEMPT)} 条全部有效")
    return 0


# ---------------------------------------------------------------- selftest
# 判据必须先证明它会红。每个变体指名"必须出现哪一条问题"，只要求 rc≠0 会被
# "被别的检查顺手拦住"的假通过骗过。
def _pair(n):
    return f"全量 `moon test --target js` = {n}/{n}"


def selftest() -> int:
    total = "439"
    base = {
        "README.md": _pair(total) + "\n> Native 后端上一轮测试 " + _pair("317") + "，本轮未复跑",
        "AGENTS.md": _pair(total) + "\n> Native 后端上一轮 " + _pair("317"),
        "docs/deliverable.md": f"测试 **{total} 项全绿**\n| 43 测试数单一真源 | 当轮实测（233/233 全绿）|",
        "docs/agent-map.md": f"**{total} 项全绿**",
        "scripts/scoring_rubric.md": f"（{total} 全绿）",
        "docs/polish-plan.md": "已 148 全绿却 continue-on-error",
        "docs/features/F008-evolve.md": "- [x] AC-2: `moon test --target js` 全量 148/148 无回归",
        # 豁免表条目必须在夹具里各有一条声明——否则 R4 会判"豁免失效"（这是设计，不是噪声）
        "README_EN.md": "native track last verified with 317/317 tests green, not re-run",
        "BACKLOG.md": "done(R107 那轮 295/295 全绿)",
        "docs/other.md": "无关文字：测试 105/104 是引文，1986/1997 是年份",
        "memory/2026-09-26.md": "当日记录写 406/406（历史面豁免）",
        "reports/2026-09-26-x.md": "报告写 406/406（历史面豁免）",
    }
    sweeps = sorted(base) + ["CHANGELOG.md", "docs/superpowers/plans/2026-09-24-p.md",
                             "docs/echo.md"]
    base["CHANGELOG.md"] = "v0.2.5 时 406/406"
    base["docs/superpowers/plans/2026-09-24-p.md"] = "当时仍 148/148"
    # 日志回显形状（D）：README 的自检示例行，本轮实测只有 check_badge 抓到 ⇒ 纳入同一口径
    base["docs/echo.md"] = "moon test --target js  # → Total tests: %s, passed: %s, failed: 0" % (
        total, total)
    done = [0]

    def run_case(name, docs, want=None, want_none=None, exempt=None):
        ex = exempt if exempt is not None else EXEMPT
        probs, agree, _ = judge(total, docs, sweeps, MUST_CARRY, ex)
        if want is None and want_none is None:
            if probs:
                print(f"SELFTEST FAIL [{name}] 期望全绿实际 {probs}")
                return None, None
            done[0] += 1
            print(f"  ok  {name}")
            return agree, probs
        if want is not None and not any(want in p for p in probs):
            print(f"SELFTEST FAIL [{name}] 期望命中 «{want}» 实际 {probs or '无违例'}")
            return None, None
        if want_none is not None and any(want_none in p for p in probs):
            print(f"SELFTEST FAIL [{name}] 不该命中 «{want_none}» 实际 {probs}")
            return None, None
        done[0] += 1
        print(f"  ok  {name}")
        return agree, probs

    print("SELFTEST 违例对照（每条要求命中自己指名的问题，基准那份必须 rc=0）")
    # 1) 基准：现状面全一致 + 豁免有效 + 历史面不参与
    agree, probs = run_case("baseline-clean", dict(base))
    if agree is None:
        print("SELFTEST FAIL 基准夹具本身不绿，后面的对照无意义")
        return 2
    if agree < len(MUST_CARRY):
        print(f"SELFTEST FAIL 基准命中数 {agree} < must-carry 份数 {len(MUST_CARRY)}（正则没吃到声明）")
        return 2
    # 2) 第 5 份文档写旧数（BUG-50 的原始形状）→ 必须红
    d = dict(base)
    d["docs/agent-map.md"] = "**316 项全绿**（旧数）"
    if run_case("R1 stale-in-5th-doc", d, want="R1 docs/agent-map.md") is None:
        return 1
    # 3) must-carry 文档删掉声明 → 不能靠"不提"来消解违例
    d = dict(base)
    d["README.md"] = "这里没有测试数，只有 native 旧数 317/317"
    if run_case("R2 must-carry-removed", d, want="R2 README.md") is None:
        return 1
    # 4) 整面改写把正则饿死 → 防空转必须红
    d = {k: "本文件不含任何数字声明（改写法）" for k in base}
    if run_case("R3 anti-noop", d, want="R3") is None:
        return 1
    # 5) 豁免条目失效（文档里的旧数被改掉了，表还留着）→ 必须红
    d = dict(base)
    d["docs/polish-plan.md"] = "初稿快照已更新为 " + _pair(total)
    if run_case("R4 stale-exemption", d, want="R4 豁免条目已失效") is None:
        return 1
    # 6) 假阳性对照：不等值对（引文/年份/编号）不得被当声明
    d = dict(base)
    d["docs/other.md"] = "工具 105/104 漂移、1986/1997 论文、BUG-22/30 编号、测试相关文字"
    if run_case("no-false-positive-on-quotes", d, want=None) is None:
        return 1
    # 7)「自洽的谎」型：把实测数整批改写成另一个数并同步扩豁免表 ——
    #    只有"must-carry 里出现非实测且未点名的声明"这一层能抓住，验证它真的会红
    d = dict(base)
    d["README.md"] = _pair("500") + "\n317/317"
    d["AGENTS.md"] = _pair("500")
    d["docs/deliverable.md"] = "**500 项全绿**"
    d["docs/agent-map.md"] = "**500 项全绿**"
    d["scripts/scoring_rubric.md"] = "（500 全绿）"
    lie = EXEMPT + [("docs/deliverable.md", "500", "谎：自称历史数")]
    if run_case("self-consistent-lie", d, want="R2 README.md", exempt=lie) is None:
        return 1
    # 8) 日志回显形状（D）里的旧数必须被抓（本轮 README 自检行就是靠这条补进来的口径红的）
    d = dict(base)
    d["docs/echo.md"] = "moon test --target js  # → Total tests: 400, passed: 400, failed: 0"
    if run_case("D-log-echo-shape", d, want="R1 docs/echo.md") is None:
        return 1
    print(f"SELFTEST PASS {done[0]} 个变体各自命中自己指名的判据（计数由 run_case 实测累加，非手写）")
    return 0


def main():
    args = sys.argv[1:]
    if args == ["--selftest"]:
        return selftest()
    total = None
    if args and args[0] == "--total" and len(args) >= 2:
        total = int(args[1])
    elif args:
        log = Path(args[0]).read_text(encoding="utf-8", errors="replace")
        m = re.search(r"Total tests:?\s*(\d+)\s*,\s*passed:\s*\d+", log)
        m2 = re.search(r"total=(\d+) passed=(\d+)", log)
        if m:
            total = int(m.group(1))
        elif m2:
            total = int(m2.group(1))
    if total is None:
        print("FAIL 无法从参数/日志解析测试总数")
        return 1
    return run(str(total))


if __name__ == "__main__":
    sys.exit(main())
