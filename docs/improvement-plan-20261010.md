# FIST-Mbt 优化增强计划 · 2026-10-10 修正版（v3）

> **输入**：用户五方向指令（Logo+HTML 配置页 / 模型路由增强含 Star 门与多账号 / 多 agent 六顶帽讨论 / 生态 skill 拿来主义 / 全 MoonBit 按规范）+ 一轮真源调研（DSH Cordis 插件系统、`dsh-our-free-model` 源码、fist-mbt 现有 router/store/守卫族）。
> **本版做的事**：把上一版（v2）里**被调研证伪的假设**逐条改正，并把每条新功能打到**四态验收面（cl1–cl7）**；能实测的已实测，测不到的标明「待研究」。
> **读法约束**：下面每个数字都是本轮实测或真源读出（来源在括号里），不引用任何未经验证的转述。上一版 subagent 调研半途失败，其产出（「Lit Templates / JSON Schema Form / 准确率 85% / 省 40-60%」等）**全部作废，本版不引用**。

---

## 0. 上一版的三处证伪（先改认知再谈计划）

| # | 上一版说法 | 真源实测 | 结论 |
|---|---|---|---|
| **证伪 A** | Star 门 = 「每轮用 GitHub API 查用户是否 star，未 star 立即失败」；「算力由 GitHub 承担」 | `dsh-our-free-model` 真源：**star 校验在 OFM 自己的签名网关上做**（`src/eac-login.js` 的 `/auth/github/start?link=` → 系统浏览器 → `/auth/poll`，状态机 `pending/expired/unstarred/ok`），客户端只持有 `worker` 模式签发的 HMAC token；真正的 LLM 调用走用户自己的厂商免费端点，**GitHub 不承担任何推理算力** | 客户端本地查 star **可被绕过**（改代码/假 token），所以「未 star 立即失败」必须落在**服务端**；「算力由 GitHub 承担」不成立——GitHub 只能承担**附属证明/发布**（Actions 定时签名一份授权名单），推理算力在厂商免费端点上 |
| **证伪 B** | 新增 `mcp_configs` / `mcp_audit_log` 两张库表用于 HTML 配置审计 | 真源 `src/store/store_sqlite.mbt` 的 schema 与 `check_store_tables_wired`（BUG-28）判据：库内每张表必须有写入点或 `schema-reserved:` 点名，否则红。**加表 = 加守卫负担**；审计已有 `call_log` / `audit_log` 现成通道 | **不加表**。HTML 配置页的写入结果只落 `fist.mcp.json` + 走 `call_log`，不新开库表 |
| **证伪 C** | 插件态已「真正可用」（129 工具） | 首次 patch 用了不存在的字段 `timeout_ms`（真源 `dsh-mcp-client` Config 只有 `toolCallTimeoutMs`）+ 相对 `_build/...` 路径按 **Host cwd** 解析（不是仓库根）→ MCP 客户端 `server is disconnected`，`list_mcp_resources` 报错。**本轮已修复**：绝对路径 + 钉 `cwd` + `toolCallTimeoutMs: 30000` + 删掉宿主面重复的 `agent-instructions` 行（web profile 该插件在宿主面是 `disabled: true`、由 preset 挂载，重复行会造成双注入） | 已实测：`list_mcp_resources` 回 `fist-mbt 0.3.6` + 3 resources；`status_summary` 回真库 **2011 任务**；`store_list` 通。**这才是「真正可用」的可复现证据** |

**连带发现（值得入库为原则）**：`AI-DEVELOPMENT-STANDARD.md` §7 已知边界写着「四宿主插件目录是生成投影，**未在真实宿主内逐一装载验证**；cl7 只保证『等于投影』，不保证『宿主可用』」——本轮实测正是补上了这一格：deepseek-harness 宿主侧真的装上了。建议下一轮把它写进 `docs/` 与 CHANGELOG，并把「host-installable」列为 cl7 之外的常驻判据候选（待研究，见 §6）。

