# R100 汇报：全局目标校验 goal_drift_check（goal drift 2505.02709 / Repetitiveness 2603.12710 蒸馏 · 96→97 工具 / 277→280 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：兑现 BACKLOG P2「全局目标校验（non-redundancy）」——每子任务完成后校验是否偏离根目标（drift）或与兄弟重复（重复造轮子），让"拆得出来"升级为"拆得对、不跑偏、不重复"。
- **交付**：新增 MCP 工具 `goal_drift_check`（96→**97** 工具）：根目标词法 vs 子任务词法 → **drift = 1 - jaccard > 0.7 判 drift_suspect**（附 `re_anchor` 提示：把根目标重新注入，防 context drift 渐失原始目标）；与任一兄弟 jaccard ≥ 0.7 判 **redundant_suspect**（防重复子目标，HiMAP uniqueness monitor）。词法 Jaccard 纯计算，复用 `@evolve.tokens/jaccard` 单真源（R13 critic 词法提升 pub），零 LLM 自评（贴"评测是计算"原则）。subtask_id 缺省校验根下全部后代；纯计算、只读不写库。
- **验收**：`dag_ext_test.mbt` **+3**（aligned/drift_suspect 附 re_anchor / redundant_suspect+subtask_id 过滤 / 根不存在 ok:false）；全量 **277→280/280**；mcp_smoke **97**；award_demo R100 段（aligned=0 drift_suspect=9）**MCP-AWARD-DEMO PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 调研：WebSearch 1 轮（goal drift 2505.02709 / Repetitiveness 2603.12710 / IntentCUA 2602.17049 / HiMAP ICML2026 命中）+ 调研档 `memory/research/20260926.goal-drift-check.md`（独立调研 commit `3e7305c`）。
- 实现：evolve.mbt（tokens/jaccard pub）/ engine_dag_ext.mbt（+goal_drift_check）/ dag_ext_test.mbt（+3）/ server.mbt（工具注册 + map 看板行）/ award_demo.py（R100 段）/ 9 文档计数与分组同步。
- 验证：`moon check` 0 错误（修 2 处：4139 嵌套 match 值位置 / subtask 标签名）、`moon test --target js -j 1` 280/280、mcp_smoke + award_demo + 守卫族全 PASS、cleanup CLEAN（移除 80 生成物）。

## 三、任务分配记录
- R100 属指挥官亲自实现（与 R92/R94/R96/R98 同模式的硬创新轮），未开子任务；调研 commit（3e7305c）与实现轮分开提交，便于留痕追溯。

## 四、遗留风险
- 词法 Jaccard 对中文按字符去重——对语义漂移是近似信号（非语义精确判定）；阈值 0.70 与 critic 同口径，误报时调用方结合真实上下文裁决（设计如此，决策权在 agent/指挥官）。
- subtask 与兄弟全同字符集（如顺序互换）会判 redundant_suspect——保守防重复，符合 non-redundancy 意图。
- Windows native 竞态等既有已知边界不变（权威门槛 = JS 双端 280/280）。

## 五、后续建议
- **R101 候选**：门禁复评确认 R100（第 24 次评估，快照 `_snapshot.md` 已更新为 97/280 + R100 硬创新）。
- 其余候选：英文 README（P3 国际受众）/ 门禁 cron 化（`--prompt-file` 通道一条命令可用）/ BACKLOG P2 剩余（quickcheck 属性测试 / 多维度健康指标 / Circuit Breaker 三态）。

## 六、超额内容
- `@evolve.tokens`/`jaccard` 提升 pub——跨包复用的必要开放（单真源不新造），R13 critic 词法成为引擎可复用资产。

## 七、来源
- 调研：`memory/research/20260926.goal-drift-check.md`（goal drift arXiv 2505.02709 / Repetitiveness Rate arXiv 2603.12710 / IntentCUA arXiv 2602.17049 / HiMAP-Travel ICML 2026 / Zylos 综述）
- 实现：`src/evolve/evolve.mbt` / `src/engine/engine_dag_ext.mbt` / `src/engine/dag_ext_test.mbt` / `src/server/server.mbt`
- 演示：`scripts/award_demo.py` R100 段
- 留痕：`memory/2026-09-25.md` R100 段
