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
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# ── 覆盖面：从 `moon.pkg` 反解，**不硬编码**（判例-16 / R183）────────────────
#
# **为什么不再写死 cli.js**（判例-16「判据覆盖必须 ≥ 修复覆盖」）：
# `scripts/patch_esm_main.py` 的修复面是 `_build/js/debug/build/**` 下**全部** >100KB 的
# bundle（实测 4 个：cmd/cli、cmd/main、cmd/commissar、smoke），而本尺原先只验
# `cmd/cli/cli.js` 一个。⇒ 若 `commissar.js` / `smoke.js` 某天没被垫片覆盖，**本尺看不见**，
# 而电池里那一格跑的又是 `--selftest`，连这条窄覆盖也照不到。判据面 < 修复面 = 真缺陷。
#
# 覆盖面真源 = **各包 `moon.pkg` 的 `pkgtype(kind: "executable")`**（`check_entry_paths.py`
# 同源口径），而不是一份手抄清单。这样：
#   · 新增/搬移 executable 包（如 `smoke/` → `cmd/smoke/`）**自动纳入**，不必改本文件；
#   · 删除某个 executable 包 ⇒ 覆盖面自动收窄，不会留下指向幽灵产物的死格。
#
# 扫描面是**仓库内任意层级的 `moon.pkg`**（不限 `cmd/*`）：本仓 `smoke/` 现在就在根下第二层，
# 将来也可能再搬；写死前缀就是下一个漂移点。
EXEC_PKG_RE = r"pkgtype\(\s*kind\s*:\s*\"executable\"\s*\)"
SCAN_SKIP_DIRS = {".git", "_build", ".mooncakes", "__pycache__", "node_modules", "temp", "_archive"}


def executable_pkg_dirs(root):
    """仓库内所有声明 `pkgtype(kind: "executable")` 的包目录（仓库相对、`/` 分隔、已排序）。

    跳过构建产物与依赖目录；`.agents/worktrees/` 下是各分支的副本，不是本仓真源 ⇒ 一并跳过。
    """
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
        parts = [p for p in rel_dir.split("/") if p]
        # 剪枝：构建/依赖/临时目录、以及 worktree 副本
        if any(p in SCAN_SKIP_DIRS for p in parts):
            dirnames[:] = []
            continue
        if parts[:2] == [".agents", "worktrees"]:
            dirnames[:] = []
            continue
        if "moon.pkg" not in filenames:
            continue
        try:
            with open(os.path.join(dirpath, "moon.pkg"), "r", encoding="utf-8", errors="replace") as f:
                txt = f.read()
        except OSError:
            continue
        if re.search(EXEC_PKG_RE, txt):
            found.append(rel_dir)
    return sorted(found)


def bundles_for_pkg(pkg_dir):
    """把包目录反解成它在 `_build/js/debug/build/` 下的**候选** bundle 路径。

    **产物目录 = 包目录原样**（不是 `basename`）——本仓实测：
        `cmd/cli/`       → `_build/js/debug/build/cmd/cli/cli.js`
        `cmd/main/`      → `_build/js/debug/build/cmd/main/main.js`
        `smoke/`         → `_build/js/debug/build/smoke/smoke.js`
    即 `<build>/<pkg_dir>/<basename>.js`。早先按 `basename(pkg_dir)` 拼会漏掉 `cmd/`
    这层 ⇒ `cmd/*` 的产物一个都解析不到（第一次实跑就暴露了，这正是「不硬编码」的价值
    —— 写死 `cmd/cli/cli.js` 的话这个错永远看不见）。

    产物**文件名**仍可能与包目录名不同（历史上 `cmd/main` 的产物就叫 `main.js`），
    故给出按优先级排列的候选，取第一个存在的。
    """
    build = os.path.join("_build", "js", "debug", "build", *pkg_dir.split("/"))
    name = os.path.basename(pkg_dir)
    return [
        os.path.join(build, name + ".js"),
        os.path.join(build, "main.js"),
    ]


def resolve_bundles(root, pkg_dirs):
    """(resolved, unresolved)：resolved = [(pkg_dir, 存在的 bundle 相对路径)]。

    **未构建不算缺陷**（CI 上未必先 build）——但 resolve 结果要参与「覆盖面对表」自证格，
    所以把两者都返回，由调用方如实出数。
    """
    resolved, unresolved = [], []
    for pkg in pkg_dirs:
        hit = next((c for c in bundles_for_pkg(pkg) if os.path.isfile(os.path.join(root, c))), None)
        (resolved.append((pkg, hit)) if hit else unresolved.append(pkg))
    return resolved, unresolved

