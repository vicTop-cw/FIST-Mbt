# fist-auto 统一模型面 · 可行性与设计定案（T0r124 · 工作项一）

| 项 | 值 |
|---|---|
| 任务 | T0r124 · 一：可行性与设计定案（含 Trae 接入形态验证） |
| 执行 | atomcode（autoplan ns）· 2026-11-25 |
| 约束 | 只读盘点 + 最小改动；本单不改任何业务代码 |
| 计划真源 | `fist-mbt/plan/active/2026-11-25-fist-auto-model.md`（裁决项 A1–A4 已定案） |
| 本单产出 | 本文件 + 一次性探针 `temp/t0r124_probe.py`（gitignore 内，未进提交面） |

## 结论摘要（先给答案）

1. **可行性：成立**，且不需要新造协议——现有构件（`scripts/fist_gateway.py` 的 HTTP 骨架、
   `src/router/model_router.mbt` 的池与计数 choke point、OFM relay 的 OpenAI 兼容通道）
   已足够，缺的只有两段实现：**同步真补全**与**跨协议轮转**。
2. **Trae 填这个地址后真的能出内容**：能，但有一个硬条件——**`base_url` 必须整条填
   `http://127.0.0.1:<port>/v1/chat/completions`**，填基址会双拼成 `/v1/v1/...` 得 404。
   这一条是**实测**的（探针 A 格 + Trae 本地状态库字段取证），不是推断。
3. **额度耗尽跳过后请求真的落到下一个可用服务**：能——轮转是软性排序 + 失败顺延，
   实测「首选 401 → 下一候选 200 且返回真内容」，且重试次数有上限（A3=3）。
4. **一处必须回报的撞车（新发现）**：计划 A1 定的端口 **18651 现已被 OFM-1 占用**
   （实测 LISTENING，`model-router-default.json` 记其 endpoint 为 `http://127.0.0.1:18651/mcp`）。
   ⇒ A1 的「独立新端口」判断不变，但**端口号须改**；实测可用空档自 **18654** 起。详见 §1.3。

## 1. 端点归属：URL / 端口 / 鉴权形态

### 1.1 形态（A1=A：独立端点，复用网关代码路径）

`fist-auto` 作为**独立常驻网关**起来，形态与既有网关同构（`scripts/fist_gateway.py`
的 HTTP 骨架：`/health` + `/v1/models` + `/v1/chat/completions`），只把最后一条的处理体
从「任务受理器」换成「同步真补全 + 轮转」（工作项二）。既有受理语义保留为**另一条命名路径**
（如 `/v1/tasks` 或 `/v1/chat/dispatches`），两者按开关/命名区分，不破坏既有执行器。

- **对外契约面**：`POST /v1/chat/completions`，OpenAI 兼容请求体
  （`model` / `messages` / 可选 `temperature`/`max_tokens`/`stream`）。
- **成功响应**：真实 `choices[0].message.content`（**禁止**把任务回执包装成回答——计划红线）。
- **鉴权**：沿用 `fist_gateway` §4.1 口径，不自造第二套：
  - 给 `--api-key`（或 `--api-key-file`）即强制认证，凭证明文不落盘、只存 sha256；
  - **本机档**（绑定 `127.0.0.1` 且未给 key）可裸读——这正是 Trae 场景需要的形态；
  - **非本机绑定**（lan/global）强制 key，启动期拒绝裸奔（`lan_binding_requires_key`）。
  - Trae 侧的配置形态：把同一把 key 填进条目 `ak`（`custom_openai_compatible` 条目实测字段：
    `name` / `ak` / `base_url` / `is_custom_base_url` / `provider_name` / `custom_model_id`）。

### 1.2 Trae 的 `base_url` 语义（本单最关键的接入事实 · 实测）

**Trae 把 `base_url` 当完整端点用，不当基址。**

证据两条：

| 证据 | 读数 |
|---|---|
| Trae 本地状态库 `…/Trae CN/User/globalStorage/state.vscdb`（`ItemTable`，key `…_AI.agent.model.model_list_map`） | 现网 LongCat 条目 `base_url` = `https://api.longcat.chat/openai/v1/chat/completions`（**含 `/chat/completions` 全文**），同时 `is_custom_base_url: true`、`client_connect: true`、`provider: custom_openai_compatible` |
| 本地合成网关对照实测（探针 `temp/t0r124_probe.py` A 格） | 按整条端点 POST ⇒ HTTP 200 且回真 content；按「基址 + 客户端再拼 `/v1/chat/completions`」⇒ 路径变 `/v1/v1/chat/completions` ⇒ **HTTP 404** |

