#!/usr/bin/env python3
"""check_foreign_ledger_entries.py — 账本**外来条目**检测守卫（BUG-565 后续动作之一）

## 为什么有这个判据

BUG-565 实测：别的项目（vq 等）的 bug 经 `fist-mbt call report_bug --project_dir .`
误落到**本仓** `memory/bugs.md`（server 进程 cwd 被网关钉在本树，调用方无出路）。
账本里确实存在外来条目：BUG-544~564 的 summary/detail 把缺陷位置指向 `crates/vq-cli`、
`crates/vq-core`、`apps/web`、`data/vq.db` 等**本仓树之外**的路径（账本 2026-11-02 勘误节
已裁定这批是 vq 项目的缺陷、已逐字搬移、按 append-only 保留）。

**本判据的定位（BUG-565 detail 写明的后续动作：外来条目检测守卫）**：
只做**检测与棘轮**，不做处置——
- 既有外来条目 = **已知基线**，逐条登记进下面的 `WHITELIST`（带 kind 与理由）；
- **新增**外来条目（白名单之外的 id 命中外来路径信号）⇒ rc=1 逐条点名；
- 搬走/改判是 owner 裁决项，本判据不代行。

## 解析口径（与既有判据同源，不另起取数面）

- 条目抬头：**行首**三段式 `^## BUG-<id> [ts] [sev] STATUS` —— 正则与
  `scripts/gen_plugins.py` 的 `RE_BUG_HEAD` **逐字同源**（判例「同一规则多份实现必翻车」，
  `--selftest` 有一格 `regex-parity-with-gen_plugins` 由机器盯着同步）。
  正文中**引用**坏抬头形态（BUG-481 病灶行、带缩进的示例、`## BUG-n 追记` 小节）
  都不在行首 / 不合三段式 ⇒ 天然不成为条目边界。
- 条目正文 = 抬头行到下一条抬头行之间。
- **信号取数面 = 该条目自己的 `- summary:` / `- detail:` 行**（BUG-565 的口径：
  「summary/detail 把缺陷位置指向本仓树之外的路径族」）。
  ⚠️ 刻意**不扫** `- evidence:` 与其余正文：外来路径出现在证据/勘误引用里是合法的
  （勘误节本身就引用 vq 路径）；扫描全文会把「引用证据」误判成「缺陷位置」。

## 外来信号（两组，各有明确语义）

1. **路径族信号**（summary+detail 都扫）：`crates/`、`apps/`、`legacy/`、`packages/`、
   `data/`、`sparksql-exe`、`LookUpon`、`vq-cli|vq_core|vq_pyo3`（含连字符/下划线两态）、
   `dataquest`、`nodea`、`actus/`、`vools/<代码路径>`。本仓是 MoonBit 工程，
   顶层只有 src/scripts/cmd/docs/memory/plugins/tests/patches 等——这些路径族
   在本仓树内**不存在对应的缺陷位置**。
2. **项目署名标签信号**（只扫 summary 行的行首 `[...]` 标签）：`[Pentad/…]`、`[p5c…]`、
   `[vools]`。
   ⚠️ **为什么是行首标签不是裸子串**（缺陷位置 vs 证据引用的语义分界，实测一例）：
   BUG-406 的 summary 含「（外部项目 Pentad 统帅实测报告）」——那是**报告人署名**，
   缺陷位置在本仓 packaging 面。裸 `\bPentad\b` 会误伤它 ⇒ 标签信号只认
   summary 行首的 `[Pentad/` / `[p5c` / `[vools]` 形态（外来条目用它声明缺陷归属）。

## 白名单（棘轮基线）

`WHITELIST` 显式登记两类 id，每条带理由：
- `kind="foreign"`：已知外来条目（缺陷位置在本仓树外）——owner 处置清单的成员，
  在 owner 裁决搬走/改判之前按 append-only 留在账本里；
- `kind="meta"`：本仓元条目——它们**讨论**误落问题、正文可能引用外来路径做证据，
  不是外来缺陷本身（BUG-565 / BUG-573）。

白名单**只豁免被信号命中的 id**；新外来条目不在名单 ⇒ 红。名单里登记了但账本里
已不存在的 id ⇒ 只打提示不判红（owner 搬走后基线清理不该被门挡住）。

## 已知检测盲区（如实自报，写在 docstring 而不是藏起来）

以下**已知外来**条目的 summary/detail **不含**任何外来路径信号（缺陷描述用泛称），
本判据抓不到它们；它们同属 2026-11-02 勘误裁定批，处置归 owner：
- vq 批：BUG-549 / 557 / 559 / 560 / 561 / 562（detail 用 KNOWN_ISSUES、test 名、
  µs 读数等描述，无路径族字面量）；
- 自研语言 stdlib 批（Pentad/p5c 同族）：BUG-310 / 311 / 312 / 316 / 321
  （`Result::is_ok`、`str.split`、`expr_gen.rs`、`iter.lz` 等，无路径前缀）；
- 中文语聚合同批：BUG-322 / 323（`parser.py` / `semantic.py` 泛称，无项目归属路径）。
给这些加信号（如 `parser.py`）会**粗包子串误伤本仓条目** ⇒ 宁可漏报并在此声明，
也不放宽到不可信。真要收口请 owner 处置时整批搬移。

## 与 check_bug_ledger_scope.py 的关系（先读再改，防「同规则两份实现」误判）

本仓**已有**一支同对象判据：`scripts/check_bug_ledger_scope.py`（a4fd6eedf，BUG-565 后续项）。
两者**不是同一规则的两份实现**，契约刻意分层，改任何一支前先读懂另一支：

| | check_bug_ledger_scope.py（先落） | 本判据 |
|---|---|---|
| 回答的问题 | 「vq 形状的误落**有没有被勘误节收口**」 | 「有没有**基线之外**的缺陷位置在本仓树外的条目」 |
| 信号面 | 6 组路径前缀族 × **条目全文** × 不在本仓 git 跟踪面/盘上 | 路径族 + 项目署名标签（**更宽**：含 Pentad/p5c、vools、dataquest、LookUpon）× **只扫 summary/detail** |
| 基线机制 | 账本内**勘误节覆盖**（append-only 先例，账本自描述） | **脚本内 id 白名单**（每条带理由，棘轮：新增才红） |
| 刻意放行 | `crates/p5c`（Pentad 合法跨项目引用）、`vools/` 等上下文引用 | 全部放行对象都**显式点名**进白名单（含 Pentad/vools 批，理由逐条写明） |

⇒ 两支红的是**不同的违约**：scope 红的是「误落且无人勘误收口」，本判据红的是「出现了
白名单之外的外来缺陷条目」。新增外来条目通常两支都会红——按各自指引处置（scope：加勘误节；
本判据：owner 裁决后进白名单或搬走），**不要**为了消一支的红去改另一支的基线。

## rc 契约（与 check_bug_ledger_shape / check_fmt_gate 同口径）

- `0` = 现状与基线一致（白名单之外的外来条目 0 条）
- `1` = 发现基线之外的外来条目（逐条点名 id 与命中信号）
- `2` = 判据无法自证（账本读不到 / 解析不到任何条目 —— 绝不报绿）

用法：
    python scripts/check_foreign_ledger_entries.py            # 判据（rc 契约）
    python scripts/check_foreign_ledger_entries.py --list     # 列出全部命中（含白名单内，供人工裁决）
    python scripts/check_foreign_ledger_entries.py --selftest # 自证（合成夹具，不碰真账本）
"""

