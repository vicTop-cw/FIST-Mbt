#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_battery_count_doc.py — 「电池读数 ↔ README 登记」对表守卫（R112 / TASK-017）。

**为什么要有它**：`run_guards.py --list` 的规模读数（尺数 / CI 面 / 电池面 / 缺执行面 +
分类记账）是手抄进 `scripts/README.md` 的。TASK-017 就是 whisperer 探测时抓到的形状：
R106 登记「宇宙 81 份 = 尺 79 把」，而 R110/R111 之后实测已是 83 份 / 尺 81 把 / 电池 43 格，
README 里那串历史读数没人对表。实现会自证，手抄的读数不会——**加一把尺就落后一次**。

**对表面**：`run_guards.py` 条目里的机器可读锚点
`BATTERY-REGISTRATION：`rulers=… ci=… battery=… missing=… gate=… exempt=… unclassified=…``，
逐键与 `python scripts/run_guards.py --list` 的现读比较。

**逐键点名（两个方向都红）**：
  X1 欠格   = 现读 < 登记（格子/尺被删，或登记没随删减更新）。
  X2 登记落后 = 现读 > 登记（新增尺/格子后没同批改数——手抄读数落后的主路径）。
  X3 缺执行面 = missing > 0（G1 的读数被登记成 0 也不能掩盖现读）。
键序：rulers / ci / battery / missing / gate / exempt / unclassified。

**自拒（真给 2）**：README 里没有 `run_guards.py` 条目 / 条目里没有锚点 / 锚点缺键或值非整数 /
多份抄本数值打架 / `run_guards --list` 跑不起来或输出解析不到汇总行——判据读不到数就无权说「对上了」。

**与 `check_selftest_inventory_doc.py` 的分工**：那把尺对表「每把脚本自己的 `--selftest` 每族几格」，
本尺对表「电池的规模读数」（尺/面/分类），判据面不重叠。

用法：
  python scripts/check_battery_count_doc.py              # 对表（裸跑即可进电池）
  python scripts/check_battery_count_doc.py --selftest   # 尺子先证明自己会红
