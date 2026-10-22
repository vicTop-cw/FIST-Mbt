# R114 · 超级管家家族的多租户寻址收口（status / task_tree / kill_plan / task_upsert / reminder_tick）

## 结果摘要

- 基线：主线 `31945570`（交付时已叠 `803293c2`，上游那两格是 BUG-383 native 门探针改指现役后端，与本单无交集）。
  本单不开新功能，只把**超级管家 5 支工具的命名空间寻址**从「只打默认引擎」修成「按物理库路由 + 撞号拒绝猜库」。
- 病灶（全开关自我迭代里真跑出来的，不是读代码猜的）：
  - `supervisor_status` 对 `ghostA` 恒报 `total=0` —— 别的租户在全景里**隐形**，而 `AGENTS.md` 写着它是
    「human_steward 查看项目状态的唯一入口」。
  - `supervisor_task_tree` / `supervisor_kill_plan` 无法寻址非 default ns，失败形状与「任务不存在」**完全同形**
    ⇒ 多租户下派发链静默断头（管家以为没这个任务，其实任务在另一个库里跑着）。
  - `supervisor_task_upsert` 把 `ghostA` 的行**写进 `default.db`**、只给它盖一个 `ns=ghostA` 的列值：
    回执 `{"ok":true,"task_id":"T0","action":"created"}` 且 `isError=False`，`list` 按 ns 路由看不见它，
    `supervisor_status` 又按列值数到它 ⇒ **与 `publish`/`list` 脑裂**（同一份数据两种真相）。
  - `supervisor_reminder_tick` 文案写「一次全库提醒检查」，实际只查默认库 ⇒ 别的 ns 停几天也不响。
  - 非法 `namespace`（如 `bad name/x`）静默回落 default，读数看着正常、其实读的是别人的库。
- 交付（真源 `src/server/supervisor_tools.mbt`）：
  - 新增私有件 `supervisor_ns_engine` / `supervisor_ns_unavailable` / `supervisor_ns_candidates` /
    `supervisor_find_task_hits` / `supervisor_ambiguous_msg` / `supervisor_status_fold` /
    `supervisor_reminder_fold` / `supervisor_stamp`，走与 `engine_for_ns` **同一条物理路由**；
    ns 打不开 ⇒ 显式发红，**绝不静默回落 default**。
  - `supervisor_status` 跨库折加：`by_namespace` 取**物理库行数**（不是列值分组），
    `progress_pct` 由 `已完成+已归档 / total` 重算（**不做各库百分比求平均**），
    `active` 每条盖 `namespace`（取回它要点名哪个库），另附 `scope` 与 `namespaces_scanned`。
  - `supervisor_task_tree` / `supervisor_kill_plan` 收 `namespace`（可选）：不传按 `default → 其余已打开 ns` 寻址，
    命中 0 个 ⇒ 回执点名搜过哪些库（`task not found: TNOPE（已搜索命名空间 default, ghostA）`），不再与「不存在」混成一条。
  - **撞号先于评估**：同一 `task_id` 在多个 ns 都存在 ⇒ 直接发红要求点名，绝不按顺序取第一个。
    这一条专为 `kill_plan` 的 `apply_pause=true` 兜底：判定在门链之前，所以它不可能把别的租户的任务 pause 掉。
  - `supervisor_task_upsert` 的 `namespace` 从「列值盖章」升级为**决定物理落库位置**（修掉脑裂）。
  - `supervisor_reminder_tick` 真遍历 `default` + 所有已打开 ns；`reminder_count` 取拼接后实际条数（不累加各库自报数），
    `reminders` 每条盖物理库 `namespace`，与引擎自报的列值 `ns` 可对照，正好用来认出 R114 之前写歪的历史脏行。
  - 5 支工具描述逐条列出返回键（J9 返回契约棘轮口径），并把「同 id 多 ns 都存在时直接发红」写进描述。
- 测试：新增 5 条白盒锁（`supervisor_status_fold 跨库合并` / `supervisor_stamp 追加与覆盖` /
  `supervisor_reminder_fold 跨库拼接` / `supervisor_kill_g2_missing 只看 G2` / `supervisor_ambiguous_msg 点名命中的每个库`）。
