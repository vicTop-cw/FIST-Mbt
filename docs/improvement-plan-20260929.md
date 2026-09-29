# FIST-Mbt 改进计划 · 2026-09-29 修正版

> **输入**：`docs/improvement-proposals-20260928.md`（Loomy 建议书，12 条）+ `fist-evidence/实验/atgc-core/自动路由闭环实验报告.md`（`auto-route-20260927`；建议书引用的那份实验报告在这条路径，不在 `_fist_meta_prompts/实验/` 下，两份文档对同一发现的编号也不一致——见 §5）。
> **本版做的事**：把 12 条建议逐条打到**调用面 / 库面 / 守卫面**复测，能测的测，测不动的标明；据此改优先级。
> **读法约束**：下面每个数字都是本轮实测（命令在 §6），不是引用建议书的自述。建议书是 09-28 截面，此后仓库前进了 6 笔提交，其中 4 条建议的前提已经变了。

---

## 1. 实测基线（2026-09-29，本机 master）

| 面 | 实测值 | 口径 |
|---|---|---|
| 缺陷账本 | **118 条抬头 = 102 FIXED / 9 DUPLICATE / 4 FALSE_POSITIVE / 3 OPEN** | 从 `## BUG-n …` 抬头反解（待修=OPEN 数，同 `memory/bugs.md` 计数口径）；OPEN = BUG-116 / BUG-118 / **BUG-119（本轮新报）** |
| 建议书的「44 条 OPEN」 | 已过期 | 现状面 3 条 OPEN，且都在分发/看护/CI 三条线上，不是销账控制面缺位 |
| 注册工具数 | **129**（与 AGENTS/README 自述一致） | `server.mbt` 注册点反解 + 活体 `tools/list` 回读 `result.tools` 长度 |
| 任务库存量 | 1986 行 / 49 个 ns：待领取 982、已领取 408、已完成 395、拆分中 104、待验收 49、已归档 41、已打回 6、已暂停 1 | 只读打开仓库根 `fist-mbt.db` |
| 时间戳形状 | **87 行**（=165 个列值）不合 `YYYY-MM-DDTHH:MM:SSZ`：`+08:00` 本地偏移 95、带毫秒 Z 33、1969 负分量 22、无时区后缀 15；`heartbeats` 12 行里 9 行非规范 | 只读普查，见 §6 命令 4 |
| 调用面键纪律 | 历史 6904 条 call_log 中可比对的 6798 条里 **3272 条（48.1%）传了 schema 未声明的键**，其中 `now`/`ts` 命中 **2167 次、涉及 44 个工具**，这些调用绝大多数 `ok=1` | `call_log.params_json` 顶层键 ⊆ 活体 `tools/list` 的 `inputSchema.properties` |
| 安装线可达性 | `raw.githubusercontent.com/.../master/moon.mod` = **200**；`github.com/.../releases/download/v0.3.4/…zip` = **000**（三次各 21s 超时，非 404/403） | 只读 curl，不带任何凭据；与 BUG-116 的「本机链路挡住公网复验」同一格 |

---

## 2. 逐条对表

判定用四个词：**已兑现**（原诉求已被现实现满足）/ **仍缺**（成立，照做）/ **前提证伪**（现象或机制不成立，照做会修不到东西）/ **改写**（病灶是真的，位置不在它说的那里）。

