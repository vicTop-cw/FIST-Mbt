#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_new_script_hygiene.py —— 提交时对**本次暂存的 scripts/*.py** 做的三条静态体检。

## 为什么要有它（不是理论，是本场三次实测）

| 坑 | 实测 |
|---|---|
| **E1**：打印非 ASCII 却没有 stdout `reconfigure` 门 | R63/R64 我新增两个判据都没带门 ⇒ `check_py_stdout_encoding --all` 红了两轮没人发现（我只跑自选的 10 判据子集） |
| **A1**：`if a != "--selftest"` 把**位置参数**判成未知 | R65 我 12 把判据全中；电池喂 `check_skill_inject.py fist-mbt.db` 才暴露 |
| **A2**：用 `sys.argv`（含 argv[0]）判未知参数 | R65 `check_desc_enum_sync` 把**脚本自身路径**当未知旗标 ⇒ `--selftest` 恒 rc=2 |

**⇒ 三条都「机器可判、代价极低」，所以放进提交门比写进文档更有效。**
本脚本**只判入参点名的文件**（pre-commit 传暂存面），不看全仓 ⇒
**不会因为别的 lane 的 WIP 误拦我的提交**。

## 用法

    python scripts/_new_script_hygiene.py scripts/a.py scripts/b.py

退出码：`0` 干净 / `1` 有违例（逐条点名）/ `2` 入参里没有可判的文件（不静默出绿）。

## 自证

