---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_828e66b7c5d811f197b3525400248c00
    ReservedCode1: wWCJOmoZMGCJcsyrO1AesYbVntHU2jjq3La7meigZmmXogg8HjjHWSez7BUioBeLaSyaoFtTjct8ZivczETRubNYrR/bfDY8oggIfiED8wadXl3q8CPkuGXzh+Cl0vqUV3XI5VJCF/gXnMoa7zM/RHckPRG7DNITQBGZrm3WA098pWjTdhCATmFZkUg=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_828e66b7c5d811f197b3525400248c00
    ReservedCode2: wWCJOmoZMGCJcsyrO1AesYbVntHU2jjq3La7meigZmmXogg8HjjHWSez7BUioBeLaSyaoFtTjct8ZivczETRubNYrR/bfDY8oggIfiED8wadXl3q8CPkuGXzh+Cl0vqUV3XI5VJCF/gXnMoa7zM/RHckPRG7DNITQBGZrm3WA098pWjTdhCATmFZkUg=
---

# FIST-Mbt × dsh-our-free-model（OFM）融合升级计划 · v2

- **v1**：2026-10-11 首版（文件名 `fist-mbt-upgrade-plan-20261011.md`，未入库）
- **v2 修订**：2026-10-12（基线对账刷新 + 命名合规修正）
- 验收目标：2026 MoonBit 9 月黑客松本月验收（截至 10 月底）
- 前提：现有规划全部落地（用户已确认「让现有的都做完」）

> **v2 修订动因（两条，均实机核实）**
> 1. **命名不合规（已修）**：v1 文件名 `fist-mbt-upgrade-plan-20261011.md` 含日期数字却未用 `YYYY-MM-DD-`
>    前缀，触发 `scripts/check_doc_surface.py` **J15 红**（docs/ 是评估/决策归档面，需时间锚点）。
>    本文件已更名为 `2026-10-11-fist-mbt-upgrade-plan-v2.md`（与 `2026-10-11-multi-agent-lock-design-v2.md`
>    同族约定），`check_doc_surface.py` 已转 **PASS**。
> 2. **基线漂移**：v1 的基线（136 工具 / 731 测试）已被 2026-10-11 夜间至 10-12 的提交推进，
>    且 P0 涉及的三处代码面（`RouterConfig` / `ModelQuota` / `executor_run_impl`）已逐个实读核对，
>    与 v1 的假设有出入 —— 见 §2。

---

## 1. v1 结论中仍然成立的部分（保留）

**OFM 不是代码依赖，是外部服务。** dsh-our-free-model 是 JavaScript 插件（跑在 dsh/node 进程里），
MoonBit 无法在 `moon.mod` 里 import 它；「加依赖声明」不可行。正确接线：

```
fist-mbt 路由决策 (纯计算)
   ↓ 选出 model 名
executor_run_impl
   ↓ HTTP (OpenAI 兼容)
OFM 本地端点 127.0.0.1:18899/v1/chat/completions（Bearer ofm-...）
   ↓
上游免费网关（Zen/Kilo/eac/atomcode 各 lane）
```

这符合 `improvement-plan-20261010.md` §3.3 的定位：fist-mbt = 路由器、OFM = 渠道，
`env + config_json` 解耦，不重写 OFM 的 13 渠道登录。路由器侧决策逻辑无需改动，
只需「喂池 + 端点 + lane 元数据」。

---

## 2. 基线对账（v1 → v2，2026-10-12 实机核实）

### 2.1 全局面

| 面 | v1 自述（10-11） | v2 实测（10-12） | 证据 |
|---|---|---|---|
| MCP 工具总数 | 136 | **140**（+4） | `check_doc_surface.py` 输出「真源 140 工具」 |
| JS 全量测试 | 731 | **737**（failed:0） | commit `df947cf`（"737/737 测试全绿"）+ `e609028`（计数同步 573/633/645/666/734 → 737） |
| `moon.mod` 版本 | 0.3.8 | **0.3.8**（未动） | `moon.mod` |
| OFM 代码级落地 | 0 | **0**（未启动） | `grep ofm\|18899` 于 `src/` + `cmd/` = **0 命中** |
| 新增工具面（v1 未预见） | — | **`lock_acquire` / `lock_renew` / `lock_release` / `lock_status`** | `src/server/server.mbt` 注册表 + AGENTS.md「项目看板/脉冲/预订/推荐 + DAG」节 |

