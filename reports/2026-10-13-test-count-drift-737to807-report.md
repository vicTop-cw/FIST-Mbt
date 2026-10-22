# 2026-10-13 · 测试总数漂移定因与修复报告（737 → 807）

## 结果摘要

**一句话**：`check_test_sync` 在干净树（CI 检出面）长期红 **31 条 R1 + 5 条 R2**，真因是文档自述 **737**
（2026-10-11 旧读数）而 HEAD 实测 **807**；本轮两批处置把违例压到 **R1=15 / R2=4**。

| 项 | 数值 |
|---|---|
| 修复前（干净树） | R1=31 / R2=5 |
| 第一批后（4 个干净面文件改数） | R1=23 / R2=4 |
| 第二批后（6 条 EXEMPT 登记） | **R1=15 / R2=4** |
| 剩余 15 条 | **全在 7 个并发会话 WIP 面**（见「结构性限制」节） |

提交：`e51d57c`（第一批 4 文件 6 行）、`52ded47`（第二批 6 条豁免 + 夹具扩展），双远端同步。

**两批合计清掉 16 条 R1 + 1 条 R2**，且 `--selftest` 保持 **rc=0 PASS**（8 变体各自命中自己指名的判据）。

## 定因：为什么是 807 而不是 737（对照实验）

| 面 | 读数 |
|---|---|
| 干净树（HEAD）+ 本地钉版 moon `-j 1` | **807/807** |
| 干净树（HEAD）+ CI nightly | **807/807**（CI #288 实证） |
| 工作树（含并发 WIP）+ 本地钉版 | **822/822** |

⇒ 差异**不是 moon 版本**（两代 moon 同树同读数），而是**并发会话未提交的 WIP 新增了 15 个测试**
（工作树 216→253 个 `.mbt` 文件）。故 **807 是 HEAD 真值**，文档的 737 属真·历史漂移。

## 一条写法纪律（本轮踩出的，已写进提交信息）

带历史日期的现状断言必须**数字与日期成对更新**：
- 只改数字 ⇒ 写成「2026-10-11 测出 807」（伪造了一次没发生的测量）
- 只改日期 ⇒ 写成「2026-10-13 测出 737」（同样是假历史）
- 正确形：`737 项全绿，2026-10-11` → `807 项全绿，2026-10-13`（807 确为本机 2026-10-13 实测）

这与本仓 `EXEMPT` 表里那四条 native `572` 的处置逻辑同源（「把 572 改成 573 等于伪造一次没发生过的测量」）。

## 分类口径（为什么只修 4 个文件）

| 类别 | 文件 | 处置 | 理由 |
|---|---|---|---|
| A 干净面 + 现状断言 | `docs/agent-map.md` / `docs/SHIP-PLAN-BLACKBOX-v2.md` / `docs/evolve.md` / `docs/atgc-selfdrive-demo.md` | **本批修** | worktree==HEAD，不含他人 WIP；语义是"当前/现状"谓词 |
| B 现状断言但在 WIP 面 | README.md / README_EN.md / README.mbt.md / AGENTS.md / ARCHITECTURE.md / `docs/deliverable.md` / `scripts/scoring_rubric.md` | **留待其 owner** | 均为并发会话未提交面（7 个）；提交会连带他人 WIP——本会话纪律禁止 |
| C 当轮实测记录 | `BACKLOG.md`（811/737/86/23/62）、`docs/improvement-plan-20261010.md:86` | **第二批已处置：登记 EXEMPT** | 改写即伪造历史；判据 docstring L12 明确 prescribe「合法的历史数必须逐条点名」 |

**C 类的处置（第二批，`52ded47`）**：按判据自述的机制登记 6 条豁免，而不是改写历史行——
`BACKLOG.md` 的 811/737/86/23/62 五条 + `docs/improvement-plan-20261010.md` 的 737 一条。
其中 `86`（`src/router` 单包）、`23`/`62`（`check_py_stdout_encoding` 的 CI 面/--all 面自检读数）
**本就不是全量测试总数声明**，属判据窄口径的过度捕获面；登记豁免是"不误伤"，收窄正则那条
影响面更大（改判据本体）⇒ 留 owner。

**R4 连带面（判据的设计要求）**：每条 EXEMPT 必须在 selftest 夹具里有对应声明，否则判「豁免失效」。
故同步扩夹具（BACKLOG 夹具五行 + 新增 improvement-plan 夹具条目）。调试中踩到**两处夹具自身缺陷**
并修正：① 先写成字面反斜杠 n 的单行串（`collect_claims` 按行扫，只认第 1 行）；
② 用了 `RX_KEY` 不认的「通过」措辞（RX_KEY = `测试|用例|全绿|passed|test`）。两处都属
"判据自己的夹具坏了"那一档，留档防后来者重犯。

**C 类需要单独说明**：`BACKLOG.md:47/48` 的 `86/86`（`src/router` 单包）、`23/23`、`62/62`
（守卫脚本自检面）都**不是全量测试总数**，但 `check_test_sync` 的窄口径（`N/N` + 同行测试语义词）
把它们当作全量声明判红。这属**判据的过度捕获**——要么判据加"仅前后文有『全量/总』限定词才计"，
要么那些 done 行改写；**两种都属 owner 裁决**，本轮未擅动（并在报告里点名）。

## 资源消耗

