# 2026-09-29 · 终审前收口报告（清 bug / 无回归 / demo 可用 / 探索模式）

> 基线：master `214fd8a` + 本工作树（含并发车道的 help 子命令、loop 重构、F094 规格与 `.mcp.json`）
> 指挥官：butler ｜ 依据：owner 2026-09-29 终审目标（见 §1）
> 本报告所有计数均从盘上反解，不手加；每条主张后面跟着它的复现命令或回执文件。

## 1. 结果摘要

Owner 本轮要求七件事，逐件的状态：

| # | 要求 | 状态 | 证据位置 |
|---|---|---|---|
| 1 | 将所有 bug 清掉（开工时 OPEN 3 条：BUG-116/118/119） | BUG-119 FIXED（实测）；BUG-118 权威 CI 门已落地、版本钉定案项如实留白；BUG-116 走"给用户一条能装上的线 + 常驻判据"的收口 | `memory/bugs.md` 抬头 + `### FIXED` 小记 |
| 2 | 确保无回归 | `moon test --target js -j 1` 全量通过（数字见 §3），守卫族逐条 rc=0；新增判据在 `git archive HEAD` 旧码树上发红（证明锁承重） | `temp/final_js.log`、`temp/head119_guard.log` |
| 3 | 符合本项目开发文档（`AI-DEVELOPMENT-STANDARD.md`） | 一源四态（cl7 重投影）、证据梯 L4（每条实测）、确定性优先（新增纯函数零 IO）、增量零回归（默认语义不变，只改被判死的那一支） | §6 checklist |
| 4 | 提供的 demo 完全可用 | 根因是 `cmd/cli/main.mbt` 把 serve 横幅打回 stdout（BUG-101 的修复被并发改动重新启用）⇒ 一条 `eprintln` 修好整族 stdio demo；其余 demo 脚本缺口逐条见 §4 | `temp/demo-audit-20260929.md` |
| 5 | 文档提及 fist-evidence 是叙事/证据项目 | README（中英）/USAGE/docs/atgc-selfdrive-demo/AGENTS 现状面都挂了指针，口径统一为「三组受控实验 + 十份真实项目驱动实例（覆盖八项目）」 | §5 |
| 6 | 定位语 `fist-mbt — AI 自驱式开发的项目管理者`，自驱与递归拆解为一等打磨对象 | README/README_EN/AGENTS/USAGE 首屏落位，且与"它用它自己的自驱式 + 递归拆解把自己打磨到可交付态"接上而不是并列 | §5 |
| 7 | 新增自驱模式「探索模式」（按复杂度自选单模式，必要时并行多模式，前提是文件不冲突） | 注册表 7 种模式 + 模板 `templates/pipeline_mode_explore.md` + 复杂度分档/估算/并行许可的纯函数 + 白盒锁 + 四宿主投影 | §2 |

## 2. 探索模式（explore）落在哪

- 注册表：`src/ops/ops_modes.mbt` —— `PipelineMode::Explore`、`parse_mode("explore")`、
  `mode_display_name` 「探索：按复杂度自选模式」、`mode_constraints` 三个新键
  `require_complexity_scoring` / `allow_parallel_modes` / `require_disjoint_files`，
  `all_modes()` 由 6 项长到 7 项（`mode_list` 直接投影它，MCP 工具数保持 129，没有新增工具）。
- 决策件（纯计算、零 IO、可复现）：`estimate_complexity`（0..5，复用难度单一抽取来源，不另起口径）、
  `select_mode_by_complexity`（分档表在函数 doc-comment 里）、`complexity_band_of_tier`、
  `file_scope_conflicts` / `file_scopes_disjoint`、`explore_plan`（返回 chosen_mode / complexity /
  basis / parallel_modes / parallel_allowed / conflict_gate）。
- 并行的许可条件写成具体工具调用而不是形容词：每一路先用 `reserve_scope` 拿到
  `reserved`/`renewed`/`taken_over`，认领前 `conflicts_check` 必须可认领，且申报的文件作用域两两不相交；
  任何一路失守 ⇒ 当场退回串行（`templates/pipeline_mode_explore.md` §三、§五）。