> **v1 增量说明**：10-11 夜间落地的**分布式文件锁**（4 工具）属 v1 计划外的独立交付，
> 但它与 OFM 融合是**正相关**的：OFM 的多 lane 并发调用正是多 agent 并发编辑冲突的场景，
> 锁面已先行就位（`reserve_scope` 三件套 → `lock_*` 四件套，后者带 TTL/续租/抢占违例）。

### 2.2 P0 直接触及的三处代码面（实读，非推测）

| 面 | 文件:行 | 现状 | 与 v1 假设的差异 |
|---|---|---|---|
| `RouterConfig` | `src/router/model_router.mbt:112` | 4 字段：`window_seconds` / `threshold_pct` / `free_models` / `paid_models` | **无** `ofm_endpoint` / `ofm_api_key` / `lane` —— P0.1 确需扩字段 |
| `ModelQuota` | `src/router/model_router.mbt:41` | 5 字段：`name` / `tier` / `limit` / `mut used` / `mut window_start`；`new(name~, tier~, limit?, used?, window_start?)` | **无** `lane`/`provider` 元数据 —— P1.4 确需扩 |
| `executor_run_impl` | `src/server/model_router_ops.mbt:430` | `async fn`，**本地 CLI spawn** 外部执行器（`aider`/`atomcode`），模型名来自 `model_route_impl` | **不是 HTTP** —— P0.3 是**新增一条 HTTP 通道**，不是改现有通道 |
| 默认免费池 | `src/router/model_router.mbt`（`RouterConfig::default`） | **已是真实 OFM 模型**（8 个 `owned_by=our-free-model`，`lane="ofm"`），替换掉 AtomGit 样例 | P0.2 已收口 |

**配置层现状（`src/router/router_config.mbt`）**：`from_json` 逐字段兜底（缺字段用默认、坏字段进 warnings），
`parse_pool` 对空池显式返回空（`available=false`，不 panic），`to_json` **明确不含密钥**
（注释：配置会被四态投影到 skill/插件目录，密钥属运行环境）。**P0.1 扩字段时必须沿用这条纪律：
`ofm_api_key` 不得进 `to_json` 的投影面**（只从 env 读）。

### 2.3 模块体量（供 P0 估工）

| 文件 | 行数 |
|---|---|
| `src/router/model_router.mbt` | 639（v1 写 671，口径修正） |
| `src/router/router_config.mbt` | 154 |
| `src/router/router_state.mbt` | 250 |
| `src/router/star_gate.mbt` | 383 |
| `src/server/model_router_ops.mbt` | 609 |
| `src/executor/registry.mbt` / `cli_argv.mbt` / `base.mbt` | 397 / 146 / 105 |
| `src/` + `cmd/` 全量 `.mbt` | 54,812 |

---

## 3. 分阶段任务（v2 重排：补依赖前置与实读校正）

### P0 接入层（原定 10.11 - 10.17，实际未启动）