| # | 原主张 | 实测 | 判定 |
|---|---|---|---|
| **P0-1** | `bug_close` API 缺位，单条销账只能走 `bug_fix` | `bug_fix` 支持任意 `bug_ids`（含单元素数组），同一笔改抬头 + 落 `### FIXED(盖章时间 / BUG-x)` 小记、幂等重跑（`server.mbt:5330`）；改判走 `bug_mark_status`（`:5360`）；账本 102 条 FIXED 全部由这两件落账，本轮我自己就这么销的。BUG-9 已 FIXED。真正缺的**不是 API**，是把 `bug_list.linked_task_status` ↔ 账本状态做成会红的双向对表 | **已兑现**（残留并入 P1′-5） |
| **P0-2** | 文档还写「显式传 now」，且服务端会把带 `now` 的调用**硬门拒绝** | ① 「硬门拒绝」不成立（活体带 `now=2020-01-01T00:00:00Z` 调 `publish_parallel` 建单成功，回读 `created_at=2026-09-29T02:58:40Z` 是服务端盖的——`now` 被**静默丢弃**，连 `nonsense_key` 也照样吞）；而「文档残留」成立但**位置指错了**：`templates/*.md` 里「传 now」零命中，残留在两本现状手册里——`USAGE.md` **36 处** `now` 参数（两个 JSON 调用示例还真写着 `"now":"2026-09-11T18:20:00Z"`），`AGENTS.md` Omega 表 6 行（3 行带 `now`；2 行把 `omega_verify`/`omega_verify_fix` 的入参写成 `task_id/判定/reason`，而活体 properties 是 `specs`(+`max_rounds`)）。外部库剩 1 处：`_fist_meta_prompts/plugin-dev/fist-mbt-plugin/commands/fist-night.md:15`。**为什么飘这么久没人看见**：`check_tools_sync` 判据 5 只扫 server.mbt 的广告位，J2 只比工具名覆盖，J8 只比 `templates/*.md` 的调用参数，`RE_TOOL_CLAIM` 四种形状都要带「MCP」而 USAGE 写的是「87 个工具」（活体实测 129）——正好全部躲过。这两格本轮已改，见 §7。② 唯一真读 `now` 的活口在 `loop_create`：HEAD 的 `server.mbt` 里 `get_str(args, "now", default=now_default())` 恰一处（HEAD 行号 2369；本轮工作区漂到 2379 ⇒ 锚点按内容取不按行号），值经 `ops_loop.mbt` 的 `created_at: now` 写进环记录，而它的 live schema **没有** `now`。 | **前提证伪 + 改写**（病灶三格：手册参数列/工具计数无判据、未声明键静默吞、`loop_create` 是唯一能影响时间戳却没 advertise 的入口） |
| **P0-3** | README 一条命令的安装线对公网用户是断的，差一次 CI | Release 已出包（v0.3.4，资产名同源判据 R1–R12 常驻）；本机侧「真的走下载」那一段由镜像 e2e（BUG-108）+ 文档线反解 e2e（BUG-113）覆盖；**卡的仍是公网复验**：raw 线 200、release 资产线 000（见 §1）。所以这条不是"差一次 CI"，是"差一次本机链路之外的复跑"= BUG-116 本体 | **仍缺**（收窄为 BUG-116 的收口条件，不另立项） |
| **P1-1** | server stdout 全缓冲 ⇒ 交互式 Popen 客户端死锁，EOF 才能绕 | 长驻 Popen（**不关 stdin**）：第 1 次 `tools/list` 0.25s 回 129 工具，同进程第 2 次往返 0.10s。死锁不复现。但同一探针的 stdout 前四行里**有两行不是 JSON**：`[fist] serve — 启动 MCP server (stdio 传输)` / `stdin/stdout 接管, Ctrl+C 停止`——严格 JSON-RPC 客户端第一帧就撞在这上面（BUG-76 记过、仍未收的那一面） | **前提证伪**（真残留＝协议 stdout 纯度，另立 P1′-1） |
| **P1-2** | `publish_parallel` 无幂等防重，重跑堆重复单 | 仍无 `idempotency_key`/防重标记（全仓 `idempot`/`dedup` 在产品面无命中）；对照现成机制：`selfdrive_publish_next` 用 description 内嵌 `[review:<file>:<idx>]`（`server.mbt:2676`）。库面实证：`auto-route-20260927` 至今躺着 **17 待领取 + 1 已暂停**（= 报告说的 18 条重复单，未清），另 4 条已归档是真正收口的那一批；本轮探针每跑一次就多建一单（T0→T0r11），症状当场可复现 | **仍缺**（保留 P1′-3） |
| **P1-3** | 人工 pause 被 watchdog/heal 当僵尸恢复，管理语义被执行语义覆盖 | 不复现：pause 回执 `已暂停` → `heal(namespace=… , timeout_sec=600)` 返回 `healed=[]` 且状态仍 `已暂停`；`watchdog_tick` 把它列进 `blocked/blocked_detail`（不当活跃）。代码对得上：`ops_heal.mbt:82` 活跃集＝执行中/已领取/拆分中，不含已暂停。**但同一轮实测炸出更严重的两格**（见 §3 新报），报告里「暂停后回到待领取」更可能是 18 条重复单躺在待领取里被读混了 | **前提证伪**（`paused_by` 白名单不再做；P1′-2 顶上来） |
| **P1-4** | `list(namespace=ns)` 过滤失灵、返回 0（BUG-12 现行变体） | 已修（BUG-85，09-27）：`store.mbt:75-96` 把 `list_tasks` 语义按声明收敛成"全量"，按 ns 取数走 `list_tasks_in`；活体实测无参 `list()` 返回 4 个 ns 共 5 行，`list(probeA)`/`list(probeB)` 各精确 1 行。回归锁也在：`store_backend_semantics_test.mbt:30`（两后端逐条同语义）+ `multi_store_test.mbt:39/66/205` | **已兑现** |
| **P1-5** | dispatch 只完成认领，执行器要人工拉起会话；缺 `fist executor spawn` | `executor_run` 已存在且能真起进程（固定 argv、`dry_run` 先审后跑、native 明确拒绝），但它的 live properties 是 `project_dir/executor/prompt/model/namespace/timeout_ms/dry_run`——**没有 `task_id`**，认领的那一单与起来的会话之间没有绑定，`execute/submit` 也没人替执行器回提；CLI 侧也没有 `executor` 子命令（词表只有 serve/version/demo/doctor/help） | **仍缺**（改名收窄为「任务绑定 + 回提」，不是新造 spawn 命令） |
| **P2-1** | 工具数 120→129 且持续增长，文档/计数守卫成本线性上涨 | 129 实测吻合；文档面成本可量化：`ci.yml` JS 轨有 17 处 `scripts/check_*` 调用，另加自述面探针与 CLI 调用面探针各 1 处 | **仍缺**（中期，先测边际成本再动） |
| **P2-2** | `bug_close` 之后做账本治理闭环（周报视角 / 发现阈值联动） | 前置已解除（P0-1 已兑现），可以直接做；但"积压年龄"这一格必须先解决时间戳形状：87 行脏形状里有 52 行 `+08:00`、22 个 1969 负分量值，`iso_to_secs` 按字面位置取数字、**不看偏移**（`ops_ts.mbt:24`），拿它算年龄就是假数 | **改写**（排到时间戳治理之后） |
| **P2-3** | 服务端盖章与系统时钟存在 ±1h 漂移（node 子进程 TZ 数据与宿主差异） | 不复现：同一时刻对表，服务端盖章 `02:57:36Z` vs 客户端 UTC `02:57:36Z` = **+0.2 秒**（`now_default()` 用 epoch 毫秒做纯 UTC 反解，`server.mbt:226`）。真正的形状问题在读侧与历史数据：95 个列值带 `+08:00` 被当 UTC 字面读（偏 8 小时）、22 个 1969 负分量值让 `iso_to_secs` 返 -1，于是 `ops_cleanup.mbt:22-24` 走"保守不清理"、看护走"不判死"分支 | **前提证伪 + 改写**（精度没问题，异构形状才是问题 → P1′-4） |
| **P2-4** | `executor_auction` 已实现但未实战 | 成立：仓内只有 R87 实现轮记录，无跨执行器竞标实测数据。另：live properties 只有 `need/bid`（没有 `namespace`），二期要跑就得先定它按哪个 ns 的注册表出价 | **仍缺**（中期） |

