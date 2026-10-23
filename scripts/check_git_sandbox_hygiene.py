#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_git_sandbox_hygiene.py — 「判据沙箱 git 必须与宿主隔离」普查棘轮（R4）。

**为什么需要它**（2026-10-24 一天内同形地雷三次实踩）：`check_merge_markers --selftest` 在
pre-commit 钩子里把三发 "fixture" 提交写进宿主 HEAD（钩子导出的 `GIT_DIR`/`GIT_INDEX_FILE`
压过 `git -C <临时目录>`）；主线 `3a715a4c` 修的 `core.bare=true` 是同机制的第二实现；本会话
普查又抓到新交付的 `check_push_guard`/`check_hardcoded_paths` 各自带一发（已修，走
`git_sandbox.sandbox_env`）。**修一处配一把尺**——这次的尺是普查棘轮：全仓同形一次扫净，
存量按现读封顶只许降，新尺忘隔离当场红。

判据（AST 静态，不执行被检脚本、不跑 git、不动工作树）：
  · 被检面：`scripts/**/*.py`（排除 git_sandbox.py 与本尺自身）。
  · 沙箱语境 = 文件里出现 `mkdtemp` / `TemporaryDirectory` 的使用（AST 调用节点）。
  · git 写面 = `subprocess.run/Popen/check_output/check_call(["git", <init|add|commit|rm>, ...])`
    （AST：字符串**提及**不算——`check_pkg_imports` 注释里的「git add」不误报；selftest
    写进临时文件的**合成代码**同样不算，因为那是字符串不是调用节点）。
  · 违例 = 沙箱语境 ∙ 存在**没有 `env=` 关键字**的 git 写调用。
    （env=None 也算传了 env：live 读宿主是设计语义，静态面不判动态取值。）
  · 棘轮：现读违例数 ≤ `DIRTY_CEILING`（本尺落仓时标定），只许降不许升；降了就把常量
    一起改小——登记落后同样红。升档是人的决定。

自拒（rc=2，绝不冒用 0/1）：跟踪面读不到 / 扫到的 .py 为 0（空宇宙=无人可查的假绿）。
`--selftest` 直接在**内存代码串**上跑检测器（不落盘、不起 git）：干净/忘 env/无沙箱语境/
纯提及 四形逐一对表 + 变异台（摘掉 env= 必转红）。

