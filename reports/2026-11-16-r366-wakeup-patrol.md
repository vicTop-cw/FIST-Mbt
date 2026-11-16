# 轮 366 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-16
- 轮次：366（第 47 轮 WIP 静止态）
- FIST 闭环：T0r122 / agent `wd-r366` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 47 轮**：`git diff --numstat` 与 r326~r365 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0），2 untracked
（`scripts/check_mcpcf_db_isolation.py` 545 行 / `templates/pipeline_mode_loop.md` 211 行）
逐字同 r365 收口后。`src/**` 与 `scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**
（BUG-527 治本 / BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_backlog_status_staleness`**（「BACKLOG 状态陈旧度」
棘轮尺，只读诊断非门禁；扫 gitcode/main 跟踪面的 BACKLOG 份 ↔ 主线点名的 TASK id，
落差超限判红、存量等 owner 盖章即下降、新增一条即红）：

- `--selftest` rc=0 **16/16 格**（反解：M×3 / P×3 / R×6 / V×4，族名取自已执行格子名首段首字母，不手写计数）
- 实跑（只读诊断）`--verify` rc=0：**backlog 23 份 / 主线点名到的 TASK id 23 个 /
  落差 0 条 / 上限 0 条 / 超限 0 条**，`BACKLOG_STALENESS=within`
- `--show-open` rc=0：TASK-001~023 全部 `done`（P0~P3 齐），无一条 open/stale 未盖章

**撞面核对**：grep git log 反解 r358~r365 近 8 轮巡检面（desc_enum_sync / sql_bind_alignment /
foreign_ledger_entries / two_faces / effective_catch / dead_params / plan_landing /
byte_slice_truncation），`check_backlog_status_staleness` 不在其列，本轮换面不撞。

例行的零漂移核对双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_rubric 对齐，R8 分组 19 组 ΣN=183
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

**无新发现（类型）、无新立账。** 禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 资源消耗

- 唤醒巡检一轮；bash 调用约 12 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node MCP server）
- 无新文件创建（报告 + 链脚本 + desc 为轮次记账面），无依赖安装
- patch_esm_main 探针先行（防 MemoryError，见 FIST 闭环核实格）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/diff numstat | WIP 静止第 47 轮，Round C 不执行 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| 换面巡检 | check_backlog_status_staleness selftest + 实跑 | selftest 16/16 格 rc=0、--verify rc=0（23/23/落差 0）、--show-open 23/23 done |
| FIST 闭环 | T0r122 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能落地——
   取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 47 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），若再持续
   建议 owner 关注 WIP 归属方是否失联。
3. **check_backlog_status_staleness 覆盖面**：只认 BACKLOG 份 ↔ 主线 TASK id 的落差形状，
   只看「主线点名到的 id 是否都在 backlog 里且状态非 open/stale」，不验证状态语义真伪
   （`done` 是否真做完不归它管）——判据自身的设计取舍，非新缺陷。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册 check_usage_tool_count 同批）。
- 巡检面已轮至 check_backlog_status_staleness，下轮可继续轮换未巡检过的守卫面
  （候选：check_mbti_sync / check_pkg_imports / check_doc_paths / check_doc_dup / check_exit_code_contract 等）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_backlog_status_staleness.py --selftest / --verify / --show-open 输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解 r358~r365 近 8 轮巡检面撞面核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / TID 稳健提取 / r365 WIP 静止第 46 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r122**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r366**、assignee=wd-r366、
  deliverable=reports/2026-11-16-r366-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T15:36:37Z / updated_at=2026-11-16T15:36:46Z
