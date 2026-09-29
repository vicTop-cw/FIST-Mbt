# 2026-09-29 · 终审前收口报告（清 bug / 无回归 / demo 可用 / 探索模式）

> 基线：master `214fd8a` + 本工作树（含并发车道的 help 子命令、loop 重构、F094 规格与 `.mcp.json`）
> 指挥官：butler ｜ 依据：owner 2026-09-29 终审目标（见 §1）
> 本报告所有计数均从盘上反解，不手加；每条主张后面跟着它的复现命令或回执文件。

## 1. 结果摘要

Owner 本轮要求七件事，逐件的状态：

| # | 要求 | 状态 | 证据位置 |
|---|---|---|---|
| 1 | 将所有 bug 清掉（开工时 OPEN 3 条：BUG-116/118/119） | BUG-119 FIXED（实测）；BUG-118 权威 CI 门已落地、版本钉定案项如实留白；BUG-116 走"给用户一条能装上的线 + 常驻判据"的收口。此后按目标继续自查，同轮又入账 **BUG-120…BUG-129** 十条（文档资产名漂移 / 插件态模式名 / demo 裸跑污染 / 指引冒充权威 / 污染同型残留面 / 安装器内部单栈 / 索引里的活体计数 / mooncakes 载荷面 / 同号双份码 / 载荷对表无常驻判据），除 BUG-128 外**当场全部收口** ⇒ 台账 **128 条入账 = 114 已修 / 9 重复并入 / 4 误报**；**剩 1 条待修 = BUG-128**，它不是漏修而是发布方向的裁决位（§7.1 给了两条出路）。**（追记，发布轮之后）**BUG-128 已按出路①收口 ⇒ 台账现 **128 条入账 = 115 已修 / 9 重复并入 / 4 误报，0 条待修**，读数取自仓内现成计数器 `gen_plugins.py`；这一格从"裁决位"变成"已修"的全过程见 `2026-09-29-mooncakes-publish-report.md`。**
（顺带把旧式那条等式的账补齐：`114 + 9 + 4 = 127 ≠ 128`，少并的就是当时那 1 条待修 —— 现在 `115 + 9 + 4 = 128` 自洽） | `memory/bugs.md` 抬头 + `### FIXED` 小记；投影行同源（§6） |
| 2 | 确保无回归 | `moon test --target js -j 1` 全量通过（数字见 §3），守卫族逐条 rc=0；新增判据在 `git archive HEAD` 旧码树上发红（证明锁承重）。收口面复跑 `temp/final_js4.log` = **572/572 rc=0**（开工那份 `temp/final_js.log` 随 temp 回收，见 §9 证据寿命段） | `temp/final_js4.log`（现存）；`temp/final_js.log`、`temp/head119_guard.log`（当时存在，现已被回收，复现命令见 §9） |
| 3 | 符合本项目开发文档（`AI-DEVELOPMENT-STANDARD.md`） | 一源四态（cl7 重投影）、证据梯 L4（每条实测）、确定性优先（新增纯函数零 IO）、增量零回归（默认语义不变，只改被判死的那一支） | §6 checklist |
| 4 | 提供的 demo 完全可用 | 根因是 `cmd/cli/main.mbt` 把 serve 横幅打回 stdout（BUG-101 的修复被并发改动重新启用）⇒ 一条 `eprintln` 修好整族 stdio demo；收口时**按 README/USAGE 文档里的命令逐字重跑 11 条**（README DEMO 表 7 条 + 独立 CLI 表 2 条 + `demo.ps1`/`showcase.ps1`）全 rc=0，且全程根台账 1987/6909 一字不动（BUG-124 的隔离面） | `temp/demo_audit.log`（现存）、§4 表 |
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
  （开工那份 `temp/final_js.log`，rc=0；**收口面复跑 `temp/final_js4.log` 同数同 rc=0**——中间只动了 `scripts/*`、
  文档面与安装器，`find src cmd -name '*.mbt' -newer …` 为空，但按「绿不能跨面抵扣」的规矩仍重跑了一遍）。
  开工基线 535/535；+37 条 = 探索模式白盒 25→59（+34）
  与看护成对改写（`ops_test` 1→2、`ops_watchdog_test` A-3→A-3a/3b/3c，+3）。
  现状面的 535 已按 `check_test_sync` 逐面同步到 572：`AGENTS.md`、`README_EN.md`（含徽章）、
  `ARCHITECTURE.md`、`README.mbt.md`、`docs/{SHIP-PLAN-BLACKBOX-v2,agent-map,atgc-selfdrive-demo,deliverable,evolve}.md`、
  `scripts/scoring_rubric.md`；`README.md` 的徽章与正文由收口最后一步同步（并发车道正在改该文件）。
