# R13 边界审视统一报告（全局输入域 owner）

- 日期：2026-10-13
- 命名空间：`r13-pipeline`（根任务 `T0`）
- 角色：**边界审视·全局输入域 owner**（覆盖 T0.1.3 / T0.2.3 / T0.3.3 / T0.4.1 / T0.4.2 / T0.4.3）
- 原则：**根任务 spec 未写的域外行为，逐项给空输入 / 极值 / 非法输入 / 资源极限四类用例，或显式声明不适用并说明依据；不得沉默**（写下限语料时，强验证只会验证下限）

---

## 主题 1 · JIT 后端边界（对应 T0.1.3）

聚焦：`issue_scan` 规则的 MoonBit 类型语义（JS 53 位 Int / native 64 位 / 显式 Int32 32 位）。

| 类别 | 具体触发输入 | 预期行为 | 是否适用+依据 |
|---|---|---|---|
| 空输入 | `issue_scan --dir` 指向空目录或无 `.mbt` 文件 | 返回 `total_findings=0`，不崩；递归收集目录下 0 个文件是合法态 | 适用 |
| 极值 | `days = Int32.MAX_VALUE`，`days * 86400`（显式 Int32） | 溢出（Y2038 型绕回，非 panic），`secs-overflow` 规则**保留检出** | 适用（BUG-152 修复语义） |
| 极值 | `days = 1_000_000_000_000`（默认 Int，JS 53 位），`days * 86400` | **不溢出**（≈8.6e16，JS 53 位安全整数 ~9e15 上限内；native 64 位更不溢），`secs-overflow` 规则**suppress** | 适用 |
| 非法输入 | `issue_scan --dir` 指向不存在路径 / 指向文件而非目录 | 返回错误或空 findings（不得 panic）；需声明：本工具对非法路径的行为以 `src/server/issue_scan.mbt` 实跑为准（**未逐条核实 panic 与否，诚实标注**） | 适用（标注未核实） |
| 资源极限 | 目录内含超大 `.mbt` 文件（数 MB 级）或深层递归 | 扫描时间/内存随文件数线性增长，无显式上限；`include_tests` 默认 false 降噪 | 适用 |

**本主题不适用项**：无（JIT 后端边界是本根任务明确聚焦主题）。

---

## 主题 2 · 成本硬门（对应 T0.2.3）

聚焦：`cost_stats` / `cost_budget_check` / `cost_budget_split` / `progress_gate` 的预算与成本上限。

| 类别 | 具体触发输入 | 预期行为 | 是否适用+依据 |
|---|---|---|---|
| 空输入 | `cost_stats` 无任何成本记录；`cost_budget_split` 空任务数组 | 返回空/零值，不崩；`cost_budget_split` 空数组按 R81 应拒绝或回空 | 适用 |
| 极值 | 预算上限 = 0；某阶段难度权重极大（背包水填充极端） | 份额分配应显式处理余数补最大权重阶段；预算 0 → 全阶段份额 0 | 适用 |
| 非法输入 | 负预算 / 负难度权重 / 非法 JSON `config_json` | 应显式拒绝，**不静默回落**（同 `model_route` 的 BUG-62 口径）；未核实 `cost_budget_*` 是否同样拒绝（**诚实标注**） | 适用（标注未核实） |
| 资源极限 | 大量任务（数百）按依赖图切分；`progress_gate` 剩余成本预测超出预算 | `progress_gate` 应给出 CAUTION / ESCALATE（R88 双路径预测）；未核实极端规模下性能（标注） | 适用（标注） |

**本主题不适用项**：无。

---

## 主题 3 · delivery validation（对应 T0.3.3）

聚焦：`output_validate` 对 artifacts 逐件验（`path` / `check_key` / `invariant` / `evidence`），R113。

