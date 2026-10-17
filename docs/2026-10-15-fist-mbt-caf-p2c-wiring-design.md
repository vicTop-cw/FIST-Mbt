# CAF P2c 接线设计文档（为实施做准备）

- 日期：2026-10-15
- 前置：P2a（knn_search）+ P2b（caf_soft_reorder）已实现并验证（Round 4-8）
- 阻塞：`src/server/model_router_ops.mbt` 被并发 agent WIP
- 本文档：精确说明 P2c 接线的**最小改动集**，等 WIP 释放后照此实施

> **进度（Round 27）**：§2.1（RouterConfig 加 `use_caf_memory`）**已实施**（commit `7b5d96f`）；
> §2.2（pick_caf 软性重排钩子）**已实施**（commit `4b3b168`，落地形态为 `ModelRouter::pick_caf` 扩展
> 而非内嵌 `pick`，实现见 `src/router/model_router_caf.mbt`，4 回归锁 152/152 全绿）。
>
> **进度（Round 29）**：标准 3 的**纯计算部分**已落地（commit `54f172c`）——新增
> `CafDryRun` + `ModelRouter::pick_caf_dry_run`（零副作用 peek）+ `apply_caf`（从 `pick_caf` 拆出的
> 纯重排函数）+ `clone_for_peek`/`clone_pools`（pool 深拷贝 probe）。配套 3 条白盒锁
> `caf_dry_1~3`（落在 `src/router/model_router_caf_wbtest.mbt`，与 §2.2 测试同文件，
> 而非本文档 §2.4 原写的 `router_caf_wbtest.mbt`——那是并发 agent 的 WIP 域，避免抢占），
> router 156/156 全绿。server 层接线时只需：把 `caf_memory` 从进程内存传入 `pick_caf_dry_run`，
> 再把返回的 `CafDryRun` 序列化为 `{suggestion, basis}` 即可，无额外 router 层改动。
>
> **进度（Round 43，commit `c2feb31`）**：§2.3 的 **server 层接线已落地**——`model_route` 新增
> `dry_run`/`context` 参数，`model_route_impl` 在 Star 门之后、`consuming` 之前短路返回零副作用
> dry_run 预览（读 `memory/model-router-caf-{ns}.json` → `pick_caf_dry_run` → `caf_dry_run_to_json`），
> `use_caf_memory=false` 显式拒绝；默认路径逐字节不动。配套 `caf_dr_1~5` 白盒锁；
> `moon test --target js src/server` 321/321/0，全仓 1297/1297。**唯一剩余**：`executor_run` 成功后
> `caf_memory.push` 回写（本段下半）——否则 CAF 状态文件永为空、dry_run 恒返回空 basis。
>
> 剩余 §2.3 的**回写**（`executor_run` 后 `caf_memory.push`）与 **status 展示**仍依赖
> `model_router_ops.mbt` 释放（并发 agent WIP）。
>
> **进度（Round 30-31）**：
> - **R30（commit `132fcca`）** 新增 `caf_loop_1_记忆可写可读闭环`，钉死 §2.3 回写的真源前提：
>   `CafMemory::push` 的签名虽是值接收 `self : CafMemory`，但 `count`/`head` 改动**实测传播**
>   到调用方（0→1→3）——因此 server 层 `executor_run` 后调 `caf_memory.push(...)` 真的能写入，
>   同一份 memory 再传给 `pick_caf_dry_run` 就能让决策从 free-a 重排到 free-b。router 157/157 全绿。
> - **R31（commit `2a669ef`）** P2c 与 P2d 在 router 层**统一**：新增 `caf_reorder_combined`，
>   `pick_caf` / `apply_caf` / `pick_caf_dry_run` 都加
>   `caf_default_preference? : Array[String] = []` 与 `caf_min_evidences? : Int = 10`。
>   偏好为空 → 纯 `caf_soft_reorder`（与 R29 完全一致，零回归）；偏好非空 → `caf_soft_reorder_with_preference`
>   （记忆充足退化成功率排序、记忆不足按偏好冷启动）。3 条新锁 `caf_pref_1~3`，router 160/160 全绿。
>
> **剩余接线**：只剩 server 层两处——① `RouterConfig` 加 `caf_default_preference` /
> `caf_min_evidences` 字段（`src/router/model_router.mbt`，本轮未动，因该文件并发 agent 也有改动面）；
> ② `model_router_ops.mbt` 里 `executor_run` 后 `caf_memory.push` + 把 config 字段透传给 `pick_caf` +
> status 展示 CAF 统计。两处都等并发 agent WIP 收口。
>
> **进度（Round 32）**：status 展示的**纯计算部分**落地（`caf_memory_status_text`，
> `src/router/model_router_caf.mbt`）——把 `CafMemory` 渲染成按模型聚合的可读文本
> （`<模型>：<成功>/<总数> 成功 (<成功率>%)，均成本 <avg>`），空记忆渲染为「0 条记录」。
> 与 `pick_caf_dry_run` 同模式：接线前先把纯计算放好，server 层 `model_route` /
> `model_router_status` 只需调用它即可让 CAF 记忆状态可观测。配套 2 条白盒锁
> `caf_status_1~2`，router 162/162 全绿。
>
> **Round 32 教训（RouterConfig 字段改动面）**：尝试给 `RouterConfig` 加
> `caf_default_preference` / `caf_min_evidences` 时发现**侵入面过大**——全仓
> `window_seconds:` 构造点 24 处、仅 `use_caf_memory` 字段就在 3 个 wbtest 里出现 36 次，
> 且构造形状不一（block literal / 内联 `from_config({...})` / 变量名各异），regex 只匹配到
> 20/36。已**回退**该改动，把它列为独立子任务，与 §2.3 server 接线一起做（届时一次性改
> 构造点 + 接线，避免两次都撞 wbtest）。
> **给后续实施者的建议**：与其逐个补 36 处，不如先给 wbtest 引入一个集中构造 helper
> （如 `rt_cfg(...)` / `mrc_cfg(...)`），测试统一走 helper，将来再加字段只改一处；
> 但这是 wbtest 重构，应与接线分开提交。
>
> **Round 32 额外确认**：并发 agent 收口后全仓编译 0 errors（`moon info` 报告
> 563 warnings, 0 errors），`moon test --target js` 全绿（1158/1158），
> 依赖侧 BUG-133 修复 + 并发 WIP 的 3 errors 已清，全仓回归恢复——之前只能跑
> `src/router` 子集的门禁约束解除。
>
> **进度（Round 33）**：**§2.1 剩余部分（`RouterConfig` 两字段）已落地**——给 `RouterConfig`
> 加 `caf_default_preference : Array[String]`（默认 `[]`，零回归）与 `caf_min_evidences : Int`
> （默认 10），同步 `default()` / `from_json`（缺字段→默认，坏类型→默认 + warning）/
> `to_json` / `clone_pools` / `router_state` merge，并一次性补齐 20 处 wbtest 构造点
> （`model_router_wbtest` 17 + `model_router_caf_wbtest` 2 + `router_config_wbtest` 1）。
> **RouterConfig 字段改动面的真实读数**：全仓 `use_caf_memory:` 构造点 **24 处**（含 1 处
> `default()` 定义 + 1 处 `router_config_wbtest` 字符串断言），其中 **20 处**是真正要补的
> wbtest 构造点；regex 一次性 20/20 命中。**R32 报的「36 处」是误判**（把不同维度重复相加）。
> 配套 2 条验证锁 `caf_cfg_1`（默认值 + JSON 往返）/ `caf_cfg_2`（偏好字段从 config 读出
> 并透传 `pick_caf`），并更新 `cfg_ofm_2` 的顶层键集合锁（7→9，新字段须显式登记）。
> router 164/164 全绿。
>
> **§2.3 接线的 router 侧前提现已齐备**：字段已存在且可 JSON 往返、可被读出透传给
> `pick_caf`/`apply_caf`/`pick_caf_dry_run`。server 层接线只需——① `executor_run` 后
> `caf_memory.push(...)`；② 把 `config.caf_default_preference` / `config.caf_min_evidences`
> 透传给 `pick_caf`；③ status 展示用 `caf_memory_status_text`。**全部等
> `model_router_ops.mbt` 释放**（并发 agent WIP）。
>
> **Round 33 教训 · 构造点批量替换要 dry-run**：`moon check` 前先用 regex 统计匹配数
> 确认覆盖（本轮 dry-run 20/20，直接替换）；`Json` 无 `Int` 构造子，整数解析须用
> `Json::Number(n, ..)` → `n.to_int()`（沿用 BUG-26 的饱和语义，caf_min_evidences 属
> 上限型 Int，饱和不 panic）。替换后 `caf_cfg_2` 首个断言首跑失败——偏好==base 时
> 不 reordered，属**断言写错**而非代码错，已改为偏好 != base（free-b）再断言。

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
