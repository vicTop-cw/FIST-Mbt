# Goal-2 Round 48 报告：标准 1 混合邻域排列不变真源锁

- **日期**：2026-10-15
- **提交**：R48 code（`src/router/router_caf_replay_distinct_test.mbt` 追加 `caf_c1_5`，纯测试，HEAD `11b6708`）
- **状态**：§2.3 server 接线仍阻塞（连续 11 轮）；本轮补标准 1 排列性质的**混合邻域**分支锁

## 结果摘要

### 接线阻塞确认

`model_router_ops.mbt` 仍 `4/9`（连续 11 轮 R38-R48）。**新增**：并发 agent 本轮提交
`56633bc fix: gitcode 队列三处写入失败静默丢弃 (BUG-223)` + `85572a2 docs: 注册 BUG-223 台账`。
修复的是 **BUG-223**（gitcode 队列写入失败静默丢弃），**非** BUG-185/186/217 重复条目。
`bugreport.mbt` 仍 WIP（8/2）。

### 寻虫结论：全仓无新 bug（MoonBit 区间用法正确）

从 R47 的 `for i in 0..<=2` 越界 panic 出发，**系统排查全仓 9 处 `for x in N..<=M`**：

| 位置 | 循环 | 判定 |
|---|---|---|
| `probe_difficulty_wbtest.mbt:5` | `for split_n in 3..<=6` | ✅ 非数组索引，合法 |
| `probe_difficulty_wbtest.mbt:9` | `for idx in 1..<=split_n` | ✅ 非数组索引 |
| `probe_difficulty_wbtest.mbt:40` | `for split_n in 1..<=6` | ✅ 非数组索引 |
| `diff.mbt:50/52` | `for i in 0..<=n` + `for _j in 0..<=m` | ✅ LCS DP 表尺寸 **(n+1)×(m+1)**，闭区间建边界行/列 |
| `diff.mbt:57/58` | `for i in 1..<=n` + `for j in 1..<=m` | ✅ 访问 `dp[i]`，i ≤ n < n+1，合法 |
| `call_log_test.mbt:80` | `for i in 1..<=3` | ✅ 非数组索引 |
| `router_caf.mbt:264` | `for j in 0..<=m` | ✅ Levenshtein `prev` 表尺寸 m+1，合法 |

**结论**：全仓 9 处闭区间都是**有意 DP**（表尺寸 N+1），`0..<=N` 恰好索引到 N 维表边界。**R47 的坑**
是「**索引恰好 length 的数组**」（我的 `caf_c1_4` 用 `0..<=2` 遍历 0,1,2 却数组长度 2）。
全仓现有代码用「索引 length+1 的表」→ 合法。**无新 bug**。

**MoonBit 区间语义记录**（R47+R48 双轮验证）：
- `0..<2` = 半开 [0,2)，遍历 0,1（Rust/Python `range(len)` 同族）
- `0..=2` / `0..<=2` = 闭区间 [0,2] **含 2**（与多数语言 `..=` 同义）
- **moon fmt 把 `0..2` 规范化为 `0..<=2`（闭区间含 end）** → 索引数组会越界
- **写数组循环必须 `0..<len`**（半开动态）；写 DP 表刻意 `0..<=N`（表尺寸 N+1）

### 实质产出：caf_c1_5 混合邻域排列不变锁

`caf_c1_4` 只锁「候选**都在邻域**且 rate 互不相同」。但 `caf_soft_reorder` 实现在
`src/router/router_caf.mbt` L361-417 有一分支：**都不在邻域 → 保留原始顺序**。

**混合场景**（部分候选在邻域、部分不在）是现实中更常见的形状——候选集可能含
「有历史依据的模型」（m_free/m_premium）+「无依据的新模型」（m_unknown）。

补 `caf_c1_5_混合邻域排列不变`：
- 候选 3 模型：`[m_free, m_premium, m_unknown]` vs 置换 `[m_unknown, m_premium, m_free]`
- 断言：
  1. 首位恒为 rate 1.0 的 `m_premium`（邻域内，与输入顺序无关）
  2. **末位恒为无依据的 `m_unknown`**（邻域外，恒排有依据之后）
  3. 完整序列逐位置一致（`0..<len` 半开，R47 教训）

