# R109 汇报：迁移契约检查 tx_contract（Design by Contract 蒸馏 · 101→102 工具 / 295→301 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：兑现 BACKLOG P2「Transactional transition：invariant 失败整笔拒绝、状态 A 回稳」——任何状态迁移动作先过 Meyer 三件套只读预检，任一失败整笔拒绝、状态 A 回稳（不落库）。
- **交付**：新增 1 个 MCP 工具（101→**102**）`tx_contract`：对 (task, action) 只读预检 precondition（复用 Task 迁移语义，Err 即前置失败）/ invariant（IN-1 id 非空 / IN-2 K 值 depth≥1 / IN-3 split_n≥1 / IN-4 身份保持 / IN-5 assignee 纪律）/ postcondition（目标态=文档化目标态）；返回 { ok, task_id, action, phase, verdict, reasons, target_state, state_stable, note }——verdict=rejected 即调用方整笔拒绝、状态 A 回稳。
- **验收**：`engine_contract_test.mbt` **+6**（前置拒绝回稳 / 三件套全通过且只读 / **K 值非法 depth=0 任务 execute：前置过但 IN-2 不变量拒、整笔拒绝回稳** / claim 空 assignee 拒绝 / submit 对称 / reopen on 已归档 拒绝）；全量 **295→301/301**；mcp_smoke **102**；award_demo R109 段 **MCP-AWARD-DEMO PASS**；守卫族 tools(102)/test(301)/badge(301%2F301)/scripts/map 全 PASS；cleanup CLEAN（移除 89 生成物）。

## 二、资源消耗
- 调研：WebSearch 1 轮（DbC Meyer 源流 + PMAT ch59 work-item 契约直接先例）+ 调研档 `memory/research/20260926.transactional-transition.md`（独立调研 commit `64ff3df`）。
- 实现：engine_contract.mbt（新，transition_contract + invariant_violations + 目标态映射）/ engine_contract_test.mbt（新，+6）/ server.mbt（tx_contract 注册 + map 运维行 + server 描述 94→102）/ award_demo.py（R109 段）/ 15 处文档计数与功能轮同步。
- 验证：`moon check` 0 错误、`moon test --target js -j 1` 301/301、mcp_smoke（102）+ award_demo + 守卫族全 PASS、cleanup CLEAN。

## 三、任务分配记录
- R109 属指挥官亲自实现的硬创新轮（与 R92-R108 同模式），未开子任务；调研 commit（64ff3df）与实现轮分开提交。

## 四、遗留风险
- tx_contract 为**只读预检层**：verdict=rejected 时由调用方不执行迁移（状态回稳由"不落库"天然保证）；「allowed」也不落库——正式迁移仍需走既有生命周期工具（编排中间层定位，与 saga/circuit/plan_revise 同抽象层）。
- invariant 均为值级规则（不读库）：父/子一致性等跨任务不变量留待 P3 Runtime monitoring 扩展。
- 与既有非法迁移拦截（Task 方法 Err）功能重叠但语义不同：前者是事后拦截，tx_contract 是事前契约预检（可解释的三件套报告）。

## 五、后续建议
- **R110 候选**：门禁复评确认 R109（第 28 次评估，快照 `_snapshot.md` 已更新为 102/301 + R109 行）。
- 复评 PASS 后硬创新候选：BACKLOG P2 剩余（Evaluator-Optimizer schema / Pre-execution audit gate / moonbitlang/core/diff）或 P1（Agent Contract 7 字段注入 ops_selfdrive）。

## 六、超额内容
- 顺手修正 fist://map server 描述陈旧计数（94→102 工具）与运维组工具串（补 circuit_* + tx_contract）。

## 七、来源
- 调研：`memory/research/20260926.transactional-transition.md`（DbC Meyer 1986/1997 + PMAT ch59 + Gray & Reuter）
- 实现：`src/engine/engine_contract.mbt` / `src/engine/engine_contract_test.mbt` / `src/server/server.mbt`
- 演示：`scripts/award_demo.py` R109 段
- 留痕：`memory/2026-09-25.md` R109 段
