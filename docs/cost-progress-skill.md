# SKILL: cost-progress — 预算告警 × 预算切分 × 进度门控

> 形态：skill（本文档）｜MCP 工具 `cost_budget_check` / `cost_budget_split` / `progress_gate`
> 真源：`AGENTS.md` 三工具条目（参数名逐字对齐）＋ MCP 注册面 `src/server/server.mbt`
> 用途：给无人值守流水线一个「预算三视图」的在线体检闭环——`cost_budget_check` 做超限时的一票否决告警，`cost_budget_split` 把总预算按依赖图阶段切分出每阶段份额，`progress_gate` 按已消耗预算与完成进度做双路径剩余成本预测并给路由决策。三者协同：`cost_budget_check` 告警 → `cost_budget_split` 切分 → `progress_gate` 路由。

## 何时用

- **预算快见底、要一个明确的「继续/停手」信号（告警）**：当前消耗已经接近或超过预算上限，`cost_budget_check` 传入 `limit` 与 `current` 直接回 `{exceeded, remaining, action}`——`exceeded` 告诉你越没越线、`remaining` 给剩余（超支时为负数，超支额可见）、`action` 给下一步建议动作，是一票否决的轻量告警位。
- **拿到一笔总预算、要按依赖图阶段分配给谁（切分）**：根任务下拆好了 DAG 子树，总预算只有一份，`cost_budget_split` 按任务 DAG 阶段（slack 分析 earliest 层级）切分——每阶段份额 = 阶段难度权重（难3/中2/易1）占总量比例 × 总预算（余数补最大权重阶段），瓶颈阶段占额一眼可见；`task_id` / `namespace` 两个作用域参数限定切分范围，回执 `scope` 自证切了哪些任务。
- **执行途中、要判断「剩的钱还够不够跑完这棵树」（路由）**：任务子树执行到一半，`progress_gate` 按已消耗预算（`spent` 手动注入或按难度权重自动估算）与完成进度（已完成+已归档 / 子树任务数）做**双路径剩余成本预测**（线性 = 燃尽率 × 剩余工作量、保守 = 1.2 × 线性），元门控给三态决策：`OK`（预算充足继续）/ `CAUTION`（线性可行但缓冲不足，建议降档缩范围）/ `ESCALATE`（线性已超支，建议追加预算或暂停）。

## 怎么调

参数名 = MCP 注册面真名（`src/server/server.mbt`），逐字对齐 `AGENTS.md` 条目，不是杜撰。

### 告警（A）—— `cost_budget_check`，预算超限告警

| 工具 | 参数（真名） | 返回键 |
|---|---|---|
| `cost_budget_check` | `limit`（预算上限，必填）、`current`（当前消耗，必填） | `{ exceeded, remaining, action }` |

```
tools/call cost_budget_check
  { "limit": 100, "current": 80 }     # 未越线：exceeded=false，remaining=20
tools/call cost_budget_check
  { "limit": 100, "current": 150 }    # 已越线：exceeded=true，remaining=-50（超支额可见）
```

- **纯计算、零副作用**：只算 `current - limit` 与剩余，不写库不派单，适合高频心跳式轮询。
- **`remaining` 超支时为负**：不做「抹成 0」处理，超支额直接可见（BUG-181 口径）。
- **`limit<=0` 是非法预算，不是「已超支」**：回 `valid=false` 之类的拒绝语义，不报误导性 `action`（BUG-181② 口径）。

### 切分（B）—— `cost_budget_split`，预算按依赖图阶段切分

| 工具 | 参数（真名） | 语义 |
|---|---|---|
| `cost_budget_split` | `budget`（总预算，必填，**必须为正**：负数/0 直接 `rejected`）、`task_id`（可选：只按该任务子树切分）、`namespace`（可选：不给 `task_id` 时按该 ns 切分） | 按任务 DAG 阶段（slack earliest 层级）切分，每阶段份额 = 阶段难度权重（难3/中2/易1）占总量比例 × 总预算（余数补最大权重阶段） |

```
tools/call cost_budget_split
  { "budget": 100 }                                # 全库切分（scope_kind=whole-store）
tools/call cost_budget_split
  { "budget": 100, "task_id": "T0" }               # 只按 T0 子树切分
tools/call cost_budget_split
  { "budget": 100, "namespace": "pentad-r1" }      # 只按 pentad-r1 ns 切分
```

- **返回体**：`{ verdict: ok|rejected|insufficient, stages:[{level,tasks,difficulty_sum,share}], total_budget, makespan, scope:{root_task_id,namespace,scoped_task_count,scope_kind}, note }`——`stages` 每项带阶段层级 `level`、该阶段任务数 `tasks`、难度权重和 `difficulty_sum` 与切到的份额 `share`；`total_budget` 回显总预算、`makespan` 给关键路径长度。
- **`budget` 必须为正**：负数/0 直接 `rejected` 不产份额（过去 -50 会切出 -42/-5/-2 的负份额，已修）。
- **作用域参数真参与取数**：`task_id` / `namespace` 过去传了也不生效、恒扫全库（BUG-20：某轮 7 个任务的子树被报成全库数），现在真的参与取数，且切了哪些任务写在 `scope` 里自证；两个都不传 = 全库（旧行为零回归）。

### 路由（C）—— `progress_gate`，进度预算路由门控

