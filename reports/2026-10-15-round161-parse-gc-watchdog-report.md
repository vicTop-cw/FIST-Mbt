# Round 161 报告 · selfdrive_parse_next_tasks + memory_gc + mcpcf.watchdog

- 日期：2026-10-15
- 提交：无（纯能力验证轮）
- 角色：审视解析 + 记忆归档 + 内嵌看门狗轮

## 结果摘要

### 1. selfdrive_parse_next_tasks（格式调试）

真源 `src/ops/ops_selfdrive.mbt:543`（**并发 agent WIP，只读不写**）：

```
fn selfdrive_parse_next_tasks(content, max_tasks~)
  → 匹配 `## Next Tasks` 段
  → 每行 `- [描述]`（find "]" 后 substring(3, end)）
  → 跳过 `- [x]` / `- [X]` 已完成
```

**格式验证**：
1. `- [ ] 描述`（复选框空格）→ desc=""，count=0 ❌
2. `- [描述]`（无空格）→ 3 条解析成功 ✓
```
selfdrive_parse_next_tasks("...- [补能力试用覆盖矩阵]...")
  → tasks=["补能力试用覆盖矩阵","验证pipeline_tick的prompt_ready分支","核查memory_gc的archive降权"]
  → count=3
```

### 2. memory_gc（记忆上限 + 软降权归档）

```
memory_gc(project_dir=temp/shim-selfdrive, kind=thinking, max_chars=200)
  → gc=true, before_chars=613, after_chars=200
  → archived_to=temp/shim-selfdrive/memory/archive/thinking.archive.md
```

**关键发现**：不硬删，老人条目移入 memory/archive/ 归档保留。

### 3. mcpcf.watchdog（内嵌看门狗）

```
mcpcf.watchdog(ns=shim-review)
  → backend=sqlite, task_count=1
```

**关键发现**：内嵌引擎已识别 T0（R159 run_batch 创建）。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | selfdrive_parse_next_tasks × 4、memory_gc × 1、mcpcf.watchdog × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无（只读 src/ops/ops_selfdrive.mbt） |

## 任务分配记录

- 本会话 Round 161 完成：selfdrive_parse_next_tasks + memory_gc + mcpcf.watchdog 三能力验证。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **R154 提交污染**——已修正纪律，但误提交需与并发 agent 协调。

## 后续建议

1. 剩余未试用能力：selfdrive_publish_next、task_cleanup（谨慎，删除性）、github_flush_plan/queue_status（远端同步，需网络）、mcpcf.circuit。
2. 里程碑（161/256）已覆盖绝大多数 MCP 能力，可补一份「能力试用覆盖矩阵」进 BACKLOG.md。

## 超额内容

- 无（严格限于审视解析 + 记忆归档 + 内嵌看门狗）。

## 来源

- `selfdrive_parse_next_tasks(content)` → 3 条解析成功（格式 `- [描述]`）
- `memory_gc(kind=thinking, max_chars=200)` → 613→200, archived_to=archive/thinking.archive.md
- `mcpcf.watchdog(shim-review)` → task_count=1