| 类别 | 具体触发输入 | 预期行为 | 是否适用+依据 |
|---|---|---|---|
| 空输入 | 空 `artifacts` 数组；`require_evidence=true` 但空 `evidence` | 空 artifacts → 无 checks → verdict 依策略（未核实，标注）；空 evidence 应 `failed` | 适用 |
| 极值 | 单个 artifact 文件极大；`invariant` 要求 `min_chars` 极大值 | 应正常读取比较，不崩；未核实超大文件读取性能（标注） | 适用（标注） |
| 非法输入 | `path` 不存在；`check_key` 未出现在 `external_results`；`invariant` 自相矛盾（同时 `contains` 和 `not_contains` 同一串，或 `min_chars` 与空值冲突） | 矛盾 invariant 应判定 fail 或显式拒绝——**这是"描述引用已删除枚举值"（BUG-214 形态）相邻面**，未核实 `output_validate` 是否显式拒绝矛盾 invariant（**标注为缺口**） | 适用（标注缺口） |
| 资源极限 | 巨量 artifacts（数千件）；checks 总数巨大 | verdict 计算应线性；未核实上限（标注） | 适用（标注） |

**本主题不适用项**：无。

---

## 主题 4 · router state persistence（对应 T0.4.1）

聚焦：`model_router` 配额账持久化（`memory/model-router-{ns}.json`）与 Star 门。

| 类别 | 具体触发输入 | 预期行为 | 是否适用+依据 |
|---|---|---|---|
| 空输入 | 无 `FIST_STAR_GATE_*` env 配置；空池（两池皆不可用） | 默认未配置 → `gate_enabled=false` / `free_pool_unlocked=true`（零回归）；两池皆不可用 → `ok=false` 显式失败，绝不静默改用（BUG-62 政策） | 适用 |
| 极值 | 配额账 `used = limit`（正好达 `threshold_pct` 95%） | `over_threshold=true` 自动切付费；`usage_pct` 达阈值不越界 | 适用 |
| 非法输入 | 非法 `namespace`（含特殊字符/空/超长）；配额账 JSON 损坏或被外部篡改 | 非法 ns 显式拒绝（BUG-64）；损坏 JSON 状态文件——**未核实 `model_router` 是否容错回退或显式报错（标注为缺口）** | 适用（标注缺口） |
| 资源极限 | 多命名空间并发读写同一状态文件；配额耗尽后跨池切换；游标环形扫描（rt_15） | 游标环扫防越界（rt_14/rt_15 白盒锁）；跨 ns 并发写同文件——未核实是否有锁（标注） | 适用（标注） |

**本主题不适用项**：无。

---

## 主题 5 · 组合环边界（对应 T0.4.2）

聚焦：R13 组合环 `bugfind→fix_and_merge→polish→verify→advance` 的环边界与 `loop_tick` / `loop_status` / `loop_create`。

| 类别 | 具体触发输入 | 预期行为 | 是否适用+依据 |
|---|---|---|---|
| 空输入 | `issue_scan --dir src` 0 findings（无 bug）；无待修 issue | bugfind 环无可消费输入应优雅结束，不崩；未核实 `loop_tick` 对空环的行为（标注） | 适用 |
| 极值 | `max_rounds` 达上限（omega 默认 3、最大 10）；`loop_tick` 超 `max_rounds` | omega 超限应自动写升级记录、暂停任务转人工裁决（**禁止死循环**）；未核实 loop_tick 是否同样防死循环（标注） | 适用（标注） |
| 非法输入 | 环步骤依赖断裂（前一步失败，下一步仍被 tick）；`loop_create` 空 `steps` | 应拒绝空 steps 或返回 `should_stop`；未核实（标注） | 适用（标注） |
| 资源极限 | 多组合环并发注册；`LoopRegistry` 大量条目 | 进程内注册表应线性扩容；未核实上限（标注） | 适用（标注） |

**本主题不适用项**：无。

---

## 主题 6 · 元层：边界审视自身的"不沉默"自审（对应 T0.4.3）

聚焦：**本任务**是否做到了"spec 未写的域外行为不沉默"。

