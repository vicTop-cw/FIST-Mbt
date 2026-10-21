# 2026-10-13 · BACKLOG 对表翻账第三批报告（L16 / L27 / L24）

## 结果摘要

**一句话**：本轮把 BACKLOG 里三处「账面落后于事实」的条目逐条核实并精确更新——
**2 条由 `pending` 翻 `done`（有实现 + 测试实证）**，**1 条 `blocked` 的技术理由已过时但保留 owner 决策**。

| 行 | 事项 | 前 | 后 | 依据 |
|---|---|---|---|---|
| L27 | Pre-execution audit gate | pending | **done** | 实现 + 2 插入点 + 7 锁，`src/engine` 146/146 实测全绿 |
| L24 | 补充 ARCHITECTURE.md（9 模块关系图+数据流+MCP 协议层） | pending | **done** | 三要素逐项指认在位（97 行、已跟踪） |
| L16 | native 侧真实自驱巡检 | blocked | **pending（前置已达成，待 owner 复核决策）** | BUG-133 两格实测达成 + 账本已 FIXED |

三段提交：`cda694b`（L16）、`0b65e1a`（L27）、`f3228ad`（L24），均双远端同步。

## 逐条取证

**L27（翻 done）**——判据面三件齐备才算落地，故逐件核：
- **实现**：`FistEngine::audit_execute_gate`（`src/engine/omega_strong.mbt:228`），拦「空交付物」与
  「占位符交付物」（`done`/`完成`/`ok`/`通过` 等，大小写与杂散空白/标点容忍；R10 修过"只 to_lower、
  注释承诺的标点容忍落空"那处漏洞）
- **插入点 2 处**（BACKLOG 要求"`can_execute` 之后、`execute` 之前"）：`src/engine/engine.mbt:189` 与 `:227`
  ——两条 execute 路径都覆盖，源码注释逐字自述"预执行审计门禁（P2 BACKLOG）"
- **测试锁 7 个**：`omega_strong_test.mbt` 六格 `omega_audit_gate_*` + `engine_boundary_test.mbt:183
  property_audit_gate_empty_only`
- **L4 实测**（不据源码存在就翻）：`moon test --target js -p vicTop-cw/fist-mbt/src/engine`
  ⇒ `Total tests: 146, passed: 146, failed: 0`；`--verbose` **逐条列出**那 7 个测试均 `ok`
  （这一手是必要的：只看汇总行无法区分"测试存在但被过滤"与"真跑过"）
- 边界如实入账：只拦确定性问题（空 / 纯占位符），不做语义判定以免过度拦截

**L24（翻 done）**——三要素**逐项指认**，不以"文件存在"充当证据：
① 五层 ASCII 关系图（§一「总分结构」）：协议层 `src/server`（`server.mbt` 工具注册 + `run_server`、
`stdio_js`/`stdio_native` 双端 STDIO）→ 引擎层 `src/engine`+`src/core`（九态状态机 / 角色矩阵 / 递归拆解 /
DAG / Omega）→ 运维层 `src/ops` → 存储层 `src/store` → 自进化层 `src/evolve`+`src/executor`；
② §二「一条关键数据流（外部调用一次 `publish`）」：JSON-RPC → 协议层 `tools/call` → 引擎层角色校验
（`human_steward` 唯一权威）→ 状态机 → Store 落库 → 回执；
③ §一 ① 即 MCP 协议层（含 `JSON-RPC over STDIO / HTTP-SSE` 传输形状）。

**L16（更新 blocked 理由，不代翻决策）**——该行结构是"决策 + 理由"两段：
- 第一句是 owner 的**独立决策**：「决定：现在不建」（2026-10-07，owner"2 条都你来决策"）
- 第二句才是技术理由：「前置＝BUG-133 的两格关闭条件」
- 该前置**已实测达成**（账本抬头 FIXED；干净树 `moon test --target native` 807/807 rc=0、
  探针连发 3 发 `crashes=0/12`，原件见 `temp/archive_native_direct.txt` + `temp/probe_repeat_direct.txt`）
⇒ 状态改为 `pending(2026-10-13 前置复核：…均已实测达成…)`，**并把原句保留在括号里供复核者对照**；
`是否改为"现在建"仍属 owner 复核`——前置达成推翻的是技术理由，不是决策本身。

## 关键方法学：三次「先反解真原文，再构造替换」

本轮三次翻账各踩/避了一次锚点风险：
1. **L24 首版失败**：我按印象写了来源列 `five-directions/§一`，实际是
   `competition/§四 P2-10 + future-roadmap/中` ⇒ 替换断言失败、构造未生成。
   **改用从 `git show HEAD:BACKLOG.md` 反解出的真原文**后成功。这是"不猜锚点"的现场价值——
   若当时不断言而直接写，会静默地把来源列改错。
2. **L27/L16** 同样先用 `assert old in t` 守住锚点，再替换；替换后逐行 diff 核对
   `差异行=[27]` / `[16]` / `[24]`，并全表核 `竖线=6 无坏行`（BACKLOG 是 selfdrive 的净拉取源，
   表格结构本身也是契约）。
