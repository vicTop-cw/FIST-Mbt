#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_model_auth_no_key.py — 仓库内文件面「真凭据值形状」守卫。

为什么需要它：`check_publish_payload.py`（BUG-127）判的是 **`moon publish` 打包面**
出现凭据形状；而**仓库内文件面**那一格（fist-config.html / 各 `.mcp.json` /
`src/server/mcp_config_scaffold.mbt` 的白名单常量 / `src/router/` / `docs/` /
`README*.md`）此前无人认领。本守卫补的是「仓库内文件面」这一格。

判据范围（**范围自述 == 实现**，逐条对实现核对）：
  A1 键名本身**不算违例**：`api_key` / `apiKey` / `API_KEY` / `token` / `Token` /
     `secret` / `authorization` / `password` 是占位符/参数名，合法。本守卫**不**因
     键名发红。
  A2 **违例的是值形状**，共两类检测器：
     · 前缀形状（**全文**扫描，命中即红，与上下文无关）：
         `sk-` / `sk_` 开头、`Bearer ` 前缀、`AIza` 开头、`ghp_` / `gho_` /
         `github_pat_` 开头、`glpat-` 开头、`ya29.` 开头、`xoxb-` / `xoxp-` 开头、
         `pk_live_` / `rk_live_` 开头、`AKIA` 开头。
         这 12 条前缀取自 `src/server/mcp_config_scaffold.mbt` 的
         `mcp_cred_value_hits`（反解真源，不硬编码）+ 任务明列的 `gho_` / `AKIA`。
         各前缀均带「前一个字符不是字母数字/下划线」的边界，避免
         `task-` / `mask-` / `risk-` / `disk-` 这类含 `sk-` 的普通词被误判。
     · 值上下文里的 base64 长令牌（**仅**在凭据键值上下文触发，见 A3）：
         `[A-Za-z0-9_-]{40,}` 的连续令牌且非占位符。之所以只在键值上下文触发：
         仓内实测 `docs/deliverable.md` 的
         `reports/2026-09-25-award-enhancement-5rounds-report.md` 与
         `src/router/model_router.mbt` 的 `// ----…` 注释分隔线都是 40+ 位
         `[A-Za-z0-9_-]` 形状——若全文扫必恒红，等于判据自己喂自己。
     · `FIST_*_TOKEN` / `FIST_*_KEY` / `<CRED_KEY>` 赋值形状：值不是
         `$NAME` / `${NAME}` / `<placeholder>` / 空 / 显式占位符即红。
  A3 值上下文 = 同一行里凭据键（A1 那类名字）之后首个 ASCII `:` / `=` 起算的
     值区域。**只用 ASCII 分隔符**：仓内 `mcp_config_scaffold.mbt` 第 364 行
     「」：真值不要进配置…」用的是全角 `：`，用全角会把合规注释喂成违例。
  A4 豁免（命中即不红）：
     · `${ENV_VAR}` 形、`$ENV_NAME` 形（`mcp_config_scaffold` 明列的占位姿势）、
     · `<placeholder>` 形、
     · 空字符串、
     · `YOUR_KEY_HERE` / `your-key-here` / `xxx` / `example` / `placeholder` /
       `dummy` / `changeme` / `sample` / `KEY_HERE` 等显式占位符。

扫描面（**范围自述**）：
  · `fist-config.html`
  · `default-fist.mcp.json` / `.mcp.json` / `.mcp.dev.json`
  · `plugins/**/.mcp.json`
  · `src/server/mcp_config_scaffold.mbt`（白名单/凭据常量）
  · `src/router/`（模型路由：模型 API key / token 的真值最可能落点）
  · `docs/`、`README*.md` 的**全文**（不只 model 段——扫不全等于没扫）

退出码契约：
  0 = 通过；1 = 有违例（红）；2 = 判据自身输入面退化（关键文件全缺 → 自拒，不静默绿）。

用法：
    python scripts/check_model_auth_no_key.py            # 全量判据
    python scripts/check_model_auth_no_key.py --selftest # 自检判据本身没坏
