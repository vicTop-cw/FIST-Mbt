# 报告 · fist-mbt Web 管理面板 M0 任务看板 MVP（一源五态·态5 落地一期）

- 日期：2026-10-13
- 命名空间：`fist-mbt-web`
- 根任务：`T0r2`（fist-mbt Web 管理面板 M0 任务看板 MVP）
- 状态：**M0 交付完成**（5 核心叶已闭环「已完成」，7 叶留后续）

---

## 1. 结果摘要

态5「Web 管理面板」M0 只读任务看板 MVP 已交付并终审通过：**打开一个浏览器就能看到 FIST 真实任务树与状态分布**，全程走 MCP Server（零侵入，面板只是另一个 MCP 客户端），不复制粘贴既有桥代码、不新增任何 MCP 工具、未改 `fist-mbt-http.py`。

新增文件（全部新建）：

| 文件 | 行数 | 说明 |
|---|---|---|
| `scripts/fist-mbt-web.py` | 584 | Web 面板后端（纯 stdlib `http.server`） |
| `web/index.html` | 69 | SPA 骨架（header/status-bar/task-tree/detail-panel/error-bar/footer） |
| `web/app.js` | 511 | `Pure` 纯函数命名空间 + 浏览器侧渲染/交互/SSE/自动刷新 |
| `web/style.css` | 228 | 复用 `fist-config.html` CSS 变量 + 树缩进/badge/响应式 |

7 个端点：`GET /`、`GET /static/<path>`、`GET /health`、`GET /api/status`、`GET /api/tasks?ns=<ns>`、`GET /api/tasks/<id>`、`GET /api/events`（SSE）。认证可选 `FIST_WEB_TOKEN`；端口位置参数 > `FIST_WEB_PORT` > 5173；只绑 `127.0.0.1`。

**实测证据（指挥官独立复测，非子代理自述）**：

```text
python scripts/fist-mbt-web.py 8645

GET /health                              → {"ok":true,"mcp_alive":true}
GET /api/status                          → total_tasks=34, by_status={已完成17,拆分中5,已领取2,待领取10}
GET /api/tasks?ns=fist-mbt-web           → 嵌套树根 T0r2 → 4 子(T0r2.1/2.2/2.3/2.4), flat_count=17
                                            by_status={拆分中5,已领取2,待领取10}
GET /api/tasks/T0r2                      → {"ok":true,"task_id":"T0r2","task":{...}}
GET /api/events (socket 手写 HTTP GET)   → event: snapshot\ndata:{"type":"snapshot",...}
GET /                                    → 200 web/index.html (2195B)
GET /static/../scripts/fist.py           → 403（路径穿越已拦）
```

子代理 A 补充自证（真跑）：token 认证 4 场景（无→401 / `Bearer secret123`→200 / `?token=secret123`→200 / 错→401）、编码穿越 `%2e%2e%2f`→403、`OPTIONS`→204、未知路径→404。
子代理 B 自证：`node --check web/app.js` exit=0；`python html.parser` HTML 标签闭合 OK；37 项断言通过（mock server 已删）。

**FIST 闭环（5 核心叶全绿）**：`T0r2.1.1`/`T0r2.1.2`（后端）、`T0r2.2.1`/`T0r2.2.2`/`T0r2.2.3`（前端）均经 omega_spec_create → omega_spec_review(approve) → execute → omega_result_verify(approve) → submit → verify 全链走完，状态「已完成」。

---

## 2. 资源消耗

- **MCP 工具调用**：未新增工具（MCP 工具数保持 152）。闭环共调 `claim`×3、`omega_spec_create`×5、`omega_spec_review`×5、`execute`×5、`omega_result_verify`×5、`submit`×5、`verify`×5、`list`×3、`status_summary`×若干。
- **构建**：未 rebuild MoonBit 产物（`cli.js` 产物新鲜度确认后直接复用，BUG-32 合规）；`moon check` 0 errors（本任务未触 MoonBit 源码）。
- **临时产物**：`scripts/_web_diag.py`、`scripts/_omega_loop.py`、`scripts/_db_check.py`、`scripts/_tmp_boundary_omega.py`（子代理遗留）均已删；临时 seed 脚本与日志已由子代理清理。
- **服务起停**：验证过程起 `fist-mbt-web.py` 于 8641/8642/8643/8645/8646 多次，全部 terminate + 确认无 `cli.js` 残留。

---

## 3. 任务分配记录

