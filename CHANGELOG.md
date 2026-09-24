---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_da2a1851a8e311f1be88525400aeaaa3
    ReservedCode1: bjwlVhY//jNc6vR1bak3cQP2fFnNxgXBoSwyG/1vXO7RcmiUeNogpvg5bJX8+s1vJkJCExuCTwep3TAb/zQpNOc6AWonho81iZe+p4SycFt/sYdnqYcCf39VAq7CINccbtup0lAEG79KluaHEsQ+mLNy7+YuOSrRqa2dF5S5nZlk8Py6wb5xilxTI2M=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_da2a1851a8e311f1be88525400aeaaa3
    ReservedCode2: bjwlVhY//jNc6vR1bak3cQP2fFnNxgXBoSwyG/1vXO7RcmiUeNogpvg5bJX8+s1vJkJCExuCTwep3TAb/zQpNOc6AWonho81iZe+p4SycFt/sYdnqYcCf39VAq7CINccbtup0lAEG79KluaHEsQ+mLNy7+YuOSrRqa2dF5S5nZlk8Py6wb5xilxTI2M=
---

# CHANGELOG

本项目变更记录（参赛期间每日至少 1 条，保证提交可追踪）。

## [0.2.3] - 2026-09-24

### 打磨与跨环境稳定化

- **可复现构建**：依赖全部来自公开 mooncakes registry；新环境首次需 `moon update` 刷新索引后即可 `moon build`/`moon test`，无需私有包或 vendor。
- **JS 目标 Node 版本约束**：SQLite JS 后端依赖 `node:sqlite` 的 `returnArrays`（Node ≥ 24 生效；<24 退化为对象行导致列读取为空）。已实测：node 25 → 135/135 全绿，node 23 → 28 失败。使用要求：**Node ≥ 24**。
- **绝对路径清理**：测试/smoke 的 `E:/proj/*` project_dir 样例统一改为 `/proj/*`，消除盘符硬编码。
- **文档对齐**：README/USAGE/AGENTS/申报书 工具数统一为 57、测试数 135；版本号统一 0.2.3。
- **新增功能**（0.2.0 后并入）：DGM 档案库 `evolve_*`、自驱闭环 `selfdrive_*`×8、看门狗 `watchdog_tick` 整合、Laya 可选决策 `laya_decide`（探针+降级）、多租户 namespace、并行发布 `publish_parallel`、`reopen_task` 等，MCP 工具由 41 → 57。

## [0.1.1] - 2026-09-09

### 源码重排（src/ 分类收拢）

- 根包散落的 `.mbt` 全部按职责收拢进 `src/` 子包并拆分子包，根包仅保留 `lib.mbt` 门面
  （导出 `Task/TaskStatus/SqliteStore/FistEngine` 与 `run_server`）。
- 新子包布局：`src/core/`（core_task/core_role/core_principle）、`src/store/`（store/store_sqlite）、
  `src/engine/`、`src/decompose/`、`src/ops/`、`src/omega/`、`src/server/`；`cmd/main`、`smoke` 保留。
- 跨包子包封装：新增 `StoreBackend::memory()/sqlite()` 工厂、`TaskStatus` 状态谓词
  （is_pending/is_claimed/is_splitting/is_executing/is_completed/is_reviewing/is_archived）、
  `Task::with_updated_at/with_deliverable`，消除跨包直接构造 readonly 类型；`plan_deep` 迁入 engine。
- 修根包 `typealias` 为 `type`（废弃语法）；更新 README 目录结构与全部 `@core./@store.` 引用。
- 验证：`moon check` 0 错误，`moon test` 全绿（engine/server/ops/omega 测试 + smoke）。

## [0.1.0] - 2026-09-05

### 首版（root commit 147e642）

- 新建 MoonBit 工程 `vicTop-cw/fist-mbt`，声明依赖 colmugx/mcp@0.17.4、mizchi/sqlite@0.3.1、
  moonbitlang/async@0.21.0。
- 领域核心：
  - `core_task.mbt`：任务实体 + 七态状态机（待领取/已领取/拆分中/执行中/待验收/已完成/已归档）与状态迁移校验。
  - `core_role.mbt`：八角色权限矩阵。
  - `core_principle.mbt`：FIST 七条金条原则。
  - `store.mbt`：Store trait + MemoryStore 内存实现。
  - `engine.mbt`：FistEngine 完整闭环（publish/plan/claim/execute/submit/verify/archive/list/get/delete）。
