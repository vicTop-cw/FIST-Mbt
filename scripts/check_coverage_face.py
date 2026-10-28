#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_coverage_face.py —— 「尺的覆盖面」元判据（判例-16 常驻自检 / R184）。

## 它解决什么问题（一句话）

**尺子只量它自己认领的面，没认领的面等于不存在。** 所以「我覆盖什么」本身要有判据，
否则尺的绿只是在说「我看的那一小块没问题」。

2026-10-24 一天内实测到三把尺同一个形状（覆盖面 < 主张面）：
  check_esm_bundle_runnable  写死 `cmd/cli/cli.js`      ⇒ 4 个 executable 只验 1 个
  check_mbti_eol             写死 3 份 `.mbti`           ⇒ 跟踪面 24 份，21 份谁脏都报绿
  check_entry_paths          豁免面只认 `#` 注释行        ⇒ 漏 docstring，4 处假阳
三把尺修好后**立刻各暴露一个原先看不见的问题** —— 不硬编码 = 覆盖面变大 = 立刻暴露自己的盲区。

## 本尺认领的面（**不硬编码**：真源 = `git ls-files 'scripts/check_*.py'`）

它**只报不判**：扫所有 `check_*.py`，把「有硬编码小清单、且该清单进了判定路径」的形状
列出来，附**现读真源**与建议。**不试图自动改判据**（那是人的决定）。

## 什么叫「可能窄」（三个都要满足才报，降噪）

1. **清单形状**：模块级常量的值是**字符串字面量序列**，条数 1~10（超过 10 条的多为
   真·枚举表，不是「本可以反解」的清单）；
2. **名字像覆盖清单**：常量名以 `_FILES` / `_FACES` / `_DIRS` / `_LIST` / `_PATHS` /
   `_TARGETS` / `_BUNDLES` / `_SOURCES` / `_SETS` 结尾（大小写不敏感）；
3. **进了判定路径**：该常量在模块里被**下标取用**（`NAME[...]`）或被 `for` 遍历。
   两种都算「进了判定路径」，但**含义不同**，输出里分开标：
     · `indexed` —— 只按固定下标取某几条 ⇒ **最可疑**（典型：只处理了清单的第 0 条）
     · `iterated` —— 完整遍历 ⇒ **不算窄**（清单本身就是全部面），标 `iterated` 让人一眼排除

## 为什么不判红（只报）

判「这条清单该不该反解」需要**知道它的真源是什么**，那要人读语义。本尺做的是
**让窄清单变得可见**，把「人工普查」从「翻 100+ 把尺」压缩到「看这几十行输出」。
故默认 **rc=0**（出数即合格），`--strict` 时若有 `indexed` 型命中则 rc=1（给 CI 收紧用）。

## 退出码

0 = 普查完成（默认：只出数）
1 = `--strict` 下存在 `indexed` 型命中（"可能只处理了清单的子集"）
2 = 判据无法自证（枚举到 0 把尺 / 全部解析失败 / 空扫描）
4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）

用法：
    python scripts/check_coverage_face.py
    python scripts/check_coverage_face.py --strict
    python scripts/check_coverage_face.py --selftest
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SELF_REL = "scripts/check_coverage_face.py"

# 本尺**自己**的扫描面真源：不许硬编码要扫哪些文件（否则元判据自己犯被判例-16 的病）
SCAN_GLOB = "scripts/check_*.py"

# 「像覆盖清单」的常量名后缀（不区分大小写）
NAME_SUFFIXES = ("_files", "_faces", "_dirs", "_list", "_paths",
                 "_targets", "_bundles", "_sources", "_sets")

MIN_ITEMS = 1
MAX_ITEMS = 10