---

## 3. 本轮新报（不在两份文档里，是复测时撞出来的）

- **BUG-119（已入账，OPEN，high）**——心跳**跨进程不可见** + 无心跳行时 `timeout_sec` 不生效。两进程实测：进程 1 `claim` 后 `heartbeat{task_id,signal}` 回执 `last_seen=2026-09-29T03:28:40Z`，进程退出；sqlite 只读确认该行确实落库；**同一库**再起进程 2 调 `heal(namespace=…, timeout_sec=3600)` → `healed=["T0"]`，`watchdog_tick` 的 `active_tasks` 里这一格 `last_seen` 读回**空串**。叠加 `ops_heal.mbt:87` 的 `None => true // 从未心跳过 -> 视为 no_signal`，后果是无人值守（cron 每拍都是新进程）**每拍把上一拍还在干活的在途任务判死并重派**，而新认领还没发心跳的单也一样首拍即死。它是 P1-5（自动拉起执行器）的硬前置，不是并列项。
- **N-1 未声明键静默吞（规模已实测）**：48.1% 的历史调用带未声明键、`now` 命中 2167 次而调用方毫无感知。仓内 `check_doc_surface.py` 的 J8 只比对模板里的顶层参数名，运行时不校验——所以"驱动以为盖了时间/以为传了过滤条件"这一类**假绿**没有常驻判据。修法不该是"立刻拒"（会把现有 48% 的调用形状当场打红），第一步应是**回执里点名被忽略的键**（`ignored_keys`），可见之后再谈拒。
- **N-2 `serve` 往协议 stdout 打横幅**（BUG-76 的未收面，本轮活体复现）。修法二选一：横幅改 stderr，或默认不带、`--banner` 显式开。验收判据要打在"首行必须 `json.loads` 得动"这一条上，而不是打文案。
- **N-3 `loop_create` 是 now 政策的唯一活口**（读 args 的 `now` 并写进 `created_at`，schema 不 advertise，描述却说时间戳由服务端盖章）。要么删掉这个读取（走测试替身通道），要么显式 advertise 成测试专用入参——现在这样是**文档与实现相反**。
- **N-4 AGENTS.md 的参数列不在任何判据的扫描面上**（本轮已按活体 schema 修好那 6 行，见 §7；这条留着的价值是**缺口本身还在**）：修前 `AGENTS.md` 的 Omega 三件套（`omega_spec_create`/`omega_spec_review`/`omega_result_verify`）的"关键参数"列写着 `now`，而这三者的 live properties 分别是 `[author,content,max_rounds,task_id]` / `[max_rounds,reason,reviewer,task_id,verdict]` / 同前，源码里也没有 `get_str(args,"now")` ⇒ 文档广告了一个实现不读、传了会被静默吞的参数。没人抓到它的原因很具体：`check_tools_sync` 判据 5 只禁 server.mbt 里广告 `"now": string_prop`，J2 只比工具名覆盖，J8 只比 `templates/*.md` 的调用参数——**AGENTS 表格那一列谁都不管**。修法便宜：把 J8 的比对面扩到 AGENTS 参数列（反解第三列的标识符逐个 ∈ 该工具 properties，并查 required 是否被漏写），配一格反向对照（把某个参数换成不存在的键必须红）。

