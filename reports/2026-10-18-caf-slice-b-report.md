# CAF Slice B —— 记忆闭环写半 + bad-JSON 降级锁 · 交付报告

- 日期：2026-10-18
- 提交：`80dfe92`（2 文件，306+/3-）
- 前置：`ee86a98`（CAF dry_run 预览 = 标准 3「读半」）+ `c2feb31`（CAF dry_run 预览接线）
- 子代理：`22bf1710`（只改 2 文件，未 commit）；父代理独立终审 + 提交

## 结果摘要

补齐 CAF（Cost-Aware Filtering，模型成本感知路由）记忆闭环的**写半**，并给 bad-JSON 降级上白盒锁：

| 目标 | 落地 | 验证 |
|---|---|---|
| `caf_memory.push`：executor_run 真消耗后把该调用回写进 CAF 记忆文件 | `model_router_ops.mbt` 新增私有 `mr_caf_push_evidence`，消耗侧加 `if consuming && r.config.use_caf_memory` 门 | `caf_dr_7`（真消耗回写+闭环+幂等 1→2→3）/ `caf_dr_8`（未开启一个字节不碰） |
| `caf_dr_6` bad-JSON 降级锁：坏 JSON 记忆 → 降级为空记忆 + warning，**不 panic** | 新增私有 `mr_try_parse` / `mr_caf_read_diag`（区分 不存在/空/坏 JSON/合法 JSON）；dry_run 读侧改走 diag | `caf_dr_6`（不 panic + 字节级保留 + warnings 点名「坏 JSON」） |

新增 4 条白盒锁（`caf_dr_6/7/8/9`），`caf_dr` 总数 5 → 9。

## 验收读数（父代理独立复跑，不采信子代理自述）

- `moon check src/server src/router` → **0 errors**（1065 warnings 全为存量）
- `moon test --target js src/server -f "*caf_dr*"` → **9/9**
- `-f "*mo_*"` → 10/10；`-f "*ma_*"` → 6/6（零回归红线）
- `moon test --target js` 全量 → **Total tests: 1323, passed: 1323, failed: 0**（28.5s，≥ 现状 1319）
- `moon fmt --check` → exit 0；`moon info` → 0 errors、**server .mbti 无内容 diff**（未新增 pub fn）
- 工作树 diff 核查：子代理**恰好**只改 `model_router_ops.mbt`(111+/3-) + `model_router_ops_wbtest.mbt`(195+/0-)；其余 `scripts/*.py`(1/1) 为并发 WIP，未提交

## 关键设计决策

1. **坏 JSON 点名必须靠 diag 分流**：`mr_caf_read` 把不存在/读失败/坏 JSON 全塌成 `Json::null()`，`caf_memory_load(null)` 只回「顶层非对象」——满足「不 panic」但说不出根因。新增 `mr_caf_read_diag` 后 dry_run **同时**给结构告警 + 根因告警（两条），符合「warnings 点名坏 JSON」。
2. **读/写共用 diag 口径**：push 需要知道 `bad_json` 才能跳过且不覆盖；复用 `mr_caf_read_diag` 保证读写同源。
3. **坏 JSON 两条路都保证据**：dry_run（读侧）与 record（写侧）都不删除/覆盖，测试用字节级 `assert_eq` 钉死。
4. **门禁在 `r.config.use_caf_memory`**：零回归——`mo_*` 全用非 CAF 配置或 query-only；`caf_dr_1/2/4/5` 走 dry_run 早退不到 push；`caf_dr_3` 无 config 即 Err。
5. **push 失败不拉黑主路径**：写盘失败进 warnings（回执可见）而非让 `model_route` 整体 Err —— 路由决策与记账已成功，CAF 是旁路增强。
6. **`cost=0.0`**：路由层无成本输入，按 `CafRecord` 契约 0 = 未知/免费处理。

## 资源消耗

- 子代理 1 名（Slice B 全量实现 + 自跑验收），未 commit
- 父代理：独立终审（moon check / 全量 test / fmt --check / 工作树范围核查 / 代码审阅）+ 提交 + 本报告
- 前置：`ee86a98`（并发 agent 提交 dry_run 预览）+ `c2feb31`

## 遗留风险 / 后续建议

1. **【重要，下一 slice / caf_dr_10 输入】executor 失败也会污染 CAF 记忆**：`mr_record_only` 在 `resp.is_error` 检查**之前**调用（`model_router_ops.mbt` L885 OFM / L1228、L1248 CLI 重试）→ 失败执行同样走消耗分支 → push `ok=true`。长期会抬高「常失败模型」的 CAF 成功率。根修是把 record/push 移到 `resp.is_error` 之后，但会改动现有回执字段顺序/quota 语义，涉「现有回执字段不得增删」红线且其他测试依赖 `quota` 字段，本轮未动。
2. **【中】写回只在状态文件已含 `use_caf_memory=true` 时触发**：`executor_run` 的取模型与记账调用不带 config，`use_caf_memory` 只能从已落盘状态读到；只有此前用含 pools + `use_caf_memory` 的 config_json 播过种才为 true。首笔无 config 的记账不会 push。符合门禁措辞，但「闭环」需项目侧先播种。
3. **【低】dry_run 的 `use_caf_memory=false` 仍显式 Err**（`caf_dr_3` 原状，非本次引入）——调用方须先播种再 dry_run。
4. 本地 moon 0.1.20260920 fmt/check 全过；CI nightly（0.1.20261012）风格可能重排，按 AGENTS.md 收口统一。

## 来源

- 真源：`src/server/model_router_ops.mbt`（新增 `mr_try_parse` / `mr_caf_read_diag` / `mr_caf_push_evidence` + dry_run 读侧与消耗侧接线）、`src/router/model_router_caf.mbt`（`caf_memory_load` / `CafRecord` / `caf_feature_hash` / `caf_normalize_context` / `caf_memory_dump`）
- 测试：`src/server/model_router_ops_wbtest.mbt`（`caf_dr_6/7/8/9` 新增；`caf_dr_1..5`、`mo_*`、`ma_*`、`bug229` 保留）
