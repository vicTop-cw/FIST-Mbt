#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_publish_payload.py — 「发布载荷面」守卫（BUG-127 的常驻判据）。

背景：`moon publish` 的打包面是 **工作树 − .gitignore**，**不是** git 跟踪面，且点号开头的文件/目录一律不进包。
0.3.4 那次发布后解注册表载荷对表，量到两件方向相反的事：
  · 载荷里多 1 件不在 git 里（`__cli_pkg.mbt.tmp`，moon 生成的临时件）⇒ 本地残留跟着公开了；
  · 载荷里少 18 件在 git 里（`.github/*`、`.mcp.dev.json` 等点号条目）⇒ 「一源四态」的 MCP 配置面本来就不随包走。
所以「扫了 git 面」不等于「扫了公开面」——这道守卫把那句话变成可执行判据，且**离线可跑**（不联网、不起进程）。

判据（两个方向都发红）：
  P1  未被 .gitignore 挡住、又**没有被 git 跟踪**的非点号文件 ⇒ 红：下一次 `moon publish` 会把它公开出去。
      （这正是 `__cli_pkg.mbt.tmp` 的形状；跟踪文件是有意公开的，不在红面里。）
  P2  红面里若出现凭据形状（`ghp_`/`github_pat_`/`sk-`/`Bearer`/`PRIVATE-TOKEN:`/slack-telegram webhook）⇒ 单独点名，
      这类不是卫生问题而是事故，必须当场人审。
  P3  扫描面自证：git 不可用 / 一条文件都没列出来 ⇒ FATAL(2)（判据看不见样本就等于没判，J10/BUG-118 同族）。
  信息项（不发红）：被 moon 排除在包外的点号跟踪文件清单——让发布人知道消费方拿不到什么。

`--selftest`：G1 干净不误红（工作树带未跟踪件时自动换成 G1'：逐件点名且无幻影红）/
              M1 造一个未跟踪未忽略文件 ⇒ 必红 / M2 造一个被现成 `*.log` 规则挡住的未跟踪文件 ⇒ 必不红 /
              M3 红面里塞凭据形状 ⇒ 必须点名 P2。造件与拆件都在仓库根，`finally` 里逐个删并复核盘上无残留。

