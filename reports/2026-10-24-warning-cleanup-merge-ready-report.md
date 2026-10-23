# 清 warning 批次 · 合并就绪说明（2026-10-24）

面向：merge agent / 主仓维护者
结论：**6 条分支可任意顺序合流，无冲突；全部基于 `origin/master` b5c8a366，未触碰主分支。**

## 一、分支一览（均为单点 commit，已推 origin + gitcode）

| 分支 | tip | 改文件（与 master 差集） | 用途 |
|---|---|---|---|
| `fix/backlog-proof-restamp` | `b9caebf4` | 5 份 `docs/tasks/backlog/TASK-*.yaml` | 给 TASK-001/007/017/020/023 补 `rebase_proven:` 顶层键 |
| `fix/warning-batch-r1` | `146e90b8` | README.md、scripts/README.md、5 个脚本 | 徽章 1387→1413、登记 5 脚本、修 5 脚本非法转义 |
| `fix/test-sync-doc-1413` | `24ebae97` | 8 份文档（AGENTS/ARCHITECTURE/README.mbt/README_EN/docs×3/scripts/scoring_rubric） | 文档测试数 1387→1413 |
| `fix/slave-task-list-anchors` | `0bdbf722` | `docs/2026-10-20-slave-tasks.md` | 21 处认领入口锚点归位 |
| `fix/memory-log-empty-universe` | `abb6e8db` | `scripts/check_memory_log_dup.py`、`check_memory_log_dedupe.py` | 空宇宙豁免（策略锚点制），修 rc=2 误判 |
| `fix/py-stdout-encoding-gates` | `29d493c1` | `scripts/fist-pr-automator.py`、`scripts/fist-task-pool.py` | 补 stdout/stderr UTF-8 闸，消 E2 预告 |

## 二、无冲突证据
6 条分支相对 `origin/master` 的 `git diff --name-only` **零交集**（见上表），故两两 `merge-base` 后无文件级冲突，任意顺序 / 一次性合并均可。

## 三、合并后预期判据读数（本侧已逐条实测，判据面 rc）
- `check_backlog_status_staleness.py`：现状 rc=1（`落差 5 条 > 上限 0`，TASK-001/007/017/020/023 均 UNPROVEN-DONE）→ `fix/backlog-proof-restamp` 合入后预期 rc=0（该分支已给 5 条补 `rebase_proven`）。
- `check_scripts_index.py`：现状 rc=1（未登记 `check_memory_log_dedupe.py` / `check_memory_log_dup.py` / `check_merge_loss.py` / `tmp_merge_batch.ps1` / `tmp_merge_batch.sh`）→ `fix/warning-batch-r1` 合入后 rc=0。其余两分支**未新增文件**（只改既有已登记脚本），不会引入新未登记项。
- `check_test_sync.py`：`fix/test-sync-doc-1413`（8 文档）+ `fix/warning-batch-r1`（README.md / scripts/README.md 徽章与计数）二者合流后才 rc=0 —— **单合任一条仍红**，需两条都进主线。
- `check_memory_log_dup/dedupe.py`：CI 干净 checkout 面原 rc=2（日日志 `788c5823` 起剔 git 跟踪，空宇宙）→ `fix/memory-log-empty-universe` 合入后 rc=0（空宇宙豁免，且真重复仍 rc=1，非假绿）。
- `check_py_stdout_encoding.py --all`：E2 预告 2→0 → `fix/py-stdout-encoding-gates` 合入后 `--all` rc=0。
- `check_slave_task_list.py`：rc=0 + `--selftest` 18 格（`fix/slave-task-list-anchors` 已独立成立）。

## 四、本侧无法在合并前清的两项（需主仓侧 / 工具链 / 决策）
1. `check_fmt_gate.py` rc=2 = **BUG-388**（moon 0.1.20261016 `--check` 管线工具链缺陷，最小独立工程可复现；权威面以 CI Linux nightly 为准），非本仓内容问题。
2. `check_delivery_gap.py` rc=1 = 本地 `master` 未推送（`ahead=1113`），属本地仓库状态，非仓库内容；需 owner 决定是否推送。
3. 主线 `origin/master` 在本次开工期间未前移（仍 `b5c8a366`），无「从新 master 重开」需求；若后续主线前移，本批分支需 rebase 到新 tip 再合。

## 五、合并顺序建议
无强制顺序（零文件交集）。若想尽早获得判据全绿，建议顺序：`fix/backlog-proof-restamp` → `fix/warning-batch-r1` → `fix/test-sync-doc-1413` → 其余三条任意。

## 六、合并线预验证（本地 `verify/warning-integration` @ `9cd5d197`，未推远端）
6 条分支在 `origin/master`(b5c8a366) 上合并：前 3 条 fast-forward，后 3 条 ort 三路合并，**全部零冲突**。

| 判据 | origin/master rc | 集成线 rc | 转绿归因 |
|---|---|---|---|
| check_scripts_index | 1 | **0** | warning-batch-r1 |
| check_doc_dup | 1 | **0** | warning-batch-r1 |
| check_badge | 1 | **0** | 需 warning-batch-r1 + test-sync-doc-1413 **双支** |
| check_test_sync | 1 | **0** | 需 warning-batch-r1 + test-sync-doc-1413 **双支** |
| check_slave_task_list | 1 | **0** | slave-task-list-anchors |
| check_memory_log_dup | 2 | **0** | memory-log-empty-universe |
| check_memory_log_dedupe | 2 | **0** | memory-log-empty-universe |
| check_backlog_status_staleness | 1 | **1**（双红，主线既存） | 需上游主线补锚点，非本批 |
| check_py_stdout_encoding --all | 0 | 0 | 维持绿 |
| check_fmt_gate | 2 | 2（BUG-388） | CI Linux 为准 |
| check_backlog_yaml_integrity / check_text_control_chars | 0 | 0 | 维持绿 |

- 12 条判据 `--selftest` 集成线**全部 rc=0**。
- JS 全量测试：`Total tests 1413 / passed 1413 / failed 0`，rc=0（与 master 基线同数，零回归）。
- **无新引入的红**：集成线唯一 rc=1 与 master 的 rc=1 位相同，其余 11 条读数 ≤ master。
- 关键原文：`check_badge` → `PASS 徽章一致 README tests-1413%2F1413 == 实测 1413/1413`；`check_test_sync` → `PASS 实测 1413，扫描 137 份现状文档，0 条不一致；must-carry 5 条全部命中`。

### 结论（merge agent 可直接引用）
> 6 条分支可任意顺序合并，零冲突；合并后 10/12 判据 rc=0（其中 7 条由红转绿），JS 1413/1413 零回归，12 条 selftest 全绿。唯一挂红的 `check_backlog_status_staleness`（落差 5，TASK-001/007/017/020/023 UNPROVEN-DONE）在 origin/master 上同样红，是主线既存、非本批引入 —— 它需上游主线对那 5 个 TASK id 补盖章或改判，不属这 6 支能消的范围。

## 七、来源
- 全量测试权威读数：`Total tests: 1413, passed: 1413, failed: 0`（Windows 本机 JS target，moon 0.1.20261016 + `MOONC_OVERRIDE` shim，经 `scripts/moon_test_env.py`）。
- 各判据读数均由独立 worktree 取 `origin/<branch>` 实测复现，非自述。
- 遗留风险：`docs/2026-10-20-slave-tasks.md` 仍含若干未点记号的「裸锚点」，后续主线再前进可能重新漂移；建议后续在 §1 使用法补一句「行号锚点每次对账按尺实算归零后再抄回」。