#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_battery_isolation.py — 「跑完一条命令，git 跟踪面必须一格未变」判据（R101）。

为什么要有这把尺（两条实锤，都出在本仓自家电池身上）：
  1. 2026-10-22 R98 全量电池跑到中途，`src/router/router_state.mbt` 与 `model_router_wbtest.mbt`
     在工作树里被刷成「同一个 struct literal 里 `use_caf_memory` 重复插入」——编译必红的形状，
     来源是电池里某格执行了会改跟踪面的补丁脚本（真因在 `patch_router_config_caf_field.py`，R99 已修）。
     当时是我手工 `git checkout --` 收的场，而「电池脏了跟踪面」这件事**没有任何判据会红**。
  2. `mcp_bug_loop.py` 这类 e2e 会把演示行写进真台账 `memory/bugs.md`；`check_demo_isolation`
     只钉 `FIST_DB_PATH` 一个方向（库改道），钉不到「文件面被写脏」。

本判据只回答一个问题：**被包住的那条命令，跑完之后 git 视图变没变**。它不判那条命令成功与否
（那是那条命令自己的契约），所以被包命令的退出码只回显在 `WRAPPED_RC=<n>` 行上，
**绝不借用本判据的退出码字母表**——`sys.exit(p.returncode)` 那一类透传正是
`check_exit_code_contract` 点名抓的不透明出口（BUG-369），本工具一个都不留。

用法：
  python scripts/check_battery_isolation.py                      # 裸跑＝有界自检（快照→空操作子进程→快照，必绿）
  python scripts/check_battery_isolation.py --selftest            # 合成违例 + 规则失明对照（尺子先证明自己会红）
  python scripts/check_battery_isolation.py -- python -c "..."    # 包住一条命令跑，判它脏没脏
  python scripts/check_battery_isolation.py --repo <dir> -- <cmd...>   # 对别的仓跑（自检格用临时沙箱仓）

