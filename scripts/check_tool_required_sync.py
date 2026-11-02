#!/usr/bin/env python3
r"""check_tool_required_sync.py —— src/server/server.mbt 工具面「schema required 数组 ↔ 必填 描述」源↔源双向对表守卫。

**为什么需要它**（续19 required 矛盾面普查立尺，本仓第一例 = bug_fix.evidence）：
MCP 工具的 `schema` 第二参数是 `required` 数组（客户端硬门：缺了就当场拒），而工具
描述 / 「参数：」summary 里的「必填」是给人看的软约束。两者漂移有两种病：

  * **漏写**：描述说「必填」但 `required` 数组没列 ⇒ 客户端不拦，空参一路漏到服务端
    函数才炸。`bug_fix.evidence` 就是这一例（描述三处「必填非空」、函数 bugreport.mbt
    硬拒空 evidence，`required` 却只有 `["project_dir","bug_ids"]`）——本尺落地时同步修掉。
  * **多写**：`required` 数组列了但描述说「可选」/「条件必填」⇒ 合法调用被客户端误拒。

本尺**源↔源**对表（直接解析 server.mbt 文本，**不起 server、不 build**，CI 可裸跑），
漂移即红，逼人在改工具 schema 的同一笔里对齐 required 与描述——与
`check_usage_tool_count.py`（USAGE 文档面）互补：一把看仓内文档、一把看仓内 schema 自洽。

**条件必填白名单**：少数参数是「条件必填」（`file_release.reason` 仅 force /
`bug_mark_status.dup_of` 仅 DUPLICATE / `ocr_scan.path` 仅 delegate|rules）——描述里写
「仅 X 必填」，`required` 数组**不该**含它（含了就变无条件必填，合法调用被误拒）。
这 3 条进 `WHITELIST_CONDITIONAL` 点名豁免（每条带理由）；`RE_COND` 再把「仅/时必填/当…必填」
措辞识别成条件必填作**辅助**（belt-and-suspenders，防新增条件必填漏进白名单）。
白名单条目过期（工具/参数消失、或已变无条件必填且进 required）会三向自红逼人清理。

**`[omega:required]` 防喂针**：那是给**根任务**打的强验证标记（server.mbt:3902 描述里的词），
不是参数 required 注解。本尺只认「参数：name(必填)」summary 措辞，不会把 `[omega:required]`
误当必填声明（selftest S7 有具体对照，且真跑 0 漂移为证）。

rc 契约：0=绿（零漂移 / selftest 全过）；1=漂移（漏写/多写）/ 白名单过期 / 失锚
（读不到 server.mbt）；2=自拒（解析面失锚：一份工具都解析不到——绝不拿空面报绿）。
参数面：argparse，未知旗标天生即拒（rc=2，AGENTS R207 判例——绝不写成 `"--flag" in argv`）。
--selftest：全合成输入（不碰真仓库、不起 server），含变异对照：漏写必红 / 多写必红
（可选 + 条件必填两形）/ 干净不误红 / 条件必填不在 required 不误红 / 白名单抑制面双向 /
白名单过期三向 / bug_fix.evidence 具体对照（缺 evidence 红、补 evidence 绿）/ 零工具失锚 /
未知旗标 rc=2。PASS 行格数从已执行格子反解，不手写（BUG-514 同族）。
"""

import argparse
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
ROOT = SCRIPT_DIR.parent
SERVER_MBT = ROOT / "src" / "server" / "server.mbt"

# 条件必填白名单：(tool, param) -> 理由。描述写「仅 X 必填」，required 数组本就不该含它。
# 白名单条目过期（工具/参数消失 / 变无条件必填且进 required）由 check_drift 三向自红。
WHITELIST_CONDITIONAL = {
    ("file_release", "reason"): "仅 force 时必填（非 force 不写库不留痕）",
    ("bug_mark_status", "dup_of"): "仅 status=DUPLICATE 时必填（并入主编号）",
    ("ocr_scan", "path"): "仅 delegate|rules 子命令时必填",
}

