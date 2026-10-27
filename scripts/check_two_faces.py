#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_two_faces.py —— 「两个面」漂移普查判据（R12）。

## 为什么需要它

本仓在 6 天内因**同一个根因**踩了 5 次：

| 标本 | 真源 | 第二个面 |
|---|---|---|
| BUG-420 | `namespace` 路由键 | 落库位置（实际写进哪个库） |
| BUG-425 | 文档原文 | 读数面（badge/摘要里的数字） |
| R10 内存/SQLite | 内存后端裁决 | SQLite 后端裁决 |
| R10 `rsv_action` | 四分支规则 | `ON CONFLICT ... WHERE` 的 SQL |
| **BUG-435** | `rsv_action` | `constraint.mbt` 的手工抄本 |

**根因一句话**：本仓的「单一真源」纪律靠注释表达、靠人遵守；
**真源与它的消费面/执行点之间没有机械化的对表判据。**

## 本判据能覆盖多少（**这是本脚本最重要的部分**）

五种「两面」形态，本脚本**只覆盖 ①②③**：

| # | 形态 | 可判据化 | 本脚本 |
|---|---|---|---|
| ① | 真源 vs **另一套执行点**（同语言，如内存 vs SQLite） | ✅ | 覆盖（同签名多定义） |
| ② | 真源 vs **SQL 编码**（谓词写进 SQL 字符串） | ✅ | 覆盖（源码里同规则的手写 SQL 谓词） |
| ③ | 真源 vs **手工抄本**（注释声称「镜像/等价」的重复定义） | ✅ | **主力覆盖** |
| ④ | 真源 vs **消费面的前提** | ❌ | **不覆盖** |
| ⑤ | 真源 vs **胶水的语义** | ❌ | **不覆盖** |

**⚠️ 为什么 ④/⑤ 不可判据化（写在这里，不写在 README 里）**：

- **形态 ④「消费面的前提」**：要检出，必须**枚举「这个面的前置条件」**。
  而前置条件通常**不写在代码里，写在作者脑子里** —— 典型是 BUG-433：
  C 案的三档诊断**都假设「路由发生了」**，而 `None => engine` 让这个前提不成立。
  **代码里没有任何文本表达「我假设路由发生了」**，所以没有可匹配的模式。
- **形态 ⑤「胶水的语义」**：要检出，必须**状态机时序建模** ——
  「绿了但语义错了」。典型是 BUG-431（sweep 先跑 ⇒ 留痕消失）与 BUG-429
  （`granted=false` 但标签说「续期成功」）。**每一步单看都合法**，
  只有把整条时序画出来才能发现 ⇒ 需要人给状态机，脚本无法从源码反推。

**⇒ 所以：本脚本 PASS 不代表「无两面」，只代表「形态 ①②③ 无两面」。**

## 判据（三条，全部静态 + 少量真跑）

- **F1 抄本漂移**：找到「注释声称与 X 等价/镜像」的函数，抽出它与被声称的参照，
  逐行比对函数体（归一化后）。**不同 ⇒ rc=1**。
- **F2 同签名多定义**：同一函数名在多个文件里有**实现**（非 trait 声明、非测试）
  ⇒ 提示「可能是一源多投影」，逐条列出供人判。**只告警不判红**（多后端是合法设计）。
- **F3 SQL 谓词对表**（**R16：无条件**）：把 `src/store/store_sqlite.mbt` 里
  `ON CONFLICT ... WHERE` 子句的比较符集合，与 `src/store/store_rsv.mbt` 里
  `rsv_action` 的比较符集合逐条对表；不一致 ⇒ DRIFT。
  **不依赖任何注释声称**（旧 docstring 曾写「注释声称时才查」，与实现相反，已改）。
  **高精度低召回**：只比比较符集合，不比名字/顺序。

**rc 契约**：`0` PASS（形态 ①②③ 无漂移）/ `1` 发现漂移（逐条点名）/ `2` 判据无法自证
（扫描面为空、找不到任何可判对象 ⇒ 拒绝出结论，绝不因"没找到"报绿）。

用法：
    python scripts/check_two_faces.py                 # 判据模式
    python scripts/check_two_faces.py --selftest      # 自证（含变异对照）
    python scripts/check_two_faces.py --json          # 机器可读
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