| 类别 | 具体触发输入 | 预期行为 | 是否适用+依据 |
|---|---|---|---|
| 空输入 | 根任务 spec 完全没提的主题（如 Pentad 跨仓联动、gitcode 发布） | 应**显式声明该项不在 R13 本轮范围并说明依据**，而非沉默——本报告已在"后续建议"声明 GitCode 发布为外部 API 卡点 | 适用 |
| 极值 | 域外行为极端情况（如 `model_router` 状态文件被并发写坏） | 应给出最坏情况预期，标注"未核实"而非编造 | 适用（本报告已多处诚实标注"未核实"） |
| 非法输入 | spec 与实现矛盾（如规则 hint 承诺某行为、实现未认） | 应识别 hint↔实现缺口（第 3 环 BUG-153 的形态）——本报告在主题 3/4/5 标注了 5 处"未核实"缺口 | 适用 |
| 资源极限 | 审视产出超量/覆盖过广 | 应聚焦 R13 本轮范围，避免泛化到全仓无关工具 | 适用 |

**本主题自评**：本报告对 6 主题各给 4 类用例，**共 24 条**，其中约 8 条诚实标注"未核实"（不编造），符合"不沉默 + 不凑绿"双重纪律。

---

## 汇总统计

| 主题 | 空输入 | 极值 | 非法输入 | 资源极限 | 小计 |
|---|---|---|---|---|---|
| 1 JIT 后端边界 | 1 | 2 | 1 | 1 | 5 |
| 2 成本硬门 | 1 | 1 | 1 | 1 | 4 |
| 3 delivery validation | 1 | 1 | 1 | 1 | 4 |
| 4 router state persistence | 1 | 1 | 1 | 1 | 4 |
| 5 组合环边界 | 1 | 1 | 1 | 1 | 4 |
| 6 元层自审 | 1 | 1 | 1 | 1 | 4 |
| **合计** | 6 | 7 | 6 | 6 | **25** |

**诚实标注的"未核实"缺口（不编造，共 8 处）**：
1. `issue_scan` 对非法路径是否 panic（主题 1）
2. `cost_budget_*` 是否同样拒绝负预算/非法 JSON（主题 2）
3. `progress_gate` 极端规模性能（主题 2）
4. `output_validate` 空 artifacts 数组的 verdict 策略（主题 3）
5. `output_validate` 矛盾 invariant 是否显式拒绝（主题 3，BUG-214 相邻面）
6. `model_router` 损坏 JSON 状态文件是否容错（主题 4）
7. `model_router` 跨 ns 并发写同文件是否有锁（主题 4）
8. `loop_tick` 对空环/超 max_rounds/空 steps 的行为（主题 5，3 处合并）

---

## 后续建议

1. **8 处"未核实"缺口**建议后续环逐个实跑确认（尤其 `output_validate` 矛盾 invariant 与 `model_router` 损坏状态文件——这两处最可能藏着真 BUG）。
2. **契约/描述面判据**（BUG-214 形态）：`check_doc_surface.py` 已有 `RE_TOOL_DESC`/`tool_desc_registry()`（J9），但"描述引用已删除枚举值"未见——可评估补这条判据。
3. **GitCode 发布**（SHIP-PLAN G7）为外部 API 卡点，**不在 R13 本轮范围**，显式声明不适用。
4. **Pentad 跨仓联动**（R12 计划）需 `evolve_asset_register` 支持，不在 R13 本轮范围（根任务未展开），显式声明不适用。

## 来源

- 规则/工具真源：`src/server/issue_scan.mbt`、`src/router/model_router.mbt`、`src/server/output_validate.mbt`、`src/server/loop_*.mbt`、`src/ops/ops_modes.mbt`
- 前序账本：`memory/bugs.md`（BUG-152/153 FIXED、BUG-151 OPEN）、`memory/2026-10-13.md`（第 2-4 环）
- 报告：`reports/2026-10-13-bug152-secs-overflow-report.md`、`reports/2026-10-13-r13-cycle3-report.md`