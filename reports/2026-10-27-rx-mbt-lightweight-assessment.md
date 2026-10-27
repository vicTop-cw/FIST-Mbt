# `rx-mbt-lightweight` 计划评估：4 个项目现在还需要做吗？

> **提案**：`docs/plans/2026-10-22-rx-mbt-lightweight-proposal.md`（PROP-2026-10-22-002，**status: 已定案 / approved**）
> **执行人**：司令-γ · **边界**：只读 + 报告（未改 `src/` `scripts/` `docs/`）
> **核心问题**：Alpha R19 报「0/4 全部未实现」——**本文核的是「还需要做吗」**

---

## 结论

| 项目 | 当前状态 | 还需要做吗 | 理由（一句话） |
|---|---|---|---|
| **A1** 限速换库 | `window_seconds:18000` + `window_reset_check` **已实现且工作** | **❌ 不需要** | 提案假设的收益是「省 300-500 行」，实际 `model_router.mbt` 是 **1188 行且已稳定**；换库**不产生行为改善**，纯重构风险 |
| **A2** 轮询改事件 | **没有常驻轮询循环**（`watchdog_tick` 是「一拍」式，外部定时器触发） | **❌ 不需要** | 提案写的「`while` 轮询 + `sleep`」**在当前代码里不存在** ⇒ **提案描述的病灶已经自然消失了** |
| **A3** 递归用 Itor | `plan_deep` 已实现，**非手搓递归** | **❌ 不需要** | 提案说「手搓递归」，实测是**逐层展开的显式循环**——Itor 能提供的「插队/重放」语义 `plan_deep` 不需要 |
| **B1** 熔断时钟复用 | **`engine_circuit.mbt` 已修过 `BUG-439`**（内存后端实读） | **❌ 不需要（且有反例支撑）** | 熔断器现在的时钟语义是「服务端盖章 `now_secs`」（BUG-33 政策），**换 RX `Clock` 会与「调用面不许注入 now」政策冲突** |

**⇒ 4 个项目：0 个仍然需要做。提案整体过时。**

**⚠️ 但「过时」不等于「当时的判断错了」** —— 提案是 2026-10-22 的，5 天后代码已经变过 5 轮
（`BUG-435/438/439/441` 全在这条线上）。**详见 §分析。**

---

## 证据

### §0 前置：rx-mbt 的版本与 API 仍然可用（先排除「依赖失效」这个可能）

```
$ grep -n 'RX-MBT' moon.mod
34:  "vicTop-cw/RX-MBT@0.3.0"          ← 提案写的是 @0.1.0，**已升到 0.3.0**
```
**⚠️ 我第一次查错了目录**（`src/` 不存在，包实际在 `rx/`），差点误报「8 个 API 全部消失」。
**修正后的实测**（`.mooncakes/vicTop-cw/RX-MBT/rx/`，42 个 `.mbt`）：

```
rate_limit        → 6 处      interval         → 7 处
throttle          → 11 处     TriggerRegistry  → 43 处
debounce          → 8 处      Itor             → 326 处
Clock             → 30 处     circuit_breaker  → 6 处
```
**⇒ 提案点名的 8 个 API 在 0.3.0 里全部存在。** 所以「不需要做」**不是因为依赖没了**，
而是因为**收益消失了**。

### §1 A1 限速换库 —— 不需要

**当前实现**：
```
src/router/model_router.mbt:421   window_seconds: 18000        ← 5 小时窗口，已经是需要的值
src/router/model_router.mbt:727   pub fn ModelRouter::window_reset_check(...)   ← 窗口滚动已实现
src/router/model_router.mbt:110   let r = self.limit - self.used
src/router/model_router.mbt:124   self.used.to_double() * 100.0 / self.limit.to_double()
```
**⇒ 5h 滚动窗口 + 阈值判定 + 窗口复位，三件都在，且被 `rt_1~15` / `rs_1~6` / `mo_1~10` 共 31 条白盒锁覆盖。**

**提案假设的收益实测不成立**：
| 提案说 | 实测 |
|---|---|
| 限速核心「数百行」，可换库省 **300-500 行** | `model_router.mbt` **1188 行**，其中「限速/窗口」段是 `used`/`window_start`/`window_reset_check` 一族，**远不足 300 行**（其余是池定义、游标、CAF、Star 门） |
| `rate_limit`/`throttle` 语义「✅ 一致」 | `rate_limit(ms)` 是**时间窗内限次**；`model_route` 要的是**累计用量百分比 + 达阈值切池 + 池间回退**。**不是同一个语义** |

