# 2026-10-13 · supervisor-tools 计划验收缺口 + 工作树测试读数交接单

## 结果摘要

**一句话**：本轮沿目标主线核查 `docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` 的落地情况，
发现**实现本体已完成但未入库**（1093 行新增）、且**计划 §5 声明的测试锁文件不存在**；
同时实测工作树全量测试 **1004 / 1002 passed / 2 failed**，两个失败均在并发会话未跟踪的
`src/claimguard/` WIP 里。

| 项 | 读数 |
|---|---|
| `supervisor_*` 工具（计划声明 7 个） | 工作树里**全部有实现命中**（源码 471 + 622 = 1093 行）|
| 这两个新增文件 | **均不在 HEAD**（`??`）——即"已实现、未提交"|
| 计划 §5 声明的 `src/server/supervisor_tools_test.mbt` | **不存在** ⇒ 计划的 P1 验收面（测试锁）**未完成**|
| 工作树 `moon check --target js` | **0 errors**（44 tasks）|
| 工作树 `moon test --target js` | **Total tests: 1004, passed: 1002, failed: 2** |
| 2 个失败 | 均在 `src/claimguard/claimguard_wbtest.mbt:738/768`（**目录整批未跟踪** = 并发 WIP）|
| `src/server` 单包测试 | **249 / 249 passed / 0 failed**（supervisor 工具所在包全绿）|

## 计划落地核查（逐项）

计划 §2 声明 7 个 `supervisor_*` 工具、§5 声明 5 处落点：

| 计划落点 | 计划状态 | 实测 |
|---|---|---|
| `src/server/supervisor_tools.mbt` | 新增 | ✅ 存在（471 行），**不在 HEAD** |
| `src/engine/engine_supervisor.mbt` | 新增 | ✅ 存在（622 行），**不在 HEAD** |
| `src/server/server.mbt` | 最小侵入（插一行） | ✅ 在 HEAD；`register_supervisor_tools` **命中 1 处**（已挂）|
| `src/core/core_task.mbt` | 追加 | ✅ 在 HEAD（638 行）|
| `src/server/supervisor_tools_test.mbt` | 新增 | ❌ **不存在** ⇒ 计划的测试锁面未落地 |

**7 个工具的实现命中**（`supervisor_tools.mbt` + `engine_supervisor.mbt` 内）：
`supervisor_status`(7) / `supervisor_task_tree`(6) / `supervisor_kill_plan`(7) /
`supervisor_prompt_inject`(6) / `supervisor_prompt_list`(3) / `supervisor_prompt_consume`(5) /
`supervisor_task_upsert`(6)。

## 计划 §7 验收标准的对照（关键：只差"测试锁"一格）

| 验收标准 | 实测 |
|---|---|
| `moon check` 零错误 | ✅ 工作树 0 errors（44 tasks）|
| `moon test` 全绿（以汇总行为准） | ⚠️ **1004 / 1002 passed / 2 failed** —— 但 2 个失败在他人 WIP 的 claimguard，不在本计划面 |
| 新增测试锁：kill 门链逐门（身份/不可杀/终态/force）| ❌ `not_authorized` **0 命中**、`not_found` **0 命中**；`protected_planner`(2) / `terminal_state`(1) 有字面量但**无测试文件承载** |
| guidance inject→list→consume 闭环测试 | ❌ 无测试文件（`guidance` 38 命中全是实现面）|
| task_upsert 的 created/updated/失败三路测试 | ❌ 无测试文件（`created`(9)/`updated`(6) 是实现面）|
| tree 聚合正确性测试 | ❌ 无测试文件 |
| 对既有 737 测试零回归 | 待其收口后以全量汇总行复核（当前工作树 1004 计数已远超 737）|

⇒ **结论**：该计划的「实现」已完成、「测试锁」未完成。这正是"计划里未实现"的一处**真实缺口**。

## 交接给并发会话（不代做，理由如下）

**为什么我不补这个测试文件**：
1. 该面（`src/server/supervisor_tools.mbt` + `src/engine/engine_supervisor.mbt`）是**他人正在开发的未跟踪 WIP**
   （1093 行、两个新文件都还没 `git add`）；我若新建测试文件，会与该面作者对同一批内部符号的
   命名/契约产生冲突（我读到的只是工作树快照，不是最终契约）。
2. 计划 §5 明确列了该测试文件名，说明**作者已有安排**；这不是"没人认领的空位"，而是"作者未走到那一步"。
3. 金条四：我负责诊断与出方案，不代做他人工作面。

**但读数已备好**（上述表格即为可直接采用的验收对照）：
- 工作树实现是**编译通过的**（0 errors）⇒ 补测试的起点是绿的
- 测试文件的落点、命名、要锁的四组行为（kill 门链 / guidance 闭环 / upsert 三路 / tree 聚合）
  **计划 §5 与 §7 已逐条写明**，照写即可
- `not_authorized` 与 `not_found` 两门在实现里**零字面量命中** ⇒ 补测试时需先确认这两门
  是否真按计划 §3 的 G1/G2 实现（**这可能是比"缺测试"更实质的缺口：门名在实现里可能叫别的**）

