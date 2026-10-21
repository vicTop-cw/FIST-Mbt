# R81 报告 · slave/ci/task001-marker-gate-r81 — TASK-001 冲突标记硬前置门禁

## 1. 结果摘要

TASK-001（风语者 P0）三个验收面逐一对表：

| 验收 | 状态 | 说明 |
|---|---|---|
| ① PR/commit 合入前自动跑 check_merge_markers.py | ✅ 已在 master | r74 接线被吸收（`.github/workflows/ci.yml:38-45`，selftest + 全量各一道） |
| ② cherry-pick 全解完 + git diff --check + selftest 过才许 commit | ✅ 本单落脚本面 | 见下；`--selftest` 由 CI 门覆盖，脚本门用更强的全量判据 |
| ③ slave-branch-merge.ps1 加 cherry-pick 后自动标记扫描 | ✅ 本单实现 | 真缺口所在 |

`scripts/slave-branch-merge.ps1`（46+/10-）：
- **per-pick 门**：每次 cherry-pick 在 `git commit` 之前跑 `python scripts/blackbox/check_merge_markers.py`，rc!=0（含 rc=2 判据自拒，fail-closed）→ 打印判据输出前 6 行 → `git cherry-pick --abort`（fallback `git reset --hard HEAD`）→ `continue` 下一 commit，`$markerSkips` 计数入汇总行；
- **收尾门**：清冲突标记循环之后、收尾 commit 之前再跑一遍，rc!=0 → 不 commit **不 push**，退出；
- **顺手修（同文件，门的前置）**：`git fetch --all --prune 2>&1 | Out-Null` 在 `$ErrorActionPreference="Stop"` 下遇远端 stderr 即终止全脚本（本机 DryRun 实测：github origin 443 不通，NativeCommandError 直接炸死在第 23 行）——BUG-109 同族。fetch 一行改临时降 EAP 模式。
- 步骤头 [x/6] 重编号 [x/8]；头部流程注释补 TASK-001 语义；`scripts/README.md` 条目同步。

## 2. 资源消耗

会话内约 8 分钟；验证发数：Parser 1 / ps_encoding 1 / DryRun 2（修复前后各一）/ EAP 微测试 1 / judge selftest 1 / doc_surface 1。

## 3. 任务分配记录

副机单干。任务来源 `docs/tasks/backlog/TASK-001-conflict-markers-no-commit.yaml`（discovered_by: lead，assignee 标 atomcode）——用户指令「docs/tasks/ 是风语者给你的任务，优先这个」为开工依据；yaml 状态位留给 owner 翻转，本单不改。

## 4. 遗留风险

- **门路径未做真实冲突 cherry-pick 端到端**：实跑 `-DryRun` 之外的流程会真合并 + push master（金条四不代做不可逆操作）。已验证的是：脚本解析 0 错、门判据 rc 语义（selftest rc=0 / fail-closed rc=2）、EAP 抑制模式微测试（stderr+rc=1 不终止、rc 正确捕获）、DryRun 全流程。真实冲突场景由合并 agent 下一次真跑验证，第一次真跑建议先 `-DryRun` 后人工确认再放行。
- **同文件同族隐患未动（预存，点名）**：cherry-pick/commit/build/push 各处的 `2>&1` 在 EAP=Stop 下同属「stderr 变终止错误」形状；本单只修了挡门的 fetch 一行，其余属合并 agent 自有施工面。
- `check_scripts_index` rc=1（master 自带预存红）：`fist-gate.py` 未在 scripts/README.md 登记（TASK-003/004 面，主机在办）。
- acceptance② 的 `git diff --check`（尾随空白）未进脚本门：对合并场景会产生风格噪音假红，判据面已由 marker 判据覆盖；如 owner 要全量对齐可在门里追加一行。

## 5. 后续建议

- TASK-005（P1，gate-auto-inject）与 TASK-002（P1，cherry-pick-blacklist——注意 r79 已持有 rhop_poll.mbt 反证）下一批；TASK-007（P1，run_guards 宇宙）适合脚本单。
- 合并 agent 真跑本脚本前，先合 r80/r81——r80 的账本补账让 merge 时的 theirs 策略不至于倒退。

## 6. 超额内容

- fetch 行 BUG-109 同族修复（原计划只加门；DryRun 复现脚本死在门之前，不修门不可达）。

## 7. 来源

- 实测读数：PowerShell Parser `PARSE OK (0 errors)`；`check_ps_encoding` rc=0（9 个 .ps1 全 BOM/ASCII）；DryRun 输出「发现 10 个 slave 分支 / 有代码改动 10 个 / DRY-RUN 退出」；EAP 微测试 `rc=1 not-thrown=True → MICRO PASS`；`check_merge_markers.py --selftest` rc=0；`check_doc_surface` rc=0。
- 证据链参照 TASK-001 yaml（259b56a8 三元组、e1b1a9d3、6/6 分支命中）。
