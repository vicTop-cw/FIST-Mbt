---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_6299d2fbe55211f184bd52540072b1e8
    ReservedCode1: xuXSookBKokHplXQnMMxruHWyahW9TmyzluKz5YsYOG9jGCEdWNlR9r7HipIuEvltUMEbFrl/Bud6bAg6U5HX/iRVF+vc1p8YSEE2MWUCweFrO1l+UtCvH8kKLDelRHfW/3tAkaSojxogjNpsWvn/Ny0HOjYxqrJnsBEUSxJapIRfw6lWEf3gwaORQk=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_6299d2fbe55211f184bd52540072b1e8
    ReservedCode2: xuXSookBKokHplXQnMMxruHWyahW9TmyzluKz5YsYOG9jGCEdWNlR9r7HipIuEvltUMEbFrl/Bud6bAg6U5HX/iRVF+vc1p8YSEE2MWUCweFrO1l+UtCvH8kKLDelRHfW/3tAkaSojxogjNpsWvn/Ny0HOjYxqrJnsBEUSxJapIRfw6lWEf3gwaORQk=
---

# 通用 Agent 服务注册平台计划（fist-mbt Agent Service Platform）

> **实施进度（2026-11-21 收口）**：
> - **P0 注册表与生命周期**：🟢 `agent_service` 表已入 `create_schema` 基线建表面（e399dcc3 修 fresh 库缺表）+ 六工具全注册（server.mbt）+ 行为锁 `src/engine/agent_service_wbtest.mbt` 4 格（生命周期/重启恢复/内存后端降级/幂等 UPSERT）全绿
> - **P1 常驻网关**：🟢 `scripts/fist_gateway.py`（MCPBridge 复用 + watchdog 退避 1s/5s/30s + svc_heartbeat 60s + 会话三件套落库 + §3.3 唯一退出路径）+ 黑盒判据 `scripts/blackbox/e2e_agent_gateway.py` 实弹 ALL PASS（39395dc0）
> - **P2 三级暴露**：�代办认证门（API-key sha256 哈希不落盘、无 key 401/带 key 200 实弹）、per-key 限流（60/min 默认）、lan 裸奔启动门、防火墙 best-effort 读数、e2e A6 lan 绑定臂（1a3865a9/3d80c46f）；余 HTTPS/mTLS 前置（global 部署项）
> - **P3 执行器矩阵**：�atomcode 🟢 已上线实弹（svc-atomcode @ 127.0.0.1:18640，local 档 + API-key 文件模式 `--api-key-file`，/health + /mcp 转发 + status_summary 真数据调用 + 无 key 401 全验证；库 `.fist-mbt/data/agent-services.db`）；**模型自动路由默认自动加入**（`--no-join-model-router` 可退出，条目落 `.fist-mbt/data/model-router-default.json` 的 agent_services 数组——4d3b2cbe）；freebuff/marvis/codearts 等无头类后续再接（§1.3 定案：各 agent 手动 start）
> - **P4 安全加固**：🟡 审计面已落（`--audit-log` mcp_call/auth_fail append-only，d22e876c）；**S3 挑战签名透传已接**（X-S3-Challenge 头注入三消费工具参数，验签/nonce 消费留在 fist serve——381a6511）；**session_pid 语义统一**（start 工具 gateway_pid 回填 + 网关侧 current_pid 统一）；S3 挑战接入 global 档完整闭环待公网部署
> - **P5 全球部署**：⚪ 需公网环境（反代 TLS + 远程 agent 接入）
> - e2e：`python scripts/blackbox/e2e_agent_gateway.py`（A1/A2/A2b/A3/A4/A6/A7 全绿；A5 watchdog 重启臂 posix only）

- 日期：2026-11-21
- 状态：计划 v2.0（通用化重写，替代 v1 面向 Marvis 单实例的 `marvis-agent-service-plan.md`）
- 定位：任意 agent 可注册为「agent 服务」；服务会话**长期不中断**，**仅收到显式中断指令**才终止；暴露范围支持**仅本机 / 局域网 / 全球**三档。

---

## 0. 目标（一句话）

把 fist-mbt 从「任务编排核心」升级为「Agent 服务托管平台」：任何 agent（Marvis、freebuff、codearts、atomcode、aider、自定义 CLI / HTTP agent）通过一次注册即可成为常驻服务，被本机、局域网或全球的调用方以 HTTP/SSE 方式按需调用，且服务生命周期只由显式中断指令控制。

