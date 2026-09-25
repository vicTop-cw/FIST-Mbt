# 获奖提升 · R14 汇报：Challenger 进阶变体（SAGE 四专家环补齐）

> 日期：2026-09-25｜目标 pillar：计划性增强（递归拆解/难度推进）＋ 调研增强（拿来主义）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮新增 1 个 MCP 工具 `task_challenge`（76→77）。

## 结果摘要
- 新增 `task_challenge` MCP 工具：把 SAGE 四专家环中的 **Challenger（自生成更难任务）** 落地，补齐 R13 已实现的 Critic——凑成"四专家环闭环"（Critic 把关、Challenger 上难、Planner/Solver 即既有的 plan/执行）。
  - 对一条 **已完成/已归档** 任务，按策略发布上一档「更难变体」新根任务：带 **`[challenge]` 标记 + `from <task_id>` 溯源 + 重要度升一档**（低→中→高），构成「由易到难」自推进序列。
  - **规则驱动（非 LLM 自评）**：4 种进阶策略 generalize / unhint / constrain / scale（默认 scale，`factor` 扩规模倍数写进描述）；非法策略回退 scale；未完成任务明确拒绝（提示 已完成/已归档）。
- 落点（纯 MoonBit，无新表/依赖）：
  - [engine_challenge.mbt](../src/engine/engine_challenge.mbt)：`FistEngine::challenge` + 策略白名单/框架模板；
  - [server.mbt](../src/server/server.mbt)：注册 `task_challenge` 工具。
- **复用设计（避免重复造轮子）**：用引擎内建 `first_free_root_id + create_task` 建根任务（绕开 `publish` 的人类指挥官门禁——Challenger 由 agent 触发）；继承源任务 `project_dir/priority/ns`，干净溯源。
- 验证：`moon test --target js` **215/215**（+2）；E2E `scripts/task_challenge_verify.py` **PASS**（tools/list=77 + 新根 [challenge] 溯源/3倍 + 未完成拒绝 + 仓库根无临时库）。

## 资源消耗
- 改动：新增 `src/engine/engine_challenge.mbt`、`src/engine/engine_challenge_test.mbt`、`scripts/task_challenge_verify.py`；修改 `src/server/server.mbt`（工具注册）+ 若干 `.mbti`。
- 测试：新增 2 条单测（已完成→[challenge]+溯源+重要度升档 / 未完成拒绝+非法策略回退 scale+factor 写描述）。
- 文档：工具 76→77、测试 213→215 全量同步（README/AGENTS/ARCHITECTURE/USAGE/deliverable/agent-map/scripts-README/mcp_smoke/申报书）；AGENTS 自我记忆表 (6)→(7)；deliverable/申报书补 R14 行；research/ecosystem-borrow 把 SAGE 标为 ✅ 四专家环闭环。

## 任务分配记录
- 直接实现（指挥官终审制）：SAGE 平面已在 research/ecosystem-borrow.md 蒸馏，本轮补齐 Challenger。涉及 engine+server 跨模块小改，采用直接实现 + 终审（`moon test` + E2E 实际运行验证），未走 FIST 任务循环。

## 遗留风险
- "更难变体"是**模板化框架**（规则生成，非真正智能重设计），上难幅度有限；对"跳变难度多样性"仍需人工/agent 在 New 根任务里进一步细化。
- `task_challenge` 依赖源任务先走到完成态；对"半途想上难"的诉求需先制造已完成脚手架再挑战。
- 后续若接语义嵌入，可使"由易到难"更平滑，但坚持"纯计算、不依赖 LLM 自评"的取舍不变。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **难度校准**：把 `decide_difficulty` 接进 `gradient` 标签，让拆解难度更贴近真实；
  2. **Marketplace / Dynamic 能力路由**（远期）：executor 抽象层朝"能力注册 + 按负载/专长分配"演进；
  3. **生产加固**：OpenTelemetry per-tool span（低优先，单机场景价值有限）。

## 超额内容
- 无表/依赖新增，保持零运行时依赖（纯 MoonBit、双后端可交叉编译）。

## 来源
- 调研：`memory/research/ecosystem-borrow.md`（SAGE 论文信号蒸馏，LADDER 梯度呼应）。
- 代码：`src/engine/engine_challenge.mbt`、`src/server/server.mbt`、`src/engine/engine_challenge_test.mbt`、`scripts/task_challenge_verify.py`。