- 守卫族（逐条 rc，日志在 `temp/g_*.log`）：`check_tools_sync` 0 / `check_doc_surface` 0（含 `--selftest` 0）/
  `check_store_tables_wired` 0 / `check_entry_paths` 0 / `check_ps_encoding` 0 /
  `check_scripts_index` 1（`gen_help_docs.py` 未登记，见 §7.3）/ `check_plugin_sync` 1（待 `gen_plugins.py` 重投影，见 §6）。
  **收口面复跑（§6 表逐条 rc=0，含本轮新增的 `check_demo_isolation` 与 R14）**取代上面那份开工中段快照——
  那两条 1 是当时的盘面，如实保留不改写。
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
| `scripts/atgc_selfdrive_demo.py`（自驱+Omega 旗舰） | PASS | `tasks 13 (期望 1 根 + 12 子节点)`、`specs approved 12/12`、`MCP-ATG-SELFDRIVE PASS · SUCCESS`，且**根台账 1987 任务/6909 调用跑前跑后一致**（BUG-122 改道后裸跑不再 +1） | `python scripts/atgc_selfdrive_demo.py`（默认改道 `temp/atgc_selfdrive_demo.db`） |
| `scripts/blackbox/e2e_mirror_install.py` | PASS（版本夹具改为从 moon.mod 反解） | `目标版本 v0.3.4`、`用户 PATH 已还原（1708 字，逐字相同）`、`真产物 … 616b7632 → 616b7632`、`=== 端到端镜像安装：PASS ===` | `python scripts/blackbox/e2e_mirror_install.py` |
| `scripts/cli_flag_probe.py` | PASS | `--help/-h rc=0 首行=FIST-Mbt Help v0.3.4 (129 MCP tools)`、未知参数 rc=2 | `python scripts/cli_flag_probe.py` |
| `scripts/fist.py call project_standards` | PASS | 回 R116 规范 10 条 + cl1–cl7 checklist（机器投影与正文一致） | 同左 |
| `.mcp.json` 连接器 | 已改指 `node …cli.js serve`（原 `moon run cmd/cli` 缺 serve + 未打 shim 必崩）；根 `.mcp.json` **未入库**（`git ls-files` 空）⇒ 需 owner 决定要不要跟踪 | `args: ["_build/js/debug/build/cmd/cli/cli.js","serve"]` | `cat .mcp.json` |
| `scripts/showcase.ps1` / `scripts/demo.ps1` | PASS（本轮由我独立复跑，不再是"车道回传未复验"） | `fist-mbt drives itself ─ 自举采用，自动演进`（rc=0 / 1.5s）、`[DEMO] PASS — 环境就绪，30 秒可复现` + `🎉 七态闭环全绿 ✅`（rc=0 / 5.3s），两条前后根账 `[1987, 6909]` 一字不动 | `temp/demo_audit2.py`（内含 pwsh 调用与只读数账；见 §9 的码页口径） |
| **文档命令全量审计（收口面）** | **11 条全 rc=0** | README DEMO 表 7 条 + 独立 CLI 表 2 条 ⇒ `temp/demo_audit.log`（9 行，`FATAL_红条数=0`）；`scripts/README` 点名的两条 `.ps1` ⇒ `temp/demo_audit2.log`（2 行，`FATAL_红条数=0`）。审计**跑在裸环境**（不预设 `FIST_DB_PATH`），所以这 11 行同时是 BUG-124 默认改道的调用面证明 | `python temp/demo_audit2.py`；前 9 行的驱动器已随 temp 回收，命令逐条在 §4 各行「复现」列 |
| `fist-mbt-http.py` 与两个 cron 驱动器 | 车道回传已修（自述数从 moon.mod/注册表反解、退役入口改指 cmd/cli）；我**未**逐条复跑，如实标 未独立复验 | 无（旧证据 `temp/demo-audit-20260929.md` 已被 temp 回收，见 §9） | 见各行脚本头 docstring 的用法行 |
| `blackbox/e2e_irm_line.py` 公网线 | 本机不稳（BUG-116 本体）：我这轮 rc=1 全针未命中；车道在另一时刻取到真装通 v0.3.4 ⇒ 判据已升级为**两臂**（主臂 + curl 兜底臂），兜底臂红一律拦退出码 | `temp/bug116_irm_recheck_20260929.log` | `python scripts/blackbox/e2e_irm_line.py` |

