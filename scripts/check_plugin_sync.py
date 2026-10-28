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
  J5 启动参数单一真源：plugins/claude/.mcp.json 与仓库根 .mcp.dev.json 逐字相等
     （BUG-131：真源按「跟踪面优先」解析，本机那份未跟踪的 .mcp.json 残留不得决定基线）；
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

# 工具注册真源的单一实现（此前 5 处复制；漏改即假绿/与生成器互掐）。
import importlib.util as _ilu

_ir_spec = _ilu.spec_from_file_location(
    "_tool_registry", Path(__file__).resolve().parent / "_tool_registry.py")
_tool_registry = _ilu.module_from_spec(_ir_spec)
_ir_spec.loader.exec_module(_tool_registry)

# BUG-58：GBK 控制台下中文判据文案会乱码/崩（不可读的守卫等于没有守卫）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
PLUGINS = ROOT / "plugins"
SERVER = ROOT / "src" / "server" / "server.mbt"
MOON_MOD = ROOT / "moon.mod"
# BUG-86：同 gen_plugins —— 真源文件名可解析，且必须把"取到了哪一份"打出来：
# 否则 J5 的"逐字相等"是在跟一个不存在的文件比。
# BUG-131：顺序与 gen_plugins 同步改为**跟踪面优先**（原来 .mcp.json 在前，本机那份未跟踪
# 残留会赢过仓库真源 ⇒ J5 拿残留当基线、投影正文跟着换文件名、CI 红而本机绿）。
MCP_CANDIDATES = (".mcp.dev.json", ".mcp.json")


def resolve_root_mcp(root: Path) -> Path:
    for name in MCP_CANDIDATES:
        cc = root / name
        if cc.exists():
            return cc
    return root / MCP_CANDIDATES[0]


ROOT_MCP = resolve_root_mcp(ROOT)

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
# BUG-157 同族（2026-10-14）：与 gen_plugins / check_tools_sync / check_doc_surface 同口径。
# 只扫 server.mbt 会得 148，而投影已是 166 ⇒ J6 会把正确的投影判成"不符"（实测：17 个投影重生成后
# 本守卫仍报 tools=166 与实测 148 不符）。真源扫描面必须跟着工具注册的拆分一起扩。
RE_TOOL_CHAIN = re.compile(r'\b\w+\.tool\(\s*"([^"]+)"')
SERVER_DIR = ROOT / "src" / "server"


def real_tools():
    """工具注册真源 —— **委托给单一实现** `scripts/_tool_registry.py`（2026-10-14 收口）。
    本函数曾在 5 个消费者里各写一份；漏改处会假绿或与生成器互掐（实测过两次）。"""
    return _tool_registry.real_tools()


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


# ↓ 严格参数面（R66）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
_known = {"--selftest", "--check"}
_unknown = [a for a in sys.argv[1:] if a.startswith("--") and a.split("=")[0] not in _known]
if _unknown:
    print("FATAL 未知参数：%s（本尺只接受：%s）" % (" ".join(_unknown), " ".join(sorted(_known))))
    sys.exit(2)

