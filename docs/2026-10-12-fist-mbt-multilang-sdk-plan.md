---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_551ff67ac61f11f197b3525400248c00
    ReservedCode1: PJDQY/s0TTTM/X4RyRqjfXpFDAyhfoG0EfXLs8trQYVSisKFEmq47Jk2azCQp6hSKAyjwpyfH9zbGX8E95aBLrLhWfw452B1bDhHB9GVUozFSWqcXiPBCTZj9J4WO02CDjY4u6kdoqfFp1DqgzObivsYhwNESD5uxKw84de6dXxZ+LEt1D0qQmN5tQ8=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_551ff67ac61f11f197b3525400248c00
    ReservedCode2: PJDQY/s0TTTM/X4RyRqjfXpFDAyhfoG0EfXLs8trQYVSisKFEmq47Jk2azCQp6hSKAyjwpyfH9zbGX8E95aBLrLhWfw452B1bDhHB9GVUozFSWqcXiPBCTZj9J4WO02CDjY4u6kdoqfFp1DqgzObivsYhwNESD5uxKw84de6dXxZ+LEt1D0qQmN5tQ8=
---



# fist-mbt 多语言接入与动作层计划（v0.2 收窄版）

- 日期：2026-10-12
- 状态：计划 v0.2（收窄版：砍掉 SDK 矩阵，改为 MoonBit 原生 + HTTP 协议）
- 前置：fist-mbt 已是一源四态（MCP/CLI/Skill/Plugin），Web 面板实现中（态5）；本计划落地"态6：多语言接入"

---

## 0. 定位澄清（先回答：这个计划到底解决什么问题）

**问题**：别的语言的开发者，怎么在自己的项目里用上 fist-mbt 的能力（任务编排 / 模型路由 / 锁 / 帽子）？

**两种答案，选第二种**：
1. ❌ 为每门语言手写 SDK 客户端（Python/TS/C#/Scala/Elixir……）→ 维护地狱，用户量≈1，不成立
2. ✅ **安装 MoonBit 即可解决**：fist-mbt 本身是 MoonBit 写的，能力面 = MoonBit 生态能力面
   - 想当库用：装 MoonBit 工具链，直接以 MoonBit 库方式调用核心
   - 前端 / 可嵌 wasm 的语言：fist-mbt 编译成 js / wasm 后端产物直接复用
   - 其余语言（Python/Rust/C#/Go……）：一律走 HTTP 协议（REST + JSON + SSE），任何语言 curl / requests / HttpClient 即可调，**不需要专用 SDK**

**因此本计划不再产出任何"语言 SDK 矩阵"**，只做三件事：
1. 定版 HTTP 契约（fist-mbt-api），作为所有非 MoonBit 语言接入的统一入口
2. vools 融合层（仅 Python，用户自己用）
3. actus 动作层（用户确认必做，动作 DSL 化封装）

**覆盖范围**（即"要覆盖啥"）：契约层 5 个接口族——任务 / 路由 / 锁 / 帽子 / 通用（详见 2.2）。

---

## 1. 目标与范围（收窄版）

只做三件事，不做 SDK 矩阵：

**A. HTTP 契约定版（fist-mbt-api）**
- 基于现有 `scripts/fist-mbt-http.py` 扩展为 REST + JSON + SSE 统一入口
- 所有非 MoonBit 语言（Python/Rust/C#/Go/JS……）一律经此接入，语言侧只需自带 HTTP 能力（curl / requests / HttpClient / fetch），无需任何专用 SDK

**B. vools 融合层（仅 Python，用户自己用）**
- `fist.vools_task` 适配器 + bridge.md 解析 → DAG 描述，混合编排

**C. actus 动作层（用户确认必做）**
- actus 将 fist-mbt 封装为"一套动作"（动作 DSL + 注册表 + 执行器 + demo/web 回填）

**边界声明**
- 不产出任何语言 SDK / 桥接包（含 lz/pentad/兹，需要时直接用 CLI 透传或 HTTP）
- Rust 线（fist-rs / tnr / lz Rust 侧）：用户自持

## 2. 契约层（单真源）

### 2.1 原则
所有 SDK / 桥接 / 动作层都只依赖一份稳定契约，禁止各自直连 MCP 私有细节。

### 2.2 契约定版
- 基于现有 `scripts/fist-mbt-http.py` 扩展为 `fist-mbt-api`：REST + JSON + SSE
- 接口族：
  | 族 | 端点（草案） | 对应 MCP 工具 |
  |---|---|---|
  | 任务 | `POST /tasks/submit` `POST /tasks/execute` `POST /tasks/verify` `GET /tasks/{id}` `POST /tasks/{id}/retry` | task_* 系列 |
  | 路由 | `GET /router/status` `GET /router/models` `GET /router/route` | model_route / model_auth_status |
  | 锁 | `POST /locks/acquire` `POST /locks/release` `GET /locks/status` | lock_* |
  | 帽子 | `GET /hats/list` `POST /hats/debate`（HexaMind 落地后扩展 `POST /hats/run`） | hat_* |
  | 通用 | `GET /tools` `POST /tools/{name}/call` `GET /health` | tools/list 等 |
- 错误码：复用 OFM 归因体系（INVALID_CREDENTIAL / RATE_LIMIT / UPSTREAM_DOWN / NOT_FOUND / TIMEOUT）
- 事件流：SSE（`GET /events`），沿用现有模式
- schema：OpenAPI 3.x 单文件（FIST-Mbt 仓内 `docs/openapi/fist.yaml`），作为所有语言接入的对照契约

