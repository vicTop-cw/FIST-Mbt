# BUG-420 诊断报告 · `ns` 字段只是标签不是落库位置

> **文种**：只读诊断（Q1/Q2 事实 + Q3 方案比较）
> **日期**：2026-10-26 · **执行**：Lane W（commander-alpha）
> **边界**：**未改任何 `src/` `docs/` `scripts/` 文件**。只读 sqlite + 只读源码。
> **所有读数均为本次现读**，脚本 `temp/audit/lane_w_ns_census.py`（只读，`mode=ro`）

---

## 结论

### Q1 的事实：`ns` 在**四个层里三种角色**

| 层 | `ns` 的角色 | 关键读数 |
|---|---|---|
| **① CLI/MCP 工具层** | **路由键** | `get`/`list`/`archive`/`publish` 都调 `engine_for_ns(ns)`（`server.mbt:63`） |
| **② 引擎层** | **路由键**（有静默回落） | `mstore.get(ns)` 取不到 ⇒ **`None => engine`（静默回落主库）** |
| **③ store 层** | **物理库选择器** | `MultiStore::get` **惰性打开**：分库不存在就**新建空库**（`multi_store.mbt:109-131`） |
| **④ DB 层** | **纯粹的标签** | `tasks.ns` 列只被 `WHERE ns=?` 用来**过滤**，从不决定物理位置 |

**⇒ 病灶：①②③ 把 `ns` 当路由键，④ 把它当标签，而两者从未对齐。**

### Q1 最关键的一条读数（这条推翻了 BUG-420 原文的措辞）

**BUG-420 记「2432 条历史任务**物理全在 default 库**」。**
**实际是：2432 条在 `fist-mbt.db`（主库），但每条各自带 62 种不同的 ns 标签，`ns='default'` 只有 161 条。**

```
fist-mbt.db 总任务 = 2432
  ns='default'   : 161
  ns!='default'  : 2271   ← 62 种不同标签
```

**⇒ 「全在 default 库」应改为「全在主库 `fist-mbt.db`，各自带不同 ns 标签」。**
**这个区别很重要**：不是「标签丢了」，而是「**标签在，但物理位置与标签不一致**」。
**⇒ 数据是对的，是路由和存储分家了。**

### Q2 的事实：BUG-407 修的是**反方向**，两者互补而非覆盖

| | BUG-407 | BUG-420 |
|---|---|---|
| 场景 | `publish` 写进分库后，**不带 ns** 的 `get` 找不到 | 历史数据在主库，**带 ns** 的 `get` 找不到 |
| 修复方向 | 让**不带 ns** 时也能找到（或让 publish 落主库） | 让**带 ns** 时能找到主库里的历史数据 |
| 现状 | 已 FIXED | OPEN |

**⇒ 两者是同一根因（路由键 vs 标签分家）的两个方向，BUG-407 只修了「新数据写入路径」，没管「历史数据位置」。**

### Q3 我的倾向：**(a) 数据迁移为正解，但必须先做「(a′) 只读盘点 + 试跑」；(b) 只在迁移完成前做临时止血且必须带显著标记**

**理由见 §5。**

---

## 证据

### 1. Q1-④：`fist-mbt.db` 的 ns 分布（63 个标签 / 2432 条）

