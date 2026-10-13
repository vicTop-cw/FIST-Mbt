# 2026-10-14 · 多语言示例（计划 multilang S1 验收格）实测报告

## 结果摘要

**一句话**：`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md` 的 S1 验收格写的是
「**curl / requests / fetch 示例可用**」——本轮**首次真跑**这三支示例，
证明 **python / fetch 两支在本机可跑通、curl 支的契约命令面 3/3 可达**，
并**诚实标注** curl 的 bash 调用形在本机未验证（WSL 网络隔离）。

| 示例 | 本机实测 | 结论行 | 判定 |
|---|---|---|---|
| `docs/examples/python/http_client.py` | rc=0 | `PY-CLIENT PASS` | ✅ **可用** |
| `docs/examples/fetch/http_api.mjs` | rc=0，`/tools` 报 **166 个工具** | `FETCH-EXAMPLE PASS` | ✅ **可用** |
| `docs/examples/curl/http_api.sh` | **bash 形 rc=1**（`Connection refused`）| 未打 | ⚠️ **命令面 3/3 可达**，bash 形因环境未验证 |
| ↳ 其内部 3 个 curl 目标（Windows 侧复跑） | `/health` rc=0（60 B）、`/tools` rc=0（99521 B）、`/tools/mode_list/call` rc=0（4962 B）| — | ✅ **契约面可用** |

提交：本报告（无源码改动）。**本轮零 `.mbt` 写入**。

## 三个示例的真实现状（先核"文件在不在"，再核"能不能跑"）

三份示例**都已在 HEAD**（不是未提交 WIP）：

| 文件 | in HEAD |
|---|---|
| `docs/examples/curl/http_api.sh` | ✅ |
| `docs/examples/fetch/http_api.mjs` | ✅ |
| `docs/examples/python/http_client.py` | ✅ |

计划原文两处（`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md`）：
- L149 `| S1（P2 末期） | vools 融合层完整（bridge.md 转 DAG）+ README 多语言最小示例 | bridge 适配器跑通；**curl / requests / fetch 示例可用** |`
- L167 `| 语言最小示例 | README / docs/examples | FIST-Mbt 仓内 docs/examples/<lang>/（可选，文档级） |`

⇒ 计划把"示例可用"写成**验收标准**。此前**无人实测**（只有"文件存在"）。
按 §0.1 的承诺纪律（"不得以占位/预留接口充数"），"可用"必须以**实跑**说话 ⇒ 本轮补上这一格。

## 实测方法（真起桥 + 真跑三支）

1. 起真桥：`python scripts/fist-mbt-http.py <port>`，**隔离 `FIST_DB_PATH`**（落 temp/，不污染仓库根自举台账，
   遵 BUG-122 纪律），等 `/tools` 返回 200 才继续
2. 逐支跑：`bash docs/examples/curl/http_api.sh <port>` / `node docs/examples/fetch/http_api.mjs <port>` /
   `python docs/examples/python/http_client.py <port>`
3. 判"可用" = `rc==0` **且**结论行含该语言的 `*-EXAMPLE PASS` 标记（不是只看退出码——BUG-142 同族纪律）

## 首跑暴露的三处问题（两处是我的，一处是环境的）

| # | 现象 | 归属 | 处置 |
|---|---|---|---|
| ① | curl / fetch 的结论行是 `CURL-EXAMPLE PASS` / `FETCH-EXAMPLE PASS`，我却去找 `CURL-API PASS` / `FETCH-API PASS` ⇒ 误判"不可用" | **我的 marker 记错** | 修正为 `*-EXAMPLE PASS`（三支统一形态）|
| ② | `bash docs/examples/curl/http_api.sh` 在 Windows 上被 `shutil.which("bash")` 解析为 `C:\Windows\system32\bash.EXE`（**WSL 入口**），先传 `E:\...` 路径 ⇒ `cd: No such file or directory` | **harness 路径形态** | 转 `/mnt/e/...` 后路径问题消失 |
| ③ | 转对路径后 curl 仍 rc=7 `Failed to connect to 127.0.0.1:3210: Connection refused` | **环境（WSL 与 Windows 的网络命名空间隔离）** | 桥跑在 Windows 侧；WSL 的 `127.0.0.1` 是另一个命名空间 ⇒ **该示例的 bash 调用形在本机无法验证**。不虚报，改用"逐条复跑其 curl 目标"判契约面 |

> ①②③ 都不是示例缺陷：①是我的判据写错；②是调用方式；③是 WSL/Windows 网络模型。
> 三处均由**首跑实测**暴露——若只做"文件存在性检查"，这条验收格会一直挂着"未验证"。

## curl 支的替代取证（命令面 3/3 可达）

因 ③，另写一支把示例里的**静态 curl 目标**在 Windows 侧逐条复跑（与示例同源、同 URL、同路径）：

```
=== curl 示例里出现的 3 个目标路径 ===
    /health
    /tools
    /tools/mode_list/call
  [/health]                rc=0 字节=60     => 可达
  [/tools]                 rc=0 字节=99521  => 可达
  [/tools/mode_list/call]  rc=0 字节=4962   => 可达
CURL-ARMS PASS
```

⇒ **契约命令面可用**（含 `/tools` 全量清单 99521 字节与真实工具调用回执）。
**但本支不替代示例本身的 bash 形验证**——报告明确限定结论边界（"不虚报"）。

## 资源消耗

