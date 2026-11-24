# R38 唤醒巡检报告（2026-11-24）

## 一、结果摘要

**本轮为非阻塞根因调查轮**：`src/**` 与 `scripts/run_guards.py` 仍被并发 WIP 占用（见 §二），按标准动作第 3 条走非阻塞路径，选定账本中唯一新鲜 OPEN 且明写「根因待查」的 **BUG-650** 做根因定位。

**结论：BUG-650 根因已完整闭合，是本仓一处设计缺陷（自名碰撞缺口），不是「历史迁移期产物」。**

一句话根因：`migrate_legacy_store(legacy_dir, new_dir, ns)` 的「旧位置」算式是 `legacy_dir + "/" + ns + ".db"`；当 **`ns` 恰好等于主库文件的 basename**（`fist-mbt`）且 `legacy_dir="."`（server cwd = 仓库根）时，`legacy_path` 就是 **server 正在用的活主库 `./fist-mbt.db`** 本身 ⇒ 「旧库」与「新库父目录」指向同一个活库，迁移逻辑把主库整份复制成命名空间分库 `.fist-mbt/data/fist-mbt.db`，此后 `namespace=fist-mbt` 的读写全落在副本上，与主库分叉。

三条证据互相咬合（详细读数见 §三）：
1. **代码路径**：`src/store/multi_store.mbt:631-638` 的路径拼接 + `src/server/server.mbt:9876-9881` 的调用点（`migrate_legacy_store(".", ".fist-mbt/data", ns, force=force_migrate)`）；
2. **数据集合关系**：两库 `integrity_check` 均 ok、`journal_mode=wal`；主库 2450 tasks / 20,033,536 B，副本 2486 tasks / 17,862,656 B；**共有 id 逐字段比对 status / assignee / completed_by / description 差异全为 0**，仅 10 条 `updated_at` 不同 —— 这是「整份快照后各自分叉」的指纹，排除「两份独立累积」；
3. **触发点**：主库 `call_log` 里 `store_open(ns="fist-mbt")` 四次，其中 `2026-11-24T08:14:42Z` 那次紧跟在 `get(task_id=T0r770.1.1, namespace=fist-mbt)` 之后；`08:37:04Z` 的 `agent_acl_grant`/`pause`/`archive` 序列只进了副本（`T0r770.*` 家族 10 条 `updated_at=08:37:0xZ`）。

## 二、并发 WIP 面（本轮未碰）

`git -c core.quotepath=false status --short` = **75 行**（M 39 + D 4 + ?? 32），与 r37 快照相比**显著扩张**：

| 类别 | 代表项 |
|---|---|
| 生成投影面 | `plugins/{atomcode,claude,codearts,deepseek-harness}/**` 全套 SKILL/INSTALL/marketplace 均在改 |
| 守卫面 | `scripts/run_guards.py`、`scripts/README.md`、新增 `scripts/check_underscore_ignore.py`（未跟踪） |
| 源码面 | `src/server/wt_tools.mbt`、`src/server/pkg.generated.mbti`、`src/store/pkg.generated.mbti`、`src/engine/router` mbti、`src/store/store_sqlite_wbtest.mbt` |
| 文档面 | `AI-DEVELOPMENT-STANDARD.md`、`ARCHITECTURE.md`、`USAGE.md`、`docs/agent-map.md`、`docs/project-standards-skill.md`、`docs/proposal-process.md`、`cmd/cli/help_topics.mbt`、`templates/tool_use_rubric.md` |
| CI/发布 | `.github/workflows/release.yml`、`.dsh/fist-mbt-plugin/package.json` |

`memory/bugs.md` 相对 HEAD **clean**（`git diff --stat` 空），他方账本改动尚未落盘。

**禁区执行**：本轮零碰上述任何文件；两份库本体（`fist-mbt.db` / `.fist-mbt/data/fist-mbt.db`）全程只读（`mode=ro`），未做任何写动作。

## 三、查明细（可复现读数）

### 3.1 根因代码路径

`src/store/multi_store.mbt:631-638`：
```moonbit
pub fn migrate_legacy_store(legacy_dir, new_dir, ns, force~ = false) -> StoreMigration {
  let legacy_path = legacy_dir + "/" + ns + ".db"   // ← ns 直接拼进文件名
  let new_path    = new_dir    + "/" + ns + ".db"
```
现有守卫只有两条，都不覆盖本形态：
- `MultiStore::safe_ns(ns) is None` → `skipped("invalid-ns")`（`fist-mbt` 合法，字符集 `[A-Za-z0-9_-]` 放行）；
- `legacy_dir == new_dir` → `skipped("same-dir")`（本例 `"." != ".fist-mbt/data"`，拦不住）。

`src/server/server.mbt:9876-9881` 是唯一调用点，也是唯一能拿到「主库真实落点」的上下文：
```moonbit
migration = if mstore.ns_list().contains(ns) {
  @store.StoreMigration::skipped("already-open")
} else {
  @store.migrate_legacy_store(".", new_dir, ns, force=force_migrate)
}
```
注意 `already-open` 这道门**挡不住首次**：副本还不存在时 `ns_list()` 不含 `fist-mbt`，于是照搬。

