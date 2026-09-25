# R98 汇报：反馈驱动计划修订 plan_revise（ReAct 2210.03629 / CoPAL 2310.07263 蒸馏 · 95→96 工具 / 273→277 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：兑现 BACKLOG P2「Interleaved 分支」——据子任务执行反馈回退改 plan，而非拆完即弃；把"拆完即弃"升级为"执行中持续修订"（Plan-and-Execute 计划在失败下变陈旧，由 interleaved revision 修复）。
- **交付**：新增 MCP 工具 `plan_revise`（95→**96** 工具）：给定根任务及子任务执行反馈，计算计划三分——**keep**（已证有效、承诺保留）/ **rework**（失败或其依赖链受牵连需返工，控级联不涟漪）/ **ready**（依赖全部有效且未执行，下一步可做）。feedback 缺省读真实状态（已完成/已归档=ok、已打回/已暂停=否、其余=未证）；传 [{task_id, ok}] 显式覆盖。纯计算、只读不写库（决策建议，执行权在 agent/指挥官，与 saga 返回补偿序列同一抽象层）。
- **验收**：`dag_ext_test.mbt` **+4**（status 基础 keep/rework 级联 / ready+feedback 覆盖 / feedback no 级联 / 根不存在 ok:false）；全量 **273→277/277**；mcp_smoke **96**；award_demo R98 段（basis=status ready=4）**MCP-AWARD-DEMO PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 调研：WebSearch 1 轮（ReAct/CoPAL/规划模式对比命中）+ 调研档 `memory/research/20260926.plan-revise.md`（独立调研 commit `a79f670`）。
- 实现：engine_dag_ext.mbt（+plan_revise）/ dag_ext_test.mbt（+4）/ server.mbt（工具注册 + map 看板行）/ award_demo.py（R98 段）/ 9 文档计数与分组同步。
- 验证：`moon check` 0 错误、`moon test --target js -j 1` 277/277、mcp_smoke + award_demo + 守卫族全 PASS、cleanup CLEAN（移除 80 生成物）。

## 三、任务分配记录
- R98 属指挥官亲自实现（与 R92/R94/R96 同模式的硬创新轮），未开子任务；调研 commit 与实现轮分开提交，便于留痕追溯。

## 四、遗留风险
- `plan_revise` 的 rework 判定含"未开工但依赖链受牵连"的下游（与 saga_repair 依赖者闭包同构）——语义为"该条执行链需重做"，调用方需结合真实返工成本决策（设计如此，非缺陷）。
- feedback 显式覆盖优先于读状态——若反馈与真实状态矛盾，以反馈为准（调用方责任）。
- Windows native 竞态等既有已知边界不变（权威门槛 = JS 双端 277/277）。

## 五、后续建议
- **R99 候选**：门禁复评确认 R98（第 23 次评估，快照 `_snapshot.md` 已更新为 96/277 + R98 硬创新）。
- 其余候选：P2「全局目标校验（non-redundancy，每子任务完成后校验是否偏离根目标）」/ 英文 README（P3 国际受众）/ 门禁 cron 化（`--prompt-file` 通道一条命令可用）。

## 六、超额内容
- 无（标准硬创新轮；R97 复评确认已在上一提交完成）。

## 七、来源
- 调研：`memory/research/20260926.plan-revise.md`（ReAct arXiv 2210.03629 / CoPAL arXiv 2310.07263 / OpenLegion 规划模式对比）
- 实现：`src/engine/engine_dag_ext.mbt` / `src/engine/dag_ext_test.mbt` / `src/server/server.mbt`
- 演示：`scripts/award_demo.py` R98 段
- 留痕：`memory/2026-09-25.md` R98 段
