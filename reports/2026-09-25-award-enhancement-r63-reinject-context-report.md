# 获奖提升 · R63 父计划回注（plan_deep reinject_context）汇报

> 日期 2026-09-26 ｜ R63 ｜ 主题：先调研后落地 · ReCAP 借鉴的递归拆解上下文增强

## 结果摘要
按目标"先调研，再落地"：派研究子代理调研 AI PM/递归拆解/项目地图库与论文（Reflexion/ReCAP/Reflection Pattern/repomap-mcp/Flux），识别三个候选增量中最贴合本项目的「父计划回注」——它避免与既有 Omega 强验证/selfdrive 重叠（弃做雷同的 self_review LMM 自验以减少工具冗余）。落地：`plan_deep` 增 `reinject_context=false`（默认关闭零回归），子任务描述携带「父计划 + 剩余兄弟」，递归下钻整树继承。**测试 240 → 241（+1），全守卫 PASS，mcp_smoke 83 工具**。

## 资源消耗
- 调研：1 研究子代理（网络搜索，~中成本）。
- 实现：`src/engine/engine.mbt`（plan_deep 增参 + decompose_rec 贯通含递归 + 子任务注入）与 `decompose_test.mbt`（+1 用例）；`src/server/server.mbt`（task_plan_deep 增 `reinject_context` 参数透传，工具数仍 83）。
- 文档：README/AGENTS/deliverable/scoring_rubric 240→241；deliverable §四 50 行；AGENTS task_plan_deep 行。

## 任务分配记录
- 调研 → 研究子代理；实现/验证/文档 → 主会话（轻-中任务）。

## 验收标准 → 实测
- 功能：开启 reinject_context 子任务描述含「父计划+剩余兄弟」且下钻孙代继承 → **通过**。
- 零回归：默认不传时描述不含父计划标记 → **通过**（+1 red/green 用例）。
- 可用性：MCP task_plan_deep 暴露参数 → **通过**；工具数不变 83 → **通过**。
- 文档即实现：四文档 241 全对齐、AGENTS tool 行、deliverable §四 50 行 → **通过**。

## 遗留风险
- 父计划描述较长时子任务描述偏长（可接受，默认关闭不受影响）；回注未做长度截断，极端长父描述下描述会较长。
- 概率门禁未重跑（本能力偏向 p1 创意生态意向的软增强，非关键路径，留待下次门禁一并复评）。

## 后续建议
- 将「父计划回注」纳入 showcase/award_demo 演示链，让评审一眼看到"递归拆解知道为什么做"。
- 若需再抬 p1，可继续吸收调研清单其余项（如 focus_tasks 就绪看板），或把本次调研沉淀为 memory/research 增量。

## 超额内容
- 无。