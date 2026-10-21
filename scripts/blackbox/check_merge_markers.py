#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/blackbox/check_merge_markers.py — 「未解决冲突标记被提交进跟踪面」硬门禁（活判据）。

**为什么要有它**：2026-10-21 沿 first-parent 实测——16:23 那波 cherry-pick 把带
`<<<<<<< / ======= / >>>>>>>` 的文件直接 commit 进了 master（check_plan_landing.py 标记
0→12→31 逐 commit 钉死），此后一直躺在跟踪面上（现 master 仍有 9 个文件带行首标记）。
后果分两种，都比红更糟：
  ① .py/.mbt 带标记 ⇒ 语法错误 ⇒ CI 当场崩，守卫族自己 SyntaxError 到连「我坏了」都说不出来；
  ② .md/.yml/.mbti 带标记 ⇒ 不报错，标记作为正文安静发布（徽章、文档、CI 步骤描述都被污染）。
两种形态此前没有任何判据覆盖：文档面守卫只看内容口径、编译门只看能不能跑，「跟踪面里存在冲突
标记」这件事无人看——正是 BUG-330/334/336 同族的「守卫族自身健壮性」缺口。

判据（只看**行首**精确的三元组，避免把正文里「提到」标记字面量误判成违例）：
  L1 某跟踪文件出现行首冲突标记 ⇒ 未解决冲突/半截污染（必红）。完整三元组之外，任何
     落单的一侧（只有 <<<<<<< 或只有 ======= 或只有 >>>>>>>）同样是污染。
  L0 扫描面为空（一个跟踪文件都没读到）⇒ 自拒 exit 2：缺样本＝没测，不是测过且对。
  L2 .py 跟踪文件标记虽已清但**解析不过**（`ast.parse` 抛 SyntaxError）⇒ 同样必红。
     这条是实测补的：「清标记」把三元组抹掉却留下半行残骸（2026-10-21 的
     check_plan_landing.py：标记 0、SyntaxError@253），只查标记会把它判成干净——
     守卫看不到自己放过的正是它要防的那类坏。非 .py（.md/.yml/.mbti/.mbt）不做解析判定，
     由各语言自己的编译门管。

用法：
    python scripts/blackbox/check_merge_markers.py             # 扫当前仓库跟踪面
    python scripts/blackbox/check_merge_markers.py --selftest   # 只跑合成对照，不碰真仓库

退出码：0 = PASS（跟踪面无未解决标记）；1 = 有违例（逐条点名文件）；
        2 = 判据无法自证（扫描面空/读不到文件/不在 git 仓库）。
