# Goal-2 Round 37 报告：CAF dry_run 预览 JSON 输出层（验收标准 3 纯计算侧补齐）

- **日期**：2026-10-15
- **提交**：R37 code（3 文件 +182：`src/router/router_caf_dryrun_json.mbt` + `_wbtest.mbt` + `pkg.generated.mbti`）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9），本轮完成接线前的**标准 3 JSON 输出**

## 结果摘要

### 发现缺口

CAF 四条验收标准里，**标准 3（dry_run 可预览）的纯计算已落地**（R29 的 `pick_caf_dry_run` 返回 `CafDryRun`），
但 `CafDryRun` **没有 JSON 输出能力**（grep 全库无 `CafDryRun::to_json`）。

标准 3 预期产物是 JSON `{"suggestion": model, "basis": [{model, rate, avg_cost, count}]}`。
接线时 server 层需把 `CafDryRun` 转成这个 JSON —— 若不提供纯计算侧，server 层要**手搓 JSON**，
易错且形状易漂移（字段改名、口径不一）。这正是 §2.3 接线时最易翻车的一格。

### 新增 JSON 输出层（独立文件，不碰并发域）

新增 `src/router/router_caf_dryrun_json.mbt`，用自由函数 `caf_dry_run_to_json(dr : CafDryRun) : Json`
（R36 已验证的自由函数模式，不做跨文件方法定义），输出标准 3 形状：

```json
{ "suggestion": "free-b",      // picked.model_name（CAF 重排后）
  "base":      "free-a",       // base.model_name（纯 pick 对照）
  "reordered": true,           // 是否发生重排
  "top_k":     10,             // 检索 k
  "basis": [ { "model": "free-b", "rate": 1.0, "avg_cost": 0.05, "count": 5 }, ... ] }
```

**口径对齐**：`rate` = success/total（total=0 时 0），`count` = total，
与 `CafMemory::to_json` 的 by_model 聚合口径一致，避免接线后两处口径不一致。

**接线成本降低**：server 层只需 `pick_caf_dry_run(...)` → `caf_dry_run_to_json(dr)` 即得标准 3 形状，
**不必手搓 JSON**。

### 新增 2 条契约锁

`src/router/router_caf_dryrun_json_wbtest.mbt`（whitebox，复用 `mrc_router/mrc_memory/mrc_now` helper
生成真实 `CafDryRun`）：

| 锁 | 钉死的契约 | 区分度 |
|---|---|---|
| `caf_dj_1_标准3形状` | suggestion==picked.model_name、base==base.model_name、reordered/top_k/basis 长度对齐真实值，basis 每条含 model/rate/avg_cost/count | 逐字段对齐真实 CafDryRun，非「能输出」弱断言 |
| `caf_dj_2_basis字段不变量` | basis 每条 model 非空、rate∈[0,1]、avg_cost≥0、count≥1 | 形状级不变量（防 rate 越界/负成本） |

### 验证

router **177/177**（R36 基线 175 + 2 锁）；全仓 **1183/1183**，0 failed。
`moon info src/router` 0 errors，`.mbti` 已含 `caf_dry_run_to_json` + `caf_memory_dump`。

## 资源消耗

`moon fmt` / `moon test --target js src/router` / `moon info src/router` / 全仓回归 / `git commit`（path-scoped）

## 任务分配记录

本轮**无任务分配**（未拆子任务）。本人在 router 域独立推进，新文件独占。

## 遗留风险

- **§2.3 server 接线仍未做**。标准 3 的**纯计算侧现已完整**（`pick_caf_dry_run` + `caf_dry_run_to_json`），
  接线时 server 层零手搓 JSON。但接线本体（`model_router_ops.mbt` dry_run 分支）仍待并发 agent 释放。
- **标准 4 与标准 1/2 已验**；**标准 2 是 Python 预演**（R16），接线完成后需真源 MoonBit 复验。
- **并发 agent WIP 引入编译错**：R37 期间 `moon info` 全仓报 `src/diff/diff.mbt:170:14` [4014]，
  是并发 agent 在改 `diff.mbt`（31+2 numstat，新增 `diff_escape_fix_wbtest.mbt`）的**中间态**。
  **全仓 `moon test --target js` 仍 1183/1183 全绿**（该错只在 `moon info` 的 .mbti 生成路径报），
  但并发 agent 若 commit 会受阻。**我的改动与 diff.mbt 无交集**，用 `moon info src/router` 独立同步了 .mbti。

## 后续建议

1. **R38 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）——dry_run 分支：
   `pick_caf_dry_run(...)` → `caf_dry_run_to_json(dr)` → 返回标准 3 形状。
   executor_run 分支：`caf_memory_load` 恢复 → pick_caf → `caf_memory_dump` 落盘。
2. **R38 备选**：标准 2 的**真源复验**（接线后）——把 Python A/B 预演升级为 MoonBit 实测。
3. **R38 备选 2**：CAF 记忆容量上限与淘汰策略审查（`max_size` 默认 10000，软淘汰需在 `CafMemory` 内，并发域）。
4. **R38 备选 3**：`caf_dry_run_to_json` 的 `suggestion` 形状若未来加字段（如 `caf_default_preference` 应用），
   需同步补锁。

## 超额内容

**本轮顺带验证**：`moon info <pkg>` 支持**单包 info**，可用于全仓 info 被并发 agent 中间态阻塞时，
单独同步自己包的 `.mbti`（`moon info src/router` 0 errors）。这是多 agent 共享 repo 的实用逃生门。

## 来源

- 代码（只读审查）：`src/router/model_router_caf.mbt` L21（`CafDryRun` 结构）、
  `src/router/router_caf.mbt` L104（`CafModelStats`）、`src/router/model_router.mbt` L382（`RouteDecision.model_name`）
- 新增：`src/router/router_caf_dryrun_json.mbt`、`src/router/router_caf_dryrun_json_wbtest.mbt`
- 文档更新：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md`（标准 3 状态 + 阻塞点段）
- 参考：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md`（R29 标准 3 纯计算已落地）