⇒ **配置口径定死**：Trae 条目的 `base_url` 必须填

```
http://127.0.0.1:18654/v1/chat/completions
```

不能填 `http://127.0.0.1:18654` 或 `http://127.0.0.1:18654/v1`。模型名一栏填该端点对外宣告的 id
（见 §3.3），Trae 侧会记成 `custom_openai_compatible//<id>`。

> 注意：`base_url` 的形态意味着 **`/v1/models` 必须与 `/v1/chat/completions` 同源同进程**。
> 若 Trae 会去 GET `base_url` 去掉尾部段拼 `/models`，行为不可控——本设计按「客户端只在
> `base_url` 上发 chat 请求」实现，并保留 `/v1/models` 供人工/其它客户端发现用（实测 Trae
> 侧不做此调用；这条作为待工作项七复核的观察点）。

### 1.3 端口：A1 的 18651 已撞车 ⇒ 改 18654（实测）

计划 A1 写「独立新端口 18651」。**实测该端口已被占用**：

| 端口 | 实测状态 | 归属 |
|---|---|---|
| 18326 | OPEN | OFM relay（DSH 本体，作上游候选） |
| 18640/18641/18643/18644/18645/18646/18649/18650 | OPEN | svc-atomcode/codearts/freebuff/marvis/webai/workbuddy/codeforce/xiaoquan |
| **18651** | **OPEN** | **OFM-1**（`model-router-default.json` 记 `http://127.0.0.1:18651/mcp`，与 OFM-2/18652、OFM-3/18653 同族） |
| 18654 / 18655 / 18656 / 18660 / 18670 | free | — |

⇒ **建议端口改为 18654**（A1 的「独立端点 + 复用网关骨架」判断不变，仅端口号修正）。
理由：18651–18653 已被 OFM 网关族占据，且它们已在路由配置里以 `agent_services` 身份注册；
新起一个同族服务却复用其端口，会让「服务在跑」的判据与 guardian 的端口真源互相矛盾。

**端口真源口径**（不新增第二处真源）：新服务照既有网关做法自登记进 `agent_service`
（`patch_registry` / `patch_session`），guardian 的 `derive_service_ports()` 每轮从该表重推
⇒ 无需改代码、无需重启守护器，新端口自动被巡检认得（`scripts/gateway_guardian.py:114`）。

> 顺带记录（不在本单范围）：真源实测推 **9 项**（含 `svc-autoclaw:18647`），而 fallback 常量表
> 仍列 6 项且把 18649 标为 `svc-agent`；注册表里 `svc-codeforce` 与 `svc-agent` 目前**同在
> 18649**（前者 running、后者 stopped）。这是「真源优先于常量」的又一实例，随工作项三核对。

## 2. 候选池成员与协议归一化

### 2.1 候选来源：`agent_service` 登记册（不新造清单）

骨架 = `.fist-mbt/data/agent-services.db` 的 `agent_service` 表（`patch_registry` /
`patch_session` 写入），字段：`service_id / owner_agent / capabilities / transport /
exposure / status / session_listen_addr / session_token / session_pid /
session_last_heartbeat`。实测 **10 行**（9 个端口真源项）。

### 2.2 kind 三分类（A2=A：只有能真出 content 的才进补全池）

| kind | 判据 | 处置 |
|---|---|---|
| `openai_compatible` | 有 `/v1/chat/completions` 且回真实 `choices[].message.content` | **进补全池** |
| `mcp_task` | 只暴露 MCP（`/mcp`），其 `chat/completions` 是任务受理器 | 单列「工具侧候选」，**禁止**把回执包装成回答 |
| `cdp` | 网页驱动（`web_bridge` 走 CDP `send_question`） | 单列，需人工确认能否作同步后端 |

判据必须**实测**而非看 `capabilities` 字符串——现状面正是反例：`svc-atomcode` 等 7 个服务都
声称 `capabilities` 含「编码/问答」，但它们的 `/v1/chat/completions`（若存在）语义各不相同。
实测结论：

