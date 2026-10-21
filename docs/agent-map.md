# FIST-Mbt Agent 项目地图（Repo Map）

> 目的：让任何一个首次进入本仓库的 AI agent **先读地图、再动代码**，不必全项目盲目探索。
> 依据：Agent Patterns Catalog「Repo Map」模式——给 agent 一张紧凑、按重要性排序的结构地图，省 context、少走弯路。

## 一、30 秒定位（对首次进入者）

`FIST-Mbt` 是**纯 MoonBit 实现的 MCP Server**：一个「AI 指挥官」式任务编排器——发布根任务，递归拆解成多层子任务，经认领/执行/提交/验收/归档闭环；含 DGM 自进化档案库（evolve）与 Omega 强验证。全栈 MoonBit，JS+Native 双后端，SQLite 持久化。

- **构建/测试**：`moon check` / `moon test --target js`（**1347 项全绿**，2026-10-19 Windows 实测）
- **跑 MCP Server**：`moon build --target js cmd/cli && python scripts/patch_esm_main.py` → `node _build/js/debug/build/cmd/cli/cli.js`
- **一键自检**：`python scripts/mcp_smoke.py`（实测 170 个工具 + publish/get 链路 + issue_scan 命中校验；这个数由 `check_doc_surface.py` 的 J14 项目地图面钉住，改工具数时这张图必须跟着改）
- **找目标项目潜问题**：`issue_scan`（MCP 工具）/ `python scripts/issue_scan.py <dir>`（CLI）/ [技能文档](issue-scan-skill.md)（skill）三处手写形态 + 插件态投影（四态），规则驱动扫描，命中喂 `report_bug` 闭环
- **语言**：MoonBit；测试用 `suite`/`test` 而非 `@test def`；guard/match 冒号后换行。

## 二、src/ 各子包职责地图（谁管什么）

| 包 | 职责 | 关键文件 |
|---|---|---|
| `core` | 领域模型：`Task`/`TaskStatus`、七条金条、schema 解析 | `core_task.mbt` |
| `store` | 持久化：Memory/SQLite 双后端、call_log/heartbeats/specs/evolve_artifacts 表 | `store.mbt` `store_sqlite.mbt` |
| `engine` | 业务核心：publish/claim/plan(deep)/execute/submit/verify/archive；DAG；Omega 门禁；docs 门禁 | `engine.mbt` `omega_strong.mbt` `docs_gate.mbt` |
| `evolve` | DGM 自进化档案库：Archive/Artifact/sample_parent/查重/新颖度/谱线 | `evolve.mbt` `scoring.mbt` `self_search.mbt` |
| `omega` | Ω-check：项目结构/回传五段式校验、spec 解析/批量校验 | `check.mbt` |
| `ops` | 运维：心跳/看门狗/google 调度 | `ops_watchdog.mbt` 等 |
| `server` | MCP 层：170 个工具+3 resources+2 prompts 注册、call_log 注入、Laya/evolve MCP 封装、规则驱动源码扫描（issue_scan） | `server.mbt` `laya_js.mbt` `evolve_distill.mbt` `evolve_lesson.mbt` `issue_scan.mbt` |
| `decompose` | 递归拆解规格 | — |
| `executor` | 执行器抽象 + 能力注册表 + 能力路由（Marketplace 雏形，R30/R31）+ store 持久化 | `registry.mbt` `base.mbt` |
| `atgc-old` | 旧 ATGC 叙事子项目（保留全量） | — |
| `atgc` | 极简双链虚拟机（能力演示） | — |

## 三、MCP 工具分组概览（导航简写，不是注册表计数）

> **边界（BUG-123 / BUG-363）**：本表组名与组值是手写的导航简写（省略公共前缀，如`succeed status`），**不等于** `tools/list` 的注册表，也不能与真源做机械差集。逐组的权威清单在 README「功能全景」，由 `check_doc_surface.py` 的 J3 同时钉「分组数字之和 == 真源」与「标题组数 == 实际分组标题数」；这张地图自己只钉**总数主张**那一句（J14 项目地图面）。本表尚未覆盖的分组（GitHub/GitCode 同步、超级管家、六顶帽、项目助理、嵌入式 MCPCf、模型路由·外部执行器、开发模式等）记在 BUG-364，改写本表属内容决策，留裁决。

