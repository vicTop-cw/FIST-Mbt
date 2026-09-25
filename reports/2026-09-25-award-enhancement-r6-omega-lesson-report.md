# 获奖提升 · 第 6 轮汇报：Omega 打回自动落 [lesson] 教训

> 日期：2026-09-25｜目标：获奖概率再往上提｜推进方式：fist-mbt 自驱式（引擎行为增强，非新 MCP 工具）

## 结果摘要
把"失败回流学习"从**手动**（需人工调 `evolve_lesson`）升级为**自动**：Omega 的三条打回路径
（语料审核打回、成果复验打回、超限升级转人工）在打回时由引擎自动把失败原因沉淀为 `[lesson]` 资产入 DGM，
供 plan/claim 的 inject 与 dead_ends 检索"踩过的坑"——把"会犯错"从黑盒变成可演绎的护城河。
测试 **200/200** 全绿，E2E `omega_lesson_verify.py` PASS，已推送 `c741150`。

> 补：**闭环修正**——第 6 轮自动回流仅落 DB（engine 侧），而 `inject`/`dead_ends`/`evolve_snapshot` 只读内存 `evolve_arc`，同进程内不可见。已加 server 私有 `sync_db_lessons` 把 DB `[lesson]` 经 `Artifact::from_json`+`Archive::add` 回灌进内存 arc（幂等），并钩到 `inject` 入口与 `evolve_snapshot`；wbtest + E2E 断言 dead_ends 进程内可见。测试 → **201/201**。

## 关键改动
- `src/engine/evolve_auto_wire.mbt`（新）：`FistEngine::omega_auto_lesson`——打回即落 [lesson]。
- `src/engine/omega_strong.mbt`：spec_review / result_verify 打回分支 + escalate 超限升级 自动调用，返回体带 `learned_lesson`。
- `src/evolve/lesson.mbt`（新）：`lesson_goal`/`lesson_ts_part`/`score_of_lesson`/`evolve_lesson_persist`——**单一真源**。
- `src/store/store.mbt`：`StoreBackend::sqlite_store` 提取 sqlite 句柄，突破 engine→server 循环依赖。
- `src/server/evolve_lesson.mbt`：独立工具改为复用 evolve 包同一落库语义。
- 边界修正：lesson id 纳入 `cat`，修复同一时间戳下 spec 与复验打回 id 冲突被 upsert 覆盖丢史。

## 复用一个性（拿来主义）
未新造教训机制：统一走 `evolve_lesson_persist` → `store.evolve_upsert`（既有），server 与 engine 两条路径共用。

## 资源消耗
代码 +481/-79；新增 1 条集成测试（199→200）；无新增依赖/MCP 工具。

## 任务分配记录
引擎行为增强 + 单测 + E2E 证据脚本 + 文档同步（README/AGENTS/ARCHITECTURE/deliverable/申报书 199→201）。

## 遗留风险
- evolve_artifacts 落库走 `engine.store`（根库），`store_open(scratch)` 仅隔离任务路由、不隔离 evolve 写入；已在 E2E 中按本脚本原因精确清理根库；进程内可见性已由 sync_db_lessons 补齐（跨进程/多 ns 彻底隔离待后续如需再定）。

## 后续建议
- 下一候选中期项：`declare` 强契约 / `@fs.tmpdir` 系统临时目录 / 多 ns 下 evolve 写入隔离。

## 来源
`git log 7eb57a3..c741150`；`scripts/omega_lesson_verify.py`；`src/{engine,evolve,store,server}/*.mbt`。