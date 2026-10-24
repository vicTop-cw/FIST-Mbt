#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_esm_bundle_runnable.py —— 打包产物「真能跑」的判据（R182 / BUG-406）。

## 为什么需要它（外部用户报的、真实发生过的阻断性 bug）

兄弟项目 Pentad 的统帅用 fist-mbt 时发现 `doctor` / `version` / `serve` **全部崩溃**：

```
ReferenceError: require is not defined in ES module scope
  at _M0FP26daqing6sqlite19new__database__sync (cli.js:2455:67)
```

根因链（三层，缺一层都读不出来）：

1. `package.json` 声明 `"type": "module"` ⇒ Node 把 `.js` 当 **ESM**；
2. 上游 `daqing/sqlite@0.4.0` 的 JS FFI 里写着 **CJS** 形态
   `(path, opts) => new (require("node:sqlite").DatabaseSync)(path, opts)`，被 MoonBit
   原样打进 ESM 产物；
3. ESM 作用域没有 `require` ⇒ `ReferenceError`。**`moon check` 全绿、`moon build` 也全绿**
   —— 源码完全没问题，坏的是**产物**。

这正是本仓反复踩的「判据存在但没接线」同族：**没有任何一格在验「产物能不能跑起来」**。
编译门只看能不能生成 bundle，不执行它。

## 本尺怎么判（四档，逐档都要能自证）

对指定 bundle：

- **B1 产物存在且非空**：不存在 ⇒ `rc=2`（判据无法自证，绝不报绿——空扫描不冒充通过）；
- **B2 shim 在场**：bundle 里有 `require(` 时，正文必须能看见 `createRequire`。
  没有 ⇒ 红，归类 `SHIM_MISSING`（这就是「忘了跑 `patch_esm_main.py`」的形状）；
- **B3 真跑**：`node <bundle> version`，看 **stdout 与 stderr 的内容**，**不看退出码**
  （判例-10：`node` 的 rc 在有 ExperimentalWarning 时也可能为 0，而崩溃时才非 0——
  但靠 rc 分不清「崩了」和「本来就没有 version 子命令」）；
- **B4 根因分类**：命中 `ReferenceError: require is not defined` ⇒ `ESM_CJS_REQUIRE`，
  其余崩溃 ⇒ `OTHER_CRASH`，能正常打印版本 ⇒ `OK`。

## 为什么它不能靠 `moon check`

`moon check --target js` = 0 errors 的**同一棵树**，产物仍可能跑不起来——本仓实测：
构建完 `_build/js/debug/build/cmd/cli/cli.js` 后**直接跑**就是 `ReferenceError`，
必须先跑 `scripts/patch_esm_main.py` 注入 shim。⇒ 判据必须**在产物上跑一次真进程**。

## 退出码

0 = 产物可跑（`version` 正常打印，无 ESM/CJS 崩溃）
1 = 产物坏了（逐档点名：SHIM_MISSING / ESM_CJS_REQUIRE / OTHER_CRASH）
2 = 判据无法自证（bundle 不存在 / node 不可用 / 空扫描）
4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）

用法：
    python scripts/check_esm_bundle_runnable.py
    python scripts/check_esm_bundle_runnable.py --bundle <path>
    python scripts/check_esm_bundle_runnable.py --selftest
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

DEFAULT_BUNDLE = os.path.join("_build", "js", "debug", "build", "cmd", "cli", "cli.js")

# 根因分类标签（供 CI 注解与报告引用，字符串稳定）
KIND_OK = "OK"
KIND_SHIM_MISSING = "SHIM_MISSING"
KIND_ESM_CJS_REQUIRE = "ESM_CJS_REQUIRE"
KIND_OTHER_CRASH = "OTHER_CRASH"

# 崩溃特征串（来自 BUG-406 实测输出）
_REQUIRE_RE = "require is not defined"


# ── 纯函数（可单测，不依赖 node/文件系统）──────────────────────────────────────


