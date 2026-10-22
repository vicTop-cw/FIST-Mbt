---
decision_id: DEC-2026-10-22-001
proposal: fist-mbt/plans/2026-10-22-fist-dir-layout-governance-proposal.md
decided_by: human_steward
decided_at: 2026-10-22T15:10:00+08:00
decision: approved
---
# 定案记录 DEC-2026-10-22-001

**提案**：FIST-Mbt 双层目录治理（`.fist-mbt/` 机器独有 + `fist-mbt/` 团队共享）

**决策**：✅ 批准（approved）

**定案人**：human_steward（指挥官）

**定案依据**：计划治理缺位（agent 把计划塞进 `reports/`）+ 机器独有工件污染主仓根（95 db / 37 temp / 10 目录 / cron state / `.git/fist`）+ `improvement-plan` 未覆盖。双层布局 + 提案→定案→执行门禁能同时解决。

**后续动作**：
1. 按 Phase 1→5 拆分为 5 件任务发布到 fist-mbt DB（T-G1 高→副机 / T-G2 高→副机 / T-G3 中→agent / T-G4 高→副机 / T-G5 中→agent）。
2. Phase 1、2、4 交副机；Phase 3、5 由 agent 自取。
3. 每阶段一次提交，过 `moon test` + 双守卫。

**关联**：`improvement-plan-20261010.md` 待补"计划治理"节（Phase 5）。
