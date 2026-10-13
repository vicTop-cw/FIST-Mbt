# fist-mbt 超级管家专属工具（supervisor tools）计划

- 日期：2026-10-12
- 状态：v0.1 实施
- 前置：`docs/2026-10-12-fist-mbt-supervisor-role-design.md`（超级管家架构 v0.1）
- 原则：**不重复造轮子**——能复用 engine/store 现有 API 的全部复用；不可逆操作只出方案不执行（金条四）；纯增量零回归（不碰别人正在改的逻辑面）。

---

## 1. 目标与范围

为超级管家（human_steward 对外入口形态）补一组专属 MCP 工具，覆盖四项能力：

1. **查看项目状态**：全项目/各命名空间任务全景、任务树进度
2. **终止任务**：终止/杀死指定任务——**方案先行**（kill 硬门链评估 + 补偿建议），本体不可逆动作留给指挥官；提供可逆的暂停出口
3. **提示词引导**：向目标 agent/项目注入引导提示词（可投递、可消费的 guidance 队列）
4. **更新目标项目任务列表**：向指定项目追加任务 / 更新任务描述与优先级 / 追加依赖

## 2. 工具清单与命名（前缀 `supervisor_`，共 6 个）

| # | 工具名 | 能力 | 输入 | 输出（JSON） | 复用 / 新增 |
|---|---|---|---|---|---|
| 1 | `supervisor_status` | 查看项目状态 | `namespace`(可选，不传=全库) | by_status / by_ns / active / progress_pct | 复用 `engine.list_all`；新增聚合 |
| 2 | `supervisor_task_tree` | 任务树状态与进度 | `root_id`(必填) | 树状节点（id/状态/描述/子任务完成度）+ summary | 复用 `engine.get_task` + `children_index`；新增递归聚合 |
| 3 | `supervisor_kill_plan` | 终止方案（**只出方案不执行**） | `task_id`(必填)、`by`(必填)、`reason`(必填)、`force`(可选)、`apply_pause`(可选默认 false) | verdict=allowed/blocked + gate 链逐条结果 + steps + saga 补偿建议；`apply_pause=true` 时执行**可逆**的 pause | 复用 `engine.get_task`/`pause_task`/`store.list_saga_actions`；新增硬门链评估（纯计算） |
| 4 | `supervisor_prompt_inject` | 注入引导提示词 | `target`(必填 agent/项目)、`prompt`(必填非空)、`namespace`(可选) | guidance_id / queued | 新增进程内 registry + call_log 双写（跨进程可回读） |
| 5 | `supervisor_prompt_list` / 6 | 列出待投递引导 | `target`(可选过滤)、`include_consumed`(可选) | pending/consumed 列表 | 同上 |
| 6 | `supervisor_prompt_consume` | 取走一条引导（标记已消费） | `guidance_id`(必填) | prompt 正文 + consumed | 同上 |
| 7 | `supervisor_task_upsert` | 更新目标项目任务列表 | `project_dir`(必填)、`namespace`(可选)、`items`(必填数组)：`{task_id?, description, priority?, depends_on?[]}`；无 task_id=追加新任务，有=更新 | per-item created/updated/failed | 追加=复用 `engine.publish`（human_steward 硬门）；更新=新增 `Task::with_description`（core 纯函数）+ `store.update_task`；依赖追加=复用 `Task::with_depends_on` |

> 共 **7 个工具**（prompt 三件套合并计数为 3 行），145 → 152。

## 3. kill 硬门链（supervisor_kill_plan 的评估面，全部只读）

按 `docs/2026-10-11-multi-agent-lock-design-v2.md` 的 kill 权唯一性 + AGENTS 金条四：

| 门 | 条件 | 不满足时 verdict |
|---|---|---|
| G1 身份门 | `by` == `human_steward` 或现任主助理（`engine.assistant_active_primary()`） | blocked: not_authorized |
| G2 目标存在 | `engine.get_task` 命中 | blocked: not_found |
| G3 不可杀目标 | 根任务（无 parent）且非 force → 拒；design 的 planner 分级在任务库无 role 字段，以「根任务=拳长承诺」近似 | blocked: protected_planner |
| G4 终态检查 | 已完成/已归档不可杀 | blocked: terminal_state |
| G5 force+reason | `force=true` 且 reason 非空才给 allowed；否则 only_plan | only_plan |
| G6 补偿建议 | 列出该任务子树内已完成但未登记补偿的下游承诺，提示走 `saga_register`/`saga_rollback` | 附加信息，不影响 verdict |

**执行语义**：本工具永不直接删除/终止任务。`apply_pause=true` 是唯一可选动作，走既有可逆迁移 `pause_task`（已暂停可 resume）。真正的 kill（删除子树/杀进程）由指挥官按方案人工执行或后续接 `assistant_kill`（v3 设计，PID 通道另立项）。

## 4. 提示词引导的持久化策略

- 进程内：`SupervisorGuidanceRegistry`（Map[id, Guidance]，模仿 DebateRegistry 的内部可变性模式）
- 跨进程：每次 inject/consume **双写 call_log**（`tool="supervisor_prompt_inject"/"..._consume"`，result_json 带 id/target/prompt），`supervisor_prompt_list` 先读进程内、再回灌 store 的 recent_call_logs（limit 放大），幂等不重复。
- 诚实标注：guidance 队列不建新表（避免与并行开发的 store.mbt/store_sqlite.mbt 冲突），call_log 500 条环形截断内的回读是 best-effort。

## 5. 文件落点（并行开发避让）

| 文件 | 状态 | 内容 |
|---|---|---|
| `src/server/supervisor_tools.mbt` | **新增** | 7 个工具注册函数 `register_supervisor_tools(s1)` + guidance registry |
| `src/server/server.mbt` | 最小侵入 | 仅插入一行 `s1 = register_supervisor_tools(s1)`（assistant 工具之后） |
| `src/engine/engine_supervisor.mbt` | **新增** | 任务树聚合、kill 硬门链评估（纯计算）、task upsert 编排 |
| `src/core/core_task.mbt` | 追加 | `Task::with_description` 纯函数（无状态机改动） |
| `src/server/supervisor_tools_test.mbt` | **新增** | 黑盒/白盒测试锁 |

不碰：store.mbt / store_sqlite.mbt / engine.mbt / ops / router（其他 agent 正在改）。

## 6. 分期

- **本期（P1）**：上述 7 工具 + 测试 + moon check/test 全绿。
- **P2（遗留）**：`assistant_kill`（PID 通道、固定 argv、登记表校验，照 v3 设计）；guidance 独立表持久化；`supervisor_status` 接 project_health/health_check 四金信号。
- **P3**：一源四态同步（插件态投影、AGENTS/README 工具计数 145→152、`fist://map` J14 面）——**须与正在进行的 v0.3.8 文档收口批次协调**，本期不动文档计数面，避免与并行 agent 打架。

## 7. 验收标准

- `moon check` 零错误；`moon test` 全绿（以 `Total tests: N, passed: N, failed: 0` 汇总行为准，不信任退出码）。
- 新增测试锁：kill 门链逐门（身份/不可杀/终态/force）、guidance inject→list→consume 闭环、task_upsert 的 created/updated/失败三路、tree 聚合正确性。
- 对既有 737 测试零回归。
