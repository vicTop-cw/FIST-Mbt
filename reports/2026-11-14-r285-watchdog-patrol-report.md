# 轮 285 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

**WIP 面冻结零变化（第 2 轮）**：四件套 mtime（10:47:48 / 10:55:34 / 2026-11-10 10:34:16 / 11:11:49）全部早于 r284 提交（15:19:37），`git diff --stat` 与 r284 逐字相同（3 文件 208+/2-），**本轮相对 r284 零新增量**。Round C 三件维持过期不执行。

本轮换面巡检两格，一格**首次实跑**出 r284 没有的读数：

- **BUG-583 方向④ 守卫首次实跑**：`python scripts/check_mcpcf_db_isolation.py` → **静态 4/4 PASS + C1 碰撞格空过，rc=0**。r284 只读了 docstring + 骨架（不执行），本轮第一次拿到执行面读数：mcpcf 默认目录后缀（`\mcpconftest\data`）/回退目录（`./mcpconftest-data`）与主库 data_dir（`.fist-mbt/data`）段族不相交、mcpcf 库名（`mcpconftest-ops.db`）≠ 主库默认库名（`fist-mbt.db`）、env 键族互不相同 ⇒ **BUG-583 方向④ 的「两条路径家族不相交」判据在当前真源下成立**。该守卫仍未注册电池执行面（r284 遗留风险 1 原样维持，禁区零碰）。
- **外来账检测面复测**：`check_foreign_ledger_entries` **rc=1**（脏树投影）——白名单外 23 条（现最高 BUG-635）逐条维持 vq 项目信号（`crates/`、`vq-cli/core/pyo3` 等），与 r283/r284 同态，**待 owner 裁决，指挥官不代行**（跨仓不可逆）。

零漂移 `check_tools_sync` PASS（183，rc=0，本轮复测）；`check_instruction_budget` 50440/65536（rc=0）。FIST 闭环 T0r41 收口（wd-r285，见下节）。

## 资源消耗

- 工具调用 ~15 次（只读核验 7 + 巡检守卫 4 + FIST 闭环脚本 2 + 收口 2）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 2 轮）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283/r284） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

## 守卫面（换面巡检）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_mcpcf_db_isolation`（未注册 WIP，巡检实跑） | **静态 4/4 PASS + C1 碰撞格空过，rc=0** | r284 只读骨架未执行 ⇒ **本轮首跑**，方向④判据成立 |
| `check_foreign_ledger_entries` | rc=1（脏树投影：白名单外 23 条 vq 信号，最高 BUG-635） | 同 r283/r284 态（待 owner 裁决） |
| `check_tools_sync` | PASS（183，rc=0） | 同（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283 |

## FIST 闭环（T0r41 · wd-r285 · ns watchdog）

**6 步全链后台串跑**（脚本 `temp/fist_r285_chain.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，比 r284 的固定 id 假设更稳；FIST_DB_PATH 改道 temp/fist-selfiter.db）：

| 步 | rc | 状态迁移 |
|---|---|---|
| publish | 0 | 发布 T0r41（writable_agents 递进，claim_ready=true） |
| agent_acl_grant | 0 | can_write=true（pid_bound=false） |
| claim | 0 | 已领取（assignee=wd-r285） |
| execute | 0 | 执行中（deliverable=本报告） |
| submit | 0 | 待验收 |
| verify | 0 | 已完成（completed_by=wd-r285） |

各步回包落盘 `temp/fist_r285_out/1..6_*.txt`。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP，无执行面。本轮实跑确认**脚本本身是好的**（rc=0，静态 4/4 过），风险收敛为「另一 agent 收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）」。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES（它是独立判据，非共享模块/一次性工具）。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

- 下一轮若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc（本轮已预核主面 rc=0，收口时只需补前两格）。
- 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
- WIP 面已连续 2 轮零变化（且四件套 mtime 全部早于 r284 提交）：若再连续 2~3 轮冻结，该 WIP 可能是**弃置**而非进行中——届时值得在巡检报告中提请 owner 关注（仍不代行清理）。
- 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_mcpcf_db_isolation.py`（rc=0，本轮**首次实跑**）
- `python scripts/check_foreign_ledger_entries.py`（rc=1，本轮复测）
- `python scripts/check_tools_sync.py`（rc=0）/ `python scripts/check_instruction_budget.py`（rc=0）
- FIST 闭环 T0r41 收口（wd-r285，ns watchdog，6 步后台串跑 `temp/fist_r285_chain.sh`，回包落盘 `temp/fist_r285_out/`）
- r284 报告磁盘原件（`reports/2026-11-14-r284-watchdog-bug583-guard-wip-report.md`，本轮只读核验 + 结构对齐）