## 5. 文档面

- 定位语与 fist-evidence 指针的落点：README.md 首屏、README_EN.md 首屏与 `## Evidence` 段、
  USAGE.md §1/§2、docs/atgc-selfdrive-demo.md 头部、AGENTS.md 原有「实证伴生仓」段保留未动。
  口径经 sibling checkout 实测核对：三组实验 + 十份驱动实例（覆盖八项目），
  `stories/…` 只存在于那个仓库，所以每条指针都写明"在伴生仓"。
- 纠正的陈旧计数：README「122 个工具」→ 129；README_EN 三个并存的测试数（310/442/535）统一到
  一个带日期与目标的口径；docs/atgc-selfdrive-demo.md 的 `node main.js` → `node …/cli.js serve`。
- 本轮最终测试数 **572/572**（`moon test --target js -j 1`，收口面复跑 `temp/final_js4.log` 尾行 `Total tests: 572, passed: 572, failed: 0.` + `MOON-TEST-RC=0`；开工那份 `temp/final_js.log`/`temp/final_js3.log` 已随 temp 回收，见 §9）
  在文档面的同步位置：`check_test_sync.py` 扫现状面 **107 份文档**、**24 条声明全部 == 实测**（must-carry 5 份齐全、豁免 8 条有效），
  `check_badge.py` 对 README『→ Total tests: 572, passed: 572』逐字相等。改动落点为 ARCHITECTURE.md、README.mbt.md、
  README_EN.md、AGENTS.md、scripts/scoring_rubric.md 与 `docs/{SHIP-PLAN-BLACKBOX-v2,agent-map,atgc-selfdrive-demo,deliverable,evolve}.md`。
- BUG-126 顺手清掉一处同类陈旧：`scripts/README` 的 `showcase.ps1` 条目原本把**读盘实时计数**当事实写死（548 tasks / 196 exec，
  实测真值 1987 / 461），现改为"脚本现数、索引不写死数字"，并把取证侧的码页坑写进同一行（见 §9）。

## 6. 开发文档合规 checklist（cl1–cl7 + r/f 条）

