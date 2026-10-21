# Goal-2 Round 39 报告：CAF 重排成功率不降契约锁（验收标准 2 纯计算侧收尾）

- **日期**：2026-10-15
- **提交**：R39 code（`src/router/router_caf_rate_monotone_wbtest.mbt`，1 文件 +62）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9），本轮补**标准 2「成功率不降」的缺失契约锁**

## 结果摘要

### 寻虫：成功率不降缺锁

标准 2 要求「开启后不增成本**且成功率不降**」。R38 已钉「不增成本」（`caf_cost_1/2`），
但**未钉「成功率不降」**：现有锁 `caf_dry_2` 只测 base/picked **不同**（对照语义），
**未测方向**——若 CAF 把 base 的 free-a（rate 0.5）重排到 rate 更低的模型，测试不会红，
而那是**成功率下降**，违反标准 2。

### 补 1 条契约锁（whitebox，复用 `mrc_router/mrc_memory/mrc_now` helper）

`src/router/router_caf_rate_monotone_wbtest.mbt`，用 `pick_caf_dry_run` 生成真实 `CafDryRun`，
从 `basis` 反查 base/picked 的 rate（`caf_dry_rate` helper，找不到返回 0）：

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_rate_1_重排后成功率不低于base` | base=pick→free-a（rate 0.5），CAF 重排→free-b（rate 1.0），断言 picked rate ≥ base rate 且**严格提升**（>） | picked rate=1.0 > base rate=0.5 |

**关键**：断言 `picked_rate > base_rate`（严格），且锁定 base=free-a/picked=free-b 场景——
证明 CAF 重排是「把低成功率 base 替换成高成功率 picked」的正向提升，而非随机抖动。

### 至此标准 2 纯计算侧**完整**

| 子契约 | 锁 | 轮次 |
|---|---|---|
| 不增成本（同 rate cost 决胜） | `caf_cost_1` | R38 |
| 邻域优先胜过成本（防无依据排前） | `caf_cost_2` | R38 |
| 成功率不降（重排后 rate ≥ base） | `caf_rate_1` | R39 |

标准 2 纯计算侧三格齐。剩余只有接线后的**真源复验**（Python 预演 → MoonBit 实测）。

### 验证

router **180/180**（R38 基线 179 + 1 锁）；全仓 **1186/1186**，0 failed。
`.mbti` **无变化**（whitebox 测试不新增 pub API）。

## 资源消耗

`moon fmt` / `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped）

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，新测试文件独占。

## 遗留风险

- **§2.3 server 接线仍未做**。CAF 四条验收标准的**纯计算侧现已全部就绪**：
  标准 1（离线回放）/ 标准 2（成本 + 成功率契约锁）/ 标准 3（`pick_caf_dry_run` + `caf_dry_run_to_json`）/ 标准 4（零回归基线）。
  接线本体（`model_router_ops.mbt` dry_run/executor_run 分支）仍待并发 agent 释放。
- **标准 2 的真源复验**：R16 是 Python 预演（A 0.59/B 0.63 成功率、成本均 2.00），接线后需 MoonBit 真源复验。
- **并发 agent WIP**：工作树 96 文件，`model_router_ops.mbt` 4/9。

## 后续建议

1. **R40 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。接线时 server 层：
   - dry_run 分支：`pick_caf_dry_run(...)` → `caf_dry_run_to_json(dr)` → 标准 3 形状 JSON
   - executor_run 分支：`caf_memory_load` 恢复 → `pick_caf` → `caf_memory_dump` 落盘 → status 用 `caf_memory_status_text`
2. **R40 备选**：CAF 记忆容量上限与淘汰策略审查（`max_size` 默认 10000，软淘汰需在 `CafMemory` 内，并发域）。
3. **R40 备选 2**：`caf_feature_hash` 碰撞风险——多项式 hash 对语义相近的不同字符串（如 "python" vs "python "）
   产生不同特征，记忆碎片化。建议接线时归一化 context（trim + lowercase）再 hash。
4. **R40 备选 3**：标准 1 的 MoonBit 真源锁（离线回放目前是 Python `caf_offline_replay.py` 验证，
   可补 MoonBit 侧「按成功率排序的模型优先级」契约锁）。

## 超额内容

**helper 复用模式验证**：whitebox 测试文件间可互相调用 `_wbtest.mbt` 里的 `fn` helper
（`mrc_router/mrc_memory/mrc_now` 定义在 `model_router_caf_wbtest.mbt`，R37 的 `caf_dj_*` 与
R39 的 `caf_rate_1` 都能直接调用）——这是 CAF 测试族的低成本扩张路径，无需重复构造。

## 来源

- 代码（只读审查）：`src/router/router_caf.mbt` L380-396（`caf_soft_reorder` 排序键）
- 新增：`src/router/router_caf_rate_monotone_wbtest.mbt`
- helper 来源：`src/router/model_router_caf_wbtest.mbt`（`mrc_router/mrc_memory/mrc_now`）
- 参考：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md`（标准 2 A/B 预演 R16）
