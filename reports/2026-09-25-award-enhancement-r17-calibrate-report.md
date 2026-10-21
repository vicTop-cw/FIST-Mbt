# 获奖提升 · R17 汇报：难度校准（LADDER 补真实难度）

> 日期：2026-09-25｜目标 pillar：计划性增强（递归拆解/难度推进）＋ 调研增强（LADDER 论文自举）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮为既有工具 `task_plan_deep` 的能力增强（工具数保持 77）。

## 结果摘要
- **闭环 R12 已记的"难度贴位置"弱项**：`task_plan_deep` 新增可选 `calibrate` 参数——调用方可按切片给真实/投影难度数组（0..5），当**长度与每层切片数一致**时难度档位改用投影难度（`difficulty_label_from`：≤2 易 / ≤3.5 中 / 否则难）并在标注里带 `d=<值>`；**长度不匹配或未传则回退**按位置的易/中/难（默认缺省零回归）。
- 落点（纯 MoonBit，无新表/依赖）：
  - [decompose.mbt](../src/decompose/decompose.mbt)：新增 `difficulty_label_from(Double)`；
  - [engine.mbt](../src/engine/engine.mbt)：`plan_deep`/`decompose_rec` 透传 `calibrate`（含递归下钻）；
  - [server.mbt](../src/server/server.mbt)：handler `get_array("calibrate")`→Array[Double] 并接入 schema/描述。
- 验证：`moon test --target js` **216/216**（+1：校准覆盖位置档 + 长度不匹配回退）；E2E `scripts/plan_gradient_verify.py` 追加 calibrate 用例（首片易 d=1、末片难 d=5）**PASS**；`mcp_smoke.py` **PASS**（工具数仍 77）。

## 资源消耗
- 改动：`decompose.mbt`、`engine.mbt`、`server.mbt`、`decompose_test.mbt` + 相关 `.mbti`；`scripts/plan_gradient_verify.py`（追加校准用例）。
- 测试：+1 条单测。
- 文档：测试 215→216 全量同步（README/AGENTS/ARCHITECTURE/deliverable/agent-map/申报书）；AGENTS 补 `calibrate` 参数说明；deliverable/申报书补 R17 行。

## 任务分配记录
- 直接实现（指挥官终审制）：小能力增强（透传数组 + 一个档位映射纯函数）；实机验证（moon test 216/216 + E2E calibrate PASS + mcp_smoke 77 工具）。

## 遗留风险
- 难度校准值是**调用方/agent 提供的投影**，本工具只做渲染与回退，不校验其合理性（符合"评测是计算、非 LLM 自评"——难度来源仍由调用方负责）。
- 递归下钻时子层切片数与本层不同，`calibrate` 数组只作用于"长度匹配的那一层"，其余层回退位置档（文档即实现，行为明确）。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **测试落盘收敛到系统 tmp**（`@fs.tmpdir`），从源头杜绝生成物（中改，可选）；
  2. **Marketplace / Dynamic 能力路由**（远期，executor 抽象层朝"能力注册 + 按负载/专长分配"）；
  3. **OpenTelemetry per-tool span**（低优先，单机场景价值有限）。

## 超额内容
- `difficulty_label_from` 与既有 `difficulty_label` 并立、语义清晰（位置档 vs 投影档），后续可复用为 Agent 难易感知的公共映射。

## 来源
- 调研：`memory/research/ecosystem-borrow.md`（LADDER 难度梯度自举，R12 落地简单变体、R17 补真实难度）。
- 代码：`src/decompose/decompose.mbt`、`src/engine/engine.mbt`、`src/server/server.mbt`、`src/engine/decompose_test.mbt`、`scripts/plan_gradient_verify.py`。