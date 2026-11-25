# T0r71 验收报告：本机消息闭环链路 + native/js 全绿

- **任务**：T0r71（ns=autoplan，status=执行中）
- **执行身份**：freebuff
- **日期**：2026-11-25
- **验收口径真源**：`fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md:52`
- **约束遵守**：只读盘点 / 最小改动；生产面零写入（未推公网、未改 `.mcp-watch.json`、未动 `.fist-mbt/msg/`）；全部实验落在 `tmp/t0r71_sb/`。工作树 he 方 WIP 一律未动。

---

## 一、结论摘要

| 链路段 | 判定 | 一句话凭据 |
|---|---|---|
| ① 落盘 `.fist-mbt/msg/inbox/*.json` | **通** | 桥 `msg_pull_git()` 实测 `landed=1`（peer 投递 m2 → 本地 inbox 落盘） |
| ② watcher fs watch 触发 | **断** | 三种挂法 + command 探针 + 就绪哨兵，事件命中数 **0**；同目录 Node 原生 `fs.watch{recursive}` **能**收到 |
| ③ 目标网关收 execute | **通（投递面）** | svc-codearts(18641) `execute` 真调用返回服务端业务回执「任务处于[已完成]…」+ autoplan ns 校验；即请求到达并被处理 |
| ④ `processed/` 归档移动 | **断（实现侧无此动作）** | mcp-watcher 全目录 grep `processed/.failed/trash_move` 在 scheduler/action 层**零命中**；归档由桥侧手工移动承担 |
| ⑤ git 提交回执 push 远端 | **通** | `msg_push_git()` 实测 `pushed=True`，远端树出现 `.fist-mbt/msg/processed/m2.json` |

**⇒ 端到端闭环当前不成立**：缺 ②（watcher 事件投递）与 ④（自动归档）。①③⑤ 三段各自实测通过，但串不起来——② 断则 watcher 永不触发 ③，④ 断则 `processed/` 只能靠人肉移动，"git 回执"失去自动来源。

**native/js 读数**：JS **2085/2085 passed, failed: 0, rc=0**（逐包复跑，见 §四）；native 本机**不可跑**（BUG-527）。故"全绿"在本机只能证 JS 一臂。

---

## 二、证据（逐条可复现）

### E1 桥 pull→land：真跑通过

沙箱 `tmp/t0r71_sb/run_bridge_probe2.py`（本地 bare 远端 + peer clone 扮演跨机投递者）：

```
[setup] baseline pushed; remote msg tree:            ← 基线三态目录为空
[peer] dropped m2 -> remote
[bridge msg]      rc=0 stdout=landed= 1  pushed= False
[bridge msg #2]   rc=0 stdout=landed= 0  pushed= True
[verify] remote msg tree AFTER:
.fist-mbt/msg/processed/m2.json
[RESULT] local_processed=True receipt_on_remote=True
```

- 第一发 `landed=1`：远端 `inbox/m2.json` 被拉下并落到本地 `.fist-mbt/msg/inbox/`（桥的 `msg_land` 幂等去重，已归档的不再重投）。
- 第二发 `pushed=True`：把本地 `processed/m2.json` 用临时 index（`GIT_INDEX_FILE=.fist-mbt/tmp/git_msg_bridge/msg_index`）基于 `origin/HEAD` 构造 commit 直推远端分支。
- 该脚本同时证明**增量性**：回执是这一轮推上去的，不是基线自带（修正版特意让基线不含 m1/m2）。

> 桥本体的完整 `--once` 面另跑过一次（`run_bridge_probe.py`），rc=1，失因在 `cmd_export` 的 pool 依赖（沙箱 DB 无 tasks 表），**与 msg 段无关**；msg 段单独调用两次 rc=0。此处如实区分，不混报。

### E2 watcher 事件面：三种挂法全静默

同一既存 js 产物 `E:/IDEProjects/AI/_build/js/debug/build/cmd/main/main.js`：

