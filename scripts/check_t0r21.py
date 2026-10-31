#!/usr/bin/env python3
r"""T0r2.1 run_check 判据：`moon test --target js src/engine` 全绿即通过（BUG-253 修复回归）。

**本件是 T0r2.1 当轮的验收判据，不是日常工具** —— 保留作活证据（BUG-325 裁决：
「删除=丢当轮证据，登记=保留作活证据，非日常工具」同型入账）。

2026-10-31 R115 打磨（两处都是「改名后失去豁免」逼出来的，判例-39）：
1. **去掉本机绝对路径** —— 原第 13/15 行内嵌「某台机器的家目录 + moon.exe」与
   「某台机器的工程绝对路径」两个字面量，换机不可复跑；`check_hardcoded_paths` 的豁免
   只认 `scripts/_*.py` 前缀（本件已按 NAMING.md 债表的「改名 `check_*.py`」建议改名，
   豁免随之消失）⇒ 改为**从 `__file__` 反推仓根** + 走常驻入口 `moon_test_env.py`
   （后者负责剔 PATH 上的 `node.cmd` 垫片与 `MOONC_OVERRIDE`，见 BUG-380/BUG-125）。
   ⚠️ 本 docstring **故意不写出那两个 token**（家目录名与工程目录名）——判据扫的是
   token 不是意图，写出来就等于自己把自己判红。
2. **去掉写死的 `passed: 162`** —— 该数是 2026-10-16 的读数，现在 `src/engine` 是
   **382/382**；写死一个旧数 = 判据恒红的哑雷（比没有判据更坏）。改为**从输出里解析
   `Total tests: N, passed: M, failed: K`**，只判 `K == 0 且 N == M`。

rc 契约（与 `moon_test_env.py` 同源）：`0` 全绿 / `1` 有失败 / `2` 判据无法自证
（没有汇总行 —— BUG-142：不许只凭 `moon` 的退出码判绿）。
"""
import os
import re
import subprocess
import sys


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCOPE = "src/engine"
ENTRY = os.path.join("scripts", "moon_test_env.py")

SUMMARY_RE = re.compile(r"Total tests:\s*(\d+),\s*passed:\s*(\d+),\s*failed:\s*(\d+)")

cmd = [sys.executable, ENTRY, "--target", "js", SCOPE]
try:
    # encoding 必须显式给 UTF-8：`text=True` 不带 `encoding=` 时 Python 用**本机 locale**
    # （本机 GBK）解码，moon 的输出是 UTF-8 ⇒ 读侧线程 UnicodeDecodeError ⇒
    # **stdout/stderr 双双返回空、而 returncode 照常是 0**（2026-10-31 实测）——
    # 父进程拿到「rc=0 + 空输出」，比直接崩更难判。与 BUG-58/138 同族，只是这一处
    # 在**取数的这一侧**，不在被取的那一侧。
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=900)
except Exception as e:
    print("ERR spawn: %s" % e)
    sys.exit(2)

out = (p.stdout or "") + (p.stderr or "")
print("CMD:", " ".join(cmd))
print("EXIT:", p.returncode)
print(out[-2000:])

m = None
for line in out.splitlines():
    m = SUMMARY_RE.search(line)
    if m:
        break
if m is None:
    print("ERR 判据无法自证：输出里没有 `Total tests: N, passed: M, failed: K` 汇总行")
    sys.exit(2)

total, passed, failed = int(m.group(1)), int(m.group(2)), int(m.group(3))
print("SUMMARY: total=%d passed=%d failed=%d" % (total, passed, failed))
if failed != 0:
    print("FAIL 有失败：failed=%d" % failed)
    sys.exit(1)
if total != passed:
    print("FAIL 总数与通过数不等：total=%d passed=%d" % (total, passed))
    sys.exit(1)
print("PASS %s 全绿：%d/%d" % (SCOPE, passed, total))
sys.exit(0)