- cl1 MCP 工具存在性 / cl2 文档逐个可查 / cl3 分组和==实测 / cl4 自述版本==moon.mod /
  cl5 交付物 / cl6 文档同步 / cl7 插件态一致 —— **收口时逐条重跑，rc 全 0**（退出码取自命令替换，不是管道尾）：

  | 守卫 | rc | 回执行（逐字） |
  |---|---|---|
  | `check_tools_sync` | 0 | `PASS 工具单一真源一致：server.mbt 注册 129 个，AGENTS/README/deliverable/scoring_rubric 对齐` |
  | `check_test_sync temp/final_js4.log` | 0 | `PASS 测试总数单一真源一致：实测 572；扫描现状面 107 份文档，24 条声明全部等于实测；must-carry 5 份齐全；豁免 8 条全部有效` |
  | `check_badge temp/final_js4.log README.md` | 0 | `PASS 自检注释一致：README 『→ Total tests: 572, passed: 572』 == 实测 572` |
  | `check_scripts_index` | 0 | `PASS 工具类辅助代码单一索引完整：所有正式脚本均已在 scripts/README.md 登记` |
  | `check_plugin_sync`（cl7） | 0 | `PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.4` |
  | `check_doc_surface`（J1–J10） | 0 | `PASS 文档面一致：129 工具在 AGENTS/README 逐个可查、分组和=129、当前自述版本=0.3.4、J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、J9 返回契约（必查清单 + 歧义键分工 + 棘轮）未退化、J10 判据范围自述==实现` |
  | `check_store_tables_wired` | 0 | `PASS store schema 接线一致：12 张表 = 11 张有写入点 + 1 张显式预留（runs）` |
  | `check_ps_encoding` | 0 | `PASS PowerShell 编码守卫：6 个 .ps1 全部带 BOM 或纯 ASCII（Windows PowerShell 5.1 按 ANSI 读也不会吞引号）` |
  | `check_entry_paths` | 0 | `PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个（扫描面 129 份文件，历史面与守卫自身除外）` |
  | `check_release_asset_names --selftest` | 0 | `SELFTEST OK（干净不误红 + 变异必红；清单从已执行格子反解：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 / R7×3 / R8×3 / R9×2 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5）`（**R13 钉 BUG-120、R14 钉 BUG-125**） |
  | `check_release_asset_names`（全量） | 0 | `PASS 分发面同源（判据范围从正文反解：R1/R2/R3/R4/R5/R6/R7/R8/R9/R10/R11/R12/R13/R14）：资产名三处一致 + 版本真源 moon.mod + 空值即失败 + 命令名两类 shell 都可见 + 200/HTML/魔数检查 + 安装自检不假绿 + 发布作业不顶掉分发 + 工具链 bootstrap 与 CI 同源 + 文档线 BOM 安全 + 源码版本常量与 moon.mod 同源` |
  | `check_demo_isolation --selftest`（本轮新增守卫，钉 BUG-124） | 0 | `SELFTEST OK（干净不误红 + 变异必红 + 空扫描自拒；格子从已执行对照反解：G1 干净不误红 / M1 摘改道针必红 / M1b 加注释不误红 / M2 豁免面漂移必红 / M3 空扫描必自拒；spawn 面 29 个脚本，显式子句 2 项 / 豁免 1 项）` |
  | `check_demo_isolation`（全量） | 0 | `PASS spawn 面隔离一致：29 个脚本 spawn \`serve\` 时都把 FIST_DB_PATH 交给了子进程（显式子句 2 项 + 豁免 1 项锚点均成立）` |
  | `blackbox/e2e_transport_stack_fallback.py`（本轮新增承重件，钉 BUG-125） | 0 | `=== 端到端传输层换栈判据：PASS（A 换栈装通 / B 无 curl 必红 / C 正向不误伤）===`，附 `用户 PATH 已还原（1708 字，逐字相同）` 与 `真产物 … sha256:616b7632 → 616b7632` |
  | `mcp_tool_tour --surface-selftest` | 0 | `SURFACE-SELFTEST: OK —— 12 支（10 违例 + 1 干净 + 1 自拒），不符 0 支` |
  | `store_isolation_probe` | 0 | `PROBE: GREEN —— 2 格中红 0 格` |
  | `check_publish_payload --selftest`（本轮新增第 13 个守卫，钉 BUG-127/129） | 0 | `SELFTEST OK（已执行格子：G1' 现状带未跟踪件时：逐件点名且无幻影红 / M1 未跟踪未忽略的文件必红 / M2 被 .gitignore 挡住则不红 / M3 红面里的凭据形状必点名 P2；打包面 552 件 / 其中未跟踪未忽略 1 件 / 被 moon 排除的点号件 18 件）` |
  | `check_publish_payload`（全量，add 之后） | 0 | `PASS 发布载荷面干净：将随包公开 552 件，其中未被 git 跟踪的 0 件（另有 18 件点号条目 moon 本来就不打包）` |
  | `cli_flag_probe`（真产物三档） | 0 | `PASS 调用面三档全对（版本旗=0.3.4 · 未知必非 0 · 帮助旗不落未知臂）` |
  | `blackbox/e2e_heartbeat_xproc`（本轮新增常驻臂） | 0 | `=== E2E-HEARTBEAT-XPROC PASS：8 格全绿（跨进程看护语义已锁） ===` |
  | `moon fmt --check` | 0 | `Finished. moon: no work to do` |
  | `gen_plugins.py` + `check_plugin_sync.py`（BUG-121 修文字后复投；收口面每批账变动后各复投一次） | 0 | `PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.4`；最终投影行 = `BUG-1~129 共 128 条入账：1 条待修 / 114 已修 / 9 条重复并入 / 4 条误报`（中途两行 `BUG-1~121 共 120 条…` / `BUG-1~126 共 125 条…0 条待修` 如实留作过程，那 1 条待修是发布后新入的 BUG-128。**"最终"只是终审收口那一刻**——发布轮把 BUG-128 收掉后重投影为 `BUG-1~129 共 128 条入账：0 条待修 / 115 已修 / 9 条重复并入 / 4 条误报`） |
  | `output_validate`（cl5 交付物硬门，跑在真产物上） | 0 | `verdict=pass passed=14 failed=0`，`evidence_layer=l4-pass` |
  | `mcp_smoke`（改道后裸跑） | 0 | `MCP-SMOKE PASS`；根台账 tasks/call_log 前后逐字 1987/6909（BUG-122 的复验） |

  对应 cl 映射：cl1/cl2/cl3 = `check_tools_sync` + `check_doc_surface`；cl4 = `check_doc_surface` J3 + `cli_flag_probe`；
  cl5 = `output_validate` 14 件；cl6 = `check_test_sync` + `check_badge` + `check_scripts_index`；cl7 = `check_plugin_sync`。
