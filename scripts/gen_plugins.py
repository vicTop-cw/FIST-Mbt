#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/gen_plugins.py — 一源四态·插件态生成器（cl7 的生成侧）。

背景：三形态（MCP / CLI / Skill）里 skill 正文长期放在仓库外的兄弟目录
（`E:\\IDEProjects\\moonbit-skills\\skills\\fist-mbt`），没人守卫，数字漂成「41 个工具」
也没人发现——这正是 BUG-22/30 记的「文档面落后于真源、守卫覆盖面窄于主张」。
插件态（第四态）如果继续手写，必然重复同样的腐烂。所以本脚本把四个宿主的插件
**全部生成为真源的投影**，人只改 `plugins/source/`，不改 `plugins/<host>/`。

单一真源：
  - 工具数：src/server/server.mbt 的 instrumented_tool 注册（与 check_tools_sync 同一正则）
  - 版本：moon.mod 的 version
  - 缺陷账本：memory/bugs.md 的 `## BUG-N ... OPEN` 与 `### FIXED(...)`
  - 正文：plugins/source/SKILL.md(+references/)、plugins/source/SKILL.commander.md
  - 启动命令：根 .mcp.json 的 mcpServers（不在插件里重写第二份）

产出（宿主顺序 = 指定顺序：atomcode → codearts → deepseek-harness → claude）：
  plugins/atomcode/skills/{fist-mbt,fist-commander}/
  plugins/codearts/skills/{fist-mbt,fist-commander}/ + UserSkillStatus.append.txt
  plugins/deepseek-harness/skills/fist-mbt/ + instructions.append.md
  plugins/claude/{.claude-plugin/plugin.json,.claude-plugin/marketplace.json,.mcp.json,skills/fist-mbt/}

字节稳定（不含时间戳）→ scripts/check_plugin_sync.py 重跑本脚本到临时区再 diff，
任何"手改插件/漂移未重生成"都会红。

