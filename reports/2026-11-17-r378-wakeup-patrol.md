# 轮 378 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：378（第 59 轮 WIP 静止态）
- FIST 闭环：T0r134 / agent `wd-r378` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 59 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），`src/engine/engine_circuit_test.mbt` 与
`scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**（BUG-527 治本 /
BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。
numstat 合计 6 文件 240+/3-，`memory/bugs.md` 仍 216/0 零再增长（与 r326~r377 同组零增量）。

本轮走**巡检分支**，换面巡检 **`check_mbti_eol`**（`.mbti` 行尾闸，2026-10-23
Windows `core.autocrlf=true` 实测踩坑后落——`moon info` 生成的 `.mbti` 本为
LF，checkout 转 CRLF 会让"没改任何语义只跑了一次 moon info"就变 dirty；
`.gitattributes` 钉 `*.mbti text eol=lf` 是本仓的修复，本尺是它的守卫：
规则在 + **git 跟踪面全部 `.mbti`** 的 HEAD blob 纯 LF（覆盖面真源 =
`git ls-files '*.mbti'`，不硬编码——早先 3 份硬编码而全仓 24 份，判例-16
「判据覆盖必须 ≥ 主张的覆盖」形状已修）+ 工作树 `.mbti` 不 dirty；
三档 rc：0 全绿 / 1 规则缺失·blob 有 CR·工作树 dirty / 3 非 git 仓诚实跳过；
`rules_cover_mbti` / `blob_has_cr` 纯函数可单测，`--selftest` 只验纯函数合成样本）。
**本面从未进过巡检轮**（grep reports/ 全库零命中，本轮首次覆盖）。

- `--selftest` **rc=0**（`SELFTEST OK（13 格：规则 8 / blob 4 / 覆盖面 1）`）
  ⇒ **判据本身健康，不是坏尺**
- 实跑 **rc=0**（`PASS .mbti 行尾闸：规则在 / HEAD blob 纯 LF / 工作树文件纯
  LF（EOL 面全绿）`）⇒ 行尾纪律面干净，autocrlf 噪声未复发

### 撞面核对

grep git log 反解近 20 轮换面巡检面（20 面各异：check_esm_bundle_runnable /
check_precedents_doc / check_model_auth_no_key / check_workflow_step_parity /
check_doc_paths / check_doc_surface / check_arg_face_strict /
check_mcp_stdio_purity / check_ps_encoding / check_selftest_hermetic /
check_exit_code_contract / check_backlog_status_staleness /
check_byte_slice_truncation / check_plan_landing / check_dead_params /
check_effective_catch / check_two_faces / check_foreign_ledger_entries /
check_sql_bind_alignment / check_desc_enum_sync）—— **`check_mbti_eol` 零命中**；
grep reports/ 全库「换面巡检 check_mbti_eol」亦零命中 ⇒ 本面为本轮首次覆盖、
非撞面。（近 120 轮窗口内 git log 仅见 `check_mbti_eol` 出现在其自身
feat/fix 提交，无巡检轮引用。）

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
| 唤醒巡检 | git status/log | WIP 静止第 59 轮，Round C 不执行 |
| 换面选面 | r377 后续建议候选 × 4 + git log 近 120 轮撞面反解 + reports/ 全库 grep | 选 check_mbti_eol（r377 点名候选中唯一从未进过巡检轮、零撞面） |
| 换面巡检 | check_mbti_eol selftest | rc=0（13 格：规则 8 / blob 4 / 覆盖面 1，判据健康非坏尺） |
| 换面巡检 | check_mbti_eol 实跑 | **rc=0**（EOL 面全绿：规则在 + HEAD blob 纯 LF + 工作树纯 LF） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r134 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 59 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
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
  （check_release_asset_names r346 后 32 轮未用 / check_publish_payload r334 后
  44 轮未用 / check_entry_paths r345 后 33 轮未用；check_mbti_eol 本轮已用、
  check_plugin_sync 脏树必现 WIP 投影漂移暂避）。
- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline -3 / git diff --numstat（唤醒巡检，只读实测）
- scripts/check_mbti_eol.py --selftest / 实跑输出（本轮实测）
- reports/2026-11-17-r377-wakeup-patrol.md（r377 后续建议点名候选 + 观察一/二）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- memory 注入（FIST 链后台收口法 / 健壮 TID 提取 / WIP 禁区纪律 /
  r377 静止第 58 轮与点名候选）

## FIST 闭环核实格（终审回填）

- TID = **T0r134**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r378**、assignee=wd-r378、
  deliverable=reports/2026-11-17-r378-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T21:32:53Z / updated_at=2026-11-16T21:33:04Z
