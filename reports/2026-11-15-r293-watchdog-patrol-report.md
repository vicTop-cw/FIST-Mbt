# 轮 293 巡检报告（ExploreWatchdog · 2026-11-15）

## 结果摘要

**WIP 面冻结零变化（第 10 轮 · 跨日）**：四件套 mtime（2026-11-10 10:34:16 / 11-14 10:47:48 / 11-14 10:55:34 / 11-14 11:11:49）逐字同 r284~r292，`git diff --stat` 与 r284~r292 逐字相同（3 文件 208+/2-），**本轮相对 r292 零新增量**。Round C 三件维持过期不执行。

本轮换面巡检一格（`check_pkg_imports`，本地包 import ↔ 跟踪面目录存在性）+ 两个零漂移基线，**均绿、无新发现**：

- **`check_pkg_imports --selftest` rc=0（8/8）**：合成违例必红（P1 形态：import 了跟踪面不存在的本地包）/ 真实形状必红（master 坏状态原形）/ `@alias` 别名不误红 / 外部依赖不判 / 模块根自身不判 / 判据空转两格（`emit_fatal` 返 2 + 子进程实测 rc 真是 2，改前同一条只给 1）。
- **`check_pkg_imports` 实测 rc=0**：29 份 `moon.pkg` 的 **40 条本地 import 指向的目录全在跟踪面**（钉的是 2026-10-13 那起「改了 moon.pkg 却没 add 包目录 ⇒ 干净树 `moon check` 崩、CI 红在 Migrate 步并 skip 其后 21 步」的真失效形态）。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183（与实测对表）。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~16 次（WIP/日志核对 3 + 守卫枚举与候选自述 2 + 换面巡检 2 + 报告/日志 3 + FIST 闭环脚本 2 + 其余核验）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 10 轮 · 跨日）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283~r292） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635，白名单外 23 条零增长） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（维持 r287 提请）**：WIP 面已连续 10 轮零变化（r284 检测到未收口 → r285~r293 逐轮零变化，四件套 mtime 全早于 r284 提交 15:19:37），且**已跨日（11-14 → 11-15）两天内仍冻结**。r287 已正式提请 owner 裁决，**本轮维持挂起**，继续以 bugs.md mtime 是否变化作为裁决落地信号；清理权保留给 owner / 另一 agent，指挥官不代行（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检 + 零漂移基线）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_pkg_imports --selftest`（旋转面） | **rc=0（8/8）**（合成违例/真实形状必红、alias/外部依赖/模块根不误红、空转 rc=2 两格） | r280~r292 未跑过，本轮首跑 |
| `check_pkg_imports` 实测 | **rc=0：29 份 moon.pkg 的 40 条本地 import 全在跟踪面** | 该面自 2026-10-13 立规后近期未纳入巡检，基线即 import 存在性一致 |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285~r292（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283~r292 |

## FIST 闭环（T0r49 · wd-r293 · ns watchdog）

**6 步全链后台串跑**（脚本 `temp/fist_r293_loop.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285~r292 结构）：

| 步 | 状态迁移 |
|---|---|
| publish | 发布 T0r49（claim_ready） |
| agent_acl_grant | can_write=true（wd-r293） |
| claim | 已领取（assignee=wd-r293） |
| execute | 执行中（deliverable=本报告） |
| submit | 待验收 |
| verify | 已完成（completed_by=wd-r293） |

各步回包落盘 `temp/fist_r293_out/1..6_*.txt`（6 步 rc 全 0，CHAIN DONE，verify 回执 status=已完成）。

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
5. **WIP 面连续 10 轮零变化（r287 已提请裁决，跨日两天仍冻结）**：owner 裁决前继续观察 bugs.md mtime。
6. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【维持 r287 提请 · owner 裁决】WIP 弃置信号已达标且跨日两天加强**：四件套连续 10 轮零变化（跨日 11-14→11-15），建议 owner 裁决另一 agent 收口（配 BUG-583 执行面 + 注意发布载荷面 P1）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**。
2. **【维持 r292 建议 · 单列待裁决】扩 `check_doc_surface` J14 / `check_tools_sync` R3b 守卫面**：把 5 个 J14 面的「N 工具」形状显式认领（各补正/反夹具），杜绝「加工具只更 README/AGENTS ⇒ 5 面再漂」复发。
3. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
4. 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读，逐字同 r292）
- `python scripts/check_pkg_imports.py --selftest`（rc=0，8/8）/ `python scripts/check_pkg_imports.py`（rc=0，29 份 moon.pkg 的 40 条本地 import 全在跟踪面）
- `python scripts/check_tools_sync.py`（rc=0，183 零漂移）/ `python scripts/check_instruction_budget.py`（rc=0，50440/65536）
- FIST 闭环 T0r49 收口（wd-r293，ns watchdog，6 步后台串跑 `temp/fist_r293_loop.sh`，回包落盘 `temp/fist_r293_out/`，verify 回执 status=已完成）
- r292 报告磁盘原件（`reports/2026-11-15-r292-watchdog-j14-toolcount-fix-report.md`，结构对齐）
