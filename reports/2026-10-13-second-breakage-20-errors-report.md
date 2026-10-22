# 2026-10-13 · 第二次 master 坏状态诊断报告（HEAD 编译不过 · 20 errors）

## 结果摘要

**一句话**：本轮在核验新判据时**发现第二次 master 坏状态**——三端同 rev 的 HEAD（`fe5840a`/`348c5e7`）
干净树 `moon check --target js` = **`Failed with 1579 warnings, 20 errors`**，
根因是 `server.mbt` 引用了**仅存在于工作树、未跟踪**的实现 ⇒ 公开面 CI 必红且其后全部步 skip。

| 项 | 读数 |
|---|---|
| HEAD 干净树 `moon check` | **Failed with 1579 warnings, 20 errors**（本地复现） |
| CI #303（`348c5e7`）/ #304（`fe5840a`） | 均 **红在 `Migrate` 步**；`Check (js)` 及其后全部步 **skipped** |
| 首处失败符号 | `self_search_runner_default` / `do_evolve_asset_register_with_search` / `@store.assistant_claim_action` / `engine.lock_violations_record` |
| 缺失文件 | 工作树有而 HEAD 无的 `.mbt` 共 **13 个** |
| 归因 | **先于我的改动**：CI #303（并发会话 `348c5e7`）已红在同一处 |

**本轮处置：只诊断 + 实证 + 记录，不代提交**（该面是并发会话未完成 WIP，且修复需判断"哪些该一起提交"）。
判据侧成果见另报告 `reports/2026-10-13-pkg-imports-guard-report.md`。

## 坏状态定性（引用了未提交的实现）

`src/server/server.mbt` 里三处引用、`src/server/pkg.generated.mbti` 里两处签名，
指向**只存在于工作树的文件**：

| 缺失符号 | HEAD 里的引用点 | 定义所在（未跟踪） |
|---|---|---|
| `self_search_runner_default()` | `server.mbt:3284`、`pkg.generated.mbti:184` | `src/server/self_search_evolve_bridge.mbt` |
| `do_evolve_asset_register_with_search(...)` | `server.mbt:3286`、`pkg.generated.mbti:30` | 同上 |
| `@store.assistant_claim_action(...)` | `server.mbt:4641` | `src/store/store_assistant.mbt` |
| `engine.lock_violations_record(...)` | `server.mbt:4656` | `src/engine/engine_assistant.mbt` |

**工作树有而 HEAD 无的 `.mbt`（13 个）**：
`src/claimguard/claimguard.mbt` + `_wbtest`、`src/constraint/constraint.mbt` + `_wbtest`、
`src/engine/engine_assistant.mbt`、`src/engine/engine_supervisor.mbt`、`src/engine/engine_supervisor_reminder_test.mbt`、
`src/server/boundary_probe.mbt`、`src/server/self_search_evolve_bridge.mbt` + `_wbtest`、
`src/server/supervisor_tools.mbt`、`src/store/store_assistant.mbt` + `_test`。

⇒ 这是**同一提交窗口"实现面先提交、配套实现未提交"的第二次发生**（第一次是上轮的 `src/diff` 悬空 import）。

## 归因（不是我引入的，有 CI 双证）

- CI **#303**（head `348c5e7`，并发会话的 ocr_scan 提交）**已红在 `Migrate` 步**
- CI **#304**（head `fe5840a`，我的报告提交）**同样红在 Migrate**
⇒ 坏状态在 #303 就存在，**先于我的推送**；我的改动（判据 + 报告）不是肇因。

## 最小修复实验（三组，已实测，供该面作者直接接手）

| 组 | 补什么 | `moon check` 结果 |
|---|---|---|
| 基线 | 无（HEAD 原样） | **20 errors** |
| A | 4 个直接相关文件（`self_search_evolve_bridge` / `store_assistant` / `engine_assistant` / `supervisor_tools`） | **9 errors**（大幅下降 ⇒ 主因就是缺文件） |
| B | 再补全部 13 个未跟踪 `.mbt` | 仍 **9 errors** |
| C | B + `claimguard`/`constraint` 的 `moon.pkg` | 仍 **9 errors** |

**剩余 9 errors 集中在 `src/store/store_assistant.mbt`**（`Error:[4032]` 类型 `AssistantReg` 未定义、
`[4091]` 字段 `assistant_reg` 不存在）⇒ 说明 **`src/store/store.mbt` 的配套改动（类型与字段声明）也未提交**。

**结论**：修复不是"补 4 个文件"那么简单——需 `store.mbt` 级配套；故本轮**不代提交**，
把这组读数留给该面作者（他们知道哪些改动应一起进）。

## 判据侧的重要发现：我新挂的判据步**被 skip 了**

CI #304 的步序实证：`Migrate` 红 ⇒ `Check (js)` / `Format check` / `Entry-list guard` /
**`Package-import guard`（我新挂的）** 全部 **skipped**。