- 一源四态：`plugins/{atomcode,codearts,deepseek-harness,claude}` 由 `gen_plugins.py` 重投影，
  `check_plugin_sync.py` 逐字节比对通过；`.mcp.json` 与 `plugins/claude/.mcp.json` 同源。
- 证据梯：每条"已修"都带调用面实测（两个真进程 / 真产物 / 真安装线），未测的写成未测。

## 7. 遗留风险与需要 owner 决定的事

> **原列在本节、本轮已闭合的两项**（留标题不留风险，防读者按旧清单去追已不存在的东西）：
> ① 安装器内部两发取数只有 .NET 单栈 ⇒ **BUG-125 已修**（curl 兜底臂 + R14 + 三格承重件，见 §6）；
> ② 根台账污染的同型残留面 ⇒ **BUG-124 已修**（21 个脚本默认改道 + `check_demo_isolation` 常驻，见 §6）。
> 那句"本轮不扩大改动面，留给下一轮"是我上一版写的，改动面已经扩大了，所以这句作废——不删条目、改口径。

1. **两项需要 owner 拍的动作**：
   - **推送**：BUG-116 的公网线、BUG-118 的"两条轨工具链版本是否同形"、以及 BUG-124/125 收口后的 CI 红点清零，
     关闭证据都只能在**推送后的 CI 运行**里产生（本机对 `cli.moonbitlang.com` 取安装脚本 TLS 失败 rc=35，
     `Invoke-RestMethod` 走系统代理时对 `raw.githubusercontent.com` 传输层被对端关闭）。
     本轮所有提交都只在本地，**没有 push**；`master` 领先 `origin/master` 的格数见 §7b。
   - **BUG-128 的出路（台账里那 1 条待修就是这个裁决位）**：注册表的 `0.3.4` 载荷取自 `a0dfef3`，
     而本地 tag `v0.3.4` 停在 `af54d5e`（差 11 个提交、`src`+`cmd` 侧 +1643/−269）⇒
     `install_onecmd.ps1 -Version 0.3.4` 与 `moon add vicTop-cw/fist-mbt@0.3.4` 现在给的是**两份不同码、同一个号**。
     ①**推荐**：`moon.mod` 前进到 0.3.5 → 重发注册表 → 打 `v0.3.5`（代价=一轮版本自述同步：moon.mod/USAGE/插件态/R11 源码常量，
     判据 R1–R14 与 `cli_flag_probe` 会逐面接住）；②把 GitHub Release 的 `v0.3.4` 资产重做到当前树
     （代价=动**已发布的 tag**，需明确授权，且本机 push tag 会触发 `release.yml`）。
     我没有自行 bump、也没有重发——注册表版本不可撤销，这一格不该由代理替 owner 决定。
     **（追记，同日晚些）** owner 选了出路①：已发 `0.3.5`（注册表 `Latest: 0.3.5` / 共 10 版）、三真源同步到 `0.3.5`、
     本地 `v0.3.5`+`mooncakes-0.3.5` 钉 `124a20a`、BUG-128 已标 FIXED（盖章 2026-09-29T10:44:53Z）⇒
     **上面那半句"没有 bump"从此刻起是历史陈述，不是当前状态**。发布链的逐格实测与新留的两格（未 push、0.3.4 是否 deprecate）
     见 `2026-09-29-mooncakes-publish-report.md`；本报告其余事实仍钉 `a0dfef3`，不回改。
2. 并发车道仍在同一工作树写代码（`cmd/cli` help 子命令、`ops_loop` 重构、`scripts/*` demo 修复）：
   本轮的全量数字是"合并面"的数字，不代表单独任何一车道；分栏见 §3。