def classify_run(stdout, stderr):
    """纯函数：给一次 `node <bundle> version` 的输出，判它是「能跑」还是哪种崩。

    **只看内容，不看 rc**（判例-10 落点）：调用方拿不到 rc，函数签名就堵死了那条路。

    Returns:
        (kind, detail) —— kind ∈ {OK, ESM_CJS_REQUIRE, OTHER_CRASH}
    """
    out = stdout or ""
    err = stderr or ""
    blob = out + "\n" + err
    # ① ESM/CJS require 崩溃：特征串 + ReferenceError 同时出现才算（防正文里提到该词误判）
    if _REQUIRE_RE in blob and ("ReferenceError" in blob or "ES module scope" in blob):
        return (KIND_ESM_CJS_REQUIRE,
                "ESM 作用域缺 require ⇒ 打包产物的 CJS 互操作层没被垫片覆盖（BUG-406 形状）")
    # ② 其它崩溃：stderr 里有 stack 味道，且 stdout 没给出正常回执
    if ("Error" in err and " at " in err) or "throw" in err:
        first = next((ln for ln in err.splitlines() if ln.strip()), "")
        return (KIND_OTHER_CRASH, "产物崩了（非 require 类）：%s" % first[:160])
    # ③ 正常：stdout 有版本回执
    if "FIST-Mbt" in out or "v0." in out:
        return (KIND_OK, "产物可跑（version 正常回执）")
    # ④ 什么都没打印 ⇒ 不能算 OK（空回执不等于成功）
    return (KIND_OTHER_CRASH,
            "产物退出但**没有任何回执**（stdout/stderr 皆空）⇒ 不算可跑，拒绝报绿")


def shim_present(text):
    """纯函数：bundle 正文里 `require(` 是否被 `createRequire` 垫片覆盖。

    规则：**只有在出现 `require(` 时才要求垫片**。不出现 ⇒ 这棵树不需要 shim，
    不构成缺陷（返回 True 表示「不违反」）。
    """
    body = text or ""
    if "require(" not in body:
        return True
    return "createRequire" in body


def bundle_checks(path):
    """对 bundle 做静态两档（B1 存在 / B2 垫片）。返回 (ok, kind, detail)。

    读不到文件 ⇒ (False, "MISSING", ...)，调用方据此走 rc=2（无法自证，**不是**红）。
    """
    if not os.path.isfile(path):
        return (False, "MISSING", "bundle 不存在：%s ⇒ 判据无法自证（先构建）" % path)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            body = f.read()
    except OSError as e:
        return (False, "MISSING", "bundle 读不到：%s" % e)
    if not body.strip():
        return (False, "MISSING", "bundle 是空文件 ⇒ 判据无法自证")
    if not shim_present(body):
        return (False, KIND_SHIM_MISSING,
                "bundle 里有 `require(` 但找不到 `createRequire` 垫片 ⇒ "
                "忘了跑 `python scripts/patch_esm_main.py`")
    return (True, KIND_OK, "静态两档通过（存在且垫片就位）")


# ── node 层 ───────────────────────────────────────────────────────────────────


def run_bundle(path, args=("version",), timeout=120):
    """真跑一个 bundle。返回 (stdout, stderr)。node 缺失抛 FileNotFoundError 由调用方处理。"""
    p = subprocess.run(
        ["node", path, *args],
        cwd=os.path.dirname(path) or ".",
        capture_output=True,
        timeout=timeout,
    )
    return ((p.stdout or b"").decode("utf-8", "replace"),
            (p.stderr or b"").decode("utf-8", "replace"))


