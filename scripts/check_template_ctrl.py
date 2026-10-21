#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""scripts/check_template_ctrl.py — 模板/提示词文件「无裸控制字符」守卫。

**为什么需要它（2026-10-14 普查实测）**：`templates/` 是**发给 agent 的提示词面**。普查发现
**9 份模板含裸控制字符**（pipeline_mode_* ×7 + pipeline_meta_prompt + tool_use_rubric），
**其中 7 份 pipeline_mode_*.md 是真缺陷**（git blob 里确有裸 CR，已被后续修复提交归零），
**pipeline_meta_prompt / tool_use_rubric 是 autocrlf 假象**（blob 本是 LF，工作树 CR 是 checkout 注入，
见判据 T1 的 CRLF 容忍说明）。真缺陷的成因是这些文件曾经过一次**转义序列解释**——
`\t` `\r` `\b` `\e` `\v` 被当成控制字符吃掉首字母：

    task_plan_deep  ->  <TAB>ask_plan_deep      （t 被 TAB 吃掉）
    reject / retry  ->  <CR>eject / <CR>etry    （r 被 CR 吃掉）
    bug_list        ->  <BS>ug_list             （b 被 BS 吃掉）
    execute         ->  <ESC>xecute             （e 被 ESC 吃掉）
    verify          ->  <VT>erify               （v 被 VT 吃掉）

**后果不是"排版难看"**：模板里的**工具名错一个字母，执行者就调不到工具**（工具名大小写/拼写敏感，
调错名 = 空回）。这正是"文档即实现"面的实质缺陷。

**判据**（窄口径，只判确定性问题）：
  T1 `templates/**/*.md` 的字节里不得含**裸**控制字符（除 LF 与 TAB）。
    白名单：`\n`(0x0a) 换行；`\t`(0x09) 制表符（Markdown 表格/缩进合法用途，本判据放行）；
    **`\r\n`(CRLF) 行尾**——Windows 侧 `core.autocrlf=true` 会把 checkout 出的文本转成 CRLF，
    这是工作树注入的合法行尾、不是真实缺陷，判据容忍（只跳过 CR，LF 照常换行计数）。
    判红：**裸 `\r`**(0x0d，后不接 LF) / `\b`(0x08) / `\v`(0x0b) / `\f`(0x0c) / `\x1b`(0x1b) 及其它 C0 控制字符。
    注：2026-10-14 普查后发现 `pipeline_meta_prompt.md` / `tool_use_rubric.md` 的 git blob 本是 LF，
    工作树里那 159/53 个 `\r` 全是 autocrlf checkout 假象（不是提交缺陷），本判据据此放宽 CRLF；
    配套 `templates/*.md  text eol=lf`（.gitattributes）从源头钉死，双保险。
  T2 防空转：一份 .md 都枚举不到 ⇒ FATAL（判据空转 ≠ 没问题）。
    R42 起该 FATAL **真给 rc=2**：改前是 `raise SystemExit("FATAL …")`，带字符串的 SystemExit
    退出码是 1 ⇒ 第 38 行自述的「2=判据无法自证」从未生效（BUG-369 三条纯幻影之一，本单按建议①修第一把尺）。

**为什么不自动修**：修复需判断"这个控制字符原本该是哪个字母"（如 `\t` 处可能是 `task_*` 也可能是别的词），
属**作者意图知识**。本判据只**点名并给出上下文**（前后 30 字 + 该字符的转义名 + 被吃掉字母的推测），
把决定权留给作者/owner。这与本会话"不越权改他人文件"的纪律一致。

用法：
  python scripts/check_template_ctrl.py [--selftest] [--list]
