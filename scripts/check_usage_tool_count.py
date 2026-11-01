#!/usr/bin/env python3
"""check_usage_tool_count.py —— BUG-525 关闭条件：USAGE.md 的工具计数自述入守卫面。

真源 = `scripts/_tool_registry.real_tools()`（src/server/*.mbt 注册口径，与
check_tools_sync / mcp_smoke / check_doc_surface 同一实现，不在此抄第二份）。

被检面：USAGE.md 里一切「N 个工具 / N 个 MCP 工具 / N MCP 工具 / 工具 N 个」
（含 `N+` 下限式）的散文计数自述：
  * 精确式（无 `+`）→ 必须等于真源计数；
  * 下限式（`N+`）→ 真源计数 ≥ N（下限超过实测 = 虚报，照样红）；
  * 整份 USAGE 一个计数自述都没有 → 红（守卫面失锚，等于回到 BUG-525 的「数不在任何面上」）。

漂移即红，逼人在加/删工具的同一笔里改 USAGE —— 这正是两次复发（87→129、130/140+→182）缺的那把尺。

rc 契约：0=绿；1=漂移/失锚；2=自拒（读不到真源或读不到 USAGE，绝不报绿）。
参数面：argparse，未知旗标天生即拒。
--selftest：变异对照（把样例改成错数必红 + 干净输入不误红 + 下限虚报必红）。
"""

import argparse
import importlib.util as _ilu
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SCRIPT_DIR = Path(__file__).resolve().parent
USAGE_PATH = SCRIPT_DIR.parent / "USAGE.md"
REGISTRY_PATH = SCRIPT_DIR / "_tool_registry.py"

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


def check(usage_text, real):
    """返回错误行列表（空 = 绿）。real 必须非 None。"""
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
    errs = check(text, real)
    if errs:
        for e in errs:
            print(f"RED {e}")
        print(f"USAGE 工具计数对表：真源 {real}，{len(errs)} 处漂移/虚报/失锚")
        return 1
    print(f"USAGE 工具计数对表 PASS：真源 {real}，USAGE 自述与之一致")
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

    ok = 0
    # ① 干净输入不误红
    if check(canonical, real) == []:
        ok += 1
    else:
        print(f"SELFTEST RED 干净样例（{real}）被误红", file=sys.stderr)
    # ② 改坏成错数必红
    broken = canonical.replace(f"{real} 个 MCP 工具", f"{real - 52} 个 MCP 工具")
    if broken != canonical and check(broken, real):
        ok += 1
    else:
        print("SELFTEST RED 错数变异未被点名", file=sys.stderr)
    # ③ 下限式虚报必红
    over = canonical.replace(f"{real} 个 MCP 工具", f"{real + 1}+ 个 MCP 工具")
    if check(over, real):
        ok += 1
    else:
        print("SELFTEST RED 下限虚报未被点名", file=sys.stderr)
    # ④ 计数自述整份消失必红（失锚）
    if check("没有计数的一页", real):
        ok += 1
    else:
        print("SELFTEST RED 失锚态未被点名", file=sys.stderr)

    if ok == 4:
        print(f"SELFTEST PASS（4/4，真源={real}）")
        return 0
    return 1


def main():
    ap = argparse.ArgumentParser(description="USAGE.md 工具计数自述 ↔ server 注册真源对表（BUG-525）")
    ap.add_argument("--selftest", action="store_true", help="变异对照自检，不扫真仓库")
    args = ap.parse_args()
    return selftest() if args.selftest else run_real()


if __name__ == "__main__":
    sys.exit(main())
