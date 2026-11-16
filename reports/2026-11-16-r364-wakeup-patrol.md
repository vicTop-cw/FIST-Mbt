# 轮 364 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-16
- 轮次：364（第 45 轮 WIP 静止态）
- FIST 闭环：T0r120 / agent `wd-r364` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 45 轮**：`git diff --numstat` 与 r326~r363 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0），2 untracked
（`scripts/check_mcpcf_db_isolation.py` 545 行 / `templates/pipeline_mode_loop.md` 211 行）
逐字同 r363 收口后。`src/**` 与 `scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**
（BUG-527 治本 / BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_plan_landing`**（计划文档「点名落点」↔ 跟踪面
存在性核对，只读诊断非门禁；R40 起带 P1 四态 tracked/on-disk/moved/missing、P4 分面、
P5 搬家态、P6 判定面棘轮、P7 豁免、P8 日日志/ P9 提案面设计性排除、R46 交付幻觉尺同源）：

- `--selftest` rc=0 **64 格**（抽取口径 9 / 干净不误报 / on-disk 必报 / missing 必报 /
  跟踪目录反解 3 / P4 分面 3 / 空转计数 / P5 搬家 7 / 搬家+豁免不进判定面 2 / P7 豁免 6 /
  P6 棘轮 3 / 退出码两口径 5 / 上限常量 1 / P2 空转三条 4 / 模式互斥 2 / FATAL 出口码 1，
  含 ratchet-over / ratchet-under / 上限≥存量 等变异对照）
- 实跑（只读诊断）rc=1 **有落点未落地**：判定面 **A 档存量 18**（≤ 上限 25），
  另出数不进判定面：存档面 19 条 / 形态说明 44 条 / ignored-log（日日志被 .gitignore 排除）
  / scratch（`_` 前缀一次性件）/ proposal（提案 ≠ 落地承诺）/ external（外部宿主文件）。
  rc=1 是「有落点未落地」的**诊断读数**，本工具刻意不是门禁（计划写「新增尚不存在的文件」合法）。
- `--gate` rc=0：判定面 A 档 18 ≤ 上限 25（存量按声明接受、增量必须归零，BUG-367 ④），门禁口径健康。

**撞面核对**：grep reports/ 反解 `check_plan_landing` 不在 r358~r363 近 6 轮巡检面之列
（r358 desc_enum_sync / r359 sql_bind_alignment / r360 foreign_ledger_entries /
r361 two_faces / r362 effective_catch / r363 dead_params），本轮换面不撞。

例行的零漂移核对双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_rubric 对齐，R8 分组 ΣN=183
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

**无新发现（类型）、无新立账。** 禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 资源消耗

- 唤醒巡检一轮；bash 调用约 12 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node MCP server）
- 无新文件创建（报告 + 链脚本 + desc 为轮次记账面），无依赖安装
- patch_esm_main 探针：10/10 bundle up to date、total patched 0，无 MemoryError

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/diff numstat | WIP 静止第 45 轮，Round C 不执行 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0 |
| 换面巡检 | check_plan_landing selftest + 实跑 + --gate | selftest 64 格、--gate rc=0（A 档 18 ≤ 上限 25） |
| FIST 闭环 | T0r120 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能落地——
   取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 45 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），若再持续
   建议 owner 关注 WIP 归属方是否失联。
3. **check_plan_landing 覆盖面有限**：只认反引号包裹的仓内路径，裸路径 / 目录名 / 命令名不认
   （避免大量误报）；`missing` 只是诊断读数，退出码 1 不代表 CI 该红——这是判据自身的设计取舍
   （BUG-367 的「窄口径、刻意保守」），非新缺陷。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册 check_usage_tool_count 同批）。
- 巡检面已轮至 check_plan_landing，下轮可继续轮换未巡检过的守卫面（候选：check_mbti_sync /
  check_pkg_imports / check_doc_paths / check_doc_dup / check_exit_code_contract /
  check_delivery_gap 等）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_plan_landing.py --selftest 与实跑 / --gate 输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（10/10 up to date，本轮实测）
- grep reports/ 反解 check_plan_landing 撞面核对（不在 r358~r363 近 6 轮面之列）
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / TID 稳健提取 / r363 WIP 静止第 44 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r120**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r364**、assignee=wd-r364、
  deliverable=reports/2026-11-16-r364-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T14:39:24Z / updated_at=2026-11-16T14:39:33Z
