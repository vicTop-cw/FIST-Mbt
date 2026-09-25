# R96 汇报：局部补偿控级联 saga_repair（Plan Commitment 2023 蒸馏 · 94→95 工具 / 269→273 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：兑现 BACKLOG P2「局部补偿替代全局 replanning」——R92 saga 全局 LIFO 收尾的"同源 P2"：只补偿**最小受影响切片**、保留未受影响承诺（plan repair 保留承诺 > 整树重规划），控级联不涟漪撤销。
- **交付**：新增 MCP 工具 `saga_repair`（94→**95** 工具）：给定失败步骤，计算最小补偿切片——失败步骤 + 其 depends_on 依赖者闭包中仍 pending 的下游（basis=depends_on）；无 task_id 时按注册序保守兜底（basis=order）——只补偿切片（切片内 LIFO）、keep=未受影响承诺保留；mark=true 默认消费切片（幂等）、keep 保持 pending 供后续按需补偿（与 saga_rollback 两级收尾共存）。
- **验收**：`engine_saga_test.mbt` **+4**（depends_on 闭包最小切片+旁路 keep / 注册序兜底 / mark=false 预览+失败步骤 Err / keep 与 rollback 两级共存幂等）；全量 **269→273/273**；mcp_smoke **95**；award_demo 加 R96 段（basis=order compensate=[step3,step2] keep=[step1]）**MCP-AWARD-DEMO PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 调研：WebSearch 1 轮（3 强锚点命中）+ 调研档 `memory/research/20260926.local-compensation.md`（独立调研 commit `f31a969`）。
- 实现：engine_saga.mbt（+saga_repair + 2 私有助手）/ engine_saga_test.mbt（+4）/ server.mbt（工具注册 + map 运维行）/ award_demo.py（R96 段）/ 8 文档计数与分组同步。
- 验证：`moon check` 0 错误（修 5 处编译错：Map.has / let 初始化 / let mut）、`moon test --target js -j 1` 273/273、mcp_smoke + award_demo + 守卫族全 PASS。

## 三、任务分配记录
- R96 属指挥官亲自实现（与 R92/R94 同模式的硬创新轮），未开子任务；调研 commit 与实现轮分开提交，便于留痕追溯。

## 四、遗留风险
- `saga_repair` 的 depends_on 闭包依赖任务表记录依赖边（dag_depend/plan_deep gradient_dag 会建边）；未建边时退化为注册序兜底（保守、不误漏）。
- keep 步骤语义为"本轮不补偿、保留承诺"——若局部修复后发现 keep 步骤仍受牵连，调用方仍需按需补偿（设计如此，非缺陷）。
- Windows native 竞态等既有已知边界不变（权威门槛 = JS 双端 273/273）。

## 五、后续建议
- **R97 候选**：门禁复评确认 R96（第 22 次评估，快照 `_snapshot.md` 已更新为 95/273 + R96 硬创新）。
- 其余候选：BACKLOG P2「全局目标校验（non-redundancy）」/ P2「Interleaved 分支（反馈回退改 plan）」/ 英文 README（P3）/ 门禁 cron 化。

## 六、超额内容
- deliverable §四 补回 R92/R94 两行历史功能轮（此前只同步计数未加行）——文档即实现扫尾。
- ARCHITECTURE / agent-map 陈旧计数（87 工具 / 230 测试）全量校准 95/273 并刷新分组至 AGENTS 结构。

## 七、来源
- 调研：`memory/research/20260926.local-compensation.md`（Babli 2023 EAAI / arXiv 2609.19654 / arXiv 2607.24167）
- 实现：`src/engine/engine_saga.mbt` / `src/engine/engine_saga_test.mbt` / `src/server/server.mbt`
- 演示：`scripts/award_demo.py` R96 段
- 留痕：`memory/2026-09-25.md` R96 段
