# 轮 371 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：371（第 52 轮 WIP 静止态）
- FIST 闭环：T0r127 / agent `wd-r371` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 52 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），`src/engine/engine_circuit_test.mbt` 与
`scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**（BUG-527 治本 /
BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。R192 车道自 r318
停摆持续。

本轮走**巡检分支**，换面巡检 **`check_arg_face_strict`**（R64「参数面必须严格」的
元判据·行为级真门：对每把 `check_*.py` 真发未知旗标 `--definitely-not-a-real-flag`、
按真 rc 判、不读源码）：

- `--selftest` rc=0 **3 格**（bad-arg-guard-is-flagged / good-arg-guard-not-flagged /
  empty-candidate-face-returns-zero-count）
- 实跑 rc=0：**100 把** `check_*.py` 逐把遇未知旗标皆拒绝出绿（rc≠0）—— 0 违例

**本轮实质进展（清偿 r332 已知债，非新立账）**：r332（第 13 轮静止态）曾发现本尺
脚本头「已知债 27 把（2026-10-28 首读）」注释落后于现状——27 把债早已全消解、
扫描面已扩到 100 把、电池登记早已翻回普通 `case()`——当时定调「不立新账，留专门
轮次更新注释」。本轮即该专门轮次：先核实（`git show HEAD:scripts/run_guards.py` 与
工作树均为 `case("check_arg_face_strict.py")` + `case(..., "--selftest")`，无
`kind="known-red"`）+ 实跑 100 把 0 违例后，把该「已知债」注释段更新为「已全数
清偿（2026-11-17 r371 核）」，保留历史出处（2026-10-28 首读 27 把）与「出路」（对新
尺仍适用）。改后复跑 `--selftest`（3 格 rc=0）+ 实跑（100 把 rc=0）均无回归；该尺
「不读源码」故注释改动不影响其行为，且已逐一核对 7 份 doc 扫描类守卫均不引用
「已知债」串 ⇒ 本改动对电池零影响。

**撞面核对**：grep git log 反解近 60 轮，`check_arg_face_strict` 最近一次为 r332
（第 13 轮静止态），不在 r356~r370 近 15 轮巡检面（store_tables_wired / tool_add_
completeness / desc_enum_sync / sql_bind_alignment / foreign_ledger_entries / two_faces /
effective_catch / dead_params / plan_landing / byte_slice_truncation / backlog_status_
staleness / exit_code_contract / selftest_hermetic / ps_encoding / mcp_stdio_purity），
本轮换面不撞。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_
  rubric 对齐，R8 分组 19 组 ΣN=183
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

**无新发现（类型）。本轮为清偿已知债（非缺陷、非新立账）；bugs.md 属 WIP 禁区零碰。**

## 资源消耗

- 唤醒巡检一轮；bash 调用约 18 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node
  MCP server）
- 改 1 文件（`scripts/check_arg_face_strict.py` 注释段，行为不变），无新依赖安装
- patch_esm_main 探针先行（防 MemoryError，见 FIST 核实格）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log | WIP 静止第 52 轮，Round C 不执行 |
| 换面巡检 | check_arg_face_strict selftest + 实跑 | 均 rc=0（3 格 / 100 把 0 违例） |
| 已知债清偿 | 核实电池登记 + 更新注释 + 改后复跑验证 | 无回归（selftest 3 格 / 实跑 100 把） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r127 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能
   落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 52 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨半个
   自然月余；建议 owner 关注 WIP 归属方是否失联（该 WIP 含 src/engine 测试与 run_guards
   注册，形似一次未收口的判据接线工作；若归属方长期失联，owner 可裁决接管收口或回滚
   该 WIP——属不可逆操作，需 owner 明确授权，巡检不代行）。
3. **WIP 内 2 个 untracked 新文件**（`scripts/check_mcpcf_db_isolation.py` 545 行 /
   `templates/pipeline_mode_loop.md` 211 行）自 r326 起零增长——收口方需同批登记执行面
   （判例-5 族），否则 `check_battery_count_doc` 会 FATAL 全仓门禁停摆。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批）。
- 巡检面下轮继续轮换未巡检过的守卫面（候选：check_release_asset_names /
  check_demo_isolation / check_publish_payload / check_entry_paths 等未在 r356~r371 出现过的面）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status --short / git log --oneline（唤醒巡检实测）
- scripts/check_arg_face_strict.py --selftest / 实跑输出（本轮实测，改前改后各一次）
- git show HEAD:scripts/run_guards.py + grep（电池登记核实）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解近 60 轮巡检面撞面核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / r332 已知债 / r370 WIP 静止第 51 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r127**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r371**、assignee=wd-r371、
  deliverable=reports/2026-11-17-r371-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T18:19:12Z / updated_at=2026-11-16T18:19:29Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（rc=0，防 MemoryError）
