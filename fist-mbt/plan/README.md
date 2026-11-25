# `fist-mbt/plan/` — 计划提案库

这是 fist-mbt 的**计划治理中枢**。所有**计划**必须走这里，禁止再塞进 `reports/`。

> **归档位置变更（2026-10-24，owner 裁决「序号3=迁」）**：本库原在 `fist-mbt/plans/`，
> 后迁至 `docs/plans/`，与本仓文档集骨架（`AI-DEVELOPMENT-STANDARD.md` §2）对齐——
> 计划属文档面，不再占用根级专有目录。
>
> **统一计划目录（2026-11-24，T0r27）**：按 `fist-mbt/plan/draft/2026-11-22-unified-plan-dir.md`
> 收编为 `<repo>/fist-mbt/plan/{draft,active,done}/` 统一形状，整库自 `docs/plans/` git mv 迁入
> （在流计划→`draft/`，原 `archived/`→`done/`，`decisions/` 沿用原名），旧路径不再新增计划。

## 流程

```
Agent 提案 → plans/*-proposal.md (status: 提案中)
  → 指挥官 human_steward 定案
    → approve → 定案记录写 decisions/ + 发布任务到 fist-mbt DB
    → reject / defer → 计划留档标记状态，不发布任务
  → 执行完成 → 汇报进 reports/ + 计划移入 archived/
```

## 文件规范

- **文件名**：`YYYY-MM-DD-<slug>.md`（slug 为短横线小写英文；本仓真源见 `AI-DEVELOPMENT-STANDARD.md` §2「计划文件规范」）。
  定案记录在 `decisions/`（沿用原名），命名同为日期前缀。
- **头部强制字段**（缺一即红，`check_plan_location` 守卫）——**仅对提案卡 `*-proposal.md` 生效**：
  ```yaml
  ---
  status: 提案中   # 提案中 | 已定案 | 已驳回 | 已推迟 | 已完成
  decided_by:      # 定案人（仅 human_steward）
  decided_at:      # 定案时间戳
  decision:        # approved | rejected | deferred
  ---
  ```

## 硬规则

1. 计划只进 `fist-mbt/plan/draft/`（定案后流转 active/done）；完成汇报只进 `reports/`。
2. 未定案（`status != 已定案`）禁止发布任务（`plan_publish` 门禁）。
3. 定案权仅 `human_steward`；agent 只提不定。
4. 临时文件只进 `.fist-mbt/tmp/`，绝不进 `src/`、`docs/`、`plans/`。

## 子目录

| 子目录 | 用途 |
|---|---|
| `plan/draft/`（根） | 在流提案与已定案待执行计划 |
| `plan/active/` | 定案执行中的计划（autoplan finalize 后登记） |
| `plan/done/` | 已完成/已驳回/已推迟的终态计划（原 `docs/plans/archived/`） |
| `plan/decisions/` | 定案记录留痕 |
