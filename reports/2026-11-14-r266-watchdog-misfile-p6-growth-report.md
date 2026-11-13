# 轮 266 巡检报告——P6 误落账增长（P3~P6 四批 32 条）+ 守卫面零漂移

> ExploreWatchdog 唤醒轮 · 2026-11-14 00:31 本地 · HEAD 基线 `5b3d2a75d`（r265 报告）
> 定性：**非零变化轮**（WIP 面真实增长，新发现 P6 批次）· 非防空转

## 一、结论摘要

本轮唯一新发现：**跨项目误落账从「P3+P4+P5 三批（24 条）」增长为「P3+P4+P5+P6 四批（32 条）」**。

P6 批次（**BUG-616~623**，8 条，全 `OPEN`，`reported_by: vq-p6-commander`，2026-11-13T15:41~15:42Z
= 本地 23:41~23:42）于 2026-11-13 本地 **23:42:22** 落入 `memory/bugs.md` 工作树（**bugs.md mtime
`23:42:22 +0800` 实测与 P6 末条时间戳逐秒吻合**），晚于 r265（23:38 本地，mtime 仍 `21:43:07`）
约 4 分钟。这打破了 r262~r265「P3+P4+P5 24 条自 r262 起冻结」的假设 ⇒ **误落账是持续模式，
四批递进（P3→P4→P5→P6），非一次性事故**。

守卫面零漂移：`check_tools_sync`（183）+ `check_instruction_budget`（50440/65536）本轮实跑，
与 r261~r265 同读数 ⇒ **仅 WIP 面增长，守卫面零漂移**。

WIP 两文件（`bugs.md` + `target.md`）维持**禁区零碰**：清理（删除 / 移回目标仓）属**不可逆跨仓操作**，
须 owner 裁决并指定目标仓，本轮不代改。

## 二、证据链（本轮实跑）

| 项 | 读数 | 来源 |
|---|---|---|
| `git status --short` | 仅 `M memory/bugs.md` + `M memory/target.md` | 开轮实跑 |
| `git diff --stat`（两 WIP 文件） | **148 insertions(+), 1 deletion(-)**（r265 为 116+/1-，**+32 行**） | 本轮实跑 |
| bugs.md 工作树新增条目 | **BUG-592~623（32 条）**（P3 9 + P4 10 + P5 5 + **P6 8**） | `git diff` grep |
| **P6 批次** | **BUG-616~623（8 条，全 `OPEN`，`vq-p6-commander`）** | `git diff` |
| P6 时间戳 | 2026-11-13T15:41~15:42Z（本地 23:41~23:42） | `git diff` |
| **bugs.md mtime** | **2026-11-13 23:42:22 +0800**（与 P6 末条 `15:42:22Z` 逐秒吻合，r265 为 21:43:07） | `ls -la --time-style=full-iso` |
| target.md mtime | 2026-11-10 10:34:16（未动，Round 24 孤儿行，引用旧 HEAD `5cbe4ce52`） | `ls -la` |
| 未跟踪面 `??` | 0（无新增文件；stray 0B 尾随空格库文件未复发，r204/r241 模式） | `git status --porcelain` |
| `check_tools_sync` | PASS（server.mbt **183** 对齐） | 本轮实跑 |
| `check_instruction_budget` | PASS（AGENTS.md **50440**/65536） | 本轮实跑 |
| HEAD | `5b3d2a75d`（r265 报告，本轮未移动，无并发提交） | `git log -1` |
| `date` | 2026-11-14 00:31 +0800 | 开轮实跑 |

### P6 八条内容（逐条摘要，均属另一 Python+Vue+Rust 项目 vq-mcp）

| 编号 | 级别 | 状态 | 摘要 |
|---|---|---|---|
| BUG-616 | high | OPEN | vq-cli `train delete` 单条删除失败仅打印错误却返回 rc=0（假成功） |
| BUG-617 | high | OPEN | vq-cli `metadata import` 未指定导入源仍 rc=0（假成功） |
| BUG-618 | medium | OPEN | vq-cli `completion` 未知 shell 仍 rc=0 且 stdout 为空 |
| BUG-619 | high | OPEN | vq-cli `train nltk` 部分或全部失败仍打印完成并 rc=0 |
| BUG-620 | medium | OPEN | vq-cli `metadata import` PRAGMA 部分失败被静默跳过仍报导入完成 |
| BUG-621 | medium | OPEN | vq-cli `history rate` 自动入训练集吞 `Result` 且无条件打印成功 |
| BUG-622 | medium | OPEN | P5 修复点 `main.rs:2158/2164` 缺少直接回归锁 |
| BUG-623 | high | OPEN | `database.py:227` 吞异常零可观测且把任意 sqlite 错误误判为列缺失 |

## 三、定性分析

1. **P6 增长实锤**：r265 报「116+/1-，BUG-592~615 24 条，mtime 21:43:07 自 r262 冻结」。本轮
   `git diff --stat` = **148+/1-**（**+32 行**），`git diff` 逐条读出 **BUG-616~623（8 条新条目，
   全 `OPEN`）**，bugs.md mtime `23:42:22` 与 P6 末条 `15:42:22Z`（UTC）逐秒吻合 ⇒ P6 批次是
   **r265 后新增**，非既有内容被误读。