三个硬性指标：
1. **任意 agent 可注册**：注册 = 身份登记 + 能力声明 + 执行通道绑定 + 暴露范围声明，与具体 agent 实现解耦。
2. **长期不中断**：常驻网关进程 + 守护自愈 + 心跳上报；客户端断开、网络波动、进程偶发崩溃均不影响服务存活。
3. **显式中断才终止**：状态机 `running → draining → stopped` 只由 `agent_service_stop`（或管理员确认的 stop 指令）触发；无其他隐式退出路径。

---

## 1. 核心模型

### 1.1 Agent 服务注册表（新增存储 `agent_service` 表，随 SqliteStore 扩展）

| 字段 | 说明 | 示例 |
|---|---|---|
| `service_id` | 全局唯一 | `svc-marvis` / `svc-codearts-win` / `svc-atomcode` |
| `owner_agent` | 注册主体身份（绑定 S3 agent key / executor 身份） | `executor_register(name="marvis", ...)` 返回的身份 |
| `capabilities` | 能力标签（语义化，供调用方发现） | `["编排","问答","文件","编码","app","web"]` |
| `transport` | 执行通道 | `mcp`（stdio 子进程）/ `cli`（本机 CLI 拉起）/ `http`（远程回调地址） |
| `exposure` | 暴露范围枚举 | `local` / `lan` / `global` |
| `status` | 生命周期状态 | `registered` / `running` / `draining` / `stopped` |
| `session` | 常驻会话信息 | `listen_addr`、`session_token`、`pid`、`last_heartbeat` |

### 1.2 新增 MCP 工具组 `agent_service_*`

| 工具 | 语义 |
|---|---|
| `agent_service_register(name, capabilities, transport, exposure, machine_id)` | 注册（幂等，返回 service_id；exposure 可后续升级） |
| `agent_service_start(service_id)` | 拉起常驻服务：生成 session token、绑定端口、启动心跳与守护 |
| `agent_service_stop(service_id)` | **唯一中断途径**：graceful drain → 终止会话（可选 force 强杀兜底） |
| `agent_service_status(service_id)` | 查询常驻状态 / 心跳 / 暴露端点 |
| `agent_service_list()` | 全量注册表（含状态过滤） |
| `agent_service_revoke(service_id)` | 撤销注册（须先 stop） |

### 1.3 启动模式（定案：由对应 agent 手动启动）

**常驻服务必须由对应 agent 手动启动**，禁止网关自动拉起无头 agent CLI：
- 用户对 Marvis 说「启动一个 agent 服务」→ Marvis 调 `agent_service_start(svc-marvis)`，此后 Marvis 的服务常驻不中断，其他 agent/脚本经 API-key 驱动 Marvis 干活。
- 同理 freebuff 侧：用户让 freebuff 启动 `svc-freebuff`，之后不中断，Marvis 也能驱使它。
- 注册（register）是静态登记；启动（start）是运行时行为：只有对应 agent 手动 start 后服务才进入 running，才有对外端点。
- 中断同理：仅对应 agent 收到显式中断指令（`agent_service_stop`）才终止。

---

## 2. 架构（三层 + 守护）

```
外部调用方（curl / 任意语言 SDK / 远程 agent / 本机脚本）
        │  HTTP + SSE（按 exposure 绑定的监听地址与认证）
        ▼
┌──────────────────────────────┐
│  fist-gateway（常驻进程）       │  ← 复用 fist-mbt-http.py 的 HTTP/SSE 转发模式
│  - 注册表读写（agent_service）   │     Python stdlib http.server 先例（web 面板计划）
│  - 认证 / 限流 / 审计门          │
│  - 暴露范围开关（绑定地址策略）    │
│  - 守护：崩溃自动重启 + 心跳      │
└──────────┬───────────────────┘
           │ spawn stdio 子进程（fist serve，MCP 协议）
           ▼
┌──────────────────────────────┐
│  fist-mbt 核心（MCP Server）    │
│  任务 / 心跳 / 认证 / 记账 / ACL │
└──────────┬───────────────────┘
           │ executor 执行通道
           ▼
  执行器池（任意已注册 agent）
  Marvis(mcp) / codearts(cli) / atomcode(cli) / aider(cli) / 自定义(http|cli)
```