# 条件必填措辞（白名单的辅助）：「必填」前带 仅/时必填/当…必填 ⇒ 非无条件必填。
RE_COND = re.compile(r"(仅|时必填|当.{0,8}必填)")


def _read_server_text():
    try:
        return SERVER_MBT.read_text(encoding="utf-8")
    except OSError:
        return None


def _tool_name(lines, i):
    for j in range(i + 1, min(i + 4, len(lines))):
        m = re.match(r'^"([a-z_][a-z0-9_]*)"\s*,?\s*$', lines[j].strip())
        if m:
            return m.group(1)
    return None


def _schema_line(lines, i):
    for j in range(i + 1, min(i + 25, len(lines))):  # 长描述（多行 + 拼接）需要大窗口
        if lines[j].strip().startswith("schema("):
            return j
    return None


def _schema_block(lines, j):
    props, required, pc = [], [], None
    for k in range(j, min(j + 80, len(lines))):
        s = lines[k].strip()
        if pc is None:
            m = re.match(r'^"([a-z_][a-z0-9_]*)"\s*:', s)
            if m:
                props.append(m.group(1))
            if s == "},":  # props 对象收尾
                pc = k
        elif s.startswith("["):  # props 收尾后的第一个顶层数组 = required（含空 `[]`）
            required = [] if s.strip("] \t,") == "" else re.findall(r'"([a-z_][a-z0-9_]*)"', s)
            break
    return props, required


def _desc(lines, i, sj):
    frag = ""
    for k in range(i + 1, sj):
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', lines[k]):
            frag += m.group(1)
    return frag


def _param_claims(desc):
    """「参数：」summary → {param: 'required'|'conditional'|'optional'|'unknown'}。找不到 summary → {}。"""
    m = re.search(r"参数：(.*)", desc)
    if not m:
        return {}
    out = {}
    for pm in re.finditer(r"([a-z_][a-z0-9_]*)\s*\(([^)]*)\)", m.group(1)):
        pname, ptxt = pm.group(1), pm.group(2)
        if "必填" in ptxt:
            out[pname] = "conditional" if RE_COND.search(ptxt) else "required"
        elif "可选" in ptxt or ptxt.strip().startswith("选"):
            out[pname] = "optional"
        else:
            out[pname] = "unknown"
    return out


def parse_tools(text):
    """[{name, props:set, required:list, claims:dict}] —— 只认真注册 `sX = instrumented_tool(`
    （排除 `fn instrumented_tool(` 的定义本身）。解析不到任何工具 → 空列表（调用方自拒 rc=2）。"""
    lines = text.splitlines()
    starts = [i for i, l in enumerate(lines) if re.search(r"=\s*instrumented_tool\(", l)]
    tools = []
    for i in starts:
        name = _tool_name(lines, i)
        sj = _schema_line(lines, i)
        if not name or sj is None:
            continue
        props, required = _schema_block(lines, sj)
        tools.append(
            {"name": name, "props": set(props), "required": required, "claims": _param_claims(_desc(lines, i, sj))}
        )
    return tools


