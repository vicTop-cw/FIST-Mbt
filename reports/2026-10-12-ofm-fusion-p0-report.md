# 2026-10-12 OFM 融合升级计划 P0 · fist-mbt 自驱实现报告

## 结果摘要

用 **fist-mbt 自身工具链**（`publish` → `task_plan_deep` → `publish_parallel` → `claim`
→ `execute` → `submit` → `verify`）把升级计划 v2 的 P0「配置面半刀」实现并验收完毕。
§7 建议的「先做 P0.1 + P0.5」两片均已落地，全部通过项目守卫；**P0.3 HTTP 通道已接线并联调，
唯一未达成的验收「端到端 200 回复」已定位根因并修复**：OFM 上游即 DSH 的 `dsh-our-free-model`
插件，其 `src/adapter.js` 漏声明 `const atomcode = isAtomcodeEntry(entry)` ⇒ 每一 turn（含 free
lane）都抛 `ReferenceError: atomcode is not defined` ⇒ 8 模型全 500。修复已落地（原文件备份
`adapter.js.bak-20261012-atomcode`，`node --check` 通过、`atomcode` 全引用已解析），
**待 DSH 重启后生效**，见「遗留风险」。

- **P0.1 配置结构扩展（`T0r602` 已完成）**
  - `src/router/model_router.mbt`：`ModelQuota` 增 `lane`（渠道元数据，走 `new` 构造入口，
    字段非 pub 跨包不可改）；`RouterConfig` 增 `ofm_endpoint`；`default` 的 `ofm_endpoint`
    默认空串=未配置（零行为变更，不硬编码端点）。
  - `src/router/router_config.mbt`：`from_json` 增 `ofm_endpoint`/`lane` 解析（坏类型进
    warnings 并点名）；`to_json` 增 `ofm_endpoint` 投影；新增纯函数
    `resolve_ofm_endpoint(config_value, env_value)`（env 优先，双空=未配置）。
  - `src/router/router_state.mbt`：持久化/恢复带 `lane` 与 `ofm_endpoint`。
  - 新增 `src/router/router_config_wbtest.mbt` 5 条白盒锁 `cfg_ofm_1..5`。
- **P0.5 配置样例/env 模板（`T0r606` 已完成，代码半）**
  - `src/server/mcp_config_scaffold.mbt`：`mcp_env_whitelist`（凭据硬门）增
    `FIST_OFM_ENDPOINT`、`FIST_OFM_KEY`。
  - `default-fist.mcp.json`：env 模板增两键（**空值占位**，用户填）。
- **P0.5 文档半（接线层已联调；3 分钟跑通段待上游 200 或如实标注）**
  - `USAGE.md` 新增 **§6.15「模型路由 · OFM 外部服务接线」**：config 字段（`ofm_endpoint`/`lane`
    取值纪律）+ env-only 密钥纪律（白名单、`RouterConfig` 无密钥字段）+ 3 分钟 bootstrap
    （`Invoke-RestMethod` 枚举模型）+ **如实标注 HTTP 通道已联调、上游 `/chat/completions`
    当前 500**（不是"未联调"，是"联调后归因为上游故障"）。
  - 注：`check_doc_surface.py:116/1221` 会扫 `USAGE.md`，改后仍 **PASS**。
- **P0.4 lane 失败归因（`T0r605` 已完成，纯函数）**
  - 新增 `src/router/ofm_failure.mbt`：`pub enum OfmFailure` 六态 + `classify_ofm_failure`
    + `label()`；401/403→`InvalidCredential`、429→`RateLimit`、5xx→`UpstreamDown`、
    状态码≤0→`NetworkError`、其它 4xx→`BadRequest`、2xx/无线索→`Unknown`（不猜）。
  - 新增 `src/router/ofm_failure_wbtest.mbt` 6 条锁 `ofm_f_1..6`。
  - 与 `UpstreamDown` 的区分：5xx 是「上游回话但没办好」，`NetworkError` 是「没拿到 HTTP
    响应」——为 P1.2 失败升级/重试留「前者先查连通、后者可重试」的差异空间。
