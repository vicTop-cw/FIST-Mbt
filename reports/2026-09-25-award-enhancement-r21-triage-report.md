# 获奖提升 · R21 汇报：下一步该做啥（task_triage，推荐式挑选原语）

> 日期：2026-09-25｜目标 pillar：计划性增强（更好的 AI 项目管理工具）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮新增 1 个 MCP 工具 `task_triage`（77→78）。

## 结果摘要
- 补一个"更好的 AI 项目管理工具"真正缺的**推荐原语**：`dag_ready`/`board_ascii` 只"列出"可领取任务，不"推荐"。新增 `task_triage`——对指定命名空间把『待领取且依赖已满足』的任务按 **优先级(高>中>低)→重要度(高>中>低)→深度(叶可执行单元优先)→id** 排行，并给出一条 `suggestion`（此刻建议先领哪条及理由），agent 无需全量扫描即知下一单。
- 落点（纯 MoonBit，无新表/依赖）：[engine_triage.mbt](../src/engine/engine_triage.mbt)（`FistEngine::triage` + 排序/难度标签纯函数）；[server.mbt](../src/server/server.mbt) 注册 `task_triage`。
- **复用（避免造轮子）**：难度标签直接复用 plan_deep gradient 嵌入描述的 `难度梯度 i/n:易/中/难`（未命中按 叶(可执行)/分支 兜底）；判定复用 `deps_satisfied`/`get_status().is_pending()`；排序即纯函数。
- **语义校准**：triage 与 status_summary/board 共用 `engine.list_all()`（当前生效命名空间的集合），`namespace` 参数在该集合内过滤（与既有工具语义一致）。
- 验证：`moon test --target js` **218/218**（+2）；`award_demo.py` 加第 ⑨ 步 task_triage（可领取 12 条、suggestion 指向）**MCP-AWARD-DEMO PASS** + 结尾 CLEAN；`mcp_smoke.py` **78 工具 PASS**。

## 资源消耗
- 新增：`src/engine/engine_triage.mbt`、`src/engine/engine_triage_test.mbt`；修改 `src/server/server.mbt`、`scripts/award_demo.py`、`scripts/mcp_smoke.py`(expected 78) + 相关 `.mbti`。
- 测试：+2 条单测。
- 文档：工具 77→78、测试 216→218 全量同步（README/AGENTS/ARCHITECTURE/USAGE/deliverable/agent-map/scripts-README/申报书/server map 78）；AGENTS 看板/脉冲/预订/推荐+DAG(11)→(12) 补 `task_triage`；deliverable/申报书补 R20 行。

## 任务分配记录
- 直接实现（指挥官终审制）：小规模新原语（复用既有判定/标签）；实机验证（moon test 218/218 + award_demo ⑨ PASS + mcp_smoke 78）。中途发现 list_all 只返回 default_ns，据此校准测试语义并复用该集合，未改 store 层。

## 遗留风险
- `namespace` 参数语义为"在当前生效命名空间集合内过滤"（与 status_summary/board 一致），不支持跨库聚合；如需跨库排行需另起有 engine 级 ns 切换的接口。
- 难度标签依赖 gradient 标记或兜底（叶/分支），对未走 plan_deep 的任务只有兜底档。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **把 `task_triage` 的 suggestion 接进自驱/看门狗**（让无人值守流水线"按推荐取单"而非固定顺序）；
  2. **Marketplace / Dynamic 能力路由**（远期，executor 抽象层朝"能力注册 + 按负载/专长分配"——triage 的"按能力匹配"是雏形）；
  3. **CI 三轨道徽章复核**。

## 超额内容
- `task_triage` 的"优先级×重要度×难度"排行可作为日后 Marketplookup 路由排序的公共基础。

## 来源
- 前置：`dag_ready`（engine_dag_ext）、`plan_deep gradient`（R12/R17）、`status_summary`（R8/R9）。
- 代码：`src/engine/engine_triage.mbt`、`src/server/server.mbt`、`scripts/award_demo.py`、`src/engine/engine_triage_test.mbt`。