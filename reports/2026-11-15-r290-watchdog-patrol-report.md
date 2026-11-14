# 轮 290 巡检报告（ExploreWatchdog · 2026-11-15）

## 结果摘要

**WIP 面冻结零变化（第 7 轮 · 跨日）**：四件套 mtime（bugs.md 10:47:48 / improvement-plan 10:55:34 / target.md 2026-11-10 10:34:16 / check_mcpcf_db_isolation.py 11:11:49）全部早于 r284 提交（15:19:37），且**已跨日（11-14 → 11-15）仍冻结**；`git diff --stat` 与 r284~r289 逐字相同（3 文件 208+/2-），**本轮相对 r289 零新增量**。弃置裁决件自 r287 起提请 owner，**维持挂起、指挥官不代行清理**。Round C 三件维持过期不执行。

本轮换面巡检一格（`check_store_tables_wired`，BUG-28 store 表接线守卫，r285~r289 之后近期未跑过的核心正确性守卫）+ 两个零漂移基线，**无新增量、无新立账**：

- **`check_store_tables_wired --selftest` rc=0**：判据对「死 schema」（表无写入点也未预留）与「声明滞后」（预留声明与实际不符）两个方向都发红，干净输入不误红，表名解析口径可证。
- **`check_store_tables_wired` 实测 rc=0**：**32 张表 = 31 张有写入点 + 1 张显式预留（`runs`）**，store 表接线一致。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单分组 19 组 ΣN=183（与实测对表）。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~16 次（只读核验 6 + 巡检守卫 4 + FIST 闭环脚本 2 + 报告/日志 4）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 7 轮 · 跨日）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283~r289） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635，白名单外 23 条零增长） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（维持 r287 提请）**：WIP 面已连续 7 轮零变化（r284 检测到未收口 → r285/r286/r287/r288/r289/r290 逐轮零变化，四件套 mtime 全早于 r284 提交 15:19:37），且**本轮已跨日（11-14 → 11-15）仍冻结**——跨日零变化比同日内零变化更强的弃置信号。r287 已正式提请 owner 裁决，**本轮维持挂起**，继续以 bugs.md mtime 是否变化作为裁决落地信号；清理权保留给 owner / 另一 agent，指挥官不代行（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_store_tables_wired --selftest`（旋转面） | **rc=0**（死 schema / 声明滞后两向都红，干净输入不红） | r285~r289 之后近期首跑 |
| `check_store_tables_wired` 实测 | **rc=0：32 表 = 31 有写入点 + 1 显式预留（runs）** | 该面近期未纳入巡检，基线即 store 表接线一致 |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285~r289（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283~r289 |

## FIST 闭环（T0r46 · wd-r290 · ns watchdog）

**6 步全链后台串跑**（脚本 `temp/fist_r290_chain.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285~r289 结构；FIST_DB_PATH 改道 temp/fist-selfiter.db）：

| 步 | 状态迁移 |
|---|---|
| publish | 发布 T0r46（claim_ready） |
| agent_acl_grant | can_write=true（wd-r290） |
| claim | 已领取（assignee=wd-r290） |
| execute | 执行中（deliverable=本报告） |
| submit | 待验收 |
| verify | 已完成（completed_by=wd-r290） |

各步回包落盘 `temp/fist_r290_out/1..6_*.txt`（收口读数见提交说明）。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP、无执行面，风险双格：收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）；没收口而先发布 ⇒ 一份半成品守卫随包公开（r288 `check_publish_payload` P1 已实证该件会被 `moon publish` 公开，无凭据形状，卫生问题非事故）。r285 已预核其主面静态 4/4+碰撞格空过 rc=0、r289 `check_arg_face_strict` 另证其参数面合格。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条零增长维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **WIP 面连续 7 轮零变化（r287 已提请裁决，本轮跨日仍冻结）**：owner 裁决前继续观察 bugs.md mtime。
5. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【维持 r287 提请 · owner 裁决】WIP 弃置信号已达标且跨日加强**：四件套连续 7 轮零变化（跨日 11-14→11-15），建议 owner 裁决另一 agent 收口（配 BUG-583 执行面 + 注意发布载荷面 P1）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**。
2. 若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc（r285 已预核主面 rc=0，收口时只需补前两格）；arg 面 r289 已证合格、`check_publish_payload` P1 会随入库自动转绿（跟踪文件不在红面）。
3. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
4. 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_store_tables_wired.py --selftest`（rc=0）/ `python scripts/check_store_tables_wired.py`（rc=0，32 表 = 31 写入点 + 1 预留 runs）
- `python scripts/check_tools_sync.py`（rc=0，183 零漂移）/ `python scripts/check_instruction_budget.py`（rc=0，50440/65536）
- FIST 闭环 T0r46 收口（wd-r290，ns watchdog，6 步后台串跑 `temp/fist_r290_chain.sh`，回包落盘 `temp/fist_r290_out/`）
- r289 报告磁盘原件（`reports/2026-11-14-r289-watchdog-patrol-report.md`，本轮只读核验 + 结构对齐）