⇒ **这是"判据挂了但没跑到"的第二次同族教训**（上一轮是 `Format check` skip 掉 HTTP 契约自证）。
**根因**：我按"同族相邻"把它挂在 Entry-list guard 之后，而它在 `Migrate` **之后**；
`Migrate` 一红，它就被 skip —— 而"依赖/编译坏状态"场景恰恰最需要它出声。

**建议**：把它（以及 `Check (js)` 这类静态判据）移到 `Migrate` **之前**，或让 `Migrate` 失败时**不跳过**静态判据。

## 资源消耗

- `moon check` 共 4 次（HEAD 复现 + A/B/C 三组），每次约 1.5 分钟；
- `git archive` 建树 5 次；CI API 只读 4 次；日志下载 1 次（14KB）；
- 本链零 `.mbt` 源码改动（未代补任何文件）、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：CI 步序核验 → 干净树复现 → 符号/缺文件定位 → 三组最小修复实验 → 归因（CI 双证）→
  判据挂点缺陷识别 → 报告。
- **未派子代理**：本链要害是"坏状态归属（谁的）"与"修复边界（该不该代提交）"，外包会引入误判。
- 边界：**未补任何文件、未改任何 `.mbt`、未代提交他人 WIP**；只做诊断与实证。

## 遗留风险（按严重度）

1. **P0：三端同 rev 的 HEAD 编译不过**（公开面 CI 必红在 `Migrate`，其后全部步 skip ⇒ 守卫族集体失效）。
   修复需并发会话补齐 13 个未跟踪 `.mbt` **+ `store.mbt` 配套改动**（本轮已实测单补文件不够）。
2. **第二次同族发生说明这不是偶发**：上轮 `src/diff`、本轮 13 文件，都是"实现面先提交、配套未提交"。
   本仓 CI 的发现时机太晚（红在 `Migrate`、且 skip 掉能点名的判据）⇒ 需要结构性改善（见下）。
3. **判据挂点位置缺陷**：本轮我自己的判据步被 skip（第二次同族）；若不改挂点，
   下一次同类坏状态仍会"判据在场但不出声"。
4. **`check_pkg_imports` 判不了符号级缺失**：本轮坏状态正是符号级（目录都在、符号未提交）。
   该判据与 `moon check` 互补不可互替。

## 后续建议

1. **把静态判据移到 `Migrate` 之前**（`Package-import guard`、`Check (js)` 等）：`Migrate` 只解包依赖，
   不构成静态判据的前置；而"依赖/编译坏状态"下静态判据恰恰最该出声。本轮实证：现状一定被 skip。
2. **给 `Migrate` 失败分支加"根因分流"**：本轮两次坏状态的 CI 红都出现在这一步，错误文本却语义不同
   （`Cannot find import <本地包>` / `Failed with N errors` / 依赖清单迁移）。建议按文本分流指路。
3. **补一支"符号级引用完整性"可见性**（口径待定）：`moon check` 输出凡含 `Error: [4021] ... unbound`
   / `[4032]` / `[4024]` ⇒ 点名"引用了未提交实现"，且该步必须在 `Migrate` 之前（否则被 skip，本轮实证）。
4. **提交纪律**：实现面与其配套文件应**同批提交**（本仓已有 `check_pkg_imports` 判目录，
   但"配套符号未提交"只能靠 `moon check` 或脚本化的符号扫描）。
5. **给"判据挂点在失败即 skip 的步之后"做一次普查**：本轮是第二次同族（Format→契约自证、Migrate→本判据），
   建议盘点所有判据步相对"前置硬门"的位置。

## 超额内容

- 顺带**把坏状态的三组最小修复读数做实**（20→9 errors；补全 13 文件仍 9 ⇒ 定位到 `store.mbt` 级配套），
  为该面作者省去整轮排查。
- 顺带**识别出我自己判据的挂点缺陷**（被 `Migrate` skip）并写成建议 #1 ——
  这是本会话第二次踩"判据挂了但没跑到"，已作为结构性问题提出。
- 顺带**用 CI 双证（#303 先红）完成归因**，避免把坏状态误记为自己的改动引入。

## 来源

- 复现：本地干净树 `moon check --target js`（`E:\temp\chk20.txt`，`Failed with 1579 warnings, 20 errors`）；
  `moon check` 原始输出定位 `Error: [4021]/[4032]/[4091]/[4024]`（`E:\temp\err20.txt`）。
- CI：`ci.yml #303`（`348c5e7`）与 `#304`（`fe5840a`）均红在 `Migrate`（日志 `temp\ci304.log`）。
- 修复实验：`temp/fix20_experiment.py`（三组 A/B/C，输出 `E:\temp\fix20.txt`）。
- 归属：CI #303 早于我的 `fe5840a` ⇒ 坏状态先于我的改动存在。
- 判据侧：`reports/2026-10-13-pkg-imports-guard-report.md`；判据 `scripts/check_pkg_imports.py`。
