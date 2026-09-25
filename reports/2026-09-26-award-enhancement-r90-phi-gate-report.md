# R90 汇报：概率式看护闭环 watchdog phi_gate（R89 原语 → 运行时行为）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：接续 R89，把 phi_accrual 从"独立原语"升级为"运行时行为"——心跳间隔历史持久化 + watchdog 端到端 φ 判活（默认关闭零回归），可靠性线程闭环：原语→持久化→运行时看护。
- **达成**：
  - store_sqlite 新增 `heartbeat_history` 表（每任务保留最近 1000 条）+ `write_heartbeat_interval`/`list_heartbeat_intervals`（时间序读回）+ `clear()` 一并清空；StoreBackend 双后端 dispatch（Mem=no-op）；engine wrapper ×2。
  - server `heartbeat` 工具每次上报自动算间隔落库（@ops.iso_to_secs，可解析且 >0 才记）。
  - ops_heal 新增 `heal_stale_tasks_by_phi`：读持久化间隔历史 + elapsed → `@engine.phi_accrual` 判 suspect 才回滚；从未心跳沿用 no_signal；无历史/不可解析/时钟回拨保守不判。
  - ops_watchdog `watchdog_tick` 加 `phi_gate`（默认 false 零回归）+ `phi_threshold`（默认 8）；server 工具 schema/handler 同步 + 顺带透传 autodispatch/autodispatch_want（R57 能力此前 MCP 不可达）。
- **验收**：`ops_watchdog_test.mbt` **+2**（间隔史写入/时间序读回/clear 清空；phi_gate 对照：静默 100s、间隔 [5,5,5]、固定 timeout 600 不判 vs φ≈8.686>8 判死回滚）；全量 **259→261/261**（+2）；守卫族 tools/test/badge/index/map 全 PASS；mcp_smoke 91 工具（计数不变，行为增强）；cleanup CLEAN。

## 二、资源消耗
- 全量 `moon test --target js -j 1`（261/261）+ mcp_smoke（build 后 91 工具）+ 守卫族 + cleanup。
- 变更：store_sqlite.mbt(新表+2 方法+clear) / store.mbt(StoreBackend dispatch+2) / engine.mbt(wrapper+2) / ops_heal.mbt(heal_stale_tasks_by_phi) / ops_watchdog.mbt(phi_gate/phi_threshold+detail) / ops_watchdog_test.mbt(+2) / server.mbt(heartbeat 间隔落库 + watchdog_tick schema/handler) / README/AGENTS/USAGE(watchdog_tick 行)/deliverable(R60)/BACKLOG(Phi 行全 done)/scoring_rubric(261)/申报书(§6 补 51 行)/memory 日志。

## 三、任务分配记录
- R90 属跨层（store/engine/ops/server）行为增强 + 2 测试，指挥官亲自做，未开子任务。

## 四、遗留风险
- phi_gate 默认关闭（零回归）；开启时无间隔历史的任务保守不判（等有历史再判），可能延迟一轮判活——可接受，避免误伤。
- 间隔历史仅 SQLite 持久化（Mem 后端 no-op，与心跳表同模式）；heartbeat_history 表为增量 schema，旧库首次 open 自动建表。

## 五、后续建议
- 下一候选：英文 README（P3 国际受众）、门禁复评确认 R87-R90 增量、或新调研线程（如 Saga 补偿事务 / 可编程 Omega invariant，BACKLOG P3）。

## 六、超额内容
- 顺带把 R57 `autodispatch`/`autodispatch_want` 在 MCP watchdog_tick 工具暴露（此前引擎支持但 MCP 不可达，默认 false 零回归）——属能力可达性修复，无行为变化。

## 七、来源
- `src/store/store_sqlite.mbt` heartbeat_history 表 + write/list_heartbeat_interval（R90）
- `src/ops/ops_heal.mbt` `heal_stale_tasks_by_phi`（R90）
- `src/ops/ops_watchdog.mbt` watchdog_tick phi_gate/phi_threshold（R90）
- `src/server/server.mbt` heartbeat 间隔落库 + watchdog_tick schema/handler（R90）
- `src/ops/ops_watchdog_test.mbt` R90 两用例
- `memory/research/20260926.reliability-phi-accrual.md`（R89 调研档，R90 兑现"watchdog 端到端接入"后置项）
