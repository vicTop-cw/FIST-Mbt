# 超级管家引导与任务通道 Skill（supervisor_prompt_inject / list / consume / task_upsert / reminder_tick）

> 一源四态 cl3 补齐 · 6b/10。真源 = `src/server/supervisor_tools.mbt` + `AGENTS.md`「超级管家专属工具」段。本组 5 工具是超级管家（human_steward 对外入口）的**两条业务通道 + 一个探测器**：`prompt_*` 三件套管"引导"（对 agent / 项目注入提示词），`task_upsert` 管"任务"（更新 / 追加根任务），`reminder_tick` 管"计划偏离探测"（plan 目标 vs 实际进度）。

## 何时用

| 场景 | 用哪个 | 为什么 |
|---|---|---|
| 我要给某个 agent 或项目**注入一条引导提示词**（纠正方向 / 提示规范） | `supervisor_prompt_inject` | 落进程内 registry + `call_log` 双写，跨进程可回读、幂等 |
| 我要**列出**所有待投递 / 已消费的引导（盘点还有多少没被消费） | `supervisor_prompt_list` | `target` 可过滤某个 agent，`include_consumed=true` 连已消费的一起列 |
| 我是被注入的 agent，要**取走**那条引导去执行 | `supervisor_prompt_consume` | 标记已消费，重复取仍返回正文（幂等，防重复投递） |
| 我要**更新或追加**目标项目的任务（改描述 / 优先级 / 依赖，或加新根任务） | `supervisor_task_upsert` | per-item `created/updated/failed` 逐项回执，一次批量处理 |
| 我要**扫描计划 vs 实际的偏离**（目标没拆 / 节点长期 pending / 产出物缺失） | `supervisor_reminder_tick` | 提醒者（Reminder）轮询一拍，产出待投递提醒 |
| human_steward 要给外部 AI 做入场引导 / 项目纠偏 | `prompt_inject` + `reminder_tick` | 先注入引导，再周期性探测偏离 |

**反面（不该用）**：
- 只是想看项目全景 → 用 `supervisor_status`（本组不含状态视图）。
- 想**真删除**某任务 → `task_upsert` 只支持更新与追加，不支持删除。
- 想真终止某任务 → 用 `supervisor_kill_plan`（本组不含终止方案）。

## 怎么调

### 1. `supervisor_prompt_inject(target 必填, prompt 必填非空)`

```
supervisor_prompt_inject(target: "agent-skill-docs", prompt: "cl3 文档需含 J8 参数名与注册集逐字对齐")
```

- `target` **必填**：要注入的 agent 或项目标识。
- `prompt` **必填非空**：引导提示词正文。
- 落**进程内 registry** + **`call_log` 双写**（跨进程可回读、幂等）。
- 返回：投递记录（含 `guidance_id`，供后续 `prompt_consume` 使用）。

### 2. `supervisor_prompt_list(target 可选, include_consumed 可选默认 false)`

```
supervisor_prompt_list(target: "agent-skill-docs", include_consumed: true)
```

- `target` **可选**：按目标过滤；不传列出全部。
- `include_consumed` **可选默认 false**：`true` 时含已消费的引导。
- 进程内优先、回灌 store `recent_call_logs`。
- 返回：待投递 / 已消费引导列表。

### 3. `supervisor_prompt_consume(guidance_id 必填)`

```
supervisor_prompt_consume(guidance_id: "<guidance_id>")
```

- `guidance_id` **必填**：要取走的那条引导的 id（来自 `prompt_list` 或 `prompt_inject` 回执）。
- 标记**已消费**；**重复调用仍返回正文**（幂等，不重复投递）。
- 返回：引导正文 + 消费标记。

### 4. `supervisor_task_upsert(project_dir 必填, by 必填, items 必填, namespace 可选)`

```
supervisor_task_upsert(
  project_dir: ".",
  by: "human_steward",
  items: [ {task_id: "T-x", description: "...", priority: "高"},
           {description: "新任务描述", depends_on: ["T-y"]} ]
)
```

