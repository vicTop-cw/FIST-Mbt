#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_py_stdout_encoding.py — CI 侧脚本的 stdout 编码闸（BUG-138）。

要防的事：守卫在 Windows 默认 cp936 控制台上**一红就崩在结论行之前**——`print` 中文结论里的
`⇒` 之类字符抛 UnicodeEncodeError，留下 traceback + rc=1，而 1 恰是「缺陷在场」那一档
（判据自己的崩冒用了被测的退出码；`e2e_native_heap_probe` 为此专门设了 4 号档）。
2026-10-07 本机实测两次打到：`check_publish_payload.py` 打 VIOLATION 时崩、守卫族跑器同一位置崩。

扫描面**默认从 workflow 反解**（`.github/workflows/*.yml` 里出现的 `scripts/**.py`），不手写清单——
手写的族名必然落后于新增的脚本（J10/BUG-122 的老账）。`--all` 把扫描面扩到**全部正式脚本**
（glob `scripts/**/*.py`，BUG-138 追记的残余面：非 CI 调用面同样会在本机崩，而且更常被人手跑）。
CI 在 Linux UTF-8 下这段是无损 no-op，所以这条判据保护的是**本机复跑时那条红能不能被看见**。

判据：会 `print` + 正文含非 ASCII ⇒ 必须含 `sys.stdout.reconfigure` 那两行。
兄弟面（纯 ASCII 脚本、不 print 的脚本）不误红，只出 E2 预告——**预告不计入退出码**，
这样「扩面」不会把今天根本不坏的东西判成违例（BACKLOG P3 扩面前提）。

退出码：0=PASS / 1=违例 / 2=判据无法自证（扫描面空、CI 指到不存在的脚本、全部脚本都不 print）。

用法：
    python scripts/check_py_stdout_encoding.py            # CI 面（从 workflow 反解）
    python scripts/check_py_stdout_encoding.py --all      # 全部正式脚本
    python scripts/check_py_stdout_encoding.py --selftest # 考这把尺自己
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WF_GLOB = os.path.join(ROOT, ".github", "workflows", "*.yml")
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
DOCS_EXAMPLES_DIR = os.path.join(ROOT, "docs", "examples")
RE_SCRIPT = re.compile(r"scripts/[\w\-/]+\.py")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def ci_script_faces():
    """从 workflow 反解被 CI 调用的脚本相对路径（去重、排序，返回 POSIX 分隔）。"""
    found = set()
    for wf in sorted(glob.glob(WF_GLOB)):
        t = io.open(wf, encoding="utf-8", errors="replace").read()
        for m in RE_SCRIPT.finditer(t):
            found.add(m.group(0))
    return sorted(found)


def all_script_faces():
    """全部正式脚本面（BACKLOG P3 扩面）：glob 而非反解，所以带连字符的文件名
    （`scripts/fist-mbt-http.py`）也在面上——CI 反解的正则 `scripts/[\\w/]+\\.py` 认不出
    连字符，那一格只有 glob 兜得住。测试用临时脚本落 temp/，不在 scripts/ 下，天然排除。

    2026-10-13 再扩：`docs/examples/**/*.py` 也在面上。触发点是我自己新加的
    `docs/examples/python/http_client.py`——它有中文 print，落在这把尺的老扫描面之外
    （只 walk scripts/）⇒ 同一条 BUG-138 风险在 examples 面没人守。目录不存在就跳过
    （不误红、也不因缺目录而 FATAL，CI 面不依赖它）。
    **排除 `_` 前缀临时脚本**：与 `check_scripts_index` 的「_ 前缀=即用即清、不要求登记」同口径。
    实测触发点——扩面后 `--all` 抓到 `scripts/_tmp_boundary_omega.py`（未跟踪临时件）缺闸报红，
    那是把临时件错当正式面判的假红，不是产品坏；临时件本就即用即清，不纳入编码闸义务。"""
    out = []
    for base in (SCRIPTS_DIR, DOCS_EXAMPLES_DIR):
        if not os.path.isdir(base):
            continue
        for dp, _dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".py") and not f.startswith("_"):
                    out.append(
                        os.path.relpath(os.path.join(dp, f), ROOT).replace(os.sep, "/"))
    return sorted(out)