try:  # Windows cp936 控制台：不 reconfigure 会因 ✓/✗ 抛 UnicodeEncodeError
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")

# ── 覆盖面声明（运行时输出，不是 README） ──────────────────────────────────
COVERAGE = """[覆盖面] 本判据只覆盖 3/5 种「两面」形态：
  ✅ ①真源 vs 另一套执行点（同语言多实现）
  ✅ ②真源 vs SQL 编码（ON CONFLICT / WHERE 谓词）
  ✅ ③真源 vs 手工抄本（注释声称「镜像/等价」的重复定义）
  ❌ ④真源 vs 消费面的前提 —— 需要枚举「该面的前置条件」，那通常不写在代码里（BUG-433）
  ❌ ⑤真源 vs 胶水的语义 —— 需要状态机时序建模，每步单看都合法（BUG-431 / BUG-429）
[结论] 本脚本 PASS 不代表「无两面」，只代表「形态 ①②③ 无两面」。"""

RC_OK, RC_DRIFT, RC_BROKEN = 0, 1, 2


# ── 工具 ─────────────────────────────────────────────────────────────────
def iter_mbt(root: str):
    for dp, _dn, fn in os.walk(root):
        for f in fn:
            if f.endswith(".mbt") and not f.endswith(("_test.mbt", "_wbtest.mbt")):
                yield os.path.join(dp, f)


