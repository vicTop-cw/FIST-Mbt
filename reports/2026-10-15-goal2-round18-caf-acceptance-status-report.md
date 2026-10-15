# Goal-2 Round 18 报告 · CAF 验收标准对照表

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：docs/2026-10-15-fist-mbt-caf-acceptance-status.md（新文件）

## 结果摘要

新建 **CAF 验收标准对照表**，把散落在 R12/R13/R16 的验证证据归拢成一份可复用依据：

| # | 验收标准 | 状态 | 关键证据 |
|---|---|---|---|
| 1 | 离线回放可复现 | ✅ 已验 | `caf_offline_replay.py` 3/3 通过（R12，commit `c45d6d6`） |
| 2 | 开启后不增成本且成功率不降 | ✅ 已验（预演） | `caf_p2c_ab_preflight.py` 2/2 通过（R16，commit `3c72c27`），B 组 +0.04/+0.00 |
| 3 | dry_run 可预览 | 📋 待 P2c 接线后验证 | 依赖 `model_router_ops.mbt`（并发 WIP 占用） |
| 4 | 零回归基线 | ✅ 已验 | `router_caf_wbtest.mbt` 135/135（R13，commit `bd46d39`） |

**验证**：`output_validate` → 2 条产物检查全过 → **l4-pass**

## 为什么做这份文档

- P2c 接线完成后需要一条**验收依据**，本表把 R12/R13/R16 的分散证据串成一条链。
- 未来实施 P2c 的人可直接看本表，知道哪些标准已验证、哪些待验、用什么脚本验证。
- 标准 3 的阻塞点被显式标注（依赖 `model_router_ops.mbt` 的 dry_run 分支），不再隐式丢失。

## 资源消耗

| 项 | 值 |
|---|---|
| 新增文件 | 1（docs/2026-10-15-fist-mbt-caf-acceptance-status.md） |
| FIST MCP 工具调用 | 1（output_validate） |
| 未修改 src/ 真源 | ✅ |

## 遗留风险

1. P2c 接线仍被并发 agent WIP 阻塞（model_router_ops.mbt，26 文件）。
2. 标准 3（dry_run 预览）仍无验证——本表把阻塞点显式标注，但未解除。

## 后续建议

1. Round 19：若 WIP 释放 → 按设计文档实施 P2c → 更新本对照表标准 3 为 ✅。
2. Round 19：实施后用真源 MoonBit 复验标准 2（本表已标注"预演非真源"）。
3. Round 19：全仓回归（当前基线 1112/1112，CAF 135/135）纳入接线验收门。

## 超额内容

- 无。

## 来源

- `docs/2026-10-14-fist-mbt-router-caf-learning-plan.md` 验收标准 §
- `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`（P2c 设计文档）
- R12（commit `c45d6d6`）、R13（commit `bd46d39`）、R16（commit `3c72c27`）
- `mcp__fist-mbt__output_validate`（l4-pass）
