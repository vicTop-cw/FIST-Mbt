# 2026-11-21 唤醒巡检 R27 报告 — EP-03 watcher 四层死链定案 + 判据三红复跑

- 轮次：R27（Windows 计划任务 FIST-Mbt-ExploreWatchdog 唤醒，findings-only 非阻塞巡检）
- 前序：[R26 报告](2026-11-21-wakeup-r26-report.md)（本报告定案其遗留 #1）
- 模式：fist-commander；本轮**未改任何跟踪面代码**（原因见 §六）

## 一、结果摘要

| # | 事项 | 结论 |
|---|---|---|
| 1 | 并发 WIP | f094 多管家收口仍在飞：主工作树 43+ 文件未收口（src/**、run_guards.py、plugins/**、docs/AGENTS* 等），本轮全程避让 |
| 2 | 判据三红复跑 | **依旧三红**（EP-03 收口方尚未同步，见 §三）——属他方在飞，不代修 |
| 3 | BUG-32 新鲜度 | 构建产物（mtime 1795203234）新于全部源文件（最新源 1795200003）⇒ **不触发**，FIST 链可安全起跑 |
| 4 | **R26 遗留 #1 定案** | **升级为算法级实锤，且死因从 2 层扩到 4 层**：EP-03 watcher 自动派发当前形态功能面为零（§五） |
| 5 | 新发现 | 守护进程根本没在跑：无 pidfile、scripts/ 无启动器、`start` 子命令是**假启动**（只写 pidfile 不 spawn，§五 L1 / §六） |
| 6 | FIST 闭环 | T0r2 六步全绿（首发缺 assignee/namespace 补跑后闭环，§七） |

## 二、并发 WIP 与提交面

- `git log --oneline` 头部：`51c3ea6ce`（R26 唤醒巡检报告）、`18810300b`（EP-03 派发脚本）、`be5f154f8`（query 三件套）、`7cc572cd2`（F094 Phase1）、`d3da675dc`（F094 Phase3 worktree dispatch）。
- 工作树 M 面 43+ 文件属另一 agent 的 f094 多管家收口（`.dsh/fist-mbt-plugin/`、`plugins/**`、`src/**`、`scripts/run_guards.py`、`README*`、`USAGE.md`、`AGENTS.md`、`docs/**` 等）——**本轮零接触**。
- 本轮落盘面仅三处：`reports/2026-11-21-wakeup-r27-report.md`（本报告，唯一提交物）+ `temp/fist_r27_chain.sh` / `temp/fist_r27_tid.py`（链脚本，temp 面不提交）。

## 三、判据复跑（三红依旧，不代修）

三条判据本机复跑结果与 R26 读数**逐项相同**，均为 f094/EP-03 收口方未同步所致：

| 判据 | 读数 | 根因 | 归属 |
|---|---|---|---|
| `check_py_stdout_encoding.py --all` | FAIL：`fist_dispatch.py` 缺 stdout UTF-8 重配（179/180 已带闸） | `18810300b` 落脚本时未带 `sys.stdout.reconfigure(encoding="utf-8")` 闸 | EP-03 收口方 |
| `check_scripts_index.py` | FAIL：`fist_dispatch.py` 未在 `scripts/README.md` 登记 | 同上，漏登记 | EP-03 收口方 |
| `check_battery_count_doc.py` | FAIL：X1 登记 158/现读 159、X6 登记 23/现读 24 | 登记数未随新脚本推进 | EP-03 收口方 |

三项修复都落在 `scripts/README.md`（他方 WIP 文件）+ `scripts/fist_dispatch.py`（EP-03 域文件）⇒ 必须**同批**由收口方处理（改计数面还需同批 `gen_plugins.py` 重投影，AGENTS 提交门禁），本轮不代修。

## 四、BUG-32 新鲜度探测（不触发）

- `_build/js/debug/build/cmd/cli/cli.js` mtime **1795203234** > 全部源文件最新 mtime **1795200003** ⇒ `ensure_fresh` 不触发 autobuild，FIST 链六步均按现有产物起跑。
- 本轮源文件零改动，探测结论在本轮内稳定成立。

## 五、R26 遗留 #1 定案升级：EP-03 watcher 四层死链（算法级实锤）

R26 #1 的怀疑是「规则 2/3 子目录 glob 三段锚定 vs 事件路径带监控根前缀 ⇒ 疑似永不命中」。
本轮把三块承重实现全部亲读（matcher 算法、glob 算法、rx-mbt js/native 事件源），定案升级：

**死因共四层，各自独立致命**——任一层单独存在就足以让「写事件自动派发」零效果：

### L1 无人拉起 + `start` 假启动（本轮新发现）

- 仓库根**无 `.mcp-watch.pid`**；`scripts/`（201 文件）与 `docs/`（135 文件）均无 watcher 启动器/启动约定 ⇒ **没有任何东西负责拉起守护进程**。
- `mcp-watcher start`（`.mooncakes/vicTop-cw/mcp-watcher/cmd/main/main.mbt:527-611`）**只写 pidfile 就返回**「✓ 守护进程启动成功」——pid 用时间戳占位（`:586` 注释自认「无法获取真实 pid」），**不 spawn 任何进程**；`stop` 子命令待实现（`:684-690`）。任何人/AI 跑 `start` 都会误信守护在跑。
- 真守护是 `run` 子命令（阻塞常驻），但仓库内无一处调用它。

### L2 js 后端 recursive 双层丢弃（本轮新死因，比 R26 的前缀问题更强）

- mcp-watcher 侧：`watch/backend.mbt:205-212` js 分支 `let _ = recursive` 丢弃；
- rx-mbt 侧：`monitor/watcher_js.mbt:71` FFI `fs.watch(path, { persistent: true }, …)` **根本没把 recursive 传给 fs.watch**。
- ⇒ 对 `watch_dir="."` 的监控是**非递归**的，`.fist-mbt/data/fist-self-tidy.db*` 这类**两层深**子目录事件**根本到不了回调**（Windows ReadDirectoryChangesW 非递归只报直接子项）。规则 2/3 在「事件到达」这一步就已经死了，轮不到匹配。

### L3 `./` 前缀 × 首段锚定失配（R26 推演 → 本轮实锤，机制定位到行）

- 事件路径构造：`watcher_js.mbt:26-27` 回调里 `join_path(path, fname)`，`:48-54` 实现对不带尾斜杠的根补 `/` ⇒ `watch_dir="."` 时事件路径 = **`./.fist-mbt/data/fist-self-tidy.db-wal`**。
- 匹配算法：`rule/matcher.mbt:11-17` 含 `/` 的模式走**整路径**匹配；`util/glob.mbt:82-126` `glob_match` 按 `/` 分段、首段必须命中且无 `**` 时不回溯（`:101-109` 失配即 false），`segment_match` 无通配符时**精确相等**（`:28-31`）。
- ⇒ 模式 `.fist-mbt/data/fist-self-tidy.db*` 首段 `.fist-mbt` vs 路径首段 `.` 精确相等失配 ⇒ **永不命中**。
- 对照组规则 1（`BACKLOG.md`，不含 `/` ⇒ basename 匹配 + 顶层文件）在 js 后端**可命中** ⇒ 同一配置「1 活 2 死」的机制定位闭环，与 R26 观测一致。

### L4 ExecPolicy 60s < fist.py node 冷启动（R26 已录，维持）

- `action.mbt:81` ExecPolicy 超时 60s（R26 报告 §缺陷候选 #4）；而本机 `fist.py call` 每次独立拉起 node MCP server、冷启动 ~2min ⇒ 即使命中规则，派发动作也会被 watcher 自己的策略杀掉。

### native 后端残差

`watch_folder_native`（`monitor/watcher_native.mbt:59-67`）**支持 recursive** 且 mcp-watcher native 分支会透传（`backend.mbt:196-201`）——native 后端没有 L2。但事件路径由 C 桩拼接（R26 引证 `watch_native_stubs.c:130-137` 根原样拼接 ⇒ 同样带根前缀，L3 仍在）；C 桩源文件不在 `.mooncakes` 包内，本轮未亲读，**留作残差**（修复轮若走 native 形态需实读 C 桩定路径形状）。

### 定案级别与 live-fire 残差

- 级别：R26 的「静态推演」→ **算法级实锤**（三块承重实现亲读 + 逐段推演，每层死因锚定到具体行号）。
- 残差：live-fire 复测（起 daemon + `touch .fist-mbt/data/fist-self-tidy.db-wal` + 断言 `fist_stale_dispatch` 被调起）**保留为 EP-03 修复轮验收项**——本轮起 daemon 需构建 mcp-watcher 产物（`_build` 无现成 watcher 构建，见 §十），与并发 WIP 的 `_build` 使用相撞，非阻塞轮不冒此险。

## 六、本轮不改码边界（任务分配记录）

本轮是**单人指挥官轮**（唤醒巡检性质，无子代理派发），工作分配如下：

| 事项 | 处置 | 不代修原因 |
|---|---|---|
| 判据三红（`fist_dispatch.py` 编码闸 / `scripts/README.md` 登记 / battery 锚漂移） | 留 EP-03 收口方同批修 | `scripts/README.md` 是他方 WIP 文件；计数面改动须同批 `gen_plugins.py`（AGENTS 提交门禁） |
| L1/L2/L3/L4 四层修复 | 留 EP-03 修复轮（收口方） | L2 涉 rx-mbt 兄弟仓 API（单独提交+发布，AGENTS「同族一源库」规则）；L1/L3/L4 在 mcp-watcher 包（`.mooncakes` 不可手改，须上游仓库改） |
| live-fire 复测 | 留 EP-03 修复轮验收 | 需构建 watcher 产物，与并发 WIP 的 `_build` 相撞 |
| 账本立账（BUG 号） | **不立**，findings 留档本报告 | `memory/bugs.md` 改动须同批 `gen_plugins.py` 重投影，而 `plugins/**` 在他方 WIP 内——R26 同款回避口径 |

## 七、FIST 闭环记账

- ns=`wakeup-patrol`，agent=`commander-atomcode`；task_id=**T0r2**（publish rc=0；回执 `writable_agents:1`——r26 的授权行仍在库）。
- 六步 rc：publish=0 / acl=0 / claim=1→**0** / execute=1→**0** / submit=1→**0** / verify=1→**0**（→ 后为补跑值）；任务终态「已完成」，completed_by=commander-atomcode。
- 首发撞墙两处与修法（**后续 ns 化链脚本的必带参数**）：
  1. `claim` 必填 `assignee`（schema required=`[task_id, assignee]`，server.mbt:2939）——只传 `--agent` 被 BUG-23 当场拒绝（行为正确）；
  2. `claim`/`execute`/`submit`/`verify` 的 `namespace` **缺省 default**——三写步的 ACL 门先于任务查找、按 default ns 判 can_write=0 直接拒绝（回执给的是 default ns 的出路指引）；显式 `--namespace wakeup-patrol` 补跑后四步全通。
  - 复盘：r26 链未踩这两坑，因为它按轮 199 记忆（m-8356dc4f）带了完整参数——其 claim 撞的就是 wakeup-patrol 的 ACL 门（R26 日志实证），证明路由正确；本轮链脚本重建时只凭上一轮摘要、漏了这两项。**重建链脚本前先查记忆条目，勿只凭摘要**；本轮起 ns 化链每步显式带 `--namespace`，claim 另带 `--assignee`。
- 附带实测（旧口径修正）：产物新鲜（BUG-32 不触发）时每步仅 ~1 秒——首发 6 步总耗时 7 秒（04:40:22→04:40:29）、补跑 4 步 5 秒（04:45:05→04:45:10）。记忆里「fist.py call 每发 ~2min」实为 **autobuild 触发时的构建耗时**（BUG-32 路径），非 node spawn 本身。
- 链日志：`temp/fist_r27_chain.log`（含首发失败回执全文，可作 BUG-23 / ACL 双门行为样本）。

## 八、遗留风险

1. **EP-03 自动派发功能面为零**（四层死链叠加），而其配置 `.mcp-watch.json` 三条规则里两条已在静默死亡状态——若有人据「规则已配置」推断「自动派发在生效」，会得出错误的安全感。
2. **`start` 假启动是误信放大器**：回执打印「✓ 守护进程启动成功」且带 pidfile，观测面（`status`）也会显示「已启动」⇒ 比单纯没启动更危险。
3. rx-mbt js FFI 不透传 recursive 是**通用层**缺陷：mcp-watcher 之外任何依赖 `watch_folder(path)` 的 recursive 语义的调用面（如 rhop watch/relay 的递归监控预期）在 js 目标同样静默失效。
4. native C 桩路径形状未亲读（残差），修复轮若按 native 形态修 L3 需先实证。

## 九、后续建议（并入 R26 建议 2/4，升级版）

1. **patterns 侧零依赖止血（可先行）**：规则 2/3 模式改写为 `**/fist-self-tidy.db*`——`glob_match` 的 `**` 跨段回溯（`util/glob.mbt:94-97`）可兼容任意根前缀（`./` 与绝对路径通吃），js/native 两形态都不用改码即可命中；需 live-fire 验证。
2. **L2 治本（rx-mbt 侧）**：js FFI 给 `fs.watch` 传 `recursive`（`fs.watch(path, { recursive: true })`），或在 monitor 包新增 `watch_folder_js(path, recursive~)`；兄弟仓单独提交+发布，本仓 `moon update` 跟进。
3. **L1 治本（mcp-watcher 侧）**：`start` 要么真 spawn 守护进程、要么改回执措辞并在 `status` 里如实报「未在监听」；或在仓库内补启动器（挂宿主计划任务/看门狗，与 FIST-Mbt-ExploreWatchdog 同款机制）。
4. **L4 放宽**：ExecPolicy 超时按动作可配（或给 `fist.py` 加常驻 server 模式，避免每发 2min 冷启动撞 60s 上限）。
5. **EP-03 修复轮验收**（f094 收口后）：三红同步 + 本报告四层修复 + live-fire 复测（R26 建议 4 原样）。
6. mcp-watcher 上游面 ISSUE（R26 已列：on_error 出口、js recursive）合并本报告 L1/L3 证据。

## 十、资源消耗

- 模型轮次：本轮指挥官单人 ~15 轮工具调用（读码 8 + 探测/判据 3 + 链与报告 4）。
- 链脚本：首发 6 步 7 秒 + 补跑 4 步 5 秒（产物新鲜时每步 ~1s；「每步 ~2min」是 autobuild 触发口径，已修正记忆 m-5171c103）。
- 人工介入：0。

## 十一、超额内容

- 无超范围改动：未触碰任何跟踪面代码；报告与链脚本均在计划内。
- 超出 R26 计划的**增量发现**：L1（无人拉起 + start 假启动）与 L2 的 FFI 层死因——R26 只定位到 patterns 侧，本轮把 kill chain 挖到四层。

## 十二、来源

- 亲读实现（本轮定案证据）：`.mooncakes/vicTop-cw/mcp-watcher/cmd/main/main.mbt`、`rule/matcher.mbt`、`util/glob.mbt`、`watch/backend.mbt`；`.mooncakes/vicTop-cw/RX-MBT/monitor/watcher_js.mbt`、`watcher_native.mbt`。
- 引证前轮：`reports/2026-11-21-wakeup-r26-report.md`（#1 疑似面、#4 ExecPolicy 60s、live-fire 建议）。
- schema 面亲读：`src/server/server.mbt`（claim/execute/submit/verify/agent_acl_grant 注册块）、`scripts/fist.py`（CLI 面与回执格式）。
- 判据复跑：`scripts/check_py_stdout_encoding.py --all` / `check_scripts_index.py` / `check_battery_count_doc.py`（读数见 §三）。