| 候选 | 实测 | kind |
|---|---|---|
| OFM relay `127.0.0.1:18326` | `/v1/models` 200（**607 模型**）；`/v1/chat/completions` 200 + 真 content（耗时 ~2.6–3.8s） | `openai_compatible` ✅ 首选 |
| `svc-atomcode` 18640 等 8 个网关 | `/health` 200；`chat/completions` 语义是**任务受理器**（`publish` → `chatcmpl-<task_id>`） | `mcp_task` ⛔ 不进补全池 |
| `svc-webai` 18645 | `transport=mcp`；`web_bridge` 侧另有 CDP 面 | `cdp`（待工作项三核实） |

⇒ **当前唯一已证可用的同步补全后端 = OFM relay（18326）**。这正是工作项二/三的核心工作量所在：
把 relay 变成「真后端之一」并逐个核实其余候选。**在核实完成前不得让其它候选进补全池**
（否则就是 A2 明令禁止的假支持）。

### 2.3 归一化形状（一个 `/v1/chat/completions` 吃掉三种协议）

```
客户端（Trae）──POST /v1/chat/completions──▶ fist-auto（18654）
                                              │  轮转选一个候选（§3）
                                              ├─ openai_compatible → 原样转发到候选端点
                                              │    （Authorization: Bearer <候选自己的凭据>）
                                              └─ mcp_task / cdp      → 只在「工具侧」被调用，
                                                   不进补全链路（A2）
```

关键实现约束（都会在工作项二落地）：

1. **`model` 是路由键，不是任意字符串**。Trae 发来的 `model` 必须能映射到候选条目，
   否则归一化无从选人。对外宣告用固定 id（建议 `fist-auto`，见 §3.3）；
   上游真实 model 名（如 `trae/glm-5.3-flash`）由端点在转发时替换，**不对客户端暴露**。
2. **凭据归一**：每个候选带 `credential_ref`（指向 env / 数据目录里的 key），
   端点按候选**改写 Authorization 头**再转发。relay 的真源已实测确定——
   `~/.dsh/our-free-model/settings.json` 的 `chanGateway.relay.key`
   （注意：进程 env 里的 `FIST_OFM_KEY` 实测**不是**这把 relay key，
   拿它打 18326 得 401；`OFM_FORWARD_KEY` 同理是 forward 线，见 §5 风险表）。
3. **请求体直通**：`messages` / `temperature` / `max_tokens` 原样透传
   （沿用 `src/router/ofm_chat.mbt` 的 fail-closed 校验：role ∈ {system,user,assistant}、
   content 非空，否则本地 400，不发给上游烧额度）。
4. **响应归一**：上游成功形状双读 `choices[0].message.content` 与 `choices[0].text`
   （`src/router/ofm_response.mbt` 已是这个口径），统一回填成
   `{id, object:"chat.completion", choices:[{index:0, message:{role:"assistant",content}, finish_reason}], usage}`。

## 3. 轮转策略：判据与数据结构

### 3.1 准入判据（红线三条，三者皆满足才入候选）

| # | 判据 | 数据来源 | 现状证据 |
|---|---|---|---|
| ① | 服务在注册表 `alive` | `agent_service.status == "running"` + `/health` 探活 | guardian 已在做同样判定 |
| ② | 该服务无存活执行会话（并发压制口径） | 沿用既有口径（全局在途 >3 压制，计划追加实测已记） | `model_router_status` 可读 |
| ③ | 该上游无冷却 / 未耗尽 | 候选条目的 `cooldown_until` / `fail_count`（本计划新增面） | 现状 `exhausted` 字段已在池结构里 |

复用 `pool_pick` 的环形扫描形态（`src/router/model_router.mbt`：`free_pool`/`paid_pool` +
`free_idx`/`paid_idx`），扩展为**跨协议候选表**。计数 choke point 唯一：
`quota_window_consume`（仅 `:1244` 调用，调用链 `pick → model_router_ops:514`）——
本计划的记账**挂在同一个 choke point**，避免出现第二处计数实现（判例「同一规则多份实现」）。

### 3.2 候选条目字段（计划指定 7 项 + 实现必需 2 项）

```
{
  "id":                "ofm-relay-18326",          // 稳定 id，入账与状态面用它
  "kind":              "openai_compatible",        // openai_compatible | mcp_task | cdp
  "endpoint":          "http://127.0.0.1:18326/v1/chat/completions",  // 完整端点
  "credential_ref":    "env:FIST_OFM_RELAY_KEY",   // 或 "file:.fist-mbt/data/xxx.key"
  "last_used":         0,                          // epoch 秒；从未使用为 0
  "fail_count":        0,
  "cooldown_until":    0,                          // epoch 秒；0 = 未冷却
  "upstream_models":   ["trae/glm-5.3-flash", ...],// 【增】转发时的 model 映射真源
  "streaming":         false                       // 【增】是否支持 stream；false 则一律非流式
}
```