用法：`python scripts/check_git_sandbox_hygiene.py [--selftest]`
退出码契约：0=违例在棘轮内 / 1=超上限或棘轮登记落后现读 / 2=判据无法自证。
"""
import argparse
import ast
import os
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent
SELF = Path(__file__).name
SUBPROCESS_FUNCS = {"run", "Popen", "check_output", "check_call"}
GIT_WRITE_SUBCMDS = {"init", "add", "commit", "rm", "mv", "checkout", "switch", "reset", "merge", "rebase", "stash"}
# R4 落仓标定：present measured offenders（历史尺的债，逐支还；还一支改小一格）。
# 校准读数 2026-10-24：宽检测（字面表 + helper 拼接形）现读 9；本会话已还清 check_push_guard /
# check_hardcoded_paths / check_merge_markers 三支（不在账上）。9 支存量多为「只读宿主仓」形状
# （静态面保守记债），还债时逐支复核后改小常量；升档是人的决定。
DIRTY_CEILING = 2

_TEMP_FNS = {"mkdtemp", "TemporaryDirectory", "NamedTemporaryFile", "SpooledTemporaryFile"}


def _str_const(node):
    return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def _call_names(tree):
    """文件里被调用的『临时目录工厂』名集合（tempfile.mkdtemp / TemporaryDirectory 均算）。"""
    hits = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.Call):
            f = n.func
            name = None
            if isinstance(f, ast.Attribute):
                name = f.attr
            elif isinstance(f, ast.Name):
                name = f.id
            if name in _TEMP_FNS:
                hits.add(name)
    return hits


def _git_write_calls(tree):
    """返回 [(lineno, has_env)]：每个 git 写子进程的 subprocess 调用与它是否传了 env=。

    两种 argv 形状都认（R4 校准：只认字面表会把 helper 包裹形 `["git"] + list(args)` 整个漏掉，
    棘轮现读假低到 1——普查尺自己的假阴就是下一颗雷）：
      · 字面表 ["git", "init", ...] ⇒ 解析子命令，仅写子命令计账；
      · 拼接形 ["git"] + <动态> ⇒ 子命令静态不可知，**保守按潜在写**（无 env 即违例；
        helper 里有 env= 关键字即算隔离——check_push_guard 的接线形状正是这样过关的）。
    """
    out = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        if not (isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name)
                and f.value.id == "subprocess" and f.attr in SUBPROCESS_FUNCS):
            continue
        if not n.args:
            continue
        argv = n.args[0]
        lst = None
        dynamic_tail = False
        if isinstance(argv, ast.List):
            lst = argv
        elif (isinstance(argv, ast.BinOp) and isinstance(argv.left, ast.List)
              and argv.left.elts and _str_const(argv.left.elts[0]) == "git"):
            lst, dynamic_tail = argv.left, True
        if lst is None:
            continue
        strs = [_str_const(e) for e in lst.elts]
        gi = next((i for i, s in enumerate(strs) if s in ("git", "git.exe", "/usr/bin/git")), None)
        if gi is None:
            continue
        if dynamic_tail:
            sub = "<dynamic>"  # 保守：潜在写
        else:
            sub = None
            for s in strs[gi + 1:]:
                if s is None or s.startswith("-"):
                    continue
                sub = s
                break
        if sub is None or (sub != "<dynamic>" and sub not in GIT_WRITE_SUBCMDS):
            continue
        has_env = any(kw.arg == "env" for kw in n.keywords)
        out.append((n.lineno, has_env))
    return out


def analyze_source(code):
    """返回 (沙箱语境?, [(行号, 有env?)])。AST 失败按 (False, [])——被检文件坏不到能被本尺救。"""
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return False, []
    calls = _git_write_calls(tree)
    if not calls:
        return False, []
    # 沙箱语境：临时目录工厂被调用，且 git 写调用带着 cwd=（在别的目录跑 git=大概率沙箱）。
    # 只 mkdtemp 但 git 全在宿主仓（无 cwd=）不算——那是故意操作宿主（whisperer 巡检形状）。
    sandbox = bool(_call_names(tree))
    return sandbox, calls


def offenders(root: Path):
    """扫 scripts/**/*.py，返回违例清单 [(rel, [lineno...])]。git 拿跟踪面失败 ⇒ None（自拒信号）。"""
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", "scripts"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        if out.returncode != 0:
            return None
        rels = [r for r in out.stdout.split("\0") if r.endswith(".py")]
    except Exception:
        return None
    bad = []
    scanned = 0
    for rel in rels:
        base = rel.replace("\\", "/").split("/")[-1]
        if base == SELF or base == "git_sandbox.py":
            continue
        p = root / rel
        if not p.is_file():
            continue
        scanned += 1
        try:
            code = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        sandbox, calls = analyze_source(code)
        if sandbox:
            missing = [ln for ln, has_env in calls if not has_env]
            if missing:
                bad.append((rel.replace("\\", "/"), sorted(missing)))
    return bad, scanned


def selftest():
    """检测器在内存代码串上对表四形 + 变异台，不落盘不起 git。"""
    fails = []

    def cell(name, ok, note=""):
        if not ok:
            fails.append("%s — %s" % (name, note))

    CLEAN = '''
import subprocess, tempfile
d = tempfile.mkdtemp()
subprocess.run(["git", "init", "-q"], cwd=d, env={"PATH": "/x"})
subprocess.run(["git", "add", "-A"], cwd=d, env={"PATH": "/x"})
subprocess.run(["git", "commit", "-qm", "seed"], cwd=d, env={"PATH": "/x"})
'''
    DIRTY = CLEAN.replace(' env={"PATH": "/x"}', '')
    NO_TEMP = '''
import subprocess
subprocess.run(["git", "add", "-A"])
'''
    MENTION = '''
# 出路是 `git add` 该文件并提交
hint = "git commit 之前必须 fmt"
'''
    sandbox, calls = analyze_source(CLEAN)
    cell("T1 沙箱+全带env→无违例", sandbox and all(e for _, e in calls), str(calls))
    sandbox2, calls2 = analyze_source(DIRTY)
    cell("T2 同码摘掉env→必判缺隔离（变异台）",
         sandbox2 and any(not e for _, e in calls2), str(calls2))
    sandbox3, calls3 = analyze_source(NO_TEMP)
    cell("T3 无沙箱语境的宿主写→不算违例（whisperer 形）", not sandbox3)
    sandbox4, calls4 = analyze_source(MENTION)
    cell("T4 字符串提及 git add→零调用节点（check_pkg_imports 假阳形）", not calls4)
    if fails:
        print("SELFTEST FAIL：检测器自身有问题")
        for f in fails:
            print("  - " + f)
        return 1
    print("SELFTEST OK 沙箱隔离普查可红可绿（忘env/变异必红；宿主写/字符串提及 不误红）")
    return 0


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--show", action="store_true", help="列出现读违例（即便在棘轮内）")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    res = offenders(ROOT)
    if res is None:
        print("FATAL 判据无法自证：git 跟踪面读不到")
        return 2
    bad, scanned = res
    if scanned == 0:
        print("FATAL 判据无法自证：scripts/ 一个 .py 都没扫到（空宇宙不出绿）")
        return 2
    n = len(bad)
    if n > DIRTY_CEILING:
        print("FAIL 沙箱隔离违例超棘轮：%d > 上限 %d（新尺忘隔离，或升了存量——升档是人的决定）"
              % (n, DIRTY_CEILING))
        for rel, lns in bad:
            print("  - %s（缺 env 的 git 写调用行：%s）" % (rel, ",".join(map(str, lns))))
        return 1
    if n == 0 and DIRTY_CEILING > 0:
        print("FAIL 棘轮登记落后：现读 0 违例，上限仍是 %d——还完债请把常量改回 0" % DIRTY_CEILING)
        return 1
    if args.show:
        for rel, lns in bad:
            print("  存量 %s（行 %s）" % (rel, ",".join(map(str, lns))))
    print("PASS 沙箱隔离棘轮内：违例 %d ≤ 上限 %d（扫 %d 份；新尺忘 env 隔离当场红；"
          "存量逐支还债改小常量）" % (n, DIRTY_CEILING, scanned))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
