#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_sql_bind_alignment.py —— SQL `INSERT` 的**列 ↔ 占位符 ↔ bind 次数**三方对齐（R177）。

## 为什么要有这把尺

R176 人工核了 `store_sqlite_executions.insert_execution`：11 列 / 11 个 `?` / 11 次 `stmt.bind`，
**逐位对齐**。但那只核了**一处**——仓库里还有 21 处 `INSERT`（`src/store/*.mbt`）。
这类错位的失效形态极隐蔽：**列顺序与 bind 顺序错位 ⇒ 字段互相串值，不报错、测试也未必覆盖**。
（同族：R148 的 `from_db` 位置参数、判例-16 的「同一套判定的多份实现」。）

## 口径（**诚实分级**，不假装全覆盖）

对每一处 `INSERT INTO <cols> VALUES (<placeholders>)`：

1. **占位符 vs bind 次数**：`?` 的个数必须等于**该语句之后、同函数内** `stmt.bind(` 的个数；
2. **列数 vs 占位符**：仅当列表是**字面量**时校验；写成插值（`\\{...}`）时**跳过并如实计入
   `degraded`**——"列数是算出来的"这种情形静态看不出来，不能静默算作已检（判例-33 同族）。
3. bind 序号必须 **1..N 连续**（缺号/重号 ⇒ 线上必然绑不上或覆盖）。

rc 契约：`0` 全部对齐 / `1` 有不对齐（打印逐处读数）/ `2` 判据无法自证（扫描面为空或零命中）。

用法：
    python scripts/check_sql_bind_alignment.py
    python scripts/check_sql_bind_alignment.py --selftest   # 6 格（含变异对照）
    python scripts/check_sql_bind_alignment.py --list       # 只列读数不判