| # | watch_dir | recursive | 规则动作 | 结果 |
|---|---|---|---|---|
| A | `.../proj` | true | webhook→execute | 无事件行、results 空、进程不退出 |
| B | `.../proj/.fist-mbt/msg/inbox` | false | webhook→execute | 同上 |
| C | `.../proj/.fist-mbt/msg/inbox` | false | **command**（python 写探针文件） | `cmd_probe.txt` **不存在** = 动作从未执行 |
| D | `.../t0r71_sb/inbox2` | false | command + `--ready` 哨兵 | 哨兵 `ready2.txt` 正常落盘（进程进入监控态），触发后探针文件仍不存在 |

**对照实验（决定性）**：同一时刻、同一目录，Node 原生 API 直接能收到子目录事件：

```
EVENT rename .fist-mbt\msg\inbox\probe_node.json
GOT_EVENT
```

⇒ 失因不在"目录/权限/debounce"，而在**产物的事件订阅链**本身。且这不是 r27 记的 L2（rx-mbt js FFI 不传 recursive）——产物里已是 EP-03 递归版（`ffi__watch__start_rec` 明确 `fs.watch(path,{persistent:true,recursive:true})`，`rx_watch_source(path, recursive)` 按 `recursive` 布尔路由，且 `process.getBuiltinModule` 在本机 node v25.2.1 可用）。B/C/D 三发连**单层非递归**都收不到，说明比 L2/L3 更靠前的一层断了（疑似产物构建于 11-21 17:48，早于 mcp-watcher 源码 11-24 19:13 的最近改动；且该产物 `v0.2.3` 与当前依赖版本需对表）。

### E3 网关 execute：投递面真实可达

- svc-codearts `http://127.0.0.1:18641/mcp`，header `X-API-Key`（无 key → HTTP 401）。`initialize` 200 → `serverInfo{name:"fist-mbt", version:"0.3.15"}`；`tools/list` = **197 工具**，含 `execute`。
- 真调用（不带 ns）：返回 `-32000 acl: ACL 默认拒绝写（can_write=0）: cdc284d29c2484e3/default … 判定身份: dsh-verify-l3（fp=…，来源=task-assignee）` —— **服务端确实收到并处理了这次 execute**，只是被该 ns 的 ACL 拦下。
- 带 `namespace:"autoplan"` 再调 T0r79：返回 `-32000 非法执行: 任务处于 [已完成]。出路：已完成→原地更正交付物请 reopen_task（→待领取）后重新走链路` —— 路由正确命中 autoplan 与 T0r79。
- 另测不存在 id → `-32000 "task not found"`（探针安全，未污染真实任务）。
- svc-freebuff `18643` `initialize` 同样 200 / fist-mbt 0.3.15。

⇒ ③ 段判**通**：webhook 若能发出来，网关会接收。当前卡点纯粹在 ②。

### E4 processed 归档：watcher 侧不存在该动作

- `.mooncakes/vicTop-cw/mcp-watcher/action/` 与 scheduler 层 grep `processed|.failed|trash_move|move_to`：**scheduler/action 零命中**；`action.mbt` 里的 trash 语义是 **P3 生命周期产物回收**（`<watch_dir>/.mcp-watcher-trash/<时间戳>/<name>`，TTL 到期清扫），与 msg 池的 `processed/` 三态**同名不同义**，不是归档实现。
- 动作 kind 全集仅 `command` / `internal(reload_config,pause_watch,resume_watch,log_event)` / `mcp_tool_call` / `webhook` ⇒ 没有"移动到 processed/"这种内建动作。
- 桥 `git_pool_bridge.py` 侧只做**读取** `processed/` 并推送（`msg_push_git`），同样不产生归档。
- 设计文档所称"归档移动全部现成"与实现不符 ⇒ **缺口，需补一段"消费成功 → move processed/"的实现**（watcher 侧动作或独立小工具）。本轮为最小改动未实现，仅出方案。