---

## 1. 实测基线（2026-10-10，本机）

| 面 | 实测值 | 口径 |
|---|---|---|
| 注册工具数 | **129**（`server.mbt` 130 处 `instrumented_tool(`，其中 1 处是函数定义本身） | 真源 `src/server/server.mbt` |
| 活体任务库 | **2011 任务**：待领取 983 / 已领取 408 / 已完成 415 / 拆分中 104 / 待验收 49 / 已归档 45 / 已打回 6 / 已暂停 1 | `status_summary` 回读（MCP 真连） |
| MCP 资源 | 3 个：`fist://map` / `fist://overview` / `fist://principles` | `list_mcp_resources` 回读 |
| DSH 宿主 | `@victop/fist-mbt` v0.3.6 bundle = 单行 `fist-mbt-mcp`；`dsh-our-free-model` 2.0.0 已装 | `plugin_manager list_bundles` |
| OFM 渠道数 | **13 个账号渠道**（codearts/workbuddy/lobsterai/loomy/minimax/qoder/qodercn/raccoon/trae/zcode/gemini/opencode/cline）+ 匿名免费通道 | `vendor/channel-pack/pack.js` 反解 |
| OFM 凭据形状 | AES-256-GCM seal + HKDF-DIGEST sha256 从 3 段掩码碎片派生密钥 + host fingerprint gate（`DSH_HOME`/`execPath`/`argv`/profile 三元组） | `src/vault.js` |
| OFM 传输 | `node:http`/`node:https`（非 global fetch，防代理插件改写 fetch） | `src/eac.js` 真源 |
| 现有黑盒安装 | `install.ps1` / `install.sh` / `install_onecmd.ps1` 产出 shim `fist` / `fist-mbt`（各 `.cmd` + 无扩展名 POSIX 双份）到 `~/.local/bin`；`.mcp.example.json` 用 `command: "fist-mbt"` + `FIST_PROJECT_DIR: "."` | `scripts/blackbox/` |
| `.mcp.json` 状态 | **gitignored**（`.gitignore:53` `/.mcp.json`）；`.mcp.dev.json` 是跟踪真源 | `git check-ignore` 实测 |
| 仓库素材 | **无 `assets/` 目录、无任何 `.html`/`.svg`/`.png`/`.ico` 跟踪文件** | `git ls-files` + glob |
| 生态 skill 本地态 | `~/.agents/skills` = **322 目录**；有 `hm-test-driven-development` / `hm-systematic-debugging` / `hm-spike` / `hm-plan` / `super-search` 等；**无 fist-mbt skill**、无 `grill-me`、无 `superpowers` | 目录枚举 |
| 既有规划资产 | `memory/research/*.md`（21 份，含 `ecosystem-borrow.md` 已落地 R10/R12/R13/R14）；`docs/improvement-plan-20260929.md`；`BACKLOG.md`；`docs/superpowers/`（仅 2 份旧 plan/spec，无根 SKILL.md） | 目录枚举 |

---

## 2. 方向一：拳头 Logo + HTML 配置页 + `fist.mcp.json`

### 2.1 目标项目内的 HTML 配置页（用户原话：配置 MCP 设置偏好，生成 `fist.mcp.json`）
- **产出**：一个 `fist-config.html`（目标项目内），纯静态单文件、无 CDN、无构建步骤，浏览器本地运行。
- **能写什么**：`{mcpServers: {fist-mbt: {command, args, env:{FIST_PROJECT_DIR}, disabled}}}` —— 只写**形状**，不写凭据（本仓 `router_config.mbt` 与 `executor_run` 的原则：密钥只来自 server 进程环境变量，不读 `.env`、不回显 key）。
- **输出两条**（对齐用户原话）：
  - `fist.mcp.json` —— 目标项目里的**使用态**配置；
  - `default-fist.mcp.json` —— fist-mbt 仓库侧生成的**默认模板**（等价于升级版 `.mcp.example.json`，但带交互表单）。
