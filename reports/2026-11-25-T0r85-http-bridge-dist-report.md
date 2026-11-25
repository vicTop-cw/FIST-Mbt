# T0r85 · HTTP 桥识别 dist（issue #1 P11 前置缺口）

- 日期：2026-11-25
- 任务池：ns `autoplan` / task_id `T0r85`
- 执行 agent：atomcode（自执行，未派子代理）
- 改动面：**仅** `scripts/run_fist_mbt_http.py`（单文件）
- 报告路径：`reports/2026-11-25-T0r85-http-bridge-dist-report.md`

## 1. 结果摘要

HTTP/SSE 桥 `scripts/run_fist_mbt_http.py` 原先只在 `_build/js/debug/build/cmd/cli/cli.js`
与 `target/js/release/build/cmd/cli/cli.js` 两个**构建缓存位**里找 MCP 入口，二者皆无即
`FATAL 找不到 MCP 入口产物`。缺的那一格正是 issue #1 P11 的前置缺口：跨机云机器 / 干净克隆
上根本没有构建缓存，而 `dist/fist-mbt.js` 是**随提交入库的发行快照**。

本次补上两条解析能力（不改其余任何行为）：

1. `resolve_server_js(env)`——入口解析链 **FIST_SERVER_JS（显式钉死）> _build > target > dist/fist-mbt.js**；
2. `FIST_SERVER_JS` 环境变量——把任意产物（含 `dist/fist-mbt.js`）**严格钉死**为唯一入口。

### 一个有意的不一致（写明，避免下一个人"顺手统一"）

`MAIN_CANDIDATES` 常量**保持原顺序不变**（`_build`、`target`），dist 不进该元组。原因：
`scripts/run_fist_mbt_web.py:67` 复用 `MAIN_CANDIDATES[0]` 做新鲜度检查
（`ensure_mcp_build()`：`[0]` 不存在才补 `moon build`）。把 dist 塞进元组会让那个门在
`_build` 缺失时不再触发补建 ⇒ 门失效。入口解析链独立取 `list(MAIN_CANDIDATES) + [DIST_SERVER_JS]`。

### dist 放末位而非首位

本机优先用刚构建出的 `_build`（它才追得上源码），dist 只当**兜底**。曾试过 dist 首位再改回：
`dist/fist-mbt.js` 实测版本 `0.3.11`、`_build` 是 `0.3.15` ⇒ 同一台机器上默认起的是**更旧**那份，
这是把回退位误当首选位的直接代价（判例-32「版本号 PASS ≠ 代码新鲜」同族）。

### 显式钉死是严格的，不是"首选"

`FIST_SERVER_JS` 指向不存在的路径时**报错退出**，不会静默换回默认链。理由：显式意图被悄悄替换
等于让"桥实际起的是哪份代码"变成不可观测的——那正是本仓反复吃亏的形态。报错文案随之改为
点名**真试过的路径**（不复述候选表），否则钉错路径时提示会把人指向错的下一步。

## 2. 产出物（路径清单）

| 路径 | 性质 |
|---|---|
| `scripts/run_fist_mbt_http.py` | 唯一改动对象（新增 `DIST_SERVER_JS` / `resolve_server_js()`；`_find_command()` 改用解析链并记录 `tried[]`；错误行改口径） |
| `reports/2026-11-25-T0r85-http-bridge-dist-report.md` | 本报告 |
| `memory/2026-11-25.md` | 当日日志 append（本地留置，`.gitignore:162` 忽略，不入库） |
| `temp/t0r85_http_probe.py` | 本轮实测探针（temp/ 下，一次性） |

未改动、仅登记的同族副本（各自另有一份候选表，本轮刻意不动以免扩大改动面）：
`scripts/fist.py:53-68`、`scripts/mcp_smoke.py:49-66`、`scripts/check_output_validate.py:47-50`、
`scripts/fist-gateway.py:92-95`。

## 3. 实证读数（全部本机实跑，2026-11-25）

工具链：`node -v` = v25.2.1；`python` = 3.13（WindowsApps）；平台 Windows。

### 3.1 解析链单元面

| 场景 | 实读 |
|---|---|
| 默认（不设 env） | `['_build\\…\\cli.js', 'target\\…\\cli.js', 'dist\\fist-mbt.js']` |
| `FIST_SERVER_JS=dist/fist-mbt.js` | `['<ROOT>\\dist\\fist-mbt.js']`（绝对化，唯一项） |
| `FIST_SERVER_JS=/tmp/x.js` | `['\\tmp\\x.js']`（保持绝对路径） |
| `MAIN_CANDIDATES[0]`（web 复用面） | 仍为 `_build\\js\\debug\\build\\cmd\\cli\\cli.js`（**未变**） |

### 3.2 沙箱对照（复刻"只有 dist"的宿主形态）

在 `temp/t0r85_sandbox/`（只放 `scripts/run_fist_mbt_http.py` + `scripts/patch_esm_main.py` +
`dist/fist-mbt.js`，**无 `_build`/`target`**）、以该目录为 cwd 实跑：

| 场景 | 实读 |
|---|---|
| A 默认（无构建位） | `['node', 'dist\\fist-mbt.js', 'serve']` ← **dist 兜底生效** |
| B 显式 `dist/fist-mbt.js` | `['node', '<sandbox>\\dist\\fist-mbt.js', 'serve']` |
| C 显式不存在的路径 | `ERROR 找不到 MCP 入口产物（试过的路径：<sandbox>\missing\x.js）` → `_find_command()` 返回 `None`（调用方 `sys.exit(1)`）；**不回落到 dist** |

