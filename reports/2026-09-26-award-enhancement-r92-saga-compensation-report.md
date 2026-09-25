# R92 汇报：Saga 补偿事务（Garcia-Molina & Salem 1987 蒸馏 · 91→93 工具 / 261→265 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：落地 BACKLOG P3「Saga 补偿事务 + durable action log」——机制设计家族补上"失败补偿"维度：多步骤任务链失败不再卡死/整树重来，按 LIFO 优雅收尾。调研先行（拿来主义，不重复造轮子）：Sagas 1987 SIGMOD 论文锚点 + Temporal/Step Functions/Cadence/DBOS 工业对标。
- **达成**：
  - store_sqlite 新增 `saga_log` 表（append-only，UNIQUE(ns,root_task_id,step)）+ `write_saga_action`（幂等重登记重置 pending）/ `list_saga_actions`（前向序）/ `mark_saga_actions_done`（批量 IN，空 ids 短路）；`clear()` 一并清空；StoreBackend 双后端 dispatch（Mem=no-op）+ engine wrapper ×3。
  - engine_saga.mbt（新）：`saga_register`（登记可补偿动作）/ `saga_rollback`（pending 按 id 倒序=LIFO；mark=true 默认消费标 done 幂等防重复回滚；mark=false 仅预览）。
  - server 注册 `saga_register`/`saga_rollback`（**91→93** 工具，运维组 7→9，fist://map 同步）。
- **验收**：`engine_saga_test.mbt` **+4**；全量 **261→265/265**；mcp_smoke 93 工具；守卫族 tools/test/badge/index 全 PASS（AGENTS/README/deliverable/scoring_rubric 93/265 对齐）；award_demo PASS（结尾 cleanup CLEAN）。

## 二、资源消耗
- 全量 `moon test --target js -j 1`（265/265）+ mcp_smoke（93 工具）+ 守卫族 + award_demo + cleanup。
- 变更：store_sqlite.mbt（saga_log 表 + 3 方法 + clear）/ store.mbt（StoreBackend dispatch +3）/ engine.mbt（wrapper +3）/ engine_saga.mbt（新，编排）/ engine_saga_test.mbt（新，+4）/ server.mbt（2 工具 + map 93/运维 9）/ README/AGENTS/deliverable/USAGE/scoring_rubric/mcp_smoke/BACKLOG（93/265 + Saga 行 done）/申报书（本地）/memory 日志 + 调研档。

## 三、任务分配记录
- R92 属跨层（store/engine/server + 4 测试 + 文档全量同步）行为新增，指挥官亲自做，未开子任务。

## 四、遗留风险
- `saga_rollback` 只"编排"补偿序列、不代执行真实补偿动作（执行器抽象层定位一致）——调用方需按 LIFO 顺序执行补偿并依赖 mark=true 幂等防重复。
- saga_log 仅 SQLite 持久化（Mem 后端 no-op，与心跳表同模式）；增量 schema 旧库首次 open 自动建表。
- 补偿 idempotency 由调用方遵守（补偿动作本身幂等是经典契约，引擎只保证"不重复下发"）。

## 五、后续建议
- 下一候选：门禁复评确认 R92 增量（大改后按纪律复评）；BACKLOG P2「局部补偿替代全局 replanning」（history-aware local compensation，在 saga 基础上控级联）；英文 README（P3 国际受众）。
- 建议把 `--prompt-file` 通道固化进 score_gate.py 默认模板（R91 遗留建议）。

## 六、超额内容
- 无超额（scope 内完成）。

## 七、来源
- `src/store/store_sqlite.mbt` saga_log 表 + write/list/mark_saga_actions（R92）
- `src/engine/engine_saga.mbt` `saga_register`/`saga_rollback`（R92）
- `src/server/server.mbt` saga_register/saga_rollback 工具 + map 同步（R92）
- `src/engine/engine_saga_test.mbt` R92 四用例
- `memory/research/20260926.saga-compensation.md`（R92 调研档：Garcia-Molina & Salem 1987 / Temporal / Step Functions / Cadence / DBOS）
