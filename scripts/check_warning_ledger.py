#!/usr/bin/env python3
"""check_warning_ledger.py — `docs/warning-ledger.md` 的**可核性**判据（Lane DU）

## 为什么有这个判据

台账是「**我说这些 warning 不用改**」的清单。
**一份没人能核的清单，和没有清单是一样的** —— 下一个人不知道它是「真核过」
还是「作者自己的声明」。

本判据把它变成**可机核**的断言：

> **每一条 `moon check` 的 warning，要么出现在台账里，要么被修掉。**
> **不存在「既不在台账、也没修」的 warning。**

## ★ 匹配粒度（本判据的核心设计，也是它会在哪儿误判）

采用 **两级**：

| 级 | 断言 | 抓什么 | 漏什么 |
|---|---|---|---|
| **L1 (类型, 文件)** | 现算出现的每个 (类型, 文件) 组合，**必须**在台账某条目里被点名 | **漏登记一个文件** | 同文件同类型多条被「一条覆盖」 |
| **L2 类型总数** | 台账 §2 覆盖率表的「现算总数」== 真正现算的该类总数 | **数量记错**（Gamma 实测踩过：`unused_value` 记 6 实际 10）| 若台账与现算「同步错」，两级都抓不到 |

**为什么不用 (类型, 文件, 行)**：行号是**代码的属性**，不是**豁免理由的属性**。
一次 `moon fmt`、一次上面插一行，台账就全 stale ⇒ **台账会变成「天天要改的负担」**，
而负担重的台账**必然被放弃** ⇒ 那比没有台账更糟。

**⇒ 本粒度明确的误判面（写在这里，不藏在注释里）**：
1. **同文件同类型多条，台账只写一条** ⇒ L1 通过（因为该文件确实被点名），
   **L2 也通过**（若总数对）⇒ **这类「粒度太粗」抓不到**。
   例：`server.mbt` 有 4 个 `result_error_return`，台账写 `server.mbt:109/128/1277/1332`
   全列了；若只写 `server.mbt` 一个位置，L1/L2 都过。
   ⇒ **这是本判据接受的已知盲区**（换来的是台账不必随行号漂移）。
2. **台账与现算同时错**（都是 16 而真实是 17）⇒ 抓不到。
   ⇒ 缓解：L1 的「文件必须在台账出现」能抓住**新增文件**这一主要漂移来源。

## rc 契约
- `0` = 全覆盖（每条 warning 都在台账）
- `1` = 有未覆盖 / 有 stale
- `2` = **判据无法自证**（`moon check` 编译红 / 台账不存在 / 台账格式解析不出 §2 表）
- `4` = 尺子坏了（判据自身异常，绝不冒用 1 那一档）

## 用法
    python scripts/check_warning_ledger.py                  # 真跑 moon check
    python scripts/check_warning_ledger.py --check-output F # 从文件读 moon check 输出（selftest 用）
    python scripts/check_warning_ledger.py --ledger F       # 指定台账（selftest 用）
    python scripts/check_warning_ledger.py --selftest       # 自证（含变异对照）
    python scripts/check_warning_ledger.py --list           # 逐条列出未覆盖 / stale
"""

from __future__ import annotations

import io
import os
import re
import subprocess
import sys

# R208：spawn `moon` 必须经 `moon_env()`（本机 moonc 的 `\\?\` 路径 ICE 靠 MOONC_OVERRIDE 绕开）。
# 病象：本文件 `run_moon_check()` 直接 `subprocess.run(["moon", …])` 没带 env
# ⇒ `moon_env_probe.py` 的 L1「真现状面」把它判成违例 1/13，且 `--selftest` 1/11 红。
# 判据自己的话：「13 份接线 / 违例 1」。修法与 R125 的 8 个入口一致：`env=moon_env()`。
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from moon_env_probe import moon_env  # noqa: E402  （同目录共享模块，需先补 sys.path）

# Windows 控制台默认 GBK ⇒ 打印 `⇒`/`✗` 会 UnicodeEncodeError。
# 判据必须**在任何平台上都能把话说出来**（说不出来 = rc 契约失效）。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_LEDGER = os.path.join(ROOT, "docs", "warning-ledger.md")

RC_OK, RC_VIOLATION, RC_CANNOT, RC_BROKEN = 0, 1, 2, 4