| 任务 | 状态 | 执行者 | 交付 |
|---|---|---|---|
| `T0r2` | 拆分中 | commander | 根任务（ns=fist-mbt-web） |
| `T0r2.1.1` | **已完成** | webagent | `fist-mbt-web.py` HTTP server + MCPBridge |
| `T0r2.1.2` | **已完成** | webagent | `fist-mbt-web.py` /api/tasks 数据聚合（list→嵌套树） |
| `T0r2.1.3` | 待领取 | — | 后端边界审视（留后续） |
| `T0r2.2.1` | **已完成** | webagent | `web/index.html` |
| `T0r2.2.2` | **已完成** | webagent | `web/app.js` |
| `T0r2.2.3` | **已完成** | webagent | `web/style.css` |
| `T0r2.3.1/.2/.3` | 待领取 | — | 集成/前端边界（留后续） |
| `T0r2.4.1/.2/.3` | 待领取 | — | 边界审视全局 owner（留后续） |

分工（write-scope 严格不相交）：子代理 A 只动 `scripts/fist-mbt-web.py`（+`web/.gitkeep`）；子代理 B 只动 `web/`；指挥官负责 `scripts/README.md` 登记、memory/report 沉淀与终审。

---

## 4. 遗留风险

1. **SSE 粒度粗**：只发 `snapshot`（连接即发）+ 15s heartbeat，无任务级变更推送。前端已用 5s 轮询双轨补。M0 够用，M2 建议按任务 id 细粒度推送。
2. **认证默认关闭**：`FIST_WEB_TOKEN` 未设时任何本机进程都能读任务树；只绑 `127.0.0.1` 降低风险，局域网共享须显式设 token。
3. **`/health` 偶发 `mcp_alive: false`**：`MCPBridge.start()` 与 MCP 就绪之间有竞态，首次起服 0.5s 内 curl 会命中。未加重试逻辑（已知偶发，非功能性缺陷）。
4. **大任务树性能**：前端一次全量渲染嵌套树，1000+ 节点会卡。M0 只读看板可接受；M2 如需懒加载可切 `children` 按需 fetch。
5. **并发**：`ThreadingHTTPServer` 多线程 + MCP 单子进程串行应答，`bridge.send` 内部有锁；极端高并发 MCP 调用会排队。
6. **7 个叶任务未闭环**：`T0r2.1.3`、`T0r2.3.x`、`T0r2.4.x` 留后续（边界审视与集成验证）。
7. **子代理 A 曾报「仓库根 `fist-mbt.db` 损坏（integrity malformed，8.9MB）」为误报**：指挥官用 `python sqlite3 PRAGMA integrity_check` 实测 `fist-mbt.db` 与 `temp/fist.db` 均 `ok`、各 17 表。可能 A 用 node:sqlite 或并发写窗口读到不一致。**已记录为「子代理自证不可取代指挥官独立复测」的教训**，不留 BUG 条目。

---

## 5. 后续建议

- **M1/M2**：任务级 SSE 细粒度推送 + 树懒加载 + 写操作面板（认领/提交/验收）——但 M2 开始触碰非只读，需重评估「零侵入」边界（写操作仍应走 MCP 工具，不直写 SqliteStore）。
- **给面板接上真实命名空间选择**：当前 `/api/status` 返回的 `active_namespaces` 在 `temp/fist.db` 里为空数组，前端只回退到 `default` + `fist-mbt-web` 两个下拉项；M1 可让 ns 下拉从 `store_list` 取全量。
- **`/health` 竞态**：若后续把面板用于自动化探活，建议在 `_mcp_alive()` 里加「启动后 N 秒内宽松判断」或客户端加 1 次重试。
- **文档**：已在 `scripts/README.md` 登记 `fist-mbt-web.py` 条目（含端点/端口/DB/认证/错误契约）。计划文档 `docs/fist-mbt-web-dashboard-plan-20261012.md` §4/§5 与实现一致。
- **边界审视叶**：建议下一轮闭环 `T0r2.4.x`（全局输入域 owner，边界四问），专门审「MCP 子进程突然断连」「SSE 长连接被浏览器回收」「`/api/tasks` ns 含非法字符」等场景。

---

## 6. 超额内容

