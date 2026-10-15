# Goal-2 Round 15 报告 · P2c 接线设计文档精度修正

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md §2.1 精度修正

## 结果摘要

P2c 接线设计文档 §2.1（RouterConfig 改动）原有两个**实施陷阱**：

| 问题 | 原文档 | 修正后 |
|---|---|---|
| **真源位置错** | `src/router/router_config.mbt` | `src/router/model_router.mbt:281`（`router_config.mbt` 只含 `from_json`/`to_json` 方法） |
| **字段类型不一致** | `use_caf_memory : Bool? = None` | `use_caf_memory : Bool`（与既有 `use_laya : Bool` 同款形态，避免 `from_json`/`to_json` 分裂） |

**补充同步改动点**（实施时三处都要改，漏一处 `.mbti` 就脱钩）：

1. `RouterConfig::default()`（model_router.mbt:302）→ 加 `use_caf_memory: false`
2. `RouterConfig::from_json()`（router_config.mbt:9）→ 解析 `"use_caf_memory"`（true/false/null/garbage 与 `use_laya` 同口径）
3. `RouterConfig::to_json()`（router_config.mbt:246）→ 序列化该字段

**为什么改 Bool 而非 Bool?**：
- 既有 `use_laya` 就是 `Bool`（默认 false）
- `use_laya` 的语义是"开关"，不是"可选提示"
- 混用两种形态会让 `from_json` 的解析分支分裂，增加维护成本
- 零回归保证：默认 `false` 时 `pick` 不消费 CAF 记忆，行为与 v0.3.8 完全一致

## 验证细节

- 修正后设计文档共 6 章，约 135 行，实施时照 §2.1-§2.5 的代码片段可 1:1 落地。
- 修正不涉及代码改动（纯文档），无需 moon test。

## 资源消耗

| 项 | 值 |
|---|---|
| 修改文件 | 1（docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md §2.1） |
| 新增文件 | 0 |
| 提交 | 待落 |

## 遗留风险

1. P2c 接线仍被并发 agent WIP 阻塞（model_router_ops.mbt，27 文件）。
2. 并发 agent 刚提交 `53e6de1`（BUG-187 str_to_int 溢出守卫），与本仓 BUG-174 同族但不同文件——不冲突。

## 后续建议

1. Round 16：若 WIP 释放 → 按修正后设计文档实施 P2c（真源位置已核准）。
2. Round 16：若仍占用 → 考虑 CAF 冷启动启发式设计文档（空记忆 → 默认偏好）。

## 超额内容

- 无。

## 来源

- `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.1
- `src/router/model_router.mbt:281`（RouterConfig struct 真源）
- `src/router/router_config.mbt:9,246`（from_json/to_json）