| ns 标签 | 条数 |
|---|---|
| `award-demo` | 661 |
| `zn` | 497 |
| **`default`** | **161** |
| `bugs` | 148 |
| `gradient-verify` | 140 |
| `fist-allmodes` | 121 |
| `mcp-smoke` | 73 |
| `cron-vq` | 43 |
| `selfdrive-all-modes` | 36 |
| `lzc-loop-20260928` | 34 |
| `cron-cypy` | 34 |
| `pentad-imp` | 32 |
| `pmode-r4-fix` | 29 |
| `omega-lesson-verify` | 28 |
| `pmode-r4-verify` / `pmode-r4` / `fist-opt-20261016` / `f094-worktree` | 21 / 21 / 21 / 21 |
| `scratch` / `challenge-verify` | 19 / 19 |
| `pmode-r5-fix` / `cypy-drive` / `auto-route-20260927` | 18 / 18 / 18 |
| `ofm-fusion` | 17 |
| `lang-zone` | 14 |
| `vq-gui` / `pentad-dev` / `pentad` / `allmodes-switch` | 13 / 13 / 13 / 13 |
| `shim-review` / `pmode-r5-verify` / `pmode-r5-erratum` | 12 / 12 / 12 |
| `enhance-e2e` | 11 |
| `tnr-polish` / `light-isolation` | 10 / 10 |
| `dispatch-verify` | 9 |
| `stdalign` / `fist-allmodes-r59` | 7 / 7 |
| `phaseC-callsite` | 6 |
| `r3verify` / `r2verify` / `fist-fix-mcp` | 5 / 4 / 4 |
| `tnr-perf` / `marvis-drive` / `cron-auto` | 3 / 3 / 3 |
| 其余 23 个标签各 1 条 | `vools-commit` `vools` `test-ns` `sagarepair-proper` `rtr16-lock` `recursive-demo` `r1` `probe` `polish-loop` `lz-r14` `lz-combo-r2` `laya-e2e2` `goalverify0928` `fist-modes-r1-m4` `fist-modes-bugfind-atomcode` `executor-verify` `cron-tnr` `b51smoke` … |

**（完整 148 个 (物理库,ns) 组合见 `temp/audit/lane_w_ns_census.py` 输出，总 2745 条跨全部 `.db`。）**

### 2. Q1-③/④：分库实际状态 —— **分库存在，但几乎是空的**

| ns | 分库 `.fist-mbt/data/<ns>.db` | 分库内 tasks | 主库同 ns 条数 |
|---|---|---|---|
| **`bugs`** | ✅ 存在 | **0** | **148** |
| `gradient-verify` | ✅ 存在 | **0** | **140** |
| `award-demo` | ✅ 存在 | 7 | 661 |
| `zn` | ✅ 存在 | 8 | 497 |
| `tnr-tql` | ✅ 存在 | 5 | 0（主库无此标签） |

**⇒ 决定性读数：`bugs` 分库 0 条 vs 主库 148 条 —— 数据从未迁移。**
**⇒ 这解释了 `get(task_id="T0r741", namespace="bugs")` 为什么 not found：它去查那个 0 条的空分库。**

### 3. 「not found」的逐行调用链

```
get(task_id="T0r741", namespace="bugs")
  │
  ├─ server.mbt:2104  "get" 工具注册
  │    fn(args): ns = get_str(args,"namespace"); eng = engine_for_ns(ns)
  │
  ├─ server.mbt:63    fn engine_for_ns(ns : String) -> FistEngine
  │    if ns == "" || ns == "default" { engine }
  │    else {
  │      match mstore.get(ns) {
  │        Some(s) => FistEngine::new(store=StoreBackend::sqlite(s))   ← 走这条
  │        None    => engine                                          ← 静默回落主库（本题不走）
  │      }
  │    }
  │
  ├─ multi_store.mbt:109  pub fn MultiStore::get(self, ns) -> SqliteStore?
  │    未打开 ⇒ 惰性打开：path = ".fist-mbt/data/{safe_ns}.db"
  │    ⇒ SqliteStore::open(path)   ← **打开的是 .fist-mbt/data/bugs.db（0 条任务）**
  │
  └─ store 层  SELECT ... FROM tasks WHERE id = 'T0r741'  在 .fist-mbt/data/bugs.db 里执行
       ⇒ 0 行 ⇒ **"task not found: T0r741"**

【断点定位】**死在最后一步：库找到了（不是 None 分支）、库也打开了，
   但那个库是空的** —— 因为历史数据在 `fist-mbt.db`，从未写进 `bugs.db`。

【另一个断点（Round 4 撞的那个）—— ⚠️ 已实测修正】
get(task_id="T0r636.1.2")  且不带 ns
  ⇒ engine_for_ns("") ⇒ engine（**主库**）
  ⇒ store_sqlite.mbt:495-499
     impl Store for SqliteStore with fn get_task(self, id) {
       let sql = "SELECT {task_columns()} FROM tasks WHERE id = ?"   ← **只按 id，不带 ns 过滤**
     }
  ⇒ **在主库按 id 查，T0r636.1.2 在主库里确实存在** ⇒ 应该能查到

**⚠️ 所以 Round 4 的 not found 不是「主库按 ns 过滤掉了」，而是别的库**：
现读 `T0r636.1.2` 在 `fist-mbt.db`、ns=`fist-opt-20261016`。
若调用方当时带上了 `--namespace fist-opt-20261016`，就会路由到
`.fist-mbt/data/fist-opt-20261016.db`（**另有一个 21 条的分库**），
而 2432 条里的那 21 条在主库、分库里另有一份 ⇒ 取决于分库内容。
**⇒ 这条的具体断点我无法从现有读数唯一确定（缺当时的完整入参），如实标注。**
**但它不改变主结论：get_task 不带 ns 过滤，一切分歧都在「选哪个物理库」这一步。**
```