def check_drift(tools, whitelist=None):
    """双向对表 + 白名单过期三向 → 错误行列表（空 = 绿）。whitelist 缺省用真仓 WHITELIST_CONDITIONAL。"""
    wl = WHITELIST_CONDITIONAL if whitelist is None else whitelist
    errs = []
    by_name = {t["name"]: t for t in tools}
    for t in tools:
        reqset = set(t["required"])
        # ① 漏写：描述无条件必填 但 required 未列（白名单/条件必填豁免）。
        for p, c in sorted(t["claims"].items()):
            if c == "required" and p not in reqset and (t["name"], p) not in wl:
                errs.append(
                    "%s: 漏写 `%s` —— 描述声称必填但 schema required 未列（客户端不拦，空参漏到服务端才炸）"
                    % (t["name"], p)
                )
        # ② 多写：required 列了 但 描述明确「可选」或「条件必填」（条件必填不该无条件进 required）。
        for p in sorted(reqset):
            c = t["claims"].get(p)
            if c in ("optional", "conditional"):
                errs.append(
                    "%s: 多写 `%s`（%s）—— schema required 列了但描述是%s（合法调用被客户端误拒）"
                    % (t["name"], p, "可选" if c == "optional" else "条件必填", "可选" if c == "optional" else "条件必填")
                )
    # ③ 白名单过期（三向）：工具消失 / 参数不在 schema / 已变无条件必填且进 required。
    for (tool, param), why in sorted(wl.items()):
        t = by_name.get(tool)
        if t is None:
            errs.append("WHITELIST_CONDITIONAL 过期 `%s.%s` 工具不存在 —— 请清理（原理由：%s）" % (tool, param, why))
        elif param not in t["props"]:
            errs.append("WHITELIST_CONDITIONAL 过期 `%s.%s` 参数已不在 schema —— 请清理（原理由：%s）" % (tool, param, why))
        elif param in set(t["required"]) and t["claims"].get(param) == "required":
            errs.append("WHITELIST_CONDITIONAL 过期 `%s.%s` 已变无条件必填且进 required —— 请清理（原理由：%s）" % (tool, param, why))
    return errs


def run_real():
    text = _read_server_text()
    if text is None:
        print("FATAL 读不到 %s —— 自拒不报绿" % SERVER_MBT, file=sys.stderr)
        return 2
    tools = parse_tools(text)
    if not tools:
        print("FATAL 从 server.mbt 解析不到任何 `= instrumented_tool(` 注册 —— 解析面失锚，自拒不报绿", file=sys.stderr)
        return 2
    errs = check_drift(tools)
    if errs:
        for e in errs:
            print("RED", e)
        print("required↔必填 对表：解析 %d 工具，%d 处漂移/白名单过期" % (len(tools), len(errs)))
        return 1
    n_cond = sum(1 for t in tools for c in t["claims"].values() if c == "conditional")
    print(
        "required↔必填 对表 PASS：解析 %d 工具；required 数组与必填描述零漂移；条件必填 %d 处（白名单 %d 条，三向未过期）"
        % (len(tools), n_cond, len(WHITELIST_CONDITIONAL))
    )
    return 0