- 文档面：`AGENTS.md`「超级管家专属工具」5 行重写；`docs/supervisor-prompt-upsert-skill.md` 补 §4/§5 的
  `namespace` 语义、返回键与三条已知边界（撞号不猜库 / 搜索面 = default + 已打开 ns / 引导面不按 ns 分库）；
  测试数自述 1379→1384 联动 9 份文档 33 处（含 README 徽章 URL）。

## 证据

### A. 修复前（同支探针在修前代码上的实测 + 机理定位）

| 现象 | 读数/机理 |
|---|---|
| `ghostA` 在全景里隐形 | `supervisor_status(namespace="ghostA")` → `total=0`，而该库里确有 4 行 |
| 树取不到、且失败与「不存在」同形 | `supervisor_task_tree("T0")` → `{"code":-32000,"message":"task not found: T0"}`（T0 在 ghostA 里存在） |
| kill 门链 G2 恒假 | `supervisor_kill_plan` 对 ghostA 子任务 → `G2_exists=False` ⇒ `verdict=blocked`（真病灶是寻址，不是门） |
| 写进别的库、回执却说 ok | `supervisor_task_upsert(namespace="ghostA")` → `{"ok":true,"task_id":"T0","action":"created"}`、`isError=False`；`list(namespace="default")` 按 ns 路由看不见，`default.db` 里躺着那行 |
| 非法 ns 静默回落 | `namespace="bad name/x"` 不报错，读数来自默认库（`MultiStore::get` 返回 None ⇒ 旧 handler 无判断） |
| 提醒只响默认库 | `supervisor_reminder_tick` handler 单点 `engine`，非 default ns 的停滞任务永不入 `reminders` |

机理根因两处，均可复核：`src/server/server.mbt:51-60`（`engine_for_ns` 在 `mstore.get` 返回 None 时**静默回落默认引擎**）
与 `src/store/multi_store.mbt:105-127`（`ns_list()` 只列**已打开句柄**，磁盘上的 `.db` 不在搜索面）。
`engine_for_ns` 的静默回落本单**不改**（55 处调用面，改动面需另立一单），但超级管家这一族已不再继承它的回落语义。

### B. 修复后（合并 `803293c2` 之后重跑，判据：仓外 `~/fist_r114_ns_routing_verify.py`）

| 项 | 命令 | 读数 |
|---|---|---|
| 编译门 | `moon check --target js` | `508 warnings, 0 errors`（与基线同数，未新增告警） |
| 全量测试 | `moon test --target js` | `Total tests: 1384, passed: 1384, failed: 0` |
| 实测探针 | `python ~/fist_r114_ns_routing_verify.py` | **20 格 / 失败 0**，读数落盘 `%TEMP%\fist_r114_verify.json` |
| A 跨 ns 寻址 | 同上 | `supervisor_status` 全库聚合 → `{"total":4,"by_namespace":{"default":0,"ghostA":4},"active_count":1}`，`active` 每条带 `namespace="ghostA"` |
| B 门链形状 | 同上 | 根任务 `verdict=blocked` 且 `G2_exists=True, G3=False`；ghostA 子任务 `verdict=allowed ns=ghostA steps=3` |
| B 撞号不落地 | 同上 | `apply_pause=true` 撞号时 ghostA/T0 状态 `拆分中 -> 拆分中`（未被误 pause） |
| C 未命中点名 | 同上 | `kill_plan("TNOPE")` → `namespaces_scanned=["default","ghostA"]` + `ns_hint`；`task_tree` → `task not found: TNOPE（已搜索命名空间 default, ghostA）` |
| D 库级落点 | 同上 | `upsert(ns=ghostB)` → `ghostB=1 ids=['T0']`；默认库 `before=0 after=0`；沙箱物理文件 `['ghostA.db','ghostB.db']` 对得上 |
| A 撞号拒绝猜库 | 同上 | `{"code":-32000,"message":"task_id T0 在多个命名空间同时存在: [ghostA, ghostB] —— 请点名 namespace，超级管家不按顺序猜库"}`；点名 `ghostB` 可取回 |
| E 非法 ns | 同上 | `命名空间不可用: bad name/x（未打开或名称非法）—— 超级管家不静默回落默认库，请先用 store_open 打开该 ns`；默认库行数 0（没被塞行） |
| F 提醒跨库 | 同上 | `reminder_count=5 ns=['ghostA','ghostB']`；点名 `ghostB` 时 `scanned=['ghostB']` |
| G 进度口径 | 同上 | `total=5 progress=0 期望=0.0`（由计数重算，不是各库百分比平均） |
| H 契约面 | 同上 | `tree/kill/reminder` 三面 schema 都带 `namespace`；`force`/`apply_pause` 仍是 `boolean`（不收字符串） |
| 文档测试数对表 | `python scripts/check_test_sync.py <moon test 日志>` | rc=0 `PASS 测试总数单一真源一致：实测 1384；扫描现状面 136 份文档，19 条声明全部等于实测；must-carry 5 份齐全；豁免 22 条全部有效` |
| 徽章对表 | `python scripts/check_badge.py <moon test 日志> README.md` | rc=0 `PASS 徽章一致：README tests-1384%2F1384 == 实测 1384/1384` |
| 工具数对表 | `python scripts/check_tools_sync.py` | rc=0 `PASS 工具单一真源一致：server.mbt 注册 170 个，AGENTS/README/deliverable/scoring_rubric 对齐` |
| 全量电池 | `python scripts/run_guards.py` | 见「遗留风险」第 1 条：合并后首跑 `58 格 / 失败 1 / SKIP 5`，唯一失败是本单**尚未 push** 的自证格；push 后复跑读数见「来源」末行 |