**取数跑在哪棵树上（并发工作区纪律）**：本轮三条结论各有各的面，不许混读——
- **调用面**：`_build/js/debug/build/cmd/cli/cli.js`（09-29 00:29 构建）＋ 起真进程打 JSON-RPC；这个产物里含别的车道未提交的改动，所以"回执长什么样"只对那一次运行负责。
- **源码锚点**：一律 `git show HEAD:<file>` 取（HEAD = `3d27271`），不引用工作区行号当准；因此 §2/§3 里的行号都注了 HEAD 口径。
- **库面**：只读打开仓库根 `fist-mbt.db`（`mode=ro`），写全部落 `temp/probe-*.db` 隔离库；仓库根那一行都没动。
- 顺带一条**清单级观察**（不属本轮、不代改）：`scripts/check_scripts_index.py` 现在红在 `gen_help_docs.py` 未登记，而 `scripts/gen_help_docs.py`、`cmd/cli/help_topics.mbt`、`__cli_pkg.mbt.tmp` 都还是未跟踪状态 ⇒ 另一条车道的在制品；我只报这一格，不替它收尾。

---

## 4. 修正后的优先级

### P0′ — 本地可闭环，且是后面所有事的前置

1. **修 BUG-119 的第一格：成对常驻判据先行**。判据形状照 §3 的三臂（A 无心跳 / B 有心跳 / C 已暂停），**A 与 B 必须在同一夹具里**，并补第四臂「心跳写在上一进程」。默认语义建议：`None` 分支不再是"即死"，而是按 `created_at` 起算给宽限期（与 `timeout_sec` 同一个闸），已暂停继续不动。
   **验收**：四臂常驻测试全绿；且在 `git archive HEAD` 的旧码树上至少 1 臂红（证明锁承重）；`watchdog_tick(namespace=…)` 不再把刚认领的单列进 `healed_tasks`。
