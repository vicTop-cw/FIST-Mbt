# CAF P2d 设计文档 · 冷启动启发式

> 状态：✅ **已实施**（2026-10-15 Goal-2 Round 23）
> 依赖：P2c wiring（实施后接线，`model_router_ops.mbt` 仍 WIP）；不阻塞 P2c（纯函数层独立实现）
> 更新者：caf-agent
> 更新日期：2026-10-15（Goal-2 Round 23 实施）

> **实施记录（Round 23）**：用独立文件 `src/router/router_caf_ext.mbt` 实施（零冲突，不碰并发 agent WIP 的 `router_caf.mbt`）。
> 新增 `caf_soft_reorder_with_preference` + 7 条测试（`src/router/router_caf_ext_wbtest.mbt`）。
> 验证：`src/router` 145/145（138+7），全仓 1124/1124 零回归。
> 剩余：接线到 `model_router_ops.mbt` 的 P2c wiring 中（依赖 P2c 释放）。

> **A/B 预演（Round 25）**：`scripts/caf_p2d_coldstart_ab.py` 验证冷启动偏好的**场景依赖**性质：
> - **成本敏感场景**：baseline（选最便宜的）最优，每成功成本 2.000。**P2d 反而不优**（2.703）。
> - **成功率敏感场景**：P2d（偏好高成功率）最优，成功率 91.0% vs baseline 50.0%。**P2d 优于 baseline 41 个百分点**。
> **结论**：默认偏好不应盲目设成"选成功率最高的"，应**按业务目标配置**（成本敏感 → 成本最低；成功率敏感 → 成功率最高）。

## 0. 问题陈述

P2c wiring 完成后，`use_caf_memory=true` 但记忆为空时，`caf_soft_reorder` 返回原序（零回归，已测试）。
但冷启动阶段（记忆 < 阈值）时，路由没有偏好——如果原序是 `m_free, m_mid, m_premium`，
冷启动时每次都选 `m_free`，可能因 `m_free` 成功率低而浪费成本。

**目标**：记忆不足时，让路由有"默认偏好"（如按配置的模型优先级排序）。

## 1. 设计原则

- **零回归**：不修改 `caf_soft_reorder` 签名（现有 32 条测试保持不动）。
- **新增函数**：`caf_soft_reorder_with_preference` 作为扩展。
- **默认关闭**：偏好为空时行为与 `caf_soft_reorder` 完全一致。
- **纯函数**：不 IO，不依赖 P2c wiring 的实现细节。

## 2. 变更集（P2d 最小改动）

### 2.1 新增函数：`caf_soft_reorder_with_preference`

文件：`src/router/router_caf.mbt`

```moonbit
///| 冷启动启发式：
///| 当记忆不足（stats 为空或 total < min_evidences）时，
///| 按 default_preference 排序候选（偏好在前的优先）。
///| 记忆充足时退化为 caf_soft_reorder（纯成功率/成本排序）。
///| preference 为空 → 行为与 caf_soft_reorder 完全一致（零回归）。
pub fn caf_soft_reorder_with_preference(
  candidates : Array[String],
  stats : Array[CafModelStats],
  default_preference : Array[String],
  min_evidences : Int,
) -> Array[String] {
  // 记忆充足 → 退化为 caf_soft_reorder
  if stats.length() > 0 && evidence_total(stats) >= min_evidences {
    return caf_soft_reorder(candidates, stats)
  }
  // 记忆不足 → 按偏好排序（偏好在前的优先），偏好外的保持原序
  if default_preference.length() == 0 {
    return candidates
  }
  let mut result : Array[String] = []
  let mut rest : Array[String] = candidates
  for pref in default_preference {
    // 找到 pref 在 rest 里的位置，取出并加入 result
    let mut idx = -1
    for i in 0..<rest.length() {
      if rest[i] == pref {
        idx = i
        break
      }
    }
    if idx >= 0 {
      result = result + [rest[idx]]
      rest = remove_at(rest, idx)
    }
  }
  // 剩下的按原序追加
  for r in rest {
    result = result + [r]
  }
  result
}
```

辅助函数 `evidence_total` 和 `remove_at` 需新增：

```moonbit
///| 统计所有模型的 evidence 总数
fn evidence_total(stats : Array[CafModelStats]) -> Int {
  let mut total = 0
  for s in stats {
    total = total + s.total
  }
  total
}

///| 从数组中删除指定索引元素（返回新数组）
fn remove_at(arr : Array[String], idx : Int) -> Array[String] {
  let mut out : Array[String] = []
  for i in 0..<arr.length() {
    if i != idx {
      out = out + [arr[i]]
    }
  }
  out
}
```