def _run_gen_check(cmd=None):
    """J1 的子进程入口：跑 `gen_plugins.py --check`，**可注入**以便自检钉住这条分支。

    为什么必须可注入（判例-29/30/50，2026-10-25 侦察兵实测）：
    本守卫的 `--selftest` 原先**只断言 `is_generated` 这类辅助纯函数，从不调 `main()`**，
    于是 J1 那条「生成器漂移 ⇒ 红」的主判据**一格自检都没有**。实测把
    `if r.returncode != 0:` 改成 `if False:`，`--selftest` 仍报 `SELFTEST OK`、一字不差
    ——四宿主插件漂移会全仓无人报警，而所有门禁都是绿的。

    可注入之后，自检传一条**必然非零**的假命令，就能断言 `problems` 里真的出现
    `J1 插件态漂移`，从而钉住「J1 分支还在不在」。
    """
    if cmd is None:
        cmd = [sys.executable, str(ROOT / "scripts" / "gen_plugins.py"), "--check"]
    return subprocess.run(
        cmd, capture_output=True, text=True, encoding="utf-8", errors="replace",
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )


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
    # 工具真源收口自检（2026-10-14）：本守卫已在 CI 的 Plugin-form guard 步里跑，
    # 而它依赖 `_tool_registry.real_tools()` 取真源。若该单一实现的"5 个消费者都接上"
    # 收口被破坏（有人把本地实现塞回来 / 断掉加载），本守卫会拿错口径去比投影，
    # 红面看起来像"插件漂移"而真因在收口 —— 故先把 `_tool_registry --selftest` 跑一遍，
    # 它红了就直接报"真源模块自检失败"（比让红面误导到插件面更早、更准）。
    r = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent / "_tool_registry.py"), "--selftest"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    if r.returncode != 0:
        out = (r.stdout or "") + (r.stderr or "")
        print("FATAL 工具真源模块自检失败（`scripts/_tool_registry.py --selftest`）——")
        print("      插件态比对的真源口径不可信，先修收口再读本守卫的结论：")
        for line in out.strip().splitlines()[-8:]:
            print("      " + line)
        return 2

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
    tools = real_tools()
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

    problems, generated, j_faces = collect_problems(tools, version)

    # ---- 判例-16 / 判例-50：J 面覆盖面对表（自我对表，主判据必须被自检认领）----
    # 为什么要在**主判据**里也跑一次：自检里的那一格只证明「selftest 认领了所有 J 面」，
    # 而「实现里到底有哪些 J 面」这个真源必须由**主判据**自己算、自己报——否则
    # 「实现新增了 J9 但自检没跟上」这件事只有自检自己知道，正判据看不见。
    problems.extend(j_face_self_consistency(j_faces))
    _LAST_J_FACES.clear()
    _LAST_J_FACES.update(j_faces)

    if problems:
        print(f"FAIL 插件态（一源四态 cl7）不一致（真源 {n} 工具 / v{version}）：")
        for p in problems:
            print("  - " + p)
        print(f"处置：python scripts/gen_plugins.py 重新生成后复跑本守卫")
        return 1
    print(
        f"PASS 插件态一致：4 宿主 / {len(generated)} "
        f"个生成文件 / {n} 工具 / v{version} / 启动参数真源 {ROOT_MCP.name}"
    )
    print("     J 面覆盖：%d 个面（%s）全部被 --selftest 认领"
          % (len(j_faces), ", ".join("J%s" % f for f in sorted(j_faces, key=_jnum))))
    return 0


def _rel(p):
    """把 Path 显示成「相对 ROOT」的形式；**不在 ROOT 子树内时退回绝对路径**。

    为什么不能直接用 `p.relative_to(ROOT)`：2026-10-25 补 J2~J6 变异格时实测，
    注入**临时目录**下的合成路径会让它抛 `ValueError: … is not in the subpath of …`
    —— 判据不是在报违例，而是**崩了**。判据对「被检路径不在仓库内」的形态必须
    优雅报出（它是被检输入，不是判据的 bug），否则任何走合成路径的自检都会炸。
    """
    try:
        return p.relative_to(ROOT)
    except ValueError:
        return p


