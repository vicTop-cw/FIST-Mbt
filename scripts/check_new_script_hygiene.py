#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_new_script_hygiene.py —— 提交时对**本次暂存的 scripts/*.py** 做的四条静态体检。

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

    python scripts/check_new_script_hygiene.py scripts/a.py scripts/b.py

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

# 自身路径（唯一真源）：main() 要排除自身，selftest 要用它做 A2 的「脚本自身路径」夹具。
# 判例-39：这里原先引用的 `SELF_PATH` **从未被定义** ⇒ 改名（`_new_script_hygiene.py` →
# `check_new_script_hygiene.py`）后第一次被真正跑就 `NameError` 崩在 main() 里。
# 它一直没暴露，是因为带 `_` 前缀时被 `EXEMPT_RULES` 的 `("_", …)` 自动豁免、
# **从未被任何一格跑过** ⇒ 豁免遮蔽了真实缺陷（判例-39 的第二现场）。
SELF_PATH = os.path.abspath(__file__)

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
# R221：**A3 的盲区被实测抓到 —— 「根本不看 argv」的脚本它一句话都不说。**
# 实测：`check_t0r21.py` 是纯线性判据（`argv` 一次都没出现），`--self-test` 拼错后
# **静默跑真检查**（正是 AGENTS.md 记的失效形态），而旧 A3_SCAN 的两侧都要求
# `"…--flag…" in argv` 这个形状 ⇒ 匹配不上 ⇒ **判据对最沉默的那一类完全瞎**。
# 为什么这不会变成狼来了：真读参数的脚本一定出现 `argv` 这个名（探针实测 147 份宇宙里
# 命中 2 份）；出现的走旧分支，不出现的只有「压根没写参数面」这一种可能。
# 判例-30：用 AST 判**真实名字**，不用子串 —— docstring 里提一嘴 `argv` 就满足子串式判据。


def _argv_names_real_code(text):
    """AST：文本里有没有真实的 `argv` 名（Name / Attribute.attr）。解析失败按「有」处理（保守不误报）。"""
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return True
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and node.id == "argv":
            return True
        if isinstance(node, ast.Attribute) and node.attr == "argv":
            return True
    return False


def _looks_like_ruler(text):
    """是不是「尺」形状：有按行的 print 结论（PASS/FAIL/FATAL/NOTHING）+ 文件级 docstring。

    两条同时成立才认。为什么两条：①纯 print 的脚本（`refresh_dist.py` 这类通用工具）
    不一定有结论行；②**判据本体的标志就是「按行吐 PASS/FAIL」**，而「拼错自检开关会
    静默跑真检查」这个失效形态恰恰只在判据本体上才有意义。两条同时要求 = 宁可漏也不误伤。
    """
    has_doc = bool(ast.get_docstring(ast.parse(text))) if _parses(text) else False
    # 行首锚定（判例-30）：只认 `print("PASS…` / `print("FAIL…` 这种**结论行**，
    # 不认注释或小结里提一嘴 PASS 的散文。
    verdict_line = re.search(r"""^\s*print\(\s*[fru]*['"](PASS|FAIL|FATAL|NOTHING)\b""",
                             text, re.M)
    return has_doc and bool(verdict_line)


def _parses(text):
    try:
        ast.parse(text)
        return True
    except SyntaxError:
        return False


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
    # R221 补盲区：**`argv` 一次都不出现的判据**同样逃不掉 —— 它拼错开关时行为与
    # 「扫了旗标但不拒」完全一样（静默跑真检查），只是旧正则看不见它。
    _a3_hit = bool(A3_SCAN.search(text)) or (
        _looks_like_ruler(text) and not _argv_names_real_code(text))
    if _a3_hit and not any(g.search(text) for g in A3_GUARD) \
            and A3_SUPPRESS not in text:
        adv.append("%s: A3(建议·**低精度**) 扫了 `--flag in argv` 但**没有拒绝未知旗标** —— 拼错自检开关"
                   "（`--self-test`）会被吃下并**静默跑真检查**（R197/R198/R199 同族三次）。"
                   '修法：argparse，或白名单 `if unknown: print(...); return 2`；'
                   '确实不需要参数门就写 `%s`。'
                   '⚠️ **R203 实测：本规则当前 6/6 误报**（`issue_scan`/`check_script_single_copy`/'
                   '`refresh_dist`/`git_env`/`store_isolation_probe` 等用 while 分派或整体拒绝，'
                   '实测拼错旗标都能 rc=2）⇒ **先自己跑一次 `python <script> --definitely-not-real` 验证，'
                   '再据它改代码**；真正的行为级门是 `check_arg_face_strict.py`（已在电池里）。'
                   '⚠️ **R221 补了另一半盲区**：「`argv` 一次都不出现的判据」以前一句话都不说 ——'
                   '见 `check_t0r21.py`（拼错 `--self-test` ⇒ rc=0 且**真跑了一整轮 382 格测试**）'
                   % (rel, A3_SUPPRESS))
    return out, adv


