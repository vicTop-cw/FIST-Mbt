# 获奖提升 · R26 汇报：自驱取单 selfdrive_pick_next（按能力推荐自动认领）

> 日期：2026-09-25｜目标 pillar：计划性增强 / 自驱式（更好的 AI 项目管理工具）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮新增 1 个 MCP 工具 `selfdrive_pick_next`（78→79）。

## 结果摘要
- 把上轮"只读推荐"升级为**动作**：新增 `selfdrive_pick_next`——对指定命名空间取 `task_triage` 的**顶部推荐并认领给 agent**（待领取→已领取，能力匹配 `want` 优先），让无人值守可按能力推荐**自推进**。**不动看门狗主流程**（零回归），只动一条推荐任务，失败不落地任何状态。
- 落点：`FistEngine::pick_next`（[engine_triage.mbt](../src/engine/engine_triage.mbt)，复用 `triage` 排行 + `claim` 认领）；[server.mbt](../src/server/server.mbt) 注册工具。
- 返回 `{ picked, remaining, claimed, ns, want, task?, note|error? }`。
- 验证：`moon test --target js` **220/220**（+1：能按推荐取走并认领 / 认领后无可领取不崩）；`award_demo.py` 第 ⑩ 步 `selfdrive_pick_next`（认领 T0r106.1.2、remaining=29）**MCP-AWARD-DEMO PASS** + 结尾 CLEAN；`mcp_smoke.py` **79 工具 PASS**。

## 资源消耗
- 新增：`FistEngine::pick_next`（并入 engine_triage.mbt）；修改 `server.mbt`、`engine_triage_test.mbt`(+1 测试)、`scripts/award_demo.py`(+⑩)、`scripts/mcp_smoke.py`(expected 79) + 相关 `.mbti`。
- 测试：+1 条单测。
- 文档：工具 78→79、测试 219→220 全量同步（README/AGENTS/ARCHITECTURE/USAGE/deliverable/agent-map/scripts-README/申报书/server map 79）；agent-map 自驱(8)→(9) 补 `selfdrive_pick_next`；deliverable/申报书补 R26 行。

## 任务分配记录
- 直接实现（指挥官终审制）：小规模新原语（复用既有 triage/claim）；实机验证 220/220 + award_demo ⑩ PASS + mcp_smoke 79。

## 遗留风险
- `pick_next` 只取**顶部一条**并按 want 偏好；对"批量取单/负载均衡"未做（可作 Marketplookup 后续）。
- 认领是即时的；若调用方认领后不执行，任务停在"已领取"（与既有 claim 语义一致，非本工具引入）。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **`selfdrive_pick_next` → watchdog/无人值守"按推荐续取"**：把取单接进定时流水线（在"无活跃任务"分支按 want 取单），让无人值守全链路按能力推进；
  2. **executor 注册 + 路由**（远期 Marketplookup 完整形态：agent 注册能力标签，router 按 want+负载分配；`pick_next` 是取单执行端）；
  3. **CI 徽章实时化**（`tests-219` → workflow 生成）。

## 超额内容
- 把"推荐（读）→ 取单（写）→ 认领"闭环打通，是自驱流水线可直接复用的最小执行原语。

## 来源
- 前置：R21 `task_triage`（排行）、R23 `want`（能力路由）、R25 自检门禁。
- 代码：`src/engine/engine_triage.mbt`、`src/server/server.mbt`、`scripts/award_demo.py`。