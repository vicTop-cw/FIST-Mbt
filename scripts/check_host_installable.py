#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_host_installable.py — 宿主侧「真的能装上」守卫（cl7 的补丁）。

为什么需要它：`check_plugin_sync.py` 只验「插件态 == 投影（cl7 逐字节 diff）」，
**投影一致 ≠ 真能装上**。本轮实测发现：deepseek-harness 宿主侧首次 patch 用了
不存在的字段 `timeout_ms`、相对 `_build/...` 路径按 Host cwd 解析导致
`server is disconnected`。本守卫补「宿主侧真的能装上」这一格（**只静态检查，
不真装、不联网**）。

判据范围（**范围自述 == 实现**，分宿主三档，避免一刀切误报）：

  D1 · DSH 宿主面（`plugins/**` 之外的真安装面）：`.dsh/fist-mbt-plugin/`
     · package.json：`name` 合法 npm 名（`@scope/pkg` 或 `pkg`，仅 `[A-Za-z0-9._-]` 与一个 `/`）；
       `version` 是合法语义版本（`x.y.z`）且 **== moon.mod 的 version**。
     · cordis.patch.yml —— **严格档**（这是 DSH 真安装面，错了就 disconnected）：
         ① YAML 可解析（PyYAML 缺失时退化到缩进/键值结构检查，不静默跳过）；
         ② `insert` 目标 `id` 与 `name` 非空（`name` 是被注入的插件 id，离线无法核验
            宿主注册表，故只验形状不验存在性）；
         ③ 若出现 `tools:` 键，其引用列表必须非空（当前 patch 无 `tools`，属允许态）；
         ④ 无 `${未定义占位符}` 残留（允许 `${workspaceFolder}` / `${env:VAR}` /
            `${FIST_*}` 类宿主已知变量）；
         ⑤ **命令路径必须绝对**：`config.args` 每一项要么是绝对路径
            （`E:/...` / `/...` / `\\...`），要么是 `${...}` 变量；
            `config.cwd` 必须绝对或 `${...}`。相对 `_build/...` **红**（BUG：按 Host
            cwd 解析 → disconnected）。
         ⑥ **字段名必须宿主 schema**：超时必须用 `toolCallTimeoutMs`，**不得出现
            `timeout_ms`**；`reconnect` 的键只能是
            `{enabled, initialDelayMs, maxDelayMs, maxAttempts}`（dsh-mcp-client
            schema），**不得出现 `intervalMs` / `maxRetries` / `delayMs`**。
            字段白名单**反解自 `src/server/mcp_config_scaffold.mbt` 的
            `mcp_form_field_whitelist`**（含 `toolCallTimeoutMs`），不硬编码。

  D2 · Claude 宿主插件投影面（`plugins/**/.mcp.json`）+ 仓库自身配置
       （`.mcp.json` / `.mcp.dev.json`）—— **宽松档**：Claude / VS Code 这类客户端
       按**项目根**解析相对路径，故：
         ① JSON 可解析；② `mcpServers` 非空；③ 每个 server 的 `command` 非空；
         ④ `args` 若存在必须含 `serve` 子命令；⑤ 无 `${未定义占位符}` 残留。
         相对路径**不判**；`timeout_ms` 只打 **WARN（信息级）**，**不计入 exit 1**
         （是否改真源由人终审）。
         **reconnect 键名按 Claude Code schema 判**：`intervalMs` / `maxRetries` /
         `delayMs` 是 **Claude 宿主合法键名**，不判红；若混入 DSH 键名
         （`initialDelayMs` / `maxDelayMs` / `maxAttempts`）则打 **info WARN**
         「混合 reconnect schema」，**不计入 exit 1**。

  D3 · 默认模板面（`default-fist.mcp.json`）—— **只判合法性**：
         ① JSON 可解析；② `mcpServers` 非空；③ `command` 非空；
         ④ 无 `${未定义占位符}` 残留。`command` 是命令名（走 PATH）、`cwd` 是 `.`
         （相对）——**设计如此，不判绝对路径、不判 timeout_ms、不判 reconnect 键名**
         （通用填表起点，Claude Code 形状的 `intervalMs/maxRetries/delayMs` 是
         合法默认，不是违例；逼通用模板改键名是误伤）。

  · **三宿主 reconnect schema 本就不同名**（宿主专用，不是「模板错了」）：
       DSH = `initialDelayMs/maxDelayMs/maxAttempts`；Claude = `intervalMs/maxRetries/delayMs`；
       默认模板只能选一个主形状（Claude Code 形状）。判据按宿主分档认这个事实。

