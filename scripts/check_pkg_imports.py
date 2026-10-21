#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_pkg_imports.py — 本地包 import ↔ 跟踪面目录 存在性守卫。

**为什么需要它（2026-10-13 master 坏状态实录）**：
`src/server/moon.pkg` 里加了 `"vicTop-cw/fist-mbt/src/diff"`，但 `src/diff/` 目录**从未被 git add**
（改了 moon.pkg 却没 add 新包目录）。于是 master 上干净树 `moon check` 当场崩：

    Error: Failed to calculate build plan
    Caused by: Cannot find import 'vicTop-cw/fist-mbt/src/diff' in vicTop-cw/fist-mbt/src/server@0.3.8

而 CI 红在 `Migrate mooncakes dep manifests` 步（**错误文本先被读成「依赖迁移问题」**），
且该步一红就 skip 其后 21 步（守卫族集体失效）⇒ 发现得晚、定位得绕。

**判据**（窄口径，只判确定性问题）：
  P1 全仓跟踪的 `moon.pkg` 里，凡 import `"vicTop-cw/fist-mbt/<sub>"`（可带 `@alias`）：
     `<sub>` 非空时，**跟踪面里必须存在以 `<sub>/` 开头的文件**（即该包目录真的在库里）。
     否则红——这条正是本轮 master 坏状态的形状。
  P2 防空转：一份 `moon.pkg` 都枚举不到（或全仓一条本地 import 都没有）⇒ FATAL，不报绿
     （判据空转 ≠ 没有问题）。

**刻意不判的**（避免过度拦截）：
  - 外部依赖（`moonbitlang/…` / `colmugx/…` / `mizchi/…` / `Tigls/…` 等）：它们不在本仓跟踪面，
    由 moon 的 registry 负责，本判据不管。
  - 模块根自身（`"vicTop-cw/fist-mbt"`，无子路径）：指向模块根，无需目录检查。
  - `.mooncakes/`（gitignored）：不在跟踪面，天然不参与。

用法：
  python scripts/check_pkg_imports.py              # 0=PASS，1=违例，2=判据无法自证（FATAL）
  python scripts/check_pkg_imports.py --selftest   # 合成违例自证会红 + 干净不误红
