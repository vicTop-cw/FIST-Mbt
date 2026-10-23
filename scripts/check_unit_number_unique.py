#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""轮次号唯一性守卫（R134，副机自立项）。

被检面：`reports/` 下文件名形如 `<日期>-<slug>-r<编号>-report.md` 的交付报告——
文件名即编号认领（**只认编号紧贴 `-report.md` 的规范形**；`…-r94-<说明>-report.md` 与
`…-award-enhancement-r110-gate-reconfirm-report.md` 这两族历史命名不在本尺面——它们要么是同一单元的补充报告、
要么属于另一套命名，把单元身份判错的代价比漏判大；扩面需要先做命名迁移，不在本单范围）。判据三条：

- U1 撞号：同一编号被**两个不同 slug**（= 两个不同单元）复用 ⇒ 违例；只有同 slug 的
  多份报告（同一单元的追记/复跑）不算撞号。
- U2 基线对表：历史撞号组登记在 `docs/tasks/unit-number-baseline.txt`，实际 slug 集合
  必须与基线**逐字相等**——新增 slug ⇒ 红（新单元撞了老号，应改号）；少 slug ⇒ 红
  （基线过期，棘轮只许收紧且必须同批改基线）。
- U3 悬空认领：基线点名了、`reports/` 里却对不上的编号 ⇒ 红。

为什么盯 `reports/` 而不是远端分支名：本尺要能在 CI 与本地电池里**离网**跑；远端分支面
需要网络与在飞状态，判不了。`reports/` 是编号落地的交付面，一旦撞号就已经进仓——
R110 / R113 / R118 / R121 四组历史撞号就是这么静默进仓的；本尺叠主线当天又当场抓到
第五组 R126（`mcp-server-moon-env` / `slave-task-list-selfproof-ruler`），已同批收紧进基线。
两支同时取同一号的残余缺口写在报告「遗留风险」，本尺不拿它换假绿。

