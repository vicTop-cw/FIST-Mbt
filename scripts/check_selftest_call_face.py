#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_selftest_call_face.py — 「`--selftest` 到底跑没跑调用面」守卫（R171，副机自立项）。

## 为什么需要它（不是「再加一道门」，是本轮真挨过一次打之后补的那一格）
R158 交付 `check_diff_scope.py` 时 `--selftest` 全绿，而**现状面一跑就崩**：`DIFFSCOPE=clean`
那行少传一个实参抛 `TypeError`，冒出来的 rc=1 长得和「有违例」一模一样。自检为什么抓不到？因为它只考
`judge()`（纯函数），**从没经过 `run()`/`main()`**——打印行、参数个数、四档退出码、折叠逻辑整层都在
自证面之外。这不是笔误特例，是本仓守卫的一族形状：`--selftest` 绿 ≠ 那把尺真的能跑。BUG-366 记的是
「零执行面 = 坏着的尺」，本尺管它剩下的另一半：**执行面存在，但不覆盖调用面**。

## 两条判据（静态 AST：不 import、不执行被检脚本、不写库、不动工作树）
- **J2 `NO_CALL_FACE`（棘轮，只许降）**：脚本申报了 `--selftest`（源码含该字面量），且有可识别的自检
  函数（函数名去掉下划线后含 `selftest`），但从自检函数出发的调用图**到不了任何调用面锚点**。锚点三形：
  ① 函数名是 `main` / `run` / `cli`；② 函数体内出现 `sys.exit(...)` / `exit(...)` / `raise SystemExit`
  （退出码是承诺面，跑过才算核过）；③ 函数体内用 `subprocess`/`Popen` 起 `sys.executable` 或自身脚本名
  （「起子进程跑自己」是调用面的另一条形）。
- **J1 `UNREACHABLE_FATAL_CODE`（棘轮，只许降）**：脚本承诺了 `4` 那一档（docstring 里有 `4=` /
  `FATAL`，或源码里有「尺子自己坏了」），但**没有任何一处 `return 4` / `exit(4)` 落在 `except` 处理器
  作用域内**。那一档的语义是「未捕获异常 = 尺子坏了」——不在 except 里的 4 永不可能由崩溃给出，属幻影
  承诺。与 `check_exit_code_contract.py` 的分工：那把尺判「承诺的码 AST 不可达」，本条判「码与它要兜的
  形状不在同一作用域」——两形不同，不重复。

**只报不判（诊断，不入棘轮）**：申报了 `--selftest` 但没有可识别自检函数（自检内联在 `main` 里，或用了
本尺词表外的名字）。这类强行计数等于替别人判红，只打印清单交人看。

## 为什么两条都做成棘轮而不是 0 容忍
存量缺口是别的单元的文件，本单不代修（owner 裁决「预存红不代修，但必须点名 rc 与成因」）。棘轮的出路
只有两条——把调用面接上，或把上限改小；放宽上限是人的决定，本判据不自动改数。上限常量钉在基点现读。

## 用法
  python scripts/check_selftest_call_face.py                  # 被检面 = 本仓 scripts/ 递归
  python scripts/check_selftest_call_face.py --root <dir>     # 指到别处（自证用合成面）
  python scripts/check_selftest_call_face.py --selftest       # 合成对照：每条判据各有必红格与不误红格