def main(argv):
    if "--selftest" in argv:
        return selftest()
    # R207 同族（AGENTS.md「新判据必须拒绝未知旗标」）：本脚本吃的是**位置参数**（.py 路径），
    # 未知旗标必须硬拒 —— 否则把 `--selftest` 拼成 `--self-test` 会落进下面的
    # 「没有 .py 入参」分支 ⇒ 打出 `NOTHING … 退出码 0`，看起来像「体检通过」，
    # 实际**自检一次都没跑**。这正是 R207 那句「自检开关拼错 = 静默失去自检」。
    # 白名单只放本脚本真认的旗标；位置参数（不以 `-` 开头）不在此列。
    _KNOWN_FLAGS = ("--selftest",)
    unknown = [a for a in argv if a.startswith("-") and a not in _KNOWN_FLAGS]
    if unknown:
        print("[FATAL] 未知参数 %s —— 已知旗标：%s（rc=2；位置参数是 .py 路径，不加 `-`）"
              % (" ".join(unknown), " / ".join(_KNOWN_FLAGS)))
        return 2
    files = [a for a in argv if not a.startswith("--")]
    targets = [f for f in files if os.path.basename(f).endswith(".py")]
    # 排除自身：本文件里的**正则源码**与**自检夹具**都含 A1/A2 的目标形状 ⇒
    # 不排它会把自己判成违规（判例-30 的自指假阳性）。这是**刻意排除**，
    # 由 selftest 格 `self-excluded` 锁定，防止有人误以为那是漏判。
    # R221 修正：这里原先写的是 `"_{self_name}.py"`，self_name 恒为 `new_script_hygiene`
    # ⇒ 拼出来是 `_new_script_hygiene.py`（**改名前的旧名**）⇒ **自身从未被排除**。
    # 因此下面那格 `self-excluded` 一直是红的（旧名还在时它是绿的，改名时没人跑自检）。
    # 判例-39（改名会同时失去按名的豁免）在这一处又踩了一遍；改成**取真文件名**，
    # 并让那格从「红着没人读」变成真门。
    targets = [f for f in targets
               if os.path.abspath(f) != os.path.abspath(SELF_PATH)]
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
    # ── R221：A3 的第二半盲区 —— 「根本不看 argv 的判据」────────────────────────
    # 这一支来自实测：`check_t0r21.py` 里 `argv` 一次都没出现，旧 A3_SCAN 匹配不上，
    # 于是 `python scripts/check_t0r21.py --self-test` **rc=0 且真跑了一整轮测试**，
    # 而判据一句提示都不给。下面四格把这个新面钉住（红 / 绿 / 不误伤 / suppression）。
    silent_ruler = (
        '"""假判据：完全不看 argv 的线性判据。"""\n'
        "import sys\n"
        "def main():\n"
        "    print('PASS 跑完了')\n"
        "    return 0\n"
        "sys.exit(main())\n"
    )
    cell("A3-silent-ruler-is-flagged",
         any("A3" in p for p in check_text("x.py", silent_ruler)[1]))
    # 反向对照①：同一份判据加了 argparse ⇒ 不再点它
    guarded_ruler = silent_ruler.replace(
        "import sys\n", "import sys\nimport argparse\nap = argparse.ArgumentParser()\n")
    cell("A3-silent-ruler-with-argparse-not-flagged",
         not any("A3" in p for p in check_text("x.py", guarded_ruler)[1]))
    # 反向对照②：同样「不看 argv」但**不是尺**（通用工具，没有 PASS/FAIL 结论行）⇒ 不点，
    # 否则这条 advisory 会从「6/6 误报」升级成「全仓一半脚本误报」。
    plain_tool = (
        '"""通用工具：打印一段东西就返回。"""\n'
        "print('hello world')\n"
    )
    cell("A3-plain-tool-not-flagged",
         not any("A3" in p for p in check_text("x.py", plain_tool)[1]))
    # 反向对照③：suppression 逃生口对这条新路径同样生效
    cell("A3-silent-ruler-suppressed",
         not any("A3" in p for p in check_text(
             "x.py", silent_ruler.replace("import sys\n", "import sys\n# %s\n" % A3_SUPPRESS))[1]))
    # 变异对照（判例-29「机制格 ≠ 实现路径格」）：把 `_looks_like_ruler` / `_argv_names_real_code`
    # 的真实现抽掉 ⇒ `A3-silent-ruler-is-flagged` 必须变红。这里不复制一份正则，
    # 而是直接调那两个函数并断言它们对上面的样本**真的**给出了预期的真假值 ——
    # 判据「红」是靠它们算出来的，它们算错则上面那一格必红。
    cell("A3-mutation-looks-like-ruler-real",
         _looks_like_ruler(silent_ruler) and not _looks_like_ruler(plain_tool),
         "got ruler=%r tool=%r（`_looks_like_ruler` 判错 ⇒ 上面那格的红是假的）"
         % (_looks_like_ruler(silent_ruler), _looks_like_ruler(plain_tool)))
    cell("A3-mutation-argv-names-real",
         not _argv_names_real_code(silent_ruler) and _argv_names_real_code(good_a3_wl),
         "got silent=%r guarded=%r（`_argv_names_real_code` 判错 ⇒ 上面那格的红是假的）"
         % (_argv_names_real_code(silent_ruler), _argv_names_real_code(good_a3_wl)))
    cell("A2-bad-is-flagged", any("A2" in p for p in check_text("x.py", bad_a2)[0]))
    cell("A2-good-not-flagged", not any("A2" in p for p in check_text("x.py", good_a2)[0]))

    # 端到端：真建文件跑 main()
    tmp = tempfile.mkdtemp(prefix="hygiene-st-")
    p_bad = os.path.join(tmp, "bad.py")
    io.open(p_bad, "w", encoding="utf-8").write(bad_e1)
    rc_bad = _quiet(main, [p_bad])
    # 自指格（判例-30）：本文件必须被排除，否则它会被自己的正则判成违规
    rc_self = _quiet(main, [os.path.abspath("scripts/check_new_script_hygiene.py")])
    cell("self-excluded", rc_self == 0, "got rc=%d（应为 0：自身已排除）" % rc_self)
    cell("end-to-end-bad-rc1", rc_bad == 1, "got rc=%d" % rc_bad)
    p_ok = os.path.join(tmp, "ok.py")
    io.open(p_ok, "w", encoding="utf-8").write(good_e1 + good_a1)
    rc_ok = _quiet(main, [p_ok])
    cell("end-to-end-good-rc0", rc_ok == 0, "got rc=%d" % rc_ok)

    # R207 同族（AGENTS.md「新判据必须拒绝未知旗标」）：本脚本吃**位置参数**，未知旗标必须硬拒。
    # 三格全部**合成入参**（不读真仓 ⇒ 不抬棘轮基线）：
    #   ① 拼错的自检开关（`--self-test`）必须被拒 —— 这正是 R207 的失效形态：没有这道闸时
    #      它会落进「没有 .py 入参」⇒ 打出 `NOTHING … 退出码 0`，看着像「体检通过」，
    #      实际**自检一次都没跑**（判例-30 第三形态的近亲：用例看起来在测，实际测了空输入）。
    #   ② 真未知旗标 ⇒ rc=2。
    #   ③ 反向对照：真的无参 ⇒ rc=0（证明这道闸是**判别**，不是一刀切拒所有参数）。
    #   ① 直接调 `main()` 本体（实现路径格），所以不需要再补一格「源码里有没有这道闸」——
    #      判据-29 要防的是「测了机制没测实现」，这里测的就是实现本身。
    rc_misspelled = _quiet(main, ["--self-test"])
    cell("end-to-end-misspelled-selftest-rejected", rc_misspelled == 2,
         "got rc=%d（应为 2：拼错的自检开关必须被拒，否则静默失去自检）" % rc_misspelled)
    rc_unk = _quiet(main, ["--definitely-not-real"])
    cell("end-to-end-unknown-flag-rc2", rc_unk == 2, "got rc=%d" % rc_unk)
    rc_noargs = _quiet(main, [])
    cell("end-to-end-no-args-rc0-is-legit", rc_noargs == 0,
         "got rc=%d（应为 0：真的无参时 NOTHING 是合法读数，闸不该一刀切）" % rc_noargs)
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
