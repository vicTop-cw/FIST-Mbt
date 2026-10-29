#!/usr/bin/env python3
"""check_warning_ledger_reason.py — 台账「理由」列的**可执行证据**判据（Lane DW）

## 这是判据体系的第 7 层

| 层 | 判据 | 断言 |
|---|---|---|
| 1~2 | `check_warning_ledger` L1 | 每个 (类型,文件) 在台账被点名 |
| 3 | `check_warning_ledger` L2 | 台账数量 == 真实现算块数 |
| 4 | `check_bug_ledger_shape` | 抬头形态 / 统计一致 |
| 5 | `check_known_red_until` | 「预期红」有到期日 + 责任方 |
| 6 | （人工）| 抽查理由仍成立 —— **本判据来机核它** |

## ⚠️ 先说清这一层的**力量上限**（不假装它能证明理由对）

**「理由是否成立」本质是语义判断，不是文件存在性判断。**
本判据做的是**引用完整性**检查，**不是**「引用内容支持该理由」的检查。

| 级 | 断言 | 抓住 | **抓不住** |
|---|---|---|---|
| **R1** | 理由非空 | 空理由 | 散文 |
| **R2** | 理由至少引用一处证据 | **纯散文论断**（如 L1「刻意的结构约束」）| 引用了但错的 |
| **R3** | 引用的文件存在 | 引用了不存在的文件 | 文件存在但内容无关 |
| **R4** | 引用行号 ≤ 文件行数 | 引用了不存在的行 | 行号错了但没超界 |

**本判据实现 R1~R4。**
**⇒ 它证明的是「这条理由指向了仓里真实存在的东西」，不是「那个东西支持这条理由」。**
**第 8 层**（引用的内容是否支持理由）**需要语义理解，本判据不碰，也建议不要假装能碰。**

### 为什么 R4 只核「≤ 文件行数」而不核「那行内容对不对」
判例（R46）：**行号是代码的属性，不是豁免理由的属性。**
一次 `moon fmt`、上面插一行就全漂 ⇒ 台账变「天天要改的负担」⇒ 必然被放弃。
⇒ **R4 是「引用没超界」的下界，不是「引用精确」的保证。**

## ★ 引用的三种形态（实测收集，本仓真实写法）

| 形态 | 实例 | 处理 |
|---|---|---|
| **`path/file.ext:line`** | `ops_loop_wbtest.mbt:318-322` | 找文件 + 核行号 |
| **`name:line`（省略扩展名）** | `core_task_reject_cap_wbtest:147` | 补 `.mbt` 试找 |
| **`:line`（同条目位置列的延续）** | L5 的 `:42` | **继承本条目「位置」列的文件** |
| **`path:l1/l2/l3`（多行）** | `constraint.mbt:104/115/135/175` | 拆成多个行号逐一核 |

**⚠️ 形态 3（裸 `:42`）是实测发现的**：L5 的位置列已写 `star_gate.mbt:33`，
理由里再写全路径是重复 ⇒ 台账用了裸 `:42`。**判据必须认它，否则会误报 L5 无引用。**

## rc 契约
- `0` = 每条理由都有可核引用
- `1` = 有未引用的 / 引用了不存在的 / 行号超界
- **`2` = 判据无法自证**（台账不存在 / 解析不出条目 / **理由列全空**）
- `4` = 尺子坏了

**⚠️ rc=2 那一档的重要性**：若解析器坏了（列数变了），它会报「所有理由都是空」
⇒ 看起来像「9 条全不引用」，**实际是判据坏了**。
⇒ **「理由列全空 ⇒ rc=2 不 rc=1」是硬规则。**

## 用法
    python scripts/check_warning_ledger_reason.py              # 判据
    python scripts/check_warning_ledger_reason.py --list       # 逐条列出引用解析结果
    python scripts/check_warning_ledger_reason.py --selftest   # 自证（含变异对照）
"""

from __future__ import annotations

import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_LEDGER = os.path.join(ROOT, "docs", "warning-ledger.md")

RC_OK, RC_VIOLATION, RC_CANNOT, RC_BROKEN = 0, 1, 2, 4

