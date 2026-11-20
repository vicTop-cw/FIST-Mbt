# 2026-11-21 唤醒巡检 R29 报告 — BUG-636 两半状态复核（A 面树面见效 / 接线半未认领）+ 165→170 口径修正 + 三尺绿 + T0r4 闭环

- 轮次：R29（Windows 计划任务 FIST-Mbt-ExploreWatchdog 唤醒，findings-only 非阻塞巡检）
- 前序：[R28 报告](2026-11-21-wakeup-r28-report.md)（BUG-636 状态推进 + 换面巡检两尺绿 + T0r3 闭环）
- 模式：fist-commander；本轮**未改任何跟踪面代码**（零改码轮，原因见 §五）

## 一、结果摘要

| # | 事项 | 结论 |
|---|---|---|
| 1 | 并发 WIP | 与 R28 快照**同形、零新落盘**（最新 mtime 仍 02:40）——f094 收口方处于暂停期，WIP 未收口；全程避让零接触 |
| 2 | **BUG-636 A 面半** | **在树面见效**：`check_tool_coverage` 本体扫描 **170 工具、外壳覆盖 170/170、零覆盖清零 PASS**——两份未跟踪测试文件（task_events/query/stats + wt_dispatch/collect）已进 A 面扫描并转绿 |
| 3 | **BUG-636 接线半** | **仍未认领**（`grep _tool_registry scripts/check_tool_coverage.py` 零命中，与 R28 结论一致）——`extract_tools()` 仍读旧扫描面 |
| 4 | **口径修正（本轮核心）** | 165→170 的 +5 **不是 WIP 注册**：判据同款正则对 HEAD 与工作树 server.mbt 逐名对比**零增删**，增量来自 r315 立账后的两笔**已提交**工具（be5f154f8 查询三件套 +3、18810300b wt_dispatch/collect +2）⇒ 账本「165 口径」自然过时 |
| 5 | 换面巡检 | 三尺绿：tool_coverage 本体 PASS / surface-selftest 14 支 OK / 指令预算 PASS（§四） |
| 6 | BUG-32 新鲜度 | 不触发（`cli.js` 03:33:54 > 最新源 02:40:03）⇒ FIST 链 6 秒全绿 |
| 7 | FIST 闭环 | **T0r4 六步首发即全绿**（复用 r28 链模板 + 参数化 TID 提取器，零补跑，§六） |

## 二、并发 WIP 与提交面

- `git log --oneline` 头部与 R28 相同：`96d5b67d2`（R28 报告）为新 HEAD，本轮无新提交。
- M 面 39 文件与 R28 完全一致（`src/server/server.mbt` +150 行、`wt_tools.mbt`、`src/store/store_sqlite*.mbt`、`scripts/run_guards.py` +6、`scripts/README.md`、`plugins/**`、`docs/**`、`README*`/`USAGE.md`/`AGENTS.md`、`.github/workflows/release.yml` 等）；未跟踪 6 项也一致（`tool_cov_query_tools_test.mbt` 02:40 / `tool_cov_wt_async_test.mbt` 22:59 / `reports/2026-11-20-tnr-ascend-round2-report.md` / `.trae-html-share-packages/` / `_moonbit_兼容性反馈.txt` / `website/`）。
- 关键文件 mtime 复核：`run_guards.py` 11-20 21:44、`server.mbt`/`wt_tools.mbt` 11-20 20:36——**自 02:40 后整树无新写入**。
- 本轮落盘面仅三处：本报告（唯一提交物）+ `memory/2026-11-21.md` 追加（本地留置不入库）+ `temp/fist_r29_chain.sh` / `temp/fist_r29_chain.log`（temp 面不提交）。

## 三、BUG-636 状态复核 + 165→170 口径修正（本轮核心发现）

### 3.1 两半状态与 R28 一致，但 A 面新增树面实证

- **A 面半**：R28 只确认「对方在飞」（文件头自述）；本轮跑判据本体取得**树面量化读数**——`python scripts/check_tool_coverage.py` 扫描 170 工具、A 外壳面 170/170 有覆盖、外壳零覆盖 **0/170（100% 覆盖）**、rc=0 PASS。即对方的清零轮在其**工作树面已达成旧扫描口径的清零**（两份未跟踪测试被 `*_test.mbt` glob 扫入）。未提交 = CI 还看不见，收口提交时该状态才生效。
- **接线半**：仍零进展。`extract_tools()` 继续用 `TOOL_RX` 正则直读 `src/server/server.mbt`（非委托 `_tool_registry` 真源），`_tool_registry.consumers()` 收口未做。

### 3.2 「165 口径」已自然过时（对账本引用面的修正建议）

r315 立账时冻结的「旧扫描面 165 口径」到本轮已**落后 5 个**。定性证据：

1. 用判据同款正则（`TOOL_RX`）分别抽取 **HEAD** 版与**工作树**版 `src/server/server.mbt` 的工具名集合：两边都是 **170 个、逐名对比零增删** ⇒ +5 与 WIP 无关；
2. +5 的来源是 r315 立账（2026-11-15）之后的**两笔正常提交**：`be5f154f8` 查询面三件套（task_events/task_query/task_stats，+3）与 `18810300b` EP-03 dispatch（wt_dispatch/wt_collect，+2）——恰是 A 面清零轮补测的那 5 个工具。

