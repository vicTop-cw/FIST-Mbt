#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_sync_workflow_reports_failures.py — 「同步 workflow 失败读数」守卫（判例-9 的机械化）。

## 为什么要有它

`.github/workflows/sync-from-gitcode.yml` 每 6 小时把 GitCode 的**全部**分支 force 推到 GitHub。
旧写法是：

    git push --force gh "$b:$b" 2>&1 || echo "push failed on $b"

`|| echo` 让 rc 恒 0 ⇒ 每一支失败都只是**一行日志**：workflow 依旧 SUCCESS，
没人能从 Actions 页面上看出「102 支没推上去」。实测形态：`origin` 51 支 vs `gitcode` 153 支、
差 **102 支**，而 workflow **从没红过**。这就是判例-9——**「workflow 存在」≠「workflow 生效」**。

## 判据（任一条不满足即红）

  S1 **禁静默吞**：workflow 的 `run:` 正文里，任何 `git push` 不得出现在
     `|| echo` / `|| true` / `|| :` 这类「失败即归零」的形状里（这是缺陷本体）。
  S2 **聚合读数在场**：正文必须真的 `echo` 出 `OK=` 与 `FAIL=` 形态的聚合行（`:;` 分号形状
     `OK=0; FAIL=0` 初始化**不算**——初始化在场而排印缺席，正是「看起来有计数其实没有读数」）。
  S3 **失败点名在场**：必须有 `::warning::failed branches:` 形态的点名行。
  S4 **枚举面空不报绿**：正文必须显式处理「一个本地分支都没读到」的分支
     （否则「0 支 = 0 失败」会被读成健康读数）。
  S5 **不许 pipefail 陷阱**：`git push ... 2>/dev/null` 与 `pipefail` 同时出现时，`$( ... )` 里的
     尾部 grep 会吃掉 push 的 rc ⇒ 失败恒读成成功。两件同时在场即红（那正是本改正要防的假绿）。

**不判面（刻意的）**：步骤顺序、`on:` / `permissions:`（owner 面）、变量命名风格、
`master` 单独分支那一段的文案——它们不是「失败可见性」的承重点。

## 为什么自带模拟跑手

判据只能证明「YAML 里长着这行字」；「这行字真跑起来会不会给出 OK/FAIL」得另有一段**真跑**。
所以本脚本的 `--selftest` 会把 `sync-from-gitcode.simulate.sh`（同期落仓，从 workflow 原样
抽段 + 假 bare 远端真跑）也拉起来，并要求它报 `SIMULATE OK`。两把合起来才叫「读数可读」被证明：
判据证明**形状**在场、模拟证明**行为**成立。

## 退出码

0 = PASS（5 条判据全过；`--selftest` 时模拟跑手也 PASS）
1 = 违例（逐条点名：哪条、哪一行、原文什么）
2 = 判据无法自证（workflow 读不到 / 抽不出 run 正文 / 扫描面为空 —— 空扫描绝不报绿）
4 = 尺子自己坏了（未捕获异常，绝不冒用 1 那一档）

用法：
    python scripts/check_sync_workflow_reports_failures.py            # 判真 workflow
    python scripts/check_sync_workflow_reports_failures.py --selftest # 合成违例自证 + 真跑模拟