# `moon check` 的 warning 行：`╰─── Warning (类型): ...`
# 位置行：`╭─[ <path>:<line>:<col> ]`
RE_POS = re.compile(r"╭─\[\s*(.+?):(\d+):(\d+)\s*\]")
RE_WARN = re.compile(r"Warning \(([a-z_]+)\)")

# 台账 §2 覆盖率表行：| `deprecated` | 17 | 14（...） | **3** | ... |
RE_COV_ROW = re.compile(
    r"^\|\s*\**`?([a-z_]+)`?\**\s*\|\s*\**(\d+)\**\s*\|", re.M
)


def read(p: str) -> str:
    return io.open(p, encoding="utf-8", errors="replace").read()


# ══════════════════════════════════════════════════════════════════════
# 左侧：解析 moon check 输出
# ══════════════════════════════════════════════════════════════════════

def parse_check_output(text: str) -> tuple[dict, bool]:
    """返回 ({类型: [(文件, 行)]}, compiled_ok)

    ⚠️ **值是 list 不是 set**（Lane DU 修正，统帅实测抓出）：
    一个表达式可以触发**多条** warning（如 `x.to_string()` 同时触发 `to_string` 的
    deprecated 与隐式 impl 的 deprecated）⇒ **位置相同，warning 是两条**。
    用 set 去重会让**分母偏小** ⇒ 覆盖率**虚高**（实测 43 vs 真值 46，虚报成 100%）。
    ⇒ 这里保留重复；**去重只发生在判 L1 文件覆盖时**。

    ⚠️ **判据-30 自检**：本函数只认 `Warning (` 与 `╭─[ path:line:col ]` 两种形态，
    台账里的 markdown 表格/反引号不会命中（它们用 `[` 不是 `╭─[`）。
    """
    lines = text.split("\n")
    compiled_ok = bool(re.search(r"\b0 errors\b|\bup to date\b", text))
    # 编译红：出现 `Error: [` 且**没有** `0 errors`
    if re.search(r"^Error: \[", text, re.M) and not compiled_ok:
        compiled_ok = False
    out: dict[str, set] = {}
    cur = None
    for ln in lines:
        m = RE_POS.search(ln)
        if m:
            path = m.group(1).replace("\\", "/")
            # 归一成相对仓库根的路径，且只用 basename 造 (dir/file) 形式
            if "/src/" in path:
                path = "src/" + path.split("/src/", 1)[1]
            elif "/cmd/" in path:
                path = "cmd/" + path.split("/cmd/", 1)[1]
            elif "/atgc" in path:
                # atgc / atgc-old 顶层目录
                for d in ("atgc-old/", "atgc/"):
                    if "/" + d in path:
                        path = d + path.split("/" + d, 1)[1]
                        break
            cur = (path, int(m.group(2)))
        w = RE_WARN.search(ln)
        if w and cur:
            out.setdefault(w.group(1), []).append(cur)
            cur = None
    return out, compiled_ok


# ══════════════════════════════════════════════════════════════════════
# 右侧：解析台账
# ══════════════════════════════════════════════════════════════════════