用法：python scripts/check_publish_payload.py [--selftest]
退出码：0=PASS，1=违例，2=判据无法自证。
"""
import argparse
import io
import os
import re
import subprocess
import sys

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

SECRET_RE = re.compile(
    r'ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9]{16,}'
    r'|Bearer [A-Za-z0-9_\-]{16,}|PRIVATE-TOKEN: [A-Za-z0-9_\-]{8,}'
    r'|hooks\.slack\.com|api\.telegram\.org/bot[0-9]')

PROBE = "zz_publish_payload_probe.txt"        # M1：未跟踪且未被忽略 ⇒ 必红
PROBE_IG = "zz_publish_payload_probe.log"     # M2：未跟踪但被现成 `*.log` 规则挡住 ⇒ 必不红
PROBE_SECRET = "zz_publish_payload_secret.txt"  # M3：红面里塞凭据形状 ⇒ 必点名 P2


def _git(*args):
    p = subprocess.run(("git",) + args, cwd=ROOT, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("git %s 失败：%s" % (" ".join(args),
                                               p.stderr.decode("utf-8", "replace").strip()[:120]))
    return [l.strip() for l in p.stdout.decode("utf-8", "replace").splitlines() if l.strip()]


def surfaces():
    """返回 (会被公开的件, 未跟踪未忽略的件, 被 moon 排除的点号跟踪件)。"""
    tracked = set(_git("ls-files", "--cached"))
    untracked = set(_git("ls-files", "--others", "--exclude-standard"))
    will_ship = sorted(x for x in tracked | untracked if not _is_dotpath(x))
    leaky = sorted(x for x in untracked if not _is_dotpath(x))
    dropped = sorted(x for x in tracked if _is_dotpath(x))
    return will_ship, leaky, dropped


def _is_dotpath(rel):
    return any(part.startswith(".") for part in rel.replace("\\", "/").split("/"))


def scan():
    will_ship, leaky, dropped = surfaces()
    problems = []
    if not will_ship:
        return will_ship, dropped, ["P3 打包面一个文件都没列出来 ⇒ 判据空转，绝不报绿"]
    for f in leaky:
        problems.append("P1 %s 未被 .gitignore 挡住又没被 git 跟踪 ⇒ `moon publish` 会把它公开出去"
                        "（载荷面=工作树−ignore，不是 git 跟踪面；修法：入库或进 .gitignore）" % f)
    for f in leaky:
        p = os.path.join(ROOT, f.replace("/", os.sep))
        try:
            body = io.open(p, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        m = SECRET_RE.search(body)
        if m:
            problems.append("P2 %s 里是凭据形状（%s…）⇒ 这不是卫生问题是事故：先发出去的版本撤不回，"
                            "必须立刻人审并按 deprecate 流程处理" % (f, m.group(0)[:6]))
    return will_ship, dropped, problems


def _rm(path):
    try:
        os.remove(path)
        return True
    except OSError:
        return False


def selftest():
    executed, fails = [], []
    probes = [os.path.join(ROOT, n) for n in (PROBE, PROBE_IG, PROBE_SECRET)]
    taken = [os.path.basename(p) for p in probes if os.path.exists(p)]
    if taken:
        print("SELFTEST FAIL 自证用文件名已被占用，拒绝覆盖：%s" % ", ".join(taken))
        return 2
    try:
        will_ship, _d, probs = scan()
        leaky_now = surfaces()[1]
        if leaky_now:
            # 起手时工作树本就带未跟踪件（比如正在开发的这份守卫自己）⇒ "干净不误红"这一格此时无从验证，
            # 改验更强的那条：每个未跟踪件都有一条 P1 点名它，且不许有点名不存在文件的幻影红。
            # （P2 可以和 P1 同件并存——一个残留既是要挡的又可能带凭据，所以不拿红条数当分母。）
            executed.append("G1' 现状带未跟踪件时：逐件点名且无幻影红")
            p1 = [p for p in probs if p.startswith("P1")]
            if len(p1) != len(leaky_now):
                fails.append("G1' 不符：P1 %d 条 vs 未跟踪件 %d 件" % (len(p1), len(leaky_now)))
            for f in leaky_now:
                if not any(f in p for p in p1):
                    fails.append("G1' 漏点名：%s 在未跟踪面里却没有对应的 P1" % f)
            for p in probs:
                if not any(f in p for f in leaky_now):
                    fails.append("G1' 幻影红（点名了不存在的件）：%s" % p[:80])
        else:
            executed.append("G1 干净不误红")
            if probs:
                fails.append("G1 干净输入被误判：%s" % probs[:2])

        io.open(probes[0], "w", encoding="utf-8").write("publish-surface selftest probe\n")
        _s, _d, probs = scan()
        executed.append("M1 未跟踪未忽略的文件必红")
        if not any(p.startswith("P1") and PROBE in p for p in probs):
            fails.append("M1 未红：造出来的本地残留没被抓到（= 判据看不见公开面）")
        _rm(probes[0])

        io.open(probes[1], "w", encoding="utf-8").write("ignored by the pre-existing *.log rule\n")
        _s, _d, probs = scan()
        executed.append("M2 被 .gitignore 挡住则不红")
        if any(PROBE_IG in p for p in probs):
            fails.append("M2 误红：.gitignore 挡住的件仍被算进公开面 ⇒ 与 moon 的打包规则不一致")
        _rm(probes[1])

        # 一眼可辨的假串，运行时拼出来——**源码里不许出现完整形状**，否则本守卫会把自己的正文当凭据（自证时实测到）
        io.open(probes[2], "w", encoding="utf-8").write("token: " + "ghp_" + "N0TAREAL" * 3 + "\n")
        _s, _d, probs = scan()
        executed.append("M3 红面里的凭据形状必点名 P2")
        if not any(p.startswith("P2") and PROBE_SECRET in p for p in probs):
            fails.append("M3 未红：载荷里躺着凭据形状却只报了 P1 ⇒ 事故与卫生混成一格")
        _rm(probes[2])
    finally:
        for p in probes:
            _rm(p)
        left = [os.path.basename(p) for p in probes if os.path.exists(p)]
        if left:
            fails.append("自证残留没清干净：%s" % ", ".join(left))

    will_ship, dropped, _p = scan()
    leaky = surfaces()[1]
    print("SELFTEST %s（已执行格子：%s；打包面 %d 件 / 其中未跟踪未忽略 %d 件 / 被 moon 排除的点号件 %d 件）"
          % ("OK" if not fails else "FAIL", " / ".join(executed),
             len(will_ship), len(leaky), len(dropped)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    will_ship, dropped, problems = scan()
    for p in problems:
        print("VIOLATION " + p)
    if problems:
        return 1
    print("PASS 发布载荷面干净：将随包公开 %d 件，其中未被 git 跟踪的 0 件（另有 %d 件点号条目 moon 本来就不打包）"
          % (len(will_ship), len(dropped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
