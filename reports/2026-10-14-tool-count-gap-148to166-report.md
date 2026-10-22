# 2026-10-14 · 闭合 148→166 工具计数差口报告（判据扩面 + 文档补齐）

## 结果摘要

**一句话**：用户建议的实现——工具注册从 `server.mbt` 拆到独立文件后，运行态 166 而三支判据真源仍只扫
`server.mbt`（148）⇒ 文档面被迫对 148 自洽。本轮把三支判据真源扩面（含 `mcpcf.*` 带点工具名的识别缺口），
并把 18 个"实现已在、文档没列"的工具补进 AGENTS/README/CLI 帮助/ARCHITECTURE。

| 项 | 读数 |
|---|---|
| 判据真源 | `src/server/*.mbt`（排除测试）+ 两种注册形态并集 ⇒ 148→**166** |
| `check_tools_sync` | **PASS**（166 个，四份文档对齐） |
| `check_doc_surface` | **PASS**（166 工具逐个可查、分组和=166、J6-J9 全过） |
| `mcp_smoke` | **PASS**（tools/list → 166） |
| `moon check --target js` | **rc=0**（45 tasks 0 errors，改 .mbt 后复验）|
| 七守卫链 | 全 PASS（+ test_sync 1033 / badge） |

提交 `c7e6ad7`（8 文件，精确 add 无并发连带），已推 origin + gitcode。

## 缺口定位（从 18 差口到具体形状）

先用**已验证可用的 mcp_smoke 握手形态**取运行态真值，与三种静态口径对表：

| 扫描面 | 工具数 |
|---|---|
| `server.mbt` + `instrumented_tool`（判据旧口径）| 148 |
| `src/server/*.mbt` + 两种形态 | **166** |
| 运行态 `tools/list` | **166** |

差 18 个构成：
- `supervisor_*` 8 个 —— 在 `src/server/supervisor_tools.mbt`（走 instrumented_tool）
- `hat_run`/`hat_debate`/`hat_merge` 3 个 —— 在 `src/server/hat_hexa_tools.mbt`
- `mcpcf.*` 7 个 —— 在 `src/server/mcpcf_embed.mbt`（走**链式** `s.tool("name", …)`）
  ⇒ 连"宽松"正则也抓不到，必须额外认一种形态

## 判据侧：三处同族缺口 + 一处识别缺口

**同族缺口（真源扫描面没跟上拆分）**：
1. `check_tools_sync.py` L36/L82 只 `SERVER.read_text()` ⇒ `real_tools()` 扩为全包 + 两形态并集
2. `check_doc_surface.py` L104/L146/L804 同样三处 ⇒ 同口径（`real_tools()` + `j14_tool_count_claims`）
3. `mcp_smoke.py`（上一轮已修，本轮确认仍在位）

**识别缺口（J2 恒报"未逐个列出"的真因）**：
`check_doc_surface.py` 的 `RE_BACKTICK` 原为 `` `([a-z_][a-z_0-9]*)` `` ——**不含 `.`**
⇒ `mcpcf.circuit` 这类带点工具名在文档里**永远匹配不上**。
首轮补完文档后仍报 7 个缺失才定位到它（若只按"文档没写"推进会一直打转）。

## 文档面补齐（18 个，全部"实现已在、文档没列"）

| 文件 | 改动 |
|---|---|
| `AGENTS.md` | 六顶帽 4→7（补 hat_run/hat_debate/hat_merge）+ 新增「超级管家专属工具（8）」节 + 新增「嵌入式 MCPCf 内部工具（7）」节 |
| `README.md` | 同样两节新增 + 六顶帽 4→7（分组数同步）|
| `cmd/cli/help_topics.mbt` | Six-Hats 4→7、新增 `[Supervisor 8]` 与 `[MCPCf-Embed 7]` 两组、三处总数 148→166、组数 15→17 |
| `ARCHITECTURE.md` | 「148 工具分组」→「166 工具分组」|
| `README_EN.md` | 目录树三元组 148→166 |
| `src/server/server.mbt` | 头注释三元组 148→166（**纯注释行**，不动并发逻辑）|

## L4 实测（全部实跑）

