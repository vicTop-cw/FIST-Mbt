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
对指定（或最近一个）**merge commit**，逐侧计算"该侧相对共同祖先新增的行"，再检查这些行是否出现在
**合并结果**里；缺席的即判为「合并丢行」。默认只关心**登记面**（README 索引行 / `case(...)` 格 / 锚点行），
可用 `--paths` 扩大或收窄扫描面。

## 判据
- 逐侧集合差：`added(parent) - present(result)`，按**去空白后的整行**比对（合并常带行尾变化）；
- rc：`0` 无丢失 / `1` 检出丢失（逐条打印缺失行与其来源侧）/ `2` 无法自证（不是 merge、或 git 读不到）。

## 用法
  python scripts/check_merge_loss.py                 # 最近一个 merge commit
  python scripts/check_merge_loss.py --rev <sha>     # 指定 merge
  python scripts/check_merge_loss.py --selftest      # 合成仓库自证（丢行能抓 / 干净合并不误报）
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


def file_lines(cwd, rev, path):
    rc, out = git(["show", "%s:%s" % (rev, path)], cwd)
    if rc != 0:
        return None
    return {l.strip() for l in out.splitlines() if l.strip()}


def run(cwd, rev="HEAD", paths=DEFAULT_PATHS, only_registration=True):
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
    for path in paths:
        present = file_lines(cwd, merge_rev, path)
        if present is None:
            continue
        for side in parts[1:]:
            for line in added_lines(cwd, base_rev, side, path):
                if only_registration and not is_registration(line):
                    continue
                if line not in present:
                    missing.append({"path": path, "side": side[:10], "line": line})
    return ("loss" if missing else "clean"), {"merge": merge_rev, "base": base_rev[:10],
                                              "missing": missing}


def selftest():
    cells = []

    def cell(name, got, want):
        cells.append((name, got == want, "got=%r want=%r" % (got, want)))

    d = tempfile.mkdtemp(prefix="mergeloss-")

    def g(*a):
        return subprocess.run(["git"] + list(a), cwd=d, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", env=isolated_git_env())

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
        verdict, detail = run(d, "HEAD", paths=("scripts/README.md",))
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
        verdict2, _ = run(d, "HEAD", paths=("scripts/run_guards.py", "scripts/README.md"))
        cell("clean-merge-no-false-positive", verdict2, "clean")

        # 场景 C：非 merge commit ⇒ unknown（拒绝出结论）
        g("checkout", "-q", "-B", "plain")
        w("scripts/README.md", read("scripts/README.md") + "- `zeta.py` — 普通提交\n")
        g("add", "-A"); g("commit", "-qm", "plain commit")
        verdict3, _ = run(d, "HEAD", paths=("scripts/README.md",))
        cell("non-merge-unknown", verdict3, "unknown")
    finally:
        shutil.rmtree(d, ignore_errors=True)

    bad = [(n, w) for n, ok, w in cells if not ok]
    if bad:
        print("SELFTEST FAIL：")
        for n, w in bad:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：丢行检出三档 + 干净合并不误报 + 非 merge 拒绝出结论）" % len(cells))
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--paths", default="")
    ap.add_argument("--all-lines", action="store_true", help="不限于登记面（连普通代码行一起比）")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    paths = tuple(p.strip() for p in args.paths.split(",") if p.strip()) or DEFAULT_PATHS
    verdict, detail = run(ROOT, args.rev, paths, only_registration=not args.all_lines)
    if verdict == "unknown":
        print("  判据无法自证：%s（rc=2，拒绝判绿也拒绝判红）" % detail.get("reason"))
        return 2
    if verdict == "clean":
        print("  PASS 合并 %s（base %s）未发现登记面丢行（扫描 %s）"
              % (detail["merge"][:10], detail["base"], ",".join(paths)))
        return 0
    print("  FAIL 合并 %s 丢了 %d 条登记行：" % (detail["merge"][:10], len(detail["missing"])))
    for m in detail["missing"]:
        print("    ✗ [%s 侧] %s :: %s" % (m["side"], m["path"], m["line"][:96]))
    print("  处置：把上面每一行补回（索引行→scripts/README.md；电池格→run_guards.py；锚点→README 的 BATTERY-REGISTRATION）")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