def needs_gate(text):
    return "print(" in text and any(ord(c) > 127 for c in text)


def has_gate(text):
    return "reconfigure" in text


def evaluate(rel_paths, reader):
    """纯判定：rel_paths=扫描面， reader(rel)->正文|None（None=盘上没有这份）。
    返回 (违例, 预告, 该带闸数, 已带闸数)——**预告不是违例**：纯 ASCII 的脚本今天崩不了，
    把它判红就是「现状面被自己的尺子打回」；但也不能当干净，否则下一个中文就无人报信。"""
    problems = []
    notes = []
    scanned = 0
    gated = 0
    for rel in rel_paths:
        text = reader(rel)
        if text is None:
            problems.append(
                "E0 workflow 点名的 %s 在盘上不存在 ⇒ 扫描面本身不可信" % rel)
            continue
        if needs_gate(text):
            scanned += 1
            if has_gate(text):
                gated += 1
            else:
                problems.append(
                    "E1 %s 会 print 非 ASCII 却没有 BUG-58/138 的 stdout UTF-8 重配 ⇒ "
                    "本机一红就崩在结论行之前，rc 被冒用成「缺陷在场」" % rel)
        elif not has_gate(text) and "print(" in text:
            notes.append(
                "E2(预告) %s 会 print、正文暂纯 ASCII 因而今天不红 ⇒ 下一句中文结论就踩 E1，"
                "补闸是待办不是可选" % rel)
    if scanned == 0:
        problems.append(
            "FATAL 扫描面里一份「会 print 非 ASCII」的脚本都没解析到（%d 个候选）⇒ "
            "判据饿死，不报绿" % len(rel_paths))
    elif gated == 0:
        problems.append(
            "FATAL %d 份该带闸的脚本里没有一份带闸 ⇒ 更可能是闸的写法变了，不是全场都坏" % scanned)
    return problems, notes, scanned, gated


# ↓ 严格参数面（R66）：未知旗标不再被静默忽略（拼错 --selftest 会假绿）
_known = {"--selftest", "--all"}
_unknown = [a for a in sys.argv[1:] if a.startswith("--") and a.split("=")[0] not in _known]
if _unknown:
    print("FATAL 未知参数：%s（本尺只接受：%s）" % (" ".join(_unknown), " ".join(sorted(_known))))
    sys.exit(2)

def real_problems(scan_all=False):
    faces = all_script_faces() if scan_all else ci_script_faces()
    if not faces:
        return (["FATAL %s 扫描面反解不到任何 scripts/*.py ⇒ 判据无从生效"
                 % ("--all" if scan_all else "workflow")], [], 0, 0)

    def reader(rel):
        p = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.isfile(p):
            return None
        return io.open(p, encoding="utf-8", errors="replace").read()

    return evaluate(faces, reader)


