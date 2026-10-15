# Goal-2 Round 33 报告：RouterConfig 加 caf_default_preference / caf_min_evidences

- **日期**：2026-10-15
- **提交**：`c54fe68`（8 文件 +192/-4）
- **目标推进**：CAF §2.3 server 接线的 **router 侧前提**全部落地；剩余唯一阻塞收窄到 `model_router_ops.mbt` 一处

## 结果摘要

`RouterConfig` 新增 `caf_default_preference : Array[String]`（默认 `[]`）与 `caf_min_evidences : Int`（默认 10），并全链路透传：

| 落点 | 内容 |
|---|---|
| `struct` + `default()` | 两字段 + 默认值（默认零回归：空偏好 / 10 证据） |
| `from_json` | 缺字段/null → 默认；坏类型 → 默认 + warning（偏好数组含非字符串元素→忽略该元素并 warning） |
| `to_json` | 序列化 `caf_default_preference`（`Array[String]`）与 `caf_min_evidences`（Number） |
| `clone_pools` / `router_state` merge | 两字段原样透传 |
| 20 处 wbtest 构造点 | regex 一次性 **20/20 命中**补齐 |
| `cfg_ofm_2` 顶层键集合锁 | 7 → 9（新字段须显式登记） |
| 新锁 `caf_cfg_1` | 默认值 + JSON 往返（含空偏好 / 非空偏好两段） |
| 新锁 `caf_cfg_2` | 偏好字段从 config 读出并透传 `pick_caf`：空记忆冷启动选偏好、记忆充足证据胜出 |

**验证**：router `moon test --target js` = **164/164** 全绿；全仓 1168 tests 中 1167 通过。

## 资源消耗

- `moon fmt` / `moon info`（同步 mbti，0 errors 564 warnings）/ `moon test --target js src/router` ×3（含 2 次断言修正）/ 全仓回归 ×1
- 一次 regex dry-run（20/20）+ 一次写盘替换

## 任务分配记录

本人在 router 域独立推进，未触碰并发 agent 工作面（`src/engine/`、`src/server/model_router_ops.mbt`）。

## 遗留风险

- **全仓 1 例失败**：`src/engine/dag_cycle_test.mbt:36`（BUG-213）——该文件是**未跟踪新文件**（`??`），属并发 agent 环保护工作（刚提交 BUG-212 `1f35342`）未收口，与本次改动无关。等其收口后全仓恢复全绿。
- **§2.3 server 接线**仍未做：`model_router_ops.mbt` 三件事（`executor_run` 后 `caf_memory.push` / 把 config 两字段透传 `pick_caf` / status 展示 `caf_memory_status_text`）。router 侧所有前提已齐备。

## 后续建议

1. 并发 agent 释放 `model_router_ops.mbt` 后立即做 §2.3 接线（R34 候选），验收 = executor_run 走 CAF 路由 + status 看到记忆聚合。
2. **更正 R32 误判**：RouterConfig 字段改动面真实读数 = `use_caf_memory:` 构造点 **24 处**（20 处需补），非 36 处——建议在 wiring 设计文档里留这条勘误，避免下个开发者再被 36 吓退。

## 超额内容

- **` M` 状态 ≠ 他人占用**的纠偏：`model_router.mbt`/`router_config.mbt` 的 ` M` 实为 CRLF 噪音（`git diff --numstat` 为空），`use_caf_memory` 是 HEAD 已提交字段。R32 因此误判并发 agent 在改，白等一轮才回退。

## 来源

- 代码：`src/router/model_router.mbt`、`src/router/router_config.mbt`、`src/router/model_router_caf.mbt`、`src/router/router_state.mbt`
- 测试：`src/router/model_router_wbtest.mbt`、`src/router/model_router_caf_wbtest.mbt`、`src/router/router_config_wbtest.mbt`
- 设计：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md`、`docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md`、`docs/2026-10-14-fist-mbt-router-caf-learning-plan.md`
- 记忆：`memory/2026-10-15.md`（Round 33 条目）
