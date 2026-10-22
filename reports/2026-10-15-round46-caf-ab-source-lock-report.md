# Goal-2 Round 46 报告：标准 2 A/B 端到端真源锁

- **日期**：2026-10-15
- **提交**：R46 code（`src/router/router_caf_rate_monotone_wbtest.mbt` 追加 `caf_ab_1`，纯测试，HEAD `9d842c3`）
- **状态**：§2.3 server 接线仍阻塞（连续 9 轮）；本轮补齐 CAF 验收标准 2 的**真源 A/B 对比缺口**

## 结果摘要

### 接线阻塞确认

`model_router_ops.mbt` 仍 `4/9`（连续 9 轮 R38-R46）。并发 WIP 面扩大：`router_caf.mbt` 5/1、
`bugreport.mbt` 8/2、`ops_hats.mbt` WIP → 可动域收窄到 `router_caf_ext.mbt` / `router_config.mbt` / `router_caf_rate_monotone_wbtest.mbt`。

### 新发现：CAF 验收状态文档（R44 扫描遗漏）

R44 穷尽 docs 时漏了 `docs/2026-10-15-fist-mbt-caf-acceptance-status.md`（21:43 更新，最晚）。
读后确认 **CAF 四条验收标准**：
- 标准 1（离线回放）、标准 4（零回归基线）✅ 已验
- **标准 2（开启后不增成本且成功率不降）**：**L44 明确「⚠ 这是 Python 预演，非真源 MoonBit 实测。P2c 接线完成后需用真源复验」**
- **标准 3（dry_run 预览）**：纯计算已落地（`pick_caf_dry_run` + `caf_dry_run_to_json`），**阻塞点仍是 server 接线**

### 实质产出：标准 2 A/B 端到端真源锁

R38 `caf_cost_1/2`（成本决胜）+ R39 `caf_rate_1`（成功率不降）分别锁了 cost_decides / rate_monotone，
但**未锁 A/B 整体端到端对比**——标准 2 要求「开启后成功率不降**且**成本不增」，是两个条件的合取。

补 `caf_ab_1_开启后成功率不降成本不增`：

| 组 | 选法 | 结果 |
|---|---|---|
| A（关闭 CAF） | 按原序选 `free-a` | rate 0.5，avg_cost 0.1 |
| B（开启 CAF） | `caf_soft_reorder` 后选首 | rate 1.0，avg_cost 0.1 |

**断言**：
1. `caf_soft_reorder` 首位 = `free-b`（rate 1.0 更高项被软重排到首位）
2. B 组 rate（1.0）≥ A 组 rate（0.5）—— 成功率不降
3. B 组 avg_cost（0.1）≤ A 组 avg_cost（0.1）—— 成本不增

从真源 `caf_stats` 聚合读 rate/avg_cost（非手写常量），钉死聚合口径一致。

**为何必需**：CAF 验收状态文档 L44 的「⚠ 待真源复验」——R46 把该缺口的**纯计算侧**闭合。
（P2c 接线完成后仍需跑真源 `pick` 端到端复验，那是接线域。）

### 并发观察

并发 agent 本轮推进：`bugreport.mbt`（8/2 重复条目 bug 修复）、`router_caf.mbt`（5/1 knn_search 侧）、`ops_hats.mbt`（六顶帽）。**均不越界**。

## 验证

- router **199/199**（R45 198 + caf_ab_1），0 failed
- 全仓 **1209/1209**（R45 1208 + 1），0 failed
- `.mbti` 无变化（纯测试追加，无新 pub fn）
- `moon fmt --check` 通过

## 资源消耗

`git status --porcelain`（WIP 面扫描）/ `grep test 锁清单`（确认幂等/成本/rate 锁已存在）/
`Get-ChildItem docs/`（R44 遗漏文档发现）/ `read` CAF 验收状态文档 / `grep CafModelStats 字段` /
`moon fmt` + `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/router_caf_rate_monotone_wbtest.mbt`
（`router_caf.mbt`/`model_router_ops.mbt`/`bugreport.mbt`/`ops_hats.mbt` 均 WIP 已避开；`.mbti` 未动证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，连续 9 轮）。接线前置四契约齐备 + 标准 3 JSON 层就绪，接线成本已最小化。
- **标准 2 的接线后端到端复验**仍待接线完成（R46 只闭合纯计算侧）。
- **并发 WIP 面扩大**：`bugreport.mbt`/`router_caf.mbt`/`ops_hats.mbt` 同时 WIP，可动域持续收窄。
- **BUG-185/186/217 重复条目**：`bugreport.mbt` WIP（并发在修），不越界。

## 后续建议

1. **R47 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。四契约 + JSON 层齐备，接线照抄。
2. **R47 备选**：标准 1 的补锁（离线回放区分度已有 `caf_c1_1/2/3`，可加「候选集置换不变」真源锁——验收文档 L32 声明了该性质但未在 MoonBit 锁）。
3. **R47 备选 2**：标准 4 的零回归锁已 135/135，无需补。
4. **持续观察**：并发收口 `model_router_ops.mbt` → 立即实施接线。

## 来源

- `docs/2026-10-15-fist-mbt-caf-acceptance-status.md` L44（标准 2 待真源复验缺口）
- `src/router/router_caf.mbt` `CafModelStats`（model/total/success/avg_cost）
- 新增锁：`src/router/router_caf_rate_monotone_wbtest.mbt` `caf_ab_1_开启后成功率不降成本不增`
- 参考：`src/router/router_caf_cost_decides_test.mbt` caf_cost_1/2（R38 构造方式复用）