def collect_problems(tools, version, gen_check_cmd=None, *,
                     host_entries=None, generated=None, plugins_dir=None,
                     mcp_pair=None):
    """主判据的可测内核：返回 (problems, generated, j_faces)。

    从 `main()` 抽出来是为了让自检能**真调主判据**（判例-29：自检必须命中实现路径，
    不能只测辅助纯函数）。

    **可注入参数**（2026-10-25 补 J2~J6 变异格，判例-29/30：
    「认领 ≠ 证明」——每条 J 分支都要有「变异 ⇒ 红」的真对照）：

    | 参数 | 覆盖 | 对应 J 面 |
    |---|---|---|
    | `gen_check_cmd` | J1 生成器子进程命令 | J1（原有） |
    | `host_entries` | 四宿主入口清单 `{host: [Path…]}` | **J2** |
    | `generated` | 生成文件清单（J3 扫占位符 / J6 扫 tools= 都读它） | **J3 / J6** |
    | `plugins_dir` | `plugins/` 根（J4 读 claude manifest） | **J4** |
    | `mcp_pair` | `(claude_mcp, root_mcp)` 两个 Path | **J5** |

    缺省全部取模块常量 ⇒ **生产路径零改动**。注入只在 `--selftest` 里用合成值，
    那正是判例-30 的要求：改坏的是**被测输入**，不是注释，且能确认变异真的生效。
    """
    n = len(tools)
    problems = []
    # 注入面（None ⇒ 取真源常量；生产路径行为逐字不变）
    _hosts = HOST_ENTRIES if host_entries is None else host_entries
    _plugins = PLUGINS if plugins_dir is None else plugins_dir
    _claude_mcp, _root_mcp = ((PLUGINS / "claude" / ".mcp.json", ROOT_MCP)
                              if mcp_pair is None else mcp_pair)
    # j_faces = **实现里执行过的 J 面**（不是「报过的面」）。
    # 为什么必须是「执行过」而不是「报过」：对表格要回答「这个 J 分支还在不在」，
    # 而干净仓库上所有分支都跑但都不报 —— 按「报过」记账会在干净面上得到空集合，
    # 于是对表格把 6 个面全判成「幻影格」（本修复第一版就是这么红的）。
    j_faces = set()

    # J1 漂移：必须由子进程跑生成器的 --check（同一份逻辑，两份实现互相制衡）
    j_faces.add("1")
    r = _run_gen_check(gen_check_cmd)
    if r.returncode != 0:
        head = (r.stdout or r.stderr or "").strip().splitlines()
        problems.append(
            "J1 插件态漂移：gen_plugins.py --check 退出码 "
            f"{r.returncode}（{head[0] if head else '无输出'}）"
        )
        for line in head[1:6]:
            problems.append("      " + line)

    # J2 四宿主齐全且非空
    j_faces.add("2")
    for host, files in _hosts.items():
        for f in files:
            if not f.exists():
                problems.append(f"J2 缺宿主入口：{host} → {_rel(f)}")
            elif f.stat().st_size == 0:
                problems.append(f"J2 宿主入口为空：{_rel(f)}")

    generated = generated_files() if generated is None else list(generated)
    j_faces.add("3")
    if _plugins.is_dir():
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
                problems.append(f"J3 残留未替换占位符：{_rel(p)}")
        # J6 每个 SKILL.md 的 stamp 计数 == 实测
        # BUG-67：原先只看 found[0]，正文里再抄第二个数字就没人对（"tools=120 的同一份
        # SKILL.md 里写着 105/112"就是这一眼漏过去的）。现在**每个** tools= 命中都必须等于实测。
        j_faces.add("6")
        for p in generated:
            if p.name != "SKILL.md":
                continue
            found = RE_STAMP_TOOLS.findall(p.read_text(encoding="utf-8", errors="replace"))
            if not found:
                problems.append(f"J6 SKILL.md 缺生成戳 tools=：{_rel(p)}")
            elif [x for x in found if x != str(n)]:
                problems.append(
                    f"J6 {_rel(p)} 有 {len(found)} 处 tools= 声明，"
                    f"其中与实测 {n} 不符的是 {sorted(set(found) - {str(n)})}"
                )

    # J4 claude manifest 自述版本 == moon.mod
    j_faces.add("4")
    for name in ("plugin.json", "marketplace.json"):
        f = _plugins / "claude" / ".claude-plugin" / name
        if f.exists():
            txt = f.read_text(encoding="utf-8")
            if f'version": "{version}' not in txt:
                problems.append(f"J4 {name} 未声明 moon.mod 版本 {version}")

    # J5 启动参数单一真源（逐字相等，防止两份 .mcp.json 漂移）
    j_faces.add("5")
    claude_mcp = _claude_mcp
    if not _root_mcp.exists():
        problems.append(
            "J5 仓库根启动参数真源不存在（试过 %s）——没有真源时『逐字相等』恒过，那是装饰"
            % ", ".join(MCP_CANDIDATES)
        )
    elif claude_mcp.exists():
        if claude_mcp.read_bytes() != _root_mcp.read_bytes():
            problems.append(
                "J5 plugins/claude/.mcp.json 与仓库根 %s 不一致（启动参数有两份真源）"
                % _root_mcp.name
            )

    return problems, generated, j_faces


# 主判据最近一次跑出来「实际存在」的 J 面集合（供自检对照，纯进程内、无副作用）
_LAST_J_FACES: set = set()

# 自检认领的 J 面清单。**新增 J\d 分支必须同批加进这里**，否则自检里那格对表会红。
# 这不是第二真源：实现真源是 collect_problems 里 `j_faces.add(...)`，本集合只声明
# 「这些面我已经配了自检格」——两边对不上就红（对表两个真源，不写死数字，判例-16）。
SELFTEST_CLAIMED_J_FACES = {"1", "2", "3", "4", "5", "6"}


def _jnum(x):
    try:
        return int(x)
    except Exception:
        return 999


