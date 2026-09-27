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

设计约束：不改被校验的文档、不写库、纯只读。
"""
import os
import re
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
        problems.append(f"J6 规范性正文缺失：{CANON.relative_to(ROOT)}（规范必须单文件成文）")
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
                        f"J7 {p.relative_to(ROOT)}:{i} 残留旧口径「{needle}」（当前承诺必须写四态；"
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
                    f"J8 {tpl.relative_to(ROOT)}:{line} {name}(...) 用了未声明参数 {unknown}"
                    f"（_instrument 只校验 required，未知键静默丢弃=写了等于没验）"
                )
            missing = sorted(k for k in reg[name]["required"] if k not in keys)
            if missing:
                problems.append(f"J8 {tpl.relative_to(ROOT)}:{line} {name}(...) 缺必填参数 {missing}")
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
                        f"J8 {tpl.relative_to(ROOT)}:{line_no} 参数表里 {tool} 的 `{tok}` 未在该工具 schema 声明（契约说谎）"
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
            out[str(p.relative_to(ROOT))] = hits
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
        print(f"SELFTEST OK: 真源解析到 {n} 个工具，J6/J7/J8/J9/J10 对合成违例均发红"
              "（J9 另含『干净输入不得误红』『英文不算契约』『分工写清不得误红』三条反向对照"
              "与『分工清单落空必红』一条；J10 含滞后/幻影/空扫描/解析器饿死四条 + 两面一致不误红对照）")
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

    problems += j6_standard_consistency()
    problems += j7_stale_wording()
    problems += j8_template_params()
    problems += j9_return_contract()
    problems += j10_range_consistency()

    if problems:
        print(f"FAIL 文档面不一致（真源 {n} 工具 / moon.mod {mv}）：")
        for x in problems:
            print("  - " + x)
        return 1
    print(
        f"PASS 文档面一致：{n} 工具在 AGENTS/README 逐个可查、分组和={n}、当前自述版本={mv}、"
        "J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、"
        "J9 返回契约（必查清单 + 歧义键分工 + 棘轮）未退化、J10 判据范围自述==实现"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
