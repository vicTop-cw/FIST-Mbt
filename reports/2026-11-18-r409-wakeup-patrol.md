# 轮 409 唤醒巡检——换面 check_doc_dup

**时间**：本地 2026-11-18 ~06:19 / UTC 2026-11-18T06:19
**HEAD**：`a71691506`（r408）
**WIP**：6M（全 unstaged）+ 1 untracked（他方 `reports/2026-11-17-iter-r192-report.md`）；本轮观测到 `dist/fist-mbt.js` 一度被他方 `git add` 又撤（暂存面 **flux**），收口时暂存面为空。bugs.md mtime 2026-11-15 23:40:40 未动（冻结第 16 轮）。

## 换面：check_doc_dup

CI 硬门判据（R48 立尺 / R136 改按块判 / BUG-539 补 D2 断头孤行）：抓 `scripts/README.md` 这类索引被合并反复拼接后的「同脚本多份说明」——登记块 = 条目抬头行（`- ` 前缀 + 反引号脚本名 + `—`）+ 缩进续行，同一脚本名被 >1 个块登记即红（**D1 重复门**）；**D2 断头孤行**（BUG-539）：合并机器人把条目抬头整行吃掉后残留的无头孤行逐条点名 rc=1，三形状（缩进外顶格残行 / 失去宿主的缩进续行 / 断头码 span 残段）。`--fix` 机械去重（每名保留最长块），不删孤行（内容裁决留人工）。

- **selftest**：rc=0 `33 格`（可红可绿：D1 clean-no-dup 必绿 / short-dup 必红 / block-dup 必红 + D2 orphan-column0 必红 / orphan-fixed-by-indent 必绿 / orphan-fixed-by-removal 必绿 / orphan-run 必红 / orphan-legal-structure 必绿 / orphan-eof-lazy-cont 必绿 / orphan-indented-beheaded 必红 / orphan-indented-host-restored 必绿 / orphan-span-fragment 必红 / orphan-span-lazy-cont 必绿 + 散文/表格行不误伤 + 多名字双登）
- **实跑**：rc=0 `scripts/README.md：755 行，登记块 176，无重复登记`
- 近未单巡（历史覆盖面查无此面单巡），输入面 `scripts/README.md` 属他方 WIP 但零触碰本条目，回面复核有效。

## 零漂移常设面

| 面 | 读数 | 状态 |
|---|---|---|
| `check_tools_sync` | 183 工具 R8 19 组 ΣN=183 | PASS |
| `check_instruction_budget` | 50440/65536 | PASS |
| `patch_esm_main` | 0/10 bundles up to date | up to date |

全 rc=0 零漂移。

## 立账（打磨）

发现 `scripts/run_guards.py:583` **死注释格数漂移**（BUG-514 同族「自述滞后于现状」）：

- 该注释写「`--selftest 21 格真断言`」，但 `check_doc_dup.py` 实际 selftest 为 **33 格**（D2 断头孤行 BUG-539 补 12 格后：33−21=12）。
- `scripts/README.md:140`（R104 判定面）已正确写「33 格真断言」⇒ **只 run_guards 注释一处漏改**。
- `check_selftest_inventory_doc`（R104）判定面**只扫 `scripts/README.md` 的 `- \`xxx.py\` — …` 条目语法**、不扫 run_guards 注释 ⇒ 该漂移**非 CI 红**，是死注释（无门在看）。
- ⇒ 同批打磨：run_guards.py:583 修为「33 格真断言（D2 断头孤行 BUG-539 补 12 格后，与 scripts/README.md 条目及 SELFTEST OK 行对齐）」，随本轮 scoped 提交。
- 说明：`memory/bugs.md` 属他方 WIP 禁区，不能在此立账，故仅报告面记录；若需正式立账，待 bugs.md 解冻后由专门轮补（建议归入 BUG-514 家族）。

## Round C 队列

空态确认（r385 2026-11-17 逐项实证，后续轮不重核）：
- BUG-527 治本：owner 否决严禁重跑（2026-11-02 A/B 裁决：摘库包 cc-link-flags 反断 CI native）
- BUG-530：FIXED（`3699f012a`）
- check_usage_tool_count：已注册 run_guards.py:175
- check_tool_coverage：延后至 bugs.md 解冻（BUG-636 中危判据缺陷）

⇒ 既定目标为空，不派单，走巡检分支。

## FIST 闭环

T0r165 六步（publish/agent_acl_grant/claim/execute/submit/verify）全 rc=0（wd-r409 / ns watchdog / `temp/fist_r409_chain.sh` 后台串跑 job bg-1），`get` 终审 `status=已完成`、`completed_by=wd-r409`、`assignee=wd-r409`、deliverable=本报告、created_at=2026-11-17T22:18:46Z / updated_at=2026-11-17T22:18:52Z（连上常驻热 server 秒级收口，patch_esm_main 探针先行 0/10 防 transient MemoryError）。

## 提交纪律实证（本轮）

本轮 WIP 出现**暂存面 flux**（`dist/fist-mbt.js` 一度被他方 `git add` 又撤）。隔离临时仓对照实证：

- `git commit -F -- <我的 paths>` 是**局部提交**：只提交 pathspec 的 working-tree 版本，**不扫入他方已暂存件**（对照：他方暂存的 `A` 未入我的提交，提交后仍在暂存面）。
- 但 `git commit -- <未跟踪新文件>` **必须先 `git add`**（否则 `pathspec did not match any file(s)` 整笔失败）。

⇒ 本轮 scoped 提交策略：`git add` 新报告 → `git commit -F msg -- <报告> <run_guards.py>`，安全隔离他方 WIP。

## 禁区

他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零碰；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 后续建议

- Round C 队列空态持续，待 owner 设下一目标。
- WIP iter-r192 车道持续冻结 ≥16 轮（r393 起未动）且暂存面 flux（dist 一度暂存又撤），建议 owner 确认该车道状态（收口 / 放弃 / 继续）。
- `run_guards.py` 注释里的自检格数（本例 21→33）与 `scripts/README.md` 条目是**两份会各自漂移的自述**，而 R104 只锁 README 面 ⇒ 建议考虑给 run_guards 注释格数也补一份「从 selftest 反解」的核对，或统一只留 README 一份权威计数（避免下次再漏改）。
