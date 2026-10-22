# 超级管家核心三工具 Skill（supervisor_status / supervisor_task_tree / supervisor_kill_plan）

> 一源四态 cl3 补齐 · 6a/10。真源 = `src/server/supervisor_tools.mbt` + `AGENTS.md`「超级管家专属工具」段。**超级管家（human_steward 对外入口）**是 FIST 的指挥官侧视图与终止决策出口，三者共同回答"项目现在怎样 / 某棵树进度如何 / 某个任务该不该终止"。

## 何时用

| 场景 | 用哪个 | 为什么 |
|---|---|---|
| 我要一眼看全项目任务全景（分状态 / 分命名空间 / 活跃 / 进度百分比） | `supervisor_status` | 唯一入口，纯读零副作用，比 `list` 更聚合（按状态/ns 分组 + 进度） |
| 我要看某个根任务下整棵树的子任务完成度（谁卡住、进度多少） | `supervisor_task_tree` | 递归聚合子树，节点带 `subtree_done/subtree_total` 完成度 |
| 我怀疑某任务失控 / 想终止它，但**先看值不值得**（能否杀、怎么收尾） | `supervisor_kill_plan` | 只出方案不执行，六门链逐门评估，避免误杀 |
| 我是 human_steward 且要对外汇报项目健康 / 给外部 AI 做入场审计 | `supervisor_status` + `supervisor_task_tree` | 一次调用看全貌，不暴露内部 store |

**反面（不该用）**：
- 只想要某单条任务详情 → 用 `get`（更轻）。
- 想终止某任务**真执行** → `supervisor_kill_plan` **永远不真杀**，它只给方案，真 kill 由指挥官按方案人工执行。
- 想改任务描述 / 优先级 / 依赖 → 用 `supervisor_task_upsert`（不是本三件套）。

## 怎么调

### 1. `supervisor_status(namespace 可选，不传=全库)`

```
supervisor_status(namespace: "default")
```

- `namespace` **可选**：不传统计全部命名空间；传某 ns 只统计该 ns（BUG-81 教训：不传 ns 的 heal 会扫全库，而 `supervisor_status` 只读不受此影响）。
- **纯读**：不落库、不改任何任务状态。
- 返回：`{version, total_tasks, by_status, by_namespace, active, progress_pct, ...}`。
  - `by_status`：各状态任务数（待领取/已领取/执行中/待验收/已完成/已归档/已暂停/已打回）。
  - `by_namespace`：各 ns 的任务数（跨 ns 隔离账本可见）。
  - `active`：活跃任务（执行中+已领取+拆分中）。
  - `progress_pct`：项目进度百分比。

### 2. `supervisor_task_tree(root_id 必填)`

```
supervisor_task_tree(root_id: "T-2026-10-20-001")
```

- `root_id` **必填**：要出树的根任务 id。
- 复用 `task_plan_deep` 的树聚合口径，逐节点递归：
  - 节点字段：`task_id / status / description / depth / subtree_done / subtree_total / children[...]`。
  - `subtree_done / subtree_total`：该节点子树的完成度（已完成+已归档 计数 / 子树总任务数）。
  - 顶层额外返回聚合 `summary`（整棵树的汇总计数）。
- **纯读**：不改状态。

### 3. `supervisor_kill_plan(task_id / by / reason 必填，force / apply_pause 可选)`

```
supervisor_kill_plan(task_id: "T-x", by: "human_steward", reason: "需求变更", apply_pause: true)
```

- `task_id` / `by` / `reason` **必填**：目标任务 / 操作者 / 终止理由（`reason` 必填非空，空理由拒绝）。
- `force` **可选默认 false**：强制路径，放行 已暂停/已打回 非流态僵尸任务（在流态仍拒）。
- `apply_pause` **可选默认 false**：`true` 时执行**唯一可逆动作** `pause_task`（暂停），其余全部只出方案。
- 返回：`{verdict: allowed|only_plan|blocked, steps: [...], saga: [...]}`。
  - `verdict=allowed`：可终止（且 `apply_pause=true` 已执行暂停）。
  - `verdict=only_plan`：只给方案（默认不执行）。
  - `verdict=blocked`：逐门被拒，附被哪一门拦。
  - `steps`：建议的执行步骤序列。
  - `saga`：Saga 补偿建议（若该任务有已登记的前向步骤）。
- **六门链**（任一不过即 blocked）：G1 身份门（`by` 须为主助理或 human_steward）→ G2 存在（task_id 须存在）→ G3 根任务不可杀 → G4 终态拒杀（已完成/已归档不可杀）→ G5 force+reason（非流态须 force）→ G6 补偿建议。

## 已知边界

- **`supervisor_kill_plan` 永不真杀**：本工具只出方案；真 kill 由指挥官按 `steps` 人工执行。`apply_pause=true` 是**唯一**在本工具内可逆执行的旁路。
- **`supervisor_status` 只读**：不能用于状态迁移，任何 `verify/reject/archive` 都不走它。
- **`supervisor_task_tree` 的 `root_id` 必须是真根**：传叶子任务返回的子树只有它自己，`subtree_done/subtree_total` 是 1/1，不构成误报但信息量低。
- **六门链可能拦下合法终止**：`G3 根任务不可杀` 意味着根任务即使看起来失控也只能 pause，不能 kill——**这是设计**，根任务承担全树责任。
- **`by` 的权限不在此工具校验**：`supervisor_kill_plan` 只按 `by` 是否为主助理/human_steward 判 G1，真实鉴权由外部（MCP 调用方）保证。

## 三工具协同

```
主管场景：
  supervisor_status(namespace)          # 1. 全项目全景 → 定位可疑 ns / 可疑状态
    └─ 若某根任务进度异常 → supervisor_task_tree(root_id)
        └─ 找到卡住的子任务 → supervisor_kill_plan(task_id, by, reason)
            └─ verdict=only_plan → 指挥官按 steps 决定真执行（或 apply_pause=true 先暂停）
```

- **`supervisor_status` → `supervisor_task_tree`**：从"项目整体健康"下钻到"某棵树的完成度"，是**漏斗式下钻**。
- **`supervisor_task_tree` → `supervisor_kill_plan`**：从"树里谁卡"到"该不该终止"，是**决策出口**。
- 三者都是**纯读 / 出方案**，不擅自改变状态——真正改变状态的动作（pause/kill/verify）由指挥官在 `steps` 指引下执行，符合金条四"不可逆操作只给方案 + 预案，执行权留在指挥官"。

## 验收

- 四段齐全：`## 何时用` / `## 怎么调` / `## 已知边界` / `## 三工具协同` ✓
- 3 工具参数名逐字：`namespace` / `root_id` / `task_id,by,reason,force,apply_pause` ✓
- 硬门点：`supervisor_kill_plan` 只出方案不真杀、`apply_pause` 是唯一可逆动作、六门链 G3 根任务不可杀 ✓
- 真源对齐：`src/server/supervisor_tools.mbt` + `AGENTS.md`「超级管家专属工具」段 ✓