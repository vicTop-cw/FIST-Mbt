# SKILL: mcpcf-embed — 嵌入式 MCPCf 内部工具（七件套，`src/server/mcpcf_embed.mbt` 真源）

> 形态：skill（本文档，一源四态第三态）｜MCP 内部工具 `mcpcf.ops_init` / `mcpcf.run_batch` / `mcpcf.verify` / `mcpcf.circuit` / `mcpcf.report` / `mcpcf.review` / `mcpcf.watchdog`
> 真源：`src/server/mcpcf_embed.mbt`（vendored from `vicTop-cw/mcpconftest@e474d8c` `src/lib/fist_ops.mbt`）+ `embed_mcpcf_tools` 链式 `s.tool` 注册面（serve 模式暴露 `mcpcf.*`）
> 用途：给**宿主内嵌**场景一个「进程内 FIST 引擎 + 全能力」的嵌入式运行时——`ops_init` 初始化引擎（SQLite 优先、内存兜底），其余六者覆盖发布/验收/熔断/报告/审查/看护全能力，复用本进程 `@engine` / `@core` API，**不跨进程、不碰 fist-mbt 主库**（数据隔离到 `mcpconftest-ops.db`）。

## 何时用

- **宿主要把 FIST 引擎「装进自己进程」用**：不想跨 stdio 起一个独立 `fist-mbt` server、也不想让宿主进程去连主库——`ops_init` 在**本进程**拉起一个内嵌 FIST 引擎（模块级 `holder` 持有），后续六个工具直接复用这个引擎对象，零跨进程开销。
- **需要一个与主库隔离的独立台账**：内嵌引擎的数据目录默认 `%LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db`，可用环境变量 `MCPCONFTEST_DATA_DIR` 或 `ops_init` 的 `data_dir` 覆盖——**与 fist-mbt 主引擎库互不干扰**，适合宿主在沙箱/临时区里跑自己的巡检批次，不污染仓库根。
- **宿主想「发布一批 → 验收 → 看护」一条链闭环**：`run_batch` 发布根任务批次、`verify` 验收、`report`/`review` 看读数、`circuit` 管外部依赖熔断、`watchdog` 看护一拍——七件合起来就是一个「内嵌 FIST 运行时全能力」，宿主不必再单独连主 server。
- **宿主进程要自愈/自检**：`watchdog` 返回引擎后端 + 任务计数（可选熔断快照），给宿主一个「引擎活着、有多少活、熔断状态」的快速体检入口。

## 怎么调

> 参数名 = MCP 注册面真名（`embed_mcpcf_tools` 里 `s.tool` 的 schema），逐字对齐 `AGENTS.md` 条目，不是杜撰。所有工具的时间戳都由服务端 `now_utc()` 盖章，**调用面无 `now` 参数**（BUG-33 政策一致）。

### (1) `mcpcf.ops_init` — 初始化内嵌 FIST 引擎（SQLite 优先，内存兜底）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `data_dir` | — | 未传走 `MCPCONFTEST_DATA_DIR` / `%LOCALAPPDATA%\mcpconftest\data` / `./mcpconftest-data` | 可选数据目录；传入会 `reset_engine()` 强制重开该目录下的库（测试隔离/换库用） |

- **SQLite 优先、内存兜底**：`FistEngine::open_sqlite(db_path)` 成功则用 SQLite 后端，失败回退 `FistEngine::new()` 内存版。
- **返回 `backend` 与库路径**：`{ ok: true, backend: <heartbeat_backend>, db: <绝对库路径> }`——`backend` 让调用方知道这次落的是 SQLite 还是内存。
- **首次调用即懒初始化**：不显式 `ops_init` 时，其余六者内部 `ensure_engine()` 也会按默认目录拉起引擎（幂等，进程内共享同一个 `holder.engine`）。

```
tools/call mcpcf.ops_init
  { }                                  // 默认目录，返回 backend + db 路径
tools/call mcpcf.ops_init
  { "data_dir": "C:/tmp/sandbox" }     // 强制重开 C:/tmp/sandbox\mcpconftest-ops.db（隔离）
```

