# Goal-2 Round 45 报告：中间空白保留语义锁

- **日期**：2026-10-15
- **提交**：R45 code（`src/router/router_caf_ext_wbtest.mbt` 追加 2 锁，纯测试无源码改动，HEAD `4791fa5`）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9）；本轮做接线前置的**语义边界**补锁

## 结果摘要

### 接线阻塞确认

`model_router_ops.mbt` 仍 `4/9` WIP（连续 8 轮 R38-R45）→ §2.3 接线本体不可行。
`src/router/router_caf.mbt` 本轮也变 `M`（并发 agent 在改）→ **knn_search 依赖域避开**。

### BUG-185/186/217 重复条目 · 真源定位

本轮确认 **BUG-185 在 `memory/bugs.md` 有 2 条**（`08:46:00Z` FIXED + `08:44:07Z` OPEN，同号不同戳）——
`report_bug` 未防同 bug_id 重复注册。定位真源：`bugreport.mbt:245 pub fn report_bug`。
**但**：`src/server/bugreport.mbt` 与 `bugreport_status_wbtest.mbt` **均为 `M`（并发 agent 正在改）** →
修复是并发 agent 的域，**不越界不抢占**。本轮仅记录，交并发收口。

### 实质产出：中间空白保留语义锁（接线前置语义契约）

R42 契约声明「trim 首尾 + ASCII lowercase」，但**未锁「中间空白保留」**——
接线方可能误以为 `caf_normalize_context` 删除所有空白，把 `"caf model"` 拼成 `"cafmodel"`（**破坏语义**）。

补 2 锁：

| 锁 | 钉死的契约 |
|---|---|
| `caf_norm_6_中间空白保留` | ASCII 空格中间保留：`"Py Thon"`→`"py thon"`、`"a  b"`→`"a  b"`、`"  a b  "`→`"a b"` |
| `caf_norm_7_全角空格中间保留` | 全角空格中间保留：`"　Py　Thon　"`→`"py　thon"`；且 hash ≠ ASCII 空格版本（全角中间保留，非空白删除） |

**为何必需**：接线前置的语义契约齐备 = R42 归一化 hash + R43 min_evidences 分界 +
R36 dump/load 往返 + **R45 trim 语义**。接线方照抄时不会把 trim 误读成「删所有空白」。

### 并发观察

并发 agent 本轮同时推进：`bugreport.mbt` WIP（重复条目 bug 修复中）、`router_caf.mbt` 变 WIP。
**git log 竞态教训**：`git log -1 --oneline` 一度显示旧 HEAD `8299d5f`（R44 docs），
复核 `git log -4` 确认 HEAD=`4791fa5` 是我的 R45 code —— **并发 agent 在我 commit 前一瞬 push，
git log 短暂读到旧状态**；R43 同现象。**判 HEAD 一律 `git rev-parse HEAD` + `git log -N` 复核**。

## 验证

- router **198/198**（R44 196 + caf_norm_6/7），0 failed
- 全仓 **1208/1208**（R44 1206 + 2），0 failed
- `.mbti` 无变化（纯测试追加，无新 pub fn）
- `moon fmt --check` 通过

## 资源消耗

`bug_list` / `Select-String BUG-185 条目数` / `git status --porcelain src/router/` / `grep test 锁清单` /
`moon fmt` + `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/router_caf_ext_wbtest.mbt`
（`router_caf.mbt` WIP 已避开；`.mbti` 未动证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9，连续 8 轮）。接线点用归一化 hash + `>=` 分界 + trim 语义（四契约齐备）。
- **BUG-185/186/217 重复条目**：`bugreport.mbt` WIP（并发在修），**不越界**；若并发收口前仍 OPEN，R46+ 上报。
- **`router_caf.mbt` 变 WIP**：knn_search 依赖域现在避开，CAF 检索侧锁需等收口。
- **并发 WIP 持续**：`model_router_ops.mbt` 4/9 + `bugreport.mbt` + `router_caf.mbt`。

## 后续建议

1. **R46 首选**：§2.3 接线（`model_router_ops.mbt` 释放后）。四前置契约齐备，接线可直接照抄。
2. **R46 备选**：若 `router_caf.mbt` 收口，补 CAF 检索侧锁（knn_search 邻域收敛终验锁）。
3. **R46 备选 2**：actus DSL 契约草案（§6.2 `#!config`，docs/openapi 扩展 actus 动作 schema 供用户项目照抄）。
4. **持续观察**：bugreport 重复条目 bug 由并发收口；git 判 HEAD 用 `rev-parse` + `log -N` 双复核。

## 来源

- `bug_list` + `Select-String memory/bugs.md BUG-185`（确认重复条目）
- `git status --porcelain src/router/`（`router_caf.mbt` WIP 确认）
- 真源：`src/router/router_caf_ext.mbt` `caf_normalize_context`（L89-106，trim 首尾 + lowercase）
- 新增锁：`src/router/router_caf_ext_wbtest.mbt` `caf_norm_6_中间空白保留` / `caf_norm_7_全角空格中间保留`
- 设计文档：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.3
