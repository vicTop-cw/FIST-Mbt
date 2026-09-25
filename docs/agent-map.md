# FIST-Mbt Agent 项目地图（Repo Map）

> 目的：让任何一个首次进入本仓库的 AI agent **先读地图、再动代码**，不必全项目盲目探索。
> 依据：Agent Patterns Catalog「Repo Map」模式——给 agent 一张紧凑、按重要性排序的结构地图，省 context、少走弯路。

## 一、30 秒定位（对首次进入者）

`FIST-Mbt` 是**纯 MoonBit 实现的 MCP Server**：一个「AI 指挥官」式任务编排器——发布根任务，递归拆解成多层子任务，经认领/执行/提交/验收/归档闭环；含 DGM 自进化档案库（evolve）与 Omega 强验证。全栈 MoonBit，JS+Native 双后端，SQLite 持久化。

- **构建/测试**：`moon check` / `moon test --target js`（223 项全绿）
- **跑 MCP Server**：`moon build --target js cmd/main && python scripts/patch_esm_main.py` → `node _build/js/debug/build/cmd/main/main.js`
- **一键自检**：`python scripts/mcp_smoke.py`（工具数 79 + publish/get 链路）
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
| `server` | MCP 层：79 个工具+3 resources+2 prompts 注册、call_log 注入、Laya/evolve MCP 封装 | `server.mbt` `laya_js.mbt` `evolve_distill.mbt` `evolve_lesson.mbt` |
| `decompose` | 递归拆解规格 | — |
| `executor` | 执行器 | — |
| `atgc-old` | 旧 ATGC 叙事子项目（保留全量） | — |
| `atgc` | 极简双链虚拟机（能力演示） | — |

## 三、MCP 工具分组概览（79 个）

| 组 | 工具 |
|---|---|
| 生命周期(12) | publish/plan/claim/execute/submit/verify/reject/retry/pause/resume/archive/delete |
| 查询(2) | list/get |
| 运维(6) | task_plan_deep/conflicts_check/heartbeat/heal/watchdog_tick/task_cleanup |
| 看板/脉冲/预订/推荐+DAG(12) | dag_critical_path/parallelism/ascii/check/ready/sort/depend/publish、board_ascii、status_summary、reserve_scope/check/release、task_triage |
| 自驱(9) | selfdrive_init/append/get/export_tasks/review_tick/review_ready/publish_next/parse_next_tasks、selfdrive_pick_next |
| 自我记忆/自进化(7) | memory_consolidate/gc/link、evolve_distill/lesson/critic、task_challenge |
| 审计/权限(2) | audit_permission/log |
| 多租户(3) | store_open/list/close |
| 强验证(4) | omega_spec_create/review/result_verify/status |
| 其它(辅助) | evolve_submit/sample/snapshot/asset_register/self_search、run_check/cost_stats、… |

## 四、入口引导（agent 该怎么走）

1. **想懂业务流** → 读 `README.md`、`ARCHITECTURE.md`、`USAGE.md`。
2. **想改某层逻辑** → 见上表定位到 `src/<包>`，再读该包 `pkg.generated.mbti` 看公开接口。
3. **想加/改 MCP 工具** → `src/server/server.mbt` 用 `.tool(name, desc, schema, handler)`，handler 经 `_instrument` 包装（自动 call_log）。
4. **想动存储** → `src/store/store_sqlite.mbt`（表结构在 `moon.pkg` 初始化处）。
5. **想跑通即走** → `python scripts/mcp_smoke.py` / `scripts/enrich_selfdrive.py`。

## 五、约定与雷区（别踩）

- **测试**：JS 目标已支持；native 需系统 SQLite + VS 环境（见 AGENTS.md）。
- **Node ≥ 24**：JS 目标依赖 `node:sqlite` 的 returnArrays，<24 会导致列读空。
- **时间戳用 Int64**：`@env.now().to_int()` 对 UInt64 做 32 位截断会产生 1969 假时间戳——务必用 `.to_int64()`。
- **勿改共享 fist-mbt.db 测试**：测试用独立内存/SQLite（见 call_log_wbtest）。
- **无硬编码路径**：分隔符跟随输入，路径不硬编码盘符。