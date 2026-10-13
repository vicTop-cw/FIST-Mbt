# posoco 六边形架构参考调研（L44）

> 参考 Agent 框架六边形架构设计，明确 FIST-Mbt 的架构取舍

## 六边形架构（Ports & Adapters）核心思想

Alistair Cockburn 的六边形架构把应用分成内外两层：
- **内层（域）**：纯业务逻辑，不依赖任何外部技术
- **外层（适配器）**：技术实现细节（数据库、HTTP、CLI、MCP）

内层通过 **port（接口）** 对外声明需求，外层通过 **adapter（适配器）** 实现 port。

## posoco 的六边形架构（参考）

posoco 作为 Agent 框架，典型六边形分层：

```
┌─────────────────────────────────────────┐
│  外层适配器                              │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ MCP Port │ │ HTTP API │ │ CLI     │ │ ← 入站适配器
│  └──────────┘ └──────────┘ └─────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ Store    │ │ LLM      │ │ Search  │ │ ← 出站适配器
│  └──────────┘ └──────────┘ └─────────┘ │
├─────────────────────────────────────────┤
│  内层（域）                              │
│  ┌───────────────────────────────────┐  │
│  │ Agent Core（状态机/记忆/规划）     │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## FIST-Mbt 的架构现状

FIST-Mbt 已经是**事实上的六边形架构**，只是没有显式标注：

### 内层（域，纯计算，无 IO）

| 模块 | 职责 |
|------|------|
| `src/evolve/` | DGM 档案库 + scoring + curriculum + mutation + self_search |
| `src/dag/` | DAG 关键路径/PERT/Monte Carlo 排程 |
| `src/ops/` | 开发模式 + 六顶帽辩论 + 调度 |
| `src/router/` | 模型路由 + Star 门 + 故障分类 |
| `src/symbolic/` | 布尔逻辑 + SAT 求解 |
| `src/ltl/` | LTL 运行时监控 |
| `src/decompose/` | 任务拆解 + 里程碑 |
| `src/constraint/` | 约束求解 |
| `src/store/store.mbt` | StoreBackend trait（port） |

### 外层适配器

| 适配器 | 实现 |
|--------|------|
| 入站：MCP | `src/server/server.mbt`（152+ 工具） |
| 入站：CLI | `cmd/cli/` |
| 出站：Store（内存） | `src/store/store_rsv.mbt` MemoryStore |
| 出站：Store（SQLite） | `src/store/store_sqlite.mbt` |
| 出站：LLM/HTTP | `src/router/ofm_*.mbt`、`src/server/*_js.mbt` |
| 出站：GitHub | `src/evolve/github_client.mbt`、`src/server/github_sync.mbt` |

## FIST-Mbt 与 posoco 的架构差异

| 维度 | posoco（参考） | FIST-Mbt（现状） |
|------|----------------|------------------|
| 域核心 | Agent 状态机/记忆/规划 | **任务编排 + 自进化** |
| 入站端口 | 多协议（MCP/HTTP/CLI） | MCP 为主 + CLI |
| 出站端口 | LLM/Store/Search | Store/LLM/GitHub/外部执行器 |
| 纯计算比例 | 中等 | **极高**（评分/难度/可移植性/健康度全是纯函数） |
| 并发安全 | 框架级 | **作用域预订 + 分布式文件锁 + 违例审计** |

## FIST-Mbt 的架构取舍

### ✅ 坚持的

1. **域逻辑纯计算**：scoring/difficulty/portability/health 全是纯函数，不碰 IO，保证可测试可复现
2. **StoreBackend trait**：内存 + SQLite 双后端实现同一 port，保证行为一致
3. **HTTP/网络由注入层执行**：github_client 生成 URL + 解析 JSON，实际 HTTP 调用由 JS/native 适配器注入
4. **评分非 LLM 自评**：所有评分都是确定性计算，不依赖 LLM 主观判断

### ❌ 不照搬 posoco 的

1. **不做纯 Agent 运行时**：FIST 的核心是任务编排，不是单个 Agent 的执行循环
2. **不抽象过多 port**：FIST 的工具面就是入站适配器，不需要再抽象一层"Agent port"
3. **不追求架构纯粹性**：当纯计算优先与架构纯粹冲突时，优先纯计算可复现

## 结论

FIST-Mbt 已经是"实用主义六边形架构"：
- 内层纯计算域（evolve/dag/ops/router/symbolic/ltl/decompose）
- 外层适配器（server/store/sqlite/js native bridge）
- 通过 StoreBackend trait / 注入式 runner 实现 port

**不照搬 posoco，而是选择性吸收其"内外分离、纯计算核心"思想**——FIST 的护城河是"自驱 + 自进化 + 并发安全"，架构服务于这个护城河。