用法：python scripts/gen_plugins.py [--check]   # --check 只报告漂移不写盘
退出码：0=已生成/无漂移；1=--check 下发现漂移；2=真源缺失或解析失败（判据自证失败）
"""
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

# BUG-58：守卫的“红”必须是判据红。Windows 默认 GBK 控制台下，中文结论里的 ↔ 等字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于“守卫不可信”。
# 统一把 stdout/stderr 钉成 UTF-8（CI 在 Linux UTF-8 下是无损 no-op）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "plugins" / "source"
SERVER = ROOT / "src" / "server" / "server.mbt"
MOON_MOD = ROOT / "moon.mod"
BUGS = ROOT / "memory" / "bugs.md"
ROOT_MCP = ROOT / ".mcp.json"

RE_TOOL = re.compile(r'instrumented_tool\(\s*s1\s*,\s*"([^"]+)"')
RE_VERSION = re.compile(r'^version\s*=\s*"([^"]+)"', re.M)
RE_BUG_HEAD = re.compile(r"^## BUG-(\d+)\b", re.M)
RE_FIXED = re.compile(r"^### FIXED\(", re.M)
# 抬头文法与闭集（真源定义写在 memory/bugs.md 的「记账规则」段）
BUG_STATUSES = ("OPEN", "FIXED", "DUPLICATE", "FALSE_POSITIVE")
RE_BUG_STATUS = re.compile(
    r"^## (BUG-\d+) \[[^\]]+\] \[(high|medium|low)\] (\S+)(?: (→BUG-\d+))?", re.M
)
# 小记抬头里点名的编号集合：### FIXED(<stamp> / BUG-a, BUG-b …)
RE_FIXED_IDS = re.compile(r"^### FIXED\([^)]* / ([^)]*?)\)\s*$", re.M)


def ledger_status(bugs_txt):
    """纯判据：喂账本正文，出 (四态计数, 违例列表)。

    抽成函数是为了能被变异证明直接考（temp/recon/prove_ledger_gates.py）——
    长在 die() 里的门禁和写在纸上的规则一样，没人验证过它会不会红。
    """
    ids = re.findall(r"^## BUG-(\d+)\b", bugs_txt, re.M)
    if not ids:
        return {}, ["账本一条 BUG 条目都没解析到（判据坏了，不是账本空）"]
    heads = RE_BUG_STATUS.findall(bugs_txt)
    problems = []
    if len(heads) != len(ids):
        problems.append(
            f"条目 {len(ids)} 条 / 可解析抬头状态 {len(heads)} 条不符 ⇒ 有抬头不合文法"
            "（`## BUG-n [时间] [严重度] 状态 [→BUG-m]`）")
    st = {h[0]: (h[2], (h[3] or "").lstrip("→")) for h in heads}
    bad_vocabulary = sorted({s for s, _ in st.values()} - set(BUG_STATUSES))
    if bad_vocabulary:
        problems.append(f"抬头出现闭集外的状态词：{bad_vocabulary}（闭集={list(BUG_STATUSES)}）")
    named = {i for grp in RE_FIXED_IDS.findall(bugs_txt)
             for i in re.split(r"[,\s]+", grp) if i.startswith("BUG-")}
    counts = {s: sum(1 for _, (v, _m) in st.items() if v == s) for s in BUG_STATUSES}
    key = lambda x: int(x.split("-")[1])  # noqa: E731
    # 硬门①：标 FIXED 必须被某条小记抬头点名（防空口标修好）
    unclaimed = sorted((k for k, (v, _) in st.items() if v == "FIXED" and k not in named), key=key)
    if unclaimed:
        problems.append(f"{len(unclaimed)} 条标 FIXED 却无小记点名：{' '.join(unclaimed[:8])}")
    # 硬门②：被点名的必须已标 FIXED（防修了没标 / 小记与状态两套话）
    stale = sorted((k for k in named if st.get(k, ("?", ""))[0] != "FIXED"), key=key)
    if stale:
        problems.append(f"{len(stale)} 条被小记点名但状态不是 FIXED：{' '.join(stale[:8])}")
    # 硬门③：DUPLICATE 必须带合法主编号（存在、不是自己、不再是个 DUPLICATE）
    for k, (v, main) in st.items():
        if v != "DUPLICATE":
            continue
        if not main:
            problems.append(f"{k} 标 DUPLICATE 却没写 →BUG-m")
        elif main == k or main not in st:
            problems.append(f"{k} 的主编号 {main} 不存在或指向自己")
        elif st[main][0] == "DUPLICATE":
            problems.append(f"{k} 的主编号 {main} 自身也是 DUPLICATE（链条不允许）")
    return counts, problems

# 宿主插件名（各宿主市场的目录名）
SKILL_MAIN = "fist-mbt"
SKILL_COMMANDER = "fist-commander"
README_DOC = ROOT / "README.md"  # BUG-67：分组表唯一真源


RE_README_GROUP = re.compile(r"^###\s+\S.*?[（(](\d+)[)）]\s*$", re.M)


def tool_groups(n: int) -> str:
    """把 README「功能全景」的分组标题投影成插件正文的一行分组表。

    BUG-67 的根因是"分组数字被手抄了第二份"。这里不新增第二份真源：
    README 的分组和由 check_doc_surface.py J4 钉住（分组和 == 注册表实测），
    本函数只把它再投影一次，并且**当场复算**——对不上直接 die，不产出"看着正常"的插件。
    """
    if not README_DOC.exists():
        die("README.md 真源缺失，无法投影工具分组")
    text = README_DOC.read_text(encoding="utf-8")
    pairs = [x for x in RE_README_GROUP.findall(text)]
    if not pairs:
        die("README.md 未解析到任何 `### 分组（N）` 标题（判据坏了，不是文档坏了）")
    names = [
        re.sub(r"[（(]\d+[)）]\s*$", "", ln.strip()[4:]).strip()
        for ln in text.splitlines()
        if RE_README_GROUP.match(ln.strip())
    ]
    total = sum(int(x) for x in pairs)
    if total != n:
        die(f"README 分组和 {total} != 注册表实测 {n} ⇒ 拒绝投影（先修 README）")
    return "、".join(f"{nm} {ct}" for nm, ct in zip(names, pairs))


def die(msg: str) -> None:
    print(f"FATAL 真源自证失败：{msg}")
    sys.exit(2)


def measure() -> dict:
    for p in (SERVER, MOON_MOD, BUGS, ROOT_MCP, SOURCE / "SKILL.md"):
        if not p.exists():
            die(f"缺真源 {p.relative_to(ROOT)}")
    tools = sorted(set(RE_TOOL.findall(SERVER.read_text(encoding="utf-8"))))
    n = len(tools)
    # 反幻影哨兵：解析不到东西时绝不生成"看似正常"的插件（空真源=判据坏了）
    if n <= 100:
        die(f"工具真源解析到 {n} 个（<=100 视为解析失败，不生成）")
    m = RE_VERSION.search(MOON_MOD.read_text(encoding="utf-8"))
    if not m:
        die("moon.mod 未解析到 version")
    bugs_txt = BUGS.read_text(encoding="utf-8")
    ids = [int(x) for x in RE_BUG_HEAD.findall(bugs_txt)]
    if not ids:
        die("memory/bugs.md 未解析到任何缺陷条目")
    total = len(ids)
    # 计数只从**条目抬头的状态位**反解（2026-09-27 兑账立的口径）。
    # 旧口径 open_cnt = total - len(### FIXED) 把"小记有几条"当成"修了几条 bug"，
    # 而一条小记可收 1~16 条、也可一条都不收 ⇒ 那句"30 条待修"从来没有定义。
    counts, problems = ledger_status(bugs_txt)
    if problems:
        die("账本状态与叙述面对不上：\n  - " + "\n  - ".join(problems))
    return {
        "TOOL_COUNT": str(n),
        "TOOL_GROUPS": tool_groups(n),
        "VERSION": m.group(1),
        "LEDGER_SUMMARY": (
            f"BUG-1~{max(ids)} 共 {total} 条入账："
            f"{counts['OPEN']} 条待修 / {counts['FIXED']} 条已修 / "
            f"{counts['DUPLICATE']} 条重复并入 / {counts['FALSE_POSITIVE']} 条误报"
            "（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）"
        ),
        "_tools": n,
        "_open": counts["OPEN"],
        "_fixed": counts["FIXED"],
        "_counts": counts,
    }


def render(text: str, vals: dict) -> str:
    out = text
    for k, v in vals.items():
        if not k.startswith("_"):
            out = out.replace("{{" + k + "}}", v)
    if "{{" in out:
        die(f"正文残留未替换占位符：{[s for s in re.findall(r'\\{\\{[A-Z_]+\\}\\}', out)]}")
    return out


def stamp(host: str, vals: dict, extra: str = "") -> str:
    return (
        f"<!-- generated by scripts/gen_plugins.py from plugins/source/ — DO NOT EDIT BY HAND\n"
        f"     host={host} tools={vals['TOOL_COUNT']} version={vals['VERSION']}\n"
        f"     ledger={vals['LEDGER_SUMMARY']}{extra} -->\n"
    )


def inject_after_frontmatter(body: str, header: str) -> str:
    """把生成戳插在 YAML frontmatter 之后（frontmatter 必须保持首块）。"""
    if not body.startswith("---"):
        return header + "\n" + body
    end = body.find("\n---", 3)
    if end < 0:
        die("SKILL.md frontmatter 未闭合")
    cut = end + 4  # 含闭合 `---` 与其后换行
    return body[:cut] + "\n" + header + body[cut:].lstrip("\n")


def write_skill(dest_dir: Path, src_file: Path, host: str, vals: dict,
                with_refs: bool = True) -> None:
    body = render(src_file.read_text(encoding="utf-8"), vals)
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / "SKILL.md").write_text(
        inject_after_frontmatter(body, stamp(host, vals)), encoding="utf-8", newline="\n"
    )
    refs = SOURCE / "references"
    if with_refs and refs.is_dir():
        target = dest_dir / "references"
        if target.exists():
            shutil.rmtree(target)
        target.mkdir(parents=True, exist_ok=True)
        # BUG-67：原来这里是 shutil.copytree —— 原样字节复制**结构上永远无法**承载
        # {{TOOL_COUNT}}，于是投影正文只能手抄数字，抄完就开始腐烂
        # （实测 references/fist-methodology.md 停在 "41 total"，真源早已 120）。
        # 现在逐文件走 render()，占位符与 SKILL.md 同一套真源。
        for f in sorted(refs.rglob("*")):
            if f.is_dir():
                continue
            dst = target / f.relative_to(refs)
            dst.parent.mkdir(parents=True, exist_ok=True)
            if f.suffix.lower() == ".md":
                dst.write_text(
                    render(f.read_text(encoding="utf-8"), vals),
                    encoding="utf-8",
                    newline="\n",
                )
            else:
                shutil.copyfile(f, dst)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def write_json(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def generate(base: Path, vals: dict) -> None:
    main_src = SOURCE / "SKILL.md"
    commander_src = SOURCE / "SKILL.commander.md"
    root_mcp = json.loads(ROOT_MCP.read_text(encoding="utf-8"))
    if "fist-mbt" not in root_mcp.get("mcpServers", {}):
        die("根 .mcp.json 未声明 mcpServers['fist-mbt']（启动参数真源异常）")

    # ① atomcode：宿主读 ~/.atomcode/skills/<name>/SKILL.md（frontmatter name/description）
    write_skill(base / "atomcode" / "skills" / SKILL_MAIN, main_src, "atomcode", vals)
    if commander_src.exists():
        write_skill(base / "atomcode" / "skills" / SKILL_COMMANDER, commander_src,
                    "atomcode", vals, with_refs=False)
    write_text(
        base / "atomcode" / "INSTALL.md",
        f"""# AtomCode 插件态安装

