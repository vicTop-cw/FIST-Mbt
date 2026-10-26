#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/_deployment_symbols.py — 「部署产物是否落后于源码」探针的**单一真源**（符号表 + 名字变形探针）。

BUG-428（high）的现场：修复 commit `72986aa7`（2026-10-26 20:40）落地后，**三份部署产物都是旧代码**，
而 `check_dist_snapshot.py` 打的是 `PASS 快照版本 0.3.10 == moon.mod 0.3.10` —— **版本对得上，代码是旧的**。
后果不是"少跑一格"：调用方被 Omega 门拦下后**误判成「判定逻辑有缺陷」**，花 40 分钟查四个正常条件，
最后靠 A/B 对照才定位到是旧构建。⇒ 需要一把按**内容**判新鲜度的尺。

本模块被两把尺共用（单一真源，避免同一张表抄两份后各自漂移）：
  · `check_deployment_freshness.py`（P0：部署产物 vs 源码，含 mtime 面 + 内容面）
  · `check_dist_snapshot.py`（P1：仓内发布快照，版本面 + 内容面）

## 实测一：MoonBit 的 JS 产物把名字里的 `_` 写成 `__`（**裸 substring 探针会假红**）
2026-10-26 实测，本机**新鲜**的 debug 构建 `_build/js/debug/build/cmd/cli/cli.js`（23:51）：

    grep -c 'omega_orphan_of_archived_parent'        -> 0     # 新鲜产物也是 0！
    grep -cE 'omega_+orphan_+of_+archived_+parent\(' -> 3     # 真身：1 处定义 + 2 处调用点

产物里的标识符长这样（`function _M0FP411vicTop_2dcw10fist_2dmbt3src6engine14<名字>` = 包路径 +
长度前缀 + 名字），**名字内部的 `_` 逐字翻倍** ⇒ `omega_enabled` 在 bundle 里是 `omega__enabled`。
于是 BUG-428 报告里那句「`grep -c omega_orphan_of_archived_parent` == 0 ⇒ 代码是旧的」**结论对、
判据错**：同一发 grep 打在**新鲜**产物上一样是 0。本模块因此一律用容忍 `_`→`__` 的正则
（`name.replace('_', '_+')`），而不是裸字符串。

