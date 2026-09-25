# vicTop-cw/fist-mbt

FIST 指挥官任务分配体系——纯 MoonBit 实现，同时作为 MCP Server 暴露给 AI 客户端。

## 特性

- **101 MCP 工具**（+3 resources +2 prompts）：任务生命周期（publish/plan/claim/execute/submit/verify/reject/retry 等）、DAG 依赖图与排程家族（dag_slack/dag_mc/dag_cost_route）、自我记忆与自进化（memory_* / evolve_*）、Omega 强验证、多租户命名空间、定时看门狗、审计与权限、可靠性机制（saga 补偿 / plan_revise / goal_drift_check / health_check / circuit_breaker）、调用日志 call_log 与 bug 上报修复闭环。
- **AI 自驱式编程闭环**：审视 → 拆解 → 发布 自收敛，selfdrive_* 系列工具 + watchdog_tick 无人值守。
- **双后端**：JS（默认，MCP server）与 Native（SQLite）均可运行，测试全绿（**295/295**，含 quickcheck 属性测试）。
- **自进化**：memory_consolidate / evolve_distill 把验收通过的任务蒸馏为原则，失败回流为 lesson。

## 依赖

- `mizchi/sqlite@0.3.1`（native 后端）
- `colmugx/mcp@0.17.4`
- `moonbitlang/async@0.22.3`
- `moonbitlang/x@0.5.5`

## 使用

以 MCP Server 方式由 AI 客户端或 CLI 驱动，详见仓库 README.md / README_EN.md 与 docs/。

## 许可

Apache-2.0
