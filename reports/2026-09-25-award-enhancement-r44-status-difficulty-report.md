# 获奖提升 · R44 汇报：status_summary 难度分布 by_difficulty

> 日期 2026-09-25 ｜ 字母轮号 R44（deliverable 功能轮第 41 行）｜ 主题：复用 · 一目了然

## 结果摘要
`status_summary` 项目脉冲新增 `by_difficulty:{易/中/难/无:数量}`，统计"待领取"任务的难度结构。`extract_difficulty` 升为 pub 供 server 包复用（支柱②"能复用则复用"），agent 一次调用既看状态分布又看待办难度结构（支柱①"一目了然"）。未加工具、测试计数不变（233/83）。

## 资源消耗
- 改动：`src/engine/engine.mbt`（`extract_difficulty` pub）、`src/server/board_ascii.mbt`（`render_status_summary` 增 `by_difficulty`）、`src/server/server.mbt`（工具描述）、`src/server/board_ascii_test.mbt`（延展用例加不变量）；文档 AGENTS / deliverable §四 41 行。
- 时间：单轮闭环。

## 任务分配记录
- 主会话直改 + 单元测试不变量（各难度档数量之和 == 待领取任务数）+ `mcp_smoke`/`check_badge` 回归。

## 遗留风险
- `by_difficulty` 仅统计"待领取"状态；其它状态任务的难度未纳入（符合"待办难度结构"语义，非缺陷）。
- `extract_difficulty` 依赖描述中的 `[难度梯度 …]` 标记，未拆解（无梯度）的任务归入"无"。

## 后续建议
- 大项单一真源化仍是首选大项：把 AGENTS/deliverable/fist://map 的分组与轮表做成单一数据源 + CI 校验。
- 可让 `board_ascii` 看板也标注每行难度，进一步贴合"一目了然"。

## 超额内容
- 不变量断言锁住 by_difficulty 与待领取计数的一致性，防未来逻辑回归。

## 来源
- `moon test --target js` 233/233；`mcp_smoke.py` PASS 83 工具；`check_badge.py` PASS。

*（内容由AI生成，仅供参考）*