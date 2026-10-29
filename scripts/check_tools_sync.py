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

判据范围自述（J10：自述==实现，少写=声明滞后、多写=幻影判据）：
R3b/R7 是唯一遍历 tracked_docs() 的两条规则，也是唯一受 BUG-139 历史豁免作用的规则。
历史豁免（只作用于 R3b/R7）：
  * 路径前缀 memory/、reports/、docs/superpowers/（HISTORY_DIRS，BUG-68 同口径）；
  * CHANGELOG.md 只取最顶部第一个 `## v...` 段（append-only 历史账的当前段），
    其下所有旧版本段视为历史跳过；读不到 `## v` 标题则整份按历史面跳过（保守）；
  * docs/improvement-plan-YYYYMMDD.md 系列只把日期最新那份当现状面，其余视为历史。
R3b/R7 之外的规则（1/2/3/4/5/6）不对 CHANGELOG 做检查，行为不因本豁免改变。

用法：python scripts/check_tools_sync.py
      python scripts/check_tools_sync.py --selftest   # BUG-139 历史豁免反向对照
"""
import re
import subprocess
import sys
from pathlib import Path

# 工具注册真源的**单一实现**（见 real_tools() 的说明：此前 5 处复制，漏改即假绿/互掐）。
# 用 importlib 从文件路径加载（脚本名带下划线前缀，不是包）。
import importlib.util as _ilu

_ir_spec = _ilu.spec_from_file_location(
    "_tool_registry", Path(__file__).resolve().parent / "_tool_registry.py")
_tool_registry = _ilu.module_from_spec(_ir_spec)
_ir_spec.loader.exec_module(_tool_registry)

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "src" / "server" / "server.mbt"
SERVER_DIR = ROOT / "src" / "server"
AGENTS = ROOT / "AGENTS.md"
README = ROOT / "README.md"
DELIV = ROOT / "docs" / "deliverable.md"
RUBRIC = ROOT / "scripts" / "scoring_rubric.md"
OPS_MODES = ROOT / "src" / "ops" / "ops_modes.mbt"
TEMPLATES = sorted((ROOT / "templates").glob("pipeline_mode_*.md"))

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
# BUG-153 同族：2026-10-14 实测运行态 tools/list = 166，而真源只扫 server.mbt 得 148 ⇒ 差 18 个
# （supervisor_tools.mbt 8 / hat_hexa_tools.mbt 3 走 instrumented_tool；mcpcf_embed.mbt 7 走链式
# `s.tool("name", ...)`）。工具注册已从 server.mbt 拆成多文件，判据的扫描面没跟上 ⇒ 文档面
# 被迫对 148 自洽、运行态却是 166，"少写"型漂移（L33 翻账要求"连同工具数一起翻"就是卡在这）。
# 修法：扫描面扩到 src/server/*.mbt（排除测试），并纳入两种注册形态的**并集**。
RE_TOOL_CHAIN = re.compile(r'\b\w+\.tool\(\s*"([^"]+)"')
RE_BACKTICK = re.compile(r"`([\w\-]+)`")
RE_FORBIDDEN_BODY = re.compile(
    r"fn mode_forbidden_tools\([^)]*\).*?\n\}", re.S
)
# BUG-80：旧口径 `"now":\s*string_prop|、now 时间戳` 在真源上**命中 0**——28 处广告用的是另外四种写法
# （、now。/ 参数：now / now(可选) / now(时间戳)），恒 0 的判据等于装饰（BUG-33 的残留因此看不见）。
# 新口径覆盖四种实测写法；"不接受调用方注入 now" 这种否定句不算广告（BUG-33 政策本身就这么写）。
RE_NOW_AD = re.compile(
    r'"now"\s*:\s*string_prop'          # 重新声明 now 入参
    r'|、now(?=[），,。)\s])'                # 参数表里的 、now
    r'|参数：now'
    r'|now\(可选'
    r'|now\(时间戳'
    r'|now\s*时间戳'
)
RE_NOW_NEGATION = re.compile(r'不接受调用方注入\s*now|无\s*now\s*入参')


def now_ad_hits(text):
    """广告 now 的命中位置，剔除否定句（否定句是政策声明，不是广告）。
    判据必须能数出条数：只报『有没有』就永远不知道它是不是饿死的。"""
    hits = []
    for m in RE_NOW_AD.finditer(text):
        lo = max(0, m.start() - 40)
        ctx = text[lo:m.end() + 10]
        if RE_NOW_NEGATION.search(ctx):
            continue
        hits.append(text.count("\n", 0, m.start()) + 1)
    return hits

# "被当成工具调用"的反引号名：`name(...)` 形状 —— 只有工具才会带括号出现，
# 因此不会把 project_dir / task_id 这类参数名误纳进来。
RE_TOOL_SHAPE = re.compile(r"`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)\(")



def real_tools():
    """工具注册真源 —— **委托给单一实现** `scripts/_tool_registry.py`（2026-10-14 收口）。

    收口原因（实测两次）：本函数曾在 5 个消费者里各写一份
    （check_tools_sync / check_doc_surface / check_plugin_sync / gen_plugins / mcp_smoke）。
    工具注册一搬家（从 server.mbt 拆到 supervisor_tools/hat_hexa/mcpcf_embed），
    5 处里漏改 2 处就会 ①假绿（拿旧口径自洽）或 ②互掐（生成器产 166、守卫判 148）。
    现在只有 `_tool_registry.real_tools()` 一处实现，口径：src/server/*.mbt（排除测试）里
    `instrumented_tool(<var>,"name",…)` 与链式 `<var>.tool("name",…)` 的并集。"""
    return _tool_registry.real_tools()


# BUG-71：resources / prompts 此前**零守卫**（六守卫只管工具名与总数），
# 于是 server.mbt 头注释写着 "16 tools + 2 resources + 2 prompts"（差一个数量级）
# 也照样全绿。计数口径与工具同一条：数注册点，不数文档。
RE_RESOURCE = re.compile(r"s1\.resource\(")
RE_PROMPT = re.compile(r"s1\.prompt\(")

# 现状面里"本项目有多少个工具"的声明形状（窄口径，避免吃进 "36 native tools" 这类旁述）。
# 支持两种形态：
#   精确式  "148 个 MCP 工具" / "148 MCP 工具" / "148 工具注册" / "工具 148 个" → 必须等于实测
#   下限式  "140+ 个 MCP 工具" / "140+ MCP 工具" / "140+ 工具注册" / "工具 140+ 个" → 只需实测 ≥ 下限
# 下限式治「写死一个数就是下一颗漂移雷」：加工具不必改文档，减到下限以下才红；
# 下限超过实测即虚报（overclaim），照样判红，不许靠模糊化掩盖虚报。
# BUG-344 根因（2026-10-21）：数字前只挡 `\.` 不够——`cl1 MCP 工具存在` 的 "1" 紧贴
# 标识符字母 "l"，被 `(\d+)\s*MCP\s*工具` 误读成「声明 1 个工具」（实测 170），
# cl 表整行假阳。把数字前 lookbehind 强化为 `(?<![A-Za-z0-9_.])`：拒绝紧贴
# 字母/数字/下划线/点的数字（标识符内数字：cl1/v1/s1/bug37），真声明数字前恒为
# 空格/标点/行首，不受影响。只降假阳、不产生假绿（真实过期声明必在词边界）。
RE_TOOL_CLAIM = re.compile(
    r"(?<![A-Za-z0-9_.])(\d+)\+?\s*个\s*MCP\s*工具|(?<![A-Za-z0-9_.])(\d+)\+?\s*MCP\s*工具|"
    r"(?<![A-Za-z0-9_.])(\d+)\+?\s*工具注册|工具\s*(?<![A-Za-z0-9_.])(\d+)\+?\s*个"
)
# 三元组："120 tools + 3 resources + 2 prompts"
RE_TRIPLE = re.compile(
    r"(\d+)\s*tools?\s*\+\s*(\d+)\s*resources?\s*\+\s*(\d+)\s*prompts?", re.I
)
HISTORY_DIRS = ("memory/", "reports/", "docs/superpowers/")
# BUG-139：下面两类也是「历史面」，不能整份当「当前态声明」比对（否则每次工具数增长
# 都会撞上历史写的旧数，逼人伪造历史）——
#   * CHANGELOG.md 是 append-only，只有最顶部第一个 `## v...` 段是最新/未发布段；
#   * docs/improvement-plan-*.md 系列只有日期（YYYYMMDD）最新那份是现状面，其余是
#     被取代的旧计划。
# 豁免**只作用于 R3b/R7**（R3b/R7 是唯一遍历 tracked_docs() 的两条规则），不影响
# 其它规则对 CHANGELOG 的检查。与 check_test_sync 的豁免口径不共用常量（那边早已
# 通过自己的 HISTORY_FILES=("CHANGELOG.md",) 把整份 CHANGELOG 排除），两边各自演进。
RE_CHANGELOG_H2 = re.compile(r"^##\s+v[^\n]*", re.M)
# BUG-261：豁免口径须认 docs/archive/ 前缀——归档的历史计划（docs/archive/
# improvement-plan-*.md）与根目录同族，日期旧于现状面即豁免。此前正则只匹配
# ^docs/improvement-plan-，归档版本整份被当现状面比对，逼人伪造历史
# （实测 docs/archive/improvement-plan-20260929.md:136 写 129，被 166 判红）。
RE_IPLAN = re.compile(r"^docs/(?:archive/)?improvement-plan-(\d{8})\.md$")
# R219：`docs/YYYY-MM-DD-*.md` 是**时点档案**（设计/评估/决策记录，J15 已按此口径管它们），
# 不是「现状声明」面 —— 拿它去对当前工具总数是**范畴错误**（判例-33 同族：自述面 ≠ 现状面）。
# 触发本条的实据：`docs/2026-10-12-fist-mbt-supervisor-role-design.md:49` 的表格单元格写
# 「**5 个 MCP 工具已在**」（项目助理那 5 个 = **分组数**），被 R3b 当成总数 178 的错报。
RE_DATED_DOC = re.compile(r"^docs/20\d{2}-\d{2}-\d{2}-.+\.md$")


def changelog_current_section(txt):
    """CHANGELOG 是 append-only：只取最顶部第一个 `## v...` 段（最新/未发布段），
    其下所有旧版本段一律视为历史截面跳过。
    读不到任何 `## v` 标题时保守地把整份归入历史面（返回 None，调用方跳过），
    不静默出绿灯——CHANGELOG 没有可解析的「当前段」时 R3b/R7 就无从比对。"""
    ms = list(RE_CHANGELOG_H2.finditer(txt))
    if not ms:
        return None
    start = ms[0].start()
    end = ms[1].start() if len(ms) > 1 else len(txt)
    return txt[start:end]


def latest_improvement_plan(rels):
    """docs/improvement-plan-*.md 里日期最新（YYYYMMDD）那份 = 现状面；多份同日期
    全部当现状面（保守）。没有任何命中返回 None。"""
    ds = [m.group(1) for rel in rels for m in [RE_IPLAN.match(rel)] if m]
    return max(ds) if ds else None


def measured_surface():
    txt = SERVER.read_text(encoding="utf-8")
    return len(RE_RESOURCE.findall(txt)), len(RE_PROMPT.findall(txt))


def tracked_docs():
    """现状面文档 = git 跟踪的 .md − 历史面（与 check_test_sync 同一口径，BUG-68）。"""
    try:
        r = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z", "--", "*.md"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except Exception as e:
        raise SystemExit(f"FATAL 无法调用 git ls-files（{e}）—— 拒绝在无枚举时出绿灯")
    if r.returncode != 0:
        raise SystemExit(f"FATAL git ls-files 退出码 {r.returncode}")
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    live = [f for f in files if not f.startswith(HISTORY_DIRS)]
    if len(live) < 10:
        raise SystemExit(f"FATAL 现状面只枚举到 {len(live)} 份 .md（枚举失效，不出假绿）")
    return live


def surface_claims(text):
    """抽出一份文档里的工具总数声明与三元组声明。
    claims 每项为 (num, is_floor, ln, snippet)：is_floor=True 表示下限式 `N+`（只需实测≥N）。
    triples 每项为 (tools, resources, prompts, ln)：三元组恒为精确式（哨兵面不模糊化）。"""
    claims, triples = [], []
    for ln, line in enumerate(text.splitlines(), 1):
        for m in RE_TRIPLE.finditer(line):
            triples.append((int(m.group(1)), int(m.group(2)), int(m.group(3)), ln))
        for m in RE_TOOL_CLAIM.finditer(line):
            num = next((g for g in m.groups() if g), None)
            if num:
                is_floor = "+" in m.group(0)
                claims.append((int(num), is_floor, ln, line.strip()[:60]))
    return claims, triples


def check_r3b_r7(rel, text, n, res_n, prompt_n):
    """对单份文档的「当前态声明」做 R3b（工具总数）/R7（三元组）比对，返回违例列表。
    R3b 支持两种声明形态：
      - 精确式 `N 个 MCP 工具` → 必须等于实测 n（写死数字必腐烂，不推荐新写）；
      - 下限式 `N+ 个 MCP 工具` → 只需 n >= N（下限超过实测即虚报，判红）。
    下限式治「写死一个数就是下一颗漂移雷」：加工具不必改文档，减到下限以下才红。
    纯函数，--selftest 直接用合成正文考它（不需要真仓库）。"""
    problems = []
    claims, triples = surface_claims(text)
    for num, is_floor, ln, snippet in claims:
        if is_floor:
            if n < num:
                problems.append(
                    f"R3b {rel}:{ln} 下限声明 {num}+ 个工具，实测仅 {n}（下限超过实测＝虚报）—— {snippet}"
                )
        elif num != n:
            problems.append(
                f"R3b {rel}:{ln} 声明 {num} 个工具，实测注册 {n} —— {snippet}"
            )
    for a, b, c, ln in triples:
        bad = [f"{x}≠{y}" for x, y in ((a, n), (b, res_n), (c, prompt_n)) if x != y]
        if bad:
            problems.append(
                f"R7 {rel}:{ln} 三元组声明 {a} tools + {b} resources + {c} prompts，"
                f"实测 {n}/{res_n}/{prompt_n}（{', '.join(bad)}）"
            )
    return problems


def current_state_text(rel, txt, latest_iplan):
    """把一份文档裁成「当前态声明」正文；返回 None 表示整份归历史面（R3b/R7 跳过）。
    BUG-139：CHANGELOG 只取最顶部 `## v` 段；日期非最新的 improvement-plan 整份跳过。"""
    if rel == "CHANGELOG.md":
        return changelog_current_section(txt)
    m = RE_IPLAN.match(rel)
    if m and latest_iplan is not None and m.group(1) != latest_iplan:
        return None
    # R219：带日期的 docs/ 档案（设计/评估/决策）整份归历史面 —— 它们记录「当时」而非「现在」。
    # 现状总数仍由 README / AGENTS(+清单) / deliverable / scoring_rubric 四个**现状面**兜住；
    # 这一格只免掉「拿历史文档里的分组数当总数」这类范畴错误，不放宽任何一个现状面。
    if RE_DATED_DOC.match(rel):
        return None
    return txt


# ↓ 严格参数面（R66）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
_known = {"--selftest"}
_unknown = [a for a in sys.argv[1:] if a.startswith("--") and a.split("=")[0] not in _known]
if _unknown:
    print("FATAL 未知参数：%s（本尺只接受：%s）" % (" ".join(_unknown), " ".join(sorted(_known))))
    sys.exit(2)

def main():
    # 与守卫族同款：cp936 控制台下中文判据文案会乱码（崩溃/不可读的守卫等于没有守卫）。
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if "--selftest" in sys.argv[1:]:
        return selftest()
    tools = real_tools()
    real = set(tools)
    n = len(tools)
    problems = []
    agents = AGENTS.read_text(encoding="utf-8")
    # R213：**AGENTS 面可能被拆开了**（R212 为了 harness 的指令字节预算，把 MCP 工具清单
    # 整块搬到 `docs/AGENTS-mcp-inventory.md`，内容逐字保留、AGENTS.md 只留指针）。
    # ⇒ 本判据的「AGENTS 面」= AGENTS.md **+ 那份清单文件**（存在才拼，不存在的仓库行为不变）。
    inv = ROOT / "docs" / "AGENTS-mcp-inventory.md"
    if inv.is_file():
        agents = agents + "\n" + inv.read_text(encoding="utf-8")
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

    # 3) 四份现状面必须各有一处与实测一致的工具总数自述（反幻影：宣称描述 MCP server 却
    #    不告诉读者工具有几个，等于让读者去猜规模）。接受两种形态：
    #    - 精确式  "148 个 MCP 工具" → 等于实测 n
    #    - 下限式  "140+ 个 MCP 工具" → n >= 下限（下限超过实测即虚报，不算一致）
    for path in (README, AGENTS, DELIV, RUBRIC):
        # R213：AGENTS 的「工具总数自述」允许落在**清单文件**里（R212 拆分后，AGENTS 只留指针
        # + 一句总数；逐工具名与总数都按「本文件 + 清单」合并面判，与规则 2 同口径）。
        _txt = agents if path == AGENTS else path.read_text(encoding="utf-8")
        claims, _ = surface_claims(_txt)
        ok = any(
            (n >= num and is_floor) or (num == n and not is_floor)
            for num, is_floor, _, _ in claims
        )
        if not ok:
            problems.append(
                f"{path.name} 缺少与实测 {n} 一致的工具总数自述"
                f"（精确值 {n} 或 ≤{n} 的下限式 N+；下限超过实测即虚报）"
            )

    # 3b) 全量现状面的"工具总数声明"必须等于实测（BUG-71 同族：只要求"出现过"的判据，
    #     文档里再写一个错数照样绿 —— ARCHITECTURE.md 的 104 就是这么活下来的）
    res_n, prompt_n = measured_surface()
    tracked = tracked_docs()
    latest_iplan = latest_improvement_plan(tracked)
    scanned = 0
    history_skipped = 0
    for rel in tracked:
        p = ROOT / rel
        if not p.is_file():
            continue
        txt = current_state_text(
            rel, p.read_text(encoding="utf-8", errors="replace"), latest_iplan
        )
        if txt is None:
            history_skipped += 1
            continue
        scanned += 1
        problems.extend(check_r3b_r7(rel, txt, n, res_n, prompt_n))
    # 反幻影：三元组在 server.mbt 头注释里必须出现，且**头注释自己也在比对范围内**
    # （BUG-71 的原始证据就是这行写着 "16 tools + 2 resources + 2 prompts"）
    head = server_txt.splitlines()[0] if server_txt.splitlines() else ""
    _, head_triples = surface_claims(head)
    if not head_triples:
        problems.append(f"R7 server.mbt:1 头注释没有 'A tools + B resources + C prompts' 三元组（判据无从比对）")
    for a, b, c, _ln in head_triples:
        bad = [f"{x}≠{y}" for x, y in ((a, n), (b, res_n), (c, prompt_n)) if x != y]
        if bad:
            problems.append(
                f"R7 server.mbt:1 头注释三元组 {a}/{b}/{c} 与实测 {n}/{res_n}/{prompt_n} 不符（{', '.join(bad)}）"
            )
    if scanned < 10:
        print(f"FATAL 现状面只扫到 {scanned} 份文档（<10），拒绝出绿灯")
        return 2

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

    # 5) 不得再向调用方广告时钟入参（BUG-33；BUG-80：判据要数得出条数）
    ads = now_ad_hits(server_txt)
    if ads:
        problems.append(
            'server.mbt 有 %d 处仍在广告 "now" 入参（行号 %s；BUG-33：时钟由服务端盖章，'
            '广告无人读的参数=契约说谎，BUG-80：旧正则命中 0 才让这批复活）'
            % (len(ads), ", ".join(str(x) for x in ads[:12]))
        )

    # 6) 模板中以 `name(...)` 调用形状出现的名字必须是真注册名（BUG-38 文档面）
    for tpl in TEMPLATES:
        for tok in sorted(set(RE_TOOL_SHAPE.findall(tpl.read_text(encoding="utf-8")))):
            if tok not in real:
                problems.append(
                    f"{tpl.name} 以调用形状引用了未注册工具 `{tok}(...)`（BUG-38：按模板执行必然调空）"
                )

    if problems:
        print(f"FAIL 工具清单不一致（实测 {n} 个；R3b/R7 扫现状面 {scanned} 份，历史面豁免 {history_skipped} 份）：")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"PASS 工具单一真源一致：server.mbt 注册 {n} 个，AGENTS/README/deliverable/scoring_rubric 对齐；"
          f"R3b/R7 扫现状面 {scanned} 份，历史面豁免 {history_skipped} 份（CHANGELOG 历史段/旧版 improvement-plan）")
    return 0


# ---------------------------------------------------------------- selftest
# 判据必须先证明它会红。BUG-139 补进「历史豁免不误伤」的反向对照：只要求 rc≠0 会被
# 「被别的检查顺手拦住」骗过，所以每条变体指名"必须出现/必须不出现"哪条违例。
# 合成正文本地考，不碰仓库真源（与 check_test_sync 的 --selftest 同族写法）。


def _tools_line(num):
    """合成一条精确式工具总数声明（形状对齐 RE_TOOL_CLAIM 的「N 个 MCP 工具」）。"""
    return f"共 **{num} 个 MCP 工具**（现状面声明）"


def _tools_floor_line(num):
    """合成一条下限式工具总数声明（形状对齐 RE_TOOL_CLAIM 的「N+ 个 MCP 工具」）。"""
    return f"共 **{num}+ 个 MCP 工具**（下限式声明，实测 ≥{num} 即过）"


def selftest():
    n, res_n, prompt_n = 130, 3, 2
    done = [0]

    def run_case(name, rel, text, want=None, want_none=None, latest_iplan="20261010"):
        txt = current_state_text(rel, text, latest_iplan)
        probs = [] if txt is None else check_r3b_r7(rel, txt, n, res_n, prompt_n)
        if want is not None and not any(want in p for p in probs):
            print(f"SELFTEST FAIL [{name}] 期望命中 «{want}» 实际 {probs or '无违例'}")
            return False
        if want_none is not None and any(want_none in p for p in probs):
            print(f"SELFTEST FAIL [{name}] 不该命中 «{want_none}» 实际 {probs}")
            return False
        done[0] += 1
        print(f"  ok  {name}")
        return True

    print("SELFTEST BUG-139 历史豁免对照（合成正文，不碰仓库）")

    # 1) BUG-139 原始形状：CHANGELOG **顶部当前段**写对（130）、**历史段**写旧数（129）→ 不误红
    if not run_case(
        "changelog-current-clean-hist-129-exempt",
        "CHANGELOG.md",
        "## v0.3.5 (unreleased)\n\n" + _tools_line(130) + "\n\n"
        "## v0.3.4 (unreleased)\n\n" + _tools_line(129),
        want_none="R3b",
    ):
        return 1
    # 2) 反向对照：CHANGELOG **当前段**写错数（128）仍必红
    if not run_case(
        "changelog-current-stale-reds",
        "CHANGELOG.md",
        "## v0.3.5 (unreleased)\n\n" + _tools_line(128) + "\n\n"
        "## v0.3.0 (unreleased)\n\n" + _tools_line(129),
        want="R3b CHANGELOG.md",
    ):
        return 1
    # 3) 反向对照：历史段写**离谱**的旧数（999）仍豁免（历史就是历史，不因离谱就当现状面）
    if not run_case(
        "changelog-hist-wild-number-exempt",
        "CHANGELOG.md",
        "## v0.3.5 (unreleased)\n\n" + _tools_line(130) + "\n\n"
        "## v0.3.0 (unreleased)\n\n" + _tools_line(999),
        want_none="R3b",
    ):
        return 1
    # 4) CHANGELOG 读不到 `## v` 标题 → 整份按历史面跳过（保守，不静默出绿灯也不误红）
    txt = current_state_text("CHANGELOG.md", "# CHANGELOG\n\n正文无版本段\n", "20261010")
    if txt is not None:
        print("SELFTEST FAIL [changelog-no-version-header] 无 `## v` 标题时没有按历史面跳过")
        return 1
    done[0] += 1
    print("  ok  changelog-no-version-header-skip")

    # 5) improvement-plan 旧日期（20260929）写 129 必须豁免
    if not run_case(
        "iplan-old-20260929-exempt",
        "docs/improvement-plan-20260929.md",
        _tools_line(129),
        want_none="R3b",
    ):
        return 1
    # 5a) BUG-261：同族，但文件落在 docs/archive/ 归档目录——RE_IPLAN 若不认
    #     archive/ 前缀，归档的历史计划就漏掉豁免、整份被当现状面比对。这是实测红面
    #     （docs/archive/improvement-plan-20260929.md:136 写 129）的原始形状。
    if not run_case(
        "iplan-archive-old-exempt",
        "docs/archive/improvement-plan-20260929.md",
        _tools_line(129),
        want_none="R3b",
    ):
        return 1
    # 5b) 反向对照：archive/ 里最新日期的计划仍是现状面——写错数（128）必红，
    #     豁免只给「非最新」，不因落 archive/ 就一刀切放行。
    if not run_case(
        "iplan-archive-current-stale-reds",
        "docs/archive/improvement-plan-20261010.md",
        _tools_line(128),
        want="R3b docs/archive/improvement-plan-20261010.md",
    ):
        return 1
    # 6) 反向对照：最新日期（20261010）写错数（128）仍必红
    if not run_case(
        "iplan-current-stale-reds",
        "docs/improvement-plan-20261010.md",
        _tools_line(128),
        want="R3b docs/improvement-plan-20261010.md",
    ):
        return 1
    # 7) 反向对照：最新日期写对（130）不误红
    if not run_case(
        "iplan-current-clean",
        "docs/improvement-plan-20261010.md",
        _tools_line(130),
        want_none="R3b",
    ):
        return 1

    # 7a) 下限式达标：实测 130 ≥ 下限 100 → 不误红（加工具不必改文档）
    if not run_case(
        "floor-pass-below-measured",
        "docs/improvement-plan-20261010.md",
        _tools_floor_line(100),
        want_none="R3b",
    ):
        return 1
    # 7b) 下限式超过实测：实测 130 < 下限 150 → 必红（下限式不许当虚报遮羞布）
    if not run_case(
        "floor-overclaim-reds",
        "docs/improvement-plan-20261010.md",
        _tools_floor_line(150),
        want="R3b docs/improvement-plan-20261010.md",
    ):
        return 1
    # 7c) 下限式边界相等：实测 130 == 下限 130 → 不误红（>= 语义含等号）
    if not run_case(
        "floor-equal-boundary",
        "docs/improvement-plan-20261010.md",
        _tools_floor_line(130),
        want_none="R3b",
    ):
        return 1
    # 7d) 下限式「N+ MCP 工具」（无「个」）也认，且与精确式同段并存时各自独立判
    if not run_case(
        "floor-alt-shape-and-mixed",
        "docs/improvement-plan-20261010.md",
        "以 **120+ MCP 工具** 暴露；另有精确口径 **130 个 MCP 工具**",
        want_none="R3b",
    ):
        return 1

    # 7e) BUG-344 根因回归：标识符内数字（cl1）不得被当成「1 MCP 工具」声明
    #     数字紧贴标识符字母（cl1）时 lookbehind `(?<![A-Za-z0-9_.])` 拒配，
    #     该形状不再产生 R3b 假阳（实测 170 的工具数不被 1 顶掉）。
    if not run_case(
        "identifier-digit-in-cl-cell-no-false-claim",
        "docs/improvement-plan-20261010.md",
        "| cl1 MCP 工具存在 | model_route 新增 dry_run 分支回写 | ✅ |",
        want_none="R3b",
    ):
        return 1

    # 8) latest_improvement_plan 取日期最大那份；无命中返回 None（不报假"最新"）
    if latest_improvement_plan([
        "docs/improvement-plan-20260929.md",
        "docs/improvement-plan-20261010.md",
    ]) != "20261010":
        print("SELFTEST FAIL [latest-improvement-plan] 取错日期")
        return 1
    if latest_improvement_plan(["README.md", "AGENTS.md"]) is not None:
        print("SELFTEST FAIL [latest-improvement-plan] 无命中应返回 None")
        return 1
    done[0] += 1
    print("  ok  latest-improvement-plan-picks-max")

    print(f"SELFTEST PASS {done[0]} 个变体各自命中自己指名的判据（计数由 run_case 实测累加，非手写）")
    return 0


if __name__ == "__main__":
    sys.exit(main())