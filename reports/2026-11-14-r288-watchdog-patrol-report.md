# 轮 288 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

**WIP 面冻结零变化（第 5 轮）**：四件套 mtime（10:47:48 / 10:55:34 / 2026-11-10 10:34:16 / 11:11:49）全部早于 r284 提交（15:19:37），`git diff --stat` 与 r284~r287 逐字相同（3 文件 208+/2-），**本轮相对 r287 零新增量**。弃置裁决件自 r287 起提请 owner，**维持挂起、指挥官不代行清理**。Round C 三件维持过期不执行。

本轮换面巡检一格（`check_publish_payload`，发布载荷面守卫 · BUG-127 常驻判据，r287 之后首次跑）+ 两个零漂移基线，**无新增量、无新立账**：

- **`check_publish_payload --selftest` rc=0**：8 格（S0 沙箱形状自证 / M4 非 git 仓自拒 / G1 干净不误红 / G2 逐件点名无幻影 / M1 未跟踪未忽略必红 / M2 被 ignore 挡不红 / M3 凭据形状必点名 P2 / M5 拆件幂等）全部打在 temp 合成仓根，真树一字节未动。
- **`check_publish_payload` 实测 rc=1（脏树投影，非回归）**：P1 **仅点名 1 件** `scripts/check_mcpcf_db_isolation.py`（未跟踪 + 未被 .gitignore 挡 ⇒ 下一次 `moon publish` 会把它公开出去）；**无 P2 凭据形状**。该件即 WIP 在飞守卫（r285 已预核主面 rc=0、静态 4/4），风险收敛为「收口时未配执行面 ⇒ `check_battery_count_doc` FATAL」（见遗留风险 1），与 r285/r286/r287 冻结面同源、零增长。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183（与实测对表）。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~18 次（只读核验 6 + 巡检守卫 4 + FIST 闭环脚本 2 + 报告/日志/收口 6）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 5 轮）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283~r287） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635，白名单外 23 条零增长） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（维持 r287 提请）**：WIP 面已连续 5 轮零变化（r284 检测到未收口 → r285/r286/r287/r288 逐轮零变化，四件套 mtime 全早于 r284 提交 15:19:37）。r287 已正式提请 owner 裁决，**本轮维持挂起**，继续以 bugs.md mtime 是否变化作为裁决落地信号；清理权保留给 owner / 另一 agent，指挥官不代行（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_publish_payload --selftest`（旋转面） | **rc=0，8 格全绿**（hermetic 合成仓） | r287 之后首次跑（该面此前未列入旋转面） |
| `check_publish_payload` 实测 | **rc=1 脏树投影：P1 仅 1 件（check_mcpcf_db_isolation.py，WIP 在飞件），无 P2 凭据形状** | 与 r285 静态面 / r287 外来账面同源零增长 |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285~r287（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283/r285/r286/r287 |

## FIST 闭环（T0r44 · wd-r288 · ns watchdog）

**6 步全链后台串跑 rc=0**（脚本 `temp/fist_r288_chain.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285~r287 结构；FIST_DB_PATH 改道 temp/fist-selfiter.db）：

| 步 | rc | 状态迁移 |
|---|---|---|
| publish | 0 | 发布 T0r44（writable_agents 42→43，claim_ready） |
| agent_acl_grant | 0 | can_write=true（wd-r288，granted_rows=2bdd1cb0694faf32） |
| claim | 0 | 已领取（assignee=wd-r288） |
| execute | 0 | 执行中（deliverable=本报告） |
| submit | 0 | 待验收 |
| verify | 0 | 已完成（completed_by=wd-r288） |

各步回包落盘 `temp/fist_r288_out/1..6_*.txt`。本轮无首发失败，一发收口。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持，本轮由发布载荷面再次实证）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP、无执行面，且本轮 `check_publish_payload` P1 实证它**会被下一次 `moon publish` 公开**（载荷面 = 工作树 − ignore）。风险双格：收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）；没收口而先发布 ⇒ 一份半成品守卫随包公开（无凭据形状，卫生问题非事故）。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条零增长维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **WIP 面连续 5 轮零变化（r287 已提请裁决，本轮维持）**：owner 裁决前继续观察 bugs.md mtime。
5. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【维持 r287 提请 · owner 裁决】WIP 弃置信号已达标**：四件套连续 5 轮零变化，建议 owner 裁决另一 agent 收口（配 BUG-583 执行面 + 注意发布载荷面 P1）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**。
2. 若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc（r285 已预核主面 rc=0，收口时只需补前两格）；**另注意 `check_publish_payload` P1 会随入库自动转绿**（跟踪文件不在红面）。
3. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
4. 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_publish_payload.py --selftest`（rc=0，8 格）/ `python scripts/check_publish_payload.py`（rc=1，P1 仅 1 件，无 P2）
- `python scripts/check_tools_sync.py`（rc=0，183 零漂移）/ `python scripts/check_instruction_budget.py`（rc=0，50440/65536）
- FIST 闭环 T0r44 收口（wd-r288，ns watchdog，6 步后台串跑 `temp/fist_r288_chain.sh`，回包落盘 `temp/fist_r288_out/`）
- r287 报告磁盘原件（`reports/2026-11-14-r287-watchdog-patrol-report.md`，本轮只读核验 + 结构对齐）
