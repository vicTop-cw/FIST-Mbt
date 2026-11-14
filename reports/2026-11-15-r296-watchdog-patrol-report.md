# 轮 296 巡检报告（ExploreWatchdog · 2026-11-15）

## 结果摘要

**WIP 面冻结零变化（第 13 轮 · 跨日）**：四件套 mtime（2026-11-10 10:34:16 / 11-14 10:47:48 / 11-14 10:55:34 / 11-14 11:11:49）逐字同 r284~r295，`git diff --stat` 与 r284~r295 逐字相同（3 文件 208+/2-），**本轮相对 r295 零新增量**。Round C 三件维持过期不执行。

本轮换面巡检一格（`check_workflow_step_parity`，CI workflow「跑 moon 的 job 必须先 migrate」尺）+ 两个零漂移基线，**均绿、无新发现**：

- **`check_workflow_step_parity --selftest` rc=0（7 格）**：干净不误红 / 缺 migrate 必红 / 顺序错必红 / 空 job 自拒 / 空 moon 自拒 / 未豁免的静默 job 必报 / 同步合规，全部真断言。
- **`check_workflow_step_parity` 实测 rc=0**：扫描面 `.github/workflows/ci.yml` + `release.yml`，跑 moon 的 job **6** 个 / 有 migrate 的 job **6** 个，全部「跑 moon」的 job 都**先** migrate，不跑 moon 的 job 已逐条点名理由。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~20 次（WIP/日志核对 3 + 守卫枚举 2 + 换面巡检 1 + 零漂移 1 + FIST 闭环 4 + 报告/日志 3 + 轮次/落盘核对 3）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 13 轮 · 跨日）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283~r295） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635，白名单外 23 条零增长） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（维持 r287 提请）**：WIP 面已连续 13 轮零变化（r284 检测到未收口 → r285~r296 逐轮零变化，四件套 mtime 全早于 r284 提交 15:19:37），且**已跨日（11-14 → 11-15）两天内仍冻结**。r287 已正式提请 owner 裁决，**本轮维持挂起**，继续以 bugs.md mtime 是否变化作为裁决落地信号；清理权保留给 owner / 另一 agent，指挥官不代行（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检 + 零漂移基线）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_workflow_step_parity --selftest`（旋转面） | **rc=0（7 格）**（干净不误红 / 缺 migrate 必红 / 顺序错必红 / 空 job 自拒 / 空 moon 自拒 / 未豁免的静默 job 必报 / 同步合规） | r284~r295 未跑过，本轮首跑 |
| `check_workflow_step_parity` 实测 | **rc=0：ci.yml+release.yml，跑 moon 的 job 6 / 有 migrate 6，全部先 migrate** | 该面近期未纳入巡检，基线即 6 job 全合规 |
| `check_tools_sync` | rc=0（183 零漂移，19 组 ΣN=183） | 同 r285~r295（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283~r295 |

## FIST 闭环（T0r52 · wd-r296 · ns watchdog）

**6 步全链后台串跑**（`temp/fist_r296_chain.sh` → `temp/fist_r296_out/` 落盘；publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285~r295 结构）：

| 步 | 状态迁移 |
|---|---|
| publish | 发布 T0r52（claim_ready） |
| agent_acl_grant | can_write=true（wd-r296） |
| claim | 已领取（assignee=wd-r296） |
| execute | 执行中（deliverable=本报告） |
| submit | 待验收 |
| verify | 已完成（completed_by=wd-r296） |

各步回包落盘 `temp/fist_r296_out/1..6_*.txt`（6 步 rc 全 0，CHAIN DONE，verify 回执 status=已完成）。

**账本落点注**：本轮 `FIST_DB_PATH` 未设 ⇒ T0r52 落**默认账本** `fist-mbt.db`（`.gitignore:15 *.db` 已挡，无跟踪面污染）。r290/r291 曾显式改道 `temp/fist-selfiter.db`；本轮回默认账本不改变任何跟踪面，仅本地运行态多一行看门狗记账。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，d43a06a28 治本→8a669992d 回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行（即便 `src/**` 未被 WIP 占用也不重推导）。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP、无执行面，风险双格：收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）；没收口而先发布 ⇒ 一份半成品守卫随包公开（r288 `check_publish_payload` P1 已实证该件会被 `moon publish` 公开，无凭据形状，卫生问题非事故）。r285 已预核其主面静态 4/4+碰撞格空过 rc=0、r289 `check_arg_face_strict` 另证其参数面合格。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条零增长维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **`check_doc_surface` J14 盲区（r292 修了值、未修面）**：`help_topics.mbt`/`ARCHITECTURE.md`/`tool_use_rubric.md`/`agent-map.md`/`deliverable.md` 这 5 面的「N 工具」形状无人认领 ⇒ 下次加工具若只更 README/AGENTS 会再漂。扩面是内容决策，维持 r292 建议单列待裁决。
5. **WIP 面连续 13 轮零变化（r287 已提请裁决，跨日两天仍冻结）**：owner 裁决前继续观察 bugs.md mtime。
6. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【维持 r287 提请 · owner 裁决】WIP 弃置信号已达标且跨日两天加强**：四件套连续 13 轮零变化（跨日 11-14→11-15），建议 owner 裁决另一 agent 收口（配 BUG-583 执行面 + 注意发布载荷面 P1）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**。
2. **【维持 r292 建议 · 单列待裁决】扩 `check_doc_surface` J14 / `check_tools_sync` R3b 守卫面**：把 5 个 J14 面的「N 工具」形状显式认领（各补正/反夹具），杜绝「加工具只更 README/AGENTS ⇒ 5 面再漂」复发。
3. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
4. 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读，逐字同 r295）
- `python scripts/check_workflow_step_parity.py --selftest`（rc=0，7 格）/ `python scripts/check_workflow_step_parity.py`（rc=0，6 job 全先 migrate）
- `python scripts/check_tools_sync.py`（rc=0，183 零漂移）/ `python scripts/check_instruction_budget.py`（rc=0，50440/65536）
- FIST 闭环 T0r52 收口（wd-r296，ns watchdog，6 步后台串跑，回包落盘 `temp/fist_r296_out/`，verify 回执 status=已完成、completed_by=wd-r296）
- r295 报告磁盘原件（`reports/2026-11-15-r295-watchdog-patrol-report.md`，结构对齐）