**影响**：接线半落地瞬间新暴露为零覆盖的**盲区集合本身不变**（mcpcf.report/review/run_batch/verify + supervisor_prompt_consume/inject/list 共 7 个，它们在旧正则下本就抽不到、与 165→170 无关），但接线后的**总扫描面是 170 不是 165**——账本条目与交接说明里所有「165 口径」字样届时应按 170 口径改写（落账编号 ≥649，见 §七）。

## 四、换面巡检读数（三尺）

| 判据 | 读数 | 覆盖面说明 |
|---|---|---|
| `check_tool_coverage.py`（本体） | **PASS**（170/170 外壳覆盖，rc=0） | 输入含 WIP 足迹（读的是工作树 server.mbt + 未跟踪测试）——读数即「收口后 CI 将见的状态」的前瞻证据 |
| `mcp_tool_tour.py --surface-selftest` | **OK**（14 支：10 违例必红 + 2 必绿 + 2 必自拒，不符 0 支） | 合成桩自证，不碰真 server/库，与 WIP 足迹零交集 |
| `check_instruction_budget.py` | **PASS**（AGENTS.md 51096 / 65536，全部章节可见） | 读 AGENTS.md（他方 WIP 面）——**在飞面口径**：收口方加字后仍在预算内 |

- fmt gate 本轮跳过：BUG-388 已钉死本地 `moon fmt --check` 不可测（rc=2 拒绝判红判绿），跑它无新信息；格式门权威面以 CI（Linux nightly）为准。
- R28 候选 `check_effective_catch` / `check_ns_write_gate_coverage` 本轮未轮：两者扫描面（scripts/ py 面、src/ mbt 面）与 WIP 足迹重叠，读数会被污染成「在飞面」——留给收口后轮。

## 五、本轮不改码边界（任务分配记录）

| 事项 | 处置 | 不动手原因 |
|---|---|---|
| BUG-636 接线半（extract_tools 委托真源 + consumers() 收口） | 留 WIP 收口轮按 r315 规格委派中任务 | 规格锚点（`run_guards.py` + `scripts/README.md` + battery 锚）**全在他方 WIP 修改面**；且接线落地须同批处理 7 盲区工具 known-red（BUG-455 先例）——R28 §五同款回避 |
| BUG-636 落账（`memory/bugs.md`，编号 ≥649） | 不落，findings 固化本报告 | 账本/计数面改动须同批 `gen_plugins.py` 重投影，`plugins/**` 在他方 WIP 内（R26/R27/R28 连续三轮同款回避） |
| 判据三红（fist_dispatch 编码闸 / scripts README 登记 / battery 锚漂移） | 维持挂 EP-03 收口方 | R26/R27 定案，复跑无新信息 |
| f094 WIP 全部文件 | 零接触 | 他方活跃 WIP（本轮暂停期 ≠ 收口，收口以提交为准） |

## 六、FIST 闭环记账（T0r4，首发即全绿）

- ns=`wakeup-patrol`，agent=`commander-atomcode`；task_id=**T0r4**。
- 六步 rc：publish=0 / acl=0 / claim=0 / execute=0 / submit=0 / verify=0——**首发即绿，零补跑**；06 秒跑完（05:33:22→05:33:28，产物新鲜免 autobuild）。
- 任务终态「已完成」（verify 步回执实测）；链日志 `temp/fist_r29_chain.log`（含完整回执）。
- 工程面小改进：链脚本复用 r28 模板，TID 提取直接复用 `temp/fist_r28_tid.py`（r318 稳健口径、argv 参数化）——**跨轮复用成立，后续轮无需再复制 tid 脚本**。

## 七、遗留风险

1. **BUG-636 接线半无人认领**（中危，CI 门禁盲区，跨 R28→R29 两轮未动）：WIP 收口后必须按 r315 规格委派中任务；届时扫描面按 **170 口径**（§3.2），接线提交务必同批 known-red 或补测转正 7 盲区工具，且「165 口径」引用面一并修。
2. **交接缝维持**：对方清零轮验收口径是旧扫描面清零（其工作树面已达成）；接线落地前 CI 侧 A 面仍按旧口径跑（收口提交才会生效），接线半不改则 18 个工具继续漏扫。
3. 判据三红维持挂 EP-03 收口方（R26/R27 定案，本轮未复跑）。
4. f094 WIP 39 文件 + 6 未跟踪未收口：本轮报告单文件 scoped 提交避让；`memory/2026-11-21.md` 当日日志按惯例留本地不提交。

## 八、后续建议

1. **WIP 收口轮次序**（等 f094 收口方落地后）：三红同批（EP-03 域）→ `gen_plugins.py` 重投影 → 委派 BUG-636 接线中任务（子代理执行 + 指挥官终审：`--selftest` + 本体新期望 170 口径 + `_tool_registry --selftest` 收口格 + `check_battery_count_doc` + 全量 `moon test --target js`）；落账 ≥649 新号并修正「165 口径」引用面。
2. 换面巡检候选改为**收口后可轮**：`check_effective_catch` / `check_ns_write_gate_coverage` / `check_ci_step_position`（三者在飞面读数会被 WIP 污染）。
3. 唤醒轮维持：publish 成功绝不重发、链模板直接复用（含 r28_tid.py）、BUG-32 新鲜度前置探测。
