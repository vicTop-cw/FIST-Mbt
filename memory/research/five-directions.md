# 调研记档：五方向可移植机制清单（递归拆解 / 形式化验证 / 自计划 / 心跳）

> 来源报告：fist-mbt 五方向业界调研报告（2026-09-24）
> 蒸馏日期：2026-09-24
> 说明：不复制原文、只蒸馏可移植机制。机制凝练成一句话可执行；状态按当前 fist-mbt 事实核对（61 工具 / 148 测试 / JS+Native 双端全绿 / evolve 已在测试内）。
> 铁律：仅机制蒸馏入档，不自动并入外部代码；未实现机制不得臆造为 done。

## 一、机制清单

| 方向 | 机制 | 来源 | 对应模块 | 优先级 | 状态 |
|------|------|------|---------|--------|------|
| 递归拆解 | Interleaved 分支：据子任务执行反馈回退改 plan，而非拆完即弃 | RaDA/SagaLLM | decompose.mbt | P2 | pending |
| 递归拆解 | 全局目标校验：每子任务完成后校验是否偏离根目标（non-redundancy） | AOP | decompose.mbt | P2 | pending |
| 递归拆解 | 里程碑式渐进：decompose 前先生成粗粒度里程碑再逐步细化 | HiPlan | decompose.mbt | P3 | pending |
| 形式化验证 | 可编程策略集：将 Omega gate 8 种 $assert 扩展为支持用户自定义 invariant 的策略集 | Bedrock Guardrails | gate.mbt | P3 | pending |
| 形式化验证 | Transactional transition：invariant 失败整笔拒绝、状态 A 回稳 | Sakura Sky | engine.mbt | P2 | pending |
| 形式化验证 | Pre-execution audit gate：can_execute 之后、execute 之前插入 gate interception | JumpCloud | engine.mbt | P2 | pending |
| 形式化验证 | Runtime monitoring：按执行 trace 对 LTL 属性低开销认证 | arXiv 2412.06512 | ops_watchdog.mbt | P3 | pending |
| 门禁 | 毫秒级符号逻辑引擎按布尔约束拦截 planned action | JumpCloud | omega_tool.mbt | P3 | pending |
| 自计划 | Agent Contract 7 字段：Objective/Constraints/Tool policy/Stop conditions/Escalation/State discipline/Evidence | zubi.ai | ops_selfdrive.mbt | P1 | pending |
| 自计划 | Tool Use Rubric：pipeline 生成 prompt 时注入工具使用硬规则降 tool 幻觉 | zubi.ai | ops_pipeline.mbt | P1 | pending |
| 自计划 | Planner/Executor 职责分离：Planner 出计划不调工具、Executor 逐步执行防 plan drift | zubi.ai/PEAR | engine.mbt | P2 | pending |
| 自计划 | Evaluator-Optimizer schema：feedback 收敛为 Defects/Evidence/Fix/Acceptance 四段式 | zubi.ai | ops_selfdrive.mbt | P2 | pending |
| 自计划 | 局部补偿替代全局 replanning：history-aware local compensation 控级联效应 | ALAS | ops_watchdog.mbt | P2 | pending |
| 心跳 | Phi Accrual 概率式检测：按心跳历史分布算 φ 值替代固定 timeout | Cassandra | ops_heartbeat.mbt | P3 | pending |
| 心跳 | 多维度健康指标：除存活外检查 CPU/内存/任务积压/最近成功（4 类检查） | Rico Tan | ops_heartbeat.mbt | P2 | pending |
| 心跳 | Circuit Breaker 三态：Closed/Open/Half-Open 对外部调用快速失败 | Resilience4j | executor/ | P2 | pending |
| 心跳 | Saga 补偿事务 + durable action log：并发动作前写 append-only 日志、失败按 LIFO 补偿 | tianpan.co | engine.mbt | P3 | pending |
| 心跳 | "Did it work?" 输出验证：除"是否运行"外校验输出是否有效 | Rico Tan | ops_watchdog.mbt | P1 | pending |

## 二、去重补遗（与其余调研重叠、被 §一 覆盖的已并入）

- 安全事件教训（Replit 删库 / DGM 伪造日志 / AlphaEvolve reward hacking / cost 断路器 / 长时漂移）不在此清单重复，已并入 competition.md 的参赛风险与各模块演进建议。
- "Saga 补偿事务 + durable action log"一条已兼含 Recursion 方向对标要点（可与门禁/形式化协同），不单列。

## 来源
QClaw《fist-mbt 五方向业界调研报告_20260924-1430.md》§五 表（原文含 Recursion/Formal Verification/Gating/Self-planning/Heartbeat 五个方向与详细论证）；本档仅保留 §五 19 行清单（去重后 18 行）＋蒸馏结论。