主库句柄是模块级 `@store.SqliteStore::new()`（`server.mbt:29`），路径来自 `SqliteStore::default_db_path()` = `FIST_DB_PATH` 或硬默认 `fist-mbt.db`（`src/store/store_sqlite.mbt:514`、`:523-542`）。**`SqliteStore` 结构体不持有路径**（`:25-28` 只有 `db` / `closed`），所以「句柄级」碰撞判据需要补一个只读回显口（见 §四方案 A）。

对照 `BUG-649`（FIXED）：它在 `MultiStore::open/get`（`multi_store.mbt:95-97` / `:124-128`）对 `safe == "default"` 特判回主库，但**没有**任何「ns 与主库 basename 同名」的防呆 ⇒ 自名碰撞无人拦截。两者同族（default/主库语义分裂），本次是第二处缺口。

### 3.2 数据集合关系（分叉机制判定）

| 读数 | 主库 `fist-mbt.db` | 副本 `.fist-mbt/data/fist-mbt.db` |
|---|---|---|
| 字节数 | 20,033,536 | 17,862,656 |
| `integrity_check` | ok | ok |
| `journal_mode` | wal | wal |
| `tasks` 总数 | 2450 | 2486 |
| 其中 `ns='fist-mbt'` | **0** | **36** |
| `archive` | 21 | 21 |
| `task_events` | 0 | 11 |
| `max(created_at)` | 2026-10-27T06:46:48Z | 2026-11-24T02:56:50Z |

逐字段比对（共有 id）：`status` / `assignee` / `completed_by` / `description` **差异各 0**，`updated_at` 差异 10。
⇒ 副本不是「另一套累积」，而是**主库某时刻的整份拷贝 + 之后只进不出地写入**（写侧分叉、读侧从未回灌）。这与 BUG-650 条目里「今日清扫把副本 21 条 `[omega:required]` 置已暂停、10 条死副本归档」的操作记录一致。

`T0r770` 家族在副本中的状态：根任务 `T0r770` 仍「已领取」（`assignee=decomposer`，`created_by=human_steward`），10 个孙任务被 08:37 那批 `pause/archive` 改成「已暂停」；主库 `archive` 里搜 `T0r770` = **0** 命中 ⇒ 这批写确实只落在副本。

### 3.3 触发点（call_log 时序）

主库 `call_log`（44,154 行）中 `store_open(ns="fist-mbt")` 共 **4 次**：

| ts | scratch | 前后文 |
|---|---|---|
| 2026-10-17T10:40:30Z | false | — |
| 2026-10-30T15:31:20Z | （读数见下条） | — |
| 2026-11-24T08:14:42Z | — | 紧接 `get(T0r770.1.1, ns=fist-mbt)` |
| 2026-11-24T08:37:04Z | — | `agent_acl_grant(ns=fist-mbt)` ×2 → `pause`/`archive(T0r653..657)` |

08:14:42 那一发调用序（seq 1→3→4）：`get(ns=fist-mbt,T0r770.1.1)` → `store_open(ns=fist-mbt)` → `get(ns=fist-mbt,T0r770.1.1)`。即：**有人带 `namespace="fist-mbt"` 去取一个主库里的历史任务，第一次 `get` 因 ns 分库不存在而落空，触发 `store_open`，而 `store_open` 顺手把主库复制成了那个分库** —— 这就是缺陷的可用路径：任何客户端只要「ns 参数填成项目名」就会踩中。

⚠️ 网关 `result_json` 只落 `"ok"`（不落详情），所以 MCP 回执里看不到 `migration` 字段 —— 这也是该缺陷潜伏到今日才被发现的原因之一（诊断只能靠直查库）。

### 3.4 旁证：命名空间路由陷阱已有案底

`docs/ISSUE_NAMESPACE_ROUTING_TRAP.md`（2026-10-24，Pentad 统帅报）已记录「read/write 工具 namespace 不生效 ⇒ 任务凭空消失 / 写到无关库」，其根因段指 `get` / `claim` / `execute` / `verify` / `archive` 的 `namespace` 默认 `"default"` + 静默回退。本次是同一族陷阱的**下一层**：不是「默认值错」，而是「ns 合法但与主库同名 ⇒ 迁移把主库复制一份」。两份文档应互指（本轮未改该文档，属他方 WIP 面之外但非本轮范围）。

## 四、防线方案（只出方案，不落码 —— `src/**` 被占用）

按 systematic-debugging Phase 3/4 口径，给出**单一假设的最小验证**路径与候选修法，供 WIP 收口后的修复轮取用：

**假设**：只要在路径解析处拒绝「旧位置 == 主库真实文件」，分叉即不可能发生；其余行为（迁移语义、幂等、留档）全部不动。