def parse_ledger(text: str) -> tuple[dict, dict, list]:
    """返回 (cov_counts, mentioned, errors)

    cov_counts : {类型: 台账 §2 声明的「现算总数」}
    mentioned  : {类型: set(被 §1 条目点名过的文件 basename)}
    """
    errors = []

    # ── §2 覆盖率表：取「现算总数」列 ──
    cov: dict[str, int] = {}
    in_cov = False
    for ln in text.split("\n"):
        s = ln.strip()
        if s.startswith("| 类型 |") and "现算总数" in s:
            in_cov = True
            continue
        if in_cov:
            if not s.startswith("|"):
                in_cov = False
                continue
            m = RE_COV_ROW.match(s)
            if m:
                cov[m.group(1)] = int(m.group(2))
            continue
    if not cov:
        errors.append("§2 覆盖率表解析不出任何 (类型, 现算总数) 行")

    # ── §1 台账条目：抽出每行点名的文件 basename ──
    # 条目行形如：| L6 | `deprecated`（Show→Debug） | **11** | `a.mbt:501`(2) · `b.mbt` | ... |
    mentioned: dict[str, set] = {}
    in_items = False
    for ln in text.split("\n"):
        s = ln.strip()
        if s.startswith("| # |") and "类型" in s:
            in_items = True
            continue
        if in_items:
            if not s.startswith("|"):
                in_items = False
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) < 4 or not cells[0].startswith("L"):
                continue
            # 类型：从 `deprecated`（Show→Debug） 里取第一个反引号内标识符
            tm = re.search(r"`([a-z_]+)`", cells[1])
            if not tm:
                continue
            ty = tm.group(1)
            # 位置列（第 4 格）：抽出所有 `xxx.mbt` / `xxx.pkg`
            # ⚠️ 实测踩坑：原正则只认 `.mbt` ⇒ `unused_package` 的 `consistency/moon.pkg`
            #    全被漏掉，判据误报「4 处未覆盖」。**判据自己会漏**（判例-30 同族：
            #    模式串只覆盖了一部分真实形态）。⇒ 同时收 `.mbt` 与 `.pkg`。
            # ⚠️ `.pkg` 尤其要**带路径**：本仓有 4 个 `moon.pkg` 都叫同一个名字，
            #    只记 basename 会把「4 个不同文件」塌成 1 个 ⇒ 覆盖判定失真。
            #    ⇒ 同时记「完整路径片段」与 basename：
            #       `consistency/moon.pkg` 记 `consistency/moon.pkg` + `moon.pkg`。
            for fm in re.finditer(
                r"((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_]+\.(?:mbt|pkg))", cells[3]
            ):
                full = fm.group(1)
                # ⚠️ **只记台账实际写出的形态**，不要附加 basename ——
                #    附加 basename 会让「带路径的登记」顺带覆盖所有同名文件
                #    （实测：`aaa/moon.pkg` 额外记 `moon.pkg` ⇒ `bbb/moon.pkg` 假绿）。
                mentioned.setdefault(ty, set()).add(full)
    if not mentioned:
        errors.append("§1 台账条目解析不出任何 (类型, 文件) 组合")

    return cov, mentioned, errors


# ══════════════════════════════════════════════════════════════════════
# 判定
# ══════════════════════════════════════════════════════════════════════

def _hit(path: str, ment: set) -> bool:
    """台账点名是否覆盖这条 warning 的文件。

    匹配顺序（由严到宽）：
      1. **完整路径相等**（台账写 `src/engine/moon.pkg` 就只算 engine）
      2. **路径后缀命中**（台账写 `consistency/moon.pkg`，现算 `src/consistency/moon.pkg`）
         —— 台账允许省略 `src/` 前缀（Gamma 的写法就是省掉的）
      3. **basename 兜底**（`server.mbt` 这类唯一名）
    ⚠️ `.pkg` 必须走 1/2：本仓 4 个 `moon.pkg` 同名，只按 basename 会把 4 个塌成 1 个。
    """
    if path in ment:
        return True
    for cand in ment:
        # ① 台账**带路径** ⇒ 只认路径后缀，**不许退回 basename**
        #    ⚠️ 本单实测踩到：4 个 `moon.pkg` 同名时，退回 basename 会让
        #    `bbb/moon.pkg` 被 `aaa/moon.pkg` 的登记「顺带覆盖」⇒ **判据假绿**。
        #    这就是 `pkg-same-name-not-collapsed` 那格锁住的东西。
        if "/" in cand:
            if path.endswith("/" + cand) or cand.endswith("/" + path):
                return True
            continue
        # ② 台账**只写 basename**（如 `server.mbt`）⇒ 才用 basename 匹配
        if cand == os.path.basename(path):
            return True
    return False


