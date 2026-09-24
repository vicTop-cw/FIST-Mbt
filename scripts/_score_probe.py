#!/usr/bin/env python3
"""_score_probe.py —— 4-AI 门禁 CLI 可用性 dry-run 探测助手。

给一条命令模板 + 提示词 + 超时 → 返回 exit code + stdout 前几行（含是否出现
SCORE_JSON 行），用于在跑真实门禁前确认各 CLI 能否 headless 驱动、输出形态是否合规。
命令模板中可用 `{PROMPT}` 占位（替换为提示词字符串）或 `{PROMPT_FILE}`（临时文件路径）。

用法
----
    python scripts/_score_probe.py --cmd 'echo PROBE'                     # 骨架验证
    python scripts/_score_probe.py --cmd 'atomcode -p "{PROMPT}"' \
        --prompt '仅回复 OK' --timeout 60                                 # 真实 CLI 探测

退出码：0=可运行（无论 SCORE_JSON 是否出现），2=CLI 不可用/超时。仅作探测，无 PASS/FAIL 语义。
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
import tempfile


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="CLI 可用性 dry-run 探测助手")
    ap.add_argument("--cmd", required=True, help="命令模板，可含 {PROMPT} 或 {PROMPT_FILE} 占位")
    ap.add_argument("--prompt", default="仅回复 OK", help="提示词文本（替换 {PROMPT}）")
    ap.add_argument("--timeout", type=int, default=60, help="超时秒数")
    ap.add_argument("--lines", type=int, default=12, help="打印 stdout/stderr 前 N 行")
    args = ap.parse_args(argv)

    prompt_file = None
    if "{PROMPT_FILE}" in args.cmd:
        with tempfile.NamedTemporaryFile("w+", suffix=".txt", encoding="utf-8", delete=False) as tf:
            tf.write(args.prompt)
            prompt_file = tf.name
        cmd = args.cmd.replace("{PROMPT_FILE}", prompt_file)
    else:
        cmd = args.cmd.replace("{PROMPT}", shlex.quote(args.prompt))

    try:
        proc = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=args.timeout,
        )
        rc = proc.returncode
        out, err = proc.stdout, proc.stderr
    except FileNotFoundError:
        print("RESULT=UNAVAILABLE\nreason=CLI not found")
        return 2
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "").decode("utf-8", "replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        err = (e.stderr or "").decode("utf-8", "replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        print(f"RESULT=TIMEOUT>={args.timeout}s")
        print(f"--- stdout 前 {args.lines} 行 ---")
        for ln in out.splitlines()[: args.lines]:
            print(ln)
        return 2
    except OSError as e:
        print(f"RESULT=UNAVAILABLE\nreason={e}")
        return 2

    print(f"exit_code={rc}")
    has = "SCORE_JSON:" in out
    print(f"has_SCORE_JSON={has}")
    print(f"--- stdout 前 {args.lines} 行 ---")
    for ln in out.splitlines()[: args.lines]:
        print(ln)
    if err.strip():
        print(f"--- stderr 前 {args.lines} 行 ---")
        for ln in err.splitlines()[: args.lines]:
            print(ln)
    return 0


if __name__ == "__main__":
    sys.exit(main())