### 2.2 新增测试：`caf_soft_reorder_with_preference`

文件：`src/router/router_caf_wbtest.mbt`

- `caf_pref_empty_baseline`：preference 空 + 记忆不足 → 返回原序（零回归）
- `caf_pref_memory_enough_fallback`：记忆充足 → 退化到 `caf_soft_reorder`（成功率排序）
- `caf_pref_orders_preference`：记忆不足 + preference=[m_premium, m_mid, m_free] → 按偏好排序
- `caf_pref_unknown_preference`：preference 里的模型不在候选 → 跳过，不 panic
- `caf_pref_preserves_unmatched`：preference 外的候选保持原序追加

### 2.3 接线（P2c wiring 之后）

文件：`src/server/model_router_ops.mbt`（P2c wiring 中加）

```moonbit
// P2c wiring 里加：
if use_caf_memory {
  // 记忆不足且配置了默认偏好 → 用冷启动启发式
  let ordered = caf_soft_reorder_with_preference(
    candidates, knn_stats, config.caf_default_preference, config.caf_min_evidences
  )
  ...
} else {
  // 现有逻辑
  ...
}
```

RouterConfig 新增字段（`src/router/model_router.mbt`）：

```moonbit
pub struct RouterConfig {
  ...
  ///| P2d：冷启动默认偏好（记忆不足时按此排序，空=零回归）
  caf_default_preference : Array[String],
  ///| P2d：记忆充足阈值（默认 10 条 evidence）
  caf_min_evidences : Int,
}
```

`default()` 中初始化为 `[]` 和 `10`。

## 3. 验收标准

1. **零回归**：`caf_soft_reorder_with_preference(candidates, [], [], _)` == `caf_soft_reorder(candidates, [])` == 原序
2. **冷启动偏好**：记忆不足 + `default_preference=[m_premium]` → `m_premium` 排第一
3. **记忆充足退化**：记忆充足 → 与 `caf_soft_reorder` 一致（成功率排序）
4. **偏好外的候选保持原序**：`preference=[m_premium]`，候选 `[m_free, m_mid, m_premium]` → 结果 `[m_premium, m_free, m_mid]`
5. **未知偏好安全**：`preference=["ghost"]` 不 panic，候选保持原序
6. **全仓零回归**：`moon test --target js` ≥ 1115/1115

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| 冷启动偏好可能选错模型 | 默认偏好可由用户配置；P2c 完成后可加"自适应默认偏好"（按历史平均成功率初始化） |
| 签名变化导致 .mbti 漂移 | 用新函数而非修改旧函数；加 pub fn 后跑 `moon info` 同步 .mbti |
| 与并发 agent 冲突 | router_caf.mbt 是 WIP（并发 agent 守卫）；实施前 `git status` 确认，若 WIP 则只写文档不写代码 |

## 5. 实施步骤（P2c wiring 释放后按序）

1. `git status` 确认 `src/router/router_caf.mbt` 干净（若非，等并发 agent 提交）
2. 按 2.1 加 `caf_soft_reorder_with_preference` + 辅助函数
3. 按 2.2 加 5 条测试
4. `moon fmt` + `moon info` + `moon test --target js src/router`（期望 143 全绿）
5. `moon test --target js`（全仓零回归，期望 ≥1115）
6. 接线到 `model_router_ops.mbt`（P2c 完成后）

## 6. 与 P2c 的关系

- **不阻塞 P2c**：P2c 实施 P2a/P2b 核心到 pick 流程；P2d 是独立扩展。
- **P2c 后接线**：P2c wiring 里加 `caf_soft_reorder_with_preference` 调用。
- **顺序**：P2c 优先（核心能力），P2d 次之（优化）。
- **验收标准 3（dry_run 预览）**：P2d 不影响标准 3，标准 3 仍由 P2c 的 dry_run 路径验证。

## 7. 资源估算

| 项 | 估算 |
|---|---|
| 代码行数（src/router） | ~60 行（函数 + 辅助） |
| 测试行数（src/router_wbtest） | ~60 行（5 条测试） |
| 接线行数（model_router_ops） | ~10 行（P2c wiring 里加） |
| 全仓测试数 | 1115 → ~1120（+5） |