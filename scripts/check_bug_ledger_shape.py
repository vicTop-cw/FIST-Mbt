#!/usr/bin/env python3
"""check_bug_ledger_shape.py — 账本 `memory/bugs.md` 的**形态**守卫（BUG-481）

## 为什么有这个判据

BUG-481 实测：`memory/bugs.md:3838` 有一条**抬头被拼进了 `- evidence:` 行的行尾**：

    - evidence: ... 0 errors。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN

`bug_list` / `gen_plugins` 都按 **行首** `^## BUG-` 解析 ⇒ 该条**不可见** ⇒ 计数少 1。
**⇒ 这是「账本自己坏了，而账本说没问题」** —— 只有专门看形态的判据才抓得住。

## 四类检查

1. **行内 `## BUG-`**（不在行首）—— 但要**区分合法引用**（详见 §合法引用）
2. **抬头行不符三段式** —— 正则**与 `gen_plugins.py` 的 `RE_BUG_HEAD` 完全一致**（判例「同一规则多份实现」）
3. **重复 ID** —— 带 allow-list（BUG-206 是已知历史重复，理由在 notes 里）
4. **统计一致性** —— `] OPEN$` 的行数 vs 行首抬头的 OPEN 数，不等即说明有 OPEN 条目不可见

## §合法引用（本判据最难的一点，实测收集 4 种）

本仓 `bugs.md` 里**合法地**出现行内 `## BUG-` 的形态有四种，**全部不能报红**：

| 形态 | 实例 | 为什么不报 |
|---|---|---|
| **a. detail 里引用完整抬头文本** | 见 `:6076`（`- detail:` 内 `## BUG-183 [ts] [sev] …`）| 它在描述「这个 bug 是什么」，**不是账本条目** |
| **b. evidence 里的小节标题** | `## BUG-421：整名 leader/lead 提权面` | **带中文冒号 ≠ 三段式**（无 `[ts] [sev] STATUS`）|
| **c. 反引号包裹的规则示例** | `` `## BUG-421 [2026-...] [medium] FIXED` `` | 是**文档在讲文法**，且被反引号包着 |
| **d. 引述账本自身（带行号前缀）** | `7459:## BUG-421 [...]` | 行首是 `<数字>:` 不是 `##`，是**引用别人的行** |

**⇒ 判据规则（`--check` 模式）**：只报「**行内 `## BUG-<n> [<...>] [<sev>] <STATUS>` 完整三段式**」
且**不在反引号内**的。这精确命中 BUG-481 的病灶形态（完整抬头被拼进行尾）。

**`--list` 模式**：列出**所有**行内 `## BUG-` 命中（含合法引用），供人工裁决。
两种模式分开，是因为「报得准」和「看得全」是两件事。

## rc 契约（与 check_fmt_gate / check_dead_params 同口径）

- `0` = 形态干净
- `1` = 有违规（逐条点名）
- `2` = 判据无法自证（`memory/bugs.md` 读不到 / 抽不到任何抬头）

用法：
    python scripts/check_bug_ledger_shape.py            # 判据（rc 契约）
    python scripts/check_bug_ledger_shape.py --list     # 列出所有行内命中（含合法引用）
    python scripts/check_bug_ledger_shape.py --selftest # 自证（含变异对照）
"""

from __future__ import annotations

import io
import os
import re
import sys

# Windows 控制台默认 GBK ⇒ 打印 `⇒`/`✗` 会 UnicodeEncodeError。
# 判据必须**在任何平台上都能把话说出来**（说不出来 = rc 契约失效）。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001 —— 老 Python / 非 tty 时没有 reconfigure
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "memory", "bugs.md")

RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