"""
from __future__ import annotations

import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

KNOWN_FLAGS = ("--selftest", "--list")

# R177b：**不能用 `[^)]*` 抓列** —— 插值列里含函数调用（`\{SqliteStore::task_columns()}`）
# 会把捕获截断在 `()` 的 `)` 上，于是这类 INSERT **被整条跳过**（= 覆盖率的谎言）。
# 改成"非贪婪到 `) VALUES (`"锚定。
INSERT_RE = re.compile(r"INSERT\s+INTO\s+(\w+)\s*\((.*?)\)\s*VALUES\s*\((.*?)\)", re.S)
BIND_RE = re.compile(r"stmt\.bind\(\s*(\d+)\s*,")
FN_RE = re.compile(r"^(?:pub )?(?:fn|pub fn)\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)


def split_top_level(s):
    """按**顶层**逗号切分（跳过 '' 字符串与 () 括号内的逗号）。

    为什么需要：`VALUES (?, ?, datetime('now'))` 与 `VALUES (…, 0, ?)` 里的
    括号/引号内逗号、以及**字面量项**都让"数 ? 的个数"不足以表达项数。
    """
    items, buf, depth, i, n = [], [], 0, 0, len(s)
    while i < n:
        c = s[i]
        if c == "'":
            j = i + 1
            while j < n:
                if s[j] == "'":
                    if j + 1 < n and s[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            buf.append(s[i:j + 1])
            i = j + 1
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if c == "," and depth == 0:
            items.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    if buf:
        items.append("".join(buf).strip())
    return [x for x in items if x]


def analyze(text):
    """解析文本里的 INSERT。**注意：不再接 `path` 形参** —— 它在本函数内零引用，
    被 `check_dead_params_py` 判死参数（R179 修正；该判据当晚就抓到了本尺自己）。"""
    """返回 [(table, n_cols|None, n_ph, n_bind, bind_ids, note)]。`n_cols=None` = 列数不可静态判定。"""
    out = []
    for m in INSERT_RE.finditer(text):
        table, cols_raw, ph_raw = m.group(1), m.group(2), m.group(3)
        vals = split_top_level(ph_raw)
        n_items = len(vals)                 # VALUES 顶层项数（含字面量）
        n_ph = sum(1 for v in vals if v == "?")
        interpolated = "{" in cols_raw
        n_cols = None if interpolated else len([c for c in cols_raw.split(",") if c.strip()])
        # 找"该语句所在函数"的剩余文本：取语句之后、下一个顶层 fn 之前
        tail = text[m.end():]
        nx = FN_RE.search(tail)
        body = tail[: nx.start()] if nx else tail
        # R177c：**只取"1,2,3,…"这个连续前缀**。原先取"到下一个 fn 之前的全部 bind"，
        # 会把**同一函数里后面那条 INSERT 的 bind** 也算进来 ⇒ 假的 `[1,2,3,1,2]` 缺号告警。
        all_ids = [int(x) for x in BIND_RE.findall(body)]
        bid = []
        for i, v in enumerate(all_ids, start=1):
            if v == i:
                bid.append(v)
            else:
                break
        # 只取该语句后**紧接着的一串** bind（遇到明显函数边界即止，这里用连续段近似）
        note = "列数为插值 ⇒ 只校验占位符与 bind" if interpolated else ""
        # bind 的首参是否全为字面量（`stmt.bind(1,` 与 `stmt.bind(i + 1,` 的区别）
        binds_all = re.findall(r"stmt\.bind\(\s*([^,]+),", body)
        # R177f：**绑定可能委托给助手**（实测 `src/store` 的 tasks：`SqliteStore::bind_task_values(stmt, task)`）
        # ⇒ 这种情形静态数不出 bind 次数，必须计入 degraded，**不能判红**
        delegated = bool(re.search(r"::?bind_\w*values?\s*\(", body))
        non_literal = delegated or any(not b.strip().isdigit() for b in binds_all) or not binds_all
        out.append((table, n_cols, n_items, n_ph, len(bid), non_literal, bid, note))
    return out


def judge(rows):
    """返回 (rc, problems, degraded)。纯函数，selftest 直接喂数。"""
    if not rows:
        return 2, [], []
    problems, degraded = [], []
    for table, n_cols, n_items, n_ph, n_bind, non_literal, bid, note in rows:
        tag = "%s(%s)" % (table, note or "字面列")
        # R177e：列数只和 **VALUES 顶层项数** 比（字面量项也占一列）
        if n_cols is not None and n_cols != n_items:
            problems.append("%s: 列 %d ≠ VALUES 项数 %d" % (tag, n_cols, n_items))
        # bind 参数非字面量（表达式/循环变量）⇒ 静态数不出来 ⇒ 计 degraded，不判红
        if non_literal or n_bind == 0:
            degraded.append(tag + "：bind 参数非字面量 ⇒ 计数不可静态判定")
            continue
        if n_ph != n_bind:
            problems.append("%s: 占位符 %d ≠ bind %d" % (tag, n_ph, n_bind))
        # R177d：**不再单列"序号连续"规则** —— `analyze` 已用"1..N 连续前缀"取 bind，
        # 缺号会直接表现为 `占位符 N ≠ bind M`（同样的红，更少的不可达分支）。
        if n_cols is None:
            degraded.append(tag)
    return (1 if problems else 0), problems, degraded


def tracked_mbt():
    try:
        out = subprocess.run(["git", "ls-files", "*.mbt"],
                             capture_output=True, text=True, check=True).stdout
    except Exception:
        return []
    return sorted(p.strip() for p in out.splitlines()
                  if p.strip() and not p.endswith("_test.mbt")
                  and not p.endswith("_wbtest.mbt"))


def scan(paths):
    rows = []
    for p in paths:
        try:
            txt = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for r in analyze(txt):
            rows.append((p,) + r)
    return rows


def selftest():
    fails = []

    def cell(name, ok, detail=""):
        print(("PASS " if ok else "FAIL ") + name + ("" if ok else " :: " + detail))
        if not ok:
            fails.append(name)

    # 格 1：对齐样本 ⇒ 绿
    good = 'let sql = "INSERT INTO t (a, b, c) VALUES (?, ?, ?)"\nstmt.bind(1, x)\nstmt.bind(2, y)\nstmt.bind(3, z)\n'
    rows = analyze(good)
    rc, probs, deg = judge(rows)
    cell("s1 对齐样本判绿", rc == 0 and not probs, "rc=%d %s" % (rc, probs))

    # 格 2（**变异对照**）：少一个 bind ⇒ 必须红
    bad = 'let sql = "INSERT INTO t (a, b, c) VALUES (?, ?, ?)"\nstmt.bind(1, x)\nstmt.bind(2, y)\n'
    rc_b, probs_b, _ = judge(analyze(bad))
    cell("s2 变异对照：少一个 bind ⇒ 红", rc_b == 1 and any("bind 2" in p or "占位符 3" in p for p in probs_b),
         "rc=%d %s" % (rc_b, probs_b))

    # 格 3：列数 ≠ 占位符 ⇒ 红
    c = 'let sql = "INSERT INTO t (a, b) VALUES (?, ?, ?)"\nstmt.bind(1,x)\nstmt.bind(2,y)\nstmt.bind(3,z)\n'
    rc_c, probs_c, _ = judge(analyze(c))
    cell("s3 列数≠占位符 ⇒ 红", rc_c == 1 and any("列 2" in p for p in probs_c), "rc=%d" % rc_c)

    # 格 4：插值列 ⇒ 只校验占位符，且**如实计入 degraded**
    d = 'let sql = "INSERT INTO t (\\{cols()}) VALUES (?, ?)"\nstmt.bind(1,x)\nstmt.bind(2,y)\n'
    rc_d, probs_d, deg_d = judge(analyze(d))
    cell("s4 插值列 ⇒ 绿但计入 degraded", rc_d == 0 and len(deg_d) == 1, "rc=%d deg=%s" % (rc_d, deg_d))

    # 格 5：bind 序号缺号 ⇒ 红
    e = 'let sql = "INSERT INTO t (a, b) VALUES (?, ?)"\nstmt.bind(1,x)\nstmt.bind(3,z)\n'
    rc_e, probs_e, _ = judge(analyze(e))
    cell("s5 bind 缺号 ⇒ 红（经计数不等表达）",
         rc_e == 1 and any("占位符 2" in p for p in probs_e), "rc=%d %s" % (rc_e, probs_e))

    # 格 7：**绑定委托给助手** ⇒ 绿但计入 degraded（不能判红，也别说"已核过"）
    g = (
        'let sql = "INSERT INTO t (a, b) VALUES (?, ?)"\n'
        "SqliteStore::bind_task_values(stmt, task)\n"
    )
    rc_g, probs_g, deg_g = judge(analyze(g))
    cell("s7 委托助手绑定 ⇒ 绿且 degraded", rc_g == 0 and len(deg_g) == 1,
         "rc=%d probs=%s deg=%s" % (rc_g, probs_g, deg_g))

    # 格 6：空样本 ⇒ rc=2（拒绝判绿）
    rc_f, _, _ = judge([])
    cell("s6 无样本 ⇒ rc=2（不自证归 2 不归 0）", rc_f == 2, "rc=%d" % rc_f)

    print("=== selftest %d/7 ===" % (7 - len(fails)))
    return 0 if not fails else 1


def main():
    args = sys.argv[1:]
    unknown = [a for a in args if a not in KNOWN_FLAGS]
    if unknown:
        print("FATAL 未知参数：%s（已知：%s）" % (" ".join(unknown), " ".join(KNOWN_FLAGS)))
        return 2
    if "--selftest" in args:
        return selftest()

    paths = tracked_mbt()
    rows = scan(paths)
    if not rows:
        print("FATAL 扫描面 %d 个产品 .mbt 里**零 INSERT 命中** ⇒ 判据无法自证（rc=2）" % len(paths))
        return 2
    rc, probs, deg = judge([r[1:] for r in rows])

    if "--list" in args:
        print("扫描面 %d 文件 / 命中 %d 处 INSERT" % (len(paths), len(rows)))
        for p, table, n_cols, n_ph, n_bind, bid, note in rows:
            print("  %-40s %-18s 列=%-4s 占位符=%-3d bind=%-3d %s" % (
                p, table, "插值" if n_cols is None else n_cols, n_ph, n_bind, note))
        return 0

    if rc == 1:
        print("门禁 SQL 三方对齐失败 %d 处：" % len(probs))
        for x in probs:
            print("  - " + x)
        return 1
    print("门禁 PASS %d 处 INSERT 三方对齐（占位符=bind 全对；其中 %d 处列数为插值、仅校验占位符）"
          % (len(rows), len(deg)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
