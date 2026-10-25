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


def patch(main_js: str) -> bool:
    if not os.path.exists(main_js):
        raise FileNotFoundError(f"not found: {main_js} (先 moon build --target js)")
    with open(main_js, "r", encoding="utf-8") as f:
        c = f.read()
    if "createRequire" in c:
        return False  # 已打过补丁（幂等）
    with open(main_js, "w", encoding="utf-8") as f:
        f.write(SHIM + c)
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