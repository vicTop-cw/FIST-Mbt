#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/check_empty_scan_face.py —— 「空扫描面必须自拒出绿」的元判据（R63）。

## 为什么要有这把自己

判例-32 的同族，但比它更靠前一步：

> **判据自己的腐烂与对象的陈旧是两种结论。**

一个判据最危险的失效形态不是「报红报错」，而是**什么都没扫到却报绿**：
- 目录改名 / 路径拼错 / `--root` 指到别处 ⇒ 扫到 0 份；
- 于是「0 条违例」被读成「没问题」；
- 而它**看起来在跑**：有输出、有 PASS、rc=0。

本仓已经吃过这个形状：`check_deployment_freshness` 的前身「只比版本号」（判例-32）、
`check_sync_workflow_reports_failures` 的 S4「枚举面为空不许报绿」（R59 事故的同源）。

**⇒ 本尺的做法是「实证」而不是「读源码」**：拿一个**空目录**当 `--root` 喂给每一把
支持 `--root` 的判据，期待它**拒绝出绿**（rc≠0）。它若 rc=0，就是「空转出绿」的实证。

## 判据面

- 候选 = `scripts/check_*.py` 里**自己声明了 `--root`** 的那些（不支持 `--root` 的尺
  无法被本尺实证，**如实计入“无法判定”并点名**，不静默略过）。
- 对每个候选：`python <尺> --root <空目录>`
  - `rc != 0` ⇒ **合格**（拒绝出绿）
  - `rc == 0` ⇒ **违例**（空扫描面报绿）
  - 超时 / 起不来 ⇒ **无法判定**（点名，不算违例也不算合格——这是「尺子不给量」的那一档）

## 退出码

- `0` = 全部候选都拒绝出绿（且至少有 1 个候选）
- `1` = 存在「空转出绿」的违例（逐条点名）
- `2` = 判据无法自证（一个候选都没有 ⇒ 本尺自己不空转出绿）
- `4` = 尺子自己坏了（未捕获异常，绝不冒用 1）

## 变异对照（判例-29/30）

