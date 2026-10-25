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


def collect_problems(tools, version, gen_check_cmd=None):
    """主判据的可测内核：返回 (problems, generated, j_faces)。

    从 `main()` 抽出来是为了让自检能**真调主判据**（判例-29：自检必须命中实现路径，
    不能只测辅助纯函数）。`gen_check_cmd` 透传给 `_run_gen_check`——自检据此注入
    必然非零的假命令，钉住 J1 分支。
    """
    n = len(tools)
    problems = []
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
    for host, files in HOST_ENTRIES.items():
        for f in files:
            if not f.exists():
                problems.append(f"J2 缺宿主入口：{host} → {f.relative_to(ROOT)}")
            elif f.stat().st_size == 0:
                problems.append(f"J2 宿主入口为空：{f.relative_to(ROOT)}")

    generated = generated_files()
    j_faces.add("3")
    if PLUGINS.is_dir():
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
        j_faces.add("6")
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
    j_faces.add("4")
    for name in ("plugin.json", "marketplace.json"):
        f = PLUGINS / "claude" / ".claude-plugin" / name
        if f.exists():
            txt = f.read_text(encoding="utf-8")
            if f'version": "{version}' not in txt:
                problems.append(f"J4 {name} 未声明 moon.mod 版本 {version}")

    # J5 启动参数单一真源（逐字相等，防止两份 .mcp.json 漂移）
    j_faces.add("5")
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