3. `check_scripts_index` 开工时报 `gen_help_docs.py` 未登记（并发车道的新脚本）——**本轮收口时已登记**，
   留此作过程记录（不登记就是 CI 文档面红）。
4. `cleanup_artifacts.py --check` 的存量脏（根目录 77 份 .db + temp 366 件）不是本轮引入，
   CI 里那一步是先清后查，本地保持不动。
5. **判据缺口 A（本轮未实现，只登记）**：没有一条常驻判据把「文档点名的开发模式名」打到
   `src/ops/ops_modes.mbt::all_modes()` 上——`mode_templates` 只验模板文件存在性，
   `check_doc_surface` 的 J8 只比「模板调用参数 == 真源 schema」，J10 只管 J 系列的范围声明。
   BUG-121 就是从这个缝里长出来的（文案已修，缝还在）。建议下一轮做成 J11 或 R 系列的一支：
   从注册表反解标识符集合，与 SKILL/AGENTS/USAGE 里点名模式的每一行双向对表
   （多一个名 = 幻影，少一个名 = 声明滞后），照 J10 的形状配「空扫描必红」哨兵。
6. **判据缺口 B（本轮新登记，与缺口 A 同一批修）**：`scripts/README` 这类索引条目把**读盘实时计数**
   当事实写死（BUG-126：548 tasks/196 exec vs 实测 1987/461）。现有守卫各管一维——
   R13 管资产名版本字面量、J 系列管工具数/版本/模板参数、`check_test_sync` 管测试总数——
   **没有一条**管"文档里的任意活体计数字面量 ↔ 盘上真值"。建议下一轮要么把这条纳入 `check_doc_surface`
   的一个新 J（对"读盘实时"类字段禁写数字字面量，或写则必须带反解来源），要么立一条字面量黑名单口径。
7. `memory/bugs.md` 的 18 条重复单与账本 `CLOSED` 词汇（建议书 D3/D4）仍是待裁决项，未动。
   本轮新增的 BUG-120…126 走的都是 `report_bug`（拿号）→ `bug_fix`（同一笔落 `### FIXED(… / BUG-n)` 小记），
   未产生修复单（修复已在同一轮落地，`publish_task=false`）。

## 7b. 提交面身份（终审对表用）

本地提交串（**未 push**；领先格数**不写死**——本段之后的每一笔补记都会让它 +1，读现值请跑
`git rev-list --count origin/master..HEAD`；发布轮收口那一刻实测为 10）：

```
9653604 feat(发布面),fix(载荷面),fix(账本): mooncakes 0.3.4 发布后的三格收口——BUG-127/129 已修、BUG-128 挂裁决
a0dfef3 docs(report),docs(memory): 第二批收口面自证——§6 表刷新、§7 两项闭合、§9 证据寿命、§10 改动清单
cd8702f fix(污染面),fix(分发面),feat(守卫面): BUG-124/125/126——残留同型面一次收干净
41eefd8 fix(demo面),docs(指引面): BUG-122/123——裸跑不再污染根台账，gen_help_docs 不再冒充 CLI 文案权威
9f3927d fix(插件态),docs(守卫面): BUG-121——SKILL 广告的模式名有两个服务端根本不认
```

（`cdd72fd`/`a8dfe60` 在其下，串起 `214fd8a` 基线。）

- `cdd72fd` = 看护修复 + 探索模式 + R13 + 文档面收口；**第一轮 572/572 与守卫族 17 步 rc=0 的测量树就是这个面**。
- `9f3927d` = BUG-121：四宿主 SKILL 的模式名对齐注册表（`hunt` / `fix-and-merge` / `night-loop` 不是标识符）。
- `41eefd8` = BUG-122/123：demo 裸跑默认改道隔离库 + `gen_help_docs.py` 的权威声明改为「不许照它落笔」。
- `a8dfe60` = 纯 `docs(report)`，不动任何被测量面；tag 曾钉在它上面。
- **`cd8702f` = 第二批（本轮收口面）**：21 个脚本默认改道 + `check_demo_isolation`（守卫族 12 个）+ 安装器内部换栈 +
  R14 + BUG-124/125/126 三条入账 + `§5/§6/§9/§10` 与 CHANGELOG/AGENTS/scripts-README 同步。
  **§6 表里那批 rc=0 与 `temp/final_js4.log` 的 572/572 是在 `cd8702f` 的工作树（含随后仅动本文档的提交）上测的**；
  这一提交不含任何 `src/**.mbt` 改动（`git show --stat cd8702f` 可见），所以码面与 `cdd72fd` 那次全量数字同源。