**⇒ 换库的关键风险**：`model_route` 的正确性依赖**跨进程持久化的 `window_start`**
（`memory/model-router-{ns}.json`）。
RX-MBT 的 `rate_limit` 是**进程内 Observable 算子**，**没有「读回上次窗口起点」的能力** ⇒
换成它等于**丢掉跨进程复现**（`BUG-62` 修过的「只问不消耗」语义会跟着碎）。

### §2 A2 轮询改事件 —— 不需要（**病灶已不存在**）

**提案描述**：
> 「用 `@rx.Observable::interval(timeout_sec*1000)` 替代 **`while` 轮询 + `sleep`**」

**实测**：
```
$ grep -rn 'TriggerRegistry|Observable::interval|Subject' src/  → 空（确实没用 Rx）
$ grep -nE 'while |sleep' src/ops/ops_watchdog.mbt src/ops/ops_heal.mbt src/ops/ops_heartbeat.mbt
  → **没有一个 while 循环，没有一处 sleep**
$ 实际循环全是 for-in 遍历集合：
  ops_watchdog.mbt:96   for n in names
  ops_watchdog.mbt:140  for row in engine.store_list_heartbeats()
  ops_watchdog.mbt:303  for t in tasks
```
**⇒ 提案要替换的东西（`while` 轮询 + `sleep`）在当前代码里根本不存在。**

**为什么不存在**：`watchdog_tick` 的模型是 **「一拍」** ——
外部（cron / 定时任务 / 人）调一次，它扫一遍、做决策、返回。
**没有常驻循环 ⇒ 没有轮询可改 ⇒ 没有 `sleep` 可除。**

**⇒ A2 是「提案对当前架构的描述已经过时」，不是「实现缺失」。**

**（唯一残留的相关点）**：`watchdog_tick` 单拍内做**全库扫描**（`list_in_ns` + `store_list_heartbeats`），
任务多时有 O(N) 成本。**但改成事件驱动需要「常驻订阅者」，而这与「一拍即退的 MCP 工具」模型冲突** ——
不是换库能解决的，是架构选择。

### §3 A3 递归用 Itor —— 不需要

**提案说**：「`task_plan_deep` 的递归展开改用 `Itor.send_value`（紧急插队）+ `restart`（重放）」

**实测**：`plan_deep` 在 `engine.mbt:1267`，展开是**逐层显式循环**：
每层对父任务调 `plan(split_n)`，把子任务收集后**按 `gradient_dag` 决定是否再下钻**。
**不是递归函数调用，也不是需要「插队/重放」的数据流。**

**Itor 能提供的两个语义，`plan_deep` 都不需要**：
| Itor 语义 | `plan_deep` 是否需要 |
|---|---|
| `send_value` 紧急插队 | ❌ 不需要 —— 拆解是**预先算完整棵树**再落库，没有「边产边消费」 |
| `restart` 重放 + `history_len` | ❌ 不需要 —— 梯度重放已由 `gradient_dag` 的 `depends_on` 表达（**DAG 边，不是重放**） |

**⇒ A3 是「为了用库而用库」**：换上去会**增加一层间接**，而 `gradient_dag` 的语义
（「更难切片依赖更简单切片」）**本来就是 DAG 前置边**，不是迭代器能更好表达的。

### §4 B1 熔断时钟复用 —— 不需要，**而且有一个明确的反例**

**提案**：「底层虚拟时钟/连续失败计数改由 RX-MBT `Clock` + `circuit_breaker_on` 驱动」

**实测当前实现**（`engine_circuit.mbt:280 行`）：
```moonbit
pub fn ...circuit_fail(..., now_secs~ : Int32, ...)      // ← 时间从**参数**传入
  let nf = if now_secs - last_fail_ts > w { 1 } else { failures + 1 }
```
**⇒ 熔断器的时钟是「调用方传入 `now_secs`」，而 `now_secs` 由 server 用 `now_default()` 盖章**
（`BUG-33` 政策：**时间戳一律服务端盖章，调用面无 `now` 参数**）。

**⇒ 换成 `@rx.Clock` 会与这条政策直接冲突**：Rx `Clock` 是**可注入/可推进的虚拟时钟**
（提案 §六.3 自己写：「所有换库点测试必须能 `advance_time` 推进」）——
**而「可注入时间」正是 BUG-33 要禁止的东西**（它会让人能伪造 `now` 绕过窗口判定）。