2. **心跳跨进程的根因定位**（JS sqlite SELECT 取值形状 / 心跳读写不同源），产出写进 BUG-119 的 `### FIXED` 小记。
3. **时钟入参归一（N-3 + N-4 一起做，两半都是"文档与实现相反"）**：① 关掉 `loop_create` 对未 advertise 的 `now` 的读取（走测试替身通道，或显式做成测试专用入参并写进 schema）；② 删掉 AGENTS Omega 三件套参数列里的 `now`（**本轮已删**，同批还修了 `omega_verify`/`omega_verify_fix` 两行的入参与描述）；③ 把 J8 的比对面从 `templates/*.md` 扩到 AGENTS 的参数列，配"改成不存在的键必须红"的反向对照。
   **验收**：全仓 `get_str(args, "now"` 命中数 = 0（HEAD 实测 = 1 处，在 `loop_create` 分支）；AGENTS 参数列反解出的标识符全部 ∈ 对应工具 properties；`check_tools_sync.py` 判据 5 之外新增这一格计数（它现在只禁"广告"，看不见"未广告却读取"，也看不见文档表格里的参数列）。

### P1′ — 结构性改进（终审后第一批）

4. **N-1 未声明键可见化**：包装层比对 `args` 键集 ⊆ `inputSchema.properties`，把被丢弃的键回进 `result.ignored_keys`（含被丢弃时的工具名）；等一轮观察之后再谈"改拒"。
   **验收**：带 `now` 的 `publish_parallel` 回执里出现 `ignored_keys:["now"]`；`scripts/mcp_tool_tour.py` 加一格"传未声明键必须能在回执里看见"（成对：干净输入不得出现该字段）。
5. **N-2 stdout 纯度** + 首行判据。
6. **P1-2 幂等防重**：`publish_parallel` 支持 `idempotency_key`（或复用 `[review:file:idx]` 那套内嵌标记，`server.mbt:2676` 已有先例）；同 key 重发返回同一 `task_id` 且 `created=false`。顺带清 `auto-route-20260927` 的 18 条重复单（处置见 §5-D4）。
7. **P2-3 改写后的时间戳形状治理**：写面形状归一（含 `heartbeats.last_seen` 的 9/12 脏行）；读面 `iso_to_secs` 要么显式处理偏移、要么拒收非 `Z` 形状并回错误，不许按字面数字当 UTC 读；再加一条库面普查判据，口径用**棘轮**（非规范形状计数只许下降，涨了即红；清历史脏行另立一次性迁移单，须先备份）。
8. **P1-5 执行器任务绑定**：`executor_run` 加可选 `task_id`，绑定后自动 `execute` 记交付、`submit` 回提，失败走 `saga_register`。**排在 P0′-1/2 之后**——跨进程心跳不修，自动拉起等于每把自己派出去的执行器判死一次。

### P2′ — 中期

9. **积压年龄 / 周报视角**（P2-2）：排在第 7 条之后，否则年龄是假数。
10. **工具数治理**（P2-1）：先量化边际成本（新增一个工具要改几处现状面、跑几个守卫），再决定哪些转插件态；不为了数字好看先动。
11. **竞标二期**（P2-4）：先补 `executor_auction` 的 namespace 语义，再跑三执行器。

---

## 5. 需要裁决的（执行权不在我这边）

