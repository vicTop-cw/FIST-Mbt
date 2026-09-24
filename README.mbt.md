# vicTop-cw/fist-mbt

FIST 指挥官任务分配体系——纯 MoonBit 实现，同时作为 MCP Server 暴露给 AI 客户端。

## 特性

- **61 MCP 工具**：任务生命周期（publish/plan/claim/execute/submit/verify/reject/retry 等）、DAG 依赖图、自我记忆与自进化、Omega 强验证、多租户命名空间、定时看门狗、审计与权限。
- **AI 自驱式编程闭环**：审视 → 拆解 → 发布 自收敛，selfdrive_* 系列工具。
- **双后端**：JS（默认，MCP server）与 Native（SQLite）均可运行，测试全绿。
- **自进化**：memory_consolidate / evolve_distill 把验收通过的任务蒸馏为原则。

## 依赖

- `mizchi/sqlite@0.3.1`（native 后端）
- `colmugx/mcp@0.17.4`
- `moonbitlang/async@0.21.0`
- `moonbitlang/x@0.4.40`

## 使用

以 MCP Server 方式由 AI 客户端或 CLI 驱动，详见仓库 README.md 与 docs/。

## 许可

Apache-2.0