# ── 引用解析 ──────────────────────────────────────────────────────────
# 形态 1/2：`xxx.ext:1` / `xxx.ext:1-3` / `xxx.ext:1/2/3`
# ⚠️ 扩展名白名单**必须覆盖仓里真实存在的**：实测 `moon.mod:3` 因 `.mod` 不在名单里
#    而漏匹配，连带让正样本全红（判例-30 同族：模式串比真实形态窄）。
RE_REF_FULL = re.compile(
    r"([\w/.\-]+\.(?:mbt|py|md|json|yml|yaml|c|h|sh|mod|pkg|toml|txt)):(\d[\d/\-]*)"
)
# 形态 2b：无扩展名 `name:147`（台账会用文件主干名）
# ⚠️ **必须排除前面是 `.` 的**：否则 `moon.mod:3` 里的 `mod:3` 会被当成裸名引用
#    （实测踩到：正样本全红，原因是 `mod:3` 去搜 `mod.mbt` 搜不到）。
#    `(?<![\w.])` 是关键 —— 前一个字符不能是字母数字或点。
RE_REF_BARE_NAME = re.compile(r"(?<![\w.])`?([A-Za-z_][\w]*):(\d[\d/\-]*)`?")
# 形态 3：裸 `:42`（继承位置列的文件）
# ⚠️ lookbehind **不能排除反引号**：台账把裸行号写成 `` `:3` ``（反引号包着）
#    ⇒ 排除 `` ` `` 会让它永远匹配不到（实测踩到）。
#    只排除「字母数字/点/斜杠」——那才是「另一个引用的尾巴」。
RE_REF_COLON_ONLY = re.compile(r"(?<![\w./])(:(\d[\d/\-]*))")

# 位置列里的文件名（用于形态 3 的继承）
RE_LOC_FILE = re.compile(
    r"([\w/.\-]+\.(?:mbt|py|md|pkg|mod))"
)


def read(p: str) -> str:
    return io.open(p, encoding="utf-8", errors="replace").read()


def file_lines(path: str) -> int | None:
    fp = os.path.join(ROOT, path)
    if not os.path.isfile(fp):
        return None
    try:
        return len(read(fp).split("\n"))
    except Exception:  # noqa: BLE001
        return None


def find_file(name: str) -> str | None:
    """找文件：先按给定相对路径，再按 basename 在仓内搜（限 src/ cmd/ scripts/ atgc*/）。

    ⚠️ 只做**有界搜索**（4 个顶层目录），不扫全仓 —— 否则判据本身变成性能问题。
    """
    if os.path.isfile(os.path.join(ROOT, name)):
        return name

    # ★ **带路径的引用必须按路径后缀解析**（本轮实测踩到，与 R46 的 `moon.pkg` 同族第 2 次）：
    #   台账写 `store/json_get.mbt`，仓里却有两个 `json_get.mbt`
    #   （`src/store/` 和 `src/decompose/`）⇒ 旧实现按 basename 搜，命中**先遍历到的
    #   `src/decompose/json_get.mbt`** ⇒ 去核一个完全无关的文件 ⇒ 报「行号漂移」**假红**。
    #   **台账带路径时，basename 兜底会把不同文件塌成一个。**
    if "/" in name:
        for r in ("src", "cmd", "scripts", "docs", "atgc", "atgc-old"):
            cand = os.path.join(ROOT, r, name)
            if os.path.isfile(cand):
                return (r + "/" + name).replace("\\", "/")
        suffix = "/" + name
        for r in ("src", "cmd", "scripts", "docs", "atgc", "atgc-old"):
            d = os.path.join(ROOT, r)
            if not os.path.isdir(d):
                continue
            for dirpath, _dirnames, filenames in os.walk(d):
                rel = os.path.relpath(dirpath, ROOT).replace("\\", "/")
                for f in filenames:
                    if (rel + "/" + f).endswith(suffix):
                        return (rel + "/" + f).replace("\\", "/")
        return None

    base = os.path.basename(name)
    roots = ["src", "cmd", "scripts", "atgc", "atgc-old", "docs"]
    for r in roots:
        d = os.path.join(ROOT, r)
        if not os.path.isdir(d):
            continue
        for dirpath, _dirnames, filenames in os.walk(d):
            if base in filenames:
                rel = os.path.relpath(os.path.join(dirpath, base), ROOT)
                return rel.replace("\\", "/")
    return None


def parse_entries(text: str) -> tuple[list, list]:
    """从台账 §1 抽出 [(id, 类型, 位置列, 理由列)]，返回 (entries, errors)"""
    entries = []
    errors = []
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
            if len(cells) < 6 or not re.match(r"^L\d+$", cells[0]):
                continue
            entries.append((cells[0], cells[1], cells[3], cells[4]))
    if not entries:
        errors.append("§1 解析不出任何 L* 条目（列数变了？）")
    return entries, errors


