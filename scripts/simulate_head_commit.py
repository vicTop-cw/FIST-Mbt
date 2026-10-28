#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/simulate_head_commit.py — 提交前"干净树模拟"：把工作树差异贴上 HEAD，预判提交后 HEAD 能不能过。

**为什么需要它（2026-10-13 两次 master 坏状态实录）**：
本仓两次 master 级坏状态都是同一种形状——**"实现面先提交、配套未提交"**：
  ① `src/server/moon.pkg` 加了 `src/diff` import，但 `src/diff/` 四文件**从未 git add**
     ⇒ 干净树 `moon check` 崩 `Cannot find import 'vicTop-cw/fist-mbt/src/diff'`（CI #300 实证）
  ② `src/server/pkg.generated.mbti` 声明了 4 个源里不存在的 pub fn，其实现只在工作树
     ⇒ 干净树 `moon check` 报 `… is unbound`（20 errors，CI #303/#304 实证）
两次都**在本地是绿的**（因为工作树里配套文件都在），只在 **CI 的干净检出**上红 ⇒ 发现晚、定位绕。

**本工具做什么**：`git archive HEAD` 出一棵干净树 → 把工作树相对 HEAD 的**源码差异**
（未跟踪 + 已修改的 `.mbt` / `moon.pkg` / `moon.mod` / `*.mbti`）贴进去 → 跑 `moon check --target js`。
    - 若**绿**：说明「把这些差异一起提交，HEAD 就是绿的」⇒ 提交动作是安全的（清单就是它贴的那些）
    - 若**红**：说明「只提交这些还不够」⇒ 先补到绿再提交（避免把坏状态写进 master）

**用法**：
  python scripts/simulate_head_commit.py                    # 贴全部源码差异（默认）
  python scripts/simulate_head_commit.py --list             # 只列清单，不跑 check
  python scripts/simulate_head_commit.py --max-seconds 900  # 给 moon check 定超时
  python scripts/simulate_head_commit.py --selftest         # 出口码面自证（不跑 moon check）
退出码：0=贴后干净树 check 通过 / 1=贴后仍红（打印 error 数与前几条）/ 2=前置不满足（无产物/moon 不在等）或自检不通过。
「2」这一档 R45 起由 `emit_fatal()` 真给：此前 4 处 `raise SystemExit("FATAL …")` 只给 1（BUG-369 的半形，
其中一处文案还自写「（rc=2）」）——**空转与违例同色**时，绿灯不可信；`--selftest` 里有格把进程退出码实测钉住。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tarfile

from moon_env_probe import moon_env
import tempfile
from git_env import isolated_git_env

# BUG-138 同族：中文结论里的 ⇒ 在 Windows 默认 cp936 控制台会先崩掉 print（rc 被读成「缺陷在场」）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 参与模拟的路径后缀（源码面）：moon.pkg 决定包依赖、moon.mod 决定模块依赖、.mbti 是接口面、
# .mbt 是正文。其它（文档/报告/脚本/CI yml）不影响 `moon check`，不贴。
SRC_SUFFIXES = (".mbt", ".mbti")
SRC_NAMES = ("moon.pkg", "moon.mod")


def emit_fatal(msg):
    """「前置不满足 / 尺子没跑成」那一档的出口：写 stderr，交回 **2**。

    带字符串的 `SystemExit` 只打印文本、退出码恒为 1 —— 用 1 出「FATAL」就是把「没跑成」冒用成
    「跑出来是红」（BUG-369 抓的正是这个形状；本份原先 4 处如此，其中一处文案还自写「（rc=2）」）。
    """
    sys.stderr.write(msg + "\n")
    return 2


def run_git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, cwd=ROOT,
                          text=True, encoding="utf-8", errors="replace")


def _expand_untracked(path):
    """`git status --porcelain` 对**整个未跟踪目录**只报一行 `?? src/diff/`（尾部带斜杠）。
    本函数把它展开成该目录下实际参与 moon check 的文件清单——不展开就会漏掉整批新包
    （2026-10-13 对抗实测抓到的脚本缺陷：`?? src/diff/` 与后缀判断对不上，导致
    "新包整批未跟踪"这一最重要的坏状态形状被静默跳过）。"""
    if not path.endswith("/"):
        return [path]
    absd = os.path.join(ROOT, path)
    out = []
    for dp, dn, fn in os.walk(absd):
        dn[:] = [d for d in dn if d not in (".git", "node_modules")]
        for f in sorted(fn):
            rel = os.path.relpath(os.path.join(dp, f), ROOT).replace("\\", "/")
            if rel.endswith(SRC_SUFFIXES) or os.path.basename(rel) in SRC_NAMES:
                out.append(rel)
    return sorted(out)


