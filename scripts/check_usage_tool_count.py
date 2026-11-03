#!/usr/bin/env python3
r"""check_usage_tool_count.py —— USAGE.md 工具面守卫（两段）：

**Part A（BUG-525）· 工具计数自述**：真源 = `scripts/_tool_registry.real_tools()`
（src/server/*.mbt 注册口径，与 check_tools_sync / mcp_smoke / check_doc_surface
同一实现，不在此抄第二份）。被检面：USAGE.md 里一切「N 个工具 / N 个 MCP 工具 /
N MCP 工具 / 工具 N 个」（含 `N+` 下限式）的散文计数自述：
  * 精确式（无 `+`）→ 必须等于真源计数；
  * 下限式（`N+`）→ 真源计数 ≥ N（下限超过实测 = 虚报，照样红）；
  * 整份 USAGE 一个计数自述都没有 → 红（守卫面失锚）。

**Part B（T0r12）· §6 参数列「工具名+参数名集」双向对表**：真源 = **tools/list 活体
schema**（自带采集逻辑：起 `node cli.js serve` 发一次 tools/list，起法与
scripts/mcp_smoke.py 同源 —— 必须带 serve、ESM require shim 幂等注入、
FIST_DB_PATH 默认改道 temp/ 隔离库（BUG-122）、不依赖 temp/ 下任何素材件）。
被检面：USAGE.md §6 的工具表行（形如 `| \`tool\` | 描述 | 参数列 |`，只解析表行；
散文段提到参数名不算）：
  * 表行工具不在活体 tools/list → 文档多写，红；
  * 表行参数名集 vs 活体 inputSchema.properties 双向 diff：文档多写必红、
    活体有而文档漏写必红（参数名抽取：`name(...)` 注解式，与 §6 现行排版一致）；
  * §6 散文反引号提及的活体工具却没有参数表行 → 红，**除非**在
    `WHITELIST_NO_ROW` 点名豁免（每条豁免必须带理由注释）；
  * 豁免条目过期（工具已有表行 / 已不在活体 / 已不被 §6 提及）→ 红，逼人清理白名单。

漂移即红，逼人在改工具 schema 的同一笔里改 USAGE —— T0r10 实测 b 类漂移
38 工具 62 处无人发现，根因就是参数列不在任何守卫面（J2 只比工具名）。

rc 契约：0=绿；1=漂移/失锚/豁免过期；2=自拒（读不到真源或 USAGE、或起不了活体
server 拿不到 tools/list —— 绝不报绿；活体采集失败先看是否 `moon build --target js cmd/cli`）。
参数面：argparse，未知旗标天生即拒。
--selftest：变异对照（Part A 四格 + Part B 八格：改坏一行表必红 + 干净现状不误红 +
豁免面双向 + §6 失锚；另加调用面自 spawn 格）。全部合成输入，不起 server，不碰真仓库。
"""

import argparse
import importlib.util as _ilu
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SCRIPT_DIR = Path(__file__).resolve().parent
USAGE_PATH = SCRIPT_DIR.parent / "USAGE.md"
REGISTRY_PATH = SCRIPT_DIR / "_tool_registry.py"
ROOT = str(SCRIPT_DIR.parent)

NODE = os.environ.get("FIST_NODE", "node")
# BUG-122：spawn serve 的脚本必须把 FIST_DB_PATH 交给子进程，否则演示行写进仓库根自举台账。
DB_PATH = os.path.join(ROOT, "temp", "check_usage_tool_count.db")
# 入口产物候选（与 scripts/mcp_smoke.py 同一份清单形状；check_entry_paths 会抓 argv 是否带 serve）。
MAIN_CANDIDATES = [
    "_build/js/debug/build/cmd/cli/cli.js",
    "target/js/release/build/cmd/cli/cli.js",
]
META = {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {"name": "usage-param-guard", "version": "1.0"},
}

# ════════════════════════════════════════════════════════════════════════
# Part A · 工具计数自述（BUG-525，原行为逐字保留）
# ════════════════════════════════════════════════════════════════════════

# 计数自述形状（与 check_tools_sync.RE_TOOL_CLAIM 同族，另加「N 个工具」通式，
# 因为 USAGE §5 写的是「182 个工具」不带 MCP）。数字前 lookbehind 拒绝紧贴
# 字母/数字/下划线/点的数字（标识符内数字 cl1/s1 不吃），真声明前恒为空格/标点/行首。
RE_CLAIM = re.compile(
    r"(?<![A-Za-z0-9_.])(\d+)(\+?)\s*个\s*(?:MCP\s*)?工具"
    r"|(?<![A-Za-z0-9_.])(\d+)(\+?)\s*MCP\s*工具"
    r"|工具\s*(?<![A-Za-z0-9_.])(\d+)(\+?)\s*个"
)


