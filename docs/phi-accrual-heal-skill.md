# SKILL: phi-accrual-heal — Phi Accrual 判活 × 心跳回滚 × 看门狗编排

> 形态：skill（本文档）｜MCP 工具 `phi_accrual` / `heal` / `watchdog_tick`
> 真源：`AGENTS.md` 三工具条目（参数名逐字对齐）＋ MCP 注册面 `src/server/server.mbt`
> 用途：给无人值守流水线一个「判活 → 回滚 → 编排」的看护闭环——`phi_accrual` 用概率式判活替代固定超时（Hayashibara 2004），`heal` 把心跳超时的活跃任务回滚为「已领取」，`watchdog_tick` 把两者串成定时任务的单入口编排（心跳超时回滚、无活跃续轮、冷启动发首任务）。三者协同：`phi_accrual` 判活 → `heal` 回滚 → `watchdog_tick` 编排。

## 何时用

- **心跳节奏不固定、固定超时会误杀（判活）**：任务的 heartbeat 间隔忽快忽慢时，写死一个 `timeout_sec` 要么误杀正常慢心跳、要么放过真死的执行者——`phi_accrual` 用间隔历史的 μ+σ 建模算怀疑度 φ，**心跳节奏越快、越久没来才值得怀疑**，把「判活」从一刀切变成概率式。
- **活跃任务卡死、需要人工/半自动回滚（回滚）**：任务停在「执行中/已领取」很久没心跳，`heal` 把心跳超时的活跃任务回滚为「已领取」让其可被重新认领；`namespace` 不传即扫全库，跨命名空间一次性清理。
- **定时任务要一把梭（编排）**：无人值守 / 定时唤醒场景，`watchdog_tick` 是**单入口**——心跳超时走 `heal` 回滚、无活跃任务自动续轮、冷启动时发布首任务；一次调用覆盖三种分支，不用自己判状态再分流。

## 怎么调

参数名 = MCP 注册面真名（`src/server/server.mbt`），逐字对齐 `AGENTS.md` 条目，不是杜撰。

### 判活（A）—— `phi_accrual`，Phi Accrual 概率式故障检测（R89，Hayashibara 2004）

| 工具 | 参数（真名） | 返回键 |
|---|---|---|
| `phi_accrual` | `intervals`（心跳间隔历史序列）、`elapsed`（距最近一次心跳的秒数）、`threshold`（可选，默认 8，原论文口径） | `{ verdict: insufficient/rejected/healthy/suspect, phi?, ... }` |

- 算法：按间隔历史在窗口内算均值 μ + 标准差 σ 建模，怀疑度 **φ = −log10(P(心跳晚于 `elapsed` 到达))**——替代固定 `timeout`：
  - `σ≈0` 回退**指数分布**；
  - `|z|≥3` 用**尾部渐近展开**保精度（极小概率尾部不欠精度）；
  - **φ ≥ `threshold`（默认 8）→ `suspect`，否则 `healthy`**。
- **verdict 四态**：`insufficient`（无间隔历史，给不出 φ）/ `rejected`（输入非法/越界被拒，不出 φ 读数）/ `healthy`（φ < threshold，判活）/ `suspect`（φ ≥ threshold，判死可疑）。
- **升级看护语义**：心跳节奏越快、越久没来才值得怀疑——高频心跳的执行者短暂无心跳不轻易判死，低频的执行者稍久没来反而更可疑。

### 回滚（B）—— `heal`，心跳超时回滚

| 工具 | 参数（真名） | 语义 |
|---|---|---|
| `heal` | `timeout_sec`（超时阈值，秒）、`namespace`（可选，缺省扫全库） | 把心跳超过 `timeout_sec` 的**活跃任务回滚为「已领取」**，使其可被重新认领；`namespace` 不传即扫全库 |

```
tools/call heal
  { "timeout_sec": 1800, "namespace": "pentad-r1" }   # 只清 pentad-r1
tools/call heal
  { "timeout_sec": 1800 }                             # 不传 namespace，扫全库
```

- 回滚目标态是「**已领取**」（非「待领取」）：任务回到可认领池但不重置其层级/依赖，供 `claim` 重新认领。
- **内存版、人工流程**：`heal` 是看门狗里最轻的一拍——只读心跳时间戳 + 回滚状态机，不做续轮/派单，那些交给 `watchdog_tick`。

### 编排（C）—— `watchdog_tick`，定时任务看门狗（单入口）

| 工具 | 参数（真名） | 语义 |
|---|---|---|
| `watchdog_tick` | `timeout_sec`（心跳超时阈值）、`namespace`（可选，显式传 ns 走无人值守面）、`cold_start`（冷启动开关：无活跃任务时发布首任务） | **单入口三分支**：①心跳超时 → 走 `heal` 回滚；②无活跃任务 → 自动续轮；③冷启动 → 发布首任务 |

```
tools/call watchdog_tick
  { "timeout_sec": 1800, "namespace": "pentad-r1" }              # 定时任务常规一拍
tools/call watchdog_tick
  { "timeout_sec": 1800, "cold_start": true }                    # 冷启动：无活跃任务发首任务
```

