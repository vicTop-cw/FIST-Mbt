# 2026-10-13 · BACKLOG 双向漂移对表翻账报告（P1×2 / P2×1 done + P3 self_search 半落地精确化）

## 结果摘要

目标「实现计划里未实现的计划」在盘完所有 BACKLOG pending/TBD 项后，发现一处**比"没实现"更坑的账实不符**：BACKLOG 是 selfdrive 审视/门禁的**净拉取源**（文首自述），却有 4 项"已实现仍标 pending"——selfdrive 会把已完成的当未做重复派单。本轮对表**源码真源逐项坐实验收标准**后翻账：

| 项 | 翻账后 | 决定性证据（源码，非函数名猜） |
|---|---|---|
| P1 Agent Contract 7 字段 | **done** | `sd_agent_contract`（`src/ops/ops_selfdrive.mbt:725`）七段齐备；注入点在同文件 L664 `desc = … + sd_agent_contract(tasks[i])`（每条 selfdrive 发布的根任务描述自带契约）；锁 `ops_selfdrive_test.mbt:444` |
| P1 Tool Use Rubric | **done** | `templates/tool_use_rubric.md` 真源 + 7 份 `pipeline_mode_*.md` **全部内嵌**硬规则段带 `<!-- TOOL_USE_RUBRIC_END -->`；`pipeline_has_rubric` 在 prompt_ready 相程序化检测（fail-open 是显式设计）；锁 `ops_pipeline_test.mbt:489/513` |
| P2 Dashboard/ASCII 可视化 | **done** | 四视角 MCP 工具在 `src/server/server.mbt` 注册齐：`dag_ascii`(L3827)/`board_ascii`(L3845)/`state_flow_ascii`(L3856)/`status_summary`(L3867)；quickcheck 三视角一致性属性测在 `board_ascii_test.mbt` |
| P3 self_search.mbt | **保持 pending，精确化** | 模块已在（`src/evolve/self_search.mbt`，5 函数 + 8 测），但全仓 grep **零调用者**——"入库那半"（接进 DGM/evolve_asset_register/MCP）没接线 ⇒ 是孤代码。**不转 done** |

**诚实边界**：翻账一律「验收到调用点/注册点/测试锁」三层，不凭函数名存在就转 done——那正是本仓最恨的假绿。`self_search` 若只看"文件已建、测试全绿"就会误转 done，实际缺的入库接线让它必须留在 pending（但补了"半落地勿重复建"的现状说明，让净拉取源不再重复建模块）。

## 资源消耗
- 只读对表（grep/read 源码 6 处 + 模板 8 份），零构建零网络。
- 一次文件编辑（BACKLOG.md 4 行状态）+ 本报告。

## 任务分配记录
- 指挥官亲自：逐翻账项读源码坐实调用链（Agent Contract 追到发布拼接 L664、Rubric 追到 pipeline_has_rubric 检测点、Dashboard 追到 server 注册行号、self_search 追到"零调用者"）。
- 未派子代理：翻账是"账 ↔ 真源"单点对表，拆给子代理反而多一层终审成本。

## 遗留风险
1. **BACKLOG 其余 pending 项仍多在并发会话占用面**（`src/server/*`、`src/store/*`、README/docs）：P2 `ARCHITECTURE.md`、P2 Pre-execution gate、P2 `core/diff`（实测 src 零命中，**确未实现**，保持 pending 正确）、P3 里程碑式渐进/可编程策略集/Runtime monitoring LTL/符号逻辑引擎/Scoring 自动进化闭环/差异化共处、F094 多管家三工具、P0 `async 升级`（工具链前置不足）与 P2 native 巡检（BUG-133 关闭条件未达）——这些要么真没做、要么属他人写面，本轮不在可安全落地范围。
2. 翻账只改状态标签与现状说明，**未验证运行期行为**（金条八的 L4 实测只覆盖到我本轮亲手做的迁移器/Star 门；BACKLOG 这几项是"账实对表"不是"重新实测已通过测试"）。

## 后续建议
1. self_search 入库接线（src/evolve 面，需并发会话收口后或由该面 owner 做）：把 `distill_candidates` 结果经 `evolve_asset_register` 落 DGM，让"调研先行"真正闭环。
2. BACKLOG 顶部那句「状态以当前源码/记忆库是否确认实现为准，未确认一律 pending」应配一支常驻判据（类似 J13 的机器可读），否则漂移会复发——本轮是手工对表。
3. P2 `core/diff` 若真要展示 diff，可复用 `board_ascii`/`dag_ascii` 的渲染模式，不必引 `moonbitlang/core/diff` 依赖（BACKLOG 原措辞把它列成待评估）。

## 超额内容
- 无（本轮就是把"翻账"这一件事做扎实：每项都追到调用点，没做的如实留 pending）。

## 来源
- `src/ops/ops_selfdrive.mbt`（L725 `sd_agent_contract`、L664 注入点）、`src/ops/ops_pipeline.mbt`（L381-425 rubric 自检）、`src/server/server.mbt`（L3827/3845/3856/3867 四工具注册）、`src/evolve/self_search.mbt`（模块在、无调用者）。
- `templates/tool_use_rubric.md` + 7 份 `templates/pipeline_mode_*.md`。
- 测试锁：`ops_selfdrive_test.mbt:444`、`ops_pipeline_test.mbt:489/513`、`self_search_test.mbt`(8 测)、`board_ascii_test.mbt`。
- `BACKLOG.md`（本轮 4 行状态翻账，commit 见下一提交）。