- 递归拆解接法：`templates/pipeline_mode_explore.md` §步骤 3.5——`c ≥ 3` 且目标复合时先 `task_plan_deep`
  拆一层（建议 `reinject_context=true` + `boundary_probe=true`），**每个子树重新算一次 c**，
  并行门申报的文件作用域取自各子树边界（可由 `dag_ascii`/`dag_depend` 回读），于是"一个复合大目标"
  长成"verify + polish + bugfind 三条各自够格的腿"而不是 `advance` 大包大揽。
- 调用面实测（不是自述）：`node _build/js/debug/build/cmd/cli/cli.js serve` 起真产物 →
  `tools/list` 129 个工具（**未新增工具**）、`mode_list` 回 7 条且 explore 条目带
  `require_complexity_scoring/allow_parallel_modes/require_disjoint_files=true` 与
  `template_path: templates/pipeline_mode_explore.md`、`mode_templates` 回
  `{... "explore": true}, missing: []`。顺带把 `mode_templates` 的名单从硬编码 6 名改成
  从注册表 `all_modes()` 反解——否则"注册表 7 种、这里只查 6 种"会让模板缺席无人可报。
- 白盒锁：`src/ops/ops_modes_wbtest.mbt`（`all_modes 长度 7`、分档边界、重叠作用域必须拒绝并行）。
- `loop_create`/`pipeline_tick` 的 step 合法集同时接受 `explore`（`src/ops/ops_loop.mbt`）。

## 3. 无回归：实测账

- 全量 JS 轨（权威门槛）：`moon test --target js -j 1` → `Total tests: 572, passed: 572, failed: 0.`
  （`temp/final_js.log`，rc=0）。开工基线 535/535；+37 条 = 探索模式白盒 25→59（+34）
  与看护成对改写（`ops_test` 1→2、`ops_watchdog_test` A-3→A-3a/3b/3c，+3）。
  现状面的 535 已按 `check_test_sync` 逐面同步到 572：`AGENTS.md`、`README_EN.md`（含徽章）、
  `ARCHITECTURE.md`、`README.mbt.md`、`docs/{SHIP-PLAN-BLACKBOX-v2,agent-map,atgc-selfdrive-demo,deliverable,evolve}.md`、
  `scripts/scoring_rubric.md`；`README.md` 的徽章与正文由收口最后一步同步（并发车道正在改该文件）。
- 守卫族（逐条 rc，日志在 `temp/g_*.log`）：`check_tools_sync` 0 / `check_doc_surface` 0（含 `--selftest` 0）/
  `check_store_tables_wired` 0 / `check_entry_paths` 0 / `check_ps_encoding` 0 /
  `check_scripts_index` 1（`gen_help_docs.py` 未登记，见 §7.3）/ `check_plugin_sync` 1（待 `gen_plugins.py` 重投影，见 §6）。
- 新增判据的承重证明：`temp/head119_guard.log` —— 同一份 `e2e_heartbeat_xproc.py` 在
  `git archive HEAD` 的旧码树上 **3 绿 5 红**，旧码回执原样
  `heal(timeout_sec=30) -> healed=['T0','T0r2','T0r4']`、`active_tasks={'T0': ''}`；
  修复后同一判据 **8/8 绿**。⇒ 锁不是装饰。
- 未跑的面（如实）：native 轨本轮未复跑，不据旧数宣称双端同版全绿。

## 4. demo 面：一条横幅挡住整族 stdio

- 根因 A（我这条修了）：`cmd/cli/main.mbt::run_serve` 把三行提示用 `println` 打到 stdout，
  而 stdout 只许走 JSON-RPC（BUG-101 的修复被并发改动重新启用）⇒ 27 个 stdio 判据/demo
  在解析第一帧时崩：`RuntimeError: malformed JSON-RPC response: '[fist] serve — ...'`。
  改成 `eprintln` 后 `scripts/mcp_smoke.py` 当场跑通（PASS tools/list → 129 个工具 /
  PASS issue_scan / PASS publish → T0 / PASS get / MCP-SMOKE PASS）。
- 根因 B（并发车道与我分开修）：`.mcp.json` / `.mcp.dev.json` 用 `moon run cmd/cli` 起服务，
  既缺 `serve` 又会重发没打 shim 的 ESM 产物（`require is not defined`）。现状：两者都指向
  `node _build/js/debug/build/cmd/cli/cli.js serve`。
