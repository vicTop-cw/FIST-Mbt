#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_merge_loss.py — 合并「丢行」探测（R57）。

## 为什么需要它
本仓的**登记面**有三份手写副本（`scripts/README.md` 索引行、`run_guards.py` 的 `case(...)` 格、
`BATTERY-REGISTRATION` 锚点）。合并机器人（`slave/*` 通道 → master）多次把其中一份**整行吃掉**，
每次都要靠"另一把尺突然变红"才发现，然后人工补。实测案例：
- R48：`check_doc_dup.py` 的索引行；
- R49：`BATTERY-REGISTRATION` 锚点整行；
- R55→R56：`check_fmt_gate.py` 的索引行 + 它的电池 `--selftest` 格（合并后主线 `check_scripts_index` rc=1、
  电池 `62 格 / 失败 1`）。
共同形状：**该行在合并的某一侧存在、在合并结果里消失**，且不产生冲突提示（两侧改的是不同位置）。

## 它做什么（只读，不写库、不改工作树）
对指定（或最近一个）**merge commit**，逐侧算两种丢失信号：
1. **丢行**：该侧相对共同祖先**新增**的行在合并结果里消失（R48/R49/R55 形状）；
2. **整段侧改被弃**：该侧相对共同祖先**增/删**过某路径，而合并结果与**另一侧**逐行相同、
   与该侧不同 ⇒ 这侧的整段改动（常见是整块删除/替换）被静默回退（R136 的 README 去重形状：
   分支侧把 README 压到 272 行，合并结果却等于第一父的千行版）。信号 1 对纯删除恒盲，
   所以两个信号分开点名、分开计数。
默认只关心**登记面**（README 索引行 / `case(...)` 格 / 锚点行），可用 `--paths` 扩大或收窄扫描面；
整段侧改被弃按**路径**判定（登记面的删除无法做行级过滤）。

## 判据
- 逐侧集合差：`added(parent) - present(result)`，按**去空白后的整行**比对（合并常带行尾变化）；
- 整段侧改被弃：`side_lines != base_lines` 且 `result == other_side_lines` 且 `result != side_lines`；
  结果里没有该路径（显式删除）不归本信号；
- **读不到 ≠ 不存在**：`git show` 失败分两类（`classify_show_output`）——「路径不在那个 rev」跳过，
  「对象读不到」（部分克隆 `promisor=true` 上缺 blob / 网络失败）累计后若两类信号都没抓到 ⇒ 自拒 rc=2，
  绝不把「没量到」报成「没丢」；
- rc：`0` 无丢失 / `1` 检出丢失（逐条打印缺失行与整段被弃路径）/ `2` 无法自证（不是 merge、
  git 读不到、或 `--all-paths` 反解不出扫描面）。

## 用法
  python scripts/check_merge_loss.py                 # 最近一个 merge commit（只扫登记面两份文件）
  python scripts/check_merge_loss.py --rev <sha>     # 指定 merge
  python scripts/check_merge_loss.py --all-paths     # 扫描面 = 各侧相对共同祖先改过的文件并集
                                                     # （加 --all-lines 连代码行的删除/替换一起比）
  python scripts/check_merge_loss.py --selftest      # 合成仓库自证（两种丢失能抓 / 干净合并不误报）
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from git_env import isolated_git_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# 登记面：默认只扫这三类行（再叠加 --pattern）
DEFAULT_PATHS = ("scripts/README.md", "scripts/run_guards.py")


def is_registration(line):
    s = line.strip()
    if not s:
        return False
    if re.match(r"^- `[A-Za-z0-9_]+\.py`", s):          # README 索引行
        return True
    if re.match(r'^case\("[A-Za-z0-9_]+\.py"', s):        # 电池格
        return True
    if "BATTERY-REGISTRATION" in s:                        # 机器锚点
        return True
    return False


def git(args, cwd):
    p = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=isolated_git_env())
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def added_lines(cwd, base, tip, path):
    """base..tip 在 path 上**新增**的行（去空白后整行），返回 set。"""
    rc, out = git(["diff", "--no-color", "-U0", base, tip, "--", path], cwd)
    if rc != 0:
        return set()
    got = set()
    for l in out.splitlines():
        if l.startswith("+++"):
            continue
        if l.startswith("+"):
            s = l[1:].strip()
            if s:
                got.add(s)
    return got