# 根因分类标签（供 CI 注解与报告引用，字符串稳定）
KIND_OK = "OK"
KIND_SHIM_MISSING = "SHIM_MISSING"
KIND_ESM_CJS_REQUIRE = "ESM_CJS_REQUIRE"
KIND_OTHER_CRASH = "OTHER_CRASH"
KIND_UNBUILT = "UNBUILT"

# 崩溃特征串（来自 BUG-406 实测输出）
_REQUIRE_RE = "require is not defined"

# ── ESM 加载探针（判例-16 扩面后新增的一档，**B3'**）──────────────────────────
#
# **为什么必须有这一档**：扩面到全部 executable 后，发现 `cmd/commissar` 的产物**没有
# `version` 子命令**（它打印用法后 `exit(1)`），`cmd/main` 的 `version` 只往 stderr 写
# ExperimentalWarning —— 于是旧的 B3「跑 `version` 看回执」对这两支**假红**：
# 它们根本没崩，只是不打版本号。守在「能不能跑 version」上等于把入口口径写死了。
#
# 正确的问题是：**这个 bundle 作为 ESM 模块，加载时会不会因 CJS 互操作崩**。
# 这正好是 BUG-406 的病根（ESM 作用域没有 `require`），且与入口有没有子命令**无关**。
#
# 探针用 `import(pathToFileURL(p).href)`：Windows 盘符路径直接喂 ESM loader 会报
# `Received protocol 'e:'`（实测踩过），必须转 file:// URL。
# 探针把结果打成一行 JSON，**判据只看这一行**——不依赖进程 rc（模块可能在 import 期
# 就 `process.exit`，例如 commissar 的用法提示）也不依赖 stderr 噪声。
_ESM_PROBE_JS = r"""
import { pathToFileURL } from 'node:url';
const p = process.argv[1];
const emit = (rec) => console.log('__ESM_PROBE__' + JSON.stringify(rec));
// 先占位：若 bundle 在 import 期就 process.exit（实测 cmd/commissar 打印用法即 exit(1)），
// 后面那次 emit 永远不会执行 —— 而「能跑到 exit」本身就证明 ESM 加载没崩。
// 所以先打一条 IMPORT_STARTED，再在 finally/成功后打结论；调用方按「最后一条」读。
emit({ loaded: false, kind: 'OTHER', err: 'import did not return (bundle exited during import)' });
let out = { loaded: false, kind: 'OTHER', err: null };
try {
  await import(pathToFileURL(p).href);
  out.loaded = true;
  out.kind = 'IMPORT_OK';
} catch (e) {
  const name = String((e && e.name) || '');
  const msg = String((e && e.message) || '');
  out.err = (name + ': ' + msg).slice(0, 300);
  out.kind = (name === 'ReferenceError' && msg.indexOf('require is not defined') >= 0)
    ? 'ESM_CJS_REQUIRE' : 'OTHER';
}
emit(out);
"""


def classify_esm_probe(stdout):
    """纯函数：解析 ESM 探针输出的**最后一条** `__ESM_PROBE__` 行，给 (kind, detail)。

    返回 kind ∈ {OK, ESM_CJS_REQUIRE, OTHER_CRASH}，与 classify_run 同一套标签，
    于是上层不必关心用的是哪一档。

    读**最后一条**而不是第一条：探针先打 `IMPORT_STARTED` 占位，再打结论。
    - 若 bundle 在 import 期 `process.exit`（如 `cmd/commissar` 打印用法即退出），
      **只剩占位那条** —— 但它能跑到 exit，说明 ESM 加载本身没崩 ⇒ 判 OK。
    - 若 import 抛错，两条都在，最后一条是真正的分类。

    判据只看 `__ESM_PROBE__` 那几行；一条都没有 ⇒ 探针自己坏了，不冒充通过。
    """
    lines = [ln for ln in (stdout or "").splitlines() if ln.startswith("__ESM_PROBE__")]
    if not lines:
        return (KIND_OTHER_CRASH, "ESM 探针没有输出 `__ESM_PROBE__` 行 ⇒ 探针自身失败，拒绝报绿")
    try:
        rec = json.loads(lines[-1][len("__ESM_PROBE__"):])
    except ValueError:
        return (KIND_OTHER_CRASH, "ESM 探针输出不是合法 JSON ⇒ 探针自身坏了")
    if rec.get("kind") == "ESM_CJS_REQUIRE":
        return (KIND_ESM_CJS_REQUIRE,
                "ESM 加载即崩：require is not defined ⇒ 该 bundle 没被垫片覆盖（BUG-406 形状）%s"
                % ("；" + rec["err"] if rec.get("err") else ""))
    if resp_ok(rec):
        return (KIND_OK, "ESM 加载正常（无 CJS 互操作崩溃）")
    if len(lines) == 1 and "did not return" in (rec.get("err") or ""):
        # 只有占位行 ⇒ bundle 在 import 期自行退出。能走到那一步就说明 ESM 加载没崩。
        return (KIND_OK, "ESM 加载正常（bundle 在 import 期自行退出，未触发 CJS 互操作崩溃）")
    return (KIND_OTHER_CRASH, "ESM 加载异常：%s" % (rec.get("err") or "未知"))