- 我这一轮亲手复跑（不是引用车道回传）：

| demo / 判据面 | 结论 | 我看到的回执（原文行） | 复现 |
|---|---|---|---|
| `node cli.js demo`（七态闭环自包含 demo） | PASS | `[7/7] archive → 已归档` / `🎉 七态闭环全绿 ✅`，rc=0 | `FIST_DB_PATH=temp/demo_cli.db node _build/js/debug/build/cmd/cli/cli.js demo` |
| `node cli.js doctor` | PASS | `5/5 checks 通过` / `🎉 全部通过 ✅` | 同上换 `doctor` |
| `node cli.js help tools` | PASS（本轮修） | 头 `129 MCP tools (13 groups)`、逐组声明和=129、逐项=129（开工时枚举 127/12 组却自称 11 组，`mode_list`/`mode_templates` 根本没在列） | `node … cli.js help tools` |
| `scripts/mcp_smoke.py` | PASS（横幅修后解封） | `PASS tools/list → 129 个工具` / `PASS publish → T0` / `MCP-SMOKE PASS` | `FIST_DB_PATH=… python scripts/mcp_smoke.py` |
| `scripts/atgc_selfdrive_demo.py`（自驱+Omega 旗舰） | PASS | `tasks 13 (期望 1 根 + 12 子节点)`、`specs approved 12/12`、`MCP-ATG-SELFDRIVE PASS · SUCCESS`，且**根台账 1986 任务/6905 调用跑前跑后一致** | `FIST_DB_PATH=temp/atgc_demo_final.db python scripts/atgc_selfdrive_demo.py` |
| `scripts/blackbox/e2e_mirror_install.py` | PASS（版本夹具改为从 moon.mod 反解） | `目标版本 v0.3.4`、`用户 PATH 已还原（1708 字，逐字相同）`、`真产物 … 616b7632 → 616b7632`、`=== 端到端镜像安装：PASS ===` | `python scripts/blackbox/e2e_mirror_install.py` |
| `scripts/cli_flag_probe.py` | PASS | `--help/-h rc=0 首行=FIST-Mbt Help v0.3.4 (129 MCP tools)`、未知参数 rc=2 | `python scripts/cli_flag_probe.py` |
| `scripts/fist.py call project_standards` | PASS | 回 R116 规范 10 条 + cl1–cl7 checklist（机器投影与正文一致） | 同左 |
| `.mcp.json` 连接器 | 已改指 `node …cli.js serve`（原 `moon run cmd/cli` 缺 serve + 未打 shim 必崩）；根 `.mcp.json` **未入库**（`git ls-files` 空）⇒ 需 owner 决定要不要跟踪 | `args: ["_build/js/debug/build/cmd/cli/cli.js","serve"]` | `cat .mcp.json` |
| `scripts/{demo,showcase}.ps1`、`fist-mbt-http.py`、两个 cron 驱动器 | 车道回传已修（`moon run cmd/cli -- demo`、自述数从 moon.mod/注册表反解、退役入口改指 cmd/cli）；我未逐条复跑，如实标 **未独立复验** | `temp/demo-audit-20260929.md` 各条 | 见该日志 |
| `blackbox/e2e_irm_line.py` 公网线 | 本机不稳（BUG-116 本体）：我这轮 rc=1 全针未命中；车道在另一时刻取到真装通 v0.3.4 ⇒ 判据已升级为**两臂**（主臂 + curl 兜底臂），兜底臂红一律拦退出码 | `temp/bug116_irm_recheck_20260929.log` | `python scripts/blackbox/e2e_irm_line.py` |

## 5. 文档面

- 定位语与 fist-evidence 指针的落点：README.md 首屏、README_EN.md 首屏与 `## Evidence` 段、
  USAGE.md §1/§2、docs/atgc-selfdrive-demo.md 头部、AGENTS.md 原有「实证伴生仓」段保留未动。
  口径经 sibling checkout 实测核对：三组实验 + 十份驱动实例（覆盖八项目），
  `stories/…` 只存在于那个仓库，所以每条指针都写明"在伴生仓"。
