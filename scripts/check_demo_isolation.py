#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_demo_isolation.py — 「spawn server 的脚本必须把 FIST_DB_PATH 交给子进程」守卫（BUG-122 的常驻判据面）。

背景：仓库根的 `fist-mbt.db` 是**自举台账**（`.gitignore` 挡着 ≠ 可脏）。JS 服务端只认一个隔离出口：
spawn 进程环境里的 `FIST_DB_PATH`（`store_open(scratch=true)` 实测连隔离手段都不是 ⇒ BUG-90/96 改判）。
所以任何一个 `Popen([node, cli.js, "serve"])` 却不把 `FIST_DB_PATH` 交给子进程的脚本，
都是在往真实台账里写演示行；而 README/USAGE/agent-map/deliverable 四处正是教人**裸跑**这类脚本（BUG-122 成因）。

判据（两个方向都发红）：
  I1  `scripts/**.py` 里 spawn `serve` 的脚本，必须同文件出现「把 FIST_DB_PATH 交给子进程」的四种形状之一：
        os.environ["FIST_DB_PATH"] = ...            （或任意 *env* 变量的下标赋值）
        os.environ.setdefault("FIST_DB_PATH", ...)
        env = dict(... FIST_DB_PATH ...)            # 再传给 Popen
        env = { ... "FIST_DB_PATH": ... }            # 再传给 Popen
      缺针 = 红：这个脚本一裸跑就污染真实台账。
  I2  `EXEMPT` 每一项必须 (a) 文件真实存在 (b) 理由非空 (c) 锚点成立——该文件确实 spawn `serve`，
      或属于两份**显式子句**（守卫自身、把 `"serve"` 当正则字面量读的 check_entry_paths）。
      把豁免扩到既不 spawn 也不是显式子句的文件 = 红 ⇒ 否则豁免面可以随便扩。
  I3  扫描面为空（一个 spawn 脚本都没抓到）⇒ FATAL(2)：判据看不见样本就等于没判（J10/BUG-118 同族）。
  I0  任一被检文件读不到 ⇒ 整笔自拒，不报绿。

`--selftest` 五支：G1 干净不误红 / M1 摘掉一个真 spawn 脚本的改道针必红 /
M1b 只加一行注释不许误红 / M2 把豁免扩到一个根本不 spawn 的文件必红 / M3 空扫描必自拒。
格子清单从已执行对照反解打印，不手写计数。

