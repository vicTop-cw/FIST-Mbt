# 轮 281 巡检报告（ExploreWatchdog · 2026-11-14）

## 结果摘要

WIP 面**首次变动**（自 r267 冻结以来 `bugs.md` mtime 首次前进）+ 外来账检测守卫（BUG-565 根治面）
**本轮首次实跑确认**。无新立账（发现属 BUG-565 已知族，非新缺陷）。Round C 队列三件维持过期裁定，不执行。

关键发现：`check_foreign_ledger_entries`（外来条目检测守卫，BUG-565 的后续动作之一）本轮首跑，
确认 **HEAD 绿 / 脏树红**：干净基线（581 条至 BUG-591）全过；工作区脏面因 **12 条白名单外外来条目
（BUG-613~624，全部为 vq 项目缺陷）**而 rc=1——这是守卫按设计的棘轮行为，非缺陷。
处置（逐字搬移到 vq 仓 / 确认后登记基线）是 owner 裁决件，指挥官不代行（跨仓不可逆）。

## 资源消耗

- 工具调用 ~14 次核验（status / log / diff --stat / mtime / HEAD 基线推演 / 守卫 CLI / 12 条处置面只读核验）
  + 外来账检测守卫实跑（full 脏树 rc=1 / --selftest 15/15 / HEAD 基线推演）
  + 零漂移双守卫（check_tools_sync + check_instruction_budget，均 rc=0）
  + FIST 闭环 6 步（后台串跑，task_id 由 publish 回包提取）
  + 报告 / 日志 / scoped 提交收口
- 无测试、无构建、无 FIST 之外的网络面；**未触碰禁区**（冻结 WIP 两文件零改、不提交）

## 任务分配记录

无子代理派发（同源收敛面 + 只读核验，指挥官直查直记）。12 条处置面逐条只读核验
（`read_file memory/bugs.md:16060-16118`），确认全部指向 vq 项目路径族，**无本仓元条目混入**。

## WIP 冻结面（本轮首次变动）

- `memory/bugs.md` mtime **2026-11-13 23:42:22 → 2026-11-14 09:31:00 +0800**（自 r267 冻结以来
  **首次前进**）；条目 **581（HEAD）→ 609（工作区）**，最高 **BUG-591（HEAD）→ BUG-624**。
  新增面为 P6 收口批（BUG-616~624 的 `### FIXED` 收口块，落盘 2026-11-14 09:31）。
- `memory/target.md` mtime 2026-11-10 10:34:16 未动（Round 24 孤儿行）。
- 两文件为另一 agent WIP（vq 项目跨项目误落账），**禁区零碰、不提交**。
- **未新增误落账批次**：新增面仍属 P3~P6 已知族的 P6 收口，非 P7 新批次。

## 守卫面

| 守卫 | 读数 | 与上轮 |
|---|---|---|
| `check_tools_sync` | PASS（183，rc=0） | 同 |
| `check_instruction_budget` | PASS（50440/65536，rc=0） | 同 |
| `check_foreign_ledger_entries` | **脏树 rc=1 / HEAD 绿**（详见换面巡检） | 本轮首跑 |
| `check_foreign_ledger_entries --selftest` | 15/15 PASS（rc=0） | 本轮首跑 |

## 换面巡检：外来账检测守卫（BUG-565 根治面）

- 本轮换面选 `check_foreign_ledger_entries`（而非 mcp_smoke），因为它直接探活工作区里**唯一活面**
  （冻结 WIP）——是否又有新外来条目混入。轮换：r277 check_host_installable → r278 check_fist_list_tools_sync
  → r279 check_ofm_endpoint → r280 mcp_smoke → **本轮 check_foreign_ledger_entries**。
- **full 扫描（读工作区脏面）**：账本 609 条 · 外来信号命中 52 条（白名单内 40 / **白名单外 12**）⇒ rc=1。
  白名单外 12 条：**BUG-613~624**，命中信号 `crates/` / `vq-cli/core/pyo3` / `apps/` / `data/` / `packages/`。
- **HEAD 基线推演**：`git show HEAD:memory/bugs.md` = 581 条、最高 BUG-591、**不含任何 BUG-592~624**
  ⇒ 干净检出下守卫全绿。**rc=1 纯由未提交的冻结 WIP 引起，非已提交回归**。
