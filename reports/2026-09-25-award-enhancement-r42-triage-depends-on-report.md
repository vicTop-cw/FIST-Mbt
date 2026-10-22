# 获奖提升 · R42 汇报：task_triage 携带真实 DAG 依赖 depends_on

> 日期 2026-09-25 ｜ 字母轮号 R42（deliverable 功能轮第 39 行）｜ 主题：复用 / 拿来主义 · DAG→推荐纵向闭合

## 结果摘要
`task_triage` 每条推荐任务新增 `depends_on` 输出：复用 R39 建的 DAG 依赖边（`dag_depend`/`gradient_dag`），让"下一单"推荐不止看难度/优先级，还能看到它就绪的前驱是谁。落实用户支柱②"能复用则复用、避免重复造轮子"——直接复用既有点，不另造存储/解析。

## 资源消耗
- 改动：`src/engine/engine_triage.mbt`（`TriageRow.depends_on` + JSON 输出）、`src/engine/engine_triage_test.mbt`（+1）；文档 README/AGENTS/deliverable/scoring_rubric 232→233 同步，deliverable §四 补 39 行。未加工具（83）。
- 时间：单轮闭环（实现→测试→文档→提交→推送）。

## 任务分配记录
- 主会话直改 + 单元测试。测试设计经一次打回修正（首版用 gradient_dag 子树完成制复杂且子叶也有链依赖易错；改双根 + `dag_depend` 更确定：依赖未满足即不在推荐 → 前驱完成后入推荐且 `depends_on=[A]`）。

## 遗留风险
- triage 只列出"依赖已满足"的任务，故 `depends_on` 在推荐结果里语义是"该任务就绪依赖的前驱"（通常为已完成集）；若评审把 `depends_on` 误读为"仍待完成"，需注意该字段表达的是就绪前驱而非待办依赖。未来可补 `deps_pending` 显式区分。

## 后续建议
- 可给 `suggestion.reason` 追加"就绪前驱 {depends_on}"，进一步增强"AIO 推荐为何此刻可行"的可解释性。
- 大项：把 AGENTS/deliverable/fist://map 的分组与轮表做成单一真源并 CI 校验，根除人工维护漂移（项目整洁支柱的架构性项）。

## 超额内容
- 测试覆盖"DAG 未满足不入推荐 / 满足后入推荐且带 depends_on"双向，证明 triage 与 DAG 真实协同而非表面字段。

## 来源
- `moon test --target js` 233/233；`check_badge.py` PASS；`mcp_smoke.py` PASS 83 工具。

*（内容由AI生成，仅供参考）*