ABSENT = "absent"
UNREADABLE = "unreadable"
PRESENT = "present"


def classify_show_output(rc, out):
    """把 `git show <rev>:<path>` 的失败分成「这个路径真不存在」与「我没能读到它」。
    本仓所在机器是**部分克隆**（`remote.*.promisor=true`，实测 2026-10-23），历史 blob 只在远端；
    网络不可达时 `git show` 报的是 `failed to read object` / `Could not fetch …`，退出码同样非 0。
    旧版只看退出码、一律当「路径不存在」跳过 ⇒ **把「我没量到」报成「对上了」**（本仓 R106/R121 立的
    「空产物反证」在同一条线上）。认不出的失败一律归 `unreadable`：宁可 rc=2 自拒，不冒判绿。"""
    if rc == 0:
        return PRESENT
    low = (out or "").lower()
    if "does not exist in" in low or "not a valid object name" in low or "pathspec" in low:
        return ABSENT
    return UNREADABLE


def file_lines(cwd, rev, path):
    """返回 (kind, 行集合)。kind=PRESENT 时集合可用；ABSENT 表示该 rev 下确实没有这个路径；
    UNREADABLE 表示读失败（部分克隆缺 blob / 网络 / 权限），调用方必须据此自拒。"""
    rc, out = git(["show", "%s:%s" % (rev, path)], cwd)
    kind = classify_show_output(rc, out)
    if kind != PRESENT:
        return kind, set()
    return PRESENT, {l.strip() for l in out.splitlines() if l.strip()}


def changed_paths(cwd, base, sides):
    """扫描面反解：各侧**相对共同祖先**改过的文件并集（顺序去重）。

    不能用「合并结果 vs 第一父」的差集——整段被弃的那一侧相对第一父恰恰没有差异
    （结果就等于第一父），拿差集当扫描面会把要抓的路径全筛掉（实测 `--rev a1abf697` 时
    连 `scripts/README.md` 都不在面上）。任一侧读取失败返回 None（判据无法自证）。
    """
    out = []
    for side in sides:
        rc, text = git(["diff", "--name-only", "-M", base, side], cwd)
        if rc != 0:
            return None
        out += [l.strip() for l in (text or "").splitlines() if l.strip()]
    return tuple(dict.fromkeys(out))


def side_dropped(cwd, merge, base, sides, paths):
    """整段侧改被弃：某侧相对共同祖先增/删过该路径，合并结果却等于**另一侧**。

    与 `added_lines` 信号互补——那个只看「新增的行后来不见了」，对「整块删除/替换被回退」
    恒盲（R136 的 README 去重正是这一形：分支侧删了几百行、没加几行，合并结果取第一父）。
    结果里没有该路径（显式删除）不归本信号：那是看得见的动作，不是静默回退。
    返回 (dropped, unreadable)：任一路径「读不到」都进 unreadable，调用方据此自拒，
    绝不把没量到当成没丢。
    """
    dropped = []
    unreadable = []
    for path in paths:
        rkind, result = file_lines(cwd, merge, path)
        if rkind == UNREADABLE:
            unreadable.append("%s @ 合并结果" % path)
            continue
        if rkind == ABSENT:
            continue
        bkind, base_lines = file_lines(cwd, base, path)
        if bkind == UNREADABLE:
            unreadable.append("%s @ 共同祖先" % path)
            continue
        if bkind == ABSENT:
            continue
        for side in sides:
            others = [s for s in sides if s != side]
            skind, side_lines = file_lines(cwd, side, path)
            if skind == UNREADABLE:
                unreadable.append("%s @ 侧 %s" % (path, side[:10]))
                continue
            if skind == ABSENT:
                continue
            added = side_lines - base_lines
            removed = base_lines - side_lines
            if not added and not removed:
                continue
            if result == side_lines:
                continue
            for other in others:
                okind, other_lines = file_lines(cwd, other, path)
                if okind == UNREADABLE:
                    unreadable.append("%s @ 侧 %s" % (path, other[:10]))
                    continue
                if okind == PRESENT and result == other_lines:
                    dropped.append({"path": path, "side": side[:10], "other": other[:10],
                                    "added": len(added), "removed": len(removed)})
                    break
    return dropped, unreadable


