# FIST-Mbt 差异化定位（L42）

> 与 moonclaw / posoco / 官方 MCP SDK 的差异化共处策略

## 一句话定位

**FIST-Mbt = 完整 MCP Server + 任务编排 + 自进化闭环**，不是单纯的 MCP 协议库，也不是单纯的 Agent 框架。

## 三方定位对比

| 维度 | FIST-Mbt | moonclaw | posoco | 官方 MCP SDK |
|------|----------|----------|--------|--------------|
| 核心身份 | MCP Server（自驱任务管理） | MCP 协议实现 | Agent 框架六边形架构 | MCP 协议参考实现 |
| 任务编排 | ✅ 完整 DAG + 状态机 + 难度梯度 | ❌ | 部分（六边形架构） | ❌ |
| 自进化闭环 | ✅ DGM 档案库 + scoring + curriculum + mutation | ❌ | ❌ | ❌ |
| MCP 协议层 | 依赖 colmugx/mcp | 自研/参考 | 自研 | 参考 |
| 工具数 | 152+ | 协议级 | 框架级 | 协议级 |
| 多 agent 并发 | ✅ 作用域预订 + 分布式文件锁 + 违例审计 | ❌ | ❌ | ❌ |
| 无人值守 | ✅ watchdog + phi accrual + saga 补偿 | ❌ | 部分 | ❌ |

## FIST-Mbt 的不可替代性

1. **自驱闭环**：从 `selfdrive_init` 到 `selfdrive_publish_next`，完整的无人值守自迭代能力，其他项目不具备
2. **编排深度**：DAG 关键路径/PERT/Monte Carlo 排程 + 难度梯度拆解 + 作用域预订防冲突，远超 Agent 框架的任务分发
3. **自进化**：DGM 档案库 + scoring（纯计算评分，非 LLM 自评）+ curriculum（四阶段课程）+ mutation（5 种变异算子）+ skill_lib（蒸馏可复用技能），构成完整的"越用越强"闭环
4. **并发安全**：作用域预订（reserve_scope）+ 分布式文件锁（lock_acquire/release/renew）+ TTL 清扫 + 违例审计（lock_violations），多 agent 操作同一文件有完整防护
5. **可计算优先**：评分、难度、可移植性、健康度全部是纯计算函数，不依赖 LLM 主观判断，保证可复现

## 共处策略

- **协议层**：复用 colmugx/mcp（已 done），不重复造 MCP 协议轮子
- **框架层**：参考 posoco 六边形架构思想，但不照搬——FIST 的"承重墙"是任务编排 + 自进化，不是纯 Agent 框架
- **工具层**：FIST 的 152+ 工具是核心差异化资产，每个工具都是"编排+自进化"闭环的一环
- **边界**：不做纯协议库的事（那是 mcp SDK 的活），不做纯 Agent 运行时的事（那是 posoco 的活），专注"自驱任务管理 + 自进化"

## 不做的事

- 不重新实现 MCP 协议（已依赖 colmugx/mcp）
- 不做通用 Agent 运行时（posoco 的六边形架构是参考，不是目标）
- 不做纯协议工具集（官方 SDK 的活）

## 核心护城河

> **自驱 + 自进化 + 并发安全**三位一体，纯计算可复现，不依赖 LLM 自评。

这是 FIST-Mbt 与 moonclaw/posoco/官方 SDK 的根本区别——其他项目解决"协议/框架"问题，FIST-Mbt 解决"AI 自己驱动自己、自己进化自己、多个 AI 协作不冲突"的问题。
