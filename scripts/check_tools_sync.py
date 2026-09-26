#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_tools_sync.py — 工具清单单一真源一致性守卫（CI JS 轨）。
唯一真源：src/server/server.mbt 里实际注册的工具名
（`instrumented_tool(\n s1,\n "<name>",` 的第二个字符串实参）。
校验 AGENTS.md 的"MCP Server"工具分组表、README/AGENTS/deliverable/scoring_rubric 的工具总数对齐：
  1. 表格行首个反引号名（工具名单元）必须真实存在（防"文档出现不存在的工具"）；
  2. 真源全部工具必须出现在 AGENTS.md（防"新增工具忘写文档"）；
  3. README/AGENTS/deliverable/scoring_rubric 的工具总数表述 == 实测；
  4. src/ops/ops_modes.mbt 的 mode_forbidden_tools 名单必须都是真注册名（BUG-37）——
     拦红线的名单写了不存在的工具，机器面上就等于没有红线；
  5. server.mbt 不得再向调用方广告时钟入参 `"now": string_prop`（BUG-33）——
     时钟由服务端盖章（BUG-1），广告一个没人读的参数就是契约在说谎；
  6. templates/pipeline_mode_*.md 里"工具名形状"的反引号词必须真实存在（BUG-37 的文档面）：
     形如 `publish_new_feature_task` 这种由真实动词前缀拼出来的臆造名，正是本条要抓的形状。
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
OPS_MODES = ROOT / "src" / "ops" / "ops_modes.mbt"
TEMPLATES = sorted((ROOT / "templates").glob("pipeline_mode_*.md"))

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
RE_BACKTICK = re.compile(r"`([\w\-]+)`")
RE_FORBIDDEN_BODY = re.compile(
    r"fn mode_forbidden_tools\([^)]*\).*?\n\}", re.S
)
RE_NOW_AD = re.compile(r'"now"\s*:\s*string_prop|、now 时间戳')
# "被当成工具调用"的反引号名：`name(...)` 形状 —— 只有工具才会带括号出现，
# 因此不会把 project_dir / task_id 这类参数名误纳进来。
RE_TOOL_SHAPE = re.compile(r"`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)\(")



def real_tools():
    return sorted(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8"))))


def main():
    # 与守卫族同款：cp936 控制台下中文判据文案会乱码（崩溃/不可读的守卫等于没有守卫）。
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    tools = real_tools()
    real = set(tools)
    n = len(tools)
    problems = []
    agents = AGENTS.read_text(encoding="utf-8")
    server_txt = SERVER.read_text(encoding="utf-8")

    # 反幻影：真源解析退化时绝不给绿灯（与 cl7 守卫同口径）
    if n <= 100:
        print(f"FATAL server.mbt 只解析到 {n} 个工具（<100），判据已退化，拒绝出绿灯")
        return 2

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

    # 4) mode_forbidden_tools 名单必须都是真注册名（BUG-37）
    m = RE_FORBIDDEN_BODY.search(OPS_MODES.read_text(encoding="utf-8"))
    if not m:
        print("FATAL 无法解析 src/ops/ops_modes.mbt 的 mode_forbidden_tools（判据无法自证）")
        return 2
    ft_names = [
        x for arm in re.findall(r"=>\s*\[([^\]]*)\]", m.group(0)) for x in re.findall(r'"([^"]+)"', arm)
    ]
    if not ft_names:
        print("FATAL mode_forbidden_tools 解析到 0 个名字（判据已退化，拒绝出绿灯）")
        return 2
    for x in ft_names:
        if x not in real:
            problems.append(f"mode_forbidden_tools 含未注册工具名 {x}（BUG-37：名单空转，红线只剩文字）")

    # 5) 不得再向调用方广告时钟入参（BUG-33）
    if RE_NOW_AD.search(server_txt):
        problems.append('server.mbt 重新广告了 "now" 入参（BUG-33：时钟由服务端盖章，广告无人读的参数=契约说谎）')

    # 6) 模板中以 `name(...)` 调用形状出现的名字必须是真注册名（BUG-38 文档面）
    for tpl in TEMPLATES:
        for tok in sorted(set(RE_TOOL_SHAPE.findall(tpl.read_text(encoding="utf-8")))):
            if tok not in real:
                problems.append(
                    f"{tpl.name} 以调用形状引用了未注册工具 `{tok}(...)`（BUG-38：按模板执行必然调空）"
                )

    if problems:
        print(f"FAIL 工具清单不一致（实测 {n} 个）：")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"PASS 工具单一真源一致：server.mbt 注册 {n} 个，AGENTS/README/deliverable/scoring_rubric 对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())