def real_tool_count():
    """真源计数：委托单一实现 _tool_registry.real_tools()。读不到 → None（自拒）。"""
    if not REGISTRY_PATH.is_file():
        return None
    try:
        spec = _ilu.spec_from_file_location("_usage_tool_registry", REGISTRY_PATH)
        mod = _ilu.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return len(mod.real_tools())
    except Exception:
        return None


def claims(text):
    """[(lineno, claimed, is_floor)] —— 从实现反解出的形状清单。"""
    out = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for m in RE_CLAIM.finditer(line):
            groups = [g for g in m.groups() if g is not None]
            digits, plus = groups[0], groups[1]
            out.append((lineno, int(digits), plus == "+"))
    return out


def check_counts(usage_text, real):
    """Part A：返回错误行列表（空 = 绿）。real 必须非 None。"""
    errs = []
    exact_seen = False
    for lineno, n, floor in claims(usage_text):
        if floor:
            if real < n:
                errs.append(f"USAGE.md:{lineno} 下限式虚报：写「{n}+」而真源只有 {real}")
        else:
            exact_seen = True
            if n != real:
                errs.append(f"USAGE.md:{lineno} 计数漂移：写 {n} 而真源是 {real}")
    if not exact_seen:
        errs.append("USAGE.md 整份没有任何精确计数自述 —— 守卫面失锚（BUG-525 形状）")
    return errs


# ════════════════════════════════════════════════════════════════════════
# Part B · §6 参数列「工具名+参数名集」双向对表（T0r12）
# ════════════════════════════════════════════════════════════════════════

# 豁免面（当前为空）：原 §6.15 五个模型路由工具（model_route / model_auth_status /
# model_router_status / model_router_reset / executor_run）的「只讲配置不排表行」豁免
# 已在五个工具补齐 §6.15 参数表行后清空（豁免过期三向自红机制保留，逼人清理）。
# 机制仍留作后续「§6 散文提及但无表行」的配置类工具的出口：每条豁免必须带理由；
# 豁免过期（工具有了表行 / 不在活体 / 不再被 §6 提及）会被判红逼人清理。
WHITELIST_NO_ROW = {}

RE_TOOL_CELL = re.compile(r"`?[a-z_][a-z0-9_]*`?")      # 表行首格（工具名，可带反引号）
RE_PARAM_REF = re.compile(r"([a-z_][a-z0-9_]*)\s*\(")   # 参数名注解式：name(必)/(选)/(选,默认x)


def section6_lines(text):
    """[(lineno, line)] —— §6 从 `## 6.` 到下一个 `## ` 标题（§6.x 子节不算边界）。
    找不到 §6 → None（守卫面失锚）。"""
    lines = text.splitlines()
    start = None
    for i, ln in enumerate(lines):
        if start is None:
            if re.match(r"^## 6\.", ln):
                start = i
        elif re.match(r"^## \d+\.", ln):
            return list(enumerate(lines[start:i], start + 1))
    if start is None:
        return None
    return list(enumerate(lines[start:], start + 1))


def parse_tool_rows(text):
    """§6 内的工具表行：{tool: [(params_cell, lineno), ...]}。
    只认 3 列且首格是裸标识符（可带反引号）的表行 —— 散文/其它 3 列表
    （首格带点、带空格、CJK）与权限矩阵（5 列）天然排除。"""
    rows = {}
    seg = section6_lines(text)
    if seg is None:
        return None
    for lineno, ln in seg:
        s = ln.strip()
        if not s.startswith("|"):
            continue
        # 先保护 \| 转义（如 executor_auction 描述列的 1-\|出价-…\|），再切列
        s2 = s.replace("\\|", "\x00")
        cells = [c.replace("\x00", "|").strip() for c in s2[1:].rstrip("|").split("|")]
        if len(cells) == 3 and RE_TOOL_CELL.fullmatch(cells[0]):
            rows.setdefault(cells[0].strip("`"), []).append((cells[2], lineno))
    return rows


def param_names(cell):
    """参数列 → 参数名集：只认 `name(...)` 注解式（§6 现行排版 100% 如此）。
    刻意不收裸标识符：说明词（JSON 数组/默认值/中文）会喂出假「多写」。"""
    return set(RE_PARAM_REF.findall(cell))


