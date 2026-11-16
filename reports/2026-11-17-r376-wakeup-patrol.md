# 轮 376 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：376（第 57 轮 WIP 静止态）
- FIST 闭环：T0r132 / agent `wd-r376` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 57 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），`src/engine/engine_circuit_test.mbt` 与
`scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**（BUG-527 治本 /
BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_precedents_doc`**（R121/R213 判例库
`docs/AGENTS-precedents.md` 形态尺：R1 编号连续无跳号/不重号、R2 AGENTS.md
「判例-32~N 已搬出」指针对表、R3 每条判例标题含日期戳；抬头按**语义取数**、
两种排版形（`### 判例-N：` 与 `## 判例-N ·`）都进 R1/R2，防「尺绿而它管的
对象已经漂移」；自拒契约 rc=2——判例库读不到/一条都解析不到/指针句缺失即
拒绝出绿灯）：

- `--selftest` **rc=0**（`SELFTEST OK（20 格：形 6 + 双形 6 + 变异 4 + 旗标 4，
  格数由格子清单算出、不手写计数；全部合成入参不读真仓，变异 4 格只读本尺自身
  源码的 RE_HEADING 真代码行）`；旗标面同步证明正确拒绝 `--self-test` 拼写与
  位置参数——「新判据必须拒绝未知旗标」纪律在本面是活的）
  ⇒ **判据本身健康，不是坏尺**
- 实跑 **rc=0**（`PASS 判例库形态：判例-32..47 连续 16 条（抬头按语义取数，
  两种排版形都进 R1/R2）、日期戳齐、AGENTS.md 指针对表一致`）

**判定：判例库面干净，无新发现。** 判例库当前到判例-47（较 R213 修尺时点的
45 增长 2 条：判例-46/47 为正常判例沉淀），编号连续、日期戳齐、AGENTS.md
指针与实测最大编号对表一致；判例库与 AGENTS.md 全在提交面（不在 WIP 组内），
rc=0 干净映射非 WIP 投影噪声。

### 撞面核对

grep git log 反解近 20 轮换面巡检面（20 面各异）：
check_model_auth_no_key / check_workflow_step_parity / check_doc_paths /
check_doc_surface / check_arg_face_strict / check_mcp_stdio_purity /
check_ps_encoding / check_selftest_hermetic / check_exit_code_contract /
check_backlog_status_staleness / check_byte_slice_truncation / check_plan_landing /
check_dead_params / check_effective_catch / check_two_faces /
check_foreign_ledger_entries / check_sql_bind_alignment / check_desc_enum_sync /
check_tool_add_completeness / check_store_tables_wired —— **`check_precedents_doc`
零命中**，本面为本轮重新覆盖、非撞面（r375 后续建议已点名本面为候选之一）。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐，R3b/R7 扫现状面 168 份、历史面豁免 25 份，R8 清单分组
  19 组 ΣN=183（已与实测 183 对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 6 次 + FIST 六步链 1 次（后台串跑）
- 零文件改动（换面巡检只读 + 记录，禁区 WIP 零碰），无新依赖安装

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log | WIP 静止第 57 轮，Round C 不执行 |
| 换面选面 | ls check_*.py × 近 20 轮巡检面反解 | 选 check_precedents_doc（R121/R213 判例库形态尺/零撞面/r375 点名候选） |
| 换面巡检 | check_precedents_doc selftest | rc=0（20 格含变异与旗标拒档，判据健康非坏尺） |
| 换面巡检 | check_precedents_doc 实跑 | **rc=0**（判例-32..47 连续 16 条、日期戳齐、指针对表一致，无新发现） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r132 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 57 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
   半个自然月余；建议 owner 关注 WIP 归属方是否失联。本轮定性延续 r374/r375：
   该 WIP 形似一次接近完成的判据接线工作（判据本体 545 行已写好、注册与配套
   文档已起笔），若归属方长期失联，owner 可裁决接管收口或回滚该 WIP——属
   不可逆操作，需 owner 明确授权，巡检不代行。
3. **r372 真发现待 WIP 收口方修**（WIP 模板 `templates/pipeline_mode_loop.md:86`
   的 run_check 示例缺必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），
   收口方应一并修全（照同文件 60 行），否则收口后 `check_doc_surface` 实跑仍会
   rc=1 红。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现），收口后 `check_doc_surface` 实跑方转绿。
- 巡检面下轮继续轮换未巡检过的守卫面（候选：check_release_asset_names /
  check_publish_payload / check_entry_paths / check_esm_bundle_runnable /
  check_plugin_sync / check_doc_dup / check_mbti_eol / check_tool_coverage 等
  未在近期出现过的面）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline（唤醒巡检，只读实测）
- scripts/check_precedents_doc.py --selftest / 实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- grep git log 反解近 20 轮巡检面撞面核对 + ls scripts/check_*.py 全量判据清单
- memory 注入（FIST 链后台收口法 / 健壮 TID 提取 / r375 WIP 静止第 56 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r132**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r376**、assignee=wd-r376、
  deliverable=reports/2026-11-17-r376-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T20:32:48Z / updated_at=2026-11-16T20:33:00Z
