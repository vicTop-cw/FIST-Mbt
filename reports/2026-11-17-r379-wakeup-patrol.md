# 轮 379 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：379（第 60 轮 WIP 静止态）
- FIST 闭环：T0r135 / agent `wd-r379` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 60 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），`src/engine/engine_circuit_test.mbt` 与
`scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**（BUG-527 治本 /
BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。
numstat 合计 6 文件 240+/3-，与 r378 逐字相同（零再增长）；`memory/bugs.md`
仍 216/0 零再增长（与 r326~r378 同组零增量）。

本轮走**巡检分支**，换面巡检 **`check_store_tables_wired`**（BUG-28 双向接线
闸——store 里每张表要么**有写入点**、要么在 store 源文件里**显式声明预留**
`schema-reserved: <表名>`；判据双向：无写入点且未声明预留→红（第二张 runs），
声明了预留却有写入点→红（声明滞后），解析不到任何表→FATAL(2) 扫描面空转绝不
报绿；覆盖面真源 = `store_sqlite.mbt` 的 `CREATE TABLE` 正则反解，不硬编码；
三档 rc：0 全绿 / 1 违例 / 2 判据无法自证；R66 严格参数面，未知旗标即 FATAL）。
本面上次巡检为 r356（22 轮前），近 20 轮零命中、非撞面。

- `--selftest` **rc=0**（`SELFTEST OK: 判据对「死 schema」与「声明滞后」两个
  方向都发红，干净输入不误红，表名解析口径可证`）⇒ **判据本身健康，不是坏尺**
- 实跑 **rc=0**（`PASS store schema 接线一致：32 张表 = 31 张有写入点 + 1 张
  显式预留（runs）`）⇒ schema 接线面干净，runs 死 schema 仍按 BUG-28 预期显式
  预留，无新发现

### 撞面核对

grep git log 反解近 20 轮换面巡检面（check_esm_bundle_runnable /
check_precedents_doc / check_model_auth_no_key / check_workflow_step_parity /
check_doc_paths / check_doc_surface / check_arg_face_strict /
check_mcp_stdio_purity / check_ps_encoding / check_selftest_hermetic /
check_exit_code_contract / check_backlog_status_staleness /
check_byte_slice_truncation / check_plan_landing / check_dead_params /
check_effective_catch / check_two_faces / check_foreign_ledger_entries /
check_sql_bind_alignment / check_desc_enum_sync / check_mbti_eol /
check_mcpcf_db_isolation / check_scripts_naming 等）—— **`check_store_tables_wired`
零命中**；其最近一次 git log 引用为 r356 巡检报告（22 轮前），无近 20 轮巡检引用
⇒ 本面为本轮轮换、非撞面。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐，R3b/R7 扫现状面 168 份、历史面豁免 25 份，R8 清单分组
  19 组 ΣN=183（已与实测 183 对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 8 次 + FIST 六步链 1 次（后台串跑）
- 零文件改动（换面巡检只读 + 记录，禁区 WIP 零碰），无新依赖安装

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/diff | WIP 静止第 60 轮，Round C 不执行 |
| 换面选面 | git log 近 20 轮撞面反解 + 候选陈旧度普查 | 选 check_store_tables_wired（r356 后 22 轮未用、近 20 轮零命中、BUG-28 重要闸） |
| 换面巡检 | check_store_tables_wired selftest | rc=0（双向发红 + 干净不误红 + 解析口径可证，判据健康非坏尺） |
| 换面巡检 | check_store_tables_wired 实跑 | **rc=0**（32 表 = 31 有写入点 + 1 显式预留 runs） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r135 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 60 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
   半个自然月余；owner 可裁决接管收口或回滚该 WIP（不可逆操作，需明确授权，
   巡检不代行，同 r374/r375/r377 定性）。
3. **r372 真发现待 WIP 收口方修**（WIP 模板 `templates/pipeline_mode_loop.md:86`
   的 run_check 示例缺必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），
   收口方应一并修全，否则收口后 `check_doc_surface` 实跑仍会 rc=1 红。
4. **r377 观察一/二仍待专门轮修**（`scripts/check_esm_bundle_runnable.py`，
   不在 WIP 组、不阻塞也不被阻塞）：观察一为纪律面破口（每次 commit 电池都在
   build 目录重写台账）+ `check_demo_isolation` 检测盲区；观察二为覆盖面口径
   污染。修复规格见 r377 报告，建议同一笔提交修全 + 同批自测。

## 后续建议

- **下轮候选**：观察一/二修复轮（r377 规格已备）；或继续轮换未巡检面
  （check_publish_payload r334 后 45 轮未用 / check_release_asset_names r346 后
  33 轮未用 / check_entry_paths r345 后 34 轮未用；check_store_tables_wired 本轮
  已用、check_plugin_sync 脏树必现 WIP 投影漂移暂避）。
- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline -3 / git diff --numstat（唤醒巡检，只读实测）
- scripts/check_store_tables_wired.py --selftest / 实跑输出（本轮实测）
- reports/2026-11-17-r378-wakeup-patrol.md（r378 后续建议点名候选 + r377 观察一/二）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- memory 注入（FIST 链后台收口法 / 健壮 TID 提取 / WIP 禁区纪律 /
  r378 静止第 59 轮与点名候选）

## FIST 闭环核实格（终审回填）

- TID = **T0r135**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r379**、assignee=wd-r379、
  deliverable=reports/2026-11-17-r379-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T22:06:54Z / updated_at=2026-11-16T22:07:05Z
