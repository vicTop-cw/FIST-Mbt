---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_a90e6914e5b411f1a9b8525400f8a581
    ReservedCode1: vwnt98j3WtNDFrsOiepc+COWFAGuBSSs/iMcmGI/pMk+reiwplXOTEJs66IGC5lmKn/ORLgs84p2W7AdjoIADdqvJpfxvGvqqFOXuMbXwZv6do1daczJoIYzNDYsdaCF5TE8D0dbADjkcQZmnxgJebRNrLYo/SEPQ8Q/8uoU/Dlgtapn0O0mWUGmMQo=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_a90e6914e5b411f1a9b8525400f8a581
    ReservedCode2: vwnt98j3WtNDFrsOiepc+COWFAGuBSSs/iMcmGI/pMk+reiwplXOTEJs66IGC5lmKn/ORLgs84p2W7AdjoIADdqvJpfxvGvqqFOXuMbXwZv6do1daczJoIYzNDYsdaCF5TE8D0dbADjkcQZmnxgJebRNrLYo/SEPQ8Q/8uoU/Dlgtapn0O0mWUGmMQo=
---

# Web 版 AI 常驻服务接入计划（web-model-agent-service）

> 日期：2026-11-21
> 状态：计划拟定，待执行
> 仓库：E:\IDEProjects\AI\FIST-Mbt
> 定位：复用 fist-agent-service-platform（P3）已建成的注册表 + 常驻网关 + API-key 认证 + 自动路由底座，把「网页版 AI（DeepSeek 网页版 / 腾讯元宝等）」接入为 fist-mbt 可调用的常驻 Agent 服务，重点服务**网页资源搜索**。

---

## 0. 背景与动机

### 0.1 为什么做

- 网页版 AI（DeepSeek 网页版、腾讯元宝）内置**联网搜索 + 多轮理解 + 总结提炼**能力，对"网页资源搜索"场景价值极高：给一个目标，它直接返回筛选后的结论与来源，而非原始 DOM 流。
- 现有方案（playwright 抓取、cli 配浏览器插件）是**纯自动化抓取**：拿回的是页面结构，仍需二次理解，且维护成本高（选择器/反爬/登录态）。
- 本方案走**用户手动建服务**模式：用户首次手动登录网页版并启动常驻桥接服务，之后该服务长期可被 fist-mbt 其他 agent / 脚本经 API-key 驱使。即"首次手动启动，后续拿来即用"。

### 0.2 与既有资产的复用关系

| 复用资产 | 位置 | 用途 |
|---|---|---|
| agent_service 注册表 | src/store/store_sqlite.mbt | 服务身份/能力/状态登记 |
| 常驻网关模式 | scripts/fist_gateway.py | 桥接服务对外暴露 /health + /mcp，API-key 认证、限流、审计 |
| 自动路由 | model_router（free/paid 池 + agent_services 数组） | 把网页版服务挂入 /v1/chat/completions 与工具路由 |
| 生命周期 | agent_service_start / stop / status / list | 用户手动启动/停止，watchdog 自愈 |

---

## 1. 目标与边界

### 1.1 目标

1. 把网页版 AI 注册为 fist-mbt 常驻 Agent 服务（service_id 拟定：`svc-webai`）。
2. 暴露 MCP 工具面：`web_search`（网页版 AI 联网搜索）、`web_extract`（从目标 URL 提炼资源/要点）、`chat`（通用对话问答）。
3. 其他 agent / 脚本可经 `POST http://127.0.0.1:<port>/mcp` + API-key 驱使该服务干活。
4. 全程复用自动路由：网页版模型可挂入 model_router 作为模型源，也可作为 executor 白名单条目。

### 1.2 非目标（边界）

- 不替代 playwright 的强自动化抓取；本方案依赖网页版 AI 自身的联网能力。
- 不做浏览器插件分发；桥接器只负责"驱动用户已登录的网页版会话"。
- 不破坏大厂免费策略：单账号自用、配额自限、审计可溯，不对外商业化。

---

## 2. 架构设计

### 2.1 总体链路

```
fist-mbt agent/脚本
   │  POST /mcp + X-API-Key（JSON-RPC 2.0）
   ▼
桥接网关（web-bridge，复用 fist_gateway.py 模式，独立端口）
   │  校验 key → 限流 → 审计
   ▼
网页版驱动层（浏览器会话驱动，用户已手动登录）
   │  构造对话/搜索指令 → 等待网页版 AI 完成 → 取回结果
   ▼
DeepSeek 网页版 / 元宝（用户账号，联网搜索 + 理解总结）
```

### 2.2 组件划分