- 本地 tag `fist-final-review-20260929` 钉在 **`a0dfef3`**（= 注册表 0.3.4 载荷所用的树，见下条），**不随本文档的
  后续提交前移**——不然"终审面"会变成"比发布面新一格"的两个身份。不用 `v*` 前缀，避免将来 push tag 时
  误触发 `release.yml` 的 tag 条件。
- 发布轮另立 `mooncakes-0.3.4` → `a0dfef3`（机器可读的"注册表那份 0.3.4 是哪棵树"），
  与既有 `v0.3.4` → `af54d5e`（GitHub Release 资产所用树）**并列可见**——BUG-128 说的"同号两份码"从此不靠回忆，
  `git tag -l --format='%(refname:short) -> %(*objectname:short)' mooncakes-0.3.4 v0.3.4` 一行就能对出来。
- **（追记，0.3.5 那一发之后）**同一套身份记法续了两枚：`v0.3.5` 与 `mooncakes-0.3.5` **同钉 `124a20a`**——
  这次"两个身份"是同一棵树，因为注册表载荷是**逐件比过字节**才打上去的（552 件、双向差集 0/0、CRLF 归一后 0 处不一致，
  见 `2026-09-29-mooncakes-publish-report.md` §3.3）。`mooncakes-0.3.4 → a0dfef3` 与 `v0.3.4 → af54d5e` 那对
  **不同树的旧事实仍留在盘上可查**，BUG-128 的账没有因为发新版而被抹掉，只是被 0.3.5 这一格封了口子（旧版撤不回）。
- 判据取号一律**钉 tag 而非 `HEAD`**，否则本段之后的补记会自比恒真。

有意**不入库**的两个文件：`.mcp.json`（254de24 起改为不跟踪，跟踪面是 `.mcp.dev.json`，两者与
`plugins/claude/.mcp.json` 语义等价，实测三处 JSON 内容相同）与 `__cli_pkg.mbt.tmp`（moon 构建残留，
不是我造的就不删，只是不进提交）。

## 8. 来源

**仍存在的证据（可直接复看）**：`temp/final_js4.log`（572/572 + `MOON-TEST-RC=0`）、**`temp/publish_gate_js.log`（发布前置那次独立复跑，同数同 rc）**、
`temp/publish_034.log`（`Server status: 200 OK` + `PUBLISH-RC=0`）、`temp/pkg_install_probe/`（从注册表真取的消费者工程，`.mooncakes/vicTop-cw/fist-mbt` 即公开载荷 552 件）、
`temp/payload_files.txt` / `temp/tracked_files.txt`（两向 `comm` 对表的原料）、`temp/demo_audit.log`（9 行文档命令 + `FATAL_红条数=0`）、`temp/demo_audit2.py`/`temp/demo_audit2.log`（两条 `.ps1`）、
`temp/r14_e2e_verify.log` 与 `temp/r14_e2e_verify2.log`（换栈三格，后者是收紧 B 负门后的复跑）、
`temp/bug124_125_receipt.json`、`temp/bug126_receipt.json`、`temp/bug127_128_receipt.json`、`temp/bug129_receipt.json`（`report_bug`/`bug_fix` 回执原文）、
`temp/payload_guard_selftest.log`、`temp/payload_guard_plain.log`（+ `.prev`：带未跟踪件那次与干净那次各留一份）、`temp/publish_cl7.log`、
`scripts/blackbox/e2e_heartbeat_xproc.py`、`scripts/blackbox/e2e_transport_stack_fallback.py`、`scripts/check_demo_isolation.py`、
`docs/improvement-plan-20260929.md`、`memory/bugs.md`（BUG-116…128 抬头与小记）、owner 2026-09-29 终审目标原文。

## 9. 证据文件寿命与取证口径（终审复核前必读）

**已被回收的证据（如实标注，不装作还在）**：`temp/final_js.log`、`temp/final_js3.log`、
`temp/head119_guard.log`、`temp/demo-audit-20260929.md`、`temp/bug116_irm_recheck_20260929.log`——
`temp/` 在 `.gitignore` 内且被清理过（`cleanup_artifacts` 那一步也会动它），所以这些文件写报告时在、现在不在。
本报告保留它们当时的读数（都是当时逐字贴的回执行），并给出**再生命令**：

