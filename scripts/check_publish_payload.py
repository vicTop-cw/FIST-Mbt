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

`--selftest`：全部格子打**合成仓根**（temp 下一份真 git 仓：一条可公开的跟踪件 + 现成 `*.log` 忽略规则），
              一个字节都不落进真树（R153 的 hermetic 律；旧版在仓库根造探针再删，写面实测 6 处）。
              S0 沙箱形状自证（夹具空转 ⇒ 「不误红」白给，故先证 tracked/ignored 两面都在）/
              G1 干净不误红 / G2 带未跟踪件时逐件点名且无幻影红 /
              M1 造一个未跟踪未忽略文件 ⇒ 必红 / M2 造一个被现成 `*.log` 规则挡住的未跟踪文件 ⇒ 必不红 /
              M3 红面里塞凭据形状 ⇒ 必须点名 P2 / M4 变异对照：不是 git 仓的目录必被 S0 拒。
              仓根经**必填形参**注入（不走默认参——默认参流进读原语是本尺明文标注的漏红面，
              用它买隔离等于把尺放宽）。现状面（真仓打包面读数）归主面，不进 `--selftest`。

用法：python scripts/check_publish_payload.py [--selftest]
退出码：0=PASS，1=违例，2=判据无法自证。
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

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


def _git(root, *args):
    p = subprocess.run(("git",) + args, cwd=root, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("git %s 失败：%s" % (" ".join(args),
                                               p.stderr.decode("utf-8", "replace").strip()[:120]))
    return [l.strip() for l in p.stdout.decode("utf-8", "replace").splitlines() if l.strip()]


def _git_rc(root, *args):
    """沙箱专用：只回 (rc, stderr)，不抛——`_git` 的抛用在主面，建夹具时要按档处置失败。"""
    p = subprocess.run(("git",) + args, cwd=root, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    return p.returncode, p.stderr.decode("utf-8", "replace").strip()[:120]


def _git_out(root, *args):
    """沙箱专用：回 (rc, stdout)，不抛。"""
    p = subprocess.run(("git",) + args, cwd=root, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE)
    return p.returncode, p.stdout.decode("utf-8", "replace").strip()


def _is_own_worktree(dirpath):
    """夹具必须是**它自己**的 git 工作树根。

    为什么不能靠 `ls-files` 抛异常：Git 2.x 在非仓目录里 `ls-files` 是**不报错**的——
    它把当前目录当隐式工作树（`--cached` 回空、`--others` 照列未跟踪件），于是旧版
    `_sandbox_ok` 的 `try/except RuntimeError` 永远接不住「这里根本不是仓」。
    实测（M4 变异格暴露）：`C:\\Users\\<user>\\AppData\\Local\\Temp\\<dir>` 这类目录会
    向上命中祖先仓（`C:/Users/<user>`），`ls-files` 全部 rc=0 ⇒ 自证格成了装饰。
    判据改成「`--show-toplevel` == 夹具自身路径」，才对「读不到 git 面」真正发红。
    """
    rc, out = _git_out(dirpath, "rev-parse", "--show-toplevel")
    if rc != 0 or not out:
        return False
    try:
        return (os.path.normcase(os.path.realpath(out))
                == os.path.normcase(os.path.realpath(dirpath)))
    except OSError:
        return False


def surfaces(root):
    """返回 (会被公开的件, 未跟踪未忽略的件, 被 moon 排除的点号跟踪件)。"""
    tracked = set(_git(root, "ls-files", "--cached"))
    untracked = set(_git(root, "ls-files", "--others", "--exclude-standard"))
    will_ship = sorted(x for x in tracked | untracked if not _is_dotpath(x))
    leaky = sorted(x for x in untracked if not _is_dotpath(x))
    dropped = sorted(x for x in tracked if _is_dotpath(x))
    return will_ship, leaky, dropped


def _is_dotpath(rel):
    return any(part.startswith(".") for part in rel.replace("\\", "/").split("/"))


def scan(root):
    will_ship, leaky, dropped = surfaces(root)
    problems = []
    if not will_ship:
        return will_ship, dropped, ["P3 打包面一个文件都没列出来 ⇒ 判据空转，绝不报绿"]
    for f in leaky:
        problems.append("P1 %s 未被 .gitignore 挡住又没被 git 跟踪 ⇒ `moon publish` 会把它公开出去"
                        "（载荷面=工作树−ignore，不是 git 跟踪面；修法：入库或进 .gitignore）" % f)
    for f in leaky:
        p = os.path.join(root, f.replace("/", os.sep))
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


def _rmtree(path):
    """删合成仓根。git 把对象写成只读，Windows 上 rmtree 不处理只读会 PermissionError——
    残留没清就是往别人树上留垃圾，故必须清位重试而不是吞掉。"""
    def _clear(func, p, _exc):
        try:
            os.chmod(p, 0o700)
            func(p)
        except OSError:
            pass
    shutil.rmtree(path, onerror=_clear)


def _sandbox(dirpath):
    """在 dirpath 里造一份真 git 仓：一条可公开的跟踪件（README.md）+ 现成的 `*.log` 忽略规则。

    夹具必须是**真 git 仓**——本尺的输入面全靠 `git ls-files` 两种旗标；非 git 目录里查询直接失败，
    夹具会退化成「扫了个空」，于是「不误红」那一格永远白给。
    """
    git_args = ("-c", "user.name=selftest", "-c", "user.email=selftest@sandbox.invalid")
    rc, err = _git_rc(dirpath, "init", "-q")
    if rc != 0:
        raise RuntimeError("沙箱 git init 失败（rc=%d）：%s" % (rc, err))
    io.open(os.path.join(dirpath, ".gitignore"), "w", encoding="utf-8").write("*.log\n")
    io.open(os.path.join(dirpath, "README.md"), "w", encoding="utf-8").write("# sandbox\n")
    rc, err = _git_rc(dirpath, "add", "-A")
    if rc != 0:
        raise RuntimeError("沙箱 git add 失败（rc=%d）：%s" % (rc, err))
    rc, err = _git_rc(dirpath, *git_args, "commit", "-q", "-m", "夹具基线")
    if rc != 0:
        raise RuntimeError("沙箱 git commit 失败（rc=%d）：%s" % (rc, err))
    return dirpath


def _sandbox_ok(dirpath):
    """沙箱形状自证：夹具要证明「判据判的东西真在场」，否则绿色是白给的。"""
    # 先证「这确实是它自己的仓」——`ls-files` 在非仓目录不抛（Git 2.x 隐式工作树），
    # 旧版靠异常分流会让本函数在非仓目录回 True（M4 变异格抓到）。
    if not _is_own_worktree(dirpath):
        return False, "读不到夹具面（%s 不是它自己的 git 工作树根）" % dirpath
    try:
        will_ship, _leaky, _dropped = surfaces(dirpath)
    except RuntimeError as e:
        return False, "读不到夹具面（不是可用的 git 仓？）：%s" % e
    if not will_ship:
        return False, "夹具里没有可公开的跟踪件 ⇒ P3 空转格会把「判据看不见样本」读成正常"
    probe = os.path.join(dirpath, "zz_sandbox_ignore.log")
    io.open(probe, "w", encoding="utf-8").write("ignore-rule witness\n")
    try:
        if any(PROBE_IG in x for x in surfaces(dirpath)[1]):
            return False, "夹具的 `*.log` 忽略规则没生效 ⇒ M2「挡住则不红」验的是空气"
    finally:
        _rm(probe)
    return True, ""


def selftest():
    executed, fails = [], []
    box = None
    try:
        try:
            box = _sandbox(os.path.abspath(tempfile.mkdtemp(prefix="cpp-selftest-")))
        except (RuntimeError, OSError) as e:
            print("SELFTEST FAIL 合成夹具起不来（判据无法自证，不冒用违例档）：%s" % e)
            return 2
        ok, why = _sandbox_ok(box)
        executed.append("S0 沙箱形状自证（tracked + 忽略规则都在场）")
        if not ok:
            fails.append("S0 不符：%s" % why)

        # M4 变异对照：不是 git 仓的目录必被 S0 拒——不配这一格，S0 只是「一切正常时的顺手绿」
        bad = os.path.abspath(tempfile.mkdtemp(prefix="cpp-selftest-bad-"))
        try:
            io.open(os.path.join(bad, "README.md"), "w", encoding="utf-8").write("# not a repo\n")
            bok, _bwhy = _sandbox_ok(bad)
        finally:
            _rmtree(bad)
        executed.append("M4 变异：非 git 仓的夹具必被 S0 自拒")
        if bok:
            fails.append("M4 未红：S0 连「读不到 git 面」都放行 ⇒ 自证格是装饰")

        _s, _d, probs = scan(box)
        executed.append("G1 干净夹具不误红")
        if probs:
            fails.append("G1 干净输入被误判：%s" % probs[:2])

        # G2：带未跟踪件时必须**逐件点名**且不许有点名不存在文件的幻影红
        # （旧版这一格寄生在真工作树的脏净上，树干净时整格跳过；合成夹具后恒可验）
        extra = [os.path.join(box, n) for n in ("zz_stray_a.txt", "zz_stray_b.txt")]
        for p in extra:
            io.open(p, "w", encoding="utf-8").write("stray\n")
        _s, _d, probs = scan(box)
        p1 = [p for p in probs if p.startswith("P1")]
        leaked = surfaces(box)[1]
        executed.append("G2 带未跟踪件时：逐件点名且无幻影红")
        if len(p1) != len(leaked):
            fails.append("G2 不符：P1 %d 条 vs 未跟踪件 %d 件" % (len(p1), len(leaked)))
        for f in leaked:
            if not any(f in p for p in p1):
                fails.append("G2 漏点名：%s 在未跟踪面里却没有对应的 P1" % f)
        for p in probs:
            if not any(f in p for f in leaked):
                fails.append("G2 幻影红（点名了不存在的件）：%s" % p[:80])
        for p in extra:
            _rm(p)

        io.open(os.path.join(box, PROBE), "w", encoding="utf-8").write("publish-surface selftest probe\n")
        _s, _d, probs = scan(box)
        executed.append("M1 未跟踪未忽略的文件必红")
        if not any(p.startswith("P1") and PROBE in p for p in probs):
            fails.append("M1 未红：造出来的本地残留没被抓到（= 判据看不见公开面）")
        _rm(os.path.join(box, PROBE))

        io.open(os.path.join(box, PROBE_IG), "w", encoding="utf-8").write("ignored by the pre-existing *.log rule\n")
        _s, _d, probs = scan(box)
        executed.append("M2 被 .gitignore 挡住则不红")
        if any(PROBE_IG in p for p in probs):
            fails.append("M2 误红：.gitignore 挡住的件仍被算进公开面 ⇒ 与 moon 的打包规则不一致")
        _rm(os.path.join(box, PROBE_IG))

        # 一眼可辨的假串，运行时拼出来——**源码里不许出现完整形状**，否则本守卫会把自己的正文当凭据（自证时实测到）
        io.open(os.path.join(box, PROBE_SECRET), "w", encoding="utf-8").write(
            "token: " + "ghp_" + "N0TAREAL" * 3 + "\n")
        _s, _d, probs = scan(box)
        executed.append("M3 红面里的凭据形状必点名 P2")
        if not any(p.startswith("P2") and PROBE_SECRET in p for p in probs):
            fails.append("M3 未红：载荷里躺着凭据形状却只报了 P1 ⇒ 事故与卫生混成一格")
        _rm(os.path.join(box, PROBE_SECRET))

        # 幂等自证：所有探针拆完后夹具必须回到 G1 那一格的形状（拆不干净 ⇒ 下一格在判上一格的残留）
        _s, _d, probs = scan(box)
        executed.append("M5 拆件后夹具回到干净形状（幂等）")
        if probs:
            fails.append("M5 未红：探针没拆干净，夹具残留会喂给后续格子：%s" % probs[:2])
    finally:
        if box is not None:
            _rmtree(box)
        if box is not None and os.path.exists(box):
            fails.append("合成夹具没清干净：%s" % box)

    print("SELFTEST %s（已执行格子：%s；以上全部打在 temp 合成仓根上，真树一字节未动）"
          % ("OK" if not fails else "FAIL", " / ".join(executed)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    will_ship, dropped, problems = scan(ROOT)
    for p in problems:
        print("VIOLATION " + p)
    if problems:
        return 1
    print("PASS 发布载荷面干净：将随包公开 %d 件，其中未被 git 跟踪的 0 件（另有 %d 件点号条目 moon 本来就不打包）"
          % (len(will_ship), len(dropped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