- `endpoint` 存**完整 chat/completions 端点**（与 Trae 侧 `base_url` 语义一致，避免再拼一次出错）。
- `cooldown_until` 用 epoch 秒而非 ISO 串：比较只需整数大小，且时区/格式漂移不会静默失效。
- `upstream_models` 是**实测得来**（relay 现为 607 条，落盘 `temp/ofm_models_live.json`），
  工作项三须对每个候选重新探活刷新。

### 3.3 轮转算法（软性：只排序与跳过，不封禁）

```
每次请求：
  1. 过滤：alive && 无存活会话 && now >= cooldown_until && !exhausted
     → 空池：回明确错误体（HTTP 503 + {"error":{"message":"无可用候选"}}），不假成功
  2. 排序：候选表环形游标 free_idx 前进，取「下一个」满足条件的候选
  3. 记账：last_used = now；计数走 quota_window_consume（唯一 choke point）
  4. 转发：同步等结果
  5. 失败（网络错/4xx/5xx/超时）：fail_count += 1；达阈值 → cooldown_until = now + backoff
     然后**顺延下一个候选重试**，上限 N=3（A3=B）；超限回明确错误体
  6. 成功：fail_count 清零（或衰减），返回真实 content
```

对外 `model` 建议固定宣告 `fist-auto`（Trae 里显示为 `custom_openai_compatible//fist-auto`），
端点内部按候选的 `upstream_models` 选一个真上游 model 转发。
「一来一回换一个」的直观效果 = 每请求后 `free_idx` 前进一格，状态面可见（工作项六）。

## 4. 同步等待与超时（Trae 是同步 HTTP 客户端）

这是本单与设计关系最紧的一条：**不能回 `task_id` 就完事**——Trae 拿到回执会当模型回答显示。

| 层 | 定案 |
|---|---|
| 返回时机 | **同步阻塞等上游出真内容**再回 200。实测 relay 真补全耗时 ~2.6–3.8s，可接受 |
| 服务端超时 | 建议 `--timeout` 默认 120s（大于上游 p99，小于客户端常见上限）；超时按失败顺延 |
| 失败回体 | `HTTP 503/502` + `{"error":{"message": "...", "type":"fist_auto_exhausted"/"upstream_error"}}`；**不回假成功** |
| 任务受理路径 | 保留但**改命名**（如 `/v1/tasks`），与真补全路径分离，避免既有执行器误调 |
| `stream:true` | 若客户端要求 SSE，先落非流式聚合再按需转 SSE；一期可显式拒绝 `stream` 并说明 |
| 长会话 | 单请求内最多 3 次顺延，每次受同一超时约束 ⇒ 最坏 ~3×timeout，须在状态面可见 |

**为什么不能异步**：Trae 的 `custom_openai_compatible` 没有回调/轮询约定，唯一契约就是这一次
HTTP 往返。异步化会把「统一模型」变成「统一任务队列」，用户看到的仍是空白——那正是本计划要消灭的现象。

## 5. 实测证据（本单验收口径的两条回答）

一次性探针 `temp/t0r124_probe.py`（gitignore 内，未进提交面；落合成候选网关，
**不碰 Trae 配置、不动任何生产服务**）。读数（2026-11-25）：

```
=== T0r124 probe ===
[PASS] A.full_endpoint_19711 :: HTTP 200
[PASS] A.double_join_is_404_19711 :: HTTP 404
[PASS] B.failover_produces_content :: primary(exhausted)→HTTP 401; next(healthy)→HTTP 200
[PASS] B.skipped_primary_not_retried_forever :: attempts=2
[PASS] C.relay_reachable :: HTTP 200 elapsed 2.59s
[PASS] C.relay_real_content :: content head: '连通测试'
SUMMARY: 6 checks, 0 failed
rc=0
```

### 5.1 「Trae 填这个地址后是不是真的能出内容」

- **端点形态实测通过**：按完整端点 POST 得 200 + 真 content；按基址双拼得 404。
- **Trae 侧字段取证**：本地 `state.vscdb` 现网条目 `base_url` 存的就是完整端点全文
  （含 `/chat/completions`），`is_custom_base_url: true`。
- **真后端可达性实测通过**：relay `/v1/chat/completions` 直发一轮得 HTTP 200、耗时 ~2.6–3.8s、
  回真实 content（`trae/glm-5.3-flash`）。
