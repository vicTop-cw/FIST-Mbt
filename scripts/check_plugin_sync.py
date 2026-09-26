#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_plugin_sync.py — 一源四态·插件态一致性守卫（cl7，挂守卫家族）。

四态 = MCP（src/server）/ CLI（scripts/fist.py）/ Skill（plugins/source）/ Plugin（plugins/<host>）。
插件态最容易腐烂：它是**投影**，投影一旦改成手写就会长期落后于真源
（外部 moonbit-skills 里的旧 skill 曾把工具数写成 41，正是 BUG-22/30 那一类）。
本守卫把"投影必须等于生成结果"变成硬门：

  J1 漂移：子进程重跑 `gen_plugins.py --check`（生成器与守卫分开，防止自证自）；
  J2 四宿主齐全：atomcode / codearts / deepseek-harness / claude 各自的入口文件存在且非空；
  J3 无残留占位符：plugins/ 下任何文件不得含 `{{`（说明生成器没跑完或真源改了没重生成）；
  J4 版本一致：claude 两个 manifest 的 version == moon.mod 的 version；
  J5 启动参数单一真源：plugins/claude/.mcp.json 与仓库根 .mcp.json 逐字相等；
  J6 计数一致：每个生成 SKILL.md 的 stamp 里 tools= 必须等于 server.mbt 实测工具数；
  J7 反幻影哨兵：实测工具数 <=100 直接 FATAL 退出 2——解析失败绝不报 PASS。

与 check_tools_sync / check_test_sync / check_badge / check_scripts_index 同一守卫家族，可挂 CI。

用法：python scripts/check_plugin_sync.py
退出码：0=四态插件一致；1=存在漂移/缺项/不一致；2=判据自身无法自证（真源解析失败）。
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGINS = ROOT / "plugins"
SERVER = ROOT / "src" / "server" / "server.mbt"
MOON_MOD = ROOT / "moon.mod"
ROOT_MCP = ROOT / ".mcp.json"

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
RE_VERSION = re.compile(r'^version\s*=\s*"([^"]+)"', re.M)
RE_STAMP_TOOLS = re.compile(r"tools=(\d+)")

# 宿主入口（顺序即指定顺序）：缺任何一个都不算"四态齐全"
HOST_ENTRIES = {
    "atomcode": [PLUGINS / "atomcode" / "skills" / "fist-mbt" / "SKILL.md"],
    "codearts": [
        PLUGINS / "codearts" / "skills" / "fist-mbt" / "SKILL.md",
        PLUGINS / "codearts" / "UserSkillStatus.append.txt",
    ],
    "deepseek-harness": [PLUGINS / "deepseek-harness" / "instructions.append.md"],
    "claude": [
        PLUGINS / "claude" / ".claude-plugin" / "plugin.json",
        PLUGINS / "claude" / ".claude-plugin" / "marketplace.json",
        PLUGINS / "claude" / ".mcp.json",
        PLUGINS / "claude" / "skills" / "fist-mbt" / "SKILL.md",
    ],
}


def main() -> int:
    # Windows 控制台默认 cp936：守卫一旦要打印中文子进程输出就会 UnicodeEncodeError 崩掉
    # （崩溃的守卫等于没有守卫）。先把自身输出钉成 UTF-8，再给子进程同样的环境变量。
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if not SERVER.exists():
        print(f"FATAL 真源缺失 {SERVER}（判据无法自证）")
        return 2
    tools = sorted(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8"))))
    n = len(tools)
    # J7 反幻影：解析退化时绝不给绿灯
    if n <= 100:
        print(f"FATAL 工具真源解析到 {n} 个（<=100 视为解析失败），本守卫无法自证")
        return 2
    mv = RE_VERSION.search(MOON_MOD.read_text(encoding="utf-8"))
    if not mv:
        print("FATAL moon.mod 未解析到 version")
        return 2
    version = mv.group(1)
    problems = []

    # J1 漂移：必须由子进程跑生成器的 --check（同一份逻辑，两份实现互相制衡）
    r = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "gen_plugins.py"), "--check"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    if r.returncode != 0:
        head = (r.stdout or r.stderr or "").strip().splitlines()
        problems.append(
            "J1 插件态漂移：gen_plugins.py --check 退出码 "
            f"{r.returncode}（{head[0] if head else '无输出'}）"
        )
        for line in head[1:6]:
            problems.append("      " + line)

    # J2 四宿主齐全且非空
    for host, files in HOST_ENTRIES.items():
        for f in files:
            if not f.exists():
                problems.append(f"J2 缺宿主入口：{host} → {f.relative_to(ROOT)}")
            elif f.stat().st_size == 0:
                problems.append(f"J2 宿主入口为空：{f.relative_to(ROOT)}")

    if PLUGINS.is_dir():
        generated = [
            p for p in PLUGINS.rglob("*")
            if p.is_file() and "source" not in p.parts
        ]
        # J3 无残留占位符
        for p in generated:
            txt = p.read_text(encoding="utf-8", errors="replace")
            if "{{" in txt:
                problems.append(f"J3 残留未替换占位符：{p.relative_to(ROOT)}")
        # J6 每个 SKILL.md 的 stamp 计数 == 实测
        for p in generated:
            if p.name != "SKILL.md":
                continue
            found = RE_STAMP_TOOLS.findall(p.read_text(encoding="utf-8", errors="replace"))
            if not found:
                problems.append(f"J6 SKILL.md 缺生成戳 tools=：{p.relative_to(ROOT)}")
            elif found[0] != str(n):
                problems.append(
                    f"J6 {p.relative_to(ROOT)} 声明 tools={found[0]}，实测 {n}"
                )

    # J4 claude manifest 自述版本 == moon.mod
    for name in ("plugin.json", "marketplace.json"):
        f = PLUGINS / "claude" / ".claude-plugin" / name
        if f.exists():
            txt = f.read_text(encoding="utf-8")
            if f'version": "{version}' not in txt:
                problems.append(f"J4 {name} 未声明 moon.mod 版本 {version}")

    # J5 启动参数单一真源（逐字相等，防止两份 .mcp.json 漂移）
    claude_mcp = PLUGINS / "claude" / ".mcp.json"
    if claude_mcp.exists():
        if claude_mcp.read_bytes() != ROOT_MCP.read_bytes():
            problems.append("J5 plugins/claude/.mcp.json 与仓库根 .mcp.json 不一致（启动参数有两份真源）")

    if problems:
        print(f"FAIL 插件态（一源四态 cl7）不一致（真源 {n} 工具 / v{version}）：")
        for p in problems:
            print("  - " + p)
        print(f"处置：python scripts/gen_plugins.py 重新生成后复跑本守卫")
        return 1
    print(
        f"PASS 插件态一致：4 宿主 / {len([p for p in PLUGINS.rglob('*') if p.is_file() and 'source' not in p.parts])} "
        f"个生成文件 / {n} 工具 / v{version}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