def selftest():
    fails = []
    ok_body = ("import sys\n"
               "# 中文说明\n"
               'if hasattr(sys.stdout, "reconfigure"):\n'
               '    sys.stdout.reconfigure(encoding="utf-8", errors="replace")\n'
               'print("PASS ⇒ 干净")\n')
    bad_body = "import sys\n# 中文说明\nprint('VIOLATION ⇒ 红在这里崩')\n"
    ascii_body = "import sys\nprint('plain ascii only')\n"
    faces = ["a.py", "b.py", "c.py"]
    books = {"a.py": ok_body, "b.py": bad_body, "c.py": ascii_body}
    probs, notes, scanned, gated = evaluate(faces, lambda r: books.get(r))
    if not any("E1 b.py" in p for p in probs):
        fails.append("M1 摘掉闸的脚本没被判红 → 判据是装饰")
    if any("a.py" in p for p in probs):
        fails.append("G1 带闸且正文含中文的脚本被误红 → 现状面会被自己的尺子打回")
    # 成对：纯 ASCII + 有 print 不算违例（只出预告），否则第一个英文脚本就红
    if not any("E2(预告) c.py" in p for p in notes):
        fails.append("M2 纯 ASCII 面没被预告 → 这道门是空的，下一份中文脚本没人报信")
    if any("c.py" in p for p in probs):
        fails.append("M2b 纯 ASCII 面被判成违例 → 现状面会被自己的尺子打回")
    # 空扫描必自拒
    probs_empty, _, _, _ = evaluate(["a.py"], lambda r: "x = 1\n")
    if not any("FATAL" in p for p in probs_empty):
        fails.append("M3 扫描面读不到任何该带闸的脚本时不自拒 → 判据失效被读成没有问题")
    # workflow 指到不存在的脚本必红（扫描面本身要可信）
    probs_missing, _, _, _ = evaluate(["gone.py"], lambda r: None)
    if not any("E0" in p for p in probs_missing):
        fails.append("M4 workflow 点名盘上不存在的脚本时不判红 → 扫描面悄悄缩小")
    real, _, scanned_n, gated_n = real_problems()
    if real:
        fails.append("现状面就红（先判尺子，再判被测）：" + real[0])
    # M5（BACKLOG P3 扩面）：--all 面必须是 CI 面的超集——CI 点名的脚本若掉出全量面，
    # 说明 glob 与反解两把尺对不上，扩面就是纸面扩面。
    wide = all_script_faces()
    narrow = ci_script_faces()
    lost = [r for r in narrow if r not in wide]
    if lost:
        fails.append("M5 --all 面不含 CI 点名脚本 %s → 两把尺对不上，扩面是假的" % lost)
    real_all, _, wn, wg = real_problems(scan_all=True)
    if real_all:
        fails.append("--all 现状面就红（先判尺子，再判被测）：" + real_all[0])
    if wn <= scanned_n:
        fails.append("M5b --all 面该带闸数 %d 不大于 CI 面 %d → 扩面没真的扩" % (wn, scanned_n))
    # M6：直接调 main() 走 PASS/FAIL 两条 print 分支——selftest 若只测纯函数 evaluate，
    # 就照不到输出行的格式化 bug（本轮真在 PASS 行写错过占位符，TypeError 崩在结论行，
    # 恰是这条守卫自己该防的「崩在结论行之前」——尺子先于被测坏掉）。
    import contextlib
    for argv in (["check_py_stdout_encoding.py"],
                 ["check_py_stdout_encoding.py", "--all"]):
        old = sys.argv
        try:
            sys.argv = argv
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = main()
            if rc != 0:
                fails.append("M6 main(%s) 返回 %d ≠ 0（现状面本该全绿）" % (argv[1:], rc))
            if "PASS" not in buf.getvalue():
                fails.append("M6 main(%s) 没打出 PASS 行" % (argv[1:],))
        except Exception as e:
            fails.append("M6 main(%s) 抛异常（输出行格式化坏了？）：%s" % (argv[1:], e))
        finally:
            sys.argv = old
    if fails:
        print("SELFTEST FAIL：")
        for f in fails:
            print("  - " + f)
        return 2
    print("SELFTEST OK：CI 面从 workflow 反解（%d 份候选，该带闸 %d 份、已带 %d 份），"
          "--all 面 glob 全量（%d 份候选，该带闸 %d 份）；M1 摘闸必红 / G1 带闸不误红 / "
          "M2 纯 ASCII 只预告不判红 / M3 空扫描必自拒 / M4 悬空点名必红 / M5 扩面超集且现状不红 / "
          "M6 main() 两档实调（照出输出行格式化 bug）"
          % (len(narrow), scanned_n, gated_n, len(wide), wn))
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    scan_all = "--all" in sys.argv
    problems, notes, scanned, gated = real_problems(scan_all=scan_all)
    for n in notes:
        print("  " + n)
    scope = "--all 全部正式脚本" if scan_all else "CI 侧（workflow 反解）"
    if problems:
        print("FAIL %s的 stdout 编码闸（该带闸 %d 份 / 已带 %d 份）：" % (scope, scanned, gated))
        for p in problems:
            print("  - " + p)
        return 2 if any(p.startswith("FATAL") or p.startswith("E0") for p in problems) else 1
    print("PASS %s的 stdout 编码闸齐备：该带闸 %d 份 / 已带 %d 份，另有 %d 份纯 ASCII 面出了预告"
          % (scope, scanned, gated, len(notes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