`--selftest` 在**临时目录**造两个合成尺：
- `bad_guard.py`：空目录也 `sys.exit(0)` ⇒ 本尺**必须报 1 条违例**（锁会咬）
- `good_guard.py`：空目录 `sys.exit(2)` ⇒ 本尺**必须 0 条违例**（不误伤）
另加一格：候选面为空 ⇒ 本尺自拒 rc=2（不空转出绿）。
"""
import argparse
import ast
import io
import os
import subprocess
import sys
import tempfile
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


ROOT = os.path.normpath(os.path.dirname(os.path.abspath(__file__)) + "/..")
SCRIPTS_DIR = os.path.join(ROOT, "scripts")
GLOB_PREFIX = "check_"
GLOB_SUFFIX = ".py"
CASE_TIMEOUT = 25
ROOT_FLAG = "--root"

# 汇总里最多点名几条（避免长列表淹没结论）
PRINT_CAP = 12


def _has_root_flag(path):
    """判据是否**真的支持** `--root`（AST 判定，不看文本；两种声明形状都认）。

    ⚠️ 踩过三次同类坑（判例-30 同族：匹配形状要锚在**真声明**上）：
      1) 文本包含 `"--root"` ⇒ 本尺把自己也算进候选（文档里到处提它）；
      2) 正则 `add_argument\\(...--root` 仍命中文档/正则源码里的字样，且漏写法不同的真声明；
      3) 只认 `add_argument("--root")` ⇒ **漏掉手动解析 argv 的两把尺**
         （`check_selftest_hermetic` 的 `if "--root" in argv`、`check_slave_task_list` 的 `elif a == "--root"`）
         ⇒ 那是**覆盖漏洞**（它们真支持 `--root`，却不在被审面里）。

    现在两种形状都认，且都是 AST 节点（注释/文档/字符串字面量不会误命中）：
      · `add_argument(\"--root\", ...)`            → ast.Call
      · `\"--root\" in argv` / `a == \"--root\"`      → ast.Compare
    """
    try:
        tree = ast.parse(io.open(path, encoding="utf-8", errors="replace").read())
    except (OSError, SyntaxError):
        return False
    for node in ast.walk(tree):
        # ① argparse 声明
        if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and node.func.attr == "add_argument" and node.args):
            a0 = node.args[0]
            if isinstance(a0, ast.Constant) and a0.value == ROOT_FLAG:
                return True
        # ② 手动 argv 解析（形如 `"--root" in argv` / `a == "--root"`）
        if isinstance(node, ast.Compare):
            for side in [node.left] + list(node.comparators):
                if isinstance(side, ast.Constant) and side.value == ROOT_FLAG:
                    return True
    return False

def candidates(scripts_dir=None):
    """返回支持 `--root` 的判据脚本绝对路径（排序）。"""
    d = scripts_dir or "."      # R97：不默认 ROOT/SCRIPTS_DIR（自检链不得触及真仓）
    out = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return []
    for n in names:
        if not (n.startswith(GLOB_PREFIX) and n.endswith(GLOB_SUFFIX)):
            continue
        p = os.path.join(d, n)
        if os.path.isfile(p) and _has_root_flag(p):
            out.append(p)
    return out


def probe_one(script, empty_dir, timeout=CASE_TIMEOUT, cwd=None):
    # R97：`cwd` 自检时传合成目录（原来无条件 ROOT ⇒ hermetic 记 G 档）。
    """跑一把尺，返回 ("ok"|"green"|"unknown", rc, 尾部读数)。"""
    try:
        r = subprocess.run([sys.executable, script, ROOT_FLAG, empty_dir],
                           capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace", cwd=cwd or os.path.dirname(script))
        rc = r.returncode
    except subprocess.TimeoutExpired:
        return "unknown", None, "超时 %ds" % timeout
    except OSError as e:  # 起不来（解释器/权限）
        return "unknown", None, "起不来：%s" % e
    txt = ((r.stdout or "") + (r.stderr or "")).strip().splitlines()
    tail = txt[-1][:100] if txt else ""
    if rc == 0:
        return "green", rc, tail
    return "ok", rc, tail


def judge(scripts_dir=None, empty_dir=None, timeout=CASE_TIMEOUT, cwd=None):
    """纯流程：返回 (verdicts, unknown, n_candidates)。verdicts = [(name, kind, rc, tail)]。"""
    cands = candidates(scripts_dir)
    if not cands:
        return [], [], 0
    own_tmp = None
    if empty_dir is None:
        own_tmp = tempfile.mkdtemp(prefix="empty-face-")
        empty_dir = own_tmp
    try:
        verdicts, unknown = [], []
        for p in cands:
            name = os.path.basename(p)
            kind, rc, tail = probe_one(p, empty_dir, timeout, cwd)
            if kind == "unknown":
                unknown.append((name, tail))
            elif kind == "green":
                verdicts.append((name, kind, rc, tail))
            # kind == "ok" 是合格，不入任何清单
        return verdicts, unknown, len(cands)
    finally:
        if own_tmp:
            import shutil
            shutil.rmtree(own_tmp, ignore_errors=True)


def run(argv=None):
    ap = argparse.ArgumentParser(
        description="空扫描面元判据：喂空目录，判据必须拒绝出绿")
    ap.add_argument("--selftest", action="store_true", help="自证（合成坏尺/好尺，判例-29/30）")
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()

    # R97：显式传真仓面（candidates 默认已改成 `.`，避免自检链触及真仓）
    verdicts, unknown, n = judge(scripts_dir=SCRIPTS_DIR, cwd=ROOT)
    if n == 0:
        print("FATAL 判据无法自证：没有一把 check_*.py 声明 `%s` ⇒ 本尺扫描面为空，拒绝出绿"
              % ROOT_FLAG)
        return 2
    print("扫描面：%d 把声明了 `%s` 的判据（空目录实证）" % (n, ROOT_FLAG))
    if unknown:
        print("  无法判定 %d 把（超时/起不来）—— 如实点名，不静默略过：" % len(unknown))
        for name, tail in unknown[:PRINT_CAP]:
            print("    ？%s：%s" % (name, tail))
    if verdicts:
        print("FAIL 空转出绿 %d 把（0 份扫到仍报 rc=0 ⇒ 「0 条违例」被读成「没问题」）："
              % len(verdicts))
        for name, _kind, rc, tail in verdicts[:PRINT_CAP]:
            print("  - %s（rc=%d）%s" % (name, rc, tail))
        print("处置：该尺在「扫到 0 份」时必须 rc=2（判据无法自证）或明确报错，不许报绿。")
        return 1
    print("PASS 空扫描面全部自拒出绿：%d 把判据喂空目录后都拒绝出绿（rc≠0）" % n)
    return 0


def selftest():
    """合成坏尺/好尺，证明本尺会咬、且不误伤（判例-29/30）。"""
    cells, fails = [], []

    def cell(name, ok):
        cells.append(name)
        if not ok:
            fails.append(name)

    tmp = tempfile.mkdtemp(prefix="empty-face-st-")
    scripts = os.path.join(tmp, "scripts")
    empty = os.path.join(tmp, "empty")
    os.makedirs(scripts)
    os.makedirs(empty)

    bad = (
        "import argparse, sys\n"
        "ap = argparse.ArgumentParser()\n"
        "ap.add_argument('--root', default='.')\n"
        "ap.parse_args()\n"
        "print('PASS 我什么都没扫到但我很快乐')\n"
        "sys.exit(0)\n"
    )
    good = (
        "import argparse, sys\n"
        "ap = argparse.ArgumentParser()\n"
        "ap.add_argument('--root', default='.')\n"
        "ap.parse_args()\n"
        "print('FATAL 扫描面为空，拒绝出绿')\n"
        "sys.exit(2)\n"
    )
    io.open(os.path.join(scripts, "check_bad_guard.py"), "w", encoding="utf-8").write(bad)
    io.open(os.path.join(scripts, "check_good_guard.py"), "w", encoding="utf-8").write(good)

    # 1) 坏尺必须被抓（变异对照：整个判据存在的理由）
    v, u, n = judge(scripts_dir=scripts, empty_dir=empty, timeout=20)
    cell("bad-guard-is-flagged", n == 2 and any(x[0] == "check_bad_guard.py" for x in v) and len(v) == 1)
    # 2) 好尺不许被误伤
    cell("good-guard-not-flagged", not any(x[0] == "check_good_guard.py" for x in v))
    # 3) 候选面为空 ⇒ 本尺自拒（不空转出绿）
    empty2 = tempfile.mkdtemp(prefix="empty-face-st2-")
    v2, _u2, n2 = judge(scripts_dir=empty2, empty_dir=empty, timeout=20)
    cell("empty-candidate-face-self-refuse", n2 == 0 and v2 == [])
    # 4) 起不来的尺记入 unknown（不静默略过，也不误判成违例）
    scripts2 = os.path.join(tmp, "scripts2")
    os.makedirs(scripts2)
    io.open(os.path.join(scripts2, "check_crash_guard.py"), "w", encoding="utf-8").write(
        "import argparse\nap = argparse.ArgumentParser()\nap.add_argument('--root', default='.')\n"
        "ap.parse_args()\nraise SystemExit(3)\n")
    v3, u3, n3 = judge(scripts_dir=scripts2, empty_dir=empty, timeout=20)
    cell("non-zero-counts-as-ok", n3 == 1 and v3 == [] and u3 == [])

    import shutil
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.rmtree(empty2, ignore_errors=True)

    print("SELFTEST %s（%d 格：%s）" % ("OK" if not fails else "FAIL", len(cells),
                                       " ".join(cells)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 1


def main(argv):
    return run(argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # 尺子自己坏了：4，绝不冒用 1
        print("FATAL 判据未捕获异常：%r" % (exc,))
        sys.exit(4)
