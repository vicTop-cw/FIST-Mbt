# Round 135 报告 · cost_budget_split + DAG 调度视图实测

- 日期：2026-10-15
- 提交：无（纯读诊断）
- 角色：运维验证轮 + 调度分析轮

## 结果摘要

### 1. cost_budget_split 实测

```
stages:
  level 0: 2079 tasks, difficulty_sum=2973, share=87%
  level 1:  155 tasks, difficulty_sum=285,  share=8%
  level 2:   63 tasks, difficulty_sum=175,  share=5%
  level 3:    6 tasks, difficulty_sum=12,   share=0%
  level 4:    1 tasks, difficulty_sum=3,    share=0%
total_budget=100, makespan=4, verdict=ok
scope: whole-store, 2304 tasks
```

**关键发现**：全库 2304 任务，level 0 占 87%（瓶颈层），预算集中在此。makespan=4。

### 2. dag_critical_path 实测

```
critical_path = T0r581.1 → .2 → .3 → .4 → .5
length = 5
```

### 3. dag_slack 实测

```
makespan = 4
critical = T0r581.1 ~ T0r581.5（关键路径）
大部分任务 slack = 4（earliest=0, latest=4，无松弛瓶颈）
```

### 4. 命名空间诊断

用 `get` 查关键路径根任务 `T0r581`：

```
namespace = fist-allmodes
project_dir = .
description = 【模式 1/7 · advance 推进】对本项目（zhi 编译器）做一轮持续开发推进...
depth = 3, status = 拆分中
```

**并发 agent 的批在 `fist-allmodes` 命名空间**（zhi 编译器项目），与我的工作（default + scripts/memory）完全隔离。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | cost_budget_split × 1、dag_critical_path × 1、dag_slack × 1、get × 1、pwsh × 1 |
| 提交 | 无 |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 135 完成：cost_budget_split + DAG 调度视图实测。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产 `asset-mcp-compat-2026-10-15T05:05:01Z`。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **BUG-161/163 内建修复未提交**。

## 后续建议

1. 并发 agent 的批在 `fist-allmodes`——如要派任务给我自己，用 `namespace=fist-allmodes` 或独立 ns，不要污染 default。
2. `cost_budget_split` 适合重任务拆解前的预算规划。

## 超额内容

- 无（严格限于调度诊断）。

## 来源

- `cost_budget_split` → 2304 任务，level 0 占 87%
- `dag_critical_path` → T0r581.1→.5 length 5
- `dag_slack` → makespan=4，大部分 slack=4
- `get(T0r581)` → namespace=fist-allmodes，zhi 编译器项目
