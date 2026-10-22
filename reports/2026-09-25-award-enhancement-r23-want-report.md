# 获奖提升 · R23 汇报：task_triage 能力偏好路由（want，Marketplace 雏形）

> 日期：2026-09-25｜目标 pillar：计划性增强（更好的 AI 项目管理工具）+ 调研增强（Marketplace/Dynamic 路由）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮为既有 `task_triage` 的能力增强（工具数保持 78）。

## 结果摘要
- **低成本落地 Marketplookup 的第一块基石**：`task_triage` 新增可选 `want` 能力关键词——非空时，`描述/id` 命中该关键词的可领取任务**排头部**（`cap_match` 命中即路由到前，再按 优先级→重要度→深度→id 主键排序），并在 suggestion reason 里标注「能力匹配<want>」、返回回显 `want`。从此"这个 agent 擅长啥就先领啥"成为可按**能力路由**的取单原语（正是调研里 Dynamic/Marketplace"按专长分配"的雏形）。
- 落点（纯 MoonBit，无新表/依赖）：[engine_triage.mbt](../src/engine/engine_triage.mbt)（`triage` 加 `want` 参数 + `cap_match` 纯函数）；[server.mbt](../src/server/server.mbt) `task_triage` 接 `want`。
- **复用（避免造轮子）**：不改既有排序主键，仅在比较器最前插一个"能力命中"首键；新增测试 + award_demo 展示。
- 验证：`moon test --target js` **219/219**（+1）；`award_demo.py` 第 ⑨ 步传 `want="编排"`（suggestion 指向编排引擎叶子）**MCP-AWARD-DEMO PASS** + 结尾 CLEAN。

## 资源消耗
- 修改：`src/engine/engine_triage.mbt`、`src/server/server.mbt`、`src/engine/engine_triage_test.mbt`（+want 测试）、`scripts/award_demo.py`（+want）、相关 `.mbti`。
- 测试：+1 条单测（want 命中排头部 + want 回显）。
- 文档：测试 218→219 全量同步（README/AGENTS/ARCHITECTURE/deliverable/agent-map/申报书）；AGENTS `task_triage` 行补 `want`。工具数不变（78）。

## 任务分配记录
- 直接实现（指挥官终审制）：低成本能力增强（给既有工具加一个可选参数 + 排序首键），实机验证 219/219 + award_demo ⑨ PASS。

## 遗留风险
- `want` 为**子串匹配**（描述/id），非语义嵌入；对"措辞不同但能力相同"的候选可能不命中。作为雏形可接受，正式 Marketplace 需接语义/元数据标签。
- 仅对"待领取且依赖已满足"的集合做路由，未跨库聚合（与既有 triage 语义一致）。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **把 `task_triage` 的 suggestion（含 want）接进自驱/看门狗"按推荐取单"**——让无人值守按能力推荐而非固定顺序；
  2. **executor 注册 + 路由**（远期 Marketplookup 完整形态：agent 注册能力标签，router 按 want 匹配 + 负载分配）；
  3. **CI 徽章实时化**（把 `tests-219/219` 静态徽章改为 workflow 生成）。

## 超额内容
- `cap_match` 与排序主键解耦，日后扩展"元数据标签匹配"只需换匹配函数，不影响排序。

## 来源
- 前置：R21 `task_triage`（初始排行）、R20 deliverable 完整、研究 `memory/research/ecosystem-borrow.md`（Dynamic/Marketplace 信号）。
- 代码：`src/engine/engine_triage.mbt`、`src/server/server.mbt`、`scripts/award_demo.py`。