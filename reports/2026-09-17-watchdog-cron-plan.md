# FIST-Mbt 定时任务看门狗（watchdog_tick）功能计划

> 状态：待实现（供实现 agent 执行）
> 日期：2026-09-17
> 前置阅读：`README.md`（36 工具 + 九态状态机）、`src/ops/ops_heartbeat.mbt`、`src/ops/ops_heal.mbt`

---

## 0. 适用范围声明（重要，必须先读）

**本计划新增的功能，推荐仅用于「定时任务 / 无人值守自动化」场景，不用于人工指挥官任务分配流程。**

理由：看门狗的核心行为是「心跳超时 → 自动回滚重派」「上一轮完成 → 自动起下一轮」。这两点在无人值守的 cron 自动化里是正确且必要的（任务跑挂了必须能自愈续跑），但**在人工指挥流程里是有害的**——人类指挥官需要自己判定「这个任务是真的挂了，还是执行者暂时离开／被阻塞」，不应由机器擅自回滚或自动派发新轮。

实现者在落地时，必须把「自动续轮 / 自动 heal」的触发控制在*定时任务命名空间*（namespace，建议如 `cron-auto`）内，并保证不影响 `default` 等人工命名空间的既有行为。任何会改变人工流程语义的行为（如默认命名空间自动派发）都视为越界。

---

## 1. 背景与目标

### 1.1 背景

兄弟项目 `lang-zone` 现有 2 个 cron 定时任务驱动任务流水线：
- `loop_prompt`：每小时用元提示词分析项目、生成任务提示词
- `action`：每小时执行最新任务提示词

二者都是 `0 */1 * * *` 整点触发，**互相不感知状态**，导致：
1. 整点并发撞车（撞「并发会话上限 3」报错）
2. 无衔接：上一任务没做完就盲堆新提示词；做完也不会立即触发下一波
3. 任务跑到一半挂掉（如 lib_hashmap 转正：代码改了、最后验证没跑），重启后上下文丢失无法续跑

### 1.2 目标

在 FIST-Mbt 中补一个**单入口看门狗编排工具 `watchdog_tick`**，由外部 cron 每 1 分钟调用一次，驱动「等待 / 重启 / 起新轮 / 跳过」的状态机闭环，从而取代 lang-zone 现有的两个对撞 cron，实现「任务完成后自动生成下一波」。

---

## 2. 现状盘点（已核对源码，务必以本文为准）

以下结论来自 2026-09-17 对 `FIST-Mbt` 源码的核对，实现 agent 可直接采信：

### 2.1 ✅ 已具备（无需重做）

- **心跳 SQLite 落库已实现**：
  - 表已建：`store_sqlite.mbt:61` `CREATE TABLE heartbeats (agent_id, task_id, last_seen, status, PRIMARY KEY(agent_id, task_id))`
  - CRUD 已实现：`store_sqlite.mbt:643 write_heartbeat`（UPSERT）、`:693 read_heartbeat`、`:728 delete_heartbeat`、`:760 list_all_heartbeats`
  - store 抽象层：`store.mbt:268-312` `StoreBackend::write_heartbeat / read_heartbeat / delete_heartbeat / list_all_heartbeats`
  - engine 委托层：`engine.mbt:209 store_write_heartbeat`、`:221 store_delete_heartbeat`、`:230 store_list_heartbeats`（返回 `Array[(agent_id, task_id, last_seen, status)]`）
- **心跳上报已落库**：`server.mbt:607-649` 的 `heartbeat` 工具已同时写内存表 `heartbeats.beat(...)` **和** `engine.store_write_heartbeat(...)`（第 630-637 行）。
- **时间戳比较工具**：`ops_ts.mbt:24 iso_to_secs(s) -> Int`（解析失败返回 -1）。
- **九态状态机**：`core_task.mbt`（待领取/已领取/拆分中/执行中/待验收/已完成/已打回/已暂停/已归档）。
- **回滚重派能力**：`engine.mbt:392 reopen_task`、`ops_heal.mbt` 的 `heal_stale_tasks`。

### 2.2 ❌ 关键缺陷（本计划要修的核心）

`heal_stale_tasks`（`ops_heal.mbt`）与 `Heartbeat::is_stale`（`ops_heartbeat.mbt:62`）**只读进程内内存 Map**，不读 SQLite。

后果：MCP 进程重启（cron 每次起新进程时必然发生）后内存心跳表清空，`is_stale` 对每个「执行中/已领取/拆分中」任务都返回「无心跳记录 → stale」，导致 **heal 把仍在正常执行的任务全部误判为挂了并回滚重派**。这直接废掉了跨进程看门狗的正确性。

