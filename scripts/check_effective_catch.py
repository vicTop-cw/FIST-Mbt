#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_effective_catch.py —— 「无效 catch」判据（BUG-465）。

## 这是语言层边界，不是「我们写错了」

MoonBit 的 `catch` / `try·catch` **只包住 `raise` 效果**。
而 FFI 库（`daqing/sqlite`、`node:sqlite` 等）抛的是 **JS 运行时异常**，
这些函数**没有 `raise` 标注** ⇒ 包住它们的 `catch` **永远不生效**。

实测（BUG-463 报告 P2/Q1/Q2 三格，真跑）：
```
P2  let _r : Unit? = Some(db.close()) catch { _ => None }   → 仍抛 database is not open
Q1  try { db.close() } catch { _ => () }                    → 仍抛
Q2  裸 db.close()                                            → 抛（对照：证明 Q1 不是"根本没抛"）
```

⇒ **`store_sqlite.mbt:101` 那种 `db.close() catch { _ => () }` 是**装饰性防线**：
它让读代码的人以为「关闭期的异常被吞掉了」，实际一次都没吞过。**

## 判法（用编译器算好的结果，不自己造）

`moon check` 已经为每一处「`try`/`catch` 包住的表达式永不 raise」报

    Warning: [0023] unused_try: The body of this try expression never raises any error.

**⇒ 判据就是：全仓 `unused_try` 计数必须为 0。**

为什么不自己写正则扫 `catch {`：
- 需要知道每个被调函数是否 `raise` ⇒ **要类型信息**，正则拿不到；
- 编译器已经在算了，且**随版本自动正确**（这是它存在的意义）。

## 诚实边界（必读）

⚠️ **`unused_try` = 0 ≠ 「没有无效 catch」**。编译器只在**它能证明**时报；
下列情况它**不报**，但人的预期仍是错的：
- `catch` 包住一个**声明了 raise 但实际从不 raise** 的函数 ⇒ 编译器认为有意义，**但运行时也拦不住 JS 异常**；
- `catch` 包住**间接调用 FFI 的包装函数**（包装函数自己没 raise 标注，内部调的 FFI 抛 JS 异常）⇒ 同上。
**⇒ 本判据只覆盖「编译器能证明」的那部分。** 它抓的是一类明确、可枚举、零误报的形态。

rc 契约（与 `check_fmt_gate.py` / `check_plan_location.py` 同口径）：
- `0` = 无 `unused_try`
- `1` = 有（逐条点名文件:行）
- `2` = 判据无法自证（`moon check` 跑不起来 / 输出里既无 `unused_try` 也无 `Finished`/`error` 汇总行）

用法：
    python scripts/check_effective_catch.py            # 判据模式
    python scripts/check_effective_catch.py --selftest # 自证（含变异对照）
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import subprocess
import sys
from moon_env_probe import moon_env

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RC_OK, RC_VIOLATION, RC_BROKEN = 0, 1, 2

# `moon check` 每处 unused_try 的上下文里有一行 `╭─[ <abs path>:<line>:<col> ]`
LOC_RX = re.compile(r"[╭├]─\[\s*(.+?):(\d+):(\d+)\s*\]")
WARN_RX = re.compile(r"unused_try")
# `moon check --json` 里 unused_try 的 error_code（**探针实证**，见 `parse_hits` docstring：
# 用最小工程 `try { 1+1 } catch {…}` 实跑得 error_code = 23，不是从文档抄的）。
UNUSED_TRY_CODE = 23


def run_moon_check(root: str):
    """返回 (text, ok)。ok=False ⇒ 拿不到可信输出。"""
    try:
        p = subprocess.run(
            ["moon", "check", "--target", "js"],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=900,
            encoding="utf-8",
            errors="replace",
            env=moon_env(),
        )
    except (OSError, subprocess.TimeoutExpired) as e:  # noqa: BLE001
        return "moon check 跑不起来: %s" % e, False
    return (p.stdout or "") + (p.stderr or ""), True


