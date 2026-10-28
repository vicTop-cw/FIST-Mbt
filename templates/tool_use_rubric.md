# Tool Use Rubric（工具使用硬规则段）

> 用途：pipeline 分支 A 第 4 步「按固定结构撰写」时必须**原样追加**到提示词末尾；
> 目的：降 tool 幻觉——让被驱动的 agent 在调用任何 MCP 工具前有一份**确定性清单**可查，
> 而不是靠记忆猜「这项目有哪些工具、什么时候该调哪个」。
> 硬规则 = 违反即视为执行失败（可被 output_validate 以 `contains` invariant 抓到）。
> 规则段必须**逐字保留**，不得改写、不得删节、不得换行重排。

---

## 一、可用工具清单（只许用这些，未列出的工具一律不得调用）

本项目是 fist-mbt MCP Server，暴露 173 个工具。核心可用工具（按用途分组）：

| 用途 | 工具名 | 说明 |
|---|---|---|
| 任务发布/拆分 | `publish` / `plan` / `task_plan_deep` | 根任务、一层拆分、递归拆解 |
| 领取/执行/验收 | `claim` / `execute` / `submit` / `verify` | 生命周期前向推进 |
| 打回/重试 | `reject` / `retry` / `pause` / `resume` / `reopen_task` | 反向与运维 |
| 依赖与调度 | `dag_depend` / `dag_ready` / `dag_check` / `dag_slack` / `dag_schedule` | DAG 显式边、可领取、依赖满足、松弛分析、排程 |
| 交付验证 | `run_check` / `output_validate` | **L3 测试层 + L4 产物状态层** |
| 缺陷 | `issue_scan` / `report_bug` / `bug_list` / `bug_fix` / `bug_mark_status` | 扫描→上报→修复→销账闭环 |
| 记忆 | `selfdrive_get` / `selfdrive_append` / `memory_consolidate` | 项目记忆读写 |
| 演进 | `evolve_lesson` / `evolve_distill` / `evolve_submit` | 失败回流、蒸馏原则、产物归档 |
| 调度 | `task_triage` / `executor_route` / `dag_cost_route` | 下一步该做啥、能力路由、成本路由 |

**禁止调用**：与上述用途无关的工具、`laya_*`（除非你确实需要 Laya 决策）、`debate_*`（除非你确实要做六顶帽辩论）、
`hat_list`、`mcp_config_scaffold`（那是安装期工具，非开发期）。

## 二、硬规则（违反任何一条 = 本轮执行失败）

1. **先读后写**：修改任何文件前必须先 `read`；不 read 就 write/edit = 违规。
2. **报告不是证据**：任何「已完成」的声明，必须先用 `output_validate` 拿到 L4 产物状态层证据，
   否则不得写「已完成」。`evidence` 字段不得为空且必须指向真实文件路径。
3. **判绿读汇总行，不信 exit 0**：`run_check` / `moon test` 类结果一律看 stdout 的
   `Total tests: N, passed: N, failed: 0` 汇总行；退出码 0 是必要不充分条件（BUG-142）。
4. **路径防御**：所有 `project_dir` / 路径参数只接受相对路径，拒绝绝对路径、`..` 穿越、盘符。
5. **工具名拼写**：MCP 工具名大小写敏感，调错名 = 空回，禁止「换一个名字试试」。
6. **一次只做一个动作**：无人值守定时任务内一次唤醒至多执行一个分支动作，失败即安全退出。
7. **不得自造判据**：`run_check` 的 `cmd` 必须在白名单内（moon/node/python/bash/sh 或项目内相对判据脚本），
   不得传 shell 拼接命令；被拒尝试一律落审计。
8. **失败必须留痕**：任何 `reject` / `report_bug` 必须写清 reason / evidence，不得空 reason。

## 三、执行收尾必做清单（顺序固定）

1. `execute` 记录交付物（`deliverable` 非空，含路径/改动说明）；
2. `output_validate` 对交付物做 L4 检查（`artifacts` 至少一条）；
3. `submit` 提交待验收；
4. 若被 `reject`：先 `read` 打回原因，再 `retry` 重做，重复步 1-3。

---

> 规则段结束标记：`<!-- TOOL_USE_RUBRIC_END -->`。该标记是 `pipeline_has_rubric` 的识别点，
> 任何工具或判据脚本都以它判断「是否已注入」。