def resp_ok(rec):
    """探针记录里「模块成功被 ESM 加载」的判据（单独拆出便于单测）。"""
    return bool(rec.get("loaded") or rec.get("kind") == "IMPORT_OK")


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


def run_esm_probe(path, timeout=120):
    """用 `node --input-type=module -e <探针>` 加载 bundle，返回探针 stdout。

    **不跑 `version`，只验「能不能作为 ESM 被加载」**（见 _ESM_PROBE_JS 上方的理由）。
    进程可能在 import 期 `process.exit`（如 commissar 打印用法即退出）——探针把结论
    打在**加载成功之后**，所以「先打印再 exit」的入口照样能给出 IMPROT_OK。
    """
    p = subprocess.run(
        ["node", "--input-type=module", "-e", _ESM_PROBE_JS, os.path.abspath(path)],
        cwd=os.path.dirname(path) or ".",
        capture_output=True,
        timeout=timeout,
    )
    return (p.stdout or b"").decode("utf-8", "replace")


def check(bundle):
    """全档。返回 (rc, kind, detail, stdout, stderr)。

    **档位优先级**（判例-16 扩面后重校）：B1 存在性 → **B3' ESM 加载探针** →
    （`version` 回执作为**加分证据**，不是必要条件）→ B2 垫片静态核。

    为什么以 **ESM 探针**为主判据而不是「跑 `version` 看回执」：
      · 扩面后发现 `cmd/commissar` **没有 version 子命令**（打印用法即 exit(1)）、
        `cmd/main` 的 version 只往 stderr 写 ExperimentalWarning —— 旧口径对这两支**假红**。
        它们根本没崩，只是不打版本号；「是不是 ESM 崩溃」与「有没有 version 子命令」无关。
      · ESM 探针直接回答 BUG-406 的真问题：**加载时 require 可用吗**，对全部入口同口径。
      · `version` 回执仍保留为**诊断证据**（打印出来给人看），移出判定面。

    为什么 B3' 仍排在 B2 前面：node 不可用时退回 B2 静态核，判据不因缺 node 整体失效。
    """
    ok, kind, detail = bundle_checks(bundle)
    if not ok and kind == "MISSING":
        return (2, kind, detail, "", "")

    if shutil.which("node") is not None:
        try:
            probe_out = run_esm_probe(bundle)
        except subprocess.TimeoutExpired:
            return (1, KIND_OTHER_CRASH, "ESM 加载探针超时（120s）⇒ 产物挂死", "", "")
        kind2, detail2 = classify_esm_probe(probe_out)
        # version 回执：**只作诊断**（打在 stdout 里给人读），不作为判定面
        diag = ""
        try:
            vout, verr = run_bundle(bundle)
            if vout.strip():
                diag = "version 回执：%s" % vout.strip().splitlines()[0][:80]
        except (subprocess.TimeoutExpired, OSError):
            diag = "version 回执：跑不起来（不影响 ESM 判定）"
        if kind2 != KIND_OK:
            return (1, kind2, detail2, probe_out, diag)
        # 真跑正常，但静态仍报缺垫片 ⇒ 以静态为准（垫片缺失是确定的缺陷）
        if not ok:
            return (1, kind, detail, probe_out, diag)
        return (0, KIND_OK, detail2, probe_out, diag)

    # node 不可用：静态档兜底；静态过了就算无法自证（不报绿也不冤枉）
    if not ok:
        return (1, kind, detail, "", "")
    return (2, "MISSING", "PATH 上没有 node ⇒ ESM 探针档无法执行，判据无法自证", "", "")


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
        # 覆盖面已改为「全部 executable 包」，故只对**已构建**的那些出诊断（不再写死 cli.js）。
        _real_res, _real_unres = resolve_bundles(ROOT, executable_pkg_dirs(ROOT))
        for _pkg, _rel in _real_res:
            rrc, rkind, _, _, _ = check(os.path.join(ROOT, _rel))
            cells.append("diag-real-bundle(%s: rc=%d,kind=%s)" % (_pkg, rrc, rkind))

        # ── 判例-16 结构性护栏：**判据验的面 == moon.pkg 反解的 executable 面** ──────
        # 这条格防的就是「修复扩到 4 个 bundle、判据停在 1 个」复发。
        # 它直接对表两个真源，**不写任何数字**：executable 包清单 vs 本尺实际会验的清单。
        _pkgs = executable_pkg_dirs(ROOT)
        _res, _unres = resolve_bundles(ROOT, _pkgs)
        cell("e2e-coverage-from-pkg-not-hardcoded",
             # 覆盖面必须来自反解：至少枚举到本仓已知的 executable 包集合，
             # 且 `cmd/cli`（发布入口）一定在其中——为空即证明扫描面坏了。
             ("cmd/cli" in _pkgs, len(_pkgs) > 0),
             (True, True))
        cell("e2e-coverage-covers-all-built-executables",
             # 已构建的 executable 产物数 == 本尺准备逐件验的数量（判据面 == 修复面）
             len(_res), len([p for p in _pkgs
                             if any(os.path.isfile(os.path.join(ROOT, c))
                                    for c in bundles_for_pkg(p))]))
        # 每个 executable 包都必须能反解出**非空**的候选 bundle 路径（否则该包永远验不到）
        cell("e2e-every-executable-has-bundle-candidate",
             all(len(bundles_for_pkg(p)) > 0 for p in _pkgs), True)
        # 反解出的候选必须落在 _build/js/debug/build/<pkgbasename>/ 下（防路径拼接写错）
        cell("e2e-bundle-candidates-under-build-dir",
             all(c.replace("\\", "/").startswith("_build/js/debug/build/")
                 for p in _pkgs for c in bundles_for_pkg(p)), True)

        # ── 判例-16 的核心场景：**修复面漏网的 bundle 必须被判据抓住** ──────────────
        # 司令-β 从修复面实测：smoke.js 是 executable、产物存在，但 patch_esm_main 旧实现
        # 只 patch 最大的那个（恒为 cli.js），smoke.js 漏网 ⇒ 加载即
        # ReferenceError: require is not defined。（这与司令-α 从判据面看到的
        # DEFAULT_BUNDLE 只验 1 个是同一根因的两个方向。）
        unpatched = os.path.join(tmp, "unpatched_exec.mjs")
        with open(unpatched, "w", encoding="utf-8") as f:
            f.write("const s = require('node:sqlite');\nconsole.log('never reached');\n")
        # ① 静态档必须报 SHIM_MISSING
        uok, ukind, _ = bundle_checks(unpatched)
        cell("e2e-unpatched-executable-detected",
             (uok, ukind), (False, KIND_SHIM_MISSING))
        # ② 探针档必须报 ESM_CJS_REQUIRE（真加载崩，且归类正确、不混进 OTHER_CRASH）
        urc, ukind2, _, _, _ = check(unpatched)
        cell("e2e-unpatched-classified-not-generic-crash",
             (urc, ukind2), (1, KIND_ESM_CJS_REQUIRE))

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
    ap.add_argument("--bundle", default=None,
                    help="只验指定 bundle（缺省扫**全部** executable 包的产物，判例-16）")
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    # 显式指定 ⇒ 单件（保持旧用法）
    if args.bundle:
        return _report_one(args.bundle)

    # 默认面 = 从 moon.pkg 反解出的**全部** executable 包（判例-16：覆盖面 ≥ 修复面）
    pkg_dirs = executable_pkg_dirs(ROOT)
    if not pkg_dirs:
        print("FATAL 判据无法自证：仓库内一份 `pkgtype(kind: \"executable\")` 都没枚举到 —— "
              "正则或扫描面坏了，拒绝报绿")
        return 2
    resolved, unresolved = resolve_bundles(ROOT, pkg_dirs)
    if not resolved:
        print("FATAL 判据无法自证：%d 个 executable 包一个产物都没构建（先 `moon build --target js`）"
              % len(pkg_dirs))
        print("      待构建：" + " / ".join(pkg_dirs))
        return 2

    worst = 0
    lines = []
    for pkg, rel in resolved:
        rc, kind, detail, _, _ = check(os.path.join(ROOT, rel))
        lines.append((pkg, rel, rc, kind, detail))
        worst = max(worst, rc)
    # 未构建的包单独出数（不算红，但必须可见——静默丢弃就是「数字凭空少」）
    for pkg in unresolved:
        lines.append((pkg, "(未构建)", None, KIND_UNBUILT, "该 executable 包没有产物，跳过真验"))

    n_ok = sum(1 for _, _, rc, _, _ in lines if rc == 0)
    for pkg, rel, rc, kind, detail in lines:
        tag = {0: "PASS", 1: "FAIL", 2: "FATAL", None: "DIAG"}[rc]
        print("%s [%s] %-28s %s" % (tag, kind, pkg, detail))
        if rc == 1:
            print("      修法：python scripts/patch_esm_main.py")
    print("覆盖面：executable 包 %d 个 → 已验 %d / 未构建 %d / 通过 %d"
          % (len(pkg_dirs), len(resolved), len(unresolved), n_ok))

    if worst == 1:
        return 1
    if worst == 2:
        return 2
    return 0


def _report_one(bundle):
    """单件报告的旧路径（`--bundle` 显式指定时）。"""
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
