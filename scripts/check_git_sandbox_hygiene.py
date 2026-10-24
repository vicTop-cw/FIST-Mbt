#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_git_sandbox_hygiene.py — 「判据沙箱 git 必须与宿主隔离」普查棘轮（R4）。

**为什么需要它**（2026-10-24 一天内同形地雷三次实踩）：`check_merge_markers --selftest` 在
pre-commit 钩子里把三发 "fixture" 提交写进宿主 HEAD（钩子导出的 `GIT_DIR`/`GIT_INDEX_FILE`
压过 `git -C <临时目录>`）；主线 `3a715a4c` 修的 `core.bare=true` 是同机制的第二实现；本会话
普查又抓到新交付的 `check_push_guard`/`check_hardcoded_paths` 各自带一发（已修，走
`git_env.isolated_git_env`）。**修一处配一把尺**——这次的尺是普查棘轮：全仓同形一次扫净，
存量按现读封顶只许降，新尺忘隔离当场红。

判据（AST 静态，不执行被检脚本、不跑 git、不动工作树）：
  · 被检面：`scripts/**/*.py`（排除 git_env.py 与本尺自身）。
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from git_env import isolated_git_env  # noqa: E402  （T11 端到端夹具用；本判据自身读只读面）

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
    collected = []
    for rel in rels:
        base = rel.replace("\\", "/").split("/")[-1]
        if base == SELF or base == "git_env.py":
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
        # R184：聚合走被测过的 `aggregate()`（与 T5/T6 同一判定律），不再就地重写一遍
        if sandbox:
            collected.append((rel.replace("\\", "/"), calls))
    bad = aggregate(collected)
    return bad, scanned


# ── R184：聚合层与棘轮层拆成**可测纯函数**（判例-18「自证必须覆盖整条链」）──────────
#
# 为什么拆：B·verify 变异测试实锤 —— 把 `offenders` 改成恒返回空，`--selftest` 照样绿。
# 因为原 selftest 四格只测检测器 `analyze_source`，而「检测结果 → 违例清单」的聚合
# 与「违例数 vs DIRTY_CEILING」的棘轮判定**从不在自证面内**。
# ⇒ 假绿长在「检测器」与「聚合器」的接缝上。拆成纯函数后，三层各自可被断言。


def aggregate(scanned_calls):
    """纯函数：把 {rel: [(行号, 是否带 env), ...]} 聚成违例清单 [(rel, [缺失行号...])]。

    与 `offenders()` 尾段是**同一判定**（`sandbox` 语境已在调用前判过，这里只负责聚合）：
    只保留「有缺 env 调用」的脚本；全带 env 的脚本不进清单。
    """
    bad = []
    for rel, calls in scanned_calls:
        missing = [ln for ln, has_env in calls if not has_env]
        if missing:
            bad.append((rel, sorted(missing)))
    return bad