- 计划 §2 原写「新建 `scripts/fist-mbt-http-web.py`」或沿用 HTTP 桥。为满足用户「保留 `fist-mbt-http.py` 既有功能」约束，落地为**新建 `scripts/fist-mbt-web.py`**，通过 `importlib.util.spec_from_file_location` 复用既有 `MCPBridge`/SSE 总线/heartbeat，不复制粘贴、不改动既有文件。这是对计划的最小偏离，已在 memory 记录。
- `configure_db_path` 默认复用同源隔离库 `temp/fist.db`（而非全新 tempdir 空库），使 M0 能读真实任务树——这是指挥官复测发现 `flat_count=0` 后做的修复，非子代理原设计。
- `web/index.html` 缺失时回退 `PLACEHOLDER_HTML` 的分支代码保留但未触发（因 `web/index.html` 已由前端子代理交付）。

---

## 7. 来源

- 计划：`docs/fist-mbt-web-dashboard-plan-20261012.md`
- 后端实现：`scripts/fist-mbt-web.py`
- 前端实现：`web/index.html`、`web/app.js`、`web/style.css`
- 复用桥：`scripts/fist-mbt-http.py`（`MCPBridge`/`_publish`/`_subscribers`/`_heartbeat_loop`）
- 设计基线：`fist-config.html`（CSS 变量与配色）
- 脚本登记：`scripts/README.md`
- 日志：`memory/2026-10-13.md`（fist-mbt-web 段 + 3 轮复核段）
- 任务树：`fist.py call list --namespace fist-mbt-web`

---

## 8. 3 轮独立复核记录（2026-10-13，workflow 并行 3 agent）

用户要求「复核 3 轮」后，用 `workflow` 起 3 个**独立视角**复核代理并行（端口 8801/8802/8803，JSON schema 结构化返回）。**裁决：3/3 pass，可放行**。

| 轮 | 视角 | 端口 | 裁决 |
|---|---|---|---|
| R1 | 后端 e2e + 契约 | 8801 | **pass** |
| R2 | 边界与健壮性 | 8802 | **pass**（带 2 项 open） |
| R3 | 合规一致性 + 前端匹配 | 8803 | **pass** |

**R1 关键证据**：`/api/tasks?ns=fist-mbt-web` keys=`[by_status,flat_count,ns,ok,tasks,updated_at]`；根 id=T0r2、children=4、flat_count=17、by_status={拆分中4,已完成5,待领取7,待验收1}；嵌套树复算=17==flat_count；SSE socket 手写收到 `event: snapshot`；`/static/../` 与 `%2f` 穿越均 403；`/` 200 含 "fist-mbt Dashboard"（2430B）；不存在 ns 返回空树不 crash。

**R2 关键证据**：认证 4 场景全过；异常输入不 crash；**杀 node 子进程后** `/health` 报 `mcp_alive:false`、`/api/status`、`/api/tasks` 返回 502 但 HTTP 始终响应；5×并发 + SSE 全 200；OPTIONS 204 / /nope 404 / static 穿越 403。

**R3 关键证据**：前端 `app.js` 消费字段逐一核对，**未发现「前端读而后端未返回」的字段**；守卫三绿（`check_demo_isolation --selftest` rc=0 / `check_scripts_index` rc=0 / `check_py_stdout_encoding` rc=0）；BUG-32 cli.js 产物存在；5 核心叶已完成；`node --check` rc=0 + html.parser OK；`git status` 证实 **`fist-mbt-http.py` 一字未动**。

**指挥官复测**：连续 5 次起服 **5/5 `mcp_alive=True`**，R2 报的启动竞态当前未复现。

### 3 轮暴露的 open 项（均非 M0 阻断，M1 建议修）
1. **MCPBridge 断连无自动恢复**：MCP 崩溃后数据接口永久 502 直到人工重启（R2 实测）。建议加 liveness 探测 + 指数退避自动重建。
2. **启动瞬时竞态**：时段相关偶发 `mcp_alive=false`（R2 某时段 6/6 死 / 另一时段 8/8 活；指挥官复测 5/5 活，未复现）。建议「起服 30s 内 mcp_alive 恒 true」作常驻冒烟门。
3. 错误体含裸 `[Errno 22] Invalid argument`；不存在的 task_id 返回 502 而非 404（语义偏差）。
4. `active_namespaces=[]` 语义待钉（前端 ns 下拉目前只回退 default + fist-mbt-web）。
5. SSE 响应行 `HTTP/1.0`（未设 `protocol_version`）+ 断连客户端空转线程清理策略待评；7 叶（`T0r2.1.3`/`T0r2.3.x`/`T0r2.4.x`）待领取未收口。