退出码：0=跟踪面未变（隔离合格）/ 1=检出变化（逐条点名，含「原本脏、被命令洗掉了」这一档）/
2=判据无法自证（不在 git 仓、取不到 git、被包命令根本没起来＝什么都没测到，不冒用 1 那一档）/
4=尺子自己坏了（未捕获异常，写 `RULER BROKEN` 后退出，绝不冒用 1 或 2）。
"""
import hashlib
import os
import subprocess
import sys
from pathlib import Path

# BUG-58/138：本脚本 print 非 ASCII，Windows 控制台（cp936）下不重配会当场 UnicodeEncodeError。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ALL_RULES = ("diff-added", "diff-content", "diff-cleaned", "untracked-added", "untracked-cleaned")


def _git(repo, args):
    """返回 (rc, 文本)。git 不可用 ⇒ FileNotFoundError 交给调用方判 2，不在这里吞。"""
    r = subprocess.run(["git", "-C", str(repo)] + args,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.returncode, (r.stdout or "")


def snapshot(repo):
    """git 视图指纹 = 每脏文件的 diff 切片哈希 + 未跟踪文件清单。刻意**不看 mtime**：
    只被 touch 过而内容未变的文件不构成污染；反过来内容变了却状态字母不变（R98 的重复插入就是这形）
    必须抓得到，所以按 diff 切片取哈希，不按 `git status` 的行取。"""
    _, dtxt = _git(repo, ["-c", "core.safecrlf=false", "diff", "HEAD", "--no-color"])
    _, utxt = _git(repo, ["ls-files", "--others", "--exclude-standard"])
    return {"diff": diff_map(dtxt), "untracked": sorted(x for x in utxt.split("\n") if x.strip())}


def diff_map(dtxt):
    """`git diff HEAD` 正文按文件切块，逐块取哈希 ⇒ 内容一变哈希就变，与状态字母无关。"""
    out, cur, buf = {}, None, []
    for line in dtxt.split("\n"):
        if line.startswith("diff --git "):
            if cur is not None:
                out[cur] = hashlib.sha1("\n".join(buf).encode("utf-8")).hexdigest()
            cur = line.split(" b/")[-1].strip() or line
            buf = []
        elif cur is not None:
            buf.append(line)
    if cur is not None:
        out[cur] = hashlib.sha1("\n".join(buf).encode("utf-8")).hexdigest()
    return out


def detect(before, after, rules=ALL_RULES):
    """纯函数：两份快照 → 变化清单（人读字符串）。空清单＝隔离合格。
    `diff-cleaned` 那一档别删：命令把「本来就脏」的文件洗掉同样是改了工作树状态——
    R98 我手工 `git checkout --` 收场那一次，如果电池里有这么一条，读数会直接点名而不是静默。"""
    v = []
    bd, ad = before["diff"], after["diff"]
    if "diff-added" in rules:
        for p in sorted(set(ad) - set(bd)):
            v.append("POLLUTED diff-added %s" % p)
    if "diff-content" in rules:
        for p in sorted(set(ad) & set(bd)):
            if ad[p] != bd[p]:
                v.append("POLLUTED diff-content %s" % p)
    if "diff-cleaned" in rules:
        for p in sorted(set(bd) - set(ad)):
            v.append("UNDIRTY diff-cleaned %s" % p)
    if "untracked-added" in rules:
        for p in sorted(set(after["untracked"]) - set(before["untracked"])):
            v.append("POLLUTED untracked-added %s" % p)
    if "untracked-cleaned" in rules:
        for p in sorted(set(before["untracked"]) - set(after["untracked"])):
            v.append("UNDIRTY untracked-cleaned %s" % p)
    return v


def synth(diff_pairs, untracked):
    """合成快照：selftest 用，不碰任何盘。diff_pairs = {路径: 内容}"""
    return {"diff": {k: hashlib.sha1(v.encode("utf-8")).hexdigest() for k, v in diff_pairs.items()},
            "untracked": sorted(untracked)}


def selftest():
    """合成违例必红 + 干净必绿（反向对照）+ 规则失明对照（证明每条规则承重）。返回 (失败清单, 格数)。"""
    fails = []

    def cell(name, ok):
        if ok:
            print("  OK   %s" % name)
        else:
            print("  FAIL %s" % name)
            fails.append(name)

    clean_a, clean_b = synth({"x.mbt": "1"}, ["a.txt"]), synth({"x.mbt": "1"}, ["a.txt"])
    cell("clean-pair-not-reported", detect(clean_a, clean_b) == [])

    added = synth({"x.mbt": "1", "src/router/router_state.mbt": "insert"}, ["a.txt"])
    got = detect(clean_a, added)
    cell("dirty-appearing-is-named", got == ["POLLUTED diff-added src/router/router_state.mbt"])

    # R98 那一形：状态字母不变（还是 M），内容又插了一份 ⇒ 只有按内容取哈希才抓得到
    b2 = synth({"y.mbt": "one"}, [])
    a2 = synth({"y.mbt": "one-plus-dup-field"}, [])
    cell("content-drift-same-status-is-caught", detect(b2, a2) == ["POLLUTED diff-content y.mbt"])

    cell("cleaned-dirt-is-named-not-silent",
         detect(added, clean_a) == ["UNDIRTY diff-cleaned src/router/router_state.mbt"])

    u_add = synth({"x.mbt": "1"}, ["a.txt", "temp/leftover.py"])
    cell("untracked-new-file-is-named", detect(clean_a, u_add) == ["POLLUTED untracked-added temp/leftover.py"])
    cell("untracked-removal-is-named", detect(u_add, clean_a) == ["UNDIRTY untracked-cleaned temp/leftover.py"])

    # 规则失明对照：把承重的那条规则摘掉 ⇒ 同一份违例必须变成「看不见」，否则说明断言是幻影。
    cell("mutation-diff-added-rule-blind", detect(clean_a, added, rules=("diff-content",)) == [])
    cell("mutation-untracked-rule-blind", detect(clean_a, u_add, rules=("diff-added",)) == [])
    cell("mutation-all-rules-off-is-blind-but-visible-in-verdict",
         detect(clean_a, added, rules=()) == [] and detect(clean_a, added) != [])

    return fails, 9


def fatal(msg):
    """判据无法自证 ⇒ **真给 2**（写 stderr，由 `sys.exit(main())` 落成退出码）。
    刻意不用 `raise SystemExit("串")`——带字符串的 SystemExit 实给 1，正是本仓在抓的那条幻影（BUG-369）。"""
    sys.stderr.write("FATAL: %s\n" % msg)
    return 2


def main(argv):
    args = list(argv)
    if "--selftest" in args:
        fails, n = selftest()
        if fails:
            print("SELFTEST FAIL: %d/%d 格红 → %s" % (len(fails), n, ",".join(fails)))
            return 1
        # 自述必须等于实现（J10「判据范围自述==实现」）：5 违例必红 + 1 干净反向对照 + 3 规则失明对照 = 9
        print("SELFTEST OK: %d 格（合成违例必红 5 + 干净反向对照 1 + 规则失明对照 3，含 R98 内容漂移那一形）" % n)
        return 0

    repo = "."
    if "--repo" in args:
        i = args.index("--repo")
        if i + 1 >= len(args):
            return fatal("--repo 后面没给目录")
        repo = args[i + 1]
        del args[i:i + 2]

    if "--" in args:
        i = args.index("--")
        cmd = args[i + 1:]
    else:
        cmd = [sys.executable, "-c", "pass"]  # 裸跑＝有界自检：什么都不改，只证明快照机制在本仓成立

    if os.path.isdir(repo) is False:
        return fatal("目录不存在：%s" % repo)
    rc, _ = _git(repo, ["rev-parse", "--git-dir"])
    if rc != 0:
        return fatal("%s 不在 git 仓里，判据测不到东西" % repo)

    try:
        before = snapshot(repo)
    except FileNotFoundError:
        return fatal("取不到 git，无法出快照")

    try:
        p = subprocess.Popen(cmd, cwd=str(Path(repo).resolve()))
    except (FileNotFoundError, OSError) as e:
        # 被包命令根本没起来 ⇒ 什么都没测到。这不能报「隔离合格」（空扫描必自拒）。
        return fatal("被包命令没能启动（%s）：隔离面未测到，拒绝出数" % e)
    p.communicate()
    print("WRAPPED_RC=%s" % p.returncode)

    after = snapshot(repo)
    v = detect(before, after)
    if v:
        for line in v:
            print(line)
        print("ISOLATION=polluted 变化 %d 处（仓库 %s）" % (len(v), repo))
        return 1
    print("ISOLATION=clean 跟踪面与未跟踪面均未变（快照前后各 %d/%d 项）" % (len(after["diff"]), len(after["untracked"])))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — 尺子自己坏了 ⇒ 真给 4，绝不冒用 1（判据红）那一档
        sys.stderr.write("RULER BROKEN: %r\n" % e)
        sys.exit(4)
