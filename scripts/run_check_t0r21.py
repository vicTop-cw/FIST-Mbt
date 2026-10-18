#!/usr/bin/env python3
"""T0r2.1 run_check 判据：moon test src/engine 全绿即通过（BUG-253 修复回归）。"""
import subprocess, sys

cmd = [r"C:\Users\victo\.moon\bin\moon.exe", "test", "src/engine"]
try:
    p = subprocess.run(cmd, cwd=r"E:\IDEProjects\AI\FIST-Mbt", capture_output=True, text=True, timeout=600)
except Exception as e:
    print(f"ERR spawn: {e}")
    sys.exit(2)
out = (p.stdout or "") + (p.stderr or "")
print("EXIT:", p.returncode)
print(out[-2000:])
if "passed: 162" in out and p.returncode == 0:
    sys.exit(0)
sys.exit(1)
