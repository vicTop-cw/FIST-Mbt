# CAF 验收标准对照表

> 用途：把 CAF 四条验收标准的当前验证状态、证据来源、脚本路径归拢成一份可复用依据。
> 更新者：caf-agent
> 更新日期：2026-10-15（Goal-2 Round 18）
> 对应计划：`docs/2026-10-14-fist-mbt-router-caf-learning-plan.md` 的验收标准 §

## 四条验收标准与当前状态

| # | 验收标准 | 状态 | 验证方式 | 关键证据 | 脚本/测试 | 时间 |
|---|---|---|---|---|---|---|
| 1 | 离线回放可复现（历史记录回放 → 按成功率排序的模型优先级） | ✅ 已验 | Python 模拟 + `output_validate` l4-pass | 简单任务→`m_free`（rate 0.93），复杂任务→`m_premium`（rate 1.0） | `scripts/caf_offline_replay.py`（3/3 通过） | 2026-10-15 R12（commit `c45d6d6`） |
| 2 | 开启后不增成本且成功率不降（A/B 对比） | ✅ 已验（预演） | Python A/B 模拟 + `output_validate` l4-pass | A 率 0.59 / 成本 2.00 → B 率 0.63 / 成本 2.00（+0.04/+0.00） | `scripts/caf_p2c_ab_preflight.py`（2/2 通过） | 2026-10-15 R16（commit `3c72c27`） |
| 3 | dry_run 可预览（返回建议模型 + 历史依据） | 📋 待 P2c 接线后验证 | 依赖 P2c wiring 的 dry_run 路径 | 未验（需要 `model_router_ops.mbt` 实现） | 暂无 | 阻塞中 |
| 4 | 零回归基线（`use_caf_memory=false` 时行为与 v0.3.8 完全一致） | ✅ 已验 | MoonBit 白盒测试 | 空记忆 → `caf_soft_reorder` 返回原序；`caf_knn_stats_empty_neighborhood` 返回空 | `src/router/router_caf_wbtest.mbt`（135/135 全绿） | 2026-10-15 R13（commit `bd46d39`） |

## 四条标准的验证证据链

### 标准 1 · 离线回放

- **脚本**：`scripts/caf_offline_replay.py`
- **验证**：`python scripts/caf_offline_replay.py` → 3/3 通过（exit 0）
- **关键断言**：
  - 简单任务：Top-1 是 `m_free`（rate=0.93, cost=0.01）
  - 复杂任务：Top-1 是 `m_premium`（rate=1.0, cost=0.5）
  - 排列性质：排序结果对候选集置换保持不变
- **output_validate**：2 条产物检查全过（`caf_soft_reorder`、`caf_feature_hash` 存在且非空）→ **l4-pass**

### 标准 2 · A/B 对比（预演）

- **脚本**：`scripts/caf_p2c_ab_preflight.py`
- **验证**：`python scripts/caf_p2c_ab_preflight.py` → 2/2 通过（exit 0）
- **关键读数**：
  - A 组（关闭）：成功率 0.59，总成本 2.00
  - B 组（开启）：成功率 0.63，总成本 2.00
  - 差值：成功率 **+0.04**，成本 **+0.00**
- **output_validate**：1 条产物检查全过（`caf_soft_reorder` 存在且非空）→ **l4-pass**
- **⚠ 注意**：这是 **Python 预演**，非真源 MoonBit 实测。P2c 接线完成后需用真源复验。

### 标准 4 · 零回归基线

- **测试**：`src/router/router_caf_wbtest.mbt`
- **验证**：`moon test --target js src/router` → 135/135 通过
- **关键断言**（R13 新增 4 条）：
  - `caf_soft_reorder_tie_stable`：同 rate+cost 时 FIFO 稳定
  - `caf_soft_reorder_mixed_neighborhood`：邻域优先 + 非邻域保持原序
  - `caf_knn_search_k_greater_than_records`：k>records 返回全部；k=0/负防御
  - `caf_knn_stats_empty_neighborhood`：空记忆 → 空 stats + 零回归
- **零回归保证**：`use_caf_memory=false` 时 `pick` 不消费 CAF 记忆，行为与 v0.3.8 完全一致

## 阻塞点：标准 3

- **依赖**：P2c wiring（`model_router_ops.mbt` 的 `dry_run` 分支）
- **现状**：`model_router_ops.mbt` 被并发 agent WIP 占用（R18 时 26 文件 WIP）
- **解除条件**：并发 agent 完成 WIP → 实施 P2c → 用真源跑 dry_run 预览
- **预期产物**：`dry_run=true` 时返回 `{"suggestion": "m_mid", "basis": [{"model": "m_mid", "rate": 0.9, "avg_cost": 0.1, "count": 3}, ...]}` 形状

## 相关脚本与测试

| 路径 | 用途 | 状态 |
|---|---|---|
| `scripts/caf_offline_replay.py` | 标准 1 验证 | ✅ 通过（l4-pass） |
| `scripts/caf_p2c_ab_preflight.py` | 标准 2 预演 | ✅ 通过（l4-pass） |
| `src/router/router_caf.mbt` | 核心实现（32 个 pub fn） | ✅ 已合入 |
| `src/router/router_caf_wbtest.mbt` | 32 条白盒测试 | ✅ 135/135 全绿 |
| `docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` | P2c 接线设计文档 | ✅ 精度已修正 |

## 下一步

1. **阻塞解除后**：实施 P2c wiring（按设计文档 §2.1-§2.5）
2. **实施后**：用真源 MoonBit 复验标准 2 和标准 3
3. **实施后**：跑全仓回归（当前基线 1112/1112，CAF 135/135）
4. **实施后**：把本对照表更新为全部 ✅