### 2.3 发布位置（收窄版）
- 契约随 FIST-Mbt 仓维护（`scripts/fist-mbt-http.py` + `docs/openapi/fist.yaml`），不另建仓
- actus 动作层在用户自己的 `E:\workspace\AI\actus\` 项目内实现（独立，用户确认必做）
- vools 融合层在用户 vools 项目内实现（Python）
- 不新建任何 fist-* 客户端仓

## 3. 客户端策略：不需要 SDK

- MoonBit 生态内（含编译到 js / wasm）：直接以 MoonBit 库或编译产物复用，零额外代码
- MoonBit 生态外：经 HTTP 契约接入，语言侧 20 行以内封装即可（README 给最小示例：curl / requests / HttpClient / fetch）
- 唯一例外：fist-py 内的 vools 融合层（见 §5），因需深度耦合用户自己的 vools 库

## 4. 语言家族（lz / pentad / 兹）接入策略

统一不做专用桥接包，按需二选一，均在语言内 20 行内完成：
- **CLI 透传**：`fist call <tool> --json <args>`（语言内 system / 子进程调用）
- **HTTP 直连**：直接调 §2 契约端点（语言自带 HTTP 能力）

需要时以"示例片段"形式追加到 FIST-Mbt 仓内 `docs/examples/<lang>/`（文档级，不建包、不建仓）。
- lz：若未来要 C ABI 级性能复用，走 fist-rs 动态库（Rust 侧用户自持），Marvis 只出 C ABI 头
- pentad / 兹：CLI 透传或 HTTP 二选一即可，无特殊要求

## 5. vools 融合层（fist-py 内）

| 接口 | 融合设计 |
|---|---|
| `fist.vools_task` | vools.task（look_upon 任务表）适配器：本地任务表提交 ↔ fist-mbt MCP/HTTP 双向转发 |
| `fist.bridge` | bridge.md（Markdown 即代码）解析 → 生成 fist-mbt 任务 DAG 描述 |
| `fist.payload` | 复用 vools `jsonb_encode / VText.toZipB64` 作为 payload 编解码，天然兼容 |
| `fist.functional` | 函数式外壳：`pipe(task, compose(...))` 风格调用 fist-mbt 动作 |

验收：Python 中 `import fist; fist.submit(...)` 与 `from vools.task import ...` 混合编排跑通一个端到端任务。

## 6. actus 动作层（用户确认必做）

### 6.1 定位
actus 不做"又一个 SDK"，而是把 fist-mbt 变成**一套可复用动作**：用户用 `#!config` 声明动作集，actus 解析注册、执行动作编排、回填展示。

### 6.2 动作 DSL（草案）

```config
#!config action plan_gen
  target: fist-mbt /plan_deep
  params: { task: "{{input}}" }
  output: plan

#!config action exec_leaf
  target: fist-mbt /execute
  depends: plan_gen
  params: { leaf: "{{plan[0].id}}" }
```

- 动作 = 名称 + 目标端点 + 参数模板（支持变量插值/引用前置动作输出）+ 依赖
- 执行器：按依赖拓扑顺序调用契约端点，结果写入动作上下文
- 回填：结果按动作契约结构回填 actus demo / web 展示

### 6.3 落地
- 目录：`E:\workspace\AI\actus\`（actus 项目内）+ 契约样例随 FIST-Mbt 仓内 `docs/openapi/fist.yaml`
- 产出：
  1. `#!config` 动作解析器
  2. 动作注册表（内置 fist-mbt 140+ 工具的"动作化"映射分类：计划类/执行类/验证类/路由类/锁类/帽子类）
  3. 执行器（HTTP 直连契约）
  4. demo：`fist-actions-demo.config` 演示"拆解 → 执行 → 验证"一套动作
- 验收：一条 actus 配置即可跑完"plan_deep → execute → verify"全流程，结果回填展示

## 7. 分期与验收

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| S0（P2 期间） | 契约 v1 定版 + actus 动作层骨架 + vools 融合基础 | OpenAPI 落盘；actus 跑通 plan→execute→verify；Python（vools）端到端任务 |
| S1（P2 末期） | vools 融合层完整（bridge.md 转 DAG）+ README 多语言最小示例 | bridge 适配器跑通；curl / requests / fetch 示例可用 |
| S2（赛后） | actus demo 完善 + 契约按需扩展 | demo 全流程回填展示 |

## 8. 风险与取舍

- **契约漂移**：MCP 工具 140+，契约只收"动作化分类"后的稳定子集（任务/路由/锁/帽子/通用），避免全量映射
- **HTTP 契约膨胀**：非 MoonBit 语言全走 HTTP，接口族必须保持小而稳，避免每加一个 MCP 工具就扩契约（扩展走 `POST /tools/{name}/call` 通用透传）
- **actus 动作依赖 DAG**：复用 fist-mbt 自身 DAG 语义，不另造轮子
- **Rust 线用户自持**：fist-rs 动态库进度依赖用户，风险标注（当前不阻塞，lz C ABI 仅在用户需要时才做）

## 9. 命名总览（收窄版）

| 产物 | 名称 | 位置 |
|---|---|---|
| HTTP 桥 | fist-mbt-api | FIST-Mbt 仓内 `scripts/fist-mbt-http.py` |
| 契约 | OpenAPI 3.x | FIST-Mbt 仓内 `docs/openapi/fist.yaml` |
| vools 融合层 | fist.vools_task | 用户 vools 项目内（Python） |
| actus 动作层 | fist-actions | `E:\workspace\AI\actus\`（独立项目，用户确认必做） |
| 语言最小示例 | README / docs/examples | FIST-Mbt 仓内 `docs/examples/<lang>/`（可选，文档级） |
*（内容由AI生成，仅供参考）*
*（内容由AI生成，仅供参考）*
