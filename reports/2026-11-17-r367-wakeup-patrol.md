# 轮 367 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：367（第 48 轮 WIP 静止态）
- FIST 闭环：T0r123 / agent `wd-r367` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 48 轮**：`git diff --numstat` 与 r326~r366 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0），2 untracked
（`scripts/check_mcpcf_db_isolation.py` 545 行 / `templates/pipeline_mode_loop.md` 211 行）
逐字同 r366 收口后。`src/**` 与 `scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**
（BUG-527 治本 / BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_exit_code_contract`**（「退出码契约」承诺面↔实现面
守卫，BUG-369 建议①②，只读诊断非门禁；ast 扫全仓 scripts/**.py，判 R1 模块面幻影 /
R2 站点类指派矛盾 / R3 站点自述码不符，S/U/O 三面只报不判）：

- `--selftest` rc=0 **28 格**（含标注集校准 5 格按名字现数：check_plan_landing /
  check_mbti_sync / check_pkg_imports / simulate_head_commit / check_template_ctrl；
  分类面：承诺与条目切片 / 实现面 / 判定 R1·R2·R3 / 只报不判与让位 / 棘轮 / 承重对照 / 自指）
- 实跑（只读诊断）rc=0：**判定面（R1+R2+R3）= 0 条 / 上限 0 条**，BUG-369 立案那批
  存量已清完（无容忍带，任何一条新假契约都必红）；只报不判 190 条
  （S 沉默出口 100 ｜ U 未认作契约 83 ｜ O 不透明/让位 7）
- `--show-ceiling` rc=0：CONTRACT_GAP_CEILING=0 / 当前判定面=0 条 / 只报不判=190 条

**撞面核对**：grep git log 反解 r358~r366 近 9 轮巡检面（desc_enum_sync / sql_bind_alignment /
foreign_ledger_entries / two_faces / effective_catch / dead_params / plan_landing /
byte_slice_truncation / backlog_status_staleness），`check_exit_code_contract` 不在其列，
本轮换面不撞（r366 后续建议已点名它为候选，本轮落地）。

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
| 唤醒巡检 | git status/log/diff numstat | WIP 静止第 48 轮，Round C 不执行 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| 换面巡检 | check_exit_code_contract selftest + 实跑 | selftest 28 格 rc=0、实跑 rc=0（判定面 0/上限 0/只报不判 190）、--show-ceiling rc=0 |
| FIST 闭环 | T0r123 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能落地——
   取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 48 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），若再持续
   建议 owner 关注 WIP 归属方是否失联。
3. **check_exit_code_contract 覆盖面**：判定面只认 R1/R2/R3 三种「自述与实现不同色」形状，
   S/U/O 三面刻意只报不判（现状 190 条），O 面外部件透传（sys.exit(p.returncode) 等）主动让位留名——
   判据自身的设计取舍，非新缺陷。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册 check_usage_tool_count 同批）。
- 巡检面已轮至 check_exit_code_contract，下轮可继续轮换未巡检过的守卫面
  （候选：check_mbti_sync / check_pkg_imports / check_doc_paths / check_doc_dup 等）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_exit_code_contract.py --selftest / 实跑 / --show-ceiling 输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解 r358~r366 近 9 轮巡检面撞面核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / TID 稳健提取 / r366 WIP 静止第 47 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r123**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r367**、assignee=wd-r367、
  deliverable=reports/2026-11-17-r367-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T16:10:30Z / updated_at=2026-11-16T16:10:52Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（防 MemoryError）