退出码：0=逐键一致 / 1=漂移（逐键点名）/ 2=判据无法自证 / 4=尺子自己坏了（未捕获异常）。
"""
import io
import os
import re
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join("scripts", "README.md")
RUN_GUARDS = os.path.join("scripts", "run_guards.py")
ANCHOR = "BATTERY-REGISTRATION"
SELF = os.path.basename(os.path.abspath(__file__))
KEY_ORDER = ("rulers", "ci", "battery", "missing", "gate", "exempt", "unclassified")
KEY_CN = {"rulers": "尺", "ci": "CI 面", "battery": "电池面", "missing": "缺执行面",
          "gate": "门禁尺", "exempt": "豁免", "unclassified": "未归类"}
BULLET_RE = re.compile(r"(?m)^- `run_guards\.py`")
NEXT_BULLET_RE = re.compile(r"(?m)^- ")
ANCHOR_RE = re.compile(r"BATTERY-REGISTRATION[^\n]*`([a-z]+=\d+(?:\s+[a-z]+=\d+)*)`")
SUMMARY_RE = re.compile(r"尺\s*(\d+)\s*把\s*/\s*CI 面\s*(\d+)\s*/\s*电池面\s*(\d+)\s*/\s*缺执行面\s*(\d+)")
CLASS_RE = re.compile(r"分类记账：门禁尺\s*(\d+)\s*/\s*豁免（带理由）\s*(\d+)\s*/\s*未归类\s*(\d+)")
TIMEOUT = 120


def parse_registration(text):
    """从 README 的 `run_guards.py` 条目里抽登记锚点。返回 (dict|None, 为什么)。"""
    m = BULLET_RE.search(text or "")
    if not m:
        return None, "%s 里没有 `run_guards.py` 条目" % DOC
    nxt = NEXT_BULLET_RE.search(text, m.end())
    block = text[m.start():nxt.start() if nxt else len(text)]
    payloads = ANCHOR_RE.findall(block)
    if not payloads:
        return None, "`run_guards.py` 条目里没有 `%s` 锚点（判据无法自证）" % ANCHOR
    parsed = []
    for payload in payloads:
        rec = {}
        for token in payload.split():
            if "=" not in token:
                return None, "锚点值不是 k=v 形状：%r" % payload
            key, val = token.split("=", 1)
            if key not in KEY_ORDER:
                return None, "锚点里有未知键 %r（合法键：%s）" % (key, " ".join(KEY_ORDER))
            if key in rec:
                return None, "锚点里键 %r 重复：%r" % (key, payload)
            if not re.fullmatch(r"\d+", val):
                return None, "锚点键 %r 的值不是整数：%r" % (key, val)
            rec[key] = int(val)
        missing = [k for k in KEY_ORDER if k not in rec]
        if missing:
            return None, "锚点缺键：%s（值：%r）" % (" ".join(missing), payload)
        parsed.append(rec)
    if any(rec != parsed[0] for rec in parsed[1:]):
        return None, "锚点有 %d 份抄本且数值打架：%s" % (len(parsed), parsed)
    return parsed[0], ""


def parse_counts(text):
    """从 `run_guards --list` 输出里抽规模读数。抽不全返回 None。"""
    s = SUMMARY_RE.search(text or "")
    c = CLASS_RE.search(text or "")
    if not s or not c:
        return None
    vals = [int(x) for x in s.groups()] + [int(x) for x in c.groups()]
    return dict(zip(KEY_ORDER, vals))


def read_counts(root=None):
    """跑一次 `run_guards --list` 拿现读。返回 (dict|None, 为什么)。"""
    path = os.path.join(root or ROOT, RUN_GUARDS)
    try:
        p = subprocess.run([sys.executable, path, "--list"], cwd=root or ROOT,
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=TIMEOUT)
    except Exception as e:  # noqa: BLE001 — 跑不动 = 无法自证，不外抛
        return None, "跑 run_guards --list 抛异常 %r" % e
    if p.returncode != 0:
        tail = ((p.stdout or "") + (p.stderr or "")).strip().splitlines()
        return None, "run_guards --list rc=%d：%s" % (p.returncode, tail[-1][:160] if tail else "")
    counts = parse_counts(p.stdout or "")
    if counts is None:
        return None, "run_guards --list 输出里解析不到汇总行（读数文法改了？）"
    return counts, ""


def compare(reg, reading):
    """逐键对表，返回违例行（空列表 = 一致）。"""
    problems = []
    for idx, key in enumerate(KEY_ORDER, 1):
        want, got = reg[key], reading[key]
        if want == got:
            continue
        if key == "missing" and got > 0:
            problems.append("X%d 缺执行面现读 %d（登记 %d）：有尺没有执行面，先修 G1 再加数"
                            % (idx, got, want))
        elif got < want:
            problems.append("X%d %s 欠格：登记 %d / 现读 %d（现读少于登记——格子或尺被删，"
                            "或登记没随删减更新）" % (idx, KEY_CN[key], want, got))
        else:
            problems.append("X%d %s 登记落后：登记 %d / 现读 %d（新增尺/格子后没同批更新 README "
                            "的 %s 锚点）" % (idx, KEY_CN[key], want, got, ANCHOR))
    return problems


def fatal(msg):
    """判据无法自证 -> 真给 2（带字符串的 SystemExit 实给 1，BUG-369）。"""
    sys.stderr.write("FATAL: %s\n" % msg)
    return 2


def selftest():
    """合成夹具自证 + 真源现状对照。返回 (fails, executed)。"""
    fails = []
    executed = []

    def cell(name, cond, detail=""):
        executed.append(name)
        if not cond:
            fails.append((name, detail))

    reg = dict(rulers=82, ci=40, battery=44, missing=0, gate=54, exempt=26, unclassified=4)
    sample = ("尺 82 把 / CI 面 40 / 电池面 44 / 缺执行面 0\n"
              "分类记账：门禁尺 54 / 豁免（带理由）26 / 未归类 4\n")
    marker = ("- `run_guards.py` — 条目正文\n"
              "  **BATTERY-REGISTRATION**：`rulers=82 ci=40 battery=44 missing=0 "
              "gate=54 exempt=26 unclassified=4`\n\n- `other.py` — 下一条\n")

    cell("G1-clean-registration-not-red", compare(reg, dict(reg)) == [])
    cell("G2-real-format-parses", parse_counts(sample) == reg)
    cell("G3-duplicate-copies-agree-not-red", parse_registration(marker) == (reg, ""), "抄本一致须不红")

    for idx, key in enumerate(("rulers", "battery", "ci", "missing", "gate", "exempt", "unclassified"), 1):
        bad = dict(reg)
        bad[key] = reg[key] + (1 if key == "missing" else (1 if idx % 2 else -1))
        if bad[key] < 0:
            bad[key] = reg[key] + 1
        problems = compare(reg, bad)
        cell("M%d-%s-drift-red" % (idx, key),
             len(problems) == 1 and (key in problems[0] or KEY_CN[key] in problems[0]),
             "单键漂移须恰好一条违例：%r" % problems)

    no_anchor = "- `run_guards.py` — 条目正文，没有锚点\n\n- `other.py` — x\n"
    reg_bad, why = parse_registration(no_anchor)
    cell("M8-anchor-missing-self-refuse", reg_bad is None and bool(why), why)

    malformed = "- `run_guards.py` — x\n  **BATTERY-REGISTRATION**：`rulers=oops`\n"
    reg_bad, why = parse_registration(malformed)
    cell("M9-anchor-malformed-self-refuse", reg_bad is None and bool(why), why)

    conflict = ("- `run_guards.py` — x\n"
                "  **BATTERY-REGISTRATION**：`rulers=82 ci=40 battery=44 missing=0 "
                "gate=54 exempt=26 unclassified=4`\n"
                "  **BATTERY-REGISTRATION**：`rulers=81 ci=40 battery=44 missing=0 "
                "gate=54 exempt=26 unclassified=4`\n")
    reg_bad, why = parse_registration(conflict)
    cell("M10-duplicate-copies-conflict-refuse", reg_bad is None and bool(why), why)

    cell("M11-empty-list-output-self-refuse", parse_counts("") is None)

    try:
        with io.open(os.path.join(ROOT, DOC), encoding="utf-8-sig", errors="replace") as f:
            text = f.read()
        real_reg, why_reg = parse_registration(text)
        real_read, why_read = read_counts()
        ok = real_reg is not None and real_read is not None and compare(real_reg, real_read) == []
        cell("R1-real-readme-vs-real-list-green", ok,
             "reg=%r（%s） reading=%r（%s）" % (real_reg, why_reg, real_read, why_read))
    except Exception as e:  # noqa: BLE001 — 真源面异常记失败，不吞
        cell("R1-real-readme-vs-real-list-green", False, repr(e))
    return fails, executed


def main(argv):
    args = list(argv)
    if "--selftest" in args:
        fails, executed = selftest()
        if fails:
            print("SELFTEST FAIL: %d/%d 格红" % (len(fails), len(executed)))
            for name, detail in fails:
                print("  - %s：%s" % (name, detail))
            return 1
        fam = {}
        for name in executed:
            key = name.split("-")[0][:1].upper()
            fam[key] = fam.get(key, 0) + 1
        print("SELFTEST OK: %d 格（反解：%s，族名取自已执行格子名首段首字母，不手写计数）"
              % (len(executed), " / ".join("%s×%d" % (k, v) if v > 1 else k
                                           for k, v in sorted(fam.items()))))
        return 0

    try:
        with io.open(os.path.join(ROOT, DOC), encoding="utf-8-sig", errors="replace") as f:
            text = f.read()
    except OSError as e:
        return fatal("%s 读不到：%r" % (DOC, e))
    reg, why = parse_registration(text)
    if reg is None:
        return fatal(why)
    reading, why = read_counts()
    if reading is None:
        return fatal(why)
    problems = compare(reg, reading)
    if problems:
        print("FAIL 电池读数与 README 登记漂移 %d 处：" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS 电池读数与 README 登记逐键一致：%s"
          % " ".join("%s=%d" % (k, reg[k]) for k in KEY_ORDER))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了走 4 号档，不冒用 1
        sys.stderr.write("FATAL(4): 尺子自己坏了：%r\n" % (e,))
        sys.exit(4)