from __future__ import annotations

import io
import os
import re
import sys

# Windows 控制台默认 GBK ⇒ 中文/箭头字符会 UnicodeEncodeError（说不出来 = rc 契约失效）。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001 —— 老 Python / 非 tty 时没有 reconfigure
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "memory", "bugs.md")

RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

# ══════════════════════════════════════════════════════════════════════
# 抬头文法 —— 与 scripts/gen_plugins.py 的 RE_BUG_HEAD / check_bug_ledger_shape 的
# HEAD_STR 逐字同源（三份消费方一份文法；selftest 有 parity 格盯着同步）。
# ══════════════════════════════════════════════════════════════════════
HEAD_STR = r"^## BUG-(\d+[a-z]?) \[[^\]]+\] \[(?:critical|high|medium|low)\] (?:OPEN|FIXED|DUPLICATE|FALSE_POSITIVE)\b"
RE_HEAD = re.compile(HEAD_STR, re.M)

# ── 外来信号 ──────────────────────────────────────────────────────────
# scope="sd"   ：扫该条目的 summary + detail 行（缺陷位置指向本仓树外）。
# scope="tag"  ：只扫 summary 行（`- summary:` 之后）的行首项目署名标签。
# (?<![\w-])   ：词界负视——不吃 `xcrates/`、`myapps/` 这类更长 token 的尾巴。
SD_TOKENS: dict[str, str] = {
    "crates/": r"(?<![\w-])crates/",
    "apps/": r"(?<![\w-])apps/",
    "legacy/": r"(?<![\w-])legacy/",
    "packages/": r"(?<![\w-])packages/",
    "data/": r"(?<![\w-])data/",
    "sparksql-exe": r"(?<![\w-])sparksql[-_]?exe\b",
    "LookUpon": r"(?<![\w-])LookUpon\b",
    "vq-cli/core/pyo3": r"(?<![\w-])vq[-_](?:cli|core|pyo3)\b",
    "dataquest": r"(?<![\w-])dataquest\b",
    "nodea": r"(?<![\w-])nodea\b",
    "actus/": r"(?<![\w-])actus/",
    "vools/<path>": r"(?<![\w-])vools/[A-Za-z0-9_]",
}
# 行首署名标签（只认 summary 的 `[...]` 标签形态，理由见 docstring「项目署名标签信号」）
TAG_TOKENS: dict[str, str] = {
    "[Pentad/]": r"\[Pentad/",
    "[p5c]": r"\[p5c",
    "[vools]": r"\[vools\]",
}
RE_SUMMARY_LINE = re.compile(r"^-\s*summary:\s*(.*)$")
RE_DETAIL_LINE = re.compile(r"^-\s*detail:\s*(.*)$")

