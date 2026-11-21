#!/usr/bin/env python3
"""e2e_agent_suite —— fist-gateway 黑盒判据套件入口（巡检打磨）

串跑全部 fist-gateway 面的黑盒判据脚本并聚合读数，供定时巡检一键回归：
  e2e_agent_shim_live.py        B1-B5  /v1/chat/completions shim
  e2e_agent_s3_header.py        S0-S4  S3 挑战签名头注入
  e2e_agent_models_status.py    M/R/X  /v1/models + GET /v1/tasks/<id>
  e2e_agent_task_wait.py        W1-W3  wait=1 长轮询（W2 共享池下允许 SKIP）
  e2e_agent_task_ns_pairing.py  跨 ns  配对缺陷回归锁（KNOWN-RED 至缺陷修复）

退出码：0 = 无硬 FAIL（PASS/SKIP/KNOWN-RED 均算过）；1 = 有脚本硬失败。
判据自身子进程退出码即为其裁决，本套件只聚合不改判。

用法：
  python scripts/blackbox/e2e_agent_suite.py            # 全量串跑
  python scripts/blackbox/e2e_agent_suite.py --list     # 只列成员不跑
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent  # scripts/blackbox/ → 仓根
HERE = Path(__file__).resolve().parent

SUITE = [
    ("e2e_agent_shim_live.py", "shim 实弹（B1-B5）"),
    ("e2e_agent_s3_header.py", "S3 头注入（S0-S4）"),
    ("e2e_agent_models_status.py", "发现面/回执面（M/R/X）"),
    ("e2e_agent_task_wait.py", "wait 长轮询（W1-W3，W2 允许 SKIP）"),
    ("e2e_agent_task_ns_pairing.py", "跨 ns 配对锁（KNOWN-RED 至修复）"),
]


def main() -> None:
    if "--list" in sys.argv:
        for name, desc in SUITE:
            print(f"{name}  {desc}")
        return
    hard_fail = []
    for name, desc in SUITE:
        path = HERE / name
        print(f"\n===== {name}  {desc} =====")
        proc = subprocess.run([sys.executable, str(path)], cwd=str(ROOT))
        if proc.returncode != 0:
            hard_fail.append(name)
    print("\n===== 套件读数 =====")
    for name, _ in SUITE:
        mark = "FAIL" if name in hard_fail else "OK  "
        print(f"  [{mark}] {name}")
    if hard_fail:
        print(f"\n套件结论：{len(hard_fail)} 项硬失败")
        sys.exit(1)
    print("\n套件结论：全绿（PASS/SKIP/KNOWN-RED，无硬失败）")


if __name__ == "__main__":
    main()
