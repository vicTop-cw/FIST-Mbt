# 轮 372 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：372（第 53 轮 WIP 静止态）
- FIST 闭环：T0r128 / agent `wd-r372` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 53 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），numstat 与 r326~r371 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0、2 untracked），
`src/engine/engine_circuit_test.mbt` 与 `scripts/run_guards.py` 仍 M ⇒
**Round C 三件维持过期不执行**（BUG-527 治本 / BUG-530 修复 / run_guards 注册
check_usage_tool_count 均未解禁）。R192 车道自 r318 停摆持续。

本轮走**巡检分支**，换面巡检 **`check_doc_surface`**（J1~J19 文档面单一真源守卫，
R116 立；本轮聚焦 J8 模板调用面契约 / J17 工具链地板对表 / J19 USAGE 参数列↔schema）：

- `--selftest` **rc=0**（`SELFTEST OK`：真源解析 183 工具，J3/J4/J6/J7/J8/J9/J10/
  J11/J12/J13/J14/J15/J17/J18/J19 对合成违例均发红 + 反向对照不误红——含『干净输入
  不得误红』『J11 合法态不误红』『J12 注释 refs/heads 不误红』『J13 标题戳早于权威
  published 不误红』等）⇒ **判据本身健康，不是坏尺**
- 实跑 **rc=1**：**一个真发现（非误报）** —— J8 报
  `templates/pipeline_mode_loop.md:86 run_check(...) 缺必填参数 ['cmd','task_id']`

### 真发现（WIP 模板缺陷 · 只记录不碰）

`templates/pipeline_mode_loop.md` 是 WIP untracked 文件（禁区）。其**第 86 行**的
`run_check` 调用示例用 `...` 省略了必填参数：

```
- `run_check({ ... "args": ["test"] ... })` → 汇总行 N 作 `current_test_count`。
```

而 templates/ 全树**其余 10 处** `run_check({...})` 调用示例**全部写全**五个参数
`task_id` / `cmd` / `args` / `workdir` / `timeout_ms`：
`bugfind:50` / `fix_and_merge:66`（同段两发）/ **`loop:60`（同一文件自身）** /
`polish:46,48` / `tidy:46,47,48` / `verify:47`。同文件第 142 行的 `run_check` 参数表
也列全 `task_id`、`cmd`、`args`、`workdir`、`timeout_ms`。

**判定：判据对省略约定非假阳，是 WIP 模板真缺陷**——J8 只报 `['cmd','task_id']`
（`workdir`/`timeout_ms` 属可选）= 与真源 schema 的 required 集精确吻合；而该文件
第 60 行（同文件的基线度量步骤）已示范了正确写法，第 86 行明显是推进步骤里图省事的
`...` 快捷写法漏补全。**严重度低**：该文件 untracked（CI 干净检出无此文件，不影响
CI 门禁），只在本脏工作树显现，属 WIP 在制品的遗留缺陷。

**处置**：禁区文件**只记录不碰**（另一 agent 的 WIP），本巡检不修改、不提交它。
立账入口：`bugs.md` 同属 WIP 禁区（M）⇒ 无法同批入账，本发现**入本报告**留档，
待 WIP 收口方一并修（第 86 行照第 60 行补全 `task_id`/`cmd`/`workdir`/`timeout_ms`）。

### 撞面核对

grep git log 反解近 22 轮，`check_doc_surface` **不在**近期巡检面（近 15 轮：
arg_face_strict / mcp_stdio_purity / ps_encoding / selftest_hermetic / exit_code_
contract / effective_catch / desc_enum_sync / delivery_gap / dead_params / byte_slice_
truncation / backlog_status_staleness / two_faces / sql_bind_alignment / plan_landing /
store_tables_wired），本轮换面不撞。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_
  rubric 对齐，R8 分组 19 组 ΣN=183
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 资源消耗

- 唤醒巡检一轮；bash 调用约 14 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node
  MCP server）
- 零文件改动（换面巡检 + 真发现均只读 + 记录，禁区 WIP 零碰），无新依赖安装
- patch_esm_main 探针先行（10 bundle 全 up to date / total patched 0，防 MemoryError）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/numstat | WIP 静止第 53 轮，Round C 不执行 |
| 换面巡检 | check_doc_surface selftest | rc=0（J3~J19 合成违例全发红，判据健康） |
| 换面巡检 | check_doc_surface 实跑 | **rc=1 真发现**（J8：loop.md:86 run_check 缺 cmd/task_id） |
| 真发现定性 | 对比全树 11 处 run_check 示例 + 读 WIP 86 行 | 判据非假阳，WIP 模板缺陷，记录不碰 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r128 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能
   落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 53 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨半个
   自然月余；建议 owner 关注 WIP 归属方是否失联（该 WIP 含 src/engine 测试与 run_guards
   注册，形似一次未收口的判据接线工作；若归属方长期失联，owner 可裁决接管收口或回滚
   该 WIP——属不可逆操作，需 owner 明确授权，巡检不代行）。
3. **本轮新发现**（WIP 模板 `templates/pipeline_mode_loop.md:86` 的 run_check 示例缺
   必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），但 WIP 收口方应一并修
   全（照同文件 60 行），否则收口后 `check_doc_surface` 实跑仍会 rc=1 红。
4. **WIP 内 2 个 untracked 新文件**（`scripts/check_mcpcf_db_isolation.py` 545 行 /
   `templates/pipeline_mode_loop.md` 211 行）自 r326 起零增长——收口方需同批登记执行面
   （判例-5 族），否则 `check_battery_count_doc` 会 FATAL 全仓门禁停摆。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**（本报告
  真发现），收口后 `check_doc_surface` 实跑方转绿。
- 巡检面下轮继续轮换未巡检过的守卫面（候选：check_release_asset_names /
  check_demo_isolation / check_publish_payload / check_entry_paths / check_badge 等未在
  r356~r372 出现过的面）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status --short / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_doc_surface.py --selftest / 实跑输出（本轮实测）
- templates/ 全树 grep run_check（11 处调用示例对比定性）+ read_file loop.md:70~109
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解近 22 轮巡检面撞面核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / r371 WIP 静止第 52 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r128**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r372**、assignee=wd-r372、
  deliverable=reports/2026-11-17-r372-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T18:36:31Z / updated_at=2026-11-16T18:36:47Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（rc=0，防 MemoryError）
