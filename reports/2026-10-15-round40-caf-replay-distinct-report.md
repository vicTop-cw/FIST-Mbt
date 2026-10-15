# Goal-2 Round 40 报告：CAF 离线回放上下文区分度契约锁（验收标准 1 真源锁）

- **日期**：2026-10-15
- **提交**：R40 code（`src/router/router_caf_replay_distinct_test.mbt`，1 文件 +139）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9，工作树 94 文件），本轮补**标准 1 的 MoonBit 真源锁**

## 结果摘要

### 寻虫：标准 1 只验 Python、缺 MoonBit 真源锁

标准 1「离线回放可复现」的核心契约：简单任务 context → 命中 m_free（rate 0.93）；
复杂任务 context → 命中 m_premium（rate 1.0）。**不同任务类型的特征哈希必须命中不同历史记录邻域**，
否则离线回放退化成"单一优先级"，无法区分任务类型。

现有锁只测了**返回数量与边界**（`caf_knn_search_topk` / `boundary` / `k_greater_than_records`），
**没测区分度**——若不同 context 都命中同一组记录，这些锁**照样全绿**。而标准 1 的验收（R12）
只跑 Python `caf_offline_replay.py`，MoonBit 侧没有对应真源锁。

### 补 3 条真源锁（blackbox，全 pub API：`CafMemory::new/push/knn_search` + `caf_stats`）

`src/router/router_caf_replay_distinct_test.mbt`，一份记忆含两组特征：
- `feature_hash("simple task")` → m_free 3 条（2 成功 1 失败，rate 0.667）
- `feature_hash("complex task")` → m_premium 3 条（3 成功，rate 1.0）

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_c1_1_简单任务回放命中m_free` | `knn_search("simple task", 3)` 首位 m_free，邻域统计 2 成功 / 3 总 | stats[0].model=="m_free" 且 2/3 |
| `caf_c1_2_复杂任务回放命中m_premium` | `knn_search("complex task", 3)` 首位 m_premium，邻域统计 3 成功 / 3 总 | stats[0].model=="m_premium" 且 3/3 |
| `caf_c1_3_两种任务类型严格区分` | 两邻域首位**不同模型** + 复杂任务 rate > 简单任务 rate | simple[0].model != complex[0].model 且 complex_rate > simple_rate |

**关键**：`caf_c1_3` 是区分度的核心——若 knn 检索被改成"全量命中"或 hash 匹配失效，
`caf_c1_1/2` 可能仍过（首条恰好是 m_free/m_premium），但 `caf_c1_3` 会红（首位模型相同）。

### 至此标准 1 纯计算侧有 MoonBit 真源锁

标准 1 原本只有 Python 离线回放 + `output_validate` l4-pass，R40 补上真源锁，
与标准 2（R38/R39）的契约锁同族，形成"Python 预演 + MoonBit 真源"双轨。

### 验证

router **183/183**（R39 基线 180 + 3 锁）；全仓 **1189/1189**，0 failed。
`.mbti` **无变化**（blackbox 测试不新增 pub API）。

## 资源消耗

`moon fmt` / `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped）

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，新测试文件独占。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，工作树 94 文件）。CAF 四条验收标准
  **纯计算侧现已全部就绪**：标准 1（R40 真源锁 + R12 Python）/ 标准 2（R38/R39 契约锁）/ 标准 3（R37 dry_run JSON）/ 标准 4（零回归基线）。
- **标准 3 接线提示**：dry_run 分支 `pick_caf_dry_run` → `caf_dry_run_to_json`（标准 3 JSON 已就绪）；
  executor_run 分支 `caf_memory_load` → `pick_caf` → `caf_memory_dump`。
- **并发 agent WIP**：工作树 94 文件，`model_router_ops.mbt` 4/9，**无已 staged 文件**（提交面干净）。

## 后续建议

1. **R41 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。
2. **R41 备选**：CAF 记忆容量上限与淘汰策略审查——`max_size` 默认 10000，软淘汰需在 `CafMemory` 内
   （并发域 `router_caf.mbt`）。可先在纯计算侧**审查**淘汰不变量（现有锁 `caf_capacity_invariant` 只钉
   all()≤max_size，未钉"淘汰后 count 保持 max_size 且 FIFO 连续"）。
3. **R41 备选 2**：`caf_feature_hash` 碰撞/归一化——多项式 hash 对语义相近的不同字符串
   （"python" vs "python "）产生不同特征，记忆碎片化。接线时归一化 context（trim + lowercase）再 hash。
4. **R41 备选 3**：标准 4「零回归」——用 `issue_scan` 扫 `src/router` 找真实缺陷候选
   （寻虫闭环用 fist-mbt 自身能力），命中再 `report_bug`。

## 超额内容

**KNN 检索的"编辑距离作用于 hash 数字串"语义**（`router_caf.mbt` L300-310）：目标 hash 转字符串后与每条记录的
hash 字符串算编辑距离。精确匹配 dist=0，k≤同特征记录数时命中该特征邻域，k 增大才会混入邻近 hash 的邻域。
这是本锁 `k=3` 能稳定命中各自邻域的前提——已在注释里点明。

## 来源

- 代码（只读审查）：`src/router/router_caf.mbt` L291-330（`CafMemory::knn_search`）、L114（`caf_stats`）
- 新增：`src/router/router_caf_replay_distinct_test.mbt`
- 参考：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md` 标准 1 行（R12 `c45d6d6`）
