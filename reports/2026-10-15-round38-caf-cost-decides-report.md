# Goal-2 Round 38 报告：CAF 路由成本决胜契约锁（验收标准 2 纯计算侧）

- **日期**：2026-10-15
- **提交**：R38 code（`src/router/router_caf_cost_decides_test.mbt`，1 文件 +102）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9），本轮补**标准 2 的缺失契约锁**

## 结果摘要

### 寻虫：成本决胜缺契约锁

审查 `caf_soft_reorder` 排序键（`src/router/router_caf.mbt` L380-396）：
**邻域内 → rate 降序 → `avg_cost` 升序 → 稳定序（原始位置）**。

成本（`avg_cost`）确实参与路由（rate 平局时 cost 决胜），这支撑标准 2「开启后不增成本」。

但**现有契约锁有盲区**：`caf_soft_reorder_tie_stable` 只测「同 rate + 同 cost → FIFO 稳定」，
**没测「同 rate 但 cost 不同 → cost 低优先」**。

**风险**：若未来重构把 cost 从排序键里漏掉（或降级为纯展示），测试**不会变红**——
`caf_soft_reorder_tie_stable` 依然通过（它只关心平局 FIFO）。而漏掉 cost 意味着
CAF 会在同成功率下选更贵的模型 → **违反标准 2**。这是「寻虫发现缺口、补锁闭环」。

### 补 2 条契约锁（blackbox，纯 pub API）

`src/router/router_caf_cost_decides_test.mbt`，stats 由真实 `CafRecord` 记忆经 `caf_stats` 聚合生成
（全 pub API，避开 `CafModelStats` 字面量构造的语法歧义——第一次写用 struct 字面量被 `moon fmt`
简写后编译报 [4036]/[4033]，改用 `CafRecord + caf_stats` 后稳过）：

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_cost_1_同率不同成本_成本低优先` | 同 rate=1.0 时，avg_cost=10 的 free-a 排到 avg_cost=0.1 的 free-b 之后 | 排序后 out[0]=="free-b" |
| `caf_cost_2_邻域优先胜过成本` | 只有 free-a 有依据（rate 0.5, cost 0.1）→ free-a 先，防「为省成本把无依据模型排前」 | out[0]=="free-a" |

**关键**：这两条**当前全绿**（cost 决胜确实生效，非 bug），是**防护锁**——
它们钉死「cost 必须参与路由」这一标准 2 前提，未来改动若破坏会**立刻变红**。

### 验证

router **179/179**（R37 基线 177 + 2 锁）；全仓 **1185/1185**，0 failed。
`moon info src/router` 0 errors，`.mbti` **无变化**（blackbox 测试不新增 pub API）。

## 资源消耗

`moon fmt` / `moon test --target js src/router` / `moon info src/router` / 全仓回归 / `git commit`（path-scoped）

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，新测试文件独占。

## 遗留风险

- **§2.3 server 接线仍未做**。标准 3 的纯计算侧已完整（R37 `pick_caf_dry_run` + `caf_dry_run_to_json`），
  标准 2 的纯计算侧契约已补锁（R38 `caf_cost_1/2`）。但接线本体（`model_router_ops.mbt` dry_run/executor_run 分支）仍待并发 agent 释放。
- **标准 2 的「成功率不降」** 纯计算侧仍缺锁：现有锁钉了「成本不增」（R38）与「邻域优先」（R38），
  但**未钉「CAF 重排后成功率 ≥ base」**（`caf_dry_2` 对照语义测了 base/picked 不同，未测成功率方向）。
  R39 可选补「重排后模型的成功率 ≥ base 模型成功率」锁。
- **并发 agent WIP**：工作树 96 文件，`model_router_ops.mbt` 4/9。`memory/bugs.md` 本轮回执显示不再 staged
  （并发 agent 或已自己 commit/reset）。

## 后续建议

1. **R39 首选**：补标准 2 的「成功率不降」契约锁——CAF 重排后 picked 模型的 rate ≥ base 模型的 rate
   （用 `CafDryRun.basis` 反查 rate 比较），补齐标准 2 纯计算侧的最后一格。
2. **R39 备选**：§2.3 接线（`model_router_ops.mbt` 释放后）。
3. **R39 备选 2**：CAF 记忆容量上限与淘汰策略审查（`max_size` 默认 10000，软淘汰需在 `CafMemory` 内，并发域）。
4. **R39 备选 3**：`caf_feature_hash` 的碰撞风险——多项式 hash（Java 变体）对语义相近的不同字符串
   （如 "python" vs "python "）产生不同特征，记忆碎片化。建议 server 层接线时归一化 context
   （trim + lowercase）再 hash，属接线配套。

## 超额内容

**语法经验**：MoonBit `moon fmt` 会把 `Type::{field: var}` 简写成 `Type::{field}`（字段简写），
但对 `CafModelStats` 报 [4036]/[4033]。**测试优先用 `CafRecord + caf_stats` 生成 `Array[CafModelStats]`**
（全 pub API），避开 struct 字面量构造的语法歧义。

## 来源

- 代码（只读审查）：`src/router/router_caf.mbt` L380-396（`caf_soft_reorder` 排序键）、L104（`CafModelStats`）
- 新增：`src/router/router_caf_cost_decides_test.mbt`
- 参考：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md`（标准 2 A/B 预演 R16）
