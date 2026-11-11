# 轮 186 汇报 · mcpcf 调用面时钟注入点（BUG-588 ①）

日期：2026-11-11　命名空间/任务：ns=iter-1109b T0（轮 183 车道 H 现场抓出的可测性缺口）
本文件按 `AI-DEVELOPMENT-STANDARD.md` 汇报七段写。

## 一、结果摘要

- **BUG-588 关闭条件之一已落地**：`mcpcf.circuit` / `mcpcf.watchdog` 新增可选参数 `now_secs`
  （`src/server/mcpcf_embed.mbt` 的 `arg_now_secs`，Number 与数字串两形态同效，越界/非法回落墙钟），
  schema 与工具描述同步点名。注入**影响到期判定**：`now_secs ≈ opened_at + recovery` ⇒ `half_open`。
- **缺陷行为锁按其自身提示改写**：`src/server/mcpcf_embed_bug583_wbtest.mbt` 的 `bug583_04`
  从「假时钟被静默丢弃」改写为「注入生效 + 2038 域在工具层可锁」，含判别式断言与两条附格（数字串形态、非法值回落）。
- **本轮另外入账一条新缺陷 BUG-591**：轮 183 车道 J（后台 Explore）回传的 5 条「文档自称有守卫、实际没有尺在看」，
  已按 file:line 现读核过锚点并入账，未代改任何判据口径。
- **状态**：BUG-588 仍 OPEN（关闭条件是「时钟 *或* 数据目录任一」，② 数据目录不可改道仍在）；BUG-591 OPEN 待下一轮接 ①③。

## 二、资源消耗

| 项 | 读数 |
|---|---|
| 模型/工具 | 主会话（统帅）直接施工 + 1 个后台 Explore 车道（车道 J 审计，2166213 tokens / 190s / 35 tool calls） |
| 测试 | `moon test --target js src/server` 597/597；`moon test --target js` 全量见 `temp/g186_full.txt` |
| 变异对照 | 2 发（A 只回退 watchdog 接线 / B 只回退 circuit 接线），各自 ~90s |
| 闸门 | `check_bug_ledger_shape` / `check_warning_ledger` / `check_battery_count_doc` / `check_plugin_sync` 全 rc=0 |
| 过程纪律 | **本轮 0 个施工子代理**（额度约束下未再开车道，属未达标项，见 §四） |

## 三、任务分配记录

- 车道 J（后台 Explore，「自述无尺审计」）：完成，回传 5 条缺口；结论由统帅逐条 grep 复核锚点后入账（未直接采信自述计数）。
- 施工：因车道额度风险，由统帅本人在主会话完成（金条四的偏离，记入 §四 流程债）。

## 四、遗留风险

1. **BUG-588 ② 仍在**：`ops_data_dir()` 不可改道 + 库名硬编码 ⇒ mcpcf 测试仍必须先 `set_engine`，且这一格没有尺在看。
2. **2038 档「可锁但未锁」**：本轮只造出注入点，引擎层 Int32 到期算术仍属 BUG-583（时钟 Int64 化专项，owner 方向待裁），不代修。
3. **流程债**：本轮 0 施工子代理 —— 与目标「多开 N 个 agent 并发迭代」不符；归档后不可补，只能转结流程债。
4. BUG-591 的五条缺口只登记不改口径（改判据=改契约，属人的决定）。

## 五、后续建议

- 下一轮可直接落 BUG-591 的第 ① 条（`check_tools_sync` 增加分组计数 ↔ 表格行数 ↔ `real_tools()` 三向对表，约 15 行）
  与第 ③ 条（`run_guards --list` 对 `CI=no` 的 `check_*` 非零退出）。两条都是「接一根线」级别，且能立刻抓到组头漂移。
- BUG-588 ② 的修法方向：给 `ops_data_dir()` 加可注入覆盖（与 `now_secs` 同形的 args 级注入），或落地 BUG-583 方向④
  「mcpcf 库路径 ≠ 主库路径」判据把风险变成断言。

## 六、超额内容

- 车道 J 的 5 条审计结论已入账为 BUG-591（非本轮原定范围），并附可复跑的 grep 证据行。
- 变异对照中发现并修掉了一条**假锁**：初版「两入口 opened_at 同值」断言在变异 A 下仍绿（`opened_at` 是回显字段，
  不吃 `now_secs`），已改为到期判定（`half_open`）断言——这条记录本身就是「变异对照必做」的又一个实证。

## 七、来源

- 代码：`src/server/mcpcf_embed.mbt`（`arg_now_secs` + 两处接线 + 两个 schema）、`src/server/mcpcf_embed_bug583_wbtest.mbt`（`bug583_04` 改写）。
- 账本：`memory/bugs.md` BUG-588 追记（轮 186）、BUG-591 新条目。
- 证据：`temp/g186_test_server4.txt`（597/597）、`temp/g186_mutA.txt` / `temp/g186_mutB.txt`（变异红）、
  `temp/g186_full.txt`（全量）、`temp/g186_cl7.txt`、`temp/g186_check_bug_ledger_shape.txt`、`temp/g186_check_warning_ledger.txt`、`temp/g186_check_battery_count_doc.txt`。