### 2.3 ❌ 缺失能力（本计划要新增）

- 无「单入口编排 tick」：heartbeat / heal / verify / publish 是各自独立的手动工具，没有把「检测完成 → 起新轮」「检测超时 → 重启」串起来的入口。
- 无「上一轮完成 → 自动起下一轮」的联动。

---

## 3. 待实现功能清单（3 项，含依赖顺序）

| # | 功能 | 类型 | 依赖 | 优先级 |
|---|---|---|---|---|
| A | heal 心跳判定改为读 SQLite（跨进程修复） | 缺陷修复 | 无 | P0 必修 |
| B | 新增 `watchdog_tick` 编排工具 | 核心新增 | A | P0 |
| C | `watchdog_tick` 内嵌「完成 → 自动起下一轮」联动 | 增强 | B | P1 |

建议实现顺序：A → B → C，每步 `moon test` + `moon check` 验证。

---

## 4. 详细设计

### 4.1 功能 A：heal 读 SQLite（跨进程修复）

**目标**：让「心跳是否超时」的判定不再依赖进程内内存，改为读 SQLite，使 cron 每次起新进程也能正确判断「任务是否还在跑」。

**改动文件**：`src/ops/ops_heal.mbt`（核心）、`src/ops/ops_heartbeat.mbt`（可选：提供从库加载的辅助）、必要时 `src/engine/engine.mbt`（补 read 委托）。

**方案**：新增一个读库版判定，不破坏现有内存版（保留 `heal_stale_tasks` 原签名给人工流程用，新增长期存活版给 watchdog 用）：

```
// ops_heal.mbt 新增
pub fn heal_stale_tasks_from_store(
  engine : @engine.FistEngine,
  now : String,
  timeout_sec? : Int = 600,
) -> Result[Array[String], String]
```

逻辑（伪代码）：

```
1. let rows = engine.store_list_heartbeats()   // Array[(agent_id, task_id, last_seen, status)]
2. 按 task_id 建 Map[String, String]（last_seen 索引）
3. for t in engine.list_all():
     status = t.get_status().to_string()
     is_active = status in {"执行中", "已领取", "拆分中"}
     if not is_active: continue
     stale = match last_seen_map.get(t.get_id()):
       None    -> true          // 从未心跳过 → 视为 stale
       Some(ts)-> iso_to_secs(now) - iso_to_secs(ts) > timeout_sec
     if stale:
       engine.reopen_task(t.get_id(), now)   // 回滚为已领取
       ignore(engine.store_delete_heartbeat(task_id=t.get_id()))
       healed.push(t.get_id())
4. return Ok(healed)
```

**注意**：
- `iso_to_secs` 解析失败返回 -1：当 `iso_to_secs(now) < 0` 或 `iso_to_secs(ts) < 0` 时，保守返回**不 stale**（不误伤），与 `ops_heartbeat.mbt:62-82` 现有保守语义一致。
- 若 `engine` 未暴露单条 `read_heartbeat` 委托，直接复用 `store_list_heartbeats()` 建索引即可，无需动 engine（若想更高效，可在 `engine.mbt` 补 `store_read_heartbeat(task_id) -> (String,String,String)?` 委托，但非必需）。
- 现有 `heal` 工具（`server.mbt:651-680`）仍调用内存版 `heal_stale_tasks`，**保持不变**，避免影响人工流程；新逻辑由 `watchdog_tick`（功能 B）调用。

### 4.2 功能 B：新增 `watchdog_tick` 编排工具

**目标**：单次调用完成「扫描 → 判定 → 动作」的闭环，作为 cron 每 1 分钟的唯一入口。

**改动文件**：`src/server/server.mbt`（注册工具）、新增 `src/ops/ops_watchdog.mbt`（编排逻辑）、`src/ops/moon.pkg`（如需加依赖）。

**工具注册**（遵循 `server.mbt` 现有 `.tool(...)` 风格）：

```
.tool(
  "watchdog_tick",
  "定时任务看门狗编排单入口（推荐仅用于定时任务/无人值守场景）：扫描活跃任务，\
   心跳超时则回滚重派，检测到上一轮完成且提供了 next_description 时自动发布下一轮。\
   参数：now、timeout_sec、namespace(可选)、next_description(可选)、next_created_by(可选)。",
  schema({
    "now": string_prop("当前时间戳(默认内置)"),
    "timeout_sec": int_prop("心跳超时秒数(可选默认600)"),
    "namespace": string_prop("作用域命名空间(可选，默认仅扫描执行中任务，不限 ns)"),
    "next_description": string_prop("上一轮完成后的下一轮任务描述(可选，缺省则不自动续轮，仅返回信号)"),
    "next_created_by": string_prop("下一轮任务的创建者(可选，默认 watchdog)"),
  }, []),
  async fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
    ...
  }
)
```

