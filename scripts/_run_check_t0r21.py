#!/usr/bin/env python3
"""T0r2.1 run_check 判据：moon test src/engine 全绿即通过（BUG-253 修复回归）。

路径全部由本文件位置 / 环境推导，零本机硬编码：
  · 仓根 = scripts/ 的上一层（可用 env FIST_MBT_HOME 覆盖）
  · moon = env FIST_MOON_BIN > PATH 上的 moon > ~/.moon/bin/moon[.exe]
"""
import os
import shutil
import subprocess
import sys


# BUG-58/138 stdout/stderr UTF-8 重配：本脚本 print 非 ASCII，
# Windows 控制台（cp1252/GBK）下不重配会当场 UnicodeEncodeError（check_py_stdout_encoding --all 面）。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

REPO_ROOT = os.environ.get("FIST_MBT_HOME") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def pick_moon() -> str | None:
    env_bin = os.environ.get("FIST_MOON_BIN")
    if env_bin:
        return env_bin
    found = shutil.which("moon")
    if found:
        return found
    home = os.path.expanduser("~")
    for name in ("moon.exe", "moon"):
        cand = os.path.join(home, ".moon", "bin", name)
        if os.path.exists(cand):
            return cand
    return None


moon = pick_moon()
if not moon:
    print("ERR 找不到 moon：设 FIST_MOON_BIN，或把 moon 放进 PATH / ~/.moon/bin")
    sys.exit(2)

cmd = [moon, "test", "src/engine"]
try:
    p = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, timeout=600)
except Exception as e:
    print(f"ERR spawn: {e}")
    sys.exit(2)
out = (p.stdout or "") + (p.stderr or "")
print("EXIT:", p.returncode)
print(out[-2000:])
if "passed: 162" in out and p.returncode == 0:
    sys.exit(0)
sys.exit(1)
