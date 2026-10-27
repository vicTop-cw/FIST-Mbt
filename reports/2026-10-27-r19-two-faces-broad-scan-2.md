# R19 · 未覆盖区域「两面」普查（第六波）

> **任务**：扫 3-4 个最可能有「两面」的面，重点找「占位返回值是合法值」的假绿形态
> **执行人**：司令-γ · **边界**：只读 + 报告（未改 `src/` `scripts/`，未碰 7 个在途文件）
> **产出**：本报告 + 1 条 `report_bug`

---

## 结论

**筛选方法变了**：不再按「面」挑，而是**先按 R18 `BUG-439` 的判定形状搜全仓**
（`StoreBackend` 分发里 `Mem(_) => None | Ok(()) | [] | "" | 0 | false`），
再沿命中点往下挖消费链。

| # | 面 | 扫了什么 | 结论 |
|---|---|---|---|
| **1** | **`saga_*`** | 3 个 store 分发 + 引擎消费 2 处 + 回执构造 11 个字段 | **★ 真 bug（`BUG-441`）** |
| 2 | `mcpcf_*` vs 主运行时 | 549 行全文 + 7 工具全部 handler + 辅助函数 | **共用引擎真源** ✓<br>⚠️ 但 `now_utc`/`fist_civil_from_days` 是**手工抄本**（现网等价） |
| 3 | `phi_accrual` + `phi_gate` | 1 处实现 + 3 处调用 + watchdog/ops_heal 两条路径 | **共用真源** ✓<br>（`heal` 的 stale 判定抄两份，R18 已记） |
| 4 | `heartbeat` 面 | 3 写 + 3 读的分发 + server 回执 | **不是 bug —— 而且它是正确典范** |

**读数汇总**：52 个 `Mem(` 分发点 · **7 个占位** · 逐个核到消费方 · 报 1 条真 bug。

---

## 证据

### §1 形状搜索结果（起点，不是猜测）

```
$ grep -nE 'Mem\(_?m?\) => (None|Ok\(\(\)\)|0|false|""|\{\})' src/store/store.mbt
460:  Mem(_) => None          ← sqlite_store() 本身（合理：内存后端没有 SqliteStore）
801:  Mem(_) => Ok(())
862:  Mem(_) => Ok(())        ← write_heartbeat
896:  Mem(_) => Ok(())        ← delete_heartbeat
921:  Mem(_) => Ok(())        ← write_heartbeat_interval
951:  Mem(_) => Ok(())        ← write_saga_action      ★
986:  Mem(_) => Ok(())        ← mark_saga_actions_done ★
$ grep -c 'Mem(' src/store/store.mbt → 52
```
**⇒ 52 个分发点里 7 个占位，占 13.5%。逐个核到消费方后：4 个已正确处理，3 个（saga）是真 bug。**

### §2 面 1：`saga_*` —— ★ 真 bug（`BUG-441`）

| Store 方法 | 内存后端 | SQLite |
|---|---|---|
| `write_saga_action` `:941-958` | **`Ok(())`** | 真写 |
| `list_saga_actions` `:966-976` | **`[]`** | 真读 |
| `mark_saga_actions_done` `:979-990` | **`Ok(())`** | 真更新 |

**引擎消费**（`engine_saga.mbt:54-95`）：
```moonbit
let rows = self.store_list_saga_actions(ns, root_task_id)   // 内存后端恒 []
for r in rows { if r.4 == "pending" { pending.push(r) } }   // 恒空
...
m.set("pending_count", Json::number(lifo.length().to_double()))  // 恒 0
m.set("pending", Json::array(steps))                             // 恒 []
m.set("marked_done", Json::number(marked_n.to_double()))         // 恒 0
```
**⇒ 回执与「这个根任务确实没有待补偿步骤」**逐字相同** ⇒ 无法区分「没有」与「读不到」。**

**为什么是假绿**：
1. `Ok(())` 是合法成功回执、`[]` 是合法空列表 ⇒ **编译器不报、调用方不疑**
2. `saga_register` 的 description 承诺「登记其可补偿动作到 **durable action log**」——
   内存后端**一条都不写，且回执说成功了**
