# SKILL: rank-saga-circuit — 军衔派单 × Saga 回滚 × 熔断保护

> 形态：skill（本文档）｜MCP 工具 `rank_of` / `soldier_type_of` / `staff_label_of` / `saga_register` / `saga_rollback` / `saga_repair` / `circuit_status` / `circuit_fail` / `circuit_succeed`
> 真源：`src/display/rank.mbt` + `src/display/soldier.mbt` + `src/display/staff.mbt`（展示层三件，纯计算零 IO）+ `src/engine/engine_saga.mbt`（Saga 补偿编排，R92/R96）+ `src/engine/engine_circuit.mbt`（熔断器三态，R104）；MCP 注册面 `src/server/server.mbt`
> 用途：给 agent 三个正交的抓手——**军衔族**给派单一个可读的角色/能力视图（展示层，不动协议）；**Saga 族**保证多步骤任务链失败时优雅回滚而非卡死/整树重来；**熔断器族**保护对外的服务调用不被不健康下游压垮。三族协同：军衔定"派给谁"、Saga 保"失败回滚"、熔断器护"外部调用"。

## 何时用

- **贴展示标签（军衔族 A）**：任务层级定军衔（`rank_of`）、任务关键词定兵种+模型档位（`soldier_type_of`）、协议角色定参谋军职（`staff_label_of`）。看板标注、派单展示、汇报分层用——**只改展示，不改协议与存储**。
- **多步骤链要能优雅收尾（Saga 族 B）**：父子 / DAG 任务链执行到一半可能失败时——每个前向步骤成功后 `saga_register` 登记"可补偿动作"；失败时 `saga_rollback` 全局 LIFO 整链收尾，或 `saga_repair` 只补最小切片控级联（不涟漪撤销）。
- **对外调用怕被压垮（熔断器族 C）**：调 HTTP API / Laya / DB 等外部服务前 `circuit_status` 查放行；失败 `circuit_fail`、成功 `circuit_succeed` 回灌推进三态；`allow_call=false` 时立即快速失败、不耗资源。

## 怎么调

参数名 = MCP 注册面真名（`src/server/server.mbt`），不是杜撰。时间戳一律**服务端盖章**（不接受调用方注入 `now`，BUG-33 政策）。

### 军衔族（A）—— 展示层，纯计算零 IO

| 工具 | 参数（真名） | 返回键 |
|---|---|---|
| `rank_of` | `level`（必填，0..7）、`role`（可选，HumanSteward/Reminder/Executor/Leader）、`leaf`（可选，true 强制士兵） | `{level, role, rank, rank_index, is_officer, officer_levels, table}` |
| `soldier_type_of` | `keywords`（可选，逗号/空格分隔，缺省工兵）、`soldier`（可选，直接指定兵种名则跳过关键词匹配） | `{soldier, pool_label, mission, model_tier, count, types}` |
| `staff_label_of` | `role`（可选，协议角色名或自由文本关键词，缺省军务文书）、`title`（可选，直接指定参谋军职名则跳过匹配） | `{title, duty, hierarchy, count, titles}` |

```
tools/call rank_of          { "level": 3 }                    # → 旅长（level 默认 6=连长；越界退士兵；leaf 恒士兵）
tools/call soldier_type_of  { "keywords": "重构,算法" }        # → 炮兵
tools/call staff_label_of   { "role": "Verifier" }            # → 验收宪兵
```

- 军衔映射：L=0 司令 / 1 军长 / 2 师长 / 3 旅长 / 4 团长 / 5 营长 / 6 连长 / 7 排长，越界回退士兵。
- 8 兵种：侦查兵 / 炮兵 / 特种兵 / 医疗兵 / 通信兵 / 后勤兵 / 工兵（默认）/ 骑兵。
- 6 参谋军职：侦察参谋 / 后勤参谋 / 验收宪兵 / 监察参谋 / 训练教官 / 军务文书（默认）。
- **协议层不感知军衔**：除统帅/士兵/政委外，所有 `*长` 在协议层一律映射 `Leader` 角色；`level` 与 `depth` 严格分离（depth 是树深/缩进/`is_leaf` 判据，不是军衔来源）。

### Saga 族（B）—— 补偿事务编排（R92 / R96）

| 工具 | 参数（真名） | 语义 |
|---|---|---|
| `saga_register` | `root_task_id`（必填）、`step`（必填）、`compensation`（必填，业务逆转描述）、`task_id`（可选）、`namespace`（可选默认 default） | 前向步骤成功后登记"可补偿动作"到 durable action log；**幂等**：同 (namespace, root_task_id, step) 重登记重置为 pending 并刷新 compensation（重试安全） |
| `saga_rollback` | `root_task_id`（必填）、`mark`（可选默认 true）、`namespace`（可选默认 default） | 按 **LIFO（严格倒序，后登记先补偿）** 返回待补偿序列；`mark=true` 返回后即标 done（幂等，重复调用返回空，防重复回滚）；`mark=false` 仅预览不消费 |
| `saga_repair` | `root_task_id`（必填）、`failed_step`（必填）、`mark`（可选默认 true）、`namespace`（可选默认 default） | 算**最小补偿切片**=失败步骤+其依赖下游（depends_on 传递闭包中仍 pending 的步骤，无 task_id 时按注册序保守兜底）——只补切片（LIFO），切片外步骤 keep 保留承诺（控级联不涟漪撤销）；与 rollback 整链收尾互补 |

