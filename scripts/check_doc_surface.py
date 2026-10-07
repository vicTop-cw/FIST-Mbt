#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_doc_surface.py — 文档面单一真源守卫（BUG-22 / BUG-30 的判据化）。

为什么要有这个文件：现有三守卫（check_tools_sync / check_test_sync / check_badge）
只校验**工具数**和**测试数**两件事。于是两类漂移能一路绿灯通过：
  · README 把标题数字改对了，正文分组表却没跟上（BUG-22：标题 116、正文只列 103、
    缺的正是 AGENTS.md 已补录的那 10 个工具）；
  · 文档里的版本自述与 moon.mod 不一致（BUG-30：USAGE.md 仍写 @0.2.3、
    README 说已发布 0.2.5 而 BACKLOG 说 0.2.4）。
本脚本把"标题对了正文没对""数字对了版本没对"这两类补上。

用法：
    python scripts/check_doc_surface.py            # 全量判据
    python scripts/check_doc_surface.py --selftest # 自检判据本身没坏

判据（任一不满足即 FAIL，退出码非 0）：
  J1 真源：src/server/server.mbt 注册的工具集合 N。
  J2 AGENTS.md 与 README.md 都必须**逐个覆盖**这 N 个工具名（不是只写对数字）。
  J3 README.md 功能全景各分组标题括号里的数字之和必须 == N。
  J4 所有文档里 `vicTop-cw/fist-mbt@x.y.z` 形态的**当前自述**版本必须 == moon.mod 的 version；
     例外：CHANGELOG.md、memory/、reports/、docs/polish-plan.md 属历史/计划陈述，允许旧值。
     子判据（BUG-30）：注册表**发布版本**（"已发布到 x.y.z"）只允许一处权威自述 = BACKLOG.md；
     本机没有注册表复核通道，第二处发布版本只能和权威面打架 ⇒ 别的现状面出现即红。
     扫描面为空、权威面缺声明、枚举器少于 10 份 .md 都判红，不许"没抓到 = 没问题"。
  J5 反幻影：J2/J3 若在"清单为空"时也能通过，就是判据自己坏了 —— 因此 J2 前置哨兵
     断言 N>100、AGENTS/README 解析到的名字数 >100，否则直接判 FATAL（而不是 PASS）。
  J6 规范正文 ↔ 机器投影一致（R116 新增）：AI-DEVELOPMENT-STANDARD.md 必须含
     project_standards.mbt 下发的全部规则 id（r1..r5 / f1..f5 / cl1..cl7）与同一 version，
     且工具输出必须带 canonical_doc 指针、README/AGENTS 必须点名该正文。
     （一源四态用在规范上：正文只有一个，其余是摘要与投影。）
  J7 旧口径禁词（R116 新增）：规范性表面（README/AGENTS/docs/templates/对外工具描述）
     不得残留「三形态」「一源三态」；memory/ reports/ CHANGELOG scripts/ 属历史陈述，豁免不追改。
  J8 模板调用面契约（R116 新增）：templates/*.md 里对**已注册工具**的调用示例与参数表，
     顶层参数名必须 ∈ 该工具在 server.mbt 声明的属性集，且不得缺 required。
     为什么必须有：_instrument 只校验 required，未知键被**静默丢弃**（BUG-31 同族）——
     模板写 `check_results`/`dry_run`/`now` 时 agent 以为自己在跑硬门，实际什么都没验。
     只比 depth-1 键，artifacts 数组元素里的 path/contains 等子 schema 键不误伤。
  J9 工具描述的返回契约（BUG-74/83）：对 server.mbt 里**每个工具的描述**做三件事——
     ① 必查清单里的工具必须写"返回 {…}"（认中文「返回」，英文 returns 不算，口径放宽=恒过）；
     ② 歧义键分工清单（如 run_check 的 ok/status）必须点名该键职责，抹掉分工即红、写清不误红，
        清单里的工具从注册表消失也判红（清单失效比缺契约更糟）；
     ③ 棘轮 RET_FLOOR：写了返回契约的工具数只许升不许降。
  J10 判据范围自述 == 实际实现（BUG-84）：AGENTS/模板/插件真源里"J1-JN"式的范围声明，
     与本脚本 `def jN_…` / `---- JN` 反解出的实现上界比对——少写=声明滞后，多写=幻影判据，
     两个方向都判红；扫描面为空、实现侧解析不到、两面一致却红，同样判红。
  J11 CI native 门步骤 ↔ 账本/规范面 三向对表（BUG-130 裁决③ 的执行面不许被悄悄删掉）：
     锚是账本上 BUG-133 抬头仍 OPEN ⇒ 每条 native 臂必须有且只有一道名字含 heap gate 的门、
     门必须挂在全量测试步骤**之前**、规范面反引号逐字点名的步名必须**等于** workflow 里的步名；
     单转 FIXED 后这一格自然失效（不留恒红判据）。尺子自保三支：账本读不到那条单 / 一份 workflow 都没读到 /
     某份 workflow 解析不到 `- name:` ⇒ 一律 FATAL，不拿"没抓到"当"没问题"。
  J12 CI 的 `if:` 守卫里不许钉分支名（BUG-132：恒假条件的门比没有门更坏）：
     `if:` 出现 `refs/heads/<分支>` 即红——分支名一变那道门就**永不可能运行**，而读数里它长得像
     「未触发所以正常」的绿灯位。分支过滤交回 `on.push.branches`（那里写错最多是少跑，不会伪装成一道门）。
     扫描面从 `.github/workflows/*.yml` 目录派生（手写清单必然落后于新增 workflow），
     且**先看剔掉注释之后的代码面**（墓碑注释里正当性地引用着旧条件，不剔就是自家注释喂回针——R9 的旧坑）。

  J13 CHANGELOG 标题里的发布状态短语不许落后于 BACKLOG 的 release-fact 读数（BUG-135）：
     形状是「标题写 GitHub Release 未发布」+「标题的盖章戳」+「权威面的 published 时刻」三者对不上——
     豁免历史文件是对的（历史不许改写），但「未发布」是现在时断言，戳晚于事实那一刻起它就在骗读者，
     而骗得最像真的位置恰恰是标题。权威面做成 BACKLOG 里机器可读的 `release-fact:` 标记
     （现成散文写的是「与本条同一版本号」，那不是可解析锚，判据不猜版本归属）。
     两支反向对照（戳早于 published 不误红 / 权威面没记这一版则这一格不作数），
     两面任一为空 ⇒ FATAL 自拒；标记自身残缺、同版本两条、版本与资产名打架也都判红。

设计约束：不改被校验的文档、不写库、纯只读。
"""
import inspect
import os
import re
import subprocess
import sys
from pathlib import Path

# BUG-58：守卫的“红”必须是判据红。Windows 默认 GBK 控制台下，中文结论里的 ↔ 等字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent  # 从 scripts/ 或 temp/ 运行都指向仓库根


def rel_posix(p) -> str:
    """违例文案里的路径一律 POSIX 分隔。
    账本/报告要**逐字**引用判据回执，而 `str(Path.relative_to(...))` 在 Windows 上打印
    `scripts\\README.md`、在 CI 上打印 `scripts/README.md` ⇒ 同一支尺两种文案，对表时只能靠猜。
    （名字不叫 `rel`：`is_plugin_surface` 里已有一个同名的局部相对路径变量。）"""
    return Path(p).relative_to(ROOT).as_posix()


SERVER = ROOT / "src" / "server" / "server.mbt"
PS_MBT = ROOT / "src" / "server" / "project_standards.mbt"
CANON = ROOT / "AI-DEVELOPMENT-STANDARD.md"  # 规范性正文：与 README/AGENTS 同级，放仓库根
SKILL_DOC = ROOT / "docs" / "project-standards-skill.md"
TEMPLATES_DIR = ROOT / "templates"
# BUG-66：插件投影真源（plugins/source/）是"发货正文"，四宿主由 gen_plugins.py 逐字节复制。
# 它此前不在任何判据射程内 ⇒ 一句过时的参数广告会被放大成 4 份对外契约。
PLUGIN_SRC = ROOT / "plugins" / "source"
DOCS_DIR = ROOT / "docs"
MOONMOD = ROOT / "moon.mod"
AGENTS = ROOT / "AGENTS.md"
README = ROOT / "README.md"
USAGE = ROOT / "USAGE.md"
BACKLOG = ROOT / "BACKLOG.md"

# J4 允许保留旧版本号的文件（历史陈述/计划/日志），不与"当前自述"混判
HISTORICAL = re.compile(r"^(CHANGELOG\.md|.*[/\\](memory|reports)[/\\].*)$")

RE_TOOL = re.compile(r"instrumented_tool\(\s*s1\s*,\s*\"([^\"]+)\"")
RE_BACKTICK = re.compile(r"`([a-z_][a-z_0-9]*)`")
RE_SELFVER = re.compile(r"vicTop-cw/fist-mbt@(\d+\.\d+\.\d+)")

# J6：规则 id 形状（r1-doc-as-impl / f2-four-forms-aligned / cl7-plugin-forms-sync）
RE_PS_ID = re.compile(r"\"id\": Json::string\(\"((?:r|f|cl)\d[a-z0-9-]*)\"\)")
RE_PS_VER = re.compile(r"\"version\":\s*Json::string\(\"(R\d+)\"\)")

# J7：规范性表面 + 禁词（历史陈述豁免）
STALE_NEEDLES = (
    "三形态",
    "一源三态",
    # BUG-66：`now` 是本项目**已删除**的调用面参数（BUG-33 政策：时间戳服务端盖章），
    # 规范性表面（含插件投影真源 plugins/source/）再广告它就是契约说谎。
    "explicit `now`",
)

# J8：工具属性声明与 required 列表
RE_PROP = re.compile(r"\"([a-z_0-9]+)\":\s*(?:required_)?(?:string|bool|int|double|number|array|object|enum)_prop")
RE_REQUIRED = re.compile(r"schema\(\s*\{.*?\},\s*\[([^\]]*)\]", re.S)
RE_TOOL_BLOCK_START = re.compile(r"instrumented_tool\(\s*s1\s*,\s*\"([a-z_0-9]+)\"\s*,")


def real_tools():
    return sorted(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8"))))


def moon_version():
    m = re.search(r'^\s*version\s*=\s*"([^"]+)"', MOONMOD.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else ""


def names_in(path):
    return set(RE_BACKTICK.findall(path.read_text(encoding="utf-8")))


def tool_registry():
    """server.mbt → {tool: {props, required}}：按 instrumented_tool 块边界切，避免跨块串味。"""
    txt = SERVER.read_text(encoding="utf-8")
    starts = [(m.group(1), m.start()) for m in RE_TOOL_BLOCK_START.finditer(txt)]
    reg = {}
    for i, (name, pos) in enumerate(starts):
        end = starts[i + 1][1] if i + 1 < len(starts) else len(txt)
        region = txt[pos:end]
        props = set(RE_PROP.findall(region))
        m = RE_REQUIRED.search(region)
        req = set()
        if m:
            req = {x.strip().strip('"') for x in m.group(1).split(",") if x.strip()}
        reg[name] = {"props": props, "required": req}
    return reg


def obj_span(text, brace_idx):
    """从 '{' 起做括号配平（跳过字符串内的括号），返回参数对象文本；失败返回 None。"""
    depth = 0
    in_str = False
    esc = False
    i = brace_idx
    while i < len(text):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c in "{[":
                depth += 1
            elif c in "}]":
                depth -= 1
                if depth == 0:
                    return text[brace_idx : i + 1]
        i += 1
    return None


def top_level_keys(blob):
    """取参数对象 depth-1 的键（嵌套对象/数组元素的键属子 schema，不参与判定）。"""
    keys, depth, i, n = [], 0, 0, len(blob)
    in_str = False
    esc = False
    pending = False
    buf = ""
    while i < n:
        c = blob[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
                if depth == 1 and pending:
                    keys.append(buf)
                pending = False
            elif depth == 1:
                buf += c
            i += 1
            continue
        if c == '"':
            j = i + 1
            while j < n and blob[j] != '"':
                j += 1
            k = j + 1
            while k < n and blob[k] in " \n\r\t":
                k += 1
            pending = depth == 1 and k < n and blob[k] == ":"
            in_str = True
            buf = ""
            i += 1
            continue
        if c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
        i += 1
    return keys


def j6_standard_consistency():
    """规范正文 ↔ 机器投影：id 全集 + 版本号 + 指针 + 摘要点名。"""
    problems = []
    if not PS_MBT.exists():
        return [f"J6 真源缺失：{PS_MBT.name} 不存在（判据无法自证）"]
    ps_src = PS_MBT.read_text(encoding="utf-8")
    ids = RE_PS_ID.findall(ps_src)
    vm = RE_PS_VER.search(ps_src)
    if not ids or not vm:
        return [f"FATAL J6 判据无法自证：从 project_standards.mbt 解析到 id={len(ids)} version={vm and vm.group(1)}"]
    ver = vm.group(1)
    if "canonical_doc" not in ps_src:
        problems.append("J6 机器投影未下发 canonical_doc 指针（调用方无从知道正文在哪）")
    if not CANON.exists():
        problems.append(f"J6 规范性正文缺失：{rel_posix(CANON)}（规范必须单文件成文）")
        return problems
    ctxt = CANON.read_text(encoding="utf-8")
    miss = [x for x in ids if x not in ctxt]
    if miss:
        problems.append(f"J6 规范正文缺 {len(miss)}/{len(ids)} 个规则 id：{', '.join(miss)}")
    if ver not in ctxt:
        problems.append(f"J6 规范正文版本号 != 机器投影 {ver}")
    for label, p in (("README.md", README), ("AGENTS.md", AGENTS)):
        if p.exists() and CANON.name not in p.read_text(encoding="utf-8"):
            problems.append(f"J6 {label} 未点名规范正文 {CANON.name}（真源不可达=摘要各自漂移）")
    if SKILL_DOC.exists():
        sm = re.search(r"version:\s*\"(R\d+)\"", SKILL_DOC.read_text(encoding="utf-8"))
        if sm and sm.group(1) != ver:
            problems.append(f"J6 {SKILL_DOC.name} 自述版本 {sm.group(1)} != 真源 {ver}")
    return problems


def j7_stale_wording():
    """规范性表面禁旧口径；历史陈述（memory/reports/CHANGELOG/生成投影副本）豁免。

    BUG-66：豁免名单里**没有** plugins/source/ —— 它是真源正文（生成副本 plugins/<host>/ 由
    cl7 逐字节比对真源，所以判真源就够，不必重复判副本一遍）。
    """
    surfaces = [README, AGENTS, CANON, SERVER, PS_MBT]
    surfaces += sorted(DOCS_DIR.glob("*.md"))
    surfaces += sorted(TEMPLATES_DIR.glob("*.md"))
    surfaces += sorted(PLUGIN_SRC.rglob("*.md"))
    problems = []
    for p in surfaces:
        if not p.exists():
            continue
        for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            for needle in STALE_NEEDLES:
                if needle in line:
                    problems.append(
                        f"J7 {rel_posix(p)}:{i} 残留旧口径「{needle}」（当前承诺必须写四态；"
                        "若是历史陈述请移入 memory/ 或 reports/）"
                    )
    return problems


def is_plugin_surface(p, plugins=None):
    """是否属于插件真源正文。BUG-70 同族防线：只看相对 plugins 根的第一段，
    用 `"source" in str(p)` / `p.parts` 会被克隆目录里任意一段叫 source 的路径骗过。
    plugins 可注入 —— 合成克隆路径必须对着**它自己的** plugins 根判。"""
    plugins = PLUGIN_SRC.parent if plugins is None else plugins
    try:
        rel = p.relative_to(plugins)
    except ValueError:
        return False
    return bool(rel.parts) and rel.parts[0] == "source"


def j8_surfaces():
    """J8 扫描面 = 模板 + 插件真源（BUG-66：只扫 templates/ 时投影正文不在射程内）。"""
    return sorted(TEMPLATES_DIR.glob("*.md")) + sorted(PLUGIN_SRC.rglob("*.md"))


def j8_template_params():
    """模板与插件真源的调用示例/参数表 vs 工具属性集：臆造参数与缺 required 都能抓到。"""
    reg = tool_registry()
    if not reg:
        return ["FATAL J8 判据无法自证：server.mbt 未解析到任何工具块"]
    problems = []
    surfaces = j8_surfaces()
    if not any(is_plugin_surface(p) for p in surfaces):
        return ["FATAL J8 扫描面不含 plugins/source/ 任何文件（枚举器坏了，不是文档坏了）"]
    for tpl in surfaces:
        text = tpl.read_text(encoding="utf-8")
        for m in re.finditer(r"\b([a-z_][a-z0-9_]{2,})\(\s*\{", text):
            name = m.group(1)
            if name not in reg:
                continue  # 工具名不存在由 check_tools_sync(BUG-37) 轨负责
            brace = text.index("{", m.start())
            blob = obj_span(text, brace)
            if not blob or len(blob) > 3000:
                continue
            line = text[:brace].count("\n") + 1
            keys = top_level_keys(blob)
            unknown = sorted({k for k in keys if k not in reg[name]["props"]})
            if unknown:
                problems.append(
                    f"J8 {rel_posix(tpl)}:{line} {name}(...) 用了未声明参数 {unknown}"
                    f"（_instrument 只校验 required，未知键静默丢弃=写了等于没验）"
                )
            missing = sorted(k for k in reg[name]["required"] if k not in keys)
            if missing:
                problems.append(f"J8 {rel_posix(tpl)}:{line} {name}(...) 缺必填参数 {missing}")
        for line_no, line in enumerate(text.splitlines(), 1):
            cells = [c.strip() for c in line.split("|")]
            if len(cells) < 3 or not cells[1].startswith("`"):
                continue
            tool = cells[1].strip("`")
            if tool not in reg or not reg[tool]["props"]:
                continue
            if not re.search(r"[、,]\s*`", cells[2]) and not cells[2].startswith("`"):
                continue
            for tok in re.findall(r"`([a-z_][a-z0-9_]*)`", cells[2]):
                if tok not in reg[tool]["props"]:
                    problems.append(
                        f"J8 {rel_posix(tpl)}:{line_no} 参数表里 {tool} 的 `{tok}` 未在该工具 schema 声明（契约说谎）"
                    )
    return problems


# ---- J9 工具描述的返回契约（BUG-74）----
# 不全量立判据的原因写在脸上：现在 120 个注册点里 54 个没写返回契约，
# 一上来按全量要求要么第一天就红、要么被迫写成"豁免 54 条"的白名单游戏。
# 取三条今天就能落地的：
#   ① 必查清单 = 本轮**亲自因为缺契约而误判过**的工具（实测来源，不是许愿清单）；
#   ② 棘轮 = 写了「返回」的工具数只许升不许降，要退必须显式改基线并写明理由；
#   ③ 歧义键分工 = 同一段返回契约里两个含义不同的键必须各自点名（见 RET_MUST_EXPLAIN）。
RE_TOOL_DESC = re.compile(
    r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"', re.S
)
RET_MUST_CARRY = [
    "task_plan_deep",         # 按 subtasks/tasks/created 取值 ⇒ 顶层全 miss，误判"拆解失败"
    "run_check",              # 只回退出码 ⇒ 判据红了举不出红在哪
    "bug_list",               # 返回是对象不是裸数组 ⇒ 当 list 取恒得空
    "github_queue_status",    # total=0 会被读成"无 bug 待同步"（其实是没开同步）
]
RET_FLOOR = 66  # 基线 = 2026-09-27 实测：120 个注册点里 66 个描述含「返回」
#   ③ 同族歧义：一个描述里同时出现两个含义不同的键时，必须把分工写在脸上。
#      实测来源 = BUG-83：run_check 回执顶层 ok=「已跑完并落库」、status=「通过与否」，
#      描述只解释了 status，Round 5 验证段驱动就把顶层 ok 当结论自述了 11/11。
#      只列本轮亲自踩过的工具，不做全量许愿清单（与 ① 同一取材口径）。
RET_MUST_EXPLAIN = {
    "run_check": ["已跑完并落库", "只看 status"],
}


def tool_desc_registry():
    """server.mbt → {工具名: 描述串}（重名取第一次，与 real_tools 的集合口径一致）。"""
    descs = {}
    for name, desc in RE_TOOL_DESC.findall(SERVER.read_text(encoding="utf-8")):
        descs.setdefault(name, desc)
    return descs


def return_contract_problems(descs, must_carry=RET_MUST_CARRY, floor=RET_FLOOR,
                             must_explain=RET_MUST_EXPLAIN):
    """纯判据：喂 {工具: 描述} 出违例列表。自测拿合成字典直接考它，不碰真源。"""
    if len(descs) < 100:
        return [f"J9 只解析到 {len(descs)} 个工具描述（<100 视为解析器坏了，不出绿）"]
    problems = []
    for t in must_carry:
        if t not in descs:
            problems.append(f"J9 必查工具解析不到：{t}（清单失效比缺契约更糟）")
        elif "返回" not in descs[t]:
            problems.append(
                f"J9 {t} 描述没有返回契约 —— 调用方只能猜键名，猜错是静默得空而不是报错")
    for t, needles in must_explain.items():
        d = descs.get(t)
        if d is None:
            problems.append(f"J9 歧义分工清单里的工具解析不到：{t}（清单失效比缺契约更糟）")
            continue
        for nd in needles:
            if nd not in d:
                problems.append(
                    f"J9 {t} 的返回契约未写明「{nd}」—— 同名键两种含义时调用方会把"
                    "「已落库」读成「已通过」（BUG-83 实测把信封 ok 汇总成 11/11）")
    has = sum(1 for d in descs.values() if "返回" in d)
    if has < floor:
        problems.append(
            f"J9 写了返回契约的工具数 {has} < 基线 {floor}（棘轮只许升；要降请显式改 RET_FLOOR 并写理由）")
    return problems


def j9_return_contract():
    return return_contract_problems(tool_desc_registry())


# ---- J10 判据范围自述 == 实际实现（BUG-84）----
# 守卫族段落里的"J1-Jn"是"这套文档面到底实现了几条判据"的唯一对外口径。
# 同一族已经重犯两次（CHANGELOG 里记着 J1-J5→J1-J8 那次也是人肉同步）：
# 少写 ⇒ 读者以为 J9/J10 不存在、绕着走；多写 ⇒ 读者拿不存在的判据当门禁。两个方向都要能发红。
RE_J_IMPL = re.compile(r"(?:def j|---- J)(\d+)")
RE_J_CLAIM = re.compile(r"J1-J(\d+)")  # 表面写的是 "J1-J8" 这种双 J 形态（实测三处皆然）


def implemented_j_rules(src=None):
    """本脚本自己实现了哪些 J 判据：`def jN_…` 与 `---- JN` 两类标记取并集。"""
    if src is None:
        src = Path(__file__).resolve().read_text(encoding="utf-8")
    return {int(x) for x in RE_J_IMPL.findall(src)}


def j10_claim_surfaces():
    """声明面 = 现状规范表面 + 对外发货表面（模板/插件真源）。
    BUG-66 的教训就是"发货正文里的过时口径会被放大成 4 份对外契约"，扫描面不许只挑两份。"""
    return ([AGENTS, CANON]
            + sorted(TEMPLATES_DIR.glob("*.md"))
            + sorted(PLUGIN_SRC.glob("*.md")))


def j10_range_claims(paths=None):
    """现状规范表面里对范围的声明：{文件名: [(行号, 声明的上界), …]}。
    只认**同一行里提到 check_doc_surface** 的 J1-n，避免把历史叙述当现状声明。"""
    out = {}
    for p in (paths or j10_claim_surfaces()):
        if not p.exists():
            continue
        hits = [(i + 1, int(n))
                for i, line in enumerate(p.read_text(encoding="utf-8").splitlines())
                if "check_doc_surface" in line for n in RE_J_CLAIM.findall(line)]
        if hits:
            out[rel_posix(p)] = hits
    return out


def j10_range_problems(claims, impl_max):
    """纯判据：喂声明与实现上界出违例。自测拿合成输入直接考它，不碰文件。"""
    if impl_max < 1:
        return ["J10 解析不到已实现判据（先判解析器坏，再判文档坏）"]
    if not claims:
        return ["J10 一处判据范围声明都没抓到（扫描面空转 ≠ 没有问题）"]
    problems = []
    for label, hits in claims.items():
        for ln, n in hits:
            if n < impl_max:
                problems.append(
                    f"J10 {label}:{ln} 声明 J1-J{n} < 实现最高 J{impl_max} —— 声明滞后，"
                    "读者会按不存在的口径绕过已有门禁")
            elif n > impl_max:
                problems.append(
                    f"J10 {label}:{ln} 声明 J1-J{n} > 实现最高 J{impl_max} —— 幻影判据，"
                    "读者会拿不存在的判据当保障")
    return problems


def j10_range_consistency():
    impl = implemented_j_rules()
    return j10_range_problems(j10_range_claims(), max(impl) if impl else 0)


# ---- J11 CI 门步骤 ↔ 规范面/账本 三向对表（BUG-130 裁决③ 的执行面不许被悄悄删掉）----
# 上一轮自己写进报告的缺口：「若日后有人删掉这两道门，没有常驻判据会红（只有 native 全量自己的崩会红，
# legibility 消失而无人认领）」。锚不是「文档里提没提」，而是**账本上 BUG-133 还 OPEN**——
# 门是那张单「红必须可解释」的执行面；单转 FIXED 后这一格自然失效（合法态），不许留恒红判据。
WORKFLOWS = (ROOT / ".github" / "workflows" / "ci.yml",
             ROOT / ".github" / "workflows" / "fist-ci.yml")
BUGS_MD = ROOT / "memory" / "bugs.md"
SCRIPTS_DOC = ROOT / "scripts" / "README.md"
GATE_NEEDLE = "heap gate"
SUITE_PREFIX = "Test (native"
GATE_GUARANTEE_BUG = "133"
RE_STEP_NAME = re.compile(r"^\s*- name: (.+?)\s*$", re.M)
RE_BACKTICK_ANY = re.compile(r"`([^`\n]+)`")
RE_HEAD_STATUS = re.compile(r"^## BUG-(\d+) \[[^\]]*\] \[[^\]]*\] (\w+)", re.M)


def workflow_step_names(text):
    return RE_STEP_NAME.findall(text)


def bug_status(ledger_text, num):
    for n, st in RE_HEAD_STATUS.findall(ledger_text):
        if n == num:
            return st
    return None


def doc_gate_claims(doc_texts):
    """规范面里用反引号点名门步骤的**逐字串**（不放宽成前缀——前缀会把改名漂移送进盲区）。"""
    return [(label, m.group(1)) for label, text in doc_texts.items()
            for m in RE_BACKTICK_ANY.finditer(text) if GATE_NEEDLE in m.group(1)]


def j11_gate_problems(wf_steps, gate_status, claims):
    """纯判据核心：喂 workflow 步名序列 / BUG-133 抬头状态 / 规范面点名的门步名 ⇒ 出违例。

    三面各自能红：门被删（账还 OPEN）、门被挪到全量之后、规范面点名的步名与 CI 里的不一致、
    两条臂的步名互不相同、账本读不到那条单（先判尺子）、解析不到任何 `- name:`（解析器饿死）。
    """
    if gate_status is None:
        return [f"FATAL J11 账本里读不到 BUG-{GATE_GUARANTEE_BUG} 抬头（先判尺子坏，再判被测面）"]
    if not wf_steps:
        return [f"FATAL J11 一个 workflow 都没读到（应有 {len(WORKFLOWS)} 份）——扫描面空转"]
    actual, problems = {}, []
    for label, names in wf_steps.items():
        if not names:
            problems.append(f"J11 {label}: 解析不到任何 `- name:` 步骤（先判解析器饿死）")
            continue
        gates = [i for i, n in enumerate(names) if GATE_NEEDLE in n]
        suites = [i for i, n in enumerate(names) if n.startswith(SUITE_PREFIX)]
        if not suites:
            problems.append(f"J11 {label}: 没有以 `{SUITE_PREFIX}` 开头的步骤 ⇒ 扫描口径坏了，本格不作数")
            continue
        if not gates:
            if gate_status == "OPEN":
                problems.append(
                    f"J11 {label}: BUG-{GATE_GUARANTEE_BUG} 仍 OPEN，native 门步骤却被删了 ⇒ 回到"
                    "「会红且没人解释」那副老样子（裁决③ 的执行面消失）")
            continue
        if len(gates) > 1:
            problems.append(f"J11 {label}: 门步骤命中 {len(gates)} 次（期望 1；重复挂门让人分不清哪一步是门）")
        if gate_status == "OPEN" and gates[0] > min(suites):
            problems.append(
                f"J11 {label}: 门在第 {gates[0] + 1} 步、全量测试在第 {min(suites) + 1} 步 ⇒ 门挂到了它要拦的那一步**之后**，等于没挂")
        for g in gates:
            actual.setdefault(names[g], []).append(label)
    if gate_status == "OPEN":
        if len(actual) > 1:
            problems.append(f"J11 两条臂的门步骤名不一致：{sorted(actual)} ⇒ 规范面只能点名一个，另一个是漂移")
        elif actual and not (set(actual) & {c for _, c in claims}):
            problems.append(
                f"J11 规范面没有一处逐字点名 CI 里的门步骤（实际名={sorted(actual)}）⇒ 「文档说的门」与「CI 里的门」无从对表")
    for label, c in claims:
        if c not in actual:
            problems.append(f"J11 {label} 逐字点名的门步骤「{c}」在 workflow 里不存在（改名或摘门都会让这句主张悬空）")
    return problems


def j11_ci_gate_steps(wf_texts=None, ledger_text=None, doc_texts=None):
    if wf_texts is None:
        wf_texts = {p.name: p.read_text(encoding="utf-8") for p in WORKFLOWS if p.exists()}
    if ledger_text is None:
        ledger_text = BUGS_MD.read_text(encoding="utf-8")
    if doc_texts is None:
        doc_texts = {rel_posix(p): p.read_text(encoding="utf-8")
                     for p in (README, AGENTS, CANON, SCRIPTS_DOC) if p.exists()}
    return j11_gate_problems(
        {label: workflow_step_names(t) for label, t in wf_texts.items()},
        bug_status(ledger_text, GATE_GUARANTEE_BUG),
        doc_gate_claims(doc_texts))


# ---- J12 CI 的 `if:` 守卫里不许钉分支名（BUG-132：恒假条件的门比没有门更坏）----
# 本仓实测过的形状：`if: github.event_name == 'push' && github.ref == 'refs/heads/main'`，
# 而默认分支是 master、该 workflow 又没有 `schedule:` ⇒ 这道作业**永不可能运行**，
# 每次读数里它却长得像一个「未触发所以正常」的绿灯位——下一个人（或下一个 agent）会读成"定时轨还没到点"。
# 口径刻意不去比对"哪个才是默认分支"（那要读 git 或调 API，两台机器取面不同、CI 上还不一定有 origin/HEAD）：
# 钉在 `if:` 里的分支名本身就是成因，与它当前叫什么无关。分支过滤交回 `on.push.branches`
# ——那里写错最坏是少跑一次，不会伪装成一道门。
WORKFLOW_DIR = ROOT / ".github" / "workflows"
RE_IF_LINE = re.compile(r"^\s*(?:-\s*)?if:\s*(.*)$")
RE_REF_HEADS = re.compile(r"refs/heads/[A-Za-z0-9._/-]+")


def j12_code_face(text):
    """逐行剔掉注释（整行 `#` 与行尾 ` #…`），只留代码面。
    不剔就会被自家注释喂回针——本仓删掉 nightly 后留的墓碑注释里正当引用着旧条件（R9 的旧坑同型）。"""
    out = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            out.append("")
            continue
        cut = re.split(r"\s#", line, maxsplit=1)
        out.append(cut[0])
    return out


def j12_workflow_texts(paths=None):
    """扫描面从目录派生，不手写文件名清单（手写清单必然落后于新增 workflow，J4/BUG-68 同族教训）。"""
    files = sorted(paths or list(WORKFLOW_DIR.glob("*.yml")) + list(WORKFLOW_DIR.glob("*.yaml")))
    return {p.name: p.read_text(encoding="utf-8", errors="replace") for p in files}


def j12_if_ref_guard_problems(wf_texts):
    if not wf_texts:
        return ["FATAL J12 一个 workflow 都没读到（扫描面空转 ≠ 没有问题）"]
    problems = []
    for label, text in wf_texts.items():
        for i, line in enumerate(j12_code_face(text), 1):
            m = RE_IF_LINE.match(line)
            if not m:
                continue
            hit = RE_REF_HEADS.findall(m.group(1))
            if hit:
                problems.append(
                    f"J12 {label}:{i} 在 if: 守卫里钉了分支引用 {sorted(set(hit))} ⇒ 分支名一变这道门就恒假，"
                    "而它在读数里长得像「未触发所以正常」（BUG-132 的形状）；分支过滤交回 on.push.branches，"
                    "if: 只留事件条件"
                )
    return problems


def j12_ci_if_ref_guards():
    return j12_if_ref_guard_problems(j12_workflow_texts())


# ---- J13 CHANGELOG 的发布状态短语 ↔ BACKLOG 的 release-fact 读数（BUG-135：短语落后于事实）----
# 为什么单立一支：CHANGELOG 在 J3/J4 的 HISTORICAL 豁免面里（历史不许改写），J7 又只管规范性表面的旧口径
# ⇒「历史文件里的**现在时**状态短语」是个真空。违例形状：标题写着「GitHub Release 未发布」，
#   而权威面记着同一版本号的 published 时刻**早于**标题的盖章戳——那句话从落盘起就是假的。
# 反向的那一半同样重要：标题戳早于 published 时它是真话（本仓 CHANGELOG 里就有一处，属于历史准确），
#   豁免历史 ≠ 连「戳晚于事实」那一档也放过，判据只抓后者。
CHANGELOG_MD = ROOT / "CHANGELOG.md"
RELEASE_UNPUBLISHED_NEEDLE = "GitHub Release 未发布"
RE_FACT_VERSION = re.compile(r"release-fact:\s*v?(\d+\.\d+\.\d+)")
RE_FACT_PUBLISHED = re.compile(r"github-published=(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)")
RE_FACT_ASSET = re.compile(r"asset=fist-mbt-js-v(\d+\.\d+\.\d+)\.zip")
RE_HEAD_LINE = re.compile(r"^## v([^\n]*)$", re.M)
RE_HEAD_VER = re.compile(r"^## v(\d+\.\d+\.\d+)")
RE_HEAD_STAMP = re.compile(r"盖章 (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)")


def j13_release_facts(backlog_text):
    """从 BACKLOG 的 `release-fact:` 标记反解 {版本: published 时刻}，顺带查标记自身是否自洽。"""
    facts, problems = {}, []
    for raw in backlog_text.splitlines():
        if "release-fact:" not in raw:
            continue
        line = raw.strip()
        mv, mp = RE_FACT_VERSION.search(line), RE_FACT_PUBLISHED.search(line)
        if not (mv and mp):
            problems.append(f"J13 release-fact 标记残缺（版本或 github-published 解析不到）：{line[:120]}")
            continue
        ver, pub = mv.group(1), mp.group(1)
        ma = RE_FACT_ASSET.search(line)
        if ma and ma.group(1) != ver:
            problems.append(f"J13 标记自相矛盾：版本 {ver} 的资产名写的是 v{ma.group(1)}")
        if ver in facts:
            problems.append(f"J13 版本 {ver} 有两条 release-fact 标记（{facts[ver]} / {pub}）"
                            "⇒ 权威面自相矛盾，判据不猜哪条正")
            continue
        facts[ver] = pub
    return facts, problems


def j13_heading_claims(changelog_text):
    """返回 (标题行总数, [(版本号, 盖章戳, 片段)])——只取含「未发布」短语的那几行标题。"""
    claims = []
    heads = RE_HEAD_LINE.findall(changelog_text)
    for h in heads:
        if RELEASE_UNPUBLISHED_NEEDLE not in h:
            continue
        full = "## v" + h
        mv, ms = RE_HEAD_VER.search(full), RE_HEAD_STAMP.search(h)
        claims.append((mv.group(1) if mv else None, ms.group(1) if ms else None, full[:90]))
    return len(heads), claims


def j13_release_status_problems(backlog_text, changelog_text):
    """纯判定：喂合成两面即可考这把尺；真实现状面走 j13_release_status_consistency()。"""
    facts, problems = j13_release_facts(backlog_text)
    if not facts:
        problems.append("FATAL J13 BACKLOG 里读不到任何合法 release-fact 标记"
                        "（权威面空转 ≠ 没有落后于事实的自述；把标记删空来消解违例也不是修法）")
        return problems
    n_heads, claims = j13_heading_claims(changelog_text)
    if n_heads == 0:
        problems.append("FATAL J13 CHANGELOG 里一行 `## v` 标题都没解析到（扫描面饿死，不拿没抓到当没问题）")
        return problems
    for ver, stamp, snippet in claims:
        if not ver or not stamp:
            problems.append(f"J13 标题含「{RELEASE_UNPUBLISHED_NEEDLE}」却读不到版本号或「盖章 <ISO>」"
                            f"⇒ 无法与权威面对表：{snippet}")
            continue
        if ver not in facts:
            continue  # 权威面没记这一版 ⇒ 这一格不作数（不弃权：上面两支 FATAL 已保证两面都非空）
        if stamp > facts[ver]:
            problems.append(
                f"J13 标题自述 v{ver}「{RELEASE_UNPUBLISHED_NEEDLE}」，但标题盖章戳 {stamp} "
                f"晚于权威面 published {facts[ver]} ⇒ 那句话从落盘起就是假的（BUG-135 的形状）；"
                "改标题的状态短语，或按读数补 BACKLOG 的 release-fact 标记")
    return problems


def j13_release_status_consistency():
    backlog = BACKLOG.read_text(encoding="utf-8", errors="replace") if BACKLOG.is_file() else ""
    ch = CHANGELOG_MD.read_text(encoding="utf-8", errors="replace") if CHANGELOG_MD.is_file() else ""
    return j13_release_status_problems(backlog, ch)


# ---- J14 工具计数自述 ↔ 真源（BUG-136 附带抓到的：`fist://map` 资源正文写着「MCP 层 102 工具」，
# 而真源注册表是 129——这一面此前没人比过：check_tools_sync 第 3 条只管 README/AGENTS/deliverable/
# scoring_rubric，J3 只管 README 的分组和，资源正文与 CLI 帮助文案两头都空着）。
# 为什么这类特别坏：它长得像事实、读起来像介绍，而且**在发货面上**（资源随插件态分发）。
J14_FACES = (
    ("src/server/server.mbt", "MCP 资源面"),
    ("cmd/cli/help_topics.mbt", "CLI 帮助面"),
    ("ARCHITECTURE.md", "架构自述面"),
)
J14_HELP = "cmd/cli/help_topics.mbt"
RE_J14_CLAIM = re.compile(
    r"(\d{2,4})\s*(?:个\s*)?(?:MCP\s*)?工具|(\d{2,4})\s*MCP\s*tools"
)
RE_J14_GROUP = re.compile(r'^\s*"\s*\[[A-Za-z][A-Za-z0-9 -]*\s+(\d+)\]', re.M)
RE_J14_GROUPN = re.compile(r"\((\d+) groups\)")


def j14_count_problems(texts, n):
    """纯判定：{相对路径: 正文} → 违例清单。自述数字 != 真源计数即红；
    三面一处都解析不到 ⇒ FATAL 自拒（扫描面饿死被读成"没有问题"是这类尺子最常见的死法）。"""
    problems = []
    hits = 0
    for rel, label in J14_FACES:
        text = texts.get(rel, "")
        for m in RE_J14_CLAIM.finditer(text):
            got = m.group(1) or m.group(2)
            hits += 1
            if int(got) != n:
                line = text[: m.start()].count("\n") + 1
                problems.append(
                    f"J14 {label}（{rel}:{line}）自述「{m.group(0)}」，真源注册表是 {n} 个"
                    " ⇒ 计数搬家时这一面没人跟着改")
    if hits == 0:
        faces = ", ".join(r for r, _ in J14_FACES)
        problems.append(f"FATAL J14 三面（{faces}）一处工具计数自述都没解析到 ⇒ 判据饿死，不报绿")
    return problems


def j14_help_group_problems(help_text, n):
    """CLI 帮助把工具摊成分组行：分组数字之和 == 真源、且标题里那句「(N groups)」== 实际组数。
    与 J3 对 README 的同口径——标题数字对了不代表正文跟上（BUG-22 的原型）。"""
    nums = [int(x) for x in RE_J14_GROUP.findall(help_text)]
    if len(nums) < 2:
        return [f"FATAL J14 {J14_HELP} 只解析到 {len(nums)} 个分组数字 ⇒ 分组面读不到，和数无意义"]
    problems = []
    s = sum(nums)
    if s != n:
        problems.append(
            f"J14 {J14_HELP} 分组数字之和={s}（{len(nums)} 组），与真源 {n} 不符"
            " ⇒ 添了工具只改标题行，正文分组表没跟上")
    declared = [int(x) for x in RE_J14_GROUPN.findall(help_text)]
    for d in declared:
        if d != len(nums):
            problems.append(
                f"J14 {J14_HELP} 标题自述「({d} groups)」，实际解析到 {len(nums)} 组 ⇒ 分组数也是主张")
    if not declared:
        problems.append(f"FATAL J14 {J14_HELP} 里没有「(N groups)」这句自述 ⇒ 对照面消失，判据读不到东西")
    return problems


def j14_tool_count_claims():
    texts = {}
    for rel, _label in J14_FACES:
        p = ROOT / rel
        texts[rel] = p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""
    n = len(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8", errors="replace"))))
    problems = j14_count_problems(texts, n)
    problems += j14_help_group_problems(texts.get(J14_HELP, ""), n)
    return problems


# ---- J4 子判据：注册表发布版本只能有一处自述（BUG-30 建议①，编号不扩，免得 J10 范围自述说谎）----
# 与 J4 主判据的分工要说清：J4 管「文档自述的本项目版本 == moon.mod」，那说的是**代码版本**；
# 「注册表上到底发布到哪个版本」是另一件事，本机没有复核通道（WebFetch 被策略拦过，实测不可达）。
# BUG-30 的原始形状正是两份现状面各写一个发布版本（README 的 MochaCakes 行 vs BACKLOG 的 done 行），
# 都无验证链接 ⇒ 读者无法判新旧。既然证不了，就把"只允许一处权威自述"做成硬门：
# 第二处出现即红；权威面（BACKLOG 的发布条目）被删空同样即红——删正身来消解违例不是修法。
RE_PUB_LINE = re.compile(r"发布|published|mochacakes|mooncakes", re.I)
RE_VER = re.compile(r"(?<![\d.])v?([0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2})(?![\d.])")
PUB_AUTHORITY = "BACKLOG.md"


def pub_surfaces():
    """扫描面从 git 跟踪清单派生（BUG-68 口径：手写元组必然落后于新增文档）。
    历史面豁免：memory/ reports/ CHANGELOG/ 日期名文件是当时的记录，不是现状断言。
    git 不可用或枚举过小时拒绝出绿灯。"""
    try:
        r = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z", "--", "*.md"],
            capture_output=True, text=True, encoding="utf-8", errors="replace")
    except Exception as e:
        raise SystemExit(f"FATAL J4 无法调用 git ls-files（{e}）—— 拒绝在无枚举时出绿灯")
    if r.returncode != 0:
        raise SystemExit(
            f"FATAL J4 git ls-files 退出码 {r.returncode}：{r.stderr.strip()[:200]}")
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    keep = [
        f for f in files
        if f != "CHANGELOG.md"
        and not f.startswith(("memory/", "reports/", "docs/superpowers/plans/"))
        and not re.match(r"^\d{4}-\d{2}-\d{2}", Path(f).name)
    ]
    if len(keep) < 10:
        raise SystemExit(f"FATAL J4 只枚举到 {len(keep)} 份现状 .md（<10 视为枚举失效）")
    return keep


def publication_claims(paths=None):
    """现状面里对『注册表发布版本』的自述：返回 [(相对路径, 行号, 版本号)]。"""
    out = []
    for rel in (paths if paths is not None else pub_surfaces()):
        p = ROOT / rel
        if not p.is_file():
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        for ln, line in enumerate(text.splitlines(), 1):
            if not RE_PUB_LINE.search(line):
                continue
            for m in RE_VER.finditer(line):
                out.append((rel.replace("\\", "/"), ln, m.group(1)))
    return out


def publication_problems(claims, authority=PUB_AUTHORITY, swept=None):
    """纯判定：权威面恰好有自述，别的现状面一处都不许有。喂合成输入即可考它。
    swept 是**扫描面**（不是命中面）：扫描面为空 ⇒ 枚举器饿死，判据不许顺势报绿。"""
    problems = []
    if swept is not None and not swept:
        return [f"J4 扫描面为空 —— 没抓到声明不等于没有问题，先判枚举器坏"]
    if not [c for c in claims if c[0] == authority]:
        problems.append(
            f"J4 {authority} 里没有发布版本自述 —— 把唯一权威删掉来消解违例不是修法")
    for rel, ln, v in [c for c in claims if c[0] != authority]:
        problems.append(
            f"J4 {rel}:{ln} 另写一处发布版本 {v}（本机无注册表复核通道，"
            f"第二处自述只会与 {authority} 打架）—— 请删掉版本号并指向 {authority} 的发布条目")
    return problems


def j_publication_consistency():
    swept = pub_surfaces()
    return publication_problems(publication_claims(swept), swept=swept)


def j_selftest():
    """负向自检：每条新判据都必须能在合成违例上发红，否则它只是装饰。"""
    fails = []
    fake = '\n'.join(f"- {x}" for x in ["r1-doc-as-impl", "f1-use-fist-self"])
    if not miss_ids_of(fake, ["r1-doc-as-impl", "r2-single-source", "cl7-plugin-forms-sync"]):
        fails.append("J6 对『正文缺 id』不敏感 → 判据是装饰")
    if not stale_hits("本项目遵守一源三态与三形态 checklist"):
        fails.append("J7 对『旧口径句子』不敏感 → 判据是装饰")
    # BUG-66：广告一个已被删除的调用面参数，必须是 J7 能发红的形状（禁词表里就该有它）
    if not stale_hits("All tool calls take an explicit `now` (ISO8601)"):
        fails.append("J7 抓不到『explicit `now`』这类幻影参数文案 → plugins/source 的 BUG-66 会重犯")
    # BUG-66/70：J8 的枚举器必须真的覆盖插件真源，而且不能被"路径里有一段叫 source"骗过
    if not any(is_plugin_surface(p) for p in j8_surfaces()):
        fails.append("J8 扫描面不含 plugins/source/ → 投影正文无人判")
    clone_plugins = Path("C:/source/proj/plugins")
    probe_in = clone_plugins / "source" / "SKILL.md"
    probe_out = clone_plugins / "atomcode" / "skills" / "fist-mbt" / "SKILL.md"
    if not is_plugin_surface(probe_in, clone_plugins):
        fails.append("is_plugin_surface 没把克隆在 …/source/… 下的真源认出来 → 扫描面空转")
    if is_plugin_surface(probe_out, clone_plugins):
        fails.append("is_plugin_surface 把生成副本也判成真源 → 会重复计一遍假违例")
    reg = tool_registry()
    # BUG-74/83：J9 的对照——缺契约必红、跌破棘轮必红、干净输入不得误红，
    # ③ 歧义键分工另含"抹词必红 + 写清不误红 + 清单落空必红"三条。
    # 合成违例文案里**不许出现 needle 本身**（"只写参数不写返回"就含着「返回」二字，
    # 那样判据永远不红，测的是我的造句而不是判据）。
    synth = {f"t{i}": ("returns {a, b}" if i else "only documents parameters")
             for i in range(120)}
    if not return_contract_problems(synth, must_carry=["t0"], must_explain={}):
        fails.append("J9 对『必查工具缺返回契约』不敏感 → BUG-74 那类误判抓不到")
    if not return_contract_problems({f"t{i}": "returns {a}" for i in range(110)},
                                    floor=120, must_explain={}):
        fails.append("J9 棘轮不承重（110 条 < 基线 120 却不红）")
    if return_contract_problems({f"t{i}": "返回 {a}" for i in range(120)},
                                must_carry=[], floor=1, must_explain={}):
        fails.append("J9 对干净输入误报（恒红判据不可信）")
    # 判据认的是中文「返回」，不是英文 returns：这条反向对照防"把判据改成大小写不敏感后恒过"
    if not return_contract_problems({f"t{i}": "returns {a}" for i in range(120)},
                                    must_carry=["t0"], floor=1, must_explain={}):
        fails.append("J9 把英文 returns 当成了契约（needle 口径被放宽）")
    amb_bad = {f"t{i}": "返回 {a}" for i in range(119)}
    amb_bad["run_check"] = "返回 {ok, status}：ok=true 表示判据通过，status 是同义字段"
    if not any("run_check" in p for p in return_contract_problems(amb_bad, must_carry=[], floor=1)):
        fails.append("J9 对『两个 ok 不分工』不敏感 → BUG-83 那类误判还会重犯")
    amb_ok = dict(amb_bad)
    amb_ok["run_check"] = ("返回 {ok, status}：顶层 ok 只表示已跑完并落库，"
                           "判据通过与否只看 status")
    if return_contract_problems(amb_ok, must_carry=[], floor=1):
        fails.append("J9 对已写清分工的描述误红")
    if not any("解析不到" in p for p in return_contract_problems(
            {f"t{i}": "返回 {a}" for i in range(120)}, must_carry=[], floor=1)):
        fails.append("J9 分工清单里的工具从注册表消失时不红 → 清单失效比缺契约更糟")
    j9_real = j9_return_contract()
    if j9_real:
        fails.append("J9 在真实真源上就红了（先判解析器坏，再判产品坏）：" + j9_real[0])
    if len(tool_desc_registry()) < 100:
        fails.append("J9 解析器饿死：tool_desc_registry 读不到 100 个描述")
    # BUG-84：J10 四个方向都要能发红，且"两面一致"这条不误红（防恒红）。
    impl_now = max(implemented_j_rules())
    if impl_now < 9:
        fails.append(f"J10 实现侧解析只到 J{impl_now} —— 枚举器饿死，范围比对没有意义")
    if not any("声明滞后" in p for p in j10_range_problems({"AGENTS.md": [(299, 8)]}, 9)):
        fails.append("J10 抓不到『声明滞后』（本轮真实违例形状：文档写 J1-J8、真源已有 J9）")
    if not any("幻影判据" in p for p in j10_range_problems({"AGENTS.md": [(299, 99)]}, 9)):
        fails.append("J10 抓不到『幻影判据』（吹比实现更大的范围）")
    if j10_range_problems({"AGENTS.md": [(299, 9)], "AI-DEVELOPMENT-STANDARD.md": [(15, 9)]}, 9):
        fails.append("J10 对两面一致的输入误红")
    if not j10_range_problems({}, 9):
        fails.append("J10 扫描面空转时不红（没抓到声明 ≠ 没有问题）")
    if not j10_range_problems({"AGENTS.md": [(299, 1)]}, 0):
        fails.append("J10 实现侧解析为空时不红（先判解析器坏）")
    j10_real = j10_range_consistency()
    if j10_real:
        fails.append("J10 在真实现状面上就红了：" + j10_real[0])
    if not j10_range_claims():
        fails.append("J10 现状规范表面一处范围声明都没有 —— 扫描面对象选错了")
    # J11（BUG-130 裁决③ 的门）：合成违例五支 + 合法态一支 + 现状不红一支。
    # 少任何一支，这格就退化成「只在门被删且文档也跟着删时才红」的半个判据。
    gname = "Native heap gate (BUG-133 探针当门)"
    wf_ok = {"ci.yml": ["Checkout", gname, "Test (native)"],
             "fist-ci.yml": ["Checkout", gname, "Test (native, j=1)"]}
    clm_ok = [("README.md", gname), ("AGENTS.md", gname)]
    if not any("门步骤却被删了" in p for p in j11_gate_problems(
            {"ci.yml": ["Checkout", "Test (native)"], "fist-ci.yml": wf_ok["fist-ci.yml"]},
            "OPEN", clm_ok)):
        fails.append("J11 抓不到『OPEN 时门被删』→ 裁决③ 的执行面消失没人知道")
    if not any("之后" in p for p in j11_gate_problems(
            {"ci.yml": ["Checkout", "Test (native)", gname], "fist-ci.yml": wf_ok["fist-ci.yml"]},
            "OPEN", clm_ok)):
        fails.append("J11 抓不到『门挪到全量测试之后』（顺序倒置等于没挂）")
    if not any("不存在" in p for p in j11_gate_problems(
            wf_ok, "OPEN", [("scripts/README.md", "Native heap gate")])):
        fails.append("J11 抓不到『规范面步名与 CI 逐字不等』（前缀式点名会放过改名漂移）")
    if not any("不一致" in p for p in j11_gate_problems(
            {"ci.yml": ["Checkout", gname, "Test (native)"],
             "fist-ci.yml": ["Checkout", "Native heap gate v2", "Test (native, j=1)"]},
            "OPEN", clm_ok)):
        fails.append("J11 抓不到『两臂门步骤名互异』（文档只能点名一个，另一个悬空）")
    if j11_gate_problems({"ci.yml": ["Checkout", "Test (native)"],
                          "fist-ci.yml": ["Checkout", "Test (native, j=1)"]}, "FIXED", []):
        fails.append("J11 在合法态（BUG-133 已 FIXED、门已撤、文档不再点名）误红 —— 恒红判据不可信")
    if not any("读不到 BUG-" in p for p in j11_gate_problems(wf_ok, None, clm_ok)):
        fails.append("J11 账本读不到那条单时不红（先判尺子坏，再判被测面）")
    if not j11_gate_problems({"ci.yml": [], "fist-ci.yml": []}, "OPEN", []):
        fails.append("J11 解析不到任何 `- name:` 时不红（解析器饿死）")
    j11_real = j11_ci_gate_steps()
    if j11_real:
        fails.append("J11 在真实现状面上就红了（先判尺子，再判被测）：" + j11_real[0])
    # 标签分隔符也是判据契约的一部分：账本/报告要**逐字**引用违例文案，
    # 而 Windows 上 `str(relative_to(...))` 打印 `scripts\README.md`、CI 上打印 `scripts/README.md`
    # ⇒ 同一支尺两种文案，对表只能靠猜（这条在 POSIX 上恒真，所以它考的是实现而不是现状面）。
    if rel_posix(SCRIPTS_DOC) != "scripts/README.md":
        fails.append(f"J11 扫描面标签随平台变（rel_posix 回 {rel_posix(SCRIPTS_DOC)}）⇒ 逐字引用在两台上对不上")
    # J12（BUG-132 恒假门）：五支缺一不可——钉分支必红、只在注释里不红、行尾注释不喂针、
    # tag 守卫这类合法形态不误红、空扫描必自拒；再加现状不红 + 枚举器没饿死。
    if not any("钉了分支引用" in p for p in j12_if_ref_guard_problems(
            {"x.yml": "jobs:\n  n:\n    if: github.event_name == 'push' && github.ref == 'refs/heads/main'\n"})):
        fails.append("J12 抓不到『if: 里钉 refs/heads/<分支>』→ BUG-132 那类恒假门会重犯")
    if j12_if_ref_guard_problems(
            {"x.yml": "# 旧条件写法是 github.ref == 'refs/heads/main'\njobs:\n  n:\n    if: github.event_name == 'pull_request'\n"}):
        fails.append("J12 被自家注释喂回针（剔注释之前就算守卫）→ 墓碑注释会把判据变成恒红")
    if j12_if_ref_guard_problems(
            {"x.yml": "jobs:\n  n:\n    - name: x  # 见 refs/heads/main 的旧事\n      if: startsWith(github.ref, 'refs/tags/')\n"}):
        fails.append("J12 对 tag 触发或行尾注释里的 refs/ 误红（恒红判据不可信）")
    if not any("一个 workflow 都没读到" in p for p in j12_if_ref_guard_problems({})):
        fails.append("J12 扫描面空转时不红（没抓到 ≠ 没有问题）")
    if len(j12_workflow_texts()) < 4:
        fails.append(f"J12 枚举器饿死：只读到 {len(j12_workflow_texts())} 份 workflow")
    j12_real = j12_ci_if_ref_guards()
    if j12_real:
        fails.append("J12 在真实现状面上就红了（先判尺子，再判 CI）：" + j12_real[0])
    # J13（BUG-135 状态短语落后于权威读数）：六支缺一不可——落后必红、戳早不误红、
    # 权威面没记这版不作数、权威面空必自拒、标题枚举空必自拒、标记自相矛盾必红；再加现状不红。
    J13_FACT = ("<!-- release-fact: v9.9.9 github-published=2026-09-30T00:03:17Z "
                "asset=fist-mbt-js-v9.9.9.zip bytes=1 -->")
    J13_HEAD_LATE = "## v9.9.9 (mooncakes 已发布 / GitHub Release 未发布) - 合成节（盖章 2026-10-01T03:20:18Z）"
    J13_HEAD_EARLY = "## v9.9.9 (mooncakes 已发布 / GitHub Release 未发布) - 合成节（盖章 2026-09-29T10:44:53Z）"
    J13_HEAD_OTHER = "## v8.8.8 (mooncakes 已发布 / GitHub Release 未发布) - 合成节（盖章 2026-10-01T03:20:18Z）"
    if not any("晚于权威面 published" in p for p in j13_release_status_problems(J13_FACT, J13_HEAD_LATE)):
        fails.append("J13 抓不到『标题状态短语晚于权威 published』→ BUG-135 那类假主张会重犯")
    if j13_release_status_problems(J13_FACT, J13_HEAD_EARLY):
        fails.append("J13 对『标题戳早于 published（当时为真）』误红 → 历史陈述被判成违例，恒红判据不可信")
    if j13_release_status_problems(J13_FACT, J13_HEAD_OTHER):
        fails.append("J13 对『权威面没记这一版』误红 → 没有权威读数时该格不作数，不该拿它当违例")
    if not any("release-fact 标记" in p for p in j13_release_status_problems("", J13_HEAD_LATE)):
        fails.append("J13 权威面为空时不自拒 → 删掉 BACKLOG 的标记就能骗过判据")
    if not any("扫描面饿死" in p for p in j13_release_status_problems(J13_FACT, "# 没有标题的一行")):
        fails.append("J13 标题枚举为空时不自拒 → 扫描面饿死被读成没有问题")
    J13_DUP = J13_FACT + "\n" + J13_FACT.replace("2026-09-30", "2026-10-05")
    if not any("两条 release-fact 标记" in p for p in j13_release_status_problems(J13_DUP, J13_HEAD_LATE)):
        fails.append("J13 对权威面自相矛盾（同版本两条标记）不敏感 → 对表只能靠猜")
    J13_BADASSET = J13_FACT.replace("v9.9.9.zip", "v0.0.0.zip")
    if not any("资产名写的是" in p for p in j13_release_status_problems(J13_BADASSET, "")):
        fails.append("J13 对『标记里版本与资产名版本打架』不敏感 → 标记本身错了没人管")
    j13_real = j13_release_status_consistency()
    if j13_real:
        fails.append("J13 在真实现状面上就红了（先判尺子，再判被测）：" + j13_real[0])
    # J14：计数自述与分组和两面都要有"错必红 + 对不误红 + 读不到必自拒"三件套
    J14_TXT_OK = 'let x = "MCP 层 129 工具"\n'
    if j14_count_problems({"src/server/server.mbt": J14_TXT_OK}, 129):
        fails.append("J14 对正确的计数自述误红 → 现状面会被自己的尺子打回")
    if not any("真源注册表是" in p for p in j14_count_problems(
            {"src/server/server.mbt": 'let x = "MCP 层 102 工具"'}, 129)):
        fails.append("J14 对『资源面数字落后于真源』不敏感 → BUG-136 那类漂移会重犯")
    if not any("判据饿死" in p for p in j14_count_problems(
            {"src/server/server.mbt": "没有计数", "cmd/cli/help_topics.mbt": "", "ARCHITECTURE.md": ""}, 129)):
        fails.append("J14 三面全空时不自拒 → 扫描面失效被读成没有问题")
    J14_HELP_OK = '  "  [Lifecycle 14] a\\n" +\n  "  [Query 2] b\\n"'
    if j14_help_group_problems(J14_HELP_OK + '  "  === 16 MCP tools (2 groups) ==="', 16):
        fails.append("J14 对正确的分组和/分组数误红")
    if not any("分组数字之和" in p for p in j14_help_group_problems(
            J14_HELP_OK + '  "  === 17 MCP tools (2 groups) ==="', 17)):
        fails.append("J14 对『分组和落后于真源』不敏感 → BUG-22 的同型漂移照不到")
    if not any("标题自述「(3 groups)」" in p for p in j14_help_group_problems(
            J14_HELP_OK + '  "  === 16 MCP tools (3 groups) ==="', 16)):
        fails.append("J14 对『标题组数与实际不符』不敏感")
    if not any("只解析到" in p for p in j14_help_group_problems('"no groups here"', 129)):
        fails.append("J14 分组面读不到时不自拒 → 和数门成了空门")
    j14_real = j14_tool_count_claims()
    if j14_real:
        fails.append("J14 在真实现状面上就红了（先判尺子，再判被测）：" + j14_real[0])
    # J4 子判据（BUG-30）：注册表发布版本只能有一处权威自述。四条对照缺一不可——
    # 两处打架必红、权威被删空必红、扫描面空转必红、单处自述不许误红。
    if not any("另写一处" in p for p in publication_problems(
            [(PUB_AUTHORITY, 15, "0.2.4"), ("README.md", 190, "0.2.5")],
            swept=["README.md", PUB_AUTHORITY])):
        fails.append("J4 对『两处发布版本自述』不敏感 → BUG-30 的原始形状会重犯")
    if not any("没有发布版本自述" in p for p in publication_problems(
            [("README.md", 190, "0.2.5")], swept=["README.md", PUB_AUTHORITY])):
        fails.append("J4 在权威面缺声明时不红 → 删掉 BACKLOG 那行就能骗过判据")
    if publication_problems([(PUB_AUTHORITY, 15, "0.2.4")],
                            swept=[PUB_AUTHORITY, "README.md"]):
        fails.append("J4 对唯一权威的干净现状误红（恒红判据不可信）")
    if not any("扫描面为空" in p for p in publication_problems([], swept=[])):
        fails.append("J4 扫描面空转时不红（没抓到声明 ≠ 没有问题）")
    if len(pub_surfaces()) < 10:
        fails.append("J4 枚举器饿死：现状面 .md 少于 10 份")
    j4_real = j_publication_consistency()
    if j4_real:
        fails.append("J4 在真实现状面上就红了（先判解析器坏，再判文档坏）：" + j4_real[0])
    if "output_validate" not in reg:
        fails.append("J8 解析不到 output_validate（解析器失效）")
    else:
        probe = 'output_validate({ "project_dir": ".", "check_results": [1], "artifacts": [ { "path": "x", "contains": "y" } ] })'
        blob = obj_span(probe, probe.index("{"))
        keys = top_level_keys(blob)
        if "check_results" not in [k for k in keys if k not in reg["output_validate"]["props"]]:
            fails.append("J8 对『臆造参数 check_results』不敏感")
        if "contains" in [k for k in keys if k not in reg["output_validate"]["props"]]:
            fails.append("J8 把子 schema 键 contains 误伤为臆造参数（应只看 depth-1）")
    return fails


# 自检正文的源码快照：SELFTEST OK 那行报"覆盖了哪几条判据"必须从这里反解，
# 手写这份清单就等于"声称有 J4 对照、实际正文里一条没有"（J10 管的正是这类漂移）。
J_SELFTEST_SRC = inspect.getsource(j_selftest)


def miss_ids_of(canon_text, ids):
    return [x for x in ids if x not in canon_text]


def stale_hits(text):
    return [n for n in STALE_NEEDLES if n in text]


def readme_group_sum(text):
    """README 功能全景分组标题：### X（N） / ### X（N · …）——取每行第一个括号内整数。"""
    total = 0
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("###"):
            continue
        m = re.search(r"[（(]\s*(\d+)\s*[)）]", s)
        if m:
            total += int(m.group(1))
    return total


def main(argv):
    selftest = "--selftest" in argv
    tools = real_tools()
    n = len(tools)
    problems = []

    # ---- J5 反幻影哨兵：判据自己坏的时候必须响，不能静默 PASS ----
    if n <= 100:
        print(f"FATAL: 真源只解析到 {n} 个工具（应 >100）——解析器或路径失效，本次判定不可信")
        return 2
    if selftest:
        fails = j_selftest()
        if fails:
            print("SELFTEST FAIL: 新判据抓不到合成违例（判据自己坏了）：")
            for f in fails:
                print("  - " + f)
            return 2
        # 自述范围从**自检正文**派生，不手写：写了 J4 的对照却没进正文，这里就少报一条。
        rules = sorted({int(x) for x in re.findall(r'"J(\d+) ', J_SELFTEST_SRC)}, key=int)
        print(f"SELFTEST OK: 真源解析到 {n} 个工具，"
              + "/".join(f"J{r}" for r in rules) + " 对合成违例均发红"
              "（反向对照含『干净输入不得误红』『英文不算契约』『分工写清不得误红』"
              "『两面一致不误红』『J11 合法态（单已 FIXED＋门已撤、文档不再点名）不误红』"
              "『J12 注释里的 refs/heads 与 tag 守卫不误红』，"
              "防空转含『分工清单落空必红』『空扫描必红』『解析器饿死必红』『J11 账本读不到那条单必红』"
              "『J12 一份 workflow 都没读到必自拒』『J13 标题戳早于权威 published 不误红』"
              "『J13 权威面没记这一版不作数』『J13 release-fact 标记缺失或自相矛盾必红』）")
        return 0

    agents_txt = AGENTS.read_text(encoding="utf-8")
    readme_txt = README.read_text(encoding="utf-8")
    anames, rnames = names_in(AGENTS), names_in(README)
    for guard_name, got, label in (("AGENTS", anames, "AGENTS.md"), ("README", rnames, "README.md")):
        if len(got) <= 100:
            print(f"FATAL: {label} 只解析到 {len(got)} 个反引号名——判据不可信")
            return 2

    # ---- J2 逐名覆盖（数字对了不算过，名字要在）----
    for label, got in (("AGENTS.md", anames), ("README.md", rnames)):
        miss = sorted(t for t in tools if t not in got)
        if miss:
            problems.append(f"{label} 未逐个列出 {len(miss)} 个已注册工具: " + ", ".join(miss))

    # ---- J3 README 分组数之和 == 实测 ----
    gs = readme_group_sum(readme_txt)
    if gs != n:
        problems.append(f"README 功能全景分组计数之和={gs}，与实测工具数 {n} 不符（标题数字对不代表正文跟上）")

    # ---- J4 当前自述版本一致性 ----
    mv = moon_version()
    if not mv:
        print("FATAL: 读不到 moon.mod 的 version")
        return 2
    for p in (README, AGENTS, USAGE, BACKLOG):
        if not p.exists():
            continue
        rel = p.name
        if HISTORICAL.match(rel):
            continue
        for v in RE_SELFVER.findall(p.read_text(encoding="utf-8")):
            if v != mv:
                problems.append(f"{rel} 自述版本 {v} != moon.mod {mv}（若为历史陈述请放进带日期的时间线小节）")

    problems += j_publication_consistency()
    problems += j6_standard_consistency()
    problems += j7_stale_wording()
    problems += j8_template_params()
    problems += j9_return_contract()
    problems += j10_range_consistency()
    problems += j11_ci_gate_steps()
    problems += j12_ci_if_ref_guards()
    problems += j13_release_status_consistency()
    problems += j14_tool_count_claims()

    if problems:
        print(f"FAIL 文档面不一致（真源 {n} 工具 / moon.mod {mv}）：")
        for x in problems:
            print("  - " + x)
        return 1
    print(
        f"PASS 文档面一致：{n} 工具在 AGENTS/README 逐个可查、分组和={n}、当前自述版本={mv}、"
        "J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、"
        "J9 返回契约（必查清单 + 歧义键分工 + 棘轮）未退化、J10 判据范围自述==实现、"
        "J11 CI native 门步骤↔账本/规范面 三向对表、J12 CI 的 if: 不钉分支名（恒假门）、J13 发布状态短语↔BACKLOG release-fact 对表、J14 工具计数自述与 CLI 分组和↔真源对表"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