退出码契约（BUG-369）：0=无违例 / 1=有撞号、基线不符或悬空认领 / 2=判据无法自证
（`reports/` 为空、带编号报告一份都解析不出、基线缺失或语法坏）/ 4=尺子自己坏了
（未捕获异常，绝不冒用 1 那一档）。
"""

from __future__ import annotations

import contextlib
import io
import os
import re
import sys
import tempfile

# BUG-58/138：本尺满屏中文结论，GBK 控制台上「判红」会先崩在打印那一行、把 rc 冒用成缺陷在场。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME_RE = re.compile(r"^(?P<date>\d{4}-\d{2}-\d{2})-(?P<slug>.+?)-r(?P<num>\d+)-report\.md$")
BASE_RE = re.compile(r"^R(?P<num>\d+)\s+(?P<slugs>\S.*)$")
SKIP_DIRS = {"__pycache__", ".git"}
DEFAULT_BASELINE = os.path.join("docs", "tasks", "unit-number-baseline.txt")


def rel_posix(p):
    return p.replace(os.sep, "/")


def find_reports(base_dir):
    """报告宇宙：base_dir 下文件名形如 `<日期>-<slug>-r<编号>-report.md` 的每一份（递归）。"""
    out = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            m = NAME_RE.match(name)
            if m:
                out.append((int(m.group("num")), m.group("slug"), os.path.join(root, name)))
    return sorted(out)


def load_baseline(path):
    """返回 (claims, errors)。claims = {编号: {slug}}；语法坏/重复认领 ⇒ errors 非空 ⇒ 2 号档。"""
    if not os.path.isfile(path):
        return {}, ["基线文件不存在：%s" % rel_posix(path)]
    claims, errors, seen = {}, [], {}
    with open(path, encoding="utf-8-sig") as fh:
        lines = fh.read().splitlines()
    for i, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        m = BASE_RE.match(s)
        if not m:
            errors.append("基线第 %d 行语法坏：%r（应为 `R<号> <slug> [slug…]`）" % (i, s[:60]))
            continue
        num = int(m.group("num"))
        if num in seen:
            errors.append("基线第 %d 行重复认领 R%d（首次在第 %d 行）" % (i, num, seen[num]))
            continue
        seen[num] = i
        claims[num] = set(m.group("slugs").split())
    return claims, errors


def scan(reports, claims):
    """返回 (violations, stats)。"""
    groups = {}
    for num, slug, path in reports:
        groups.setdefault(num, {}).setdefault(slug, []).append(path)
    violations = []
    for num in sorted(groups):
        slugs = set(groups[num])
        if len(slugs) <= 1:
            continue
        if num not in claims:
            violations.append(
                "R%d 撞号：%d 个不同单元共用同一编号（%s），基线里没有认领"
                % (num, len(slugs), " / ".join(sorted(slugs))))
            continue
        extra = slugs - claims[num]
        missing = claims[num] - slugs
        if extra or missing:
            bits = []
            if extra:
                bits.append("新增 %s" % " / ".join(sorted(extra)))
            if missing:
                bits.append("基线多出 %s" % " / ".join(sorted(missing)))
            violations.append(
                "R%d 基线不符：%s（基线=%s）"
                % (num, "；".join(bits), " / ".join(sorted(claims[num]))))
    for num in sorted(claims):
        if num not in groups:
            violations.append("R%d 悬空认领：基线点名了，reports/ 里没有这个编号的报告" % num)
    stats = dict(numbers=len(groups), reports=len(reports), baseline=len(claims))
    return violations, stats


def run(args):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = main(args)
    return rc, buf.getvalue()


_EXECUTED = []


def check(cell, ok, detail=""):
    _EXECUTED.append((cell, bool(ok)))
    print("%s %s %s" % ("PASS" if ok else "FAIL", cell, detail))
    return ok


def _sandbox(names):
    d = tempfile.mkdtemp(prefix="unitnum-")
    rdir = os.path.join(d, "reports")
    os.makedirs(rdir)
    for n in names:
        with open(os.path.join(rdir, n), "w", encoding="utf-8") as fh:
            fh.write("# 桩报告\n")
    return d, rdir


def _write_baseline(d, text):
    p = os.path.join(d, "baseline.txt")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)
    return p


def selftest():
    global _EXECUTED
    _EXECUTED = []
    two = ["2026-01-01-alpha-r10-report.md", "2026-01-02-beta-r10-report.md"]

    # S1：两个不同 slug 共用 R10，基线没有认领 ⇒ 真给 1
    d, rdir = _sandbox(two)
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "")])
    check("S1", rc == 1 and "撞号" in out, "rc=%d 判红=%s" % (rc, "撞号" in out))

    # S2：历史撞号进基线后不误红（棘轮的正常态）
    d, rdir = _sandbox(two)
    rc, _ = run(["--scan", rdir, "--baseline", _write_baseline(d, "R10 alpha beta\n")])
    check("S2", rc == 0, "基线认领后 rc=%d" % rc)

    # S3：基线只认领了 alpha，新单元 beta 又撞上来 ⇒ 必红（新增 slug）
    d, rdir = _sandbox(two)
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "R10 alpha\n")])
    check("S3", rc == 1 and "新增 beta" in out, "rc=%d 新增=%s" % (rc, "新增 beta" in out))

    # S4：基线多出一个实际不存在的 slug ⇒ 红（基线过期，只许收紧）
    d, rdir = _sandbox(two)
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "R10 alpha beta gamma\n")])
    check("S4", rc == 1 and "基线多出 gamma" in out, "rc=%d 多出=%s" % (rc, "基线多出 gamma" in out))

    # S5：基线点名 R20，reports/ 里没有这个编号 ⇒ 悬空认领必红
    d, rdir = _sandbox(["2026-01-03-alpha-r30-report.md"])
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "R20 alpha\n")])
    check("S5", rc == 1 and "悬空" in out, "rc=%d 悬空=%s" % (rc, "悬空" in out))

    # S6：同一 slug 的多份规范命名报告（同一单元追记/复跑）不是撞号。
    #     两份都必须命中 NAME_RE——用不匹配的名字会落成「根本没进宇宙」的幻影格。
    d, rdir = _sandbox(["2026-01-04-alpha-r10-report.md",
                        "2026-02-04-alpha-r10-report.md"])
    rc, _ = run(["--scan", rdir, "--baseline", _write_baseline(d, "")])
    check("S6", rc == 0, "同单元追记 rc=%d" % rc)

    # S7：空宇宙自拒（真给 2，不冒用 0）
    d, rdir = _sandbox([])
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "")])
    check("S7", rc == 2 and "为空" in out, "空宇宙 rc=%d" % rc)

    # S8：面板里有一堆报告，但一份带编号的都解析不出 ⇒ 文法失效，自拒不报绿
    d, rdir = _sandbox(["notes.md", "2026-01-05-round999-legacy-report.md"])
    rc, _ = run(["--scan", rdir, "--baseline", _write_baseline(d, "")])
    check("S8", rc == 2, "无编号报告 rc=%d" % rc)

    # S9：真源现状面必须绿——本尺在现状不恒红（否则它只是个装饰）
    rc, out = run([])
    check("S9", rc == 0, "真源 rc=%d %s" % (rc, out.strip().splitlines()[-1][:70] if out.strip() else ""))

    # S10：基线语法坏 ⇒ 判据无法自证（2），不许当 0 也不许当 1
    d, rdir = _sandbox(two)
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "R alpha\n")])
    check("S10", rc == 2 and "语法坏" in out, "rc=%d" % rc)

    # S11：同一编号被基线认领两次 ⇒ 无法自证（2）
    d, rdir = _sandbox(two)
    rc, out = run(["--scan", rdir, "--baseline", _write_baseline(d, "R10 alpha\nR10 beta\n")])
    check("S11", rc == 2 and "重复认领" in out, "rc=%d" % rc)

    ok = all(passed for _, passed in _EXECUTED)
    cells = " / ".join("%s×1" % c for c, _ in _EXECUTED)
    print("SELFTEST %s（%d 格：%s，清单从已执行格子反解，不手写计数）"
          % ("OK" if ok else "FAIL", len(_EXECUTED), cells))
    return 0 if ok else 1


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if "--selftest" in argv:
        return selftest()
    scan_dir = os.path.join(REPO_ROOT, "reports")
    if "--scan" in argv and len(argv) > argv.index("--scan") + 1:
        scan_dir = argv[argv.index("--scan") + 1]
    baseline = os.path.join(REPO_ROOT, DEFAULT_BASELINE)
    if "--baseline" in argv and len(argv) > argv.index("--baseline") + 1:
        baseline = argv[argv.index("--baseline") + 1]
    if not os.path.isdir(scan_dir):
        print("UNITNUM=reject 被检面不存在：%s" % rel_posix(scan_dir))
        return 2
    reports = find_reports(scan_dir)
    if not reports:
        print("UNITNUM=reject 被检面为空：%s 下一份带编号的交付报告都没枚举到——判据无法自证"
              % rel_posix(scan_dir))
        return 2
    claims, errors = load_baseline(baseline)
    if errors:
        print("UNITNUM=reject 基线不可用（%s）：%s"
              % (rel_posix(baseline), "；".join(errors)))
        return 2
    violations, stats = scan(reports, claims)
    if violations:
        print("UNITNUM=violate 违例 %d 条（报告 %d 份 / 编号 %d 个 / 基线认领 %d 组）"
              % (len(violations), stats["reports"], stats["numbers"], stats["baseline"]))
        for v in violations:
            print("  - " + v)
        print("处置：新单元改号（`reports/<日期>-<slug>-r<新号>-report.md`）；"
              "历史撞号只许在基线里收紧，不许放宽")
        return 1
    print("UNITNUM=clean 编号 %d 个 / 报告 %d 份；撞号基线 %d 组逐组对表一致"
          % (stats["numbers"], stats["reports"], stats["baseline"]))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了 -> 真给 4，绝不冒用 1（判据红）
        sys.stderr.write("RULER BROKEN: %r\n" % e)
        sys.exit(4)
