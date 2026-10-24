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


def judge(rel, text):
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
    cell("judge-flags-indexed", [r[0] for r in judge("scripts/check_bad.py", bad)], ["BAD_FILES"])
    good = 'OK_FILES = (\n    "a.mbti",\n    "b.mbti",\n)\nfor f in OK_FILES:\n    use(f)\n'
    # 设计如此：iterated **也列出**，但标 iterated 让人一眼排除（不静默丢弃 = 数字不能凭空少）
    _gj = judge("scripts/check_good.py", good)
    cell("judge-marks-iterated-not-indexed",
         [(r[0], r[3]) for r in _gj], [("OK_FILES", "iterated")])
    # 反向验证（这三格钉住「修复前的形态必须能被看见」）：
    # ① check_mbti_eol 修复前的形态（硬编码 3 份 + for 遍历）必须**被列出**（needs-review）
    _before = ('MBTI_FILES = (\n    "a.mbti",\n    "b.mbti",\n    "c.mbti",\n)\n'
               'for rel in MBTI_FILES:\n    pass\n')
    cell("reverse-mbti-before-fix-is-listed",
         [(r[0], r[3]) for r in judge("x.py", _before)], [("MBTI_FILES", "iterated")])
    # ② 单值常量（check_esm_bundle_runnable 修复前的 DEFAULT_BUNDLE）**不在本尺射程**
    #    —— 诚实缺口：本尺只认「清单」，单值写死由「覆盖面自证格」在各自尺里钉
    cell("reverse-single-const-out-of-scope",
         judge("x.py", 'DEFAULT_BUNDLE = "a/cli.js"\n'), [])
    # ③ 典型 indexed 形态必须判为 indexed（最高可疑）
    cell("reverse-indexed-detected",
         [(r[0], r[3]) for r in judge("x.py", 'SCAN_FILES = (\n    "a",\n    "b",\n)\nf = SCAN_FILES[0]\n')],
         [("SCAN_FILES", "indexed")])
    # 名字不像覆盖清单的，即使 indexed 也不报
    other = 'REG = (\n    "a",\n    "b",\n)\nuse(REG[0])\n'
    cell("judge-skips-other-name", [r[0] for r in judge("scripts/check_other.py", other)], [])

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
    cell("fatal-on-empty-face", verdict_rc(0, 0), 2)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def verdict_rc(n_guards, n_indexed):
    """纯函数：由读数给退出码（便于单测）。空扫描=2；--strict 且有 indexed=1；否则 0。"""
    if n_guards <= 0:
        return 2
    if n_indexed > 0 and "--strict" in sys.argv:
        return 1
    return 0


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
    for rel in guards:
        p = os.path.join(ROOT, rel)
        try:
            txt = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            unreadable.append(rel)
            continue
        for name, n, line, kind, hint in judge(rel, txt):
            rows.append({"guard": rel, "const": name, "items": n, "line": line,
                         "kind": kind, "hint": hint})

    n_indexed = sum(1 for r in rows if r["kind"] == "indexed")
    n_iterated = sum(1 for r in rows if r["kind"] == "iterated")

    if args.json:
        print(json.dumps({"guards": len(guards), "unreadable": unreadable,
                          "findings": rows, "indexed": n_indexed,
                          "iterated": n_iterated}, ensure_ascii=False, indent=1))
        return verdict_rc(len(guards), n_indexed)

    print("扫描面：%d 份 check_*.py（真源 git ls-files '%s'）" % (len(guards), SCAN_GLOB))
    if unreadable:
        print("  读不到 %d 份：%s" % (len(unreadable), ", ".join(unreadable[:5])))
    if not rows:
        print("PASS 未发现「硬编码小清单 + 进了判定路径」的形状（%d 份尺全查）" % len(guards))
        return verdict_rc(len(guards), n_indexed)

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
    print()
    print("读法：indexed 型才可疑（常量按固定下标取某几条）；iterated 型清单本身就是全部面，"
          "列出只为让你一眼排除。本尺只报不判 —— 判「该不该反解」要人读语义。")
    return verdict_rc(len(guards), n_indexed)


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