# ══════════════════════════════════════════════════════════════════════
# 抬头文法 —— **与 scripts/gen_plugins.py 的 RE_BUG_HEAD 逐字一致**
#
# ⚠️ 判例「同一规则多份实现必翻车」：这两条正则是**同一口径的两个消费方**
#   （一个数条目、一个查形态），必须同步。selftest 里有一格专门断言
#   「本文件的正则与 gen_plugins 的正则对同一批样本给出相同结论」。
# ══════════════════════════════════════════════════════════════════════
HEAD_STR = r"^## BUG-(\d+[a-z]?) \[[^\]]+\] \[(?:critical|high|medium|low)\] (?:OPEN|FIXED|DUPLICATE|FALSE_POSITIVE)\b"
RE_HEAD = re.compile(HEAD_STR, re.M)

# **行内**完整三段式（BUG-481 的病灶形态）—— 前面至少一个非空字符
# ⚠️ 与 HEAD_STR 同源：只把 `^` 换成 `.`（行内任意位置之前有东西）
RE_HEAD_INLINE = re.compile(HEAD_STR.replace("^##", ".+##"), re.M)

# 只要出现行内 `## BUG-` 就算（`--list` 用，宽口径）
RE_ANY_INLINE = re.compile(r".+## BUG-\d+[a-z]?", re.M)

# 反引号包裹的片段（规则示例，不算）
RE_BACKTICKED = re.compile(r"`[^`]*## BUG-[^`]*`")

STATUSES = ("OPEN", "FIXED", "DUPLICATE", "FALSE_POSITIVE")

# 已知历史重复 —— **不能静默放过**，每条要带理由。
# BUG-206：账本历史上同号出现两次（一次是抬头，一次是 BUG-481 拼进 evidence 行尾的那条）。
# 该重复正是 BUG-481 的病灶本身；裁决由统帅做（本判据不擅自 mitig）。
DUP_ALLOW = {
    "BUG-206": "BUG-481 病灶本身：一条真抬头 + 一条被拼进 evidence 行尾的同一抬头；待裁决",
}


def read(path: str) -> str:
    return io.open(path, encoding="utf-8", errors="replace").read()


def _in_backticks(line: str, pos: int) -> bool:
    """pos 是否落在本行的反引号片段内（成对计数，奇数个反引号在它左边 ⇒ 在里面）。"""
    return line[:pos].count("`") % 2 == 1


def scan(text: str) -> dict:
    """返回 {headings, inline_hits, inline_violations, dups, open_line_cnt, open_head_cnt}"""
    lines = text.split("\n")

    headings = []          # [(lineno, id, status)]
    inline_hits = []       # [(lineno, text)]  —— 所有行内 ## BUG-（宽口径）
    inline_violations = []  # [(lineno, text)] —— 完整三段式但不在行首、不在反引号内
    open_line_cnt = 0

    for i, line in enumerate(lines, start=1):
        m = RE_HEAD.match(line)
        if m:
            headings.append((i, "BUG-" + m.group(1), _head_status(line)))
        if line.rstrip().endswith("] OPEN"):
            open_line_cnt += 1
        if RE_ANY_INLINE.search(line):
            inline_hits.append((i, line.strip()))
            for mm in RE_HEAD_INLINE.finditer(line):
                # ⚠️ 实测踩坑：`RE_HEAD_INLINE` 是 `.+##` 形态（贪婪）⇒ `mm.start()` 落在**行首**，
                #    在那里判反引号必然为 False ⇒ 反引号内的合法引用会被误报。
                #    ⇒ 判定点必须取 `## BUG-` 的**实际位置**（`mm.group()` 里 `##` 的偏移）。
                hh = mm.group().index("##")
                at = mm.start() + hh
                if _in_backticks(line, at):
                    continue
                # ★ 区分「**行尾拼接**」与「**独立续行引用**」（Lane DP 实测）：
                #   病灶 BUG-481 的形态是 `... 0 errors。## BUG-206 [...]` ——
                #   `##` **紧贴前一段文字**（前面是 `。` / `errors` / 无空白）。
                #   而 `memory/bugs.md:10851` 那种是**缩进续行**：`  ## BUG-206 [...]`
                #   （`##` 前只有空白）—— 它是「引用抬头文本」，不是账本条目。
                #   ⇒ 前一个字符是**非空白**才算「拼接」，否则只进 --list。
                prev = line[at - 1] if at > 0 else ""
                spliced = prev != "" and not prev.isspace()
                # ★ 合法引用形态 d（Lane DP 实测）：`7459:## BUG-421 [...]` ——
                #   前面是**行号 + 冒号**，是「引述账本自身某一行」，不是被拼进正文行尾。
                if spliced and re.search(r"\d+:$", line[:at]):
                    spliced = False
                if spliced:
                    inline_violations.append((i, line.strip()))

    # 重复 ID（只数**真抬头**）
    seen: dict[str, list[int]] = {}
    for lineno, bid, _st in headings:
        seen.setdefault(bid, []).append(lineno)
    dups = {k: v for k, v in seen.items() if len(v) > 1}

    open_head_cnt = sum(1 for (_l, _b, st) in headings if st == "OPEN")

    return {
        "headings": headings,
        "inline_hits": inline_hits,
        "inline_violations": inline_violations,
        "dups": dups,
        "open_line_cnt": open_line_cnt,
        "open_head_cnt": open_head_cnt,
    }