- 纠正的陈旧计数：README「122 个工具」→ 129；README_EN 三个并存的测试数（310/442/535）统一到
  一个带日期与目标的口径；docs/atgc-selfdrive-demo.md 的 `node main.js` → `node …/cli.js serve`。
- 本轮最终测试数 **572/572**（`moon test --target js -j 1`，`temp/final_js3.log` 尾行 `Total tests: 572, passed: 572, failed: 0.`）
  在文档面的同步位置：`check_test_sync.py` 扫现状面 **105 份文档**、**24 条声明全部 == 实测**（must-carry 5 份齐全、豁免 8 条有效），
  `check_badge.py` 对 README『→ Total tests: 572, passed: 572』逐字相等。改动落点为 ARCHITECTURE.md、README.mbt.md、
  README_EN.md、AGENTS.md、scripts/scoring_rubric.md 与 `docs/{SHIP-PLAN-BLACKBOX-v2,agent-map,atgc-selfdrive-demo,deliverable,evolve}.md`。

## 6. 开发文档合规 checklist（cl1–cl7 + r/f 条）

- cl1 MCP 工具存在性 / cl2 文档逐个可查 / cl3 分组和==实测 / cl4 自述版本==moon.mod /
  cl5 交付物 / cl6 文档同步 / cl7 插件态一致 —— **收口时逐条重跑，rc 全 0**（退出码取自命令替换，不是管道尾）：

  | 守卫 | rc | 回执行（逐字） |
  |---|---|---|
  | `check_tools_sync` | 0 | `PASS 工具单一真源一致：server.mbt 注册 129 个，AGENTS/README/deliverable/scoring_rubric 对齐` |
  | `check_test_sync temp/final_js3.log` | 0 | `PASS 测试总数单一真源一致：实测 572；扫描现状面 105 份文档，24 条声明全部等于实测；must-carry 5 份齐全；豁免 8 条全部有效` |
  | `check_badge temp/final_js3.log README.md` | 0 | `PASS 自检注释一致：README 『→ Total tests: 572, passed: 572』 == 实测 572` |
  | `check_scripts_index` | 0 | `PASS 工具类辅助代码单一索引完整：所有正式脚本均已在 scripts/README.md 登记` |
  | `check_plugin_sync`（cl7） | 0 | `PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.4` |
  | `check_doc_surface`（J1–J10） | 0 | `PASS 文档面一致：129 工具在 AGENTS/README 逐个可查、分组和=129、当前自述版本=0.3.4、J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、J9 返回契约（必查清单 + 歧义键分工 + 棘轮）未退化、J10 判据范围自述==实现` |
  | `check_store_tables_wired` | 0 | `PASS store schema 接线一致：12 张表 = 11 张有写入点 + 1 张显式预留（runs）` |
  | `check_ps_encoding` | 0 | `PASS PowerShell 编码守卫：6 个 .ps1 全部带 BOM 或纯 ASCII（Windows PowerShell 5.1 按 ANSI 读也不会吞引号）` |
  | `check_entry_paths` | 0 | `PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个（扫描面 127 份文件，历史面与守卫自身除外）` |
  | `check_release_asset_names --selftest` | 0 | `SELFTEST OK（干净不误红 + 变异必红；清单从已执行格子反解：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 / R7×3 / R8×3 / R9×2 / R10×2 / R11×5 / R12×2 / R13×2）`（**R13 本轮新增**，钉 BUG-120） |
  | `mcp_tool_tour --surface-selftest` | 0 | `SURFACE-SELFTEST: OK —— 12 支（10 违例 + 1 干净 + 1 自拒），不符 0 支` |
  | `store_isolation_probe` | 0 | `PROBE: GREEN —— 2 格中红 0 格` |
  | `cli_flag_probe`（真产物三档） | 0 | `PASS 调用面三档全对（版本旗=0.3.4 · 未知必非 0 · 帮助旗不落未知臂）` |
  | `blackbox/e2e_heartbeat_xproc`（本轮新增常驻臂） | 0 | `=== E2E-HEARTBEAT-XPROC PASS：8 格全绿（跨进程看护语义已锁） ===` |
  | `moon fmt --check` | 0 | `Finished. moon: no work to do` |
  | `gen_plugins.py` + `check_plugin_sync.py`（BUG-121 修文字后复投） | 0 | `PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.4`；投影行 = `BUG-1~121 共 120 条入账：0 条待修 / 107 条已修 / 9 条重复并入 / 4 条误报` |
  | `output_validate`（cl5 交付物硬门，跑在真产物上） | 0 | `verdict=pass passed=14 failed=0`，`evidence_layer=l4-pass` |

  对应 cl 映射：cl1/cl2/cl3 = `check_tools_sync` + `check_doc_surface`；cl4 = `check_doc_surface` J3 + `cli_flag_probe`；
  cl5 = `output_validate` 14 件；cl6 = `check_test_sync` + `check_badge` + `check_scripts_index`；cl7 = `check_plugin_sync`。