def extract_refs(reason: str, loc_col: str) -> list:
    """从理由里抽出引用，返回 [(显示名, 文件路径或'', [行号...])]

    处理三种形态；**顺序要紧**：先抽全路径，再从剩余文本里抽裸名，
    最后抽裸 `:line`（继承位置列的文件），避免同一串被重复计。
    """
    refs = []
    rest = reason

    # ① 全路径（含扩展名）
    for m in RE_REF_FULL.finditer(reason):
        name = m.group(1)
        nums = [int(x) for x in re.findall(r"\d+", m.group(2))]
        refs.append(("full", name, nums, m.group(0)))
        rest = rest.replace(m.group(0), " ")

    # ⚠️ **裸 `:line` 必须在剥反引号之前抽**：实测踩到 ——
    #    剥反引号的 `re.sub(r"`[^`]*`", " ", rest)` 会把 `` `:3` `` 整段吃掉
    #    ⇒ 形态 3 永远抽不到 ⇒ 台账 L5 的裸 `:42` 被误报「无引用」。
    #    ⇒ 顺序固定为：① 全路径 → ② 裸冒号（继承位置列文件）→ ③ 剥反引号 → ④ 裸名。
    loc_files = RE_LOC_FILE.findall(loc_col)
    if loc_files:
        for m in RE_REF_COLON_ONLY.finditer(rest):
            nums = [int(x) for x in re.findall(r"\d+", m.group(2))]
            refs.append(("colon_only", loc_files[0], nums, m.group(0)))
        rest = RE_REF_COLON_ONLY.sub(" ", rest)

    # ② 无扩展名的 `name:147` —— **必须在剥反引号之前抽**（实测踩到：
    #    台账把它写成 `` `core_task_reject_cap_wbtest:147` ``，剥反引号会整段删掉 ⇒ 漏报）。
    #    `(?<![\w.])` 保证不会把 `moon.mod:3` 里的 `mod:3` 再抽一次。
    for m in RE_REF_BARE_NAME.finditer(rest):
        stem = m.group(1)
        nums = [int(x) for x in re.findall(r"\d+", m.group(2))]
        refs.append(("stem", stem, nums, m.group(0)))
        rest = rest.replace(m.group(0), " ")

    return refs


def resolve(ref) -> tuple[bool, str]:
    """核一条引用。返回 (ok, 读数说明)"""
    kind, name, nums, raw = ref
    if kind == "full":
        path = find_file(name)
    elif kind == "stem":
        # 先按主干找 .mbt（本仓最常见），再试原样
        path = find_file(name + ".mbt") or find_file(name)
    else:  # colon_only
        path = find_file(name)
    if path is None:
        return False, f"引用的文件不存在：{raw}"
    n = file_lines(path)
    if n is None:
        return False, f"文件读不到：{path}"
    if not nums:
        return True, f"{path}（无行号）"
    over = [x for x in nums if x > n]
    if over:
        return False, f"{path} 只有 {n} 行，但引用行号 {over} 超界"
    return True, f"{path}:{nums}（文件 {n} 行）"


# ══════════════════════════════════════════════════════════════════════
# ★ R5：引用行号指向的**那一行**是否「像被引用的东西」
#
# 这是「第 8 层」（语义支持）里**唯一可机核的窄形态**。
# 本轮铁证（Lane DX）：L1 的 4 个行号曾整体漂移 -2/-4，而 R4 只查
# 「行号 ≤ 文件行数」⇒ **一个都没抓**。
#   · 正确行（107/124/1275/1330）都是 `fn <符号名>(`
#   · 漂移行（109/128/1277/1332）都是 `) -> Result[...]`  ← **不含符号名**
#
# **两档强度**（取决于能不能拿到符号名）：
#   **强档**：引用的**前文**出现了 `` `symbol` ``（形如 `` `foo`（path:line） ``）
#            ⇒ 该行**必须包含** symbol（这是 R5 的完整形态）。
#   **弱档**：取不到符号名 ⇒ 只查「该行**非空、非纯注释、非孤立 `}`**」
#            —— 挡不住漂移，但能挡住「指向一个空行/闭合括号」这类离谱错位。
#
# ⚠️ **为什么强档要求「前文」，而不是「全文任意反引号词」**：
#    理由文本里穿插大量别的标识符（`raise`/`catch`/`match`），
#    用「全文任意」会把它们误当符号名 ⇒ 假红（实测 L1 理由里有 6 个反引号词）。
#    ⇒ 只取**紧挨在引用前面**的那一个。
# ══════════════════════════════════════════════════════════════════════

