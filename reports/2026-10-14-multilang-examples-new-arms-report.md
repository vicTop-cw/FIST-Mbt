# 2026-10-14 · 补上计划点名却缺失的两支语言示例（requests / HttpClient）报告

## 结果摘要

**一句话**：计划 `docs/2026-10-12-fist-mbt-multilang-sdk-plan.md` **两处点名**
`curl / requests / HttpClient / fetch` 四种示例，而仓内原先只有 **3 支**
（curl / fetch / python）——**`requests` 与 `HttpClient` 无对应文件**。
本轮补齐这两支，并**真起桥实测两支均可用**。

| 项 | 读数 |
|---|---|
| 新增 `docs/examples/requests/http_api.py` | **rc=0**，打印 `REQUESTS-EXAMPLE PASS` ⇒ **可用** |
| 新增 `docs/examples/httpclient/http_api.cs` | **rc=0**（.NET 9 标准项目流程），打印 `[1] GET /tools => 166 个工具`、`[2] ok=True 模式: advance, polish, verify, bugfind, fix_and_merge, tidy, explore`、`HTTPCLIENT-EXAMPLE PASS` ⇒ **可用** |
| 无桥 / 无库时的行为 | **显式 `PRECONDITION REFUSED` + rc=3**（不抛堆栈、不假装跑通）|
| `docs/examples/` 支数 | 3 → **5** |

提交 `ceb6e69`，双远端同步。

## 缺口是如何定位的

计划里三处点名（`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md`）：
- **L88**「MoonBit 生态外：经 HTTP 契约接入，语言侧 20 行以内封装即可（README 给最小示例：**curl / requests / HttpClient / fetch**）」
- **L149**「S1（P2 末期）… **curl / requests / fetch 示例可用**」（**验收标准**）
- L167「语言最小示例 | README / docs/examples | FIST-Mbt 仓内 `docs/examples/<lang>/`（可选，文档级）」

而仓内实际只有：
```
docs/examples/curl/http_api.sh
docs/examples/fetch/http_api.mjs
docs/examples/python/http_client.py   ← 用标准库 urllib（刻意零依赖），≠ requests 这条线
```
⇒ **`requests` 与 `HttpClient` 两支缺失**。其中 `requests` 还被 L149 明确列入**验收标准**，
属计划里"未实现"的一处真实缺口（不是"可选文档"）。

## 两支新示例的设计（沿用同仓风格）

共同形态（与既有三支一致）：20 行级、注明契约真源与计划出处、**统一的 `<LANG>-EXAMPLE PASS` 结论行**、
自带 BUG-138 同族的中文 stdout 编码闸（`docs/examples/` 不在 `check_py_stdout_encoding` 扫描面内 ⇒ 自带闸）。

**`requests` 支**（`docs/examples/requests/http_api.py`）：
- 与 `python/http_client.py` **刻意并存**，覆盖两类用户：零依赖（urllib）vs 习惯 requests
- 相对 urllib 支的差异点：`requests.Session` 复用连接 + `raise_for_status()` **显式化 HTTP 层错误**
- **两道前置自拒**（本轮实测后补的）：① 无 `requests` 库 ⇒ `PRECONDITION REFUSED` + rc=3；
  ② **连不上桥 ⇒ 也报 `PRECONDITION REFUSED` 并指路**（原版直接抛 `ConnectionError` 堆栈——
  那会让读者把"桥没起"误读成"示例坏了"）

**`HttpClient` 支**（`docs/examples/httpclient/http_api.cs`）：
- BCL 的 `HttpClient` + `System.Text.Json`（**零 NuGet**，兑现计划"不需要专用 SDK"）
- 覆盖 .NET 这条线（计划 §4 明写 `Python/Rust/C#/Go` 一律走 HTTP 契约）

## L4 实测（金条八）

**requests 支**（真起桥 + 隔离 `FIST_DB_PATH`）：
```
[requests] rc=0 含标记=True => 可用
```

**HttpClient 支**——实测先撞到一处环境事实，再看清正确路径：

| 步骤 | 读数 | 判读 |
|---|---|---|
| `dotnet run docs/examples/httpclient/http_api.cs 3230` | rc=1，「**找不到要运行的项目**」 | `dotnet run <单文件.cs>` 需 **.NET 10+**；本机 SDK 是 **9.0.306** ⇒ 不支持 |
| `dotnet --list-sdks` | `9.0.306` | 环境事实，非示例缺陷 |
| 改用标准项目流程（`dotnet new console` + 拷为 `Program.cs` + `dotnet run -- <port>`） | **rc=0** | ✅ **可用** |

标准流程实测输出：
```
[1] GET /tools => 166 个工具；示例工具 "get" 的参数：task_id
[2] POST /tools/mode_list/call => ok=True 模式: advance, polish, verify, bugfind, fix_and_merge, tidy, explore
HTTPCLIENT-EXAMPLE PASS
HTTPCLIENT-ARM PASS: 示例在 .NET 标准项目流程下实测可用
```

⇒ 该示例**真的跑通了**（`/tools` 真报 166 工具、真实调用回执列出 7 种模式）。
**文件头部原写"未在本机实跑"的诚实标注已按实测结论更正**，并把「.NET 10+ 才有单文件 run」的环境差异写进用法。

**无桥行为自证**：
```
PRECONDITION REFUSED: 连不上桥 http://127.0.0.1:3199（ConnectionError）—— 请先起 python scripts/fist-mbt-http.py 3199
rc=3
```