- **D1 分发线公网复验**：本机对 `github.com/.../releases/download/...` 三次全 000，而 raw 线 200——同一条链不同形状，说明是链路侧对某个主机的处理问题。要么换环境复跑 `scripts/blackbox/e2e_irm_line.py`（BUG-116 的收口条件），要么接受"镜像 e2e + 本机文档线"作为可达性证据、把公网那一格标为"未证"。**不为了关单而关单。**
- **D2 `now` 的兼容期策略**：只 advertise 到错误信息（建议书方案③），还是连未声明键一起拒（N-1 的强版）？48.1% 这个命中率意味着强拒会当场打红所有旧驱动。
- **D3 18 条重复单的处置**：`archive` 还是 `delete`？（`delete` 是引擎级不可逆；按本项目纪律我只出方案。）
- **D4 账本要不要加 `CLOSED` 词汇**：现闭集是 OPEN/FIXED/DUPLICATE/FALSE_POSITIVE，加词要同时动 `gen_plugins` 的硬门文法与 J 系列判据，属新轨道决策，不是补一个 API。
- **D5 两份文档的编号互指不一致**：实验报告把"now 纪律"叫 P0-3、把"pause 复活"叫 P1-3，建议书里 P0-3 是 README 安装线、P0-2 才是 now 纪律。建议给建议书加一段「复核注记」并把编号冻结到本文件的表名上，避免第三份文档再来一次漂移。

---

## 6. 复现命令（本轮用的，都可重放）

```bash
# 1) 交互长驻 + list 过滤 + 盖章对表 + pause/heal 三臂（隔离库，不动仓库根 fist-mbt.db）
python temp/plan_probe_p1.py     # tools/list 往返耗时、publish/list/get、pause→heal、now vs UTC
python temp/plan_probe_p4.py     # 两个 ns 各种一单：list() 全库 vs list(ns) 过滤 + 时间戳普查
python temp/plan_probe_p5.py     # 三臂成对：A 无心跳 / B 有心跳 / C 已暂停（读 healed 点名清单，不比状态字面）
python temp/plan_probe_p6.py     # 两进程心跳可见性（BUG-119 的复现臂）

# 2) 未知键命中率（tools/list 真 properties × call_log.params_json 顶层键）
python temp/plan_probe_p3.py

# 3) 活体 schema 点名（判断"这个工具到底读不读某键"）
node _build/js/debug/build/cmd/cli/cli.js serve   # params 必须带 _meta.protocolVersion，否则 -32602

# 4) 库面普查（只读）
python -c "import sqlite3,re;c=sqlite3.connect('file:fist-mbt.db?mode=ro',uri=True);p=re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');r=list(c.execute('select created_at,updated_at from tasks'));print(len(r),sum(1 for a,b in r if not(p.match(str(a)) and p.match(str(b)))))"

# 5) 账本计数（从抬头反解，不手加）
grep -E '^## BUG-[0-9]+ ' memory/bugs.md | awk '{print $NF}' | sort | uniq -c
```

`temp/` 是 gitignore 的临时区：这些探针是**本轮取证件**，不是交付件。要常驻的三条（三臂看护判据、未声明键可见化、时间戳形状普查）在 P0′/P1′ 里各自点名了落点，落进 `src/**` 常驻测试或 `scripts/check_*.py` 之后才算进仓库。

```bash
# 6) 文档参数列 ↔ 活体 schema 对表（P0′-3③ 那条判据的原型）
python temp/plan_probe_p7.py     # 只扫 AGENTS 的三列工具表
python temp/plan_probe_p8.py     # 扫 git 跟踪的全部现状 .md（104 份 / 97 行参数列 / 74 个工具）
```

---

## 7. 本轮已经落地的修正（不是计划项，是已改完并跑过守卫的）

复核时打到调用面就顺手改掉的两格——同一形状：**文档点的参数，实现根本不读**（比"文档少写"更坏，因为调用方以为生效了）。