**至此标准 1 排列性质两分支锁齐**：都在邻域（caf_c1_4）+ 混合邻域（caf_c1_5）。

### 工具链教训：pwsh StreamWriter 绝对路径落盘（R48 新坑）

**caf_c1_5 前两次写盘失败**：
1. `Add-Content <rel>` → 显示「追加完成」但文件未变（静默失败）
2. `edit` 工具 → 返回成功但文件未变
3. `pwsh StreamWriter($absolutePath, append=true, UTF8-noBOM)` → **立即验证命中行 197**，落盘成功

**根因**：相对路径写盘在本会话不可靠（疑似 sandbox/后端路径解析问题）。**教训**：
写文件用 `pwsh` + `[System.IO.StreamWriter]` + **绝对路径**（`Join-Path $PWD ...`），
写后**立即 grep 验证**，不依赖工具返回的「成功」。

### 并发观察

并发 agent 本轮推进：`model_router_ops.mbt`（4/9）、`router_caf.mbt`（WIP）、`bugreport.mbt`（8/2）、
`ops_hats.mbt`（六顶帽）、`bugreport_status_wbtest.mbt`。新增 BUG-223 修复（gitcode 队列）。
**均不越界**。

## 验证

- router **201/201**（R47 200 + caf_c1_5），0 failed
- 全仓 **1212/1212**（HEAD 85572a2 的 1211 + caf_c1_5），0 failed
- `.mbti` 无变化（纯测试追加，无新 pub fn）
- `moon fmt --check` 通过
- 改动范围：`37+ 0-`（纯追加，仅 caf_c1_5）

## 资源消耗

查接线释放（4/9）/ 重扫 docs 未实现计划（13 命中，P2c 相关全阻塞）/
读 `p2d-cold-start-design.md`（已实施 R23）/ 查 boundary_probe（已实施）/
读 CAF learning-plan 待办面（接线相关全阻塞）/ **grep 全仓 `for x in N..<=M` 寻虫**（9 命中）/
读 `diff.mbt` + `router_caf.mbt` 判定 DP 合法 / **两次写 caf_c1_5 失败（Add-Content + edit）** /
第三次 StreamWriter 绝对路径成功 / `moon fmt` + `moon test --target js src/router` / 全仓回归 /
`git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/router_caf_replay_distinct_test.mbt`
（`model_router_ops.mbt`/`router_caf.mbt`/`bugreport.mbt`/`bugreport_status_wbtest.mbt`/`ops_hats.mbt` 均 WIP/并发已避开；`.mbti` 未动证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，连续 11 轮）。接线前置四契约齐备 + 标准 1/2/3/4 真源锁齐备，接线成本已最小化。
- **标准 2 的接线后端到端复验**仍待接线完成（R46 只闭合纯计算侧）。
- **标准 3 的 server 层 dry_run 零副作用锁**仍待接线。
- **并发 WIP 面持续**：BUG-223 已修复，但 `bugreport.mbt` 仍 8/2、`router_caf.mbt` 仍 WIP。
- **工具链写盘不可靠**：相对路径写文件在本会话需 StreamWriter 绝对路径，写后必须 grep 验证。

## 后续建议

1. **R49 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。四契约 + JSON 层 + 标准 1/2/4 锁齐备，接线照抄。
2. **R49 备选**：标准 2 接线后端到端复验（接线完成前提）。
3. **R49 备选 2**：标准 3 server 层 dry_run 零副作用锁（接线后）。
4. **CAF 检索侧**：`router_caf.mbt` 释放后可补 knn_search 邻域收敛终验锁（R44 已锁 topk/boundary/k>records）。

## 来源

- `docs/2026-10-15-fist-mbt-caf-acceptance-status.md` L32（标准 1 排列性质声明）
- `src/router/router_caf.mbt` `caf_soft_reorder`（L361-417 混合邻域分支）
- `src/diff/diff.mbt` L42-69（LCS DP 表尺寸 n+1，闭区间合法参照）
- 新增锁：`src/router/router_caf_replay_distinct_test.mbt` `caf_c1_5_混合邻域排列不变`