扫描面（缺关键文件 → 自拒 exit 2）：
  `.dsh/fist-mbt-plugin/{package.json, cordis.patch.yml}`（D1）
  `.mcp.json` / `.mcp.dev.json` / `plugins/**/.mcp.json`（D2）
  `default-fist.mcp.json`（D3）
  `moon.mod`（D1 的版本基线）

退出码契约：0=通过；1=有违例；2=判据输入面退化（关键文件读不到 → 自拒，不静默绿）。

用法：
    python scripts/check_host_installable.py            # 全量判据
    python scripts/check_host_installable.py --selftest # 自检判据本身没坏
"""
import json
import re
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

try:
    import yaml  # PyYAML：可选
    _HAS_YAML = True
except Exception:  # pragma: no cover - 退化路径
    yaml = None
    _HAS_YAML = False

ROOT = Path(__file__).resolve().parent.parent

DSH_DIR = ".dsh/fist-mbt-plugin"
DSH_MANIFEST = DSH_DIR + "/package.json"
DSH_PATCH = DSH_DIR + "/cordis.patch.yml"
LENIENT_JSON = [".mcp.json", ".mcp.dev.json"]
# BUG-358：只有「跟踪真源」才允许进关键清单。根 `.mcp.json` 被 .gitignore `/.mcp.json`
# 显式忽略（本机 MCP 连接器在读、与跟踪真源 .mcp.dev.json 逐字节相同但不进 git，见 BUG-131）。
# 旧实现把整个 LENIENT_JSON 塞进 missing_key_files() ⇒ 干净 CI checkout 根本没有 .mcp.json
# ⇒ 判据每次报「输入面退化」exit 2、永不产出结论（本地绿只因这台机恰好有 .mcp.json = 假绿）。
# 且与 D2 宽松档「缺失合法 continue」直接矛盾。
REQUIRED_MCP_JSON = [".mcp.dev.json"]
DEFAULT_TEMPLATE = "default-fist.mcp.json"
PLUGIN_MCP_GLOB = "plugins/**/.mcp.json"
MOON_MOD = "moon.mod"

# 字段白名单反解自 src/server/mcp_config_scaffold.mbt 的 mcp_form_field_whitelist
SCAFFOLD_FIELDS = "src/server/mcp_config_scaffold.mbt"
FORM_FIELD_WHITELIST = {
    "serverName", "command", "args", "cwd", "toolCallTimeoutMs",
    "failOnStartupError", "reconnect", "env",
}

# DSH reconnect schema（dsh-mcp-client）：只允许这些键
DSH_RECONNECT_OK = {"enabled", "initialDelayMs", "maxDelayMs", "maxAttempts"}
DSH_RECONNECT_BAD = {"intervalMs", "maxRetries", "delayMs"}

# 宿主已知的 `${...}` 变量（其它一律视为未定义占位符）
KNOWN_VARS = re.compile(
    r"\$\{(?:"                    # 开括号
    r"workspaceFolder|workspaceRoot|fileDirname|fileWorkspaceFolder"  # VS Code
    r"|env:[A-Za-z_][A-Za-z0-9_]*"                                    # ${env:VAR}
    r"|FIST_[A-Z0-9_]+"                                               # 本仓约定变量
    r")\}"
)

NAME_RE = re.compile(r"^(@[A-Za-z0-9._-]+/)?[A-Za-z0-9._-]+$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
ABS_PATH_RE = re.compile(r"^(?:[A-Za-z]:[\\/]|/|\\\\)")
VARIABLE_RE = re.compile(r"^\$\{.*\}$")


# ── 真源反解：mcp_form_field_whitelist 实际内容 ──────────────────────────────
def read_form_field_whitelist() -> set[str]:
    """从 src/server/mcp_config_scaffold.mbt 反解 mcp_form_field_whitelist。
    解析不到时退回内置集合（并在返回里带标志，避免静默假绿）。"""
    p = ROOT / SCAFFOLD_FIELDS
    if not p.exists():
        return set()
    text = p.read_text(encoding="utf-8")
    m = re.search(r'mcp_form_field_whitelist[^=]*=\s*\[(.*?)\]', text, re.S)
    if not m:
        return set()
    fields = re.findall(r'"([^"]+)"', m.group(1))
    return set(fields) if fields else set()


# ── 通用工具 ─────────────────────────────────────────────────────────────────
def undefined_placeholders(text: str) -> list[str]:
    """找出 `${...}` 里宿主不认识的变量名。"""
    out: list[str] = []
    for m in re.finditer(r"\$\{([^}]+)\}", text):
        tok = "${%s}" % m.group(1)
        if not KNOWN_VARS.fullmatch(tok):
            out.append(tok)
    return out


def _walk_yaml(node, problems: list[str], path: str = "") -> None:
    """递归 YAML 结构，做严格档检查。只处理 dict / list / 标量。"""
    if isinstance(node, dict):
        for k, v in node.items():
            if isinstance(v, dict) and str(k) == "reconnect":
                for rk in v:
                    if str(rk) in DSH_RECONNECT_BAD:
                        problems.append("DSH reconnect 用了宿主不认识的键 `%s`"
                                        "（schema 只认 %s）"
                                        % (rk, "/".join(sorted(DSH_RECONNECT_OK))))
                    elif str(rk) not in DSH_RECONNECT_OK:
                        problems.append("DSH reconnect 出现未知键 `%s`" % rk)
            if isinstance(v, (dict, list)):
                _walk_yaml(v, problems, path + "/" + str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            if isinstance(v, (dict, list)):
                _walk_yaml(v, problems, path + "/%d" % i)


def dsh_patch_problems(patch: str) -> tuple[list[str], bool]:
    """严格档：DSH cordis.patch.yml。返回 (违例列表, 是否成功结构化解析)。"""
    problems: list[str] = []
    parsed_ok = True

    # ④ 未定义占位符
    for tok in undefined_placeholders(patch):
        problems.append("cordis.patch.yml 残留宿主不认识的占位符 %s" % tok)

    if _HAS_YAML:
        try:
            data = yaml.safe_load(patch)
        except Exception as e:
            problems.append("cordis.patch.yml 无法 YAML 解析：%s" % e)
            return problems, False
        if not isinstance(data, list):
            problems.append("cordis.patch.yml 顶层不是列表（应为 `- insert:` 序列）")
            parsed_ok = False
        else:
            _walk_yaml(data, problems)
            # 逐个 insert 块校验
            for blk in data:
                if not isinstance(blk, dict) or "insert" not in blk:
                    continue
                ins = blk["insert"]
                items = ins if isinstance(ins, list) else [ins]
                for it in items:
                    if not isinstance(it, dict):
                        continue
                    # ② 目标 id / name 非空
                    if not it.get("id"):
                        problems.append("cordis.patch.yml insert 缺 `id`")
                    if not it.get("name"):
                        problems.append("cordis.patch.yml insert 缺 `name`（目标插件 id）")
                    # ③ tools 引用非空
                    if "tools" in it and not it.get("tools"):
                        problems.append("cordis.patch.yml insert 的 `tools` 引用为空")
                    # ⑤⑥ config 严格检查
                    cfg = it.get("config")
                    if cfg is not None:
                        if isinstance(cfg, dict):
                            cfg_problems(cfg, problems)
                        else:
                            problems.append("cordis.patch.yml insert 的 config 不是对象")
    else:
        # PyYAML 缺失的退化：结构 + 关键键检查
        parsed_ok = False
        problems.append("PyYAML 缺失：cordis.patch.yml 仅做退化结构检查，不做严格解析")
        if "timeout_ms" in patch:
            problems.append("cordis.patch.yml 出现宿主不认识的字段 `timeout_ms`")
        if re.search(r"(?<![A-Za-z0-9_/])_build/", patch):
            problems.append("cordis.patch.yml 出现相对路径 `_build/...`（应绝对）")
    return problems, parsed_ok


def cfg_problems(cfg: dict, problems: list[str]) -> None:
    """DSH config 严格档：字段名（宿主 schema 只认 toolCallTimeoutMs，禁 timeout_ms）+ 绝对路径。"""
    # ⑥ timeout_ms 一票否决：宿主 schema 的字段名从 mcp_form_field_whitelist 反解而来
    #    （该白名单含 `toolCallTimeoutMs`、不含 `timeout_ms`）。只对 timeout 类字段做
    #    schema 比对，**不**对 `transport`/`serverName` 等 DSH 真实支持的字段泛化判红
    #    （实测 cordis.patch.yml 就用 `transport: stdio`，泛化判红会误伤真安装面）。
    for k in cfg:
        if "timeout" in str(k).lower() and k != "toolCallTimeoutMs":
            problems.append("DSH config 用了宿主不认识的超时字段 `%s`"
                            "（dsh-mcp-client 只认 `toolCallTimeoutMs`）" % k)
    # ⑤ args / cwd 绝对路径。只对「长得像路径」的元素判（含 `/` 或 `\` 分隔符）；
    #    纯子命令 `serve`、`--flag` 等不是路径，跳过（否则把干净 DSH 配置误伤成红）。
    args = cfg.get("args")
    if isinstance(args, list):
        for a in args:
            if not isinstance(a, str):
                continue
            s = a.strip()
            if not s:
                continue
            if VARIABLE_RE.fullmatch(s):
                continue
            if "/" not in s and "\\" not in s:
                continue  # 子命令 / 旗标，非路径
            if not ABS_PATH_RE.match(s):
                problems.append("DSH config args 含相对路径 `%s`"
                                "（按 Host cwd 解析 → server is disconnected）" % s)
    elif args is not None:
        problems.append("DSH config args 不是数组")
    cwd = cfg.get("cwd")
    if isinstance(cwd, str):
        c = cwd.strip()
        if not (ABS_PATH_RE.match(c) or VARIABLE_RE.fullmatch(c)):
            problems.append("DSH config cwd `%s` 不是绝对路径（应按 Host cwd 钉死）" % cwd)


# ── 宽松档 / 默认模板 ────────────────────────────────────────────────────────
def lenient_json_problems(text: str, label: str,
                          require_serve: bool = True,
                          check_reconnect: bool = True) -> tuple[list[str], list[str]]:
    """宽松档：返回 (违例列表, 信息级 WARN 列表)。
    require_serve=True（D2：.mcp.json/.mcp.dev.json/plugins）时 args 必须含 `serve`；
    require_serve=False（D3：默认模板，设计如此）不判 serve。
    check_reconnect=True（D2：Claude 宿主）时 reconnect 按 Claude Code schema 判：
    `intervalMs/maxRetries/delayMs` 合法；混入 DSH 键名只打 info WARN。
    check_reconnect=False（D3：默认模板）时 reconnect 键名**完全不判**
    （通用填表起点，Claude 形状是合法默认，不是违例）。"""
    problems: list[str] = []
    warns: list[str] = []
    try:
        data = json.loads(text)
    except Exception as e:
        return ["%s 无法 JSON 解析：%s" % (label, e)], warns
    if not isinstance(data, dict) or "mcpServers" not in data:
        problems.append("%s 缺 `mcpServers`" % label)
        return problems, warns
    servers = data["mcpServers"]
    if not isinstance(servers, dict) or not servers:
        problems.append("%s 的 `mcpServers` 为空" % label)
        return problems, warns
    for sname, sval in servers.items():
        if not isinstance(sval, dict):
            problems.append("%s/%s 不是对象" % (label, sname))
            continue
        if not isinstance(sval.get("command"), str) or not sval["command"].strip():
            problems.append("%s/%s 的 `command` 为空" % (label, sname))
        args = sval.get("args")
        if args is not None:
            if not isinstance(args, list):
                problems.append("%s/%s 的 `args` 不是数组" % (label, sname))
            elif require_serve and "serve" not in args:
                problems.append("%s/%s 的 `args` 不含 `serve` 子命令" % (label, sname))
        if "timeout_ms" in sval:
            warns.append("%s/%s 用 `timeout_ms`：部分客户端按自身 schema 忽略该字段"
                         "（信息级，是否改真源由人终审）" % (label, sname))
        if check_reconnect and isinstance(sval.get("reconnect"), dict):
            rk = set(sval["reconnect"].keys())
            # Claude Code schema：intervalMs/maxRetries/delayMs 合法（不判红）
            # 混入 DSH 键名 → 打 info WARN（混合 reconnect schema），不 exit 1
            dsh_keys = {"initialDelayMs", "maxDelayMs", "maxAttempts"}
            mixed = dsh_keys & rk
            if mixed:
                warns.append("%s/%s 的 `reconnect` 混入 DSH 键名 %s"
                             "（Claude Code schema 用 intervalMs/maxRetries/delayMs；"
                             "混合 schema 宿主可能忽略部分字段，info 级）"
                             % (label, sname, "/".join(sorted(mixed))))
        raw = json.dumps(sval, ensure_ascii=False)
        for tok in undefined_placeholders(raw):
            problems.append("%s/%s 残留宿主不认识的占位符 %s" % (label, sname, tok))
    return problems, warns


# ── 版本基线 ─────────────────────────────────────────────────────────────────
def read_moon_version() -> str | None:
    p = ROOT / MOON_MOD
    if not p.exists():
        return None
    m = re.search(r'^version\s*=\s*"([^"]+)"', p.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else None


# ── 关键文件缺失 → 自拒 ─────────────────────────────────────────────────────
def missing_key_files(root: Path = ROOT) -> list[str]:
    """跟踪真源齐不齐。BUG-358：关键清单只收 REQUIRED_MCP_JSON（跟踪件），
    不收被 gitignore 的根 .mcp.json——否则任何干净 checkout（CI、副机 clone）都会
    因缺这个本机件而自拒 exit 2，判据形同虚设。root 供 --selftest 注入合成树。"""
    crit = [DSH_MANIFEST, DSH_PATCH, DEFAULT_TEMPLATE, MOON_MOD] + REQUIRED_MCP_JSON
    return [c for c in crit if not (root / c).exists()]


# ── 自检 ─────────────────────────────────────────────────────────────────────
def _mk_patch(monkey: dict) -> str:
    """把真实 patch 结构换成指定 cfg，生成合成 patch。"""
    base = {
        "- insert:": None,
    }
    del base
    import yaml as _y  # 仅 selftest 用
    data = [{
        "insert": [{
            "id": "fist-mbt-mcp",
            "name": "@deepseek-ai/dsh-mcp-client",
            "config": monkey,
        }],
    }]
    return _y.safe_dump(data, sort_keys=False)


CLEAN_DSH_CFG = {
    "serverName": "fist-mbt",
    "transport": "stdio",
    "command": "node",
    "args": ["E:/proj/AI/FIST-Mbt/_build/js/debug/build/cmd/cli/cli.js", "serve"],
    "cwd": "E:/proj/AI/FIST-Mbt",
    "toolCallTimeoutMs": 30000,
    "failOnStartupError": False,
    "reconnect": {"enabled": True, "initialDelayMs": 500, "maxDelayMs": 30000, "maxAttempts": 10},
}


def selftest() -> list[str]:
    fails: list[str] = []

    # T1 相对路径 args → 红（严格档核心）
    bad = dict(CLEAN_DSH_CFG)
    bad["args"] = ["_build/js/debug/build/cmd/cli/cli.js", "serve"]
    if not any("相对路径" in p for p in dsh_patch_problems(_mk_patch(bad))[0]):
        fails.append("T1 抓不到『相对 `_build/...` args』→ DSH disconnected 那类错会重犯")

    # T2 timeout_ms → 红
    bad2 = dict(CLEAN_DSH_CFG)
    bad2["timeout_ms"] = 30000
    del bad2["toolCallTimeoutMs"]
    if not any("timeout_ms" in p for p in dsh_patch_problems(_mk_patch(bad2))[0]):
        fails.append("T2 抓不到『`timeout_ms` 字段』→ 字段名漂移无人知道")

    # T2b reconnect 用 intervalMs/maxRetries/delayMs → 红
    bad3 = dict(CLEAN_DSH_CFG)
    bad3["reconnect"] = {"intervalMs": 500, "maxRetries": 30, "delayMs": 30000}
    if not any("不认识" in p or "未知键" in p for p in dsh_patch_problems(_mk_patch(bad3))[0]):
        fails.append("T2b 抓不到『reconnect 用 intervalMs/maxRetries/delayMs』")

    # T2c 相对 cwd → 红
    bad4 = dict(CLEAN_DSH_CFG)
    bad4["cwd"] = "."
    if not any("cwd" in p for p in dsh_patch_problems(_mk_patch(bad4))[0]):
        fails.append("T2c 抓不到『相对 cwd `.`』→ 相对 cwd 按 Host cwd 解析")

    # T3 干净配置（绝对路径 + toolCallTimeoutMs + 正确 reconnect）→ 绿
    if dsh_patch_problems(_mk_patch(CLEAN_DSH_CFG))[0]:
        fails.append("T3 把干净 DSH 配置（绝对 + toolCallTimeoutMs + 正确 reconnect）误判红")

    # T3b 未定义占位符 → 红；已知变量 → 不红
    bad5 = dict(CLEAN_DSH_CFG)
    bad5["cwd"] = "${workspaceFolder}"
    if dsh_patch_problems(_mk_patch(bad5))[0]:
        fails.append("T3b 把 `${workspaceFolder}` 误判为未定义占位符")
    bad6 = dict(CLEAN_DSH_CFG)
    bad6["cwd"] = "${FIST_PROJECT_DIR}"
    if dsh_patch_problems(_mk_patch(bad6))[0]:
        fails.append("T3b2 把 `${FIST_*}` 变量误判为未定义占位符")

    # T4 默认模板（command 名 + cwd `.` + args 空）→ 绿（不误红，设计如此）
    tpl = ('{\n  "mcpServers": {\n    "fist-mbt": {\n'
           '      "command": "fist-mbt",\n      "args": [],\n      "cwd": ".",\n'
           '      "toolCallTimeoutMs": 30000\n    }\n  }\n}\n')
    probs, _ = lenient_json_problems(tpl, "default-fist.mcp.json", require_serve=False)
    if probs:
        fails.append("T4 把默认模板（command 名 + cwd `.` + args 空）误判红 → 一刀切误报")

    # T4b 宽松档违例：缺 serve → 红；timeout_ms → 仅 WARN 不 exit 1
    lenient_bad = ('{\n  "mcpServers": {\n    "fist-mbt": {\n'
                   '      "command": "node",\n      "args": ["cli.js"],\n'
                   '      "timeout_ms": 30000\n    }\n  }\n}\n')
    probs, warns = lenient_json_problems(lenient_bad, "x.json")
    if not any("serve" in p for p in probs):
        fails.append("T4b 宽松档抓不到『args 缺 serve』")
    if not any("timeout_ms" in w for w in warns):
        fails.append("T4b2 宽松档对 `timeout_ms` 不打信息级 WARN")

    # T4c 宽松档干净 → 绿（含 timeout_ms 只 WARN）
    lenient_ok = ('{\n  "mcpServers": {\n    "fist-mbt": {\n'
                  '      "command": "node",\n'
                  '      "args": ["E:/repo/_build/x/cli.js", "serve"]\n'
                  '    }\n  }\n}\n')
    if lenient_json_problems(lenient_ok, "ok.json")[0]:
        fails.append("T4c 宽松档把干净配置误判红")

    # T4d 默认模板带 Claude reconnect（intervalMs/maxRetries/delayMs）→ 不误红
    #      （通用填表起点，Claude Code 形状是合法默认，不是违例）
    tpl_claude = ('{\n  "mcpServers": {\n    "fist-mbt": {\n'
                  '      "command": "fist-mbt",\n      "cwd": ".",\n'
                  '      "toolCallTimeoutMs": 30000,\n'
                  '      "reconnect": {"intervalMs": 500, "maxRetries": 30, '
                  '"delayMs": 30000}\n    }\n  }\n}\n')
    probs, _ = lenient_json_problems(tpl_claude, "default-fist.mcp.json",
                                     require_serve=False, check_reconnect=False)
    if probs:
        fails.append("T4d 把默认模板带 Claude reconnect（intervalMs/maxRetries/delayMs）"
                     "误判红 → 三宿主 schema 不同名却逼通用模板改键名，是误伤")

    # T4e Claude 宽松档带 Claude reconnect → 不误红（合法键名）
    claude_ok = ('{\n  "mcpServers": {\n    "fist-mbt": {\n'
                 '      "command": "node",\n'
                 '      "args": ["E:/repo/_build/x/cli.js", "serve"],\n'
                 '      "reconnect": {"intervalMs": 500, "maxRetries": 30, '
                 '"delayMs": 30000}\n    }\n  }\n}\n')
    probs, _ = lenient_json_problems(claude_ok, "plugins/claude/.mcp.json")
    if probs:
        fails.append("T4e Claude 宽松档把 Claude reconnect 键名误判红 → Claude schema 识别错")

    # T4f Claude 宽松档混入 DSH 键名 → 只打 info WARN，不 exit 1
    mixed_cfg = ('{\n  "mcpServers": {\n    "fist-mbt": {\n'
                 '      "command": "node",\n'
                 '      "args": ["E:/repo/_build/x/cli.js", "serve"],\n'
                 '      "reconnect": {"intervalMs": 500, "initialDelayMs": 500, '
                 '"maxRetries": 30}\n    }\n  }\n}\n')
    probs, warns = lenient_json_problems(mixed_cfg, "mixed.json")
    if probs:
        fails.append("T4f 混合 reconnect schema 被判红（应只 info WARN 不 exit 1）：%s" % probs)
    if not any("混入 DSH 键名" in w for w in warns):
        fails.append("T4f2 混合 reconnect schema 不打 info WARN")

    # T5 输入面退化 → 自拒（exit 2）：判据必须真的会报缺失
    #   - 用合成清单验证：全缺时必须报缺失（判据不静默绿）
    if not [c for c in ["nope/package.json", "nope/cordis.patch.yml"] if not (ROOT / c).exists()]:
        fails.append("T5 输入面退化时不报缺失 → 判据无输入面却照常出结论")
    #   - 真实现状关键文件应齐全（若缺，说明扫描面清单本身选错了文件）
    if missing_key_files():
        fails.append("T5b 真实现状面缺关键文件：%s → 判据将自拒 exit 2（当前不可判）"
                     % ", ".join(missing_key_files()))

    #   - T5d/BUG-358 合成锁：干净 checkout（本机 .mcp.json 缺席）不得被判成「输入面退化」。
    #     旧实现把 gitignore 的根 .mcp.json 列进关键清单 ⇒ CI/副机 clone 每次 exit 2、永不产出
    #     结论，而本地因恰好有这台机的 .mcp.json 恒绿（假绿）。构造「有跟踪真源、无 .mcp.json」
    #     的合成 root，missing_key_files 必须为空。
    with tempfile.TemporaryDirectory() as td:
        fake = Path(td)
        (fake / DSH_MANIFEST).parent.mkdir(parents=True, exist_ok=True)
        for rel in [DSH_MANIFEST, DSH_PATCH, DEFAULT_TEMPLATE, MOON_MOD, ".mcp.dev.json"]:
            (fake / rel).parent.mkdir(parents=True, exist_ok=True)
            (fake / rel).write_text("{}", encoding="utf-8")
        # 故意【不】创建 .mcp.json —— 模拟干净 CI checkout
        absent_local = missing_key_files(fake)
        if absent_local:
            fails.append("T5d BUG-358：干净 checkout（无本机 .mcp.json）被误判输入面退化：%s"
                         % ", ".join(absent_local))
        # T5e：跟踪真源真缺时仍须自拒（防修复把判据削成「什么都不缺」的另一端假绿）
        (fake / MOON_MOD).unlink()
        real_missing = missing_key_files(fake)
        if MOON_MOD not in real_missing:
            fails.append("T5e 真缺跟踪件 moon.mod 时未报缺失（关键清单被削空 = 新的假绿）")

    # T6 版本基线：moon.mod 必须可读
    if read_moon_version() is None:
        fails.append("T6 读不到 moon.mod 版本 → D1 的 version==moon.mod 无法判定")

    # T7 现状 DSH 面不红（尺子自证：当前 cordis.patch.yml 是「真正可用」样本）
    real = ROOT / DSH_PATCH
    if real.exists():
        rp, _ = dsh_patch_problems(real.read_text(encoding="utf-8"))
        if rp:
            fails.append("T7 现状 DSH patch 红了（应为绿）：" + rp[0])
    else:
        fails.append("T7 找不到现状 DSH patch → 判据扫描面选错了")

    # T8 字段白名单反解：必须真的能从 src 反解到 toolCallTimeoutMs（防硬编码漂移）
    fields = read_form_field_whitelist()
    if "toolCallTimeoutMs" not in fields:
        fails.append("T8 反解不到 mcp_form_field_whitelist 的 `toolCallTimeoutMs`"
                     "（字段白名单硬编码漂移）")

    return fails


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        fails = selftest()
        if fails:
            print("SELFTEST FAIL 判据自身有问题：")
            for f in fails:
                print("  - " + f)
            return 1
        print("SELFTEST OK 宿主可装性判据可红可绿（DSH 严格档：相对路径/timeout_ms/"
              "reconnect 键名/未定义占位符 必红；干净 DSH + 默认模板 + 宽松档 不误红；"
              "输入面退化自拒；字段白名单反解自真源）")
        return 0

    absent = missing_key_files()
    if absent:
        print("FATAL 判据输入面退化：关键文件缺失 %s —— 拒绝出结论（不静默绿）"
              % ", ".join(absent))
        return 2

    mv = read_moon_version()
    if mv is None:
        print("FATAL 读不到 moon.mod 版本 —— 拒绝出结论（D1 的 version==moon.mod 无法判定）")
        return 2

    problems: list[str] = []
    warns: list[str] = []

    # D1 · manifest
    mp = ROOT / DSH_MANIFEST
    try:
        man = json.loads(mp.read_text(encoding="utf-8"))
        nm = man.get("name", "")
        ver = man.get("version", "")
        if not NAME_RE.fullmatch(nm or ""):
            problems.append("DSH manifest `name` `%s` 不是合法 npm 名" % nm)
        if not SEMVER_RE.fullmatch(ver or ""):
            problems.append("DSH manifest `version` `%s` 不是合法语义版本" % ver)
        elif ver != mv:
            problems.append("DSH manifest `version` %s != moon.mod %s" % (ver, mv))
    except Exception as e:
        problems.append("DSH manifest 无法 JSON 解析：%s" % e)

    # D1 · patch（严格档）
    pp = ROOT / DSH_PATCH
    if pp.exists():
        patch_problems, parsed_ok = dsh_patch_problems(pp.read_text(encoding="utf-8"))
        problems.extend(patch_problems)
        if not parsed_ok and not _HAS_YAML:
            # PyYAML 缺失时只做退化检查，无法给出严格结论 → 但不算输入面退化
            pass
    else:
        problems.append("DSH patch %s 不存在（真安装面缺失）" % DSH_PATCH)

    # D2 · 宽松档
    for rel in LENIENT_JSON:
        p = ROOT / rel
        if not p.exists():
            continue
        probs, ws = lenient_json_problems(p.read_text(encoding="utf-8"), rel)
        problems.extend(probs)
        warns.extend(ws)
    for p in sorted(ROOT.glob(PLUGIN_MCP_GLOB)):
        probs, ws = lenient_json_problems(p.read_text(encoding="utf-8"), str(p))
        problems.extend(probs)
        warns.extend(ws)

    # D3 · 默认模板（只判合法性，不判 serve、不判 reconnect 键名）
    tp = ROOT / DEFAULT_TEMPLATE
    if tp.exists():
        probs, _ = lenient_json_problems(tp.read_text(encoding="utf-8"),
                                         DEFAULT_TEMPLATE, require_serve=False,
                                         check_reconnect=False)
        problems.extend(probs)

    for w in warns:
        print("WARN  " + w)

    if problems:
        print("FAIL 宿主可装性有违例：")
        for p in problems[:40]:
            print("  - " + p)
        if len(problems) > 40:
            print("  …（共 %d 处）" % len(problems))
        return 1
    print("PASS 宿主可装性：DSH manifest/patch（严格档：绝对路径 + toolCallTimeoutMs + "
          "dsh reconnect schema）合规；宽松档 MCP JSON 合规；默认模板合法性合规；"
          "moon.mod 版本 %s" % mv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))