3. **比 `BUG-439` 更隐蔽**：熔断器至少 `state` 恒 `closed` 有点异常；**saga 的空列表在任何正常系统里都合法**

**关键对照 —— 本仓已有正确做法**（`server.mbt:3160`）：
```moonbit
"persisted": Json::boolean(store_ok && hb_backend == "sqlite")
```
**⇒ `heartbeat` 披露了降级，`saga` 三工具没沿用。**

### §3 面 2：`mcpcf_*` vs 主运行时 —— 共用真源 ✓（含一处抄本）

**7 工具的 handler 全部调同一个引擎**：
```
mcpcf_embed.mbt:218  e.publish(project_dir~, description~, created_by~, now=now_utc(), ns~)
mcpcf_embed.mbt:240  e.verify(...)
```
**⇒ 不是两面，是共用真源** ✓

**但辅助函数是抄的**（`mcpcf_embed.mbt:71-106` vs `server.mbt:458-483/599-610`）：

| mcpcf_embed | server | 关系 |
|---|---|---|
| `fist_civil_from_days` `:93` | `_civil_from_days` `:470` | **算法逐字相同**（仅函数名 + 一行风格差异） |
| `fist_pad2` `:83` | `_pad2` `:458` | 同 |
| `now_utc` `:71` | `now_default` `:599` | **7 行逐字相同**，仅末行调用的函数名不同 |

`diff` 实测（`_civil_from_days` vs `fist_civil_from_days`）：
```
1c1  < fn _civil_from_days(...)          > fn fist_civil_from_days(...)
11,12c11,12  < let y2 = ... (y2, m, d)   > (if m <= 2 {...}, m, d)
```
**⇒ 算法等价，但「Howard Hinnant 日期算法」有两份。**
**未报 bug**（现网等价、无生产分叉风险），**列建议**：`server.mbt` 那两个是无 `pub` 的私有函数，
`mcpcf_embed` 同包可见 ⇒ **直接调 `_civil_from_days` / `_pad2` 即可**，`fist_*` 三件可删。

### §4 面 3：`phi_accrual` + `phi_gate` —— 共用真源 ✓

```
$ grep -rn 'fn phi_accrual' src/ → 只有 engine_phi.mbt:102 一处实现
$ grep -rn 'phi_accrual(' 调用点 → ops_heal.mbt:225 / server.mbt:6406 / :6408
```
**⇒ 三处调用同一个函数，共用真源** ✓

`watchdog_tick` 的 `phi_gate=true` 走 `heal_stale_tasks_by_phi`（`:265`），
而后者 `:225` 调**同一个** `@engine.phi_accrual` ⇒ **不存在第二份 φ 实现**。

**⇒ 面 3 无 bug。**（`heal` 的 **stale 判定**抄两份是 R18 已记录的，与 φ 本身无关。）

### §5 面 4：`heartbeat` —— 不是 bug，是正确典范

**3 写全占位**（`write_heartbeat` / `write_heartbeat_interval` / `delete_heartbeat` → `Ok(())`），
**3 读全占位**（`read_heartbeat` → `("", "", "")` / `list_all_heartbeats` → `[]` / `list_heartbeat_intervals` → `[]`）。

**但它不在「假绿」之列**，三条理由：
1. **server 回执披露了降级**（`:3160` `persisted: store_ok && hb_backend=="sqlite"`）
2. **`heal` 有 BUG-119 兜底**：`list_all_heartbeats` 返回 `[]` ⇒ `last_seen_map` 为空 ⇒
   走 `stale_by_task_clock(updated_at, now_s, timeout_sec)` ⇒ **行为正确**
3. **`store.mbt` 的注释是承认式的**，且 `heartbeat_backend()` 让调用面看得见

**⇒ 这是「内存后端不做持久化」的正确形状：功能降级 + 回执可见 + 有兜底路径。**
**`BUG-441` 缺的正是这三条里的第 1 条（和 HEARTBEAT 的第 2 条）。**

---

## 分析

### 为什么这次按「形状」搜而不是按「面」搜

R17/R18 的教训：**按面挑是「猜哪里有问题」，按形状搜是「找已知缺陷的同族」。**
`BUG-439` 的形状是明确的：**`StoreBackend` 分发里，一个后端返回占位值，而占位值是合法值**。
⇒ 这个形状**可以在 3 条 grep 内枚举完**（52 个分发点 → 7 个占位 → 3 个未处理消费方）。

