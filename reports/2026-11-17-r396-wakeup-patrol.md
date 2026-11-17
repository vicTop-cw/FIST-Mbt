# 轮 396 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

> 日期 2026-11-17 ｜ 轮次 r396（HEAD `7da768e04`，r395 之后无新提交）｜ agent wd-r396 ｜ ns watchdog

## 一、唤醒状态

- **WIP 收口核查**：`git status --short` = 6M + 1 untracked，与 r393~r395 一致（iter-r192 车道在途：`dist/fist-mbt.js` 已暂存 M、`memory/bugs.md` +216/0、`memory/target.md`、`scripts/README.md`、`scripts/check_plan_landing.py`、`templates/pipeline_mode_loop.md`、untracked `reports/2026-11-17-iter-r192-report.md`）⇒ iter-r192 车道仍未收口，**禁区零碰**（零改零提交，`git restore`/`git add` 他方文件一概未动）。
- **Round C 队列维持 r385 实证移交态**：BUG-527 治本已被 2026-11-02 追记3 A/B 裁决否决（摘库包 link 反断 CI native）/ BUG-530 已 FIXED（`3699f012a`）/ `check_usage_tool_count` 已注册（run_guards.py:175，selftest 13/13）⇒ **既定目标为空**，不派单，走巡检分支（标准动作 3）。

## 二、换面巡检：`check_doc_surface`（J1–J19 文档面守卫）

选择依据：该面是 CI 硬门禁（文档面一致性的总守卫，J1–J19 族），上次单独巡为 r382 大扫除，此后 14 轮未单巡，期间有 r393 修 `check_mbti_sync.py` 等多轮变动，文档面一致性值得复核。近 15 轮换面清单反解（r380 hardcoding / r381 deployment+dist+mcpcf+usage / r382 大扫除 / r383 selftest_inventory+unit_number / r384 pkg_imports / r385 battery+plan_landing / r386 battery+plan_landing / r387 battery+host_installable / r388 fist_list_tools+tool_required+mbti_eol / r389 release_asset_names / r390 entry_paths / r391 ofm_endpoint / r392 store_tables+demo_isolation / r393 mbti_sync 修复 / r394 arg_face_strict+plan_landing / r395 ns_write_gate_coverage）——`check_doc_surface` 不在其中。

| 项 | 结果 |
|---|---|
| `--selftest` | **rc=0**（真源解析 183 工具；J3/J4/J6/J7/J8/J9/J10/J11/J12/J13/J14/J15/J17/J18/J19 对合成违例均发红；反向对照含「干净输入不误红」「英文不算契约」「分工写清不误红」「两面一致不误红」「J11 合法态不误红」「J12 注释 refs/heads 与 tag 守卫不误红」；防空转含「分工清单落空必红」「空扫描必红」「解析器饿死必红」「J11 账本读不到必红」「J12 一份 workflow 都读不到必自拒」「J13 标题戳早于 published 不误红 / 权威面没记不作数 / release-fact 缺失或自相矛盾必红」） |
| 全量实跑 | **rc=0 PASS**：183 工具在 AGENTS/README 逐个可查、分组和=183、自述版本=0.3.11（== moon.mod）、J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、J9 返回契约未退化、J10 判据范围自述==实现、J11 CI native 门↔账本/规范面三向对表、J12 if: 不钉分支名、J13 发布状态↔BACKLOG release-fact 对表、J14 工具计数自述↔CLI 分组和↔真源、J15 docs/ 文件名日期前缀、J17 工具链地板↔toolchain.json、J19 USAGE 参数列↔schema 属性集 |

**结论：零漂移**（与 r382 大扫除同态；r393 修的是判据脚本本身、非文档面，不触发 J 面红）。

## 三、零漂移常设面

| 判据 | 结果 |
|---|---|
| `check_tools_sync` | rc=0（server.mbt 注册 183；AGENTS/README/deliverable/scoring_rubric 对齐；R8 清单 19 组 ΣN=183） |
| `check_instruction_budget` | rc=0（AGENTS.md = 50440 / 预算 65536，全部章节可见） |
| `patch_esm_main` | rc=0（10 bundle 全 up to date / total patched 0） |

## 四、立账与禁区

- **无新发现（类型）、无新立账**（换面 + 常设面全绿零漂移）。
- **禁区零碰**：6M + 1untracked 他方 WIP 零改零提交。

## 五、FIST 闭环

T0r152 六步全链 **rc=0**（wd-r396 / ns watchdog / `temp/fist_r396_chain.sh` 稳健 TID 提取后台串跑，node 温态总耗时 <60s；patch_esm_main 探针先行 10 bundle up to date / 0 patched 防 MemoryError）。verify 回执：status=已完成、completed_by=wd-r396、assignee=wd-r396、deliverable=本报告、namespace=watchdog、created_at=2026-11-17T15:34:35Z / updated_at=2026-11-17T15:34:41Z。

## 六、遗留风险与后续建议

1. 无新增。Round C 队列空 → 需 owner 设下一迭代目标（与 r385 移交态一致，持续挂起）。
2. iter-r192 车道（dist 重构 +216 行 bugs.md 等）在途 30+ 轮未收口，其 scoped 提交收口前本树维持「巡检分支」节奏；target.md 陈旧行问题 r394 已交接（需 owner 授权 `git restore`），维持不代改。

*（内容由AI生成，仅供参考）*