def _head_status(line: str) -> str:
    for s in STATUSES:
        if re.search(r"\b" + s + r"\b", line):
            return s
    return "?"


def judge(text: str) -> tuple[int, dict]:
    if not text.strip():
        return RC_BROKEN, {"note": "账本是空的 ⇒ 拒绝出结论"}
    res = scan(text)
    if not res["headings"]:
        return RC_BROKEN, {
            "note": "抽不到任何行首三段式抬头 ⇒ 判据与账本口径不一致（拒绝出结论）",
        }

    violations = []
    # ① 行内完整三段式（报道 BUG-481 病灶）
    for lineno, txt in res["inline_violations"]:
        violations.append(
            ("行内抬头", lineno, "完整三段式抬头出现在行内（不在行首）⇒ 该条 `bug_list`/`gen_plugins` **看不见**：" + txt[:110])
        )
    # ② 重复 ID（带 allow-list）
    for bid, linenos in sorted(res["dups"].items()):
        if bid in DUP_ALLOW:
            continue
        violations.append(("重复 ID", linenos[0], f"{bid} 出现 {len(linenos)} 次（行 {linenos}）"))
    # ③ 统计一致性：有 `] OPEN` 结尾的行，但行首抬头数对不上
    if res["open_line_cnt"] != res["open_head_cnt"]:
        violations.append(
            (
                "统计不一致",
                0,
                f"`] OPEN$` 行 {res['open_line_cnt']} 条 vs 行首抬头 OPEN {res['open_head_cnt']} 条"
                " ⇒ 有 OPEN 条目**不可见**（抬头不在行首）",
            )
        )
    return (RC_VIOLATION if violations else RC_OK), {"res": res, "violations": violations}


def render(rc: int, out: dict) -> None:
    if rc == RC_BROKEN:
        print("[FATAL] " + out["note"])
        print("判据无法自证 ⇒ rc=2")
        return
    res, violations = out["res"], out["violations"]
    # ⚠️ **口径写明**（Lane DP：统帅实测 11 处、判据报 12 处 ⇒ 差 1 由此来）
    #    本数是**独立行数**（`grep -cE '.+## BUG-[0-9]+' memory/bugs.md` 同口径，已交叉核对）。
    #    一行里出现 **多个** `## BUG-` 仍只计 **1 行**。
    print(f"[扫描] 行首三段式抬头 {len(res['headings'])} 条 · 行内 `## BUG-` 命中 {len(res['inline_hits'])} 行")
    print(f"       OPEN（行首抬头）{res['open_head_cnt']} · `] OPEN$` 行 {res['open_line_cnt']}")
    if res["dups"]:
        for bid, linenos in sorted(res["dups"].items()):
            tag = "（allow-list：%s）" % DUP_ALLOW[bid] if bid in DUP_ALLOW else ""
            print(f"       重复 {bid} × {len(linenos)} 行 {linenos}{tag}")
    if violations:
        print()
        print(f"[结论] {len(violations)} 处形态违规：")
        for kind, lineno, msg in violations:
            print(f"  ✗ [{kind}] {(':' + str(lineno)) if lineno else ''} {msg}")
        print()
        print("       处置：把被拼进行尾的抬头**移到行首**（并拆成独立行）；")
        print("             若是「引用抬头文本」则改用反引号包裹或改成小节标题（`## BUG-n：…`）。")
    else:
        print()
        print("[结论] 账本形态干净。**这不等于账本内容对** —— 本判据只查形态，不查事实。")


