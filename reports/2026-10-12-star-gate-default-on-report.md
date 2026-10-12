# 2026-10-12 · Star 门默认开启（发布模板带默认值）+ ofm response_format 部分容错

## 结果摘要

按 owner 裁决「默认开启 star 门（推荐）：把 `FIST_STAR_GATE_*` 默认配置带入发布模板，未 star 用户免费池保持锁定」落地，并顺带处理我上一轮提出的 ofm JSON 容错缺口。**判绿：`moon test --target js -j 1` = Total tests: 799, passed: 799, failed: 0**（基线 796 + 新增 3 条白盒锁）。

| 项 | 状态 | 证据 |
|---|---|---|
| ① Star 门默认开启 | ✅ 落地 | `temp/star_gate_probe.py` 真起 MCP server 双组对跑，A（模板公钥+无 attestation）`gate_enabled=true/free_pool_unlocked=false/model_route ok=false`（锁死）、B（不设 env）`gate_enabled=false/free_pool_unlocked=true/model_route ok=true`（零回归）——**双 PASS** |
| ② ofm `response_format=json_object` | ⚠ 部分修复 | 真模型 E2E 复跑：2/3 单元能出干净 JSON 并进 `hat_merge converged`，但每次仍有 1 个单元回「OFM 回体不是合法 JSON」；原始回体诊断确认缺口在 HTTP 层重试，非本层可修 |

### 落点选择（关键决策）

`src/router/star_gate_wbtest.mbt` mo_10（属并发会话的 `model_router_ops_wbtest.mbt`）钉死了「默认未配置 → `gate_enabled=false` 零回归」。若在 `star_gate_policy` 纯函数里翻转默认，会让并发会话的锁变红 ⇒ **不碰并发会话文件**，改为把默认值带进**发布模板 `.mcp.example.json` 的 env**（`FIST_STAR_GATE_PUBKEY_HEX`），部署态由模板把公钥带进去 → 门默认开启；本地开发态（不设 env）维持零回归开放。

## 资源消耗

- 全量 `moon test --target js -j 1` 多次（判绿用）；`moon fmt` 一次（误格式化整个 router 包，已 `git checkout` 回退到仅保留 5 个目标文件）。
- 真模型 E2E `temp/hexamind_real_run.py` 复跑 3 次（`FIST_HAT_MODEL=mimo-v2.6-flash-free`），含 1 次经 `temp/ofm_raw_proxy.py` 代理落盘原始回体。
- 网关 A/B 对照 2 次（带/不带 `response_format`）。
- 生成 Ed25519 密钥对 1 对（公钥入库，私钥只在对话交 owner）。

## 任务分配记录

本次为短链实现 + 自证，未再拆子代理：改动全部落在 `src/router`（纯计算、干净、可单测）与发布模板，无需跨模块协调；并发会话正在改 `src/server/model_router_ops.mbt` 与 `src/server/ofm_http_{js,native}.mbt`，**全程未触碰**，避免写面冲突。

## 遗留风险

1. **ofm 通道「非 JSON 二次修复重试」未做**——`src/server/ofm_http_{js,native}.mbt` 属并发会话文件。真模型 E2E 每次仍有 1/3 单元回「OFM 回体不是合法 JSON」，且原始回体诊断表明失败那次拿到的是**真·非 JSON/被截断回体**（网关偶发），`response_format` 只是弱缓解、**抓到的 golddigger content 仍是 ```json 围栏多行 JSON**（网关对 `response_format` 执行不一致）。
2. **Star 门默认公钥对应私钥未接入 CI**——需 owner 把私钥设为仓库 secret `ED25519_PRIVATE_KEY_HEX`（`attest.yml` 已用该 secret 签名、公钥由它派生，两者必须匹配）。**私钥入库前，attestation 验签不过、全员锁死**（这是默认开启的预期后果，但要让 star 用户能解锁必须完成这一步）。
3. **换钥纪律**：`star_release_default_pubkey_hex`（`src/router/star_gate.mbt`）与 `.mcp.example.json` 的 `FIST_STAR_GATE_PUBKEY_HEX` 必须同步改，否则白盒锁 `star_gate_release_default_pubkey_hex 与发布模板 .mcp.example.json 钉死值一致` 会红；同时必须同步换 CI secret。
4. **文档面未同步**：`AGENTS.md`/`README.md`/`server.mbt` 工具描述仍写「默认未配置即不设门（零回归）」——本轮未改（这些文件属并发会话/禁改面）。需并发会话收口后把「发布模板默认开启、未通过验签免费池锁定」写进 `model_route`/`model_auth_status` 描述与 AGENTS.md 的 Star 门段。

## 后续建议

1. **优先**：与并发会话协调，在 `ofm_http_*.mbt` 补「非 JSON 回体 → 重发一次并追加『请只返回合法 JSON』」+ `max_tokens` 留余量 + content 侧去围栏/修复半截 JSON。这是 user 明确要求的三条，也是把真模型 E2E 从「2/3」抬到「3/3」的唯一路径。
2. **文档同步**：`AGENTS.md` Star 门段与 `model_route`/`model_auth_status` 工具描述改为「发布模板默认带上公钥 → 部署态默认开启；未通过验签免费池锁定」，与 `check_doc_surface`/`check_tools_sync` 对齐。
3. **owner 必做**：把本轮生成的私钥设为 `ED25519_PRIVATE_KEY_HEX` 仓库 secret，否则 star 用户无法解锁。

## 超额内容

- 额外交付了诊断工具 `temp/ofm_raw_proxy.py`（落盘原始 OFM 请求/回体）与验证工具 `temp/star_gate_probe.py`（Star 门双组对跑探针），均 gitignored，不入库。
- 为「发布默认公钥」加了**单一真源**：路由常量 + 模板 + 白盒锁三方对表，防止换钥时静默失配导致全员锁死。

## 来源

- `src/router/star_gate.mbt`（新增 `star_release_default_pubkey_hex`）、`src/router/star_gate_wbtest.mbt`（2 条新锁）、`src/router/ofm_chat.mbt`（恒带 `response_format`）、`src/router/ofm_chat_wbtest.mbt`（`ofm_c_7`）、`.mcp.example.json`（发布模板 env 默认值）。
- `memory/2026-10-12.md`「2026-10-12 二发」段。
- 真源文件：`src/router/model_router.mbt`、`src/server/model_router_ops.mbt`、`.github/workflows/attest.yml`、`src/router/ofm_response.mbt`、`src/server/ofm_http_js.mbt`（只读勘察，未改）。