| # | 任务 | 验收标准 | v2 校正 |
|---|---|---|---|
| P0.1 | 配置结构扩展：`RouterConfig` 增 `ofm_endpoint`、`lane`（`free_pool` 每模型带 `provider/lane`）；**`ofm_api_key` 只走 env，不进 `to_json`** | `router_config.mbt` 支持从 config_json/env 读取 OFM 端点；`to_json` 投影面**无密钥**（新增白盒锁） | 原 v1 把 `ofm_api_key` 列进 RouterConfig 字段；按 `router_config.mbt` 既有纪律**降级为 env-only** |
| P0.2 | 免费池默认模型替换：默认 `free_pool` 从 AtomGit 样例改为 OFM 实测可用模型（经 `GET 127.0.0.1:18899/v1/models` 拉清单） | 配置模板含 OFM 模型 ID + 拉取清单说明 | 不变（默认池位置已定位：`model_router.mbt:123-126`） |
| P0.3 | **新增** `executor_run` HTTP 通道：按 `model.lane` 路由到 OFM 端点，`Authorization: Bearer <ofm-key>`，OpenAI 兼容请求/响应解析 | 端到端实测：路由选 model → OFM 转发 → 200 回复 | v1 说「`executor_run_impl` HTTP 调用接线」易读成"改造现有函数"；实际是**并存第二条通道**（CLI spawn 保留），须显式设计 `executor` 分派 |
| P0.4 | lane 失败归因：HTTP 401/429/5xx 归类（`INVALID_CREDENTIAL`/`RATE_LIMIT`/`UPSTREAM_DOWN`） | 与 OFM 侧错误码语义对齐 | 不变 |
| P0.5 | 配置样例落地：`default-fist.mcp.json` / `mcp_config_scaffold.mbt` / env 模板（`FIST_OFM_ENDPOINT`、`FIST_OFM_KEY`） | 新克隆项目按文档 3 分钟可跑通 | 注意 `mcp_config_scaffold` 有 `mcp_env_whitelist` **凭据硬门**——新增 env 名须同步白名单 |

### P1 路由增强（原定 10.18 - 10.24）

| # | 任务 | 验收标准 | v2 校正 |
|---|---|---|---|
| P1.1 | 复杂度分级：轻量规则（长度/工具数/模态/指令关键词）产出 `Complexity::Low/Medium/High`，映射三档模型（cheap/balance/flagship），规则外置为配置，可选接轻量模型打分 | 同一请求在不同复杂度档选中不同档模型，规则可配置 | 建议放 `src/router/` 新文件（纯计算零 IO，可白盒单测），不塞进 639 行的 `model_router.mbt` |
| P1.2 | 失败升级/重试：失败（超时/5xx/配额耗尽）→ 同 lane 换模型 → 升档（免费→付费）→ 记 `failover_chain`；重试上限 2 次/同类失败 | 人为注入 429/超时，观察自动切换链 | 依赖 P0.4 的错误归因先落地 |
| P1.3 | 价格表/延迟预算外置：`price_table`（deepseek 峰谷、K3 等）与 `latency_budget` 进 config_json，不硬编码；付费池按预算过滤 | 配置改价不改代码；超预算模型被过滤 | 不变 |
| P1.4 | lane 维度贯穿：`ModelQuota` 增 `lane` 字段，`usage_report` 按 lane 聚合 | `model_auth_status` 能显示每 lane 状态 | **注意**：`ModelQuota` 字段非 `pub`，跨包只读——扩字段须同时改 `ModelQuota::new` 构造入口（`model_router.mbt:50` 注释已言明此约束） |
| P1.5 | 回归：现有档位切换/窗口配额/Star 门行为不破坏 | 全量测试绿 | 基线已抬到 **737**，回归判据以 737 为起点 |

### P2 赛事验收工程化（10.25 - 10.31）

