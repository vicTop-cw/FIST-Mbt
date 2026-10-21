# R104 汇报：熔断器三态 circuit_fail/succeed/status（Nygard Release It! 2007 蒸馏 · 98→101 工具 / 283→287 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：兑现 BACKLOG P2「Circuit Breaker 三态：Closed/Open/Half-Open 对外部调用快速失败」——外部调用失败不盲目重试，快速失败 + 恢复探测，防级联失败。
- **交付**：新增 3 个 MCP 工具（98→**101**）：`circuit_fail`（Closed 窗口内失败计数达阈值 → Open 记 opened_at / Half-Open 探测失败 → 回 Open）、`circuit_succeed`（Closed 复位 / Half-Open 探测成功 → Closed）、`circuit_status`（Open 且 elapsed≥recovery_secs → 转 Half-Open 放行探测）——返回 `allow_call`（false 即调用方立即 fail-fast）；store 双后端 `circuit_breakers` 表（幂等 upsert + clear 清空）+ engine 纯函数状态机（now_secs Int 规避 engine 无 ops 依赖）。
- **验收**：`engine_circuit_test.mbt` **+4**（Closed 计数达阈值→Open fail-fast / Open 到期→Half-Open→探测成功→Closed / Half-Open 探测失败→回 Open / 窗口外复位+clear）；全量 **283→287/287**；mcp_smoke **101**；award_demo R104 段（fail×3→open→half_open→closed 全环）**MCP-AWARD-DEMO PASS**；守卫族 tools/test/badge/index/map 全 PASS；cleanup CLEAN。

## 二、资源消耗
- 调研：WebSearch 1 轮（Nygard Release It! / Fowler / Azure / AWS / BEE-12001 命中）+ 调研档 `memory/research/20260926.circuit-breaker.md`（独立调研 commit `63abeb6`）。
- 实现：store_sqlite.mbt（表 + cb_get/cb_save + clear）/ store.mbt（StoreBackend 分发）/ engine_circuit.mbt（新，三函数状态机）/ engine_circuit_test.mbt（新，+4）/ server.mbt（三工具 + map 运维行）/ award_demo.py（R104 段）/ 9 文档计数与分组同步。
- 验证：`moon check` 0 错误、`moon test --target js -j 1` 287/287、mcp_smoke + award_demo + 守卫族全 PASS、cleanup CLEAN（移除 84 生成物）。

## 三、任务分配记录
- R104 属指挥官亲自实现（与 R92-R102 同模式的硬创新轮），未开子任务；调研 commit（63abeb6）与实现轮分开提交。

## 四、遗留风险
- 熔断器为"决策原语"（allow_call 指示），不真调外部服务——真实调用的 fail-fast 行为由调用方按 allow_call=false 执行（编排中间层定位，与 saga/plan_revise 同抽象层）。
- now_secs 由调用方（server 经 @ops.iso_to_secs）提供——时钟回拨场景下窗口判定以调用方时钟为准（设计如此）。
- Windows native 竞态等既有已知边界不变（权威门槛 = JS 双端 287/287）。

## 五、后续建议
- **R105 候选**：门禁复评确认 R104（第 26 次评估，快照 `_snapshot.md` 已更新为 101/287 + R104 硬创新）。
- 其余候选：英文 README（P3 国际受众）/ 门禁 cron 化 / BACKLOG P2 剩余（Transactional transition / Evaluator-Optimizer schema / quickcheck 属性测试）。

## 六、超额内容
- 无（标准硬创新轮）。

## 七、来源
- 调研：`memory/research/20260926.circuit-breaker.md`（Nygard Release It! 2007 / Fowler / Azure / AWS / BEE-12001）
- 实现：`src/store/store_sqlite.mbt` / `src/store/store.mbt` / `src/engine/engine_circuit.mbt` / `src/engine/engine_circuit_test.mbt` / `src/server/server.mbt`
- 演示：`scripts/award_demo.py` R104 段
- 留痕：`memory/2026-09-25.md` R104 段