### (2) `mcpcf.circuit` — 内嵌熔断器状态机查询/推进（closed / open / half-open 三态）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `circuit` | ✅ | — | 熔断器名称；为空直接报 `circuit requires circuit name` |
| `action` | — | `status` | `status` \| `fail` \| `succeed`：查询 / 上报失败 / 上报成功 |
| `ns` | — | `default` | 命名空间 |

- 按 `action` 分流调引擎层 `circuit_status` / `circuit_fail` / `circuit_succeed`，返回该熔断器三态（**closed / open / half-open**）的 JSON 快照——与主 server 的 `circuit_status` / `circuit_fail` / `circuit_succeed` 同口径，只是走内嵌引擎。
- `action` 缺省 `status`（只查不改）；`fail` / `succeed` 会推进三态状态机（失败计数达阈值 → open；half-open 探测成功 → closed）。

```
tools/call mcpcf.circuit
  { "circuit": "github_api" }                          // action 缺省 status，只查三态
tools/call mcpcf.circuit
  { "circuit": "github_api", "action": "fail" }        // 上报一次失败，推进状态机
```

### (3) `mcpcf.report` — 内嵌运行报告（按 ns 汇总，机器可读 JSON）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `ns` | — | `default` | 命名空间 |

- 按 `ns` 汇总该命名空间下的任务——返回 `{ ok, ns, total, by_status: {<状态>: 计数}, tasks: [...] }`，每状态计数 + 精简任务清单（id/status/description/depth/updated_at）。
- 纯读快照、机器可读，可直接喂给宿主的巡检/上报逻辑。

```
tools/call mcpcf.report
  { "ns": "default" }    // 该 ns 的按状态计数 + 任务清单
```

### (4) `mcpcf.review` — 内嵌验收视图（列待验收任务及其交付物与门禁结果）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `task_id` | — | 未传 | 指定单个任务 id → 返回该任务完整字段（id/status/description/depth/updated_at） |
| `status` | — | 空串=全量 | 未传 `task_id` 时按状态过滤（如 `待领取`/`执行中`/`已完成`）；非法状态报 `unknown status` |

- **两种形态**：传 `task_id` → 单任务对象；不传 → 按 `status` 过滤（空则全量）列出 `{ ok, count, tasks }`。
- 供宿主在验收环节「看一眼这个任务现在什么状态、交付物挂没挂、门禁过没过」。

```
tools/call mcpcf.review
  { "task_id": "t-001" }                 // 单任务完整字段
tools/call mcpcf.review
  { "status": "待验收" }                  // 按状态列待验收任务
```

### (5) `mcpcf.run_batch` — 内嵌批量执行（按任务批次串行推进 claim/execute/submit）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `project_dir` | ✅ | — | 本批次的项目目录；空则报 `run_batch requires project_dir and description` |
| `description` | ✅ | — | 批次描述；空同上 |
| `created_by` | — | `human_steward` | 创建者角色；须为 `human_steward` 或 `human` |
| `ns` | — | `default` | 命名空间 |

- 发布一个根任务批次——**按给定任务批次串行推进 claim/execute/submit，遇门禁失败即停并回执已推进到哪一条**。返回新任务的 `{ ok, task_id, ns }`。
- 与主 server 的 `publish` 同口径的根任务发布，只是走内嵌引擎 + 面向宿主批量场景。

```
tools/call mcpcf.run_batch
  { "project_dir": "E:/proj/foo", "description": "巡检批次 #42",
    "created_by": "human_steward", "ns": "default" }
```

### (6) `mcpcf.verify` — 内嵌验收（对指定 task 跑 verify 同款校验）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `task_id` | ✅ | — | 要验收的任务 id；空则报 `verify requires task_id` |
| `verifier` | — | `mcpconftest` | 验收者名 |
| `docs_check` | — | `false` | 验收时是否跑文档门禁（boolean） |

- 对指定 `task_id` 跑 verify 同款校验（语料门禁 / 成果复验），返回 `{ ok, task_id, status }`。
- 与主 server 的 `verify` 同口径，只是走内嵌引擎；`docs_check` 缺省 `false` 不开文档门禁。