- 干净树实验 3 次（每次 `git archive HEAD` + `git init` + `add -A -f`）；
- 守卫复跑：`check_test_sync` 3 次 + `check_doc_surface` / `check_release_asset_names` /
  `check_entry_paths` 各 1 次；
- 逐文件 diff 核对 4 次；本链零 `.mbt` 改动、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：对照实验定因（807 vs 822）→ 逐处审计 737 语境（39 处）→ 分类 → 构造与逐行核对
  → 干净树验证 → 提交。
- **未派子代理**：本链每一步都要判定"该文件是不是他人 WIP 面"（13 个文件里 7 个是），
  外包会引入连带提交他人 WIP 的风险。
- 边界：只动 4 个干净面 docs；`README.md` / `README_EN.md` / `README.mbt.md` / `AGENTS.md` /
  `ARCHITECTURE.md` / `docs/deliverable.md` / `scripts/scoring_rubric.md` / `BACKLOG.md` /
  `docs/improvement-plan-20261010.md` 一律未碰。

## 结构性限制（为什么 R1=15 / R2=4 是当前可达的下界）

干净树终审（新 HEAD `52ded47`）剩余 **15 条 R1 全在这 7 个文件**：
`README.md` / `README_EN.md` / `README.mbt.md` / `AGENTS.md` / `ARCHITECTURE.md` /
`docs/deliverable.md` / `scripts/scoring_rubric.md`。

**这 7 个全部是并发会话的未提交 WIP 面**（` M`）。本会话纪律禁止连带提交他人 WIP，故：
只要它们的 WIP 未落地，`check_test_sync` 与 `check_badge`（README 徽章同写 737）**就一直红**——
这不是"我的修法无效"，而是"干净面已修尽、剩余须由其 owner 收口"的结构性下界。
**唯一能同时转绿的时机**是那份 WIP 落地时：由那一方（或下一轮的我）把 737→807 与徽章一起改。

## 遗留风险

1. **R1=23 / R2=4 仍红**，且 R2 的四份（README.md / AGENTS.md / `docs/deliverable.md` /
   `scripts/scoring_rubric.md`）**全是并发 WIP 面** ⇒ 只要它们的 WIP 未落地，`check_test_sync` 就一直红。
   这不是"我的修法无效"，是"修法只能覆盖干净面"这一结构性限制。
2. **`check_test_sync` 与 `check_badge` 互锁**：徽章在 README（WIP 面）里同样写 737，
   `check_badge` 报 `BADGE-STALE`。两份红同源，须**同一批**修（否则改一处另一处仍红）。
3. **C 类的过度捕获**（见上）未处置，可能被后来者误当作"文档写错"去改 done 行 —— 那是伪造历史。
4. **本批的 4 个文件在 J15/J13 面上无影响**（已复跑三支守卫 PASS），但 `docs/SHIP-PLAN-BLACKBOX-v2.md`
   的 L219/L377 是**验收标准快照**——把 737 改成 807 等于把当时的验收线抬到今天的读数；
   语义上可辩（"通过标准"随实测走），但与"历史快照"的边界值得 owner 确认。

## 后续建议

1. **测试计数单一真源**：README 徽章 + `check_test_sync`（文档）+ `check_tools_sync`（工具面）三处
   各写各的数、各有判据。建议由 CI 在跑完 `moon test` 后生成一份计数基线（如 `scripts/counts.json`），
   三支都读它 —— 否则每次都要在"改文档还是改徽章"之间来回。
2. **把 `check_test_sync` 的过度捕获收窄**：加"仅同行出现『全量/总/所有』等限定词才计"，
   或维护一份"局部计数豁免"表（如 `src/router` 86、脚本自检 23/62）——两者都需 owner 定。
3. **`docs/SHIP-PLAN-BLACKBOX-v2.md` 的验收快照语义**：建议区分「当时验收线」与「当前实测」两种表格列。
4. **WIP 落地后一次性收口**：等并发会话提交 README/AGENTS/ARCHITECTURE/deliverable/scoring_rubric 后，
   由那一方（或下一轮的我）把 737→807 与徽章一起改 —— 那才是 `check_test_sync` + `check_badge`
   能同时转绿的唯一时机。

## 超额内容

- 顺带确立"807 是 HEAD 真值"的对照实验（同树换工具链 = 807、同工具链换树 = 822），把
  「文档该写哪个数」这个悬置问题**用读数钉死**，而不是靠猜 moon 版本。
- 顺带**审计了全部 39 处 737 的语境**（`temp/audit737.txt`），确认无年份/编号误混，
  从而敢用批量替换而不是逐处精修。
- 顺带纠正我自己一处**PowerShell 计数假象**（再次：`Select-String` 计数报 0 而落盘重数为 23）——
  这已是本会话第二次踩，报告里留档。

## 来源

- 违例原件：`E:\temp\c65b\ts_after.txt`（修复后 R1=23/R2=4）、修复前清单 `E:\temp\counts_dump.txt`。
- 737 语境审计：`E:\temp\audit737.txt`（39 处逐行上下文）。
- 对照实验读数：干净树本地钉版 = 807；工作树本地钉版 = 822；CI #288 native/windows ✅、
  js,ubuntu `Test (js)` 807/807（`Format ✗` 之后 skip）。
- 判据面：`scripts/check_test_sync.py` 的 `MUST_CARRY`(L51-57) / `EXEMPT`(L63-75) / `judge()`(L168-205) /
  窄口径自述(L17-26)。
- 提交：`e51d57c`（4 文件 6 行）。