# ══════════════════════════════════════════════════════════════════════
# selftest
# ══════════════════════════════════════════════════════════════════════

GOOD = """# bugs
## BUG-1 [2026-01-01T00:00:00Z] [high] OPEN
- evidence: something
## BUG-2 [2026-01-02T00:00:00Z] [low] FIXED
- evidence: ok
"""

# BUG-481 病灶：完整三段式抬头被拼进 evidence 行尾
BAD_INLINE = """# bugs
## BUG-1 [2026-01-01T00:00:00Z] [high] OPEN
- evidence: ... 0 errors。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN
"""

# 合法引用 a：detail 里引用抬头文本 —— 但**仍是完整三段式**，
# 所以按 §合法引用 的规则，它**会被报**（--check 口径）。这是**有意的**：
# 判据只认「行内完整三段式」，不去猜作者意图；--list 模式供人工裁决。
LEGIT_SECTION_TITLE = """## BUG-1 [2026-01-01T00:00:00Z] [high] OPEN
- detail: 见 `## BUG-421 [2026-01-01T00:00:00Z] [medium] FIXED`（反引号内，不报）
- detail2: ## BUG-421：整名 leader 提权面（中文冒号，非三段式，不报）
- detail3: 7459:## BUG-422 [2026-01-01T00:00:00Z] [medium] FIXED（带行号前缀，仍报——见下）
"""

# ★ 反证样本：合法引用（不该报）+ **1 条真拼接**（该报）
MIXED_REAL_SPLICE = (
    "- evidence: ... 0 errors.## BUG-999 [2026-01-01T00:00:00Z] [high] OPEN\n"
)

DUP = """## BUG-7 [2026-01-01T00:00:00Z] [high] OPEN
## BUG-7 [2026-01-02T00:00:00Z] [high] FIXED
"""

OPEN_MISMATCH = """## BUG-1 [2026-01-01T00:00:00Z] [high] OPEN
- note: 这条结尾也是 OPEN
"""