## 实测二：探针必须命中**调用形**（防止被字符串字面量喂绿）
bundle 里有大量工具名/配置键的**字符串**（`"omega_strong_verify"`、`"omega_spec_create"` …）。
裸 substring 命中一个字符串，等于把"提到过这个名字"当成"这段代码在"。故探针要求命中后紧跟 `(`
—— MoonBit 产出的定义与调用都长这样，而字符串字面量后面跟的是引号/逗号/括号外的分隔符。
残余风险见 `check_deployment_freshness.py` 的「缺口与风险」段：一句恰好写成 `name(` 的文档串仍
可能喂绿；这条用**多符号**（三个不同年代的符号）摊薄，不靠单个名字。
"""
import io
import os
import re

# ---------------------------------------------------------------------------
# 符号表（唯一真源）
# ---------------------------------------------------------------------------
class KeySymbol(object):
    """一条新鲜度探针：`name` 在产物里以调用形出现 ⇒ 产物含这段代码。

    `origin` / `why` 是**维护面**：这条探针什么时候进来的、凭什么值得当探针。没有维护面的探针
    迟早变成"谁都看不懂为什么在这里、没人敢删"的化石（本仓判例-5 同族：接线要有名字）。
    """

    __slots__ = ("name", "origin", "why")

    def __init__(self, name, origin, why):
        self.name = name
        self.origin = origin
        self.why = why

    def __repr__(self):
        return "KeySymbol(%r)" % (self.name,)


# 入选标准（三条都要满足，否则探针会假红）：
#   ① 今天源码里还有 `fn <name>(` 的定义 —— 由 `anchor_problems()` 每次现查，脱锚即 rc=4；
#   ② 从 CLI 入口**可达**（不是死代码）⇒ 产物里留名；MoonBit 会 DCE 掉不可达函数；
#   ③ 名字**稳定**（不是"刚加上就被改名"的一次性中间名），且**不是 MCP 工具名**
#      （工具名在 bundle 里是字符串，与"代码在不在"无关，混进来会污染语义）。
KEY_SYMBOLS = (
    KeySymbol(
        "omega_orphan_of_archived_parent",
        "72986aa7（2026-10-26 20:40，BUG-417 止血 patch A）",
        "BUG-428 的**现场符号**：产物里没有它 ⇒ 构建早于那次修复 ⇒ 归档门误拦会立刻复现。"
        "被 engine 的归档路径调用（engine.mbt / engine_archive_force.mbt 两处），非死代码。",
    ),
    KeySymbol(
        "strip_plan_annotations",
        "e8cf3dca（2026-10-22，plan_deep 标注不再逐层叠乘）",
        "读的是 task_plan_deep 的描述生成路径、5 处调用点，比 BUG-417 老 4 天 ⇒ "
        "用来分辨「落后几天」与「落后几分钟」，也让探针不止盯一个 commit。",
    ),
    KeySymbol(
        "omega_enabled",
        "老符号（≤ 84bddb29 / 2026-10-22 合并面即在产）",
        "**基线对照**：连它都缺 ⇒ 产物不是本仓构建（或老得离谱），与「刚落后一次提交」区分开。"
        "三个符号按年代梯度排布，缺哪个就说明落后到哪个年代。",
    ),
)

# 源码里认作"定义"的形状：`fn NAME(` / `pub fn NAME(` / `pub(open) fn NAME(` …
RE_FN_DEF = r"\bfn\s+%s\s*\("
# 注释行（MoonBit 的 `///` 文档注释与 `//` 行注释）不参与定义判定 —— 判例-30：改坏代码而不是注释。
RE_COMMENT_LINE = re.compile(r"^\s*//")


def name_pattern(name):
    """名字 → 容忍 `_`→`__` 变形的正则片段（`omega_enabled` → `omega_+enabled`）。"""
    return "_+".join(re.escape(part) for part in name.split("_"))


def call_regex(name):
    """调用形探针：`<名字>(`，容忍 `_`→`__` 且允许中间空白。返回编译好的正则。"""
    return re.compile(name_pattern(name) + r"[ \t]*\(")


def count_calls(text, name):
    """产物正文里该符号的**调用形**出现次数。空正文 ⇒ 0（不是"命中"）。"""
    if not text:
        return 0
    return len(call_regex(name).findall(text))


def found_report(text, symbols=KEY_SYMBOLS):
    """逐符号命中次数（保序 dict）。"""
    return dict((s.name, count_calls(text, s.name)) for s in symbols)


def missing_symbols(text, symbols=KEY_SYMBOLS):
    """产物里**一个调用形都没有**的符号名列表（空列表 = 内容面齐全）。"""
    return [s.name for s in symbols if count_calls(text, s.name) == 0]


def read_artifact(path):
    """读产物正文（二进制读 + UTF-8 replace）。读不到 ⇒ None（调用方据此判"无法自证"）。"""
    try:
        with io.open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return None


# ---------------------------------------------------------------------------
# 锚：探针必须钉在今天仍在产的源码上（脱锚 ⇒ 尺子坏了，rc=4，不是"产物旧"）
# ---------------------------------------------------------------------------
SOURCE_DIRS = ("src", "cmd")
SOURCE_EXTS = (".mbt",)
WALK_EXCLUDE = {"_build", ".git", ".mooncakes", "node_modules", "temp", "__pycache__",
                ".moon", ".moon-lock", "dist", "_release"}


def iter_source_files(root, dirs=SOURCE_DIRS):
    """源码文件（`.mbt`），跳过构建缓存/依赖缓存/产物目录。"""
    for sub in dirs:
        base = os.path.join(root, sub)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = sorted(d for d in dirnames if d not in WALK_EXCLUDE)
            for fname in sorted(filenames):
                if fname.endswith(SOURCE_EXTS):
                    yield os.path.join(dirpath, fname)


def source_definitions(root, names=(), dirs=SOURCE_DIRS):
    """返回源码里**真有代码定义**的符号集合（`fn NAME(` 且该行不是注释）。

    **为什么不用裸 substring**（判例-30 自指假绿）：`omega_orphan_of_archived_parent` 这个名字在
    `engine.mbt` 的注释里、在 `*_wbtest.mbt` 的测试名里都出现过 ⇒ 裸 substring 在"代码已删、注释还在"
    时照样命中，探针就变成了恒绿装饰。这里只认 `fn NAME(` 形状，且先剔除注释行。
    """
    wanted = list(names) or [s.name for s in KEY_SYMBOLS]
    if not wanted:
        return set()
    pats = dict((n, re.compile(RE_FN_DEF % re.escape(n))) for n in wanted)
    found = set()
    for path in iter_source_files(root, dirs):
        try:
            with io.open(path, encoding="utf-8", errors="replace") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        for line in lines:
            if RE_COMMENT_LINE.match(line):
                continue          # 注释行不算定义（判例-30）
            for name, pat in pats.items():
                if name in found:
                    continue
                if pat.search(line):
                    found.add(name)
    return found


def anchor_problems(root, symbols=KEY_SYMBOLS):
    """探针脱锚清单（源码里找不到定义 ⇒ 探针不再钉住今天的代码）。空列表 = 锚完好。"""
    found = source_definitions(root, [s.name for s in symbols])
    return [s.name for s in symbols if s.name not in found]


def describe_symbols(symbols=KEY_SYMBOLS):
    """人读清单（`--symbols`）：名字 / 出处 / 为什么值得当探针。"""
    lines = ["KEY_SYMBOLS（%d 条；本表是 check_deployment_freshness 与 check_dist_snapshot 的单一真源）"
             % len(symbols)]
    for i, s in enumerate(symbols, 1):
        lines.append("  %d. %s" % (i, s.name))
        lines.append("     出处：%s" % s.origin)
        lines.append("     为什么：%s" % s.why)
    return "\n".join(lines)
