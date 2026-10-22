# `fist-mbt/plans/` — 计划提案库

这是 fist-mbt 的**计划治理中枢**。所有**计划**必须走这里，禁止再塞进 `reports/`。

## 流程

```
Agent 提案 → plans/*-proposal.md (status: 提案中)
  → 指挥官 human_steward 定案
    → approve → 定案记录写 decisions/ + 发布任务到 fist-mbt DB
    → reject / defer → 计划留档标记状态，不发布任务
  → 执行完成 → 汇报进 fist-mbt/reports/ + 计划移入 archived/
```

## 文件规范

- **文件名**：`YYYY-MM-DD-<topic>-proposal.md`
- **头部强制字段**（缺一即红，`check_plan_location` 守卫）：
  ```yaml
  ---
  status: 提案中   # 提案中 | 已定案 | 已驳回 | 已推迟 | 已完成
  decided_by:      # 定案人（仅 human_steward）
  decided_at:      # 定案时间戳
  decision:        # approved | rejected | deferred
  ---
  ```

## 硬规则

1. 计划只进 `fist-mbt/plans/`；`fist-mbt/reports/` 只放完成汇报。
2. 未定案（`status != 已定案`）禁止发布任务（`plan_publish` 门禁）。
3. 定案权仅 `human_steward`；agent 只提不定。
4. 临时文件只进 `.fist-mbt/tmp/`，绝不进 `src/`、`docs/`、`plans/`。

## 子目录

| 子目录 | 用途 |
|---|---|
| `plans/`（根） | 在流提案与已定案待执行计划 |
| `plans/decisions/` | 定案记录留痕 |
| `plans/archived/` | 已完成/已驳回/已推迟的终态计划 |