- **黑盒路径默认**（对齐 `scripts/blackbox/` 与 `.mcp.example.json`）：生成的配置优先 `command: "fist-mbt"` + `FIST_PROJECT_DIR: "."`（安装器装的 shim，跨项目可用）；只有用户显式选了「源码模式」才写 `node <绝对路径>/cli.js serve`。**不要再复制我上一版那种硬编码仓库绝对路径的写法**——那正是插件态「host cwd 解析错」的教训。
- **审计走现成通道**：HTML 页本身不落库；生成的 JSON 由 agent 落盘时自然进 `call_log`，**不加表**（证伪 B）。
- **守卫对齐**：新增文件若进包，`check_publish_payload`（BUG-127）会扫「工作树 − .gitignore」，点号文件不进包——所以 `fist.mcp.json` 必须写进 `.gitignore`（与 `/.mcp.json` 同级），`default-fist.mcp.json` 不带点号、作为模板进包。**这条必须和 HTML 一起做，否则 CI 红**。

### 2.2 拳头 Logo
- 仓库无任何位图/矢量素材 → 需要新增 `assets/fist-logo.svg`（拳头，单色/线性风格，适合 favicon 与 README 徽章）。
- **生成方式**：SVG 是**静态资产**，不是 gen_plugins 的投影面；但它会被四宿主插件目录与 README 引用 → 在 `scripts/gen_plugins.py` 里**追加一步 assets 拷贝**（把 `assets/` 下文件按字节复制到 `plugins/<host>/assets/`），保持 cl7 逐字节 diff 的语义。
- 建议同时做 `docs/assets/README.md`（谁用、怎么换、尺寸规格），满足「文档即实现」。

### 2.3 四态对齐
| cl | 判据 | 本功能动作 |
|---|---|---|
| cl1 | MCP 工具存在 | 新增 `mcp_config_scaffold(project_dir, form_json)` 工具，服务端校验 form 并**返回可落盘的 JSON 正文**（不代写目标项目文件，写由 agent/安装器做） |
| cl2 | CLI 封装 | `python scripts/fist.py call mcp_config_scaffold ...` 可路由 |
| cl3 | skill 文档 | `docs/fist-config-skill.md`（何时用/怎么调/已知边界） |
| cl4 | 测试 | `src/server/*_wbtest.mbt` 正/负路径（非法 form、缺字段、含凭据键→必须拒） |
| cl5 | L4 证据 | `output_validate` 验 `default-fist.mcp.json` 存在 + `assets/fist-logo.svg` 非空 + schema 校验 |
| cl6 | 文档同步 | README 工具数 +1、版本同步 |
| cl7 | 插件投影 | `gen_plugins.py` 重跑 + `check_plugin_sync.py` 绿（含新 assets 拷贝） |

---

## 3. 方向二：模型路由增强（OFM 式）+ Star 门 + 多账号

### 3.1 路由本体增强（不重复造轮子）
fist-mbt 已有 `src/router/`（免费优先 + 达阈值切付费 + 每模型 5h 滚动窗口 + `config_json` 覆盖池定义 + 只问不消耗零副作用 + 白盒锁 rt_1~15/rs_1~6/mo_1~9）。**增强不做「另一个路由」，做的是「多池 + 多 provider 元数据」**：
- `RouterConfig` 支持**多个免费池**（如 `free_pool: [anon-opencode, eac, kilo]`），每个池独立 `limit`/`window_seconds`，`threshold_pct` 仍是切付费的门。
- **账号/授权**：真源 `RouterConfig` 明确不含 key/base_url，**继续不放进 config_json**（否则四态投影会把凭据复制进 `plugins/*`，违反 cl7 + `check_publish_payload`）。凭据只走环境变量，HTML 配置页只填「池名称 + 环境变量名占位」，不填真值。
- **多账号「薅羊毛」**：诚实标注风险——这是各厂商免费端点的**使用条款边界**，与 OFM 同族。fist-mbt 只做**路由与轮询**（哪个池还剩配额、切换），不做**账号保管与自动注册**；账号真值沿用 OFM 的 vault 思路（AES-256-GCM + HKDF 碎片派生 + host fingerprint gate）**由用户在自己侧落一份本地 vault**，fist-mbt 通过环境变量读解锁态。**若做账号池，必须把「用户自持 vs 平台托管」作为独立决策点交用户拍板**（见 §6 决策点 D2）。

