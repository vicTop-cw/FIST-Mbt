#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_push_guard.py — 「直推 main 拦截当前是否生效」判据（BUG-389(2) 缺口③）。

**为什么需要它**：pre-push 拦截（scripts/check_direct_push.py）此前只有两格读数都答不上问题——
钩子装在共享 `$GIT_COMMON_DIR/hooks/`（本机手装、不在跟踪面），而"拦得住房不住房"没有任何
判据：换机/清理 ⇒ 手装壳退化成 fail-open，拦截静默失效，没人看见。本尺把三件事收成一条可跑
读数（全部**只读 + 本地子进程**，无网络 ⇒ CI 可跑）：

判据面（红）：
  H1 `.githooks/pre-push` 存在且被 git 跟踪（收编进跟踪面是 BUG-389(2) 的修法本体）
  H2 `scripts/check_direct_push.py` 存在且被 git 跟踪
  H3 `.githooks/pre-push` 文本引用 `check_direct_push.py`（壳与脑不得分家——分家即壳漂移）
  S1 stdin 语义矩阵（真起本地子进程喂 check_direct_push.py，逐格验 rc）：
     推 gitcode/main  → 必须 rc=1（拦住）
     推 github main   → 必须 rc=0（不是本拦截的对象）
     推 feature 分支  → 必须 rc=0（正常交付通道不许误伤）
     畸形行/空输入    → 必须 rc=0（按文档 fail-open，判据不许把它改成 fail-close）
  S2 壳语义同构：把钩子壳对 stdin 的处理方式（`"$PY" "$SCRIPT"` 直传、无中间吞管道）
     以文本锚点核对（`check_direct_push` 引用存在已由 H3 判，这里补「stdin 未被重定向丢弃」锚）

只报不判（环境态，永远不出红）：
  E1 `core.hooksPath`：== `.githooks` ⇒ `PASS(生效=跟踪壳)`；未设置但共享 hooks/ 有手装 pre-push
     ⇒ `WARN(手装在本机，非跟踪面——merge 后请跑 install_git_hooks.py --install)`；两者皆无 ⇒
     `WARN(本机未装，直推拦截不生效；跑 install_git_hooks.py --install)`。CI 上是干净 clone，
     E1 恒 WARN，不拦 PR——拦的是"跟踪面本身坏了"，本机装没装由安装器与读数负责。

退出码契约：0=跟踪面+语义面全绿（允许 E1 WARN）/ 1=H/S 违例（点名）/ 2=判据无法自证
（git 跑不动 / 子进程起不来 / 脚本缺失导致语义无从验证）。

用法：
  python scripts/check_push_guard.py            # 全量判据
  python scripts/check_push_guard.py --selftest # 合成仓自证可红可绿（temp 沙箱，零副作用）
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from git_env import isolated_git_env

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HOOK_REL = ".githooks/pre-push"
SCRIPT_REL = "scripts/check_direct_push.py"
HOOKS_PATH = ".githooks"


def git(*args, cwd=None):
    return subprocess.run(["git"] + list(args), cwd=cwd or ROOT,
                          capture_output=True, text=True,
                          encoding="utf-8", errors="replace", env=isolated_git_env())


def is_tracked(rel, cwd=None):
    return git("ls-files", "--error-unmatch", rel, cwd=cwd).returncode == 0


def py_exec():
    for cand in ("python3", "python"):
        p = shutil.which(cand)
        if p:
            return p
    return None


def run_stdin(script_path, stdin_text, py):
    r = subprocess.run([py, script_path], input=stdin_text, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=30)
    return r.returncode


# pre-push stdin 行形状：<local-ref> <local-oid> <remote-ref> <remote-oid> <remote-url>
LINE_GITCODE_MAIN = ("refs/heads/main aaaa refs/heads/main bbbb "
                     "gitcode.com:VictorTop/Fist-Mbt.git\n")
LINE_GITHUB_MAIN = ("refs/heads/main aaaa refs/heads/main bbbb "
                    "github.com:vicTop-cw/FIST-Mbt.git\n")