- 一源四态：`plugins/{atomcode,codearts,deepseek-harness,claude}` 由 `gen_plugins.py` 重投影，
  `check_plugin_sync.py` 逐字节比对通过；`.mcp.json` 与 `plugins/claude/.mcp.json` 同源。
- 证据梯：每条"已修"都带调用面实测（两个真进程 / 真产物 / 真安装线），未测的写成未测。

## 7. 遗留风险与需要 owner 决定的事

1. **推送授权**：BUG-116 的公网线与 BUG-118 的"两条轨工具链版本是否同形"，关闭证据只能在
   推送后的 CI 运行里产生（本机对 `cli.moonbitlang.com` 取安装脚本 TLS 失败 rc=35，
   `Invoke-RestMethod` 走系统代理时对 `raw.githubusercontent.com` 传输层被对端关闭）。
   本轮所有提交都只在本地，**没有 push**。
2. **安装器内部的取数段仍是 .NET `Invoke-WebRequest`**（BUG-116 车道的活证据 run6/run7：脚本取回来了、红在内部那一发）。
   两臂只换掉「取脚本」这一发的传输栈；链路整断时主臂与兜底臂一起红，只剩 `-LocalZip` 离线线。
   彻底修要动 `scripts/blackbox/install_onecmd.ps1` 的 zip/moon.mod 取数（换 curl 臂或加传输层重试），
   属产品码改动、判据 R12/R13 已能接住回归——**要不要在本轮做，请 owner 裁决**。
3. 并发车道仍在同一工作树写代码（`cmd/cli` help 子命令、`ops_loop` 重构、`scripts/*` demo 修复）：
   本轮的全量数字是"合并面"的数字，不代表单独任何一车道；分栏见 §3。
4. `check_scripts_index` 开工时报 `gen_help_docs.py` 未登记（并发车道的新脚本）——**本轮收口时已登记**，
   留此作过程记录（不登记就是 CI 文档面红）。
5. `cleanup_artifacts.py --check` 的存量脏（根目录 77 份 .db + temp 366 件）不是本轮引入，
   CI 里那一步是先清后查，本地保持不动。
6. **新增判据缺口（本轮未实现，只登记）**：没有一条常驻判据把「文档点名的开发模式名」打到 `src/ops/ops_modes.mbt::all_modes()` 上——`mode_templates` 只验模板文件存在性，`check_doc_surface` 的 J8 只比「模板调用参数 == 真源 schema」，J10 只管 J 系列的范围声明。BUG-121 就是从这个缝里长出来的（文案已修，缝还在）。建议下一轮把它做成 J11 或 R14 的一支：从注册表反解标识符集合，与 SKILL/AGENTS/USAGE 里点名模式的每一行做双向对表（多一个名 = 幻影，少一个名 = 声明滞后），照 J10 的形状配「空扫描必红」哨兵。
6. `memory/bugs.md` 的 18 条重复单与账本 `CLOSED` 词汇（建议书 D3/D4）仍是待裁决项，未动。
   本轮新增的 BUG-120 走的是 `report_bug`（拿号）→ `bug_fix`（同一笔落 `### FIXED(… / BUG-120)` 小记），
   未产生修复单（修复已在同一轮落地，`publish_task=false`）。

## 8. 来源

`temp/demo-audit-20260929.md`、`temp/head119_guard.log`、`temp/bug116_irm_recheck_20260929.log`、
`scripts/blackbox/e2e_heartbeat_xproc.py`、`docs/improvement-plan-20260929.md`、
`memory/bugs.md`（BUG-116/118/119 三条抬头）、owner 2026-09-29 终审目标原文。
