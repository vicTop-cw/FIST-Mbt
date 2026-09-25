# 获奖提升 · R68 项目健康卡 project_health 汇报

> 日期 2026-09-26 ｜ R68 ｜ 主题：新增工具 · 单次调用看全项目健康（工具数 83→84）

## 结果摘要
新增 `project_health` MCP 工具：单次调用聚合六类状态计数（in_flight/ready/done/blocked/reviewing/archived）+ 健康等级（empty/attention/stalled/healthy）+ blocked_tasks 详情，可 namespace 过滤。正中支柱①"agent 一眼看全项目健康，不用逐条 list"。**测试 241→242（+1），工具 83→84，全守卫/map_verify/冒烟 PASS**。

## 资源消耗
- `board_ascii.mbt` + `render_project_health` 纯函数；`server.mbt` 注册工具；`board_ascii_test.mbt` +1 用例。工具数同步到 84（README/AGENTS/deliverable/scoring_rubric + AGENTS 看板组 + scripts/README + deliverable §四 51 行）。

## 任务分配记录
- 主会话直改 + 全量验证（中任务）。

## 验收标准 → 实测
- 功能：健康卡聚合 + 等级判定正确 → **通过**（空=empty、有进行=healthy、已暂停=attention 且 blocked_tasks 含该任务）。
- 工具可用：tools/list 84 工具 + project_health 注册 → **通过**（mcp_smoke 84、tools_sync PASS）。工具计数文档全同步 → **通过**。
- 无回归：全量 242/242，badge/test_sync/scripts_index/map_verify PASS，cleanup 洁净 → **通过**。

## 遗留风险
- 健康等级为启发式（有阻塞→attention，无进行无就绪→stalled），未接成本/门禁实时状态；如需"全量健康评分"可后续并入 gate/clean 子卡。

## 后续建议
- 可把 `project_health` 并入 `status_summary` 文档对照与 `fist://map` 说明，形成"脉冲+健康卡"双视图。根底为空时"进化"。
- 概率门禁未随工具数变动重跑（新工具为只读增强，非关键路径改）；下次大改连带复评。

## 超额内容
- 无。