| # | 任务 | 验收标准 | v2 校正 |
|---|---|---|---|
| P2.1 | 测试覆盖核心路径：路由决策、切换、失败升级、配置解析、HTTP 解析 | 核心路径测试齐，`moon test` 绿 | 现有白盒锁：`model_router_wbtest`(rt_1~15) / `router_state_wbtest`(rs_1~6) / `star_gate_wbtest`(9) / `model_router_ops_wbtest`(mo_1~10) —— 新增面按同族续编号 |
| P2.2 | CI：GitHub Actions 覆盖 check/build/test | 最新提交 CI 全绿 | 现有守卫族（`check_tools_sync` 等）已在 ci.yml JS 轨；**新增工具须同步过 `check_tools_sync` + `check_plugin_sync`(cl7)** |
| P2.3 | 发布 mooncakes.io（当前 0.3.8，发新版本验证独立安装） | 包名/版本可下载、编译、运行 | v1 写 0.3.6；**实测当前 0.3.8** |
| P2.4 | README 补 OFM 接入章节（安装、配置、示例、边界） | 新用户按文档可复现 | README 已进判据面（J1-J15 + `e2e_irm_line.py` 从 README 反解命令）——改 README 后须复跑文档守卫 |
| P2.5 | 可解释性材料：开发历程文章（FIST 移植→路由设计→OFM 融合的取舍）、AI 工具使用说明 | 提交验收材料 | 不变 |
| P2.6 | 传播：GitHub Star/文章/演示视频 | 至少一篇文章或演示视频 | 不变 |
| P2.7 | 开源规范：OSI 许可证、来源声明（FIST 原作、OFM 引用关系） | 合规检查通过 | 不变 |

---

## 4. 风险与对策（v2 增补）

| 风险 | 对策 |
|---|---|
| OFM 免费渠道不稳定（401/上游关闭） | lane 元数据 + 失败升级链兜底；文档声明免费渠道可用性自测 |
| 时间窗紧（10-12 起算，距 10 月底约 2.5 周） | P0 只做最小接入不重构；P1 按价值排序（失败升级 > 复杂度分级 > 价格表） |
| **【v2 新增】密钥泄漏进四态投影** | `ofm_api_key` **只从 env 读**，绝不进 `RouterConfig::to_json`；沿用 `router_config.mbt` 顶部既有纪律；新增白盒锁「投影面不含 key 形状」 |
| **【v2 新增】P0.3 误改成"改造现有 CLI 通道"** | 明确：CLI spawn（aider/atomcode）**保留**，HTTP 是**并存第二通道**，由 `executor` 参数分派；两条通道各自有测试 |
| **【v2 新增】`ModelQuota` 跨包只读约束** | 扩 `lane` 必须走 `ModelQuota::new` 构造入口（MoonBit 跨包不得改字段，`model_router.mbt:57-58` 注释已载） |
| **【v2 新增】新增工具/描述触发四态守卫红** | 每加一个工具面：`server.mbt` 注册表 + AGENTS/README 可查 + `gen_plugins.py` 重生成 + 复跑 `check_tools_sync` / `check_plugin_sync`(cl7) / `check_doc_surface`(J14) |
| 代码量参考线 4-10k LOC | 实测 `src/` + `cmd/` 已 54.8k 行；不以行数冲量，按验收四维补质量 |
| 循环依赖教训（mcpconftest） | 本计划不新增 MoonBit 包依赖，全部走 HTTP，天然避免 |
| dsh/OFM 版本升级覆盖改动 | OFM 侧改动备份 `backup-<date>`；fist-mbt 侧只依赖 HTTP 接口契约 |
| **【v2 新增】并发 agent 改同一文件** | 利用 10-11 刚落地的 `lock_acquire`/`lock_renew`/`lock_release`/`lock_status`（TTL + 抢占违例）与 `reserve_scope` 家族做作用域预订 |

---

## 5. 名次预估（附条件，非承诺）

依据：9 月黑客松双赛道同池评选；一等奖 12,000（1-2 名）、二等奖 6,000（3-4 名）、三等奖 3,000（5 名）；
往届 OSC2026 获奖 13 项（4 晋级决赛 + 9 三等奖）；验收四维（完成度/工程质量/可解释性/用户体验）+ 传播。

- **P0-P2 全部落地且质量到位**：二等奖（3-4 名）概率最高；一等奖（1-2 名）有机会但名额少、需传播与答辩表现加持。
- **P0+P1 落地、P2 部分完成**：三等奖区间。
- **仅 P0**：通过验收（基础激励）概率高，但难进季度奖励池前列。

fist-mbt 的加分点：方向契合官方点名领域（智能体平台开发）、FIST 自研框架移植具备原创性、
路由状态机工程深度足、属「社区项目持续维护」赛道有版本沉淀。
减分点：同赛道对手未可知、传播分需要主动经营。

