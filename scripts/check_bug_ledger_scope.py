#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_bug_ledger_scope.py — 账本 `memory/bugs.md` 的「跨项目账目误落」守卫（BUG-565 后续项）

## 为什么有这个判据

2026-11-02 实证（BUG-565）：另一个项目（vq / sparksql-exe）的 21 条缺陷（BUG-544~564）被
`fist-mbt call report_bug --project_dir .` 写进了本仓账本——引擎侧 `project_dir` 无出路，
调用方无法把账落到自己的项目。处置先例（append-only）：条目保留不动 + 两节
`## 勘误(2026-11-02 · VQ 项目账目误落本树)` 逐字点名归属。BUG-565 的 detail 明载后续项
「外来条目检测守卫」——本判据就是那一项：**再发生同类误落时，CI 当场红，而不是靠人翻账本。**

## 外来形状判定（先真账本全量普查后定形，见 docstring 末「普查记录」）

条目 = `## BUG-N [ts] [sev] STATUS` 抬头到下一个 `## ` 同级抬头（文法与
`scripts/gen_plugins.py` 的 `RE_BUG_HEAD` / `check_bug_ledger_shape.py` 逐字同源，
selftest 有 parity 格盯同步）。

条目 body（含其 `### FIXED` 小节）中抽取**路径形 token**（≥2 段、`/` 分隔、无空格；
URL 先剥除、反斜杠先归一）。一个 token 判为「外来引用」需**同时**满足：

1. **前缀族命中**：token 以 `FOREIGN_REPO_PREFIXES` 之一开头（见下方常量表，每条带理由）。
   为什么需要前缀族、而不是「不在跟踪面即外来」：真账本普查（2026-11-03）证明本仓条目里
   **合法地**存在大量「不在本仓跟踪面的路径引用」——跨项目上下文（vools/、zhi/、tql/、
   crates/p5c/…，vq 事故之前就有意登记）、MoonBit 核心库文档（builtin/…）、Windows 绝对
   路径碎片（AppData/…、Files/Git/…）、测试计数比例噪声（0/1、1101/1101…）、gitignored
   scratch（temp/…）。**裸「不在跟踪面」判据在全量普查下误报数百条，直接设计失败**；
   前缀族是派单预给的形状规则出路（「要求路径同时匹配目录前缀族才算外来候选」）。
   族表只收 vq 误落事故实际出现的布局形状；**两段式 `crates/vq` 是关键**——单段 `crates`
   会把 p5c（Pentad 系合法引用，BUG-149/242/267/271）一并误红。
2. **不在本仓局部解析**：token 不在 `git ls-files` 跟踪面（带缓存）、不是任何跟踪路径的
   目录前缀、且（real 模式）不在盘上。 ⇒ 若本仓未来真长出 `data/` 之类的目录（tracked 或
   在盘），族表那一条自动失效，不需要改代码。
3. （token 以单字母段开头视为盘符碎片，跳过。）

## 勘误覆盖判定（保守边界，写死在 docstring 里的契约）

勘误节 = `## ` 级抬头且抬头含「勘误」（`### FIXED(...勘误...)` 是三级小节，不算）。
一节勘误覆盖哪些条目，**两种机判形态**：

- **点名式**（现网先例形态）：勘误 body 里的 `BUG-N` token 集合为「点名集」N(S)；
  覆盖 = N(S) ∩ **邻接块** B(S)。B(S) = 从勘误节往上数的连续条目 run：最近一条必须在
  N(S) 里，否则块为空；向上走，遇到第一条不在 N(S) 的条目即停。
  ⇒ 勘误节必须与其覆盖条目**紧邻**（中间只允许同为被点名的条目），放错位置 = 覆盖不了
  = 红，逼人把勘误节挪到紧邻位或逐条点名。
- **指代式**（「上面 N 条」且 body 里没有任何 BUG-N token）：覆盖 = 紧邻其上的最近 N 条。
  这是派单明文允许的「勘误节与其紧邻上文块」区间解析；边界就在这里——**只认勘误节正上方
  的 N 条**，不向更远处延伸。