### E5 服务登记与 watcher 守护现状

- 登记真源 `.fist-mbt/data/agent-services.db`：svc-freebuff=freebuff@18643、svc-codearts 18641、svc-atomcode 18640、svc-marvis 18644、svc-webai 18645、svc-agent 18649、svc-xiaoquan 127.0.0.1:18650、svc-autoclaw registered 未起；`.fist-mbt/data/svc-*.apikey` 九枚齐备。
- `.mcp-watch.json`：`watch_dir="."`、`recursive=true`、`allowed_programs=["python"]`、5 条规则，**无任何 msg/inbox 规则**；全盘 grep 亦无第二份含该规则的配置。
- 进程面无 watcher 守护（无 `main.js run` 常驻进程）。计划任务 `Mbt-AgentServiceWatch`(ONLOGON) 拉起的是 FIST-Mbt 自身 js 产物 `E:/IDEProjects/AI/_build/js/debug/build/cmd/main/main.js`（684445 B → 实际 681400 B，11-21 构建）。
- `.fist-mbt/msg/` **当前不存在**（`.fist-mbt/` 下仅 cache/data/db/lock/logs/pool/scripts/state/tmp）⇒ 生产面 ① 段目前也无承载目录，需先 `ensure_msg_dirs()` 建起来。

---

## 三、native/js 读数

### JS：2085/2085 passed, failed: 0, rc=0

```
moon test --target js -p src/core src/claimguard … src/symbolic cmd/cli cmd/main tests/smoke
Total tests: 2085, passed: 2085, failed: 0.
status: exited (code 0)
```

**为什么是逐包而不是全仓一条命令**（如实说明，不粉饰）：

- 直跑 `moon test --target js` **rc=1**，编译错误**全部集中在一个文件**：`src/longrun/baton_wbtest.mbt`（`:84 Some(Number(n,_))`、`:185/:200/:210 raw.replace(needle,…)` 位置参数），7 处 `[4080]`/`[4086]` 全在该文件。
- 该文件 **untracked（`??`，mtime 11-25 16:02）**，头部自述"T0r58 交接包生成/消费的白盒锁"，契约真源 `docs/plans/2026-11-25-longrun-baton-handover-contract.md`（同 untracked）⇒ **他方在办 WIP，用的是旧 moonc 语法**。按工作树纪律未动它。
- 因此改用 `-p` 逐包过滤剔除 `src/longrun`，得到上表绿面。**这不等于全仓绿**：longrun 包（含 baton/guard/longrun 三套测试）本轮**未被覆盖**。
- `scripts/moon_test_env.py --target js` 两轮均自拒 rc=2（「判据无法自证：没有汇总行 `Total tests:`」），与上述同源，非判据坏。

### native：本机不可跑（BUG-527，实测形态记录）

```
moon test --target native src/core
Error: Failed to resolve the module dependency graph
Caused by: 0: When installing packages  1: 拒绝访问。 (os error 5)
```

- 与 AGENTS/账本 BUG-527 记的"Windows 本机 native 必崩"一致（带 link 库包被当可执行目标去链，MSVC/GCC flag 不兼容）。
- 权威 native 面在 CI Linux nightly，本机无法取证 ⇒ 本报告**不宣称 native 全绿**。

---

## 四、缺口与风险