| 面 | 改动 | 依据（实测，非引用） |
|---|---|---|
| `AGENTS.md` Omega 表 6 行 | ① 三行删掉 `now`；② `omega_verify` / `omega_verify_fix` 两行按真 schema 改写：入参是 `specs`(JSON 数组，每项 `{file_name, content}`) 与 `max_rounds`，**不是** `task_id/判定/reason`；③ 描述随之改成"批量验证 spec JSON（schema + fingerprint 校验，accuracy < 100% 一票否决）"并明写「不是按 task_id 走的总入口」 | 活体 `tools/list`：`omega_spec_create props=[author,content,max_rounds,task_id]`、`omega_spec_review`/`omega_result_verify` `props=[max_rounds,reason,reviewer,task_id,verdict]`、`omega_verify props=[specs]`、`omega_verify_fix props=[max_rounds,specs]`；`git show HEAD:src/server/server.mbt` 里这几处也没有 `get_str(args,"now")` |
| `USAGE.md` 36 处 `now` + 2 处工具总数 | 参数列里 `now(选)` / 裸 `now` / `, now` 共 36 处摘净（含两个 JSON 调用示例里的 `"now":"…"`，摘键时连前一行遗留的逗号一起摘，示例仍可解析：改前改后都是 13 块可解析 / 0 坏块）；§5 与结尾各一处「87 个工具」改成 `tools/list` 实测的「**129 个 MCP 工具**」——刻意写成带 `MCP` 的形状，好让 `check_tools_sync.py` 的 `RE_TOOL_CLAIM` 数得着，往后漂了会自己红。§7 那条「补充实测：`tools/list` 返回 87 个工具」是**那一次实跑的截面记录，没改数**，只加限定语指向 §6 标题 | USAGE.md:164 自称「参数表取自本机 `tools/list` 返回的真实 Schema」，而活体 schema 里 0 个工具带 `now`；摘前 `\bnow\b` 命中 36、摘后 0（逐类命中数与预算逐格相等才落盘） |
| `plugins/**`（9 个生成文件） | BUG-119 入账导致账本投影行漂移 ⇒ 按 cl7 给的处置跑 `python scripts/gen_plugins.py` 重投影 | 逐文件 diff 只有那一行：`BUG-1~118 共 117 条入账：2 条待修` → `BUG-1~119 共 118 条入账：3 条待修`；复跑 `check_plugin_sync.py` = `PASS 插件态一致：4 宿主 / 56 个生成文件 / 129 工具 / v0.3.4` |

守卫复跑（本机）：`check_tools_sync` 0 / `check_doc_surface` 0 / `check_plugin_sync` 0。
另有两格红**不是本轮造成的**，也不归本轮处置，只登记：`check_scripts_index` 红在 `scripts/gen_help_docs.py` 未登记（它与 `cmd/cli/help_topics.mbt`、`__cli_pkg.mbt.tmp` 都还是未跟踪状态）；`cleanup_artifacts.py --check` 报 77 个根 `.db` + 366 个 `temp/` 文件（CI 那一步是先删再查；本机我没跑删除——**别人的在制品我不删**）。

还有一格属**别车道已记未修**，我只做存在性确认、不并入本轮改动：`plugins/source/references/omega-verification.md:33/60/65/68` 与 `storage.md:64` 仍写 `omega_specs` / `gate_records`，而实测 `sqlite_master` 没有这两张表（真名 `specs`；`run_check` 判定按 `spec_type='check'` 落 `specs`，`runs` 表存在但整量 0 行）。`memory/2026-09-29.md` 里"下一次投影仍会把假表名带出去"这句已被本轮的重新生成验证——投影确实又带出去了。**修法与判据归那条线，本计划把它排进 P1′。**

顺带把"摘文档里的假参数"这件事的**噪声形状**量清楚了（给 P0′-3③ 那条判据用，不写明白下一轮一定照抄踩坑）：粗暴地拿"参数列标识符 ⊆ properties"比对，104 份现状 .md / 97 行参数列报出 14 处，其中只有 6 处是真违例（全是指纹相同的 `now`），另 8 处是**取值枚举与散文**被当成参数名——`tx_contract` 的 `action` 取值（claim/execute/pause/…）、`eval_feedback` 的四段名（Acceptance/Evidence/Fix）、`selfdrive_append` 的 `kind` 取值（thinking/product/target/task）、`dag_publish` 的"JSON数组"、`issue_scan` 描述里的 `unwrap`、`report_bug` 描述里的 `bugs`。⇒ 判据必须带**形状约束**（只认"按逗号/空格分段的段首标识符 + 该工具确实有 properties + 排除括号内的取值枚举"），并把这 8 条钉成 `--selftest` 的"干净不误红"格，否则第一天上岗就把手册判红，守卫会被当噪音绕过。

---

*修正人：butler（2026-09-29）｜ 基线：master `3d27271` + 隔离库实测 ｜ 依据：建议书 12 条逐条复测 + 本轮新报 4 条 + 已落地修正 3 格 ｜ 每条独立可立项，P0′ 三条建议整批先行*