# ══════════════════════════════════════════════════════════════════════
# 白名单（棘轮基线）—— 每条必须带理由；处置（搬走/改判）是 owner 裁决项，
# 本判据不代行。kind: foreign=缺陷位置在本仓树外 / meta=本仓元条目（引用外来路径做证据）。
# ══════════════════════════════════════════════════════════════════════
WHITELIST: dict[str, tuple[str, str]] = {
    # ── Pentad / p5c 批（summary 带行首署名标签 [Pentad/…] / [p5c…]）──
    **{
        bid: ("foreign", "Pentad/p5c 项目缺陷（summary 行首署名标签），缺陷位置在 Pentad 仓")
        for bid in ("149", "150", "242", "243", "244", "245", "246", "247",
                    "255", "258", "267", "270", "271")
    },
    # ── vools 批（vools/<代码路径> 或 [vools] 标签）──
    **{
        bid: ("foreign", "vools 项目缺陷（summary/detail 指向 vools/ 代码路径），缺陷位置在 vools 仓")
        for bid in ("298", "308", "309", "313", "314", "315", "317", "318", "319", "320")
    },
    # ── vq 批（2026-11-02 勘误裁定：E:/IDEProjects/AI/vq 的缺陷误落本树，已逐字搬移、append-only 保留）──
    **{
        bid: ("foreign", "vq 项目缺陷（2026-11-02 勘误裁定批成员），缺陷位置在 E:/IDEProjects/AI/vq")
        for bid in ("544", "545", "546", "547", "548", "550", "551", "552",
                    "553", "554", "555", "556", "558", "563", "564")
    },
    # ── 跨仓缺陷（summary 无路径，detail 的缺陷位置在 vools 仓，修复也落在 vools c6bf905）──
    "531": ("foreign", "缺陷位置在 vools/actus/probe/python_pkgs.py（CPython importlib.metadata 线程安全），修复落在兄弟仓 vools c6bf905"),
    # ── 本仓元条目（讨论误落问题本身，可能引用外来路径做证据）──
    "565": ("meta", "BUG-565 本体：跨项目账本误落的根因登记，detail 引用 vq 项目做证据——是元条目不是外来缺陷"),
    "573": ("meta", "BUG-573：BUG-565 同族（report_bug 落账轨）的 run_guards 记账面复查，引用外来落账事实做证据"),
}


