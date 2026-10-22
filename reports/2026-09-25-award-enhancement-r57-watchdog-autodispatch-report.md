# 获奖提升 · R57 看门狗自治派单接入（watchdog_tick + autodispatch → dispatch_next）汇报

> 日期 2026-09-26 ｜ 字母轮号 R57（deliverable 功能轮第 48 行，测试 +2 → 239）｜ 主题：自治闭环闭环 · 无人值守自动派单

## 结果摘要
把 R56 的引擎层 store-backed 派单 primitive（`FistEngine::dispatch_next`）接入 `watchdog_tick`，
显式 ns 无人值守且无活跃任务时，看门狗即可按能力/负载把待领取任务自动认领给最佳执行者——
"该派哪单即可自动派给谁"这条自治链路首次全打通。**测试 237 → 239（+2），三守卫 PASS，mcp_smoke 83 工具，moon check 0 错误**。

## 资源消耗
- 改动面极小：仅 `src/ops/ops_watchdog.mbt`（watchdog_tick 加 `autodispatch`/`autodispatch_want` 参数 +
  idle 分支调 `dispatch_next`，`detail` 由 `let` 改 `var`）与 `src/ops/ops_watchdog_test.mbt`（+2 用例）。
- 文档同步：README/AGENTS/deliverable/scoring_rubric 237→239；deliverable §四 补 48 行。
- 验证：`moon test --target js -j 1` 239/239；check_badge / check_test_sync / check_tools_sync 全 PASS；mcp_smoke PASS。

## 任务分配记录
- 主会话直改 + 单文件测试（R57 2/2）+ 全量 239/239 + 三守卫 + 文档同步（未起子代理，属轻任务）。

## 验收标准 → 实测
- 功能：watchdog_tick 支持自动派单，默认关闭零回归 → **通过**（autodispatch=false 不认领不改动回归确认）。
- 能力路由：正例按 `autodispatch_want` 命中 store 注册执行者 worker-57 并认领 → **通过**。
- 文档即实现：四文档测试总数 239 全量一致 → **通过**；工具数 83 不变 → **通过**。

## 遗留风险
- `route_pick` 对空 want 走 cover=0 的名称/负载兜底且注册表来自 Map 迭代顺序不确定；
  故自动派单需调用方显式传 `autodispatch_want` 才能稳定路由，空 want 时回退语义依赖兜底（已实测不崩溃）。
- Windows native 竞态等既有边界不变（JS 后端为权威稳定门槛）。

## 后续建议
- 可进一步把 `autodispatch_want` 从任务描述自动抽取（复用 executor_route R33 的免手传思路），做到真正"零参数自动派单"。
- 自治闭环已闭环，下一轮可转向三支柱其余薄弱点（项目整洁 / 复用 / 地图）或推进评审节点（4 AI 打分、申报书、演示脚本）。

## 超额内容
- 无（严格按任务包边界交付）。