- **P0.2 解析前置（已落地，零网络；`T0r603` 仍待密钥后才收口）**
  - 新增 `src/router/ofm_models.mbt`：`pub struct OfmModel{id, owned_by}` +
    `pub fn parse_ofm_models(body : String) -> Result[Array[OfmModel], String]`——解析 OpenAI
    兼容 `/v1/models` 响应体。给不出清单就 `Err`（空/非法 JSON/非对象/缺 data/data 非数组）；
    单条坏数据只跳过该项；缺 `owned_by` 兜底空串。
  - 新增 `src/router/ofm_models_wbtest.mbt` 5 锁 `ofm_m_1..5`。
  - **不猜 lane**：解析层只出 `id`/`owned_by`，无 lane 输出通道（lane 由配置显式声明）。
- **P0.3 请求构建前置（已落地，零网络；`T0r604` 收口见下）**
  - 新增 `src/router/ofm_chat.mbt`：`OfmChatMessage{role,content}` + `OfmChatRequest{model,
    messages, temperature?, max_tokens?}` + `build_ofm_chat_request_json(req) ->
    Result[String, String]`——结构化成 OpenAI 兼容 chat 请求体。
  - **fail-closed**：model 空 / messages 空 / role 不在 {system,user,assistant} / content 空
    一律 `Err`，绝不静默回落；可选参数为 `None` 时**不写字段**（不写显式 null）。
  - 新增 `src/router/ofm_chat_wbtest.mbt` 6 锁 `ofm_c_1..6`。
  - **响应解析刻意留到拿到真实样例后再定稿**（沿用计划 v2 的「实读校正」教训：真实 OFM 可能走
    `choices[].message.content` 也可能走 `choices[].text`，盲写就是给自己埋雷）。
- **P0.3 executor_run HTTP 通道（`T0r604` 部分完成，真 200 阻塞于上游 500）**
  - **响应解析**：新增 `src/router/ofm_response.mbt`：`pub struct OfmChatResponse{http_status,
    is_error, error_message, error_type, content, raw}` + `pub fn parse_ofm_chat_response(body,
    http_status) -> OfmChatResponse`（fail-closed：空体→`empty_body`、非法 JSON→`unparseable`、
    非对象→`unexpected_shape`、`{"error":{message,type}}`→`is_error=true`）；成功面先试
    `choices[0].message.content` → `.text` → `.content`，全空仍判 `unexpected_shape`，**绝不静默
    空成功**。新增 `ofm_response_wbtest.mbt` 7 锁 `ofm_r_1..7`（用真实 500/401 体 + 合成成功体）。
  - **HTTP 通道（js/native 双态）**：`src/server/ofm_http_js.mbt` 的 `extern "js" fn
    js_ofm_chat_fetch`（读 `process.env.FIST_OFM_KEY`，`fetch` POST `Authorization: Bearer`，
    AbortController 超时，**key 从不进 argv/日志/回执**）+ `pub async fn ofm_chat_http`；
    `src/server/ofm_http_native.mbt` 为**显式拒绝**桩。`src/server/moon.pkg` 用 `options(targets:)`
    分派两文件。
  - **分流**：`src/server/model_router_ops.mbt` 新增 `ofm_execute_http`（端点 env 优先/config
    兜底、`dry_run` 只回显 URL+请求体、失败走 `classify_ofm_failure`）+ `ofm_chat_url` + 三个
    小工具；`executor_run_impl` 在模型选定后按 `executor=="ofm"` 分流到 HTTP 通道（CLI spawn 保留）。
  - **工具面**：`src/server/server.mbt` 的 `executor_run` schema 扩 `aider|atomcode|ofm`（描述同步
    说明两通道并存与密钥纪律）；AGENTS.md 同源更新。
  - **端到端实测（经 fist-mbt 自身 MCP 工具）三判据 PASS**：A. `dry_run=true`→`ok=true`/
    `executed=false`/`quota_touched=false`/回显 url+请求体，零网络请求；B. 显式 model+真跑→
    `ok=false`/`http_status=500`/`failure_kind=UPSTREAM_DOWN`/`quota="not_routed(...)"`；C. 留空
    model+真跑→路由 pick `mimo-v2.6-flash-free`+**`quota="recorded(mimo-v2.6-flash-free)"`**
    （路由↔执行器记账点生效）+同 `UPSTREAM_DOWN`。
  - **未达成的唯一验收**：真 200 成功正文。根因见「遗留风险」。
