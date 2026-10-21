---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_845ea1e7c64d11f197b3525400248c00
    ReservedCode1: jJKex0pA7w8FN54eMeZ56S8tfCKfiQozK8DRO5brKb+YPdQTEV6O+lbL8bW2cUYWH0pU/Ch2jE2K1JVVGUc1DzYlih+XAxLItDJkgVyVqv8h+rV7EhOQkRfhQRdrUrY5uyLGPhm5cLDzlKeV0Hbweau7mDmcS4R8KemP0pHUFgZV3c48iR4IIDg10Nw=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: 9f2a11add43fbf12a546606fb2b962ab_845ea1e7c64d11f197b3525400248c00
    ReservedCode2: jJKex0pA7w8FN54eMeZ56S8tfCKfiQozK8DRO5brKb+YPdQTEV6O+lbL8bW2cUYWH0pU/Ch2jE2K1JVVGUc1DzYlih+XAxLItDJkgVyVqv8h+rV7EhOQkRfhQRdrUrY5uyLGPhm5cLDzlKeV0Hbweau7mDmcS4R8KemP0pHUFgZV3c48iR4IIDg10Nw=
---

# FIST-Mbt 超级管家「提醒者（Reminder）」角色计划

- 日期：2026-10-12
- 状态：计划待实施（纳入夜间开发批次，优先于 FIST-Mbt 下一轮迭代）
- 关联文档：2026-10-12-fist-mbt-supervisor-role-design.md、2026-10-12-fist-mbt-supervisor-tools-plan.md

## 1. 定位

提醒者（Reminder）是超级管家（human_steward）体系下的**轮询调度角色**，不直接执行业务任务，专职"盯着状态、到点提醒"，让管家与各执行角色不错过引导、不跑偏方向、不漏掉关键事项。

提醒者复用既有 supervisor 工具集（supervisor_status / task_tree / prompt_inject / prompt_list / prompt_consume / task_upsert），以只读审计 + 定向注入为主要动作，不抢占执行资源。

## 2. 职责清单

| 编号 | 职责 | 触发方式 | 动作 |
|---|---|---|---|
| R1 | 引导提醒 | 轮询发现未消费的引导/提示词（prompt_list 非空）或管家新注入引导 | 向目标角色 prompt_inject 提醒其消费；超时未消费升级提醒管家 |
| R2 | 方向偏离提醒 | 轮询对照当前任务 plan 目标与 task_tree 实际进展，偏差超阈值（如进度停滞超过 N 轮、产出偏离目标描述） | 生成偏离报告并 prompt_inject 给管家/对应执行角色，附修正建议 |
| R3 | 事项提醒 | 轮询发现依赖到期、任务超时、风险项、需要人类决策的事项（如模型通道失效、版本发布待确认） | 汇总为提醒清单，注入管家决策队列 |
| R4 | 心跳汇报 | 按调度周期输出提醒者自身的轮询摘要（检查了哪些项、发现几条提醒） | 写入状态存储，供 supervisor_status 展示 |

## 3. 轮询调度设计

- 调度方式：轮询（polling），独立轻量循环，不与任务执行争抢主循环。
- 默认周期：基础轮询 10 分钟/轮；R2 偏离审计 30 分钟/轮；R3 事项扫描 10 分钟/轮（可在配置中调整）。
- 事件触发：task_upsert / prompt_inject 产生新数据时，提醒者立即追加一轮增量检查（事件优先，轮询兜底）。
- 优先级：R1 引导提醒 > R2 方向偏离 > R3 事项提醒；同轮多条提醒按角色与严重度排序后批量注入，避免刷屏。
- 幂等与防噪：同一条提醒在未解决前最多提醒 3 次（间隔递增），已解决自动归档，防止重复打扰。

## 4. 偏离检测规则（R2 初步口径）

- 任务 plan 目标与 task_tree 实际节点比对：目标未拆解 / 节点长期 pending / 产出物缺失。
- 执行产出与任务描述的关键词/产出物清单比对（如要求落地某工具但工具列表未见新增）。
- 连续 N 轮无状态变更（heartbeat 停滞）判定为疑似卡死，提醒续跑或 kill_plan 重排。
- 规则随实践迭代，第一版先落地"未消费引导提醒 + 进度停滞提醒 + 事项提醒"三个最小闭环。

## 5. 与现有体系的融合

- 注册为超级管家角色表一员（core 角色扩展或 audit 角色补充，按角色设计文档既有分类归位），角色名 `reminder`。
- 数据复用：task_tree / supervisor_status 的输出即为轮询输入，不新建重复存储；提醒记录追加到状态存储新段 `reminder_log`。
- 工具复用：提醒动作全部走 prompt_inject（提醒即注入引导），无新增 MCP 工具可先行落地；如需展示轮询摘要，扩展 supervisor_status 增加 `--reminder` 视图。
- 后续演进：提醒者可在人类 steward 缺席时暂代日常看护，但不具备任务派发与终止权（保留给管家/人类）。

## 6. 落地步骤（供夜间开发批次使用）

1. 新增 reminder 轮询模块（engine 层），提供 start/stop/status 与配置项（周期、阈值、最大提醒次数）。
2. 实现 R1：读取 prompt_list 未消费项，向目标角色注入"待消费引导"提醒。
3. 实现 R2 最小版：对照 task_tree 与 plan 目标做停滞检测，生成偏离提醒。
4. 实现 R3：扫描超时任务与风险事项，生成提醒清单。
5. 接入 supervisor_status 展示提醒者状态与提醒日志。
6. 全量 moon test 通过，提交 git，更新角色设计文档标记"提醒者已落地"。
*（内容由AI生成，仅供参考）*
