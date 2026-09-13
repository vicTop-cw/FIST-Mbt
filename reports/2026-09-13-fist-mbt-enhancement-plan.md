# FIST-Mbt 增强计划 — 对比 fistcode + FIST Python 的能力差距

> 日期：2026-09-13
> 负责人：FIST 指挥官（AtomCode / LongCat-2.0）
> 范围：FIST-Mbt 项目（MoonBit 纯 MCP Server 指挥层）
> 参考项目：fistcode（Rust，执行器层）、FIST（Python，闭环指挥体系）

---

## 0. 核心定位重申

FIST-Mbt 是 **MoonBit 原生重写的 FIST 指挥层**，通过 MCP Server 协议暴露给 AI 客户端。本次增强遵循：

- **全程使用 MoonBit 语言**（不引入其他语言代码）
- **保留和兼容原有功能**（现有 22 tools + 所有状态机语义不动）
- **MCP 委托模式**（执行器通过 MCP 委托给客户端，不硬桥接 CLI）

---

## 1. 三个项目能力对比矩阵

| 能力域 | fistcode | FIST Python | FIST-Mbt (当前) | FIST-Mbt (目标) |
|---|---|---|---|---|
| **状态机** | 内置 agent 状态 | 九态 | 九态（完整版） | ✅ 保持 |
| **DAG 依赖** | — | 有 | 有（6 个工具） | ✅ 保持 |
| **AO 递归拆解** | — | 有 | 有（decompose.mbt） | ✅ 增强（自适应参数） |
| **调度路由** | — | L1-L4 分级 + 模型映射 | 无（固定 split=3） | 🆕 新增 |
| **执行器抽象层** | 核心（CLI 派发） | 5 个真实执行器 | 仅记录交付物 | 🆕 MCP 委托 |
| **Omega spec 解析** | — | — | 有（纯函数） | ✅ 保持 |
| **Omega gate 跑批** | — | — | 有（纯函数） | ✅ 保持 |
| **Omega 验证工具化** | — | omega-verify 命令 | 无 | 🆕 新增 |
| **verify-fix 闭环** | — | 3 轮修复循环 | 无 | 🆕 新增 |
| **心跳持久化** | — | 内存 Map | 内存 Map | 🆕 SQLite |
| **自动 heal** | — | heal 命令 | heal 工具（手动） | 🆕 定时自动 |
| **成本统计** | — | executions 表 | 无 | 🆕 新增 |
| **成本熔断** | — | switch_free/pause | 无 | 🆕 新增 |
| **多租户命名空间** | — | — | 有（3 个工具） | ✅ 保持 |
| **审计日志** | — | — | 有 | ✅ 保持 |
| **冲突检测** | — | — | 有 | ✅ 保持 |
| **归档清理** | — | — | 有 | ✅ 保持 |

---

## 2. 增强项 Top5（按优先级）

### 🥇 P0：Omega 验证工具化 + verify-fix 闭环

**目标**：落地金条八"一票否决"，让 FIST-Mbt 从任务跟踪升级为质量门禁。

**新增文件**：
- `src/omega/omega_tool.mbt` — omega_verify + omega_verify_fix 工具实现
- `src/omega/omega_tool_test.mbt` — 测试

**交付内容**：
1. `omega_verify` 工具
   - 输入：`{ project_dir, corpus_dir?, threshold? }`
   - 遍历 corpus/ 下所有 spec JSON 文件
   - 调用 `spec.validate_full` + `gate.run_tests`
   - 汇总 `{ total, passed, failed[], accuracy, passed: bool }`
   - accuracy < 100% → 一票否决（返回 `exit_code: 1` + 失败明细）
2. `omega_verify_fix` 工具
   - 输入：`{ project_dir, corpus_dir?, max_rounds? }`
   - 失败根因分类：结构缺失 / 格式偏差 / 语义错误 / 指纹不匹配
   - 每种类型一个修复函数（纯 MoonBit 字符串/JSON 变换）
   - 修复后回归验证，循环上限 3 轮
   - 返回修复报告 `{ rounds, final_accuracy, fixes_applied[] }`
3. 注册到 `server.mbt` 作为第 23、24 个 tool

---

### 🥈 P1：调度路由层（scheduler + router）

**目标**：用 fistcode 的能力递归拆解任务推进，任务分配智能化。

**新增文件**：
- `src/engine/scheduler.mbt` — 任务分级 + 自适应参数
- `src/engine/router.mbt` — 成本档 → 执行器映射
- `src/engine/schedule_tool.mbt` — schedule MCP 工具

**交付内容**：
1. `scheduler.mbt`：`schedule_task(desc, project_dir, n_files) → ScheduleResult`
   - 复杂度分级：
     - L1（单文件 / <50 字描述）→ n_split=1, depth=1, parallel=1, cost_tier=free
     - L2（多文件 / 50-200 字）→ n_split=3, depth=2, parallel=2, cost_tier=free
     - L3（重构 / >200 字 / 跨模块）→ n_split=5, depth=3, parallel=3, cost_tier=premium
     - L4（不可逆 / 高风险关键词）→ hold=true, cost_tier=hold
   - 关键词命中检测（delete/drop/publish/deploy → L4）
   - 自适应规则（基于历史成功率反馈调参，预留接口）