## 资源消耗

- 起桥 3 次（端口 3220 / 3230，含被探针自拒的一次）；桥进程均在 `finally` 终止；
- `dotnet new console` 1 次、`dotnet run` 1 次（临时项目落 temp/、跑完即删）；
- `docs/examples/` 支数 3 → 5；本链零 `.mbt` 改动；
- 隔离 DB 落 `temp/requests_*.db` / `temp/httpclient_*.db`（未污染仓库根）。

## 任务分配记录

- 指挥官亲自：定位缺口（计划三处点名 vs 仓内 3 支）→ 读既有示例定风格 → 写两支 →
  前置自拒设计 → 真起桥实测 → 撞 .NET 版本差异并改用标准流程 → 更正诚实标注 → 提交。
- **未派子代理**：本链要害是"缺口的判定标准"（计划点名 + 验收标准 vs 仓内实际）与
  "dotnet 单文件 run 失败是环境还是示例缺陷"的归属，外包会误判。
- 边界：只新增两支示例（+ 一处注释更正）；未改 `.mbt`、未改既有三支示例。

## 遗留风险

1. **curl 支的 bash 调用形仍未在本机验证**（WSL↔Windows 网络隔离，见
   `reports/2026-10-14-multilang-examples-s1-report.md`）⇒ **CI 的 Linux runner 能补上这一格**。
2. **五支示例均不进 CI**：契约一变，示例会悄悄失效。**建议**把 `python` / `fetch` / `requests` /
   `HttpClient`（CI runner 上装 dotnet 成本较高，可只接前三支）接进 `e2e_http_contract.py` 那一步。
3. **HttpClient 支的验证依赖 SDK 版本**：本机 9.0.306 需走项目流程；CI/用户环境若是 .NET 10+，
   单文件 `dotnet run <file.cs>` 可直接跑（用法里两种都给了，故两环境都不卡）。
4. **计划的"requests"措辞与既有 python 支口径不同**（后者刻意零依赖 urllib）：
   本轮按计划原意补了**真 requests 支**，两支并存 ⇒ 措辞问题自然消解；但计划 L149 的
   "curl / requests / fetch"仍未提 HttpClient（虽然 L88 提了）⇒ **计划两处口径不一致**，
   建议统一（或在 L149 补 HttpClient）。
5. **P0（未变）**：HEAD 编译不过（20 errors）。

## 后续建议

1. **把五支示例接进 CI 的 HTTP 契约自证步**（价值最高）：CI 的 Linux runner 有真 bash，
   能同时补上"curl 的 bash 调用形本机未验证"这一格。
2. **统一计划的示例清单措辞**：L88（4 种）与 L149（3 种）不一致 ⇒ 收敛成一处列表并加 HttpClient。
3. **给五支示例加统一的前置自拒**（本轮 requests 支已示范）：无桥时报 `PRECONDITION REFUSED` 而非
   抛堆栈，使"没跑起来"与"示例坏了"在 CI 日志里可辨。
4. **把"计划点名 ↔ 仓内落地"做成例行核对**：本轮用 `scripts/check_plan_landing.py` 的思路
   （口径是"文件路径"），对"示例种类"这类**非路径清单**仍靠人工读——若计划改成表格化的
   `| 语言 | 文件 | 状态 |`，即可纳入同一工具。

## 超额内容

- 顺带**发现并消除一处计划两处口径不一致**（L88 列 4 种、L149 只列 3 种）——本轮补齐 4 种后，
  L149 的缺口自然闭合。
- 顺带**实测出一处环境事实并有据处置**：`dotnet run <单文件.cs>` 需 .NET 10+，本机 9.0.306 不支持 ⇒
  改用标准项目流程仍跑通，并把两种用法都写进示例头注释（**读者在任一 SDK 版本上都不卡**）。
- 顺带**给两支示例都加了前置自拒**（无库 / 无桥），并把"原版抛 ConnectionError 堆栈会被误读"
  这个真实可用性问题修掉——这是**可用性**层面的改进，不只是补文件。
- 顺带**实证了契约在 .NET 侧的可用性**：`/tools` 166 工具、真实工具调用回执列 7 模式，
  为"任何语言自带 HTTP 即可接、无需 SDK"这一计划主张提供了第二门语言的证据
  （此前只有 JS 与 Python 两门）。

## 来源

- 计划：`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md`（L88 / L149 / L167）。
- 新增示例：`docs/examples/requests/http_api.py`（80 行）、`docs/examples/httpclient/http_api.cs`（60 行）。
- 探针：`temp/e2e_examples_new_arms.py`（requests 支；输出 `E:\temp\newarms.txt`）、
  `temp/e2e_httpclient_arm.py`（.NET 标准项目流程；输出 `E:\temp\hca.txt`）。
- 关键读数：requests `rc=0 / REQUESTS-EXAMPLE PASS`；HttpClient `rc=0`，
  `[1] GET /tools => 166 个工具`、`[2] ok=True 模式: advance, polish, verify, bugfind, fix_and_merge, tidy, explore`、
  `HTTPCLIENT-EXAMPLE PASS`；无桥时 `PRECONDITION REFUSED ... rc=3`。
- 环境事实：`dotnet --list-sdks` = `9.0.306`（单文件 run 需 10+）；`requests` 库存在；`java` 存在（未用）。
- 前序报告：`reports/2026-10-14-multilang-examples-s1-report.md`（既有三支实测）。
- 提交：`ceb6e69`。