（一格方法论注记：同一段脚本先在仓库根 cwd 下跑会误命中 `_build`——`is_file()` 相对**进程 cwd**
解析而非 ROOT。沙箱必须在沙箱 cwd 下跑，否则测到的不是目标语义。）

### 3.3 端到端（真入口 `python scripts/run_fist_mbt_http.py <port>`，非自造调用形状）

两轮各自起桥 → `/health` → `tools/call status_summary` → 收桥日志：

| 模式 | health | 回执 serverInfo.version | 桥日志首行 |
|---|---|---|---|
| build（不设 env） | `200 {"status":"ok","product":"FIST-Mbt","transport":"http"}` | `0.3.15` | `Starting MCP server: node _build\js\debug\build\cmd\cli\cli.js serve` |
| dist（`FIST_SERVER_JS=dist/fist-mbt.js`） | `200`（同上） | `0.3.11` | `Starting MCP server: node E:\IDEProjects\AI\FIST-Mbt\dist\fist-mbt.js serve` |

`status_summary` 回执正文（两模式均 `isError:false`）：
`{"version":…,"total_tasks":0,"by_status":{},"done_no_artifact":0,"by_difficulty":{"易":0,"中":0,"难":0,"无":0},"active_namespaces":[]}`。

### 3.4 幂等与洁净面

- `python -m py_compile scripts/run_fist_mbt_http.py` → OK
- 桥起服时对 dist 注入 ESM require shim 为**幂等 no-op**（dist 已带 `createRequire`，计数 1）⇒
  探针跑完 `git status --short dist/` 为空、mtime 仍是 `2026-11-17 10:32:48`（未被写入）。
- `check_entry_paths.py` rc=1，但 5 处违例全在 `scripts/blackbox/e2e_agent_*.py`（argv 未带 serve），
  **不含** `run_fist_mbt_http.py`（grep 计数 0）⇒ 非本次引入。
- `check_scripts_index.py` rc=1，缺登记的是 `pack_exe_to_md.py` / `web_bridge.py`（既有 WIP）。
- 本文件是既有跟踪文件的原地修改 ⇒ 不触发判例-5（新 `.py` 需执行面）。

### 3.5 一次探针自身的失败，记下来免得被当成产品缺陷

首轮 HTTP 探针拿到 `502 {"error":"Server not running"}`。**对照实验证明它与本次改动无关**：
同一探针在 build 模式下同样 502。根因是探针用 importlib 加载桥模块后自建 server，未走
`main()` 的起服路径（桥模块在 import 期即执行 `PORT = resolve_port(sys.argv[1:], os.environ)`，
且请求形状与真入口不同）。改成直接 spawn 真入口后两模式全绿。
（过程注：早前一版探针经管道 `| tail` 挂死——桥 spawn 的 node 子进程继承父 stdout，
父 Python 被 terminate 后写端仍被持有，`communicate()` 等不到 EOF ⇒ 探针输出改落盘文件。）

## 4. 遗留风险

1. **dist 是快照，会落后于源码**：实测 `dist` = 0.3.11 vs `_build` = 0.3.15。兜底位解决的是
   "起不来"，不是"起得太旧"。若某轮只有 dist 可用而源码已前进，桥会静默跑旧版——
   目前无任何判据拦这一格（`check_dist_snapshot.py` 只守 dist 自身版本 == moon.mod，
   看不见 `_build` 的新旧差）。建议在 `resolve_server_js` 命中 dist 时打一条 WARN（本轮未加，
   属最小改动边界外）。
2. **`FIST_SERVER_JS` 空串 = 未设**：`strip()` 后为空则走默认链。显式写 `FIST_SERVER_JS=""` 不会被
   当成"钉死到空路径"，属刻意的宽松。
3. **同族四个脚本仍是各自的候选表**：`fist.py` / `mcp_smoke.py` / `check_output_validate.py` /
   `fist-gateway.py` 都复制了 `_build`/`target` 两候选，没吃到 dist 兜底 ⇒ 跨机形态下它们仍会 FATAL。
   本轮按约束只读登记、未改；若要一并收口，建议单立任务（四处同改 + 各自 e2e）。
4. `check_entry_paths` 的 5 处 `e2e_agent_*` 违例是既有红面，不在本单范围；本文件未被它点名。

## 5. 后续建议

1. 单立任务：把 dist 兜底推广到同族四脚本（`fist.py` / `mcp_smoke.py` / `check_output_validate.py` /
   `fist-gateway.py`），抽公共 `resolve_server_js()` 消重（判例「同一规则多份实现」）。
2. 单立任务：命中 dist 兜底时打 WARN + 在 `/health` 回执里带上实际入口路径与版本
   （现在桥对外只说 `transport: http`，"起的是哪份代码"不可观测）。
3. `temp/t0r85_http_probe.py` 与 `temp/t0r85_sandbox/` 是一次性件，可留作回归探针或清掉。

## 6. 来源

- 计划真源：`fist-mbt/plan/active/2026-11-25-fist-agent-worker-issue1.md:14`（本任务原文）
- 任务池：ns `autoplan` / `T0r85`（HTTP 实测：status 执行中，assignee atomcode，priority/importance 高，depth 3）
- 仓库既有读数（引用不自造）：`moon test --target js` 2067/2067（2026-11-11 Windows 本机）；
  本地 native 必崩（BUG-527 `-lsqlite3`），本轮未跑 native。
- 全部本报告读数为本轮实跑所得，见 §3。
