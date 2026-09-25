# 获奖提升 · R30 执行者能力路由（Marketplace/Dynamic 范式雏形）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，拿来主义 + 更好的 AI 项目管理工具。
> 本轮续接 R29：**79 MCP 工具 + 3 resources + 2 prompts，测试 227/227（Windows + WSL 双端全绿）**。

## 一、调研先行（拿来主义）
- 调研蒸馏 `memory/research/ecosystem-borrow.md`：四种 MCP 编排范式中 **Dynamic/Marketplace**（agent 注册能力 + router 按负载/专长分配）此前仅列为远期；
- 现状：`task_triage want` 只是"agent 自选时偏好"，尚未有"系统按专长+负载把任务路由给谁"的原语 → 本轮补齐真正的能力路由。

## 二、本轮落地
- **扩既有 `executor` 抽象（复用，不造轮子）**：`src/executor/registry.mbt` 的 `ExecutorRegistry` 原本只是未接线的 `name→name` map，本轮加：
  - `abilities: Map[String,Array[String]]` + `add_ability`/`abilities_of`（登记/查询能力标签）；
  - 纯函数 `split_need_tags`（逗号/顿号/空格分隔）、`ability_coverage`（命中所需标签/所需标签数 0..1）、`route_pick(need, load)`（按 { 覆盖率 desc → 负载 asc → 名称 asc } 稳定排序）。
- **server 加 2 个 MCP 工具（工具数 79→81）**：
  - `executor_register`：执行者登记能力标签（Marketplace 注册）；
  - `executor_route`：给定任务所需能力 need，从已注册执行者按「能力覆盖率 → 负载」路由最佳执行者；负载 = 各 assignee 名下"非终态"活跃任务数（`executor_loads` 实时统计，进程内内存注册表）。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **81**（+2） |
| 测试 | **`moon test --target js` 227/227**（223→227，+4） |
| E2E | `executor_route_verify.py`：register(exec-A:编排/json, exec-B:编排) → route(编排) 负载均衡到 exec-B / route(json) 专长路由到 exec-A **MCP-EXECUTOR-ROUTE-VERIFY PASS**；mcp_smoke 81 |
| 回归 | 0（纯新增工具；扩既有 ExecutorRegistry 为向后兼容的增量） |
| 文档 | 全量同步（README/AGENTS/ARCHITECTURE/deliverable/agent-map/USAGE/scripts-README/mcp_smoke/申报书/scoring_rubric/server map） |

## 四、资源消耗
- 工具链：`moon check --target js` / `moon test --target js -j 1` / `moon build --target js cmd/main` / `moon info && moon fmt`；
- 无新增依赖/表；纯 MoonBit + 既有 executor 包扩展。

## 五、任务分配记录
- R30 主代理全流程直做（扩 registry + server 两工具 + 单测 + E2E），含自审三关（typecheck+tests+E2E）。

## 六、遗留风险
- 执行者能力注册表为**进程内内存**（复用例 executor 原 in-memory 模式），跨 server 重启不持久——"持久化能力注册（store 新表）"列为后续；单进程 MCP 会话内可完整演示。
- 覆盖率以"标签精确匹配"判，未做同义词/语义泛化；与既有 `evolve_critic`（Jaccard）一致的"精确标签"口径，后续可挂词嵌入。

## 七、后续建议（按强度）
1. **能力注册持久化**（store `executors` 表，双后端）——补上"跨进程可复现"短板；
2. `selfdrive_pick_next` 接 `executor_route`：按"任务所需能力 + 注册执行者负载"自动派单（把推荐真正的"分配"出去）；
3. `plan_deep` 深化 LADDER"先生成简单变体再逆推原题"；挑战题难档在线课程（R-Few/SPICE）；
4. README CI 徽章实时化（静态 227/227 → workflow 生成）。

## 八、超额内容（相对任务边界）
- 顺手修正 README「一键完整自检」里过时的 `Total tests: 220` → `227`（文档即实现扫尾）。

## 九、来源
- 调研：memory/research/ecosystem-borrow.md；既有 executor 抽象 base.mbt/registry.mbt。
- 源码：src/executor/registry.mbt、registry_test.mbt、src/server/server.mbt、scripts/executor_route_verify.py。

*（内容由AI生成，仅供参考）*