| 判据/命令 | 结果 |
|---|---|
| `moon check --target js` | `Finished. moon: ran 45 tasks … 0 errors`（rc=0）|
| `check_tools_sync` | `PASS … server.mbt 注册 166 个，AGENTS/README/deliverable/scoring_rubric 对齐` |
| `check_doc_surface` | `PASS … 166 工具在 AGENTS/README 逐个可查、分组和=166 … J9 返回契约` |
| `mcp_smoke` | `PASS tools/list → 166 个工具` + `MCP-SMOKE PASS` |
| 五守卫 | scripts_index / py_stdout / ps_encoding / pkg_imports / mbti_sync 全 PASS |
| `check_test_sync` / `check_badge` | PASS（1033 / badge） |

> 过程中 `check_doc_surface` 曾出现"假绿"（148 口径自洽）⇒ 扩面后才报真缺口；
> 这正是"判据范围自述==实现"（J10）的又一生动例证：判据自己旧了比没有判据更危险。

## 资源消耗

- 探针 1 支（`temp/gap_probe92.py`，基于 mcp_smoke 同款握手；此前两版自造握手探针均死等/读空，
  **第三版改为复用仓内已验证形态后才拿到真值**）
- `moon check` 1 次（45 tasks）；判据复跑约 10 次（每步修完立即验）
- 零 `.mbt` 逻辑改动（只改头注释一行与 CLI 帮助字符串）

## 任务分配记录

- 指挥官亲自：定位差口（探针对表）→ 判据扩面（3 处）→ 识别缺口（RE_BACKTICK）→
  文档补齐（4 文件）→ 逐判据复验 → 提交。
- **未派子代理**：本链要害是"哪些工具真在运行态"与"带点工具名的识别缺口"，误判会导致补错文档。
- 边界：`git add` 精确列 8 个文件（`git show` 确认无并发连带）；`server.mbt` 只改头注释一行。

## 遗留风险

1. **另有两处同族缺口未修**（本轮只修了自己在跑的三支）：
   - `check_plugin_sync.py` L109 与 `gen_plugins.py` L201 的真源仍是 `server.mbt` 单文件
     ⇒ 插件态投影/cl7 会拿 148 口径工作。**建议**同口径扩面（属 WIP 面但不是我的）。
2. **`fist help tools` 的分组表是手写清单**：本次已补齐 166，但工具增减仍需人工同步该表
   ⇒ 长期看应改由真源生成（属改进项）。
3. **L33 翻账的前置已就绪**：工具数 148→166 的一致口径已建立，翻账方现在可以
   "连同工具数一起翻"（本报告即事实链）。

## 后续建议

1. **`check_plugin_sync`/`gen_plugins` 同口径扩面**（价值直接）：否则插件态 SKILL.md 的
   `tools=` 会停在 148，cl7 自洽假绿。
2. **L33 翻账**：判据口径已统一（166），翻账方按 `reports/2026-10-14-l33-self-search-fact-report.md`
   的事实链连同工具数一起翻。
3. **`fist help tools` 改真源生成**（可选）：消掉"手写分组表"这个持续漂移面。
4. **给"带点工具名"建一支识别回归**：本次 `mcpcf.*` 的 `.` 卡了 J2，可加 selftest 格锁定。

## 超额内容

- 顺带**发现 J2 恒报缺失的真因不是"文档没写"而是"正则不认 `.`"**——避免了在错误方向上
  反复补文档（首轮补完仍报 7 个缺失就是这个信号）。
- 顺带**识别并记录"判据假绿"**：`check_doc_surface` 在 148 口径下自洽 PASS，比没有判据更危险
  ⇒ 本轮把三支判据的真源一起扩面，消掉了这个自洽面。
- 顺带**第三版探针才成功**：前两版自造握手（通知帧/带 id initialize）分别死等与读空，
  最终改为复用 `mcp_smoke.py` 的同款 `rpc()` 形态才稳定拿到 166 —— 印证"不自造协议、复用仓内已验证件"。

## 来源

- 探针：`temp/gap_probe92.py`（mcp_smoke 同款握手；输出 server.mbt=148 / 全包=166 / 运行态=166、
  差口 18 个逐个列名与归属）
- 判据：`scripts/check_tools_sync.py`（real_tools 扩面）、`scripts/check_doc_surface.py`
  （real_tools + RE_BACKTICK 加 `.` + j14 计数）、`scripts/mcp_smoke.py`（前序轮已修）
- 文档：`AGENTS.md`、`README.md`、`README_EN.md`、`ARCHITECTURE.md`、`cmd/cli/help_topics.mbt`、
  `src/server/server.mbt`（仅头注释）
- 读数：moon check rc=0(45 tasks)；tools_sync PASS 166；doc_surface PASS 166；mcp_smoke PASS 166
- 提交：`c7e6ad7`（8 files, +85/-15）；三端同步