```
tools/call mcpcf.verify
  { "task_id": "t-001" }                          // 验收，verifier=mcpconftest，docs_check=false
tools/call mcpcf.verify
  { "task_id": "t-001", "verifier": "reviewer", "docs_check": true }
```

### (7) `mcpcf.watchdog` — 内嵌看门狗一拍（scan 超时任务 + 自动续轮，与 `watchdog_tick` 同口径）

| 参数（真名） | 必填 | 默认 | 说明 |
|---|---|---|---|
| `circuit` | — | 未传 | 可选熔断器名；传入则回执附该熔断器三态快照 |
| `ns` | — | `default` | 命名空间（仅在带 `circuit` 时读） |

- 看护检查：返回引擎 `{ ok, backend, task_count }`（引擎后端 + 全量任务计数），带 `circuit` 时再附 `{ circuit: <三态快照> }`——给宿主一个「引擎活着、有多少活、熔断状态」的体检一拍。
- 与主 server 的 `watchdog_tick` 同口径的「scan 超时任务 + 自动续轮」看护，只是走内嵌引擎。

```
tools/call mcpcf.watchdog
  { }                                   // 只回 backend + task_count
tools/call mcpcf.watchdog
  { "circuit": "github_api", "ns": "default" }   // 附熔断三态快照
```

## 已知边界

- **引擎是进程内共享的可变单例**：七件套都通过 `ensure_engine()` 读模块级 `holder : EngineHolder { mut engine : @engine.FistEngine? }`——**同一进程内共享一个引擎对象，进程重启即失**，跨进程/跨会话要重新 `ops_init`。`ops_init` 传 `data_dir` 会先 `reset_engine()` 置空再强制重开该目录库，等价「换库/测试隔离」。
- **数据隔离是硬设计，不是默认**：内嵌库默认落在 `%LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db`，可被 `MCPCONFTEST_DATA_DIR` env 或 `ops_init` 的 `data_dir` 覆盖——**与 fist-mbt 主引擎库是两份独立数据**，别指望内嵌引擎里发布的任务能在主 server 的 `list` 里看到（反之亦然）。
- **SQLite 优先、内存兜底，`backend` 是判断依据**：`open_sqlite` 失败（无盘/权限/缺 SQLite 运行时）会静默回退内存版 `FistEngine::new()`——此时数据不落盘、进程重启即丢。读 `ops_init` 回执的 `backend` 字段才能确认真正用的是 SQLite 还是内存，**别假设一定是持久化的**。
- **`run_batch` 当前 vendored 实现是「发一个根任务批次」，非字面多任务串行**：`AGENTS.md`/本 skill 的语义描述是「按批次串行推进 claim/execute/submit、遇门禁失败即停并回执已推进到哪一条」；当前 `src/server/mcpcf_embed.mbt` 的 `tool_run_batch` 落地为向引擎 `publish` 一个根任务（`project_dir`+`description`+`created_by`+`ns`），返回 `{ ok, task_id, ns }`——批次内的 claim/execute/submit 串行推进由宿主/上层按 `task_id` 续接，本 vendored 函数本身只负责把批次根任务发进去（vendored from mcpconftest，行为以该源为准）。
- **`created_by` 受角色硬门**：`run_batch` 的创建者须为 `human_steward` 或 `human`（schema 描述点名），非法角色会被引擎发布层拒绝——不是任意字符串都能创建者。
- **参数缺省口径**：`arg_str` 读不到回默认空串（`created_by`→`human_steward`、`ns`→`default`、`action`→`status`、`verifier`→`mcpconftest`）；`arg_bool` 读不到回 `false`（`docs_check`）；`arg_str_opt` 读不到回 `None`（`data_dir`/`task_id`/`circuit`——「未传」与「传空串」语义不同，`run_batch`/`circuit`/`verify` 的必填项靠空串判定报错，`ops_init`/`review`/`watchdog` 的可选项靠 None 判定走默认分支）。
- **`review` 双形态、两种返回结构不一样**：传 `task_id` 返回 `{ ok, task }`（单对象）；不传返回 `{ ok, count, tasks }`（数组）——消费方要按「传没传 `task_id`」分流解析。
- **`watchdog` 的 `ns` 只在带 `circuit` 时才被读**：不传 `circuit` 时 `ns` 不影响输出（只回 `backend`+`task_count`）；带 `circuit` 时 `ns` 决定查哪个命名空间的熔断器。
- **`verify` 的 `docs_check` 缺省 `false`**：不显式开启则不跑文档门禁；要文档门禁验收必须显式 `docs_check=true`。
- **时间戳服务端盖章**：`publish`/`verify` 的 `now` 都由 `now_utc()` 生成，调用面没有 `now` 参数——不接受调用方注入时间（BUG-33 政策一致）。
- 本次为**纯文档**：不编译 src、不跑 `moon test`。