### 3.2 Star 门（证伪 A 之后的正确形状）
正确模型 = **签名授权清单（attestation）**，不是客户端实时查：
1. **GitHub Actions 定时 job**（如每 6h）拉取 stargazer 列表，用仓库 secrets 里的私钥对「授权名单 + 时间戳」做 Ed25519 签名，发布到 GitHub Pages / Release 资产。
2. **fist-mbt 侧**启动或每次 `model_route` 前拉取该清单，验签 + 校验 `login ∈ 名单` + 校验时间戳新鲜度（TTL），通过才解锁免费池；失败→降级到匿名池或显式 `ok=false`（对齐现有「两池皆不可用显式失败，绝不静默改模型」语义）。
3. **取消 star 即失效**：TTL 到期后下次拉清单自然不含该用户 → 自动失效，**不需要「每轮查」**（那正是证伪 A 里被绕过的脆弱设计）。
4. **诚实边界**：客户端验签的清单是**公开可伪造不了但可被「用户自己改本地缓存」绕过**——这不是缺陷而是模型本身的性质；要**强门禁**就必须回到 OFM 那种**服务端网关**（需要 fist-mbt 自己有一台服务器，超出本仓范围）。**推荐默认 = 签名清单（弱门禁/仪式感门禁）+ 显式文档写出边界**；服务端网关列为「远期、需用户自备主机」的独立选项。
5. **「算力由 GitHub 承担」的修正**：GitHub 只承担**证明发布**（Actions + Pages/Release）；推理算力在用户自己的厂商免费端点上。这条要在 README 写清楚，否则是承诺说谎。
6. **公钥钉死（终审补上的另一半边界，2026-10-10）**：`.github/workflows/attest.yml` 把 `public_key_hex` 与 `signature_hex` **放在同一个 payload 里一起发布**（attest.yml L92-101），客户端没有**离线钉死**的期望公钥。诚实结论：该 Ed25519 签名只能自证「workflow 跑过 + 载荷自洽」，**对能改写 Pages 内容/CI 产物的攻击者不构成认证**（攻击者可换成自己的密钥对 + 自己的名单）；现实的信任根是 **GitHub Pages 的 HTTPS + GitHub 仓库本身完整性**，不是 Ed25519 本身。要与「仪式感门禁」区分：只有把期望 `public_key_hex` 在客户端**离线钉死**（源码常量或另一次独立签名发布），Ed25519 才真正用上；未钉死时本条维持「弱门禁/仪式感门禁」定性不变。这条与 §3.2 第 4 点的「本地改缓存绕过」是**两条独立**的弱化面，第 4 点已被原 plan 写明，本点此前未写。

### 3.3 与 OFM 的关系（拿来主义）
**不重写 OFM 的 13 渠道登录**。fist-mbt 的 `model_route` 只做**路由决策**，把「真实调用」委托给已装的外部 provider（如 `dsh-our-free-model` 暴露的本地 OpenAI 兼容端点，或环境变量指向的任意 base_url）。即：**fist-mbt = 路由器，OFM = 渠道**，两者通过 `env` + `config_json` 解耦。这符合本仓 r2 单真源 + 「轮子不要重复造」。