把本目录的 `skills/` 整体拷到 `~/.atomcode/skills/`（或软链），重启即见 `/{SKILL_MAIN}`。

- 本目录内容全部由 `scripts/gen_plugins.py` 从 `plugins/source/` 生成，**不要手改**；
  改了会在 `scripts/check_plugin_sync.py`（cl7）下红。
- MCP server 真源在仓库根 `.mcp.json`（{vals['TOOL_COUNT']} 工具 / v{vals['VERSION']}）；
  AtomCode 侧只需在 mcp 配置里指向同一命令，不在插件里复制第二份启动参数。
""",
    )

    # ② codearts：宿主读 ~/.codeartsdoer/skills/<name>/SKILL.md + UserSkillStatus.txt 登记
    write_skill(base / "codearts" / "skills" / SKILL_MAIN, main_src, "codearts", vals)
    if commander_src.exists():
        write_skill(base / "codearts" / "skills" / SKILL_COMMANDER, commander_src,
                    "codearts", vals, with_refs=False)
    write_text(
        base / "codearts" / "UserSkillStatus.append.txt",
        f"{SKILL_MAIN}=true\n{SKILL_COMMANDER}=true\n",
    )
    write_text(
        base / "codearts" / "INSTALL.md",
        f"""# CodeArts Doer 插件态安装