def parse_hits(text: str):
    """从 `moon check` 输出里抽出每一处 unused_try 的位置。

    做法：按 `Warning:` 分块，块内含 unused_try ⇒ 取该块内第一条 `╭─[ ... ]` 定位。
    （**不**用「unused_try 前后各抓 N 行」—— 实测会串到相邻 warning 的位置上。）

    **也吃 `--json` 格式**（R74）：`run_guards.py` 的 `_ensure_check_dump()` 落的是
    `moon check --json`（给另外 3 格用），而 JSON 里**没有 `Warning:` 块** ⇒
    本函数此前喂它会返回空 hits，看起来像「没有违例」，其实**没解析到**。
    JSON 的 `unused_try` 用 `error_code == 23` 标识（**探针实证**，不是猜：
    用最小工程 `try { 1+1 } catch {…}` 跑 `moon check --json` 得
    `{"level":"warning","error_code":23,"message":"Warning (unused_try): …"}`）。
    """
    hits = []
    # ① JSON 形态：以 `{` 开头的单行/多行 JSON ⇒ 走 diagnostics
    maybe = text.lstrip()
    if maybe.startswith("{"):
        try:
            doc = json.loads(maybe)
        except (ValueError, TypeError):
            doc = None
        if isinstance(doc, dict):
            for d in doc.get("diagnostics") or []:
                if not isinstance(d, dict):
                    continue
                # 两条判据都用：error_code（稳）+ message 里出现 unused_try（可读性兜底）
                if d.get("error_code") == UNUSED_TRY_CODE or WARN_RX.search(
                        str(d.get("message") or "")):
                    path = str(d.get("path") or "").replace("\\", "/")
                    try:
                        path = os.path.relpath(path, ROOT).replace("\\", "/")
                    except ValueError:
                        pass
                    loc = str(d.get("loc") or "")
                    m = re.match(r"(\d+)", loc)
                    hits.append((path, int(m.group(1)) if m else 0))
            return hits
    # ② 人类可读形态（原路径，逐字不变）
    blocks = re.split(r"\nWarning: ", text)
    for b in blocks:
        if not WARN_RX.search(b):
            continue
        m = LOC_RX.search(b)
        if m:
            path = m.group(1).replace("\\", "/")
            try:
                path = os.path.relpath(path, ROOT).replace("\\", "/")
            except ValueError:
                path = path.replace("\\", "/")
            hits.append((path, int(m.group(2))))
    return hits


