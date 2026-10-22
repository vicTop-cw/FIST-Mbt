---
proposal_id: PROP-2026-10-22-002
title: fist-mbt 轻量化——深度复用 RX-MBT 依赖
status: 已定案
decided_by: human_steward
decided_at: 2026-10-22
decision: approved
decision_detail: |
  指挥官按 lead 建议定案，三点裁决：
  1. 顺序：A1 限速 → A2 轮询改事件 → A3 递归用 Itor → B1 熔断时钟复用。
  2. 熔断器**保留半开态**（closed/open/half-open + probe_limit 配额，BUG-34 修过不得丢），
     只把底层虚拟时钟/连续失败计数换 RX-MBT Clock；禁止整体替换。
  3. 归属：纳入 `rx-mbt-governance` 任务树作为**功能 F**，依赖功能 C（写入门禁）；
     轻量化必须写在写入门禁之后。
created: 2026-10-22
related_proposal: 2026-10-22-fist-dir-layout-governance-proposal.md
---

# 提案：fist-mbt 轻量化——深度复用 RX-MBT 依赖

> 指挥官原话（2026-10-22）：「rx-mbt 这个依赖目前用的太少了，很多可以直接用这个库解决，做到轻量化，你看看」
> 本提案承接 `PROP-2026-10-22-001`（双层目录治理）。**轻量化必须写在写入门禁（功能 C）之后**——门禁管住写入面，才敢放开手改跨模块代码。

---

## 一、为什么（背景）

fist-mbt 依赖 `vicTop-cw/RX-MBT@0.1.0`，但**全仓仅 1 处使用**——`src/ops/ops_commissar.mbt:197` 的 `@rx.Observer::new`（政委常驻 watch）。其余 Rx 能力（熔断、限速、节流、防抖、事件触发、可控制迭代器）全部**手搓**，导致：

1. **代码冗余**：同样语义重复实现多份（熔断器 516 行、限速核心数百行、轮询循环近千行）。
2. **维护成本**：每个手搓组件都要自己写测试、修 bug、保持与 Rx 语义一致。
3. **轻量化目标未达成**：依赖已引入却只用 1/10，浪费。

RX-MBT 是**完整 RxJS 式库**（Observable/Observer/Subject/Clock/TriggerRegistry/Itor/Node），自带熔断器、退避重试、限速、节流、防抖、事件触发——正是 fist-mbt 手搓的那批。

---

## 二、现状审计（手搓 vs RX-MBT 现成）

| # | fist-mbt 手搓的 | 代码量 | RX-MBT 现成 API | 语义一致度 |
|---|---|---|---|---|
| 1 | 熔断器 R104（`engine_circuit.mbt`） | 280 行 + 236 测试 = **516** | `circuit_breaker(max_failures, reset_ms)` | ⚠️ 半一致 |
| 2 | 模型路由限速（`model_router.mbt` 5h 滚动窗口） | 1161 行（+state 280 + caf 305） | `rate_limit(ms)` / `throttle(ms)` / `debounce(ms)` | ✅ 一致 |
| 3 | 心跳/看门狗/heal 轮询 | 998 行（heal 261 + heartbeat 83 + watchdog 654） | `interval(ms)` / `timer(ms)` / `TriggerRegistry` | ✅ 一致 |
| 4 | 状态管理（project_health/status 散在 `server.mbt` 8100 行） | 散落 | `BehaviorSubject` / `Subject` | ⚠️ 中 |
| 5 | 递归拆解 task_plan_deep（手搓递归） | 手搓 | `Itor.send / send_value / restart / history_len` | ✅ 一致 |

**全仓手搓量估 3000+ 行**，与 RX-MBT 高度重叠。

---

## 三、三档分类（决定换不换）

### ✅ A 档·干净换库（收益高、风险低、语义一致）

