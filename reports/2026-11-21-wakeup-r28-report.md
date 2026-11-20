# 2026-11-21 唤醒巡检 R28 报告 — BUG-636 状态推进（A 面半在飞）+ 换面巡检两尺绿 + T0r3 闭环

- 轮次：R28（Windows 计划任务 FIST-Mbt-ExploreWatchdog 唤醒，findings-only 非阻塞巡检）
- 前序：[R27 报告](2026-11-21-wakeup-r27-report.md)（T0r2 闭环 + EP-03 四层死链定案）
- 模式：fist-commander；本轮**未改任何跟踪面代码**（原因见 §五）

## 一、结果摘要

| # | 事项 | 结论 |
|---|---|---|
| 1 | 并发 WIP | f094 收口方**仍在飞且活跃**：39 文件 M 面 + 6 项未跟踪；`src/server/tool_cov_query_tools_test.mbt` mtime **今天 02:40**——全程避让零接触 |
| 2 | **BUG-636 状态推进** | **A 面半在飞**：对方 WIP 测试文件标题即「BUG-455『外壳零覆盖』清零轮」，补的正是 `check_tool_coverage` 实跑点名工具；**判据接线半仍未认领**（§三） |
| 3 | 落账复核（r315 遗留） | 账本最大号 **648**；`BUG-636` 已被 vq 外来账（MinGW，FIXED）占用 ⇒ FIST 侧条目落账须用 **≥649 新号** |
| 4 | 换面巡检 | 两尺全绿：`check_bug_ledger_shape` 自检 12/12 + 本体 PASS；`check_ps_encoding` 自检 OK + 本体 PASS（§四） |
| 5 | 判据三红 | 未复跑——R26/R27 已定案归属 EP-03 收口方，修复落点 `scripts/README.md` 在他方 WIP 内，复跑无新信息 |
| 6 | BUG-32 新鲜度 | 不触发（产物 03:33:54 > 最新源 02:40:03）⇒ FIST 链 6 秒全绿 |
| 7 | FIST 闭环 | **T0r3 六步首发即全绿**（r27 记坑的 `--namespace`/`--assignee` 已内置链脚本，零补跑，§六） |

## 二、并发 WIP 与提交面

- `git log --oneline` 头部与 R27 相同：`7ecb4ce68`（R27 报告）为新 HEAD，本轮无新提交。
- M 面 39 文件：f094 多管家/worktree-dispatch 收口（`src/server/server.mbt` +150 行、`wt_tools.mbt`、`src/store/store_sqlite*.mbt`、`scripts/run_guards.py` +6、`scripts/README.md`、`plugins/**`、`docs/**`、`README*`/`USAGE.md`/`AGENTS.md`、`.github/workflows/release.yml` 等）。
- 未跟踪 6 项：`src/server/tool_cov_query_tools_test.mbt`（**02:40**）/ `tool_cov_wt_async_test.mbt`（昨晚 22:59）/ `reports/2026-11-20-tnr-ascend-round2-report.md` / `.trae-html-share-packages/` / `_moonbit_兼容性反馈.txt` / `website/`。
- `scripts/check_tool_coverage.py` **不在** M 面（无他方改动，但本轮仍不动它——接线须与 `run_guards.py` 锚点同批，见 §五）。
- 本轮落盘面仅三处：本报告（唯一提交物）+ `temp/fist_r28_chain.sh` / `temp/fist_r28_tid.py` / `temp/fist_r28_chain.log`（temp 面不提交）。

## 三、BUG-636 状态推进（本轮核心发现）

r315 立账的判据缺陷（`check_tool_coverage` 是 `_tool_registry` 真源第 6 个未接线消费者，漏扫 18 工具/7 个零覆盖）本轮复核：**接线仍未发生**（`grep _tool_registry scripts/check_tool_coverage.py` 零命中），但出现了**归属新证据**：

1. **A 面半（修复规格第 2/3 条：补外壳测试）正由 f094 收口方活跃执行**。两份未跟踪测试文件的文件头自述：
   - `tool_cov_query_tools_test.mbt`：「BUG-455『外壳零覆盖』清零轮 · 查询面三件套的接线锁」，覆盖 `task_events` / `task_query` / `task_stats`；
   - `tool_cov_wt_async_test.mbt`：同标题，覆盖 `wt_dispatch` / `wt_collect`（async 实现行为锁）。
   两份都**逐字引用了 `scripts/check_tool_coverage.py` 实跑点名**这一口径——即对方是按**旧扫描面（165 口径）**在补测。
2. **因此接线半（规格第 1 条：`extract_tools()` 委托 `real_tools()`）+ 收口半（第 5 条：加进 `_tool_registry.consumers()`）仍未被认领**——对方的补测清单是旧扫描面的输出，**不含** `mcpcf.report/review/run_batch/verify` 与 `supervisor_prompt_consume/inject/list` 这 7 个盲区工具。
3. **推论（交接风险）**：接线落地瞬间，这 7 个工具将**新暴露为零覆盖**，按 BUG-455 先例须同批登记 known-red 或补测转正——收口轮执行接线时若只改判据不做这一步，CI 当场半红（r315 规格已预警）。**不能假设「对方会顺带做接线」**：其清零轮的验收口径是旧扫描面清零，与本缺陷无交集。