def selftest():
    results = []

    def cell(name, passed):
        results.append((name, bool(passed)))
        if not passed:
            print("SELFTEST RED", name, file=sys.stderr)

    def T(name, required, claims, props=None):
        return {"name": name, "props": set(props if props is not None else list(required)), "required": required, "claims": claims}

    # S1 干净样例（一致）不误红（whitelist={} 隔离白名单过期面，纯测漂移逻辑）
    clean = [T("t", ["a"], {"a": "required", "b": "optional"}, props=["a", "b"])]
    cell("干净样例（required 与描述一致）被误红", check_drift(clean, whitelist={}) == [])
    # S2 漏写变异必红（描述必填 但 required 没列）
    leak = [T("t", [], {"a": "required", "b": "optional"}, props=["a", "b"])]
    cell("漏写变异未被点名", check_drift(leak, whitelist={}))
    # S3 多写变异必红（两形：可选进 required / 条件必填进 required）
    extra_opt = [T("t", ["a"], {"a": "optional", "b": "required"}, props=["a", "b"])]
    cell("多写变异（可选进 required）未被点名", check_drift(extra_opt, whitelist={}))
    extra_cond = [T("t", ["a"], {"a": "conditional"}, props=["a"])]
    cell("多写变异（条件必填进 required）未被点名", check_drift(extra_cond, whitelist={}))
    # S4 条件必填不在 required 不误红（reason 仅 force 必填，required 本就不该含它）
    cond_ok = [T("file_release", ["project_dir"], {"project_dir": "required", "reason": "conditional"}, props=["project_dir", "holder", "reason"])]
    cell("条件必填（不在 required）被误红", check_drift(cond_ok, whitelist={}) == [])
    # S5 白名单抑制面双向（COND_RE 未识别为条件必填的必填参数，靠白名单挡）：带白名单绿 / 摘除红
    wl_case = [T("t", ["a"], {"a": "required", "b": "required"}, props=["a", "b"])]
    cell("白名单在挡时漏写未被挡（应绿）", check_drift(wl_case, whitelist={("t", "b"): "合成理由"}) == [])
    cell("白名单摘除后漏写未被点名（豁免面失效，应红）", check_drift(wl_case, whitelist={}))
    # S6 白名单过期三向（每格用最小单条白名单隔离，精测各自那一向）
    tool_gone = [T("other", [], {}, props=[])]
    cell("白名单过期（工具消失）未被点名", check_drift(tool_gone, whitelist={("file_release", "reason"): "工具消失对照"}))
    param_gone = [T("file_release", ["project_dir"], {"project_dir": "required"}, props=["project_dir", "holder"])]
    cell("白名单过期（参数不在 schema）未被点名", check_drift(param_gone, whitelist={("file_release", "reason"): "参数不在对照"}))
    became_uncond = [T("file_release", ["project_dir", "reason"], {"project_dir": "required", "reason": "required"}, props=["project_dir", "holder", "reason"])]
    cell("白名单过期（变无条件必填且进 required）未被点名", check_drift(became_uncond, whitelist={("file_release", "reason"): "变无条件对照"}))
    # S7 bug_fix.evidence 具体对照（本尺落地同步修掉的真缺陷）：缺 evidence 红 / 补 evidence 绿
    bf_leak = [T("bug_fix", ["project_dir", "bug_ids"], {"project_dir": "required", "bug_ids": "required", "evidence": "required"}, props=["project_dir", "bug_ids", "evidence"])]
    bf_fix = [T("bug_fix", ["project_dir", "bug_ids", "evidence"], {"project_dir": "required", "bug_ids": "required", "evidence": "required"}, props=["project_dir", "bug_ids", "evidence"])]
    cell("bug_fix 缺 evidence（漏写）未被点名", check_drift(bf_leak, whitelist={}))
    cell("bug_fix 补 evidence 后误红", check_drift(bf_fix, whitelist={}) == [])
    # S8 零工具解析面失锚（只有 fn 定义、没有 `= instrumented_tool(` 注册 ⇒ 0 工具）
    def_only = "pub fn instrumented_tool(s, name, description, input_schema, handler) -> @mcp.MCPServer { s.tool(name, description, input_schema, handler) }"
    cell("零工具解析面（失锚）未被识别", parse_tools(def_only) == [])
    # S9 调用面自 spawn 拒未知旗标（锚点③形：argparse 天生 rc=2；cwd 落临时目录 ⇒ hermetic）
    face_dir = tempfile.mkdtemp(prefix="req_sync_face_")
    face_ok = False
    try:
        p = subprocess.run(
            [sys.executable, os.path.abspath(__file__), "--definitely-not-real"],
            cwd=face_dir, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
        )
        face_ok = p.returncode == 2
    except Exception:
        face_ok = False
    finally:
        shutil.rmtree(face_dir, ignore_errors=True)
    cell("调用面自 spawn 未按 rc=2 拒未知旗标", face_ok)

    total, failed = len(results), [n for n, ok in results if not ok]
    if not failed:
        print("SELFTEST PASS（%d/%d）" % (total, total))
        return 0
    print("SELFTEST FAIL（%d/%d）" % (total - len(failed), total), file=sys.stderr)
    return 1


def main():
    ap = argparse.ArgumentParser(
        description="src/server/server.mbt 工具面 required 数组 ↔ 必填 描述 源↔源双向对表守卫（续19 立尺，本仓第一例 bug_fix.evidence）"
    )
    ap.add_argument("--selftest", action="store_true", help="变异对照自检（全合成输入），不碰真仓库、不起 server")
    args = ap.parse_args()
    return selftest() if args.selftest else run_real()


if __name__ == "__main__":
    sys.exit(main())
