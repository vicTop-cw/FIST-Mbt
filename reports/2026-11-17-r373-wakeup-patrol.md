# 轮 373 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：373（第 54 轮 WIP 静止态）
- FIST 闭环：T0r129 / agent `wd-r373` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 54 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），numstat 与 r326~r372 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0、2 untracked 545+211 行），
`src/engine/engine_circuit_test.mbt` 与 `scripts/run_guards.py` 仍 M ⇒
**Round C 三件维持过期不执行**（BUG-527 治本 / BUG-530 修复 / run_guards 注册
check_usage_tool_count 均未解禁）。R192 车道自 r318 停摆持续。

本轮走**巡检分支**，换面巡检 **`check_doc_paths`**（R135 文档路径真源守卫：
canonical 文档里反引号包裹的 `src|scripts|docs|templates|patches/…` 路径必须真实
存在——R134 连带发现「白盒锁文件从未存在」那一类「文档承诺了不存在的文件」缺陷）：

- `--selftest` **rc=0**（`SELFTEST OK` 5 格：`all-paths-exist-passes` /
  `missing-path-is-caught`（变异对照：把路径从存在集拿掉必被抓到，判例-29/30）/
  `placeholder-is-exempt`（`xxx`/`<…>`/`*` 示例写法豁免不误红）/ `prose-not-parsed`
  （非路径文本不误报）/ `dedupe-same-path`（同路径多次只查一次））⇒ **判据本身
  健康，不是坏尺**
- 实跑 **rc=0**（`PASS 文档路径引用全部存在（8 份文档 / 47 处引用）`）

**判定：扫描面干净，无新发现。** 8 份 canonical 文档
（AGENTS.md / README.md / README_EN.md / ARCHITECTURE.md / README.mbt.md /
docs/agent-map.md / docs/deliverable.md / docs/SOP.md）**全部是提交面文件**，
无一在 WIP 组内（WIP 的 docs/improvement-plan-20261010.md 与 memory/target.md 均
不在 check_doc_paths 的 DOCS 清单），故本轮 rc=0 干净映射「文档承诺的路径全部
真实存在」，非 WIP 投影噪声。47 处引用无一缺文件。

### 撞面核对

grep git log 反解近 22 轮，`check_doc_paths` **不在**近期巡检面（近 22 轮已巡检的
20 面：arg_face_strict / backlog_status_staleness / byte_slice_truncation /
dead_params / delivery_gap / desc_enum_sync / doc_surface / effective_catch /
exit_code_contract / foreign_ledger_entries / mcp_stdio_purity / ns_write_gate_
coverage / ofm_endpoint / plan_landing / ps_encoding / selftest_hermetic /
sql_bind_alignment / store_tables_wired / tool_add_completeness / two_faces×2），
本轮换面不撞。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_
  rubric 对齐，R8 分组 19 组 ΣN=183（已与实测对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 15 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node
  MCP server）
- 零文件改动（换面巡检只读 + 记录，禁区 WIP 零碰），无新依赖安装
- patch_esm_main 探针先行（10 bundle 全 up to date / total patched 0，防 MemoryError）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/numstat | WIP 静止第 54 轮，Round C 不执行 |
| 换面选面 | 列全量 check_*.py + 读 8 把候选头部 | 选 check_doc_paths（面干净/高价值/未撞面） |
| 换面巡检 | check_doc_paths selftest | rc=0（5 格含变异对照，判据健康） |
| 换面巡检 | check_doc_paths 实跑 | **rc=0**（8 份文档 / 47 处引用全存在，无新发现） |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r129 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能
   落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 54 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨半个
   自然月余；建议 owner 关注 WIP 归属方是否失联（该 WIP 含 src/engine 测试与 run_guards
   注册，形似一次未收口的判据接线工作；若归属方长期失联，owner 可裁决接管收口或回滚
   该 WIP——属不可逆操作，需 owner 明确授权，巡检不代行）。
3. **r372 真发现待 WIP 收口方修**（WIP 模板 `templates/pipeline_mode_loop.md:86` 的
   run_check 示例缺必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），收口方
   应一并修全（照同文件 60 行），否则收口后 `check_doc_surface` 实跑仍会 rc=1 红。
4. **WIP 内 2 个 untracked 新文件**（`scripts/check_mcpcf_db_isolation.py` 545 行 /
   `templates/pipeline_mode_loop.md` 211 行）自 r326 起零增长——收口方需同批登记执行面
   （判例-5 族），否则 `check_battery_count_doc` 会 FATAL 全仓门禁停摆。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**（r372
  真发现），收口后 `check_doc_surface` 实跑方转绿。
- 巡检面下轮继续轮换未巡检过的守卫面（候选：check_release_asset_names /
  check_demo_isolation / check_publish_payload / check_entry_paths / check_badge /
  check_esm_bundle_runnable / check_plugin_sync 等未在 r356~r373 出现过的面）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status --short / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_doc_paths.py --selftest / 实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解近 22 轮巡检面撞面核对 + ls scripts/check_*.py 全量判据清单
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / r372 WIP 静止第 53 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r129**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r373**、assignee=wd-r373、
  deliverable=reports/2026-11-17-r373-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T19:05:07Z / updated_at=2026-11-16T19:05:19Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（rc=0，防 MemoryError）