def mentioned_tools(text, known, row_line_numbers):
    """§6 非表行里以反引号提及的已知工具名（散文提及；表行自己那格不算）。"""
    out = set()
    for lineno, ln in section6_lines(text) or []:
        if lineno in row_line_numbers:
            continue
        for m in re.finditer(r"`([a-z_][a-z0-9_]*)`", ln):
            if m.group(1) in known:
                out.add(m.group(1))
    return out


def check_params(usage_text, live, whitelist=None):
    """Part B：usage 全文 × 活体 {tool: [param,...]} → 错误行列表（空 = 绿）。
    live 为 None 由调用方先自拒；whitelist 缺省用真仓 WHITELIST_NO_ROW。"""
    wl = WHITELIST_NO_ROW if whitelist is None else whitelist
    rows = parse_tool_rows(usage_text)
    if rows is None:
        return ["USAGE.md 找不到 §6（## 6. 起头的工具手册节）—— 参数列守卫面失锚"]
    errs = []
    # ① 表行工具 ↔ 活体：多写工具 / 参数名集双向 diff
    for tool, entries in sorted(rows.items()):
        for cell, lineno in entries:
            if tool not in live:
                errs.append(f"USAGE.md:{lineno} §6 表行工具 `{tool}` 不在活体 tools/list —— 文档多写")
                continue
            lp = set(live[tool])
            dp = param_names(cell)
            for p in sorted(dp - lp):
                errs.append(f"USAGE.md:{lineno} §6 `{tool}` 参数列多写 `{p}`（活体 schema 无此参数）")
            for p in sorted(lp - dp):
                errs.append(f"USAGE.md:{lineno} §6 `{tool}` 参数列漏写 `{p}`（活体 schema 有）")
    # ② §6 散文提及却无表行的活体工具：白名单外必红
    row_line_numbers = {lineno for entries in rows.values() for _, lineno in entries}
    mentioned = mentioned_tools(usage_text, set(live), row_line_numbers)
    no_row = mentioned - set(rows)
    for t in sorted(no_row):
        if t in wl:
            continue
        errs.append(
            f"§6 提及工具 `{t}`（散文反引号）但没有参数表行 —— 需补表行，"
            f"或进 WHITELIST_NO_ROW 点名豁免并带理由")
    # ③ 豁免过期（三向）：有表行了 / 不在活体了 / 不再被 §6 提及了
    for t, why in sorted(wl.items()):
        if t in rows:
            errs.append(f"WHITELIST_NO_ROW 条目 `{t}` 已有参数表行 —— 豁免过期，请清理白名单（原理由：{why}）")
        elif t not in live:
            errs.append(f"WHITELIST_NO_ROW 条目 `{t}` 不在活体 tools/list —— 豁免过期，请清理白名单")
        elif t not in mentioned:
            errs.append(f"WHITELIST_NO_ROW 条目 `{t}` 已不被 §6 散文提及 —— 豁免过期，请清理白名单")
    return errs


# ════════════════════════════════════════════════════════════════════════
# 活体采集（Part B 真源：自带，不依赖 temp/ 素材件）
# ════════════════════════════════════════════════════════════════════════

def find_main_js():
    for p in MAIN_CANDIDATES:
        if os.path.exists(os.path.join(ROOT, p)):
            return os.path.join(ROOT, p)
    return ""


def collect_live_schema():
    """起 `node cli.js serve` 发 tools/list → {tool: [param,...]}。
    任何一步失败 → None（调用方自拒 rc=2，绝不拿残缺面报绿）。"""
    main_js = find_main_js()
    if not main_js:
        return None
    try:
        # moonc ≥0.10.14 ESM × mizchi/sqlite CJS require → 注入 require shim（幂等，与 mcp_smoke 同源）
        spec = _ilu.spec_from_file_location(
            "patch_esm_main", str(SCRIPT_DIR / "patch_esm_main.py"))
        mod = _ilu.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.patch(main_js)
    except Exception:
        return None
    env = dict(os.environ)
    env.setdefault("FIST_DB_PATH", DB_PATH)
    try:
        proc = subprocess.Popen(
            [NODE, main_js, "serve"], cwd=ROOT, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", errors="replace", bufsize=1,
        )
    except OSError:
        return None
    try:
        req = {"jsonrpc": "2.0", "id": "1", "method": "tools/list", "params": {"_meta": META}}
        proc.stdin.write(json.dumps(req, ensure_ascii=False) + "\n")
        proc.stdin.flush()
        line = None
        for _ in range(100):  # 跳过启动横幅，直到出现 JSON 行
            line = proc.stdout.readline()
            if not line:
                break
            if line.strip().startswith("{"):
                break
        if not (line and line.strip().startswith("{")):
            return None
        resp = json.loads(line)
        tools = (resp.get("result") or {}).get("tools") or []
        if len(tools) < 100:  # 解析失效护栏（同 mcp_smoke：<100 视为活体不可信，不出假绿）
            return None
        out = {}
        for t in tools:
            schema = t.get("inputSchema") or {}
            out[t["name"]] = sorted((schema.get("properties") or {}).keys())
        return out
    except Exception:
        return None
    finally:
        try:
            proc.stdin.close()
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        except Exception:
            pass