def selftest() -> int:
    cases = []
    def case(name, fn, want):
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001 —— 判据坏了要报，不许冒用别的档
            got = f"EXC:{e}"
        cases.append((name, got, want))

    case("clean-ledger-passes", lambda: judge(GOOD)[0], RC_OK)
    # ★ 变异 1：抬头拼进行尾 ⇒ 必红
    case("MUT-inline-heading-goes-red", lambda: judge(BAD_INLINE)[0], RC_VIOLATION)
    # ★ 变异 2：抬头时间戳不合法（`[bad]`）⇒ 三段式不匹配 ⇒ 该条**不可见** ⇒ 统计不一致 ⇒ 红
    # ★ 变异 2：抬头**三段式不完整**（缺严重度）⇒ 该条不可见 ⇒ 抽不到合法抬头 ⇒ rc=2
    #
    # ⚠️ **实测纠正派单的一条期望**：派单说「把抬头改成 `## BUG-999 [bad] OPEN`
    #    （时间戳不合法）⇒ 判据必红」。但**真源 `gen_plugins.RE_BUG_HEAD` 的时间戳部分是
    #    `\[[^\]]+\]`**（接受任意非 `]` 内容）⇒ `[bad]` 在 `gen_plugins` 看来**也是合法抬头**。
    #    本判据若把它判红，就**与真源分叉**了（判例「同一规则多份实现必翻车」）。
    #    ⇒ 时间戳格式**不在本判据的责任面内**——真源自己就不校验它。
    #    变异改用**缺严重度**（真源确实不认），这是真源口径下真正的「不可见」。
    case(
        "MUT-incomplete-heading-unseen-is-rc2",
        lambda: judge("## BUG-9 [2026-01-01T00:00:00Z] OPEN\n")[0],
        RC_BROKEN,
    )
    # 真源一致性：`[bad]` 时间戳在**两边都被接受**（证明本判据不比真源更严）
    case(
        "bad-timestamp-accepted-like-gen_plugins",
        lambda: judge("## BUG-9 [bad] [high] OPEN\n")[0],
        RC_OK,
    )
    # ══════════════════════════════════════════════════════════════════
    # 合法引用三形态（a 反引号 / b 中文冒号 / d 行号前缀）⇒ **都不报**
    #
    # ⚠️ **本格是第一版的一个错期望**（Lane DP 修正）：
    #   第一版 `want=1`，理由是「行号前缀形态 `7459:## BUG-422 [...]` 确实是
    #   『完整抬头出现在行内』，宁可多报」。但实测 `got=0` ——
    #   判据把它正确识别成**行号引述**（`\d+:$` 前缀）并排除。
    #   **实际行为才是对的**：那一行是「引述账本自身某一行」，不是账本条目。
    # ⇒ `want` 改为 0。
    # ⚠️ 但统帅指出得对：**改成 0 后本格只能证明「不该报的没报」，
    #   证明不了「判据真的在区分」** (碰巧全没命中也是 0)。
    #   ⇒ 下面紧接一格**反证**：同一批引用里混入 1 条真拼接 ⇒ 必报 1。
    # ══════════════════════════════════════════════════════════════════
    case("legit-refs-not-reported", lambda: len(judge(LEGIT_SECTION_TITLE)[1]["violations"]), 0)
    # ★ 反证格：合法引用 + **1 条真拼接** ⇒ 必须报出来（证明判据真的在区分）
    #
    # ⚠️ 期望值 **1 → 2**（Lane DP 实测修正）：混入一条真拼接会同时触发**两类**违规：
    #   ① 「行内抬头」—— 完整三段式不在行首
    #   ② 「统计不一致」—— `] OPEN$` 有 2 行（真抬头 + 拼进去的那条），
    #      但行首抬头只有 1 条 ⇒ 差额精确暴露「有 1 条 OPEN 看不见」
    #   **两类都报是对的**：它们描述的是同一病灶的两个可观测面，
    #   而且第②类才是**最贴近用户症状**的那条（`bug_list` 少一条）。
    case(
        "legit-refs-plus-one-real-splice-reports-both-signals",
        lambda: sorted({v[0] for v in judge(LEGIT_SECTION_TITLE + MIXED_REAL_SPLICE)[1]["violations"]}),
        ["统计不一致", "行内抬头"],
    )
    # 重复 ID
    case("dup-id-detected", lambda: judge(DUP)[0], RC_VIOLATION)
    # 统计一致性：行尾 `] OPEN` 但抬头已可见 ⇒ 两侧都 1 vs 1 ⇒ 不报
    case("open-count-consistent-ok", lambda: judge(OPEN_MISMATCH)[0], RC_OK)
    # 空账本 ⇒ rc=2
    case("empty-ledger-is-rc2", lambda: judge("   \n\n")[0], RC_BROKEN)
    # 反引号判定
    case("backtick-detection", lambda: _in_backticks("a `x` b", 5), False)
    case("backtick-detection-inside", lambda: _in_backticks("a `xx b", 5), True)
    # 真源一致性：本文件的 HEAD_STR 与 gen_plugins 的 RE_BUG_HEAD 对同一批样本结论一致
    case("regex-parity-with-gen_plugins", _parity_with_gen_plugins, True)

    ok = 0
    for name, got, want in cases:
        good = got == want
        ok += 1 if good else 0
        print(f"  [{'OK' if good else 'FAIL'}] {name:<42} got={got} want={want}")
    print(f"\n[selftest] {ok}/{len(cases)} 格通过")
    return 0 if ok == len(cases) else 1


