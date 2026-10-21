# Goal-2 Round 3 报告 · 修复 BUG-173（sort_by 弱序）+ BUG-174（哈希溢出）

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 提交：d4d7cc2（BUG-173）+ 5792271（BUG-174）

## 结果摘要

Round 3 完成了【修复-验证】两环：

| Bug | 严重度 | 根因 | 修复 | 验证 | 状态 |
|---|---|---|---|---|---|
| BUG-173 | medium | caf_stats sort_by 比较器相等时返回 1（非 0），违反严格弱序 | 三档比较 + model 字典序 tiebreak | moon test 116/116 | FIXED |
| BUG-174 | low | caf_feature_hash h*31+c 无检查溢出 + h.abs() 在 Int64.min_value() 未定义 | (h*31+c).land(0xFFFFFFFF) 32 位截断，删 abs() | moon test 116/116 | FIXED |

## 任务分配记录

| Task | 内容 | 状态 |
|---|---|---|
| T0r612 | 修复 BUG-173 | 已完成 |
| T0r613 | 修复 BUG-174 | 已完成 |

## 验证细节

- `moon test --target js src/router` → Total tests: 116, passed: 116, failed: 0（原 114 + 新增 4 条回归测试）。
- `moon fmt --check` → no work to do。
- 全仓 moon test 退出码 1 由并发 agent WIP `src/ops/ops_pipeline.mbt:874` 的预存编译错误导致（`git status` 显示 `M src/ops/ops_pipeline.mbt`），与本次改动无关。

## 资源消耗

| 项 | 值 |
|---|---|
| 工具调用 | 编辑 × 4、pwsh × 4、bug_fix × 2、execute/submit/verify × 各 2 |
| 提交 | 2（d4d7cc2 / 5792271） |
| 触碰并发 WIP | 0 |

## 遗留风险

1. `src/ops/ops_pipeline.mbt` 编译错误仍在（并发 agent WIP）——非我的职责范围。
2. C-A-F 仍有 3 个测试覆盖缺口（Round 2 报告中列出）：环形回绕顺序、max_size=1、满缓冲覆盖。
3. BUG-155 fake green（HEAD 仍含 stale dist/fist-mbt.js）——并发 agent scope。

## 后续建议

1. Round 4 建议：寻虫扩面到 `src/server/model_router_ops.mbt`（C-A-F 接线面）。
2. 若并发 agent 修好 ops_pipeline，再跑一次全仓 moon test 确认零回归。

## 超额内容

- 无。

## 来源

- bug_list → BUG-173/174 原 OPEN
- get(T0r612/T0r613) → 待领取 → claim → execute → submit → verify
- git log --oneline → d4d7cc2 / 5792271