### 3.4 四态对齐
- cl1：新增/扩展 `model_route`（已有，只扩展 schema 支持多池 + `auth_provider` 元数据），新增 `model_auth_status`（只读查当前 star 门 TTL / vault 解锁态）。
- cl2：CLI 路由；cl3：`docs/model-router-skill.md` 已有 → 追加多池与 Star 门节；cl4：router 白盒测试补多池切换用例；cl5：`output_validate` 验 vault 文件存在 + 签名单样例验签通过；cl6/cl7：文档与插件投影同步。
- **新增守卫候选**：`check_model_auth_no_key`（config_json / HTML 输出里**禁止**出现 `api_key`/`token` 值形状）——待研究立项（见 §6）。

---

## 4. 方向三：多 agent 六顶帽讨论 + 用户终审门

用户原话：「增加多 agent 对话式探讨自驱式开发方向，六顶思维帽中至少 2 个，前期先调研、计划详细清晰后再动手，最终由用户拍板」。

### 4.1 机制设计（复用手头已有的子代理体系，不新开调度器）
- **六帽**（Edward de Bono）选 **≥2**：默认 `White`（事实/数据）+ `Black`（风险/反例）+ `Yellow`（收益/乐观）三顶起步；`Red`/`Green`/`Blue` 作可选扩展。
- **承载**：DSH 的 `subagent` / `subagent_fork` 工具 + fist-mbt 的 `workflow`（多 agent 编排）；每顶帽子 = 一个 subagent，输入 = 议题 + 该帽子的**角色指令模板**，输出 = 结构化结论（对齐 `eval_feedback` 的四段式契约：`Defects/Evidence/Fix/Acceptance`）。
- **帽子角色模板真源**：新增 `src/ops/ops_hats.mbt`（纯计算，返回每帽子的角色指令/禁做事项/输出 schema），`mode_list` 同族可扩展为 `hat_list` 工具。
- **终审门 = 用户拍板**：各帽结论汇聚后由 **指挥官/用户** 做最终裁决，`subagent` 只有建议权。fist-mbt 侧提供 `debate_convene(question, hats)` / `debate_register(hat_id, verdict, evidence)` / `debate_verdict(threshold)` 三件，把「多帽一致性」算成确定性结果（如同意率 ≥ 0.6 才放行），**不代用户决定**。
- **防课程漂移**：复用 `evolve_critic`（重合 ≥70% 拒收）+ `goal_drift_check`（jaccard 判漂移/冗余）作为帽子结论的**同质化过滤**——六帽最怕七顶帽子说同一句话。
- **不新开库表**：讨论记录走 `call_log` + `memory/YYYY-MM-DD.md`（证伪 B 同一理由）。

### 4.2 与既有 BACKLOG/research 去重
`ecosystem-borrow.md` 已落地 SAGE 四专家环（`evolve_critic` + `task_challenge`）、LADDER 梯度、`reserve_scope`；`five-directions.md` 已列「Evaluator-Optimizer schema」「Agent Contract 7 字段」。**六顶帽不是新领域，是把「单指挥官裁决」升级为「多视角证据收敛」**——与 SAGE 的 Challenger/Planner/Solver/Critic 角色互补但不重叠（SAGE 是进化环，六帽是同一议题内的多视角）。

### 4.3 四态对齐
- cl1：`debate_*` 三件（或合一件 `debate` + `debate_status`）；cl2：CLI；cl3：`docs/debate-skill.md`；cl4：白盒测试（帽子模板存在性、verdict 阈值、critic 拒收路径）；cl5：`output_validate`；cl6/cl7：同步。

---

## 5. 方向四：生态 skill 拿来主义（grill-me / super-power / tdd / research / build）

### 5.1 先摸清已有
实测：`~/.agents/skills` = 322 目录，**已有** `test-driven-development`、`systematic-debugging`、`spike`、`plan`、`research-paper-writing`、`super-search`、`requesting-code-review`、`ideation`、`subagent-driven-development` 等；**没有** `grill-me`、没有 `superpowers` 根目录、**没有 `fist-mbt` skill**。
另：`docs/superpowers/` 只有 2 份旧 plan/spec、无根 SKILL.md —— 说明历史上用过「superpowers 命名」但没建成常驻体系。