- `project_dir` **必填**：目标项目目录（相对 server cwd）。
- `by` **必填**：操作者身份；**追加须为 `human_steward`**（复用 `engine.publish` 的 human_steward 硬门）。
- `items` **必填数组**：每项 `{task_id?, description, priority?, depends_on?[]}`。
  - 带 `task_id` → **更新**该任务（描述 / 优先级 / 追加依赖）。
  - 不带 `task_id` → **追加**新根任务（复用 `publish` 的 human_steward 硬门）。
- `namespace` **可选默认 default**：任务落哪个 ns。
- 返回：per-item `{created/updated/failed}` 逐项回执（逐条独立成败，不整体回滚）。
- **终态任务拒改**（已完成 / 已归档不改描述）。

### 5. `supervisor_reminder_tick(stale_hours 可选默认 24, pending_hours 可选默认 48, include_consumed 可选默认 false)`

```
supervisor_reminder_tick(stale_hours: 24, pending_hours: 48)
```

- **提醒者（Reminder）轮询一拍**：扫描 plan 目标 vs task_tree 实际的偏离。
- 三类偏离：
  - R1 未消费引导（`include_consumed=false` 时只看待投递）。
  - R2 停滞任务（活跃超 `stale_hours` 未更新）。
  - R3 待处理超时（`pending` 超 `pending_hours` 未被接管）。
- 返回：提醒清单（**只读**，不注入不修改）。

## 已知边界

- **`prompt_inject` 是进程内 registry + call_log 双写**：进程重启后 registry 丢失，靠 call_log 可回读；跨进程回读依赖 call_log 是否已落库。
- **`prompt_consume` 幂等**：重复调用不重复返回（同 guidance_id 只消费一次）。
- **`task_upsert` 追加须 `human_steward`**：非 human_steward 传无 `task_id` 的 items 会被拒（engine.publish 硬门）。
- **`task_upsert` 不改终态任务**：已完成 / 已归档任务拒改描述。
- **`task_upsert` 逐条独立成败**：一条失败不整体回滚，回执 `failed` 项要逐条看。
- **`reminder_tick` 只读**：它只产出提醒清单，不自动注入；注入要走 `prompt_inject`（人工或上层调度）。
- **`stale_hours` / `pending_hours` 默认值对活跃项目偏保守**：24h / 48h 适合日级节奏，高频项目需下调。

## 五工具协同

```
主管（human_steward）侧：
  supervisor_reminder_tick(stale_hours, pending_hours)   # 1. 周期性扫描 plan vs 实际偏离
    └─ 发现偏离 → supervisor_prompt_inject(target, prompt)   # 2. 注入引导提示词纠正
        └─ 引导被 agent 取走：supervisor_prompt_consume(guidance_id)  # 3. agent 侧消费
            └─ 消费状态盘点：supervisor_prompt_list(include_consumed: true)  # 4. 看谁还没消费

任务通道：
  supervisor_task_upsert(project_dir, by, items)          # 更新 / 追加根任务（逐条回执）
    └─ items 带 task_id → 更新；不带 → 追加（须 human_steward）
```

- **`reminder_tick` → `prompt_inject` → `prompt_consume` → `prompt_list`**：形成"探测 → 引导 → 消费 → 盘点"的**引导闭环**，治 agent 方向漂移。
- **`task_upsert`** 是**任务通道**，与引导通道独立：一个是"改任务清单"，一个是"给 agent 说该怎么做"。
- 五者都**不擅自改变任务状态**（不 verify / 不 reject / 不 kill），只做引导与任务定义，符合金条四"不可逆操作只给方案 + 预案"。

## 验收

- 四段齐全：`## 何时用` / `## 怎么调` / `## 已知边界` / `## 五工具协同` ✓
- 5 工具参数名逐字：`target, prompt` / `target, include_consumed` / `guidance_id` / `project_dir, by, items, namespace` / `stale_hours, pending_hours, include_consumed` ✓
- 硬门点：`task_upsert` 追加须 `human_steward`、`prompt_consume` 幂等、`reminder_tick` 只读不注入、终态任务拒改 ✓
- 真源对齐：`src/server/supervisor_tools.mbt` + `AGENTS.md`「超级管家专属工具」段 ✓