## 资源消耗

- `moon check` 2 次、`moon test` 2 次（全量 + `src/server` 单包），单次约 3–8 分钟；
- 扫描/核查脚本 1 支（`temp/scan_supervisor_plan.py` 口径的手工命令）；
- 零 `.mbt` 改动、零提交（本轮只做核查）；零网络请求。

## 任务分配记录

- 指挥官亲自：读计划 §2/§5/§6/§7 → 逐项核对落点 → 7 工具实现命中统计 → 工作树 check/test 实跑 →
  失败归属（claimguard = 他人 WIP）→ 判定"测试锁缺口"不代做并写出交接单。
- **未派子代理**：本链要害是"该不该代做他人 WIP 的测试"，外包会引入误判。
- 边界：**本轮零写入**（除 temp/ 与报告）；未改任何 `.mbt`、未提交任何他人 WIP。

## 遗留风险

1. **P0（未变）**：HEAD 编译不过（20 errors，13 个 `.mbt` 仅入库 1 个）。`supervisor_tools.mbt` +
   `engine_supervisor.mbt` 正是缺失文件中的两个 ⇒ 它们不进 HEAD，`register_supervisor_tools`
   这一行在 HEAD 上就是**悬空引用**，而 `check_mbti_sync` 报的 4 个符号里**明确含它**
   （另三个是 `do_evolve_asset_register_with_search` / `parse_search_lines` / `self_search_runner_default`，
   均报"实现已在工作树磁盘上、只是没进跟踪面"）。
2. **工作树测试 2 红**在 `src/claimguard/`（他人 WIP）：若他们整批提交，CI 的 `Test (js)` 会红。
   **建议他们在提交前跑全量并把 claimguard 那 2 格修到绿**——本单已给出精确位置
   （`claimguard_wbtest.mbt:738` / `:768`，diff `-1 +0`）。
3. **`supervisor_tools_test.mbt` 缺失**：计划的验收面不完整；补测试时需同时确认 G1/G2 两门实现名。
4. **测试计数口径漂移**：工作树已 1004（AGENTS/README 自述 737/148 工具等面未跟）⇒ 收口时需同步。

## 后续建议

1. **给该面作者的提交清单**（我实测可闭合）：`src/server/supervisor_tools.mbt` +
   `src/engine/engine_supervisor.mbt` + `src/engine/engine_supervisor_reminder_test.mbt`
   （+ 其依赖的 `src/core/core_task.mbt` 等已改文件）——一并提交后 HEAD 的悬空引用减少两个。
2. **补 `supervisor_tools_test.mbt`**（计划 §5 已列明）：四组测试照 §7 写；**先核 G1/G2 门名**。
3. **claimguard 2 红的归属提醒**：见遗留风险 2，建议该面作者提交前修绿。
4. **把"计划落点核查"做成例行**：本轮手法（读计划 §落点表 → 逐文件核对 in_HEAD/exists → 实跑 check/test）
   可复用于其余 5 份未入库计划文档（`multilang-sdk` / `reminder-role` / `hexamind-design` /
   `supervisor-role-design` / `web-dashboard`），快速列出"声明 vs 落地"对照。

## 超额内容

- 顺带**实测出工作树测试 2 红并定位到具体行**（`claimguard_wbtest.mbt:738/768`）——这是并发会话
  提交前必须处理的一格，我提前给出精确位置，省他们一轮排查。
- 顺带**把"计划 §7 验收标准"与"实测读数"逐条对照成表**，使"哪一格已满足、哪一格未满足"一目了然
  （而不是笼统说"计划未实现"）。
- 顺带**发现一处可能比"缺测试"更实质的缺口**：`not_authorized` / `not_found` 两门在实现里
  **零字面量命中** ⇒ 补测试前需确认 G1/G2 是否真按计划实现（若门名不同，是计划-实现漂移）。

## 来源

- 计划：`docs/2026-10-12-fist-mbt-supervisor-tools-plan.md`（§2 工具清单 / §5 落点 / §6 分期 / §7 验收）。
- 实测：工作树 `moon check --target js` = 0 errors（44 tasks）；`moon test --target js` =
  `Total tests: 1004, passed: 1002, failed: 2`；`src/server` 单包 = `249/249`。
  失败定位：`[vicTop-cw/fist-mbt] test src/claimguard/claimguard_wbtest.mbt:738
  ("cg_schedule_admit_cascade_benefit")` / `:768 ("cg_schedule_admit_reject")`，diff `-1 +0`。
- 归属：`git cat-file -e HEAD:src/claimguard/claimguard_wbtest.mbt` = **不在 HEAD**；
  `git status` 显示 `?? src/claimguard/` ⇒ 整目录未跟踪（他人 WIP）。
- 落点核查：`git cat-file -e HEAD:src/server/supervisor_tools.mbt` = 不在 HEAD（存在，471 行）；
  `src/engine/engine_supervisor.mbt` = 不在 HEAD（存在，622 行）；
  `src/server/server.mbt` 里 `register_supervisor_tools` 命中 1 处（已挂，但在 HEAD 上引用的是缺失符号）。
