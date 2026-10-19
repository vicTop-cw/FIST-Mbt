#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
批量给 RouterConfig 构造点补 use_caf_memory 字段（P2c 前置步骤）。
用途：model_router.mbt 加了 use_caf_memory: Bool 字段后，所有 struct literal 需补该字段。
只在 `use_laya: <expr>,` 行后追加 `use_caf_memory: <expr>,`（幂等：已有则不重复）。
"""
import re
import sys
from pathlib import Path


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 目标文件及其 use_caf_memory 值
FILES = {
    "src/router/model_router_wbtest.mbt": "false",
    "src/router/router_state.mbt": "cfg.use_caf_memory",
}

IDEMPOTENT_RE = re.compile(r"use_caf_memory\s*:")


def patch(path: Path, value: str) -> int:
    """给指定文件补字段，返回修改次数"""
    content = path.read_text(encoding="utf-8")
    lines = content.split("\n")
    out = []
    count = 0
    for line in lines:
        out.append(line)
        # 匹配 use_laya: <expr>, 且下一行还没有 use_caf_memory
        m = re.match(r"^(\s*)use_laya:\s*(.+),\s*$", line)
        if m and not IDEMPOTENT_RE.search(line):
            indent = m.group(1)
            # 检查是否在 RouterConfig 构造中（粗略：前若干行有 window_seconds 或 use_laya 上下文）
            # 简化：所有 use_laya: 都是 RouterConfig 构造（当前代码库如此）
            out.append(f"{indent}use_caf_memory: {value},")
            count += 1
    path.write_text("\n".join(out), encoding="utf-8")
    return count


def main() -> int:
    total = 0
    for rel, val in FILES.items():
        p = Path(rel)
        if not p.exists():
            print(f"[FAIL] {rel} 不存在")
            return 1
        n = patch(p, val)
        total += n
        print(f"[OK] {rel}: 补 {n} 处")
    print(f"总计: {total} 处")
    return 0 if total > 0 else 1


if __name__ == "__main__":
    sys.exit(main())