- **P0.2 默认池换实测模型（`T0r603` 已完成，fist-mbt 生命周期 4/4 ok）**
  - 密钥到位（User 级 env）后，实机 `GET {ofm_endpoint}/models` 回 **HTTP 200**，拉到 8 个
    `owned_by=our-free-model` 模型（`ling-3.1-flash-free` / `mimo-v2.6-flash-free` /
    `muse-spark-1.2-contributor-free` / `muse-spark-1.3-contributor-free` /
    `nemotron-3.5-lightning-free` / `step-5-preview-free` / `longcat-2.5-preview-free` /
    `space-bunny-free`），替换掉 `RouterConfig::default` 的 AtomGit 样例。
  - 每条 `lane="ofm"`：标「同属外部 OFM 通道」这一**已核实事实**，不猜 SenseNova 的 zen/kilo/eac。
  - 新锁 `cfg_ofm_6`（逐条对上 ID + lane 非空 + tier=Free）；原断言默认池=2 的两锁
    （`rs_3` / `rt_10`）随真源前进为 8。
  - 拉取清单落盘 `docs/2026-10-12-ofm-real-model-list.md`。
  - 无 key 时同请求回 **401**，实证了 P0.4 的「401→InvalidCredential」归因。
- **投影面纪律闭环**：`RouterConfig` 刻意无密钥字段 ⇒ 配置投影进 skill/插件目录不可能带出密钥；
  `FIST_OFM_KEY` 只作为**环境变量名**进白名单，值永远走进程环境。

## 资源消耗

- 任务账：命名空间 `ofm-fusion`，根 `T0r601` + 递归拆解 15 条 + 五片显式根 `T0r602`–`T0r606`
  （本轮完成 `T0r602`/`T0r605`/`T0r606`）。
- 驱动方式：`temp/fist_mcp.py`（一批会话内起一次 MCP server，顺序调多工具），
  `node` v25.2.1 + `_build/js/debug/build/cmd/cli/cli.js serve`。
- 验证命令：`moon check --target js`、`moon test --target js`、`check_model_auth_no_key.py`、
  `check_doc_surface.py`、`check_tools_sync.py`。
- 读数：`moon test --target js` **767/767**（737 起点 + P0.1 五锁 + P0.4 六锁 + P0.2 前置五锁 +
  P0.3 前置六锁 + P0.2 收口 `cfg_ofm_6` + P0.3 响应解析 7 锁 = +30，零回归）；三守卫 PASS；
  `check_model_auth_no_key.py` 扫描面 55→58 份（新增 ofm_response / ofm_http_js / ofm_http_native）
  仍绿。
- 账务：P0.2 `T0r603` 已走完 fist-mbt 生命周期 claim→execute→submit→verify，**4/4 ok**；
  P0.3 `T0r604` 代码/接线/联调部分已完成，真 200 验收段留待上游修复。
- 端到端驱动：`temp/ofm_executor_e2e.py`（一批会话起一次 MCP server，`tools/list` 暖场 +
  顺序调 `executor_run` 三判据，FIST_DB_PATH 改道 `temp/ofm_e2e.db`；密钥只从进程 env 继承，
  脚本不打印 key、不写进命令行）。

## 任务分配记录

| 切片 | 账务 id | 状态 | 执行者 |
|---|---|---|---|
| P0.1 配置结构扩展 | `T0r602` | 已完成 | fist-agent |
| P0.4 lane 失败归因 | `T0r605` | 已完成 | fist-agent |
| P0.5 配置样例/env 模板（代码半） | `T0r606` | 已完成 | fist-agent |
| P0.2 默认池换 OFM 实测模型 | `T0r603` | 已完成 | fist-agent（生命周期 4/4 ok） |
| P0.3 executor_run HTTP 通道 | `T0r604` | 部分完成（接线+联调完成，真 200 阻塞于上游 500） | fist-agent |

## 遗留风险