## 退出码（承诺与实现同批核过；四档都在 `--selftest` 的调用面格里被真跑）
0=违例数在棘轮上限内 / 1=超限（逐条点名 kind 与文件） /
2=判据无法自证（被检根不存在、被检面为空、一份 .py 都没读到） / 4=尺子自己坏了（未捕获异常，BUG-369）。
"""
import argparse
import ast
import io
import os
import sys
import warnings
from contextlib import redirect_stdout

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SELF_NAME = os.path.basename(__file__)
CALL_FACE_FUNCS = ("main", "run", "cli")
EXIT_SHAPE_NAMES = ("exit", "SystemExit")
SUBPROCESS_NAMES = ("Popen", "check_output", "call", "run", "check_call")
FATAL_PROMISE_KEYS = ("4=", "4 =", "FATAL", "尺子自己坏了")
# 棘轮上限：只许下降。存量属别的单元的文件，本单不代修，故钉在基点现读而不是 0。
J2_GAP_CEILING = 30
J1_GAP_CEILING = 0
PRINT_CAP = 30


def read_text(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def scan_face(root):
    """被检面：`root` 下 `scripts/` 递归的 `.py`（跳过 `__pycache__`）。
    一份都没读到 ⇒ 返回空列表，由调用方自拒——缺样本＝没测，不许报绿。"""
    base = os.path.join(root, "scripts")
    out = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in ("__pycache__", ".mooncakes", "_build")]
        for fn in filenames:
            if fn.endswith(".py"):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def call_names(node):
    """节点里出现的所有被调用名：`f(...)`→`f`，`a.b(...)`→`b` 与 `a.b`。"""
    names = set()
    for n in ast.walk(node):
        if isinstance(n, ast.Call):
            f = n.func
            if isinstance(f, ast.Name):
                names.add(f.id)
            elif isinstance(f, ast.Attribute):
                names.add(f.attr)
                if isinstance(f.value, ast.Name):
                    names.add("%s.%s" % (f.value.id, f.attr))
    return names


def ancestors(tree):
    """child -> parent 表：判「这一处 4 是不是落在 except 作用域里」需要往上走。"""
    par = {}
    for n in ast.walk(tree):
        for c in ast.iter_child_nodes(n):
            par[c] = n
    return par


def in_except(par, node):
    p = par.get(node)
    while p is not None:
        if isinstance(p, ast.ExceptHandler):
            return True
        p = par.get(p)
    return False


def analyze(path):
    """静态收一张表：自检函数、调用面锚点、`4` 出现位置（是否落在 except 内）。"""
    name = os.path.basename(path)
    txt = read_text(path)
    # 被检脚本的正则/文案里常有不合法转义（`\F` `\{` `\w` `\``）——那对 Python 是 SyntaxWarning，
    # 由 ast.parse 打到 stderr 上，本尺的结论行被几十条 warning 淹掉（且 <unknown> 的定位无法追）。
    # 判据判的是「自检有没有跑到调用面」，不是那些字符串写得规不规范（后者归 check_py_escape 族）；
    # 故在解析这一格里显式忽略 SyntaxWarning，别让 warning 噪声冒充当尺子的输出。
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", SyntaxWarning)
        tree = ast.parse(txt)
    par = ancestors(tree)
    funcs = {}
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            funcs[n.name] = n
    selftest = [nm for nm in funcs if "selftest" in nm.lower().replace("_", "")]
    anchors = set(nm for nm in funcs if nm in CALL_FACE_FUNCS)
    for nm, fn in funcs.items():
        cn = call_names(fn)
        if any(s in cn for s in EXIT_SHAPE_NAMES):
            anchors.add(nm)
        if cn & set(SUBPROCESS_NAMES):
            body = ast.unparse(fn)
            if "sys.executable" in body or ("%s.py" % name[:-3]) in body:
                anchors.add(nm)
    sites = []
    for n in ast.walk(tree):
        val = None
        if isinstance(n, ast.Return):
            val = n.value
        elif isinstance(n, ast.Call):
            nm = n.func.id if isinstance(n.func, ast.Name) else \
                (n.func.attr if isinstance(n.func, ast.Attribute) else "")
            if nm in EXIT_SHAPE_NAMES and n.args:
                val = n.args[0]
        if isinstance(val, ast.Constant) and val.value == 4:
            sites.append(in_except(par, n))
    doc = ast.get_docstring(tree) or ""
    promises = any(k in doc for k in FATAL_PROMISE_KEYS) or any(k in txt for k in ("尺子自己坏了",))
    return {"name": name, "declared": "--selftest" in txt, "selftest": selftest,
            "funcs": funcs, "anchors": anchors, "fatal_sites": sites, "promises_fatal": promises}


def reachable(funcs, start):
    """从 start 函数出发沿调用名闭包能到哪些函数（只走 AST 里同名的 def，不猜动态派发）。"""
    seen, queue = set(), [start]
    while queue:
        nm = queue.pop()
        node = funcs.get(nm)
        if node is None or nm in seen:
            continue
        seen.add(nm)
        for c in call_names(node):
            if c in funcs and c not in seen:
                queue.append(c)
    return seen


def judge_one(path):
    """返回 (kind, detail)。kind ∈ self / clean / J2 / J1 / diag-inline / unparsable。"""
    name = os.path.basename(path)
    if name == SELF_NAME:
        return ("self", "本尺自锁：跳过自身")
    try:
        a = analyze(path)
    except SyntaxError as e:
        return ("unparsable", "%s: 解析不了 %s" % (name, e))
    if not a["declared"]:
        return ("clean", "%s 未申报自证面" % name)
    if not a["selftest"]:
        return ("diag-inline", name)
    hit = set()
    for st in a["selftest"]:
        hit |= reachable(a["funcs"], st)
    touched = hit & a["anchors"]
    if not touched:
        return ("J2", "%s（自检 %s 的调用图到不了 main/run/退出码面）"
                % (name, ",".join(sorted(set(a["selftest"])))))
    if a["promises_fatal"] and a["fatal_sites"] and not any(a["fatal_sites"]):
        return ("J1", "%s（承诺 4=尺子坏了，但 %d 处 `4` 全在 except 之外，崩溃路径给不出那一档）"
                % (name, len(a["fatal_sites"])))
    return ("clean", "%s 调用面 %s" % (name, ",".join(sorted(touched))))


def run(argv, root):
    """一次调用的实体。rc 只从这里出；任何异常由 `main()` 收成 4——尺子坏了不许冒用 1。"""
    ap = argparse.ArgumentParser(description="自检是否真跑调用面（J1/J2 两棘轮）")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default="")
    ap.add_argument("--j2-ceiling", type=int, default=J2_GAP_CEILING)
    ap.add_argument("--j1-ceiling", type=int, default=J1_GAP_CEILING)
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    base = a.root or root
    if not os.path.isdir(base):
        print("CALLFACE=unverifiable 被检根不存在：%s" % base)
        return 2
    face = scan_face(base)
    if not face:
        print("CALLFACE=unverifiable 被检面为空（%s 下没有 scripts/*.py）⇒ 缺样本＝没测" % base)
        return 2
    j2, j1, diag, unp, clean = [], [], [], [], 0
    for p in face:
        kind, det = judge_one(p)
        if kind == "J2":
            j2.append(det)
        elif kind == "J1":
            j1.append(det)
        elif kind == "diag-inline":
            diag.append(det)
        elif kind == "unparsable":
            unp.append(det)
        else:
            clean += 1
    print("CALLFACE 被检面 %d 份｜干净或本尺自身 %d｜J2 缺口 %d（上限 %d）｜J1 缺口 %d（上限 %d）｜只报不判 %d｜解析不了 %d"
          % (len(face), clean, len(j2), a.j2_ceiling, len(j1), a.j1_ceiling, len(diag), len(unp)))
    bad = len(j2) > a.j2_ceiling or len(j1) > a.j1_ceiling
    shown = 0
    for kind, items in (("NO_CALL_FACE", j2), ("UNREACHABLE_FATAL_CODE", j1)):
        for d in items:
            if shown >= PRINT_CAP:
                break
            print("  违例 [%s] %s" % (kind, d))
            shown += 1
    if shown == PRINT_CAP:
        print("  （违例逐条打印到上限 %d 条，其余按 kind 计数，不改判据）" % PRINT_CAP)
    for d in diag[:6]:
        print("  诊断（只报不判）inline-or-unknown-selftest：%s" % d)
    for d in unp[:5]:
        print("  诊断（AST 解析不了，不计入判据）：%s" % d)
    if bad:
        print("CALLFACE=red 处置：把调用面接进自检（`run()`/`main()` 真跑一遍四档退出码），"
              "或把上限改小——放宽上限是人的决定，本判据不自动改数。")
        return 1
    if len(j2) < a.j2_ceiling or len(j1) < a.j1_ceiling:
        print("CALLFACE=green-with-headroom 缺口低于棘轮上限，请同批把常量改小（J2 %d→%d / J1 %d→%d），"
              "否则下一次新增缺口看不出来。" % (a.j2_ceiling, len(j2), a.j1_ceiling, len(j1)))
    else:
        print("CALLFACE=clean 无超限（棘轮钉在现读 J2=%d / J1=%d）" % (a.j2_ceiling, a.j1_ceiling))
    return 0


# 干净形：自检**驱动 `run()`**（合成 argv 走真调用面），打印行与退出码才谈得上被核过
CLEAN_SRC = '''#!/usr/bin/env python3
"""demo — 退出码：0=干净 / 1=有违例 / 2=判据无法自证 / 4=尺子自己坏了。"""
import sys


def judge(x):
    return 0 if x else 1


def run(argv, root):
    if "--selftest" in argv:
        return selftest()
    return judge(True)


def selftest():
    ok = run(["x"], ".") == 0
    print("SELFTEST OK" if ok else "SELFTEST FAIL")
    return 0 if ok else 1


def main(argv=None):
    try:
        return run(list(sys.argv[1:] if argv is None else argv), ".")
    except Exception:
        print("FATAL 尺子自己坏了")
        return 4
'''
# 缺口形 = R158 第一版：`--selftest` 照报、纯函数照考，`run()`/`main()` 一次都不经过
GAP_SRC = CLEAN_SRC.replace('    ok = run(["x"], ".") == 0', "    ok = judge(True) == 0")
# 幻影 4：承诺写着 4，`return 4` 却落在 except 之外——崩溃路径永远走不到那一档
PHANTOM_SRC = CLEAN_SRC.replace("""    except Exception:
        print("FATAL 尺子自己坏了")
        return 4""", """    if 0:
        print("FATAL 尺子自己坏了")
        return 4
    return 4""").replace("""    try:
        return run(list(sys.argv[1:] if argv is None else argv), ".")""", """    try:
        return run(list(sys.argv[1:] if argv is None else argv), ".")
    except IndexError:
        return 1""")
# 自检函数换了词表外的名字 ⇒ 本尺认不出它的执行路径，只能只报不判
INLINE_SRC = CLEAN_SRC.replace("def selftest():", "def prove_face():").replace(
    "return selftest()", "return prove_face()")


def selftest():
    """合成对照：每条判据各有必红格与不误红格；再加调用面四档（本尺自己吃自己的纪律）。"""
    import shutil
    import tempfile
    fails, done = [], []

    def cell(label, got, want):
        done.append(label)
        if got != want:
            fails.append("%s: got %r want %r" % (label, got, want))

    def mk(root, name, src):
        d = os.path.join(root, "scripts")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(src)

    def cap(thunk):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = thunk()
        return rc, buf.getvalue()

    tmp = tempfile.mkdtemp(prefix="callface-selftest-")
    try:
        r_clean = os.path.join(tmp, "clean")
        mk(r_clean, "a_clean.py", CLEAN_SRC)
        cell("clean-not-flagged", run(["--root", r_clean], r_clean), 0)

        r_gap = os.path.join(tmp, "gap")
        mk(r_gap, "b_gap.py", GAP_SRC)
        cell("j2-must-red", run(["--root", r_gap, "--j2-ceiling", "0"], r_gap), 1)
        cell("j2-ratchet-allows-known", run(["--root", r_gap, "--j2-ceiling", "1"], r_gap), 0)

        r_ph = os.path.join(tmp, "phantom")
        mk(r_ph, "c_phantom.py", PHANTOM_SRC)
        cell("j1-must-red", run(["--root", r_ph], r_ph), 1)

        r_in = os.path.join(tmp, "inline")
        mk(r_in, "d_inline.py", INLINE_SRC)
        cell("inline-is-diagnostic-only", run(["--root", r_in, "--j2-ceiling", "0"], r_in), 0)

        r_unp = os.path.join(tmp, "unparsable")
        mk(r_unp, "e_broken.py", "def x(:\n")
        cell("unparsable-not-counted", run(["--root", r_unp, "--j2-ceiling", "0"], r_unp), 0)

        r_empty = os.path.join(tmp, "empty")
        os.makedirs(os.path.join(r_empty, "scripts"))
        cell("empty-face-refuses", run(["--root", r_empty], r_empty), 2)
        cell("missing-root-refuses", run(["--root", os.path.join(tmp, "nope")], tmp), 2)

        # 调用面（本尺的纪律由本尺自己跑一遍）：0/1/2 三档 + 逐条上限 + 折叠计数 + main() 的 4
        rc, out = cap(lambda: run(["--root", r_gap, "--j2-ceiling", "0"], ""))
        cell("callface-red-rc1", rc, 1)
        cell("callface-prints-kind", "违例 [NO_CALL_FACE]" in out, True)
        cell("callface-prints-disposal", "放宽上限是人的决定" in out, True)
        rc, out = cap(lambda: run(["--root", r_clean], ""))
        cell("callface-clean-rc0", rc, 0)
        cell("callface-clean-prints-face", "被检面 1 份" in out, True)
        rc, out = cap(lambda: main(["--root", r_empty]))
        cell("callface-rc2-via-main", rc, 2)

        r_fold = os.path.join(tmp, "fold")
        for i in range(PRINT_CAP + 3):
            mk(r_fold, "fold%02d_gap.py" % i, GAP_SRC)
        rc, out = cap(lambda: run(["--root", r_fold, "--j2-ceiling", "0"], ""))
        cell("fold-print-cap", out.count("违例 [NO_CALL_FACE]") == PRINT_CAP, True)
        cell("fold-keeps-total", "J2 缺口 %d" % (PRINT_CAP + 3) in out, True)
        cell("fold-notes-cap", "违例逐条打印到上限" in out, True)
        cell("fold-rc1", rc, 1)

        rc, out = cap(lambda: run(["--root", r_fold, "--j2-ceiling", str(PRINT_CAP + 3)], ""))
        cell("ratchet-at-reading-clean", rc, 0)
        rc, out = cap(lambda: run(["--root", r_fold, "--j2-ceiling", str(PRINT_CAP + 4)], ""))
        cell("headroom-asks-lower-constant", "请同批把常量改小" in out, True)

        # 尺子自己坏了：argv 里塞非字符串 ⇒ argparse 内部抛未捕获异常 ⇒ 只有 main() 的收口能给 4
        rc, out = cap(lambda: main([None]))
        cell("ruler-broken-rc4", rc, 4)
        cell("ruler-broken-says-fatal", out.startswith("FATAL 尺子自己坏了"), True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if fails:
        print("SELFTEST FAIL（%d 格）：%s" % (len(fails), " ; ".join(fails)))
        return 1
    print("SELFTEST OK（%d 格，数从已执行格子反解；未测面 0 条记为诊断，不充数）" % len(done))
    return 0


def main(argv=None):
    try:
        return run(list(sys.argv[1:] if argv is None else argv), REPO_ROOT)
    except SystemExit:
        raise                                            # argparse 的 0/2 是承诺面，不许改成 4
    except Exception as e:                               # 未捕获异常=尺子坏了，走 4，不冒充 1（BUG-369）
        print("FATAL 尺子自己坏了：%r" % e)
        return 4


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


if __name__ == "__main__":
    sys.exit(main())