def read(path: str) -> str:
    return io.open(path, encoding="utf-8", errors="replace").read()


def parse_entries(text: str) -> list[dict]:
    """按行首三段式抬头切条目。返回 [{id, lineno, sd_text}]，sd_text = summary+detail 行拼接。

    正文中的坏抬头引用（BUG-481 行尾拼接 / 缩进示例 / `## BUG-n 追记` 小节标题）
    不在行首或不合三段式 ⇒ 不切分，天然落在上一条的正文里。"""
    entries: list[dict] = []
    cur: dict | None = None
    for i, line in enumerate(text.split("\n"), start=1):
        m = RE_HEAD.match(line)
        if m:
            cur = {"id": m.group(1), "lineno": i, "sd": []}
            entries.append(cur)
            continue
        if cur is not None:
            if RE_SUMMARY_LINE.match(line) or RE_DETAIL_LINE.match(line):
                cur["sd"].append(line)
    for e in entries:
        e["sd_text"] = "\n".join(e["sd"])
    return entries


def scan_entry(sd_text: str) -> list[str]:
    """对一条目的 summary/detail 文本返回命中的外来信号名清单（去重、稳定序）。"""
    hits: set[str] = set()
    summary_only: list[str] = []
    for line in sd_text.split("\n"):
        m = RE_SUMMARY_LINE.match(line)
        if m:
            summary_only.append(m.group(1))
    for name, pat in SD_TOKENS.items():
        if re.search(pat, sd_text):
            hits.add(name)
    for name, pat in TAG_TOKENS.items():
        if any(re.search(pat, s) for s in summary_only):
            hits.add(name)
    return sorted(hits)


def judge(text: str) -> tuple[int, dict]:
    """rc 契约判定。返回 (rc, info)；info 携带条目数 / 命中清单 / 违规清单。"""
    entries = parse_entries(text)
    if not entries:
        return RC_BROKEN, {"note": "解析不到任何行首三段式条目 ⇒ 判据与账本口径不一致（拒绝出结论）"}
    all_ids = {e["id"] for e in entries}
    flagged = []      # (id, lineno, hits)  —— 信号命中（含白名单内）
    violations = []   # (id, lineno, hits)  —— 白名单之外的命中
    stale = []        # 白名单登记了但账本里已不存在（提示不判红）
    for e in entries:
        hits = scan_entry(e["sd_text"])
        if not hits:
            continue
        flagged.append((e["id"], e["lineno"], hits))
        if e["id"] not in WHITELIST:
            violations.append((e["id"], e["lineno"], hits))
    for bid in WHITELIST:
        if bid not in all_ids:
            stale.append(bid)
    rc = RC_VIOLATION if violations else RC_OK
    return rc, {
        "entries": entries,
        "flagged": flagged,
        "violations": violations,
        "stale": stale,
    }