LINE_FEATURE = ("refs/heads/feat/x aaaa refs/heads/feat/x bbbb "
                "gitcode.com:VictorTop/Fist-Mbt.git\n")


def check(root):
    """对给定仓根跑 H/S/E 三面。返回 (rc, lines)。"""
    out = []
    problems = []
    hook = os.path.join(root, HOOK_REL)
    script = os.path.join(root, SCRIPT_REL)

    # H0 安装器即真源：pre-push 必须在 REQUIRED 里。
    # 为什么单列一格：安装器是钩子的唯一安装面；`REQUIRED` 一旦被改回只剩 pre-commit，
    # `--install` 就把 pre-push 当无关文件跳过 chmod/核对 ⇒ 跟踪壳存在而安装面不认（静默漂移）。
    il = os.path.join(root, "scripts", "install_git_hooks.py")
    if os.path.isfile(il):
        try:
            itext = open(il, encoding="utf-8", errors="replace").read()
            m = re.search(r"^REQUIRED\s*=\s*\((.*?)\)", itext, re.M)
            if not m or "pre-push" not in m.group(1):
                problems.append("H0 install_git_hooks.REQUIRED 未含 pre-push（安装器与钩子脱钩）")
        except OSError as e:
            problems.append("H0 安装器读不动：%s" % e)
    else:
        problems.append("H0 `scripts/install_git_hooks.py` 失踪（安装面真源不在位）")

    # H1 / H2 跟踪面
    if not os.path.isfile(hook):
        problems.append("H1 `.githooks/pre-push` 不在盘上（钩子真源失踪）")
    elif not is_tracked(HOOK_REL, cwd=root):
        problems.append("H1 `.githooks/pre-push` 存在但**未被 git 跟踪**（又回到本机手装态）")
    if not os.path.isfile(script):
        problems.append("H2 `scripts/check_direct_push.py` 不在盘上")
    elif not is_tracked(SCRIPT_REL, cwd=root):
        problems.append("H2 `scripts/check_direct_push.py` 未被 git 跟踪")

    # H3 壳引用脑（文本锚，壳与脑不得分家）
    if os.path.isfile(hook):
        try:
            body = open(hook, encoding="utf-8", errors="replace").read()
            if "check_direct_push.py" not in body:
                problems.append("H3 `.githooks/pre-push` 未引用 check_direct_push.py（壳漂移）")
            # S2 壳语义锚：脚本必须吃到 stdin（钩子由 git 以 stdin 喂 ref 行；
            # `| head`、重定向 /dev/null、或把 stdin 换成参数都会让拦截瞎掉）
            if re.search(r"<\s*/dev/null", body):
                problems.append("S2 钩子壳把 stdin 掐了（/dev/null）⇒ 拦截永远看不到 ref 行")
        except OSError as e:
            problems.append("H3 钩子读不动：%s" % e)

    # S1 语义矩阵（真子进程，逐格验 rc）
    py = py_exec()
    if py is None:
        return 2, ["FATAL 判据无法自证：找不到 python/python3，语义矩阵无从运行"]
    if not os.path.isfile(script):
        return 2, ["FATAL 判据无法自证：%s 不在盘上，S 面无法运行" % script]
    cells = [
        ("S1a 推 gitcode/main 必须拦", LINE_GITCODE_MAIN, 1),
        ("S1b 推 github main 不拦", LINE_GITHUB_MAIN, 0),
        ("S1c 推 feature 分支不拦", LINE_FEATURE, 0),
        ("S1d 空输入 fail-open", "", 0),
        ("S1e 畸形行 fail-open", "garbage-line\n", 0),
    ]
    try:
        for name, stdin_text, want in cells:
            got = run_stdin(script, stdin_text, py)
            if got != want:
                problems.append("%s：期望 rc=%d，实回 rc=%d" % (name, want, got))
    except Exception as e:
        return 2, ["FATAL 判据无法自证：子进程运行异常 %s" % e]

    # E1 本机安装态（只报不判）
    r = git("config", "--get", "core.hooksPath", cwd=root)
    val = (r.stdout or "").strip()
    if val.replace("\\", "/").rstrip("/") == HOOKS_PATH:
        out.append("E1 core.hooksPath=.githooks ⇒ 跟踪壳生效（PASS）")
    else:
        hp = git("rev-parse", "--git-path", "hooks/pre-push", cwd=root)
        path = (hp.stdout or "").strip()
        shared = path and os.path.isfile(os.path.join(root, path) if not os.path.isabs(path) else path)
        if val:
            out.append("E1 WARN core.hooksPath=%r 未指向 .githooks（本机安装态，不判红）" % val)
        elif shared:
            out.append("E1 WARN 本机在用共享目录手装 pre-push（非跟踪面）；merge 后请跑 "
                       "python scripts/install_git_hooks.py --install")
        else:
            out.append("E1 WARN 本机未装钩子 ⇒ 直推拦截不生效；跑 python scripts/install_git_hooks.py --install")

    lines = out + [("  - " + p) for p in problems]
    return (1 if problems else 0), lines


