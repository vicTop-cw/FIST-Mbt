#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_scripts_index.py — 工具类辅助代码单一索引守卫（R62）。

项目整洁 / 工具统一管理：所有「正式」辅助脚本（无 `_` 前缀）都必须在
`scripts/README.md` 中被登记（出现其文件名或去扩展名基名），否则视为「漏登记」
——把拳头①「地图一目了然」下沉到工具层，并防新生脚本不留说明就堆积。

与 check_badge / check_tools_sync / check_test_sync 同一守卫家族，可挂 CI。

用法：
    python scripts/check_scripts_index.py

退出码：0 = 全部正式脚本已登记；1 = 存在未登记脚本（打印缺失清单）。
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
README = SCRIPTS / "README.md"

# 无需登记的固定文件（文档/配套数据，非"工具"）
IGNORE_NAMES = {"README.md", "scoring_rubric.md", "_score_probe.py"}


def formal_scripts():
    """列出 scripts/ 下所有「正式」工具文件名（排除 _ 前缀临时脚本与固定文档）。"""
    ok = []
    for p in SCRIPTS.iterdir():
        if not p.is_file():
            continue
        name = p.name
        if name in IGNORE_NAMES:
            continue
        if name.startswith("_"):
            continue  # 临时脚本不要求登记（即用即清）
        ok.append(name)
    return ok


def main() -> int:
    if not README.exists():
        print(f"FAIL 缺少索引 {README}")
        return 1
    index_text = README.read_text(encoding="utf-8")
    missing = []
    for name in formal_scripts():
        base = Path(name).stem  # 去扩展名基名
        if name in index_text or base in index_text:
            continue
        missing.append(name)
    if missing:
        print("FAIL 以下正式辅助脚本未在 scripts/README.md 登记（工具统一管理缺口）：")
        for m in missing:
            print("  - " + m)
        return 1
    print("PASS 工具类辅助代码单一索引完整：所有正式脚本均已在 scripts/README.md 登记")
    return 0


if __name__ == "__main__":
    sys.exit(main())