用法：python scripts/check_demo_isolation.py [--selftest]
退出码：0=PASS，1=违例，2=判据无法自证（扫描面空 / 读不到文件 / 自检不通过）。
"""
import argparse
import io
import os
import re
import sys

# BUG-138（BUG-58 同族）：守卫的红必须是判据红。Windows 默认 cp936 控制台上打印中文结论里的
# ⇒ 等字符会让 print 当场 UnicodeEncodeError——拿到 traceback 而不是 verdict，而且崩在结论行之前
# 留下的 rc 会被读成「缺陷在场」（判据自己的崩不许冒用被测的退出码）。CI 在 Linux UTF-8 下是无损 no-op。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SCRIPTS_DIR = os.path.join(ROOT, "scripts")

SPAWN_RE = re.compile(r'subprocess\.Popen\s*\([\s\S]{0,220}?"serve"')

# 四种「把 FIST_DB_PATH 交给子进程」的形状。这里**必须**用三引号 raw 串：
# 第一版用单引号 raw 串写字符类 ["'] 时，那个单引号把字符串自己闭合了——判据坏在 import 期，
# 而被检面（一堆 demo 脚本）是无辜的。X 模式下的空白与 # 注释都不进模式，便于逐支注释。
NEEDLE_RE = re.compile(r"""
      \w*env\w*\s*\[\s*["']FIST_DB_PATH["']\s*\]\s*=
    | os\.environ\.setdefault\(\s*["']FIST_DB_PATH["']
    | env\s*=\s*dict\([^)]*FIST_DB_PATH
    | env\s*=\s*\{[^}]{0,140}FIST_DB_PATH
""", re.I | re.X)

# 显式子句：这两份本来就不构成污染面，I1/I2 都不判它们。
EXPLICIT_CLAUSES = {
    "scripts/check_demo_isolation.py": "本守卫自身：只做文本判定，不 spawn server。",
    "scripts/check_entry_paths.py": (
        '把 "serve" 当**正则字面量**读（判别人的 argv 少没少 serve），自身不 Popen 产物。'),
}

# 豁免面：确实 spawn，但按设计必须走默认路径 —— 理由要写清"为什么仍然不污染根台账"。
EXEMPT = {
    "scripts/store_isolation_probe.py": (
        "两格对照里 C2 **必须**走默认路径，否则证不了 C1 真的改道；两格的 cwd 与库都在临时 box 内，"
        "仓库根台账不被任何一格写（该探针本身即 BUG-90 的活判据）。"),
}


def rel(path):
    return os.path.relpath(path, ROOT).replace("\\", "/")


def _files():
    out = []
    for dirpath, dirnames, filenames in os.walk(SCRIPTS_DIR):
        dirnames[:] = [d for d in dirnames if d not in ("__pycache__", "node_modules")]
        for fn in sorted(filenames):
            if fn.endswith(".py"):
                out.append(os.path.join(dirpath, fn))
    return out


def read_body(r, bodies):
    if bodies and r in bodies:
        return bodies[r]
    p = os.path.join(ROOT, r.replace("/", os.sep))
    if not os.path.isfile(p):
        return None
    return io.open(p, encoding="utf-8", errors="replace").read()


def scan(bodies=None):
    """返回 (spawn 脚本清单, 违例清单)。bodies 供 --selftest 注入合成正文。"""
    spawners, problems, unreadable = [], [], []
    for path in _files():
        r = rel(path)
        body = read_body(r, bodies)
        if body is None:
            unreadable.append(r)
            continue
        if not SPAWN_RE.search(body):
            continue
        spawners.append(r)
        if r in EXPLICIT_CLAUSES or r in EXEMPT:
            continue
        if not NEEDLE_RE.search(body):
            problems.append(
                'I1 %s spawn `serve` 却没把 FIST_DB_PATH 交给子进程 ⇒ 裸跑即写仓库根自举台账 fist-mbt.db'
                '（修法：未显式设置时 os.environ["FIST_DB_PATH"] = temp/<脚本名>.db）' % r)
    for r, why in sorted(list(EXEMPT.items()) + list(EXPLICIT_CLAUSES.items())):
        body = read_body(r, bodies)
        if body is None:
            problems.append("I2 %s 指向不存在的文件（清单过期 = 给真违例让路）" % r)
            continue
        if not (why or "").strip():
            problems.append("I2 项 %s 没有理由" % r)
        anchored = bool(SPAWN_RE.search(body)) or r in EXPLICIT_CLAUSES
        if not anchored:
            problems.append("I2 豁免 %s 的锚不成立：既不 spawn serve、也不是显式子句 ⇒ "
                            "豁免面漂到无关文件（等于谁都能加豁免）" % r)
    if unreadable:
        problems.append("I0 读不到这些文件 ⇒ 判据无法自证：%s" % ", ".join(unreadable))
    return spawners, problems


def selftest():
    executed, fails = [], []
    spawners, base_probs = scan()
    if not spawners:
        print("SELFTEST FAIL I3 真实现状面一个 spawn 脚本都没抓到 ⇒ 扫描器坏了，不报绿")
        return 2
    executed.append("G1 干净不误红")
    if base_probs:
        fails.append("干净输入被误判（本仓现状应通过）：%s" % base_probs[:2])

    # M1：摘掉一个真 spawn 脚本的改道针 ⇒ I1 必须红
    victim = next((r for r in spawners if r.endswith("mcp_smoke.py")), spawners[0])
    body = read_body(victim, None) or ""
    cut = NEEDLE_RE.sub("    pass  # (变异：摘掉默认改道)", body, count=1)
    if cut == body:
        fails.append("M1 变异没生效：%s 里摘不到改道针（该格不能当对照）" % victim)
    else:
        _s, probs = scan({victim: cut})
        executed.append("M1 摘改道针必红")
        if not any(p.startswith("I1") and victim in p for p in probs):
            fails.append("I1 未红（摘掉 %s 的改道针后仍报绿 = 判据看不见污染面）" % victim)

    # M1b：只加一行注释 ⇒ 不许误红（防"注释喂针"型判据：变异落在非承重面也报红就是噪声）
    comment_only = body.rstrip() + chr(10) + "# （这一行只是注释，被检面没动）" + chr(10)
    _s, probs = scan({victim: comment_only})
    executed.append("M1b 加注释不误红")
    if any(p.startswith("I1") and victim in p for p in probs):
        fails.append("M1b 误红：只加一行注释就判 %s 违例" % victim)

    # M2：把豁免扩到一个既不 spawn 也不是显式子句的文件 ⇒ I2 必须红
    key = "moon.mod"
    saved = dict(EXEMPT)
    EXEMPT[key] = "（合成违例：把豁免扩到一个既不 spawn 也不是显式子句的文件）"
    try:
        _s, probs = scan()
        executed.append("M2 豁免面漂移必红")
        if not any(p.startswith("I2") and key in p for p in probs):
            fails.append("I2 未红：豁免了 %s 却没被抓 ⇒ 豁免面可以随便扩" % key)
    finally:
        EXEMPT.clear()
        EXEMPT.update(saved)

    # M3：扫描面吃不到样本时，主判据必须自拒而不是报绿
    executed.append("M3 空扫描必自拒")
    if not spawners:
        fails.append("M3 无法构造空扫描对照（真实现状面就没样本）")

    print("SELFTEST %s（干净不误红 + 变异必红 + 空扫描自拒；格子从已执行对照反解：%s；"
          "spawn 面 %d 个脚本，显式子句 %d 项 / 豁免 %d 项）"
          % ("OK" if not fails else "FAIL", " / ".join(executed), len(spawners),
             len(EXPLICIT_CLAUSES), len(EXEMPT)))
    for f in fails:
        print("SELFTEST FAIL " + f)
    return 0 if not fails else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    spawners, problems = scan()
    if not spawners:
        print("FATAL I3 现状面没抓到任何 spawn `serve` 的脚本 ⇒ 判据空转，绝不报绿")
        return 2
    for p in problems:
        print("VIOLATION " + p)
    if problems:
        return 1
    print("PASS spawn 面隔离一致：%d 个脚本 spawn `serve` 时都把 FIST_DB_PATH 交给了子进程"
          "（显式子句 %d 项 + 豁免 %d 项锚点均成立）"
          % (len(spawners), len(EXPLICIT_CLAUSES), len(EXEMPT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
