# 2026-10-14 · 新增 check_plan_landing 计划落点核对工具报告

> 日期说明：本链跨过零点（工作始于 2026-10-13 深夜，收口于 2026-10-14 00:0x），报告按**收口当日**命名。

## 结果摘要

**一句话**：本会话反复遇到「计划说某文件已实现/将新增，但该文件不在 HEAD」，
本轮把这种核对机械化——`scripts/check_plan_landing.py` 扫 `docs/` 里反引号点名的仓内路径，
三态标注 `tracked` / `on-disk`（**在工作树、只是没进跟踪面**）/ `missing`。

| 项 | 读数 |
|---|---|
| `--selftest` | **11 格全过** |
| 变异实测 | **4/4 被抓住** |
| 全量（38 份文档 / 249 条点名路径） | 未在跟踪面 **58** 条（磁盘上有 **5** 条、都没有 53 条） |
| 首跑误报 → 修正后 | **82 → 58**（修掉 24 条"存在的目录被误报"） |
| **首跑抓到本工具两处自身缺陷** | ① `disk_set` 只收文件；② 一行**死代码** |

提交：`9267572`（工具）、`ec6064a`（README 登记）。双远端同步。

## 要解决的问题（本会话实测清单）

| 实例 | 形状 |
|---|---|
| `supervisor-tools` 计划 §5 的 `src/server/supervisor_tools_test.mbt` | 计划点名、**文件根本不存在**（测试锁未做）|
| 同计划两个新增实现（`supervisor_tools.mbt` 471 行 + `engine_supervisor.mbt` 622 行）| **在磁盘却不在 HEAD** |
| `web-dashboard` 计划 M0 后端 `scripts/fist-mbt-web.py` | **README 登记已入库、本体却未跟踪**（已在本会话第 76 轮补提交）|
| 多份 design v2/v3 点名的 `engine_assistant.mbt` / `store_assistant.mbt` | **在磁盘、不在 HEAD** |

⇒ 人工逐份核对要读十几份文档、几十个路径，极易漏。本工具把这步机械化。

## 判据设计（窄口径 + 刻意不是门禁）

**三态**：
- `tracked` —— 在 `git ls-files`（常态，不报）
- `on-disk` —— **在工作树磁盘上、只是没进跟踪面** ⇒ 出路是 `git add` 并提交
- `missing` —— 跟踪面与磁盘都没有 ⇒ 若计划说"已完成"则是虚报；若说"将新增"属正常未做

**刻意不是门禁**：计划写「将新增尚不存在的文件」是**合法的** ⇒ `missing` 只是诊断读数。
退出码 1 表示"有落点未落地"，**不代表 CI 该红**。若做成门禁，`docs/` 里大量"将新增"条目会恒红。

**刻意不判**：状态列语义（散文机器判不了，判了就是伪精确）；裸路径（会引入大量误报）。
**防空转**：零文档或零路径 ⇒ FATAL。

**抽取口径**：只认反引号包裹 + 仓内顶层目录开头（`src/` `scripts/` `cmd/` `docs/` `templates/` `plugins/`
`patches/` `reports/` `memory/` `specs/` `resources/` `.github/`）+ 已知扩展名（或目录形态）。

## L4 实测（金条八）

**`--selftest` 11 格**：
1. `extract-basic`（认三种仓内路径）2. `extract-rejects-foreign`（绝对/非仓内/裸命令名不认）
3. `extract-rejects-abs-only`（`/src/...` 必须被拒）4. `extract-dir-form`（目录去斜杠）
5. `clean-no-findings`（干净不误报）6. `on-disk-detected`（必报 on-disk）
7. `missing-detected`（必报 missing）8. `tracked-dirs-derived`（从跟踪文件反解隐含目录）
9. `tracked-dirs-empty-when-noinput` 10. `tracked-dir-not-reported`（已跟踪目录不误报）
11. `untracked-dir-on-disk` + `empty-doc-counts-zero`

**变异实测 4/4 被抓住**：

| # | 变异 | 抓它的格 |
|---|---|---|
| 1 | 磁盘判定恒 False | `on-disk-detected` |
| 2 | 跟踪目录反解架空（恒空集） | `tracked-dirs-derived` |
| 3 | 抽取口径放宽（认非仓内顶层） | `extract-rejects-foreign` |
| 4 | 目录判定反（已跟踪目录也报） | `clean-no-findings` |

**全量读数（承重证据）**：
```
INFO 计划落点核对（38 份文档、249 条点名路径）：未在跟踪面 58 条（其中磁盘上有 5 条、都没有 53 条）
- [on-disk] docs/2026-10-11-multi-agent-lock-design-v2.md 点名 `src/engine/engine_assistant.mbt`
- [on-disk] docs/2026-10-11-multi-agent-lock-design-v2.md 点名 `src/store/store_assistant.mbt`
- [on-disk] docs/2026-10-11-multi-agent-lock-design-v3.md 点名 `src/engine/engine_assistant.mbt`
- [on-disk] docs/2026-10-11-multi-agent-lock-design-v3.md 点名 `src/store/store_assistant.mbt`
- [on-disk] docs/posoco-hexagonal-architecture.md 点名 `src/constraint`
```
⇒ 那 5 条 `on-disk` 就是**可 `git add` 的现成交付**（其中 2 个正是 `check_mbti_sync` 报的悬空符号来源）。

## 首跑抓到的两处自身缺陷（对抗式用法的价值）