def judge(actual: dict, cov: dict, mentioned: dict) -> dict:
    """★★ **两级分母分开算**（Lane DU 修正，统帅实测抓出「分母偏小」）

    | 级 | 分母 | 断言 |
    |---|---|---|
    | **L1 文件覆盖** | 按 (类型, 文件) **去重** 的组合数 | 每个组合必须被台账点名 |
    | **L2 数量核对** | 按 **Warning 块**计数（**不去重**） | 台账 §2「现算总数」== 真实块数 |

    **为什么必须分开**：
    · L1 问的是「**这个文件有没有被登记过**」—— 同文件同类型多条，登记一次就够 ⇒ 必须去重；
    · L2 问的是「**台账记的数量对不对**」—— 数量就是 warning 条数 ⇒ **绝不能去重**。
    用一个分母同时服务两个问题，就会出现本单实测的：
    **L1 去重把分母缩小 3 ⇒ 43/43 = 100% 虚高**（真值 46）。
    """
    # 块计数（不去重）—— L2 用的分母
    block_counts = {t: len(v) for t, v in actual.items()}
    total_blocks = sum(block_counts.values())

    # 去重到 (类型, 文件) —— L1 用的分母
    combos: dict[str, set] = {}
    for ty, poss in actual.items():
        for (path, _line) in poss:
            combos.setdefault(ty, set()).add(path)

    uncovered_files = []   # [(类型, 文件, 示例行)]
    covered_combos = 0
    total_combos = 0
    for ty, paths in sorted(combos.items()):
        for path in sorted(paths):
            total_combos += 1
            if _hit(path, mentioned.get(ty, set())):
                covered_combos += 1
            else:
                line = next(l for (p, l) in actual[ty] if p == path)
                uncovered_files.append((ty, path, line))

    count_mismatch = []    # [(类型, 台账, 现算块数)]
    for ty, n in sorted(block_counts.items()):
        if ty in cov and cov[ty] != n:
            count_mismatch.append((ty, cov[ty], n))

    # stale：台账 §2 记某类型 N>0，而现算 0 块
    stale_types = []
    for ty, n in sorted(cov.items()):
        if n > 0 and block_counts.get(ty, 0) == 0:
            stale_types.append((ty, n))

    return {
        "uncovered_files": uncovered_files,
        "count_mismatch": count_mismatch,
        "stale_types": stale_types,
        "covered_combos": covered_combos,
        "total_combos": total_combos,
        "total_blocks": total_blocks,
        "block_counts": block_counts,
        "cov": cov,
    }


def render(rc: int, r: dict, note: str = "") -> None:
    if rc in (RC_CANNOT, RC_BROKEN):
        print(f"[{'FATAL' if rc == RC_CANNOT else 'BROKEN'}] {note}")
        print(f"判据无法自证 ⇒ rc={rc}")
        return
    bc = r["block_counts"]
    print(f"[现算] 合计 **{r['total_blocks']}** 条 warning —— "
          + " · ".join(f"{k}={v}" for k, v in sorted(bc.items(), key=lambda x: -x[1])))
    # ★ 两级读数分开打印（Lane DU：分母口径不同，混在一起会掩盖「虚高」）
    p1 = (100.0 * r["covered_combos"] / r["total_combos"]) if r["total_combos"] else 100.0
    print(f"[L1 文件覆盖] {r['covered_combos']}/{r['total_combos']} 个 (类型,文件) 组合已登记"
          f" = {p1:.1f}%")
    n_match = len(r["block_counts"]) - len(r["count_mismatch"])
    print(f"[L2 数量核对] {n_match}/{len(r['block_counts'])} 类与台账声明相符"
          f"（分母按 **Warning 块** 计：{r['total_blocks']} 条）")
    bad = bool(r["uncovered_files"] or r["count_mismatch"] or r["stale_types"])
    if not bad:
        print()
        print("[结论] L1 全覆盖 且 L2 数量全相符。")
        print("       ⚠️ **这不等于台账理由都对** —— 本判据只查「有没有登记 + 数量对不对」，")
        print("          不查「为什么保留」是否成立。")
        return
    if r["uncovered_files"]:
        print()
        print(f"[L1 未覆盖] {len(r['uncovered_files'])} 个 (类型,文件) 组合未在台账点名：")
        for ty, path, line in r["uncovered_files"]:
            print(f"  ✗ ({ty}) {path}:{line}")
    if r["count_mismatch"]:
        print()
        print(f"[L2 数量不符] {len(r['count_mismatch'])} 类（台账 §2 vs **块计数**）：")
        for ty, lv, nv in r["count_mismatch"]:
            print(f"  ✗ {ty}: 台账记 {lv}，现算 **{nv}** 块")
    if r["stale_types"]:
        print()
        print(f"[stale] {len(r['stale_types'])} 类（台账记有，现算 0 ⇒ 修了但没删台账行）：")
        for ty, n in r["stale_types"]:
            print(f"  ✗ {ty}: 台账记 {n}，现算 0")
    print()
    print("  处置：L1 未覆盖 ⇒ 登记进 §1（带理由 + 复审条件）；")
    print("        L2 不符 ⇒ 改正 §2 的「现算总数」（**注意：要按 Warning 块计数，不是按去重后的位置数**）；")
    print("        stale ⇒ 从台账删除该项。")