def analyze(cwd, rev="HEAD", paths=DEFAULT_PATHS, only_registration=True):
    """返回 (verdict, detail): verdict ∈ {"clean","loss","unknown"}。"""
    rc, parents = git(["rev-list", "--parents", "-n", "1", rev], cwd)
    if rc != 0:
        return "unknown", {"reason": "git 读不到 %s" % rev}
    parts = parents.split()
    if len(parts) < 3:
        return "unknown", {"reason": "%s 不是 merge commit（父数=%d）" % (rev, max(0, len(parts) - 1))}
    merge_rev = parts[0]
    base = git(["merge-base"] + parts[1:], cwd)[1].strip().splitlines()
    base_rev = base[0] if base else ""
    if not base_rev:
        return "unknown", {"reason": "取不到共同祖先"}

    missing = []
    unreadable = []
    for path in paths:
        pkind, present = file_lines(cwd, merge_rev, path)
        if pkind == UNREADABLE:
            unreadable.append("%s @ 合并结果" % path)
            continue
        if pkind == ABSENT:
            continue
        for side in parts[1:]:
            for line in added_lines(cwd, base_rev, side, path):
                if only_registration and not is_registration(line):
                    continue
                if line not in present:
                    missing.append({"path": path, "side": side[:10], "line": line})
    dropped, dropped_unreadable = side_dropped(cwd, merge_rev, base_rev, parts[1:], paths)
    unreadable += dropped_unreadable
    if unreadable and not (missing or dropped):
        return "unknown", {"reason": "扫描面有 %d 处读不到正文（部分克隆缺 blob / 网络 / 权限），"
                                     "拒绝把「没量到」报成「没丢」：%s"
                                     % (len(unreadable), "; ".join(unreadable[:3]))}
    return ("loss" if (missing or dropped) else "clean"), {
        "merge": merge_rev, "base": base_rev[:10],
        "missing": missing, "side_dropped": dropped, "unreadable": unreadable}


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    d = tempfile.mkdtemp(prefix="mergeloss-")

    def g(*a):
        return subprocess.run(["git"] + list(a), cwd=d, capture_output=True, text=True, env=isolated_git_env(),
                              encoding="utf-8", errors="replace")

    def w(p, s):
        full = os.path.join(d, p)
        os.makedirs(os.path.dirname(full) or d, exist_ok=True)
        open(full, "w", encoding="utf-8", newline="\n").write(s)

    def read(p):
        return open(os.path.join(d, p), encoding="utf-8").read()

    try:
        g("init", "-q", "-b", "master", ".")
        g("config", "user.email", "t@t")
        g("config", "user.name", "t")
        base_readme = "# idx\n\n- `alpha.py` — 原有条目\n"
        w("scripts/README.md", base_readme)
        w("scripts/run_guards.py", 'CASES = [\n    case("alpha.py"),\n]\n')
        g("add", "-A"); g("commit", "-qm", "base")

        # 场景 A：两侧各加一条登记，合并时**吃掉**其中一条 ⇒ 必须检出
        g("checkout", "-q", "-b", "sideA")
        w("scripts/README.md", base_readme + "- `beta.py` — A 侧新增（合并会丢）\n")
        g("add", "-A"); g("commit", "-qm", "A adds beta")
        g("checkout", "-q", "master")
        g("checkout", "-q", "-b", "sideB")
        w("scripts/README.md", base_readme + "- `gamma.py` — B 侧新增（保留）\n")
        g("add", "-A"); g("commit", "-qm", "B adds gamma")
        g("checkout", "-q", "master")
        g("merge", "-q", "--no-ff", "-m", "merge B", "sideB")
        # 造"丢行"：--no-commit 合并 A（其改动与 B 冲突），然后把工作树内容改成**只保留 B**，
        # 再提交 —— 这样 merge commit 的两个父都在，但 A 的那一行在结果里缺席。
        # （第一版用普通 merge + --amend，实测会因冲突把父/内容弄成不可判，自检当场抓到）
        g("merge", "--no-ff", "--no-commit", "-m", "merge A (lossy)", "sideA")
        w("scripts/README.md", base_readme + "- `gamma.py` — B 侧新增（保留）\n")
        g("add", "-A"); g("commit", "-q", "-m", "merge A (lossy)")
        verdict, detail = analyze(d, "HEAD", paths=("scripts/README.md",))
        cell("detects-loss", verdict, "loss")
        cell("loss-count-1", len(detail.get("missing", [])), 1)
        cell("loss-names-line", "beta.py" in detail["missing"][0]["line"], True)

        # 场景 B：干净合并（两侧都保留）⇒ 不误报
        g("checkout", "-q", "-b", "sideC", "master")
        w("scripts/run_guards.py", read("scripts/run_guards.py").replace(
            '    case("alpha.py"),\n', '    case("alpha.py"),\n    case("delta.py"),\n'))
        g("add", "-A"); g("commit", "-qm", "C adds delta case")
        g("checkout", "-q", "master")
        g("checkout", "-q", "-b", "sideD")
        # 注意：D 侧改**另一个文件**，避免与 C 侧同区冲突（第一版两边同改 run_guards ⇒ 合并冲突、
        # 后续场景全被污染，自检当场抓到）
        w("scripts/README.md", read("scripts/README.md") + "- `epsilon.py` — D 侧新增（保留）\n")
        g("add", "-A"); g("commit", "-qm", "D adds epsilon index line")
        g("checkout", "-q", "master")
        r1 = g("merge", "-q", "--no-ff", "-m", "merge D", "sideD")
        r2 = g("merge", "-q", "--no-ff", "-m", "merge C", "sideC")
        cell("fixture-merges-succeed", (r1.returncode, r2.returncode), (0, 0))
        verdict2, _ = analyze(d, "HEAD", paths=("scripts/run_guards.py", "scripts/README.md"))
        cell("clean-merge-no-false-positive", verdict2, "clean")

        # 场景 C：非 merge commit ⇒ unknown（拒绝出结论）
        g("checkout", "-q", "-B", "plain")
        w("scripts/README.md", read("scripts/README.md") + "- `zeta.py` — 普通提交\n")
        g("add", "-A"); g("commit", "-qm", "plain commit")
        verdict3, _ = analyze(d, "HEAD", paths=("scripts/README.md",))
        cell("non-merge-unknown", verdict3, "unknown")

        # 场景 D：整段**删除**被合并静默回退（R136 README 去重的形状）。
        #    侧分支只删行、不加行 ⇒ 旧的「新增行消失」信号恒盲（missing 必为空），
        #    只有「整段侧改被弃」能抓到；两个信号分开断言，防新信号被旧信号代偿。
        g("checkout", "-q", "-b", "sideE", "master")
        cur = read("scripts/README.md")
        kept = [l for l in cur.splitlines(True) if "epsilon.py" not in l]
        w("scripts/README.md", "".join(kept))          # 删掉一条登记行，不新增任何行
        g("add", "-A"); g("commit", "-qm", "E drops epsilon index line")
        g("checkout", "-q", "master")
        before = read("scripts/README.md")
        g("merge", "-q", "--no-ff", "--no-commit", "-m", "merge E (whole-side revert)", "sideE")
        w("scripts/README.md", before)                 # 结果取第一父 ⇒ E 的删除被弃
        g("add", "-A"); g("commit", "-q", "-m", "merge E (whole-side revert)")
        verdict4, detail4 = analyze(d, "HEAD", paths=("scripts/README.md",))
        cell("side-revert-detected", verdict4, "loss")
        cell("side-revert-not-caught-by-added-lines", len(detail4.get("missing", [])), 0)
        cell("side-revert-names-path", len(detail4.get("side_dropped", [])), 1)
        cell("side-revert-counts-removed",
             detail4["side_dropped"][0]["removed"] >= 1 and detail4["side_dropped"][0]["added"] == 0,
             True)
        # 扫描面反解口径（本信号唯一会漏的地方）：整段被弃时「结果 vs 第一父」没有差异，
        # 用那份差集当 --all-paths 的扫描面，要抓的路径一开始就不在面上；
        # 「各侧相对共同祖先」的并集才看得见它。两格互为对照。
        pv = git(["rev-list", "--parents", "-n", "1", "HEAD"], d)[1].split()
        dbase = git(["merge-base"] + pv[1:], d)[1].strip().splitlines()[0]
        cell("scan-face-union-sees-dropped-path",
             "scripts/README.md" in (changed_paths(d, dbase, pv[1:]) or ()), True)
        rc_dv, out_dv = git(["diff", "--name-only", "-M", "%s^1" % pv[0], pv[0]], d)
        cell("result-vs-first-parent-face-would-miss-it",
             rc_dv == 0 and "scripts/README.md" not in out_dv, True)

        # 场景 E：正常的删除合并（结果真的把行删了）⇒ 不许误报
        g("checkout", "-q", "-b", "sideF")
        cur = read("scripts/README.md")
        kept = [l for l in cur.splitlines(True) if "gamma.py" not in l]
        w("scripts/README.md", "".join(kept))
        g("add", "-A"); g("commit", "-qm", "F drops gamma line")
        g("checkout", "-q", "master")
        rf = g("merge", "-q", "--no-ff", "-m", "merge F (clean)", "sideF")
        cell("fixture-merge-F-succeeds", rf.returncode, 0)
        verdict5, detail5 = analyze(d, "HEAD", paths=("scripts/README.md",))
        cell("clean-delete-merge-not-red", verdict5, "clean")
        cell("clean-delete-merge-no-side-drop", len(detail5.get("side_dropped", [])), 0)
        # 绿行的扫描面标注：宽面只印条数（实测 `--all-paths` 一次 45 个文件，逐字印会把绿行撑成墙），
        # 登记面（≤3）仍逐字点名——"扫了哪两面"对人是可读性，45 个名字对人是噪音。
        cell("green-line-labels-wide-face-by-count",
             scan_face_label(tuple("p%d.py" % i for i in range(5))), "5 个路径")
        cell("green-line-labels-narrow-face-by-name",
             scan_face_label(("scripts/README.md", "scripts/run_guards.py")),
             "scripts/README.md,scripts/run_guards.py")
        # 场景 G：两侧同改**同一个文件**的不同行 ⇒ 正常三方合并的结果不等于任何一侧。
        #   这一格是「结果逐行等于另一侧」那闸的承重对照：前面 A–F 的夹具里，某侧改过的文件
        #   在结果中恰好等于该侧自己（另一侧没碰它），先被 `result == side_lines` 短路，
        #   所以把那闸摘掉也不红（变异实测过，红不出来就是没钉住）。
        g("checkout", "-q", "master")
        g("checkout", "-q", "-b", "sideG1")
        w("scripts/run_guards.py", read("scripts/run_guards.py").replace(
            '    case("alpha.py"),\n', '    case("alpha.py"),\n    case("zeta.py"),\n'))
        g("add", "-A"); g("commit", "-qm", "G1 adds zeta at list head")
        g("checkout", "-q", "master")
        g("checkout", "-q", "-b", "sideG2")
        w("scripts/run_guards.py", read("scripts/run_guards.py").replace(
            "]\n", '    case("eta.py"),\n]\n'))          # 改同一文件的**另一处**，避免文本冲突
        g("add", "-A"); g("commit", "-qm", "G2 adds eta at list tail")
        g("checkout", "-q", "master")
        g1 = g("merge", "-q", "--no-ff", "-m", "merge G1", "sideG1")
        g2 = g("merge", "-q", "--no-ff", "-m", "merge G2", "sideG2")
        cell("fixture-merge-G-succeeds", (g1.returncode, g2.returncode), (0, 0))
        verdict6, detail6 = analyze(d, "HEAD", paths=("scripts/run_guards.py",))
        cell("three-way-merge-result-matches-no-side", verdict6, "clean")
        cell("three-way-merge-no-side-drop", len(detail6.get("side_dropped", [])), 0)
        # 读不到 ≠ 不存在（部分克隆实测面）：三档分类 + 一处真 absent 路径不许把结论拖成自拒。
        cell("show-rc0-is-present", classify_show_output(0, "- `a.py` — x\n"), PRESENT)
        cell("show-absent-path-classified",
             classify_show_output(128, "fatal: path 'scripts/ghost.py' does not exist in 'HEAD'"), ABSENT)
        cell("show-lazy-fetch-failure-classified-unreadable",
             classify_show_output(128, "fatal: failed to read object 1b2c3d: Invalid argument"), UNREADABLE)
        cell("show-unknown-failure-not-guesses-absent",
             classify_show_output(1, "remote: Support for git protocol version 1..."), UNREADABLE)
        ghost = analyze(d, "HEAD", paths=("scripts/README.md", "scripts/ghost.py"))
        cell("absent-path-does-not-self-refuse", ghost[0] in ("clean", "loss"), True)
    finally:
        shutil.rmtree(d, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：丢行检出三档 / 干净合并不误报两档 / 非 merge 拒绝出结论一档 / "
          "整段侧改被弃四档 + 扫描面口径两档 / 正常删除合并不误报三档 / 绿行扫描面标注两档 / "
          "两侧同改一文件的三方合并不误报三档 / 读不到↔不存在分类四档 + 不存在路径不拖自拒一档）" % len(cells))
    return 0