def read(p: str) -> str:
    with open(p, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def rel(p: str) -> str:
    """相对仓库根；跨盘（tempfile 在 C:、仓库在 E:）时退回绝对路径，不许抛。"""
    try:
        return os.path.relpath(p, ROOT).replace("\\", "/")
    except ValueError:
        return p.replace("\\", "/")


def norm(body: str) -> str:
    """归一化函数体：去注释、压空白、去尾部逗号 —— 只比语义骨架。"""
    out = []
    for ln in body.splitlines():
        s = ln.split("//")[0].rstrip()
        if s.strip():
            out.append(s.strip().rstrip(","))
    return " ".join(out)


FN_RE = re.compile(
    r"^(?:pub\s+)?fn\s+([A-Za-z_][\w:]*)\s*\(", re.M)


def functions(text: str):
    """粗粒度切函数体（按 `///|` 块 + 大括号配平）。产出 (name, body, start_line)。"""
    blocks = re.split(r"^///\|$", text, flags=re.M)
    line = 1
    for blk in blocks:
        m = None
        for mm in FN_RE.finditer(blk):
            m = mm
        if m:
            name = m.group(1)
            # 取大括号配平体
            i = blk.find("{", m.end())
            if i >= 0:
                depth, j = 0, i
                while j < len(blk):
                    if blk[j] == "{":
                        depth += 1
                    elif blk[j] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                yield name, blk[i : j + 1], line
        line += blk.count("\n")


# ── F1：抄本漂移（主力） ──────────────────────────────────────────────────
# 只抓「带明确参照名」的声称（`src/x/y.mbt::fn` 或 `same as `fn``）。
# 不抓裸「镜像/等价」——那类没有参照对象，无法对表。
# 本判据宁可漏判（F1-unresolved 会点名）也不误判。
# 收紧后的判据（R12）：必须同时满足
#   (a) 注释里出现**等价声称词**（镜像/等价/忠实/副本/抄自/同一条规则/same as/duplicate of）
#   (b) 且能从中抽出一个**明确的参照函数名**
# 只满足 (b) 的（如「从 `Task::to_json` 的 `"namespace"` 键读」）**不是等价声称**，
# 那只是在说「我用了它」，不构成「我是它的副本」。⇒ 上一版把这类当漂移，65/66 全是误报。
# ⚠️ 只收「**强副本关系**」词。实测剔除掉的泛用词及其误报形态（R12 分类依据）：
#   "等价于 X"         → instrumented_tool 的「等价于 .tool」是**功能等价**，不是副本
#   "等价副本"         → issue_scan 的「`to_owned()` 等价副本」是**值相等**，不是函数副本
#   "等价于 `f`"       → ops_watchdog 的「等价于 `watchdog_ts_newer`」是**语义相同**，实现独立
#   光有 `X::f` 引用    → 「从 `Task::to_json` 读键」是**使用**，不是副本（65 处误报的主因）
# 只认这些词：明确说「我是它的镜像/忠实镜像/抄自/duplicate of」。
EQUIV_WORDS = ("忠实镜像", "的镜像", "镜像自", "抄自", "副本自", "duplicate of",
               "mirror of", "identical to")
NAME_RE = re.compile(r"::([A-Za-z_][A-Za-z0-9_]*)|`([A-Za-z_][A-Za-z0-9_]*)`|same as `?([A-Za-z_][A-Za-z0-9_]*)`?")


def _equiv_ref(note: str):
    """从一段 doc 注释里抽「等价声称」的参照名；无声称 ⇒ None。"""
    low = note.lower()
    w = next((x for x in EQUIV_WORDS if x in note or x in low), None)
    if w is None:
        return None
    m = NAME_RE.search(note)
    if not m:
        return None
    return m.group(1) or m.group(2) or m.group(3)


def find_mirror_claims(root: str):
    """找「doc 注释里带明确参照名」的定义。

    判据：注释里出现 `xxx::fname` 或 `same as `fname`` ⇒ 该函数声称自己是 fname 的副本/镜像。
    只有带**明确参照名**的才算 —— 裸「镜像/等价」没有对表对象，本判据不猜（宁可漏判）。
    """
    fname_rx = None
    defs = {}
    for p in iter_mbt(root):
        for name, body, ln in functions(read(p)):
            defs.setdefault(name.split("::")[-1], []).append((p, ln, body))

    claims = []
    for p in iter_mbt(root):
        txt = read(p)
        lines_t = txt.splitlines()
        for name, body, ln in functions(txt):
            bare = name.split("::")[-1]
            # 定位本函数定义所在行
            fn_row = None
            for k in range(max(0, ln - 1), min(ln - 1 + 60, len(lines_t))):
                if re.search("\\bfn\\s+" + re.escape(bare) + "\\s*\\(", lines_t[k]):
                    fn_row = k
                    break
            if fn_row is None:
                continue
            # 向上收集连续 /// doc 行
            note = []
            k = fn_row - 1
            while k >= 0 and lines_t[k].lstrip().startswith("///"):
                note.append(lines_t[k])
                k -= 1
            note_s = "\n".join(reversed(note))
            if not note_s:
                continue
            ref = _equiv_ref(note_s)
            if not ref or ref == bare:
                continue
            claims.append({
                "file": rel(p), "line": ln, "name": bare,
                "ref": ref, "body": body,
                "ref_defs": defs.get(ref, []),
            })
    return claims

def check_f1(root: str):
    """F1：抄本与参照是否逐语义骨架相同。"""
    violations, checked = [], []
    for c in find_mirror_claims(root):
        if not c["ref_defs"]:
            # 声称了参照却找不到 ⇒ 判据无法核（不报红，但点名）
            checked.append({"kind": "F1-unresolved", "file": c["file"],
                            "line": c["line"], "name": c["name"], "ref": c["ref"]})
            continue
        for rp, rln, rbody in c["ref_defs"]:
            same = norm(c["body"]) == norm(rbody)
            item = {"kind": "F1", "file": c["file"], "line": c["line"],
                    "name": c["name"], "ref": c["ref"],
                    "ref_file": rel(rp), "ref_line": rln, "same": same}
            checked.append(item)
            if not same:
                violations.append(item)
    return violations, checked


# ── F2：同签名多定义（只告警） ────────────────────────────────────────────
def check_f2(root: str):
    """F2：同名函数在多文件有多份实现（只告警，不判红 —— 多后端可能是合法设计）。"""
    defs = {}
    for p in iter_mbt(root):
        for name, body, _ln in functions(read(p)):
            bare = name.split("::")[-1]
            nbody = norm(body)
            if not nbody:          # 空体（trait 声明）不计
                continue
            defs.setdefault(bare, []).append({"file": rel(p), "line": _ln,
                                              "len": len(nbody)})
    return {k: v for k, v in defs.items() if len(v) > 1}


# ── F3：SQL 谓词对表 ──────────────────────────────────────────────────────
SQL_CMP_RE = re.compile(r"(ttl_until|ttl|now|created_at)\s*(<=|>=|<>|!=|=|<|>)\s*"
                        r"(excluded\.\w+|\w+)")
MB_CMP_RE = re.compile(r"ttl\s*(<=|>=|<|>)\s*now")


def check_f3(root: str):
    """F3：**无条件**把两侧比较符对表（R16：不再依赖注释声称）。

    R16 改动：上一版 docstring 写「注释声称『SQL 编码的是同一条规则』时才查」——
    **但代码从来就是无条件的**（`check_f3` 里没有任何读注释的分支）。
    那是一句**与实现相反**的 docstring：读代码的人会以为「没在注释里声称就查不到」，
    从而要么误以为覆盖面比实际小、要么（更糟）照着这句去加注释以求被检查。
    ⇒ 本版把 docstring 改成与实现一致：**按判定形状扫，不看注释文字**。

    ⚠️ R12 修正（原版 100% 误报）：上一版在整个文件里抓所有 `ttl <=> x` 形式的比较符，
    把**别处逻辑**（`MemoryStore::locks_upsert` 的「旧锁是否仍 live」用 `old.ttl_until >= lock.ts`）
    当成 rsv_action 的投影 ⇒ 报 DRIFT，而 `rsv_action` 的投影是严格 `<`，**两侧本就一致**。

    当前只对表**真正成对的**两处（无条件，不要求任何注释）：
      · MoonBit 侧：`fn rsv_action` 体内的比较符
      · SQL 侧：`reservations` / `file_locks` 表的 `ON CONFLICT ... WHERE` 子句里的比较符
    其它比较符（如 live 判定）不属于这条规则，**不入表**。

    **高精度低召回**：只比比较符集合，不比名字/顺序 ⇒ 不报「名字不同但逻辑相同」。
    SQL 侧删掉 `ON CONFLICT ... WHERE` ⇒ 本面不产生条目（不误报 DRIFT）；
    由 selftest 的 `MUTATION-f3-no-where-no-false-drift` 钉住该行为。
    """
    findings = []
    rsv_mb = os.path.join(root, "store", "store_rsv.mbt")
    sqlite = os.path.join(root, "store", "store_sqlite.mbt")
    if not (os.path.isfile(rsv_mb) and os.path.isfile(sqlite)):
        return findings

    # MB 侧：只取 rsv_action 函数体
    mb_cmps = set()
    for name, body, _ln in functions(read(rsv_mb)):
        if name.split("::")[-1] == "rsv_action":
            mb_cmps |= set(m.group(1) for m in MB_CMP_RE.finditer(body))
    if not mb_cmps:
        return findings

    # SQL 侧：只取 ON CONFLICT ... WHERE 里的 ttl 比较符
    sql_cmps = set()
    for m in re.finditer(r"ON CONFLICT[^\"]*WHERE([^\"]*)", read(sqlite)):
        for cm in SQL_CMP_RE.finditer(m.group(1)):
            sql_cmps.add(cm.group(2))
    if not sql_cmps:
        return findings

    findings.append({
        "file": "src/store/store_rsv.mbt ↔ src/store/store_sqlite.mbt",
        "sql_cmp": sorted(sql_cmps), "mb_cmp": sorted(mb_cmps),
        "aligned": sql_cmps == mb_cmps,
    })
    return findings


# ── 主判据 ───────────────────────────────────────────────────────────────
def judge(root: str = SRC):
    v1, c1 = check_f1(root)
    f2 = check_f2(root)
    f3 = check_f3(root)
    f3_bad = [x for x in f3 if not x["aligned"]]

    scanned = sum(1 for _ in iter_mbt(root))
    # 自拒：扫描面为空 / 一个 F1 对象都没找到 ⇒ 判据无法自证
    if scanned == 0 or not c1:
        return RC_BROKEN, {
            "scanned_files": scanned, "f1_checked": [], "f1_checked_n": len(c1),
            # R16：自拒分支也必须带齐**全部**结果键 ——
            # 否则调用方 `res["f3_violations"]` 会 KeyError（不是"没漂移"，是"键不存在"）。
            # 这正是「缺键 ≠ 空值」判例：缺键必须显式补空值，不能靠调用方 get() 兜。
            "f1_violations": v1,
            "f2_multi_def": {k: v for k, v in sorted(f2.items())},
            "f3_checked": f3, "f3_violations": f3_bad,
            "note": "扫描面为空或无可判对象 ⇒ 拒绝出结论（绝不因「没找到」报绿）",
        }
    res = {
        "scanned_files": scanned,
        "f1_checked": c1, "f1_violations": v1,
        "f2_multi_def": {k: v for k, v in sorted(f2.items())},
        "f3_checked": f3, "f3_violations": f3_bad,
        "coverage": "3/5",
    }
    return (RC_DRIFT if (v1 or f3_bad) else RC_OK), res


def render(res) -> str:
    print(COVERAGE)
    print()
    if "note" in res:
        print("[FATAL] " + res["note"])
        return
    print("[扫描] .mbt 文件 %d 个 · F1 可判对象 %d 条" % (
        res["scanned_files"], res.get("f1_checked_n", len(res["f1_checked"]))))
    print()
    print("[F1 抄本漂移] 覆盖形态 ③")
    for c in res["f1_checked"]:
        if c["kind"] == "F1-unresolved":
            print("  ? %s:%d %s — 声称镜像 `%s` 但找不到参照（未判）" % (
                c["file"], c["line"], c["name"], c["ref"]))
        elif c["same"]:
            print("  ✓ %s:%d %s == %s:%d %s" % (
                c["file"], c["line"], c["name"], c["ref_file"], c["ref_line"],
                c["ref"]))
        else:
            print("  ✗ DRIFT %s:%d %s ≠ %s:%d %s" % (
                c["file"], c["line"], c["name"], c["ref_file"], c["ref_line"],
                c["ref"]))
    print()
    print("[F2 同签名多定义] 覆盖形态 ① —— **只告警不判红**（多后端可能是合法设计）")
    multi = res["f2_multi_def"]
    if multi:
        for name, defs in list(multi.items())[:12]:
            print("  · %-30s %d 处：%s" % (
                name, len(defs), ", ".join("%s:%d" % (d["file"], d["line"]) for d in defs[:4])))
        if len(multi) > 12:
            print("  … 另有 %d 组" % (len(multi) - 12))
    else:
        print("  （无）")
    print()
    print("[F3 SQL 谓词对表] 覆盖形态 ②")
    if res["f3_checked"]:
        for f in res["f3_checked"]:
            mark = "✓" if f["aligned"] else "✗ DRIFT"
            print("  %s %s  SQL=%s  MB=%s" % (mark, f["file"], f["sql_cmp"], f["mb_cmp"]))
    else:
        print("  ? 未找到「注释声称 SQL 同规则且两侧比较符都可解析」的文件（未判）")
    print()
    nv = len(res["f1_violations"]) + len(res["f3_violations"])
    if nv:
        print("[结论] 发现 %d 处漂移（形态 ①②③ 范围内）" % nv)
    else:
        print("[结论] 形态 ①②③ 无漂移。**这不代表无两面** —— ④⑤ 不在本判据覆盖面内。")


# ── selftest（判例-5 同族：必须给执行面；判例-29/30：必须有变异对照） ────────
def selftest() -> int:
    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-46s got=%r want=%r" % ("OK" if got == want else "FAIL", name, got, want))

    print("[selftest] 临时裸目录端到端（不碰真 src/）")
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        os.makedirs(os.path.join(td, "pkg"))
        pkg = os.path.join(td, "pkg")

        # ── 格1：抄本与参照完全相同 ⇒ 不报漂移 ──
        with open(os.path.join(pkg, "a.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\npub fn real_one(p : Int) -> Int {\n  p + 1\n}\n")
        with open(os.path.join(pkg, "b.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\n/// 本函数是 `a.mbt::real_one` **的镜像**。\n"
                     "pub fn copy_one(p : Int) -> Int {\n  p + 1\n}\n")
        rc, res = judge(pkg)
        cell("copy-identical-no-drift", rc, RC_OK)
        cell("copy-identical-f1-count", len(res["f1_checked"]), 1)
        cell("copy-identical-no-violation", len(res["f1_violations"]), 0)

        # ── 格2（★变异对照）：把抄本改坏一个字符 ⇒ 必须报漂移 ──
        with open(os.path.join(pkg, "b.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\n/// 本函数是 `a.mbt::real_one` **的镜像**。\n"
                     "pub fn copy_one(p : Int) -> Int {\n  p + 2\n}\n")
        rc2, res2 = judge(pkg)
        cell("MUTATION-copy-drift-detected", rc2, RC_DRIFT)
        cell("MUTATION-drift-count", len(res2["f1_violations"]), 1)

        # ── 格3（★变异对照 2）：比较符 < → <= 必须被判为漂移 ──
        with open(os.path.join(pkg, "b.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\n/// 本函数是 `a.mbt::real_one` **的镜像**。\n"
                     "pub fn copy_one(p : Int) -> Int {\n  if p < 1 { 0 } else { 1 }\n}\n")
        with open(os.path.join(pkg, "a.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\npub fn real_one(p : Int) -> Int {\n  if p <= 1 { 0 } else { 1 }\n}\n")
        rc3, _ = judge(pkg)
        cell("MUTATION-lt-vs-le-detected", rc3, RC_DRIFT)

        # ── 格4：注释里的字面量不得自命中（判例-30）──
        # 参照名在注释里出现、但函数体相同 ⇒ 不应报漂移
        with open(os.path.join(pkg, "a.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\npub fn real_one(p : Int) -> Int {\n  p + 1\n}\n")
        with open(os.path.join(pkg, "b.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\n/// 注意：**不是** `real_one` 的镜像（本行含参照名但不声称等价）。\n"
                     "/// 本函数是 `a.mbt::real_one` **的镜像**。\n"
                     "pub fn copy_one(p : Int) -> Int {\n  p + 1\n}\n")
        rc4, _ = judge(pkg)
        cell("comment-literal-no-false-red", rc4, RC_OK)

        # ── 格5：空扫描面 ⇒ 自拒 rc=2（绝不报绿）──
        empty = os.path.join(td, "empty")
        os.makedirs(empty)
        rc5, res5 = judge(empty)
        cell("empty-scan-self-reject", rc5, RC_BROKEN)
        cell("empty-scan-has-note", "note" in res5, True)

        # -- cell6: F2 same-name multi-def needs TWO implementations --
        with open(os.path.join(pkg, "c.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\npub fn dup_me(p : Int) -> Int {\n  p + 1\n}\n")
        with open(os.path.join(pkg, "d.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\npub fn dup_me(p : Int) -> Int {\n  p + 2\n}\n")
        rc6, res6 = judge(pkg)
        cell("multi-def-detected", "dup_me" in res6["f2_multi_def"], True)
        cell("multi-def-count", len(res6["f2_multi_def"].get("dup_me", [])), 2)
        cell("multi-def-does-not-fail", rc6 in (RC_OK, RC_DRIFT), True)

        # -- cell7: coverage declaration MUST be in runtime output (not just docstring) --
        import contextlib, io as _io
        buf = _io.StringIO()
        with contextlib.redirect_stdout(buf):
            render({"scanned_files": 0, "f1_checked": [], "f1_violations": [],
                    "f2_multi_def": {}, "f3_checked": [], "f3_violations": []})
        out = buf.getvalue()
        cell("coverage-3of5-in-output", "3/5" in out, True)
        cell("coverage-names-form4", chr(28040)+chr(36153)+chr(38754)+chr(30340)+chr(21069)+chr(25552) in out, True)
        cell("coverage-names-form5", chr(33014)+chr(27700)+chr(30340)+chr(35821)+chr(20041) in out, True)
        cell("coverage-pass-not-full", chr(19981)+chr(20195)+chr(34920) in out, True)

        # ── 格 8~10：★ F3 SQL 谓词对表的三个变异对照（R16）──
        #
        # 为什么必须补这三格：格 2/3 的变异只测 **F1 抄本漂移**，
        # **F3（SQL 谓词对表）此前没有任何变异对照** ⇒ 把 check_f3 整个删掉、
        # 或把它改成恒 true，自检**照样全绿**（判例-29：机制格 ≠ 实现路径格）。
        #
        # 造法：在临时裸目录里搭一对最小 store 包（store_rsv.mbt + store_sqlite.mbt），
        # 只放 rsv_action 与一条 ON CONFLICT ... WHERE，然后分别变异两侧。
        f3pkg = os.path.join(td, "f3pkg", "store")
        os.makedirs(f3pkg)
        # ⚠️ 必须同时造一个**可判的 F1 对象**，否则 judge() 会走「一个 F1 对象都没找到 ⇒ 自拒」
        # 分支并返回 RC_BROKEN(2)，把 F3 的 DRIFT 吃掉（实测踩到：F3 违反计数正确为 1，
        # 但整体 rc=2）。F1 的可判对象 = 一个带「镜像/等价」声称且参照存在的定义 ⇒
        # 这里造一对内容**相同**的最小镜像（不产生 F1 违例），只为让判据不进入自拒分支。
        with open(os.path.join(td, "f3pkg", "anchor_a.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\npub fn anchor_real(p : Int) -> Int {\n  p + 1\n}\n")
        with open(os.path.join(td, "f3pkg", "anchor_b.mbt"), "w", encoding="utf-8") as fh:
            fh.write("///|\n/// 本函数是 `anchor_a.mbt::anchor_real` **的镜像**。\n"
                     "pub fn anchor_copy(p : Int) -> Int {\n  p + 1\n}\n")

        def _write_f3(rsv_cmp, sql_cmp, drop_where=False):
            """按给定比较符写一对最小 store 文件。drop_where=True 时删掉 ON CONFLICT 子句。"""
            with open(os.path.join(f3pkg, "store_rsv.mbt"), "w", encoding="utf-8") as fh:
                fh.write(
                    "///|\n"
                    "pub fn rsv_action(prev : String, agent : String, now : String) -> String {\n"
                    "  if ttl " + rsv_cmp + " now { \"taken_over\" } else { \"conflict\" }\n"
                    "}\n")
            sql = ("INSERT INTO reservations (scope) VALUES (?) "
                   "ON CONFLICT(scope) DO UPDATE SET agent=excluded.agent "
                   "WHERE reservations.ttl_until " + sql_cmp + " excluded.created_at")
            if drop_where:
                sql = "INSERT INTO reservations (scope) VALUES (?) ON CONFLICT(scope) DO NOTHING"
            with open(os.path.join(f3pkg, "store_sqlite.mbt"), "w", encoding="utf-8") as fh:
                fh.write('///|\n/// 表\nlet sql = "' + sql + '"\n')

        # 格 8（基线）：两侧都是 < ⇒ 对齐，不得报漂移
        _write_f3("<", "<")
        rc8, res8 = judge(os.path.join(td, "f3pkg"))
        cell("f3-baseline-aligned", len(res8["f3_violations"]), 0)
        cell("f3-baseline-checked", len(res8["f3_checked"]), 1)

        # 格 9（★变异 A）：**MB 侧** < → <= ⇒ 必须报 DRIFT
        _write_f3("<=", "<")
        rc9, res9 = judge(os.path.join(td, "f3pkg"))
        cell("MUTATION-f3-mb-cmp-drift-detected", rc9, RC_DRIFT)
        cell("MUTATION-f3-mb-cmp-violation-count", len(res9["f3_violations"]), 1)

        # 格 10（★变异 B）：**SQL 侧** < → <= ⇒ 必须报 DRIFT
        _write_f3("<", "<=")
        rc10, res10 = judge(os.path.join(td, "f3pkg"))
        cell("MUTATION-f3-sql-cmp-drift-detected", rc10, RC_DRIFT)
        cell("MUTATION-f3-sql-cmp-violation-count", len(res10["f3_violations"]), 1)

        # 格 11（★变异 C）：删掉 SQL 侧 ON CONFLICT ... WHERE ⇒
        #   不是 DRIFT，而是「无法对表」⇒ check_f3 返回空 ⇒ **不得报漂移**、
        #   但整体也不得因此变成绿（其余面仍照常判）。
        #   本格断言「SQL 侧无比较符时不产生 F3 条目」（高精度：不误报）。
        _write_f3("<", "<", drop_where=True)
        rc11, res11 = judge(os.path.join(td, "f3pkg"))
        cell("MUTATION-f3-no-where-no-false-drift", len(res11["f3_violations"]), 0)
        cell("MUTATION-f3-no-where-not-checked", len(res11["f3_checked"]), 0)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    if ok != len(cells):
        print("[selftest] ✗ 有格未通过 —— 判据自身坏了（rc=4 契约由调用方处理）")
        return 4
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--root", default="")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    root = a.root or SRC
    rc, res = judge(root)
    if a.json:
        print(json.dumps({**res, "rc": rc, "coverage": "3/5",
                          "coverage_note": COVERAGE}, ensure_ascii=False, indent=1))
    else:
        render(res)
    return rc


if __name__ == "__main__":
    sys.exit(main())