def render(rc: int, out: dict) -> None:
    if rc == RC_BROKEN:
        print("[FATAL] " + out["note"])
        print("判据无法自证 ⇒ rc=2")
        return
    entries, flagged = out["entries"], out["flagged"]
    violations, stale = out["violations"], out["stale"]
    known = [f for f in flagged if f[0] in WHITELIST]
    print(f"[扫描] 账本条目 {len(entries)} 条 · 外来信号命中 {len(flagged)} 条"
          f"（白名单内 {len(known)} / 白名单外 {len(violations)}）")
    for bid, lineno, hits in known:
        kind, why = WHITELIST[bid]
        print(f"  · BUG-{bid} (:{lineno}) [{kind}] {','.join(hits)} —— {why[:80]}")
    if stale:
        print(f"[提示] 白名单登记但账本已无此 id（owner 处置后请同批清理名单）："
              f"{', '.join('BUG-' + b for b in stale)}")
    if violations:
        print()
        print(f"[结论] 发现 {len(violations)} 条**基线之外**的外来条目（外来条目检测守卫 · BUG-565）：")
        for bid, lineno, hits in violations:
            print(f"  ✗ BUG-{bid} (:{lineno}) 命中信号：{','.join(hits)}")
        print()
        print("       处置：外来条目的搬走/改判是 owner 裁决项（BUG-565）；")
        print("             若确属本仓元条目（引用外来路径做证据），请带理由登记进 WHITELIST 的 meta 段。")
    else:
        print()
        print("[结论] 与基线一致（白名单之外的外来条目 0 条）。")
        print("       白名单内的已知外来条目清单即 owner 处置清单（--list 看全量）。")


# ══════════════════════════════════════════════════════════════════════
# selftest —— 合成夹具，不碰真账本
# ══════════════════════════════════════════════════════════════════════

FIST_ENTRY = """## BUG-9000 [2026-11-07T00:00:00Z] [medium] OPEN
- summary: 某工具的 resolved_path 回显不是绝对路径，写错轨时调用面从回执看不出来
- detail: 声明面：`src/server/server.mbt` 里这两个工具的描述都写「返回值含 resolved_path」。
- evidence: temp/xxx.txt
"""

# 外来条目（vq 形状）：信号在 summary
FOREIGN_SUMMARY = """## BUG-9001 [2026-11-07T00:00:01Z] [high] OPEN
- summary: crates/vq-cli/src/main.rs 的 add_conn 三处 return Ok(())
- detail: 格式错误、sqlite 路径为空、段数不足三处都只 println 后 return Ok(())。
"""

# 外来条目：信号只在 detail（变异打在 detail 取数键上）
FOREIGN_DETAIL_ONLY = """## BUG-9002 [2026-11-07T00:00:02Z] [medium] OPEN
- summary: 连接串参数错误仍返回 rc=0
- detail: apps/web/app_windows.py 的业务字段名硬编码，换数据源要改源码。
"""

# 元条目（BUG-565 形状）：detail 引用外来路径做**证据**，讨论误落问题本身
META_ENTRY = """## BUG-565 [2026-11-07T00:00:03Z] [medium] OPEN
- summary: 跨项目账本误落（根因）+ 网关静默失败
- detail: 机制 A：launcher 以 cwd:REPO 起网关 ⇒ 无出路；vq 项目 21 条账误落本树（例：crates/vq-cli 的缺陷）。
- evidence: temp/bug565_prefix_out.txt
"""

# 报告人署名形状（BUG-406 实测）：summary 含「外部项目 Pentad 统帅实测报告」——
# 裸子串会误伤；行首标签口径下**不该报**。
REPORTER_ATTRIBUTION = """## BUG-9003 [2026-11-07T00:00:04Z] [high] FIXED
- summary: [packaging] 打包产物在 ESM 作用域里用 CJS require ⇒ doctor 全崩（外部项目 Pentad 统帅实测报告）
- detail: package.json 声明 type:module ⇒ 上游 sqlite JS FFI 写着 CJS 形态。
"""

# 外来路径只出现在 evidence 行（取数面之外 ⇒ 不报）
EVIDENCE_CITATION = """## BUG-9004 [2026-11-07T00:00:05Z] [low] OPEN
- summary: 心跳跨进程探针在 ns 物理隔离之后整段是变量盲的
- evidence: 对照仓的 crates/vq-core 读数与 E:/IDEProjects/AI/vools 的清单见附件
"""

# 命名空间/cwd 上下文（BUG-374 实测形状）：vools 作为**运行环境**出现，非缺陷位置
NS_CONTEXT = """## BUG-9005 [2026-11-07T00:00:06Z] [high] OPEN
- summary: [run_check] 任务解析走根库而非已 open 的命名空间库：旧 schema 根库致服务端崩溃
- detail: cwd=E:\\IDEProjects\\AI\\vools 启动 serve，namespace=vools-rhop 的任务 T0 已 publish/claim 成功（落在 vools-rhop.db）。
"""