**为什么必须另起网关进程**：`fist serve` 仅支持 stdio 传输，进程生命周期由 MCP 客户端控制（客户端断开即退出）。常驻 HTTP 服务必须由独立网关托管子进程，与任何单一客户端解耦。

---

## 3. 长期不中断机制

### 3.1 三层存活保障

| 层 | 机制 | 参数（沿用 v1 设计） |
|---|---|---|
| 服务会话层 | 心跳上报 `svc_heartbeat(service_id)` + 注册表 `last_heartbeat` 刷新 | TTL=300s，超时仅标记异常不终止 |
| 网关进程层 | watchdog 守护：崩溃检测 → 自动重启 → 恢复 running（会话 token 落库） | 重启退避 1s/5s/30s |
| 任务执行层 | 任务心跳 `heartbeat(task_id)` + `heal`（显式 ns） | timeout=600s，异常任务自愈 |

### 3.2 会话持久化
- `session_token`、`listen_addr`、`pid` 均落 SqliteStore；网关重启后按注册表恢复 `running` 态。
- 客户端（调用方）断开连接**不影响**服务进程存活——调用方只是 HTTP 请求的发起者，不是生命周期所有者。

### 3.3 唯一退出路径
```
agent_service_stop(service_id)
      → 状态机 running → draining（拒新任务，等存量任务 drain）
      → 30s 内未优雅退出 → force 强杀（审计记录）
      → stopped（注册保留，可再次 start）
```
无超时自杀、无客户端断开退出、无 idle 回收。**只有显式中断指令能终止服务**。

---

## 4. 三级暴露范围设计

| 档位 | 监听 | 认证 | 传输安全 | 适用场景 |
|---|---|---|---|---|
| `local`（仅本机） | `127.0.0.1:port` | 可选 session token | 明文 HTTP 可接受 | 本机脚本 / 本机 agent 互调 |
| `lan`（局域网） | `0.0.0.0:port` 或指定网卡 IP | **强制** API-key（哈希存储）+ 每 key 限流 | 建议 HTTPS / mTLS；HTTP 仅限可信内网 | 多机协作、公司内网、模拟器集群 |
| `global`（全球） | 公网入口（反向代理 / 云主机端口映射） | **强制** API-key + 可选 S3 挑战签名（`agent_issue_challenge`） | **强制** HTTPS（TLS1.2+） | 远程 agent、跨地域服务、对外开放 |

### 4.1 各档位安全矩阵（随档位升级强制项递增）

| 安全项 | local | lan | global |
|---|---|---|---|
| API-key 认证 | 可选 | 强制 | 强制 |
| key 哈希存储（不落明文） | ✅ | ✅ | ✅ |
| per-key 限流 / 配额 | 可选 | 强制（复用 `cost_budget_check`） | 强制 |
| 命名空间隔离（每服务独立 ns + `agent_acl_grant` fail-closed） | ✅ | ✅ | ✅ |
| 审计（`call_log` / `audit_log`） | 可选 | 可选 | 强制 |
| HTTPS / TLS | — | 建议 | 强制 |
| 启动时防火墙检查（Windows 入站规则 / iptables） | — | 强制 | 前置条件 |

### 4.2 档位变更规则
- 支持 `local → lan → global` 逐级升级（需管理员确认，升级时重新生成 API-key 并提示安全影响）。
- `global` 档**默认禁止**从纯 local 直接一步升到 global，必须经过 lan 验证。

---

## 5. 执行器接入矩阵

| agent | transport | 接入方式 | 备注 |
|---|---|---|---|
| Marvis | `mcp` | 本机 stdio 子进程作为执行端 | 沿用 v1 executor_register 身份 `marvis` |
| freebuff / codearts | `cli` | `codearts.cmd` 无头 CLI 拉起 | 经 Get-Command 可发现 |
| atomcode | `cli` | `atomcode.exe` | 已在 executor_run 白名单 |
| aider | `cli` | aider CLI | 已在 executor_run 白名单 |
| 自定义 agent | `http` / `cli` | 远程 HTTP 回调地址 / 本机 CLI | `executor_run` 自定义注册走受限 CLI 通道 |

