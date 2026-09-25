# R81 汇报：预算按依赖图阶段切分 cost_budget_split（ZEBRA 蒸馏落地）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：接续 R80 的"调研蒸馏转落地"节奏，兑现 R78 留痕候选「ZEBRA 背包预算切分」——预算在任务图上按阶段切分，瓶颈阶段占额可见。
- **达成**：新增 `cost_budget_split` 工具（87→88）：`budget_split_by_dag` 按 slack 分析 earliest 层级分阶段，每阶段份额 = 阶段难度权重(难3/中2/易1，复用 triage_label_of)占总量比例 × 总预算（向下取整，余数补最大权重阶段），返回 { stages:[{level,tasks,difficulty_sum,share}], total_budget, makespan, note }。
- **验收**：engine **57/57**（+1），全量 **249/249**（+1），mcp_smoke 88 工具，守卫族全 PASS，cleanup CLEAN。

## 二、资源消耗
- 全量 `moon test --target js`（249/249）+ mcp_smoke（build 后 88 工具）+ 守卫族 + cleanup。
- 变更：engine_dag_ext.mbt(+80) / dag_ext_test.mbt(+1) / server.mbt(工具注册+1) / README/AGENTS/deliverable/scoring_rubric/mcp_smoke(87→88、248→249 全同步)。

## 三、任务分配记录
- R81 属轻量单函数硬能力 + 1 测试，指挥官亲自做，未开子任务。

## 四、遗留风险
- 切分为线性归一化简化（非 ZEBRA 真非线性背包/水填充 Lagrange 搜索）——已如实标注"蒸馏简化版"；复杂预算曲线场景可后续加深。
- `mcp_smoke` 首跑仍遇陈旧 main.js（工具数 87≠88），build 后通过——与历史已知项一致，演示脚本前需先 `moon build`。

## 五、后续建议
- 概率兜底连续 PASS 已稳（R77+R78）。候选：把 cost_budget_split 并入 award_demo 演示段（软可见）、门禁 cron 化（需定时场景）、或转申报书/demo 收尾打磨。

## 六、超额内容
- 无超额；改动严格限定预算切分工具家族。

## 七、来源
- `src/engine/engine_dag_ext.mbt` `budget_split_by_dag`（R81）
- `src/engine/dag_ext_test.mbt` R81 用例
- `src/server/server.mbt` cost_budget_split 注册
- `memory/research/20260926.cost-market-routing.md` §二（ZEBRA 背包预算切分候选）