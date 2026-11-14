# 轮 279 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

WIP 零变化第 14 轮 + 守卫面零漂移。本轮巡检换面 `check_ofm_endpoint`（r278 已换
`check_fist_list_tools_sync`、r277 已换 `check_host_installable`，避免空转）：
**rc=1（down，WinError 10061 连接被拒）**——`http://127.0.0.1:18326/v1/models` 不可达。
按 r194 已坐实定性（电池 `tolerant(0,1,2,3)` 登记、端点 env-only、死活随外部
OFM/DSH 服务浮动，探活告警语义属 owner 接线决定）与 r218 同读数 ⇒ **非新缺陷、
非新发现，不新立账**。Round C 队列三件维持过期裁定（owner 否决 / 已 FIXED / 已注册），不执行。

## 资源消耗

- 工具调用 ~10 次核验（状态/提交/mtime/diff 面/双守卫/换面守卫/历史读数溯源/FIST 网关 CLI 阅读）
  + FIST 闭环 6 步（publish 后台取 task_id，余 5 步后台串跑收全）
  + 报告/日志/scoped 提交收口
- 无测试、无构建、无 FIST 之外的网络面（OFM 探活为判据内置的一次 HTTP GET，超时 5s）

## 任务分配记录

无子代理派发（同源收敛面 + 单判据探活，指挥官直查直记）。

## WIP 冻结面

- `memory/bugs.md` mtime **2026-11-13 23:42:22 +0800 未动**（与 r266~r278 相同，
  WIP 零变化自 r267 起连续第 14 轮）；最高 BUG-623；diff 面 148 insertions 未变
  （P3~P6 跨项目误落账冻结面）。
- `memory/target.md` mtime 2026-11-10 10:34:16 未动（工作区脏面，Round 24 孤儿行）。
- 两文件为另一 agent WIP，禁区零碰，不提交。
- `src/**` 与 `scripts/**` 工作区零改动（无并发占用面）。

## 守卫面

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_tools_sync` | PASS（183，rc=0；AGENTS/README/deliverable/scoring_rubric 对齐，R8 清单 19 组 ΣN=183） | 同 |
| `check_instruction_budget` | PASS（50440/65536，rc=0；全部章节可见） | 同 |

## 本轮巡检（非阻塞 · 换面）

| 巡检 | 读数 | 与上轮 |
|---|---|---|
| `check_ofm_endpoint` | **rc=1**：`http://127.0.0.1:18326/v1/models -> down（unreachable: WinError 10061 连接被拒）` | 换面复测（r218 同读数） |

- 定性溯源（r194 坐实 + r218 复测一致）：18326 是本机 DSH chanGateway relay（外部桌面进程），
  端点/密钥 env-only 不入库（`FIST_OFM_ENDPOINT`），relay 随 DSH 进程起停而浮动——
  down 是**环境态**不是本仓缺陷面；探针行为正确（探到 down 并如实回 rc=1，正是其设计目的）。
- 电池登记 `tolerant(0,1,2,3)`：CI 无 env 读 3、本机 env 指旧端点读 1，均为正确读数，不进门禁。
- 若后续需要「relay 掉线即告警」语义，属 owner 接线决定（r194 遗留面），本轮不越权。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，d43a06a28 治本 → 8a669992d 回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **P3~P6 跨项目误落账（32 条，最高 BUG-623）**：vq-mcp 项目条目持续落进本纯 MoonBit 仓，
   根治需给记账路径加项目作用域守卫（owner 裁决件，r245 起挂起）。WIP 冻结未动，维持只读观察。
2. `memory/bugs.md` 工作区脏面未收口 ⇒ 任何 `git add -A` 型批量操作都会误吞，
   提交纪律（scoped `--` 路径 / commit_scoped.sh）维持强制。
3. **唤醒轮收口中断风险（r206 / r272 两次实证）**：计划任务 30 分钟无窗唤醒，
   会话若在「FIST 闭环后、提交前」被截断即漏两格。缓解：每轮退出前的两格核对
   已写入项目记忆；缺口次轮可补账，不影响安全面（报告内容以磁盘原件为准）。
4. **OFM relay（18326）持续 down**：自 r218（2026-11-12）起每次探活均 down。
   环境态（DSH 桌面进程未起/relay 未转发），非本仓缺陷；「relay 掉线告警」接线
   属 owner 决定面，维持只读观察。

## 后续建议

- 下一轮若 bugs.md mtime 再变，优先核对是新增误落账批次还是 owner 裁决后的清理提交。
- 换面轮换候选（供后续轮取用，避免空转）：`scripts/mcp_smoke.py`（重面，node 冷启动）、
  `check_host_installable`（r277 已跑）、`check_fist_list_tools_sync`（r278 已跑）、
  `check_ofm_endpoint`（本轮已跑）、`check_demo_isolation` / `check_entry_paths` 等守卫族未轮换面。
- 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --stat` / `ls -la memory/{bugs,target}.md`（本轮实跑）
- `python scripts/check_tools_sync.py`（rc=0）/ `python scripts/check_instruction_budget.py`（rc=0）
  / `python scripts/check_ofm_endpoint.py`（rc=1，down）（本轮实跑）
- r218 报告磁盘原件（`reports/2026-11-12-r218-watchdog-wip-freeze-report.md`，OFM 同读数溯源）
- r278 报告磁盘原件（`reports/2026-11-14-r278-watchdog-zerochange-brief-report.md`，只读核验）
- FIST 闭环 T0r35（ns watchdog，6 步全链 rc=0，FIST_DB_PATH 改道 temp/fist-selfiter.db，completed_by=wd-r279）