| 旧证据 | 现成替代 / 再生命令 |
|---|---|
| `final_js.log` / `final_js3.log` | `moon test --target js > temp/final_js4.log 2>&1`（本轮已复跑，同数同 rc） |
| `head119_guard.log`（旧码树承重证明） | `git archive HEAD \| tar -x -C temp/headtree && python temp/headtree/scripts/blackbox/e2e_heartbeat_xproc.py`（旧码树上的红是这一格；本轮未复跑，故 §3 的承重结论以 `r14_e2e_verify2.log` 这类现存件为准） |
| `demo-audit-20260929.md` | `python temp/demo_audit2.py`（python 侧 9 条的驱动器一并被回收，命令逐条在本报告 §4 的「复现」列，照抄即可） |
| `bug116_irm_recheck_20260929.log` | `python scripts/blackbox/e2e_irm_line.py`（公网线，本机 TLS 抖动即 rc=3/1，属 BUG-116 未推送期间的已知态） |

**取证侧两条口径（本轮踩过、已写进常驻文档）**：
① pwsh 的重定向默认落控制台码页，中文回执在**子进程内**就被写成 `?`——外层按 UTF-8/GBK 猜解都救不回来，
必须调用前置 `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8`（口径已写进 `scripts/README` 的 showcase 行）；
② 负门格（"这一格必须红"）的期望要写成**一个真非零整数**，`rc is None`（没起跑/超时）也算判据坏——
`e2e_transport_stack_fallback.py` 的 B 格已按这条收紧，复跑见 `temp/r14_e2e_verify2.log`。

## 10. 本轮（第二批）改了哪些面

| 面 | 改动 | 落点 |
|---|---|---|
| 污染面 | 21 个 `spawn serve` 脚本加默认改道（未显式设 `FIST_DB_PATH` 时落 `temp/<脚本名>.db`） | `scripts/{atgc_selfdrive_demo,dag_depend_verify,dispatch_verify,enhance_verify,evolve_critic_verify,executor_route_verify,fist,issue_scan,lesson_chain_selfdrive,lesson_selfdrive,lesson_verify,log_fix_selfdrive,map_verify,mcp_bug_loop,output_validate,pentad_fist,plan_gradient_verify,scratch_selfdrive,scratch_verify,task_challenge_verify,test_mcp_bugs}.py` |
| 新守卫 | `scripts/check_demo_isolation.py`（I1/I2/I3 + 五支 selftest）与 `scripts/check_publish_payload.py`（P1/P2/P3 + 四支 selftest）挂 ci.yml JS 轨 | 守卫族 11→13，AGENTS 与 scripts/README 同步 |
| 分发面 | `install_onecmd.ps1` 内部两发取数接 curl 兜底臂（只在无 HTTP 响应时换栈） | 判据 R14 + 三格承重件 |
| 账本 | BUG-124/125/126/127 四条 `report_bug`→`bug_fix` + BUG-128 只入账（隔离库跑真 RPC，`publish_task=false`） | `memory/bugs.md`，投影行 127 条 / 1 待修（=BUG-128 裁决位） |
| 发布面 | `moon publish` 把 `vicTop-cw/fist-mbt@0.3.4` 发上 mooncakes（202 预检 → 200 OK → `moon view` 回读 Latest=0.3.4 / 9 版 / Downloads 31）；发布前置 = 全量 JS 轨 + 守卫族逐条 rc=0 | `temp/publish_034.log`、`temp/publish_gate_js.log` |
| 载荷门禁面 | 发布后**解包对表**量出「打包面 = 工作树 − .gitignore」：1 件本地残留进了公开包、18 件点号文件没进包 ⇒ `.gitignore` 追加 `*.mbt.tmp`、USAGE §10 补第三步与载荷边界、BACKLOG P1 改为实测注册表态 | `.gitignore:48`、`USAGE.md` §10、`temp/payload_files.txt` |
| 文档面 | README 诚实边界段、CHANGELOG 三条 + 口径更正段、scripts/README 两个新件登记 + showcase 行去死数字、SHIP-PLAN 现状指针 | §5 / §7 |
