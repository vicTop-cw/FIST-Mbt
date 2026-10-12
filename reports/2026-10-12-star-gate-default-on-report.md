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

---

## 三发追加 · 复核 → 发布 v0.3.8 → 更新本地命令

### 结果摘要
- **提交**：✅ 对齐 `cmd/cli/help_topics.mbt` 的 `FIST_VERSION` 到 `moon.mod` 的 0.3.8（`df40607`），修 `check_release_asset_names` R11；合并 origin 领先提交生成 `99b94e5`，master 推到 origin（`5f19832..99b94e5`）与 gitcode；打带注解 tag `v0.3.8`（`bb2009b8`→`df40607`）推到 origin。
- **发布**：⚠️ `release.yml` run #6 失败 —— `build-js` 红在 `Build JS target`（`moon build --target js`），`build-native-linux` 红在 `Build native`，`build-native-windows` 红在 `Install MoonBit`，`release` skipped ⇒ **GitHub Release 未产出**（API `releases/tags/v0.3.8` = 404，latest 仍 v0.3.5）。
- **本地命令**：✅ `install_onecmd.ps1 -Version 0.3.8 -LocalZip` 用本地打包的 v0.3.8 资产装到本机，实测 `fist version` = `FIST-Mbt v0.3.8`（旧 v0.3.0 已备份保留）。

### 关键证据（不据自述）
- `moon test --target js -j 1` = **Total tests: 799, passed: 799, failed: 0**。
- 本地 `moon build --target js`（CI 同命令全量）= **Finished, 15 tasks, cli.js 产出** ⇒ **代码不是 CI 红的元凶**。
- 真实产物 `node cli.js -V` = `FIST-Mbt v0.3.8`、`--help` 版本面 `v0.3.8`（**先 `python scripts/patch_esm_main.py`**，否则首行是 `file:///...`，会让 cli_flag_probe 假红）。
- API 逐 job 拆解（`actions/runs/38238264053/jobs`）：`Install MoonBit` / `Refresh registry` 已绿 ⇒ R8/R9 那两格已过，**问题在真正的构建步**，不再是"runner 上没有 moon"。
- 版本差：本地 moon **0.1.20260920**（AGENTS.md 与全量测试用的验证版本）vs release.yml `MOON_VERSION: 'latest'` + `install/unix.sh` ⇒ **疑似 `latest` moon 在 Linux 上的回归/新弃用提错**，但**未闭环**：匿名读日志 `actions/jobs/{id}/logs` = **403**、`workflow_dispatch` = **401**（无 GitHub token），拿不到失败步 `::error::` 正文。

### 资源消耗
- 一次 tag 发布触发 4 个 job（meta 绿 / build-js / build-native-linux / build-native-windows 红 / release skipped）；本地多次 `moon build`、`moon test`、一次 JS 打包 + 一次本地安装；若干 GitHub API 只读调用。

### 任务分配记录
- 本会话：复核 + 版本对齐 + 合并推主 + tag 发布 + 失败定位 + 本地打包安装 + 记忆/报告沉淀。**未动**并发会话文件（`README.md` / `src/server/*` / `docs/*-20261012.md`）。

### 遗留风险
- **GitHub Release v0.3.8 未产出**：安装横幅/离线线仍指向不存在的 `fist-mbt-js-v0.3.8.zip` 公网资产；tag 已推但无资产。
- `check_release_asset_names` **R13 仍红**：README 资产名字面量 0.3.6（README 属并发会话文件）。
- `check_doc_surface` **J15** + `check_publish_payload` **3×P1**：3 份 `docs/*-20261012.md` 未入库未 ignore，`moon publish` 会公开出去。
- 并发会话的 `src/server/fist-mbt_wbtest.mbt` 的 `project_version` 锁面仍未收口。

### 后续建议
1. **钉 moon 版本**：release.yml `MOON_VERSION: 'latest'` → `0.1.20260920`（与 ci.yml / 本地验证面同源），再打一次 tag 触发。
2. **或拿 GitHub token** 读 run #6 `build-js` 的 `Build JS target` 失败步 `::error::` 正文，确认是 moon 回归还是代码在 Linux 上才触发。
3. 在拿到失败日志前，**别改 release.yml 之外的东西猜**。

### 超额内容
- 额外产出一份**本地可用的 v0.3.8 资产**（`_release/fist-mbt-js-v0.3.8.zip`，gitignored）让本地命令先升级到位，不阻塞公网 Release。
- 发现 `build_release.ps1` 自己读陈旧的 `_release/VERSION` 而不是 `moon.mod`（与 R11 同族漂移），本轮手动绕过。

### 来源
- `cmd/cli/help_topics.mbt`（`FIST_VERSION` 0.3.6→0.3.8）、`memory/2026-10-12.md`「三发 · 复核 + 发布 v0.3.8」段。
- `.github/workflows/release.yml`（`MOON_VERSION: latest` L25、`install/unix.sh` L67）、`scripts/blackbox/install_onecmd.ps1`（`-LocalZip` 布局）、`scripts/blackbox/build_release.ps1`（`-SkipNative` / 陈旧 `_release/VERSION`）。