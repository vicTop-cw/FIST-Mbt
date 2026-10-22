# 执行者能力路由 Skill（executor_register / executor_route / executor_auction / executor_clear / selfdrive_dispatch）

> 一源四态 cl3 补齐 · 9/10。真源 = `AGENTS.md`「Marketplace·执行者能力路由」段 + `src/executor/` + `src/ops/dispatch.mbt`。本组 5 工具构成 **执行者 Marketplace** 从「能力登记 → 路由推荐 → 竞拍 → 自动派单 → 整洁」的闭环：把"任务该派给谁"从 agent 自选升级为**按能力 + 历史信任 + 负载**的确定性分派。

## 何时用

| 场景 | 用哪个 | 为什么 |
|---|---|---|
| 我要**登记**一个执行者的能力标签（如 `[编排,json]`） | `executor_register` | 持久化到 store，跨进程可复现 |
| 我要**推荐**某个任务该派给哪个已注册执行者 | `executor_route` | 按能力覆盖率 desc → 历史信任 desc → 负载 asc 排序 |
| 我要**竞拍**出最优执行者（带置信度校准，防胜者诅咒） | `executor_auction` | 每个执行者对 need 出价，校准系数折扣过度自信者 |
| 我要**清空**全部执行者能力注册（测试残留清理） | `executor_clear` | 重置 Marketplace，防测试数据污染 |
| 我要**自动派单**（无人值守 / 定时流水线） | `selfdrive_dispatch` | 取 triage 顶部任务 → 路由 → 直接认领给最佳执行者 |
| 外部 AI 要判断任务分派 | `executor_route` + `selfdrive_dispatch` | 前者出建议，后者落成动作 |

**反面（不该用）**：
- 只是想看任务清单 → 用 `list` / `task_triage`（本组不含任务列表）。
- 想**真跑**任务 → 用 `executor_run`（本组只做分派，不执行）。
- 分派前没登记任何执行者 → `route` 返回空候选，需先 `register`。

## 怎么调

### 1. `executor_register(name 必填, abilities 可选数组)`

```
executor_register(name: "executor-A", abilities: ["编排","json"])
```

- `name` **必填**：执行者标识。
- `abilities` **可选数组**：能力标签集合（如 `["编排","json"]`）。
- **持久化到 store**（跨进程可复现）；写盘失败回执 `persisted=false` + `persist_error`。
- 返回：`{name, abilities, executors, persisted}`。

### 2. `executor_route(need 必填)`

```
executor_route(need: "编排,json")
```

- `need` **必填**：任务所需能力标签（逗号 / 顿号 / 空格分隔）。
- 从已注册执行者排序：
  1. **能力覆盖率 desc**（Marketplace 雏形）
  2. **历史信任 desc**（R80 信任轴：名下已完成 / 名下总数；无历史 0.5 中性）——防只认领不交付
  3. **负载 asc**（名下活跃任务数）
- 返回：`{need, parsed, count, candidates, best, basis}`。
- 启动会**回灌已持久化注册**（跨进程可复现）。

### 3. `executor_auction(need 必填, bid 可选对象)`

```
executor_auction(need: "编排,json")
executor_auction(need: "编排,json", bid: {"executor-A": 0.9, "executor-B": 0.7})
```

- `need` **必填**：任务所需能力标签。
- `bid` **可选对象**：`{执行者: 0..1 置信度}`；缺省按能力覆盖率自动出价。
- 拍卖分 = **校准系数** `1 - |出价 - 历史验收通过率|` × 出价 × **负载折扣** `1/(1+负载)`。
  - 校准系数**惩罚过度自信者**（胜者诅咒），能力覆盖 > 0 方可竞拍。
- 返回：`{need, parsed, count, bids, winner, basis, note}`。

### 4. `executor_clear()`

```
executor_clear()
```

- 无参数。**清空 store executors 表**（进程内注册表以 store 为空为基准重建）。
- 返回：`{persisted}`。
- **重置 / 整洁**用，防测试残留。

### 5. `selfdrive_dispatch(namespace 可选, agent 可选默认 self, want 可选)`

```
selfdrive_dispatch(namespace: "ns-skill-worktree")
selfdrive_dispatch(want: "json")
```

- `namespace` **可选**：作用域；空 = 全部。
- `agent` **可选默认 self**：回退认领者身份。
- `want` **可选**：所需能力关键词（优先）；否则从任务描述自动抽取已注册能力标签（R33 免手传）。
- 流程：取 triage 顶部可领取任务 → 确定所需能力 → `executor_route` 找最佳执行者 → **直接认领给该执行者**（待领取 → 已领取）。
- 无匹配执行者时**回退认领给 `agent`**（默认 self）。
- 返回：`{dispatched, task_id, assignee, want, need_auto, route?}`。

## 已知边界

- **`register` 能力标签持久化可能失败**：写盘失败回执 `persisted=false` + `persist_error`，此时只在进程内生效，重启即失（跨进程不可复现）。
- **`route` 依赖已注册执行者**：未 `register` 任何执行者时返回空候选，需先登记。
- **`route` 信任轴是历史信任不是能力证明**：无历史 0.5 中性，不代表能力水平。
- **`auction` 默认按能力覆盖率自动出价**：不等于执行者真实置信度，显式 `bid` 才反映置信。
- **`auction` 能力覆盖 > 0 方可竞拍**：覆盖 0 的执行者不参与。
- **`clear` 是全量清空**：会清掉所有执行者注册，包括正在使用的；谨慎调用。
- **`selfdrive_dispatch` 会真改任务状态**：把待领取改为已领取（认领动作），非只读；且命名空间要显式传以免误派其他 ns 任务。
- **`selfdrive_dispatch` 回退认领给 `agent`**：无匹配执行者时可能认领给自己，需注意。

## 五工具协同

```
登记 → 路由 → 竞拍 → 派单 → 整洁

executor_register(name, abilities)      # 1. 登记能力（持久化）
executor_route(need)                    # 2. 推荐：能力覆盖率 → 历史信任 → 负载
executor_auction(need, bid?)            # 3. 竞拍：校准系数折扣胜者诅咒
selfdrive_dispatch(namespace, want?)    # 4. 自动派单：triage → route → 直接认领
executor_clear()                        # 5. 整洁：清空注册（重置 / 防残留）
```

- **`register` → `route` → `dispatch`** 是主链路：登记能力、按任务推荐、落成认领动作。
- **`auction`** 是 `route` 的进阶：把"排序推荐"升级为"按出价竞拍"，适合对置信度有要求的场景。
- **`clear`** 是运维门：重置 Marketplace，防测试数据污染。
- 五者都**不真执行任务**（不 spawn 子进程），只做分派决策；真跑走 `executor_run`。

## 验收

- 四段齐全：`## 何时用` / `## 怎么调` / `## 已知边界` / `## 五工具协同` ✓
- 5 工具参数名逐字：`name, abilities` / `need` / `need, bid` / （无参）/ `namespace, agent, want` ✓
- 硬门点：`register` 持久化失败 `persisted=false`、`route` 历史信任轴 R80、`auction` 校准系数防胜者诅咒 R87、`dispatch` 回退认领 `agent` R32/R33、`clear` 全量清空 ✓
- 真源对齐：`AGENTS.md`「Marketplace·执行者能力路由」段 + `src/executor/` ✓