- **12 条处置面逐条只读核验**（`bugs.md:16060-16118`），全部为 vq 项目缺陷：
  - BUG-613 / 615 / 616 / 617 / 618 / 619 / 620 / 621 / 622 → `crates/vq-cli/src/main.rs`
  - BUG-614 → `data/vq.db` settings 表（conn.pgdemo 口令明文）
  - BUG-623 → `apps/api/app/database.py`（`_migrate_add_column_if_not_exists` 吞异常）
  - BUG-624 → `scripts/check_repo_layout.py` SKIP_PREFIXES（deliverables/ workbuddy/ 归档）
  - **无一条是本仓元条目**（引用外来路径做证据）⇒ **不应**登记进 WHITELIST 的 meta 段。
- **判定**：守卫按设计正确棘轮（绿=基线干净 / 红=有未裁决外来条目）。"修掉"这个红
  （把 12 条塞进白名单）= 掩盖未裁决问题（systematic-debugging 反模式）。
  ⇒ 本轮**不动守卫、不动白名单、不搬移条目**，只把精确处置清单交回 owner。

## Round C 队列状态（依据记忆裁定，不重推导）

- BUG-527 摘 cc-link-flags：owner 已否决（CI A/B 实证有害）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

⇒ 队列三件全部过期，本轮不执行。

## 遗留风险

1. **P3~P6 跨项目误落账（vq 项目缺陷，现最高 BUG-624）**：vq-mcp 项目条目持续落进本纯 MoonBit 仓。
   根治面（外来账检测守卫 `check_foreign_ledger_entries`）已落地并注册（`run_guards.py:333-334`，
   含 `--selftest`），本轮实跑确认其正确棘轮。**待 owner 裁决的 12 条处置清单（白名单外）**：
   BUG-613 / 614 / 615 / 616 / 617 / 618 / 619 / 620 / 621 / 622 / 623 / 624（全 vq 缺陷，见「换面巡检」逐条面）。
   处置二选一：(a) 逐字搬移到 vq 仓账本（本仓按 append-only 保留勘误引用）；
   (b) 若 owner 裁定保留本仓，则带理由登记进 WHITELIST（kind=foreign-adjudicated，**非** meta 段）。
   **指挥官不代行**（跨仓不可逆）。
2. **外来账守卫脏树恒红的连带效应**：冻结 WIP 在树期间，任何对**脏工作区**跑全量电池
   （`run_guards.py` 136 case）的本地动作都会因 `check_foreign_ledger_entries` rc=1 而红；
   **CI（干净检出）不受影响**（HEAD 全绿）。⇒ 本地跑电池需知悉：这一档红是 WIP 的投影，非回归。
3. `memory/bugs.md` 工作区脏面未收口 ⇒ 任何 `git add -A` 型批量操作都会误吞，
   提交纪律（scoped `--` 路径 / commit_scoped.sh）维持强制。
4. **唤醒轮收口中断风险（r206 / r272 两次实证）**：计划任务 30 分钟无窗唤醒，会话若在
   「FIST 闭环后、提交前」被截断即漏两格。缓解：每轮退出前的两格核对已写入项目记忆；缺口次轮可补账。

## 后续建议

- 下一轮若 `bugs.md` mtime 再变，优先核对是新增误落账批次（P7）还是 owner 裁决后的清理提交。
- 若 owner 已裁决 12 条处置，下一轮按裁决执行（搬移 / 登记基线），并复核守卫脏树转绿。
- 无其它行动项。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --stat`（本轮实跑）
- `git show HEAD:memory/bugs.md`（条目计数 / 最高 id / P5P6 面推演，本轮实跑）
- `python scripts/check_foreign_ledger_entries.py`（脏树 rc=1，12 条白名单外点名）/
  `--selftest`（15/15 rc=0）（本轮实跑）
- `python scripts/check_tools_sync.py`（rc=0）/ `python scripts/check_instruction_budget.py`（rc=0）（本轮实跑）
- `read_file memory/bugs.md:16060-16118`（12 条处置面逐条只读核验，本轮实读）
- FIST 闭环 T0r37 收口（wd-r281，writable_agents=36，ns watchdog，6 步全链 rc=0，FIST_DB_PATH 改道 temp/fist-selfiter.db）
- r280 报告磁盘原件（`reports/2026-11-14-r280-watchdog-zerochange-brief-report.md`，本轮只读核验）
