# 调研记档：AI 项目管理 / 任务编排 MCP 生态与论文（拿来主义蒸馏）

> 蒸馏日期：2026-09-25｜目标 pillar：调研增强《能复用则复用、拿来主义》｜用途：为 fist-mbt（AI 项目管理工具）设计完善提供可借力信号。

## 一、MCP 编排生态信号（2026 实况）
- **四种编排范式**：Hierarchical(Manager-Worker) / Peer-to-Peer(Consensus) / Pipeline / **Dynamic(Marketplace，agent 注册能力 + router 按负载/专长分配)**。
  - 对 fist-mbt：已实现 Hierarchical(递归拆解) + DAG(依赖)；**Dynamic/Marketplace 路由未做**（executor 抽象层可朝此演进）。
- **Interlinked**（多 agent MCP 编排）：**文件/作用域预订**(reserve files → 防编辑冲突)、任务依赖+自动分配队列、agent 消息/优先级线程、跨 agent 协调脚本。
  - ✅ **已落地**：`reserve_scope/reserve_check/reserve_release`（作用域预订，双后端持久化，TTL 让渡）——R10。
- **Concurrent Agent MCP（hegner123）**：SQLite 协调、原子 step 认领、依赖管理、崩溃恢复(heartbeat)、跨项目队列、metrics/analytics、WAL。
  - 对 fist-mbt：心跳/heal/DAG/成本统计已具备；analytics 已有 cost_stats/status_summary。
- **生产级加固**：认证(JWT)、限流(token bucket per client)、输入校验(JSON Schema)、**observability(OpenTelemetry spans per tool call)**、熔断(circuit breaker)。
  - 对 fist-mbt：call_log 已做(opentelemetry 化可选)；限流/熔断未做（单机 MCP 场景价值有限）。

## 二、论文信号（自改进 / 拆解）
- **LADDER**（自改进 LLM via 递归难度分解）：模型自生成"更简单变体"形成难度梯度再自举。→ fist-mbt 的递归拆解可吸收"难度梯度/简单变体"提示。
- **SAGE**（四智能体专家环：Challenger/Planner/Solver/Critic + 外部验证器）：Critic 打分过滤防"课程漂移"、保证训练信号质量。→ fist-mbt 已具 spec_author/verifier(Omega) 双角色；可加"Challenger 生成更难任务 + Critic 过滤 lesson/principle 防漂移"。
- **ReflexGrad**（层级 TODO 分解 + 历史因果反思 + 梯度优化三协同）：TODO 状态跟踪(pending/inprogress/completed) + 失败根因→纠偏。→ fist-mbt 状态机 + evolve_lesson(根因→lesson) 已对齐该直觉。
- **MetaSkill-Evolve / EvoTest**（两时间尺度技能进化 / 每 episode 演化整个 agent 系统）。→ 远期"scoring 驱动的自动进化闭环"呼应。
- **任务规划综述**：CoT→ToT→**GoT(图依赖)**。→ fist-mbt 已用 DAG。

## 三、蒸馏出拳（已落地/可落地）
| 信号来源 | 提炼 | 落地 |
|---|---|---|
| Interlinked | 作用域预订防并发编辑冲突 | ✅ R10 `reserve_*` |
| SAGE | Challenger/Critic 防 drift | 中期：plan_deep 加"难度梯度/简单变体"+ lesson 过滤 |
| LADDER | 难度梯度自举 | 中期：plan_deep 输出 simple-variant 提示 |
| Dynamic(Marketplace) | 能力注册 + 路由 | 远期：executor 抽象层朝 marketplace |
| 生产指南 | OpenTelemetry/限流 | 低优先（单机场景） |

## 四、一句总结
fist-mbt 已覆盖编排层(Hierarchical+DAG+心跳+成本+地图+脉冲)的主流能力；**差异化护城河再夯实一笔 = 作用域预订(冲突预防)**已落地；下一可借力点按强度排序：Challenger/Critic 防漂移 → 难度梯度拆解 → Marketplace 路由。