退出码：0=全部干净 / 1=有裸控制字符 / 2=判据无法自证（FATAL）。
"""
import argparse
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL_DIR = os.path.join(ROOT, "templates")
# 放行：LF(0x0a) 换行、TAB(0x09) 制表符（Markdown 表格/缩进合法）
ALLOWED = {0x0a, 0x09}
# 控制字符 -> (转义名, 它"吃掉"的字母)。用于把红面说得可执行。
CTRL_INFO = {
    0x0d: ("\\r (CR)", "r"),
    0x08: ("\\b (BS)", "b"),
    0x0b: ("\\v (VT)", "v"),
    0x0c: ("\\f (FF)", "f"),
    0x1b: ("\\e (ESC)", "e"),
    0x07: ("\\a (BEL)", "a"),
    0x00: ("\\0 (NUL)", ""),
}


def md_files():
    out = []
    for dp, dn, fn in os.walk(TPL_DIR):
        for f in sorted(fn):
            if f.endswith(".md"):
                out.append(os.path.join(dp, f))
    return sorted(out)


def scan(path):
    """返回 (违例列表, 该文件字节数)。违例 = (行号, 列号, 字符码, 上下文)。
    容忍 CRLF：0x0d 后紧跟 0x0a 视为 autocrlf 注入的合法行尾，跳过；只判"裸"控制字符。"""
    raw = open(path, "rb").read()
    problems = []
    line = 1
    col = 0
    for i, b in enumerate(raw):
        if b == 0x0a:
            line += 1
            col = 0
            continue
        # CRLF：CR 后紧跟 LF => 合法行尾（Windows autocrlf checkout 注入），不判红
        if b == 0x0d and i + 1 < len(raw) and raw[i + 1] == 0x0a:
            continue
        col += 1
        if b in ALLOWED:
            continue
        if b < 0x20 or b == 0x7f:
            # 取上下文（按字节，前后各 24）；压平换行、截短，便于一行读完
            lo = max(0, i - 24)
            hi = min(len(raw), i + 24)
            ctx = raw[lo:hi].decode("utf-8", "replace").replace("\n", "⏎").replace("\r", "⏎")
            ctx = " ".join(ctx.split())
            problems.append((line, col, b, ctx))
    return problems, len(raw)


def emit_fatal(msg):
    """判据无法自证 ⇒ **真给 2**（写 stderr，由 `sys.exit(main())` 落成退出码）。

    BUG-369：改前这一处是 `raise SystemExit("FATAL …")`，而带字符串的 SystemExit 退出码是 1
    ⇒ 第 38 行自述的「2=判据无法自证（FATAL）」从来没有生效过，「判据空转」与「有裸控制字符」
    在退出码面上同色。这里刻意不用 `raise SystemExit(msg)`。
    """
    sys.stderr.write(msg + "\n")
    return 2


def selftest():
    """合成违例自证：判据必须先证明它会红，且干净输入不误红。"""
    import tempfile
    cells = []

    def cell(name, got, want):
        cells.append((name, bool(got) == bool(want), "got=%s want=%s" % (got, want)))

    d = tempfile.mkdtemp(prefix="tplctrl-")
    try:
        clean = os.path.join(d, "clean.md")
        open(clean, "wb").write("正常文本\n\t缩进\n".encode("utf-8"))
        p, n = scan(clean)
        cell("clean-no-false-positive", len(p) == 0 and n > 0, True)
        print("  ok  clean-no-false-positive（换行+制表符不误红，%d 字节）" % n)

        bad = os.path.join(d, "bad.md")
        open(bad, "wb").write("fy / \reject / \retry\n".encode("utf-8"))
        p, n = scan(bad)
        cell("cr-caught", len(p) == 2 and all(x[2] == 0x0d for x in p), True)
        print("  ok  cr-caught（2 个 CR 被抓：%s）" % p[0][3][:36])

        bad2 = os.path.join(d, "bad2.md")
        open(bad2, "wb").write("ask_plan_deep / xecute / erify".replace("a", "\t", 1).replace("x", "\x1b", 1).replace("e", "\x0b", 1).encode("utf-8"))
        p, n = scan(bad2)
        cell("multi-ctrl-caught", len(p) >= 2, True)
        print("  ok  multi-ctrl-caught（TAB 放行、ESC/VT 被抓：%d 个违例）" % len(p))

        cell("tab-allowed", all(x[2] != 0x09 for x in p), True)
        print("  ok  tab-allowed（TAB 在放行白名单里，不被判红）")

        # CRLF（Windows autocrlf checkout 注入的合法行尾）必须被容忍
        crlf = os.path.join(d, "crlf.md")
        open(crlf, "wb").write("正常\r\n文本\r\n".encode("utf-8"))
        p, n = scan(crlf)
        cell("crlf-tolerated", len(p) == 0, True)
        print("  ok  crlf-tolerated（CRLF 合法行尾被容忍，0 违例；%d 字节）" % n)

        # 裸 CR（后不接 LF）仍必须被点名（用两个裸 CR 考计数，单靠一个区分不出"被抓"和"被吞"）
        bare = os.path.join(d, "bare_cr.md")
        open(bare, "wb").write("eject\retry\reject".encode("utf-8"))
        p, n = scan(bare)
        cell("bare-cr-caught", len(p) >= 2 and all(x[2] == 0x0d for x in p), True)
        print("  ok  bare-cr-caught（裸 CR 仍被抓：%d 个违例）" % len(p))

        # 空扫描面自拒（由 main 判，这里考枚举函数）
        cell("md-enum-nonempty", len(md_files()) > 0, True)
        print("  ok  md-enum-nonempty（templates/ 枚举到 %d 份 .md）" % len(md_files()))

        # 出口码自证（BUG-369 建议①：改行为必须同时补一支「FATAL 的码真是 2」格）。
        # 子进程里把 TPL_DIR 指向空目录、跑真 main()，考的是**进程退出码**，不是函数返回值。
        import subprocess
        empty = os.path.join(d, "empty-templates")
        os.makedirs(empty, exist_ok=True)
        child = os.path.join(d, "child_fatal_rc.py")
        with open(child, "w", encoding="utf-8") as fh:
            fh.write("import importlib.util, sys\n"
                     "spec = importlib.util.spec_from_file_location('tc', %r)\n"
                     "m = importlib.util.module_from_spec(spec)\n"
                     "spec.loader.exec_module(m)\n"
                     "m.TPL_DIR = %r\n"
                     "sys.argv = ['check_template_ctrl.py']\n"
                     "sys.exit(m.main())\n"
                     % (os.path.abspath(__file__), empty))
        pr = subprocess.run((sys.executable, child), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        cell("fatal-exit-code-is-really-2", pr.returncode == 2, True)
        print("  ok  fatal-exit-code-is-really-2（子进程实测 rc=%s；改前那条 `raise SystemExit(串)` 只给 1，"
              "承诺面第 38 行的 2 从未生效）%s"
              % (pr.returncode,
                 "" if pr.returncode == 2 else "  ← stderr：%s"
                 % pr.stderr.decode("utf-8", "replace").strip()[-160:]))
    finally:
        import shutil
        shutil.rmtree(d, ignore_errors=True)

    badc = [(n, w) for n, ok, w in cells if not ok]
    if badc:
        print("SELFTEST FAIL：")
        for n, w in badc:
            print("  - %s：%s" % (n, w))
        return 1
    print("SELFTEST OK（%d 格：干净不误红 / CR 必红 / ESC+VT 必红 / TAB 放行 / CRLF 容忍 / 裸CR 必红 / "
          "枚举非空 / **判据空转的退出码真是 2**）" % len(cells))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--list", action="store_true", help="列出全部模板与控制字符统计")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    files = md_files()
    if not files:
        return emit_fatal("FATAL templates/ 下一份 .md 都没枚举到 —— 判据空转，拒绝报绿")

    total = 0
    hits = []
    for f in files:
        probs, n = scan(f)
        if probs:
            hits.append((f, probs, n))
            total += len(probs)

    if args.list:
        for f, probs, n in hits:
            rel = os.path.relpath(f, ROOT).replace("\\", "/")
            kinds = {}
            for _, _, b, _ in probs:
                kinds[CTRL_INFO.get(b, (hex(b), "?"))[0]] = kinds.get(CTRL_INFO.get(b, (hex(b), "?"))[0], 0) + 1
            print("  %-46s %s" % (rel, kinds))
        return 0 if not hits else 1

    if not hits:
        print("PASS 模板无裸控制字符：%d 份 templates/*.md 全部只含 LF/TAB" % len(files))
        return 0

    print("FAIL 模板含裸控制字符（%d 份 / %d 处）—— 提示词里的工具名可能已被吃掉首字母："
          % (len(hits), total))
    for f, probs, n in hits:
        rel = os.path.relpath(f, ROOT).replace("\\", "/")
        print("  - %s（%d 处）：" % (rel, len(probs)))
        for line, col, b, ctx in probs[:3]:
            name, letter = CTRL_INFO.get(b, (hex(b), "?"))
            hint = ("（上下文：…%s…；被吃掉的字母疑似 %r）" % (ctx[:40], letter)) if letter else ("（上下文：…%s…）" % ctx[:40])
            print("      L%d:%d %s %s" % (line, col, name, hint))
        if len(probs) > 3:
            print("      …（其余 %d 处同型）" % (len(probs) - 3))
    print()
    print("注：本判据**只点名不自动修** —— 修复需判断该控制字符原本该是哪个字母（属作者意图知识）。")
    print("    建议：对照 `python scripts/_tool_registry.py --list` 的真源工具名逐处核对后修。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
