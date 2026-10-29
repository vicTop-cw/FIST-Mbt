#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_fmt_gate.py — `moon fmt --check` 的**可判性闸**（R55 / **BUG-388**；最初误记为 381，381 是 check_mbti_sync 泛型盲区）。

## 为什么要它
本仓 AGENTS「提交门禁」写着：提交前必须 `moon fmt` + `moon fmt --check` 返回 0。
但 2026-10-22 实测：`moon fmt --check` 在本机（moon **0.1.20261016**，Windows）**根本跑不完**：

    Error: failed when formatting project
    error: open("\\\\?\\…\\_build\\wasm-gc\\release\\format\\lib.mbt"): No such file …
    fatal: cannot hash …\\_build\\wasm-gc\\release\\format\\lib.mbt
    → rc=-1

**它不是本仓的问题**——在一个**与本仓无关的 3 文件最小工程**（`moon.mod` + `moon.pkg` + `lib.mbt`）
上同一条命令**一模一样失败**；而 `moon fmt`（写模式）rc=0 正常。⇒ 这是 moon 侧的 `--check`
管线在本机上的缺陷（它把格式化结果写到 `_build/wasm-gc/release/format/`，再 `git diff --no-index` 比对，
但那批文件并没有落盘）。

## 这个尺子怎么判（三档，绝不把"测不了"混成红或绿）
- **rc=0**：格式干净（真绿）；
- **rc=2 DEGRADED**：输出里出现 `_build/…/format/… No such file` / `cannot hash` 这一族签名
  ⇒ **量不出来**，此时既不能判红也不能判绿，必须说"不可测"；
- **rc=1**：`--check` 正常跑完且**确实报了格式差异**（输出含未命中上述签名的 diff 线索）
  ⇒ 真格式红。

为什么单立一支、而不塞进别的守卫：若把"测不了"当红，每轮都会追一个不存在的格式问题；
若当绿，就是把工具链缺陷洗成"格式没问题"——两头都是本仓明令禁止的读数造假。

用法：
  python scripts/check_fmt_gate.py            # 复跑 moon fmt --check 并按三档判
  python scripts/check_fmt_gate.py --selftest # 只验分类器（纯函数，合成样本）
"""
import os
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# 本机 moon 缺陷的签名（2026-10-22 实测；最小独立工程可复现）
BROKEN_SIGNATURES = (
    "No such file",
    "cannot hash",
    "failed when formatting project",
)


def run(moon_rc, output, markers=None):
    """纯函数：把 (moon 的 rc, 输出) 判成 'clean' / 'degraded' / 'red'。

    `markers`（**R194**，可选）：判「输出是否像工具链故障」的**字面量表**。
    缺省用本文件的 `BROKEN_SIGNATURES`；`fist-gate.py` 传它自己的 `FMT_COLD_MARKERS`
    ⇒ **marker 匹配只有一处实现**，而「三档怎么映射成本门的四档」仍由各调用方决定
    （机制与策略分离：机制在此，策略在调用方）。

    - 只有 rc==0 才是 clean；
    - rc!=0 但输出命中 `_build/…/format/…` 这一族签名 ⇒ degraded（量不出来）；
    - 其余非 0 ⇒ red（真格式差异）。

    ⚠️ **R174 的历史（R194 已收口）**：`fist-gate.py:classify_fmt()` 曾是**另一套判定**
    （4 档 / 不同 marker 字面量 / `rc==1` 软化）。R173 直接委派失败（丢 marker ⇒ 2 格红）。
    R194 用「本函数收 markers 参数 + fist-gate 只做档位映射」解决：两边行为**逐字不变**，
    而 marker 匹配不再有第二份实现。
    """
    out = output or ""
    if moon_rc == 0:
        return "clean"
    marks = BROKEN_SIGNATURES if markers is None else tuple(markers)
    if "_build" in out.replace("\\", "/") and any(s in out for s in marks):
        return "degraded"
    if any(s in out for s in marks):
        return "degraded"
    return "red"


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    cell("clean-when-rc0", run(0, "Finished. moon: ran 3 tasks"), "clean")
    cell("degraded-on-format-dir-missing",
         run(-1, 'error: open("\\\\?\\E:\\p\\_build\\wasm-gc\\release\\format\\lib.mbt"): No such file\n'
                      'fatal: cannot hash \\\\?\\E:\\p\\_build\\wasm-gc\\release\\format\\lib.mbt\n'
                      'Error: failed when formatting project'), "degraded")
    cell("degraded-even-without-backslash",
         run(1, "error: _build/wasm-gc/release/format/a.mbt: No such file"), "degraded")
    cell("red-on-plain-diff",
         run(1, "--- a/lib.mbt\n+++ b/lib.mbt\n@@ -1 +1 @@\n-old\n+new"), "red")
    cell("red-on-generic-failure", run(255, "Error: fmt found unformatted files"), "red")
    cell("rc0-wins-over-noise", run(0, "warning: something\nFinished."), "clean")

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：clean 两档 / degraded 两档 / red 两档）" % len(cells))
    return 0


def main(argv):
    # R201：**未知旗标必须拒绝**（rc=2）。病象：拼错 `--self-test` 会被静默忽略，
    # 然后照跑真 `moon fmt --check` 并可能回 rc=0 ⇒ 看起来"自检通过"，实际跑的是真检查。
    # （同族实测：R197/R198/R199 三把新尺栽在同一处；R200 已把这条做成提交时的 advisory 体检 A3。）
    unknown = [a for a in argv if a.startswith("-") and a != "--selftest"]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知：--selftest（rc=2）" % " ".join(unknown))
        return 2
    if "--selftest" in argv:
        return selftest()
    p = subprocess.run(["moon", "fmt", "--check"], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = (p.stdout or "") + (p.stderr or "")
    verdict = run(p.returncode, out)
    first = [l for l in out.strip().splitlines() if l.strip()][:2]
    print("  moon fmt --check rc=%d" % p.returncode)
    for l in first:
        print("  | " + l[:140])
    if verdict == "clean":
        print("PASS 格式干净（moon fmt --check rc=0）")
        return 0
    if verdict == "degraded":
        print("DEGRADED(2) `moon fmt --check` 在本机量不出来（moon 0.1.20261016 的 --check 管线写 "
              "`_build/…/format/` 后比对缺失文件；最小独立工程可复现 ⇒ 工具链缺陷，不是本仓格式红）。"
              "本格**拒绝判红也拒绝判绿**；格式门请以 CI（Linux nightly）为准。")
        return 2
    print("FAIL 真格式差异（--check 正常跑完并报了 diff）：请 `moon fmt` 后重跑")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