- MCP 层：
  - `server.mbt`：注册 10 tools + 2 resources（fist://principles、fist://overview）+ 2 prompts（fist:check_in、fist:verify）。
  - `cmd/main`：async 可执行入口，`run_stdio()` 启动 STDIO 传输。
- 修复记录：
  - 根包别名含点号非法 → 使用 @mcp_types/@mcp_resource。
  - main 入口 async/raise 问题 → 引入 moonbitlang/async 并改用 `catch` 包裹 run_stdio。
  - engine.claim 此前一步跳到「执行中」，导致 plan（要求已领取）无法走通 → 改为 claim 只做
    待领取→已领取，execute 进入执行中；同步更新 server 文案。
- 质量：`moon test` 7 项黑盒单测全绿；MCP STDIO 全链路冒烟通过。
*（内容由AI生成，仅供参考）*

## [0.2.0] - 2026-09-13

### M6 — Omega 验证闭环 + 智能调度 + 执行器抽象层

**新增工具（+8 个，总计 57 个）：**
- `omega_verify` — 批量验证 spec JSON（schema + fingerprint 校验，accuracy < 100% 一票否决）
- `omega_verify_fix` — 失败 spec 根因分类 → 定向修复 → 回归验证（3 轮循环）
- `schedule` — 调度预览：根据任务描述自适应计算分级/拆分/成本档/执行器（不落库）
- `cost_stats` — 执行成本聚合统计（total_records/total_cost/total_tokens/by_executor）
- `cost_budget_check` — 预算超限告警（exceeded/remaining/action）

**元数据扩展：**
- `execute` 工具向后兼容扩展：支持 executor/model/tokens_in/tokens_out/cost/duration_ms/rate_limited/failure_reason 元数据
- `StoreBackend::record_execution` — 执行记录持久化到 executions 表
- `engine.execute_with_meta` — 统一入口写入元数据

**新增子包：**
- `src/omega/`：spec.mbt / gate.mbt / check.mbt / omega_tool.mbt — 可解释性子包
- `src/engine/scheduler.mbt`：L1-L4 分级调度（根据描述长度/n_files 自适应计算 split_n/cost_tier/executor）
- `src/engine/router.mbt`：成本档路由（low→本地/delegate, medium→mcp_delegate, high→mcp_delegate:priority）
- `src/engine/cost_tool.mbt`：aggregate_stats + budget_check
- `src/executor/`：base.mbt（Executor trait + ExecResult）/ mcp_delegate.mbt / registry.mbt

**验证：** `moon check` 0 错误，`moon test` 77 项全绿。

### M7 — 成本追踪 + 心跳持久化 + WAL 并发修复

**核心修复与增强：**
- `StoreBackend::cost_stats()` — 聚合 executions 表统计（total_cost/total_tokens/by_executor 分组）
- 心跳持久化：`write_heartbeat`/`read_heartbeat`/`delete_heartbeat`/`list_all_heartbeats` 四层 CRUD
- `SqliteStore::open` 启用 WAL 模式 + `synchronous=NORMAL`（提升并发读写性能）
- 启动时 `init_heartbeats()` 从 SQLite 加载残留心跳；heartbeat/heal 操作同步落库
- `is Some(_)` 语法修复 → `match` 表达式（MoonBit 不支持该语法）
- 测试 base_dir 修复：`"test-data"` → `"."`（SQLite 不自动创建父目录）

**验证：** 77/77 测试通过（含新增 WAL 并发测试 3 ns × 5 tasks）。

### M8 — 文档体系完善 + 用户体验增强

**文档更新：**
- README.md：工具数 22→36、测试数 57→77；新增 Omega/调度/成本工具表；新增项目结构 executor/ 子包
- CHANGELOG.md：补录 M6/M7/M8 条目（本条）
- USAGE.md：新增 Omega 验证/调度/成本/心跳完整示例；更新测试验证命令

**验证：** `moon check` 0 错误，`moon test` 77/77 全绿，`moon info` 8 个 .mbti 接口文件生成。

---