# ════════════════════════════════════════════════════════════════════════
# 真跑 / 自检
# ════════════════════════════════════════════════════════════════════════

def run_real():
    real = real_tool_count()
    if real is None:
        print("FATAL 读不到工具注册真源（_tool_registry.real_tools()）——自拒不报绿", file=sys.stderr)
        return 2
    try:
        text = USAGE_PATH.read_text(encoding="utf-8")
    except OSError as e:
        print(f"FATAL 读不到 USAGE.md（{e}）——自拒不报绿", file=sys.stderr)
        return 2
    errs = check_counts(text, real)
    live = collect_live_schema()
    if live is None:
        print("FATAL 起不了活体 server / 拿不到 tools/list（先 `moon build --target js cmd/cli`；"
              "入口候选 %s）——自拒不报绿" % " / ".join(MAIN_CANDIDATES), file=sys.stderr)
        return 2
    errs += check_params(text, live)
    if errs:
        for e in errs:
            print(f"RED {e}")
        print(f"USAGE 工具面对表：真源计数 {real}，活体 {len(live)} 工具，{len(errs)} 处漂移/虚报/失锚/豁免过期")
        return 1
    n_rows = sum(len(v) for v in (parse_tool_rows(text) or {}).values())
    print(f"USAGE 工具面对表 PASS：真源计数 {real}；活体 {len(live)} 工具 × §6 表行 {n_rows} 行"
          f"参数名集零漂移；豁免 {len(WHITELIST_NO_ROW)} 条（§6.15 配置小节，带理由）")
    return 0