```
tools/call saga_register { "root_task_id": "T1", "step": "create-row",
                           "compensation": "delete-row(id=42)", "task_id": "T1a" }  # → status: pending
tools/call saga_rollback { "root_task_id": "T1", "mark": false }                    # 预览 LIFO 序列
tools/call saga_repair   { "root_task_id": "T1", "failed_step": "send-mail" }       # 最小切片，默认消费
```

- 补偿是**业务逆转动作描述**（非 DB ROLLBACK）：工具只登记/返回 LIFO 序列与最小切片，**真实补偿由 agent/指挥官按 pending 顺序执行**。

### 熔断器族（C）—— 三态状态机（R104）

`Closed（窗口内失败计数）→ 达阈值 Open（fail-fast 拒绝）→ 恢复定时器到期 Half-Open（放行 probe_limit 次探测）→ 探测成功 Closed / 探测失败回 Open`。

| 工具 | 参数（真名） | 语义 |
|---|---|---|
| `circuit_fail` | `circuit`（必填，熔断器名）、`window_secs`（可选默认 60）、`threshold`（可选默认 3）、`recovery_secs`（可选默认 30）、`namespace`（可选默认 default） | 上报失败推进状态机：Closed 窗口内计数达 threshold → Open；Half-Open 探测失败 → 回 Open 重启恢复定时器 |
| `circuit_succeed` | `circuit`（必填）、`namespace`（可选默认 default） | 上报成功回灌：Closed 复位计数；Half-Open 探测成功 → Closed（恢复）；Open 保持 |
| `circuit_status` | `circuit`（必填）、`probe_limit`（可选默认 1，<=0 视为不节流）、`namespace`（可选默认 default） | 查三态 + Half-Open 到期判定：Open 且 elapsed≥recovery_secs → 转 Half-Open（只放行 probe_limit 次探测，配额用尽即 allow_call=false） |

```
tools/call circuit_status  { "circuit": "http-api" }   # → { state, allow_call, ... }
tools/call circuit_fail    { "circuit": "http-api" }   # 失败计数
tools/call circuit_succeed { "circuit": "http-api" }   # 成功回灌
```

返回 `{ circuit, state, failures, probes_granted, probe_limit, window_secs, threshold, recovery_secs, opened_at, allow_call, note, persist_error? }`。**`allow_call=false` 即调用方应立即快速失败**（微秒返回不耗资源）；半开态下 `failures` 即 `probes_granted`（已放行探测数），别按失败数解释。

## 已知边界

- **三件军衔工具是展示层，非协议枚举**：协议与存储零改动，不改变任务生命周期/状态机；只是看板/汇报/派单的可读标签。`rank_of` 的 `level` 与 `depth` 严格分离（depth 不是军衔来源）。
- **时间戳一律服务端盖章**：saga/circuit 调用面**没有** `now`/`now_secs` 参数（BUG-33 政策：可注入时钟 = 可伪造窗口过期）。
- **Saga 不执行补偿**：只登记/返回 LIFO 序列与最小切片，真实"业务逆转"由 agent/指挥官执行；补偿是幂等契约（标记 done 后重试安全）。
- **Saga 幂等边界**：`saga_register` 同 (namespace, root_task_id, step) 重登记只重置 pending + 刷 compensation，不改 LIFO 位置；`saga_repair` 无 `task_id` 时按注册序保守兜底，切片外步骤 keep 不撤销。
- **熔断器是编排中间层**：不真调外部服务，只做状态推进 + `allow_call` 决策。半开态**必须节流**——只放行 `probe_limit` 次探测（默认 1），配额用尽即 `allow_call=false`（BUG-34：旧实现全量透传，半开退化成 closed）；拿到配额却长期不 `succeed`/`fail` 超过一个 recovery 窗自动重置配额（防半开被一次吞掉的探测永久锁死）。
- **BUG-254**：`circuit_fail` 的 `threshold`/`window_secs` 必须为正（`threshold<=0` 首败即熔断、`window_secs<=0` 计数每次重置——破坏语义，服务端显式拒绝）。
- **BUG-230**：`persist_error` 仅在持久化写盘失败时出现，**非空即"状态变更未落库"**，调用方不得把该回执当作已持久化。
- 本次为**纯文档**：不编译 src、不跑 `moon test`。

## 三族协同

三族正交、可串联，构成"派单 → 干活 → 对外 → 失败收尾"的一条闭环：

1. **军衔定"派给谁"**：`rank_of` 由层级定指挥链（谁带谁）、`soldier_type_of` 由关键词定兵种并给模型档位提示（重活→paid 池、轻活→free 池）、`staff_label_of` 定参谋军职——三者给出派单的可读角色/能力视图，但**不阻断协议**（协议层只认 Executor/Leader 等）。
2. **Saga 保"失败回滚"**：任务链每完成一个前向步骤就 `saga_register` 登记补偿；一旦中途失败，`saga_rollback` 全局 LIFO 整链收尾、`saga_repair` 只补最小切片控级联——**优雅收尾而非卡死/整树重来**。
3. **熔断器护"外部调用"**：干活中调外部服务前先 `circuit_status` 查 `allow_call`；失败 `circuit_fail`、成功 `circuit_succeed`——下游不健康时快速失败、恢复后探测放行，保护整条链不被不健康下游拖垮。

**典型串法**：派单（军衔族定角色视图）→ 逐步执行 + `saga_register` 登记补偿 → 每次对外调用前 `circuit_status`（`allow_call=false` 即快速失败）→ 链中途失败时 `saga_rollback`/`saga_repair` 优雅收尾。与看护族（`heal`/`phi_accrual`）互补：**看护发现失败 → Saga 负责收尾；熔断器护住"对外那一跳"**。
