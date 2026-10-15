# CAF P2c 接线设计文档（为实施做准备）

- 日期：2026-10-15
- 前置：P2a（knn_search）+ P2b（caf_soft_reorder）已实现并验证（Round 4-8）
- 阻塞：`src/server/model_router_ops.mbt` 被并发 agent WIP
- 本文档：精确说明 P2c 接线的**最小改动集**，等 WIP 释放后照此实施

> **进度（Round 26）**：§2.1（RouterConfig 加 `use_caf_memory`）**已实施**（commit `7b5d96f`）。
> 剩余 §2.2（pick 钩子）与 §2.3（回写 + status）依赖 `model_router_ops.mbt` 释放（并发 agent WIP）。

## 1. 目标

让 CAF 记忆层真正**参与路由决策**，而不仅是静态记忆：

- 加 `router.use_caf_memory` 配置项（默认 false → 零回归）
- 在 `ModelRouter::pick` 加 `caf_prefer_model?` 软性排序钩子（消费 `caf_soft_reorder`）
- `model_router_status` 展示 CAF 记忆统计
- 每次 `executor_run` 完成后回写 `caf_memory.push`

## 2. 最小改动集（按文件）

### 2.1 `src/router/model_router.mbt`（**RouterConfig 真源所在，非 router_config.mbt**）

```moonbit
// 既有 struct（line 281）：
pub struct RouterConfig {
  window_seconds : Int
  threshold_pct : Double
  free_models : Array[ModelQuota]
  paid_models : Array[ModelQuota]
  ofm_endpoint : String
  use_laya : Bool        // ← 既有字段，Bool 默认 false
} derive(Eq, Debug)

// P2c 加一个配置项（与 use_laya 同款形态）：
pub struct RouterConfig {
  // ... 既有字段 ...
  // CAF 记忆开关：默认关闭（零回归），开启后 pick 用 caf_soft_reorder 软性排序
  use_caf_memory : Bool,
}
```

- **用 `Bool` 而非 `Bool?`**：与既有 `use_laya` 保持**同款形态**（既有字段是 `Bool`，混用两种形态会让 `from_json`/`to_json` 的解析/序列化逻辑分裂）。默认 `false` = 零回归。
- **同步改动点**（同文件内）：
  - `RouterConfig::default()`（line 302）加 `use_caf_memory: false`
  - `RouterConfig::from_json()`（`src/router/router_config.mbt:9`）解析 `"use_caf_memory"`（true/false/null/garbage → 与 `use_laya` 同口径）
  - `RouterConfig::to_json()`（`src/router/router_config.mbt:246`）序列化该字段
- **注意**：`router_config.mbt` 只含 `from_json`/`to_json` 两个**方法**，struct 定义在 `model_router.mbt`。改字段时不要漏掉任何一边，否则 `.mbti` 与调用面会脱钩。

### 2.2 `src/router/model_router.mbt`（pick 钩子）

在 `ModelRouter::pick` 的**配额筛选之后、最终返回之前**插入软性排序：

```moonbit
// 现状（伪代码）：
// 1. 筛选 free_pool 中配额未耗尽的模型 → candidates: Array[String]
// 2. laya_prefer_tier? → 软性重排
// 3. 返回 candidates[0]

// 新增（P2c）：
let candidates2 = match config.use_caf_memory {
  Some(true) => {
    // 用当前请求的 context 做 kNN 检索，取 Top-K 邻域统计
    let stats = caf_memory.knn_stats(context, k=32)
    caf_soft_reorder(candidates, stats)
  }
  _ => candidates,
}
// 后续用 candidates2 替代 candidates
```

**关键不变量**：
- `caf_soft_reorder` 只做**置换**，不增不减候选集 → 配额硬约束不破
- `use_caf_memory=None/false` → 原路径，零回归
- `knn_stats` 空（无记忆）→ `caf_soft_reorder` 返回原序（已测试）

### 2.3 `src/server/model_router_ops.mbt`（回写 + status 展示）

**回写**（`executor_run` 成功/失败后）：

```moonbit
// executor_run 拿到 executor 结果后：
let ok = ... // 执行结果
let cost = ... // 实际成本
caf_memory.push(
  CafRecord::new(
    feature_hash=caf_feature_hash(context),  // 与 knn_search 同源
    model=model,       // 路由选出的模型
    ok=ok,
    cost=cost,
    ts=now_iso(),      // 服务端盖章
  ),
)
```

**status 展示**（`model_router_status` 返回值）：

```moonbit
// 在返回 JSON 里追加：
"caf_memory": {
  "enabled": config.use_caf_memory,
  "count": caf_memory.count,
  "max_size": caf_memory.max_size,
  "total_records": caf_memory.to_json().total_records,
  ...
}
```

### 2.4 `src/router/router_caf_wbtest.mbt`（新增回归测试）

```moonbit
test "caf_p2c_pick_hook_no_regression" {
  // 1. use_caf_memory=None → pick 结果与无 CAF 时一致
  // 2. use_caf_memory=Some(false) → 同上
  // 3. use_caf_memory=Some(true) + 空记忆 → 同上
  // 4. use_caf_memory=Some(true) + 有记忆 → 软性重排生效但配额约束保持
}
```

## 3. 验收清单

- [ ] `moon test --target js src/router` 全绿（含新回归测试）
- [ ] `moon test --target js`（全仓）零回归
- [ ] `moon info` 同步 `.mbti`
- [ ] `use_caf_memory` 默认关闭时，`model_router_status` 显示 `enabled: false` 且 `caf_memory.count: 0`
- [ ] `executor_run` 后 `caf_memory.count` 增加 1
- [ ] `moon fmt --check` 通过

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| `pick` 变慢（kNN O(count*k)） | `k=32` + 环形表 ≤10000 → O(320k) 可忽略；`knn_stats` 用 Top-K 而非全量 |
| 软性重排破坏配额 | `caf_soft_reorder` 只置换不增删（已测试置换性） |
| `use_caf_memory=true` 但记忆为空 | `caf_soft_reorder` 返回原序（已测试空 stats） |
| 并发 agent 已改了 `model_router_ops` | 本文档是**增量**说明，不覆盖其 WIP；实施时先 `git diff` 再审 |

## 5. 实施步骤（WIP 释放后按序）

1. `git status` 确认 `src/server/model_router_ops.mbt` 干净
2. `git log --oneline -5` 确认并发 agent 无新冲突提交
3. 按 2.1 → 2.2 → 2.3 → 2.4 顺序改
4. `moon fmt` → `moon info` → `moon test --target js src/router` → `moon test --target js`（全仓）
5. `git commit` 分 2-3 个原子提交：
   - `config + pick hook`（src/router/）
   - `server wiring`（src/server/）
   - `test + docs update`

## 6. 参考

- 计划原文：`docs/2026-10-14-fist-mbt-router-caf-learning-plan.md`
- 实现基线：`src/router/router_caf.mbt`（P2a/P2b 已完成，130+ 测试）
- 钩子模式参考：`src/router/model_router.mbt:652` `laya_prefer_tier?`
