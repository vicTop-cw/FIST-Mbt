# 获奖提升 · R51 汇报：看门狗无人值守派发预览

> 日期 2026-09-26 ｜ 字母轮号 R51（deliverable 功能轮第 45 行，测试 +1 → 234）｜ 主题：自治闭环 · 前置信号

## 结果摘要
`watchdog_tick` 在显式 `ns` 的无人值守场景新增 `detail.ready_dispatch_preview`：复用 `engine.triage` 给出一台"下一单可自动派发"的候选 `{task_id, note, hint}`（hint 指明可对这条调 `selfdrive_dispatch`/`schedule` 做能力路由自治派单）。纯读、不自动认领，是完整自治派单的前置可见信号。

## 资源消耗
- 改动：`src/ops/ops_watchdog.mbt`（detail 加 ready_dispatch_preview）、`src/ops/ops_watchdog_test.mbt`（+1 用例）、文档同步 README/AGENTS/deliverable/scoring_rubric 233→234、deliverable §四 45 行、AGENTS watchdog 行。工具数不变（83），测试 233→234。

## 任务分配记录
- 主会话直改 + 单文件测试（ops_watchdog 26/26）+ 全量 234/234 + 三守卫（test_sync/tools_sync/smoke）。

## 遗留风险
- 完整"看门狗自动执行 `selfdrive_dispatch`"仍依赖把 server 进程内 `exec_reg` 派单下沉到 engine 层（跨包注入），属中改、回归风险高；本轮以只读预览落"自治预备信号"，派单下沉作被记录的后置项。
- `ready_dispatch_preview` 仅当显式传 `ns` 时出现（与既有看门狗"未传 ns 不自动续轮"语义一致），不改变既有调用方返回结构语义。

## 后续建议
- 若推完整自治闭环：把 executor 能力路由从 server 进程内 `exec_reg` 迁为 engine 层 store-backed 函数，`watchdog_tick` 即可直接调派单；需配套跨包单测与本轮 preview 一致性回归。
- 本轮 preview 值可作为后续派单的"预演断言"复用。

## 超额内容
- 复用既有 `engine.triage`（支柱②"复用"），不绕开看门狗既有 idle/advanced/restarted 语义（零回归）。

## 来源
- `moon test --target js` 234/234；`mcp_smoke` PASS 83 工具；`check_test_sync --total 234` PASS；`check_tools_sync` PASS；`moon check` 0 错误。

*（内容由AI生成，仅供参考）*