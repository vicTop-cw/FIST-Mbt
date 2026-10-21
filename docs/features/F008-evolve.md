---
feature_ids: [F008-evolve]
related_features: [F000-selfdrive, omega]
topics: [evolve, dgm, self-driving]
doc_kind: spec
created: 2026-09-24
---

# F008: DGM 档案库（evolve 模块）

> Status: done | Owner: fist-mbt
> 完整使用指南见 [`docs/evolve.md`](../evolve.md)。

## Why

把 DGM 论文「档案库保留次优解 + 多样性加权采样」的核心机制引入 fist-mbt，作为自驱/演化能力的基础设施；评价为可计算（非 LLM 自评），可对接已有 Omega gate / run_check。

## What

- 新增 `src/evolve/` 包：`Archive` / `Artifact`，实现 `p∝s·h` 采样、Jaccard 查重、novelty、lineage 谱系。
- store 新增 `evolve_artifacts` 表 + `evolve_upsert / evolve_list / evolve_bump_child`。
- MCP 新增 3 工具：`evolve_submit / evolve_snapshot / evolve_sample`。
- 域无关：`goal / note / code` 通用，评分注入式。

## Acceptance Criteria

- [x] AC-1: evolve 包 5 个测试全绿（采样/查重/新颖性/谱系）
- [x] AC-2: `moon test --target js` 全量 148/148 无回归
- [x] AC-3: MCP 端到端可用（submit→snapshot→sample，查重拒绝重复、谱系正确）
- [x] AC-4: SQLite 持久化表与方法就绪

## Dependencies

`moonbitlang/core/json`、`vicTop-cw/fist-mbt/src/store`。

## Risk

- 当前 MCP Archive 为进程内状态，重启清空（持久化方法已就绪，待接入）。
- 查重基于字符级 Jaccard（粗粒度），生产可换 embedding。

## Open Questions

- 是否在 watchdog/selfdrive 循环中自动调用 evolve（无人值守演化闭环）。