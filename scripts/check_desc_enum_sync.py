#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scripts/check_desc_enum_sync.py — 契约面「描述侧落后检测」守卫（BUG-214 同族）。

为什么需要它：`check_doc_surface.py` 的契约判据只查「desc ↔ schema ↔ 真源」三方当前一致，
不查「工具描述是否引用了源码闭集里**已删除**的枚举值」。BUG-214 正是这一形态：
`bug_severities()` 早删了 `open`（抬头状态词冒充严重度），而 `report_bug` 工具描述还写着
`severity(可选 open/critical/high/medium/low)`——照描述传 `severity="open"` 会整笔 Err 不落账。
schema 与真源闭集都已是新值，唯独描述落后，而现有判据看不见。

本守卫：对每个登记的 (工具, 参数, 闭集函数) 三元组，读源码闭集函数返回的数组字面量，
再到该工具描述里找 `参数(可选 …)` 子句，逐值比对——描述里出现闭集外的值即红。

登记表可扩展：往 ENUM_REGISTRY 里加 (描述文件, 闭集文件, 闭集函数名, 工具名, 参数名)。
--selftest 用合成违例证明能发红、干净输入不误红、闭集解析不到必自拒（沿本仓判据自证纪律）。

用法（项目根）：python scripts/check_desc_enum_sync.py [--selftest]
退出码：0 全绿；1 有违例或判据自身失灵。
"""

from __future__ import annotations


# BUG-138 残余面：Windows 默认 cp936 控制台下，中文结论一红就崩在 print 里，
# traceback + rc=1 会被读成「缺陷在场」那一档——那是尺子自己坏了。先把两条流钉 UTF-8。
import sys as _sys
if hasattr(_sys.stdout, "reconfigure"):
    _sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(_sys.stderr, "reconfigure"):
    _sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (描述文件, 闭集文件, 闭集函数名, 工具名, 参数名, 描述里的值列表子句正则)
# 第 6 列不**只**认「参数(可选 …)」子句形——`bug_mark_status` 把闭集写在正文散文里
# （「状态闭集 = OPEN/…」），参数子句只写「status(必填，FIXED 会被拒)」不带列表。
# 两种形共用同一个逻辑：正则抓值串 → 按 `/` 切 → 逐值比对闭集。
ENUM_REGISTRY = [
    (
        "src/server/server.mbt",
        "src/server/bugreport.mbt",
        "bug_severities",
        "report_bug",
        "severity",
        # 参数子句形：severity(可选 open/critical/high/medium/low)
        r"severity\s*\(\s*可选\s+([^)]*)\)",
    ),
    (
        "src/server/server.mbt",
        "src/server/bugreport.mbt",
        "bug_status_closed",
        "bug_mark_status",
        "status",
        # 散文形：值串截止到全角/半角括号或句末，避免把「（真源 memory/bugs.md…）」说明词带进来。
        r"状态闭集\s*=\s*([^。；\n（(]+)",
    ),
]

# 闭集函数形如：fn bug_severities() -> Array[String] {\n  ["a", "b", "c"]\n}
FN_RE = re.compile(r"fn\s+(\w+)\s*\(\s*\)\s*->\s*Array\[String\]\s*\{")
ARR_RE = re.compile(r"\[\s*((?:\"[^\"]*\"\s*,?\s*)+)\s*\]")


def parse_closure(file: Path, fn_name: str) -> list[str] | None:
    """从源码里解析 `fn <fn_name>() -> Array[String]` 的数组字面量，返回值列表；找不到返回 None。"""
    text = file.read_text(encoding="utf-8")
    m = FN_RE.search(text)
    while m:
        if m.group(1) == fn_name:
            seg = text[m.end(): m.end() + 400]
            am = ARR_RE.search(seg)
            if not am:
                return None
            return [s.strip().strip('"') for s in am.group(1).split(",") if s.strip()]
        m = FN_RE.search(text, m.end())
    return None


def parse_desc_clause(file: Path, pattern: str) -> str | None:
    """从工具描述里抽 `<参数>(可选 …)` 子句的取值串；没命中返回 None。"""
    text = file.read_text(encoding="utf-8")
    mm = re.search(pattern, text)
    if not mm:
        return None
    return mm.group(1).strip()


def check_entry(desc_file: Path, close_file: Path, close_fn: str,
                tool: str, param: str, pattern: str) -> list[str]:
    """对单个登记项跑守卫，返回问题清单（空=通过）。"""
    problems: list[str] = []
    closure = parse_closure(close_file, close_fn)
    if closure is None or not closure:
        problems.append(f"{close_file} 里解析不到闭集函数 `{close_fn}()`（判据自拒，不出假绿）")
        return problems
    desc = parse_desc_clause(desc_file, pattern)
    if desc is None:
        problems.append(f"{desc_file} 里找不到 `{tool}` 的 `{param}(可选 …)` 子句（判据自拒，不出假绿）")
        return problems
    listed = [v.strip().strip('"').strip("'") for v in desc.split("/") if v.strip()]
    # 允许「缺省 xx」这类尾部说明被 `/` 切开，只比对前段纯取值；这里简单处理：全段都进比对，
    # 但把形如 "缺省 ..." / "default ..." 的说明词剔掉。
    listed = [v for v in listed if not re.match(r"^(缺省|默认|default)", v)]
    closure_set = set(closure)
    for v in listed:
        if v not in closure_set:
            problems.append(
                f"{tool}.{param} 描述列了闭集外的值 `{v}`（闭集 {sorted(closure_set)}）"
            )
    return problems


def main() -> int:
    unknown = [a for a in sys.argv[1:] if a != "--selftest"]
#     必须切掉 argv[0]（脚本自身路径），否则它会被当成未知旗标 ⇒ 恒 rc=2
    if unknown:
        print("FATAL 未知参数：%s（本尺只接受 --selftest）" % " ".join(unknown))
        sys.exit(2)
    # ↑ 严格参数面（R65）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
    selftest = "--selftest" in sys.argv
    if selftest:
        # 合成违例：闭集外值 → 必红
        closure = parse_closure(ROOT / ENUM_REGISTRY[0][1], "bug_severities")
        if not closure:
            print("SELFTEST FAIL 基线闭集解析不到，无法自证")
            return 1
        assert "open" not in closure, "BUG-214 应已删 open，闭集不该含它"
        # 反向：若闭集含 open（旧码），合成违例即真实违例
        fake_closure_has_open = "open" in closure
        real = check_entry(
            ROOT / ENUM_REGISTRY[0][0], ROOT / ENUM_REGISTRY[0][1],
            "bug_severities", "report_bug", "severity", ENUM_REGISTRY[0][5],
        )
        # 干净输入必须不误红：当前描述只列闭集内值
        if real:
            print(f"SELFTEST FAIL 当前 report_bug 描述已红：{'；'.join(real)}")
            return 1
        # 合成违例必红：临时把描述改造成含 `open` 再跑
        text = (ROOT / ENUM_REGISTRY[0][0]).read_text(encoding="utf-8")
        mm = re.search(ENUM_REGISTRY[0][5], text)
        if not mm:
            print("SELFTEST FAIL 找不到 severity 子句，无法做违例反证")
            return 1
        mutated = text[:mm.start()] + "severity(可选 open/critical/high/medium/low)" + text[mm.end():]
        tmp = ROOT / "temp" / "_enum_sync_mutated.mbt"
        tmp.parent.mkdir(exist_ok=True)
        tmp.write_text(mutated, encoding="utf-8")
        mut_problems = check_entry(
            tmp, ROOT / ENUM_REGISTRY[0][1], "bug_severities",
            "report_bug", "severity", ENUM_REGISTRY[0][5],
        )
        tmp.unlink(missing_ok=True)
        if not mut_problems:
            print("SELFTEST FAIL 合成违例（severity(可选 open/…)）没被抓住，判据失灵")
            return 1
        print(f"SELFTEST OK 闭集={closure}，干净不误红，合成违例必红（抓住 {mut_problems[0]}）")

        # 第二格：散文形（`状态闭集 = …`）同样要能发红——不然判据只在「参数子句形」上自证，
        # bug_mark_status 这类把闭集写在正文散文里的工具就是守卫的盲区。
        s = ENUM_REGISTRY[1]  # status 条目
        real_s = check_entry(
            ROOT / s[0], ROOT / s[1], s[2], s[3], s[4], s[5],
        )
        if real_s:
            print(f"SELFTEST FAIL 当前 bug_mark_status 描述已红：{'；'.join(real_s)}")
            return 1
        stext = (ROOT / s[0]).read_text(encoding="utf-8")
        smm = re.search(s[5], stext)
        if not smm:
            print("SELFTEST FAIL 找不到「状态闭集 = …」子句，无法做违例反证")
            return 1
        # 合成违例：往闭集里塞一个抬头状态词（open）冒充合法状态
        smutated = stext[:smm.start()] + "状态闭集 = OPEN/FIXED/CLOSED" + stext[smm.end():]
        stmp = ROOT / "temp" / "_enum_sync_status_mutated.mbt"
        stmp.parent.mkdir(exist_ok=True)
        stmp.write_text(smutated, encoding="utf-8")
        smut_problems = check_entry(
            stmp, ROOT / s[1], s[2], s[3], s[4], s[5],
        )
        stmp.unlink(missing_ok=True)
        if not smut_problems:
            print("SELFTEST FAIL 合成违例（状态闭集 = OPEN/FIXED/CLOSED）没被抓住，散文形判据失灵")
            return 1
        print(f"SELFTEST OK(散文形) 抓 status 闭集外值（抓住 {smut_problems[0]}）")
        return 0

    all_problems: list[str] = []
    for entry in ENUM_REGISTRY:
        desc_file = ROOT / entry[0]
        close_file = ROOT / entry[1]
        if not desc_file.exists() or not close_file.exists():
            print(f"FAIL 路径缺失：{entry[0]} / {entry[1]}")
            return 1
        all_problems += check_entry(desc_file, close_file, entry[2], entry[3], entry[4], entry[5])

    if all_problems:
        print("FAIL 描述侧 enum 同步违例：")
        for p in all_problems:
            print(f"  - {p}")
        return 1
    print("PASS 描述侧 enum 同步：登记项全部一致（描述未引用闭集外的枚举值）")
    return 0


if __name__ == "__main__":
    sys.exit(main())