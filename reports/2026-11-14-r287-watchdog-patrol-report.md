# 轮 287 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

**WIP 面冻结零变化（第 4 轮）**：四件套 mtime（10:47:48 / 10:55:34 / 2026-11-10 10:34:16 / 11:11:49）全部早于 r284 提交（15:19:37），`git diff --stat` 与 r284/r285/r286 逐字相同（3 文件 208+/2-），**本轮相对 r286 零新增量**。Round C 三件维持过期不执行。

**本轮关键信号——弃置触发线已达成**：r286 后续建议预设「再连续 1~2 轮冻结（r287/r288）即达『可能弃置』信号阈值、提请 owner 裁决」。**本轮即 r287（连续第 4 轮冻结）⇒ 已达标**，正式提请 owner 裁决（**不代行清理**，见后续建议 1）。

本轮换面巡检一格（`check_foreign_ledger_entries`，r285 上次跑、本轮回旋复跑核增长）+ 两个零漂移基线，**无新增量、无新立账**：

- **`check_foreign_ledger_entries` rc=1（脏树投影，非回归）**：白名单外 **23 条**（BUG-613~635），**与 r285 逐字同（23 条、最高 BUG-635），零增长**；全部 vq 项目缺陷（信号面 crates/,vq-cli/core/pyo3、apps/,data/、packages/），待 owner 裁决（r245 三件之一，指挥官不代行跨仓不可逆）。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183（与实测对表）。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~15 次（只读核验 5 + 巡检守卫 3 + FIST 闭环脚本 2 + 报告/日志/收口 5）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 4 轮）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283/r284/r285/r286） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635，白名单外 23 条零增长） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（本轮达触发线）**：WIP 面已连续 4 轮零变化（r284 检测到未收口 → r285/r286/r287 逐轮零变化，四件套 mtime 全早于 r284 提交 15:19:37）。按 r286 预设口径，**本轮（r287）已达「可能弃置」触发线 ⇒ 正式提请 owner 裁决**另一 agent 是否收口四件套或确认为弃置；**清理权保留给 owner / 另一 agent，指挥官不代行**（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_foreign_ledger_entries`（旋转面） | **rc=1 脏树投影：白名单外 23 条（BUG-613~635，最高 BUG-635）** | r285 同态（23 条 / BUG-635）⇒ **零增长**；全 vq 项目缺陷，待 owner 裁决 |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285/r286（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283/r285/r286 |

## FIST 闭环（T0r43 · wd-r287 · ns watchdog）

**6 步全链后台串跑 rc=0**（脚本 `temp/fist_r287_chain.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285/r286 结构；FIST_DB_PATH 改道 temp/fist-selfiter.db）：

| 步 | rc | 状态迁移 |
|---|---|---|
| publish | 0 | 发布 T0r43（writable_agents 41→42，claim_ready） |
| agent_acl_grant | 0 | can_write=true（wd-r287，granted_rows=2bdd1fb0694fb44b） |
| claim | 0 | 已领取（assignee=wd-r287） |
| execute | 0 | 执行中（deliverable=本报告） |
| submit | 0 | 待验收 |
| verify | 0 | 已完成（completed_by=wd-r287） |

各步回包落盘 `temp/fist_r287_out/1..6_*.txt`。

> ⚠️ **补记（本轮收口 · 诚实记账）**：r287 首发链路（16:44）在 `patch_esm_main` 读 bundle 时抛 **transient `MemoryError`**（server 未起、**0 条入 `call_log`**），链路随即在 task_id 提取处 FATAL 退出，报告在 FIST 收口前被写盘（首发 `temp/fist_r287_out/` 仅存 `1_publish.txt` 的 traceback）。本轮 probe 确认系内存瞬时压力（10 bundle 全 `up to date`、2.6s、无复现）后重跑同脚本，6 步全链 rc=0（`call_log` seq 106–111 全 `ok`），T0r43 落定、writable_agents 41→42、granted_rows=2bdd1fb0694fb44b。本段数值已按真实回执核对。

## Round C 队列状态（依据记忆裁定 + 本轮 grep 复核，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（**本轮 grep 复核 run_guards.py:175 在案**）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP，无执行面。r285 实跑已确认脚本本身是好的（rc=0，静态 4/4 过），风险收敛为「另一 agent 收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）」。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条零增长维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **WIP 面连续 4 轮零变化（本轮达弃置触发线）**：已提请 owner 裁决（见后续建议 1），继续观察 bugs.md mtime 是否变化作为裁决落地信号。
5. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【本轮新增 · 提请 owner 裁决】WIP 弃置信号已达标**：四件套连续 4 轮零变化达 r286 预设触发线，建议 owner 裁决另一 agent 收口（配 BUG-583 执行面）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**；owner 裁决后由 owner / 另一 agent 执行。
2. 若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc（r285 已预核主面 rc=0，收口时只需补前两格）。
3. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
4. 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_foreign_ledger_entries.py`（rc=1 脏树投影，白名单外 23 条 BUG-613~635，零增长，本轮旋转面）
- `python scripts/check_tools_sync.py`（rc=0，183 零漂移）/ `python scripts/check_instruction_budget.py`（rc=0，50440/65536）
- `scripts/run_guards.py` grep 复核（check_usage_tool_count 已注册 :175；check_foreign_ledger_entries 已注册 :333-334；check_mcpcf_db_isolation 未注册）
- FIST 闭环 T0r43 收口（wd-r287，ns watchdog，6 步后台串跑 `temp/fist_r287_chain.sh`，回包落盘 `temp/fist_r287_out/`）
- r286 报告磁盘原件（`reports/2026-11-14-r286-watchdog-patrol-report.md`，本轮只读核验 + 结构对齐）