"""
import argparse
import os
import re
import subprocess
import sys

# BUG-138（BUG-58 同族）：守卫的红必须是判据红——中文结论里的 ⇒ 在 Windows 默认 cp936 控制台
# 会先崩掉 print，把 traceback 冒充成「缺陷在场」那一档。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULE = "vicTop-cw/fist-mbt"

RE_IMPORT = re.compile(r'"([^"]+)"')
RE_ALIAS = re.compile(r"@\w+$")


def emit_fatal(msg):
    """「尺子坏了」那一档的出口：写 stderr，交回 **2**。

    带字符串的 SystemExit 只打印文本、退出码恒为 1 —— 把判据失灵冒用成「有违例」正是 BUG-369 在抓的形状。
    """
    sys.stderr.write(msg + "\n")
    return 2


def tracked_files(root=None):
    """跟踪面文件清单（用 git ls-files，与 check_entry_paths / check_test_sync 同口径）。
    取不到 git 或清单为空 ⇒ SystemExit(2)：判据无法自证绝不报绿。"""
    root = root or ROOT
    try:
        r = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
    except Exception as e:  # git 不在 PATH
        raise SystemExit(emit_fatal("FATAL 无法调用 git ls-files（%s）—— 拒绝在无枚举时出绿灯" % e))
    if r.returncode != 0:
        raise SystemExit(emit_fatal("FATAL git ls-files 退出码 %s：%s"
                                    % (r.returncode, (r.stderr or "").strip()[:200])))
    files = [x.replace("\\", "/") for x in (r.stdout or "").split("\0") if x.strip()]
    if not files:
        raise SystemExit(emit_fatal("FATAL git ls-files 返回空清单 —— 拒绝在无枚举时出绿灯"))
    return files


def pkg_files(files):
    """跟踪面里的全部 moon.pkg（含仓根那份）。"""
    return [f for f in files if f == "moon.pkg" or f.endswith("/moon.pkg")]


def local_imports(text):
    """从一份 moon.pkg 正文抽出本地包 import 的子路径（去掉 @alias）。
    返回 [(原始 import, 子路径)]；子路径为空（模块根自身）的也返回，由调用方决定跳不跳。"""
    out = []
    for m in RE_IMPORT.finditer(text):
        imp = m.group(1)
        if not imp.startswith(MODULE):
            continue          # 外部依赖：不在本仓跟踪面，不判
        sub = imp[len(MODULE):].lstrip("/")
        sub = RE_ALIAS.sub("", sub)
        out.append((imp, sub))
    return out


def judge(files, pkg_texts):
    """纯判定：files = 跟踪面清单，pkg_texts = {moon.pkg 相对路径: 正文}。
    返回 (问题列表, 检查过的 import 数)。"""
    problems = []
    dirs = set()
    for f in files:
        d = os.path.dirname(f).replace("\\", "/")
        while d and d not in dirs:
            dirs.add(d)
            d = os.path.dirname(d).replace("\\", "/")

    n = 0
    for rel in sorted(pkg_texts):
        for imp, sub in local_imports(pkg_texts[rel]):
            if not sub:
                continue      # 模块根自身：无需目录检查
            n += 1
            if sub not in dirs:
                problems.append(
                    "P1 %s 里 import 了 %r，但跟踪面里没有 %s/ 目录下的任何文件 "
                    "——该包目录没被 git add（master 坏状态形状：改了 moon.pkg 却漏 add 新包）"
                    % (rel, imp, sub)
                )
    return problems, n


def selftest():
    """合成违例自证：判据必须先证明它会红，且干净输入不误红。"""
    files = ["moon.pkg", "src/server/moon.pkg", "src/server/server.mbt", "src/diff/moon.pkg",
             "src/diff/diff.mbt", "cmd/cli/moon.pkg", "cmd/cli/main.mbt"]
    cells = []

    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    # 1) 干净输入：import 的包都在跟踪面 ⇒ 0 违例
    clean = {
        "src/server/moon.pkg": 'import {\n  "vicTop-cw/fist-mbt/src/diff",\n  "moonbitlang/core/json",\n}\n',
    }
    p, n = judge(files, clean)
    cell("clean-no-false-positive", len(p) == 0 and n == 1, True)
    print("  ok  clean-no-false-positive（%d 条本地 import，0 违例）" % n)

    # 2) 合成违例：import 一个跟踪面里不存在的目录 ⇒ 必红
    bad = {
        "src/server/moon.pkg": 'import {\n  "vicTop-cw/fist-mbt/src/nonexistent",\n}\n',
    }
    p, n = judge(files, bad)
    hit = any("src/nonexistent" in x for x in p)
    cell("synthetic-violation-caught", hit, True)
    print("  ok  synthetic-violation-caught（%s）" % (p[0][:78] if p else "未编制"))

    # 3) 本轮真实形状：import src/diff 但 src/diff 不在跟踪面 ⇒ 必红
    real = {
        "src/server/moon.pkg": 'import {\n  "vicTop-cw/fist-mbt/src/diff",\n}\n',
    }
    p, n = judge([f for f in files if not f.startswith("src/diff/")], real)
    hit = any("src/diff" in x for x in p)
    cell("real-shape-src-diff-caught", hit, True)
    print("  ok  real-shape-src-diff-caught（master 坏状态原形）")

    # 4) @alias 形态不误判（去掉 alias 后仍能正确比对）
    alias = {
        "src/server/moon.pkg": 'import {\n  "vicTop-cw/fist-mbt/src/diff" @diff,\n}\n',
    }
    p, n = judge(files, alias)
    cell("alias-form-ok", len(p) == 0 and n == 1, True)
    print("  ok  alias-form-ok（@diff 别名不误红）")

    # 5) 外部依赖一律不判（哪怕它不在跟踪面）
    ext = {
        "src/server/moon.pkg": 'import {\n  "moonbitlang/core/json",\n  "colmugx/mcp",\n}\n',
    }
    p, n = judge(files, ext)
    cell("external-deps-ignored", len(p) == 0 and n == 0, True)
    print("  ok  external-deps-ignored（外部依赖不判，%d 违例）" % len(p))

    # 6) 模块根自身不判（无子路径）
    root_import = {
        "cmd/main/moon.pkg": 'import {\n  "vicTop-cw/fist-mbt",\n}\n',
    }
    p, n = judge(files, root_import)
    cell("module-root-ignored", len(p) == 0 and n == 0, True)
    print("  ok  module-root-ignored（模块根自身不判）")

    # 7) 出口码自证（BUG-369 建议① / R44：改行为必须同时补一支「FATAL 的码真是 2」格）。
    #    本份原先 6 处 `raise SystemExit("FATAL …")` 全给 1，而承诺面（本文档用法段与 scripts/README）写着 2
    #    ⇒ 「尺子坏了」与「有违例」同色。这里考的是**进程退出码**，不是函数返回值：返回值对不等于 rc 对。
    cell("emit-fatal-returns-2", emit_fatal("（自检探针，非违例）") == 2, True)
    print("  ok  emit-fatal-returns-2")
    import tempfile
    d = tempfile.mkdtemp(prefix="pkgimp-fatal-")
    try:
        child = os.path.join(d, "child_fatal_rc.py")
        with open(child, "w", encoding="utf-8") as fh:
            fh.write("import importlib.util, sys\n"
                     "spec = importlib.util.spec_from_file_location('pi', %r)\n"
                     "m = importlib.util.module_from_spec(spec)\n"
                     "spec.loader.exec_module(m)\n"
                     "m.ROOT = %r\n"                      # 指到非仓库目录 ⇒ git ls-files 必失败
                     "sys.argv = ['check_pkg_imports.py']\n"
                     "sys.exit(m.main())\n"
                     % (os.path.abspath(__file__), d))
        pr = subprocess.run((sys.executable, child), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cell("fatal-unusable-git-rc-is-really-2", pr.returncode == 2, True)
        print("  ok  fatal-unusable-git-rc-is-really-2（子进程实测 rc=%s；改前同一条只给 1）%s"
              % (pr.returncode,
                 "" if pr.returncode == 2 else "  ← stderr：%s"
                 % pr.stderr.decode("utf-8", "replace").strip()[-160:]))
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)

    bad_cells = [(nm, why) for nm, ok, why in cells if not ok]
    if bad_cells:
        print("SELFTEST FAIL：")
        for nm, why in bad_cells:
            print("  - %s：%s" % (nm, why))
        return 1
    print("SELFTEST OK（%d 格：干净不误红 / 合成违例必红 / 真实形状必红 / alias / 外部依赖 / 模块根 / "
          "判据空转的退出码真是 2（两格：emit_fatal 返 2 + 子进程 rc 是 2）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    files = tracked_files()
    pkgs = pkg_files(files)
    if not pkgs:
        raise SystemExit(emit_fatal("FATAL 跟踪面里一份 moon.pkg 都没枚举到 —— 判据空转，拒绝报绿"))
    texts = {}
    for rel in pkgs:
        p = os.path.join(ROOT, rel)
        if os.path.isfile(p):
            texts[rel] = open(p, encoding="utf-8", errors="replace").read()
    if not texts:
        raise SystemExit(emit_fatal("FATAL 读不到任何 moon.pkg 正文 —— 判据空转，拒绝报绿"))

    problems, n = judge(files, texts)
    if n == 0:
        raise SystemExit(emit_fatal("FATAL 全仓 moon.pkg 里一条本地包 import 都没有 —— 判据空转，拒绝报绿"))
    if problems:
        print("FAIL 本地包 import 存在性守卫（扫 %d 份 moon.pkg、%d 条本地 import）：" % (len(texts), n))
        for x in problems:
            print("  - " + x)
        return 1
    print("PASS 本地包 import 存在性一致：%d 份 moon.pkg 的 %d 条本地 import 指向的目录都在跟踪面"
          % (len(texts), n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