def collect_diffs(extra_all=False):
    """返回 (未跟踪清单, 已修改清单)——只取影响 moon check 的源码面。
    `extra_all=True` 时放宽到「工作树所有差异」（供 --all 查看口径用）。"""
    p = run_git("status", "--porcelain")
    if p.returncode != 0:
        raise SystemExit(emit_fatal("FATAL git status 失败：%s" % (p.stderr or "")[:200]))
    untracked, modified = [], []
    for line in p.stdout.splitlines():
        if not line.strip():
            continue
        code, path = line[:2], line[3:].strip().strip('"')
        if code == "??":
            for rel in _expand_untracked(path):
                ok = extra_all or rel.endswith(SRC_SUFFIXES) or os.path.basename(rel) in SRC_NAMES
                if ok:
                    untracked.append(rel)
        elif code.strip() in ("M", "MM", "T", "R"):
            ok = extra_all or path.endswith(SRC_SUFFIXES) or os.path.basename(path) in SRC_NAMES
            if ok:
                modified.append(path)
    return sorted(set(untracked)), sorted(set(modified))


def _is_strish(node):
    """退出码面「串式」判定的最小件：字符串字面量、f-string、`"% …" % x` 都算。
    注意 `emit_fatal(…)` 的返回值也是 str，但它是**整式出口**（函数里 return 2），由调用方先排除。"""
    import ast
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):
        return True
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Mod):
        return _is_strish(node.left)
    return False


def stringy_exit_sites(src):
    """ast 现读「串式 `raise SystemExit("…")`」站点数（BUG-369 的形状；数站点用 ast 不用正则）。"""
    import ast
    n = 0
    for node in ast.walk(ast.parse(src)):
        if not (isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call)
                and getattr(node.exc.func, "id", "") == "SystemExit" and len(node.exc.args) == 1):
            continue
        a = node.exc.args[0]
        if isinstance(a, ast.Call) and getattr(a.func, "id", "") == "emit_fatal":
            continue
        if _is_strish(a):
            n += 1
    return n