1. 把 `skills/` 拷到 `~/.codeartsdoer/skills/`；
2. 把 `UserSkillStatus.append.txt` 的两行追加进 `~/.codeartsdoer/skills/UserSkillStatus.txt`。

内容由 `scripts/gen_plugins.py` 生成（真源=`plugins/source/`）；手改由 cl7 守卫拦。
MCP 启动参数以仓库根 `.mcp.json` 为准（{vals['TOOL_COUNT']} 工具 / v{vals['VERSION']}）。
""",
    )

    # ③ deepseek-harness：宿主以单一 instructions 文件为规则入口
    write_skill(base / "deepseek-harness" / "skills" / SKILL_MAIN, main_src,
                "deepseek-harness", vals)
    write_text(
        base / "deepseek-harness" / "instructions.append.md",
        f"""<!-- generated by scripts/gen_plugins.py — DO NOT EDIT BY HAND
     host=deepseek-harness tools={vals['TOOL_COUNT']} version={vals['VERSION']} -->

## FIST-Mbt（一源四态·插件态）

- 本 harness 走 FIST 指挥官模式：意图 → 分流 → 派单 → 终审 → 沉淀汇报；不亲力亲为可分配工作。
- MCP server `fist-mbt`（{vals['TOOL_COUNT']} 工具 / v{vals['VERSION']}）经仓库根 `.mcp.json` 暴露；
  工具清单唯一真源是 `src/server/server.mbt`，**以 tools/list 为准**，任何文档数字都可能滞后。
- 已知缺陷账本：{vals['LEDGER_SUMMARY']}（真源 `memory/bugs.md`，状态位可就地改、叙述面只追加）。
- 详细操作见 `skills/{SKILL_MAIN}/SKILL.md` 与 `references/`（同为生成产物）。
""",
    )

    # ④ claude：.claude-plugin/{plugin.json,marketplace.json} + .mcp.json + skills/
    write_skill(base / "claude" / "skills" / SKILL_MAIN, main_src, "claude", vals)
    if commander_src.exists():
        write_skill(base / "claude" / "skills" / SKILL_COMMANDER, commander_src,
                    "claude", vals, with_refs=False)
    write_json(
        base / "claude" / ".claude-plugin" / "plugin.json",
        {
            "name": "fist-mbt",
            "description": (
                f"FIST 指挥官 MCP server（{vals['TOOL_COUNT']} 工具）+ 自驱流水线四模式，"
                f"v{vals['VERSION']}。真源：vicTop-cw/fist-mbt"
            ),
            "version": vals["VERSION"],
            "author": {"name": "vicTop"},
            "repository": "https://github.com/vicTop-cw/fist-mbt",
            "keywords": ["fist", "moonbit", "mcp", "orchestration", "selfdrive"],
        },
    )
    write_json(
        base / "claude" / ".claude-plugin" / "marketplace.json",
        {
            "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
            "name": "fist-mbt",
            "metadata": {
                "version": vals["VERSION"],
                "description": "FIST-Mbt 插件态（由 scripts/gen_plugins.py 生成）",
            },
            "owner": {"name": "vicTop"},
            "plugins": [
                {
                    "name": "fist-mbt",
                    "description": (
                        f"FIST 指挥官任务编排与自驱流水线：{vals['TOOL_COUNT']} 个 MCP 工具 + "
                        f"{SKILL_MAIN}/{SKILL_COMMANDER} 两个 skill"
                    ),
                    "source": "./",
                    "category": "development",
                }
            ],
        },
    )
    # .mcp.json：**逐字节复制**根真源（不是重新序列化——序列化会改排版，等于偷偷造第二份）
    claude_mcp = base / "claude" / ".mcp.json"
    claude_mcp.parent.mkdir(parents=True, exist_ok=True)
    claude_mcp.write_bytes(ROOT_MCP.read_bytes())
    write_text(
        base / "claude" / "INSTALL.md",
        f"""# Claude 插件态安装