3. **翻账不写计数**：L24 的说明里刻意不写"145 工具"——HEAD 版是 140，而并发会话正在 WIP 里校正到 145；
   代写任一数字都会在别人提交后立刻变成新的漂移雷。

## 资源消耗

- 干净树守卫验证 3 次（每次 `git archive HEAD` + `git init` + `add -A -f` 模拟 CI 检出面）；
- `moon test` 1 次（`-p src/engine` 146 测试，含一次 `--verbose` 重跑以确认 7 锁真执行）；
- 逐行 diff 校验 6 次（含 1 次失败重做）；
- 本链零 `.mbt` 改动、零网络请求。

## 任务分配记录

- 指挥官亲自：三次真原文反解 → 构造 → 逐行校验 → 干净树守卫验证 → 精确暂存 → 提交。
- **未派子代理**：每步都要与并发会话的 WIP 做归属判定（BACKLOG 带 32 行他人 WIP），
  外包会引入"代提交他人账"的风险，正是本仓禁的那类动作。
- 边界：全程只动 `BACKLOG.md`（用索引法，并发 WIP 原样留在工作树）；`src/**`(92 脏)、
  `docs/**`、`ARCHITECTURE.md`（并发 WIP 正改计数）、`memory/**` 均未碰未提交。

## 遗留风险

1. **L24 的 done 说明与 ARCHITECTURE.md 正文暂时不同版本**：正文被并发会话改成 145 而说明列不写计数；
   这不是缺陷，但复核者若对照会发现"文件里的数"与"账面描述"不同步——**那是执意为之**（见方法学 3）。
2. **L16 仍在 pending 且带 owner 决策句**：我只更新了事实面。若 owner 复核后决定"现在建"，该行需再改一次；
   若维持"不建"，可把状态收成 `won't-do(前置已达成但决定不建)`——两种都属 owner 裁决。
3. **本轮未碰的 pending 项已逐条粗核**（保持 pending 正确）：L31 `moonbitlang/core/diff` 集成是**真空**
   （`moon.mod` 无 diff 依赖、源码无真实 diff 用法，两处命中都是 `difficulty` 的误匹配）；
   L43/L44 是外部资产调研（`gaato/github API 客户端`、`colmugx/posoco`）；L35~L42 为设计类。
   这些**未逐项深核**，下一轮可继续同法（尤其 L33 self_search 的"入库半"与 L49 file_binds）。
4. **`check_doc_surface` 的 J11 在本轮翻完 L16 后仍 PASS**（BUG-133 已 FIXED ⇒ 该格自然失效），
   与账本口径一致；但若 owner 决定"现在建 native 巡检"，该格会被重新激活，需与 workflow 步名对表。

## 后续建议

1. **继续同法扫完剩余 pending**：L33（self_search 入库半）、L49（file_binds 多管家协调层）、
   L35~L42（设计类，多为"未实现"而非"未翻账"）。判据仍是"实现/测试/插入点三件齐备才算 done"。
2. **给 BACKLOG 造一支"翻账锚点自检"**：本轮 L24 的失败说明"来源列不同就无法断言替换"——
   可写一支只读脚本，按事项标题（而非整行）定位行、报出当前状态与原文，供翻账前取锚。
3. **计数一律不写进翻账说明**：本轮已按此执行；建议写进本仓记账惯例（与 J14「工具计数单一真源」互补）。

## 超额内容

- 顺带把"机器可读锚点必须反解、不可凭印象"从教训变成三处可复现的现场记录（一次真失败 + 两次守备）。
- 顺带确认 L31 是真空而非遗漏——避免下一轮把它误当"已实现未翻账"重做一遍（本仓明令勿重复造）。

## 来源

- 真原文与校验：`git show HEAD:BACKLOG.md` 逐行 diff（差异行 `[16]` / `[27]` / `[24]`，63 行对 63 行）。
- L27 实证：`moon test --target js -p vicTop-cw/fist-mbt/src/engine` ⇒ 146/146 + `--verbose` 逐条 `ok`；
  实现 `src/engine/omega_strong.mbt:228`、插入点 `src/engine/engine.mbt:189`/`:227`、
  测试 `src/engine/omega_strong_test.mbt`（6 格）、`src/engine/engine_boundary_test.mbt:183`。
- L24 实证：`ARCHITECTURE.md`（97 行、`git ls-files` 已跟踪）§一/§二/§一① 三处要素；
  `src/` 下 11 个包目录（图覆盖其中 9 个）。
- L16 前置实证：`temp/archive_native_direct.txt`（807/807 rc=0）、`temp/probe_repeat_direct.txt`（连发 3 发 0/12）、
  `memory/bugs.md` 抬头 `## BUG-133 … [high] FIXED`、
  `reports/2026-10-13-native-arms-green-bug133-report.md`。
- 暂存态守卫：`check_doc_surface` rc=0、`check_release_asset_names` rc=0（干净树 + 暂存版 BACKLOG）。
- 提交：`cda694b` / `0b65e1a` / `f3228ad`。
