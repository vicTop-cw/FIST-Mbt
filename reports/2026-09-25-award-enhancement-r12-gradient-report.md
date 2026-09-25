# 获奖提升 · R12 汇报：难度梯度拆解（LADDER 自举信号）

> 日期：2026-09-25｜目标 pillar：计划性增强（递归拆解）＋ 调研增强（拿来主义）
> 方式：fist-mbt 自驱式（持续获奖概率提升链路），本轮为既有工具 `task_plan_deep` 的能力增强，非新增工具。

## 结果摘要
- 新增：`task_plan_deep` 可选参数 `gradient`（默认 `false`，零回归）。开启后每个拆出的子任务描述附带 **「难度梯度 序号/总数:易/中/难」** 与 **「更简单变体」** 提示，使递归拆解产出"由易到难、可独立验证最小片"的梯度，而非扁平同难单元。
- 落地点（纯 MoonBit，无新表/依赖）：
  - [decompose.mbt](../src/decompose/decompose.mbt)：`difficulty_label`（三分档 易/中/难）+ `simpler_variant_hint`；
  - [engine.mbt](../src/engine/engine.mbt)：`plan_deep`/`decompose_rec` 透传 `gradient` 并拼接标注；
  - [server.mbt](../src/server/server.mbt)：工具描述/schema/handler 接入。
- 验证：`moon test --target js` **209/209**（+1）；E2E `scripts/plan_gradient_verify.py` **PASS**（默认关闭零回归 + gradient=true 标注 + scratch 隔离无根库残留）。

## 资源消耗
- 改动文件：`decompose.mbt`、`engine.mbt`、`server.mbt`、`decompose_test.mbt` + 4 份 `.mbti`；新增 `scripts/plan_gradient_verify.py`。
- 测试：新增 1 条单测（梯度标注 + 默认零回归）；E2E 脚本 1 个。
- 文档同步：README/AGENTS/ARCHITECTURE/deliverable/agent-map/scripts-README/项目申报书 测试数 208→209；deliverable/申报书补 R11+R12 行；research/ecosystem-borrow 把 LADDER 标记为已落地。

## 任务分配记录
- 本轮为直接实现（指挥官终审制）——调研蒸馏结论已在前序轮次沉淀于 [ecosystem-borrow.md](../memory/research/ecosystem-borrow.md)；本轮把其中"难度梯度自举"信号落到核心里程碑。未走 FIST 任务循环（小改动，直接终审）。

## 遗留风险
- 难度标签是**按位置三分档的经验估计**，非按任务真实体量；对"识别难度"有主观成分。
- lesson 过滤（Critic 防漂移，SAGE 信号）仍是下一候选，未落地。

## 后续建议
- 下一可借力点按调研强度：① **Challenger/Critic 防漂移**（`evolve` 入库 admission 阈值 + 打回过滤 lesson/principle）；② **难度估计可接 `decide_difficulty` 校准**（把躬身难度接受进 `plan_deep`，让标签更真实）；③ Dynamic/Marketplace 能力路由（远期）。

## 超额内容
- 顺带补全 deliverable/申报书 R10/R11 记录（作用域预订 + 预订整洁），使"文档即实现"完整对齐当前真实状态。

## 来源
- 调研：`memory/research/ecosystem-borrow.md`（LADDER/SAGE 论文信号蒸馏）。
- 代码：`src/decompose/decompose.mbt`、`src/engine/engine.mbt`、`src/server/server.mbt`、`src/engine/decompose_test.mbt`。