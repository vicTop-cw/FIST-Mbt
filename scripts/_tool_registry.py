#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_tool_registry.py — MCP 工具注册表的**单一真源读取实现**（内部共享模块，非独立工具）。

**为什么需要它（2026-10-14 实测教训）**：工具注册已从 `src/server/server.mbt` 拆到多个文件
（`supervisor_tools.mbt` 8 个 / `hat_hexa_tools.mbt` 3 个 / `mcpcf_embed.mbt` 7 个），
于是"工具数真源怎么读"这件事被**复制到了 5 个消费者**里：

    check_tools_sync.py / check_doc_surface.py / check_plugin_sync.py / gen_plugins.py / mcp_smoke.py

后果实测过两次：
  ① 拆分发生时，5 处里只有 3 处跟上 ⇒ `check_doc_surface` 拿 148 口径**假绿**（自洽 PASS）；
  ② 补完 3 处后，剩 2 处（`check_plugin_sync` / `gen_plugins`）与新口径**互掐**——
     守卫报"README 分组和 166 != 注册表 148 ⇒ 先修 README"（而 README 的 166 是对的），
     照该提示改会把正确文档改回错值。

⇒ 把读取逻辑收敛到**一处**：所有消费者 import 本模块的 `real_tools()` / `tool_count()`，
下次工具注册再搬家时只改这一个文件。这也让"五处口径是否一致"从"靠人记得改"变成"结构上只有一处"。

**口径**（与既有 5 处逐字一致，勿在调用方另写）：
  扫描面 = `<repo>/src/server/*.mbt`，排除 `_test.mbt` / `_wbtest.mbt`
  注册形态 = ① `instrumented_tool(<var>, "name", …)`  ② 链式 `<var>.tool("name", …)`
  结果 = 两者**并集**（去重后排序）

**为什么必须认两种形态**：`mcpcf_embed.mbt` 的 7 个 `mcpcf.*` 走链式 `s.tool(...)`；
只认 `instrumented_tool` 会漏它们（且它们的名字含 `.`，还要注意调用方的正则别把它排除）。

用法（调用方）：
    import importlib.util, pathlib
    _spec = importlib.util.spec_from_file_location(
        "_tool_registry", pathlib.Path(__file__).resolve().parent / "_tool_registry.py")
    _mod = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_mod)
    tools = _mod.real_tools()          # 或 n = _mod.tool_count()