**方案 A（推荐，最小侵入）**：给 `SqliteStore` 补一个只读路径回显口（如 `pub fn SqliteStore::db_path(self) -> String?`，构造时记下 `db_path`），然后在 `MultiStore` 增一个纯判定函数，例如
```moonbit
pub fn MultiStore::legacy_hits_main(main : SqliteStore?, legacy_path : String) -> Bool
```
在 `migrate_legacy_store` 入口（`safe_ns` 之后、任何文件动作之前）命中即返回 `StoreMigration::skipped_at("legacy-is-main", ...)`，并在 `note` 点名两条出路（① 换个 ns 名；② 若要迁主库请走显式备份流程，由人执行）。
判据建议：`store_migration_reason` 加一档 reason（如 `legacy-is-main`，闭集 + `store_migration_applies` 必须为假），白盒锁钉住「主库同名时 `applied=false` 且不产生 `.fist-mbt/data/<主库名>.db`」+ 一格**变异对照**（把守卫删掉必须红，且变异点落在代码不在注释 —— 判例-30 口径）。

**方案 B（更彻底，成本高）**：在 `store_open` 入口就把 `ns` 与主库 basename 比对，命中直接 `Err` 并自带出路文案（与既有「非法 namespace」/「非法 data_dir」两条拒绝文案同族风格）。缺点：`ns` 名是客户端传的，拒绝会打断既有调用方（r37 已实测有 `ns=fist-mbt` 的真实调用）；需 owner 裁「兼容 vs 硬拒」。

**共同前提**：A/B 都需要「主库真实落点」可读。当前 `SqliteStore` 不存路径，A 需要新增只读字段，B 可以在 `server.mbt` 用 `SqliteStore::default_db_path()` 现场比较（但 env 可被改，需确认 server 进程内 cwd/env 一致性）。

**数据合并 / 副本退役**：仍**不做自动迁移**，需 owner 决策（BUG-650 条目已如此约束）。本轮只提供判据：两库 `status/description` 全同、仅 `updated_at` 10 条分叉 ⇒ 合并风险面是「副本多出的 36 条 `ns=fist-mbt` 行 + 11 条 `task_events`」，主库缺失这部分状态推进。

## 五、不改码边界与遗留风险

- **`src/**` 与 `scripts/run_guards.py` 仍占用** ⇒ 本轮零改码，Round C 队列（BUG-527/530/check_usage_tool_count）**不重活**（记忆载明 r385 已全消）。
- **账本未改**：BUG-650 仍为 `[medium] OPEN`，**本报告的根因结论尚未写进 `memory/bugs.md`** —— 原因是账本计数面属提交门禁面（改 `bugs.md` 须同批跑 `python scripts/gen_plugins.py`，而 `plugins/**` 正被他方 WIP 全面改写，此时重投影会与他方落盘撞车）。⇒ **这是本轮已知记账缺口**，已列入 §六后续建议；建议在他方 plugins WIP 收口后由专门一轮补「BUG-650 追记（根因段 + 防线方案 + 计数面重投影）」同批提交。
- **待落账新号**：若修复轮认为需要独立编号，用 **≥651**（现最大 650，避免与 vq 外来账撞号 —— BUG-636 先例）。本轮不新立号。
- 两份库本体全程只读，未触碰。

## 六、FIST 闭环

- ns=`wakeup-patrol`，`publish`（human_steward 特权路径）→ `agent_acl_grant(agent_id=commander-atomcode, can_write=true)` → `claim` → `execute` → `submit` → `verify`。
- publish 成功绝不重发；TID 提取用 `temp/fist_r28_tid.py`（r318 稳健口径，notice 行免疫）。
- ⚠️ 本轮首格探活 `python scripts/fist.py call health_check` 在 25s 内无输出（首次 spawn 冷启动/或节点占用），已在链脚本步骤中带完整日志重试；若最终仍不可用，按「报账留痕 + 下轮补步」处理，不冒名报绿。

## 七、资源消耗与来源

- **资源**：根因调查 ~15 次定向读取/查询，无长构建、无 `moon test`（本轮零改码 ⇒ 无编译面可验，符合 VERIFY 跳过条件）。
- **来源**：本报告全部读数为**本机现读**（2026-11-24）：`sqlite3 mode=ro` 直查两库 + `grep`/`read_file` 源码；代码行号对应工作树当前版本（`multi_store.mbt` 31,578 B / 11-24 16:53；`server.mbt` 585,913 B / 11-24 16:53）。
- **任务分配**：本轮为单 agent 非阻塞调查（轻任务直派子代理口径不适配 —— 调查需要连续上下文与判断，拆给子代理会丢证据链）；终审由统帅本人完成。
- **超额内容**：§3.4 的互指建议与 §3.3 的「回执不落 migration 字段」归因属本轮附加发现，未落码。

## 八、后续建议（下一轮）

1. **补 BUG-650 账本追记**（根因 + 防线方案 + 计数面 `gen_plugins.py` 同批重投影），等 `plugins/**` WIP 收口。
2. **修复轮**（src 解禁后）：按 §四方案 A 落地 + 白盒锁（含变异对照），验收＝`moon test --target js src/store` + `src/server` 全绿。
3. **数据合并**：待 owner 裁定后单独出方案（不可逆，先出方案后执行）。
4. 下一轮唤醒若 src 仍占用，继续非阻塞巡检（候选：`check_host_installable` / OFM 端点探活 / BUG-636 接线半复核）。
