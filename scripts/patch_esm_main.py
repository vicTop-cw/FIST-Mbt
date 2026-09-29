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

ROOT = os.path.dirname(os.path.abspath(__file__)) + os.sep + ".."
ROOT = os.path.normpath(ROOT)
def _find_executable_js() -> str | None:
    """自动发现 _build/js/debug/build/cmd/*/ 下的可执行产物（最大的 .js）。
    硬编码路径兼容旧行为，优先用自动发现。"""
    build_dir = os.path.join(ROOT, '_build', 'js', 'debug', 'build')
    if not os.path.isdir(build_dir):
        return None
    candidates = []
    for root, dirs, files in os.walk(build_dir):
        for f in files:
            if f.endswith('.js') and not f.endswith('.mbti.js'):
                fp = os.path.join(root, f)
                try:
                    sz = os.path.getsize(fp)
                except OSError:
                    continue
                if sz > 100_000:  # 产物 > 100KB
                    candidates.append((sz, fp))
    if not candidates:
        return None
    candidates.sort(reverse=True)  # 最大的那个
    return candidates[0][1]


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
    if len(sys.argv) > 1:
        target = sys.argv[1]
    else:
        auto = _find_executable_js()
        if not auto:
            print("ERROR: no executable .js found in _build/js/debug/build/. Run 'moon build --target js <pkg>' first.", file=sys.stderr)
            sys.exit(1)
        target = auto
    changed = patch(target)
    print(("patched " if changed else "up to date  ") + target)
    sys.exit(0)