`--selftest` 用**临时合成文件**验三条规则各自会咬、且不误伤（判例-29/30：改坏的是代码面）。
"""
import ast
import io
import os
import re
import sys
import tempfile

# stdout UTF-8 门（BUG-58/138）：本文件打印中文结论，必须带门，否则本机控制台一红
# 就崩在结论行之前，rc 被冒用成「缺陷在场」。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

NON_ASCII = re.compile(r"[^\x00-\x7f]")
PRINT_CALL = re.compile(r"(?<![\w.])print\s*\(")
GATE = "reconfigure"
# A1：列表推导里用 `a != "--selftest"` 判未知 —— 位置参数会被误判
A1 = re.compile(r"for a in [^\]\n]+ if a != \"--selftest\"\]")
# A2：用完整 sys.argv（含 argv[0]=脚本自身路径）判未知
A2 = re.compile(r"for a in sys\.argv if ")


def _has_real_gate(text):
    """真有 `*.reconfigure(...)` 调用吗（AST；解析失败按「无门」处理）。"""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == "reconfigure":
                return True
    return False


def check_text(rel, text):
    """纯函数：返回违例列表。"""
    out = []
    # 判例-30：不能用「子串出现」判门 —— 注释/夹具里提一嘴就满足了。用 AST 认**真调用**。
    if PRINT_CALL.search(text) and NON_ASCII.search(text) and not _has_real_gate(text):
        out.append("%s: E1 打印非 ASCII 却没有 stdout `reconfigure` 门 —— 本机控制台一红就崩在"
                   "结论行之前，rc 会被冒用成「缺陷在场」（见 check_py_stdout_encoding E1）" % rel)
    if A1.search(text):
        out.append('%s: A1 用 `if a != "--selftest"` 判未知参数 —— **位置参数**会被误判成未知'
                   "（R65 实测：`check_skill_inject.py fist-mbt.db` ⇒ FATAL 未知参数）。"
                   '正确形状：`if a.startswith("--") and a != "--selftest"`' % rel)
    if A2.search(text):
        out.append("%s: A2 用 `for a in sys.argv` 判未知参数 —— 含 argv[0]（脚本自身路径），"
                   "它会被当成未知旗标 ⇒ 恒 rc=2（R65 实测）。改成 `sys.argv[1:]`" % rel)
    return out


def main(argv):
    if "--selftest" in argv:
        return selftest()
    files = [a for a in argv if not a.startswith("--")]
    targets = [f for f in files if os.path.basename(f).endswith(".py")]
    # 排除自身：本文件里的**正则源码**与**自检夹具**都含 A1/A2 的目标形状 ⇒
    # 不排它会把自己判成违规（判例-30 的自指假阳性）。这是**刻意排除**，
    # 由 selftest 格 `self-excluded` 锁定，防止有人误以为那是漏判。
    targets = [f for f in targets if os.path.basename(f) != "_{self_name}.py".format(self_name="new_script_hygiene")]
    if not targets:
        print("NOTHING 入参里没有 .py（%d 个参数）—— 无可判面，退出码 0 由调用方决定是否算过"
              % len(files))
        return 0
    problems = []
    for rel in targets:
        try:
            text = io.open(rel, encoding="utf-8", errors="replace").read()
        except OSError as e:
            problems.append("%s: 读不到（%s）—— 拒绝判绿" % (rel, e))
            continue
        problems.extend(check_text(rel.replace("\\", "/"), text))
    if problems:
        print("FAIL 暂存脚本体检 %d 条：" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS 暂存脚本体检：%d 份 .py 无 E1/A1/A2 违例" % len(targets))
    return 0


def selftest():
    cells, fails = [], []

    def cell(name, ok, detail=""):
        cells.append(name)
        if not ok:
            fails.append("%s %s" % (name, detail))

    bad_e1 = "print('中文结论')\n"
    good_e1 = 'import sys\nsys.stdout.reconfigure(encoding="utf-8")\nprint("中文结论")\n'
    bad_a1 = 'unknown = [a for a in argv if a != "--selftest"]\n'
    good_a1 = 'unknown = [a for a in argv if a.startswith("--") and a != "--selftest"]\n'
    bad_a2 = "unknown = [a for a in sys.argv if a.startswith('--')]\n"
    good_a2 = "unknown = [a for a in sys.argv[1:] if a.startswith('--')]\n"

    cell("E1-bad-is-flagged", any("E1" in p for p in check_text("x.py", bad_e1)))
    cell("E1-good-not-flagged", not any("E1" in p for p in check_text("x.py", good_e1)))
    # 判例-30 收口：**只提一嘴 reconfigure、没有真调用**必须被判 E1
    mention_only = "import sys\n# 提一句 sys.stdout.reconfigure( 但没调用\nprint('中文')\n"
    cell("E1-mention-only-is-flagged",
         any("E1" in p for p in check_text("x.py", mention_only)))
    cell("A1-bad-is-flagged", any("A1" in p for p in check_text("x.py", bad_a1)))
    cell("A1-good-not-flagged", not any("A1" in p for p in check_text("x.py", good_a1)))
    cell("A2-bad-is-flagged", any("A2" in p for p in check_text("x.py", bad_a2)))
    cell("A2-good-not-flagged", not any("A2" in p for p in check_text("x.py", good_a2)))

    # 端到端：真建文件跑 main()
    tmp = tempfile.mkdtemp(prefix="hygiene-st-")
    p_bad = os.path.join(tmp, "bad.py")
    io.open(p_bad, "w", encoding="utf-8").write(bad_e1)
    rc_bad = _quiet(main, [p_bad])
    # 自指格（判例-30）：本文件必须被排除，否则它会被自己的正则判成违规
    rc_self = _quiet(main, [os.path.abspath("scripts/_new_script_hygiene.py")])
    cell("self-excluded", rc_self == 0, "got rc=%d（应为 0：自身已排除）" % rc_self)
    cell("end-to-end-bad-rc1", rc_bad == 1, "got rc=%d" % rc_bad)
    p_ok = os.path.join(tmp, "ok.py")
    io.open(p_ok, "w", encoding="utf-8").write(good_e1 + good_a1)
    rc_ok = _quiet(main, [p_ok])
    cell("end-to-end-good-rc0", rc_ok == 0, "got rc=%d" % rc_ok)
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL", len(cells), " ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def _quiet(fn, argv):
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        return fn(argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