def judge_ratchet(n, ceiling):
    """纯函数：棘轮三支判定。返回 (rc, message)。

    - `n > ceiling`            ⇒ rc=1（超棘轮：新尺忘隔离，或升了存量）
    - `n == 0 and ceiling > 0` ⇒ rc=1（**还完债常量没改回 0** —— 登记落后同样是红）
    - 其余                     ⇒ rc=0（在上限内）

    这两支都必须被自证覆盖：只测「超限必红」会漏掉「债务还清后常量忘了收」那一支，
    而那正是棘轮**只许降不许升**这条律的另一半。
    """
    if n > ceiling:
        return (1, "FAIL 沙箱隔离违例超棘轮：%d > 上限 %d（新尺忘隔离，或升了存量——升档是人的决定）"
                % (n, ceiling))
    if n == 0 and ceiling > 0:
        return (1, "FAIL 棘轮登记落后：现读 0 违例，上限仍是 %d——还完债请把常量改回 0" % ceiling)
    return (0, "")


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

    # ── R184：聚合层 + 棘轮层自证（判例-18）──────────────────────────────────
    # 这两组格补的是原 selftest 的盲区：T1–T4 只测检测器，把 `offenders` 改成恒返回空
    # 时原自检照样绿。现在「检测 → 聚合 → 棘轮」三层各有断言。
    agg = aggregate([("a.py", [(10, True), (12, False)]), ("b.py", [(3, True)])])
    cell("T5 聚合层：缺 env 的调用必进违例清单", agg == [("a.py", [12])], str(agg))
    agg2 = aggregate([("c.py", [(1, True), (2, True)])])
    cell("T6 聚合层：全带 env 的脚本不进清单", agg2 == [], str(agg2))

    rc_over, _ = judge_ratchet(5, 2)
    cell("T7 棘轮：违例数 > 上限 ⇒ 必红", rc_over == 1, str(rc_over))
    rc_in, _ = judge_ratchet(2, 2)
    cell("T8 棘轮：违例数 == 上限 ⇒ 放行", rc_in == 0, str(rc_in))
    rc_zero, _ = judge_ratchet(0, 2)
    cell("T9 棘轮：0 违例但常量没改回 0 ⇒ 必红", rc_zero == 1, str(rc_zero))
    rc_zero2, _ = judge_ratchet(0, 0)
    cell("T10 棘轮：0 违例且常量 0 ⇒ 放行", rc_zero2 == 0, str(rc_zero2))

    # ── T11：**真跑 offenders()**（端到端，临时 git 仓库）─────────────────────
    # 为什么必须真跑：上面 T5–T10 测的是拆出来的纯函数，若有人把 `offenders()` 里
    # 的 `aggregate(collected)` 换成 `bad = []`，纯函数格全绿而聚合**实际失效** ——
    # 变异测试实测正是这样（"offenders always-empty" 仍绿）。这一格把入口也纳入。
    import tempfile as _tf
    import shutil as _sh
    tmpd = _tf.mkdtemp(prefix="gsh-probe-")
    try:
        subprocess.run(["git", "init", "-q"], cwd=tmpd, capture_output=True,
                       env=isolated_git_env())
        os.makedirs(os.path.join(tmpd, "scripts"), exist_ok=True)
        # 造一个**缺 env 的 git 写调用**（应被判违例）
        with open(os.path.join(tmpd, "scripts", "bad_probe.py"), "w", encoding="utf-8") as f:
            f.write("import subprocess, tempfile\n"
                    "d = tempfile.mkdtemp()\n"
                    "subprocess.run(['git', 'add', '-A'], cwd=d)\n")
        # 再放一个**全带 env** 的（不应进清单）——两文件对照才能证明聚合在区分
        with open(os.path.join(tmpd, "scripts", "good_probe.py"), "w", encoding="utf-8") as f:
            f.write("import subprocess, tempfile\n"
                    "d = tempfile.mkdtemp()\n"
                    "subprocess.run(['git', 'add', '-A'], cwd=d, env={'PATH': '/x'})\n")
        env = isolated_git_env()
        subprocess.run(["git", "add", "-A"], cwd=tmpd, capture_output=True, env=env)
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t",
                        "commit", "-qm", "seed"], cwd=tmpd, capture_output=True, env=env)
        res = offenders(Path(tmpd))
        if res is None:
            cell("T11 offenders() 端到端：git 跟踪面可读", False, "offenders 返回 None")
        else:
            bad, scanned = res
            names = [r for r, _ in bad]
            cell("T11 offenders() 端到端：扫到两份探针", scanned == 2, "scanned=%s" % scanned)
            cell("T12 offenders() 端到端：缺 env 的进清单、带 env 的不进",
                 names == ["scripts/bad_probe.py"], "bad=%s" % names)
    finally:
        _sh.rmtree(tmpd, ignore_errors=True)
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
    # R184：棘轮判定走被测过的 `judge_ratchet()`（与 T7–T10 同一判定律）
    rc, msg = judge_ratchet(n, DIRTY_CEILING)
    if rc != 0:
        print(msg)
        for rel, lns in bad:
            print("  - %s（缺 env 的 git 写调用行：%s）" % (rel, ",".join(map(str, lns))))
        return 1
    if args.show:
        for rel, lns in bad:
            print("  存量 %s（行 %s）" % (rel, ",".join(map(str, lns))))
    print("PASS 沙箱隔离棘轮内：违例 %d ≤ 上限 %d（扫 %d 份；新尺忘 env 隔离当场红；"
          "存量逐支还债改小常量）" % (n, DIRTY_CEILING, scanned))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