2. `router.mbt`：`route(complexity, project_dir) → RouteResult`
   - cost_tier → executor 映射：
     - free → `McpDelegateExecutor`（默认客户端）
     - premium → `McpDelegateExecutor`（标注高优先级）
     - hold → 返回 `hold_reason`，等待人类确认
   - 输出：`{ executor, cost_tier, hold, reason? }`
3. `schedule` MCP 工具（不落库，仅预览）
4. 集成到 engine：`publish` 时自动调用 scheduler 建议参数，`plan` 时根据 router 结果选择执行器

---

### 🥉 P2：执行器抽象层（Executor trait + MCP 委托）

**目标**：实现"发布 → 执行 → 交付"闭环，不破坏现有 execute 工具语义。

**新增文件**：
- `src/executor/base.mbt` — Executor trait + ExecResult 类型
- `src/executor/mcp_delegate.mbt` — MCP 委托执行器
- `src/executor/registry.mbt` — 执行器注册表

**交付内容**：
1. `Executor` trait：
   ```moonbit
   trait Executor {
     fn name(self) -> String
     fn run(self, task: Task, ctx: ExecContext) -> ExecResult
   }
   ```
2. `McpDelegateExecutor`：
   - 接收 Task → 生成 task_context.json（同 mavis_executor 格式）
   - 通过 MCP 通知工具告知客户端执行
   - 客户端执行完毕后回调 `execute` 工具写回交付物
3. `registry.mbt`：
   - 注册表单例（默认 `McpDelegateExecutor`）
   - `register(name, executor)` / `get(name)` 接口
4. `execute` 工具扩展：
   - 保留原有签名和语义（向后兼容）
   - 新增可选字段：`executor?`, `model?`, `tokens?`, `cost?`
   - 写入 executions 表

---

### 4️⃣ P3：成本统计 + executions 表

**目标**：让 FIST-Mbt 能回答"这个任务花了多少钱"，为成本熔断打基础。

**新增文件**：
- `src/store/store_sqlite_executions.mbt` — executions 表 schema + CRUD
- `src/engine/cost_tool.mbt` — cost_stats + cost_budget_check 工具

**交付内容**：
1. executions 表 schema：
   ```sql
   CREATE TABLE executions (
     id TEXT PRIMARY KEY,
     task_id TEXT NOT NULL,
     executor TEXT NOT NULL DEFAULT 'manual',
     model TEXT,
     tokens_in INTEGER DEFAULT 0,
     tokens_out INTEGER DEFAULT 0,
     cost REAL DEFAULT 0.0,
     duration_ms INTEGER DEFAULT 0,
     rate_limited BOOLEAN DEFAULT FALSE,
     failure_reason TEXT,
     created_at TEXT NOT NULL
   );
   ```
2. `cost_stats` 工具：按执行器/模型聚合统计
3. `cost_budget_check` 工具：预算超限告警（`{ limit, current, exceeded, action }`）

---

### 5️⃣ P4：心跳持久化 + 自动 heal

**目标**：运维自动化，心跳不丢失，超时任务自动回滚。

**修改/新增文件**：
- `src/ops/ops_heartbeat.mbt` — 扩展为 SQLite 持久化
- `src/ops/ops_heal.mbt` — 扩展为定时自动触发
- `src/store/store_sqlite_heartbeat.mbt` — heartbeats 表 schema + CRUD
- `src/engine/heartbeat_tool.mbt` — heartbeat_status 工具

**交付内容**：
1. heartbeats 表 schema：
   ```sql
   CREATE TABLE heartbeats (
     id TEXT PRIMARY KEY,
     task_id TEXT NOT NULL,
     agent_id TEXT NOT NULL,
     status TEXT NOT NULL,  -- active/stalled/suspended/terminated
     last_seen TEXT NOT NULL,
     progress_note TEXT,
     created_at TEXT NOT NULL
   );
   ```
2. `heartbeat` 工具：写入 SQLite（替换内存 Map）
3. `heal` 工具：改为支持定时自动触发（async 轮询，可配置 interval）
4. `heartbeat_status` 工具：查看各任务心跳状态

---

## 3. 实施阶段拆解（按 fistcode 递归拆解推进）