## 七工具协同

> 一句话：**`ops_init` 是「点火」——在宿主进程内拉起一个与主库隔离的内嵌 FIST 引擎；其余六者是这个引擎的「全能力面」——发布/验收/熔断/报告/审查/看护，宿主不必跨进程连主 server，就能在自己的进程里把 FIST 任务闭环跑通。**

```
① 点火（引擎初始化，进程内单例）
   mcpcf.ops_init { "data_dir": "..." }   // SQLite 优先 / 内存兜底
     → { backend, db }                    // backend 判定真持久化还是内存
     // 不显式调也行：其余六者 ensure_engine() 会懒初始化同一引擎

② 发布批次（进引擎）
   mcpcf.run_batch { "project_dir", "description", "created_by", "ns" }
     → { task_id, ns }                    // 批次根任务发进内嵌引擎

③ 推进 + 验收（引擎内 claim/execute/submit 同款校验）
   mcpcf.verify { "task_id", "verifier", "docs_check" }
     → { task_id, status }                // verify 同款校验（语料门禁/成果复验）

④ 看护 + 熔断（外部依赖健康度）
   mcpcf.circuit  { "circuit", "action", "ns" }   // closed/open/half-open 三态推进
   mcpcf.watchdog { "circuit", "ns" }             // backend + task_count（+ 熔断快照）体检一拍

⑤ 读数（机器可读报告 / 验收视图）
   mcpcf.report { "ns" }                  // by_status 计数 + 任务清单
   mcpcf.review { "task_id" | "status" }  // 单任务 / 按状态列待验收
```

**为什么这样分工**：

- **`ops_init` 只管「引擎存在且用哪个库」**——它是唯一有初始化副作用的工具（`reset_engine` / `set_engine`），其余六者都假定引擎已在（不在就 `ensure_engine` 懒拉起）。先 `ops_init` 拿到 `backend`/`db` 再干活，是「确认真持久化 vs 内存」的唯一显式入口。
- **`run_batch` 进、`verify` 收**——一个把批次根任务推进引擎（发布面），一个对任务做验收（验收面）；中间的 claim/execute/submit 串行推进由宿主按 `task_id` 续接（vendored 源 `tool_run_batch` 只发根任务，见「已知边界」）。
- **`circuit` + `watchdog` 管外部依赖与引擎自身健康**——`circuit` 是外部调用（如某 API）的三态熔断（失败上报/成功回灌/状态查询），`watchdog` 是引擎自身「活着、多少活、熔断快照」的看护一拍；两者互补：前者管「外部依赖会不会打爆我」，后者管「我（引擎）现在什么状态」。
- **`report` + `review` 是只读读数面**——`report` 按 ns 给按状态计数 + 任务清单（面向统计/上报），`review` 按 `task_id` 或 `status` 给单任务/任务列表（面向验收环节逐条看）；纯读快照，不改状态。

**与主 server 的关系**：七件套走的是**内嵌引擎**（本进程 `@engine` / `@core`），与主 `fist-mbt` server 的 140+ 工具**共用同一套引擎 API 但各持一份引擎实例 + 各落一份库**（内嵌库 `mcpconftest-ops.db`，主库走 `FIST_DB_PATH`）——所以内嵌面是「宿主进程内自洽的小运行时」，主 server 是「跨进程的完整服务面」，两者互不干扰、按需选用。

> 一句话收尾：`ops_init` 点火、`run_batch` 进、`verify` 收、`circuit`/`watchdog` 看护、`report`/`review` 读数——七件一起，宿主进程里就有一个与主库隔离、能自闭环的 FIST 运行时。