| 目标 | 换法 | 省码 | 公共 API |
|---|---|---|---|
| **A1 限速换库** | `model_router` 的 5h 滚动窗口限速段，改用 `rate_limit`/`throttle` 驱动计数 | ~300-500 行 | 无变化（`model_route` 签名不动） |
| **A2 轮询改事件** | `ops_watchdog`/`ops_heal`/`ops_heartbeat` 的轮询循环，改用 `interval` 定时 + `TriggerRegistry` 事件分发 | ~300-500 行 | 无变化 |
| **A3 递归拆解用 Itor** | `task_plan_deep` 的递归展开改用 `Itor.send_value`（紧急插队）+ `restart`（重放）| ~100-200 行 | 无变化 |

### ⚠️ B 档·半替换（保留 fist-mbt 特性，底层换 RX-MBT）

| 目标 | 换法 | 保留 | 省码 |
|---|---|---|---|
| **B1 熔断器时钟复用** | fist-mbt 熔断器本体**保留三态 closed/open/half-open + 探测配额**（BUG-34 修过，不能丢），但**底层虚拟时钟/连续失败计数改由 RX-MBT `Clock` + `circuit_breaker_on` 驱动** | 三态状态机 + `probe_limit` 半开配额 | ~100-150 行 |

### ❌ C 档·不换（RX-MBT 没有或语义不合）

- **Saga 补偿（R92/R96）**：LIFO 补偿序列 + 最小切片，RX-MBT 无对应。
- **Phi Accrual 故障检测（R89）**：按心跳间隔历史算 φ 值，非 Rx 范畴。
- **多命名空间 SQLite 存储**：持久化层，Rx 管不到。
- **门禁/守卫体系**：确定性硬门，不该被 Rx 抽象化。

---

## 四、分阶段设计（依赖顺序）

> 顺序遵守 `PROP-2026-10-22-001`：**先写入门禁（功能 C）→ 再轻量化**。每阶段独立可验收、可回退。

### 阶段 1：A1 限速换库

**范围**：`src/router/model_router.mbt` 的限速/窗口计数段。**不动** `star_gate`（独立门）、`router_state.mbt` 的持久化格式（跨进程复现依赖它）。

**改动**：
1. 引入 `@rx.Observable::interval` 作为 5h 窗口的虚拟时钟源（替代手搓 `window_start` + elapsed 计算）。
2. 用 `@rx.Observable::rate_limit`/`throttle` 语义替换「`used >= threshold_pct` → 切换付费池」的判断节奏。
3. `model_router_ops.mbt` 的 MCP 接口层**零改动**——内部接线换 Rx。

**验收**：`moon test --target js` 全绿；`model_route`/`model_router_status` 白盒锁（`mo_1~10`、`rt_1~15`、`rs_1~6`）全部保持；`star_gate` 默认未启用零回归（`mo_10` 锁）。

### 阶段 2：A2 轮询改事件

**范围**：`src/ops/ops_watchdog.mbt`（654）、`ops_heal.mbt`（261）、`ops_heartbeat.mbt`（83）的轮询循环。

**改动**：
1. 用 `@rx.Observable::interval(timeout_sec*1000)` 替代 `while` 轮询 + `sleep`。
2. 心跳/超时事件用 `@rx.Subject[HeartbeatEvent]` 多播，heal/watchdog 订阅响应（替代手搓回调链）。
3. `TriggerRegistry` 承载「任务状态变更 → 触发 heal 检查」的事件分发，替代硬编码 if-else 链。

**验收**：`ops_watchdog_test`/`ops_heal_wbtest`/`ops_heartbeat` 全部保持；无人值守流水线（`watchdog_tick` + `phi_gate`）行为不变。

### 阶段 3：B1 熔断器时钟复用（半替换）

**范围**：`src/engine/engine_circuit.mbt` 的时钟/计数段。

**保留**（不能动）：closed/open/half-open **三态状态机**、`probe_limit` **半开探测配额**、`persist_error` 落库失败回执（BUG-230）、时间戳服务端盖章（BUG-33，不接受调用方注入 now）。

**改动**：
1. 用 `@rx.Clock` + `@rx.Observable::circuit_breaker_on` 驱动**连续失败计数与熔断定时**，替代手搓的 `window_start` + 失败列表扫描。
2. 三态迁移逻辑保留在 `engine_circuit.mbt`，但底层时序判断交给 RX-MBT 时钟。

