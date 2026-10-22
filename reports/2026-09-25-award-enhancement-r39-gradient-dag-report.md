# 获奖提升 · R39 汇报：LADDER 真实 DAG 前驱链（gradient_dag）

> 日期 2026-09-25 ｜ 字母轮号 R39（deliverable 功能轮第 37 行）｜ 主题：结构化 / 计划性增强

## 结果摘要
`task_plan_deep` 新增可选参数 `gradient_dag`（须 `gradient=true` 生效）。开启后，把 LADDER「更简单变体→先易后逆推」由**描述提示文本**升级为**真实 DAG 前置依赖**：每层拆解把兄弟切片按"由易到难"连成 `depends_on` 前驱链，更难的后续切片必须等它更简单的前驱切片完成后才可认领，`dag_ready/dag_ascii/topo_sort` 全部可见。默认关闭，零回归，工具数保持 83。

## 资源消耗
- 改动文件：`src/engine/engine.mbt`（plan_deep + decompose_rec）、`src/server/server.mbt`（schema/解析/透传）、`src/engine/decompose_test.mbt`（+1 测试）；文档 `README/AGENTS/docs|deliverable/scoring_rubric` 230→231 同步。
- 时间：单轮闭环（调研→实现→测试→文档→提交→推送）。

## 任务分配记录
- 调研：Explore 子代理定位 `decompose.mbt`（难度标签/hint）、`engine.mbt` 递归点、`dag_depend` 复用 API、`Task.depends_on`、claim 受 `deps_satisfied` 门禁。
- 实现/验证：主会话直改 + 单元测试 + badge/smoke 守卫。

## 遗留风险
- `gradient_dag` 为严格前驱链（线性），当调用方用 `calibrate` 传非单调真实难度时，链仍按切片位置排序（非按难度值）——语义为"先易后逆推"，可接受；如需按难度值建偏序，为后续可选增强。
- Windows native 偶发竞态（既有，非本改动引入）。

## 后续建议
- 把 `gradient_dag` 接入 `award_demo.py` 的拆解演示段，让评审在一条命令里看到真实 DAG 前驱链。
- 探索"更简单变体"成独立子任务（而非仅前驱片排序）的更强形态，权衡任务数/脚本断言影响。

## 超额内容
- 返回树的每个节点附 `depends_on` 字段，便于 E2E 与 topo 断言。

## 来源
- git `e21331e → HEAD`（本轮）；`moon test --target js` 231/231；`check_badge.py` PASS；`mcp_smoke.py` PASS 83 工具。

*（内容由AI生成，仅供参考）*