#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_byte_slice_truncation.py —— **中文文本字节硬切**的常驻判据（R154）。

## 为什么要有这把尺

R148/R149 修了 `replace` 只替首个（一类），R152/R153 修了 `[0:N]` 字节硬切（另一类）。
后者在这仓特别容易复发：**MoonBit 的 `String` 长度按字节算**，`len > 40 ⇒ s[0:40]`
在英文上完全正确，在中文上会**切在字符中间**（半个汉字）。

仓库**已经有**正确实现：`src/core/core_task.mbt` 的 `clip_utf8`（逐字节回退到字符边界），
R152 已把它提升为 `pub` 并在文档里写「不要自己写 `[0:N]`」—— 但**文档拦不住新代码**。

## 判据口径（棘轮，不是"全禁"）

- 扫 **git 跟踪的**产品 `.mbt`（跳过 `_test` / `_wbtest`）；
- **跳过注释行**（判例-30：本判据自己的文档就写着 `desc[0:40]`，把注释算进去 = 锁坏了）；
- 找 `[0:N]`（N 为数字）切片，取前面的表达式基底；
- 命中 `EXEMPT`（**逐条带理由**）→ 放行；否则 **rc=1** 并打印全部未解释点。

⚠️ **本判据只看形状，不看语义** —— 它不能证明某个 `[0:N]` 切的是中文，只能保证
**每个新增的硬切都被显式解释过一次**。语义判定要人，形态判定归机器。