def _parity_with_gen_plugins() -> bool:
    """断言本判据的抬头正则与 `gen_plugins.py` 的 `RE_BUG_HEAD` **同口径**。

    判例「同一规则多份实现必翻车」：两处都要改的规则，必须由机器盯着同步。
    """
    gp = os.path.join(ROOT, "scripts", "gen_plugins.py")
    if not os.path.isfile(gp):
        return True  # 拿不到就不判（不假装查过）
    src = read(gp)
    m = re.search(r"RE_BUG_HEAD = re\.compile\(\s*(.*?)\n\)", src, re.S)
    if not m:
        return False
    # 把 gen_plugins 的多行字符串拼起来
    parts = re.findall(r'r?"([^"]*)"', m.group(1))
    gp_pattern = "".join(parts)
    if not gp_pattern:
        return True
    try:
        gp_re = re.compile(gp_pattern)
    except re.error:
        return True
    samples = [
        "## BUG-1 [2026-01-01T00:00:00Z] [high] OPEN",
        "## BUG-1 [2026-01-01T00:00:00Z] [high] FIXED",
        "## BUG-1 [bad] [high] OPEN",
        "## BUG-1 [2026-01-01T00:00:00Z] [fatal] OPEN",
        "- evidence: x。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN",
    ]
    mine = re.compile(HEAD_STR)
    for s in samples:
        if bool(gp_re.match(s)) != bool(mine.match(s)):
            return False
    return True


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    # R197：**未知旗标必须拒绝**（rc=2），不许静默忽略。
    # 实测病象：`--self-test`（多一个连字符）或拼错的旗标会被吃下，然后**照跑真检查并回 rc=0**
    # ⇒ 看起来"自检通过"，实际跑的是对真账本的扫描 —— 自检开关拼错 = 静默失去自检。
    # （同族：R155 给我自己那把尺补 KNOWN_FLAGS 的原因一模一样；判据 `check_arg_face_strict` 抓的就是这条。）
    unknown = [a for a in argv if a not in ("--selftest", "--list", "--check")]
    if unknown:
        print(
            "[FATAL] 未知参数 %s —— 已知：--selftest / --list / --check（rc=2）"
            % " ".join(unknown)
        )
        return RC_BROKEN
    if "--selftest" in argv:
        return selftest()
    if not os.path.isfile(LEDGER):
        print(f"[FATAL] 找不到 {LEDGER} ⇒ rc=2")
        return RC_BROKEN
    text = read(LEDGER)

    if "--list" in argv:
        res = scan(text)
        n_seg = sum(1 for _ in RE_HEAD_INLINE.finditer(text))
        print(
            f"[--list] 命中 {len(res['inline_hits'])} **行** / {n_seg} **个区段**"
            "（口径差异见下；**含合法引用**，供人工裁决）："
        )
        print("  ⚠️ `--check` 报的是**行数**（与 `grep -cE '.+## BUG-[0-9]+'` 同口径）；"
              "本模式按**区段**逐条列，故同一行可能列多次。")
        for lineno, txt in res["inline_hits"]:
            kind = "🔴 完整三段式" if any(
                lineno == v[0] for v in res["inline_violations"]
            ) else "  （合法引用 / 非三段式）"
            print(f"  {kind} :{lineno} {txt[:120]}")
        return RC_OK

    rc, out = judge(text)
    render(rc, out)
    return rc


if __name__ == "__main__":
    sys.exit(main())