"""
import argparse
import io
import os
import re
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WF = os.path.join(ROOT, ".github", "workflows", "sync-from-gitcode.yml")
SIMULATE = os.path.join(ROOT, ".github", "workflows", "sync-from-gitcode.simulate.sh")

# 「失败即归零」的三种写法。`|| :` 与 `|| true` 等价（`: ` 是恒成功内建）。
RE_SWALLOW = re.compile(r"\|\|\s*(?:echo\b|true\b|:\s*(?:$|[;\n])|exit\s+0\b)")
RE_PUSH = re.compile(r"\bgit\s+push\b")
RE_INIT_ONLY = re.compile(r"^\s*(?:OK|FAIL)\s*=\s*0\s*;\s*(?:OK|FAIL)\s*=\s*0", re.M)
RE_AGG_ECHO = re.compile(r"echo\b[^\n]*\bOK=\$?\{?\w+\}?[^\n]*\bFAIL=")
RE_NAME_WARN = re.compile(r"echo\b[^\n]*::warning::failed branches:", re.M)
RE_EMPTY_GUARD = re.compile(r"if\s+\[\s*-z\s+\"?\$?\{?\w+\}?\"?\s+\]", re.M)
RE_PIPEFAIL = re.compile(r"set\s+-o\s+pipefail")
RE_DEVNULL = re.compile(r"git\s+push\b[^\n]*2>\s*/dev/null")
# 真陷阱形状：命令替换里带 push 的 stderr 重定向，后面还接了管道（尾部命令的 rc 顶替 push 的）
RE_TRAP = re.compile(r"\$\([^)]*git\s+push\b[^)]*2>\s*/dev/null[^)]*\|")


def read_text(path):
    with io.open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def run_bodies(text):
    """从 workflow 正文抽出所有 `run: |` 块的正文（去掉 2 空格 yaml 缩进后的纯 bash）。"""
    bodies, cur, on = [], [], False
    for ln in text.splitlines():
        if not on:
            if ln.strip() in ("run: |", "run: |-"):
                on = True
                cur = []
            continue
        if ln.strip() == "":
            cur.append("")
            continue
        stripped = ln.strip()
        if ln.strip() and not ln.startswith(" "):
            on = False
            bodies.append("\n".join(cur))
            continue
        cur.append(ln)
    if on:
        bodies.append("\n".join(cur))
    # 统一去掉每块的最小公共缩进
    out = []
    for b in bodies:
        lines = b.splitlines()
        ind = [len(x) - len(x.lstrip(" ")) for x in lines if x.strip()]
        cut = min(ind) if ind else 0
        out.append("\n".join(x[cut:] if len(x) >= cut else x for x in lines))
    return out


def strip_comments(body):
    """只留代码面：剔除整行注释（`#` 起头）与行尾注释前的说明。
    BUG-132/R9 的口径：**自家注释喂回针**是最常见的假红来源——本 workflow 的改正注释里
    就原样写着旧写法 `git push ... || echo` 作反例，不剔注释等于让说明文字把自己判红。"""
    out = []
    for ln in body.splitlines():
        if ln.lstrip().startswith("#"):
            out.append("")
            continue
        # 行尾注释：只在 `#` 前有空白时切（避免切坏 URL 里的 `#` 与 ${#x} 之外的正常用法）
        cut = None
        for i, ch in enumerate(ln):
            if ch == "#" and i > 0 and ln[i - 1] in " 	":
                cut = i
                break
        out.append(ln if cut is None else ln[:cut].rstrip())
    return "\n".join(out)


def judge(text):
    """纯函数：给 workflow 正文一份裁决。返回 (violations, metrics)。只看代码面（剔注释）。"""
    v, m = [], {}
    bodies = [strip_comments(b) for b in run_bodies(text)]
    bodies = [b for b in bodies if b.strip()]
    m["n_bodies"] = len(bodies)
    if not bodies:
        return v, m  # 由调用方判 2（扫描面为空）

    pushed = 0
    # S1 禁静默吞：逐行看「同一行里既有 git push 又有 || echo/true/:」
    for bi, b in enumerate(bodies):
        for li, ln in enumerate(b.splitlines(), 1):
            if RE_PUSH.search(ln):
                pushed += 1
                if RE_SWALLOW.search(ln):
                    v.append(("S1", bi + 1, li, "静默吞失败（rc 归零）", ln.strip()))
    m["n_push_lines"] = pushed

    whole = "\n".join(bodies)

    # S2 聚合读数：必须有 echo 出 OK=… FAIL=…（排除「初始化 `OK=0; FAIL=0`」这种不算读数的形状）
    agg = 0
    for bi, b in enumerate(bodies):
        for li, ln in enumerate(b.splitlines(), 1):
            if RE_AGG_ECHO.search(ln) and not RE_INIT_ONLY.search(ln):
                agg += 1
    if agg == 0:
        v.append(("S2", 0, 0, "缺聚合读数的 echo（要求 OK=… 与 FAIL=… 同现于一行 echo）", ""))
    m["n_agg_echo"] = agg

    # S3 失败点名
    if not RE_NAME_WARN.search(whole):
        v.append(("S3", 0, 0, "缺 `::warning::failed branches:` 形态的失败点名行", ""))

    # S4 枚举面空守卫
    if not RE_EMPTY_GUARD.search(whole):
        v.append(("S4", 0, 0, "缺「枚举面为空」守卫（0 支会被读成健康读数）", ""))

    # S5 pipefail × 2>/dev/null 陷阱：**同一行**里 `$( … git push … 2>/dev/null | grep … )`
    # 同时开了 pipefail 才吃 rc。分处不同行不构成陷阱（原版「全文同现即红」是误报，
    # 本 workflow 注释里解释「为什么不用 pipefail」就会让它自己触电）。
    if RE_PIPEFAIL.search(whole):
        for bi, b in enumerate(bodies):
            for li, ln in enumerate(b.splitlines(), 1):
                if RE_TRAP.search(ln):
                    v.append(("S5", bi + 1, li,
                              "pipefail 下 `$( … git push … 2>/dev/null | … )` 的尾部命令会吃掉 push 的 rc",
                              ln.strip()))
    return v, m


def report(path, violations, metrics):
    print("判据面：%s" % os.path.relpath(path, ROOT).replace("\\", "/"))
    print("  读数：run 块 %d / push 行 %d / 聚合 echo %d"
          % (metrics.get("n_bodies", 0), metrics.get("n_push_lines", 0), metrics.get("n_agg_echo", 0)))
    if not violations:
        print("PASS 同步 workflow 的失败读数齐备（S1 禁静默吞 / S2 聚合 / S3 点名 / S4 空守卫 / S5 pipefail）")
        return 0
    for code, bi, li, why, line in violations:
        loc = "（run 块 %d 第 %d 行）" % (bi, li) if li else ""
        print("VIOLATION [%s] %s%s" % (code, why, loc))
        if line:
            print("         原文：%s" % line)
    print("FAIL 共 %d 条违例" % len(violations))
    return 1


def run_simulate():
    """真跑模拟跑手（从 workflow 原样抽段 + 假 bare 远端）。返回 (ok, tail)。"""
    if not os.path.isfile(SIMULATE):
        return False, "模拟跑手不在：%s" % os.path.relpath(SIMULATE, ROOT)
    p = subprocess.run(["bash", SIMULATE], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", cwd=ROOT)
    out = (p.stdout or "") + (p.stderr or "")
    tail = "\n".join(out.strip().splitlines()[-6:])
    return (p.returncode == 0 and "SIMULATE OK" in out), tail


def selftest():
    """尺子先证明自己会红：合成 4 个形状（旧写法 / 只初始化不排印 / 缺点名 / pipefail 陷阱）+ 1 个干净面。"""
    clean = (
        "jobs:\n  s:\n    steps:\n      - name: x\n        run: |\n"
        "          OK=0; FAIL=0; FAILED_LIST=\"\"\n"
        "          B=$(git for-each-ref refs/heads)\n"
        "          if [ -z \"$B\" ]; then\n            echo \"::warning::empty\"\n          fi\n"
        "          for b in $B; do\n"
        "            if git push --force gh \"$b:$b\" 2>/dev/null; then\n"
        "              OK=$((OK+1))\n            else\n              FAIL=$((FAIL+1))\n            fi\n"
        "          done\n"
        "          echo \"::notice::branch sync: OK=$OK FAIL=$FAIL\"\n"
        "          echo \"::warning::failed branches: $FAILED_LIST\"\n"
    )
    old_swallow = (
        "jobs:\n  s:\n    steps:\n      - name: x\n        run: |\n"
        "          for b in $(git for-each-ref refs/heads); do\n"
        "            git push --force gh \"$b:$b\" 2>&1 || echo \"push failed on $b\"\n"
        "          done\n"
        "          git push --force gh \"master:master\" 2>&1 || echo \"push failed on default branch\"\n"
        "          git push gh --tags 2>&1 || true\n"
    )
    only_init = clean.replace('          echo "::notice::branch sync: OK=$OK FAIL=$FAIL"\n', "")
    no_name = clean.replace('          echo "::warning::failed branches: $FAILED_LIST"\n', "")
    # S5 的合成违例必须是**真陷阱**形状（不是「全文同现」）：pipefail 下
    # 把 push 塞进 $( … 2>/dev/null | grep … )，尾部 grep 的 rc 会顶替 push 的 rc。
    pipefail_trap = clean.replace(
        "            if git push --force gh \"$b:$b\" 2>/dev/null; then",
        "            if out=$(git push --force gh \"$b:$b\" 2>/dev/null | grep -c new); then",
    ).replace("          OK=0; FAIL=0", "          set -o pipefail\n          OK=0; FAIL=0")
    no_guard = "\n".join(x for x in clean.splitlines() if "-z" not in x and "empty" not in x
                         and "\"::warning::empty\"" not in x and "fi" not in x
                         or "for b in" in x or "if git push" in x) + "\n"

    cells, fails = [], []

    def cell(name, text, want_rc):
        v, m = judge(text)
        rc = 0 if not v else 1
        cells.append(name)
        if m.get("n_bodies", 0) == 0 and want_rc != 2:
            fails.append("%s: 抽出 0 个 run 块（夹具坏了）" % name)
            return
        if rc != want_rc:
            fails.append("%s: got rc=%d (%s) want %d"
                         % (name, rc, ",".join(x[0] for x in v) or "无违例", want_rc))

    cell("S0-clean", clean, 0)
    cell("S1-old-swallow", old_swallow, 1)
    cell("S2-only-init", only_init, 1)
    cell("S3-no-name", no_name, 1)
    cell("S5-pipefail", pipefail_trap, 1)
    # S4：把「空枚举守卫」摘掉必须红
    v4, _ = judge(no_guard.replace("if [ -z \"$B\" ]; then", "# guard removed"))
    cells.append("S4-no-guard")
    if not any(x[0] == "S4" for x in v4):
        fails.append("S4-no-guard: 摘掉空枚举守卫后没有 S4 违例")

    # S1 的形状必须逐条点到：两条 || echo 都该被点
    v1, _ = judge(old_swallow)
    n_s1 = sum(1 for x in v1 if x[0] == "S1")
    cells.append("S1-count-3")
    if n_s1 != 3:
        fails.append("S1-count-3: 期望 3 条 S1 命中，实得 %d" % n_s1)

    # 真跑：模拟跑手
    sim_ok, sim_tail = run_simulate()
    cells.append("SIM-run")
    if not sim_ok:
        fails.append("SIM-run: 模拟跑手未 PASS\n%s" % sim_tail)

    print("SELFTEST %s (%d cells: %s)" % ("OK" if not fails else "FAIL", len(cells), " / ".join(cells)))
    print("  SIM 尾部：\n    " + sim_tail.replace("\n", "\n    "))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--selftest", action="store_true", help="合成违例自证 + 真跑模拟跑手")
    args = ap.parse_args(argv)
    try:
        if args.selftest:
            return selftest()
        if not os.path.isfile(WF):
            print("FATAL 读不到 %s ⇒ 判据无法自证" % os.path.relpath(WF, ROOT))
            return 2
        text = read_text(WF)
        v, m = judge(text)
        if m.get("n_bodies", 0) == 0:
            print("FATAL 抽不出任何 run 正文（扫描面为空）⇒ 判据无法自证，绝不报绿")
            return 2
        return report(WF, v, m)
    except Exception as e:  # 尺子自己坏了：绝不冒用 1 那一档
        print("RULER-BROKEN %r" % (e,))
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