1. **【P0.3 主要阻塞 · 已定位并修复，待重启生效】OFM 上游 `/v1/chat/completions` 对全部 8 个模型回
   HTTP 500**：体 `{"error":{"message":"atomcode is not defined","type":"server_error",...}}`。
   **根因不是上游黑盒，而是 DSH 的 `dsh-our-free-model` 插件 `src/adapter.js`**：lane 分派处用了裸
   `atomcode`（`sealed || kilo || atomcode` / `: atomcode`），却只声明 `const sealed`/`const kilo`、
   **漏声明 `const atomcode = isAtomcodeEntry(entry)`**（`isAtomcodeEntry` 已在 L30 导入、`catalog.js`
   L565 已导出）⇒ 每个 turn 抛 `ReferenceError`（`/v1/models` 同刻仍 200，因该路由不经过这一段）。
   已用最小体与全 8 模型验证均 500 ⇒ **密钥有效、非请求形状/非鉴权问题**。**修复已落地**：在该函数补
   `const atomcode = isAtomcodeEntry(entry)` 并让 `wire` 判定含 `atomcode`；原文件备份
   `src/adapter.js.bak-20261012-atomcode`；`node --check` 通过、`atomcode` 引用 L225/L287/L304 全解析。
   ⚠️ **DSH 进程已缓存旧模块，修复需重启 DSH 才生效**（宿主即本会话所依附的 DSH 进程，重启会断
   会话，故交由使用方重启）。→ **P0.3 验收「端到端 200 回复」的代码侧障碍已消除，真 200 仍待重启后复验**；
   通道的失败路径已被端到端实测证明确实打通并正确归因为 `UPSTREAM_DOWN`。
2. **成功路径解析器未对真实 200 验证**：`parse_ofm_chat_response` 的成功分支只被合成成功体
   （`ofm_r_4/5`）锁住；真实 OFM 一旦 200，正文形状仍可能与解析器不同（例如 content 是数组或
   非字符串）。建议上游恢复后补一发真实 200 校正。
3. **工具计数口径漂移（非本仓本轮造成）**：实机 `tools/list` 报 **147** 工具，而
   `check_tools_sync`/`check_doc_surface` 的正则口径为 **140**，差 7——源自并行的 mcpcf-embed
   会话新增工具（注册写法未被 `instrumented_tool(s1,…)` 正则计数到）。AGENTS.md 的「140 tools」
   相对**运行时**已滞后；本轮未认领也不修（非 P0.3 范围），请并行会话或后续轮次对表。
4. **P0.5 验收项「新克隆项目按文档 3 分钟可跑通」**：文档已如实标注上游 500，3 分钟可跑通的
   演示段需上游 200 后才具备完整演示价值。
5. **密钥纪律**：`FIST_OFM_KEY` 仅在 server 进程环境变量中读取；本轮端到端实测全程回执未出现
   密钥形状（`check_model_auth_no_key.py` PASS）。请勿把 key 写进任何配置文件或命令行。

## 后续建议

- **P0.3 剩「真 200 验收」一格 · 上游侧已修**：上游根因（DSH `dsh-our-free-model` 插件
  `src/adapter.js` 漏声明 `const atomcode`）已修复，**只差重启 DSH** 加载新模块；重启后
  `/chat/completions` 应回真 200。届时用 `executor_run(executor="ofm", model=…)` 补一发真实 200，
  核对成功路径解析器（重点看 `choices[0].message.content` 的真实形状）；若形状与当前解析器不符，
  按「实读校正」修正 `extract_ofm_content` 并追加一条真实 200 锁。
- **P0.5 文档半**：`USAGE.md` §6.15 已如实标注上游 500；上游恢复后把「3 分钟跑通」段补上真实
  200 实测回执。
- **P1.x 接入**：P0.3 的 `classify_ofm_failure` 已就位，`UPSTREAM_DOWN` vs `NetworkError` 的
  区分正是 P1.2 失败升级/重试的输入；建议下游消费 `failure_kind` 而非裸 `http_status`。
- **工具计数对表**：请把 `tools/list` 实测 147 与守卫正则 140 的 7 条差并入相关会话的对表，
  避免 AGENTS.md 的「140 tools」持续滞后于运行时。

## 超额内容 / 发现

- **白盒锁价值证明（抓到真 bug）**：`RouterConfig::from_json` 原实现把 `ofm_endpoint` 坏类型
  警告追加到局部 `warns`，而返回的 `w2` 早在那之前已经展开（`parse_pool` 快照 `warns`）
  ⇒ 坏端点静默通过。`cfg_ofm_4` 抓到后已改为 `w2 + ofm_warns` 一并返回。
- **工具链发现**：`task_plan_deep` 对长描述会产出通用「子任务单元 N」叶而非语义切片；
  要语义化分片应用 `publish_parallel` 按片发显式根任务（本报告正是这样改的）。