**编排逻辑**（`ops_watchdog.mbt`，伪代码，返回统一 JSON）：

```
pub fn watchdog_tick(
  engine, now, timeout_sec~, namespace?, next_description?,
) -> Result[Json, String]:

  1. 回滚阶段（功能 A）：
     healed = heal_stale_tasks_from_store(engine, now, timeout_sec~)
     若 healed 非空：返回 action="restarted", restarted=healed, count=N

  2. 后续阶段（功能 C，仅当提供 next_description）：
     若 next_description 存在：
       完成的根任务 = 扫描 namespace 内 status=="已完成" 且未被续轮的根任务
       （判定"续轮"方式见 4.3，建议靠根任务 deliverable 或专门标记字段）
       若存在已完成根任务：
         publish 新根任务(project_dir=原根 project_dir, description=next_description,
                          created_by=next_created_by||"watchdog", namespace, now)
         返回 action="advanced", new_task_id=..., previous_task_id=...

  3. 等待阶段（默认）：
     活跃任务 = namespace 内 status∈{执行中,已领取,拆分中} 且心跳新鲜的任务
     若活跃任务非空：返回 action="waiting", active=N, detail={task_id: last_seen}
     否则：返回 action="idle"

  4. 阻塞任务（已暂停/已打回）不参与任何动作，直接跳过（不返回、不计入 active），
     仅在 detail 里附带 blocked 列表供排查。
```

**返回 JSON 结构约定**（实现需稳定，供调用方 cron 分支判断）：

```json
{ "action": "waiting"|"restarted"|"advanced"|"idle",
  "active": <int>, "healed": <int>,
  "new_task_id": "<string|null>", "previous_task_id": "<string|null>",
  "blocked": ["<task_id>", ...], "detail": { ... } }
```

**约束**：
- `namespace` 限定：自动续轮/自动 heal **只作用于传入的 namespace**；未传 namespace 时**默认不自动续轮**（只做 heal + 状态汇报），把「自动起新轮」留待调用方显式指定 ns，贯彻第 0 节「仅用于定时任务」的边界。
- 全程不 panic、不阻塞：所有 store 操作失败 `ignore(...)`，保证 tick 幂等、可被任意频率安全调用。

### 4.3 功能 C：完成 → 自动起下一轮

**目标**：上一轮根任务完成后，watchdog_tick 能自动 publish 下一轮。

**关键设计点：「怎么识别上一轮已经完成但仍未续轮」**

建议采用**根任务 deliverable 约定**（最轻量、不引入新状态字段）：

- 约定：续轮动作发生后，`publish` 新根任务时，将**旧根任务的 `deliverable` 置为特殊标记**（如 `"__advanced__:<new_task_id>"`），或调用 `archive` 归档旧根任务。
- `watchdog_tick` 判定续轮：namespace 内存在 `status=="已完成"` 且 `deliverable` 不含 `__advanced__` 前缀（且未被 archive）的根任务 → 视为「待续轮」。

（备选：在 `core_task.mbt` 增加布尔字段 `auto_advanced`，但改动面较大，不推荐本期做。**本期推荐 deliverable 约定方案**。）

**publish 新根任务复用现有 `engine.publish(...)`**（`engine.mbt:35`），跑通后旧根任务 `archive`（`engine.mbt:337`）。

**边界**：
- 只有当调用方传了 `next_description`（定时任务场景由外部元提示词 agent 生成）时才触发续轮；不传则只返回 `action="idle"`（或 `waiting`），把「生成下一轮描述」的决策权留给外部。FIST-Mbt **不负责生成任务描述内容**。
- 续轮消耗 `next_description` 后，同一次 tick 不再复用（防止每 1 分钟重复发布相同下一轮）。

---

## 5. tick 状态机（总览）

```
             ┌─────────────────────────────┐
  cron 每1分 │  watchdog_tick(now, ns, next_desc?)  │
  ──────────►│                                │
             └───────────────────────────────┘
                          │
        扫描 namespace 内活跃/已完成/阻塞任务
                          │
   ┌──────────┬───────────┼───────────┬──────────┐
   ▼          ▼           ▼           ▼          ▼
 心跳超时   上一轮完成   心跳新鲜    已完成但   已暂停/已打回
  (挂了)   +next_desc    (还在跑)   无next_desc (阻塞)
   │          │           │           │          │
  heal      publish     等待        回报 idle   跳过(skip)
  回滚重派   新根任务      │
   │          │           │
 restarted  advanced    waiting
```