| 组 | 工具 |
|---|---|
| 生命周期(14) | publish/publish_parallel/plan/claim/execute/submit/verify/reject/retry/pause/resume/reopen_task/archive/delete |
| 查询(2) | list/get |
| 运维(13) | task_plan_deep/conflicts_check/heartbeat/heal/watchdog_tick/task_cleanup/phi_accrual/saga_register/saga_rollback/saga_repair/circuit_fail/circuit_succeed/circuit_status |
| 运维·日志/缺陷/成本/调度(12) | call_log/bug_list/report_bug/run_check/issue_scan/schedule/pipeline_tick/cost_stats/cost_budget_check/cost_budget_split/progress_gate/laya_decide |
| 自驱闭环(9) | selfdrive_init/append/get/export_tasks/review_tick/review_ready/publish_next/parse_next_tasks/pick_next（+ selfdrive_dispatch 见 Marketplace） |
| 看板/脉冲/预订/推荐+DAG(20) | dag_critical_path/parallelism/ascii/check/ready/sort/depend/publish/slack/schedule/cost_route/mc/plan_revise/goal_drift_check、board_ascii、status_summary、project_health/health_check、reserve_scope/check/release、task_triage |
| 自我记忆与自进化(11) | memory_consolidate/gc/link、evolve_submit/sample/snapshot/distill/lesson/critic/asset_register、task_challenge |
| Marketplace·能力路由(5) | executor_register、executor_auction、executor_route、executor_clear、selfdrive_dispatch（能力登记/置信度拍卖/专长+信任+负载路由/重置/自动派单，R30-R33/R87 跨进程持久化） |
| 审计/权限(2) | audit_permission/log |
| 多租户(3) | store_open/list/close |
| 强验证(6) | omega_spec_create/review/result_verify/status/verify/verify_fix |
| 衍生·ATGC-old(3) | atgc_old_compile/run/talk |
| 其它(辅助) | evolve_self_search、cmd/cli 示例、HTTP/SSE 桥接（fist-mbt-http.py）… |

## 四、入口引导（agent 该怎么走）

1. **想懂业务流** → 读 `README.md`、`ARCHITECTURE.md`、`USAGE.md`。
2. **想改某层逻辑** → 见上表定位到 `src/<包>`，再读该包 `pkg.generated.mbti` 看公开接口。
3. **想加/改 MCP 工具** → `src/server/server.mbt` 用 `.tool(name, desc, schema, handler)`，handler 经 `_instrument` 包装（自动 call_log）。
4. **想动存储** → `src/store/store_sqlite.mbt`（表结构在 `moon.pkg` 初始化处）。
5. **想跑通即走** → `python scripts/mcp_smoke.py` / `scripts/enrich_selfdrive.py`。
6. **提交前想确认守卫面** → `python scripts/run_guards.py`（仓内电池真源，35 格：逐格打 rc/期望/结论，
   预存红按声明的期望值命中、不算失败但也写在汇总里）。**别在 `temp/` 里另写一份电池**：
   历轮 11 份手写电池的格数是 13 → 30 → 37 全靠回忆，漏的那格永远不会被发现漏了（BUG-366）。

## 五、约定与雷区（别踩）

- **测试**：JS 目标已支持；native 需系统 SQLite + VS 环境（见 AGENTS.md）。
- **Node ≥ 24**：JS 目标依赖 `node:sqlite` 的 returnArrays，<24 会导致列读空。
- **时间戳用 Int64**：`@env.now().to_int()` 对 UInt64 做 32 位截断会产生 1969 假时间戳——务必用 `@env.now().reinterpret_as_int64()`（`UInt64::to_int64` 自 BUG-359 起已由 core 弃用，仓内 11 处调用全部改名；写 `.to_int64()` 会给 `moon check` 新增一条 0020 warning）。注意 `to_int64` 是重载名：`Double::to_int64()` / `Int::to_int64()` 是**饱和转换**、未弃用，不要跟着改。
- **勿改共享 fist-mbt.db 测试**：测试用独立内存/SQLite（见 call_log_wbtest）。
- **无硬编码路径**：分隔符跟随输入，路径不硬编码盘符。
- **一把尺不跑就等于一把坏尺**：本仓的守卫只在 CI 有红门，本地提交面是空的（`.githooks/pre-commit` 只跑 `moon check`，而且 `core.hooksPath` 未设置 ⇒ 连这一条都不生效）。新写或改 `scripts/check_*.py` 时，**同时给它一个执行面**（挂 CI 或进 `run_guards.py` 的 `CASES`），否则它会像 `check_plan_landing` 那样带着虚报缺陷躺一周（BUG-365/366）。
- **自述的退出码必须实测**：`raise SystemExit("FATAL …")` 给的是 **1**，不是 2 —— 带字符串的 SystemExit 只打印文本。ast 普查真调用点：3 份尺自述「2=判据无法自证」而代码里一条 2 都给不出（`check_mbti_sync` 7 处串式 FATAL / `check_pkg_imports` 6 处 / `check_template_ctrl` 1 处），另 1 份是**半形**（`simulate_head_commit`：moon 超时走 `return 2` 真给 2，其余 4 处 FATAL 给 1，其中一条文案自己写着「（rc=2）」）⇒ BUG-369。要承诺 rc=2 就写 `SystemExit(2)` 或 `return 2`，并在 `--selftest` 留一格锁「FATAL 那条出口的码真是 2」。
- **数站点要用 ast，不要用正则**：同一份普查，正则版把 docstring 里的 `SystemExit("…")` 字样当调用点（数字虚高到 33），又把 `sys.exit(main())` 这种**正常透传**当「已有整式出口」（家族漏判）——两条缺陷都在同一轮现形。凡是「数代码里的某种形状」的判据，先问一句：读的是站点面还是文本面？
- **模式互斥不是洁癖**：同一把尺的两种模式若共享一个「按某面标定的上限」，允许它们同时打开就是在未标定的宇宙上比数。实测 `check_plan_landing.py --gate --all-faces` 去掉互斥闸后：同一份存量从 25 跳到 38，门禁反而给 **0** —— 红是假的、绿也是假的，而「绿得莫名」比红更坏。