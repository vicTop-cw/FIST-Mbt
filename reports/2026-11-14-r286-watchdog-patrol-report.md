# 轮 286 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

**WIP 面冻结零变化（第 3 轮）**：四件套 mtime（10:47:48 / 10:55:34 / 2026-11-10 10:34:16 / 11:11:49）全部早于 r284 提交（15:19:37），`git diff --stat` 与 r284/r285 逐字相同（3 文件 208+/2-），**本轮相对 r285 零新增量**。Round C 三件维持过期不执行。

本轮换面巡检一格（`check_host_installable`，r281 起未跑的旋转面）+ 两个零漂移基线，**均绿、无新发现**：

- **`check_host_installable` rc=0（PASS）**：DSH 严格档（绝对路径 + `toolCallTimeoutMs` + dsh reconnect schema）合规、宽松档 MCP JSON 合规、默认模板合法性合规；moon.mod 版本 0.3.11。3 条 **info 级** WARN（`.mcp.json` / `.mcp.dev.json` / `plugins/claude/.mcp.json` 的 `fist-mbt` 用 `timeout_ms`）为既有信息级（守卫明言「是否改真源由人终审」，不计入 exit 1），非回归、不新立账。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183（与实测对表）。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~12 次（只读核验 5 + 巡检守卫 1 合并批 + FIST 闭环脚本 2 + 收口 4）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 3 轮）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283/r284/r285） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读**：WIP 面已连续 3 轮零变化（四件套 mtime 全早于 r284 提交）。按 r285 后续建议口径（「再连续 2~3 轮冻结」⇒ 可能是**弃置**而非进行中），**本轮尚未到触发线**——再连续 1~2 轮冻结（r287/r288）即达「提请 owner 关注」阈值。届时在巡检报告中提请，**仍不代行清理**。

## 守卫面（换面巡检）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_host_installable`（旋转面） | **rc=0（PASS：DSH 严格档 + 宽松档 + 默认模板全合规，moon.mod 0.3.11）** | r281 起未跑 ⇒ **本轮旋转复跑**；3 条既有 info 级 `timeout_ms` WARN（不计 exit 1） |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283/r285 |

## FIST 闭环（T0r42 · wd-r286 · ns watchdog）

**6 步全链后台串跑 rc=0**（脚本 `temp/fist_r286_chain.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285 结构；FIST_DB_PATH 改道 temp/fist-selfiter.db）：

| 步 | rc | 状态迁移 |
|---|---|---|
| publish | 0 | 发布 T0r42（writable_agents 40→41，claim_ready） |
| agent_acl_grant | 0 | can_write=true（pid_bound=false，granted_rows=2bdd1eb0694fb298） |
| claim | 0 | 已领取（assignee=wd-r286） |
| execute | 0 | 执行中（deliverable=本报告） |
| submit | 0 | 待验收 |
| verify | 0 | 已完成（completed_by=wd-r286） |

各步回包落盘 `temp/fist_r286_out/1..6_*.txt`。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP，无执行面。r285 实跑已确认脚本本身是好的（rc=0，静态 4/4 过），风险收敛为「另一 agent 收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）」。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES（它是独立判据，非共享模块/一次性工具）。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。
5. **WIP 面连续 3 轮零变化**：弃置信号累积中（未达触发线，见 WIP 面节判读），继续观察。

## 后续建议

- 下一轮若 WIP 再冻结 1~2 轮（r287/r288），达「可能弃置」信号阈值，提请 owner 裁决另一 agent 是否收口四件套或弃置（仍不代行清理）。
- 若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc（r285 已预核主面 rc=0，收口时只需补前两格）。
- 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
- 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_host_installable.py`（rc=0，本轮旋转面）
- `python scripts/check_tools_sync.py`（rc=0）/ `python scripts/check_instruction_budget.py`（rc=0）
- FIST 闭环 T0r42 收口（wd-r286，ns watchdog，6 步后台串跑 `temp/fist_r286_chain.sh`，回包落盘 `temp/fist_r286_out/`）
- r285 报告磁盘原件（`reports/2026-11-14-r285-watchdog-patrol-report.md`，本轮只读核验 + 结构对齐）
