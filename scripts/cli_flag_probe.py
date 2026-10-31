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


def help_banner_prefix():
    """从**被检面**反解帮助横幅的前缀（`"FIST-Mbt Help  v"` 这一段，`cmd/cli/help_topics.mbt`）。

    为什么必须反解而不是在夹具里写一遍（判例-30「期望值的字面形要同面取」）：
    夹具原来写着 `FIST-Mbt CLI v<ver>`，而产品早在横幅里插了个 topic 标签
    （现读是 `FIST-Mbt Help  v0.3.11  (182 MCP tools)`）⇒ 判据的针认不出真实形状，
    三条帮助臂**集体假红**（CI 第 53 步，BUG-522）。反解之后产品的形状一变，夹具跟着变，
    不会再出现「产品没错、夹具脱锚」这种红。读不到 ⇒ FATAL 自拒，不拿旧字面量凑。
    """
    src = io.open(os.path.join(ROOT, "cmd", "cli", "help_topics.mbt"),
                  encoding="utf-8", errors="replace").read()
    m = re.search(r'"(FIST-Mbt[^"]*)"\s*\+\s*\n\s*v\s*\+', src)
    if not m:
        raise SystemExit("FATAL cmd/cli/help_topics.mbt 反解不到帮助横幅前缀 ⇒ 判据看不见被检面，不报绿")
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
        if first.strip() != "FIST-Mbt v%s" % ver:
            problems.append("%-11s 首行没回显 moon.mod 版本 %s，实得 %r（BUG-114 源码常量漂移 / BUG-359 反向版本漂移）"
                            % (arm, ver, first[:48]))
    for arm in ARMS_HELP:
        rc, out = transcript[arm]
        if rc != 0:
            problems.append("%-11s rc=%s（帮助旗应 0）" % (arm, rc))
        if marker in out:
            problems.append("%-11s 落了未知子命令文案（BUG-106 第一半复发）" % arm)
        first_h = (out.split("\n")[0] if out else "").strip()
        # 只认「**首行**同时有 `FIST-Mbt` 与 `v<ver>`」——中间允许产品放 topic 标签（现读是 `Help`）。
        # 不锚首行的话，帮助正文里任何一处版本号都会替横幅说谎（判例-35：针要盯在被检的那一面）。
        if not re.search(r"^FIST-Mbt\b.*\bv%s\b" % re.escape(ver), first_h):
            problems.append("%-11s 帮助面不回显版本 %s（帮助自己也是自述面），实得 %r"
                            % (arm, ver, first_h[:56]))
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


def good_transcript(ver, marker, banner=None):
    t = {}
    # 帮助臂用**从被检面反解的横幅前缀**拼夹具（判例-30：期望值的字面形要同面取）；
    # 只有合成对照（R6 那类）需要假形状时，调用方才显式传 banner。
    head = banner if banner is not None else help_banner_prefix()
    for arm in ARMS_VERSION:
        t[arm] = (0, "FIST-Mbt v%s\n(moon.mod version 单一真源)" % ver)
    for arm in ARMS_HELP:
        t[arm] = (0, "%s%s  (N MCP tools)\n用法: fist <subcommand>" % (head, ver))
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
    # 反脱锚三格（BUG-522：夹具曾写着 `FIST-Mbt CLI v…` 而产品现印 `FIST-Mbt Help  v…`，
    # 三条帮助臂集体假红；G1 的头现在**从被检面反解**，产品的形状一变夹具跟着变）：
    # 针既要认得**没有标签**的旧形状（不许过拟合到某一个字面），又不许把「正文里出现过版本号」当横幅自述。
    cases.append(("G2 无标签旧形状照样认", good_transcript(ver, marker, banner="FIST-Mbt v"), False))
    cases.append(("G3 帮助面一个版本号都没有",
                  good_transcript(ver, marker, banner="FIST-Mbt Help  "), True))
    cases.append(("G4 版本号只在正文不在首行 ⇒ 仍算说谎",
                  {"version": (0, "FIST-Mbt v%s\n" % ver), "--version": (0, "FIST-Mbt v%s\n" % ver),
                   "-V": (0, "FIST-Mbt v%s\n" % ver),
                   "help": (0, "FIST-Mbt Help\n正文里提到 v%s 过\n" % ver),
                   "--help": (0, "FIST-Mbt Help\n正文里提到 v%s 过\n" % ver),
                   "-h": (0, "FIST-Mbt Help\n正文里提到 v%s 过\n" % ver),
                   UNKNOWN_ARG: (2, "%s%s\n" % (marker, UNKNOWN_ARG))}, True))
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
        sys.exit(1)  # NO_CALL_FACE J2
    # 自述面：对照清单从 cases 反解，别手写（手写的范围数字会变成没人认领的主张）
    reds = ", ".join(n.split()[0] for n, _, must in cases if must)
    print("SELFTEST OK：%d 支对照全按预期（违例必红 %s / 干净必绿）" % (len(cases), reds))
    sys.exit(0)  # NO_CALL_FACE J2


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