def run_moon_check() -> str:
    """跑 `moon check` 并把 **stdout + stderr 合并**返回。

    ⚠️ **实测（Lane DU，统帅提醒）**：本机 `moon check` 的**全部输出走 stderr**
    （`stdout len=0` / `stderr len≈13934`）。
    ⇒ 只读 stdout 的判据会拿到空 ⇒ **「永远 0 warnings」且静默判绿**。
    这里两路都读；若两路都空则**显式报错**，绝不让「没读到」变成「没问题」。
    """
    r = subprocess.run(
        ["moon", "check", "--target", "js"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=ROOT,
        env=moon_env(),
    )
    out = (r.stdout or "") + (r.stderr or "")
    if not out.strip():
        # 不静默：输出流变了（或 moon 换版本）必须说出来，走 rc=2 那一档
        raise RuntimeError(
            "moon check 的 stdout 与 stderr **都为空** ⇒ 无法测量"
            "（可能输出流变了）⇒ 拒绝判绿"
        )
    return out


# ══════════════════════════════════════════════════════════════════════
# selftest
# ══════════════════════════════════════════════════════════════════════

CHECK_GOOD = """\
Error: [0020]
    ╭─[ /r/src/a.mbt:10:5 ]
 10 │   x.to_string()
    │    ╰─ Warning (deprecated): Use Debug
Warning: [0001]
    ╭─[ /r/src/b.mbt:20:4 ]
 20 │ fn dead() {}
    │    ╰─ Warning (unused_value): Unused function 'dead'
Finished. moon: ran 3 tasks, now up to date (49 warnings, 0 errors)
"""

# ★ 同位置两条 warning（Lane DU 修正的锁）：一个表达式可触发多条 deprecated
#   —— 统帅实测抓出「按 (类型,文件:行) 去重 ⇒ 分母偏小 ⇒ 覆盖率虚高」。
CHECK_DUP_POS = """\
Error: [0020]
    ╭─[ /r/src/a.mbt:10:5 ]
 10 │   x.to_string()
    │    ╰─ Warning (deprecated): Use Debug instead of Show
Error: [0020]
    ╭─[ /r/src/a.mbt:10:5 ]
 10 │   x.to_string()
    │    ╰─ Warning (deprecated): Use `@debug.Debug` instead of `Show`
Finished. moon: ran 3 tasks, up to date (9 warnings, 0 errors)
"""

CHECK_RED = """\
Error: [4021]
    ╭─[ /r/src/a.mbt:10:5 ]
 10 │   bad()
    │    ╰─ Value not found
Error: failed when checking project
"""

LEDGER_GOOD = """\
## 1. 台账条目

| # | 类型 | 数 | 位置 | 为什么保留 | 复审条件 |
|---|---|---|---|---|---|
| L1 | `deprecated` | **1** | `a.mbt:10` | r | c |
| L2 | `unused_value` | **1** | `b.mbt:20` | r | c |

## 2. 覆盖率表

| 类型 | 现算总数 | 台账收录 | 未收录 | 未收录处理 |
|---|---|---|---|---|
| `deprecated` | 1 | 1 | 0 | — |
| `unused_value` | 1 | 1 | 0 | — |
"""

# ★ 变异 1：删掉台账里 b.mbt 的点名 ⇒ L1 必红
LEDGER_MISSING_FILE = LEDGER_GOOD.replace("`b.mbt:20`", "`c.mbt:30`")

# ★ 变异 2：把 deprecated 的总数改错 ⇒ L2 必红
LEDGER_WRONG_COUNT = LEDGER_GOOD.replace(
    "| `deprecated` | 1 | 1 | 0 | — |", "| `deprecated` | 7 | 7 | 0 | — |"
)

# stale：台账记有某类 N 条，现算 0
LEDGER_STALE = LEDGER_GOOD.replace(
    "| `unused_value` | 1 | 1 | 0 | — |", "| `unused_value` | 5 | 5 | 0 | — |"
)
CHECK_NO_UNUSED = CHECK_GOOD.replace(
    """Warning: [0001]
    ╭─[ /r/src/b.mbt:20:4 ]
 20 │ fn dead() {}
    │    ╰─ Warning (unused_value): Unused function 'dead'
""", "").replace("49 warnings", "48 warnings")

# ★ 判例-30 自检：台账里放一段「示例表格」，判据不许把它当条目
LEDGER_WITH_EXAMPLE = LEDGER_GOOD.replace(
    "## 2. 覆盖率表",
    """## 1.5 示例（**这是文档，不是条目**）

| # | 类型 | 数 | 位置 |
|---|---|---|---|
| EX | `deprecated` | **99** | `zzz.mbt:1` |

## 2. 覆盖率表""",
)


def _measure(check_text: str, ledger_text: str) -> tuple[int, dict]:
    actual, ok = parse_check_output(check_text)
    if not ok:
        return RC_CANNOT, {"note": "编译红 / 无 `0 errors` ⇒ 拒绝出结论"}
    cov, ment, errs = parse_ledger(ledger_text)
    if errs:
        return RC_CANNOT, {"note": "台账格式解析失败：" + "；".join(errs)}
    if not actual and sum(cov.values()) > 0:
        return RC_CANNOT, {"note": "现算 0 条 warning 但台账记有 N 条 ⇒ 口径不一致，拒绝出结论"}
    r = judge(actual, cov, ment)
    bad = bool(r["uncovered_files"] or r["count_mismatch"] or r["stale_types"])
    return (RC_VIOLATION if bad else RC_OK), r


def selftest() -> int:
    cases = []

    def case(name, fn, want):
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001
            got = f"EXC:{e}"
        cases.append((name, got, want))

    case("clean-ledger-is-rc0",
         lambda: _measure(CHECK_GOOD, LEDGER_GOOD)[0], RC_OK)
    # ★ 变异 1
    case("MUT-missing-file-goes-red",
         lambda: _measure(CHECK_GOOD, LEDGER_MISSING_FILE)[0], RC_VIOLATION)
    # ★ 变异 2
    case("MUT-wrong-count-goes-red",
         lambda: _measure(CHECK_GOOD, LEDGER_WRONG_COUNT)[0], RC_VIOLATION)
    case("stale-entry-goes-red",
         lambda: _measure(CHECK_NO_UNUSED, LEDGER_STALE)[0], RC_VIOLATION)
    case("compile-red-is-rc2",
         lambda: _measure(CHECK_RED, LEDGER_GOOD)[0], RC_CANNOT)
    # 判例-30：文档里的示例表不许被当成条目（示例写 `zzz.mbt`，若被当真则 b.mbt 未覆盖）
    case("example-table-not-counted-as-entry",
         lambda: _measure(CHECK_GOOD, LEDGER_WITH_EXAMPLE)[0], RC_OK)
    # 明细断言：MUT-missing-file 必须**点名** b.mbt
    def _names_missing():
        _rc, r = _measure(CHECK_GOOD, LEDGER_MISSING_FILE)
        return [p for (_t, p, _l) in r["uncovered_files"]]
    case("MUT-missing-file-names-it", _names_missing, ["src/b.mbt"])
    # ★ 回归格（本单实测踩到的真 bug）：4 个同名 `moon.pkg` 不许塌成 1 个
    def _pkg_not_collapsed():
        check = """Error: [0029]
   ╭─[ /r/src/aaa/moon.pkg:2:3 ]
 2 │   "x",
   │    ╰─ Warning (unused_package): Unused package 'x'
Error: [0029]
   ╭─[ /r/src/bbb/moon.pkg:3:3 ]
 3 │   "y",
   │    ╰─ Warning (unused_package): Unused package 'y'
Finished. moon: ran 3 tasks, up to date (9 warnings, 0 errors)
"""
        # 台账只点名 aaa，bbb 必须被判未覆盖
        ledger = """| # | 类型 | 数 | 位置 | 为什么 | 复审 |
|---|---|---|---|---|---|
| L1 | `unused_package` | **2** | `aaa/moon.pkg:2` | r | c |

| 类型 | 现算总数 | 台账收录 | 未收录 | 未收录处理 |
|---|---|---|---|---|
| `unused_package` | 2 | 2 | 0 | — |
"""
        rc, r = _measure(check, ledger)
        return (rc, [p for (_t, p, _l) in r["uncovered_files"]])
    case(
        "pkg-same-name-not-collapsed",
        _pkg_not_collapsed,
        (RC_VIOLATION, ["src/bbb/moon.pkg"]),
    )

    # ★ 同位置两条 warning（统帅实测抓出的「分母偏小」缺陷的锁）：
    #   台账记 `deprecated` 1 条，现算 **2 块**（同位置）⇒ L2 必须报数量不符 ⇒ rc=1。
    #   ⚠️ 若判据按 (类型,文件:行) 去重，这里会得 1 == 1 ⇒ **假绿**。
    def _dup_pos_reports_mismatch():
        rc, r = _measure(CHECK_DUP_POS, LEDGER_GOOD)
        return (rc, [t for (t, _lv, _nv) in r["count_mismatch"]])

    case(
        "same-position-two-warnings-not-merged",
        _dup_pos_reports_mismatch,
        (RC_VIOLATION, ["deprecated"]),
    )

    # 同一份样本：L1 (类型,文件) 只有一个组合 ⇒ 覆盖率仍按去重算 = 1/1
    def _dup_pos_l1_still_full():
        _rc, r = _measure(CHECK_DUP_POS, LEDGER_GOOD)
        return (r["covered_combos"], r["total_combos"])

    case("same-position-l1-still-deduped", _dup_pos_l1_still_full, (1, 1))

    # 台账解析不出 §2 ⇒ rc=2
    case("no-cov-table-is-rc2",
         lambda: _measure(CHECK_GOOD, "## 什么都没有\n")[0], RC_CANNOT)
    # 真实 `moon check` 输出（新鲜样本标定，判例-32）：能让解析器认出至少 deprecated
    def _calibrate_on_real():
        txt = run_moon_check()
        if "0 errors" not in txt:
            return "SKIP"
        actual, ok = parse_check_output(txt)
        return ok and "deprecated" in actual
    case("calibrate-on-real-moon-check", _calibrate_on_real, True)

    ok_n = 0
    for name, got, want in cases:
        good = got == want or (want is True and got == "SKIP")
        ok_n += 1 if good else 0
        print(f"  [{'OK' if good else 'FAIL'}] {name:<40} got={got} want={want}")
    print(f"\n[selftest] {ok_n}/{len(cases)} 格通过")
    return 0 if ok_n == len(cases) else 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    # R199：**未知旗标必须拒绝**（rc=2），不许静默忽略。
    # 病象与 R197/R198 修过的两把尺同族：拼错 `--selftest`（例如 `--self-test`）会被吃下，
    # 然后**照跑真检查并回 rc=0** ⇒ 看起来"自检通过"，实际跑的是对真台账的扫描。
    # 判据 `check_arg_face_strict` 就是为这一族立的；带值旗标（`--ledger X` / `--check-output X`）的白名单只放旗标名。
    _KNOWN = ("--selftest", "--list", "--ledger", "--check-output")
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN]
    if unknown:
        print(
            "[FATAL] 未知参数 %s —— 已知：%s（rc=2）" % (" ".join(unknown), " / ".join(_KNOWN))
        )
        return 2
    if "--selftest" in argv:
        return selftest()

    ledger = DEFAULT_LEDGER
    if "--ledger" in argv:
        ledger = argv[argv.index("--ledger") + 1]

    if "--check-output" in argv:
        cf = argv[argv.index("--check-output") + 1]
        if not os.path.isfile(cf):
            print(f"[FATAL] 找不到 check 输出文件: {cf}")
            return RC_CANNOT
        check_text = read(cf)
    else:
        check_text = run_moon_check()

    if not os.path.isfile(ledger):
        print(f"[FATAL] 找不到台账: {ledger} ⇒ rc=2")
        return RC_CANNOT

    rc, r = _measure(check_text, read(ledger))
    if rc in (RC_CANNOT, RC_BROKEN):
        render(rc, r, r.get("note", ""))
        return rc

    if "--list" in argv:
        for ty, path, line in r["uncovered_files"]:
            print(f"UNCOVERED ({ty}) {path}:{line}")
        for ty, lv, nv in r["count_mismatch"]:
            print(f"COUNT {ty}: ledger={lv} actual={nv}")
        for ty, n in r["stale_types"]:
            print(f"STALE {ty}: ledger={n} actual=0")
        return RC_VIOLATION if (
            r["uncovered_files"] or r["count_mismatch"] or r["stale_types"]
        ) else RC_OK

    bad = bool(r["uncovered_files"] or r["count_mismatch"] or r["stale_types"])
    render(RC_VIOLATION if bad else RC_OK, r)
    return RC_VIOLATION if bad else RC_OK


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 —— 判据自己坏了要报 rc=4，不许冒用 1
        print(f"[BROKEN] 判据自身异常: {e} ⇒ rc=4")
        sys.exit(RC_BROKEN)
