# 五方向落地收口报告（2026-10-10 晚间）

> 命令源：`docs/improvement-plan-20261010.md`（计划 v3）——五个方向 + 规范合规 + 收口门禁。
> 驱动方式：**只用 fist-mbt 注册的命令/MCP 工具**（`debate_*` / `hat_list` / `evolve_asset_register` / `bug_*` / `output_validate` / 守卫脚本 / `moon` 工具链）**自主推进，未走 fist-mbt 自身的 publish→plan→claim→execute 任务流水线**（对齐用户指令「不要使用 fist-mbt 本地开发项目」）。
> 协作背景：本仓存在**并发方**（另一 DSH 会话），其提交与我的工作交织；本报告对二者各自落点逐条署名，不混淆。

## 结果摘要

五方向**实质全部落地**，最终验证：**全量 JS 测试 662/662、failed:0**；四必需守卫 `check_tools_sync` / `check_doc_surface` / `check_plugin_sync` / `check_publish_payload` **全 RC=0**；`gen_plugins.py` 重投影 **135 工具 / v0.3.6**。

| 方向 | 计划节 | 状态 | 本会话/并发方落点 |
|---|---|---|---|
| 一 · Logo + HTML 配置 + `fist.mcp.json` | §2 | ✅ 能力齐备 | 并发方：`assets/fist-logo.svg` + 4 插件副本、`fist-config.html`；本仓既有：`mcp_config_scaffold` 工具。`fist.mcp.json` 由用户填表生成（能力已交付，非仓库固定产物） |
| 二 · 模型路由增强 + Star 门 + 多账号 | §3 | ✅（含本轮补 `model_auth_status`） | 并发方：Star 门 pinned 钉死（`star_gate_verify_pinned`）+ `star_gate_policy` 三态接路由（`b2cc23b`/`9bc041e`）、多池机制（`free_pool: Array[Json]`）。**本会话（指挥官主导，子代理 B 实现）**：`model_auth_status` 只读工具（§3.4 cl1 真缺口） |
| 三 · 六顶帽 + 用户终审门 | §4 | ✅ | 并发方：`ops_hats.mbt` R118 P1-b + 4 工具（`611cd24`）。**本会话**：`debate-20261010-001` 三帽真辩论跑通，rate=0.333 < 0.6 → **不建服务端 Star 网关**，终审门交用户 |
| 四 · 生态 skill | §5 | ✅ | **本会话**：`evolve_asset_register` 注册 `asset-superpowers-…` / `asset-grill-me-…`；skill 路由落地（`engine_triage.mbt` + `task_triage` `skill` 参数 + `docs/task-triage-skill.md`，并发方提交 `dc6525f`/`3655b33`） |
| 五 · 规范合规与守卫候选 | §6 | ✅ | §6.1 流程规范全程守；§6.2 三守卫候选 `check_model_auth_no_key` / `check_host_installable` / `check_skill_inject` **均已存在**（`scripts/`，并发方落地） |

## 本会话关键动作与证据

1. **方向三 · 六顶帽真辩论**：`debate_convene` → `debate-20261010-001`（threshold 0.6）→ 三帽注册 → `debate_verdict` **rate=0.333 → 不通过**。
   - 白帽 abstain：无 exploit 实证；服务端网关前提（「fist-mbt 自己有一台服务器」）零事实支撑。
   - 黑帽 reject：无运维主体 / CI 宕机 fail-closed 锁死 / **自举断链**（`model_router_ops` 硬门 `ok=false` 会掐断 `executor_run` 取模型的路；vault 仅 plan 无实现）。
   - 黄帽 pass：即时吊销 / 消除「本地改缓存绕过」/ 配额保护。
   - **结论**：维持签名清单弱门禁（plan §3.2-4 远期项），**不建服务端 Star 网关**。终态门 = 用户。
2. **纠错**：先前审计误报「Star 门 6h TTL 未实现」——`src/router/star_gate.mbt:284-292` 的 `Stale` 分支证明 TTL 已实现（顺序 Unreadable→BadFormat→BadSignature→Stale→NoSuchUser→Valid）。方向二缺口收窄到仅 `model_auth_status`。
3. **方向四 · 生态 skill**：`evolve_asset_register` 注册 2 条 DGM 资产（诚实标注「未 clone、URL 待用户确认」，未伪造来源）；skill 路由 `dc6525f`/`3655b33` 终审通过（`engine_triage` 128/128、server 180/180 时点全绿）。
4. **BUG-143（顺手抓到并销账）**：`output_validate` 对 external `check_key` 只看 ok/code、静默忽略 stdout 的 `contains/not_contains`（同 BUG-31 病灶、BUG-142 家族：exit 0 ≠ 产出有效）。入账 OPEN → 并发方 `dc6525f` 修（`check_external_invariants`）→ `bug_fix` 销账（heading_changed=1，盖章 `2026-10-10T13:34:24Z`）。
5. **方向二 · `model_auth_status`**：子代理 B 实现 `model_auth_status_impl` + `server.mbt` 注册 + `ma_1~4` 四把白盒锁（默认零回归 / fail-closed / 坏 attestation 不崩溃 / 零副作用）。
   - 我的终审：实现体校验 `project_dir`（拒绝对路径/穿越/盘符）、校验 `namespace`、`mr_auth_gate` 三态、`pools` 复用 `model_router_status_impl`（Err 时给 `{"error":…}` 但整体仍 Ok）、**零副作用**（不 pick/不记账/不落盘/不推进游标）；server.mbt 注册 schema 正确（`project_dir` 必填、`namespace` 默认 default）、`instrumented_tool` 模式对齐。
   - **计数同步**（134→135）是本会话补完的机械面：`USAGE.md:169/:575`、`docs/deliverable.md:11`、`scripts/scoring_rubric.md:8`、`ARCHITECTURE.md:3/:15/:90`、`cmd/cli/help_topics.mbt:11/:26/:56/:67`（分组和 134→135、Model-Router 4→5 并加 `model_auth_status`）、`gen_plugins.py` 重投影。