### 3.1 由此得到一个重要的负面结论

**`get_task` 不带 ns 过滤 ⇒ (b) 路由兜底的「跨 ns 泄露」风险比想象中更直接：**
因为即使不做兜底，**只要选对了库，`get(id)` 就会返回该库里任何 ns 的任务**。
`fist-mbt.db` 里有全部 62 个 ns 的 2432 条 ⇒
**任何能用主库句柄（`ns=""` 或 `ns="default"`）查询的调用方，都能按 id 拿到任意 ns 的任务。**

**⇒ 「ns 隔离」在「主库」这条路径上**现在就**不成立**（不是兜底后才不成立）。
**这是本报告的第二个重要发现，建议单独立项。**
```

### 4. Q2：BUG-407 落点

```
$ grep -rn "BUG-407" src/ docs/ reports/
reports/2026-10-24-tidy-residual-cleanup.md:29, :160
reports/2026-10-25-pr-batch-merge-and-bug407-408-report.md:1, :14, :68, :69

$ grep BUG-407 src/ --> **0 命中**（源码里没有 BUG-407 标记）
```

**BUG-407 账本原文（`memory/bugs.md`）**：
> `list` 可见但 `get --namespace` 找不到：任务 namespace 字段与实际落库不一致
> （namespace 查询路由到**空 store**）

**⇒ BUG-407 与 BUG-420 描述的是同一个现象，但修的方向不同：**
- **BUG-407 修的是「`publish` 之后同一会话内 `get` 找不到」**（新数据写入路径）
- **BUG-420 是「历史数据的位置与标签不一致」**（存量数据）
**⇒ 修复只覆盖了「真分库」场景：新 publish 会写进当前打开的分库，所以同一会话内 get 得到；
但 2432 条历史数据留在主库，任何按 ns 的路由都找不到它们。**

**⚠️ 一个必须说清的细节**：`grep BUG-407 src/` = **0 命中** ——
说明那次修复**没有在源码留下 BUG-407 标记**，无法从代码反推改了哪一行。
**⇒ 这是「修复不可追溯」的一个实例**，建议后续修复必须在源码留标记。

---

## 5. Q3：三条路的比较与我的倾向

### 5.1 数据侧先给三个关键读数（这决定可行性）

| 读数 | 值 | 对方案的意义 |
|---|---|---|
| **跨 ns 的 id 冲突** | **0 个**（`SELECT id, COUNT(DISTINCT ns) HAVING >1` = 0） | ✅ **迁移不会产生 id 冲突** —— 这是 (a) 可行的**最强依据** |
| **非 default 的 ns 标签** | **62 个**，其中 **32 个已有分库**、**30 个需新建** | 迁移要处理 62 个目标库 |
| **分库 vs 主库同 ns 的交集** | **0 条**（`award-demo` 7/661、`tnr-tql` 5/0） | ✅ **不会覆盖已有分库数据** |

### 5.2 三方案对比

#### (a) 数据迁移 —— **正解，我倾向这条**

**做法**：把 `fist-mbt.db` 里 `ns != 'default'` 的 **2271 条**按标签搬进 `.fist-mbt/data/<ns>.db`。

**支持它的读数**：
- **id 零冲突**（0 个跨 ns 重复）
- **与现有分库零交集**（不会覆盖）
- 搬完后**语义完全对齐**：`ns` 既是标签也是位置，四层一致

**风险**：
| 风险 | 说明 | 缓解 |
|---|---|---|
| **不可逆** | 迁移后主库那 2271 条要删，删错了无法恢复 | **迁移前 `cp fist-mbt.db` 全量备份**；且**先 dry-run 打印「将搬 N 条到 M 个库」** |
| **30 个 ns 要新建库** | 部分 ns 可能本就不该独立（如 `scratch` / `test-ns` / `probe`） | **先裁决哪些 ns 值得独立**，不值得的留在 default 或归档 |
| **`safe_ns` 可能拒绝某些标签** | `MultiStore::safe_ns`（`multi_store.mbt:28`）只允许特定字符 | **dry-run 时对每个标签跑一遍 safe_ns**，被拒的要先改标签或特殊处理 |
| 事务边界 | 62 个库、2271 条，跨库无原子事务 | **每库一个事务**，失败可重入（幂等：`INSERT OR IGNORE`） |

#### (b) 路由兜底 —— **止血，但会破坏隔离语义**

**做法**：`engine_for_ns(ns)` 在分库查不到时回落到主库查一次。

**必须回答的两个问题（任务硬要求）**：

**Q3-b-1：「按 ns 隔离」这个承诺还成不成立？**
**⇒ 不成立。** 隔离的本质是「ns A 的客户端看不到 ns B 的数据」。
兜底后 `engine_for_ns("bugs")` 在 `bugs.db` 查不到时会去 `fist-mbt.db` 查 ——
**而 `fist-mbt.db` 里有全部 62 个 ns 的数据**。
⇒ **A ns 的客户端确实能查到 B ns 的任务**（只要它知道 task_id）。

**Q3-b-2：「A ns 能查/改 B ns 的任务」会出现吗？**
**⇒ 会出现，而且分两种情况**：
- **只读（`get`）**：只要 id 对得上，`get(id, ns="A")` 会返回 `ns="B"` 的任务 ⇒ **信息泄露**
- **写（`archive`/`claim`/`execute`）**：**更危险** —— 若兜底命中后直接用主库句柄写，
  **就是跨 ns 写**；若写回分库又是另一套语义。**这是设计上的两难，不是实现细节。**

**Q3-b-3：「这是不是只是掩盖问题」？**
**⇒ 是。** 历史数据仍然错位在 `fist-mbt.db`，只是**查得到了**。
更糟的是**兜底会让「数据在哪」这个问题永久失去紧迫性** —— 没人再需要迁移。

**⇒ 我的判断：(b) 只能作为迁移完成前的**临时止血**，且必须**
1. **仅在读路径兜底**（`get`/`list`），**绝不在写路径兜底**
2. **回执必须显著标记** `"ns_fallback": true` + `"actual_ns": "..."`，让调用方知道这是兜底结果
3. **日志/审计留痕**每次兜底

#### (c) 视图 —— **物理上不可行**

**做法**：`tasks` 表建一个覆盖所有分库的视图。

**⇒ SQLite 的视图**不能跨 ATTACH 的多个库做「自动 UNION 所有库」** ——
`CREATE VIEW` 只能引用**当前连接可见的表**，跨库必须显式 `UNION ALL`
且**库清单是编译期写死的**，新建一个 ns 库就要重建视图。
**⇒ 62 个库、且会动态增长 ⇒ 视图方案不可维护。**

**替代形态**：加一个「全局索引表」（`task_ns_index(task_id, ns, db_path)`），
每次写任务时维护。**但那是新的双写一致性问题**，比 (a) 更复杂。

### 5.3 我的倾向（明确给出）

> **选 (a) 数据迁移，但必须先做 (a′) 只读盘点 + dry-run，不允许一步到位。**

**分三阶段**：
```
阶段 0（只读，本次已做一部分）：盘点 62 个 ns × 2271 条的标签分布、id 冲突、分库交集
阶段 1（dry-run）：对每个 ns 跑 safe_ns、列出「将搬 N 条到 <path>」、标出哪个库不存在需新建
                   —— 不写任何数据，人工审这份清单
