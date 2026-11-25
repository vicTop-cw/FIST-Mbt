#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""patch_esm_main.py —— 修复 moonc 0.10.14+ 下 JS 可执行产物为 ESM 时,
mizchi/sqlite 内部 `require("node:sqlite")` 抛 "require is not defined in ES module scope" 的兼容层。

原因：moonc ≥ 0.10.14 对 `cmd/main`(executable) 输出 ESM bundle(顶层 import)，
而 mizchi/sqlite 的 JS 桩用 CJS `require`。Node ESM 中无裸 require。
在 bundle 顶部注入 `import {createRequire} from "node:module"; const require=createRequire(import.meta.url)`
即可让同一个模块作用域内的 require 可用（幂等，重复调用安全）。

用法：python scripts/patch_esm_main.py [路径]
路径缺省时自动扫描 <repo>/_build/js/debug/build/ 找最大 .js（MoonBit 可执行产物，>100KB）。
任何 runner(demo.ps1 / mcp_smoke.py)在 `moon build` 后先调用本脚本再启动 server。
"""
import os
import sys

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.abspath(__file__)) + os.sep + ".."
ROOT = os.path.normpath(ROOT)
def _find_executable_js() -> str | None:
    """自动发现 _build/js/debug/build/cmd/*/ 下的可执行产物（最大的 .js）。
    硬编码路径兼容旧行为，优先用自动发现。
    保留此函数供旧调用方/文档；**新逻辑见 _find_all_bundles**。"""
    all = _find_all_bundles()
    return all[0] if all else None


def _find_all_bundles() -> list[str]:
    """发现 `_build/js/{debug,release}/build/` 下**所有**可执行 bundle（>100KB 的 .js）。

    BUG-406（统帅 R36）：原实现只取"最大的那个"，于是 `cmd/main/main.js` 被 patch 了，
    而 `cmd/cli/cli.js`、`cmd/commissar/commissar.js` **漏网**——它们同样含
    `require("node:sqlite")`（来自上游 daqing/sqlite），同样会 ESM 崩溃。
    改为 patch **全部**，并在脚本用法注释里说明任何 runner 在 `moon build` 后调用即可。

    BUG-406 追记（2026-10-25）：又发现**只扫 debug profile** —— `moon build --release`
    的产物（打包/安装面、DSH Desktop 等宿主实际拉起的那份）从没被 patch，
    `node _build/js/release/build/cmd/cli/cli.js version` 照样
    `ReferenceError: require is not defined in ES module scope`。
    实测：本机 MCP server 由宿主用 release profile 拉起、跑了 18 小时仍崩在旧产物上。
    现同时扫 debug + release，两个 profile 都覆盖。
    """
    found = []
    for profile in ("debug", "release"):
        build_dir = os.path.join(ROOT, "_build", "js", profile, "build")
        if not os.path.isdir(build_dir):
            continue
        for root, dirs, files in os.walk(build_dir):
            for f in files:
                if f.endswith(".js") and not f.endswith(".mbti.js"):
                    fp = os.path.join(root, f)
                    try:
                        sz = os.path.getsize(fp)
                    except OSError:
                        continue
                    if sz > 100_000:
                        found.append(fp)
    # 按大小降序（最大的在前，保持旧行为的顺序直觉）
    found.sort(key=lambda p: os.path.getsize(p), reverse=True)
    return found


# 注释示例: 手动指定时 python scripts/patch_esm_main.py _build/js/debug/build/cmd/cli/cli.js
# 自动发现: 扫描 _build/js/debug/build/ 下最大的 .js（非测试产物）

SHIM = "import { createRequire as _cr } from 'node:module';\nconst require = _cr(import.meta.url);\n"


GATE_MARKER = "FIST_MBT_MIN_NODE_MAJOR"


def node_gate_present(c: str) -> bool:
    """是否已经带版本门（**单独一个符号**，与垫片无关）。

    旧产物只打了垫片、没有门（实测 `dist/fist-mbt.js` 里 `process.versions.node` 零命中）。
    垫片与门是两件事：垫片修 CJS 互操作（BUG-406），门拦 Node<24（T0r84）——
    各自可独立缺失，故不能拿「有没有垫片」当「有没有门」。
    """
    return GATE_MARKER in (c or "")


# ── Node 版本门（T0r84 / 计划条目 2026-11-25「Node 版本门」）────────────────────
#
# **为什么门必须在产物前言、而不能写在 MoonBit 源码里**：
# `src/server/server.mbt:29` 是**模块级** `let main_store : @store.SqliteStore? = @store.SqliteStore::new()`，
# 而 `cmd/cli/main.mbt` 要经 `run_server()` 才走到它。产物是 ESM，`import` 全部先于模块体求值
# ⇒ 源码里任何位置的门都跑在 store 构造**之后**，等于没设。本前言紧跟垫片注入：它排在
# **垫片之后、产物自身依赖图的第一个 import 之前**（ESM 里先声明的 import 先求值，
# 而 moonc 把产物的 import 全放在正文开头），是唯一「先门后库」的位置。
# ⚠️ 别把口径写成「早于全部 import」——垫片 `SHIM` 自己就是一条 import，那条判据对真产物恒红。
#    锁的实际口径：门排在**垫片之后、产物自身第一个顶层 import 之前**（判据同此）。
#
# **为什么 <24 需要显式拦**：`toolchain.json` 的 node 地板是 24（`why_node`：SQLite 依赖
# `node:sqlite` 的 `returnArrays`；node<24 退化为对象行，列读取为空）。那个退化不是崩溃而是
# **静默错**——不设门就等于容忍假绿。npm/宿主启动器（`packaging/dsh/launch-mcp.mjs:44-51`）
# 与安装器（`scripts/blackbox/install_onecmd.ps1:48`）已有 ≥24 提示，缺口只在**裸调**
# `node dist/fist-mbt.js serve` / `node _build/js/*/build/cmd/cli/cli.js serve`。
#
# 阈值在本脚本只出现一次（`MIN_NODE_MAJOR`）；文档面的地板一致性另有 `check_doc_surface`
# J17 对表 `toolchain.json`。
MIN_NODE_MAJOR = 24

# 用 **const** 而非 var：产物以 ESM 严格模式加载，且 const 不挂 globalThis，零污染。
NODE_GATE = (
    "const FIST_MBT_MIN_NODE_MAJOR = %d;\n"
    "if (Number((process.versions.node || '0').split('.')[0]) < FIST_MBT_MIN_NODE_MAJOR) {\n"
    "  console.error('fist-mbt: 需要 Node.js >= ' + FIST_MBT_MIN_NODE_MAJOR\n"
    "    + '（当前 ' + process.versions.node + '）。');\n"
    "  console.error('原因：JS 后端的 SQLite 依赖 node:sqlite 的 returnArrays，'\n"
    "    + '更早的 Node 会退化为对象行、列读取为空（toolchain.json 的 why_node）。');\n"
    "  console.error('解决：升级 Node 到 24 或更新（Windows: winget install OpenJS.NodeJS.LTS；'\n"
    "    + '或改用 native 目标）。');\n"
    "  process.exit(1);\n"
    "}\n"
) % MIN_NODE_MAJOR


def _strip_injected(c: str) -> str:
    """剥掉前言里**已注入**的垫片与门，还原 moonc 原始正文。

    两者都是本脚本逐字写入的常量文本，moonc 不会产出同串 ⇒ 按前缀剥离是安全的。
    顺序固定为「垫片 → 门」；旧产物只有垫片，剥完即回到原始正文。
    """
    rest = c
    if rest.startswith(SHIM):
        rest = rest[len(SHIM):]
    if rest.startswith(NODE_GATE):
        rest = rest[len(NODE_GATE):]
    return rest


def patch(main_js: str) -> bool:
    if not os.path.exists(main_js):
        raise FileNotFoundError(f"not found: {main_js} (先 moon build --target js)")
    with open(main_js, "r", encoding="utf-8") as f:
        c = f.read()
    if "createRequire" in c and node_gate_present(c):
        return False  # 已打过补丁（幂等：垫片与门都在）
    # 门插在垫片之后、原有正文之前 ⇒ 先于全部 import 求值（唯一「先门后库」位）。
    body = _strip_injected(c)
    with open(main_js, "w", encoding="utf-8") as f:
        f.write(SHIM + NODE_GATE + body)
    return True


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("--help", "-h"):
        print(__doc__)
        sys.exit(0)
    if len(sys.argv) > 1:
        # 显式指定：仍支持单文件（旧用法）
        changed = patch(sys.argv[1])
        print(("patched " if changed else "up to date  ") + sys.argv[1])
        sys.exit(0)
    # 自动发现：patch **所有**可执行 bundle（BUG-406 修复点）
    bundles = _find_all_bundles()
    if not bundles:
        print("ERROR: no executable .js found in _build/js/debug/build/. Run 'moon build --target js <pkg>' first.", file=sys.stderr)
        sys.exit(1)
    total_changed = 0
    for target in bundles:
        changed = patch(target)
        total_changed += 1 if changed else 0
        print(("patched " if changed else "up to date  ") + target)
    print("total patched: %d / %d bundles" % (total_changed, len(bundles)))
    sys.exit(0)