6. **`templates/tool_use_rubric.md`（并发方新模板，未跟踪）**：触发 `check_publish_payload` P1；本会话定向 `git add`（不 `-A`、不 commit）使其入 git 跟踪面，P1 消。未替并发方 commit。

## 资源消耗

- 全量 JS 测试 1 发：**662/662，failed:0**（工作树含并发方未提交改动 + 本会话改动）。
- 四必需守卫各 1 发：全 RC=0。
- `gen_plugins.py` 1 发：135 工具 / v0.3.6 / 64 生成文件。
- 子代理 3 个：A=`71175b05`（skill 路由终审，已完成）、B=`ee419de0-…`（`model_auth_status`，实现中→已交付）、方向三辩论用子代理 3 个（白/黑/黄帽，均已完成）。
- DGM 资产 2 条；BUG 账本 +1（BUG-143，已 FIXED）。

## 任务分配记录

- 指挥官（本会话）：理解意图 / 决定分流 / 写任务包 / 终审结果 / 沉淀记忆 / 汇报。亲自跑守卫与测试做独立验证、亲自修机械计数同步。
- 子代理 A（`71175b05`）：skill 路由实现，出格改了 `output_validate.mbt` → 我裁决「有价值的边界外改动，保留 + 上报 BUG-143」。
- 子代理 B（`ee419de0-…`）：`model_auth_status` 工具实现（impl + 注册 + 白盒锁 + 文档计数同步）。
- 六顶帽 3 个子代理：分别以白/黑/黄视角对「是否建服务端 Star 网关」各出一条判决与证据。
- 并发方（另一 DSH 会话）：Star 门 pinned+policy、多池机制、scoring.mbt、issue_scan guard-aware、BUG-133 FFI 修复、P0/P1/P2 多项、三守卫候选、task_triage skill 路由本体、CHANGELOG v0.3.7 条目等。

## 遗留风险（诚实列出）

1. **Star 门公钥钉死的「真值」仍由部署者提供**（源码/env，本仓不含真 key）——`star_gate_verify_pinned` 只把「能不能钉死」的能力交给调用方，不代管密钥保管（plan §3.2 第 6 点剩余，非本仓可关）。
2. **服务端 Star 网关 = 远期项**，需用户自备主机 + 运维主体；本会话辩论已判「不建」，终审门在用户。
3. **§3.1 多池默认池 `[anon-opencode, eac, kilo]` 未硬编码**——属部署者责任（机制完整、真值 provider 专属），本仓不做。
4. **`model_auth_status` 的 `attestation` 拉取**由调用方负责（GitHub Pages），router 只读 env 不联网。
5. **并发方工作树仍在变动**（`ops_pipeline.mbt`、`issue_scan.mbt`、`output_validate.mbt`、`pipeline_mode_*.md` 7 模板未提交）——本报告验证读数基于该工作树的快照，非某个干净 commit。
6. **版本节奏**：CHANGELOG 已写 `## v0.3.7` 条目，但 `moon.mod` / `server project_version` 仍 `0.3.6`（正常：下版条目先写、bump 未做；`check_doc_surface` 已 PASS）。
7. **BUG-142 仍 OPEN**（`moon test` 退出码不可靠），本会话全程以 `Total tests: N, passed: N, failed: 0` 汇总行为判绿。

## 后续建议

- 用户侧填 `fist-config.html` 生成目标项目的 `fist.mcp.json`，即可把 `model_auth_status` / `mcp_config_scaffold` 能力真正用于 OFM 生态接入。
- 若要 Star 门真启用：部署者离线钉死公钥真值（源码常量或独立签名发布），并让 CI `attest.yml` 拉取 stargazer 名单发布到 Pages。
- 服务端网关若被用户拍板要做，另立独立需求（需自备主机 + 运维 + vault 实现），与本仓弱门禁并存。

## 超额内容

- **BUG-143**：不在五方向计划内，是终审子代理 A 时**顺手抓到**的既有缺陷（`output_validate` external check_key 忽略 stdout 不变量），已入账并销账。
- **六顶帽辩论真跑通**：方向三计划明写「工具在、真辩论留给 DSH 编排」，本会话把这条落地为 `debate-20261010-001` 三帽判决 + 收敛读数，形成可审计的决策证据链。
- **四守卫全绿的计数同步补完**：134→135 跨 7 个文件 + CLI 帮助分组表，是本会话机械补完（非计划新增项）。

## 来源

- 计划：`docs/improvement-plan-20261010.md`
- 账本：`memory/bugs.md`（BUG-143 OPEN→FIXED）
- 日志：`memory/2026-10-10.md`（本会话追加段）
- 提交链（并发方，供回溯）：`9bc041e`→`b2cc23b`→`06fc7cd`→`aa0fccf`→`dc6525f`→`3655b33`→`ad13992`→`bd99a6f`
- 辩论记录：`debate-20261010-001`（进程内会话，重启即失）
- 验证读数：`moon test --target js` = 662/662；四必需守卫 RC=0；`gen_plugins.py` 135 工具