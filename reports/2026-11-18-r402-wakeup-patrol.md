# 轮 402 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

> 日期 2026-11-18（本地 02:34 / UTC 2026-11-17T18:34）｜ 轮次 r402（HEAD `41f6a1181`，r401 之后无新提交）｜ agent wd-r402 ｜ ns watchdog

## 一、唤醒状态

- **WIP 收口核查**：`git status --short` = 6M + 1 untracked，与 r393~r401 一致（iter-r192 车道在途：`dist/fist-mbt.js` M、`memory/bugs.md`、`memory/target.md`、`scripts/README.md`、`scripts/check_plan_landing.py`、`templates/pipeline_mode_loop.md` 均 unstaged；untracked `reports/2026-11-17-iter-r192-report.md`；暂存面为空）⇒ iter-r192 车道仍未收口，**禁区零碰**（零改零提交，`git restore`/`git add` 他方文件一概未动）。
- **Round C 队列维持 r385/r400/r401 实证移交态**：BUG-527 治本已被 2026-11-02 追记3 A/B 裁决否决（摘库包 `cc-link-flags` 反断 CI native，现行态 18 份 moon.pkg 全保留为正确态，**严禁重跑**）/ BUG-530 已 FIXED（`3699f012a`）/ `check_usage_tool_count` 已注册（run_guards.py:175，selftest 13/13）⇒ **既定目标为空**，不派单，走巡检分支（标准动作 3）。
- **check_tool_coverage（BUG-636 同族临时项）明确延后**：修它需动冻结的 `memory/bugs.md`（现 WIP +vq 外来账待 owner 裁决），越界 ⇒ 本轮不修，维持延后（规格见 `reports/2026-11-15-r315-wakeup-patrol.md`）。注：账本内 `BUG-636` 实为 vq 项目 MinGW 入口 bug（已 FIXED），与本仓 check_tool_coverage 盲区同号不同事。

## 二、换面巡检：`check_two_faces`（R12 两面漂移普查判据）

选择依据：近 22 轮（r380 hardcoding / r381 deployment+dist+mcpcf+usage / r382 大扫除 / r383 selftest_inventory+unit_number / r384 pkg_imports / r385 battery+plan_landing / r386 battery+plan_landing / r387 battery+host_installable / r388 fist_list_tools+tool_required+mbti_eol / r389 release_asset_names / r390 entry_paths / r391 ofm_endpoint / r392 store_tables+demo_isolation / r393 mbti_sync 修复 / r394 arg_face_strict+plan_landing / r395 ns_write_gate_coverage / r396 doc_surface / r397 sql_bind_alignment / r398 battery_count_doc / r399 host_installable / r400 mbti_sync / r401 precedents_doc）换面清单反解**不在其中**。本判据是本仓最高危族「两面漂移」（6 天 5 踩：BUG-420/425/435、R10 内存/SQLite、R10 SQL 谓词）的形态尺，R16 已把 F3 从「注释声称时才查」改成「无条件」，值得回面复核。

| 项 | 结果 |
|---|---|
| `--selftest` | **rc=0**（27/27 格全过，含 F1 抄本漂移 / F3 SQL 谓词对表的变异对照格，如 `MUTATION-f3-sql-cmp-drift-detected`、`MUTATION-f3-no-where-no-false-drift`；全合成入参不读真仓） |
| 实跑 | **rc=0 PASS**：F1 抄本漂移无；F2 同签名多定义 80+ 组（如 `agents_set_pid` 2 处 / `assistant_get` 4 处）仅告警不判红（多后端是合法设计）；F3 SQL 谓词对表 `src/store/store_rsv.mbt ↔ src/store/store_sqlite.mbt` 比较符集合 `SQL=['<']` `MB=['<']` 逐条对齐 |

**结论：形态 ①②③ 零漂移**（判据自述边界：④ 消费面前提 / ⑤ 胶水语义 不在覆盖面内，PASS ≠ 无两面）。

## 三、零漂移常设面

| 判据 | 结果 |
|---|---|
| `check_tools_sync` | rc=0（server.mbt 注册 183；AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 169 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 与实测对表） |
| `check_instruction_budget` | rc=0（AGENTS.md = 50440 字节 / 预算 65536，实际注入上限 50440，全部章节可见） |
| `patch_esm_main` | rc=0（10 bundle 全 up to date / total patched 0 / 10） |

## 四、立账与禁区

- **无新发现（类型）、无新立账**（换面 + 常设面全绿零漂移）。
- **禁区零碰**：6M + 1 untracked 他方 WIP（iter-r192 车道）零改零提交；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 五、FIST 闭环

T0r158 六步全链 **rc=0**（wd-r402 / ns watchdog / `temp/fist_r402_chain.sh` 稳健 TID 提取后台串跑；patch_esm_main 探针先行 10 bundle up to date / 0 patched 防 MemoryError）。verify 回执：status=已完成、completed_by=wd-r402、assignee=wd-r402、deliverable=本报告、namespace=watchdog、created_at=2026-11-17T18:36:47Z / updated_at=2026-11-17T18:36:53Z。

## 六、遗留风险与后续建议

1. 无新增。Round C 队列空 → 需 owner 设下一迭代目标（与 r385/r400/r401 移交态一致，持续挂起）。
2. check_tool_coverage 盲区（_tool_registry 真源未接线的第 6 消费者，漏扫 18 工具中 7 个零 A 面覆盖）维持延后——待 `memory/bugs.md` 解冻（当前 WIP vq 外来账待 owner 裁决）后按巡检口径认领，规格见 `reports/2026-11-15-r315-wakeup-patrol.md`。
3. iter-r192 车道（dist 重构 + bugs.md 外来账等）在途 40+ 轮未收口，其 scoped 提交收口前本树维持「巡检分支」节奏；target.md 陈旧行问题 r394 已交接（需 owner 授权 `git restore`），维持不代改。

*（内容由AI生成，仅供参考）*