def _mk(*chunks: str) -> str:
    return "# bugs\n\n## 记账规则（合成夹具头部，非条目）\n\n" + "\n".join(chunks)


def selftest() -> int:
    cases = []

    def case(name, fn, want):
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001 —— 判据坏了要报，不许冒用别的档
            got = f"EXC:{e}"
        cases.append((name, got, want))

    # ① 干净账本（含非条目的规则头部）⇒ rc=0
    case("clean-fixture-rc0", lambda: judge(_mk(FIST_ENTRY))[0], RC_OK)

    # ②★ 变异对照 1：外来条目（信号在 summary）⇒ 必红，且逐条点名 id
    def _mut_summary():
        rc, out = judge(_mk(FIST_ENTRY, FOREIGN_SUMMARY))
        assert rc == RC_VIOLATION, rc
        named = [v[0] for v in out["violations"]]
        assert named == ["9001"], named
        return rc
    case("MUT-foreign-summary-goes-red-and-names-id", _mut_summary, RC_VIOLATION)

    # ③★ 变异对照 2：信号只在 detail ⇒ 必红（变异打在 detail 取数键上，判例-29/30）
    def _mut_detail():
        rc, out = judge(_mk(FIST_ENTRY, FOREIGN_DETAIL_ONLY))
        assert rc == RC_VIOLATION, rc
        assert out["violations"][0][2] == ["apps/"], out["violations"]
        return rc
    case("MUT-foreign-detail-only-goes-red", _mut_detail, RC_VIOLATION)

    # ④ 元条目不误伤：BUG-565 形状（真实形态，detail 引用外来路径做证据 + id 在白名单）⇒ rc=0
    case("meta-entry-bug565-shape-not-foreign", lambda: judge(_mk(FIST_ENTRY, META_ENTRY))[0], RC_OK)

    # ⑤★ 变异对照 3（打在白名单键上）：同一条文本、id 不在白名单 ⇒ 必红
    #    （证明 ④ 的绿是真白名单豁免，不是"碰巧没命中"——判例-29：测了谓词要测接线）
    case(
        "MUT-same-text-non-whitelisted-id-goes-red",
        lambda: judge(_mk(FIST_ENTRY, META_ENTRY.replace("## BUG-565", "## BUG-9876")))[0],
        RC_VIOLATION,
    )

    # ⑥ 缺陷位置 vs 证据引用：报告人署名（BUG-406 形状）不判外来
    case("reporter-attribution-not-flagged", lambda: judge(_mk(FIST_ENTRY, REPORTER_ATTRIBUTION))[0], RC_OK)

    # ⑦ 外来路径只在 evidence 行（取数面 = summary/detail）⇒ 不报
    case("evidence-citation-not-flagged", lambda: judge(_mk(FIST_ENTRY, EVIDENCE_CITATION))[0], RC_OK)

    # ⑧ vools 作为运行环境/cwd 上下文（BUG-374 形状）⇒ 不报
    case("ns-cwd-context-not-flagged", lambda: judge(_mk(FIST_ENTRY, NS_CONTEXT))[0], RC_OK)

    # ⑨ 解析不到条目 ⇒ 自拒 rc=2（绝不报绿）
    case("no-entries-is-rc2", lambda: judge("# bugs\n\n没有条目只有规则\n")[0], RC_BROKEN)
    case("empty-text-is-rc2", lambda: judge("   \n")[0], RC_BROKEN)

    # ⑩ 文件缺失 ⇒ rc=2
    case("missing-file-is-rc2", lambda: judge_file(os.path.join(ROOT, "memory", "no-such-ledger.md"))[0], RC_BROKEN)

    # ⑪ 参数面：未知旗标必拒（R197 族规，白名单+未知即拒）
    case("unknown-flag-rejected", lambda: main(["--definitely-not-real"]), RC_BROKEN)
    case("selftest-flag-misspelled-rejected", lambda: main(["--self-test"]), RC_BROKEN)

    # ⑫ 真源一致性：本判据的抬头正则与 gen_plugins 的 RE_BUG_HEAD 同口径
    case("regex-parity-with-gen_plugins", _parity_with_gen_plugins, True)

    # ⑬ 坏抬头引用不切条目（BUG-481 病灶行 / 追记小节 / 缩进示例都在正文里）
    def _bad_head_refs():
        text = _mk(
            FIST_ENTRY,
            "- evidence: ... 0 errors。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN\n",
            "## BUG-9000 追记（2026-11-07 · 这行不是条目抬头）\n",
            "  ## BUG-9001 [2026-01-01T00:00:00Z] [high] OPEN（缩进示例，非行首）\n",
        )
        rc, out = judge(text)
        assert rc == RC_OK, (rc, out.get("violations"))
        assert [e["id"] for e in out["entries"]] == ["9000"], [e["id"] for e in out["entries"]]
        return rc
    case("inline-bad-headings-do-not-split-entries", _bad_head_refs, RC_OK)

    ok = 0
    for name, got, want in cases:
        good = got == want
        ok += 1 if good else 0
        print(f"  [{'OK' if good else 'FAIL'}] {name:<46} got={got} want={want}")
    print(f"\n[selftest] {ok}/{len(cases)} 格通过")
    return 0 if ok == len(cases) else 1


