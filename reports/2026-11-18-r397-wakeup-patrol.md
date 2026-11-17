# 轮 397 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

> 日期 2026-11-18 ｜ 轮次 r397（HEAD `8b186dd25`，r396 之后无新提交）｜ agent wd-r397 ｜ ns watchdog

## 一、唤醒状态

- **WIP 收口核查**：`git status --short` = 6M + 1 untracked，与 r393~r396 一致（iter-r192 车道在途：`dist/fist-mbt.js` 已暂存 M、`memory/bugs.md` +216/0、`memory/target.md`、`scripts/README.md`、`scripts/check_plan_landing.py`、`templates/pipeline_mode_loop.md`、untracked `reports/2026-11-17-iter-r192-report.md`）⇒ iter-r192 车道仍未收口，**禁区零碰**（零改零提交，他方 WIP 一概未动）。
- **外来账确认（BUG-565 族）**：`memory/bugs.md` 的 +216 行 WIP 为 **vq 项目缺陷条目 BUG-592~636（全 FIXED，reported_by WorkBuddy P4/P5、vq-p6/p7-commander、vq 统帅 P7-3）**，非本仓元条目——MCP server cwd 钉本树致别的项目误落本账（检测面 `check_foreign_ledger_entries` 对白名单外条目会红 = 冻结 WIP 的投影，非回归）。**冻结 65+ 轮待 owner 裁决**（搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated），本巡检不代改、不立新 BUG 号（避免与 vq 侧撞号——如 BUG-636 已在两义并存）。
- **Round C 队列维持 r385 实证移交态**：BUG-527 治本已被 2026-11-02 追记3 A/B 裁决否决（摘库包 link 反断 CI native）/ BUG-530 已 FIXED（`3699f012a`）/ `check_usage_tool_count` 已注册（run_guards.py:175，selftest 13/13 真源=183）⇒ **既定目标为空**，不派单，走巡检分支（标准动作 3）。

## 二、换面巡检：`check_sql_bind_alignment`（R177 SQL 三方对齐）

选择依据：该面是 R177 落的 store 层 SQL 完整性守卫（列数 ↔ VALUES 项数 ↔ bind 次数三方对齐），run_guards 注释载明 R176 仅人工核过一处 `insert_execution`（11/11），其余 INSERT 长期无人核。近 17 轮换面清单反解（r380 hardcoding / r381 deployment+dist+mcpcf+usage / r382 大扫除 / r383 selftest_inventory+unit_number / r384 pkg_imports / r385 battery+plan_landing / r386 battery+plan_landing / r387 battery+host_installable / r388 fist_list_tools+tool_required+mbti_eol / r389 release_asset_names / r390 entry_paths / r391 ofm_endpoint / r392 store_tables+demo_isolation / r393 mbti_sync 修复 / r394 arg_face_strict+plan_landing / r395 ns_write_gate_coverage / r396 doc_surface）——`check_sql_bind_alignment` 不在其中，属长期未单巡的完整性面。

| 项 | 结果 |
|---|---|
| 全量实跑 | **rc=0 PASS**：门禁 PASS 19 处 INSERT 三方对齐（占位符=bind 全对；其中 3 处列数为插值、仅校验占位符） |
| `--selftest` | **rc=0**：7/7（s1 对齐样本判绿 / s2 少一个 bind⇒红 / s3 列数≠占位符⇒红 / s4 插值列⇒绿但计 degraded / s5 bind 缺号⇒红 / s7 委托助手绑定⇒绿且 degraded / s6 无样本⇒rc=2 不自证归 2 不归 0） |

**结论：零漂移**（19 处 INSERT 全部三方对齐，占位符与 bind 次数逐一相等；3 处插值列按设计降级校验，非缺陷）。

## 三、零漂移常设面

| 判据 | 结果 |
|---|---|
| `check_tools_sync` | rc=0（server.mbt 注册 183；AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单 19 组 ΣN=183） |
| `check_instruction_budget` | rc=0（AGENTS.md = 50440 / 预算 65536，全部章节可见） |
| `patch_esm_main` | rc=0（10 bundle 全 up to date / total patched 0） |

## 四、立账与禁区

- **无新发现（类型）、无新立账**（换面 + 常设面全绿零漂移）。
- **禁区零碰**：6M + 1 untracked 他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零改零提交。
- **外来账 BUG-592~636**：确认全为 vq 项目缺陷（无本仓元条目），维持冻结待 owner；本巡检不立新 BUG 号（防撞号，BUG-636 已两义并存）。

## 五、FIST 闭环

T0r153 六步全链 **rc=0**（wd-r397 / ns watchdog / `temp/fist_r397_chain.sh` 稳健 TID 提取后台串跑；patch_esm_main 探针先行 10 bundle up to date / 0 patched 防 MemoryError）。verify 回执：status=已完成、completed_by=wd-r397、assignee=wd-r397、deliverable=reports/2026-11-18-r397-wakeup-patrol.md、namespace=watchdog、created_at=2026-11-17T16:11:24Z / updated_at=2026-11-17T16:11:31Z。

## 六、遗留风险与后续建议

1. **外来账 BUG-592~636（BUG-565 族）冻结待 owner**：建议 owner 裁决搬移 vq 仓或登记 WHITELIST（kind=foreign-adjudicated）；根治面（server cwd 钉本树、调用方无出路）仍未落地，检测半 `check_foreign_ledger_entries` 已注册（run_guards.py:333-334）。
2. **Round C 队列空**：既定迭代目标为空，需 owner 设下一目标（与 r385 移交态一致，持续挂起）。
3. **iter-r192 车道在途 30+ 轮未收口**（dist 重构 + 外来账 +216 行 + check_plan_landing 车道 F 提交③ 就绪）：其 scoped 提交收口前本树维持「巡检分支」节奏。`dist/fist-mbt.js`（41402+/35319-）为巡检中止轮遗留、r192 报告点名「归属巡检专门轮、统帅未代收」——本巡检**不代收**（近全文件重写属他方未定稿重构面，卷入提交有风险），留待 owner 裁决或专门轮收口。

*（内容由AI生成，仅供参考）*
