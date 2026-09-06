---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_d6da448aa8e311f1a393525400f8a581
    ReservedCode1: GRSWKKcGS+h75rRxWqwGNxtMKibO8CYeDd9QifndbDCNr64hZqY8aT7XDiY4qeVSpsLrDQv1ZIPpWWKx1A7KftfgIBoeC66TS6YB89/6jVD8qk7JUFwhnHzofKO0i5p56pwt/4995ml2uT5EUgNLh+hSlI55QPNg5iJ7aPSKh9X9yXgSRZDtCB8Skt0=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_d6da448aa8e311f1a393525400f8a581
    ReservedCode2: GRSWKKcGS+h75rRxWqwGNxtMKibO8CYeDd9QifndbDCNr64hZqY8aT7XDiY4qeVSpsLrDQv1ZIPpWWKx1A7KftfgIBoeC66TS6YB89/6jVD8qk7JUFwhnHzofKO0i5p56pwt/4995ml2uT5EUgNLh+hSlI55QPNg5iJ7aPSKh9X9yXgSRZDtCB8Skt0=
---

# FIST-Mbt

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260827-blue)](https://www.moonbitlang.com)

将 **FIST 指挥官任务分配体系**（原 Python 实现）用 **纯 MoonBit 原生重写** 并包装为 **MCP Server** 的参赛作品（2026 MoonBit 九月黑客松）。

指挥官（人类 / 主力模型）通过标准 MCP 协议调用 FIST-Mbt 暴露的 10 个 `task` 系列工具，完成任务的
**发布 → 认领 → 拆分 → 执行 → 提交 → 验收 → 归档** 完整闭环，全程贯彻 FIST 七条金条原则。

> 该项目为 `E:\IDEProjects\AI\FIST`（Python）的 MoonBit 原生重写 + MCP 化，非原代码搬运。

---

## 快速开始

依赖：MoonBit 工具链（≥ 0.1.20260827，需支持 `errdefer` 与 `async`）。

```bash
# 依赖解析 & 编译
moon check
moon build --target native

# 运行测试（7 项核心状态机单测）
moon test

# 启动 MCP Server（STDIO 传输）
moon run
# 或直接运行编译产物（等价）
./_build/native/debug/build/cmd/main/main.exe
```

任意 MCP 客户端（Claude Desktop / MCP Host / 自研 JSON-RPC 客户端）以 STDIO 方式拉起该可执行文件即可交互。

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

### Tools（10）

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `publish` | 发布根任务（仅 human_steward/human） | project_dir, description, created_by, now |
| `plan` | 对已认领任务拆分为子任务 | task_id, split_n, by, now |
| `claim` | 认领任务（待领取 → 已领取） | task_id, assignee, now |
| `execute` | 记录执行交付物（→ 执行中） | task_id, deliverable, now |
| `submit` | 提交验收（→ 待验收） | task_id, now |
| `verify` | 验收（→ 已完成） | task_id, verifier, now |
| `archive` | 归档（→ 已归档，仅人类指挥官） | task_id, by, now |
| `list` | 列出全部任务，可按状态过滤 | status(可选) |
| `get` | 查询单个任务详情 | task_id |
| `delete` | 删除任务（仅限已归档） | task_id |

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
E:\IDEProjects\AI\FIST-Mbt
├── core_task.mbt       # 任务实体 + 七态状态机（待领取/已领取/拆分中/执行中/待验收/已完成/已归档）
├── core_role.mbt       # 八角色权限矩阵（human_steward/leader/executor/searcher/reviewer/cleaner/verifier/documenter）
├── core_principle.mbt  # 七条金条原则常量
├── store.mbt           # Store trait + MemoryStore 内存实现（后续可换 SQLite）
├── engine.mbt          # FistEngine：publish/plan/claim/execute/submit/verify/archive/list/get/delete 完整闭环
├── server.mbt          # MCPServer 装配：tools/resources/prompts 注册 + run_stdio
├── cmd/main/           # 可执行入口（async fn main → run_server）
├── fist-mbt_test.mbt   # 黑盒单测（moon test）
├── README.mbt.md       # 本文档
└── CHANGELOG.md
```

**设计要点**：

- 纯 MoonBit 实现，无 Rust / C 包装；MCP 协议层使用 [`colmugx/mcp`](https://mooncakes.io/colmugx/mcp)（Apache-2.0，协议 2026-07-28）。
- 领域核心（core\*/store/engine）与协议层（server）分离，核心为纯逻辑、易单测。
- K 值递归衰减：根任务 depth=3，每拆一层减 1，depth≤1 为原子任务不再拆分。
- `plan` 需任务处于**已领取**态（先 `claim` 再 `plan`），保证拆分动作归属到具体负责人。

---

## 状态机（七态）

```
待领取 --claim--> 已领取 --plan--> 拆分中 --execute--> 执行中
已领取 --execute--> 执行中
执行中 --submit--> 待验收 --verify--> 已完成 --archive--> 已归档 --delete--> 移除
待验收 --reopen--> 已领取（被打回重做）
```

非法迁移由状态机拒绝并返回错误，例如未认领直接 `plan` / `execute` 会报「非法迁移」。

---

## 测试

```bash
moon test   # 7 项黑盒测试全部通过
```

覆盖：根任务发布、发布权限（仅人类指挥官）、claim/plan/execute/submit/verify/archive/delete 全闭环、
非法迁移拦截（未认领 plan / execute、未归档 delete）、按状态过滤查询。

另含 MCP 全链路冒烟验证（JSON-RPC over STDIO）：publish → claim → plan → 子任务
claim/execute/submit/verify → list/get → resources/read，全部通过。

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
*（内容由AI生成，仅供参考）*