阶段 2（执行）：备份 fist-mbt.db → 逐库事务迁移（INSERT OR IGNORE 幂等）→ 核验条数
阶段 3（收尾）：确认四层一致后，才从主库删已迁走的行
```

**明确反对「直接上 (b)」作为最终方案**：它让隔离承诺失效，且掩盖问题。
**若 owner 要求先止血**，我建议 **最小版 (b)**：只在 `get` 兜底 + 回执带 `ns_fallback` 标记 + 写路径绝不兜底。

---

## 6. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| **R1** | **未做 dry-run** | 本报告只做了阶段 0 盘点。**safe_ns 对 62 个标签的逐一判定未做** —— 有些标签可能被拒（含非法字符） |
| **R2** | **「哪些 ns 该独立」未裁决** | `scratch` / `test-ns` / `probe` / `r1` 这类 1 条标签，**独立建库是否值得**是人的决定，不是数据能答的 |
| **R3** | **写路径的 ns 语义未查** | `archive`/`claim`/`execute` 是否也走 `engine_for_ns`、是否按 ns 过滤 —— **我只核了 `get`/`list`/`publish`**，写路径需补核才能评估 (b) 的写风险 |
| **R4** | ~~`store 层按 id 查询是否带 ns 过滤未核~~ | ✅ **已实测消解**：`store_sqlite.mbt:495-499` 的 `get_task` SQL 是 `WHERE id = ?`，**不带任何 ns 过滤**。⇒ 我在 §3 的「若带 `AND ns='default'`」假设**是错的**，已改写。**且由此发现「ns 隔离在主库路径上现在就不成立」（见 §3.1）—— 这是比 BUG-420 更严重的独立问题** |
| **R5** | **`grep BUG-407 src/` = 0 命中** | 那次修复源码无标记，无法反推改动点，只能从账本描述判断方向。**这是「修复不可追溯」实例** |
| **R6** | 本次未触碰 `src/server/server.mbt` / `multi_store.mbt` / `ocr_scan.mbt` 的 `M` 状态改动 | 按你提醒，只读，未 edit |

