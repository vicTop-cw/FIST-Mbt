# Round 153 报告 · project_standards + supervisor_prompt 引导管道

- 日期：2026-10-15
- 提交：无（纯能力验证轮）
- 角色：规范投影 + 引导提示词轮

## 结果摘要

### 1. project_standards（AI 项目开发规范机器投影）

```
project_type = moontbit_mcp
version      = R116
canonical_doc = AI-DEVELOPMENT-STANDARD.md
```

**5 条通用规则**：
- r1 文档即实现（hard）
- r2 一源四态单真源（hard）
- r3 确定性优先于语义性（hard）
- r4 增量零回归（hard）
- r5 自我迭代（medium）

**5 条 FIST 专项**：
- f1 必须使用 FIST 自身能力迭代（hard）
- f2 四态必须对齐 MCP/CLI/Skill/Plugin（hard）
- f3 证据梯至少 L4（hard）
- f4 重任务先拆 DAG（medium）
- f5 工具命名即文档（medium）

**7 项四态 checklist**：
- cl1 MCP 工具注册（hard）
- cl2 CLI 封装到位（hard）
- cl3 skill 文档写了（hard）
- cl4 moon test 全绿（hard）
- cl5 output_validate L4 硬门 pass（hard）
- cl6 README/AGENTS 计数同步（medium）
- cl7 四宿主插件态重生成且一致（hard）

### 2. supervisor_prompt_inject → list → consume

```
supervisor_prompt_inject(target=shim-steward, prompt="Round 153 引导…")
  → id=sg-1, queued=true

supervisor_prompt_list(target=shim-steward)
  → count=1, items=[{id:sg-1, consumed:false}]

supervisor_prompt_consume(guidance_id=sg-1)
  → consumed=true
```

**关键发现**：
- 引导队列进程内保存 + call_log 双写（跨进程可回读、幂等）。
- 目标 agent 用 `supervisor_prompt_consume` 取走并标记已消费（重复调用不重复返回）。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | project_standards × 1、supervisor_prompt_inject × 1、supervisor_prompt_list × 1、supervisor_prompt_consume × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 153 完成：project_standards + supervisor_prompt 引导管道。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **DGM 8 条 dead_ends（score=0）**——外部资产未真正使用。

## 后续建议

1. 剩余未试用能力：pipeline_tick（无人值守流水线）、selfdrive_*（自驱会话）、supervisor_task_upsert（任务列表更新）、task_cleanup（归档清理，谨慎）、memory_gc（记忆上限+降权归档）。
2. 里程碑（153/256）已覆盖绝大多数 MCP 能力，可补一份「能力试用覆盖矩阵」进 BACKLOG.md。

## 超额内容

- 无（严格限于规范投影 + 引导管道）。

## 来源

- `project_standards(project_type=moontbit_mcp, include_checklist=true)` → 10 规则 + 7 checklist
- `supervisor_prompt_inject(target=shim-steward, prompt=…)` → sg-1 queued
- `supervisor_prompt_list(target=shim-steward)` → count=1, consumed=false
- `supervisor_prompt_consume(guidance_id=sg-1)` → consumed=true