**⚠️ 更强的一条**：熔断器**本周刚修过** `BUG-439`（内存后端 `cb_get` 恒 `None` ⇒ 永不熔断）。
**在一次刚修完缺陷的模块上做「换底层时钟」的重构，是最差时机。**

---

## 分析：为什么 4 个项目全部过时

### 三条具体原因（不是「提案写得差」）

**① 提案的代码量估算是「手搓总量」，不是「可换段的量」**
提案 §二 表格列的是「熔断器 516 行 / 限速 1161 行 / 轮询 998 行」——
**这些是文件总行数**，而可换的只是其中**窗口计数 / 状态迁移 / 循环外壳**那几十行。
**⇒ 收益被高估约 5-10 倍。**

**② 提案假设的病灶有两个已经自然消失**
- A2 的「`while` 轮询 + `sleep`」→ **架构后来改成「一拍」式，病灶没了**
- A1 的「手搓 5h 窗口」→ **`window_seconds:18000` + `window_reset_check` 已完整**

**③ 5 天里这条线上修了 5 个 bug，每个都强化了「别动这里」的理由**
| BUG | 内容 | 对换库的影响 |
|---|---|---|
| `BUG-435` | `constraint.mbt` 手抄 `rsv_action` | 说明**本仓的「抄本」问题靠收拢解决，不靠换库** |
| `BUG-438` | `locks_upsert` 两后端语义相反 | 两后端问题与 Rx 无关 |
| `BUG-439` | 熔断器内存后端占位 ⇒ **永不熔断** | **刚修的模块，最不该重构** |
| `BUG-441` | saga 内存后端占位 | 同上 |

### 「过时」的正确处置不是「删提案」

提案**status: 已定案 / approved**，有 `decisions/002` 记录。
**⇒ 它不该被删，应该被「结项」**：在提案里追加一段「结项说明：4 项在当前代码库下收益不成立，
不再执行」，并把状态改为已完成（或新增 `已结项` 终态）。

**为什么不能只是「不管它」**：`docs/plans/README.md` 的硬规则要求终态进 `archived/`，
而**一个「已定案但永不做」的提案留在 `plans/` 根**，会让下一个读计划库的人
**误以为还有 4 项待做** —— 这正是 Alpha R19 得出「0/4 未实现」结论的原因。

---

## 缺口与风险

### 1. **本评估只核了「要不要做」，没核「换库是否技术可行」**

如果将来某个理由让 A1/A2/A3/B1 重新变得值得（比如 `rx-mbt` 提供了**跨进程持久化的 `rate_limit`**），
**本报告不构成「换库会失败」的结论**。我只证明了**收益不存在**，没证明**换不成**。

### 2. `rx-mbt` 已从 0.1.0 升到 0.3.0，提案里的 API 语义**未逐条核**（只核了存在性）

`Itor` 326 处、`TriggerRegistry` 43 处说明 API 都在，但**0.3.0 的语义是否与 0.1.0 相同，本轮未查**。

### 3. `@rx.` 使用仍是 **1 处**（`ops_commissar.mbt:197`），与提案时相同

**⇒ 5 天来零推进。** 这本身是「提案未能推进」的证据，但**不构成「应当推进」的理由**。

### 4. 本报告**未跑测试**

所有读数来自 `grep` + 读实现。**「不需要做」的判断是设计判断，不需要动态验证**，
但 §2 的「没有 `while` 循环」若在某个我没扫到的文件里存在，结论需修正
（我扫了 `ops_watchdog.mbt` / `ops_heal.mbt` / `ops_heartbeat.mbt` 三个提案点名的文件，共 997 行）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-rx-mbt-lightweight-assessment.md` |
| **建议动作** | 在 `docs/plans/2026-10-22-rx-mbt-lightweight-proposal.md` 追加「结项说明」（4 项收益不成立），状态改为已完成/已结项，**移到 `archived/`** |
| **不建议** | 删除提案（它记录了 5 天前的真实判断，且 `decisions/002` 依赖它） |
| **未做** | **未改任何文件**（只读边界）· **未跑测试** |

**⚠️ 一句话回答用户目标里的那个问题**：
**「这 4 个项目里，有几个在当前代码库下仍然需要做？」——答案是 0 个。
不是「没时间做」，是「做了不会更好」。**
