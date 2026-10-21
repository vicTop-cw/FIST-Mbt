# R94 汇报：Monte Carlo 概率式完工预测 dag_mc（Van Slyke 1963 蒸馏 · 93→94 工具 / 265→269 测试）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：PERT 家族确定性分析（dag_slack，R71）的概率式补充——整网 Monte Carlo 模拟，回答"能不能按期、风险在哪"。调研先行：Van Slyke 1963《Monte Carlo methods and the PERT problem》首倡 MCS 求网络完工 CDF；PERT 三点估算的单关键路径/merge bias 局限由整网模拟克服。
- **达成**：
  - engine_dag_mc.mbt（新）：xorshift32 确定性 PRNG（32 位掩码 js/native 一致）+ 牛顿法 mc_sqrt（core 无 sqrt）+ 三角分布采样（难度档→易(2,3,5)/中(3,5,8)/难(5,8,14)）；作用域子树过滤（parent 链传递闭包，环保护）；单样本最长完成时间（memo 化 DFS）；`dag_mc(ns~, root_task_id?, deadline?, samples?=1000, seed?=42)` → makespan 分布(min/mean/p50/p90/max) + P(≤deadline) + criticality 排行(top 10)。
  - server 注册 `dag_mc`（**93→94** 工具，DAG 组 16→17，fist://map 同步）。
- **验收**：dag_mc_test.mbt **+4**（可复现 + 按期概率单调 / 关键度 / insufficient / samples 钳制）；全量 **265→269/269**；mcp_smoke **94**；守卫族 tools/test/badge/index 全 PASS（94/269 对齐）；award_demo PASS（cleanup CLEAN）。

## 二、资源消耗
- 全量 `moon test --target js -j 1`（269/269）+ mcp_smoke（94 工具）+ 守卫族 + award_demo + cleanup。
- 变更：engine_dag_mc.mbt（新）/ dag_mc_test.mbt（新，+4）/ server.mbt（dag_mc 工具 + map 94/DAG 17）/ README/AGENTS/deliverable/USAGE/scoring_rubric/mcp_smoke/BACKLOG（94/269）/申报书（本地）/memory 日志。

## 三、任务分配记录
- R94 属跨层（engine + 4 测试 + server + 文档全量同步）硬创新新增，指挥官亲自做，未开子任务。

## 四、遗留风险
- 时长分布按难度档静态映射（无历史执行时长校准）——是 PM 工具常用的先验近似，后续可接 executions 历史校准分布参数（候选）。
- dag_mc 为确定性近似（seed 固定可复现）；任务时长独立同分布假设（经典 MC-PERT 同款，不建模相关性）。

## 五、后续建议
- 下一候选：门禁复评确认 R94 增量（大改后按纪律复评，`--prompt-file` 通道一条命令）；BACKLOG P2 局部补偿（history-aware，控级联）；英文 README（P3 国际受众）。
- 可选增强：dag_mc 接入 executions 历史时长校准分布参数（由先验近似 → 数据驱动）。

## 六、超额内容
- 无超额（scope 内完成）。

## 七、来源
- `src/engine/engine_dag_mc.mbt` `dag_mc` + PRNG/三角采样/最长路径模拟（R94）
- `src/engine/dag_mc_test.mbt` R94 四用例
- `src/server/server.mbt` dag_mc 工具 + map 同步（R94）
- 调研锚点：Van Slyke 1963《Monte Carlo methods and the PERT problem》（dl.acm.org）；PERT 三点估算公式；Primavera Risk Analysis / Crystal Ball 工业对标