def _entry_probe() -> None:
    """入口面自证（R171 口径）：自检必须把入口纳入调用图。

    R158 交付 check_diff_scope.py 时 `--selftest` 全绿而**现状面一跑就崩**
    （clean 分支少传一个实参抛 TypeError，冒出来的 rc=1 和「有违例」一模一样）。
    自检只考纯函数、不碰入口，照不出「自检面与入口面脱钩」。本探测**零副作用**：
    只验证入口存在且可调用，不起真 git、不碰网络。
    """
    if not callable(main):
        raise SystemExit("入口 main 不可调用（自检面与入口面脱钩）")


def selftest():
    """合成仓自证：干净树全绿；H1/H2/H3/S1/S2 各造违例必须红；变异台证明断言咬人。"""
    _entry_probe()
    fails = []
    if git("--version").returncode != 0:
        print("SELFTEST BLOCKED：git 不可用，尺子无法自证")
        return 2
    py = py_exec()
    if py is None:
        print("SELFTEST BLOCKED：python 不可用")
        return 2

    def mk_tree():
        td = tempfile.mkdtemp(prefix="push-guard-st-")
        git("init", "-q", cwd=td)
        git("config", "user.email", "st@local", cwd=td)
        git("config", "user.name", "st", cwd=td)
        h = os.path.join(td, ".githooks")
        os.makedirs(h)
        s = os.path.join(td, "scripts")
        os.makedirs(s)
        shutil.copy(os.path.join(ROOT, HOOK_REL), os.path.join(h, "pre-push"))
        shutil.copy(os.path.join(ROOT, SCRIPT_REL), os.path.join(s, "check_direct_push.py"))
        shutil.copy(os.path.join(ROOT, "scripts", "install_git_hooks.py"),
                    os.path.join(s, "install_git_hooks.py"))
        git("add", "-A", cwd=td)
        git("commit", "-qm", "seed", cwd=td)
        return td

    def cleanup(td):
        shutil.rmtree(td, ignore_errors=True)

    try:
        # C1 干净合成树 ⇒ 跟踪面+语义面绿（E1 WARN 不出红）
        td = mk_tree()
        rc, lines = check(td)
        bad = [l for l in lines if l.strip().startswith("- H") or l.strip().startswith("- S")]
        if rc != 1 or bad:
            # 注意：合成树里 E1 可能 WARN，rc 必须 0；H/S 必须无违例
            if bad:
                fails.append("C1 干净合成树出现 H/S 违例：%s" % bad)
            if rc != 0:
                fails.append("C1 干净合成树 rc=%d（应为 0，E1 WARN 不判红）：%s" % (rc, lines))
        cleanup(td)

        # C2 删钩子 ⇒ H1 红
        td = mk_tree()
        os.remove(os.path.join(td, HOOK_REL))
        rc, lines = check(td)
        if not any("H1" in l for l in lines):
            fails.append("C2 钩子失踪没被 H1 抓到：%s" % lines)
        cleanup(td)

        # C3 钩子未跟踪 ⇒ H1 红（tracked 断言必须咬人）
        td = mk_tree()
        git("rm", "--cached", "-q", ".githooks/pre-push", cwd=td)
        rc, lines = check(td)
        if not any("未被 git 跟踪" in l for l in lines):
            fails.append("C3 钩子脱跟踪没被抓到：%s" % lines)
        cleanup(td)

        # C4 壳漂移（不引用脚本）⇒ H3 红
        td = mk_tree()
        open(os.path.join(td, HOOK_REL), "w", encoding="utf-8").write("#!/bin/sh\nexit 0\n")
        git("add", "-A", cwd=td)
        git("commit", "-qm", "drift", cwd=td)
        rc, lines = check(td)
        if not any("H3" in l for l in lines):
            fails.append("C4 壳脑分家没被 H3 抓到：%s" % lines)
        cleanup(td)

        # C4b 安装器 REQUIRED 摘掉 pre-push ⇒ H0 红（安装面与钩子脱钩的静默漂移）
        td = mk_tree()
        ip = os.path.join(td, "scripts", "install_git_hooks.py")
        it = open(ip, encoding="utf-8", errors="replace").read()
        it2 = it.replace('REQUIRED = ("pre-commit", "pre-push")', 'REQUIRED = ("pre-commit",)')
        if it2 == it:
            fails.append("C4b 变异台失效：安装器 REQUIRED 形状变了，同步本自检")
        else:
            open(ip, "w", encoding="utf-8").write(it2)
            rc, lines = check(td)
            if not any("H0" in l for l in lines):
                fails.append("C4b 安装器脱钩没被 H0 抓到：%s" % lines)
        cleanup(td)

        # C5 变异台：语义被改松（永不拦）⇒ S1a 必红
        td = mk_tree()
        sp = os.path.join(td, SCRIPT_REL)
        t = open(sp, encoding="utf-8", errors="replace").read()
        t2 = t.replace("return 1 if blocked else 0", "return 0")
        if t2 == t:
            fails.append("C5 变异台失效：找不到语义锚点（实现形状变了，同步本自检）")
        else:
            open(sp, "w", encoding="utf-8").write(t2)
            git("add", "-A", cwd=td)
            git("commit", "-qm", "loose", cwd=td)
            rc, lines = check(td)
            if not any("S1a" in l for l in lines):
                fails.append("C5 语义改松没被 S1a 抓到：%s" % lines)
        cleanup(td)

        # C6 变异台：语义改死（啥都拦）⇒ S1c 必红
        td = mk_tree()
        sp = os.path.join(td, SCRIPT_REL)
        t = open(sp, encoding="utf-8", errors="replace").read()
        t2 = t.replace("return 1 if blocked else 0", "return 1")
        if t2 == t:
            fails.append("C6 变异台失效：锚点未命中")
        else:
            open(sp, "w", encoding="utf-8").write(t2)
            rc, lines = check(td)
            if not any("S1b" in l or "S1c" in l for l in lines):
                fails.append("C6 误伤面没被抓到：%s" % lines)
        cleanup(td)
    except Exception as e:
        print("SELFTEST BLOCKED：沙箱异常 %s" % e)
        return 2

    if fails:
        print("SELFTEST FAIL：判据自身有问题")
        for f in fails:
            print("  - " + f)
        return 1
    print("SELFTEST OK 推送守卫判据可红可绿（钩子失踪/脱跟踪/壳漂移/语义改松/误伤 必红；"
          "干净合成树 不误红；E1 环境态只报不判）")
    return 0


def main():
    ap = argparse.ArgumentParser(description="直推拦截生效性判据（BUG-389(2)）")
    ap.add_argument("--selftest", action="store_true", help="合成仓自证")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    rc, lines = check(ROOT)
    for l in lines:
        print(l)
    if rc == 0:
        print("PASS 推送守卫：跟踪面（钩子+脚本+引用）在位，stdin 语义矩阵逐格命中；"
              "本机安装态见 E1（WARN 不拦 CI）")
    return rc


if __name__ == "__main__":
    sys.exit(main())