---

## 7. 建议入档位置

1. **本报告**：`reports/2026-10-26-bug420-ns-routing-diagnosis.md`
2. **修正 BUG-420 的措辞**（如果允许改账本）：
   > 原文：「2432 条历史任务物理全在 default 库」
   > 建议：「2432 条历史任务物理全在主库 `fist-mbt.db`，各自带 62 种 ns 标签（`ns='default'` 仅 161 条）；
   > 分库 `.fist-mbt/data/<ns>.db` 存在但几乎为空（`bugs` 0 条 vs 主库 148 条）」
   **⇒ 「全在 default 库」这个说法会误导修法人去查 default 特殊逻辑，而真正的问题是「路由键与物理位置分家」。**
3. **判例候选**：
   > **判例-XX：修复必须留标记。** `grep BUG-407 src/` = 0 命中 ⇒ 那次修复只能靠账本描述推断。
   > **⇒ 每笔缺陷修复必须在本仓源码留 `BUG-nnn` 标记**（哪怕只是一行注释），否则半年后无人能定位改动面。
   > 本轮我做的三个诊断（BUG-411/417/418）都因此受益 —— 那三处源码里都有标记。
4. **另一条判例候选（本轮最重要）**：
   > **判例-XX：「在某个库里」与「带某个标签」是两件事，混用会产生沉默的不可达数据。**
   > `ns` 同时被当作**路由键**（决定查哪个物理库）和**标签**（`WHERE ns=?` 过滤）。
   > 当存量数据的标签与物理位置不一致时，**数据既没丢也没坏，但永远查不到** ——
   > 这是最难排查的一类：无报错、无日志、`sqlite3` 直查还看得见。
   > **⇒ 任何「键 + 标签」双用的字段，必须有一次性校验「标签与位置一致」的普查。**

---

**本报告未修改 `src/` `docs/` `scripts/` 任何文件。未 commit 前已列出。未调 `bug_fix`。**