**验收**：`circuit_fail`/`circuit_succeed`/`circuit_status` MCP 工具签名与回执字段**逐字不变**；`persist_error` 在写盘失败时仍非空；`probe_limit` 配额耗尽仍 `allow_call=false`。

### 阶段 4：A3 递归拆解用 Itor

**范围**：`task_plan_deep`（AO 式递归拆解）的展开/切片逻辑。

**改动**：
1. 用 `@rx.Itor::send_value`（紧急插队）实现「更简单变体 → 先易后逆推」的 LADDER 插队，替代手搓的优先队列。
2. 用 `@rx.Itor::restart` + `history_len` 实现梯度重放，替代手搓的递归回溯。
3. `gradient=true` / `gradient_dag=true` 行为**逐项保持**。

**验收**：`task_plan_deep` 白盒锁全绿；`boundary_probe=true` 的「边界审视叶」追加逻辑不变；`reinject_context` 回注逻辑不变。

---

## 五、验收清单（全绿才收口）

- [ ] `moon fmt --check` = 0（本仓硬门）
- [ ] `moon test --target js` = **1358/1358**（或 `--update` 后新基线，且 diff 逐项审）
- [ ] `model_route`/`model_router_status`/`circuit_*`/`task_plan_deep` 等公共工具**签名与回执字段零变化**
- [ ] 写入门禁（功能 C）**已上线且生效**——所有轻量化改动落在目标项目 `.fist-mbt/`+`fist-mbt/` 内
- [ ] `check_tools_sync`（工具数=155 注册点）不变
- [ ] `check_test_sync` 不变
- [ ] 双守卫 `check_fist_layout` / `check_plan_location` 通过
- [ ] 无新增第三方依赖（RX-MBT 已在 moon.mod）
- [ ] 回滚预案：每阶段独立 commit，可单独 revert

---

## 六、风险与边界

1. **回归风险**：1358 测试 + 72 轮迭代积累的稳定态。**必须增量推进**（A1 → A2 → A3 → B1），每阶段全绿再进下一阶段。
2. **语义漂移**：RX-MBT `circuit_breaker` **无半开态**，直接替换会丢 BUG-34 修的能力 → **必须走 B1 半替换**，禁止整体删 `engine_circuit.mbt`。
3. **虚拟时钟注入**：所有换库点测试必须能 `advance_time` 推进，不能依赖真实 sleep（否则测试变慢且 flaky）。
4. **persist_error 通道**：熔断器换库时，状态写盘失败仍须回执非空 `persist_error`（BUG-230），不许静默吞。
5. **时间戳盖章**：`now` 参数一律服务端盖章（BUG-33），换库后调用面仍无 `now` 参数。
6. **跨模块依赖**：A1 动 `src/router`、A2 动 `src/ops`、B1 动 `src/engine`、A3 动 `task_plan_deep`——**四个独立 scope**，不可合并 commit，便于回退。
7. **不做的事**：不重构 `src/store`（SQLite 持久化）、不重构 `star_gate`、不引入 Rx 抽象到门禁/守卫。

---

## 七、不做什么（明确排除）

- ❌ 不整体替换熔断器（丢半开态）
- ❌ 不改任何 MCP 工具的公共签名/回执字段
- ❌ 不新增依赖（RX-MBT 已有）
- ❌ 不动 `src/store` 持久化层
- ❌ 不动门禁/守卫的确定性硬门
- ❌ 不为了"换库"而降低 1358 测试通过率

---

## 八、决策请求

请指挥官定案以下 3 点：

1. **是否按 A1→A2→A3→B1 顺序推进**（先限速/轮询/递归，熔断器时钟最后）？
2. **熔断器是否保留半开态**？（我倾向**保留**——BUG-34 修过，只换底层时钟）
3. **是否纳入 `rx-mbt-governance` 任务树作为功能 F**（依赖功能 C 写入门禁）？还是独立命名空间？

定案后本提案状态改 `已定案`，写进 `fist-mbt/plans/decisions/`。