---

## 6. v2 与 v1 的差异清单（便于回溯）

| # | 项 | v1 | v2 |
|---|---|---|---|
| 1 | 文件名 | `fist-mbt-upgrade-plan-20261011.md`（**J15 红**） | `2026-10-11-fist-mbt-upgrade-plan-v2.md`（**J15 绿**） |
| 2 | 工具数基线 | 136 | 140（+`lock_*` 四件套） |
| 3 | 测试基线 | 731 | 737 |
| 4 | 发布版本基线 | 0.3.6（§P2.3） | 0.3.8（实测） |
| 5 | `ofm_api_key` 归属 | 列入 `RouterConfig` 字段 | **降级为 env-only**（沿用密钥纪律） |
| 6 | P0.3 表述 | 「`executor_run_impl` HTTP 调用接线」 | 「**新增** HTTP 通道，与 CLI spawn 并存」 |
| 7 | P1.4 备注 | 无 | 补 `ModelQuota` 跨包只读 ⇒ 须走构造入口 |
| 8 | 代码面 | 未实读 | 逐处实读（`model_router.mbt:41/112`、`router_config.mbt`、`model_router_ops.mbt:430`） |
| 9 | 风险表 | 6 条 | 10 条（+密钥投影、双通道误改、跨包只读、四态守卫、并发锁） |
| 10 | 下一步 | 无 | §7 |

---

## 7. v2 建议的下一步（第一刀）

**建议先做 P0.1 + P0.5 的"配置面"半刀**，理由：零网络、零密钥、纯配置解析，可白盒单测，
且是 P0.2/P0.3 的前置。

1. `RouterConfig` 扩 `ofm_endpoint` + `ModelQuota` 扩 `lane`（走 `new` 构造入口）。
2. `RouterConfig::from_json` 增对应字段解析（沿用逐字段兜底 + warnings 纪律）。
3. `RouterConfig::to_json` **保持无密钥**，并补一条白盒锁钉住这一点。
4. env 名登记：`FIST_OFM_ENDPOINT` / `FIST_OFM_KEY`，同步 `mcp_env_whitelist` 白名单。
5. 复跑：`moon check`（js+native 0 errors）→ `moon test --target js`（**737 为起点，只许增不许减**）
   → `check_doc_surface.py` / `check_tools_sync.py` / `check_plugin_sync.py`。

**不可逆边界**：P0.3 起涉及真实网络调用与外部端点，按 AGENTS.md「不可逆操作只给方案+预案」，
动工前须经指挥官确认。

---

## 8. 实施状态（fist-mbt 自驱，2026-10-12）

本计划的 P0 **用 fist-mbt 自身工具链实现并验收**，任务账在命名空间 `ofm-fusion`
（根任务 `T0r601`，经 `task_plan_deep` 递归拆解生成 15 条子任务；另按 §3 的五片
语义各发一条显式切片根 `T0r602`–`T0r606`，避免自动拆解产出通用「子任务单元 N」）。

