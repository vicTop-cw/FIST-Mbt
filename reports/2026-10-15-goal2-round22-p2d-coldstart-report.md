# Goal-2 Round 22 报告 · P2d 冷启动启发式设计

- 日期：2026-10-15
- 目标：使用 fist-mbt 全程开发，持续【寻虫-修复-验证-推进】循环轮转
- 交付：docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md（新文件）

## 结果摘要

新建 **P2d 冷启动启发式设计文档**，解决 P2c wiring 完成后冷启动阶段的偏好缺失问题：

### 问题

`use_caf_memory=true` 但记忆为空时，`caf_soft_reorder` 返回原序（零回归，已测试）。
但冷启动阶段如果原序是 `m_free, m_mid, m_premium`，每次都选 `m_free` 可能浪费成本。

### 设计

**新增函数**（不改旧函数，零回归）：
```moonbit
pub fn caf_soft_reorder_with_preference(
  candidates : Array[String],
  stats : Array[CafModelStats],
  default_preference : Array[String],
  min_evidences : Int,
) -> Array[String]
```

- 记忆充足（`evidence_total >= min_evidences`）→ 退化到 `caf_soft_reorder`
- 记忆不足 + preference 空 → 返回原序（零回归）
- 记忆不足 + preference 非空 → 按偏好排序，偏好外的保持原序

**新增 5 条测试**：
- `caf_pref_empty_baseline`（零回归）
- `caf_pref_memory_enough_fallback`（退化）
- `caf_pref_orders_preference`（偏好生效）
- `caf_pref_unknown_preference`（未知偏好安全）
- `caf_pref_preserves_unmatched`（偏好外保持原序）

### 与 P2c 的关系

- **不阻塞 P2c**：独立纯函数层
- **P2c 后接线**：在 `model_router_ops.mbt` 的 P2c wiring 里加调用
- **顺序**：P2c 优先（核心能力），P2d 次之（优化）

## 并发 agent 动态

- 新提交 `bd8c778`：修复 BUG-192（router_config/router_state 的 Double.to_int overflow guard）
- model_router_ops.mbt 仍 WIP（26 文件）
- router_caf.mbt 仍 WIP（守卫未提交）

## 资源消耗

| 项 | 值 |
|---|---|
| 新增文件 | 1（docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md） |
| FIST MCP 工具调用 | 0 |
| 未修改 src/ 真源 | ✅ |

## 遗留风险

1. P2c wiring 仍被并发 agent WIP 阻塞。
2. P2d 尚未实施（设计就位，等 P2c 释放）。
3. 并发 agent 的 router_caf.mbt 守卫仍未提交（可能与 P2d 冲突——如果并发 agent 改签名）。

## 后续建议

1. Round 23：若 model_router_ops.mbt 释放 → 实施 P2c wiring → 然后实施 P2d。
2. Round 23：若 router_caf.mbt 释放 → 加 5 条 P2d 测试验证设计。
3. Round 23：持续跟踪并发 agent 的 router_caf.mbt WIP（守卫是否提交）。

## 超额内容

- 无。

## 来源

- `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`（P2c 前置）
- `git log --oneline -5`（并发 agent 新提交 bd8c778）
