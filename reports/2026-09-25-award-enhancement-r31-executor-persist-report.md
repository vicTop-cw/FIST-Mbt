# 获奖提升 · R31 执行者能力注册持久化（跨进程可复现）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，拿来主义 + 更好的 AI 项目管理工具。
> 本轮续接 R30：**81 MCP 工具 + 3 resources + 2 prompts，测试 230/230（Windows + WSL 双端全绿）**。

## 一、调研先行（拿来主义）
- 闭环 R30 明确遗留："执行者能力注册为进程内内存、跨 server 重启不持久"。
- 方案：让能力注册与既有 `reserve_*` / `evolve` 一样落库（镜像 reservations 双后端模式，不造新范式）。

## 二、本轮落地
- **store 层新增 executors 表**（双后端）：
  - `executors(name, abilities_json, created_at)`；`executor_save`（`ON CONFLICT DO UPDATE` 幂等）/ `executor_list` / `executor_clear`；
  - SqliteStore + MemoryStore + `StoreBackend` 统一调度；`clear()` 一并清空（防测试/scratch 残留，对齐 R11）。
- **engine**：`executor_save/list/clear` 透传（存/取/清，路由纯计算仍在 executor 包单真源）。
- **server 三工具**（工具数 81→**82**）：
  - `executor_register` 登记时持久化；
  - `executor_route` 启动先 `sync_db_executors()` 回灌持久化注册（跨进程可复现）；
  - **新 `executor_clear`**：清空全部注册（Marketplace 重置/整洁）。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **82**（+1，`executor_clear`） |
| 测试 | **`moon test --target js` 230/230**（227→230，+3 store 双后端） |
| E2E | `executor_route_verify.py` 跨进程三段：进程A 注册 exec-RJX → 进程B（全新）路由读到并命中 → `executor_clear` → 进程C 不再见 **MCP-EXECUTOR-ROUTE-VERIFY PASS**（tools/list=82，不建任务零污染） |
| 回归 | 0（新增工具 + 新表；既有 tool 语义不变） |
| 文档 | 全量同步（README/AGENTS/ARCHITECTURE/deliverable/agent-map/USAGE/scripts-README/mcp_smoke/申报书/scoring_rubric/server map） |

## 四、资源消耗
- 工具链：`moon check --target js` / `moon test --target js -j 1` / `moon build --target js cmd/main` / `moon info && moon fmt`；
- 无新增依赖；store 新增一表（复刻 reservations 模式）。

## 五、任务分配记录
- R31 主代理全流程直做（store 双后端 + engine 透传 + server 三工具 + 单测 + 跨进程 E2E），自审三关（typecheck+tests+E2E）。

## 六、遗留风险
- 执行者负载仍按"indata 活跃 assignee"粗算（未细分执行中/暂停）；能力匹配为精确标签（未做语义泛化）——远期为词嵌入悬挂点到；
- 能力注册持久化到默认引擎 store；多租户命名空间若需各自市场，列为后续（当前引擎为单一实例）。

## 七、后续建议（按强度）
1. `selfdrive_pick_next` 接 `executor_route`：按"任务所需能力 + 已注册执行者负载"自动派单（把推荐真正"分配"出去）——R30/R31 的 Marketplace 闭环落到动作；
2. `plan_deep` 深化 LADDER"先生成简单变体再逆推原题"；挑战题难档在线课程（R-Few/SPICE）；
3. README CI 徽章实时化（静态 230/230 → workflow 生成，减少手工同步）。

## 八、超额内容（相对任务边界）
- 顺手把 R30 的 E2E 从"内存演示 + 负载均衡"重构为"跨进程持久化三段"，让评审一条命令看到 Market 的真实"可复现 + 可重置"。

## 九、来源
- 源码：src/store/store_sqlite.mbt、store.rsv→store.mbt(MemoryStore/dispatch)、src/store/executor_store_test.mbt、src/engine/engine_executor.mbt、src/server/server.mbt、scripts/executor_route_verify.py。

*（内容由AI生成，仅供参考）*