### 5.2 拿来主义路径（按性价比排序）
1. **P0 · 先补 fist-mbt 自己的 skill 安装**：本仓 `plugins/deepseek-harness/skills/fist-mbt/` 已由 gen_plugins 生成，但**宿主侧 `~/.agents/skills/` 里没有它** → 装上它 = 让用户「用 fist-mbt 时真的拿到 fist-mbt skill」。这是当前最贵的一格缺失。
2. **P0 · 注册外部资产进 DGM**：本仓已有 `evolve_asset_register`（外部资产注册，plan/claim 的 `inject` 可按关键词检索）。把 `test-driven-development` / `grill-me`（若引入）/ `superpowers`（若引入）注册成 `[asset]<来源名>`，让 plan 自动注入对应玩法——**零新代码，只加档案条目**。
3. **P1 · `grill-me` / `superpowers` 按需引入**：这两个不在本地 322 目录里 → 需要 `git clone` 或 `skill` 加载。按用户「轮子不要重复造」的原则，**优先 clone 第三方仓库到 `~/.agents/skills/`，fist-mbt 只做注册与注入**，**不要在 MoonBit 里重写**。
4. **P1 · skill 路由增强**：`task_triage` 现在只按能力标签排任务；可扩展为「按 skill 命中度」给下一单建议（如 `tdd` 命中 → 建议走 `fix_and_merge` 模式）。**这是把「skill 库」变成「路由信号」的一格**，是真正的新价值，而不是又收一份 skill。

### 5.3 四态对齐
- 外部 skill 本身不是四态投影面（gen_plugins 不生成它）；fist-mbt 侧只把 `evolve_asset_register` 的注入路径做 cl2（CLI）+ cl3（文档）+ cl4（白盒测 inject 命中）。
- 新增守卫候选：`check_skill_inject`（plan/claim 传了 `inject` 时，返回的 `injected_assets` 非空才算命中）——待研究。

---

## 6. 规范合规与新增守卫候选

### 6.1 规范面逐条对齐（`AI-DEVELOPMENT-STANDARD.md`）
| 规则 | 本计划怎么守 |
|---|---|
| r1 文档即实现 | 每个新工具先写 `docs/<tool>-skill.md` + README 速查，再动代码 |
| r2 一源四态 | 全部逻辑写在 MoonBit（`src/ops/`、`src/router/`）；CLI 薄封装；插件态 = `gen_plugins.py` 重跑；**凭据不进 config_json** |
| r3 确定性优先 | 帽子判定、签名验签、TTL 全走纯计算 + 白盒测试，不用 LLM 自评 |
| r4 增量零回归 | 每步 `moon test --target js` 全绿；临时脚本用完清理；新功能默认关闭（`disabled: false` 除外） |
| r5 自我迭代 | 用 `evolve_distill`/`evolve_lesson`/`task_challenge` 收口每轮 |
| f1 用自身能力迭代 | 用 fist-mbt 自己 publish→plan→claim→execute→submit→verify 完成本计划（**本轮就可以起个头：把「方向一」发布为根任务**） |
| f2 四态对齐 | cl1–cl7 全过才 verify |
| f3 证据梯 L4 | `output_validate` verdict=pass 才算完 |
| f4 重任务先拆 DAG | 方向二（涉及 router/ops/store/守卫/文档）跨 5+ 文件，必须先 `task_plan_deep` |
| f5 命名即文档 | 新工具名动宾结构：`mcp_config_scaffold` / `model_auth_status` / `debate_convene` / `hat_list` |

### 6.2 新增守卫候选（立项前先写判据再写代码）
- **`check_model_auth_no_key`**：`config_json`、HTML 生成物、`default-fist.mcp.json` 里禁止出现 `api_key`/`Bearer`/`sk-` 值形状（对齐 BUG-127 的凭据形状红）。
- **`check_host_installable`**：`check_plugin_sync` 之外补一格——deepseek-harness 宿主侧**真的能装上**（对齐本轮实测），避免 cl7「等于投影」却「装不上」的旧边界（§0 连带发现）。
- **`check_skill_inject`**：`evolve_asset_register` 注入路径可测命中。

