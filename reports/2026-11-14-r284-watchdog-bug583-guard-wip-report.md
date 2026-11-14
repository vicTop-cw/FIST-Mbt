# 轮 284 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

**WIP 面维持未收口（4 文件，均为另一 agent WIP），本轮相对 r283 的唯一新增量 = BUG-583 方向④ 守卫**。r283 提交（11:09:59）后 2 分钟（11:11:49）落盘一份**未跟踪**新文件 `scripts/check_mcpcf_db_isolation.py`——BUG-583 方向④ 判据：**mcpcf 沙箱库路径 ≠ 主库路径**（把「两条路径家族不相交」从注释里的约定变成机器可核断言）。该脚本现状**未注册电池执行面**（`run_guards.py` 不在 WIP 面，全 `scripts/` 树无 case/expected/EXEMPT_RULES 引用）⇒ 另一 agent 若只提交脚本而不配执行面，`check_battery_count_doc` 将 FATAL（缺面清单）。**禁区零碰、不提交、指挥官不代行**（属另一 agent WIP）。

其余 3 个 WIP 文件与 r283 逐字未变：`memory/bugs.md`（P3~P7 跨项目误落账，现最高 BUG-635，待 owner 裁决）、`docs/improvement-plan-20261010.md`（BUG-589 A 档措辞校正）、`memory/target.md`（Round 24 孤儿行，2026-11-10 陈旧内容）。

零漂移 `check_tools_sync` PASS（183，rc=0，本轮复测）。Round C 三件维持过期不执行。FIST 闭环 T0r40 收口（wd-r284）。

## 资源消耗

- 工具调用 ~22 次（只读核验 12 + 零漂移守卫 1 + FIST 闭环脚本 2 + 收口 7）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（4 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（未收口 —— 新增 BUG-583 方向④ 守增量）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `scripts/check_mcpcf_db_isolation.py` | 2026-11-14 11:11:49 | **新增量**：BUG-583 方向④ 守卫（未跟踪，530 行 / 22 符号） |
| `memory/bugs.md` | 2026-11-14 10:47:48 | 同 r283（P3~P7 误落账，现最高 BUG-635） |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | 同 r283（BUG-589 A 档校正） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

四文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**BUG-583 方向④ 守卫定性**（本轮只读其 docstring + 骨架，不执行）：
- **判据面（真源现读，不抄副本）**：mcpcf 库名/目录优先级/回退目录从 `src/server/mcpcf_embed.mbt` 的 `ops_data_dir()` 与三处库名拼接现解析；主库 data_dir 默认与 ns 库形状从 `multi_store.mbt` 现解析；主库默认库名/env 键/trim 事实从 `store_sqlite.mbt` 现解析。任一份读不到/为空/解析不出 ⇒ 自拒 rc=2，绝不给绿。
- **A1-A4 静态断言（默认配置下两条路径家族不相交）**：A1 mcpcf 默认目录后缀段族 ∩ 主库 data_dir 段族 = ∅；A2 mcpcf 回退目录（cwd 相对）∩ 主库 data_dir 段族 = ∅；A3 mcpcf 库名 ≠ 主库默认库名；A4 mcpcf 两个 env 键 ≠ 主库 env 键。
- **C1 碰撞格（env 面）**：`FIST_DB_PATH` 已设且（按真源 trim 事实处理后）与 mcpcf 沙箱库路径归一后同文件 ⇒ 红，点名两条路径；未设置 ⇒ 格空过，但输出明说「FIST_DB_PATH 未设置，碰撞格空过」，不许静默。
- **覆盖面盲点（脚本如实自注，不冒充已覆盖）**：只管路径面不管时基面（裸 Unix 秒 vs ops_ts 混写机理是方向①②③，owner 裁决项）；碰撞格读本检查进程 env，非 server 运行时 env；归一只做 normcase/normpath + cwd 拼接，不做 symlink samefile；对称面（`MCPCONFTEST_DATA_DIR` 指进主库 data_dir）不在碰撞格口径内。

## 守卫面

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_tools_sync` | PASS（183，rc=0） | 同（零漂移） |
| `check_battery_count_doc`（新守卫预核） | 新脚本**未注册**（全 `scripts/` 树无 case/expected/EXEMPT 引用，`run_guards.py` 不在 WIP） | 新增风险（见遗留风险 1） |

## FIST 闭环（T0r40 · wd-r284 · ns watchdog）

**6 步全链首改即 rc=0**（脚本逐字复用 r283 已实证模板，仅改 AGENT/DESC/DELIV/OUT 四处，无新引入变量）：

| 步 | rc | 状态迁移 |
|---|---|---|
| publish | 0 | 发布 T0r40（**writable_agents=39**，claim_ready=true） |
| agent_acl_grant | 0 | can_write=true（granted_rows=2bdd20b0694fb5fe，pid_bound=false） |
| claim | 0 | 已领取（assignee=wd-r284） |
| execute | 0 | 执行中（deliverable=本报告） |
| submit | 0 | 待验收 |
| verify | 0 | 已完成（completed_by=wd-r284） |

FIST_DB_PATH 改道 temp/fist-selfiter.db；各步回包落盘 temp/fist_r284_out/1..6_*.txt。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **BUG-583 方向④ 守卫未注册电池（本轮新增）**：`scripts/check_mcpcf_db_isolation.py` 为未跟踪 WIP，无执行面（`run_guards.py` 不在 WIP 面，全 `scripts/` 树无 case/expected/EXEMPT_RULES 引用）。另一 agent 若只提交脚本而不配执行面，`check_battery_count_doc` 将 FATAL（缺面清单），全仓门禁停摆。建议：该脚本是**独立判据**（非被导入共享模块、非一次性工具），收口时应以 `case(...)` 进电池，或带理由 `expected(...)`；不建议用 EXEMPT_RULES。
2. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
3. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。
4. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

- 下一轮若另一 agent 收口 BUG-583 方向④ 守卫，核对三格：脚本 + 电池 case **同批**（`check_battery_count_doc` 绿）+ `--selftest` 全绿（含变异对照）+ 主面 rc。三格齐则该守卫可计入新增常驻判据。
- 若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
- 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -6` / `git --no-pager diff --stat` / `git --no-pager diff`（本轮实跑）
- 4 个 WIP 文件 mtime（本轮 stat 实读）
- `python scripts/check_tools_sync.py`（rc=0，本轮复测）
- `scripts/check_mcpcf_db_isolation.py` docstring + 骨架（本轮只读核验）
- FIST 闭环 T0r40 收口（wd-r284，ns watchdog，6 步后台串跑，FIST_DB_PATH 改道 temp/fist-selfiter.db）
- r283 报告磁盘原件（`reports/2026-11-14-r283-watchdog-p7-foreign-ledger-report.md`，本轮只读核验 + 脚本模板复用）