**对比：如果按你给的 10 个面扫，我至少要打开 `saga_*` / `mcpcf_*` / `loop_*` / `debate_*` /
`memory_*` / `evolve_*` / `supervisor_*` / `selfdrive_*` / `omega_*` / `phi_*` 十份实现。
而形状搜索只花了 1 次 grep 就定位到 `saga_*`。**

### 「占位返回值是合法值」是这个仓的一个**可枚举缺陷类**

**判定条件（三条全满足才是假绿）**：
1. 一个多后端接口，**一个后端返回占位值**
2. 占位值是**该类型的合法值**（`Ok(())` / `[]` / `None` / `""` / `0`）
3. **消费方无法从回执区分「降级」与「真空状态」**

**本仓实例与处置**：

| 接口 | 占位 | 回执披露？ | 兜底？ | 判定 |
|---|---|---|---|---|
| `cb_get`/`cb_save` | `None`/`Ok(())` | ❌ | ❌ | **`BUG-439`**（已修） |
| `saga_*` ×3 | `Ok(())`/`[]` | ❌ | ❌ | **`BUG-441`**（本单） |
| `heartbeat` ×6 | `("","","")`/`[]`/`Ok(())` | **✅** | **✅**（BUG-119） | **正确** |
| `sqlite_store()` | `None` | — | — | 正确（它就是「有没有 SQLite」的查询） |

**⇒ 3 个实例、1 个正确、2 个是 bug。这个类值得做成机械判据（见 §缺口）。**

---

## 缺口与风险

### 1. 未扫 `loop_*` / `debate_*` / `memory_*` / `evolve_*` / `supervisor_*` / `selfdrive_*` / `omega_*`

**理由**：形状搜索已覆盖「双后端占位」这一类；剩余 7 个面若藏 bug，属于**别的形状**
（如「各写一份不等价逻辑」），不是本单方法能覆盖的。
**⇒ 这是本单明确的未完成项，不是「扫过没问题」。**

### 2. `.fist-mbt/data/*.db` 里可能有 saga 表历史数据

`BUG-441` 的修复若选「内存后端真实实现」，需确认真实 SQLite 库里 `saga_actions` 表有没有数据
（判断该表是否被真实使用过）。**本轮未查库。**

### 3. `mcpcf_embed` 的 `now_utc` 抄本有**理论上的漂移风险**

`server.mbt:599-610` 的 `now_default` 带一条重要注释：
> 「`@env.now()` 返回 UInt64 毫秒；直接用 Int64 做整数运算，避免 `.to_int()` 对 UInt64 的 32 位截断
> （1790 亿级别毫秒被截成负值，导致 1969 时间戳）」

**`mcpcf_embed.mbt:71-81` 的 `now_utc` 逐字抄了这段，所以现在也正确。**
但**如果将来有人只修 `now_default`（比如适配新时间源），`now_utc` 不会跟着变** ⇒ 这是第二条 R17 `BUG-435` 式的手抄本。
**建议合并（同包可见，直接调 `_pad2`/`_civil_from_days`）。**

### 4. 未跑测试

`BUG-441` 全部来自**静态推演**（分发 → 占位 → 消费 → 回执字段）。
**没有实际执行**「内存后端调 `saga_register` + `saga_rollback`」。
**建议落地方**：补一格双后端锁（同组 (root, step, compensation) 喂两后端，断言条数相同），**现在会红**。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r19-two-faces-broad-scan-2.md` |
| `BUG-441` | `memory/bugs.md`（已写入，medium） |
| **建议后续** | ① `BUG-441` 修法（A：回执加 `persisted`，照抄 `server.mbt:3160`）② `mcpcf_embed` 三个 `fist_*` 辅助函数合并到 `server.mbt` 私有件 ③ **把「占位返回值是合法值」做成机械判据**（3 个实例已够标定）④ 扫剩余 7 个面 |
| **未做** | **未调 `bug_fix`** · **未改 `src/` `scripts/`** · **未跑测试**（7 文件在途） |