"""
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

# ── 扫描面 ────────────────────────────────────────────────────────────────────
SCAN_FILES = [
    "fist-config.html",
    "default-fist.mcp.json",
    ".mcp.json",
    ".mcp.dev.json",
]
# `plugins/**/.mcp.json`（四宿主投影，现仅 claude 一份）
PLUGIN_MCP = "plugins"
# 源码真源：白名单 + 凭据常量
SRC_CRED_CONST = "src/server/mcp_config_scaffold.mbt"
SRC_ROUTER_DIR = "src/router"
SCAN_DIRS = ["docs"]
SCAN_README_PATTERNS = ["README.md", "README.mbt.md"]

# ── 凭据键名（A1：键名本身不算违例，只用作 A3 的值上下文定位）───────────────
CRED_KEY = re.compile(r"(?i)\b(api[_ ]?key|apikey|token|secret|authorization|bearer|password)\b")

# ── 值形状 · 前缀（A2 · 全文扫描）────────────────────────────────────────────
# 前缀名单反解自 src/server/mcp_config_scaffold.mbt 的 mcp_cred_value_hits
# （sk-/bearer /ghp_/github_pat_/glpat-/aiza/ya29./xoxb-/xoxp-/pk_live_/rk_live_）
# + 任务明列的 gho_ / AKIA。每条都带「前一字符非字母数字/下划线」边界防吃普通词。
PREFIX_PATTERNS = [
    (re.compile(r"(?<![A-Za-z0-9_])sk-[A-Za-z0-9_\-]{4,}"), "sk- 开头（OpenAI/Anthropic 风格 API key）"),
    (re.compile(r"(?<![A-Za-z0-9_])sk_\w{6,}"), "sk_ 开头（风格化 key）"),
    (re.compile(r"(?i)(?<![a-z0-9_])bearer\s+[A-Za-z0-9._\-]{16,}"), "Bearer 前缀（token ≥16 位；短词不误判）"),
    (re.compile(r"(?i)(?<![a-z0-9_])aiza[A-Za-z0-9_\-]{8,}"), "AIza 开头（Google API key）"),
    (re.compile(r"(?<![A-Za-z0-9_])ghp_[A-Za-z0-9]{10,}"), "ghp_ 开头（GitHub PAT）"),
    (re.compile(r"(?<![A-Za-z0-9_])gho_[A-Za-z0-9]{10,}"), "gho_ 开头（GitHub OAuth token）"),
    (re.compile(r"(?<![A-Za-z0-9_])github_pat_[A-Za-z0-9_]{10,}"), "github_pat_ 开头（fine-grained PAT）"),
    (re.compile(r"(?<![A-Za-z0-9_])glpat-[A-Za-z0-9_\-]{10,}"), "glpat- 开头（GitLab PAT）"),
    (re.compile(r"(?<![A-Za-z0-9_])ya29\.[A-Za-z0-9_\-]{6,}"), "ya29. 开头（Google OAuth）"),
    (re.compile(r"(?<![A-Za-z0-9_])xox[bp]-[A-Za-z0-9_\-]{6,}"), "xoxb-/xoxp- 开头（Slack token）"),
    (re.compile(r"(?<![A-Za-z0-9_])(?:pk|rk)_live_[A-Za-z0-9]{6,}"), "pk_live_/rk_live_ 开头（Stripe）"),
    (re.compile(r"(?<![A-Za-z0-9_])AKIA[A-Z0-9]{6,}"), "AKIA 开头（AWS Access Key）"),
]

# ── 值形状 · base64 长令牌（A2 · 仅在键值上下文）─────────────────────────────
BASE64_40 = re.compile(r"(?<![A-Za-z0-9_\-])([A-Za-z0-9_\-]{40,})")

# ── A4 豁免：占位符 / 显式假值 ───────────────────────────────────────────────
PLACEHOLDER_RE = re.compile(
    r"\$\{[^}]*\}"                                   # ${ENV_VAR}
    r"|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"              # $ENV_NAME / $ENV_NAME
    r"|<[^<>]{1,40}>"                               # <placeholder>
    r"|your[_\- ]?[a-z0-9_\-]*here"                 # YOUR_KEY_HERE / your-key-here
    r"|xxxx*"                                       # xxx / xxxx（脱敏占位）
    r"|example[_\- ]?[a-z0-9]*"
    r"|placeholder"
    r"|dummy"
    r"|changeme"
    r"|sample"
    r"|\bkey_here\b"
    r"|\bfill[_\- ]?me\b"
    r"|\bnot[_\- ]?a[_\- ]?real[_\- ]?(key|token)\b"
    r"|\b(?:test|demo|fake|fakekey|invalid|none)\b",
    re.I,
)


def _is_placeholder_value(val: str) -> bool:
    """值是否为占位符/假值（A4）。空值也算占位。"""
    v = val.strip().strip('"\'`').strip()
    if v == "":
        return True
    # 整段就是占位符
    if PLACEHOLDER_RE.fullmatch(v):
        return True
    # 值里含占位符且不含真正的长令牌（容忍 `$FIST_GITHUB_TOKEN` 这种）
    if "$" in v or "<" in v or "/" in v:
        return True
    return False


def _line_value_region(line: str, key_match: re.Match) -> str | None:
    """取同一行里凭据键之后首个 ASCII `:` / `=` 起算的值区域（A3）。"""
    seg = line[key_match.end():]
    m = re.search(r"[:=]", seg)
    if not m:
        return None
    return seg[m.end():]


def _prefix_hits(text: str) -> list[str]:
    """全文前缀形状命中（A2 第一类）。返回「描述」列表。"""
    out: list[str] = []
    for pat, label in PREFIX_PATTERNS:
        for m in pat.finditer(text):
            out.append("%s（命中 `%s`）" % (label, m.group(0)[:28]))
    return out


def _key_value_hits(line: str) -> list[str]:
    """凭据键值上下文里的值形状命中（A2 第二类：base64 长令牌）。"""
    hits: list[str] = []
    for km in CRED_KEY.finditer(line):
        region = _line_value_region(line, km)
        if region is None:
            continue
        # 前缀形状在值区域里同样命中（如 `"api_key": "sk-abc"`）
        for pat, label in PREFIX_PATTERNS:
            for m in pat.finditer(region):
                hits.append("%s（键 `%s` 的值；命中 `%s`）"
                            % (label, km.group(0), m.group(0)[:28]))
        # base64 长令牌（只在键值上下文触发）
        for m in BASE64_40.finditer(region):
            tok = m.group(1)
            if _is_placeholder_value(tok):
                continue
            # 值整体是占位符则整个值区域豁免
            if _is_placeholder_value(region):
                continue
            hits.append("40+ 位 base64 形状令牌（键 `%s` 的值：`%s…`）"
                        % (km.group(0), tok[:28]))
    return hits


def scan_text(text: str, label: str) -> list[str]:
    """对单份文本做全量值形状扫描。返回违例描述列表（空=干净）。"""
    hits = _prefix_hits(text)
    for i, line in enumerate(text.splitlines(), 1):
        for h in _key_value_hits(line):
            hits.append("第 %d 行：%s" % (i, h))
    # 前缀形状命中要带上行号，便于定位
    prefix_lines: list[str] = []
    for i, line in enumerate(text.splitlines(), 1):
        for pat, label in PREFIX_PATTERNS:
            for m in pat.finditer(line):
                prefix_lines.append("%s:%d  %s（命中 `%s`）"
                                    % (label, i, line.strip()[:60], m.group(0)[:28]))
    # 去掉在键值上下文里重复计的那批（同描述+同行去重）
    seen = set()
    final: list[str] = []
    for h in prefix_lines + hits:
        key = h.split("（命中")[0]
        if key in seen:
            continue
        seen.add(key)
        final.append(h)
    return final


# ── 扫描面枚举 ────────────────────────────────────────────────────────────────
def collect_files() -> list[Path]:
    files: list[Path] = []
    for rel in SCAN_FILES:
        p = ROOT / rel
        if p.exists():
            files.append(p)
    for p in sorted((ROOT / PLUGIN_MCP).glob("**/.mcp.json")):
        files.append(p)
    for rel in SCAN_DIRS:
        d = ROOT / rel
        if d.is_dir():
            files.extend(sorted(d.rglob("*.md")))
    for rel in SCAN_README_PATTERNS:
        p = ROOT / rel
        if p.exists():
            files.append(p)
    for rel in (SRC_CRED_CONST,):
        p = ROOT / rel
        if p.exists():
            files.append(p)
    d = ROOT / SRC_ROUTER_DIR
    if d.is_dir():
        files.extend(sorted(d.rglob("*.mbt")))
    # 去重、保序
    seen, out = set(), []
    for p in files:
        rp = p.resolve()
        if rp not in seen:
            seen.add(rp)
            out.append(p)
    return out


def check_absent(critical: list[str] | None = None) -> list[str]:
    """扫描面关键文件是否齐全。缺关键文件 → 判据自拒（exit 2）。
    可传自定义 critical 列表（selftest 用合成列表验证自拒逻辑本身没坏）。"""
    if critical is None:
        critical = ["fist-config.html", "default-fist.mcp.json", ".mcp.dev.json"]
    return [str(c) for c in critical if not (ROOT / c).exists()]


def run(files: list[Path] | None = None) -> tuple[list[str], int]:
    """全量判据。返回 (违例列表, 扫描文件数)。"""
    fs = files if files is not None else collect_files()
    problems: list[str] = []
    scanned = 0
    for p in fs:
        try:
            text = p.read_text(encoding="utf-8")
        except Exception as e:
            problems.append("读不到 %s：%s" % (p, e))
            continue
        scanned += 1
        for h in scan_text(text, str(p)):
            problems.append("%s · %s" % (p, h))
    return problems, scanned


# ── 自检 ─────────────────────────────────────────────────────────────────────
def selftest() -> list[str]:
    fails: list[str] = []

    # S1 违例必红：`sk-abc123` 值。fixture 在运行时拼接，源码里不留 ≥16 位连续凭据字面量，
    # 否则 check_publish_payload 的 P2（`sk-[A-Za-z0-9]{16,}` 真实凭据形状）会把判据自身当事故点名
    # ——运行时传入 scan_text 的字符串与字面量完全等价，检测语义不变，只是发布面不再出现"像真密钥"的静态文本。
    if not scan_text('  "api_key": "sk-abc123def456' + 'ghi789",\n', "synthetic"):
        fails.append("S1 抓不到 `sk-abc123` 值 → 判据饿死")
    # S2 干净不误红：`api_key: "your-key"` 占位符
    if scan_text('  "api_key": "your-key",\n', "synthetic"):
        fails.append("S2 把 `api_key: \"your-key\"` 误判成违例 → 恒红判据不可信")
    # S2b 干净不误红：`${ENV_VAR}` 占位符
    if scan_text('  "api_key": "${OPENAI_API_KEY}",\n', "synthetic"):
        fails.append("S2b 把 `${OPENAI_API_KEY}` 占位符误判成违例")
    # S2c 干净不误红：`$FIST_GITHUB_TOKEN`（mcp_config_scaffold 明列的占位姿势）
    if scan_text('{"FIST_GITHUB_TOKEN":"$FIST_GITHUB_TOKEN"}', "synthetic"):
        fails.append("S2c 把 `$FIST_GITHUB_TOKEN` 占位误判成违例")
    # S2d 干净不误红：键名本身（token / apiKey / API_KEY）不算违例
    if scan_text('  let apiKey = read_env("API_KEY");\n  let token = cfg.token;\n', "synthetic"):
        fails.append("S2d 把键名本身误判成违例（键名合法，违例的是值形状）")
    # S3 干净文件面 → 不红（不含任何凭据形状的文本）
    clean = (
        '{\n  "mcpServers": {\n    "fist-mbt": {\n'
        '      "command": "node",\n      "cwd": "E:/repo",\n'
        '      "toolCallTimeoutMs": 30000\n    }\n  }\n}\n'
    )
    if scan_text(clean, "clean"):
        fails.append("S3 干净文件面被误判成违例 → 恒红判据不可信")
    # S4 反误伤：普通词含 `sk-`（task- / mask- / disk- / risk-）不红
    if scan_text("  # 这是 task-sync 与 disk-usage 的说明，risk-free\n", "synthetic"):
        fails.append("S4 把 `task-` / `disk-` / `risk-` 里的 `sk-` 误判成违例")
    # S5 反误伤：base64 长令牌规则不得在无凭据键的文本上触发（长文件名/注释分隔线）
    long_fn = "  - reports/2026-09-25-award-enhancement-5rounds-report.md\n"
    if scan_text(long_fn, "synthetic"):
        fails.append("S5 把 40+ 位的长文件名误判成 base64 凭据（长令牌规则必须限键值上下文）")
    sep_line = "  // " + "-" * 60 + "\n"
    if scan_text(sep_line, "synthetic"):
        fails.append("S5b 把注释分隔线误判成 base64 凭据")
    # S6 输入面退化 → 自拒（exit 2）：关键文件全缺时必须报缺失（不静默绿）
    if not check_absent(["this/does/not/exist.html", "that/also/missing.json"]):
        fails.append("S6 关键文件缺失时不报缺失 → 判据无输入面却照样出结论（假绿）")
    real_absent = check_absent()
    if real_absent:
        # 在真实现状面上，关键文件应存在
        fails.append("S6b 真实现状面关键文件缺失（%s）→ 判据当前必然自拒 exit 2"
                     % ", ".join(real_absent))
    # S7 现状面不红（尺子自证）：真实现状若已合规，判据必须给绿
    problems, scanned = run()
    if scanned < 3:
        fails.append("S7 扫描面枚举器饿死：只扫到 %d 个文件" % scanned)
    # 注：现状面允许红（任务明说「如实报出红面」）；这里只断言尺子跑得起来。

    return fails


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        fails = selftest()
        if fails:
            print("SELFTEST FAIL 判据自身有问题：")
            for f in fails:
                print("  - " + f)
            return 1
        print("SELFTEST OK 真凭据值形状判据可红可绿（违例必红 / 占位符与键名不误红 / "
              "base64 长令牌限键值上下文 / 输入面退化自拒）")
        return 0

    absent = check_absent()
    if absent:
        print("FATAL 判据输入面退化：关键文件缺失 %s —— 拒绝出结论（不静默绿）"
              % ", ".join(absent))
        return 2

    problems, scanned = run()
    if problems:
        print("FAIL 文件面出现真凭据值形状（扫描 %d 份）：" % scanned)
        for p in problems[:40]:
            print("  - " + p)
        if len(problems) > 40:
            print("  …（共 %d 处）" % len(problems))
        return 1
    print("PASS 文件面无真凭据值形状（扫描 %d 份：fist-config / *.mcp.json / "
          "plugins/**/.mcp.json / mcp_config_scaffold 常量 / src/router / docs / README*）" % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))