注册与启动流程（常驻服务由对应 agent 手动启动）：
```
agent_service_register(...) → 生成 service_id（静态登记，任意 agent 可预先注册）
  → 自动创建独立命名空间 store_open(ns=svc_xxx) + agent_acl_grant(can_write=true)
  → [对应 agent 手动] agent_service_start(service_id) → 网关绑定端口、生成 API-key/session token、心跳上线
  → 服务进入 running 常驻，其他 agent/脚本经 API-key 调用；仅显式 stop 才中断
```

---

## 6. 里程碑（合计约 4.5~5 人日）

| 阶段 | 内容 | 验收标准 | 工时 |
|---|---|---|---|
| P0 注册表与生命周期 | `agent_service_*` 工具 + 状态机 + 会话持久化 | 注册/启动/停止/状态查询闭环，重启后恢复 running | 0.5 天 |
| P1 常驻网关 | fist-gateway 进程（复用 fist-mbt-http.py 模式）+ watchdog 守护 + 心跳 | 断开调用方连接服务不退出；进程被杀自动重启 | 1 天 |
| P2 三级暴露 | 绑定策略 + API-key + 限流 + 防火墙检查 | local/lan 端到端调用成功；global 网关具备 TLS 前置 | 1 天 |
| P3 执行器矩阵 | Marvis / codearts / atomcode / aider 注册为服务 | 4 个 agent 均注册为 running 服务并被外部调用成功 | 1 天 |
| P4 安全加固 | S3 挑战签名 + 全量审计 + 配额 | lan/global 认证与审计链路验证 | 0.5 天 |
| P5 全球部署 | 公网反代 TLS + 远程 agent 接入 | 远程 agent 经 global 端点调用本机服务成功 | 0.5 天（需公网环境） |

---

## 7. 风险与踩坑规避（复用已知教训）

| 风险 / 坑 | 规避 |
|---|---|
| `fist serve` 仅 stdio，生命周期随客户端 | 网关独立进程托管子进程，禁止客户端直接持有生命周期 |
| `commissar_read` 短轮询勿 subscribe/watch（BUG-480） | 服务心跳用显式 `svc_heartbeat` + 短轮询，不用订阅句柄 |
| `heal` 不带 ns 扫全库（BUG-81） | 所有 heal / heartbeat 显式传 namespace |
| `publish` / `dag_publish` 传 default 或空立即 Err（BUG-459） | 注册即显式建 ns，任务发布永远带 ns |
| `claim` 按 ns ACL fail-closed；`writable_agents` 空则拒绝 | 注册流程自动 `agent_acl_grant(can_write=true)` |
| `report_bug` / `project_dir` 拒绝对盘符 / `..` 上跳 | 注册数据与网关日志只落相对路径（server cwd 下） |
| 定时任务低可用时段 Agent 占位空转（历史踩坑） | 服务常驻后由本平台统一拉起执行，不再依赖 Agent 在线接收 |
| 全球暴露安全 | global 强制 TLS + key + 挑战签名 + 审计，默认禁止一步从 local 直升 global |

---

## 8. 与既有计划 / 资产的关系

- **复用**：`scripts/fist-mbt-http.py`（HTTP/SSE 转发）、`fist-mbt-api` 契约草案（`docs/openapi/fist.yaml`）、web 面板的 `FIST_WEB_TOKEN` 本地绑定认证先例、`executor_register` / `agent_register_key` / `agent_acl_grant` / `store_open` / `cost_budget_check` 等既有 MCP 能力。
- **替代**：v1 的 `marvis-agent-service-plan.md`（三层架构与三级心跳设计保留并泛化，命名空间由 `marvis` 扩展为每服务独立 `svc_*`）。
- **不动**：`fist serve` 核心、MCP 工具面、既有命名空间数据。

---

## 9. 待用户确认项

1. 执行器矩阵是否先接入这 4 个（Marvis / codearts / atomcode / aider），还是需要把 freebuff 也纳入？
2. 本机模拟器集群（Android 模拟器）是否作为 lan 档的首批调用方场景？
3. `global` 档是否已有公网服务器 / 云主机可做反向代理，还是先只做设计 + lan 落地？
4. P0–P5 是否按此顺序排期，还是需要压缩到 P0–P2 先出可演示闭环？
*（内容由AI生成，仅供参考）*