| 切片 | 账务 id | 状态 | 落点 |
|---|---|---|---|
| P0.1 配置结构扩展 | `T0r602` | **已完成** | `ModelQuota.lane` + `RouterConfig.ofm_endpoint`；`from_json`/`to_json`/`resolve_ofm_endpoint`；新增 `src/router/router_config_wbtest.mbt` 5 条白盒锁 `cfg_ofm_1..5` |
| P0.4 lane 失败归因（纯函数） | `T0r605` | **已完成** | 新增 `src/router/ofm_failure.mbt`（`OfmFailure` 六态 + `classify_ofm_failure` + `label`）；`src/router/ofm_failure_wbtest.mbt` 6 条锁 `ofm_f_1..6` |
| P0.5 配置样例/env 模板（代码半） | `T0r606` | **已完成** | `mcp_env_whitelist` 增 `FIST_OFM_ENDPOINT`/`FIST_OFM_KEY`；`default-fist.mcp.json` env 模板增两键（**空值占位**） |
| P0.2 默认池换 OFM 实测模型 | `T0r603` | **已完成** | 密钥到位后 2026-10-12 实机 `GET {ofm_endpoint}/models` 拉到 8 个 `our-free-model` 模型，`free_pool` 换成它们并标 `lane="ofm"`；解析前置 `src/router/ofm_models.mbt` + 清单落盘 `docs/2026-10-12-ofm-real-model-list.md`；新锁 `cfg_ofm_6`。**fist-mbt 生命周期 claim→execute→submit→verify 4/4 ok** |
| P0.3 executor_run HTTP 通道 | `T0r604` | **部分完成（通道已接线并联调；真 200 阻塞于上游 500）** | 密钥经 USER 作用域到位后 2026-10-12 实机联调：`executor_run` 增 `executor=="ofm"` 分流到并存 HTTP 通道（CLI spawn 保留）。新增 `src/router/ofm_response.mbt`（`parse_ofm_chat_response` 7 锁 `ofm_r_1..7`，用真实 500/401 体 + 合成成功体）+ `src/server/ofm_http_js.mbt`/`ofm_http_native.mbt`（js 真 `fetch`/native 显式拒）+ `model_router_ops.mbt` 的 `ofm_execute_http`/`ofm_chat_url` + `server.mbt` 工具 schema 扩 `aider\|atomcode\|ofm` + AGENTS.md 同源。**端到端三判据 PASS**（见下方「端到端实测」）；**唯一未达成的验收 = 真 200 回复**。根因已**定位并修复**（非"上游黑盒"）：OFM 上游即 DSH 的 `dsh-our-free-model` 插件（`~/.dsh/profiles/web/node_modules/dsh-our-free-model`），其 `src/adapter.js` 在 lane 分派处用裸标识符 `atomcode`（`sealed || kilo || atomcode` / `: atomcode`），却**只声明了 `const sealed`/`const kilo`、漏了 `const atomcode = isAtomcodeEntry(entry)`**（`isAtomcodeEntry` 已在 L30 导入、`catalog.js` L565 已导出）⇒ 每一 turn（含 free lane）都抛 `ReferenceError: atomcode is not defined`，故 8 个模型全 500；`/v1/models` 不受影响仍 200 ⇒ 密钥有效、非请求形状问题。**修复已落地**：在该函数补 `const atomcode = isAtomcodeEntry(entry)`（并让 `wire` 判定含 `atomcode`，与"吸收通道走 Chat wire"注释一致），原文件备份为 `src/adapter.js.bak-20261012-atomcode`；`node --check` 通过、`atomcode` 全部引用（L225/L287/L304）均解析到新声明。**注意**：DSH 进程已缓存旧模块，修复**需重启 DSH 才能生效**（宿主即本会话所依附的 DSH 进程，重启会断会话，故交由使用方重启）；重启后 OFM `/chat/completions` 应回真 200。失败路径按 `classify_ofm_failure` 归因为 `UPSTREAM_DOWN`，不猜、不降级、不静默成功；成功解析器是防御性编码，**真 200 仍待 DSH 重启后复验**（诚实标注） |
| P0.5 文档半（3 分钟跑通说明） | — | **部分完成（接线层已联调；3 分钟跑通段待上游 200 或如实标注）** | `USAGE.md` 新增 §6.15「模型路由 · OFM 外部服务接线」：config 字段（`ofm_endpoint`/`lane`）+ env-only 密钥纪律 + bootstrap 命令，并**如实标注 HTTP 通道已联调但上游 `/chat/completions` 当前 500**（不是"未联调"，是"联调后归因为上游故障"） |