def judge(root: str = ROOT, check_output: str = ""):
    """`check_output` 非空时**从文件读 `moon check` 输出**，不真跑（R72）。

    为什么需要：本判据会自己 spawn `moon check`。而**并发 lane 恰好在编译时**
    `moon check` 可能瞬时失败 ⇒ 本判据 rc=2（**拒绝出结论，行为正确**），
    但电池里就出现一条「无法自证」的假红 —— 实测撞过一次（`check_effective_catch.py`
    在电池里 rc=2 而单独连跑 3 次全 rc=0）。

    加了这个入口后：电池可以先跑**一次** `moon check` 落文件，再把同一份输出喂给需要它的判据
    ⇒ 既消除并发抖动，也让同一份事实只被采一次（判例-29「机制格 ≠ 实现路径格」的延伸）。
    """
    if check_output:
        try:
            with io.open(check_output, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError as e:
            return RC_BROKEN, {"note": "读 --check-output 失败: %s" % e}
    else:
        text, ok = run_moon_check(root)
        if not ok:
            return RC_BROKEN, {"note": text}
    # 自拒：既没有 unused_try 也没有正常汇总行 ⇒ 输出不可信
    #
    # ⚠️ JSON 形态要**换一条判据**（R74）：`--json` 里既没有 `unused_try` 字样（除非真违例）
    #    也没有 `Finished.` / `now up to date`（那是人类可读面的词）⇒ 用原来的自拒式会把
    #    一份**合法的 JSON dump** 判成"不可信"（实测 rc=2）。
    #    JSON 的可信判据是它自己的 `status == "success"` 且有 `diagnostics` 数组。
    stripped = text.lstrip()
    if stripped.startswith("{"):
        try:
            _doc = json.loads(stripped)
        except (ValueError, TypeError):
            return RC_BROKEN, {"note": "check_output 是 JSON 但解析失败 ⇒ 拒绝出结论"}
        if not (isinstance(_doc, dict) and _doc.get("status") == "success"
                and isinstance(_doc.get("diagnostics"), list)):
            return RC_BROKEN, {
                "note": "JSON dump 缺少 status=success 或 diagnostics 数组 ⇒ 拒绝出结论"}
    elif not WARN_RX.search(text) and not re.search(r"Finished\.|now up to date", text):
        return RC_BROKEN, {"note": "moon check 输出里既无 unused_try 也无汇总行 ⇒ 拒绝出结论"}
    hits = parse_hits(text)
    return (RC_OK if not hits else RC_VIOLATION), {"hits": hits, "raw": text}


def render(res) -> None:
    print("[覆盖面] 本判据只判「编译器能证明无意义的 try/catch」：")
    print("  ✅ `moon check` 报 `unused_try` 的每一处（catch/try 包住的表达式永不 raise）")
    print("  ✅ 这类在 FFI 面上是**装饰性防线**：FFI 抛的是 JS 运行时异常，catch 拦不住")
    print("  ❌ 不判：包住「声明了 raise 但实际不 raise」的函数（编译器认为有意义）")
    print("  ❌ 不判：包住「间接调 FFI 的包装函数」（包装函数自己没 raise 标注）")
    print("  ⇒ **PASS 不代表「没有无效 catch」，只代表「编译器证明不了有」**")
    print()
    hits = res["hits"]
    if hits:
        print("[违例] 发现 %d 处 unused_try：" % len(hits))
        for path, line in hits:
            print("  ✗ %s:%d" % (path, line))
        print()
        print("[结论] 有 %d 处「永不生效的 try/catch」—— 读代码的人会以为它在保护什么。" % len(hits))
    else:
        print("[违例] （无）")
        print()
        print("[结论] 全仓无 unused_try。**这不等于「没有无效 catch」** —— 见上面的覆盖边界。")


def selftest() -> int:
    cells = []

    def cell(name, got, want):
        cells.append((name, got, want))
        print("  [%s] %-44s got=%r want=%r"
              % ("OK" if got == want else "FAIL", name, got, want))

    print("[selftest] 用合成的 moon check 输出驱动解析（不跑真编译）")

    SAMPLE_CLEAN = """Warning: [0020]
    ╭─[ /x/src/a.mbt:5:3 ]
 5 │   try { 1 } catch { _ => 0 }
   │   ─┬─
   │    ╰─── Warning (deprecated): whatever
Finished. moon: ran 28 tasks, now up to date (85 warnings, 0 errors)
"""
    SAMPLE_DIRTY = """Warning: [0023]
    ╭─[ /x/src/store/store_sqlite.mbt:101:7 ]
101 │       db.close() catch {
    │       ─────┬────
    │            ╰────── Warning (unused_try): The body of this try expression never raises any error.
Warning: [0020]
    ╭─[ /x/src/server/laya_js.mbt:18:10 ]
 18 │   args : Array[String],
   │          ────────┬───────
   │                  ╰───────── Warning (deprecated): Use !expr instead
Warning: [0023]
    ╭─[ /x/src/server/hat_hexa_tools.mbt:21:3 ]
 21 │   try {
    │   ─┬─
    │    ╰─── Warning (unused_try): The body of this try expression never raises any error.
Finished. moon: ran 28 tasks, now up to date (85 warnings, 0 errors)
"""

    # 格1：干净输出 ⇒ 0 hits
    hits1 = parse_hits(SAMPLE_CLEAN)
    cell("clean-no-hits", len(hits1), 0)

    # 格2：脏输出 ⇒ 2 hits，且「未串到相邻 warning 的位置」
    hits2 = parse_hits(SAMPLE_DIRTY)
    cell("dirty-two-hits", len(hits2), 2)
    cell("dirty-keeps-first-path",
         any("store_sqlite.mbt" == os.path.basename(p) and ln == 101 for p, ln in hits2), True)
    cell("dirty-does-not-borrow-neighbor",
         any("laya_js.mbt" in p for p, _ in hits2), False)

    # 格3（★变异对照）：把 unused_try 词从脏样本里删掉 ⇒ 必须判 0
    #   模拟「编译器不再报（或词改了名）」⇒ 判据不能凭空报红
    mutated = SAMPLE_DIRTY.replace("unused_try", "some_other_warning")
    hits3 = parse_hits(mutated)
    cell("MUTATION-keyword-removed-no-hits", len(hits3), 0)

    # 格4（★反脱锚）：输出里既无 unused_try 也无汇总行 ⇒ 必须自拒（rc=2）
    broken = "some random failure text without the summary"
    looks_ok = bool(WARN_RX.search(broken)) or bool(re.search(r"Finished\.|now up to date", broken))
    cell("MUTATION-unrecognizable-output-self-rejects", looks_ok, False)

    # 格5：覆盖率声明必须在输出里（不只写在 docstring）
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        render({"hits": []})
    out = buf.getvalue()
    cell("coverage-note-in-output", "不代表「没有无效 catch」" in out.replace("不等于", "不代表"), True)
    cell("ffi-runtime-exception-explained", "JS 运行时异常" in out, True)

    ok = sum(1 for _n, g, w in cells if g == w)
    print("\n[selftest] %d/%d 格通过" % (ok, len(cells)))
    sys.exit(0 if ok == len(cells) else 4)  # NO_CALL_FACE J2：自检函数自己就是调用面


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default="")
    # R72：从文件读 `moon check` 输出（不真跑）—— 供电池复用同一份事实，消除并发抖动。
    ap.add_argument("--check-output", default="")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    rc, res = judge(a.root or ROOT, a.check_output)
    if rc == RC_BROKEN:
        print("[FATAL] " + res["note"])
        print("判据无法自证 —— 拒绝出结论，也拒绝因「没找到」报绿。rc=2")
        return RC_BROKEN
    render(res)
    return rc


if __name__ == "__main__":
    sys.exit(main())
