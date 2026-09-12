# FIST-Mbt

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260827-blue)](https://www.moonbitlang.com)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-57%2F57-brightgreen)](./src)

将 **FIST 指挥官任务分配体系**（原 Python 实现）用 **纯 MoonBit 原生重写** 并包装为 **MCP Server** 的参赛作品（2026 MoonBit 九月黑客松）。

指挥官（人类 / 主力模型）通过标准 MCP 协议调用 FIST-Mbt 暴露的 22 个工具，完成任务的 **发布 → 认领 → 拆分 → 执行 → 提交 → 验收 → 归档** 完整闭环，全程贯彻 FIST 七条金条原则。

> 该项目为 `E:\IDEProjects\AI\FIST`（Python）的 MoonBit 原生重写 + MCP 化，非原代码搬运。

---

## 快速开始

依赖：MoonBit 工具链（≥ 0.1.20260827，需支持 `errdefer` 与 `async`）。

```bash
# 依赖解析 & 编译
moon check

# 运行测试（57 项全部通过）
moon test

# 启动 MCP Server（STDIO 传输）
moon run cmd/main

# 启动 HTTP/SSE 桥接（可选）
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py
```

任意 MCP 客户端（Claude Desktop / AtomCode / 自研 JSON-RPC 客户端）以 STDIO 方式拉起该可执行文件即可交互。

### 最小调用示例（JSON-RPC over STDIO）

```json
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"publish",
  "arguments":{"project_dir":"E:/proj/demo","description":"示例根任务","created_by":"human_steward","now":"2026-09-05T10:00:00Z"},
  "_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}
}}
```

---

## MCP 暴露面

### Tools（22 个）

#### 生命周期八件套（九态状态机）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `publish` | 发布根任务（仅 human_steward/human） | project_dir, description, created_by, namespace, now |
| `claim` | 认领任务（待领取 → 已领取） | task_id, assignee, now |
| `plan` | 对已认领任务拆分为子任务 | task_id, split_n, by, now |
| `execute` | 记录执行交付物（→ 执行中） | task_id, deliverable, now |
| `submit` | 提交验收（→ 待验收） | task_id, now |
| `verify` | 验收通过（→ 已完成，父任务自动上卷） | task_id, verifier, now |
| `reject` | 验收拒绝（→ 已打回） | task_id, reason, by, now |
| `retry` | 打回后重试（→ 执行中） | task_id, now |
| `pause` | 暂停任务（任意活跃 → 已暂停） | task_id, now |
| `resume` | 恢复任务（已暂停 → 已领取） | task_id, now |
| `archive` | 归档（→ 已归档，仅人类指挥官） | task_id, by, now |
| `delete` | 删除任务（仅限已归档） | task_id |

#### 查询

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `list` | 列出全部任务，可按状态过滤 | status(可选) |
| `get` | 查询单个任务详情 | task_id |

#### 深拆与运维

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `task_plan_deep` | AO 式递归拆解，拆出整棵多层子任务树并写库 | task_id, split_n, by, spec, now |
| `conflicts_check` | claim 冲突检测（认领前检查是否已被他人/本人持有） | task_id, assignee |
| `heartbeat` | 活动信号上报（超时静默将触发 heal 回滚） | task_id, signal, now |
| `heal` | no_signal 看护：心跳超时静默的任务回滚为已领取待重派 | now, timeout_sec |
| `task_cleanup` | 归档清理：删除超保留期的已归档任务 | now, retention_days |

#### DAG 扩展（依赖图）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `dag_critical_path` | 返回当前最长依赖链（关键路径） | 无 |
| `dag_parallelism` | 返回当前可并行执行的任务数（待领取且依赖已满足） | 无 |
| `dag_ascii` | 返回当前命名空间任务的 ASCII 依赖结构图 | namespace(可选) |
| `dag_check` | 检查某任务的依赖是否全部完成 | task_id |
| `dag_ready` | 列出所有依赖满足、可领取的任务 | namespace(可选) |
| `dag_sort` | 对任务列表按依赖深度拓扑排序 | task_ids(JSON 数组) |

#### 审计与权限（M5 治理）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `audit_permission` | 查询某角色是否可执行指定操作 | role, action |
| `audit_log` | 查看追加式审计日志 | filter_actor(可选), filter_task_id(可选) |

#### 多租户命名空间（M5 多库隔离）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `store_open` | 打开（或复用）一个命名空间 | namespace, data_dir(可选) |
| `store_list` | 列出当前已打开的命名空间及任务数 | 无 |
| `store_close` | 关闭指定命名空间（不删除物理库文件） | namespace |

### Resources（2）

| URI | 内容 |
|---|---|
| `fist://principles` | FIST 七条金条原则（JSON） |
| `fist://overview` | 任务体系概览 |

### Prompts（2）

| 名称 | 用途 |
|---|---|
| `fist:check_in` | 执行者开工打卡自查模板 |
| `fist:verify` | 验收人验收要点模板 |

---

## 架构

```
E:/IDEProjects/AI/FIST-Mbt
├── .mcp.json            # MCP server 注册（moon run cmd/main）
├── AGENTS.md            # FIST 指挥官模式行为指令
├── README.md            # 本文档
├── USAGE.md             # 实操调用手册
├── cmd/
│   ├── main/            # STDIO MCP server 入口（moon run cmd/main）
│   └── cli/             # CLI 入口（moon run cmd/cli/main）
├── scripts/
│   └── fist-mbt-http.py # HTTP/SSE 桥接（FIST_MCP_PORT=3000）
├── src/
│   ├── core/            # 领域核心实体
│   │   ├── core_task.mbt       # 任务实体 + 九态状态机 + DAG depends_on
│   │   ├── core_role.mbt       # 角色权限矩阵（human_steward/leader/agent）
│   │   └── core_principle.mbt  # 七条金条原则常量
│   ├── store/           # 持久化
│   │   ├── store.mbt           # Store 抽象 + StoreBackend 工厂
│   │   ├── store_sqlite.mbt    # SQLite 实现（内建 DB）
│   │   └── multi_store.mbt     # 多库命名空间管理器（内部可变性）
│   ├── engine/          # FistEngine：业务逻辑闭环 + DAG 扩展
│   │   ├── engine.mbt          # publish/plan/claim/execute/submit/verify/archive + reject/retry/pause/resume
│   │   ├── engine_dag_ext.mbt  # critical_path/parallelism/dag_ascii
│   │   ├── decompose.mbt       # 任务拆解计算
│   │   └── *_test.mbt          # 引擎测试
│   ├── ops/             # 运维与治理
│   │   ├── audit.mbt           # 追加式审计日志 + Role 权限矩阵
│   │   ├── ops_conflicts.mbt   # 冲突检测
│   │   ├── ops_heartbeat.mbt   # 心跳上报
│   │   ├── ops_heal.mbt        # 超时回滚
│   │   ├── ops_cleanup.mbt     # 归档清理
│   │   └── ops_ts.mbt          # 时间戳工具
│   ├── omega/           # 可解释性子包：spec/gate/check
│   └── server/          # MCP server 装配
│       ├── server.mbt          # 22 个工具注册 + run_server
│       ├── stdio_js.mbt        # JS 后端 STDIO 传输
│       └── stdio_native.mbt    # 原生后端 STDIO 传输
└── moon.mod             # 模块元数据
```

**设计要点**：

- 纯 MoonBit 实现，无 Rust / C 包装；MCP 协议层使用 [`colmugx/mcp`](https://mooncakes.io/colmugx/mcp)（Apache-2.0，协议 2026-07-28）。
- 领域核心（core\*/store/engine）与协议层（server）分离，核心为纯逻辑、易单测。
- K 值递归衰减：根任务 depth=3，每拆一层减 1，depth≤1 为原子任务不再拆分。
- `plan` 需任务处于**已领取**态（先 `claim` 再 `plan`），保证拆分动作归属到具体负责人。
- 多租户：`MultiStore` 按 ns 路由到独立 SQLite 文件 `{data_dir}/{ns}.db`，惰性打开。
- 审计：`AuditLog` 进程内追加式日志，不落库；角色权限矩阵遵循"唯一指挥官/人类主权"原则。

---

## 状态机（九态）

```
                    ┌─ pause ──┐
                    ▼          │
待领取 ──claim──► 已领取 ──plan──► 拆分中 ──execute──► 执行中
   │                │                                       │
   │                └──────execute───────────────────────────┘
   │                                                        ▼
   │               待验收 ◄── submit ─── 执行中
   │                │    │
   │           verify    reject
   │                │    │
   │                ▼    ▼
   │           已完成   已打回 ──retry──► 执行中
   │                │
   │           archive
   │                │
   │                ▼
   │           已归档 ──delete──► 移除
   │
   └── resume ◄── 已暂停
```

**新增状态（M5 扩展）**：

| 状态 | 说明 | 进入方式 |
|---|---|---|
| `Rejected` | 已打回（验收不通过，需重做） | `reject`（待验收 → 已打回） |
| `Paused` | 已暂停（外部中断/等待依赖） | `pause`（任意活跃 → 已暂停） |

**新增迁移**：

| 迁移 | 触发 | 约束 |
|---|---|---|
| `retry` | `retry_task` | 仅 Rejected → Executing |
| `pause` | `pause_task` | 任意活跃状态 → Paused |
| `resume` | `resume_task` | Paused → Claimed |

非法迁移由状态机拒绝并返回错误，例如未认领直接 `plan` / `execute` 会报「非法迁移」。

---

## 测试

```bash
moon test   # 57 项黑盒测试全部通过
```

覆盖：根任务发布、发布权限（仅人类指挥官）、claim/plan/execute/submit/verify/archive/delete 全闭环、
reject/retry/pause/resume 新增迁移、非法迁移拦截（未认领 plan / execute、未归档 delete）、
按状态过滤查询、DAG 依赖检查、审计权限矩阵、多租户命名空间。

---

## 多租户（命名空间）使用

```json
// 1. 打开命名空间 "project-alpha"
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
  "name":"store_open",
  "arguments":{"namespace":"project-alpha","data_dir":"."},
  "_meta":{...}
}}

// 2. 发布任务到该 namespace
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
  "name":"publish",
  "arguments":{"project_dir":"...","description":"...","namespace":"project-alpha","created_by":"human_steward","now":"2026-09-05T10:00:00Z"},
  "_meta":{...}
}}

// 3. 查看已打开的命名空间
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
  "name":"store_list",
  "arguments":{},
  "_meta":{...}
}}

// 4. 关闭命名空间（不删除物理库文件）
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{
  "name":"store_close",
  "arguments":{"namespace":"project-alpha"},
  "_meta":{...}
}}
```

每个命名空间对应独立的 SQLite 文件 `{data_dir}/{namespace}.db`，实现数据隔离。

---

## HTTP/SSE 桥接（可选）

```bash
FIST_MCP_PORT=3000 python scripts/fist-mbt-http.py
```

暴露两个端点：

| 端点 | 说明 |
|---|---|
| `GET /health` | 健康检查，返回 `{"status":"ok","tools":22}` |
| `POST /mcp` | JSON-RPC over HTTP，请求体与 STDIO 模式一致 |

---

## 移植与合规声明

- **来源**：`E:\IDEProjects\AI\FIST`（Python），作者 victo。
- **许可证**：Apache-2.0。
- **本期范围**：用 MoonBit 原生重写核心领域逻辑与状态机，并封装为 MCP Server；
  未搬运 Python 原代码，未包含原项目未开源的业务数据。
- 原 Python 项目中的 scheduler / executor / webpanel 等模块不在本期范围内（见 CHANGELOG 演进说明）。

---

## License

Apache-2.0