def selftest():
    """出口码面自证：本份曾是 BUG-369 的「半形」——moon 超时那支真给 2，其余 4 处 FATAL 只给 1，
    其中一处文案还自写「（rc=2）」。R45 起这些格子把「改完必须还是这个形状」钉住。
    刻意不跑 `moon check`：自检要能在任何机器上秒回，且不依赖构建产物。"""
    cells = []

    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    # 1) emit_fatal 交回的整数真是 2
    cell("emit-fatal-returns-2", emit_fatal("（自检探针，非违例）") == 2, True)
    print("  ok  emit-fatal-returns-2")

    # 2) 承诺面（模块 docstring 的退出码段）仍写着 2=前置不满足 —— 改码不许顺手把承诺删绿
    cell("promise-face-declares-two", "2=前置不满足" in (__doc__ or ""), True)
    print("  ok  promise-face-declares-two")

    # 3) 形状守死：本份不得再有任何串式 SystemExit 站点（有人图省事改回去就红）
    with open(os.path.abspath(__file__), encoding="utf-8") as fh:
        n_str = stringy_exit_sites(fh.read())
    cell("no-stringy-exit-site-left", n_str == 0, True)
    print("  ok  no-stringy-exit-site-left（ast 现读串式站点 %d 处）" % n_str)

    # 4) 考的是**进程退出码**，不是函数返回值：把 ROOT 指到非仓库目录 ⇒ 取不到 HEAD ⇒ 子进程 rc 真是 2
    d = tempfile.mkdtemp(prefix="sim-head-fatal-")
    try:
        box = os.path.join(d, "not-a-repo")
        os.makedirs(box)
        child = os.path.join(d, "child_fatal_rc.py")
        with open(child, "w", encoding="utf-8") as fh:
            fh.write("import importlib.util, sys\n"
                     "spec = importlib.util.spec_from_file_location('sh', %r)\n"
                     "m = importlib.util.module_from_spec(spec)\n"
                     "spec.loader.exec_module(m)\n"
                     "m.ROOT = %r\n"                       # 非仓库目录 ⇒ git rev-parse 必失败
                     "sys.argv = ['simulate_head_commit.py']\n"
                     "sys.exit(m.main())\n"
                     % (os.path.abspath(__file__), box))
        pr = subprocess.run((sys.executable, child), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cell("fatal-headless-root-rc-is-really-2", pr.returncode == 2, True)
        print("  ok  fatal-headless-root-rc-is-really-2（子进程实测 rc=%s；改前同一条只给 1）%s"
              % (pr.returncode,
                 "" if pr.returncode == 2 else "  ← stderr：%s"
                 % pr.stderr.decode("utf-8", "replace").strip()[-160:]))
    finally:
        shutil.rmtree(d, ignore_errors=True)

    # 5) 正常模式不误红：--list 只列清单、不跑 moon，必须给 0
    pl = subprocess.run((sys.executable, os.path.abspath(__file__), "--list"),
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    cell("list-mode-exits-0", pl.returncode == 0, True)
    print("  ok  list-mode-exits-0（rc=%s）" % pl.returncode)

    fails = [(nm, why) for nm, ok, why in cells if not ok]
    if fails:
        print("SELFTEST FAIL：")
        for nm, why in fails:
            print("  - %s：%s" % (nm, why))
        return emit_fatal("判据自检不通过 —— 尺子坏了，先修尺再读结论")
    print("SELFTEST OK（%d 格：emit_fatal 返 2 / 承诺面仍写 2 / ast 现读串式站点归零 / "
          "判据无法自证的子进程退出码真是 2 / --list 不误红）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true", help="出口码面自证（不跑 moon check）")
    ap.add_argument("--list", action="store_true", help="只列清单，不跑 check")
    ap.add_argument("--all", action="store_true", help="贴工作树所有差异（不限源码后缀）")
    ap.add_argument("--max-seconds", type=int, default=1800)
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    head = run_git("rev-parse", "--short", "HEAD")
    if head.returncode != 0:
        raise SystemExit(emit_fatal("FATAL 取不到 HEAD（这不是 git 仓库？）"))
    head = head.stdout.strip()

    untracked, modified = collect_diffs(extra_all=args.all)
    paths = untracked + modified
    print("=== 提交前干净树模拟 ===")
    print("  HEAD = %s" % head)
    print("  未跟踪（源码面）%d 个；已修改（源码面）%d 个；合计 %d 个" % (len(untracked), len(modified), len(paths)))
    if args.list or not paths:
        for p in paths:
            print("    %s" % p)
        if not paths:
            print("  （没有源码差异 ⇒ 提交后 HEAD == 当前 HEAD，模拟无意义；直接跑 moon check 即可）")
        return 0

    if shutil.which("moon") is None:
        raise SystemExit(emit_fatal("FATAL PATH 上没有 moon —— 本工具要跑 moon check，拒绝出结论（rc=2）"))

    box = tempfile.mkdtemp(prefix="sim-head-")
    tarp = os.path.join(box, "_head.tar")
    try:
        a = run_git("archive", "--format=tar", "--output=" + tarp, "HEAD")
        if a.returncode != 0:
            raise SystemExit(emit_fatal("FATAL git archive 失败：%s" % (a.stderr or "")[:200]))
        with tarfile.open(tarp) as tf:
            tf.extractall(box)
        os.remove(tarp)

        copied = 0
        for p in paths:
            src = os.path.join(ROOT, p)
            if not os.path.isfile(src):
                continue          # 已删除的文件：模拟里保持 HEAD 版（保守）
            dst = os.path.join(box, p)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            copied += 1
        print("  已贴入 %d 个文件到模拟树" % copied)

        print("  跑 moon check --target js（最长 %ds）…" % args.max_seconds)
        try:
            r = subprocess.run(["moon", "check", "--target", "js"], capture_output=True,
                               cwd=box, timeout=args.max_seconds, env=moon_env())
        except subprocess.TimeoutExpired:
            print("SIMULATE REFUSED: moon check 超时（%ds）—— 拒绝出结论" % args.max_seconds)
            return 2
        out = (r.stdout + r.stderr).decode("utf-8", "replace")
        tail = [l for l in out.splitlines() if "Failed with" in l or "Finished" in l]
        errs = [l for l in out.splitlines() if l.strip().startswith("Error: [")
                or "Cannot find import" in l]
        print("  %s" % (tail[-1].strip()[:110] if tail else "(无汇总行)"))
        if r.returncode == 0 and not errs:
            print("SIMULATE PASS: 把这些差异一起提交 ⇒ 干净树 moon check 通过（%d 个文件）" % copied)
            print("  提交命令形状：git add -- <上面清单> 然后 commit（别只 add 一半）")
            return 0
        print("SIMULATE FAIL: 贴入这些差异后干净树仍红（error 线索 %d 条）——**先补到绿再提交**" % len(errs))
        for e in errs[:6]:
            print("    %s" % e.strip()[:110])
        print("  提示：若上面点名的是本地包/符号，跑 python scripts/check_pkg_imports.py 与")
        print("        python scripts/check_mbti_sync.py —— 后者会区分「已在工作树未提交」与「真缺失」")
        return 1
    finally:
        shutil.rmtree(box, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
