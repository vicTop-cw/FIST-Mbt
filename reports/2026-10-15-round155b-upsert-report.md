# Round 155 续 · selfdrive_pick_next + supervisor_task_upsert

- 日期：2026-10-15
- 提交：memory/links.md（R151 memory_link 产物）
- 角色：无人值守取单 + 终态拒改轮

## 结果摘要

### 1. selfdrive_pick_next（按能力自动取下一单）

```
selfdrive_pick_next(namespace=shim-review)
  → picked="", remaining=0, claimed=false
  → note=无可领取的推荐任务（待领取且依赖已满足集合为空）
```

**关键发现**：shim-review 全部任务已归档，无待领取任务，correct。

### 2. supervisor_task_upsert（终态拒改）

```
supervisor_task_upsert(project_dir=temp/shim-selfdrive, items=[{task_id:T0r609, description:"Round 155 更新…"}])
  → total=1, ok_count=0
  → results=[{task_id:T0r609, ok:false, error:"终态任务 [已归档] 拒改；请走 reopen_task 或重新发布"}]
```

**关键发现**：终态任务拒改——防篡改审计轨迹，走 reopen_task 才能改。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | selfdrive_pick_next × 1、supervisor_task_upsert × 1、pwsh × 1 |
| 提交 | memory/links.md |
| 触碰并发 WIP | 无（用 pathspec 严格隔离） |

## 任务分配记录

- 本会话 Round 155 完成：selfdrive_pick_next + supervisor_task_upsert。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **R154 提交污染**——已修正纪律，`.mcp.dev.json` 与 `src/router/router_caf.mbt` 已被误提交，需与并发 agent 协调。

## 后续建议

1. 剩余未试用能力：pipeline_tick（无人值守流水线）、selfdrive_append/review_tick/publish_next、task_cleanup（谨慎）、memory_gc（记忆上限+降权归档）。
2. 里程碑（155/256）已覆盖绝大多数 MCP 能力，可补一份「能力试用覆盖矩阵」进 BACKLOG.md。

## 超额内容

- 无（严格限于无人值守取单 + 终态拒改）。

## 来源

- `selfdrive_pick_next(shim-review)` → picked="", remaining=0
- `supervisor_task_upsert(T0r609)` → 终态拒改
