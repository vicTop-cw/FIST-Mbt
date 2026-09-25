#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_tools_sync.py — 工具清单单一真源一致性守卫（CI JS 轨）。
唯一真源：src/server/server.mbt 里实际注册的工具名
（`instrumented_tool(\n s1,\n "<name>",` 的第二个字符串实参）。
校验 AGENTS.md 的"MCP Server"工具分组表、README/AGENTS/deliverable/scoring_rubric 的工具总数对齐：
  1. 表格行首个反引号名（工具名单元）必须真实存在（防"文档出现不存在的工具"）；
  2. 真源全部工具必须出现在 AGENTS.md（防"新增工具忘写文档"）；
  3. README/AGENTS/deliverable/scoring_rubric 的工具总数表述 == 实测。
任一漂移即 FAIL（退出码非 0）。

用法：python scripts/check_tools_sync.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "src" / "server" / "server.mbt"
AGENTS = ROOT / "AGENTS.md"
README = ROOT / "README.md"
DELIV = ROOT / "docs" / "deliverable.md"
RUBRIC = ROOT / "scripts" / "scoring_rubric.md"

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
RE_BACKTICK = re.compile(r"`([\w\-]+)`")


def real_tools():
    return sorted(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8"))))


def main():
    tools = real_tools()
    real = set(tools)
    n = len(tools)
    problems = []
    agents = AGENTS.read_text(encoding="utf-8")

    # 1) 表格行首个反引号名 ⊆ 真源
    claimed = set()
    for line in agents.splitlines():
        if line.strip().startswith("|"):
            m = RE_BACKTICK.search(line)
            if m:
                claimed.add(m.group(1))
    phantom = sorted(claimed - real)
    if phantom:
        problems.append("AGENTS 表格出现但 server 未注册: " + ", ".join(phantom))

    # 2) 真源全部工具都应在 AGENTS 出现
    missing = sorted(t for t in tools if t not in agents)
    if missing:
        problems.append(f"server 注册但 AGENTS 未列出 ({len(missing)}): " + ", ".join(missing))

    # 3) 各文档工具总数 == 实测
    re_near = re.compile(rf"MCP 工具[\s\S]{{0,30}}?{re.escape(str(n))}")
    for path in (README, AGENTS, DELIV, RUBRIC):
        txt = path.read_text(encoding="utf-8")
        ok = (f"{n} 个 MCP 工具" in txt) or (f"{n} tools" in txt) \
            or (f"工具 {n}" in txt) or (f"（{n} 工具" in txt) \
            or (f"{n} MCP 工具" in txt) or bool(re_near.search(txt))
        if not ok:
            problems.append(f"{path.name} 缺少工具总数 {n} 的表述")

    if problems:
        print(f"FAIL 工具清单不一致（实测 {n} 个）：")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"PASS 工具单一真源一致：server.mbt 注册 {n} 个，AGENTS/README/deliverable/scoring_rubric 对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())