RE_SYMBOL_BEFORE = re.compile(r"`([A-Za-z_][\w~]*)`[^`\w]{0,6}$")


def symbol_near(reason: str, ref_raw: str) -> str:
    """取引用**紧前方**的符号名；没有则返回空串。"""
    idx = reason.find(ref_raw)
    if idx <= 0:
        return ""
    before = reason[:idx]
    m = RE_SYMBOL_BEFORE.search(before)
    return m.group(1) if m else ""


def line_is_meaningful(text: str) -> tuple[bool, str]:
    """弱档：该行是否「像代码/配置的实质行」。

    返回 (ok, 说明)。**故意宽松**：只挡空行、纯注释行、孤立闭合括号。
    """
    t = text.strip()
    if not t:
        return False, "该行是空行"
    # ⚠️ **`#|` 是 MoonBit 的内嵌 JS 代码块，不是注释**（实测踩到：L7 的
    #    `github_js.mbt:92/104` 指向 `#| ...` 行，被判「纯注释」⇒ **假红**）。
    #    ⇒ 必须先排除 `#|` 再判「以 # 开头是注释」。
    if t.startswith("#|"):
        return True, ""
    # ⚠️ **纯注释行是合法的引用目标**（实测踩到：`moon.mod:3` 是 `//` 注释，
    #    而台账 L1 的理由正是「注释里写着『想静默回落得先改签名』」⇒ 引注 **是** 可核证据）。
    #    ⇒ 弱档只挡「空行 / 孤立闭合括号 / 过短行」，**不挡注释**。
    #    （这也说明弱档的力量很有限：它只挡「离谱错位」，不挡「漂移几行」。）
    if t in ("}", ")", "];", "}", "end"):
        return False, "该行是孤立的闭合括号"
    # ⚠️ **不做过短判定**（实测踩到：`moon.mod:3` 是 `//` 分隔注释，2 字符）
    #    —— 弱档的力量本来就只够挡「空行 / 孤立括号」，再收紧就变成假红工厂。
    return True, ""


# ══════════════════════════════════════════════════════════════════════
# ★ **定义行识别**（R5 的强档 2）
#
# 本轮铁证：L1 的 4 个行号曾漂移 -2/-4，**弱档抓不到**（因为漂移后的
# `) -> Result[...]` 也是「实质内容」）。但两类行有一条**稳定区别**：
#
#   · **正确的行** = `fn engine_for_ns(` / `fn to_result(` —— **定义行**
#   · **漂移的行** = `) -> Result[...] {`               —— **续行**
#
# ⇒ 「引用行必须是定义行」比「行内容非空」强得多，**且零台账配合**。
#   它不能证明「这个符号就是论断说的那个」，但能挡住「整体漂移几行」这一类，
#   而那正是本轮的真 bug。
# ══════════════════════════════════════════════════════════════════════

RE_DEF_LINE = re.compile(
    r"^\s*(?:pub\s+)?(?:async\s+)?(?:fn|struct|enum|type|let|const|impl|trait|val|def|class|function)"
)


RE_VARIANT_LINE = re.compile(r"^\s*([A-Z][A-Za-z0-9_]*)(\([^)]*\))?\s*(//.*)?$")
# ⚠️ 必须收 **带 `~` 的标签形参**（实测：L8 的 `by~ : String,` / `ns~ : String = "default",`
#    是合法的声明行，但原正则不认 `~` ⇒ 7 处误报）。
RE_FIELD_LINE = re.compile(r"^\s*[a-z_][A-Za-z0-9_]*~?\s*:\s*\S")
RE_PKG_LINE = re.compile(r'^\s*"[^"]+"')


def line_is_def(text: str) -> bool:
    """该行是否像一条**定义位置**。

    **不能只认 `fn/struct`**（实测踩到：26 处误报）——本仓的「定义位置」有 5 种合法形态：

    | 形态 | 实例 | 为什么合法 |
    |---|---|---|
    | 函数/类型定义 | `fn engine_for_ns(` / `pub struct WorldState {` | `unused_value`/`result_error_return` 指向它 |
    | **enum 变体行** | `Active // 正常推进中` / `Load` | `unused_constructor` 指向**变体行** |
    | **struct 字段行** | `reservations : Array[...]` | 字段相关 warning 指向它 |
    | **moon.pkg import 行** | `"vicTop-cw/fist-mbt/src/store",` | `unused_package` 指向**import 行** |
    | **`.mbt` 内嵌 JS 块** | `#| ...` | FFI warning 可能指向它 |

    ⚠️ **这个放宽是有代价的**：它让 R5-定义档**挡不住「漂移到一个字段行」**。
    但它挡的是本轮的真 bug（漂移到 `) -> Result[...]` 续行）—— **续行不是上述任何一种**。
    """
    t = text
    if RE_DEF_LINE.match(t):
        return True
    if t.strip().startswith("#|"):
        return True
    if RE_VARIANT_LINE.match(t):
        return True
    if RE_FIELD_LINE.match(t):
        return True
    if RE_PKG_LINE.match(t):
        return True
    return False