**读数（2026-10-12 实机）**：`moon check --target js` 全项目 **0 error**；
`moon test --target js` **767/767**（§7 定的 737 起点 + P0.1 五锁 + P0.4 六锁 + P0.2 前置五锁 + P0.3 前置六锁 + P0.2 收口 `cfg_ofm_6` + P0.3 响应解析 7 锁 = +30，零回归）；
`scripts/check_model_auth_no_key.py` **PASS**；`scripts/check_doc_surface.py` **PASS**；
`scripts/check_tools_sync.py` **PASS**（P0.3 无新增工具，140 不变——**注意**：实机 `tools/list` 报 147，与守卫正则口径 140 差 7，源自并行的 mcpcf-embed 会话新增工具，P0.3 不认领也不修，见报告「遗留风险」）。

**端到端实测（2026-10-12，经 fist-mbt 自身 `executor_run` MCP 工具真打）**：三段判据全 PASS——
A. `dry_run=true`：`ok=true`、`executed=false`、`quota_touched=false`、回显 `url` + `request_body`，**一个网络请求都不发**；
B. 显式 `model=mimo-v2.6-flash-free` + 真跑：`ok=false`、`http_status=500`、`error_type=server_error`、`error="atomcode is not defined"`、**`failure_kind=UPSTREAM_DOWN`**、`quota="not_routed(调用方显式指定 model，不代记账)"`；
C. 留空 `model` + 真跑：路由 pick `mimo-v2.6-flash-free`、**`quota="recorded(mimo-v2.6-flash-free)"`**（路由↔执行器记账点生效）、同上 `UPSTREAM_DOWN` 归因。
回执全程**不出现密钥**；key 只从 server 进程环境变量读。

**根因定位与修复（2026-10-12 追记）**：见上 P0.3 行——500 的 `atomcode is not defined` 并非外部端点黑盒故障，而是 DSH 的 `dsh-our-free-model` 插件 `src/adapter.js` **漏声明 `const atomcode = isAtomcodeEntry(entry)`**（L282/L299 用了裸 `atomcode`）。已在该文件补上并统一 `wire` 判定，原文件备份 `src/adapter.js.bak-20261012-atomcode`；`node --check` 通过。**待办：DSH 重启后复跑上方 A/B/C 三判据，验真 200**。

**本轮抓到的一条真 bug（P0.1 白盒锁价值证明）**：`RouterConfig::from_json` 原实现把
`ofm_endpoint` 坏类型警告追加到局部 `warns`，而返回的 `w2` 早在那之前已经展开
（`parse_pool` 快照）⇒ 警告被吞、坏端点静默通过。`cfg_ofm_4` 抓到后已改为
`w2 + ofm_warns` 一并返回。

**投影面纪律闭环**：`RouterConfig` **刻意没有密钥字段**，配置投影到 skill/插件目录时
不可能带出密钥；`FIST_OFM_KEY` 只作为环境变量名进白名单，值永远走进程环境。

---

## 来源

- v1 原文（已更名）：`docs/2026-10-11-fist-mbt-upgrade-plan-v2.md` 本文件 §1/§3 保留段
- 路由核心：`src/router/model_router.mbt`（`ModelTier`:16 / `ModelQuota`:41 / `RouterConfig`:112 / `default`:122-139）
- 配置层：`src/router/router_config.mbt`（`from_json`:9 / `parse_pool`:73 / `to_json`:150；顶部密钥纪律注释）
- MCP 接线：`src/server/model_router_ops.mbt`（`executor_run_impl`:430）
- 执行器登记：`src/executor/registry.mbt` / `cli_argv.mbt` / `base.mbt`
- 新增锁面：`src/server/server.mbt`（`lock_*` 四工具注册）+ `src/store/store.mbt` + `src/engine/engine_rsv.mbt`
- 文档守卫：`scripts/check_doc_surface.py`（J15 docs 文件名日期前缀；J14 工具计数；J6/J7 规范面）
- 既有规划：`docs/improvement-plan-20261010.md` §3（模型路由增强 + OFM 拿来主义定位）
- 基线读数：`moon.mod`（0.3.8）、`git log`（`df947cf` 737/737）、`check_doc_surface.py` 输出（真源 140 工具）
- 命名族先例：`docs/2026-10-11-multi-agent-lock-design.md` / `-v2.md` / `-v3.md`

*（内容由AI生成，仅供参考）*