`--selftest` 的格子清单**从已执行格子反解**，不手写计数。
"""
import ast
import re
import subprocess
import sys
from pathlib import Path

# BUG-58：守卫的「红」必须是判据红。Windows 默认 GBK 控制台下，中文结论里的特殊字符
# 会让 print 直接 UnicodeEncodeError——拿到 traceback 而不是 verdict，本地就等于「守卫不可信」。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent.parent

# 行首精确的三种冲突标记（按 git 原样：顶格）。
RE_OURS = re.compile(r"^<{7}(?: |$)")
RE_SEP = re.compile(r"^={7}$")
RE_THEIRS = re.compile(r"^>{7}(?: |$)")


def tracked_files(root):
    """git 跟踪面文件名清单（用 git 而不是走磁盘 glob，保证与 CI checkout 看到的面一致）。
    不在仓库 / git 不可用 ⇒ 返回 None（调用方自拒，绝不报绿）。"""
    r = subprocess.run(["git", "-C", str(root), "ls-files", "-z"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        return None
    return [f for f in r.stdout.split("\0") if f.strip()]


def marker_problems(text):
    """纯判定：一个文件正文里的冲突标记问题（返回标签列表，空 == 无标记）。"""
    ours = sep = theirs = 0
    for line in text.split("\n"):
        if RE_OURS.match(line):
            ours += 1
        elif RE_SEP.match(line):
            sep += 1
        elif RE_THEIRS.match(line):
            theirs += 1
    if not (ours or sep or theirs):
        return []
    if ours and sep and theirs:
        kind = "未解决冲突（完整三元组）"
    else:
        # 完整三元组之外的任何形状（落单 =======、只有一侧箭头）同样是污染。
        kind = "半截标记"
    return ["%s：<<<<<<< x%d / ======= x%d / >>>>>>> x%d" % (kind, ours, sep, theirs)]


def scan(root, files):
    """返回 (读到并扫描的文件数, 违例清单)。读不到的文件单独记账（不静默跳过）。"""
    problems = []
    unreadable = []
    scanned = 0
    for f in files:
        p = root / f
        if not p.is_file():
            unreadable.append(f)
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            unreadable.append(f)
            continue
        scanned += 1
        for why in marker_problems(text):
            problems.append("L1 %s ⇒ %s（冲突标记被提交进跟踪面）" % (f, why))
        if f.endswith(".py"):
            # L2：标记清干净 ≠ 文件能用。半行残骸照样 SyntaxError。
            try:
                ast.parse(text)
            except SyntaxError as e:
                problems.append("L2 %s ⇒ 无冲突标记但解析失败 SyntaxError@%s：%s"
                                "（「清标记」留下的残骸，只查标记会放它过去）"
                                % (f, e.lineno, (e.msg or "")[:40]))
    if unreadable:
        problems.append("L1 有 %d 个跟踪文件读不到 ⇒ 判据输入面不完整：%s"
                        % (len(unreadable), ", ".join(sorted(unreadable)[:5])))
    return scanned, problems


def selftest():
    """判据必须先证明自己会红：合成违例必红 + 干净不误红 + 空扫描自拒。
    用临时 git 仓库当注入面（真跑 git ls-files，不 mock 跟踪面），格子从已执行对照反解。"""
    import tempfile

    executed = []
    fails = []

    def new_repo(fixture):
        d = Path(tempfile.mkdtemp(prefix="cmk-"))
        subprocess.run(["git", "init", "-q"], cwd=d, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.email", "t@t"], cwd=d, capture_output=True, text=True)
        subprocess.run(["git", "config", "user.name", "t"], cwd=d, capture_output=True, text=True)
        for rel, body in fixture.items():
            fp = d / rel
            fp.parent.mkdir(parents=True, exist_ok=True)
            fp.write_text(body, encoding="utf-8")
        if fixture:
            subprocess.run(["git", "add", "-A"], cwd=d, capture_output=True, text=True)
            subprocess.run(["git", "commit", "-qm", "fixture"], cwd=d, capture_output=True, text=True)
        return d

    CONFLICT = ("def f():\n"
                "<<<<<<< HEAD\n"
                "    return 1\n"
                "=======\n"
                "    return 2\n"
                ">>>>>>> abc1234 (some commit)\n")
    CLEAN_PY = "def f():\n    return 1\n"
    # 正文「提到」标记字面量（非行首三元组）⇒ 不得判违例（防把散文/文档示例读成污染）。
    MENTION = "# 本文解释 <<<<<<< 与 >>>>>>> 这类标记的含义（行内提及，非行首）\n"

    # C1 干净面 ⇒ 0 违例
    d = new_repo({"a.py": CLEAN_PY, "b.md": MENTION})
    n, probs = scan(d, tracked_files(d) or [])
    executed.append("C1 干净不误红")
    if probs:
        fails.append("C1 干净面被误判：%s" % (probs[:2],))
    if n == 0:
        fails.append("C1 一个文件都没读到（跟踪面反解失效）")

    # C2 真冲突 ⇒ 必红且点名文件、不牵连干净文件
    d = new_repo({"pkg/bad.py": CONFLICT, "ok.py": CLEAN_PY})
    n, probs = scan(d, tracked_files(d) or [])
    executed.append("C2 未解决冲突必红")
    if not any("pkg/bad.py" in p and p.startswith("L1") for p in probs):
        fails.append("C2 真冲突没被抓到/没点名：%s" % (probs[:2],))
    if any("ok.py" in p for p in probs):
        fails.append("C2 牵连误判：干净文件也被点名")

    # C3 半截标记（落单 ======= / 只有 >>>>>>>）⇒ 同样必红
    executed.append("C3 半截标记必红")
    d = new_repo({"orphan.md": "text\n=======\nmore\n"})
    n, probs = scan(d, tracked_files(d) or [])
    if not probs:
        fails.append("C3 落单 ======= 未被判为污染")
    d = new_repo({"tail.py": "x\n>>>>>>> deadbeef (x)\n"})
    n, probs = scan(d, tracked_files(d) or [])
    if not probs:
        fails.append("C3 落单 >>>>>>> 未被判为污染")

    # C4 行内提及不误红（单点复证，防正则放宽）
    d = new_repo({"note.md": MENTION})
    n, probs = scan(d, tracked_files(d) or [])
    executed.append("C4 提及字面量不误红")
    if probs:
        fails.append("C4 行内提及被判违例（正则太宽）：%s" % (probs[:1],))

    # C5b L2：标记已被抹平、但 .py 解析不过（真实事故形状）⇒ 必红且点名
    dead_py = "def f():\n    return 1\n    end if x > 0。\n"
    d = new_repo({"dead.py": dead_py, "fine.py": CLEAN_PY})
    n, probs = scan(d, tracked_files(d) or [])
    executed.append("C6 无标记但解析死必红")
    if not any(p.startswith("L2") and "dead.py" in p for p in probs):
        fails.append("C6 解析死的 .py 未被抓到（守卫只认标记 = 放过残骸）：%s" % (probs[:2],))
    if any("fine.py" in p for p in probs):
        fails.append("C6 误伤：能解析的 fine.py 也被 L2 点名")
    # 反向：非 .py 不套 L2（避免把 .md 里的中文残骸误判成语法错）
    d = new_repo({"note.md": "随便一段中文。\n"})
    n, probs = scan(d, tracked_files(d) or [])
    if any(p.startswith("L2") for p in probs):
        fails.append("C6 越界：L2 不该管非 .py 文件")

    # C5 空跟踪面 ⇒ main 自拒 exit 2，绝不报绿
    executed.append("C5 空扫描必自拒")
    empty_repo = new_repo({})
    rc = main(empty_repo)
    if rc != 2:
        fails.append("C5 空跟踪面 main 返回 %s（应为 2 自拒，不许冒用 0）" % rc)

    print("SELFTEST %s（干净不误红 + 变异必红 + 空扫描自拒；格子从已执行对照反解：%s）"
          % ("OK" if not fails else "FAIL", " / ".join(executed)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 2


def main(root=ROOT):
    """root 供 --selftest 注入合成仓库。返回退出码（0/1/2）。"""
    files = tracked_files(root)
    if files is None:
        print("FATAL 判据输入面退化：`git ls-files` 不可用（不在 git 仓库？）⇒ 拒绝出结论")
        return 2
    if not files:
        print("FATAL 判据输入面退化：跟踪面为空 ⇒ 缺样本＝没测，绝不报绿")
        return 2
    scanned, problems = scan(root, files)
    if scanned == 0:
        print("FATAL 判据输入面退化：%d 个跟踪文件全部读不到 ⇒ 拒绝出结论" % len(files))
        return 2
    if problems:
        for p in problems:
            print("VIOLATION " + p)
        print("FAIL 跟踪面存在冲突标记（%d 处）——必须逐条解冲突后重新提交，"
              "不许「取一边」留下标记；.py/.mbt 带标记会直接崩编译。" % len(problems))
        return 1
    print("PASS 跟踪面无未解决冲突标记（扫描 %d 个 git 跟踪文件）" % scanned)
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    if len(sys.argv) > 1:
        raise SystemExit("用法: python scripts/blackbox/check_merge_markers.py [--selftest]")
    sys.exit(main())
