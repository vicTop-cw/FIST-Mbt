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
import subprocess
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
    return sorted(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8"))))


# BUG-71：resources / prompts 此前**零守卫**（六守卫只管工具名与总数），
# 于是 server.mbt 头注释写着 "16 tools + 2 resources + 2 prompts"（差一个数量级）
# 也照样全绿。计数口径与工具同一条：数注册点，不数文档。
RE_RESOURCE = re.compile(r"s1\.resource\(")
RE_PROMPT = re.compile(r"s1\.prompt\(")

# 现状面里"本项目有多少个工具"的声明形状（窄口径，避免吃进 "36 native tools" 这类旁述）
RE_TOOL_CLAIM = re.compile(
    r"(\d+)\s*个\s*MCP\s*工具|(\d+)\s*MCP\s*工具|(\d+)\s*工具注册|工具\s*(\d+)\s*个"
)
# 三元组："120 tools + 3 resources + 2 prompts"
RE_TRIPLE = re.compile(
    r"(\d+)\s*tools?\s*\+\s*(\d+)\s*resources?\s*\+\s*(\d+)\s*prompts?", re.I
)
HISTORY_DIRS = ("memory/", "reports/", "docs/superpowers/")


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
    """抽出一份文档里的工具总数声明与三元组声明。"""
    claims, triples = [], []
    for ln, line in enumerate(text.splitlines(), 1):
        for m in RE_TRIPLE.finditer(line):
            triples.append((int(m.group(1)), int(m.group(2)), int(m.group(3)), ln))
        for m in RE_TOOL_CLAIM.finditer(line):
            num = next((g for g in m.groups() if g), None)
            if num:
                claims.append((int(num), ln, line.strip()[:60]))
    return claims, triples


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

    # 3b) 全量现状面的"工具总数声明"必须等于实测（BUG-71 同族：只要求"出现过"的判据，
    #     文档里再写一个错数照样绿 —— ARCHITECTURE.md 的 104 就是这么活下来的）
    res_n, prompt_n = measured_surface()
    scanned = 0
    for rel in tracked_docs():
        p = ROOT / rel
        if not p.is_file():
            continue
        scanned += 1
        claims, triples = surface_claims(p.read_text(encoding="utf-8", errors="replace"))
        for num, ln, snippet in claims:
            if num != n:
                problems.append(
                    f"R3b {rel}:{ln} 声明 {num} 个工具，实测注册 {n} —— {snippet}"
                )
        for a, b, c, ln in triples:
            bad = [
                f"{x}≠{y}"
                for x, y in ((a, n), (b, res_n), (c, prompt_n))
                if x != y
            ]
            if bad:
                problems.append(
                    f"R7 {rel}:{ln} 三元组声明 {a} tools + {b} resources + {c} prompts，"
                    f"实测 {n}/{res_n}/{prompt_n}（{', '.join(bad)}）"
                )
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
        print(f"FAIL 工具清单不一致（实测 {n} 个）：")
        for p in problems:
            print("  - " + p)
        return 1
    print(f"PASS 工具单一真源一致：server.mbt 注册 {n} 个，AGENTS/README/deliverable/scoring_rubric 对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())