## 四、换面巡检读数（两尺，均避开 WIP 足迹）

| 判据 | 自检 | 本体 | 覆盖面说明 |
|---|---|---|---|
| `check_bug_ledger_shape.py` | **12/12 格 PASS** | **PASS**（账本形态干净：行首三段式抬头 633 条、行内 `## BUG-` 17 行、OPEN 10） | 只读 `memory/bugs.md`（本轮 M 面**不含**账本） |
| `check_ps_encoding.py` | **SELFTEST OK**（P1/P2 双向对照 + 翻转验证） | **PASS**（现状面 11 个 .ps1 全合规） | 扫 .ps1 面（WIP 无 .ps1） |

- 本轮读数均为**干净工作树面的读数**（两尺输入与 WIP 足迹零交集），可作为 HEAD 状态证据。
- r315 候选（`check_effective_catch` / `check_ns_write_gate_coverage` / `check_ci_step_position`）本轮未轮：后者读 `.github/workflows`（`release.yml` 在 WIP 面，读数会被污染），前两者下轮可轮。

## 五、本轮不改码边界（任务分配记录）

| 事项 | 处置 | 不动手原因 |
|---|---|---|
| BUG-636 接线半（判据改真源 + consumers() 收口） | 留 WIP 收口轮按 r315 规格委派中任务 | 规格第 4 条锚点同批要求改 `run_guards.py` + `scripts/README.md` + battery 锚——三者**全在他方 WIP 修改面**；抢修 = 两半不同序列改同一 CI 门 |
| BUG-636 落账（`memory/bugs.md`） | 不落，findings 固化本报告 | 账本/计数面改动须同批 `gen_plugins.py` 重投影，而 `plugins/**` 在他方 WIP 内（R26/R27 同款回避）；**编号复核已做**：落账须用 ≥649 新号 |
| 判据三红（`fist_dispatch.py` 编码闸 / scripts README 登记 / battery 锚漂移） | 留 EP-03 收口方同批 | 同 R27 §三定案，复跑无新信息 |
| f094 WIP 全部文件 | 零接触 | 他方活跃 WIP（02:40 仍在写） |

## 六、FIST 闭环记账（T0r3，首发即全绿）

- ns=`wakeup-patrol`，agent=`commander-atomcode`；task_id=**T0r3**。
- 六步 rc：publish=0 / acl=0 / claim=0 / execute=0 / submit=0 / verify=0——**首发即绿，零补跑**（R27 首发曾撞 assignee/namespace 两坑；本轮链脚本把 `--namespace wakeup-patrol` 与 claim `--assignee` 内置后一次通过，坑位修法已沉淀进链脚本注释）。
- 产物新鲜（BUG-32 不触发）⇒ 总耗时 **6 秒**（05:04:34→05:04:40）。
- 任务终态「已完成」，completed_by=commander-atomcode；链日志 `temp/fist_r28_chain.log`（含完整回执）。

## 七、遗留风险

1. **BUG-636 接线半无人认领**（中危，CI 门禁盲区）：WIP 收口后必须按 r315 规格委派中任务，**务必含「`check_tool_coverage` 加进 `_tool_registry.consumers()`」这一最易漏环节**；落账用 **≥649** 新号（BUG-636 已被 vq 外来账占用——本轮复核固化，届时勿再临时取 636）。
2. **交接缝**：对方清零轮按旧扫描面（165 口径）工作；接线落地瞬间 7 个盲区工具新暴露为零覆盖——接线提交必须同批 known-red（BUG-455 先例）或补测转正，否则 CI 半红。
3. 判据三红维持挂 EP-03 收口方（R26/R27 定案，本轮未复跑）。
4. f094 WIP 39 文件未收口：本轮报告单文件 scoped 提交避让；`memory/2026-11-21.md` 当日日志按惯例留本地不提交。

## 八、后续建议

1. **WIP 收口轮次序**（等 f094 收口方落地后）：三红同批（EP-03 域）→ `gen_plugins.py` 重投影 → 委派 BUG-636 接线中任务（子代理执行 + 指挥官终审：`--selftest` 10 格 + 本体新期望 + `_tool_registry --selftest` 收口格 + `check_battery_count_doc` + 全量 `moon test --target js`）。
2. 换面巡检下轮候选：`check_effective_catch` / `check_ns_write_gate_coverage`（均避开 WIP 足迹）；`check_ci_step_position` 等 WIP 收口后再轮。
3. 唤醒轮维持：publish 成功绝不重发、`--namespace`/`--assignee` 内置、BUG-32 新鲜度前置探测。