退出码：`0` 全部已解释 / `1` 有未解释的硬切 / `2` 判据无法自证（扫描面或命中面为空）。
"""
from __future__ import annotations

import io
import os
import re
import subprocess
import sys
import tempfile

# 打印含中文（结论行/文件路径）⇒ 必须固定 stdout/stderr 编码，否则本机 GBK 控制台
# 一红就崩在结论行之前，rc 会被冒用成「缺陷在场」（check_py_stdout_encoding E1）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SLICE_RE = re.compile(r"([A-Za-z_][A-Za-z0-9_.]*)\s*\[0:(\d+)\]")

# 逐条带理由的豁免表（键 = 仓库相对路径 + "::" + 表达式基底）
EXEMPT = {
    "src/evolve/evolve.mbt::a.id": "asset id（[principle]/[lesson] + 短 hash），纯 ASCII",
    "src/evolve/lesson.mbt::compact": "时间戳去分隔符（YYYYMMDD.HH.MM.SS），纯 ASCII",
    "src/server/evolve_distill.mbt::compact": "同上（distill 侧的时间戳片段）",
    "src/server/board_ascii.mbt::tid": "task id（TASK-xxx / r<轮>-<序号>），纯 ASCII",
    "src/server/run_check_guard.mbt::s": "盘符（C:），纯 ASCII",
    # ⚠️ 以下这处**未修**，不是"安全"，是"要动跨包依赖，待 owner"：
    "src/evolve/curriculum.mbt::note":
        "中文 note 的硬切**确实不安全**；src/evolve 不依赖 core，复用 clip_utf8 需新增跨包依赖（R152 记 OPEN）",
}


def tracked_mbt_files() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "*.mbt"],
            capture_output=True, text=True, check=True,
        ).stdout
    except Exception:
        return []
    files = []
    for line in out.splitlines():
        p = line.strip()
        if not p or p.endswith("_test.mbt") or p.endswith("_wbtest.mbt"):
            continue
        files.append(p)
    return sorted(files)


def scan(paths: list[str]) -> list[tuple[str, str, int, int]]:
    """返回 [(path, base, cap, lineno)]，**跳过注释行**。"""
    hits = []
    for p in paths:
        try:
            text = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("//"):
                continue
            for m in SLICE_RE.finditer(line):
                hits.append((p, m.group(1), int(m.group(2)), i))
    return hits


def judge(paths: list[str], base_dir: str | None = None) -> tuple[int, list, list]:
    """返回 (rc, unexplained, explained)。base_dir 仅自检用（绝对路径折成相对键）。"""
    if not paths:
        return 2, [], []
    hits = scan(paths)
    if not hits:
        return 2, [], []
    unexplained, explained = [], []
    for p, base, cap, ln in hits:
        rel = os.path.relpath(p, base_dir).replace(os.sep, "/") if base_dir else p
        key = "%s::%s" % (rel, base)
        (explained if key in EXEMPT else unexplained).append((key, cap, ln))
    return (1 if unexplained else 0), unexplained, explained


def selftest() -> int:
    fails = []

    def check(name, ok, detail=""):
        print(("PASS " if ok else "FAIL ") + name + ((" :: " + detail) if detail and not ok else ""))
        if not ok:
            fails.append(name)

    def sample(files):
        d = tempfile.mkdtemp(prefix="bs_")
        out = []
        for name, body in files.items():
            full = os.path.join(d, name)
            parent = os.path.dirname(full)
            if parent:
                os.makedirs(parent, exist_ok=True)
            io.open(full, "w", encoding="utf-8").write(body)
            out.append(full)
        return out, d

    # 格 1：已豁免的基底 ⇒ 绿
    p1, d1 = sample({"src/server/board_ascii.mbt": "let x = desc[0:40]\n"})
    EXEMPT["src/server/board_ascii.mbt::desc"] = "selftest 临时豁免"
    rc, un, ex = judge(p1, base_dir=d1)
    check("s1 豁免表命中即放行", rc == 0 and len(ex) == 1 and not un, "rc=%d" % rc)

    # 格 2：未豁免的基底 ⇒ 红
    p2, d2 = sample({"src/server/x.mbt": "let x = body[0:80]\n"})
    rc, un, ex = judge(p2, base_dir=d2)
    check("s2 未豁免硬切判红", rc == 1 and len(un) == 1, "rc=%d" % rc)

    # 格 3：`clip_utf8` 调用不是硬切 ⇒ 不命中
    p3, d3 = sample({"src/server/y.mbt": "let x = @core.clip_utf8(desc, 40)\n"})
    rc, un, ex = judge(p3, base_dir=d3)
    check("s3 clip_utf8 不误报", not un, "un=%s" % (un,))

    # 格 4（**变异对照**）：清空豁免后同一份样本必须由绿转红
    #    —— 证明"绿"来自豁免判定，而不是扫描没看见
    saved = dict(EXEMPT)
    try:
        rc0, _, _ = judge(p1, base_dir=d1)
        EXEMPT.clear()
        rc1, un1, _ = judge(p1, base_dir=d1)
    finally:
        EXEMPT.clear()
        EXEMPT.update(saved)
    check("s4 变异对照（清空豁免 ⇒ 由绿转红）", rc0 == 0 and rc1 == 1 and len(un1) == 1,
          "rc0=%d rc1=%d" % (rc0, rc1))

    # 格 5：注释里的示例**不该**命中（判例-30 的直接回归锁）
    p5, d5 = sample({"src/server/z.mbt": "// 文档说：desc[0:40] 是错的写法\nlet x = 1\n"})
    rc, un, ex = judge(p5, base_dir=d5)
    check("s5 注释里的示例不命中（判例-30）", rc == 2 and not un, "rc=%d un=%s" % (rc, un))

    print("=== selftest %d/5 ===" % (5 - len(fails)))
    return 0 if not fails else 1


def main() -> int:
    args = sys.argv[1:]
    if "--selftest" in args:
        return selftest()

    paths = tracked_mbt_files()
    rc, unexplained, explained = judge(paths)

    if "--list" in args:
        print("扫描面 %d 个产品 .mbt 文件" % len(paths))
        for key, cap, ln in explained:
            print("  已解释 %s[0:%d] (line %d)" % (key, cap, ln))
        for key, cap, ln in unexplained:
            print("  未解释 %s[0:%d] (line %d)" % (key, cap, ln))
        return 0

    if rc == 2:
        print("FATAL 扫描面为空或一个 `[0:N]` 都没找到 ⇒ 判据无法自证（rc=2）")
        print("  可能原因：不在仓库根跑 / git 不可用 / 正则被改坏")
        return 2
    if rc == 1:
        print("门禁 有 %d 处**未解释的字节硬切**（`[0:N]`）：" % len(unexplained))
        for key, cap, ln in unexplained:
            print("  %s[0:%d]  (line %d)" % (key, cap, ln))
        print("  修法二选一：")
        print("   ① 中文文本 ⇒ 改用 `@core.clip_utf8(s, N)`（UTF-8 边界安全，全仓唯一真源）")
        print("   ② 确认是 ASCII（id/时间戳/盘符）⇒ 加进本文件 EXEMPT 表**并写理由**")
        return 1
    print("门禁 PASS 字节硬切 %d 处全部已解释（豁免表 %d 条）" % (len(explained), len(EXEMPT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