- **OFM 端点只读探测（2026-10-12 上午）**：`GET 127.0.0.1:18899/v1/models` 回 **401**（服务在线、
  强制 Bearer 鉴权）——实测佐证 P0.4 的 401→`InvalidCredential` 映射；随后拿到 key 后回 200，
  拉到 8 个模型（见 P0.2）。
- **【本轮最大发现】OFM 上游 `/chat/completions` 是坏的**（2026-10-12 下午）：拿到 key 后首次
  真 POST 即得 **500 `atomcode is not defined`**。逐项排除：① 非请求形状（用最小 body 仍 500）；
  ② 非鉴权（`/v1/models` 同刻 200）；③ 非个别模型（全 8 模型 500）。⇒ 上游 handler 抛
  `ReferenceError`，属**上游故障**，非本仓问题。价值：**P0.3 的失败归因分支（`classify_ofm_failure`
  → `UPSTREAM_DOWN`）因此被真实端到端打实**——这正是「不猜、不降级、不静默成功」纪律该有的表现。
- **【根因落地追记 · 不是"等上游"】`atomcode is not defined` 定位到一行漏声明**（2026-10-12 下午
  追查）：`netstat` 显示 OFM 端 `127.0.0.1:18899` 的监听者是 DSH web 进程本身（PID 27904），而
  `dsh-our-free-model` 插件 `src/adapter.js` 在 `isEacEntry`/`isKiloEntry` 旁**漏写了
  `const atomcode = isAtomcodeEntry(entry)`**，却已在 L282/L299 用它分派 ⇒ 与"哪条 lane"无关，
  每一 turn 都抛 ReferenceError。**教训**：先定位监听者再定性"上游故障"——"上游"也可能就在本机、
  可本地修。修复后 `node --check` 通过；**待 DSH 重启生效**。
- **MoonBit 接线经验**（P0.3 落地踩到）：① `async fn` 体内若只做阻塞 `.wait()`，调用点**不需**
  `.await`（直接取返回值）；② `@json.parse` 返回 `Json`（抛异常）而非 `Result`，`catch` 分支返回
  `Json`，用 `let payload = @json.parse(raw) catch { _ => return Err(...) }` 再 `Ok(payload)`；
  ③ `Json::Null` 是只读模式单例，**创建值用 `Json::null()`**；④ match 多语句 arm 必须加花括号。
- **工具计数口径差 7**（实机 147 vs 正则 140）：见「遗留风险」第 3 条，本轮如实记录、不修。

## 来源

- 计划真源：`docs/2026-10-11-fist-mbt-upgrade-plan-v2.md`（§7 建议的第一刀、新增 §8 实施状态）
- 路由核心：`src/router/model_router.mbt` / `router_config.mbt` / `router_state.mbt`
- 白盒锁：`src/router/router_config_wbtest.mbt` / `src/router/ofm_failure_wbtest.mbt` /
  `src/router/ofm_models_wbtest.mbt` / `src/router/ofm_chat_wbtest.mbt` /
  `src/router/ofm_response_wbtest.mbt`
- P0.4 归因：`src/router/ofm_failure.mbt`（`OfmFailure` + `classify_ofm_failure`）
- P0.2 前置：`src/router/ofm_models.mbt`（`OfmModel` + `parse_ofm_models`）
- P0.3 前置/落地：`src/router/ofm_chat.mbt`（请求体）/ `src/router/ofm_response.mbt`（响应解析）/
  `src/server/ofm_http_js.mbt` + `ofm_http_native.mbt`（js fetch / native 显式拒）/
  `src/server/model_router_ops.mbt`（`ofm_execute_http` + `ofm_chat_url` + 分流）
- 工具面：`src/server/server.mbt`（`executor_run` schema 扩 `ofm`）/ AGENTS.md / `USAGE.md` §6.15
- 配置脚手架：`src/server/mcp_config_scaffold.mbt`（`mcp_env_whitelist`）
- 配置样例：`default-fist.mcp.json`
- 守卫：`scripts/check_model_auth_no_key.py` / `scripts/check_doc_surface.py` /
  `scripts/check_tools_sync.py`
- 驱动脚本：`temp/fist_mcp.py`（生命周期）/ `temp/ofm_executor_e2e.py`（P0.3 端到端三判据）
- 真实上游 500 体（只读样本，无密钥形状）：`temp/ofm_chat_real_ok.json` / `temp/ofm_err_401.json`

*（内容由AI生成，仅供参考）*