| # | 缺陷 | 症状 | 修法 |
|---|---|---|---|
| ① | `disk_set` 只收集**文件** | `cmd/cli` / `src/store` / `src/router` / `scripts/blackbox` 等**明明存在的目录**被误报 `missing`（82 条里占 24 条）| 同时收集目录 + `tracked_dirs` 反解隐含目录 + 前缀匹配判磁盘 |
| ② | 单独的 `startswith("/")` 绝对路径拦截 | 是**死代码**——`TOP_DIRS` 闸（要求以 `src/` 等开头）已天然排除 `/` 开头者；变异实测"去掉它"**无格可抓** | 删除该行，改由 `extract-rejects-abs-only` 格锁定"绝对路径必须被拒" |

> ②尤其值得记：**变异测试发现了一行永不生效的防御代码**。若不跑变异，我会以为"绝对路径有专门拦截"
> 而交付一份含死代码的判据——死代码比没有更危险（读的人以为那面已被守住）。

## 资源消耗

- 全量跑 3 次（首跑 82 条 → 修目录后 58 条 → 终态 58 条）、`--selftest` 跑 7 次（含变异前后）；每次 < 5s（纯文件扫描，不跑 moon）；
- 变异实测 2 轮（首轮 5 处锚点含 2 处写错 → 修正后 4/4 命中）；
- 本链零 `.mbt` 改动、零 `moon` 调用、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：动机梳理（本会话 4 类实例）→ 判据口径取舍（为何不是门禁）→ 实现 → selftest →
  首跑实测（抓到 2 处自身缺陷）→ 修 → 变异实测 → 登记 → 报告。
- **未派子代理**：本链要害是"判据口径取舍（是门禁还是诊断）"与"首跑误报的根因归属"
  （是抽取错、还是 disk 集合形态错），外包会引入误判。
- 边界：只新增一支只读诊断工具 + README 一行；未改 `.mbt`、未代提交他人 WIP。

## 遗留风险

1. **工具是诊断而非门禁，故不会自己"红得有意义"**：`docs/` 里合法的"将新增"条目使它恒有读数。
   若未来要接 CI，必须先有"状态列语义"的机器可读标记（如 `[已实现]` 标签），否则会恒红。
2. **抽取依赖反引号惯例**：裸路径（无反引号）不认 ⇒ 计划里写成裸路径的落点会漏。
   **建议**：文档写作时统一用反引号包路径（本仓已是惯例，但非强制）。
3. **`missing` 与"虚报"的区分靠散文**：工具给出两可提示（"若已说完成则是虚报 / 若说将新增属正常"），
   实际判断仍需人读计划原文。**这是刻意的**——不假装机器能读散文。
4. **目录形态的 `on-disk` 判定用前缀匹配**：可能把 `src/constraint` 这类**新包目录**判为 on-disk
   （正确，因为其下有未跟踪文件）；但也意味着**空目录**不会被判。
5. **P0（未变）**：HEAD 编译不过（20 errors）。本工具的输出已把其中 2 个悬空符号的源文件
   （`engine_assistant.mbt` / `store_assistant.mbt`）列为 `on-disk` ⇒ **并列证据再次指向"整批 git add"**。

## 后续建议

1. **把本工具接进提交前流程**（与 `simulate_head_commit.py` 互补）：后者管"编译面能不能过"，
   本工具管"计划点名的落点有没有落地"；两者一起跑可覆盖本会话两类坏状态。
2. **给计划文档加机器可读的状态标记**（可选，使本工具可升级为门禁）：
   如 `` `src/x.mbt` `` 后跟 `[已实现]` / `[将新增]` —— 有了它，`已实现` 而 `missing` 就能真红。
3. **复用本工具核查其余计划文档**：`multilang-sdk-plan` / `reminder-role-plan` / `hexamind-design` /
   `supervisor-role-design` / `web-dashboard-plan`（后者的 M0 已在本会话补提交）。
4. **把"死代码也要有格抓"写进判据纪律**：本轮变异发现的那行永不生效的绝对路径拦截
   （本会话在 `check_entry_paths` 的历史记录里也见过同型："被自家注释喂回针的那格变异不红"）⇒
   **每条防御性判断都应有变异格证明它真在生效**。

## 超额内容

- 顺带**用首跑实测（真数据）抓到本工具两处自身缺陷**，而非靠合成用例发现——真文档的形态
  （目录落点、绝对路径写法）比我的合成用例更丰富。
- 顺带**发现一行死代码防御**（绝对路径拦截），并把它转化为一格显式 self-证（`extract-rejects-abs-only`）。
- 顺带**量化了本会话的坏状态家族**：把 4 类实例（缺测试 / 实现未提交 / 登记与本体分离 / design 点名未落地）
  归到同一工具的三态输出下，使"哪一类还剩多少"一眼可数。
- 顺带**误报量化**：82 → 58（修掉的 24 条全是"存在的目录被误报"），使修正的效果可核而非自述。

## 来源

- 工具：`scripts/check_plan_landing.py`（`build_tracked_dirs` / `extract_paths` / `judge` / `selftest` 11 格）。
- 登记：`scripts/README.md` 的 `check_plan_landing.py` 条目。
- 全量读数：`INFO 计划落点核对（38 份文档、249 条点名路径）：未在跟踪面 58 条（磁盘上有 5 条、都没有 53 条）`。
- 变异原件：`temp/mutate_plan_landing.py`（输出 `E:\temp\mut78c.txt` / 终轮 `mut78` 系列）。
- 首跑误报原件：`E:\temp\pland78.txt`（82 条）；修正后：`E:\temp\pland78c.txt` / `E:\temp\pland_final.txt`（58 条）。
- 前序相关报告：`reports/2026-10-13-supervisor-tools-plan-gap-report.md`（缺测试锁实例）、
  `reports/2026-10-13-simulate-head-commit-report.md`（互补工具）。
- 提交：`9267572`、`ec6064a`。