---

## 7. 落地顺序（P0 → P1 → P2，每步一个四态闭环）

| 阶段 | 内容 | 涉及文件 | 依赖 | 交付 |
|---|---|---|---|---|
| **P0-a** | 拳头 Logo + `assets/` + gen_plugins 加 assets 拷贝 + cl7 重跑 | `assets/fist-logo.svg`、`scripts/gen_plugins.py`、`plugins/*/`（生成） | 无 | SVG 进包，cl7 绿 |
| **P0-b** | `mcp_config_scaffold` 工具 + `fist-config.html` + `default-fist.mcp.json` + `.gitignore` 补两行 | `src/server/*`、`docs/fist-config-skill.md`、`.gitignore` | P0-a | 目标项目能一键生成 `fist.mcp.json`（黑盒路径优先） |
| **P0-c** | fist-mbt skill 装进 `~/.agents/skills` + `evolve_asset_register` 注册既有生态 skill | `plugins/deepseek-harness/skills/fist-mbt/`、DGM 档案 | 无 | 用户用 fist-mbt 时真的拿到 skill |
| **P1-a** | 路由多池 + Star 门签名清单（GitHub Actions + Ed25519） | `src/router/router_config.mbt`、`src/ops/`、`.github/workflows/attest.yml` | P0-b | `model_route` 支持多免费池；`model_auth_status` 可查 TTL |
| **P1-b** | 六顶帽 `hat_list` + `debate_*`（≥2 帽，White/Black/Yellow） | `src/ops/ops_hats.mbt`、`src/server/*`、`docs/debate-skill.md` | 无 | 指挥官能对议题做多帽收敛 + 用户拍板门 |
| **P2** | 守卫族三个新增候选 + 文档/README 收口 + `memory/2026-10-10.md` + `reports/` | `scripts/*.py`、`AGENTS.md`、`README.md` | P1-a/b | CI 全绿 + 常驻判据就位 |

---

## 8. 待研究 / 需用户拍板的决策点

| 决策点 | 选项 | 建议 |
|---|---|---|
| **D1 · Star 门强度** | A) 签名清单（GitHub Actions + Pages，仪式感门禁，可被本地改缓存绕过） B) 自建服务端网关（强门禁，需用户自备主机/长期运行） C) 不做 | **默认 A**，B 列为远期，C 不推荐（用户明确要求） |
| **D2 · 多账号账号托管** | A) 账号真值用户自持（环境变量/vault），fist-mbt 只路由 B) 平台托管账号池（需自备服务器 + 合规审查） | **默认 A**；B 涉及条款边界与运维成本，必须用户拍板 |
| **D3 · 六顶帽默认帽数** | 2 / 3 / 6 | **默认 3**（White+Black+Yellow），后续按需扩到 6 |
| **D4 · 生态 skill 引入方式** | A) 只注册不进库（`evolve_asset_register`） B) clone 进 `~/.agents/skills` 并注册 | **默认 A 起步**，需要时再 B（避免仓库外依赖） |
| **D5 · 本轮是否立即用 fist-mbt 自己开工** | A) 先把「方向一」发布为根任务走 f1 全流程 B) 只出计划文档，动手等用户看后再说 | **推荐 A**：符合 f1，也能真实验证「插件可用」 |

---

## 9. 一句总结
上一版最贵的错不是写错了代码，而是**把「客户端查 star 就能当门禁」「加两张表做审计」「插件已可用」这三个未经证伪的假设当成了事实**。本版把三处全部改正（证伪 A/B/C），并给出按四态验收面逐条对齐的落地顺序。**下一步建议先做 D5（用 fist-mbt 自己发布方向一根任务），因为它本身就是对「插件真正可用」的第二次实测。**
