#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_py_stdout_encoding.py — CI 侧脚本的 stdout 编码闸（BUG-138）。

要防的事：守卫在 Windows 默认 cp936 控制台上**一红就崩在结论行之前**——`print` 中文结论里的
`⇒` 之类字符抛 UnicodeEncodeError，留下 traceback + rc=1，而 1 恰是「缺陷在场」那一档
（判据自己的崩冒用了被测的退出码；`e2e_native_heap_probe` 为此专门设了 4 号档）。
2026-10-07 本机实测两次打到：`check_publish_payload.py` 打 VIOLATION 时崩、守卫族跑器同一位置崩。

扫描面**从 workflow 反解**（`.github/workflows/*.yml` 里出现的 `scripts/**.py`），不手写清单——
手写的族名必然落后于新增的脚本（J10/BUG-122 的老账）。CI 在 Linux UTF-8 下这段是无损 no-op，
所以这条判据保护的是**本机复跑守卫时那条红能不能被看见**。

判据：被 CI 调用 + 会 `print` + 正文含非 ASCII ⇒ 必须含 `sys.stdout.reconfigure` 那两行。
`reconfigure` 的兄弟面（纯 ASCII 脚本、不 print 的脚本）不误红。

退出码：0=PASS / 1=违例 / 2=判据无法自证（扫描面空、CI 指到不存在的脚本、全部脚本都不 print）。

用法：
    python scripts/check_py_stdout_encoding.py            # 全量
    python scripts/check_py_stdout_encoding.py --selftest # 考这把尺自己
"""
import glob
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WF_GLOB = os.path.join(ROOT, ".github", "workflows", "*.yml")
RE_SCRIPT = re.compile(r"scripts/[\w/]+\.py")

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


def real_problems():
    faces = ci_script_faces()
    if not faces:
        return (["FATAL workflow 里反解不到任何 scripts/*.py ⇒ 扫描面为空，判据无从生效"],
                [], 0, 0)

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
    if fails:
        print("SELFTEST FAIL：")
        for f in fails:
            print("  - " + f)
        return 2
    print("SELFTEST OK：扫描面从 workflow 反解（%d 份候选，其中该带闸 %d 份、已带 %d 份），"
          "M1 摘闸必红 / G1 带闸不误红 / M2 纯 ASCII 只预告不判红 / M3 空扫描必自拒 / "
          "M4 悬空点名必红" % (len(ci_script_faces()), scanned_n, gated_n))
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    problems, notes, scanned, gated = real_problems()
    for n in notes:
        print("  " + n)
    if problems:
        print("FAIL CI 侧脚本的 stdout 编码闸（该带闸 %d 份 / 已带 %d 份）：" % (scanned, gated))
        for p in problems:
            print("  - " + p)
        return 2 if any(p.startswith("FATAL") or p.startswith("E0") for p in problems) else 1
    print("PASS CI 侧脚本的 stdout 编码闸齐备：%d 份该带闸 / 全部带闸（扫描面从 workflow 反解 %d 份，"
          "另有 %d 份纯 ASCII 面出了预告）"
          % (scanned, gated, len(notes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
