# 获奖提升 · R36 项目地图 fist://map 全量同步（agent 首读即有地图）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，第一支柱"结构化项目（地图一目了然）"。
> 本轮续接 R35：**83 MCP 工具 + 3 resources + 2 prompts，测试 230/230（Windows + WSL 双端全绿）**。

## 一、调研先行（审计缺口）
- `fist://map` 资源是 agent 首读定位的最重要入口，但其 `tool_groups` 仍停留在老分组：缺 **看板/脉冲/预订/推荐+DAG**、自驱缺 `selfdrive_pick_next`、记忆缺 `evolve_critic/lesson/task_challenge`、**`Marketplace·能力路由`（executor_* / selfdrive_dispatch）整组缺失**——直接违背"让每个 agent 有地图、别全项目去找"。

## 二、本轮落地
- **同步（纯 JSON 地图，零代码/计数变化）**：`src/server/server.mbt::fist://map::tool_groups` 补全到当前 **83 工具 / 10 大分组**（生命周期/查询/运维/看板·脉冲·预订·推荐+DAG/自驱/记忆与自进化/Marketplace·能力路由/审计权限/多租户/强验证），与 AGENTS/agent-map 分组对齐。
- `map_verify.py` 追加断言锁住（缺 Marketplace / 看板分组即 FAIL），防"地图又过时"回归。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **83**（不变） |
| 测试 | **`moon test --target js` 230/230**（不变） |
| E2E | `map_verify.py` **MCP-MAP-VERIFY PASS**（tool_groups=10 组，含 Marketplace·能力路由/看板·脉冲） |
| 回归 | 0（纯资源文案同步） |
| 文档 | 无计数涟漪 |

## 四、资源消耗
- 工具链：`moon check --target js` / `moon build --target js cmd/main` / `moon test --target js -j 1` / `map_verify.py`；无新增依赖。

## 五、任务分配记录
- R36 主代理直做（地图 JSON 补全 + map_verify 断言），自审两关（typecheck+tests && map_verify PASS）。

## 六、遗留风险
- `fist://map` 与 AGENTS/agent-map 三处分组为人工维护，仍有漂移窗口；把三处改为"单一真源自动生成"列为后续（可抽取共享分组定义）。
- tool_groups 为"精选分组"，辅助工具（cost_stats/bug_* 等）未逐一列全；明示"完整清单见 AGENTS/fist://map"。

## 七、后续建议（按强度）
1. `watchdog_tick` 无人值守接 `selfdrive_dispatch`（完成自驱闭环）；
2. 把"更简单变体→本体"做成显式 DAG 前置依赖（`dag_depend`）；
3. 地图分组单一真源化（消除 AGENTS/agent-map/fist://map 三处人工同步）。

## 八、超额内容（相对任务边界）
- 无。

## 九、来源
- 源码：src/server/server.mbt（`fist://map` tool_groups）、scripts/map_verify.py（断言）。

*（内容由AI生成，仅供参考）*