# Goal-2 Round 43 报告：min_evidences 分界契约锁（接线前置）

- **日期**：2026-10-15
- **提交**：R43 code（`src/router/router_caf_ext_wbtest.mbt` 追加 2 锁，纯测试无源码改动，HEAD `c7c1905`）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9 WIP）；本轮做接线前置的**分界语义**补锁

## 结果摘要

### 全仓编译恢复（R42 红已收口）

R42 记录的全仓 `Error:[4080]`（`github_sync_wbtest.mbt:250` `github_queue_append` 8 参 vs 6 参）**已收口**：
`github_sync.mbt` + `github_sync_wbtest.mbt` 的 M WIP 状态消失。
本轮 `moon test --target js` **1202/1202 全绿**（R42 时红），加 R43 的 2 锁后 **1204/1204 全绿**。

### R1 引导复核：BUG-193（is_finite）已 stale

`supervisor_reminder_tick` 的 R1 未消费引导提示：
> BUG-193 仍在 OPEN（`router_config.mbt:219` + `router_state.mbt:45` 各 1 处 `is_finite` 编译错误）

**复核**：`grep is_finite src/` **0 匹配** → BUG-193 已修（`is_finite` 已从源码移除），全仓 1204/1204 绿亦证实。
该引导创建于 09:23，现 22:18，**已 stale**。**教训**：R1 引导须在消费前复核真源，不凭引导正文下结论。

### 提醒者角色 plan 已落地（R42 遗留备选方向复核）

`docs/2026-10-12-fist-mbt-reminder-role-plan.md` 标记「计划待实施」，但其核心工具
`supervisor_reminder_tick` 已在 AGENTS.md 超级管家工具族内。实跑返回 **1731 reminders**
（R1 未消费引导 1 条 / R2 stale 大量 / R3 pending_timeout 大量）→ **plan 已落地**，仅 docs 未更新标记。
**此方向不推进**（已实现）。

### OPEN bug = 0

`bug_list` 显示 223 条，R42 遗留候选 **BUG-217/185/186 抬头均已 FIXED**
（`bug_list` 中间段曾短暂读到旧抬头，复核 `memory/bugs.md` 确认：
BUG-217 evidence 写于 `src/claimguard/claimguard.mbt` commit `ba4fd93`，
BUG-185/186 由 `scripts/blackbox/e2e_irm_line.py` 并发 WIP 修复）。
**账本无 OPEN bug，无 open_with_linked_done 矛盾**。

### 实质产出：min_evidences 分界契约锁（接线前置第二件）

复核现有 14 条 `caf_soft_reorder_with_preference` 锁，发现**恰好边界**未覆盖：
- 已有锁覆盖：`total=0, min=10`（L138 走偏好）、`min=0, total=1`（L119 走重排）、`total=1, min=10`（L77 走偏好）
- **缺**：`total == min_evidences`（恰好达标）与 `total = min-1`（差一档）的**分界语义**

真源 L44 用 `evidence_total(stats) >= min_evidences`（**`>=`**）→ 恰好达标走重排，差一档走偏好。

补 2 条互补锁（`caf_pref_exact_boundary_reorder` / `caf_pref_one_below_boundary_pref`）：
- **`caf_pref_exact_boundary_reorder`**：`total=2, min=2` → 走重排（偏好 m_free 被忽略，m_mid 排第一）
- **`caf_pref_one_below_boundary_pref`**：`total=1, min=2` → 走偏好（m_free 排第一）

**为何接线前置必需**：接线时 `min_evidences` 参数的**分界语义**不明确会导致记忆「够/不够」误判。
若接线误用 `>` 而非 `>=`，恰好达标的记忆会被当成不够而走偏好，丢弃已积累的 A/B 数据；
若误用 `<` 而非 `<=`，差一档的弱记忆会被当成够而走重排，用噪声数据排序。
两锁把 `>=` 分界钉死，接线方照抄即可。

### 并发观察

并发 agent 本轮同时推进：修 BUG-221（`2ec9cb2 fix` + `0b849e7 docs`，`read_dir` 失败静默转默认值）、
`model_router_ops.mbt` 仍 4/9 WIP。**未触碰**（AGENTS.md 并发 WIP 隔离）。

## 验证

- router **195/195**（R42 193 + 2 边界锁），0 failed
- 全仓 **1204/1204**（R42 1202 + 2），0 failed
- `.mbti` 无变化（纯测试追加，无新 pub fn）

## 资源消耗

`supervisor_reminder_tick`（R1 引导复核）/ `bug_list`（OPEN 复核）/ `grep is_finite`（BUG-193 复核）/
`grep test 锁清单`（边界缺口定位）/ `moon fmt` + `moon test --target js src/router` / 全仓回归 /
`git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/router_caf_ext_wbtest.mbt`
（无并发 WIP，`moon info` 前 `git diff --numstat pkg.generated.mbti` 为空证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9）。接线点必须用 `caf_feature_hash(caf_normalize_context(ctx))`（R42 契约）+ `min_evidences >=` 分界（R43 契约）。
- **R1 引导存在 stale 风险**：`supervisor_reminder_tick` 未消费项若不消费会累积；建议消费后 `supervisor_prompt_consume` 标记，减少下轮重复提示。
- **并发 WIP 持续**：`model_router_ops.mbt` 4/9、`e2e_irm_line.py` M、BUG-221 刚修。
- **提醒者 docs 未更新标记**「已落地」（非代码问题，属文档一致性；可由 concurrent 或后续轮补齐）。

## 后续建议

1. **R44 首选**：§2.3 接线（`model_router_ops.mbt` 释放后），接线点用归一化 hash + `>=` 分界。
2. **R44 备选**：把 R1 引导的 stale 治理做成**消费闭环**（R1 发现 → R2 提示 → prompt_consume 标记），
   或给 `supervisor_reminder_tick` 补「引导 stale 判定」锁（创建超 N 小时未消费降级提醒）。
3. **持续观察**：并发 agent 提交节奏快（BUG-221 当天开当天修），R1 引导复核务必先 grep 真源再行动。
4. **文档一致性**：提醒者 plan 与 supervisor-tools-plan 的「已落地」标记可在并发收口后统一更新。

## 来源

- `supervisor_reminder_tick`（R1 引导 BUG-193 / 1731 reminders）
- `bug_list` + `memory/bugs.md` 复核（BUG-217/185/186 抬头 FIXED）
- 真源：`src/router/router_caf_ext.mbt` L44 `evidence_total(stats) >= min_evidences`
- 新增锁：`src/router/router_caf_ext_wbtest.mbt`（`caf_pref_exact_boundary_reorder` / `caf_pref_one_below_boundary_pref`）
- 设计文档：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.3