---

## 6. 文件改动清单

| 文件 | 改动 | 说明 |
|---|---|---|
| `src/ops/ops_heal.mbt` | 新增 `heal_stale_tasks_from_store(...)` | 功能 A，读 SQLite 判定超时回滚 |
| `src/ops/ops_watchdog.mbt` | **新增文件** | 功能 B/C 编排逻辑 `watchdog_tick(...)` |
| `src/ops/moon.pkg` | 若新文件需要 import 其他包则补充依赖 | 视 `@engine`/`@store` 访问方式 |
| `src/ops/ops_test.mbt` | 新增黑盒测试 | 覆盖 A/B/C |
| `src/server/server.mbt` | 新增 `.tool("watchdog_tick", ...)` 注册 | 参考现有 `heartbeat`/`heal` 注册写法 |
| `README.md` / `AGENTS.md` | 更新工具表 + 适用范围标注 | 注明「推荐仅用于定时任务」 |

> 无需改动：`store_sqlite.mbt`、`store.mbt`、`engine.mbt` 的 store_* 心跳委托（均已就绪）。仅当想补单条 read 委托时才会动 `engine.mbt`（非必需）。

---

## 7. 测试计划（新增用例）

在 `src/ops/ops_test.mbt`（或独立 `watchdog_test.mbt`）新增，全部 `moon test` 通过：

1. **A-1 跨进程 stale 判定**：向 store 写入一条 10 分钟前的心跳，调用 `heal_stale_tasks_from_store(now, timeout_sec=600)`，断言该执行中任务被回滚。
2. **A-2 心跳新鲜不回滚**：写入 1 分钟前心跳，调用后断言任务仍「执行中」。
3. **A-3 无心跳记录判定 stale**：执行中任务无任何心跳记录，断言被回滚。
4. **A-4 非活跃状态不回滚**：已暂停/已完成/已归档任务即使心跳超时也不回滚。
5. **B-1 waiting**：存在心跳新鲜的执行中任务，tick 返回 `action=="waiting"`。
6. **B-2 idle**：无活跃任务且无待续轮，tick 返回 `action=="idle"`。
7. **B-3 blocked 跳过**：存在已暂停任务，tick 返回中 `blocked` 含该任务且 `active` 不计它。
8. **C-1 自动续轮**：已完成未续轮根任务 + 传入 `next_description`，tick 返回 `action=="advanced"` 且产生新 `task_id`，旧根被 archive 或打标记。
9. **C-2 无 next_description 不续轮**：已完成但未传 next_description，tick 不发布新任务，返回 `idle`。
10. **幂等性**：连续两次 tick，第二次不应重复发布相同 next_description。

---

## 8. 完成标准

- [x] `moon check` 通过（无编译错误）
- [x] `moon test` 全部通过（含新增约 10 条用例，原 77 条无回归）
- [x] `moon info && moon fmt` 已执行，`.mbti` 变更符合预期
- [x] `watchdog_tick` 工具在 `moon run cmd/main` 启动的 server 中可被调用
- [x] 判定/续轮/回滚行为**仅作用于显式传入的 namespace**，不影像 `default` 人工流程
- [x] README / AGENTS 已标注「推荐仅用于定时任务」的适用范围

---

## 9. 对接层（不属于本仓库改动，仅说明）

FIST-Mbt 是被动 MCP，`watchdog_tick` 落地后仍需一个**外部 cron** 每 1 分钟调它（不需要「1 小时 + 1 分钟」两层节奏，一个「每 1 分钟 tick」即可全覆等待/重启/起新轮/跳过）。

- 外部 cron 调用 `watchdog_tick`，按返回 `action` 分支：
  - `waiting` / `idle`：本分钟无事，结束
  - `restarted`：记录重启日志，结束
  - `advanced`：本分钟已自动起新轮，结束（下一轮的「生成描述」由外部元提示词 agent 产出后，作为下次 tick 的 `next_description` 传入）
- lang-zone 现有两个 cron（`loop_prompt`/`action`）届时可下线，改由该单点调度接管。

> 附：`lang-zone` 侧「生成下一轮任务描述」的职责仍由外部元提示词 agent 承担，FIST-Mbt 只负责「状态推进 + 触发」，二者通过 `watchdog_tick` 的 `next_description` 参数衔接。