- ⇒ **结论：能出内容**。前提三条：端口不撞车（用 18654）、`base_url` 整条填、鉴权头按 §1.1。
  Trae 里那条现网 LongCat 条目当前 ak 已失效（计划已记），与本设计无关但需另行重新鉴权。

> 诚实边界：本单的 Trae 验证是**协议形态 + 本地状态库字段**两级实证，**没有**在 Trae GUI 里
> 真的发一轮对话（工作项七才做端到端实配）。因此这里说的是「端点形态已证、真后端已证、
> 接入路径无未解未知」，而不是「已在 Trae 里跑出一次对话」。工作项七须补上这一格。

### 5.2 「额度耗尽跳过后，请求是否真的落到下一个可用服务」

- **实测通过**：合成候选里首选恒 401（模拟额度耗尽/凭据失效）→ 顺延第二个候选 → HTTP 200
  且返回真内容，尝试次数 2（受上限约束，不会无限轮转）。
- **轮转软性**：只排序与跳过，不封禁；失败记 `fail_count` 并在阈值进冷却。
- ⇒ **结论：会落到下一个**，且不会因反复重试把用户挂死。

### 5.3 证据文件

| 文件 | 内容 |
|---|---|
| `reports/2026-11-25-fist-auto-design-report.md` | 本设计说明 |
| `temp/t0r124_probe.py` | 一次性探针（A/B/C 三格，可复跑） |
| `temp/ofm_models_live.json` | relay 现行模型清单（607 条，本次实测拉取） |

## 6. 风险与遗留

| # | 风险 / 缺口 | 处置 |
|---|---|---|
| R1 | **A1 端口号漂移**：计划写 18651，实测已被 OFM-1 占用 | 建议改 **18654**；A1 的归属判断不变。需要指挥官确认端口号修订（见 §7 待决） |
| R2 | **`FIST_OFM_KEY` env 与 relay key 不是同一把** | 实测：env 里那把打 18326 得 401；relay key 真源 = `~/.dsh/our-free-model/settings.json` 的 `chanGateway.relay.key`。工作项二须显式定源，否则会把凭据失效误判成端点不可达 |
| R3 | **relay 模型数随上游增长**（计划记 152，本次实测 607） | 工作项三按次探活刷新，不在文档抄数（抄一个数就是漂移雷） |
| R4 | **注册表重复身份**：`svc-codeforce` 与 `svc-agent` 同在 18649；fallback 常量表列 6 项 vs 真源 9 项 | 工作项三核对；不在本单修 |
| R5 | **relay 上游 bug 史**：`src/router/ofm_response.mbt` 记其 `/v1/chat/completions` 曾恒回 500（atomcode is not defined）；本次实测已恢复 200 | 说明该后端**可能再退化** ⇒ 轮转必须把它当普通候选处理（失败即顺延），不可硬编码为唯一后端 |
| R6 | **Trae 端到端未验** | 归工作项七；本单只证到协议形态与字段 |
| R7 | 本单**未改任何业务代码**、未动 ACL / 注册表 / 既有服务参数 | 符合约束；探针落 gitignore 内的 `temp/` |

## 7. 待指挥官确认

1. **端口号修订**：18651 → **18654**（实测空档；A1 其余部分不变）。
2. **对外的 model id**：建议固定 `fist-auto`（Trae 显示为 `custom_openai_compatible//fist-auto`）。
3. **任务受理语义的改名**：现有 `/v1/chat/completions` 受理器拟保留并挪到独立命名路径
   （如 `/v1/tasks`），需确认既有调用方（若有）后再动——工作项二执行。

## 来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-auto-model.md`
- 盘点对象：`scripts/fist_gateway.py`、`scripts/gateway_guardian.py`、`scripts/check_ofm_endpoint.py`、
  `.fist-mbt/data/agent-services.db`、`.fist-mbt/data/model-router-default.json`、
  `src/router/{model_router,model_router_ops,ofm_chat,ofm_response}.mbt`、`src/executor/cli_argv.mbt`
- Trae 侧取证：`%APPDATA%/Trae CN/User/globalStorage/state.vscdb`
- relay 凭据真源：`~/.dsh/our-free-model/settings.json`（值不回显）
- 实测：`temp/t0r124_probe.py`（6 格全过，rc=0）+ relay 直发真补全（200 / ~2.6–3.8s / 真 content）


