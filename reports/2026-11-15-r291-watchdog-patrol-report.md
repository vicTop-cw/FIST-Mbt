# 轮 291 巡检报告（ExploreWatchdog · 2026-11-15）

## 结果摘要

**WIP 面冻结零变化（第 8 轮 · 跨日）**：四件套 mtime（2026-11-10 10:34:16 / 11-14 10:47:48 / 11-14 10:55:34 / 11-14 11:11:49）全部早于 r284 提交（15:19:37），`git diff --stat` 与 r284~r290 逐字相同（3 文件 208+/2-），**本轮相对 r290 零新增量**。Round C 三件维持过期不执行。

本轮换面巡检一格（`check_sql_bind_alignment`，R177 SQL 三方对齐）+ 两个零漂移基线，**均绿、无新发现**：

- **`check_sql_bind_alignment --selftest` rc=0（7/7）**：s1 对齐样本判绿 / s2 少一个 bind ⇒ 红 / s3 列数≠占位符 ⇒ 红 / s4 插值列 ⇒ 绿但计入 degraded / s5 bind 缺号 ⇒ 红 / s7 委托助手绑定 ⇒ 绿且 degraded / s6 无样本 ⇒ rc=2（不自证归 2 不归 0）。
- **`check_sql_bind_alignment` 实测 rc=0**：门禁 PASS **19 处 INSERT 三方对齐**（占位符=bind 全对；其中 3 处列数为插值、仅校验占位符，degraded 计入）。
- **`check_tools_sync` rc=0（零漂移）**：server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183（与实测对表）。
- **`check_instruction_budget` rc=0**：AGENTS.md 50440/65536（全部章节可见）。

无新立账项。

## 资源消耗

- 工具调用 ~16 次（只读核验 6 + 换面确认 4 + 巡检守卫 1 + FIST 闭环脚本 2 + 报告/日志 3）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 冻结零变化第 8 轮 · 跨日）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | 未动（同 r283~r290） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 未动（P3~P7 误落账，现最高 BUG-635，白名单外 23 条零增长） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 未动（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**弃置信号判读（维持 r287 提请）**：WIP 面已连续 8 轮零变化（r284 检测到未收口 → r285~r291 逐轮零变化，四件套 mtime 全早于 r284 提交 15:19:37），且**已跨日（11-14 → 11-15）两天内仍冻结**。r287 已正式提请 owner 裁决，**本轮维持挂起**，继续以 bugs.md mtime 是否变化作为裁决落地信号；清理权保留给 owner / 另一 agent，指挥官不代行（跨仓不可逆 + 禁区文件）。

## 守卫面（换面巡检）

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_sql_bind_alignment --selftest`（旋转面） | **rc=0（7/7）**（少 bind / 列数≠占位符 / bind 缺号三向都红，无样本归 rc=2 不归 0） | r285~r290 之后近期首跑 |
| `check_sql_bind_alignment` 实测 | **rc=0：19 处 INSERT 三方对齐**（3 处插值列 degraded，仅校验占位符） | 该面近期未纳入巡检，基线即 SQL 绑定一致 |
| `check_tools_sync` | rc=0（183 零漂移） | 同 r285~r290（零漂移） |
| `check_instruction_budget` | 50440/65536，rc=0 | 同 r283~r290 |

## FIST 闭环（T0r47 · wd-r291 · ns watchdog）

**6 步全链后台串跑**（脚本 `temp/fist_r291_chain.sh`：publish 后从回包 JSON 提取 task_id 再串后 5 步，沿用 r285~r290 结构；FIST_DB_PATH 改道 temp/fist-selfiter.db）：

| 步 | 状态迁移 |
|---|---|
| publish | 发布 T0r47（claim_ready） |
| agent_acl_grant | can_write=true（wd-r291） |
| claim | 已领取（assignee=wd-r291） |
| execute | 执行中（deliverable=本报告） |
| submit | 待验收 |
| verify | 已完成（completed_by=wd-r291） |

各步回包落盘 `temp/fist_r291_out/1..6_*.txt`（6 步 rc 全 0，CHAIN DONE，verify 回执 status=已完成）。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（r284 起维持）**：`scripts/check_mcpcf_db_isolation.py` 仍为未跟踪 WIP、无执行面，风险双格：收口时只提交脚本不配执行面 ⇒ `check_battery_count_doc` FATAL（缺面清单）；没收口而先发布 ⇒ 一份半成品守卫随包公开（r288 `check_publish_payload` P1 已实证该件会被 `moon publish` 公开，无凭据形状，卫生问题非事故）。r285 已预核其主面静态 4/4+碰撞格空过 rc=0、r289 `check_arg_face_strict` 另证其参数面合格。建议不变：收口时以 `case(...)` 进电池或带理由 `expected(...)`，不建议 EXEMPT_RULES。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条零增长维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **WIP 面连续 8 轮零变化（r287 已提请裁决，本轮跨日两天仍冻结）**：owner 裁决前继续观察 bugs.md mtime。
5. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

1. **【维持 r287 提请 · owner 裁决】WIP 弃置信号已达标且跨日两天加强**：四件套连续 8 轮零变化（跨日 11-14→11-15），建议 owner 裁决另一 agent 收口（配 BUG-583 执行面 + 注意发布载荷面 P1）或确认弃置。清理属跨仓不可逆 + 禁区文件，**指挥官不代行**。
2. 若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc（r285 已预核主面 rc=0，收口时只需补前两格）；arg 面 r289 已证合格、`check_publish_payload` P1 会随入库自动转绿（跟踪文件不在红面）。
3. 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
4. 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -6` / `git diff --stat`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_sql_bind_alignment.py --selftest`（rc=0，7/7）/ `python scripts/check_sql_bind_alignment.py`（rc=0，19 处 INSERT 三方对齐、3 处插值列 degraded）
- `python scripts/check_tools_sync.py`（rc=0，183 零漂移）/ `python scripts/check_instruction_budget.py`（rc=0，50440/65536）
- FIST 闭环 T0r47 收口（wd-r291，ns watchdog，6 步后台串跑 `temp/fist_r291_chain.sh`，回包落盘 `temp/fist_r291_out/`，verify 回执 status=已完成）
- r290 报告磁盘原件（`reports/2026-11-15-r290-watchdog-patrol-report.md`，本轮只读核验 + 结构对齐）
