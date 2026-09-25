# R75 汇报：排程视图负载感知——建议派单（dag_schedule 增强）

> 日期 2026-09-25 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：延续 R74 排程视图"排程优化闭环"，把 flexible 批可并行任务的"assignee 现状"升级为"具体派给谁"。
- **达成**：`FistEngine::dag_schedule` 增负载感知——flexible_batch 中**未认领**任务附 `suggest = 活跃负载最低的已注册执行者`（无注册则空）。复用 `executor_list` + 既有状态判断，不重复算图。
- **验收**：engine **54/54**（+1），全量 **245/245**（+1），工具数稳定 **86**，mcp_smoke 86 工具，守卫族全 PASS，cleanup 洁净。

## 二、资源消耗
- 全量 `moon test --target js`（Node ≥24）一次通过 245/245。
- 变更：`src/engine/engine_dag_ext.mbt`(+36) / `dag_ext_test.mbt`(+1 用例) / `server.mbt`(工具描述 R74→R75) / 四文档计数同步。

## 三、任务分配记录
- R75 属单人轻量增强（既有工具内部字段增强 + 1 断言），FIST 指挥官亲自做，未开子任务。后续如需转文档/申报同步可再派子代理。

## 四、遗留风险
- `suggest` 仅在 flexible 批未认领项出现；critical 批（瓶颈）仍只标 assignee 现状，不强行给建议——符合"关键路径须串行盯紧"语义。无注册执行者时 suggest 为空，调用端需自行兜底。

## 五、后续建议
- 门禁复评一次，确认 R74+R75（排程视图+负载建议）在新档位（70/85/97）下概率仍稳。
- 或调研增量：把 `suggest` 与 `selfdrive_dispatch` 打通（建议→自动认领），形成"排程即派单"闭环，作下一硬创新备选。

## 六、超额内容
- 无超额行为，改动严格限定 dag_schedule 家族。

## 七、来源
- `src/engine/engine_dag_ext.mbt` `dag_schedule`（R74 R75）
- `src/engine/dag_ext_test.mbt` R75 断言
- `git a2348ac..worktree` 差分即 R75 全部改动（本轮未另立 commit，随本节金条五合入下一 commit）