| 工具 | 参数（真名） | 语义 |
|---|---|---|
| `progress_gate` | `task_id`（必填，根任务 id）、`budget`（总预算，必填）、`spent`（可选，手动注入已消耗，缺省按难度权重自动估算） | 对任务子树做双路径剩余成本预测（线性 = 燃尽率 × 剩余工作量、保守 = 1.2 × 线性），元门控给决策 `OK` / `CAUTION` / `ESCALATE` |

```
tools/call progress_gate
  { "task_id": "P", "budget": 10 }                          # spent 缺省：按难度权重自动估算
tools/call progress_gate
  { "task_id": "P", "budget": 10, "spent": 3 }              # 手动注入真实消耗（如 token 统计）
```

- **返回体**：`{ ok, task_id, budget, spent, remaining, progress, burn_rate, projection:{linear, conservative}, verdict, action, basis }`——`projection` 双路径预测（线性/保守），`verdict` 给门控决策，`basis` 给判定依据。
- **`verdict` 三态**：`OK`（线性与保守均在剩余预算内，预算充足继续）/ `CAUTION`（线性可行但保守缓冲不足，建议降档缩范围）/ `ESCALATE`（线性已超支，建议追加预算或暂停）。
- **非法预算整笔拒绝**：`budget<=0` 回 `ok=false` + `verdict=rejected`，不尝试预测（负预算回显实收值，不被抹成 0）。
- **边界口径**：进度 0% 但已有消耗 → 燃尽率不可计算，`burn_rate=-1.0` 判 `ESCALATE` 不静默归零判 `OK`（BUG-165）；已完成但已超支 → `ESCALATE` 而非 `OK`（BUG-169）。

## 已知边界

- **三件都是纯计算、零副作用**：`cost_budget_check` / `cost_budget_split` / `progress_gate` 都不写库、不派单、不改任务状态——`action` / `verdict` 是**决策建议**，执行权在调用方；别把门控回执当已执行动作。
- **`cost_budget_check` 只看两个数，不懂 DAG**：它不读任务库，`limit` / `current` 都得调用方自己带——「当前消耗」从哪算（`cost_stats`、`progress_gate` 的 `spent`、外部账单）是你的事，工具只算越线与否。
- **`cost_budget_split` 的份额是「难度权重比例」，不是「工作量预测」**：份额按 难3/中2/易1 的权重占比切，阶段真烧多少还取决于执行效率——它是**预算分配**不是**完工预测**，完工预测找 `progress_gate` / `dag_mc`。
- **`cost_budget_split` 两个作用域参数语义不同**：`task_id` = 按该任务子树切分；`namespace` = 不给 `task_id` 时按该 ns 切分；两个都不传 = 全库（`scope_kind=whole-store`）。`budget<=0` 整笔 `rejected`。
- **`progress_gate` 的 `spent` 缺省是「按难度权重自动估算」**：不传 `spent` 时已消耗 = 已开工任务难度权重和——估算口径偏粗，要拿真实 token/成本统计喂它就显式传 `spent`。
- **`progress_gate` 的保守路径 = 1.2 × 线性，是固定系数**：不是按历史方差算的置信区间；`CAUTION` 的含义就是「线性够、保守不够」，缓冲系数 1.2 本身不可调。
- **`progress_gate` 看的是「子树」不是「全局」**：它只算 `task_id` 子树内的进度与消耗，跨子树的总账要用 `cost_budget_check` 自己汇总。
- 本次为**纯文档**：不编译 src、不跑 `moon test`。

## 三工具协同

三件正交、各占预算生命周期的一个截面，构成「预算三视图」的在线体检闭环：

1. **`cost_budget_check` 告警（总量面）**：只问一件事——`current` 超没超 `limit`？越线即 `exceeded=true` 给 `action`，是**最粗粒度的一票否决位**，适合高频轮询（心跳拍、成本快照后随手一问），零参数成本。
2. **`cost_budget_split` 切分（分配面）**：预算还没花或刚开始花时，回答「这笔总预算按依赖图各阶段该怎么分」——份额按难度权重比例切，瓶颈阶段占额可见，`task_id` / `namespace` 限定作用域，`scope` 自证切了哪些任务；它是**事前分配**，给执行者/调度器一份可问责的预算账。
3. **`progress_gate` 路由（进度面）**：执行途中，回答「按现在的烧钱速度和完成进度，剩的钱够不够跑完这棵树」——双路径预测（线性/保守）+ 三态门控（`OK` 继续 / `CAUTION` 降档缩范围 / `ESCALATE` 追加预算或暂停），是**事中路由**，每拍执行完都可重跑。

**典型串法**：开局 → `cost_budget_split(budget, task_id=根)` 给各阶段切份额（分配账）→ 执行途中每拍 `progress_gate(task_id=根, budget, spent=真实消耗)` 做双路径体检（`OK` 继续、`CAUTION` 降档缩范围、`ESCALATE` 追加预算或暂停）→ 任意时刻 `cost_budget_check(limit, current)` 做总量一票否决（越线即停）。三者合起来：`check` 管「越没越线」，`split` 管「钱怎么分」，`gate` 管「按这个速度还能不能跑完」——预算×进度在线体检，先预警后决策。

> 一句话：`cost_budget_check` 告诉我「这单还许不许做」，`cost_budget_split` 告诉我「这笔钱各阶段分多少」，`progress_gate` 告诉我「按现在的烧法能不能跑完」——三件一起，无人值守流水线才不超支、不盲跑、不停摆。
