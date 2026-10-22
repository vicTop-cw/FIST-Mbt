# 获奖提升 · R32 能力路由自动派单（selfdrive_dispatch）

> 日期：2026-09-25｜目标：把获奖概率再往上提——先调研、再环视薄弱点，拿来主义 + 更好的 AI 项目管理工具。
> 本轮续接 R31：**82 MCP 工具 + 3 resources + 2 prompts，测试 230/230（Windows + WSL 双端全绿）**。

## 一、调研先行（拿未主义）
- 闭环 R30/R31：`executor_route` 只"推荐"、`selfdrive_pick_next` 按 want 自取——缺"把推荐真正分配出去"的动作。
- 方案：新增 `selfdrive_dispatch`，把 Marketplace 从"建议"升级为"动作"。

## 二、本轮落地
- **新 MCP 工具 `selfdrive_dispatch`**（工具数 82→**83**）：先 `task_triage` 取顶部可领取任务 → 按 `want` 所需能力经 `executor_route` 找最佳执行者（覆盖率 desc→负载 asc）→ **直接 `claim` 给该执行者**（待领取→已领取）；无覆盖匹配回退 `agent`。返回 {dispatched, task_id, assignee, routed, route{best,coverage}}。
- **纯组合、零新表/依赖**：复用 `engine.triage` + `exec_reg.route_pick` + `engine.claim` + `executor_loads` + `sync_db_executors`，单一真源仍在 executor 包。

## 三、结果摘要
| 项 | 值 |
|---|---|
| MCP 工具 | **83**（+1，`selfdrive_dispatch`） |
| 测试 | **`moon test --target js` 230/230**（不变；组合工具由 E2E 覆盖） |
| E2E | `dispatch_verify.py`：登记 exec-DP([编排]) → publish 编排任务 → `selfdrive_dispatch(want=编排)` → routed=true 派给 exec-DP、任务已领取、executor_clear 复位 **MCP-DISPATCH-VERIFY PASS**（tools/list=83） |
| 回归 | 0（纯新增组合工具） |
| 文档 | 全量同步（README/AGENTS/ARCHITECTURE/deliverable/agent-map/USAGE/scripts-README/mcp_smoke/申报书/scoring_rubric/server map） |

## 四、资源消耗
- 工具链：`moon check --target js` / `moon test --target js -j 1` / `moon build --target js cmd/main`；
- 无新增依赖/表；E2E 运行后以 `git checkout -- fist-mbt.db` 恢复交付库 + `cleanup --check` CLEAN。

## 五、任务分配记录
- R32 主代理直做（server 组合工具 + 单工具 E2E），自审三关（typecheck+tests+E2E）。

## 六、遗留风险
- 派单用 `want` 作为所需能力（与 triage 一致）；若任务描述无对应能力标签、也未注册执行者，则退化为自领——符合预期，但"任务→所需能力"的自动抽取列为后续（可接 plan_deep 标注/LLM 提取）。
- 认证安全：`selfdrive_dispatch` 直接向注册执行者认领，适合无人值守流水线；人机混合场景建议配合 reserve_scope 或权限矩阵。

## 七、后续建议（按强度）
1. `watchdog_tick` 无人值守"无活跃任务"分支接 `selfdrive_dispatch`：按能力自动派单续推（把 R26 自驱取单向"能力路由派单"升级）；
2. "任务→所需能力"自动抽取（结合 plan_deep 难度/能力标注），让派单免手传 want；
3. `plan_deep` 深化 LADDER"先生成简单变体再逆推原题"；
4. README CI 徽章实时化（静态 230/230 → workflow 生成）。

## 八、超额内容（相对任务边界）
- 无（专注把 R30/R31 的 Marketplace 落成可动作闭环）。

## 九、来源
- 源码：src/server/server.mbt（selfdrive_dispatch + jstr/jnum 助手）、scripts/dispatch_verify.py。
- 复用之既有原语：engine.triage / engine.claim / executor pkg route_pick。

*（内容由AI生成，仅供参考）*