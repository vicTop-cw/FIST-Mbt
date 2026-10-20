# 报告：BUG-332 残余 stdout UTF-8 重配收口（R1）

## 结果摘要
- 用 fist-mbt 发布版 MCP 工具全程驱动本轮（`project_health` / `bug_list` / `reserve_scope` / `issue_scan` / `bug_fix`）。
- 销账 **BUG-332**（[medium] OPEN → FIXED）：补上 BUG-58/138 的 stdout UTF-8 重配到残余 2 处脚本。
- 变更只落在 2 份 Python 脚本的 import 段后（各 6 行），无 MoonBit 改动。

## 证据
- `python scripts/check_py_stdout_encoding.py --all`：修复前 FAIL（该带闸 82 / 已带 80，E1 点名这两份）→ 修复后 **PASS（该带闸 82 / 已带 82，纯 ASCII 面预告 0）**。
- CI 面（workflow 反解）：PASS（30/30）。
- 判据自证：`--selftest` → `SELFTEST OK`。
- `python -m py_compile` 两文件 rc=0。
- 冒烟：`FistClient()` 独立实例化 + `store_list` 调用正常返回（`{"active_namespaces":[],"stats":{}}`），未破坏客户端。

## 变更内容
- `scripts/fist_mbt_mcp_client.py`：`import subprocess, json, os, threading, time, sys` 后插入
  `sys.stdout/stderr.reconfigure(encoding="utf-8", errors="replace")`（带 `hasattr` 守卫），附 BUG-58/138 注释。
- `scripts/ns_route_probe.py`：`import sys, os, json, shutil, tempfile as tf` 后插入同款重配。

## 并发协调
- 两文件与 `memory/bugs.md` 在他人在改（git M）。均先 `reserve_scope` 预订（无冲突：`lock_status` locked=false、`reserve_check` free=true）→ 编辑 → `reserve_release`；销账前同样先预订账本。
- 既有 M 改动（`JS` 路径指向 `_build` 产物）与本轮插入点零重叠，未触碰。

## 遗留风险
- `scripts/ns_route_probe.py` 实跑失败：`OSError [Errno 22] Invalid argument`（写子进程 stdin）。独立测 `FistClient` 正常，判断为该探针自身 cwd 未建导致 server 未起，属多租户探针域、非 BUG-332 范围；待该域 owner 复核。
- 该探针另有他人在改的未提交行带 `SyntaxWarning: invalid escape sequence '\I'`（`"E:\IDEProjects\..."` 原始字符串问题），`py_compile` 仍 rc=0，未代改。

## 后续建议
- 寻虫面：`issue_scan dir=src/executor` 162 命中全为 low/info 启发式噪音（long-function 36 / unused-variable 61 / private-field-leak 与 noop-assignment 均为结构体字段/struct-update 语法的子串误报），**无可修新 bug**，与 BUG-333 的噪音诊断一致。
- 下一轮候选（无冲突优先序）：BUG-327（ocr_scan 对 .mbt unsupported_ext，诚实门禁，面在 src/server）、BUG-333（issue_scan 降噪）、BUG-342（`?`→`~` 参数签名回归）。

## 来源
- 账本 `memory/bugs.md` BUG-332 条目 + `### FIXED(2026-10-20T12:01:05Z / BUG-332)` 小记（bug_fix 同笔）。
- 判据 `scripts/check_py_stdout_encoding.py`（BUG-58/138 单一真源）。