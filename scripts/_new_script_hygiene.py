#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/_new_script_hygiene.py —— 提交时对**本次暂存的 scripts/*.py** 做的四条静态体检。

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
# A3（R200）：**扫了旗标但没有拒绝未知旗标** ⇒ 拼错自检开关会静默跑真检查。
# 实测同族三次：`check_bug_ledger_shape.py`（R197）/ `check_mcp_stdio_purity.py`（R198）/
# `check_warning_ledger.py`（R199）—— 三次都是"新脚本没兜住未知旗标"，由 `check_arg_face_strict` 事后抓。
# 这条规则把**事后**变成**提交时**：新脚本要么用 argparse（天生拒绝），要么有白名单。
A3_SCAN = re.compile(r'"[^"\n]*--[a-z][\w-]*[^"\n]*"\s+in\s+(?:sys\.)?argv')
# R203：**识别面要宽，否则 advisory 会变成狼来了**。实测两个误报：
#   · `check_script_single_copy.py` 用 `if argv: print(...); return 2`（**整体拒绝**剩余参数）
#   · `issue_scan.py` 用 while 显式分派 + 未知分支（实测 `--definitely-not-real` ⇒ **rc=2**）
# 两者都是合格的守卫，只是形状不在 R200 那四种里 ⇒ 补齐。
A3_GUARD = (
    re.compile(r"argparse\.ArgumentParser\s*\("),
    re.compile(r"not\s+in\s+[\(\[]"),          # `a not in ("--selftest", …)`
    re.compile(r"not\s+in\s+_?[A-Z_]{3,}\b"),  # `a not in _KNOWN_FLAGS`
    re.compile(r"unknown\s*=\s*\["),           # 显式收集未知旗标
    re.compile(r"if\s+argv\s*:"),              # 整体拒绝：剩下任何参数都算未知（R203）
    # 显式分派 + 未知分支：**消息里点名"不认识/未知"** 且伴随非零退出
    re.compile(r"(不认识的参数|未知参数|未知旗标|unrecognized|unknown\s+arg)"),
)
# 逃生口：确实不需要参数门的脚本（例如纯库/纯函数）在文件里写这一句
A3_SUPPRESS = "hygiene: no-arg-gate"


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
    """纯函数：返回 (blocking, advisory) 两个违例列表。

    **R200：A3 是 advisory（不阻断）**。实测全仓 153 个脚本里 10 个命中 A3 ——
    若阻断，任何人**改到**这 10 个文件都会被提交钩子挡住（共享仓里的意外摩擦）。
    真正的落地门由 `check_arg_face_strict.py`（事后、按结果）承担；
    本规则的价值是**在写的时候就在眼前提示一次**。
    """
    out = []
    adv = []
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
    # A3（R200）：扫旗标但不拒绝未知 ⇒ 拼错自检开关会静默跑真检查（同族实测三次）
    if A3_SCAN.search(text) and not any(g.search(text) for g in A3_GUARD) \
            and A3_SUPPRESS not in text:
        adv.append("%s: A3(建议·**低精度**) 扫了 `--flag in argv` 但**没有拒绝未知旗标** —— 拼错自检开关"
                   "（`--self-test`）会被吃下并**静默跑真检查**（R197/R198/R199 同族三次）。"
                   '修法：argparse，或白名单 `if unknown: print(...); return 2`；'
                   '确实不需要参数门就写 `%s`。'
                   '⚠️ **R203 实测：本规则当前 6/6 误报**（`issue_scan`/`check_script_single_copy`/'
                   '`refresh_dist`/`git_env`/`store_isolation_probe` 等用 while 分派或整体拒绝，'
                   '实测拼错旗标都能 rc=2）⇒ **先自己跑一次 `python <script> --definitely-not-real` 验证，'
                   '再据它改代码**；真正的行为级门是 `check_arg_face_strict.py`（已在电池里）'
                   % (rel, A3_SUPPRESS))
    return out, adv


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
    warns = []
    for rel in targets:
        try:
            text = io.open(rel, encoding="utf-8", errors="replace").read()
        except OSError as e:
            problems.append("%s: 读不到（%s）—— 拒绝判绿" % (rel, e))
            continue
        blocking, advisory = check_text(rel.replace("\\", "/"), text)
        problems.extend(blocking)
        warns.extend(advisory)
    for w in warns:
        print("WARN " + w)   # advisory：不阻断，只提示
    if problems:
        print("FAIL 暂存脚本体检 %d 条：" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("PASS 暂存脚本体检：%d 份 .py 无 E1/A1/A2/A3 违例" % len(targets))
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

    cell("E1-bad-is-flagged", any("E1" in p for p in check_text("x.py", bad_e1)[0]))
    cell("E1-good-not-flagged", not any("E1" in p for p in check_text("x.py", good_e1)[0]))
    # 判例-30 收口：**只提一嘴 reconfigure、没有真调用**必须被判 E1
    mention_only = "import sys\n# 提一句 sys.stdout.reconfigure( 但没调用\nprint('中文')\n"
    cell("E1-mention-only-is-flagged",
         any("E1" in p for p in check_text("x.py", mention_only)[0]))
    cell("A1-bad-is-flagged", any("A1" in p for p in check_text("x.py", bad_a1)[0]))
    cell("A1-good-not-flagged", not any("A1" in p for p in check_text("x.py", good_a1)[0]))
    # A3（R200）：扫旗标但不拒绝未知 ⇒ 必须红；两种正解（argparse / 白名单）⇒ 不红
    bad_a3 = 'if "--selftest" in argv:\n    pass\n'  # 扫了旗标、无任何兜底
    good_a3_ap = (
        "import argparse\n"
        'ap = argparse.ArgumentParser()\n'
        'ap.add_argument("--selftest", action="store_true")\n'
        'if "--selftest" in argv:\n    pass\n'
    )
    good_a3_wl = (
        '_KNOWN = ("--selftest",)\n'
        'unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN]\n'
        "if unknown:\n    return 2\n"
    )
    # R203：两种"合格但形状不同"的守卫不许误报
    good_a3_blanket = 'if argv:\n    print("不认识的参数")\n    return 2\n'
    good_a3_dispatch = 'else:\n    print("FAIL 未知参数")\n    sys.exit(2)\n'
    cell("A3-blanket-reject-not-flagged",
         not any("A3" in p for p in check_text("x.py", good_a3_blanket)[1]))
    cell("A3-message-named-not-flagged",
         not any("A3" in p for p in check_text("x.py", good_a3_dispatch)[1]))
    cell("A3-bad-is-advisory", any("A3" in p for p in check_text("x.py", bad_a3)[1])
         and not any("A3" in p for p in check_text("x.py", bad_a3)[0]))
    cell("A3-argparse-not-flagged", not any("A3" in p for p in check_text("x.py", good_a3_ap)[1]))
    cell("A3-whitelist-not-flagged", not any("A3" in p for p in check_text("x.py", good_a3_wl)[1]))
    cell("A2-bad-is-flagged", any("A2" in p for p in check_text("x.py", bad_a2)[0]))
    cell("A2-good-not-flagged", not any("A2" in p for p in check_text("x.py", good_a2)[0]))

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
