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

# BUG-58：GBK 控制台下中文判据文案会乱码/崩（不可读的守卫等于没有守卫）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
PLUGINS = ROOT / "plugins"
SERVER = ROOT / "src" / "server" / "server.mbt"
MOON_MOD = ROOT / "moon.mod"
# BUG-86：同 gen_plugins —— 真源文件名可解析（.mcp.json 优先，回落 .mcp.dev.json），
# 且必须把"取到了哪一份"打出来：否则 J5 的"逐字相等"是在跟一个不存在的文件比。
MCP_CANDIDATES = (".mcp.json", ".mcp.dev.json")


def resolve_root_mcp(root: Path) -> Path:
    for name in MCP_CANDIDATES:
        cc = root / name
        if cc.exists():
            return cc
    return root / MCP_CANDIDATES[0]


ROOT_MCP = resolve_root_mcp(ROOT)

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
RE_VERSION = re.compile(r'^version\s*=\s*"([^"]+)"', re.M)


def is_generated(p, plugins=None):
    """p 是否属于"生成投影"（而不是真源 plugins/source/）。纯函数，可喂合成路径自测。"""
    plugins = PLUGINS if plugins is None else plugins
    rel = p.relative_to(plugins)
    return bool(rel.parts) and rel.parts[0] != "source"


def generated_files():
    """四宿主的生成投影（排除真源 plugins/source/）。

    BUG-70：原来写的是 `"source" not in p.parts`，而 `p` 来自 PLUGINS.rglob —— parts 里含
    **整条绝对路径**。把仓库克隆到 C:/source/FIST-Mbt 这类任一段叫 source 的目录时，
    真源过滤会顺手把所有生成文件也滤掉，集合变空而判据照打 PASS。
    ⇒ 只按"相对 PLUGINS 的第一段"判归属，绝对路径长什么样都无关。
    """
    if not PLUGINS.is_dir():
        return []
    return sorted(p for p in PLUGINS.rglob("*") if p.is_file() and is_generated(p))
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
        generated = generated_files()
        # BUG-70 反幻影哨兵：集合为空时 J3/J6 会"无对象可比"而打 PASS —— 判据无法自证绝不报绿
        if not generated:
            problems.append(
                f"FATAL 生成文件集合为空（PLUGINS={PLUGINS}）⇒ J3/J6 全程空转，不是"
                "插件干净，是枚举器坏了"
            )
        # J3 无残留占位符
        for p in generated:
            txt = p.read_text(encoding="utf-8", errors="replace")
            if "{{" in txt:
                problems.append(f"J3 残留未替换占位符：{p.relative_to(ROOT)}")
        # J6 每个 SKILL.md 的 stamp 计数 == 实测
        # BUG-67：原先只看 found[0]，正文里再抄第二个数字就没人对（"tools=120 的同一份
        # SKILL.md 里写着 105/112"就是这一眼漏过去的）。现在**每个** tools= 命中都必须等于实测。
        for p in generated:
            if p.name != "SKILL.md":
                continue
            found = RE_STAMP_TOOLS.findall(p.read_text(encoding="utf-8", errors="replace"))
            if not found:
                problems.append(f"J6 SKILL.md 缺生成戳 tools=：{p.relative_to(ROOT)}")
            elif [x for x in found if x != str(n)]:
                problems.append(
                    f"J6 {p.relative_to(ROOT)} 有 {len(found)} 处 tools= 声明，"
                    f"其中与实测 {n} 不符的是 {sorted(set(found) - {str(n)})}"
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
    if not ROOT_MCP.exists():
        problems.append(
            "J5 仓库根启动参数真源不存在（试过 %s）——没有真源时『逐字相等』恒过，那是装饰"
            % ", ".join(MCP_CANDIDATES)
        )
    elif claude_mcp.exists():
        if claude_mcp.read_bytes() != ROOT_MCP.read_bytes():
            problems.append(
                "J5 plugins/claude/.mcp.json 与仓库根 %s 不一致（启动参数有两份真源）"
                % ROOT_MCP.name
            )

    if problems:
        print(f"FAIL 插件态（一源四态 cl7）不一致（真源 {n} 工具 / v{version}）：")
        for p in problems:
            print("  - " + p)
        print(f"处置：python scripts/gen_plugins.py 重新生成后复跑本守卫")
        return 1
    print(
        f"PASS 插件态一致：4 宿主 / {len(generated_files())} "
        f"个生成文件 / {n} 工具 / v{version}"
    )
    return 0


def selftest() -> int:
    """负向自检：BUG-70 的合成违例必须被抓、真源必须不被误抓，且真实仓库上枚举非空。"""
    fails = []
    clone = Path("C:/source/proj")  # 路径中间段就叫 source —— 旧过滤器正是在这里失明的
    gen = clone / "plugins" / "atomcode" / "skills" / "fist-mbt" / "SKILL.md"
    src = clone / "plugins" / "source" / "SKILL.md"
    if not is_generated(gen, clone / "plugins"):
        fails.append(f"BUG-70 仍在：克隆到 …/source/… 下时生成文件被判成局外（{gen}）")
    if is_generated(src, clone / "plugins"):
        fails.append("成对反例失守：真源 plugins/source/ 被当成生成投影（会拿真源自比自）")
    real = generated_files()
    if len(real) < 40:
        fails.append(f"真实仓库上只枚举到 {len(real)} 个生成文件（<40 ⇒ 枚举器空转）")
    if is_generated(PLUGINS / "source" / "SKILL.md"):
        fails.append("本仓真源 plugins/source/SKILL.md 被算进了生成集合")
    if fails:
        print("SELFTEST FAIL（cl7 判据自身违例）：")
        for f in fails:
            print("  - " + f)
        return 1
    print(f"SELFTEST OK：合成克隆路径两判都对，真实生成集合 {len(real)} 个文件")
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
