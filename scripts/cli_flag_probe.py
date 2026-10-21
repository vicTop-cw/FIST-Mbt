# -*- coding: utf-8 -*-
r"""调用面判据：全局命令的旗与退出码必须**真的**对得上（BUG-106 第二半 + BUG-114 的入口锁）。

为什么单开一条（白盒测试不够）：
  · `cmd/cli/subcmd_wbtest.mbt` 钉的是词法函数 `parse_subcmd` / `exit_code_of`——
    它在 `main` 被改回字符串 match、或 `cli_exit` 被摘掉之后**照样全绿**（模块有实现 ≠ 入口可用）。
  · BUG-114 的形态正是"有常驻回归锁、锁也红了，但没人从入口读"：装出来的 `fist version` 回 v0.3.0，
    而横幅/文档/moon.mod 都是 0.3.3。所以这里必须起真产物、看真 rc、读真首行。

三档判据（缺一不可）：
  1. `version` / `--version` / `-V` ⇒ rc=0 且**首行**回显 moon.mod 的版本（源码常量漂移即红）
  2. `help` / `--help` / `-h`       ⇒ rc=0、不落"未知子命令"文案、且回显当前版本（帮助面自述也不许说谎）
  3. 未知参数                       ⇒ rc≠0（BUG-106：`未知子命令` 却回 0，会让 `fist --version || exit 1` 把失败读成成功）

文案针（"未知子命令"）从 `cmd/cli/main.mbt` 反解，版本针从 `moon.mod` 反解——
两处都不抄字面量，否则判据自己会变成第二个真源。
"""
import argparse
import io
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_PRODUCT = os.path.join(ROOT, "_build", "js", "debug", "build", "cmd", "cli", "cli.js")
ARMS_VERSION = ["version", "--version", "-V"]
ARMS_HELP = ["help", "--help", "-h"]
UNKNOWN_ARG = "__probe_not_a_subcommand__"


def mod_version():
    m = re.search(r'^version\s*=\s*"([^"]+)"',
                  io.open(os.path.join(ROOT, "moon.mod"), encoding="utf-8").read(), re.M)
    if not m:
        raise SystemExit("FATAL moon.mod 反解不到 version ⇒ 判据没有基线，绝不报绿")
    return m.group(1)


def unknown_marker():
    """从被检面的源码反解"未知子命令"文案前缀（插值模板之前的那一段）。"""
    src = io.open(os.path.join(ROOT, "cmd", "cli", "main.mbt"), encoding="utf-8").read()
    m = re.search(r'println\("([^"\\]*未知[^"\\]*)', src)
    if not m:
        raise SystemExit("FATAL cmd/cli/main.mbt 反解不到未知子命令文案 ⇒ 判据看不见被检面，不报绿")
    return m.group(1)


def judge(transcript, ver, marker):
    """纯判定：转录 = {参数: (rc, stdout)}。返回问题清单（空 == 绿）。"""
    problems = []
    if not transcript:
        return ["判据拿不到任何调用回执 ⇒ 自拒，不报绿"]
    missing = [a for a in ARMS_VERSION + ARMS_HELP + [UNKNOWN_ARG] if a not in transcript]
    if missing:
        return ["转录缺臂 %s ⇒ 判据自拒（缺样本＝没测，不是测过且对）" % ", ".join(missing)]
    for arm in ARMS_VERSION:
        rc, out = transcript[arm]
        first = (out.split("\n")[0] if out else "").strip()
        if rc != 0:
            problems.append("%-11s rc=%s（版本旗应 0）" % (arm, rc))
        if marker in out or marker in first:
            problems.append("%-11s 落了未知子命令文案（BUG-106 第一半复发）" % arm)
        if ver not in first:
            problems.append("%-11s 首行没回显 moon.mod 版本 %s，实得 %r（BUG-114：源码常量漂移）"
                            % (arm, ver, first[:48]))
    for arm in ARMS_HELP:
        rc, out = transcript[arm]
        if rc != 0:
            problems.append("%-11s rc=%s（帮助旗应 0）" % (arm, rc))
        if marker in out:
            problems.append("%-11s 落了未知子命令文案（BUG-106 第一半复发）" % arm)
        if ver not in out:
            problems.append("%-11s 帮助面不回显版本 %s（帮助自己也是自述面）" % (arm, ver))
    rc, out = transcript[UNKNOWN_ARG]
    if rc == 0:
        problems.append("未知子命令回 rc=0 ⇒ `fist --version || exit 1` 会把失败读成成功（BUG-106 第二半）")
    if marker not in out:
        problems.append("未知子命令没有点名被拒的是什么（拒绝要有形）")
    return problems