def selftest():
    real = real_tool_count()
    if real is None:
        print("FATAL 自检无法取得真源计数", file=sys.stderr)
        return 2
    canonical = (
        "## 12. 一句话总结\n\n"
        f"FIST-Mbt = ……（本机 `tools/list` 实测 **{real} 个 MCP 工具**）。\n"
        "→ （本机实测：**{} 个工具**；真源是 server 注册表）\n"
    ).format(real)

    # ── Part A 合成样例 ──
    results = []

    def cell(name, passed):
        """格子登记器：PASS 行的格数从 results 反解，不手写计数（BUG-514 同族）。"""
        results.append((name, bool(passed)))
        if not passed:
            print(f"SELFTEST RED {name}", file=sys.stderr)

    # A① 干净输入不误红
    cell("干净样例（计数）被误红", check_counts(canonical, real) == [])
    # A② 改坏成错数必红
    broken = canonical.replace(f"{real} 个 MCP 工具", f"{real - 52} 个 MCP 工具")
    cell("错数变异未被点名", broken != canonical and check_counts(broken, real))
    # A③ 下限式虚报必红
    over = canonical.replace(f"{real} 个 MCP 工具", f"{real + 1}+ 个 MCP 工具")
    cell("下限虚报未被点名", check_counts(over, real))
    # A④ 计数自述整份消失必红（失锚）
    cell("失锚态未被点名", check_counts("没有计数的一页", real))

    # ── Part B 合成样例（全 hermetic：合成活体 + 合成 §6，不起 server）──
    live_synth = {
        "publish": ["created_by", "description", "level", "namespace", "project_dir"],
        "claim": ["agent", "assignee", "namespace", "task_id"],
        "get": ["namespace", "task_id"],
        "model_route": ["config_json", "context"],
        "purge_cache": ["namespace"],  # 活体有、§6 无行且不在白名单 → 提及即红
    }
    wl_synth = {"model_route": "合成豁免理由：§6.x 只讲配置"}
    base_usage = (
        "## 6. MCP 工具手册\n\n"
        "| 工具 | 说明 | 参数 |\n|---|---|---|\n"
        "| `publish` | 发布根任务 | project_dir(必) description(必) created_by(选) namespace(选) level(选) |\n"
        "| `claim` | 认领任务 | task_id(必) assignee(必) agent(选) namespace(选) |\n"
        "| `get` | 查询任务 | task_id(必) namespace(选) |\n\n"
        "模型路由工具（`model_route`）的接线配置见 §6.15（本节只讲配置）。\n\n"
        "## 7. 结尾\n"
    )
    # B⑤ 干净现状不误红（含豁免面：model_route 提及无行但已豁免）
    cell("干净样例（§6 参数列）被误红", check_params(base_usage, live_synth, whitelist=wl_synth) == [])
    # B⑥ 文档多写参数必红（改坏一行表）
    extra = base_usage.replace("namespace(选) level(选) |", "namespace(选) level(选) bogus_param(选) |")
    cell("多写参数变异未被点名",
         extra != base_usage and any("多写" in e for e in check_params(extra, live_synth, whitelist=wl_synth)))
    # B⑦ 活体有而文档漏写必红（改坏一行表）
    lacking = base_usage.replace(" namespace(选) level(选) |", " |")
    cell("漏写参数变异未被点名",
         lacking != base_usage and any("漏写" in e for e in check_params(lacking, live_synth, whitelist=wl_synth)))
    # B⑧ 表行工具不在活体必红（文档多写工具）
    ghost = base_usage.replace(
        "| `get` | 查询任务 | task_id(必) namespace(选) |",
        "| `get` | 查询任务 | task_id(必) namespace(选) |\n| `fake_tool` | 幻影 | a(必) |")
    cell("幻影工具变异未被点名",
         ghost != base_usage and any("不在活体" in e for e in check_params(ghost, live_synth, whitelist=wl_synth)))
    # B⑨ 白名单外「提及但无表行」必红
    mention = base_usage.replace("## 7. 结尾", "空闲时可调 `purge_cache` 清缓存。\n\n## 7. 结尾")
    cell("白名单外提及无行未被点名",
         mention != base_usage and any(
             "没有参数表行" in e for e in check_params(mention, live_synth, whitelist=wl_synth)))
    # B⑩ 豁免真的在挡（同一提及，把 model_route 摘出白名单 ⇒ 必红）
    cell("豁免摘除后提及无行未被点名（豁免面失效）",
         any("没有参数表行" in e for e in check_params(base_usage, live_synth, whitelist={})))
    # B⑪ 豁免过期必红（被豁免工具有了表行 ⇒ 逼人清理白名单）
    stale = base_usage.replace(
        "| `get` | 查询任务 | task_id(必) namespace(选) |",
        "| `get` | 查询任务 | task_id(必) namespace(选) |\n"
        "| `model_route` | 模型路由 | context(必) config_json(选) |")
    cell("豁免过期变异未被点名",
         stale != base_usage and any("豁免过期" in e for e in check_params(stale, live_synth, whitelist=wl_synth)))
    # B⑫ §6 整节消失必红（失锚）
    cell("§6 失锚态未被点名", check_params("## 1. 没有手册的一页\n", live_synth, whitelist=wl_synth))

    # ⑬ CALLFACE（check_selftest_call_face J2）：selftest 的调用图要够得着调用面锚点。
    # 改走「自 spawn 拒未知旗标」（锚点③形：subprocess 起 sys.executable + 自身脚本名）：
    # argparse 天生即拒 rc=2；cwd 落系统临时目录 ⇒ hermetic S 档（跑真尺子、打合成输入，
    # 记账不进棘轮）。
    _face_dir = tempfile.mkdtemp(prefix="usage_tc_face_")
    _face_ok = False
    try:
        _p = subprocess.run(
            [sys.executable, os.path.abspath(__file__), "--definitely-not-real"],
            cwd=_face_dir, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=60)
        _face_ok = _p.returncode == 2
    except Exception:
        _face_ok = False
    finally:
        shutil.rmtree(_face_dir, ignore_errors=True)
    cell("调用面自 spawn 未按 rc=2 拒未知旗标", _face_ok)

    total, failed = len(results), [n for n, p in results if not p]
    if not failed:
        print(f"SELFTEST PASS（{total}/{total}，真源={real}）")
        return 0
    print(f"SELFTEST FAIL（{total - len(failed)}/{total}）", file=sys.stderr)
    return 1


def main():
    ap = argparse.ArgumentParser(
        description="USAGE.md 工具面守卫：计数自述（BUG-525）+ §6 参数列活体对表（T0r12）")
    ap.add_argument("--selftest", action="store_true", help="变异对照自检（全合成输入），不扫真仓库、不起 server")
    args = ap.parse_args()
    return selftest() if args.selftest else run_real()


if __name__ == "__main__":
    sys.exit(main())