`/plugin marketplace add <本仓路径>/plugins/claude` → `/plugin install fist-mbt@fist-mbt`。

- `.mcp.json` 是仓库根 `.mcp.json` 的**逐字副本**（启动参数只有一份真源）；
- `skills/` 由 `scripts/gen_plugins.py` 投影自 `plugins/source/`；手改由 cl7 守卫拦。
""",
    )

    write_text(
        base / "README.md",
        f"""# 插件态（一源四态的第四态）

四个宿主的插件目录**全部是生成产物**，唯一可编辑真源是 `plugins/source/`：

| 宿主 | 目录 | 宿主读取方式 |
|---|---|---|
| AtomCode | `atomcode/skills/<name>/SKILL.md` | 拷/链到 `~/.atomcode/skills/` |
| CodeArts Doer | `codearts/skills/<name>/SKILL.md` + `UserSkillStatus.append.txt` | 拷 + 追加登记行 |
| DeepSeek Harness | `deepseek-harness/instructions.append.md` + `skills/fist-mbt/` | 追加进 `~/.deepseek/instructions.md` |
| Claude | `claude/.claude-plugin/*.json` + `.mcp.json` + `skills/` | marketplace add |

- 生成：`python scripts/gen_plugins.py`
- 守卫（cl7）：`python scripts/check_plugin_sync.py`——重跑生成器到临时区再逐字节 diff，
  手改插件、忘重生成、数字漂移都会红。
- 当前投影：{vals['TOOL_COUNT']} 工具 / v{vals['VERSION']} / 缺陷账本 {vals['LEDGER_SUMMARY']}
""",
    )


def tree_digest(base: Path) -> dict:
    out = {}
    for p in sorted(base.rglob("*")):
        if p.is_file():
            out[str(p.relative_to(base))] = p.read_bytes()
    return out


def is_source(path_key: str) -> bool:
    """plugins/source/ 是人手维护的真源，不参与投影 diff。"""
    parts = Path(path_key).parts
    return bool(parts) and parts[0] == "source"


def comparable(base: Path) -> dict:
    return {k: v for k, v in tree_digest(base).items() if not is_source(k)}


def main() -> int:
    check = "--check" in sys.argv
    vals = measure()
    if check:
        tmp = Path(tempfile.mkdtemp(prefix="fist_plugins_"))
        try:
            generate(tmp, vals)
            cur = comparable(ROOT / "plugins")
            new = comparable(tmp)
            drift = sorted(k for k in set(cur) | set(new) if cur.get(k) != new.get(k))
            if drift:
                print(f"FAIL 插件态漂移（{len(drift)} 个文件与真源投影不一致）：")
                for k in drift:
                    if k not in cur:
                        why = "缺失（真源已生成，插件目录里没有）"
                    elif k not in new:
                        why = "多余（插件目录里有手写残留，真源已不生成）"
                    else:
                        why = "内容不一致"
                    print("  - " + k + "：" + why)
                return 1
            print(f"OK 插件态与真源一致（{vals['TOOL_COUNT']} 工具 / v{vals['VERSION']}）")
            return 0
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    target = ROOT / "plugins"
    for host in ("atomcode", "codearts", "deepseek-harness", "claude"):
        d = target / host
        if d.exists():
            shutil.rmtree(d)
    generate(target, vals)
    print(
        f"OK 已生成四宿主插件态：{vals['TOOL_COUNT']} 工具 / v{vals['VERSION']} / "
        f"{vals['LEDGER_SUMMARY']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
