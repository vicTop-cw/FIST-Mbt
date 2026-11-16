# 轮 370 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：370（第 51 轮 WIP 静止态）
- FIST 闭环：T0r126 / agent `wd-r370` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 51 轮**：`git diff --numstat` 与 r326~r369 逐字同
（bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
run_guards.py 9/0、engine_circuit_test.mbt 5/0），2 untracked
（`scripts/check_mcpcf_db_isolation.py` 545 行 / `templates/pipeline_mode_loop.md` 211 行）
逐字同 r369 收口后。`src/**` 与 `scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**
（BUG-527 治本 / BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_mcp_stdio_purity`**（MCP server 的 **stdout 纯净性**
判据 BUG-477：MCP stdio 传输把 stdout 当 JSON-RPC 通道，任何非 JSON 输出都会污染整个
server——BUG-476 当时一行 `println` 就把 server 打死，而同一时刻 `moon test` 1835/1835
全绿（moon test 走引擎层调用、结构上看不见 stdio 缺陷）⇒ 三层判据 L1 静态 +
L2 生产启动描述握手 + L3 工具调用）：

- `--selftest` rc=0 **19/19 格**：形态识别 8（`println`/`print`/`print_char` 命中、
  `eprintln`/`eprint`/注释/字符串字面量正确放行）
  + 变异对照 6（真往产品文件写 `println` 必红 / 注释与字符串诱饵不误报 / 干净 mini 基线）
  + 反脱锚 2（`src/server` 缺失 / 一个 `instrumented_tool` 都解析不到 ⇒ rc=4 尺子坏了，不判绿）
  + L2/L3 判据 3（非 JSON 行判脏 rc=1 / 空输出 rc=2 无法自证 / 干净 JSON rc=0）
- 实跑 rc=0：**L1** 静态扫 41 个产品文件（181 处 `instrumented_tool`）干净；
  **L2** 原样读 `.mcp.json` 生产启动描述（`node serve-launcher.cjs serve`）spawn，
  喂一行 `initialize`，stdout 2 行全部是合法 JSON-RPC；
  **L3** `tools/call` 回执有 `result.content`（R33 `KeyError: 'content'` 场景复刻位）

**撞面核对**：grep git log 反解 r356~r369 近 14 轮巡检面（store_tables_wired /
tool_add_completeness / desc_enum_sync / sql_bind_alignment / foreign_ledger_entries /
two_faces / effective_catch / dead_params / plan_landing / byte_slice_truncation /
backlog_status_staleness / exit_code_contract / selftest_hermetic / ps_encoding），
`check_mcp_stdio_purity` 不在其列，本轮换面不撞。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/scoring_rubric 对齐，R8 分组 19 组 ΣN=183
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

**无新发现（类型）、无新立账。** 禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 资源消耗

- 唤醒巡检一轮；bash 调用约 15 次 + FIST 六步链 1 次（后台串跑，每步独立冷启动 node MCP server）
- 无新文件创建（报告 + 链脚本 + desc 为轮次记账面），无依赖安装
- patch_esm_main 探针先行（防 MemoryError，见 FIST 闭环核实格）

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log/diff numstat | WIP 静止第 51 轮，Round C 不执行 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| 换面巡检 | check_mcp_stdio_purity selftest + 实跑 | 均 rc=0（19/19 格 / L1+L2+L3 全过） |
| FIST 闭环 | T0r126 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册均不能落地——
   取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 51 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
   半个自然月（r326 首次逐字同读数起算 51 轮 ≈ 25.5 小时唤醒轮次）；若再持续
   建议 owner 关注 WIP 归属方是否失联（该 WIP 含 src/engine 测试与 run_guards 注册，
   形似一次未收口的判据接线工作）。
3. **WIP 内 2 个 untracked 新文件**（`scripts/check_mcpcf_db_isolation.py` 545 行 /
   `templates/pipeline_mode_loop.md` 211 行）自 r326 起零增长——若归属方收口时
   忘记补「scripts/ 加 .py 必须同批给执行面」纪律（判例-5 族），
   `check_battery_count_doc` 会 FATAL 全仓门禁停摆；收口方需同批登记执行面。

## 后续建议

- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册 check_usage_tool_count 同批）。
- 巡检面已轮至 check_mcp_stdio_purity，下轮可继续轮换未巡检过的守卫面
  （候选：check_release_asset_names / check_demo_isolation / check_publish_payload /
  check_entry_paths 等未在 r356~r369 出现过的面）。
- 基线外外来条目 BUG-613~635（23 条）继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记。

## 超额内容

无。

## 来源

- git status / git log --oneline / git diff --numstat（唤醒巡检实测）
- scripts/check_mcp_stdio_purity.py --selftest / 实跑输出（本轮实测）
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- scripts/patch_esm_main.py 探针输出（本轮实测，见 FIST 核实格）
- grep git log 反解 r356~r369 近 14 轮巡检面撞面核对
- memory 注入（FIST 链后台收口法 / patch_esm_main 探针 / TID 稳健提取 / r369 WIP 静止第 50 轮）

## FIST 闭环核实格（终审回填）

- TID = **T0r126**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r370**、assignee=wd-r370、
  deliverable=reports/2026-11-17-r370-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T17:35:57Z / updated_at=2026-11-16T17:36:07Z
- patch_esm_main 探针先行：10 bundle 全 up to date / total patched 0（rc=0，防 MemoryError）
