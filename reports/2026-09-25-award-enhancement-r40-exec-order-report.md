# 获奖提升 · R40 汇报：「执行计划视图」（task_plan_deep 新增 exec_order）

> 日期 2026-09-25 ｜ 字母轮号 R40（deliverable 功能轮第 38 行）｜ 主题：结构化 / 计划性增强 · 一目了然

## 结果摘要
`task_plan_deep` 返回新增顶层 `exec_order`：拆解后即给出整棵子树的**按 DAG 拓扑序、附难度档/依赖/深度的扁平执行清单**，agent 拿到即可照单执行。纯读、无副作用、未加工具（83 不变）、默认零回归。与 R39 的 `gradient_dag` 协同——真实依赖 + 可见可执行的顺序，把"先易后逆推"落到实处。

## 资源消耗
- 改动文件：`src/engine/engine.mbt`（`plan_exec_order` + `find_sub_chars`/`extract_difficulty` 辅助）、`src/server/server.mbt`（`task_plan_deep` 输出附 `exec_order`）、`src/engine/decompose_test.mbt`（+1）；文档 README/AGENTS/deliverable/scoring_rubric 231→232 同步，deliverable §四 补第 38 行。
- 时间：单轮闭环（调研→实现→测试→文档→提交→推送）。

## 任务分配记录
- 主会话直改 + 单元测试；工程约束（guard/match 冒号换行、Char 数组扫描避免 index_of/substring 签名坑）已遵循。

## 遗留风险
- `plan_exec_order` 的 `children_of` 每次全表扫描，超大树/海量任务下 BFS 有性能放大；当前规模与测试语义下可接受，后续可在 store 层加按 parent 索引优化。
- Windows native 偶发竞态（既有，非本改动引入）。

## 后续建议
- 把 `gradient_dag` + `exec_order` 并入 `award_demo.py` 演示段，让评审一条命令看到"拆解→真实 DAG→执行计划照单执行"完整链。
- `extract_difficulty` 可复用于 `task_triage`/`board_ascii` 展示难度档，避免重复解析。

## 超额内容
- 执行清单附带每任务 `status`，计划视图可当轻量进度快照用。

## 来源
- git HEAD 本轮提交；`moon test --target js` 232/232；`check_badge.py` PASS；`mcp_smoke.py` PASS 83 工具。

*（内容由AI生成，仅供参考）*