2. **持续模式升级为四批（不同 agent，不同时间）**：
   - **P3**（2026-11-12 本地 16:29，`FIST-Mbt 生命周期闭环官`，BUG-592~600，9 条，全 FIXED）
   - **P4**（2026-11-13 本地 14:09~14:10，`WorkBuddy P4`，BUG-601~610，10 条，全 FIXED）
   - **P5**（2026-11-13 本地 21:39~21:43，`WorkBuddy P5`，BUG-611~615，5 条，全 FIXED）
   - **P6**（2026-11-13 本地 23:41~23:42，`vq-p6-commander`，BUG-616~623，8 条，全 **OPEN**）

   四批均为**另一 Python+Vue+Rust 项目（vq-mcp）**的账本条目：`main.rs` / `cargo` / `clippy`
   / `data/vq.db`（Rust/DB）、`database.py`（Python）。**注意 P6 是全 `OPEN`（未修复）**——
   前 5 批是各批次收口时的 FIXED 快照，P6 是 `vq-p6-commander` 新立尚未闭环的活条目。

3. **结构不可能**（r249/r262 结构证明，本轮不重推）：本仓纯 MoonBit（tracked rs=0 / vue=0 /
   py=0），P6 点名 `crates/vq-cli` / `main.rs:2158` / `database.py:227` / `clippy` 在本仓结构上
   **不可能成立** ⇒ 确属跨项目误落（BUG-565 形状）。

4. **根因**（r245 已定性，P3~P6 四批再证）：记账 / `report_bug` 落盘指向 `FIST_MBT_REPO` 所指树
   （BUG-565 形状）⇒ vq-mcp 项目的 P3/P4/P5/P6 收口把账写进了 FIST-Mbt 仓的 `memory/bugs.md`。
   四批由**不同 agent**（生命周期闭环官 / WorkBuddy P4 / WorkBuddy P5 / vq-p6-commander）在
   **不同时间**触发 ⇒ 是**系统性路由缺口**，非单点失误。

## 四、处置（本轮）

- **WIP 禁区零碰**：`bugs.md`（32 条误落账）+ `target.md`（孤儿行）不删、不改、不提交。
  清理属**不可逆跨仓操作**，须 owner 裁决 + 指定目标仓（见 §五）。
- **不代立代码修复**：根因（记账路径缺项目作用域守卫，BUG-565 形状）是 FIST-Mbt 代码面修复，
  属新立项，本轮不代办，交 owner 决定是否立项 + 派单。
- **Round C 队列判空维持**（memory 已钉，勿重推导）：BUG-527 摘 cc-link-flags 已被 owner 否决
  （0fe9146a6）、BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）
  ⇒ 唤醒轮直接非阻塞巡检。
- **聚焦巡检维持全绿（非防空转重跑）**：`check_tools_sync`（183）+ `check_instruction_budget`
  （50440/65536）本轮实跑，与 r261~r265 同读数 ⇒ 守卫面零漂移，**仅 WIP 面增长**。
- **FIST 闭环记账**：ns `watchdog`（复用），**T0r22** 全链 publish→agent_acl_grant→claim→execute→
  submit→verify 至已完成（completed_by=wd-r266；ns 计数器续行 r265 T0r21 → r266 T0r22）。

## 五、owner 裁决件（r245 三件，本轮以 P6 增长再补强第 2 件）

1. **看门狗降频 / 事件驱动**（三选一：事件驱动 / 30min→2h / 维持）。
2. **跨项目误落账处置**（**本轮升级：从「P3+P4+P5 三批 24 条」→「P3~P6 四批 32 条」，P6 全 OPEN**）：
   - 选项 A：从本仓 `memory/bugs.md` 删除 32 条误落账（BUG-592~623）。
   - 选项 B：移回 vq-mcp 项目自己的账本（需 owner 指定目标仓 / 路径）。
   - 选项 C：保留但标注「跨项目误落」，待 vq-mcp 侧统一清理。
   - **另附根治**：给记账 / `report_bug` 路径加项目作用域守卫（代码面，防再犯）。
3. **target.md 孤儿 WIP**：一行 Round 24 巡检日志覆盖了真实迭代目标（mtime 2026-11-10 未动）。
   选项：恢复迭代目标 / 清空 / 标注。

误落账已**四批递进**（P3→P4→P5→P6，且 P6 是未闭环的 OPEN 活条目），owner 裁决件第 2 件
（跨项目误落账处置）的紧迫性持续上升 ⇒ 维持呈报待裁，不代改。

## 六、资源消耗 / 任务分配

- **FIST 闭环**：ns `watchdog`（复用），T0r22，6 步全链（`temp/fist_chain_r266.sh` 后台一次收全；
  fist.py `call` 每发独立拉 node MCP server，冷启动成本，非缺陷）；agent=verifier=wd-r266
  （同身份模式，单次 ACL 授权）。
- **巡检命令**：`git status/diff/log` + `ls -la --time-style=full-iso` + `date` + `check_tools_sync`
  + `check_instruction_budget`（后两者本轮实跑，与 r261~r265 同读数；mcp_smoke / moon test /
  moon check / fmt 门按防空转纪律不重跑）。
- **子代理**：本轮为读面巡检 + 记账，无可分配代码面工作，未派子代理（指挥官亲做状态核读）。

## 七、来源

- `git status --short` / `git diff --stat` / `git diff -- memory/bugs.md` / `git status --porcelain` /
  `git log --oneline -3` / `ls -la --time-style=full-iso memory/bugs.md memory/target.md` / `date`（本轮实跑）
- `check_tools_sync` / `check_instruction_budget`（本轮实跑）
- `reports/2026-11-13-r265-watchdog-zerochange-brief-report.md`（r265 基线）
- `reports/2026-11-13-r262-watchdog-misfile-p5-growth-report.md`（r262 P5 增长实证 + owner 裁决件权威面）
- `memory/2026-11-13.md` 轮 244~265（WIP 增长/冻结基线 + r245 owner 呈报权威面）
- AGENTS.md「FIST 指挥官模式 / 提交纪律 / 禁区意识 / 不可逆操作先出方案」