| # | 缺口 | 影响 | 建议 |
|---|---|---|---|
| G1 | watcher 事件投递静默（②） | 整条链断在第一跳；`.mcp-watch.json` 配了也不派发 | 优先：用**当前** mcp-watcher 源码 + 匹配版本重新构建 js 产物（现产物 11-21 早于源码 11-24），再复跑本报告 E2 的四格 |
| G2 | 无 `processed/` 自动归档（④） | 回执靠人肉移动，"自动 git 回执"不成立 | 补一个动作：webhook/mcp_tool_call 成功后 `mv inbox/<n> → processed/<n>`（桥侧或 watcher 侧均可，建议放桥侧以免再依赖 watcher 事件面） |
| G3 | `.fist-mbt/msg/` 三态目录不存在 | 生产面 ① 无落点 | 先跑一次 `python scripts/git_pool_bridge.py --once`（其 `ensure_msg_dirs()` 会建）或手工建三态目录 |
| G4 | 无 msg/inbox 规则、无 watcher 守护 | 即便 G1 修好，也没有常驻触发器与规则 | 在 `.mcp-watch.json` 增一条 `events:[create]` + `patterns:[".fist-mbt/msg/inbox/*.json"]` + webhook 指向目标网关；并接一个常驻启动（r27 L1：现 start 只写 pidfile） |
| G5 | `allowed_programs` 默认空 = command 动作不执行任何命令 | command 类规则静默失效 | 配规则时显式给 `["python"]`（本报告各探针均已显式给出，故不构成 E2 失因） |
| G6 | JS 全量被他方 untracked WIP 阻断 | longrun 包无绿面读数 | 待他方收口后复跑 `python scripts/moon_test_env.py`；本轮不代改 |

---

## 五、后续建议（按优先级）

1. **G1 复构建 + 复跑 E2 四格**：这是唯一能让 ② 翻案的路径，成本最低（一次构建 + 四个已有探针）。若新产物仍静默，则按 r27 口径升级 EP-03（产物/上游版本漂移，需 f094 收口方介入）。
2. **G2 归档动作落地**：建议放桥侧（`msg_push_git` 前由独立步骤做 `inbox→processed` 移动），使 ④ 不依赖 watcher 事件面；这样 G1 未修好也能先让"半条链"（落盘→人确认→归档→回执 push）可演示。
3. **G3/G4 一次性接线**：建三态目录 + 加规则 + 常驻启动，把 ①→⑤ 的静态面补齐。
4. 他方 `baton_wbtest.mbt` 收口后，复跑 JS 全仓 + `check_plugin_sync`/`run_guards.py`。

---

## 六、资源消耗

- 会话轮次：约 30 轮（含 7 次 watcher 真跑尝试、2 次桥探针、2 次 JS 全量、1 次 native 尝试）。
- 命令：moon test ×3、node 真跑 ×5、git 沙箱操作若干、MCP RPC 探测 ×4。
- 无长驻进程遗留（bg-3/4/5/6 已全部 kill；bg-7 已自然退出 rc=0）。

---

## 七、产出物路径

- 本报告：`reports/2026-11-25-T0r71-msg-loop-acceptance-report.md`
- 沙箱与全部原始读数：`tmp/t0r71_sb/`
  - `run_bridge_probe2.py`（桥回执闭环，修正版，结论来源）
  - `run_bridge_probe.py`（首版，含 export 段失败的真实记录）
  - `rule.json` / `rule_inboxroot.json` / `rule_cmd.json` / `rule_ready.json`（四格 watcher 探针规则）
  - `watcher.log` / `watcher2.log` / `watcher_cmd.log` / `watcher_ready.log`、`results*.jsonl`、`cmd_probe*.txt`

---

## 八、来源

- 验收口径：`fist-mbt/plan/draft/2026-11-24-msg-loop-closed.md:52`
- 桥实现：`scripts/git_pool_bridge.py`（`msg_land` `:122`、`msg_pull_git` `:136`、`msg_push_git` `:162`、`cmd_msg_sync` `:226`）
- 服务登记：`.fist-mbt/data/agent-services.db`；本机 watcher 规则：`.mcp-watch.json`
- watcher 源码：`E:/IDEProjects/AI/mcp-watcher/{watch,action,scheduler}`；依赖副本 `.mooncakes/vicTop-cw/mcp-watcher/watch/`
- 历史定案：`reports/2026-11-21-wakeup-r27-report.md`（EP-03 四层死链）、账本 BUG-527 / BUG-133 / BUG-142
