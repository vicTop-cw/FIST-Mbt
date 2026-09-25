# 获奖提升 · R56 汇报：引擎层自治派单 primitive（dispatch_next）

> 日期 2026-09-26 ｜ 字母轮号 R56（deliverable 功能轮第 47 行，测试 +2 → 237）｜ 主题：自治闭环 · 派单下沉 engine

## 结果摘要
把"给执行者派单"下沉到 engine 层做成 `FistEngine::dispatch_next`：取 triage 顶部可领取任务 → 读 store 持久化的执行者能力注册（`executor_list`）→ 复用 executor 包 `route_pick`（单真源路由）按「能力覆盖 → 负载」路由最佳执行者 → 直接认领给该执行者（无注册回退 agent）。纯增量、零回归，不经 server 进程内 `exec_reg`——是"看门狗自动派单"的地基；本轮只落 engine primitive 与单测，未起 watchdog。

## 资源消耗
- 新文件：`src/engine/engine_dispatch.mbt`、`src/engine/engine_dispatch_test.mbt`（+2 用例）；改动：`src/engine/moon.pkg`（+executor 依赖，叶包无循环）。文档同步 README/AGENTS/deliverable/scoring_rubric 235→237、deliverable §四 47 行。工具数不变（83），测试 235→237。

## 任务分配记录
- 主会话直改 + 单文件测试（dispatch 2/2）+ 全量 237/237 + 三守卫 PASS。

## 遗留风险
- `dispatch_next` 目前未被任何工具/看门狗调用（是待接入的 primitive 而非上线的派单动作）；接入 watchdog_tick 需再一步 + 跨包单测，属可被证伪的后续项。
- 能力路由的 need 现取调用方 `want`；若需免手传自动抽取，可续 R33 的 `auto_need` 思路（此处留作后续）。
- abilities_json 解析用朴素 String 数组解析，与 server 端 `ab_from_jsonstr` 是同语义的双实现；为彻底避重复，后续可把该解析也收拢到 executor 包（单真源），本轮先落 engine 侧最小实现。

## 后续建议
- 把 `dispatch_next` 接入 `watchdog_tick`（显式 ns + autodispatch 开关），并加"跨进程 store executor + watchdog 自动派单"E2E——这是自治闭环的最后一步；得益于本轮 engine-backed 改写，server 进程内 exec_reg 不再是障碍。
- 把 abilities_json 解析收拢到 executor 包单一来源，彻底去重。

## 超额内容
- 实证"派单下沉不依赖 server 进程内 exec_reg"：executor 为叶包、engine 可直读 store 执行者，推翻了我此前"中改/跨包耦合高"的顾虑——本轮即为此前冻结项的真正解冻。

## 来源
- `moon test --target js` 237/237；`dispatch_next` 单测 2/2；三守卫 PASS；`moon check` 0 错误。

*（内容由AI生成，仅供参考）*