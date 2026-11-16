# 轮 361 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-16
- 轮次：361（第 42 轮 WIP 静止态）
- FIST 闭环：T0r117 / agent `wd-r361` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 42 轮**：`git diff --numstat` 与 r326~r360 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0），2 untracked
（`scripts/check_mcpcf_db_isolation.py` 545 行 / `templates/pipeline_mode_loop.md` 211 行）
逐字同 r360 收口后。`src/**` 与 `scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**
（BUG-527 治本 / BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_two_faces`**（R12 两面漂移普查：真源 vs 另一套执行点 /
真源 vs SQL 编码，覆盖形态 ①②③）：

- `--selftest` rc=0 **27/27 格**（含 f3 变异对照 4 支：MUTATION-f3-mb-cmp-drift-detected /
  MUTATION-f3-mb-cmp-violation-count / MUTATION-f3-sql-cmp-drift-detected /
  MUTATION-f3-sql-cmp-violation-count，加 no-where 不误红反向对照、覆盖面声明格）
- 实跑 rc=0：**形态 ①②③ 无漂移**，运行时输出覆盖率声明
  （本判据只覆盖 3/5 种「两面」形态，④消费面前提 ⑤胶水语义在覆盖面外、需人工判据）+
  符号组普查（80+ 组，如 agents_acl_grant 2 处 engine.mbt:590 / store_sqlite.mbt:3319）+
  F3 SQL 谓词对表（store_rsv.mbt ↔ store_sqlite.mbt SQL=['<'] MB=['<'] 对齐）

**撞面核对**：grep reports/ 反解 check_two_faces 上次被单点巡检是 2026-10-27 R12 立尺轮
（精度修正 + rc 契约 + 执行面），不在 r356~r360 五轮巡检面之列
（store_tables_wired / tool_add_completeness / desc_enum_sync / sql_bind_alignment /
foreign_ledger_entries），本轮换面不撞。

例行的零漂移核对双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_rubric 对齐，R8 分组 ΣN=183
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

**无新发现（类型）、无新立账。** 禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 资源消耗

- 唤醒巡检一轮；bash 调用约 12 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node MCP server）
- 无新文件创建（报告 + 链脚本 + desc 为轮次记账面），无依赖安装
- patch_esm_main 探针：10/10 bundle up to date，无 MemoryError

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/diff numstat | WIP 静止第 42 轮，Round C 不执行 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0 |
| 换面巡检 | check_two_faces selftest + 实跑 | selftest 27/27、实跑形态①②③无漂移 rc=0 |
| FIST 闭环 | T0r117 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能落地——
   取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 42 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），若再持续
   建议 owner 关注 WIP 归属方是否失联。
3. **check_two_faces 覆盖面 3/5**：④消费面前提、⑤胶水语义不在本判据覆盖面内（需人工判据），
   实跑 PASS 不代表无两面——这是判据自身的覆盖面声明，非新缺陷。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册 check_usage_tool_count 同批）。
- 巡检面已轮至 check_two_faces，下轮可继续轮换未巡检过的守卫面（候选：check_mbti_sync /
  check_dead_params_py / check_pkg_imports / check_doc_paths 等）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status / git log --oneline -6 / git diff --numstat（唤醒巡检实测）
- scripts/check_two_faces.py --selftest 与实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- grep reports/ 反解 check_two_faces 上次巡检面（撞面核对）
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / TID 稳健提取 / r360 WIP 静止第 41 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r117**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r361**、assignee=wd-r361、
  deliverable=reports/2026-11-16-r361-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T13:20:39Z / updated_at=2026-11-16T13:20:46Z