## 资源消耗

- 会话轮次：续跑会话内单个交付单元；无外部模型调用费用（本地构建 + 探针 + 守卫）。
- 计算：`moon check` ~20s；`moon test --target js` ~35s；电池全量约数分钟（58 格）；探针 20 格 <1 分钟（起一个沙箱 server，DB 全部针到 `%TEMP%\fist-r114-sandbox`，不污染仓库根 `fist-mbt.db`）。

## 任务分配记录

- 无子代理分派。按金条一：本单是「单文件真源 + 同包白盒锁 + 文档面联动」的中任务，且需要**实跑才能定案**
  （读代码只能看出「只打默认引擎」，看不出撞号会误 pause），自己执行并自验。
- 设计被实测改写的地方（记下来防「读代码自嗨」）：探针最初按「不点名时取第一个命中的库」实现，
  真跑 `A ghostB 新行可寻址` 那格 FAIL —— ghostA 也有一行 `T0`，于是取到的是 ghostA 的树。
  这一格把寻址语义从「first-hit」逼成「hits-based + 撞号拒绝」，并把 `apply_pause` 的撞号判定提到门链之前。
  修完后该格改写为三格（撞号拒绝 / 点名可取回 / 撞号不落地 pause）。

## 遗留风险

1. **电池那一格红是本单自己的未交付状态**：`check_delivery_gap.py got=1 expect=0`，读数为
   `HEAD f0cb6939 ahead=2 files=13 pushed=False ✗ 未交付`。push 之后该格自动归零 —— 本单不含「绕过它」的改动，
   交付后读数见「来源」末行。
2. **`engine_for_ns` 的静默回落仍在**（`src/server/server.mbt:51-60`，55 处调用面）：非管家族的工具里，
   打不开的 ns 仍可能读到默认库。本单只把超级管家 5 支工具与这条回落语义解耦；全仓收口需另立一单，
   否则一刀切会让 55 个调用点同时改判，超出「增量零回归」。
3. **搜索面 = `default` + 已打开的 ns**：磁盘上存在但本轮没 `store_open` 过的库，不点名就搜不到。
   回执的 `namespaces_scanned` 是用来区分「没数据」与「没开库」的唯一凭据，已在文档写明。
4. **历史脏行仍在库里**：R114 之前 `task_upsert` 写歪的行（列值 `ns` 与物理库不一致）不会被本单搬迁。
   识别面已给出（`reminders` 每条同时带物理库 `namespace` 与列值 `ns`）；搬迁脚本需 owner 点名才做。
5. **`iso_to_epoch` 的 Int32 上限**：探针最初用 `now="2099-…"` 造超时，`ts_ok` 恒假导致提醒格 0 条。
   本单绕开（用 2035），但「2099 年以后的时间戳静默算成 0」是引擎侧真缺陷，另立一单。