def scan_face_label(paths):
    """绿行的「扫描面」标注：登记面（2-3 个文件）逐字点名，宽扫描面只印条数。
    `--all-paths` 一次能扫 40+ 个文件，逐字印会把「没发现问题」那一行撑成一堵墙，
    人（和 AI）读绿行要的是「扫了多宽」，不是文件名清单——清单只在红里才值钱。"""
    paths = list(paths)
    return ",".join(paths) if len(paths) <= 3 else "%d 个路径" % len(paths)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--paths", default="")
    ap.add_argument("--all-paths", action="store_true",
                    help="扫描面从 DEFAULT_PATHS（登记面两把文件）扩到本次合并真正改过的所有文件——"
                          "「整段侧改被弃」只有在这里才看得见代码面的回退")
    ap.add_argument("--all-lines", action="store_true", help="不限于登记面（连普通代码行一起比）")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.all_paths:
        # 扫描面用「各侧相对共同祖先」的并集，口径与理由见 changed_paths
        rc, pv = git(["rev-list", "--parents", "-n", "1", args.rev], ROOT)
        ps = pv.split()
        if rc != 0 or len(ps) < 3:
            print("  判据无法自证：--all-paths 需要 merge commit（%s 父数不足）" % args.rev)
            return 2
        base = git(["merge-base"] + ps[1:], ROOT)[1].strip().splitlines()
        if not base:
            print("  判据无法自证：--all-paths 取不到共同祖先")
            return 2
        changed = changed_paths(ROOT, base[0], ps[1:])
        if changed is None:
            print("  判据无法自证：--all-paths 取「各侧相对共同祖先」的改动文件面失败")
            return 2
        paths = changed
        if not paths:
            print("  判据无法自证：--all-paths 两侧相对共同祖先都没改文件（合并无内容差异）")
            return 2
    else:
        paths = tuple(p.strip() for p in args.paths.split(",") if p.strip()) or DEFAULT_PATHS
    verdict, detail = analyze(ROOT, args.rev, paths, only_registration=not args.all_lines)
    if verdict == "unknown":
        print("  判据无法自证：%s（rc=2，拒绝判绿也拒绝判红）" % detail.get("reason"))
        return 2
    if verdict == "clean":
        print("  PASS 合并 %s（base %s）未发现登记面丢行 / 整段侧改被弃（扫描 %s）"
              % (detail["merge"][:10], detail["base"], scan_face_label(paths)))
        return 0
    print("  FAIL 合并 %s：登记丢行 %d 条 / 整段侧改被弃 %d 个路径："
          % (detail["merge"][:10], len(detail["missing"]), len(detail["side_dropped"])))
    if detail.get("unreadable"):
        u = detail["unreadable"]
        print("    ⚠ 另有 %d 处正文读不到（部分克隆缺 blob / 网络 / 权限）——红是抓到的，绿不保证完整：%s"
              % (len(u), "; ".join(u[:3])))
    for m in detail["missing"]:
        print("    ✗ [%s 侧] %s :: %s" % (m["side"], m["path"], m["line"][:96]))
    for s in detail["side_dropped"]:
        print("    ⇤ [%s 侧] %s 整段改动被弃（侧 +%d/-%d 行，结果逐行等于另一侧 %s）"
              % (s["side"], s["path"], s["added"], s["removed"], s["other"]))
    print("  处置：丢行逐条补回（索引行→scripts/README.md；电池格→run_guards.py；锚点→README 的 "
          "BATTERY-REGISTRATION）；整段侧改被弃 → `git show <merge>^N:<path>` 与该侧对照后重新合入，"
          "别按「第一父为准」再盖一次")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
