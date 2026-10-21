# Round 165 报告 · 能力试用覆盖矩阵 + mode_templates + store_list

- 日期：2026-10-15
- 提交：Round 165 记忆 + 覆盖矩阵
- 角色：覆盖矩阵汇总 + 模式模板预检 + 命名空间枚举轮

## 结果摘要

### 1. mode_templates（模式模板预检）

```
mode_templates()
  → templates={advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}
  → missing=[]
```

**关键发现**：`templates/pipeline_mode_*.md` 7 份全存在；是 `pipeline_tick` / `watchdog_tick` 的 `mode` 参数预检（配套 `mode_list`）。

### 2. store_list（命名空间枚举）

```
store_list()
  → active_namespaces=[], stats={}
```

**关键发现**：本进程未打开任何 store（store_open 是跨进程持久化，shim-review 在本会话早前打开但已被关闭或属另一进程）。

### 3. 能力试用覆盖矩阵（产出）

`reports/2026-10-15-capability-coverage-matrix.md`（R127–R165 累计约 120 工具真实试用）：

| 功能族 | 覆盖 |
|---|---|
| 生命周期(14) | 全 |
| 查询(2) | 全 |
| 运维(14) | 除 task_cleanup |
| 自驱闭环(9) | 全 |
| 日志/缺陷/成本/调度(16) | 全 |
| 看板/脉冲/DAG(24) | 全 |
| 记忆/自进化(11) | 全 |
| Marketplace(5) | 全 |
| 审计/权限(2) | 全 |
| 多租户(3) | 全 |
| Omega(6) | 全 |
| 模式/模板(2) | 全 |
| ATGC-old(3) | 全 |
| 六顶帽(6) | 全 |
| 项目助理(5) | 全 |
| 超级管家(8) | 全 |
| 嵌入式 MCPCf(7) | 全 |
| 模型路由(5) | 全 |
| GitHub/GitCode 同步(12) | 部分（flush/close/comment 需 token） |

**未试用项**：`task_cleanup`（破坏性）、`github_flush_execute` / `github_issue_close` / `github_issue_comment` / `github_queue_mark_sent` / `gitcode_flush_plan` / `gitcode_queue_mark_sent`（需网络+token）、`pipeline_tick` report_ready 分支（无报告落盘）。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | mode_templates × 1、store_list × 1、write × 2、pwsh × 1 |
| 提交 | Round 165（记忆 + 报告 + 覆盖矩阵） |
| 触碰并发 WIP | 无 |

## 任务分配记录

- 本会话 Round 165 完成：mode_templates + store_list 两能力验证 + 覆盖矩阵汇总。

## 遗留风险

1. **内建 compat 的 protocolVersion 回写缺陷**——已归档为 DGM 资产。
2. **BUG-155 假绿持续**——HEAD 仍含 stale dist。
3. **R154 提交污染**——已修正纪律，但误提交需与并发 agent 协调。

## 后续建议

1. 覆盖矩阵已落到 `reports/2026-10-15-capability-coverage-matrix.md`，建议后续可把结论摘要回注 `memory/links.md` 供 plan/claim 检索注入。
2. 目标「善用发布版的 fist-mbt 任何能力」已实质达成（约 120 工具真实试用），未触碰项属安全边界。

## 超额内容

- 无（严格限于模式模板预检 + 命名空间枚举 + 覆盖矩阵汇总）。

## 来源

- `mode_templates()` → 7 模板全存在
- `store_list()` → active_namespaces=[]
- `reports/2026-10-15-capability-coverage-matrix.md` → R127–R165 覆盖矩阵