```
Phase 1: Omega 验证闭环（P0）
  ├── 1.1 spec corpus 加载器（遍历目录 + 解析 JSON）
  ├── 1.2 omega_verify 工具（跑批 + 一票否决）
  ├── 1.3 根因分类器（失败 → 修复策略映射）
  ├── 1.4 修复函数集合（每种根因一个修复器）
  ├── 1.5 omega_verify_fix 工具（修复循环 + 回归）
  └── 1.6 注册到 server.mbt + 测试

Phase 2: 智能调度（P1）
  ├── 2.1 scheduler.mbt（分级逻辑）
  ├── 2.2 router.mbt（成本档映射）
  ├── 2.3 schedule MCP 工具（预览不落库）
  └── 2.4 集成到 publish/plan 流程

Phase 3: 执行闭环（P2 + P3）
  ├── 3.1 Executor trait + ExecResult
  ├── 3.2 McpDelegateExecutor（task_context.json 生成）
  ├── 3.3 registry.mbt
  ├── 3.4 executions 表 schema + CRUD
  ├── 3.5 execute 工具扩展（向后兼容）
  ├── 3.6 cost_stats + cost_budget_check 工具
  └── 3.7 测试

Phase 4: 运维自动化（P4）
  ├── 4.1 heartbeats 表 schema + CRUD
  ├── 4.2 heartbeat 工具持久化
  ├── 4.3 heal 工具自动触发
  ├── 4.4 heartbeat_status 工具
  └── 4.5 测试

Phase 5: 集成验证
  ├── 5.1 全链路测试（publish → schedule → plan → claim → execute → submit → verify → archive）
  ├── 5.2 moon check + moon test
  ├── 5.3 moon info + moon fmt
  └── 5.4 README / USAGE 更新
```

---

## 4. 文件变更清单

### 新增文件（12 个）

| 文件路径 | 归属阶段 | 说明 |
|---|---|---|
| `src/omega/omega_tool.mbt` | Phase 1 | omega_verify + verify_fix 工具 |
| `src/omega/omega_tool_test.mbt` | Phase 1 | 测试 |
| `src/engine/scheduler.mbt` | Phase 2 | 任务分级调度 |
| `src/engine/router.mbt` | Phase 2 | 成本档路由 |
| `src/engine/schedule_tool.mbt` | Phase 2 | schedule MCP 工具 |
| `src/executor/base.mbt` | Phase 3 | Executor trait |
| `src/executor/mcp_delegate.mbt` | Phase 3 | MCP 委托执行器 |
| `src/executor/registry.mbt` | Phase 3 | 执行器注册表 |
| `src/store/store_sqlite_executions.mbt` | Phase 3 | executions 表 |
| `src/engine/cost_tool.mbt` | Phase 3 | 成本统计工具 |
| `src/store/store_sqlite_heartbeat.mbt` | Phase 4 | heartbeats 表 |
| `src/engine/heartbeat_tool.mbt` | Phase 4 | heartbeat_status 工具 |

### 修改文件（5 个）

| 文件路径 | 变更内容 |
|---|---|
| `src/server/server.mbt` | 注册 6 个新工具 + 扩展 execute 工具参数 |
| `src/ops/ops_heartbeat.mbt` | 替换内存 Map 为 SQLite |
| `src/ops/ops_heal.mbt` | 增加自动触发逻辑 |
| `src/engine/engine.mbt` | 集成 scheduler + router |
| `src/store/moon.pkg` | 新增依赖声明 |

### 文档更新（3 个）

| 文件路径 | 变更内容 |
|---|---|
| `README.md` | 更新 tools 表（24 tools）+ 新增能力说明 |
| `USAGE.md` | 新增 Omega 验证 / 调度 / 执行器 / 成本章节 |
| `CHANGELOG.md` | 追加 M6 增强记录 |

---

## 5. 验收标准（金条八）

- [ ] `moon check` 全量通过（无 error）
- [ ] `moon test` 全量通过（含新增测试）
- [ ] `moon info` 生成的 .mbti 接口与实现一致
- [ ] `moon fmt` 格式化后无 diff
- [ ] 全链路 CRUD 测试通过（publish → archive）
- [ ] omega_verify 对失败 corpus 正确一票否决
- [ ] omega_verify_fix 3 轮内修复失败 spec 至 accuracy=100%
- [ ] schedule 工具正确分级 L1-L4
- [ ] execute 工具向后兼容（旧调用方式不报错）
- [ ] cost_stats 正确聚合 executions 数据
- [ ] heartbeat 持久化后重启不丢失
- [ ] heal 自动触发回滚超时任务
- [ ] 所有新工具通过 MCP stdio 调用验证

---

## 6. 风险与预案

| 风险 | 预案 |
|---|---|
| MoonBit async 定时器 API 不稳定 | 降级为手动触发 + 文档标注 |
| MCP 委托模式客户端不支持 | 保留 manual executor 作为 fallback |
| SQLite schema 迁移破坏现有数据 | 新增表不修改已有表，兼容旧库 |
| MoonBit 文件系统 API 限制 corpus 读取 | 用 read_file 逐文件读取，不依赖目录遍历 |
| 修复函数无法覆盖所有失败类型 | 第 3 轮仍未修复 → 标记 `needs_human_review` |

---

## 7. 与原功能的兼容性保证

1. **状态机不动**：九态转换逻辑、DAG 依赖、AO 拆解语义完全保留
2. **现有 22 tools 不动**：接口签名、行为、返回格式不变
3. **命名空间不动**：multi_store 完全兼容
4. **审计不动**：audit.mbt 逻辑不变，新操作自动进入审计链
5. **execute 工具**：扩展可选参数，旧调用（仅 task_id + deliverable）继续生效
6. **存储向后兼容**：新增 executions/heartbeats 表，不修改 tasks/deps 表

---

*本计划作为 FIST-Mbt M6 阶段的实施指南，所有代码使用 MoonBit 编写。*
