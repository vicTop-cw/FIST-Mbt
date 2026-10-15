# Goal-2 Round 8 报告 · caf_edit_distance 长度守卫 + .mbti 同步

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 提交：39a2f26

## 结果摘要

1. **长度守卫**：加 `pub const CAF_EDIT_MAX_LEN : Int = 256`，`caf_edit_distance` 对超长字符串截断到 256 字符后计算。防止调用方误传长 context 导致 O(n*m) 爆炸（10^4 字符 = 10^8 运算不可接受）。
   - 短串回归基线不变（<=256 直接原路径）
   - 超长串不 panic，返回有限值（<=256）

2. **过程缺陷修复**：发现 R4/R5 加了多个 pub 函数（`caf_edit_distance`/`knn_search`/`knn_stats`/`caf_soft_reorder`/`CafMemory::knn_*`）但未跑 `moon info`，`.mbti` 未同步。本次 `moon info` 同步。
   - **教训**：AGENTS.md 明确要求「`moon info` → `moon fmt` → `moon test` → `git commit`」，但加 pub 函数时容易跳过 `moon info`。应把 `moon info` 视为硬门。

3. **验证**：
   - `moon test src/router`：131/131 ✅
   - `moon test`（全仓）：1108/1108 ✅ 零回归

## 资源消耗

| 项 | 值 |
|---|---|
| 提交 | 1（39a2f26） |
| 新增测试 | 1 |
| 新增常量 | 1（CAF_EDIT_MAX_LEN） |
| 同步 .mbti | 1（修复 R4/R5 遗留） |

## 遗留风险

1. P2c 接线仍未完成（pick 钩子 + 配置项 + status 展示）——`model_router_ops.mbt` WIP。
2. `.mbti` 同步纪律：以后加 pub 函数必跑 `moon info`。

## 后续建议

1. Round 9：若并发 WIP 释放 → P2c 接线。
2. Round 9：探索其他 docs/ 未实现计划（multilang-sdk / web-dashboard 等）。

## 超额内容

- 无。

## 来源

- `src/router/router_caf.mbt`（实现）
- `src/router/router_caf_wbtest.mbt`（测试）
- `moon test --target js` 全仓实测