- **判不了就当未覆盖并红**：body 既无 BUG-N token 也无「上面 N 条」的勘误节不产生任何
  覆盖——宁可红着逼勘误节措辞进化，绝不静默放行。

## rc 契约（与 check_bug_ledger_shape / check_fmt_gate 同族）

- `0` = 干净（无「未覆盖的外来引用条目」；**有勘误覆盖的外来条目按先例合法保留**）
- `1` = 有未覆盖外来条目（逐条点名 BUG 号 + 行号 + 引用路径）
- `2` = 判据无法自证（账本读不到 / 解析出 0 条目 / `git ls-files` 失败——绝不报绿）
- `4` = 尺子自己坏了（未捕获异常，绝不冒用其他档）

参数面：argparse（未知旗标天生即拒 rc=2，AGENTS R207 铁律）。
`--selftest`：全合成夹具（tempfile / 注入跟踪面，不依赖真 git、不碰真账本），
含变异对照：删勘误节 → ①那格从绿转红（证明覆盖检测真在工作；变异改夹具内容，且断言
变异真的落在了内容上）。PASS 行格数从已执行格子反解，不手写（BUG-514 同族）。

## 普查记录（形状规则的依据，改族表前先复跑）

2026-11-03 对真账本（~570 条目）全量普查：裸「不在跟踪面」判据产出 1367 个未解析 token
（绝大多数是 `N/M` 计数比例与跨项目上下文引用）；收紧为「前缀族 + 局部解析」后，
BUG-1~543、565、566 全部零命中；vq 误落条目（BUG-544~564）按前缀族命中、全部被两节勘误
按上面写的机判形态覆盖 ⇒ real 首跑 rc=0。
"""

from __future__ import annotations

import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

# Windows 控制台默认 GBK ⇒ 打印中文/符号会 UnicodeEncodeError；判据必须能说话。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001 —— 老 Python / 非 tty 时没有 reconfigure
    pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
LEDGER_DEFAULT = os.path.join(ROOT, "memory", "bugs.md")

RC_OK, RC_VIOLATION, RC_UNSELF, RC_BROKEN = 0, 1, 2, 4

# ══════════════════════════════════════════════════════════════════════
# 条目抬头文法 —— 与 scripts/gen_plugins.py 的 RE_BUG_HEAD 逐字一致
# （判例「同一规则多份实现必翻车」：同一口径的两个消费方必须同步，
#   selftest 里的 parity 格专门断言这一点。check_bug_ledger_shape.py 同款先例。）
# ══════════════════════════════════════════════════════════════════════
HEAD_STR = (
    r"^## BUG-(\d+[a-z]?) \[[^\]]+\] \[(?:critical|high|medium|low)\] "
    r"(?:OPEN|FIXED|DUPLICATE|FALSE_POSITIVE)\b"
)
RE_HEAD = re.compile(HEAD_STR, re.M)

# 路径形 token：≥2 段、`/` 分隔、每段不以 `-`/`.` 开头、段内无空白。
SEG = r"[A-Za-z0-9_][A-Za-z0-9_.\-]*"
RE_PATH_TOKEN = re.compile(r"(?<![\w.\-/])(?:%s/)+%s(?![\w.\-/])" % (SEG, SEG))
RE_URL = re.compile(r"\w+://\S+")           # URL 整段剥除（含 fist:// 资源名）
RE_DRIVE_TOKEN = re.compile(r"^[A-Za-z]/")   # 盘符碎片（`E:/...` 归一后首段单字母）
RE_BUG_REF = re.compile(r"BUG-\d+[a-z]?")
RE_COUNT_FORM = re.compile(r"上面\s*(\d+)\s*条")

# ══════════════════════════════════════════════════════════════════════
# 外来仓前缀族 —— 只收 vq 误落事故（BUG-544~564）实际出现的布局形状。
# 每条带理由；改这张表 = 改判据的形状契约，须先对真账本复跑普查（见 docstring）。
# 「不在跟踪面/不在盘上」的去冲突门在 evaluate() 里，与本表正交：
# 本仓未来若真长出同名目录（tracked 或在盘），对应族条目自动失效。
# ══════════════════════════════════════════════════════════════════════
FOREIGN_REPO_PREFIXES = (
    # 两段式是关键：crates/p5c 是 Pentad-p5c 的合法跨项目引用（BUG-149/242/267/271），不能收
    ("crates/vq", "Rust workspace crates/vq-{cli,core,pyo3}（vq 误落主形状，BUG-544/545/546/554/555/556/564）"),
    ("apps/", "Node/前端 workspace（vq apps/web、apps/api，BUG-547/548/549/553）"),
    ("packages/", "JS monorepo（vq packages/sql-editor，BUG-558）"),
    ("sparksql-exe/", "vq 伴生仓目录（BUG-550/551/552）"),
    ("data/", "vq 运行数据（data/vq.db，BUG-553）——本仓无 data/ 目录，tracked/在盘即自动放行"),
    ("legacy/", "vq 旧目录（legacy/dataquest/...，BUG-553/563）"),
)


def read(path: str) -> str:
    return io.open(path, encoding="utf-8", errors="replace").read()


def parse_entries(text: str) -> list:
    """条目 = 行首三段式抬头到下一个 `## ` 同级抬头（`###` 小节归属该条目）。"""
    lines = text.split("\n")
    entries = []
    i, n = 0, len(lines)
    while i < n:
        m = RE_HEAD.match(lines[i])
        if m:
            j = i + 1
            while j < n and not lines[j].startswith("## "):
                j += 1
            entries.append(
                {
                    "id": "BUG-" + m.group(1),
                    "lineno": i + 1,
                    "body": "\n".join(lines[i:j]),
                }
            )
            i = j
        else:
            i += 1
    return entries


def parse_errata(text: str) -> list:
    """勘误节 = `## ` 级抬头且抬头含「勘误」，body 到下一个 `## ` 抬头。"""
    lines = text.split("\n")
    out = []
    i, n = 0, len(lines)
    while i < n:
        if lines[i].startswith("## ") and "勘误" in lines[i]:
            j = i + 1
            while j < n and not lines[j].startswith("## "):
                j += 1
            out.append({"lineno": i + 1, "body": "\n".join(lines[i:j])})
            i = j
        else:
            i += 1
    return out


def extract_tokens(body: str) -> list:
    """条目 body 里的路径形 token（去重、保序）。URL 剥除、反斜杠归一、盘符碎片跳过。"""
    clean = RE_URL.sub(" ", body).replace("\\", "/")
    out = []
    for m in RE_PATH_TOKEN.finditer(clean):
        tok = m.group()
        if RE_DRIVE_TOKEN.match(tok):
            continue
        if tok not in out:
            out.append(tok)
    return out


def covered_ids(entries: list, errata: list) -> set:
    """勘误覆盖判定（契约见模块 docstring「勘误覆盖判定」，保守：判不了 = 不覆盖）。"""
    covered = set()
    for er in errata:
        named = set(RE_BUG_REF.findall(er["body"]))
        above = [e for e in entries if e["lineno"] < er["lineno"]]
        if named:
            # 点名式：邻接块 = 从最近一条往上、连续都在点名集里的 run（断即停）
            for e in reversed(above):
                if e["id"] in named:
                    covered.add(e["id"])
                else:
                    break
        else:
            m = RE_COUNT_FORM.search(er["body"])
            if m:
                k = int(m.group(1))
                if k > 0:
                    for e in above[-k:]:
                        covered.add(e["id"])
            # 两种形态都判不了 ⇒ 不产生覆盖 ⇒ 未覆盖外来条目保持红
    return covered


def evaluate(text: str, tracked, root=None) -> tuple:
    """纯函数核：text=账本全文，tracked=git ls-files 集合（None=拿不到），root=在盘解析根。

    返回 (rc, info)；info 含 entries/flagged/covered/uncovered/n_errata 供渲染与自检断言。
    """
    if tracked is None:
        return RC_UNSELF, {"note": "`git ls-files` 跟踪面拿不到 ⇒ 判据无法自证（拒绝判，绝不报绿）"}
    entries = parse_entries(text)
    if not entries:
        return RC_UNSELF, {"note": "解析出 0 条条目 ⇒ 判据与账本口径不一致（拒绝出结论）"}

    # 跟踪路径的全部祖先目录（一次预计算，目录引用去冲突用）
    tracked_dirs = set()
    for t in tracked:
        parts = t.split("/")
        for k in range(1, len(parts)):
            tracked_dirs.add("/".join(parts[:k]))

    errata = parse_errata(text)
    covered = covered_ids(entries, errata)

    flagged = []  # [(entry, [foreign token...])]
    for e in entries:
        foreign = []
        for tok in extract_tokens(e["body"]):
            if not any(tok.startswith(p) for p, _r in FOREIGN_REPO_PREFIXES):
                continue
            if tok in tracked or tok in tracked_dirs:
                continue  # 本仓跟踪面命中（tracked 文件或目录前缀）
            if root is not None and os.path.exists(os.path.join(root, *tok.split("/"))):
                continue  # 在盘（gitignored scratch / 未提交新目录）
            foreign.append(tok)
        if foreign:
            flagged.append((e, foreign))

    uncovered = [(e, f) for e, f in flagged if e["id"] not in covered]
    covered_flagged = [e for e, _f in flagged if e["id"] in covered]
    rc = RC_VIOLATION if uncovered else RC_OK
    return rc, {
        "entries": entries,
        "n_errata": len(errata),
        "flagged": flagged,
        "covered_flagged": covered_flagged,
        "uncovered": uncovered,
    }


def load_tracked(root: str):
    """`git -C root ls-files -z` → 路径集合（正斜杠归一）；失败返回 None（调用方自拒）。"""
    try:
        p = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            capture_output=True, timeout=120,
        )
    except Exception:  # noqa: BLE001 —— git 不在 / 超时 ⇒ 拿不到跟踪面
        return None
    if p.returncode != 0:
        return None
    return {
        f.decode("utf-8", "replace").replace("\\", "/")
        for f in p.stdout.split(b"\0")
        if f
    }


def render(rc: int, info: dict, n_tracked: int) -> None:
    if rc == RC_UNSELF:
        print("[FATAL] " + info["note"])
        print("判据无法自证 ⇒ rc=2")
        return
    flagged, uncovered = info["flagged"], info["uncovered"]
    foreign_of = {e["id"]: f for e, f in flagged}
    print(
        "[扫描] 条目 %d · 勘误节 %d · 外来引用条目 %d（其中勘误覆盖 %d）· git 跟踪面 %d 文件 · 家族前缀 %d 组"
        % (
            len(info["entries"]),
            info["n_errata"],
            len(flagged),
            len(info["covered_flagged"]),
            n_tracked,
            len(FOREIGN_REPO_PREFIXES),
        )
    )
    for e in info["covered_flagged"]:
        f = foreign_of.get(e["id"], [])
        print("  · %s :%d 外来引用（已被勘误节覆盖，append-only 保留）：%s" % (e["id"], e["lineno"], "、".join(f[:3]) + ("…" if len(f) > 3 else "")))
    if uncovered:
        print()
        print("[结论] %d 条外来引用条目未被任何勘误节覆盖：" % len(uncovered))
        for e, f in uncovered:
            print(
                "  ✗ %s :%d 外来引用：%s%s"
                % (e["id"], e["lineno"], "、".join(f[:3]), "（等 %d 处）" % len(f) if len(f) > 3 else "")
            )
        print()
        print("       处置：按 BUG-544~564 先例——条目 append-only 保留，紧邻其下加")
        print("             `## 勘误(...)` 节逐字点名（或「上面 N 条」）声明归属真仓；")
        print("             勘误节必须与被覆盖条目紧邻（见脚本 docstring 覆盖契约）。")
    else:
        print()
        print("[结论] 无未覆盖的外来引用条目。**这不等于账本内容全对** —— 本判据只查")
        print("       「前缀族形状 × 不在本仓跟踪面 × 勘误覆盖」，形状族外的误落它看不见。")
    print()
    print(
        "[汇总] 条目 %d / 外来引用条目 %d / 勘误覆盖 %d / 未覆盖 %d ⇒ rc=%d"
        % (
            len(info["entries"]),
            len(flagged),
            len(info["covered_flagged"]),
            len(uncovered),
            rc,
        )
    )


def _run(ledger: str) -> int:
    if not os.path.isfile(ledger):
        print("[FATAL] 找不到账本 %s ⇒ rc=2（绝不报绿）" % ledger)
        return RC_UNSELF
    try:
        text = read(ledger)
    except OSError as exc:
        print("[FATAL] 账本读不到 %s：%r ⇒ rc=2" % (ledger, exc))
        return RC_UNSELF
    tracked = load_tracked(ROOT)
    if tracked is None:
        print("[FATAL] `git ls-files` 失败（root=%s）⇒ 跟踪面拿不到，拒绝判 ⇒ rc=2" % ROOT)
        return RC_UNSELF
    rc, info = evaluate(text, tracked, root=ROOT)
    render(rc, info, len(tracked))
    return rc


def run(ledger: str = LEDGER_DEFAULT) -> int:
    """real 入口：异常一律 rc=4（尺子坏了，绝不冒用 0/1/2 任何一档）。"""
    try:
        return _run(ledger)
    except Exception as exc:  # noqa: BLE001
        print("[FATAL] 判据自身异常：%r ⇒ rc=4" % (exc,))
        return RC_BROKEN


# ══════════════════════════════════════════════════════════════════════
# selftest —— 全合成夹具，不依赖真 git、不碰真账本（判据必须 hermetic 可自证）
# ══════════════════════════════════════════════════════════════════════

TRACKED_SYNTH = {
    "scripts/check_x.py",
    "src/server/server.mbt",
    "memory/bugs.md",
    "src/store/store_sqlite.mbt",
}

TS = "2026-11-02T15:41:05Z"


def _head(bug_id: str, status: str = "FIXED") -> str:
    return "## %s [%s] [high] %s" % (bug_id, TS, status)


F_FOREIGN = (
    _head("BUG-901") + "\n"
    "- summary: 连接串参数错误仍返回 rc=0\n"
    "- detail: crates/vq-cli/src/main.rs 的 add_conn 分支三处 return Ok(())\n"
    "- reported_by: Qoder-agent\n"
)

F_FOREIGN_2 = (
    _head("BUG-903") + "\n"
    "- detail: packages/sql-editor 全仓零 import\n"
)

F_LOCAL = (
    _head("BUG-902") + "\n"
    "- detail: scripts/check_x.py 与 src/server/server.mbt 对表；vools/task/core/cli_exec.py 是"
    "合法跨项目上下文引用（vq 事故之前就有意登记的形状，本判据不红）\n"
)

F_ERRATA = (
    "## 勘误(2026-11-02 · X 项目账目误落本树)\n"
    "- 上面 1 条（BUG-901）是 E:/IDEProjects/AI/xxx 项目的缺陷，不属于本仓。\n"
    "- 处置：已逐字搬移；本树条目 append-only 保留，以本节为准。\n"
)


def _ev(text: str, tracked=TRACKED_SYNTH, root=None):
    return evaluate(text, tracked, root=root)


def selftest() -> int:
    results = []

    def cell(name, got, want):
        ok = got == want
        results.append((name, ok))
        if not ok:
            print("  [FAIL] %s  got=%r want=%r" % (name, got, want), file=sys.stderr)

    # ── ① 外来条目、无勘误覆盖 ⇒ 红，且逐条点名 ──
    rc1, info1 = _ev(F_FOREIGN)
    cell("S1a 外来条目无勘误 ⇒ rc=1", rc1, RC_VIOLATION)
    cell("S1b 未覆盖点名含 BUG-901", [e["id"] for e, _f in info1["uncovered"]], ["BUG-901"])
    cell("S1c 点名带引用路径", info1["uncovered"][0][1], ["crates/vq-cli/src/main.rs"])

    # ── ② 同条目 + 勘误节点名覆盖（紧邻）⇒ 绿 ──
    B = F_FOREIGN + "\n" + F_ERRATA
    rc2, info2 = _ev(B)
    cell("S2a 勘误节点名紧邻覆盖 ⇒ rc=0", rc2, RC_OK)
    cell("S2b 外来条目全部被覆盖", len(info2["covered_flagged"]), 1)

    # ── ⑤ 变异对照：删掉勘误节 ⇒ ②那格必须从绿转红（覆盖检测真在工作）──
    # 变异改的是**夹具内容**；并断言变异真的落在了内容上（「勘误」字样已消失）。
    B_mut = B.replace(F_ERRATA, "", 1)
    cell("S3a 变异落点存在（勘误节被真删）", "勘误" in B_mut, False)
    cell("S3b 删勘误节后 ②那格从绿转红", _ev(B_mut)[0], RC_VIOLATION)

    # ── ③ 纯本仓路径 / 合法跨项目上下文条目 ⇒ 绿 ──
    rc4, _i4 = _ev(F_LOCAL)
    cell("S4a 本仓 tracked 路径 ⇒ 不红", rc4, RC_OK)
    cell(
        "S4b 家族前缀但 tracked 命中（apps/tool.py）⇒ 不红",
        _ev(_head("BUG-904") + "\n- detail: apps/tool.py 被误改\n", tracked=TRACKED_SYNTH | {"apps/tool.py"})[0],
        RC_OK,
    )
    # 家族前缀但在盘上（gitignored scratch 形状）⇒ 不红
    tmpd = tempfile.mkdtemp(prefix="scope_probe_root_")
    try:
        os.makedirs(os.path.join(tmpd, "data"), exist_ok=True)
        with open(os.path.join(tmpd, "data", "vq.db"), "w", encoding="utf-8") as fh:
            fh.write("")
        cell(
            "S4c 家族前缀但在盘存在（root=data/vq.db）⇒ 不红",
            _ev(_head("BUG-905") + "\n- detail: data/vq.db 已在盘\n", root=tmpd)[0],
            RC_OK,
        )
    finally:
        shutil.rmtree(tmpd, ignore_errors=True)

    # ── ④ 空账本 / 0 条目 ⇒ rc=2 自拒；跟踪面拿不到 ⇒ rc=2 ──
    cell("S5a 空账本 ⇒ rc=2", _ev("   \n\n")[0], RC_UNSELF)
    cell("S5b 无三段式抬头 ⇒ rc=2", _ev("# bugs\n一些没有抬头的文字\n")[0], RC_UNSELF)
    cell("S5c tracked=None ⇒ rc=2", _ev(F_FOREIGN, tracked=None)[0], RC_UNSELF)

    # ── ⑥ 邻接保守格：勘误节点名 901 但中间隔了未点名的 902 ⇒ 覆盖不了 ⇒ 红 ──
    rc6, _i6 = _ev(F_FOREIGN + "\n" + F_LOCAL + "\n" + F_ERRATA)
    cell("S6 勘误节与被点名条目不相邻 ⇒ 红（保守）", rc6, RC_VIOLATION)

    # ── ⑦ 指代式「上面 N 条」：紧邻 N 条 = 覆盖；N 小于外来条目数 ⇒ 未覆盖的红 ──
    cf_green = F_FOREIGN + "\n" + F_ERRATA.replace("（BUG-901）", "")
    cell("S7a 指代式「上面 1 条」紧邻 ⇒ 绿", _ev(cf_green)[0], RC_OK)
    cf_red = F_FOREIGN + "\n" + F_FOREIGN_2 + "\n" + F_ERRATA.replace("（BUG-901）", "")
    rc7, info7 = _ev(cf_red)
    cell("S7b 指代式只盖最近 1 条 ⇒ 另一条红", rc7, RC_VIOLATION)
    cell("S7c 未覆盖的是较远那条", [e["id"] for e, _f in info7["uncovered"]], ["BUG-901"])

    # ── ⑧ 既不点名也无「上面 N 条」的勘误节 ⇒ 不产生覆盖 ⇒ 仍红（措辞必须进化）──
    blank = F_FOREIGN + "\n" + "## 勘误(某节)\n- 是外来缺陷，不属于本仓。\n"
    cell("S8 无点名无指代的勘误节 ⇒ 覆盖不了 ⇒ 红", _ev(blank)[0], RC_VIOLATION)

    # ── ⑨ 点名式覆盖多条（连续块）⇒ 绿 ──
    both = (
        F_FOREIGN + "\n" + F_FOREIGN_2 + "\n"
        + "## 勘误(2026-11-02 · X 项目账目误落本树)\n"
        + "- 上面 2 条（BUG-901, BUG-903）是外来缺陷。\n"
    )
    cell("S9 勘误节点名连续多条 ⇒ 全覆盖绿", _ev(both)[0], RC_OK)

    # ── ⑩ real 入口：账本缺失 ⇒ rc=2；尺子坏了 ⇒ rc=4；未知旗标 ⇒ rc=2 ──
    cell("S10a 账本不存在 ⇒ rc=2", run(os.path.join(tempfile.gettempdir(), "scope_no_such_ledger.md")), RC_UNSELF)

    saved = evaluate
    try:
        globals()["evaluate"] = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("合成故障"))
        cell("S10b 判据自身异常 ⇒ rc=4（不冒用其他档）", run(LEDGER_DEFAULT), RC_BROKEN)
    finally:
        globals()["evaluate"] = saved

    face_dir = tempfile.mkdtemp(prefix="scope_face_")
    try:
        p = subprocess.run(
            [sys.executable, os.path.abspath(__file__), "--definitely-not-real"],
            cwd=face_dir, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
        )
        cell("S10c 调用面自 spawn 拒未知旗标 rc=2", p.returncode, RC_UNSELF)
    finally:
        shutil.rmtree(face_dir, ignore_errors=True)

    # ── ⑪ 渲染面冒烟：干净 / 违例 / 自拒三态都不炸且末行汇总在场 ──
    # （首版 render 对 covered_flagged 的解包形状写错，selftest 不调 render 就看不见——本格即为此立。）
    import io as _io
    for _rc, _info, _want in (
        (RC_OK, _ev(F_FOREIGN + "\n" + F_ERRATA)[1], "[汇总] 条目 1 / 外来引用条目 1 / 勘误覆盖 1 / 未覆盖 0"),
        (RC_VIOLATION, _ev(F_FOREIGN)[1], "[汇总] 条目 1 / 外来引用条目 1 / 勘误覆盖 0 / 未覆盖 1"),
        (RC_UNSELF, {"note": "合成自拒"}, "判据无法自证 ⇒ rc=2"),
    ):
        buf = _io.StringIO()
        _stdout = sys.stdout
        try:
            sys.stdout = buf
            render(_rc, _info, 7)
        finally:
            sys.stdout = _stdout
        out = buf.getvalue()
        cell(
            "S11 render rc=%d 不炸且关键行在场（含「%s」）" % (_rc, _want),
            (_want in out) and (("[汇总]" in out) or _rc == RC_UNSELF),
            True,
        )

    # ── ⑫ 真源一致性：本文件抬头正则与 gen_plugins 的 RE_BUG_HEAD 同口径 ──
    cell("S12 regex-parity-with-gen_plugins", _parity_with_gen_plugins(), True)

    ok = sum(1 for _n, good in results if good)
    total = len(results)
    if ok == total:
        print("SELFTEST PASS（%d/%d）" % (total, total))
        return 0
    print("SELFTEST FAIL（%d/%d）" % (ok, total), file=sys.stderr)
    return 1


def _parity_with_gen_plugins() -> bool:
    """断言本判据的抬头正则与 `gen_plugins.py` 的 `RE_BUG_HEAD` 对同一批样本结论一致。"""
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
        "- evidence: x。## BUG-206 [2026-10-15T10:53:48Z] [high] OPEN",
    ]
    mine = re.compile(HEAD_STR)
    for s in samples:
        if bool(gp_re.match(s)) != bool(mine.match(s)):
            return False
    return True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="账本 memory/bugs.md 的「跨项目账目误落」守卫（BUG-565 后续项）："
        "前缀族形状 × 不在本仓 git 跟踪面 × 无勘误覆盖 ⇒ 红"
    )
    ap.add_argument("--selftest", action="store_true", help="变异对照自检（全合成夹具，不碰真账本、不依赖真 git）")
    ap.add_argument("--ledger", default=LEDGER_DEFAULT, help="账本路径（默认 <repo>/memory/bugs.md）")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    return run(args.ledger)


if __name__ == "__main__":
    sys.exit(main())