6. **本轮撞到的另一支缺陷（不在本单范围，但已实测）**：`scripts/whisperer.py --fast` 把自己**落后**主线报成
   「本地 HEAD 与远端 main 不一致（篡改）」，处方写 `git reset --hard 803293c`；
   而 `git merge-base --is-ancestor HEAD 803293c2` = yes（零分叉、零篡改）。full 模式会真的 reset，
   在带未提交工作的 worktree 上等于删工作 —— 与金条四「不可逆只给方案」冲突。下一单修判据（落后 ≠ 篡改）与处方（只报不改）。

## 后续建议

1. 把「撞号拒绝猜库」上升为多租户寻址的**通用律**：`get` / `pause` / `resume` / `archive` 等按 `task_id` 寻址的工具同样有 this 形状，
   可复用 `supervisor_find_task_hits` 的思路（先数命中再决定，不 first-hit）。
2. 补一支尺 `scripts/check_disguised_bool_flag.py`：扫「schema 声明 boolean 但 handler 用字符串比较取真」的幻影布尔参数
   （R110 的 `include_consumed` 是这一族的第一个样本，本单撞号那格说明这族还有第二形态：参数 advertised 但 handler 不用）。
3. `supervisor_prompt_list` / `consume` 目前不按 ns 过滤（进程内 registry 是进程级），
   与本轮写进文档的「引导面不按 ns 分库」一致；若要真分库，需要给引导表落物理库，属于功能新增，不在收口单里顺手做。
4. 文档面 `docs/supervisor-prompt-upsert-skill.md` 现在同时讲参数语义与返回键，建议把返回键并入 `J9` 的
   契约清单机器对表（当前靠描述文本自述，尺子只比工具数）。

## 超额内容

- 顺手把电池里 `check_backlog_status_staleness.py` 那格从「登记红」转回「门禁格」：主线 `60558289` 已把 9 条状态落差
  逐条清零、`STALE_CEILING` 4→0，登记依据已不存在。按 `run_guards.py` 自订的律「被检内容修好 ⇒ 把期望改回 0」处理，
  尺未削弱（`--selftest` 11 格照旧全过；上限 0 ⇒ 新增一条落差就红）。
- 探针文件与沙箱名从 `r111` 改为 `r114`（主线已消费 R111/R112/R113，且已合入我上一单的 R110 标签）。
- 仓外判据脚本、沙箱 DB 均在 `%TEMP%`，未向仓库写入任何探针产物。

## 来源

- 真源与测试：`src/server/supervisor_tools.mbt`、`src/server/supervisor_tools_wbtest.mbt`、
  `src/engine/engine_supervisor.mbt`（`supervisor_status` / `supervisor_task_tree` / `supervisor_kill_plan` /
  `supervisor_reminder_tick` / `iso_to_epoch`，本单未改引擎侧）、`src/store/multi_store.mbt`、`src/server/server.mbt`。
- 文档：`AGENTS.md`「超级管家专属工具」段、`docs/supervisor-prompt-upsert-skill.md`、
  `ARCHITECTURE.md`、`README.md` / `README.mbt.md` / `README_EN.md`、`docs/SOP.md`、`docs/agent-map.md`、
  `docs/deliverable.md`、`scripts/scoring_rubric.md`。
- 判据：`~/fist_r114_ns_routing_verify.py`（20 格，读数 `%TEMP%\fist_r114_verify.json`）、
  `scripts/run_guards.py`（58 格）、`scripts/check_test_sync.py`、`scripts/check_tools_sync.py`、
  `scripts/whisperer.py --fast`（本轮读数见「遗留风险」第 6 条）。
- 上一单同族：R110 的 `include_consumed` 幻影布尔（已合入主线），本单在其 handler 上叠跨库折加，零回归。
- 预存红（非本单引入，逐条点名 rc 与成因）：
  `check_ci_step_position.py` rc=1（棘轮超限 35 > 34，升档是人的决定）；
  `check_ci_step_position.py --selftest` rc=2（T9 真源现状 rc=1 不在上限内，同一根因）；
  `blackbox/check_merge_markers.py` rc=1（跟踪面存在 1 处冲突标记；本单文件 `git grep "^<<<<<<< "` 无命中）；
  `check_scripts_naming.py` rc=1（命名判定面 2 条 > 棘轮上限，只许下降）。
  四格在电池里均以 `exp=1/exp=2` 登记，不计入失败。