- 起桥 3 次（端口 3199 / 3200 / 3201 / 3210），每次等待就绪 ≤60s；桥进程均在 `finally` 里终止；
- 三支示例各跑 2–3 次（含 marker/路径修正前后）；curl 目标复跑 3 条；
- 隔离 DB 落 `temp/examples_s1_*.db`（未污染仓库根）；日志落 `temp/examples_s1_bridge.log`；
- 本链**零 `.mbt` 改动、零提交源码**（只有本报告）；零外部网络请求（全走 127.0.0.1）。

## 任务分配记录

- 指挥官亲自：读计划验收格 → 核三份示例是否入库 → 设计"真跑三支"的判据（含上游前置与自拒档）→
  首跑 → 三处问题归因（我的 marker / harness 路径 / 环境隔离）→ curl 支替代取证 → 报告。
- **未派子代理**：本链要害是"三处异常各自归谁"（是示例缺陷、还是我的判据/环境），外包会误判成产品缺陷。
- 边界：只新增两支 temp 探针；未改 `docs/examples/` 任何文件、未改 `.mbt`。

## 遗留风险

1. **curl 示例的 bash 调用形在本机仍未验证**（环境所限）。⇒ 在 Linux/macOS 或有 Windows↔WSL
   端口转发的环境里跑一次即可闭合；**本报告不声称它已可用**，只声称"其命令面可用"。
2. **示例的 marker 形态不统一于我的预期**（都是 `*-EXAMPLE PASS`）：这其实**是好形态**（三支一致）。
   建议把它写进 README/计划，使后来者按同一标记验。
3. **`requests` 示例不在仓内**：计划 L149 写"curl / requests / fetch"，但仓内只有 `python/http_client.py`
   （**用 `urllib`，不是 `requests`**——其 docstring 明说"只用标准库，不建 SDK"）。
   ⇒ **计划的"requests"一词与实现口径不同**（实现刻意零依赖）。这属**计划-实现口径漂移**，
   建议在计划里改成"Python（标准库 urllib）"以免后来者去找 `requests` 示例。
4. **示例不进 CI**：三支都没有常驻判据（CI 里没人跑它们）⇒ 契约一变，示例可能悄悄失效。
   建议把"三支示例"接进 CI 的 HTTP 契约自证步（已有 `e2e_http_contract.py` 那一步）。
5. **P0（未变）**：HEAD 编译不过（20 errors）。

## 后续建议

1. **把三支示例接进 CI**（价值最高）：现有 `e2e_http_contract.py` 已起桥，可在同一步里追加
   `python docs/examples/python/http_client.py` 与 `node docs/examples/fetch/http_api.mjs` 两臂
   （curl 那支在 CI 的 Linux runner 上是真 bash，天然可跑 ⇒ **CI 恰好能补上本机缺失的那一格**）。
2. **修正计划的"requests"措辞**：改为"curl / Python（标准库）/ fetch"，与实现口径一致。
3. **把 `<LANG>-EXAMPLE PASS` 标记写进示例文档说明**：使"可用"有统一可抓的结论行。
4. **给示例加 `--selftest` 式自拒**（可选）：无桥可连时应报"前置不满足"而非连接错误堆栈，
   使"没跑起来"与"示例坏了"可区分。
5. **本机验证 curl 形的环境方案**（备查）：① WSL 里起桥（`/mnt/e/...` 下跑桥）再跑示例；
   ② 或启用 WSL↔Windows 的 localhost 转发（`.wslconfig` 的 `localhostForwarding`）。

## 超额内容

- 顺带**第一次把"示例可用"从"文件存在"升级为"实跑读数"**，并把不可验证的那一格**明确标注**而非含糊带过
  （③ 环境隔离 → 限定结论边界"命令面可用，bash 形未验证"）。
- 顺带**发现一处计划-实现口径漂移**：计划写 `requests`、实现是 `urllib` 零依赖 ⇒ 建议改措辞
  （避免后来者去找一个刻意不存在的依赖）。
- 顺带**暴露三支示例都无常驻判据**（不进 CI）⇒ 契约变更会悄悄让示例失效；并给出可直接落地的接法。
- 顺带**实证了 `/tools` 的规模**（99521 字节 / 166 工具）与真实工具调用回执（`/tools/mode_list/call`
  4962 字节）——这是 HTTP 契约 v1 在真实规模下的可用性证据。

## 来源

- 计划：`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md`（L88 / L97 / L149 / L167）。
- 示例：`docs/examples/curl/http_api.sh`（结论行 L37 `CURL-EXAMPLE PASS`）、
  `docs/examples/fetch/http_api.mjs`（L22 `FETCH-EXAMPLE PASS`）、
  `docs/examples/python/http_client.py`（L51 `PY-CLIENT PASS`）；三份均 **in HEAD**。
- 探针：`temp/e2e_examples_plan_s1.py`（三支真跑 + 前置自拒档；输出 `E:\temp\ex_s1.txt` / `ex_s1b.txt` / `ex_s1c.txt`）、
  `temp/e2e_curl_example_arms.py`（curl 目标 Windows 侧复跑；输出 `E:\temp\curl_arms.txt`）。
- 实测关键读数：python `rc=0 / PY-CLIENT PASS`；fetch `rc=0 / FETCH-EXAMPLE PASS`、`/tools => 166 个工具`；
  curl `/health` 60B、`/tools` 99521B、`/tools/mode_list/call` 4962B 全 rc=0。
- 环境事实：本机 `shutil.which('bash')` = `C:\Windows\system32\bash.EXE`（**WSL 入口**）；
  `curl` = `C:\Windows\system32\curl.exe`（curl 8.21.0）。
