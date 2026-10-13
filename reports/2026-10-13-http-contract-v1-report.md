# 2026-10-13 · 多语言 HTTP 契约 v1 落地报告（fist-mbt-api）

## 结果摘要

实现 `docs/fist-mbt-multilang-sdk-plan-20261012.md` §2.2「A. HTTP 契约定版（fist-mbt-api）」——
该计划三件事里**唯一落在本仓**的一件（B vools 融合层在用户 vools 项目、C actus 动作层在
`E:\IDEProjects\AI\actus\`，均不在本仓范围）。`docs/openapi/fist.yaml` 此前不存在，本轮定版。

交付面（4 提交，双远端同步，终态 HEAD `6a6fb9c`）：

| 提交 | 内容 |
|---|---|
| `56345eb` | 桥加两条 REST 透传口 + `docs/openapi/fist.yaml` 定版 + scripts/README 同步 |
| `b222617` | `docs/examples/python/http_client.py`（计划 §4 指定落点） |
| `05ae303` | `check_py_stdout_encoding --all` 扩面纳 `docs/examples/**` 并排除 `_` 前缀临时件 |
| `46a5764` | `docs/examples/curl/http_api.sh`（S1「curl/requests/fetch 示例可用」的 curl 格） |

**实现（`scripts/fist-mbt-http.py`，只加两条通用透传口，不动既有 `/health` `/mcp` `/events`）**：
- `GET /tools` —— 映射 MCP `tools/list`，剥 JSON-RPC 壳返 `{tools:[…]}`，每项含 `inputSchema` ⇒ 客户端可**自描述驱动**，无需为每个工具写映射表。
- `POST /tools/{name}/call` —— 请求体就是该工具的 `arguments`；桥**替调用方补齐** `params._meta`
  （本 server 走 MCP 2026-07-28 形状、缺 `_meta` 直接拒 ⇒ HTTP 侧不该要求每门语言手抄信封）；
  回执 `{ok, result, data?}`，`data` 是便利而非替换，**`result` 永远原样保留**。

**契约定版的纪律**：计划 §2.2 那张「任务/路由/锁/帽子」端点表是**草案**，`fist.yaml` 刻意只写被真实服务的端点
（`x-implementation: served` 3 条 + `pre-existing` 1 条，零幻影端点）——照草案登记未实现端点就是本仓
BUG-214 的「描述承诺 vs 实现」落差（J9 同族）。

**L4 实测（金条八，逐端点真发 HTTP 读回执，非据自述）**：

| 用例 | 结果 |
|---|---|
| `GET /health` | 200 `{"status":"ok","product":"FIST-Mbt","transport":"http"}` |
| `GET /tools` | 200 剥壳成 **163 工具**；`get` 的 `inputSchema` 参数 `[task_id]` |
| `POST /tools/mode_list/call` | 200 `ok=True`，data 真读出 7 模式 `advance,polish,verify,bugfind,fix_and_merge,tidy,explore` |
| `POST /tools/get/call`（查无单） | **502** `{"error":{"code":-32000,"message":"task not found: …"}}` |
| 未知工具名 | 502（走 error 通道，不崩） |
| body=`[1,2]`（非对象） | 400 |
| 老 `POST /mcp` `tools/list` | 200 / 163 工具（**零回归**） |

curl 示例是**真 Linux 端到端**（WSL2 内起桥 + WSL 原生 curl/bash 消费，比 Windows 侧更硬）：`CURL-EXAMPLE PASS`、`EXAMPLE_RC=0`。

## 资源消耗

- 桥起停 5 次（Windows 3 次 + WSL 2 次），DB 一律 `FIST_DB_PATH` 改道 `temp/`（BUG-122 纪律，不污染仓库根台账）。
- 只读守卫复跑约 10 次；**本链零 `.mbt` 改动**（凭据 = 逐提交 `git show --name-only` 核 5 个链上提交
  `56345eb`/`b222617`/`05ae303`/`46a5764`/`6a6fb9c`，每个 `.mbt` 命中均为 0；用逐提交而非 range diff，
  是因为中间夹着并发会话的提交，range 会把别人的改动混进来当"我的凭据"），
  故不需要跑 `moon test`——**注意：本报告刻意不宣称全量测试当前值**。上一次全量实测读数（811/811）
  是在契约链开始**之前**取的，此后并发会话大量改动了 `src/**`，那个数字不代表现在的基线，
  也不该被引用成本链的验收（引用未复验的旧数字=幻影断言）。
- 两次 WSL 失败重跑源于**我自己 harness 的错**（见「遗留风险」3、4），非产品缺陷。

## 任务分配记录

- 指挥官亲自：契约设计（含"只登记真被服务面"的取舍）、桥两条端点、两份客户端示例、守卫扩面、全部实测与账面同步。
- 未派子代理：本链每步都要实跑回执 + 涉及并发会话占用面判定（归属判断不可外包），拆给子代理反增一层终审。
- **边界**：全程只动干净跟踪面（`scripts/`、`docs/openapi/`、`docs/examples/`、`BACKLOG.md`、`.github/`）；
  `src/**`（92 脏）、`cmd/**`（10 脏）、`README*`、`memory/2026-10-13.md`（工作树 246 行 vs HEAD 83 行）
  均为并发会话未提交面，一律未碰未 add。

## 遗留风险

1. **契约定格在「通用透传」层，未做资源化端点**：计划 §2.2 的 `POST /tasks/submit`、`GET /router/status`
   等 RESTful 族**没实现**，因此也**故意不写进 yaml**。理由：那需要为每个工具做参数映射与语义约定，
   是独立一轮，且 `data` 剥壳规则在资源化后反而更难自描述。现契约以 `GET /tools` 的 `inputSchema` 为唯一
   参数真源，工具增减不动契约——这是取舍不是遗漏。
2. **`422` 分支是登记而非实测**：yaml 里 `isError=true → 422` 覆盖的是 MCP 标准分支；**本 server 当前把
   业务失败走 JSON-RPC `error` ⇒ 实际落 502**（已实测）。yaml 内已就地注明该差异，不算已验。
3. **`--all` 扫描面扩到 `docs/examples/**` 后才看见的假红**：扩面当场抓到未跟踪的
   `scripts/_tmp_boundary_omega.py` 缺闸报红——那是把「即用即清的临时件」错当正式面判。修法按本仓既有先例
   （`check_scripts_index` 对 `_` 前缀豁免登记）排除 `_` 前缀，**没有**去改别人的文件。
4. **我本轮自犯并自纠的三处**（都靠"先跑通再入库"抓到，非事后补）：
   - Python 示例首版假设 `mode_list` 正文是 `{modes:[…]}` 对象 ⇒ `TypeError`（实为数组）；
   - 示例首版靠外部 `PYTHONIOENCODING` 才不崩 ⇒ 正是 BUG-138 的形状，改为脚本自带 UTF-8 闸并复跑验证自足；
   - 我**自己的新示例**落在 `check_py_stdout_encoding` 只 walk `scripts/` 的盲区 ⇒ 扩面（风险 3 即其副产物）。
   另有两处编辑事故：curl 示例内嵌 f-string 同种引号嵌套（Python<3.12 SyntaxError，改 `%` 格式化）、
   BACKLOG 编辑一度吞掉表格行 `| - |` 收尾致 markdown 断行（补回并 awk 全表核竖线=6、`BAD_COUNT 0`）。
5. **`self_search` 入库那半由并发会话在做，我未代翻账**：其接线只在未提交工作树
   （HEAD 命中 0 / 工作树命中 1~2，且有两个 `?? src/server/self_search_evolve_bridge*.mbt`）⇒
   BACKLOG 该行**保持 pending**，并注明「谁提交谁连同工具数一起翻」。旁观者代翻半成品账是本仓明令的形状。
6. **金条五的 memory 一段本轮无法落**：`memory/2026-10-13.md` 被并发会话占着未提交段，`git add` 整份等于
   代提交他们的账 ⇒ 本报告即本链一手记录，待该文件腾清再补当日日志（连续多轮同一阻塞，非一次性）。

## 后续建议

1. 资源化端点（若确要 `POST /tasks/submit` 一族）：先定「arguments 来源」约定（body 平铺 vs `{arguments:{}}` 包裹），
   再逐个映射，并把 `x-implementation` 从 `planned` 改 `served` 时才对外宣传——保持 yaml「只写服务着的面」这条纪律。
2. `422` 与 `502` 的边界要么在 server 侧把业务失败统一走 `result.isError`（则 422 成实测），要么把 yaml 该分支降级为注释；别长期挂"登记但未实测"。
3. `requests` / `fetch` / `HttpClient` 三格若也想要，落点同样在 `docs/examples/<lang>/`（计划 §4），每格都应先跑通再入库。
4. `check_py_stdout_encoding` 的 `_` 前缀豁免与 `check_scripts_index` 已是同一条纪律——可考虑抽出成共用的「正式脚本面」定义，避免第三把尺再各自发明一遍口径。
5. CI 可挂一次「契约自证」：起桥 → 跑 `docs/examples/curl/http_api.sh` → 断言 `CURL-EXAMPLE PASS`。这是本契约唯一会随实现漂移而无声失效的点。

## 超额内容

- 顺带修了 `check_py_stdout_encoding --all` 的**真盲区**（不纳 `docs/examples/**`）并补 `_` 前缀豁免口径，
  同时把 `scripts/README.md` 现状读数从 63/62/62 同步到实测 64/63/63（写死数字滞后就是下一颗漂移雷）。
- `BACKLOG.md` 的 self_search 行补了一段带归属判定的状态复验（含「谁提交谁翻」的约定），
  把一次例行复验变成防重复派单/防代翻半成品账的账面事实。
- `.gitattributes`（上一段工作，提交 `6bba279`）本轮被自己的新 `.sh` 示例反向验证：
  `git check-attr` 报 `text: set / eol: lf`，且**暂存 blob CR=0**——钉死生效，Linux checkout 不再炸。

## 来源

- 实现与契约：`scripts/fist-mbt-http.py`（`do_GET` `/tools`、`_handle_tool_call`、`_route_rest`、`do_POST` 分流）、
  `docs/openapi/fist.yaml`（OpenAPI 3.0.3，4 路径、`x-implementation` 全部 `served`/`pre-existing`、文件头含实测读数）。
- 示例：`docs/examples/python/http_client.py`、`docs/examples/curl/http_api.sh`。
- 登记与读数：`scripts/README.md`（桥条目 + 守卫条目两处同步）、`BACKLOG.md`（multilang 无独立行，计划真源在 docs）。
- 计划真源：`docs/fist-mbt-multilang-sdk-plan-20261012.md` §2.2 契约定版 / §2.3 发布位置 / §3 不需 SDK / §4 落点 / §S1 验收。
- 实测原件（gitignored）：`temp/final10_direct.txt`（Linux 装 + serve 163 工具）、`temp/curl_ex2_direct.txt`（curl 端到端 PASS 读数）。
- 相关前序：`reports/2026-10-13-linux-wsl-install-report.md`（G5 与 `.gitattributes`）、
  `reports/2026-10-13-star-gate-implementation-report.md`（Star 门端到端）、
  `reports/2026-10-13-backlog-drift-reconcile-report.md`（BACKLOG 对表翻账）。