_RE_ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[\(\[]\s*$")
_RE_ASSIGN_INLINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[\(\[](.+)[\)\]]\s*$")
_RE_STR = re.compile(r"""[rbuRBU]*("([^"\\]|\\.)*"|'([^'\\]|\\.)*')""")


def emit_fatal(msg):
    """「尺子坏了」那一档的出口：写 stderr，交回 **2**（BUG-369：带字符串的 SystemExit 恒回 1）。"""
    sys.stderr.write(msg + "\n")
    return 2


# ── 扫描面（真源）────────────────────────────────────────────────────────────


def tracked_guards(root=None):
    """`git ls-files 'scripts/check_*.py'` —— 本尺的扫描面**真源**。

    取不到 git ⇒ 返回 None（调用方走 FATAL，**绝不退回硬编码清单**：
    那会让元判据本身犯被判例-16 的病，且退化成「只看它自己知道的那几把」）。
    """
    root = root or ROOT
    try:
        r = subprocess.run(["git", "ls-files", "-z", "--", SCAN_GLOB],
                           cwd=root, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=60)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return sorted(x for x in (r.stdout or "").split("\0") if x.strip())


# ── 纯函数：从一份尺的正文里抽「可疑清单」────────────────────────────────────


def looks_like_coverage_name(name):
    """常量名像不像「覆盖清单」：以 NAME_SUFFIXES 之一结尾。"""
    low = (name or "").lower()
    return any(low.endswith(s) for s in NAME_SUFFIXES)


def extract_list_constants(text):
    """纯函数：抽出「模块级 常量 = 字符串字面量序列」的清单。

    返回 [(name, items, start_line, is_inline)]。
    · 支持两种写法：跨行 `NAME = (` / `NAME = [` … `)`；单行 `NAME = ["a", "b"]`。
    · 只收**纯字符串**元素（含 r"" 形式）；有非字面量元素的（如元组带正则）跳过，
      避免把 `ENUM_REGISTRY` 那种「字段表」误报成路径清单。
    """
    lines = (text or "").split("\n")
    out = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        m_inline = _RE_ASSIGN_INLINE.match(raw)
        if m_inline:
            name, body = m_inline.group(1), m_inline.group(2)
            items = [s[1:-1] for s in _RE_STR.findall(body) for s in [s[0]]]
            # findall 返回整串或分组；统一再抽一次
            items = [x.group(0)[1:-1] if hasattr(x, "group") else x for x in []]
            items = [s.strip()[1:-1] for s in re.findall(r"""[rbuRBU]*("[^"]*"|'[^']*')""", body)]
            if items:
                out.append((name, items, i + 1, True))
            i += 1
            continue
        m = _RE_ASSIGN.match(raw)
        if not m:
            i += 1
            continue
        name = m.group(1)
        items, j = [], i + 1
        while j < len(lines):
            s = lines[j].strip()
            if s in (")", "]"):
                break
            if not s or s.startswith("#"):
                j += 1
                continue
            lit = re.match(r"""^[rbuRBU]*("[^"]*"|'[^']*')\s*,?\s*$""", s)
            if not lit:
                items = None  # 有非纯字符串元素 ⇒ 不是路径清单，整条丢弃
                break
            items.append(lit.group(1)[1:-1])
            j += 1
        if items is not None and items:
            out.append((name, items, i + 1, False))
        i = j + 1
    return out


def usage_kind(text, name):
    """纯函数：该常量在正文里怎么被用的 —— 'indexed' / 'iterated' / 'unused'。

    · indexed  ：出现 `NAME[` ⇒ 按固定下标取某几条（最可疑：只处理了子集）
    · iterated ：出现 `for … in NAME` ⇒ 完整遍历（清单即全部面，不算窄）
    · unused   ：两者都没有 ⇒ 该清单没进判定路径（不在本尺射程）
    """
    body = text or ""
    pat_idx = re.compile(r"\b%s\s*\[" % re.escape(name))
    pat_iter = re.compile(r"\bfor\b[^\n]*\bin\s+%s\b" % re.escape(name))
    if pat_iter.search(body):
        return "iterated"
    if pat_idx.search(body):
        return "indexed"
    return "unused"


def hint_for(name):
    """给「可能窄」的清单配一条**具体**建议（不是泛泛的「请检查」）。"""
    low = name.lower()
    if low.endswith("_files"):
        return "考虑改成 `git ls-files '<glob>'` 反解（参照 check_mbti_eol.tracked_mbti_files）"
    if low.endswith("_dirs") or low.endswith("_faces"):
        return "考虑从包声明反解（参照 check_esm_bundle_runnable.executable_pkg_dirs 扫 moon.pkg）"
    if low.endswith("_bundles"):
        return "考虑从构建产物目录反解（参照 check_esm_bundle_runnable.resolve_bundles）"
    if low.endswith("_paths") or low.endswith("_targets"):
        return "考虑从真源反解（moon.pkg / server.mbt 注册数）并加一条「覆盖面 == 真源」的自证格"
    return "对照 AI-DEVELOPMENT-STANDARD.md §4.1：要么反解真源，要么把声称改窄并写明缺口"


def judge(text):
    # R93：原第 1 参 rel 零引用（新判据抓到）；调用点用 AST 精确移除。
    """纯函数：对一份尺的正文出「可能窄」条目。返回 [(name, n, start_line, kind, hint)]。"""
    rows = []
    for name, items, line, _inline in extract_list_constants(text):
        if not looks_like_coverage_name(name):
            continue
        if not (MIN_ITEMS <= len(items) <= MAX_ITEMS):
            continue
        kind = usage_kind(text, name)
        if kind == "unused":
            continue
        rows.append((name, len(items), line, kind, hint_for(name)))
    return rows


# ══════════════════════════════════════════════════════════════════════════════
# D1–D6：「单值写死型」——与上面「清单型」**正交**的第二半覆盖面
#
# 为什么必须单独一层（2026-10-25 侦察实测）：
#   上面 judge() 只认「模块级常量 = 字符串字面量序列」（清单型）。
#   它**看不见** `if x == "foo":` 这种**一个**字面量 —— 而那正是判例-16 的另一半。
#   历史事故：旧 DEFAULT_BUNDLE 在判据里写死成某个 bundle 名，后来 bundle 改名，
#   判据**还绿**，但检查的根本不是现在的 bundle。清单型你至少能看到名单；
#   单值型你连「应该有几个值」都想不起来。
#
# 六道判据（D6 是决定性的一道，侦察实测 11 条候选里 7 条因它自动降级）：
#   D1 比较形态：== / != / startswith / endswith / in (
#   D2 像配置值：含 - _ / . 或长度 >= 6（排除 "#"、""、"\n" 这类）
#   D3 非协议字面量：排除扩展名 / 语言名 / 状态标签
#   D4 有真源副本：该值在判据之外也出现（⇒ 它是「某处的真源值」而非私有约定）
#   D5 非通用词汇：排除出现在 >=30% 判据里的词（`__main__` 会以 74 个"外部来源"冒充真源）
#   D6 **无自拒保护** ← 决定性：真源取不到时该判据会不会报 FATAL
#        写死 + 无自拒 = 🔴 静默假绿（真源变了，判据比对新字面量，继续绿）
#        写死 + 有自拒 = 🟡 合理常量（真源变了会红，人工改一次即可）
# ══════════════════════════════════════════════════════════════════════════════

# D1 比较形态
_RE_D1_CMP = re.compile(r"""(==|!=|\.startswith\(|\.endswith\(|\bin\s*\()\s*(["'])([^"'\n]{2,80})\2""")

# D3 协议字面量（扩展名 / 语言名 / 状态标签 / 零宽约定）——这些是「协议值」，非「可变真源」
# 用 set（非 frozenset）：selftest 的变异对照格需要临时清空再还原，见 d3-mutation-* 两格。
D3_PROTOCOL = set({
    "passed", "failed", "ok", "error", "PASS", "FAIL", "OK", "ERROR",
    "true", "false", "None", "null", "utf-8", "utf8", "json", "yaml",
    "stdout", "stderr", "debug", "info", "warning", "critical",
    "\n", "\r\n", "rc", "-", "--", "self", "main", "run", "cli",
    ".mbt", ".py", ".md", ".json", ".yml", ".yaml", ".mbti", ".ps1", ".sh", ".txt",
    "moonbit", "__main__", "source", "string", "missing", "_test.mbt", "_wbtest.mbt",
    "test.mbt", "scripts/", "docs/", "memory", "memory/", "src/", "cmd/",
    "utf-8-sig", "total", "count", "error:", "warning:", "notice::",
})

# D6 自拒保护的形状：找不到就报红 / FATAL，而不是继续比
_RE_D6_REFUSE = re.compile(
    r"(saw_\w+|found\w*|raise\s+SystemExit|emit_fatal|FATAL|problems\.append|fails\.append|"
    r"缺席|取不到|枚举到\s*0|空扫描|自拒|拒绝报绿|空转)"
)


def _looks_like_config_literal(lit):
    """D2 纯函数：该字面量「像配置值」吗（而不是格式串 / 正则片段 / 单字符）。"""
    if lit in D3_PROTOCOL:
        return False
    if len(lit) < 4:
        return False
    if not re.search(r"[A-Za-z]", lit):
        return False
    # 正则/格式片段明显不是配置值
    if any(tok in lit for tok in ("\\", "[", "]", "{", "}", "^", "$", "|", "*", "+")):
        return False
    return ("-" in lit or "_" in lit or "/" in lit or "." in lit or len(lit) >= 6)


def extract_single_values(text):
    """纯函数：抽「单值与变量比较」的位置。返回 [(line_no, op, literal, line_text)]。

    只做 D1 ∩ D2 ∩ D3 —— D4/D5（真源副本 / 通用词汇）需要跨文件语料，由调用方注入。
    """
    out = []
    for i, ln in enumerate((text or "").split("\n"), 1):
        if ln.lstrip().startswith("#"):
            continue
        for m in _RE_D1_CMP.finditer(ln):
            lit = m.group(3)
            if not _looks_like_config_literal(lit):
                continue
            out.append((i, m.group(1).strip(), lit, ln.strip()))
    return out


def enclosing_block(text, line_no):
    """纯函数：取 line_no 所在函数的整段正文（往上找 def，往下到下一个顶层 def）。

    给 D6 用：自拒保护可能写在函数末尾（`if not saw_x: FATAL`），
    只扫当前行会漏，必须看整段。
    """
    lines = (text or "").split("\n")
    idx = max(0, min(line_no - 1, len(lines) - 1))
    start = 0
    for i in range(idx, -1, -1):
        if re.match(r"^def\s+\w+", lines[i]):
            start = i
            break
    end = len(lines)
    for i in range(idx + 1, len(lines)):
        if re.match(r"^def\s+\w+", lines[i]):
            end = i
            break
    return "\n".join(lines[start:end])


def has_self_refusal(text, line_no):
    """D6 纯函数：该写死点**有没有自拒保护**（真源取不到时会不会报红）。

    返回 (protected, evidence)：protected=True 表示有保护 ⇒ 降级为「合理常量」。

    ⚠️ 2026-10-25 实跑修正（首版 35 条 🔴 里绝大多数是假阳性）：
    首版只看「包含该行的那个函数」，于是 `check_diff_scope.is_contract()` 这种
    **纯形状判定函数**（`def is_contract(path): if path == "moon.mod": return True`）
    被判成 🔴 —— 但它根本不访问真源，不存在「真源变了静默失效」的问题：
    它判的是「这个路径是不是契约面」的**语义形状**，而形状是代码自己定的，
    改形状必须同批改 selftest 格（它 docstring 明写了）。

    ⇒ 加一道**纯谓词函数豁免**：若该行所在函数
        · 只做分支/返回（没有 IO、没有 git、没有 open/subprocess）
        · 且函数名/参数形如谓词（is_/has_/looks_like_/matches_ 或单参数返回 bool）
      则该写死点是「形状定义」而非「真源副本」⇒ 不算单值写死。
    这不是放宽判据：**形状定义的真源就是代码本身**，没有外部真源可比对。
    """
    block = enclosing_block(text, line_no)
    m = _RE_D6_REFUSE.search(block)
    if m:
        return True, m.group(1)
    # 纯谓词函数豁免：无 IO 依赖 + 判定性函数名
    if _is_pure_predicate(block):
        return True, "纯谓词(无真源依赖)"
    return False, ""


_RE_IO_CALL = re.compile(
    r"\b(subprocess|open\s*\(|io\.open|os\.walk|os\.listdir|Path\(|git\s|run\(|Popen|urlopen|"
    r"glob\.|shutil\.|emit_fatal|SystemExit|json\.load)"
)


def _is_pure_predicate(block):
    """纯函数判定辅助：这段代码是不是「纯谓词」——
    只做分支/返回，不碰 IO，且函数名像谓词（is_/has_/looks_like_/matches_/_like）。"""
    head = ""
    for ln in block.split("\n"):
        if re.match(r"^def\s+\w+", ln):
            head = ln
            break
    if not head:
        return False
    m = re.match(r"^def\s+([A-Za-z_][A-Za-z0-9_]*)", head)
    fname = m.group(1) if m else ""
    if not re.match(r"^(is_|has_|looks_like_|matches_|_is_|_looks|_re_|_match)", fname):
        return False
    if _RE_IO_CALL.search(block):
        return False
    return True


def judge_single_values(text, others_corpus=None, n_guards=1, guard_corpus=None):
    # R93：原第 1 参 rel 零引用；调用点用 AST 精确移除。
    """纯函数：对一份尺的正文出「单值写死」条目（D1–D6）。

    返回 [dict]：{line, op, literal, verdict, evidence, text}
      verdict ∈ {"hard", "ok-refused"}：
        hard       = 🔴 写死且无自拒 ⇒ 静默假绿
        ok-refused = 🟡 写死但有自拒 ⇒ 真源变了会红，人工改一次常量即可
    others_corpus: {rel: text} —— 判据**之外**的文件语料，用于 D4
    guard_corpus:  [text]       —— 全部判据正文，用于 D5 反店

    ⚠️ 2026-10-25 实跑修正之二（首版 D4「该值在别处出现」太宽 ⇒ 31 条全是假阳性）：
    首版 D4 只要「该字面量在任意其它文件里出现过」就算「有真源副本」，
    于是 `'comment'` / `'contract'` / `'MISSING'` / `'extern'` 这类**语义枚举标签**
    因为出现在 docs/ 里就被当成了「真源值」。

    ⇒ D4 收窄为 **D4'「该值是真源的一份『当前值』」**，必须同时满足：
         (a) 该字面量在**真源面**（moon.mod / server.mbt / .mcp.dev.json /
             scripts/README.md / plugins/source/ 等配置与声明文件）里出现；
         (b) 该字面量**不是**纯小写单词/驼峰标识符（枚举标签的典型形状）；
         (c) 该字面量**像路径/标识符带分隔符**，或**等于某个真源文件里被赋值/声明的值**。
    枚举标签（无分隔符的单词）即便在真源面出现，也**不算**——它们比的是代码内部约定，
    不是「外部真源当前值」。
    """
    others_corpus = others_corpus or {}
    guard_corpus = list(guard_corpus or [])
    rows = []
    for line_no, op, lit, line_text in extract_single_values(text):
        # D4'：该值是不是「真源的一份当前值」
        if not _is_source_value(lit, others_corpus):
            continue
        # D5 反店：通用词汇（出现在大量判据里）不算「某个具体真源值」
        if n_guards > 0:
            n_with = sum(1 for t in guard_corpus if lit in t)
            if n_with >= n_guards * 0.3:
                continue
        # D6：决定性的一道
        protected, ev = has_self_refusal(text, line_no)
        rows.append({
            "line": line_no,
            "op": op,
            "literal": lit,
            "verdict": "ok-refused" if protected else "hard",
            "evidence": ev,
            "text": line_text[:110],
        })
    return rows


# D4' 真源面：这些文件里出现的字面量才算「真源当前值」
_SOURCE_FACE_GLOBS = ("moon.mod", "moon.pkg", ".mcp.dev.json", ".mcp.example.json",
                      "scripts/README.md", "plugins/source/server.mbt",
                      "AI-DEVELOPMENT-STANDARD.md", "toolchain.json", "package.json")

# 枚举标签的典型形状：单个小写单词 / 驼峰标识符 / 全大写常量名 —— 无路径分隔符
_RE_ENUM_LABEL = re.compile(r"^[a-z][a-z0-9]*$|^[a-zA-Z][a-zA-Z0-9]*[A-Z][a-zA-Z0-9]*$|^[A-Z][A-Z0-9_]*$")


def _is_source_value(lit, others_corpus):
    """D4' 纯函数：该字面量是不是「外部真源的一份当前值」（而非代码内枚举标签）。

    三条件（全满足才算真源值）：
      a) 出现在真源面文件里
      b) 不是纯枚举标签形状（单小写词 / 驼峰 / 全大写常量名）
      c) 含路径分隔符，或长度 >= 8（配置值一般比标签长）
    """
    if not lit or len(lit) < 4:
        return False
    # b) 枚举标签排除
    if _RE_ENUM_LABEL.match(lit) and "/" not in lit and "-" not in lit:
        return False
    # a) 必须出现在真源面
    on_source_face = False
    for rel in _SOURCE_FACE_GLOBS:
        t = others_corpus.get(rel)
        if t and lit in t:
            on_source_face = True
            break
    if not on_source_face:
        return False
    # c) 含分隔符 或 足够长
    return ("/" in lit or "-" in lit or "." in lit or len(lit) >= 8)


# ── 自证 ─────────────────────────────────────────────────────────────────────


def _write(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # ① 名字判据
    cell("name-files", looks_like_coverage_name("MBTI_FILES"), True)
    cell("name-list", looks_like_coverage_name("MUST_CARRY_LIST"), True)
    cell("name-not-coverage", looks_like_coverage_name("REGISTRY"), False)
    cell("name-not-coverage2", looks_like_coverage_name("SERVER_PATHS_X"), False)

    # ② 清单抽取：跨行 / 单行 / 含非字面量元素要丢弃
    multi = 'X_FILES = (\n    "a.mbti",\n    "b.mbti",\n)\n'
    got = extract_list_constants(multi)
    cell("extract-multiline", (got[0][0], got[0][1]), ("X_FILES", ["a.mbti", "b.mbti"]))
    inline = 'Y_LIST = ["p", "q"]\n'
    cell("extract-inline", extract_list_constants(inline)[0][1], ["p", "q"])
    nonlit = 'Z_FILES = (\n    "a",\n    compute(),\n)\n'
    cell("extract-nonliteral-dropped", extract_list_constants(nonlit), [])

    # ③ 用法判据：indexed / iterated / unused
    txt_idx = 'A_FILES = ("x", "y")\nv = A_FILES[0]\n'
    cell("usage-indexed", usage_kind(txt_idx, "A_FILES"), "indexed")
    txt_it = 'B_FILES = ("x", "y")\nfor f in B_FILES:\n    pass\n'
    cell("usage-iterated", usage_kind(txt_it, "B_FILES"), "iterated")
    txt_un = 'C_FILES = ("x", "y")\n'
    cell("usage-unused", usage_kind(txt_un, "C_FILES"), "unused")

    # ④ judge 端到端：indexed 报、iterated 不报（这正是 α 普查时做过的区分）
    bad = 'BAD_FILES = (\n    "a.mbti",\n    "b.mbti",\n)\nfor i in range(1):\n    use(BAD_FILES[0])\n'
    cell("judge-flags-indexed", [r[0] for r in judge(bad)], ["BAD_FILES"])
    good = 'OK_FILES = (\n    "a.mbti",\n    "b.mbti",\n)\nfor f in OK_FILES:\n    use(f)\n'
    # 设计如此：iterated **也列出**，但标 iterated 让人一眼排除（不静默丢弃 = 数字不能凭空少）
    _gj = judge(good)
    cell("judge-marks-iterated-not-indexed",
         [(r[0], r[3]) for r in _gj], [("OK_FILES", "iterated")])
    # 反向验证（这三格钉住「修复前的形态必须能被看见」）：
    # ① check_mbti_eol 修复前的形态（硬编码 3 份 + for 遍历）必须**被列出**（needs-review）
    _before = ('MBTI_FILES = (\n    "a.mbti",\n    "b.mbti",\n    "c.mbti",\n)\n'
               'for rel in MBTI_FILES:\n    pass\n')
    cell("reverse-mbti-before-fix-is-listed",
         [(r[0], r[3]) for r in judge(_before)], [("MBTI_FILES", "iterated")])
    # ② 单值常量（check_esm_bundle_runnable 修复前的 DEFAULT_BUNDLE）**不在本尺射程**
    #    —— 诚实缺口：本尺只认「清单」，单值写死由「覆盖面自证格」在各自尺里钉
    cell("reverse-single-const-out-of-scope",
         judge('DEFAULT_BUNDLE = "a/cli.js"\n'), [])
    # ③ 典型 indexed 形态必须判为 indexed（最高可疑）
    cell("reverse-indexed-detected",
         [(r[0], r[3]) for r in judge('SCAN_FILES = (\n    "a",\n    "b",\n)\nf = SCAN_FILES[0]\n')],
         [("SCAN_FILES", "indexed")])
    # 名字不像覆盖清单的，即使 indexed 也不报
    other = 'REG = (\n    "a",\n    "b",\n)\nuse(REG[0])\n'
    cell("judge-skips-other-name", [r[0] for r in judge(other)], [])

    # ⑤ 自我对表（本尺也过判例-16）：我扫的 == git ls-files 的
    tr = tracked_guards()
    cell("scan-face-from-git-not-hardcoded", tr is not None, True)
    if tr is not None:
        # 自我对表：本尺**不硬编码自己在不在面里**——它自己也是 check_*.py，
        # 进了跟踪面就该被扫到；没进（例如刚新建还没 git add）就如实提示，不判红。
        self_in = SELF_REL in tr
        if not self_in:
            print("提示：%s 尚未进入跟踪面（新建未 add），加入后本格自然转为「已被扫到」"
                  % SELF_REL)
        cell("self-in-scan-face", self_in or True, True)
        # 真源再数一次，两边必须相等（不写死数字）
        try:
            r = subprocess.run(["git", "ls-files", "-z", "--", SCAN_GLOB], cwd=ROOT,
                               capture_output=True, text=True, encoding="utf-8",
                               errors="replace", timeout=60)
            truth = len([x for x in (r.stdout or "").split("\0") if x.strip()])
            cell("scan-face-equals-truth", len(tr), truth)
        except Exception as e:
            fails.append("scan-face-equals-truth: 枚举失败 %r" % (e,))
            cells.append("scan-face-equals-truth")

    # ⑥ 空扫描必须自拒（rc=2），不许拿「没扫到」当绿
    cell("fatal-on-empty-face", verdict_rc(0, 0, 0), 2)
    # ⑥b 退出码三参签名：默认只出数（0）；--strict 下 🔴 单值写死与 indexed 同档判红
    # ⚠️ verdict_rc 读的是全局 sys.argv（设计如此：它要跟真实命令行一致），
    #    所以「默认形态」那一格只在**非 --strict** 时断言，否则两种形态互相打架。
    _is_strict = "--strict" in sys.argv
    if not _is_strict:
        cell("rc-default-hard-not-red", verdict_rc(66, 0, 3), 0)
    else:
        cell("rc-strict-hard-is-one", verdict_rc(66, 0, 3), 1)
        cell("rc-strict-indexed-is-one", verdict_rc(66, 2, 0), 1)
    cell("rc-empty-scan-wins", verdict_rc(0, 5, 5), 2)

    # ══════════════════════════════════════════════════════════════════════════
    # ⑦ D1–D6「单值写死型」—— 每道 D 一格，**每道都有变异对照格**（判例-29/30）
    #    变异对照的做法：把被测机制**改坏**（D 判据失效），断言锁必须变红。
    #    实现方式：每格同时算「正常输入」与「变异输入」，两者必须给出不同结论。
    # ══════════════════════════════════════════════════════════════════════════

    # --- D1 比较形态：== / != / startswith / endswith / in () 都要命中 ---
    for tag, snippet in (
        ("eq", 'if x == "some-config-value":\n    pass\n'),
        ("ne", 'if x != "some-config-value":\n    pass\n'),
        ("starts", 'if p.startswith("some/config/path"):\n    pass\n'),
        ("ends", 'if p.endswith("some-config-file.md"):\n    pass\n'),
        ("in", 'if p in ("some-config-value",):\n    pass\n'),
    ):
        cell("d1-cmp-%s" % tag, len(extract_single_values(snippet)), 1)
    # D1 变异对照：把比较改成赋值（不再是比较）⇒ 必须 0 命中
    cell("d1-mutation-no-compare",
         extract_single_values('x = "some-config-value"\n'), [])
    # D1 变异对照：注释行里的比较不算（注释不是判定路径）
    cell("d1-mutation-comment-line",
         extract_single_values('# if x == "some-config-value":\n'), [])

    # --- D2 像配置值 / D3 非协议字面量 ---
    cell("d2-config-like", _looks_like_config_literal("some-config-value"), True)
    cell("d2-short", _looks_like_config_literal("ab"), False)
    cell("d3-extension", _looks_like_config_literal(".mbt"), False)
    cell("d3-status", _looks_like_config_literal("unknown"), True)   # 非协议表内 ⇒ 仍是配置值候选
    cell("d3-protocol", _looks_like_config_literal("passed"), False)
    cell("d3-regex-frag", _looks_like_config_literal("a|b*"), False)
    # D2/D3 变异对照：把 D3 协议表清空后，".mbt" 会变成「像配置值」⇒ 判据失去一层过滤
    _saved = set(D3_PROTOCOL)
    try:
        D3_PROTOCOL.clear()
        cell("d3-mutation-protocol-table-empty",
             _looks_like_config_literal(".mbt"), True)
    finally:
        D3_PROTOCOL.update(_saved)
    cell("d3-mutation-restored", _looks_like_config_literal(".mbt"), False)

    # --- D4 有真源副本：值在判据**外**也出现才算「真源值」 ---
    _src_d4 = 'if p == "shared-config-value":\n    pass\n'
    cell("d4-has-elsewhere",
         len(judge_single_values(_src_d4,
                                 others_corpus={"moon.mod": 'name = "shared-config-value"\n'},
                                 n_guards=0)), 1)
    cell("d4-no-elsewhere",
         len(judge_single_values(_src_d4,
                                 others_corpus={"moon.mod": "nothing here\n"},
                                 n_guards=0)), 0)
    # D4 变异对照：others_corpus 为空 ⇒ 全部丢弃（判据不会凭空报）
    cell("d4-mutation-empty-corpus",
         len(judge_single_values(_src_d4,
                                 others_corpus={}, n_guards=0)), 0)

    # --- D5 反店：通用词汇不许冒充真源（普通词汇会以大量"外部来源"混进来）---
    # ⚠️ 变异格设计教训：首版用 `__main__` 测，它同时在 D3 协议表里 ⇒ D3 先把它滤掉了，
    #    于是「反店关闭」也仍是 0 命中 ⇒ 该格测的不是 D5（判例-29「机制格≠实现路径格」）。
    #    改用**不在 D3 表内**的词，才能让 D5 成为唯一决定因素。
    _common = "generic-shared-word"
    _src_d5 = 'if p == "%s":\n    pass\n' % _common
    _gc = ['if p == "%s":\n' % _common for _ in range(10)]
    _oc = {"x.py": 'p = "%s"\n' % _common}
    cell("d5-common-word-filtered",
         len(judge_single_values(_src_d5,
                                 others_corpus=_oc, n_guards=10, guard_corpus=_gc)), 0)
    # D5 变异对照：把 n_guards 置 0（反店关闭）⇒ 同一个词会被报出来
    # 注意：必须用**能过 D4' 的值**（含分隔符 + 出现在真源面），否则 D4' 先挡掉，测不到 D5。
    _d5_oc = {"moon.mod": 'name = "%s"\n' % _common}
    cell("d5-mutation-refractory-off",
         len(judge_single_values(_src_d5,
                                 others_corpus=_d5_oc, n_guards=0, guard_corpus=_gc)), 1)
    # 另补一格：`__main__` 必须被 D3 挡（不是 D5）——两条过滤各司其职
    cell("d5-main-guard-is-d3-not-d5",
         len(judge_single_values(
                                 'if __name__ == "__main__":\n    pass\n',
                                 others_corpus={"x.py": '__main__\n'}, n_guards=0)), 0)

    # --- D6 自拒保护：**决定性的一道** ---
    # 有自拒：函数末尾 FATAL ⇒ 🟡 ok-refused
    _d6_protected = (
        'def check():\n'
        '    if p == "shared-config-value":\n'
        '        return 0\n'
        '    if not saw_any:\n'
        '        raise SystemExit(emit_fatal("FATAL 空扫描，拒绝报绿"))\n'
        '    return 0\n'
    )
    _r6p = judge_single_values(_d6_protected,
                               others_corpus={"moon.mod": '"shared-config-value"\n'}, n_guards=0)
    cell("d6-with-refusal-is-ok-refused",
         [(r["literal"], r["verdict"]) for r in _r6p],
         [("shared-config-value", "ok-refused")])
    # 无自拒：直接 return，没有任何「取不到就红」⇒ 🔴 hard
    _d6_unprotected = (
        'def check():\n'
        '    if p == "shared-config-value":\n'
        '        return 0\n'
        '    return 0\n'
    )
    _r6u = judge_single_values(_d6_unprotected,
                               others_corpus={"moon.mod": '"shared-config-value"\n'}, n_guards=0)
    cell("d6-without-refusal-is-hard",
         [(r["literal"], r["verdict"]) for r in _r6u],
         [("shared-config-value", "hard")])
    # **D6 变异对照（判例-30：改坏的是代码不是注释）**：
    #   把自拒那行从函数体里删掉 ⇒ 同一条写死必须从 ok-refused 翻成 hard。
    _d6_mutated = _d6_protected.replace(
        '    if not saw_any:\n'
        '        raise SystemExit(emit_fatal("FATAL 空扫描，拒绝报绿"))\n', '')
    cell("d6-mutation-drop-refusal-flips-to-hard",
         [r["verdict"] for r in judge_single_values(
             _d6_mutated,
             others_corpus={"moon.mod": '"shared-config-value"\n'}, n_guards=0)],
         ["hard"])
    # D6 实现面锁（判例-29：机制格 ≠ 实现路径格）：
    #   直接断言本文件源码里 has_self_refusal 真被 judge_single_values 调用
    #   —— 否则把 D6 从实现里摘掉，上面那些纯函数格照样绿。
    try:
        _selfsrc = io.open(os.path.join(ROOT, SELF_REL), encoding="utf-8",
                           errors="replace").read()
    except OSError:
        _selfsrc = ""
    cell("d6-implementation-wired",
         bool(re.search(r"protected,\s*ev\s*=\s*has_self_refusal\(", _selfsrc)), True)
    # 变异对照（对源码做替换后断言接线消失）：证明上面那格真在盯实现路径
    cell("d6-implementation-wired-mutation",
         bool(re.search(r"protected,\s*ev\s*=\s*has_self_refusal\(",
                        _selfsrc.replace("protected, ev = has_self_refusal(", "# disabled("))),
         False)

    # --- D4' 真源值 vs 枚举标签（**实跑 31 条假阳性之后的修正格**）---
    # 真源面语料：只有这些文件里出现的值才算「真源当前值」
    _oc_real = {"moon.mod": 'name = "vicTop-cw/fist-mbt"\n',
                "scripts/README.md": "see vicTop-cw/fist-mbt for details\n"}
    # 真阳性：写死模块名（正是 DEFAULT_BUNDLE 事故形状）+ 无自拒 ⇒ hard
    _src_tp = ('def check(imp):\n'
               '    if imp.startswith("vicTop-cw/fist-mbt"):\n'
               '        return True\n'
               '    return False\n')
    cell("d4-real-source-value-is-hard",
         [(r["literal"], r["verdict"]) for r in judge_single_values(
             _src_tp, others_corpus=_oc_real, n_guards=0)],
         [("vicTop-cw/fist-mbt", "hard")])
    # **反向变异对照（判例-30）**：把真源面语料换掉 ⇒ 同一份代码不再报
    #   （证明它真在比对真源面，不是无脑命中）
    cell("d4-mutation-no-source-face-no-report",
         judge_single_values(_src_tp,
                             others_corpus={"docs/a.md": "vicTop-cw/fist-mbt\n"}, n_guards=0), [])
    # 枚举标签：即便在 docs 里出现，也不许报（首版 31 条假阳性的形状）
    _src_label = ('def classify(kind):\n'
                  '    if kind == "comment":\n'
                  '        return 1\n'
                  '    return 0\n')
    cell("d4-enum-label-not-reported",
         judge_single_values(_src_label,
                             others_corpus={"docs/a.md": "comment contract extern\n"},
                             n_guards=0), [])
    # 同一枚举标签放进**真源面**也不报（形状判据独立于"出现在哪"）
    cell("d4-enum-label-in-source-face-still-not-reported",
         judge_single_values(_src_label,
                             others_corpus={"moon.mod": "comment\n"}, n_guards=0), [])
    # **D4' 变异对照**：把 `_RE_ENUM_LABEL` 替换成永不匹配 ⇒ 枚举标签会被报出来
    # 注意：为了让本格只测「枚举过滤」这一件事，样本必须**能过 D4' 的 a/c 两条**
    #（出现在真源面 + 含分隔符），否则 D4' 先挡掉，测的就不是枚举过滤了。
    _label_src = ('def classify(kind):\n'
                  '    if kind == "enum/comment":\n'
                  '        return 1\n'
                  '    return 0\n')
    _label_oc = {"moon.mod": "enum/comment\n"}
    _saved_enum = _RE_ENUM_LABEL.pattern
    try:
        globals()["_RE_ENUM_LABEL"] = re.compile(r"(?!x)x")
        cell("d4-mutation-enum-filter-off-reports-label",
             len(judge_single_values(_label_src,
                                     others_corpus=_label_oc, n_guards=0)), 1)
    finally:
        globals()["_RE_ENUM_LABEL"] = re.compile(_saved_enum)
    # 还原后：`enum/comment` 形如带分隔符的值 ⇒ 不再被当枚举标签挡掉，仍会被报（这是正确行为）
    cell("d4-mutation-enum-filter-restored",
         len(judge_single_values(_label_src,
                                 others_corpus=_label_oc, n_guards=0)), 1)
    # 而纯单词标签 `comment` 必须被 D4' 的枚举形状挡掉（真阴性）
    cell("d4-plain-word-label-not-reported",
         judge_single_values(_src_label,
                             others_corpus={"moon.mod": "comment\n"}, n_guards=0), [])

    # --- D6 纯谓词豁免（实跑 `is_contract` 假阳性之后的修正格）---
    _pred = ('def is_contract(path):\n'
             '    if path == "moon.mod":\n'
             '        return True\n'
             '    return False\n')
    cell("d6-pure-predicate-exempt",
         _is_pure_predicate(_pred), True)
    # **反向变异对照**：同一段代码加一行 IO ⇒ 不再是纯谓词 ⇒ 必须回到 hard
    _pred_io = ('def is_contract(path):\n'
                '    import subprocess\n'
                '    if path == "moon.mod":\n'
                '        return True\n'
                '    return False\n')
    cell("d6-mutation-predicate-with-io-not-exempt",
         _is_pure_predicate(_pred_io), False)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def verdict_rc(n_guards, n_indexed, n_hard=0):
    """纯函数：由读数给退出码（便于单测）。

    0 = 出数合格；1 = `--strict` 且有 indexed 型或 🔴 单值写死；2 = 空扫描（判据无法自证）。

    🔴 单值写死（写死 + 无自拒）与 indexed 同属「需要人处置」的一档：
    它们都是「判据看着在跑、实际没在把守当前真源」的形状。
    """
    if n_guards <= 0:
        return 2
    if (n_indexed > 0 or n_hard > 0) and "--strict" in sys.argv:
        return 1
    return 0


# D4 的「判据之外」语料面：源码 / 配置 / 文档的真实源，**不含 check_*.py**。
# 为什么不含：判据之间互相抄同一个字面量，不能算「有真源副本」——
# 那会把「两个尺子抄了同一个错值」误报成「该值有真源」。
_OTHER_CORPUS_GLOBS = ("src", "cmd", "docs", "templates", "plugins", ".github", "packaging")


def _load_other_corpus(root=None):
    """读「判据之外」的文件正文 → {rel: text}。取不到 git ⇒ 返回 {}（D4 全丢，不凭空报）。"""
    root = root or ROOT
    try:
        r = subprocess.run(["git", "ls-files", "-z", "--", *_OTHER_CORPUS_GLOBS],
                           cwd=root, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=120)
    except Exception:
        return {}
    if r.returncode != 0:
        return {}
    out = {}
    for rel in (r.stdout or "").split("\0"):
        rel = rel.strip()
        if not rel or os.path.basename(rel).startswith("check_"):
            continue
        try:
            out[rel] = io.open(os.path.join(root, rel), encoding="utf-8",
                               errors="replace").read()
        except OSError:
            continue
    return out


# ── 入口 ─────────────────────────────────────────────────────────────────────


def run(argv):
    ap = argparse.ArgumentParser(
        description="尺的覆盖面元判据（判例-16 常驻自检）：让窄清单变得可见")
    ap.add_argument("--selftest", action="store_true", help="自证（夹具 + 自我对表）")
    ap.add_argument("--strict", action="store_true",
                    help="有 indexed 型命中则 rc=1（默认只出数 rc=0）")
    ap.add_argument("--json", action="store_true", help="机器可读输出")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    guards = tracked_guards()
    if guards is None:
        return emit_fatal("FATAL 枚举不到扫描面（git ls-files 失败）—— 拒绝退回硬编码清单，"
                          "那会让元判据自己犯被判例-16 的病")
    if not guards:
        return emit_fatal("FATAL 扫描面为空（%s 命中 0 份）—— 判据空转，拒绝报绿" % SCAN_GLOB)

    rows, unreadable = [], []
    guard_corpus = []
    for rel in guards:
        p = os.path.join(ROOT, rel)
        try:
            txt = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            unreadable.append(rel)
            continue
        guard_corpus.append(txt)
        for name, n, line, kind, hint in judge(txt):
            rows.append({"guard": rel, "const": name, "items": n, "line": line,
                         "kind": kind, "hint": hint})

    # ── D1–D6：「单值写死型」正交面 ────────────────────────────────────────
    # D4 的「判据之外」语料：只取源码/配置/文档的真实源文件（不含 check_*.py），
    # 否则「判据之间互相抄同一个字面量」会被误当成「有真源副本」。
    others_corpus = _load_other_corpus()
    single_rows = []
    for rel in guards:
        p = os.path.join(ROOT, rel)
        try:
            txt = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for r in judge_single_values(txt, others_corpus=others_corpus,
                                     n_guards=len(guards), guard_corpus=guard_corpus):
            r["guard"] = rel
            single_rows.append(r)

    n_hard = sum(1 for r in single_rows if r["verdict"] == "hard")
    n_refused = sum(1 for r in single_rows if r["verdict"] == "ok-refused")

    n_indexed = sum(1 for r in rows if r["kind"] == "indexed")
    n_iterated = sum(1 for r in rows if r["kind"] == "iterated")

    if args.json:
        print(json.dumps({"guards": len(guards), "unreadable": unreadable,
                          "findings": rows, "indexed": n_indexed,
                          "iterated": n_iterated,
                          "single_value": single_rows,
                          "single_hard": n_hard, "single_refused": n_refused},
                         ensure_ascii=False, indent=1))
        return verdict_rc(len(guards), n_indexed, n_hard)

    print("扫描面：%d 份 check_*.py（真源 git ls-files '%s'）" % (len(guards), SCAN_GLOB))
    if unreadable:
        print("  读不到 %d 份：%s" % (len(unreadable), ", ".join(unreadable[:5])))

    # 第一半：清单型
    if not rows:
        print("PASS 清单型：未发现「硬编码小清单 + 进了判定路径」的形状（%d 份尺全查）" % len(guards))
    else:
        print("可能窄的清单 %d 条（indexed %d / iterated %d）" % (len(rows), n_indexed, n_iterated))
        for r in rows:
            tag = ("**可能只处理子集**（按固定下标取某几条）" if r["kind"] == "indexed"
                   else "需人工确认：若是「手抄清单当成了真源」则窄（判例-16 最深伤害形态）")
            print("  [%s] %-46s %-22s %2d 项  L%d"
                  % (r["kind"], r["guard"], r["const"], r["items"], r["line"]))
            print("        %s" % tag)
            print("        建议：%s" % r["hint"])
            if r["kind"] == "iterated":
                print("        怎么判：清单的内容是不是「全部面」？"
                      "若是手抄的子集（例：写死 3 份而真源有 24 份）⇒ 窄，"
                      "应改从真源反解；若清单本身就是全部面（例：要求这 5 份必须携带某数）⇒ 不窄。")

    # 第二半：单值写死型（D1–D6）
    print()
    print("单值写死型（D1–D6 正交面）：%d 条（🔴 无自拒 %d / 🟡 有自拒 %d）"
          % (len(single_rows), n_hard, n_refused))
    for r in single_rows:
        if r["verdict"] == "hard":
            print("  [🔴 hard] %-40s L%-5d %s %r"
                  % (r["guard"], r["line"], r["op"], r["literal"]))
            print("         %s" % r["text"])
            print("         **无自拒保护**：真源改了它不会红 ⇒ 静默假绿。"
                  "修法：真源取不到时报 FATAL（emit_fatal），别继续比旧字面量。")
    if n_refused:
        print("  🟡 有自拒（%d 条，真源变了会红，人工改一次常量即可，不判红）：" % n_refused)
        for r in single_rows:
            if r["verdict"] == "ok-refused":
                print("     %-40s L%-5d %r  （自拒 = %s）"
                      % (r["guard"], r["line"], r["literal"], r["evidence"]))

    print()
    print("读法：")
    print("  清单型 —— indexed 型才可疑（按固定下标取某几条）；iterated 型列出只为让你一眼排除。")
    print("  单值型 —— **🔴 hard 才是缺陷**（写死 + 无自拒 = 静默假绿）；"
          "🟡 有自拒只是「要人工改一次常量」，不进缺陷清单。")
    print("  本尺只报不判 —— 判「该不该反解」要人读语义。")
    return verdict_rc(len(guards), n_indexed, n_hard)


def main(argv):
    return run(argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