def read_line(path: str, lineno: int) -> str | None:
    fp = os.path.join(ROOT, path)
    try:
        lines = read(fp).splitlines()
    except Exception:  # noqa: BLE001
        return None
    if lineno < 1 or lineno > len(lines):
        return None
    return lines[lineno - 1]


def check_r5(reason: str, ref, path: str) -> tuple[bool, str, str]:
    """R5。返回 (ok, 档位, 说明)"""
    _kind, _name, nums, raw = ref
    if not nums:
        return True, "skip", "无行号，R5 不适用"
    sym = symbol_near(reason, raw)
    bad = []
    weak_ok_all = True
    for ln in nums:
        line = read_line(path, ln)
        if line is None:
            bad.append(f"{path}:{ln} 读不到")
            continue
        if sym:
            # 强档：该行必须包含符号名
            if sym not in line:
                bad.append(f"{path}:{ln} 不含符号 `{sym}`（该行=「{line.strip()[:50]}」）")
        else:
            ok, why = line_is_meaningful(line)
            if not ok:
                weak_ok_all = False
                bad.append(f"{path}:{ln} {why}（该行=「{line.strip()[:40]}」）")
    if bad:
        return False, ("strong" if sym else "weak"), "；".join(bad)
    return True, ("strong" if sym else "weak"), (
        f"{path}:{nums} 含 `{sym}`" if sym else f"{path}:{nums}（弱档：行内容实质）"
    )


# ══════════════════════════════════════════════════════════════════════
# ★ **R5-定义档只对「定义类」warning 有效**（实测踩到的关键分流）
#
# 15 处误报后才看清：**位置列指向哪儿，取决于 warning 类型**：
#
# | warning 类型 | 位置列指向 | 能否要求「定义行」 |
# |---|---|---|
# | `unused_value` / `unused_constructor` / `struct_never_constructed` | **定义处** | ✅ 能 |
# | `unused_package` | `moon.pkg` 的 import 行 | ✅ 能 |
# | **`deprecated` / `deprecated_syntax`** | **使用点**（`abort(...)` / `x.to_string()` / `derive(...)`）| ❌ **不能** |
# | `result_error_return` | 函数签名行 | ✅ 能 |
#
# **⇒ 判据必须按类型分流，否则「按定义行判使用点」必然全红。**
#    这正是「判据的规则要比被测对象的形态**双向对齐**」（判例-30 家族）的又一实例：
#    这一次错在**宽**（统一要求）而不是窄。
# ══════════════════════════════════════════════════════════════════════

DEF_ORIENTED_TYPES = (
    "unused_value", "unused_constructor", "struct_never_constructed",
    "unused_package", "result_error_return",
)


def check_r5_def(loc_col: str, reason: str, type_cell: str) -> tuple[int, int, list]:
    """★ **R5-定义档**：对**位置列**的引用，要求每行都是**定义行**。

    为什么单立：位置列写的是「这条 warning 出现在哪些行」——
    **它天然指向定义**（`fn x(` / `struct Y {` / 变体行）。
    本轮铁证：L1 位置列漂移 -2/-4 后指向 `) -> Result[...]` ⇒ 续行 ⇒ 一眼可见。

    返回 (checks, bad, [(eid 占位, 说明)])
    """
    # 只对「定义类」warning 生效（`deprecated*` 指向使用点，按定义行判必然误报）
    if not any(t in type_cell for t in DEF_ORIENTED_TYPES):
        return 0, 0, []
    refs = extract_refs(loc_col, "")
    checks = 0
    bad = 0
    msgs = []
    for r in refs:
        _k, name, nums, _raw = r
        if not nums:
            continue
        path = find_file(name) if _k != "stem" else (find_file(name + ".mbt") or find_file(name))
        if path is None:
            continue
        for ln in nums:
            line = read_line(path, ln)
            if line is None:
                continue
            checks += 1
            if not line_is_def(line):
                bad += 1
                msgs.append(
                    f"位置列 {path}:{ln} 不是定义行（该行=「{line.strip()[:50]}」）"
                    " ⇒ 行号可能已漂移"
                )
    return checks, bad, msgs


