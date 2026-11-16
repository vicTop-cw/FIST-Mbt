# 轮 368 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：368（第 49 轮 WIP 静止态）
- FIST 闭环：T0r124 / agent `wd-r368` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 49 轮**：`git diff --numstat` 与 r326~r367 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0），2 untracked
（`scripts/check_mcpcf_db_isolation.py` 545 行 / `templates/pipeline_mode_loop.md` 211 行）
逐字同 r367 收口后。`src/**` 与 `scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**
（BUG-527 治本 / BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_selftest_hermetic`**（自检 hermetic 守卫 R153：
`--selftest` 只许读合成夹具、禁读真仓现状面，纯静态 AST 污点分析，两条形
H1 调用闭包仓根锚点污染 / H2 相对路径字面量直参；分档 W/R/G 红档 + S/T 记账档 +
C 校准档不进棘轮，R151 根因面的常驻判据）：

- `--selftest` rc=0 **51 格**（族名从已执行格子反解不手写：A×3 / B×3 / C×9 /
  F×7 / G×2 / N×2 / P×4 / R×11 / S×1 / T×5 / W×4）
- 实跑 rc=0：**182 份带自检脚本**，棘轮 W=8/8 R=87/92 G=34/34 三档全在基线内；
  R 现读 87 < 基线 92 属「真还债基线不降」已知状态（`--bless-baseline` 拒绝下调）；
  记账档 10 处（S 自 spawn 跑真尺子 3 / T 约定 gitignored temp/ 读写 7）、
  校准档 8 处全在 `check_scripts_naming.py` 且已显式 `HERMETIC_CALIBRATION` 声明
  （BUG-516 走路②，只豁免读、锚点粒度、不进棘轮）
- 判定口径：「PASS ≠ 零违例」，是「没比基线更差」——本轮无新增、无越线

**撞面核对**：grep git log 反解 r358~r367 近 10 轮巡检面（desc_enum_sync /
sql_bind_alignment / foreign_ledger_entries / two_faces / effective_catch /
dead_params / plan_landing / byte_slice_truncation / backlog_status_staleness /
exit_code_contract），`check_selftest_hermetic` 不在其列，本轮换面不撞。

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
| 唤醒巡检 | git status/log/diff numstat | WIP 静止第 49 轮，Round C 不执行 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| 换面巡检 | check_selftest_hermetic selftest + 实跑 | selftest 51 格 rc=0、实跑 rc=0（W=8/8 R=87/92 G=34/34 全在基线内，记账 10 + 校准 8） |
| FIST 闭环 | T0r124 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能落地——
   取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 49 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），若再持续
   建议 owner 关注 WIP 归属方是否失联。
3. **check_selftest_hermetic 漏红面（判据自述）**：锚点经函数默认参流进读原语不判、
   形参只判一跳、cwd/env 给字符串常量算隔离、跨模块 import 的 helper 不判、
   三跳以上字符串拼装不判、子进程内部再读盘不判——判据自身声明的诚实边界，
   扩面需先攒实测形状，非新缺陷。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册 check_usage_tool_count 同批）。
- 巡检面已轮至 check_selftest_hermetic，下轮可继续轮换未巡检过的守卫面
  （候选：check_mbti_sync / check_pkg_imports / check_doc_paths / check_doc_dup 等）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_selftest_hermetic.py --selftest / 实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解 r358~r367 近 10 轮巡检面撞面核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / TID 稳健提取 / r367 WIP 静止第 48 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r124**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r368**、assignee=wd-r368、
  deliverable=reports/2026-11-17-r368-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T16:34:02Z / updated_at=2026-11-16T16:34:11Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（防 MemoryError）