def check(bundle):
    """全四档。返回 (rc, kind, detail, stdout, stderr)。

    **档位优先级**（实测校准）：B1 存在性 → **B3/B4 真跑并分类** → B2 垫片静态核。

    为什么 B3/B4 排在 B2 前面：两个原因——
    1. **精确性**：真跑出来的根因（`ESM_CJS_REQUIRE`）比静态推断（`SHIM_MISSING`）
       更接近真相。同一个"缺垫片"毛病，真跑能直接指出是 `require is not defined`；
    2. **`node` 不可用时的退化**：CI 上若没装 node，B3 跑不了，此时**退回 B2 静态核**
       仍然能挡住「忘跑 patch」这一形 —— 判据不因缺 node 就整体失效。
    """
    ok, kind, detail = bundle_checks(bundle)
    if not ok and kind == "MISSING":
        return (2, kind, detail, "", "")

    # 先真跑（B3/B4）；node 不在或静态已判缺垫片时退回静态结论
    if shutil.which("node") is not None:
        try:
            out, err = run_bundle(bundle)
        except subprocess.TimeoutExpired:
            return (1, KIND_OTHER_CRASH, "跑 `version` 超时（120s）⇒ 产物挂死", "", "")
        kind2, detail2 = classify_run(out, err)
        if kind2 != KIND_OK:
            return (1, kind2, detail2, out, err)
        # 真跑正常，但静态仍报缺垫片 ⇒ 以静态为准（垫片缺失是确定的缺陷）
        if not ok:
            return (1, kind, detail, out, err)
        return (0, KIND_OK, detail2, out, err)

    # node 不可用：静态档兜底；静态过了就算无法自证（不报绿也不冤枉）
    if not ok:
        return (1, kind, detail, "", "")
    return (2, "MISSING", "PATH 上没有 node ⇒ 真跑档无法执行，判据无法自证", "", "")


# ── 自证 ───────────────────────────────────────────────────────────────────────


def selftest():
    cells, fails = [], []

    def cell(name, got, want):
        cells.append(name)
        if got != want:
            fails.append("%s: got=%r want=%r" % (name, got, want))

    # ── 纯函数格：classify_run 四态（判例-10：传内容不传 rc）──────────────────
    real_crash_err = (
        "file:///x/cli.js:2455\n"
        "const f = (path, opts) => new (require(\"node:sqlite\").DatabaseSync)(path, opts);\n"
        "                            ^\n\n"
        "ReferenceError: require is not defined in ES module scope, you can use import instead\n"
        "    at _M0FP (file:///x/cli.js:2455:67)\n"
    )
    cell("classify-esm-cjs-require", classify_run("", real_crash_err)[0], KIND_ESM_CJS_REQUIRE)
    cell("classify-ok-version", classify_run("FIST-Mbt v0.3.10\n(moon.mod version)\n", "")[0], KIND_OK)
    cell("classify-other-crash",
         classify_run("", "TypeError: x is not a function\n    at Object.<anonymous> (a.js:1)\n")[0],
         KIND_OTHER_CRASH)
    cell("classify-empty-is-not-ok", classify_run("", "")[0], KIND_OTHER_CRASH)
    # 防误判：正文「提到」该词但没崩（例如 version 输出里有说明）⇒ 不该归类为崩溃
    cell("classify-mention-only-not-crash",
         classify_run("FIST-Mbt v0.3.10\nnote: require is not defined 是历史 bug 名\n", "")[0],
         KIND_OK)

    # ── 纯函数格：shim_present（只在真有 require( 时才要求垫片）───────────────
    cell("shim-not-needed-when-no-require", shim_present("import x from 'y';\n"), True)
    cell("shim-missing-blocks", shim_present("const a = require('node:sqlite');\n"), False)
    cell("shim-present-ok",
         shim_present("import {createRequire as _cr} from 'node:module';\n"
                      "const require = _cr(import.meta.url);\n"
                      "const a = require('node:sqlite');\n"), True)

    # ── 端到端格：真造 bundle + 真跑 node（临时目录，不碰真仓）───────────────
    tmp = tempfile.mkdtemp(prefix="fist-esm-probe-")
    try:
        # 好 bundle：真能打印版本
        good = os.path.join(tmp, "good.mjs")
        with open(good, "w", encoding="utf-8") as f:
            f.write("console.log('FIST-Mbt v0.0.0-selftest');\n")
        rc, kind, detail, out, err = check(good)
        cell("e2e-good-bundle-rc0", rc, 0)
        cell("e2e-good-bundle-kind-ok", kind, KIND_OK)

        # 坏 bundle：真造 `require is not defined`（ESM 里用 require）
        bad = os.path.join(tmp, "bad.mjs")
        with open(bad, "w", encoding="utf-8") as f:
            f.write("const s = require('node:sqlite');\nconsole.log('FIST-Mbt v0');\n")
        rc, kind, detail, _, _ = check(bad)
        cell("e2e-bad-bundle-red", rc, 1)
        cell("e2e-bad-bundle-classified", kind, KIND_ESM_CJS_REQUIRE)

        # 坏 bundle 2：静态缺垫片（B2 格）—— 有 require( 但没有 createRequire
        #   注意：这里走静态档，不跑 node，所以不会被 node 的报错混淆
        noshim = os.path.join(tmp, "noshim.mjs")
        with open(noshim, "w", encoding="utf-8") as f:
            f.write("const s = require('node:sqlite');\n")
        ok, kind2, _ = bundle_checks(noshim)
        cell("e2e-shim-missing-static", (ok, kind2), (False, KIND_SHIM_MISSING))

        # 不存在的 bundle ⇒ rc=2（无法自证，**不是**红）
        rc, kind, _, _, _ = check(os.path.join(tmp, "nope.js"))
        cell("e2e-missing-bundle-rc2", rc, 2)

        # 空文件 ⇒ 同样 rc=2
        empty = os.path.join(tmp, "empty.js")
        with open(empty, "w", encoding="utf-8") as f:
            f.write("   \n")
        rc, _, _, _, _ = check(empty)
        cell("e2e-empty-bundle-rc2", rc, 2)

        # 保险：真仓当前 bundle（若已构建且已 patch）应当 rc=0 —— 但**不**作为自证硬格，
        # 因为 CI 上可能没构建。这里只把它记成诊断读数，不参与 fails。
        real = os.path.join(ROOT, DEFAULT_BUNDLE)
        if os.path.isfile(real):
            rrc, rkind, _, _, _ = check(real)
            cells.append("diag-real-bundle(rc=%d,kind=%s)" % (rrc, rkind))

        # 入口面（J2 口径）：真调 main(["--selftest"])
        if not _ENTRY_PROBED[0]:
            _ENTRY_PROBED[0] = True
            try:
                cell("entry-main-selftest-rc0", main(["--selftest"]), 0)
            finally:
                _ENTRY_PROBED[0] = False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s (%d cells: %s)"
          % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


