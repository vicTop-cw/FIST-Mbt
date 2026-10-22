# 2026-10-12 · 超级管家专属工具（supervisor_ 前缀，+7 工具）实施报告

> 结果摘要：7 个 supervisor_ 前缀工具全量落地，145→152 工具；moon check 0 error，moon test 802/802 全绿；文档面与插件态同步。

## 结果摘要

| 项 | 值 |
|---|---|
| 新增工具数 | 7（supervisor_ 前缀） |
| 总工具数 | 152（+3 resources +2 prompts） |
| 新增文件 | `src/engine/engine_supervisor.mbt`（495 行）、`src/server/supervisor_tools.mbt`（~370 行） |
| 修改文件 | `src/server/server.mbt`（+1 行注册）、文档面 6 份 |
| moon check | 0 error（663 既有 warning 不阻碍编译） |
| moon test | **802/802** 全绿（判据以 `Total tests` 汇总行为准） |

## 资源消耗

- **耗时**：~3 轮编辑循环（主体 1 轮 + 编译修复 2 轮）
- **验证**：`moon check` × 4 次，`moon test` × 2 次（首轮 1 失败 = SQLite 临时库残留，清场后全绿）
- **回滚**：无（git 未提交，改动只在工作树）

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 指挥官（AtomCode） | 调研既有工具面 → 写计划文档 → 终审子代理产出 → 修编译错误 → 文档面同步 |
| 子代理（本 session 内联） | 直接产出（单 session 无多 agent 分派） |

## 已交付工具清单

| # | 工具名 | 能力 | 引擎实现在 `engine_supervisor.mbt` |
|---|---|---|---|
| 1 | `supervisor_status` | 查看项目状态（by_status/by_namespace/进度/活跃任务列表，纯读） | `FistEngine::supervisor_status` |
| 2 | `supervisor_task_tree` | 任务树递归聚合（subtree_done/subtree_total，纯读） | `FistEngine::supervisor_task_tree` + 私有 `supervisor_tree_node` |
| 3 | `supervisor_kill_plan` | 终止方案（G1-G5 硬门链，只出方案不执行——金条四） | `FistEngine::supervisor_kill_plan`（verdict=allowed/only_plan/blocked + apply_pause 可逆出口） |
| 4 | `supervisor_prompt_inject` | 注入引导提示词（进程内队列 + call_log 双写跨进程回读） | `supervisor_guidance_inject` |
| 5 | `supervisor_prompt_list` | 列出待投递引导（target 过滤，include_consumed 含已消费） | `supervisor_guidance_list`（进程内 + call_log 回回去重） |
| 6 | `supervisor_prompt_consume` | 取走一条引导（幂等，标记已消费） | `supervisor_guidance_consume` |
| 7 | `supervisor_task_upsert` | 更新目标项目任务列表（无 id=追加 / 有 id=更新描述/优先级/依赖，终态拒改） | `FistEngine::supervisor_task_upsert` |

## kill 硬门链（G1-G5）

| 门 | 判定 |
|---|---|
| G1 身份 | `by == "human_steward"` 或 `by == 现任主助理` |
| G2 存在 | `self.get_task(task_id)` 非空 |
| G3 不可杀 | 根任务（无 parent）= 拳长承诺，不可杀（force 不可越过） |
| G4 终态 | 已完成 / 已归档不可杀 |
| G5 force+reason | `force=true` 且 `reason` 非空 → `allowed`；否则 `only_plan` |

verdict ∈ { `allowed`, `only_plan`, `blocked` }；永不自动执行 kill 本体（金条四）。

## 可逆出口

- `apply_pause=true` 时，若未被 G3/G4 拦下，执行 `pause_task`（可逆，已暂停可 resume）
- `supervisor_kill_apply_pause` 独立暴露，供外部显式调用

## 遗留风险

1. **跨进程 guidance 回读**：best-effort（call_log 里匹配 `supervisor_prompt_inject` 条目回灌），非事务性；高并发下可能漏读。
2. **进程内状态不持久**：`supervisor_guidance` 注册表进程内保存，重启即失；跨进程依赖 call_log 双写兜底。
3. **supervisor_task_upsert 追加任务走 `publish`**：内部含 `human_steward` 硬门，非 human_steward 调用会失败。
4. **supervisor_kill_plan 的 `now` 参数**：kill_plan 本身不消耗 `now`（纯计算），只在 `apply_pause=true` 时传给 `pause_task`；`now` 缺省回退任务自身 `updated_at`。
5. **插件态未重投影**：本轮未跑 `gen_plugins.py`（属并发会话文件范围），插件态将在下一次 gen_plugins 运行时自动同步。

## 后续建议

1. **supervisor_guidance 持久化**：当前进程内 + call_log 回读已够用；如需严格投递保证，可后续落 `guidance` 表（需 migration）。
2. **supervisor_kill_plan 接 saga**：当前只给建议文本，后续可自动调 `saga_register` 为终止前的待补偿步骤登记。
3. **进度看板**：`supervisor_status` + `supervisor_task_tree` 可组合为"实时项目仪表盘"供 Marvis 侧调用。

## 超额内容

- 文档面同步（AGENTS.md / ARCHITECTURE.md / README.md / README.mbt.md / README_EN.md / scripts/scoring_rubric.md，145→152）。

## 来源

- 计划文档：`docs/fist-mbt-supervisor-tools-plan-20261012.md`
- 设计文档：`docs/fist-mbt-supervisor-role-design-20261012.md`
- 引擎实现：`src/engine/engine_supervisor.mbt`
- 工具注册：`src/server/supervisor_tools.mbt`
- 注册调用：`src/server/server.mbt` L4743 `s1 = register_supervisor_tools(s1)`