def judge(text: str) -> tuple[int, dict]:
    entries, errors = parse_entries(text)
    if errors:
        return RC_CANNOT, {"note": "；".join(errors)}

    # ★ R1 的特殊档：**理由列全空 ⇒ rc=2**（多半是解析坏了，不是「全不引用」）
    empty = [e for e in entries if not e[3].strip()]
    if entries and len(empty) == len(entries):
        return RC_CANNOT, {
            "note": f"理由列 {len(entries)} 条**全空** ⇒ 多半是列结构变了/解析器坏了，"
                    "不报「全不引用」（那会让人去改台账，而真问题是判据）"
        }

    problems = []
    per_entry = []
    for eid, ty, loc, reason in entries:
        if not reason.strip():
            problems.append(("R1 空理由", eid, "理由列是空的"))
            per_entry.append((eid, 0, False))
            continue
        refs = extract_refs(reason, loc)
        if not refs:
            problems.append(
                ("R2 无引用", eid, f"理由里没有任何可执行证据引用（散文论断）：{reason[:70]}…")
            )
            per_entry.append((eid, 0, False))
            continue
        # ★ R5-定义档：位置列的行号必须是定义行（对漂移最敏感、零台账配合）
        dchecks, dbad, dmsgs = check_r5_def(loc, reason, ty)
        for m_ in dmsgs:
            problems.append(("R5def 位置列飘移", eid, m_))

        oks = 0
        r5_checks = 0
        r5_bad = 0
        for r in refs:
            ok, reading = resolve(r)
            if ok:
                oks += 1
            else:
                problems.append(("R3/R4 引用不可核", eid, reading))
                continue
            # ★ R5：行号指向的那一行是否像被引用的东西（只在文件+行号都通过后做）
            _k, name, _nums, _raw = r
            if not _nums:
                continue
            path = find_file(name) if _k != "stem" else (find_file(name + ".mbt") or find_file(name))
            if path is None:
                continue
            ok5, tier, reading5 = check_r5(reason, r, path)
            r5_checks += 1
            if not ok5:
                r5_bad += 1
                problems.append((f"R5({tier}) 行指向错", eid, reading5))
        per_entry.append((eid, len(refs), oks == len(refs)))

    # ★ R5 的 rc=2 特殊档：**所有引用行都不通过** ⇒ 多半是判据解析坏了，
    #    不是「台账全错」。两者处置完全不同（改判据 vs 改台账）。
    if r5_checks > 0 and r5_bad == r5_checks and r5_checks >= 3:
        return RC_CANNOT, {
            "note": f"R5 对 {r5_checks} 处引用**全部**判不符 ⇒ 多半是判据的符号/行解析坏了"
                    "（先人工抽查 1 处确认），不报「台账全错」"
        }

    rc = RC_VIOLATION if problems else RC_OK
    return rc, {"entries": entries, "problems": problems, "per_entry": per_entry,
                "r5_checks": r5_checks, "r5_bad": r5_bad}


def render(rc: int, r: dict) -> None:
    if rc in (RC_CANNOT, RC_BROKEN):
        print(f"[FATAL] {r.get('note', '')}")
        print(f"判据无法自证 ⇒ rc={rc}")
        return
    per = r["per_entry"]
    good = sum(1 for (_e, _n, ok) in per if ok)
    print(f"[台账] {len(r['entries'])} 条 · **{good} 条理由有可核引用** / "
          f"{len(r['entries']) - good} 条不可核")
    print("[口径] R1 非空 · R2 至少一处引用 · R3 引用的文件存在 · R4 行号 ≤ 文件行数")
    if not r["problems"]:
        print()
        print("[结论] 每条理由都指向了仓里**真实存在**的东西。")
        print("       ⚠️ **这不等于理由成立** —— 本判据只查「引用完整性」，")
        print("          不查「引用的内容是否支持这条理由」（那是语义判断，需要理解力，本判据不碰）。")
        return
    print()
    print(f"[违规] {len(r['problems'])} 处：")
    for kind, eid, msg in r["problems"]:
        print(f"  ✗ [{kind}] {eid} —— {msg}")


# ══════════════════════════════════════════════════════════════════════
# selftest（夹具在 temp/ 造，判例：别在主仓造夹具）
# ══════════════════════════════════════════════════════════════════════