# 入口自证的一次性哨兵（防 `main(["--selftest"])` 随递归层层重入）
_ENTRY_PROBED = [False]


# ── 入口 ───────────────────────────────────────────────────────────────────────


def run(argv):
    ap = argparse.ArgumentParser(
        description="打包产物「真能跑」判据（BUG-406：ESM 作用域缺 require）")
    ap.add_argument("--selftest", action="store_true", help="自证（造好/坏 bundle 各跑一遍）")
    ap.add_argument("--bundle", default=None, help="指定 bundle 路径（缺省 debug cli.js）")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    bundle = args.bundle or os.path.join(ROOT, DEFAULT_BUNDLE)
    rc, kind, detail, out, err = check(bundle)

    if rc == 2:
        print("FATAL 判据无法自证：%s" % detail)
        return 2

    if rc == 1:
        print("FAIL [%s] %s" % (kind, detail))
        print("      bundle = %s" % bundle)
        if kind == KIND_ESM_CJS_REQUIRE or kind == KIND_SHIM_MISSING:
            print("      修法 1（立即解锁）：python scripts/patch_esm_main.py")
            print("      修法 2（根治）：上游 daqing/sqlite 把 JS FFI 改 ESM 形态，本仓升依赖")
            print("      为什么 moon check 照绿：检查的是源码，坏的是**打包产物**——两件事")
        tail = (err or out or "").strip().splitlines()
        for ln in tail[:8]:
            print("      | " + ln)
        return 1

    print("PASS [%s] %s" % (kind, detail))
    return 0


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