- **推荐仅用于定时任务**：`watchdog_tick` 是跨进程的 `heal` + 自动续轮编排，适合 cron / 定时唤醒，不适合在交互式会话里随手调。
- **无人值守面（显式传 `namespace`）**：回执附 `detail.ready_dispatch_preview`——复用 triage 给出「下一单可自动派发」候选（**纯读，不自动认领**）；`autodispatch=true` 时进一步调引擎层 `dispatch_next` 把顶部待领取任务按能力/负载自动认领给最佳执行者（`autodispatch_want` 可选，缺省自动从任务描述抽取能力；结果并入 `detail.autodispatch`，**默认关闭零回归**）。
- **`phi_gate=true`（R90）**：心跳超时判定改用 **Phi Accrual 概率式判活**——读持久化间隔历史 + `elapsed` 算 φ，**φ ≥ `phi_threshold` 才回滚**（把 (B) 的固定超时升级成 (A) 的概率判活）；**默认关闭零回归**（不传即走 (B) 的固定 `timeout_sec` 判死）。

## 已知边界

- **`phi_accrual` 是概率判活，不是「判死」**：φ 高只说明「这次心跳晚了比正常概率更低」，是**怀疑度**不是**裁决**——是否真回滚由 `heal` / `watchdog_tick` 的判死口径决定。`verdict=suspect` ≠ 已判死，别拿它直接 kill。
- **`verdict` 四态，`insufficient` 最常见于冷启动**：没有间隔历史（首次心跳 / 新任务）给不出 φ，回 `insufficient`——此时 (A) 帮不上忙，回落到 (B) 的固定 `timeout_sec` 判死。
- **`rejected` 不出 φ 读数**：`intervals` / `elapsed` 非法（如 `elapsed<=0`、间隔为负）时回 `rejected`，不尝试建模、不出怀疑度——调用方应先校正输入再调。
- **`threshold` 默认 8 是原论文口径**：φ≥8 对应「心跳晚到概率 ≈ 1e-8」，极保守——误判率极低但也意味着要「久到近乎不可能」才判 `suspect`；调低更快怀疑（更激进），调高更宽容（更保守）。
- **`heal` 回滚到「已领取」而非「待领取」**：回滚后的任务保留层级/依赖，回到可认领池；不是重置成全新任务。且是**内存版 + 人工流程**——只回滚、不续轮、不派单。
- **`namespace` 缺省语义不同**：`heal` 不传 `namespace` = **扫全库**；`watchdog_tick` 显式传 `namespace` 才进**无人值守面**（附 `ready_dispatch_preview` / 可选 `autodispatch`）——不传 ns 的 `watchdog_tick` 走常规拍，不触发那套派发预览。
- **`watchdog_tick` 默认关闭的开关都零回归**：`autodispatch`（默认 false，不自动认领，只给预览）、`phi_gate`（默认 false，走固定 `timeout_sec` 判死而非 φ 判活）、`cold_start`（默认不发布首任务）——不显式开启时行为与旧版完全一致。
- **`cold_start` 只在「无活跃任务」时发布首任务**：不是每次调用都发；已有活跃任务时这一分支不触发。
- 本次为**纯文档**：不编译 src、不跑 `moon test`。

## 三工具协同

三件正交、可串联，构成无人值守流水线的「判活 → 回滚 → 编排」看护闭环：

1. **`phi_accrual` 判活（读）**：把「心跳超时了吗」从固定 `timeout_sec` 一刀切，升级为按间隔历史 μ+σ 的概率怀疑度 φ——**只读不出手**，给 `watchdog_tick` 的 `phi_gate` 分支提供判活依据（φ ≥ `phi_threshold` 才该回滚）。
2. **`heal` 回滚（改）**：拿到判活结论后，把真超时的活跃任务回滚为「已领取」回到可认领池——**只回滚不出手续轮**，是看门狗里最小的一拍。
3. **`watchdog_tick` 编排（串）**：定时任务的单入口——心跳超时调 `heal` 回滚、无活跃任务自动续轮、冷启动发布首任务；开 `phi_gate` 时把 (1) 的 φ 判活接进超时判定，开 `autodispatch` 时把续轮的下一单按能力/负载自动认领。

**典型串法**：定时唤醒 → `watchdog_tick`（`phi_gate=true`）→ 对每个活跃任务 `phi_accrual` 判活（`intervals` + `elapsed` 出 φ）→ φ ≥ `phi_threshold` 者交 `heal` 回滚为「已领取」→ 无活跃任务则自动续轮 / `cold_start` 发首任务。与 `saga_rollback`（任务链失败收尾）互补：**看护族发现「谁卡死了」，Saga 族负责「链断了怎么收尾」**——前者管活的（判活/回滚/续轮），后者管断的（补偿/收敛）。

> 一句话：`phi_accrual` 告诉我「这个心跳还值不值得信」，`heal` 告诉我「卡死的怎么拉回可认领池」，`watchdog_tick` 把两者串成「定时唤醒一拍到底」——三件一起，无人值守流水线才不漏掉卡死、不放过续轮。