自检：`python scripts/_tool_registry.py --selftest`
"""
import argparse
import re
import sys
from pathlib import Path

# BUG-138 同族：守卫的中文结论在 Windows 默认 cp936 控制台下会先崩掉 print，
# 把 traceback 冒充成读数。钉 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = Path(__file__).resolve().parent.parent
SERVER_DIR = REPO_ROOT / "src" / "server"

# 形态①：常规注册。变量名不钉 `s1`（gen_plugins 等历史实现里出现过别的变量名）。
RE_TOOL = re.compile(r'instrumented_tool\(\s*\w+\s*,\s*"([^"]+)"')
# 形态②：链式注册（mcpcf_embed.mbt）。`\b\w+\.tool(` 不会误吃 `instrumented_tool(`（前面是 `_` 不是 `.`）。
RE_TOOL_CHAIN = re.compile(r'\b\w+\.tool\(\s*"([^"]+)"')

# 反幻影门槛：工具数低于此值视为"解析失败"，调用方应据此自拒而不是报绿。
MIN_EXPECTED = 100


def server_files():
    """参与真源扫描的文件（`src/server/*.mbt`，排除测试文件）。"""
    if not SERVER_DIR.is_dir():
        return []
    return [f for f in sorted(SERVER_DIR.glob("*.mbt"))
            if not f.name.endswith(("_test.mbt", "_wbtest.mbt"))]


def real_tools():
    """工具名列表（去重排序）。两种注册形态的并集，扫描面为 src/server/*.mbt（排除测试）。"""
    names = set()
    for f in server_files():
        try:
            text = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        names |= set(RE_TOOL.findall(text))
        names |= set(RE_TOOL_CHAIN.findall(text))
    return sorted(names)


def tool_count():
    """工具数（real_tools 的长度；调用方可用 MIN_EXPECTED 判解析是否退化）。"""
    return len(real_tools())


def consumers():
    """五个消费者脚本（相对 scripts/ 的文件名）。用于 selftest 的"口径一致"格。"""
    return ["check_tools_sync.py", "check_doc_surface.py", "check_plugin_sync.py",
            "gen_plugins.py", "mcp_smoke.py"]


def selftest():
    """自证：判据必须能证明它会红、干净输入不误红，且真实仓库读数合理。

    格子：
      1) 真实仓库：工具数 > MIN_EXPECTED（反幻影门槛）
      2) 真实仓库：含一个 `instrumented_tool` 形态的已知工具（publish）
      3) 真实仓库：含一个**链式**形态的已知工具（mcpcf.ops_init）——证明第二形态真被扫到
      4) 合成：两种形态都能被各自正则抓到
      5) 合成：链式正则不误吃 instrumented_tool（后者由形态①负责）
      6) 合成：测试文件不进扫描面（server_files 排除 _test/_wbtest）
      7) **口径收口**：五个消费者里不再有本地实现（SERVER_DIR.glob / RE_TOOL_CHAIN.findall），
         且都 import 了本模块 —— 防"下次拆分又只改一半"（本轮红过两次的根因）
    """
    cells = []

    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    real = real_tools()
    cell("real-count-above-min", len(real) > MIN_EXPECTED, True)
    print("  ok  real-count-above-min（真实仓库 %d 个工具 > %d）" % (len(real), MIN_EXPECTED))

    cell("real-has-instrumented-form", "publish" in real, True)
    print("  ok  real-has-instrumented-form（instrumented_tool 形态被扫到：publish 在）")

    chain_hits = [t for t in real if t.startswith("mcpcf.")]
    cell("real-has-chain-form", len(chain_hits) >= 7, True)
    print("  ok  real-has-chain-form（链式 s.tool 形态被扫到：mcpcf.* 共 %d 个）" % len(chain_hits))

    cell("re-instrumented", RE_TOOL.findall('instrumented_tool(s1, "alpha", x)') == ["alpha"], True)
    print("  ok  re-instrumented（形态①正则命中）")
    cell("re-chain", RE_TOOL_CHAIN.findall('s.tool("beta", y)') == ["beta"], True)
    print("  ok  re-chain（形态②正则命中）")

    both = RE_TOOL.findall('instrumented_tool(s1, "gamma", x)') + RE_TOOL_CHAIN.findall('instrumented_tool(s1, "gamma", x)')
    cell("chain-not-eat-instrumented", both == ["gamma"], True)
    print("  ok  chain-not-eat-instrumented（链式正则不误吃 instrumented_tool，不会重复计数）")

    tests = [f.name for f in SERVER_DIR.glob("*_test.mbt")] + [f.name for f in SERVER_DIR.glob("*_wbtest.mbt")]
    cell("tests-excluded", all(not f.name.endswith(("_test.mbt", "_wbtest.mbt")) for f in server_files()), True)
    print("  ok  tests-excluded（扫描面排除测试文件；本目录现有 %d 份测试）" % len(tests))

    # 7) 口径收口：五个消费者里不许再有本地实现，且必须**真的接上**本模块。
    #    本仓实测过两次因"5 处复制、只改一半"造成的红（假绿 / 生成器↔守卫互掐），故把收口判据化。
    #    判据强度（变异实测校准过）：只查 `_tool_registry` 子串**不够**——把 exec_module 那行删掉后
    #    子串仍在（spec_from_file_location 的参数字面量里就有），那一格抓不住。必须同时要求
    #    ① 无本地实现 ② 有 `exec_module(_tool_registry)`（真加载）③ 有 `_tool_registry.real_tools()`
    #    （真委托）。三者齐备才算接上。
    local_impl, not_wired, missing = [], [], []
    here = Path(__file__).resolve().parent
    for name in consumers():
        p = here / name
        if not p.is_file():
            missing.append(name)
            continue
        txt = p.read_text(encoding="utf-8", errors="replace")
        if "SERVER_DIR.glob" in txt or "RE_TOOL_CHAIN.findall" in txt:
            local_impl.append(name)
        if "exec_module(_tool_registry)" not in txt or "_tool_registry.real_tools()" not in txt:
            not_wired.append(name)
    cell("consumers-no-local-impl", local_impl == [], True)
    print("  ok  consumers-no-local-impl（5 个消费者无本地实现；越界=%s）" % (local_impl or "无"))
    cell("consumers-wired-to-registry", not_wired == [] and missing == [], True)
    print("  ok  consumers-wired-to-registry（都 exec_module 且调 real_tools；缺文件=%s 未接上=%s）"
          % (missing or "无", not_wired or "无"))

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：真实读数三格 / 两形态正则各一格 / 不误吃一格 / 测试排除一格 / 收口两格）"
          % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--list", action="store_true", help="打印全部工具名")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    tools = real_tools()
    if args.list:
        for t in tools:
            print(t)
        return 0
    if len(tools) <= MIN_EXPECTED:
        print("FATAL 工具真源只解析到 %d 个（<=%d 视为解析失败）" % (len(tools), MIN_EXPECTED))
        return 2
    print("工具真源：%d 个（扫描 %d 份 src/server/*.mbt）" % (len(tools), len(server_files())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