| 组件 | 形态 | 职责 |
|---|---|---|
| `web-bridge` 网关 | Python 薄壳（复用 fist_gateway.py 模式） | /health、/mcp、API-key 校验、限流、审计日志 |
| 网页版驱动 | 浏览器会话驱动层 | 用户手动登录一次；封装"发送提问 → 等待回答 → 提取文本/来源" |
| 会话状态 | 本地文件 | 登录态保持、会话恢复、心跳 |
| 注册行 | agent_service 表 | svc-webai：capabilities=["web_search","web_extract","chat"]，transport=mcp，exposure=local |

### 2.3 工具面契约（MCP JSON-RPC）

| 工具名 | 入参 | 出参 |
|---|---|---|
| `web_search` | query(必填)、max_results(可选) | 结果列表：title/url/snippet |
| `web_extract` | url(必填)、question(可选) | 提炼要点 + 来源 |
| `chat` | prompt(必填)、history(可选) | 网页版 AI 回复文本 |

认证：`X-API-Key`；key 明文只存 `.fist-mbt/data/svc-webai.apikey`，网关比对 sha256 哈希。

---

## 3. 实施计划（分期）

### P0：桥接器骨架（本次执行）

- [ ] 新建 `scripts/web_bridge.py`：浏览器会话管理（用户手动登录入口）、提问/等待/提取循环、MCP 工具注册骨架。
- [ ] 会话状态落盘：`.fist-mbt/data/webai-session.json`（登录态、最近心跳）。
- [ ] 首次手动启动指引：打印"请在弹出的浏览器窗口中登录网页版 AI，登录完成后按回车"。

### P1：注册 + 网关暴露

- [ ] 注册行：`agent_service_register(name=svc-webai, capabilities=["web_search","web_extract","chat"], transport=mcp, exposure=local)`。
- [ ] 生成 API-key：`secrets.token_hex(12)`，明文写 `.fist-mbt/data/svc-webai.apikey`，网关存 sha256 哈希。
- [ ] 网关拉起：独立端口（拟定 18645，避开 18640/18641/18643/18644），watchdog 心跳 + 自愈。
- [ ] 验收 A1：`GET /health` 返回 alive。

### P2：工具面落地

- [ ] `web_search`：把 query 送入网页版 AI → 取回搜索结论与来源列表。
- [ ] `web_extract`：给定 URL → 网页版 AI 提炼要点与来源。
- [ ] `chat`：通用对话。
- [ ] 验收 A2：`initialize → tools/list` 两次握手，工具清单含上述三工具。

### P3：自动路由挂载

- [ ] 将 svc-webai 挂入 model_router 的 `agent_services` 数组（或注册为 executor 白名单条目）。
- [ ] `/v1/models` 与 `/v1/chat/completions` 可将外部模型请求路由到 svc-webai。
- [ ] 验收 A3：经 `/v1/chat/completions` 完成一次网页资源搜索问答。

### P4：端到端验收

- [ ] e2e：派发一次"搜索某主题并提炼"任务，验证返回结论 + 来源真实可用。
- [ ] 配额与审计核对：call_log 记账、网关审计日志含 mcp_call，无 auth_fail 异常。
- [ ] 生命周期：agent_service_stop 后服务干净退出，重新 start 可恢复。

---

## 4. 安全与配额约束

1. **红线**：端口勿用 18640（atomcode 在用）；勿动其他服务行；API-key 明文只存 `.fist-mbt/data/svc-<agent>.apikey`。
2. **认证**：local 档绑定 127.0.0.1；lan/global 强制 API-key（本计划默认 local）。
3. **限流**：per-key 令牌桶默认 60/min，超限 429。
4. **审计**：`mcp_call` / `auth_fail` 落 append-only 日志。
5. **免费策略**：单账号自用、配额自限（窗口/次数）、审计可溯；不对外商业化。
6. **会话安全**：登录态文件仅本机可读；不在日志中打印 cookie/token 明文。

---

## 5. 交付物清单

| 交付物 | 路径 |
|---|---|
| 桥接器脚本 | scripts/web_bridge.py |
| 注册脚本 | temp/register_webai_svc.py（或 scripts/） |
| 网关日志 | temp/gateway-svc-webai.log |
| API-key 文件 | .fist-mbt/data/svc-webai.apikey |
| 会话状态 | .fist-mbt/data/webai-session.json |
| 本计划 | docs/plans/2026-11-21-web-model-agent-service.md |

---

## 6. 执行方式

按用户指令：**执行计划使用现已建成的自动路由服务，全程由 fist-mbt 驱动开发**（经 svc-codearts 的 executor_run / 免费池自动路由派发开发任务），本次先执行 P0。
*（内容由AI生成，仅供参考）*
