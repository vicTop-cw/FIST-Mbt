# 轮 283 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

**WIP 面解冻（连续 16 轮零变化终结）**：`memory/bugs.md` mtime 09:31→**10:47**，**P7 批次 BUG-625~635（11 条，全 OPEN）落入**，全部指向 `crates/vq-cli` / `crates/vq-core` / `crates/vq-mcp`（Rust 的 vq-mcp 项目）——与 P3~P6 同族跨项目误落账（根因 BUG-565：记账路径钉本树，调用方无出路）。同期 `docs/improvement-plan-20261010.md` 10:55 被并行 agent 做**本仓真实修复**（BUG-589 A 档措辞校正：§2.2 旧名 `docs/assets/README.md` 改根级 `assets/README.md`，真身 84bddb299 已建且在跟踪面；旧名刻意不加反引号纯文本保留，防 check_plan_landing 误判）。检测守卫 `check_foreign_ledger_entries` 白名单外红面 **12→23**（620 账本条目 / 63 外来信号命中 = 40 白名单内 + 23 白名单外），rc=1（脏树投影，非回归）。零漂移双守卫（check_tools_sync 183 + check_instruction_budget 50440/65536）均 PASS。Round C 三件维持过期不执行。**跨仓处置=owner 裁决项，指挥官不代行**。FIST 闭环 T0r39 六步全链 rc=0 收口（本轮无首改失败，writable_agents=38）。

## 资源消耗

- 工具调用 ~18 次（只读核验 6 + 检测守卫 2 + 零漂移双守卫 1 + FIST 闭环 1 后台 + 收口 6）。
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（3 个 WIP 文件零改、不提交）。

## 任务分配记录

无子代理派发（事件驱动核验 + 只读巡检，指挥官直查直记）。

## WIP 面（解冻——16 轮冻结终结）

| 文件 | mtime（本轮实读） | 本轮变化 |
|---|---|---|
| `memory/bugs.md` | 2026-11-14 10:47:48 | P7 批次 BUG-625~635（11 条全 OPEN）落入；最高条目号 624→635 |
| `docs/improvement-plan-20261010.md` | 2026-11-14 10:55:34 | **本仓真实修复**：BUG-589 A 档措辞校正（+8/-1，"轮 191 校正"标注） |
| `memory/target.md` | 2026-11-10 10:34:16 | 未动（Round 24 孤儿行，陈旧内容） |

三文件均为另一 agent（或 vq 项目记账通道）的 WIP，**禁区零碰、不提交**。

**P7 批次 11 条定性**（逐条已核 summary/detail）：

| 条目 | 性质 |
|---|---|
| BUG-625~628 | vq-cli 缺陷：ask -i 因 question 必填 rc=2 / template delete 误调 delete_table 删错对象 / template train 空壳不写训练集 / history export --format 不生效恒出 JSON |
| BUG-629~630 | vq-cli 缺陷：init 吞 create_dir_all/remove_file 错误 / metadata import driver 默认 mysql 致 is_empty 分支死代码 |
| BUG-631~635 | vq-mcp 18 工具全无状态的能力面缺口：无对话上下文承接出口（prev_questions/prev_sql 旁路）/ 无图表配置出口（ChartService::infer 未暴露）/ 无训练记录读出口（vq_train 写入与读取分属两表闭环不可见）/ vq_history_rate 不触发入训练集与 CLI 语义断裂 / 无元数据树·历史详情·设置·变量读出口（建议新增 4 只读工具） |

全部为 vq 项目缺陷、无一条本仓元条目（本仓真实改动在 improvement-plan 的 diff 面，不涉账本）。

## 守卫面

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_tools_sync` | PASS（183，rc=0） | 同（零漂移） |
| `check_instruction_budget` | PASS（50440/65536，rc=0） | 同（零漂移） |
| `check_foreign_ledger_entries`（事件驱动复查） | rc=1（脏树）：620 条目 / 63 外来信号命中（白名单内 40 / **白名单外 23**） | r281 白名单外 12，本轮 **+11（P7 批次）** |

白名单外 23 = P5/P6（BUG-613~624，12 条）+ P7（BUG-625~635，11 条）；逐条命中信号 `crates/`、`vq-cli/core/pyo3`、`apps/`、`packages/`，全为 vq/Pentad 系外来路径。守卫判定与处置提示均正常（"搬走/改判是 owner 裁决项 BUG-565；若属本仓元条目请带理由登记 WHITELIST meta 段"）。

## FIST 闭环（T0r39 · wd-r283 · ns watchdog）

**6 步全链首改即 rc=0**（无 r282 的变量笔误事故——脚本逐字复用 r282 已实证模板，仅改 AGENT/DESC/DELIV/OUT 四处，无新引入变量）：

| 步 | rc | 状态迁移 |
|---|---|---|
| publish | 0 | 发布 T0r39（**writable_agents=38**，claim_ready=true） |
| agent_acl_grant | 0 | can_write=true（granted_rows=2bdd23b0694fbb17，pid_bound=false） |
| claim | 0 | 已领取（assignee=wd-r283） |
| execute | 0 | 执行中（deliverable=本报告） |
| submit | 0 | 待验收 |
| verify | 0 | 已完成（completed_by=wd-r283） |

FIST_DB_PATH 改道 temp/fist-selfiter.db；各步回包落盘 temp/fist_r283_out/1..6_*.txt。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害，8a669992d 已回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **P3~P7 跨项目误落账（vq 项目缺陷，现最高 BUG-635）**：白名单外 23 条维持呈报待 owner 裁决（r245 三件之一）。指挥官不代行（跨仓不可逆）。
2. **BUG-565 根因仍活**：记账落盘路径钉本树（server cwd），调用方无项目作用域出路。P7 的落入再次实证该根因未根治；根治需给记账路径加项目作用域守卫（代码面项）。
3. **唤醒轮收口中断风险（r206/r272 实证）**：维持每轮退出前两格核对（报告已 scoped 提交 + 当日日志已追加本地留置）。

## 后续建议

- 下一轮若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P8）还是 owner 裁决后的清理提交；若为清理提交（白名单外 23→0），检测面该族可记「裁决关闭」。
- P7 批次 11 条均为 vq-mcp 能力面/CLI 语义缺口，若 owner 裁决搬移 vq 仓，可整批随迁（条目内已含修复方向，可直接作 vq 侧任务包）。
- 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --stat` / `git --no-pager diff`（本轮实跑）
- bugs.md / target.md / improvement-plan mtime（本轮 stat 实读）
- `python scripts/check_tools_sync.py`（rc=0）/ `python scripts/check_instruction_budget.py`（rc=0）/ `python scripts/check_foreign_ledger_entries.py`（rc=1 脏树投影）（本轮实跑）
- FIST 闭环 T0r39 收口（wd-r283，ns watchdog，6 步全链 rc=0，FIST_DB_PATH 改道 temp/fist-selfiter.db）
- r282 报告磁盘原件（`reports/2026-11-14-r282-watchdog-store-tables-brief-report.md`，本轮只读核验 + 脚本模板复用）