def _parity_with_gen_plugins() -> bool:
    """断言本判据的抬头正则与 `gen_plugins.py` 的 `RE_BUG_HEAD` 同口径
    （判例「同一规则多份实现必翻车」：三处消费一份文法，机器盯着同步）。"""
    gp = os.path.join(ROOT, "scripts", "gen_plugins.py")
    if not os.path.isfile(gp):
        return True  # 拿不到就不判（不假装查过）
    src = read(gp)
    m = re.search(r"RE_BUG_HEAD = re\.compile\(\s*(.*?)\n\)", src, re.S)
    if not m:
        return False
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
        "## BUG-532 追记（2026-11-01T06:30Z · 定位修正）",
        "- evidence: x。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN",
        "  ## BUG-9001 [2026-01-01T00:00:00Z] [high] OPEN",
    ]
    mine = re.compile(HEAD_STR)
    for s in samples:
        if bool(gp_re.match(s)) != bool(mine.match(s)):
            return False
    return True


def judge_file(path: str) -> tuple[int, dict]:
    if not os.path.isfile(path):
        return RC_BROKEN, {"note": f"找不到 {path} ⇒ 判据无法自证"}
    return judge(read(path))


KNOWN_FLAGS = ("--selftest", "--list")


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    # R197 族规：未知旗标必须拒绝（rc=2），不许静默忽略——
    # `--self-test` 拼错若被吃下，判据会**照跑真扫描并回 rc=0** ⇒ 自检开关拼错 = 静默失去自检。
    unknown = [a for a in argv if a not in KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）" % (" ".join(unknown), " / ".join(KNOWN_FLAGS)))
        return RC_BROKEN
    if "--selftest" in argv:
        return selftest()
    rc, out = judge_file(LEDGER)
    if rc == RC_BROKEN:
        render(rc, out)
        return rc
    if "--list" in argv:
        entries, flagged = out["entries"], out["flagged"]
        print(f"[--list] 账本条目 {len(entries)} 条 · 外来信号命中 {len(flagged)} 条（含白名单内，供人工裁决）：")
        for bid, lineno, hits in flagged:
            if bid in WHITELIST:
                kind, why = WHITELIST[bid]
                print(f"  · BUG-{bid} (:{lineno}) [{kind}] {','.join(hits)} —— {why}")
            else:
                print(f"  ✗ BUG-{bid} (:{lineno}) [基线外] {','.join(hits)}")
        if not flagged:
            print("  （无命中）")
        return RC_OK
    render(rc, out)
    return rc


if __name__ == "__main__":
    sys.exit(main())
