# FIST-Mbt 拿来主义调研总结（2026-09-25）

> 原则：非硬性要求下，**能复用则复用，能借力则借用**，避免重复造轮子。
> 本条对 `memory/research/20260925.enrich-roadmap.md` 的去重蒸馏，供后续增强直接引用。

## 一、可借力的外部范式（已评估可落地）

| 范范式/来源 | 是什么 | 是否已用/建议 |
|---|---|---|
| **Repo Map（Agent Patterns）** | 给 agent 紧凑按需的结构地图，先地图后文件 | ✅ 本轮落地 `docs/agent-map.md` + 拟加 `fist://map` resource |
| **DALIA**（arXiv 2601.17435） | 能力语义模型 + 声明式任务图，分离 discovery/planning/execution | ✅ fist-mbt 已有 claim(discovery) / plan_deep(planning) / execute(execution) 分层，方向吻合 |
| **TURA**（arXiv 2508.04604） | DAG Task Planner 构最优并行计划 | ✅ 已有 DAG 六件套，无需再造 |
| **AgentX**（arXiv 2509.07595） | Stage→Planner→Executor 三阶段 | ✅ 与递归拆解同构，定位已对齐 |

→ 结论：**编排/拆解方向已被论文与同类佐证，fist-mbt 不必造更复杂的轮子**；增分点在「入口体验 + 让 AI 更好上手」。

## 二、可借力的 MoonBit 库/语法（拿来自用候选）

| 能力 | MoonBit 提供 | 建议用途 |
|---|---|---|
| AI 原生规范 | v0.8 `declare type/fn/impl` | omega 语料/子任务写「declare 式契约」，让 AI 读规范即实现（后续） |
| 正则 | v0.9 `s =~ re"..."` 稳定 | 替换部分硬编码 `contains` 检查 |
| 临时目录 | v0.8 `@fs.tmpdir(prefix~)` | 整洁主线：临时脚本/产物落系统 tmp，不污染仓库 |
| 列表推导 | v0.9 `[ for .. if .. => .. ]` | 简化过滤/投影逻辑 |
| JSON/schema 校验 | `moonbitlang/x`（类比 zod 思路） | server 层 schema 已自实现，不强求引入 |

## 三、去重蒸馏结论

- **已经有的不重复做**：递归拆解(plan_deep)、DAG、Omega、evolve 档案、call_log、docs_gate —— 都是已有的"轮子"，本轮不再造。
- **本轮新增/增强**：
  1. 项目地图入口（`docs/agent-map.md` + `fist://map` resource）——解决"agent 全项目乱找"，最高性价比。
  2. 脚本整洁规范（`scripts/README.md`）——让临时/正式工具可区分。
  3. 调研记档（本条 + roadmap）——供后续增强随时引用。
  4. **失败回流学习**（`evolve_lesson`）——把打回/失败原因归档成 [lesson] 资产，配合 inject 检索"踩过的坑"（已实现，2026-09-25）。
- **记入后续 backlog**：`declare` 强契约、`@fs.tmpdir` 临时产物隔离。

## 四、来源
- `memory/research/20260925.enrich-roadmap.md`（含全部 URL 引用）
- agentpatternscatalog.org / agentpatterns.ai / arxiv / moonbitlang.com updates