def j_face_self_consistency(j_faces):
    """J 面对表（判例-16/50）：实现里出现的每个 J 面，必须被自检认领。

    这条在**主判据**里跑：它能看见「实现新增了 J9、自检没跟上」这件事。
    返回违例清单（空=对得上）。
    """
    problems = []
    unclaimed = sorted(set(j_faces) - SELFTEST_CLAIMED_J_FACES, key=_jnum)
    if unclaimed:
        problems.append(
            "J-COVERAGE 实现里有 J 面未被 --selftest 认领：%s（新增 J 分支必须同批补自检格并"
            "加进 SELFTEST_CLAIMED_J_FACES，否则这条主判据没有自证）"
            % ", ".join("J%s" % f for f in unclaimed)
        )
    stale = sorted(SELFTEST_CLAIMED_J_FACES - set(j_faces), key=_jnum)
    if stale:
        problems.append(
            "J-COVERAGE 自检认领了实现里不存在的 J 面：%s（自述滞后于实现——要么补实现，"
            "要么从认领表里删掉，不留幻影格）"
            % ", ".join("J%s" % f for f in stale)
        )
    return problems


def selftest() -> int:
    """负向自检：BUG-70 合成违例必抓、真源不误抓、真实枚举非空，**且主判据的 J 面全被认领**。

    2026-10-25 侦察兵实测的假绿与修复（判例-29/30/50）：
      本自检原先**只断言 `is_generated` 这类辅助纯函数，从不调 `main()`**，于是 J1
      「生成器漂移 ⇒ 红」这条 **cl7 主判据一格自检都没有**——把 `if r.returncode != 0:`
      改成 `if False:`，自检仍报 `SELFTEST OK` 且一字不差。四宿主插件漂移会全仓无人报警。

      修法两层（组合，不只做一层）：
        ① 把生成器子进程抽成可注入的 `_run_gen_check(cmd)`，自检注入**必然非零**的假命令，
           断言 `collect_problems()`（主判据真身）真的报出 `J1 插件态漂移`；
        ③ 按判例-16 补 **J 面覆盖面对表**：断言「实现里出现的每个 J 面」都被本自检认领，
           且认领表里没有实现里不存在的幻影面。
    """
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

    tools = real_tools()
    version = (RE_VERSION.search(MOON_MOD.read_text(encoding="utf-8")) or [None, "0"])[1]

    # ① J1 变异对照（判例-29/30/50）：注入**必然非零**的假命令 ⇒ 主判据必须报 J1 漂移
    rc_bad = subprocess.CompletedProcess(
        args=[], returncode=7, stdout="SIMULATED DRIFT: plugins 与投影不一致\n", stderr="")
    fake_cmd = [sys.executable, "-c", "raise SystemExit(7)"]
    probs_bad, _, faces_bad = collect_problems(tools, version, gen_check_cmd=fake_cmd)
    if not any("J1 插件态漂移" in p for p in probs_bad):
        fails.append(
            "J1-变异对照失守：注入必然非零的生成器命令后，主判据没报 `J1 插件态漂移`"
            f" ⇒ J1 分支已失效（拿到的 problems={probs_bad[:2]}）")
    if "1" not in faces_bad:
        fails.append("J1-变异对照失守：J1 触发后没把 J 面 '1' 记进 j_faces（覆盖面记账漏了）")
    else:
        # 判例-50 自证：**确认变异真的改变了被测行为**，而不是「变异没生效所以绿」
        # （假命令 rc=7 与真命令 rc=0 必须不同，否则这一格等于没测）
        real_rc = _run_gen_check().returncode
        if real_rc == rc_bad.returncode:
            fails.append(
                "判例-50 自证失败：假命令 rc=%d 与真生成器 rc=%d 相同 ⇒ 本格没区分开『漂移』"
                "与『干净』，变异未命中锁" % (rc_bad.returncode, real_rc))

    # ③ J 面覆盖面对表（判例-16）：实现里出现的每个 J 面都必须被本自检认领
    probs_ok, _, faces_ok = collect_problems(tools, version)

    # ── ④ J2~J6 变异对照（2026-10-25，判例-29/30/50）────────────────────────────
    #
    # **为什么必须补**：β 修完 J1 后自己承认的边界 ——
    #   「J2~J6 有认领、无变异。按判例-29/30，认领 ≠ 证明。」
    # 认领格（上面的 J-COVERAGE 对表）只能证明「自检**声称**管了这 6 个面」，
    # 证明不了「每个面的分支真的会红」。判例-30 的病灶正是这个：格子在、断言在、
    # 匹配也命中，但**改坏真代码后锁恒绿**。
    #
    # 统一用**合成输入注入**（`collect_problems` 的五个关键字参数），不用改仓库文件：
    #   · 判例-30 要求「改坏的是代码不是注释」⇒ 注入的是**被测输入**（路径/文件内容），
    #     主判据的分支代码一行没动，但它拿到的世界是坏的 —— 这才是真变异；
    #   · 判例-50 要求「先验变异真的改变了被测行为」⇒ 每格都对比
    #     `clean（不注入）` 与 `mutated（注入坏值）` 的 problems，两者必须不同。
    import tempfile as _tf

    _tmp = _tf.TemporaryDirectory(prefix="cl7-mut-")
    try:
        _tp = Path(_tmp.name)

        # —— 干净的合成世界：四宿主入口都存在且非空 / 生成集合非空且无占位符 /
        #    claude manifest 版本正确 / .mcp.json 与根真源逐字相等 ——
        # 这个世界必须让 J2~J6 **全绿**，否则下面的变异就分不清「红是因为变异」还是「本来就红」。
        _hosts = {}
        for host in HOST_ENTRIES:
            f = _tp / host / "entry.md"
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text("# entry\n", encoding="utf-8")
            _hosts[host] = [f]
        _gen_ok = _tp / "gen" / "SKILL.md"
        _gen_ok.parent.mkdir(parents=True, exist_ok=True)
        _gen_ok.write_text("tools=%d\n" % len(tools), encoding="utf-8")
        _plugins_ok = _tp / "plugins"
        (_plugins_ok / "claude" / ".claude-plugin").mkdir(parents=True, exist_ok=True)
        for name in ("plugin.json", "marketplace.json"):
            (_plugins_ok / "claude" / ".claude-plugin" / name).write_text(
                '{"version": "%s"}' % version, encoding="utf-8")
        _claude_mcp_ok = _tp / "claude.mcp.json"
        _root_mcp_ok = _tp / "root.mcp.json"
        _claude_mcp_ok.write_bytes(b'{"mcpServers": {}}')
        _root_mcp_ok.write_bytes(b'{"mcpServers": {}}')

        def _run(**kw):
            """在合成世界上跑主判据。默认参数即干净世界。"""
            base = dict(host_entries=_hosts, generated=[_gen_ok],
                        plugins_dir=_plugins_ok,
                        mcp_pair=(_claude_mcp_ok, _root_mcp_ok))
            base.update(kw)
            return collect_problems(tools, version, **base)

        # 基线：干净世界必须**零 J2~J6**问题（J1 由真生成器跑，干净仓应为 0）
        _clean, _, _ = _run()
        _clean_j = [p for p in _clean if any(p.startswith("J%d" % i) for i in (2, 3, 4, 5, 6))]
        if _clean_j:
            fails.append("J2~J6 变异基线不干净（合成世界本应全绿，实际报 %s）⇒ 下面的变异无意义"
                         % _clean_j[:2])

        # ── J2 变异：把某个宿主入口换成**不存在**的路径 ──
        _h2 = dict(_hosts)
        _h2["atomcode"] = [_tp / "atomcode" / "GHOST.md"]      # 不存在
        _p2, _, _f2 = _run(host_entries=_h2)
        _j2 = [p for p in _p2 if p.startswith("J2")]
        if not any("J2 缺宿主入口" in p for p in _j2):
            fails.append("J2-变异对照失守：注入不存在的宿主入口后，主判据没报 `J2 缺宿主入口`")
        # 判例-50：变异必须真的改变行为（干净 0 条 vs 变异 ≥1 条）
        if len(_j2) == len(_clean_j):
            fails.append("J2-变异对照未生效：注入坏入口前后的 J2 问题数相同 ⇒ 变异没命中判据")

        # ── J3 变异：生成文件里塞残留占位符 `{{` ──
        _gen3 = _tp / "gen3.md"
        _gen3.write_text("tools=%d\n{{PLACEHOLDER}}\n" % len(tools), encoding="utf-8")
        _p3, _, _ = _run(generated=[_gen3])
        _j3 = [p for p in _p3 if p.startswith("J3")]
        if not any("J3 残留未替换占位符" in p for p in _j3):
            fails.append("J3-变异对照失守：注入含 `{{` 的生成文件后，主判据没报 `J3 残留未替换占位符`")
        if len(_j3) == 0:
            fails.append("J3-变异对照未生效：占位符注入后 J3 一条都没报 ⇒ 变异没命中判据")

        # ── J4 变异：claude manifest 声明**错误版本** ──
        _plugins4 = _tp / "plugins4"
        (_plugins4 / "claude" / ".claude-plugin").mkdir(parents=True, exist_ok=True)
        for name in ("plugin.json", "marketplace.json"):
            (_plugins4 / "claude" / ".claude-plugin" / name).write_text(
                '{"version": "99.99.99-WRONG"}', encoding="utf-8")
        _p4, _, _ = _run(plugins_dir=_plugins4)
        _j4 = [p for p in _p4 if p.startswith("J4")]
        if not any("J4" in p and "未声明 moon.mod 版本" in p for p in _j4):
            fails.append("J4-变异对照失守：注入错误版本后，主判据没报 `J4 … 未声明 moon.mod 版本`")
        if len(_j4) == 0:
            fails.append("J4-变异对照未生效：错误版本注入后 J4 一条都没报 ⇒ 变异没命中判据")

        # ── J5 变异：claude/.mcp.json 与根真源**内容不同** ──
        _claude5 = _tp / "claude5.mcp.json"
        _claude5.write_bytes(b'{"mcpServers": {"DRIFT": true}}')     # 与根真源不同
        _p5, _, _ = _run(mcp_pair=(_claude5, _root_mcp_ok))
        _j5 = [p for p in _p5 if p.startswith("J5")]
        if not any("J5" in p and "不一致" in p for p in _j5):
            fails.append("J5-变异对照失守：注入内容不同的启动参数后，主判据没报 `J5 … 不一致`")
        if len(_j5) == 0:
            fails.append("J5-变异对照未生效：内容漂移注入后 J5 一条都没报 ⇒ 变异没命中判据")

        # ── J6 变异：SKILL.md 的 tools= 写成**错误数字** ──
        _gen6 = _tp / "gen6" / "SKILL.md"
        _gen6.parent.mkdir(parents=True, exist_ok=True)
        _gen6.write_text("tools=%d\n" % (len(tools) + 7), encoding="utf-8")   # 故意偏差 7
        _p6, _, _ = _run(generated=[_gen6])
        _j6 = [p for p in _p6 if p.startswith("J6")]
        if not any("J6" in p and "不符" in p for p in _j6):
            fails.append("J6-变异对照失守：注入错误 tools= 数字后，主判据没报 `J6 … 不符`")
        if len(_j6) == 0:
            fails.append("J6-变异对照未生效：错误计数注入后 J6 一条都没报 ⇒ 变异没命中判据")
        # 判例-50 强化：J6 的偏差必须**被具体点名**（不是笼统红）
        if _j6 and not any(str(len(tools) + 7) in p for p in _j6):
            fails.append("J6-变异对照点名失效：报红了但没写出实际偏差值 %d" % (len(tools) + 7))
    finally:
        _tmp.cleanup()

    unclaimed = sorted(set(faces_ok) - SELFTEST_CLAIMED_J_FACES, key=_jnum)
    if unclaimed:
        fails.append(
            "J-COVERAGE 实现里有 J 面未被自检认领：%s（新增 J 分支必须同批补自检格并加进"
            " SELFTEST_CLAIMED_J_FACES）" % ", ".join("J%s" % f for f in unclaimed))
    stale = sorted(SELFTEST_CLAIMED_J_FACES - set(faces_ok), key=_jnum)
    if stale:
        fails.append(
            "J-COVERAGE 自检认领了实现里不存在的 J 面：%s ⇒ 幻影格"
            % ", ".join("J%s" % f for f in stale))
    # 反证：对表格本身必须能红（在合成输入上试一次，证明它不是恒绿装饰）
    fake_probe = j_face_self_consistency(set(faces_ok) | {"99"})
    if not fake_probe:
        fails.append("J-COVERAGE 对表格是装饰：塞进幻影面 J99 后仍不报 ⇒ 该格恒绿")

    if fails:
        print("SELFTEST FAIL（cl7 判据自身违例）：")
        for f in fails:
            print("  - " + f)
        return 1
    print(f"SELFTEST OK：合成克隆路径两判都对，真实生成集合 {len(real)} 个文件；"
          f"J1 变异对照已钉住（假命令 rc={rc_bad.returncode} ⇒ 报 J1 插件态漂移）；"
          f"J 面覆盖对表通过（{len(SELFTEST_CLAIMED_J_FACES)} 个面：%s）"
          % ", ".join("J%s" % f for f in sorted(SELFTEST_CLAIMED_J_FACES, key=_jnum)))
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else main())