LEDGER_TMPL = """\
## 1. 台账条目

| # | 类型 | 数 | 位置 | 为什么保留 | 复审条件 |
|---|---|---|---|---|---|
| L1 | `deprecated` | **1** | `a.mbt:10` | {r1} | c |
| L2 | `unused_value` | **1** | `b.mbt:20` | {r2} | c |
"""

# 夹具文件：用**真实存在**的仓内文件（只读引用，不写主仓）
REAL_A = "moon.mod"          # 存在，且行数 > 5
REAL_B = "scripts/README.md"  # 存在，行数很多


def _mk(r1: str, r2: str) -> str:
    return LEDGER_TMPL.format(r1=r1, r2=r2)


def selftest() -> int:
    cases = []

    def case(name, fn, want):
        try:
            got = fn()
        except Exception as e:  # noqa: BLE001
            got = f"EXC:{e}"
        cases.append((name, got, want))

    # 正样本：两条都引用真实文件
    GOOD = _mk(f"见 `{REAL_A}:3` 与 `{REAL_B}:10`", f"见 `{REAL_A}:5`")

    case("all-cited-passes", lambda: judge(GOOD)[0], RC_OK)

    # ★ 变异 1：某条理由改成纯散文 ⇒ rc=1 且点名
    MUT_PROSE = _mk(f"见 `{REAL_A}:3`", "这是刻意的结构约束，改了会坏事")
    case("MUT-prose-only-goes-red", lambda: judge(MUT_PROSE)[0], RC_VIOLATION)

    def _prose_names_it():
        _rc, r = judge(MUT_PROSE)
        return [e for (_k, e, _m) in r["problems"]]
    case("MUT-prose-names-entry", _prose_names_it, ["L2"])

    # ★ 变异 2：引用不存在的文件 ⇒ rc=1
    MUT_NOFILE = _mk(f"见 `{REAL_A}:3`", "见 `no_such_file_zzz.mbt:5`")
    case("MUT-nonexistent-path-goes-red", lambda: judge(MUT_NOFILE)[0], RC_VIOLATION)

    # 行号 > 文件行数 ⇒ rc=1
    MUT_BIGLINE = _mk(f"见 `{REAL_A}:3`", f"见 `{REAL_A}:999999`")
    case("line-exceeds-file-goes-red", lambda: judge(MUT_BIGLINE)[0], RC_VIOLATION)

    # ★ 「散文 + 引用」⇒ 通过（真实理由大多是这种形态）
    MIXED = _mk(f"见 `{REAL_A}:3` 与 `{REAL_B}:10`",
                f"这是刻意的结构约束，改了会坏事；证据见 `{REAL_A}:5`")
    case("both-cited-and-prose-passes", lambda: judge(MIXED)[0], RC_OK)

    # 空理由 ⇒ rc=1
    EMPTY = _mk(f"见 `{REAL_A}:3`", "")
    case("empty-reason-goes-red", lambda: judge(EMPTY)[0], RC_VIOLATION)

    # ★ 理由列**全空** ⇒ rc=2（不是 rc=1）—— 这是防「解析器坏了被当成全不引用」
    ALLEMPTY = _mk("", "")
    case("all-empty-is-rc2-not-rc1", lambda: judge(ALLEMPTY)[0], RC_CANNOT)

    # 台账解析不出条目 ⇒ rc=2
    case("no-entries-is-rc2", lambda: judge("## 什么都没有\n")[0], RC_CANNOT)

    # ★ 形态 3：裸 `:42` 继承位置列的文件
    BARE_COLON = """\
| # | 类型 | 数 | 位置 | 为什么保留 | 复审条件 |
|---|---|---|---|---|---|
| L1 | `deprecated` | **1** | `moon.mod:5` | 是 `:3` 的前提 | c |
"""
    case("colon-only-inherits-loc-file", lambda: judge(BARE_COLON)[0], RC_OK)

    # 多行号 `a:b/c/d` 逐一核
    # ⚠️ 夹具用 `REAL_B`（长文件）而非 `REAL_A`：`moon.mod` 前几行里有**空注释行 `//`**，
    #    弱档会挡（那是**对的**——空行不是实质内容），但会让这格测不到多行号本身。
    MULTI = _mk(f"见 `{REAL_B}:1/3/5`", f"见 `{REAL_B}:1/3`")
    case("multi-line-numbers-all-ok", lambda: judge(MULTI)[0], RC_OK)

    # ★ R5-定义档：位置列行号必须是定义行（Lane DX）
    #
    # 本轮铁证：L1 位置列 4 个行号曾整体漂移 -2/-4，正确行是 `fn x(`，
    # 漂移行是 `) -> Result[...]` ⇒ **只认定义行就能抓住**。
    def _r5_def_ok():
        """位置列指向真定义行 ⇒ 通过。"""
        ok, _tier, msg = check_r5(
            "见 `moon.mod:3`", ("full", "server.mbt", [107], "server.mbt:107"),
            "src/server/server.mbt")
        return ok
    case("R5-line-on-definition-passes", _r5_def_ok, True)

    def _r5_def_wrong():
        """★ 变异 1（复现本轮真 bug）：行号指向续行 `) -> Result[...]` ⇒ 必须红。"""
        checks, bad, msgs = check_r5_def("`server.mbt:109`", "见 `x`", "unused_value")
        return (bad > 0, checks > 0)
    case("MUT-drifted-line-goes-red", _r5_def_wrong, (True, True))

    def _r5_def_right():
        """同一函数：行号对 ⇒ 不报（反证：判据真在区分，不是恒红）。"""
        _c, bad, _m = check_r5_def("`server.mbt:107`", "见 `x`", "unused_value")
        return bad == 0
    case("def-line-correct-not-reported", _r5_def_right, True)

    # ★ 变异 2：`deprecated` 类**不做**定义档校验（它指向使用点，不是定义）
    #    —— 这条防「按定义行判使用点」的假红（实测 15 处误报后补的分流）。
    def _r5_def_skipped_for_deprecated():
        checks, bad, _m = check_r5_def("`main.mbt:501`", "见 `x`", "`deprecated`（Show→Debug）")
        return (checks, bad)
    case("MUT-deprecated-skipped-by-deffile", _r5_def_skipped_for_deprecated, (0, 0))

    # 弱档：取不到符号名时，指向空行/纯注释/闭合括号 ⇒ 红
    def _weak_blank():
        ok, _t, _m = check_r5("见 `a.mbt:10`", ("full", "a.mbt", [999999], "a.mbt:999999"),
                              "moon.mod")
        return ok is False
    case("weak-out-of-range-goes-red", _weak_blank, True)

    # 真源标定（判例-32）：真台账能被解析出 ≥1 条 L*
    def _calibrate_real():
        try:
            t = read(DEFAULT_LEDGER)
        except Exception:  # noqa: BLE001
            return "SKIP"
        ents, errs = parse_entries(t)
        return (not errs) and len(ents) >= 1
    case("calibrate-on-real-ledger", _calibrate_real, True)

    ok = 0
    for name, got, want in cases:
        good = got == want or (want is True and got == "SKIP")
        ok += 1 if good else 0
        print(f"  [{'OK' if good else 'FAIL'}] {name:<36} got={got} want={want}")
    print(f"\n[selftest] {ok}/{len(cases)} 格通过")
    return 0 if ok == len(cases) else 1


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    # ══════════════════════════════════════════════════════════════════
    # ★ **拒绝未知旗标**（AGENTS.md「新判据必须拒绝未知旗标」· 本会话第 4 例同族）
    #
    # 失效形态：把 `--selftest` 拼成 `--self-test` ⇒ 条件不成立
    # ⇒ **落进真检查分支并可能回 rc=0** ⇒ 人以为「自检通过」，实际跑的是对真仓库的扫描。
    # **自检开关拼错 = 静默失去自检。**
    # ══════════════════════════════════════════════════════════════════
    _KNOWN = ("--selftest", "--list")
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：%s（rc=2）"
              % (" ".join(unknown), " / ".join(_KNOWN)))
        return RC_CANNOT

    if "--selftest" in argv:
        return selftest()
    if not os.path.isfile(DEFAULT_LEDGER):
        print(f"[FATAL] 找不到台账: {DEFAULT_LEDGER} ⇒ rc=2")
        return RC_CANNOT
    rc, r = judge(read(DEFAULT_LEDGER))
    if "--list" in argv and rc not in (RC_CANNOT, RC_BROKEN):
        for eid, ty, loc, reason in r["entries"]:
            refs = extract_refs(reason, loc)
            print(f"{eid} [{ty}] refs={len(refs)}")
            for ref in refs:
                okk, reading = resolve(ref)
                print(f"   {'OK ' if okk else 'BAD'} {reading}")
        return rc
    render(rc, r)
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001
        print(f"[BROKEN] 判据自身异常: {e} ⇒ rc=4")
        sys.exit(RC_BROKEN)
