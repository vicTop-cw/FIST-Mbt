# R111 任务池状态对账报告 — 9 条落差清零，STALE_CEILING 4→0

- 单元：`slave/fix/backlog-status-reconcile-r111`（基点 `gitcode/master` = `8e6dcb13`）
- 作者：副机 AtomCode（自立项；接在主机任务池 TASK-001 常驻化之后）
- 时间：2026-10-22 07:47 UTC

## 结果摘要

`check_backlog_status_staleness.py` 在 `8e6dcb13` 上现读 rc=1：主线 commit subject 已点名的 9 张单仍 `status: backlog`（落差 9 / 上限 4 / 超限 5）。本单元逐条核对证据后给真状态，不整批翻 `done`：

| 任务 | 新状态 | 依据 / 未完成面 |
|---|---|---|
| TASK-001 | `done` | 三条验收全部在 `acceptance_met` 有证（CI 门 / pre-commit 三步 + install_git_hooks.py / slave-branch-merge.ps1），behavior_test 临时仓库端到端通过 |
| TASK-005 | `in_review` | `fist-gate.py --scan` 已落（ahead/cherry_plus/conflict_markers/src_lines_changed/suggested_action + 巡检 prompt 行；S2/S6 自证）；验收④「scan 产物状态 backlog→claimed→done 可被下一轮看到」未取证（scan 固定写 `status: backlog`，认领生命周期在 `fist-task-pool.py`） |
| TASK-006 | `in_review` | `docs/DOCS-STRUCTURE.md` 已落（r85）；验收②未做——根目录仍有 9 份 .md，迁移/删除要 owner 定档 |
| TASK-008 | `in_review` | 验收①已交付（`scripts/NAMING.md` + `check_scripts_naming.py`，R95）；②③④未做——N1 仍有 16 份真债、改名总成本 1224 处引用，先等 owner 裁「只动活面 vs 连归档面回写」 |
| TASK-009 | `in_review` | whisperer.py Step 0-4 / `--scan-only` / `--auto-merge` / `--selftest`（rc=0）/ fist-gate G5 / Step 3 写 TASK yaml 均已落；验收③写的旗名 `--apply` 实际实现为 `--auto-merge`（未留别名） |
| TASK-018 | `in_review` | 危险面仍在：`step0_head_safety(full=True)` 在 `--scan-only/--auto-merge` 之前执行，判「篡改」后仍 `reset --hard` + 双远端 `--force`；但电池面已封（run_guards 对 whisperer.py 只点名 `--selftest`，另有危险无参格普查），已无无人值守触发路径，等 commander 裁决 |
| TASK-019 | `in_review` | 双活解已落地并接线（`whisperer_patrol.py`；fist-gate 第 6 查指 patrol；run_guards 两格 `--selftest`）；但 `scripts/README.md` 仍写「等 TASK-019 裁决」、owner 裁决未落字 |
| TASK-022 | `in_review` | bdedc73 已合入；a457aea 的 `install_git_hooks.py` 与 4da1126 的 whisperer gitdir/selftest 修复已分别以其他提交进主线；2be0c89 的白名单设计未采用，但其风险面（whisperer 无参强推格）已被 run_guards 危险无参普查封住。合序已无待行动作，正式裁决未落字 |
| TASK-023 | `done` | `check_bug_reference_integrity.py` 现读 J1=0 条 / 上限 0（rc=0）；`engine.mbt` 已改 BUG-176；账本五条抬头 `grep -c=5` |

配套三处接线（让「修好」变成永久门禁，而不是改完就忘）：

1. `scripts/check_backlog_status_staleness.py`：`STALE_CEILING` 4→0（尺自己打印 RATCHET 要求降数，本次兑现）。
2. `scripts/run_guards.py`：`expected("check_backlog_status_staleness.py", 1, ...)` → `case(...)`——按「预存红被修好 ⇒ 期望改回 0」的律转回门禁格，依据一起删。
3. `scripts/README.md`：该尺条目里的 within 读数 `落差 4 / 上限 4 / 超限 0` → `落差 0 / 上限 0 / 超限 0`。

## 证据（实跑）

- 主尺：`python scripts/check_backlog_status_staleness.py` ⇒ `扫描面=gitcode/main | backlog 23 份 | 主线点名到的 TASK id 13 个 | 落差 0 条 / 上限 0 条 / 超限 0 条`，rc=0。
- 自证：`python scripts/check_backlog_status_staleness.py --selftest` ⇒ 11 格全 OK，rc=0。
- 电池自证：`python scripts/run_guards.py --selftest` ⇒ rc=0（81 把尺 / CI 面 39 / 电池面 43 / 缺面 0 / 常驻豁免 2）。
- 文档对表：`python scripts/check_selftest_inventory_doc.py` ⇒ `INVENTORY_SYNC=clean 判定族 22 条逐一对表通过`，rc=0。
- EOL：本单编辑面全部保持 CRLF、bare LF=0（清单见提交前 `git diff --stat`）。
- 全量电池：`python scripts/run_guards.py`（隔离 `FIST_DB_PATH=/tmp/fist-r111.db`）⇒ **rc=0 / 55 格 / 失败 0 / SKIP 5 / 缺执行面 0**；`check_backlog_status_staleness.py` 那格已是门禁格（rc=0 exp=0）。预存红照旧：ci_step_position(1/2)、merge_markers(1)、scripts_naming(1)、cleanup_artifacts(1)、fist-gate(2)。

## 资源消耗

1 个副机 agent，约 40 分钟：fetch/对账 9 份 YAML、跑主尺 + 自证 + 电池 + 文档对表、写报告/日志。无子代理。

## 任务分配记录

无子代理、无 MCP 任务发布；全部由副机 agent 执行并自审。

## 遗留风险

- 7 条 `in_review` 都有真实未完成面（见上表），不能当 `done` 直接关闭；状态变更只解决「重复派单」，不改变剩余工作量。
- TASK-018 的破坏性路径仍在代码里（Step 0 full 模式），仅电池触发面被封；若有人裸跑 `whisperer.py --scan-only/--auto-merge` 仍可能 `reset --hard` + 强推共享线。
- 预存红不代修：`check_scripts_naming.py` rc=1 等照旧，本单只点名原因。
- 若后续主线 commit 点名 TASK 而 YAML 未同步状态，主尺会立即 rc=1（设计意图，不是误红）。

## 后续建议

- TASK-005/009 补最后一条验收（005 的状态生命周期取证；009 加 `--apply` 别名或改验收原文）后转 done。
- TASK-006/008 等 owner 裁范围；TASK-018/019/022 由 commander 落正式裁决并把 README/状态改成既成事实。
- 合并时 `memory/2026-10-22.md` 是大文件纯追加：与 R108/R110 段落的冲突只可能在尾部，按「先 merge-tree 再断言」处理。

## 超额内容

- 把尺自报的 RATCHET 提示当场兑现（上限 4→0），并顺手把电池里的期望红转成真门禁——这一步不在原计划，但是「修好之后不留下免检牌」的同一纪律。

## 来源

- 主线基点：`gitcode/master` = `8e6dcb13`（2026-10-22 07:43 UTC 现读）。
- 触发读数：`扫查面=gitcode/main | backlog 23 份 | 主线点名到的 TASK id 13 个 | 落差 9 条 / 上限 4 条 / 超限 5 条`，rc=1。
- MR 入口：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/fix/backlog-status-reconcile-r111
