# Round 146 报告 · Saga 补偿 + dispatch 续跑

- 日期：2026-10-15
- 提交：无（纯能力验证轮）
- 角色：Saga 补偿轮 + dispatch 续跑轮

## 结果摘要

### 1. saga_register（补偿登记）

```
root_task_id   = T0r611
step           = unit-1-boundary-analysis
task_id        = T0r611.1.2
compensation   = 若 T0r611.1 整体回滚，把已完成交付物作废 + Omega 记录标 invalid + 恢复到待领取
status         = pending
registered     = true
```

**关键发现**：
- 幂等：同 (ns, root_task_id, step) 重登记重置为 pending 并刷新 compensation（重试安全）。
- 补偿描述是**业务逆转动作**（非逆向操作）。

### 2. saga_rollback(mark=false) — LIFO 预览

```
root_task_id   = T0r611
lifo           = true
pending_count  = 1
pending        = [{id:54, step:unit-1-boundary-analysis, task_id:T0r611.1.2, status:pending}]
marked_done    = 0（预览不消费）
```

**关键发现**：mark=false 只预览不消费（幂等，重复调用仍返回 pending 步骤）。

### 3. saga_repair(mark=false) — 局部补偿切片

```
root_task_id   = T0r611
failed_step    = unit-1-boundary-analysis
basis          = depends_on
compensate_count = 1
keep_count     = 0
compensate     = [{id:54, step:unit-1-boundary-analysis}]
keep           = []
marked_done    = 0
note           = 局部补偿（控级联）：仅补偿受影响切片，切片外保留承诺不补偿
```

**关键发现**：
- `basis=depends_on`：失败步骤 + 其依赖下游（传递闭包中仍 pending 的步骤）。
- `keep` 保留切片外步骤承诺（控级联不涟漪撤销）。
- 与 `saga_rollback` 全局 LIFO 整链收尾互补。

### 4. dispatch 续跑 T0r611.2.1

```
selfdrive_dispatch(namespace=shim-review)
  → dispatched=true, task_id=T0r611.2.1, assignee=ops-steward
  → want=shim（自动抽取）, coverage=1
```

完整 Omega 生命周期：
```
omega_spec_create  → spec:T0r611.2.1:r1
omega_spec_review  → approved
execute            → 交付泛化抽象评估
submit             → 待验收
omega_result_verify → result:T0r611.2.1:r1 approved
verify             → 已完成 ✓
```

### 5. 交付物内容（T0r611.2.1 · 泛化抽象）

```
(1) 三件通用能力：
    - 透明代理（请求/响应透传）
    - 兜底 stub（吸收可选方法）
    - 幂等 _meta 注入（任何 MCP 版本行为一致）
(2) 四项配置化：
    - FIST_SERVER_PATH（server 路径）
    - FIST_SHIM_TIMEOUT_MS（超时）
    - FIST_SHIM_STDERR（stderr 开关）
    - FIST_SHIM_DEBUG（debug 日志）
(3) 泛化验证：
    - 三档 protocolVersion（2025-06-18 / 2024-11-05 / 2026-07-28）
    - 10 检查全 PASS + 20 并发 20/20
```

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | saga_register × 1、saga_rollback × 1、saga_repair × 1、selfdrive_dispatch × 1、omega_spec_create × 1、omega_spec_review × 1、execute × 1、submit × 1、omega_result_verify × 1、verify × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 146 完成：saga_register/rollback/repair + T0r611.2.1 dispatch + Omega 生命周期。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **T0r611 剩 1 叶子未完成**（T0r611.2.2）。

## 后续建议

1. T0r611.2.2 可用相同 dispatch + Omega 流程续跑，形成完整闭环。
2. saga_repair 与 plan_revise 互补：plan_revise 是"计划三分"（keep/rework/ready），saga_repair 是"补偿切片"（compensate/keep）——前者管计划修订，后者管执行回滚。

## 超额内容

- 无（严格限于 Saga 补偿 + dispatch 续跑）。

## 来源

- `saga_register(T0r611, step=unit-1-boundary-analysis)` → registered=true, status=pending
- `saga_rollback(T0r611, mark=false)` → lifo=true, pending_count=1
- `saga_repair(T0r611, failed_step=unit-1-boundary-analysis, mark=false)` → compensate=1, keep=0
- `selfdrive_dispatch(namespace=shim-review)` → T0r611.2.1, assignee=ops-steward
