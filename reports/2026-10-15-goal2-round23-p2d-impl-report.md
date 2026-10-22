# Goal-2 Round 23 报告 · 实施 P2d 冷启动启发式

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：P2d 纯函数层 + 7 条测试 + 全仓零回归

## 结果摘要

### 实施 P2d 冷启动启发式

**新文件** `src/router/router_caf_ext.mbt`（独立文件，零冲突——不碰并发 agent WIP 的 `router_caf.mbt`）：

```moonbit
pub fn caf_soft_reorder_with_preference(
  candidates : Array[String],
  stats : Array[CafModelStats],
  default_preference : Array[String],
  min_evidences : Int,
) -> Array[String]
```

行为：
- **记忆充足**（`evidence_total >= min_evidences`）→ 退化到 `caf_soft_reorder`
- **记忆不足 + preference 空** → 返回原序（零回归）
- **记忆不足 + preference 非空** → 按偏好排序，偏好外的保持原序

**7 条测试**（`src/router/router_caf_ext_wbtest.mbt`）：

| 测试 | 验证 |
|---|---|
| `caf_pref_empty_baseline` | 零回归（preference 空 → 原序） |
| `caf_pref_memory_enough_fallback` | 记忆充足退化到 caf_soft_reorder |
| `caf_pref_orders_preference` | 偏好生效 |
| `caf_pref_unknown_preference` | 未知偏好安全 |
| `caf_pref_preserves_unmatched` | 偏好外保持原序 |
| `caf_pref_insufficient_evidences_fallback` | 记忆不足但非空 → 走偏好 |
| `caf_pref_duplicate_preference` | 重复偏好不 panic |

### 验证

```
src/router: Total tests: 145, passed: 145, failed: 0.   ← 138 + 7
全仓:       Total tests: 1124, passed: 1124, failed: 0.  ← 1115 + 7 + 2(并发 agent 新增)
```

## 资源消耗

| 项 | 值 |
|---|---|
| 新增文件 | 2（src/router/router_caf_ext.mbt + _wbtest.mbt） |
| 修改文件 | 1（pkg.generated.mbti，moon info 同步） |
| FIST MCP 工具调用 | 0 |
| 并发 agent 新提交 | 未发现（连续 5 轮无新提交） |

## 遗留风险

1. P2c wiring 仍被并发 agent WIP 阻塞（model_router_ops.mbt 仍 WIP）。
2. P2d 尚未接线到 pick 流程（依赖 P2c wiring）。
3. 并发 agent 似乎停滞（bd8c778 后 5 轮无提交）——可能在做别的事或遇到问题。

## 后续建议

1. Round 24：若 model_router_ops.mbt 释放 → 实施 P2c wiring + P2d 接线。
2. Round 24：若 router_caf.mbt 释放 → 确认守卫已提交。
3. Round 24：检查并发 agent 是否停滞，若停滞可考虑接管 model_router_ops.mbt（但需谨慎）。

## 超额内容

- 无。

## 来源

- `src/router/router_caf_ext.mbt`（新增，P2d 函数）
- `src/router/router_caf_ext_wbtest.mbt`（新增，7 条测试）
- `moon test --target js src/router` → 145/145
- `moon test --target js` → 1124/1124
- `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`（R22 设计）