def run_product(product, arm):
    node = "node"
    try:
        p = subprocess.run([node, product, arm], cwd=ROOT, capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=120)
    except FileNotFoundError:
        raise SystemExit("FATAL  PATH 上没有 node ⇒ 调用面判据无法自证，不报绿")
    except subprocess.TimeoutExpired:
        raise SystemExit("FATAL  %s 无回执（120s）⇒ 不报绿" % arm)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def good_transcript(ver, marker):
    t = {}
    for arm in ARMS_VERSION:
        t[arm] = (0, "FIST-Mbt v%s\n(moon.mod version 单一真源)" % ver)
    for arm in ARMS_HELP:
        t[arm] = (0, "FIST-Mbt CLI v%s\n用法: fist <subcommand>" % ver)
    t[UNKNOWN_ARG] = (2, "%s%s\n用法: fist <subcommand>" % (marker, UNKNOWN_ARG))
    return t


def selftest(ver, marker):
    """判据必须先证明自己会红：违例必红 + 干净必绿 + 缺样本必自拒。
    对照清单就是下面的 cases —— 计数一律从它反解，不手写第二份。"""
    cases = []
    t = good_transcript(ver, marker)
    for arm in ["--version", "-V"]:
        t[arm] = (0, "%s%s" % (marker, arm))
    cases.append(("R1 版本旗被当未知子命令", t, True))
    t = good_transcript(ver, marker)
    t[UNKNOWN_ARG] = (0, "%s%s" % (marker, UNKNOWN_ARG))
    cases.append(("R2 未知子命令回 0", t, True))
    t = good_transcript(ver, marker)
    t["version"] = (0, "FIST-Mbt v0.0.0-stale\n")
    cases.append(("R3 版本自述落后（源码常量漂移）", t, True))
    t = good_transcript(ver, marker)
    t["--help"] = (0, "FIST-Mbt CLI v0.0.0-stale\n用法: fist <subcommand>")
    cases.append(("R6 帮助面版本说谎", t, True))
    t = good_transcript(ver, marker)
    del t["--help"]
    cases.append(("R4 缺臂（转录不完整）", t, True))
    cases.append(("R5 零样本（判据瞎了）", {}, True))
    cases.append(("G1 干净三档全对", good_transcript(ver, marker), False))
    bad = 0
    for name, tr, must_red in cases:
        got = judge(tr, ver, marker)
        red = bool(got)
        ok = (red if must_red else not red)
        print("  %-26s %s  %s" % (name, "红" if red else "绿", "符合预期" if ok else "不符合预期"))
        if not ok:
            bad += 1
            for p in got[:2]:
                print("      └ %s" % p)
        elif red:
            print("      └ 原因可见：%s" % got[0][:88])
    if bad:
        print("SELFTEST FAIL：%d/%d 支不符预期" % (bad, len(cases)))
        return 1
    # 自述面：对照清单从 cases 反解，别手写（手写的范围数字会变成没人认领的主张）
    reds = ", ".join(n.split()[0] for n, _, must in cases if must)
    print("SELFTEST OK：%d 支对照全按预期（违例必红 %s / 干净必绿）" % (len(cases), reds))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true", help="只跑合成对照，不起产物")
    ap.add_argument("--product", default=DEFAULT_PRODUCT, help="被检的 JS 产物路径")
    a = ap.parse_args()
    ver, marker = mod_version(), unknown_marker()
    if a.selftest:
        return selftest(ver, marker)
    if not os.path.isfile(a.product):
        print("FATAL 产物不存在：%s ⇒ 先 moon build --target js cmd/cli && python scripts/patch_esm_main.py"
              % a.product)
        return 2
    transcript = {}
    for arm in ARMS_VERSION + ARMS_HELP + [UNKNOWN_ARG]:
        transcript[arm] = run_product(a.product, arm)
    problems = judge(transcript, ver, marker)
    print("=== 调用面：node %s ===" % os.path.relpath(a.product, ROOT).replace("\\", "/"))
    for arm in ARMS_VERSION + ARMS_HELP + [UNKNOWN_ARG]:
        rc, out = transcript[arm]
        print("  %-32s rc=%-3s 首行=%s" % (arm, rc, (out.split("\n")[0] if out else "").strip()[:56]))
    if problems:
        print("FAIL %d 条：" % len(problems))
        for p in problems:
            print("  ✗ %s" % p)
        return 1
    print("PASS 调用面三档全对（版本旗=%s · 未知必非 0 · 帮助旗不落未知臂）" % ver)
    return 0


if __name__ == "__main__":
    sys.exit(main())
