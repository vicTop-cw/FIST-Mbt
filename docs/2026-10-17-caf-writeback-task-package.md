# CAF 标准 3 闭环后半：`executor_run` 写回 CAF 记忆 —— 派单任务包

- 日期：2026-10-17
- 前置：标准 3 前半已落地（commit `c2feb31`，`model_route(dry_run=true)` 可零副作用预览）
- 唯一剩余：**CAF 状态文件 `memory/model-router-caf-{ns}.json` 没有写入源** → dry_run 恒返回空 basis
- 用途：工具链恢复后交给子代理实施

---

## 一、目标

在 **`executor_run` 成功之后**把本次路由结果推入 CAF 记忆并落盘，使标准 3 真正闭环：
`executor_run` 真实跑过一次（成功）→ 记入 CAF 记忆 → 后续 `model_route(dry_run=true)` 的 `basis` 不再为空。

## 二、边界（只许动这些）

| 优先级 | 文件 | 理由 |
|---|---|---|
| 允许（新增/修改） | 定位到 `executor_run` 的**共享成功路径**后，在该处挂钩子；涉及的新私有 helper 落到 `src/server/model_router_ops.mbt` | 与 dry_run 读侧同源，helper 复用 |
| 允许（新增） | `src/server/model_router_ops_wbtest.mbt` 追加白盒锁 | 终审要真跑 |
| **禁止** | `src/server/ofm_http_js.mbt` / `ofm_http_native.mbt` / `github_js.mbt` / `github_native.mbt` / `laya_js.mbt` / `laya_native.mbt` / `run_check_js.mbt` / `run_check_native.mbt` / `stdio_js.mbt` / `stdio_native.mbt` | 并发 agent 平台分拆 WIP 正在重写，改动必冲突 |
| **禁止** | `src/server/pkg.generated.mbti` | 已被并发 agent 弄脏，绝不 `git add` |
| **禁止** | `scripts/gen_plugins.py` 及 `plugins/` | cl7 现红于并发方未提交的 `memory/bugs.md`（317 条入账），此时重生成会 bake 进对方未定稿账本 |
| **禁止** | `memory/bugs.md` / `memory/2026-10-17.md` | 并发方占用 |

## 三、实施步骤（先侦察，后动手）

1. **定位共享成功路径**：先跑 `git status --porcelain -- src/server`，确认 `executor_run` 的共享分发文件（非 `_js/_native` 后缀的）当前是 clean；若它已被并发方改脏，**停下来回报**，不要改。
2. **理解读侧**：读 `src/server/model_router_ops.mbt` 里 R43 加的 `mr_caf_state_path`/`mr_caf_read`，写侧必须**镜像同一条路径**（同 `safe_ns` 归一化、同文件名），否则读写不对称。
3. **理解 CAF 记忆 API**：读 `src/router/router_caf_persist.mbt` 的 `caf_memory_load`/`caf_memory_dump`，与 `src/router/model_router_caf.mbt` 的 `CafMemory` 类型，确认 push 入口（记录一次 {model, success, cost, context}）。
4. **挂钩子**：在 `executor_run` 成功（`ok=true`）的收尾处，**只在有真实 model/context 可记录时** push 一次并 `caf_memory_dump` 落盘；失败路径不写（避免污染成功率）。
5. **零回归红线**：默认行为不得改变——写回只在 `config.use_caf_memory=true` 时发生；`false` 时一个字节都不碰；`executor_run` 的现有回执字段不得增删。
6. **加白盒锁**（仿 `caf_dr_*` 风格）：至少 3 条——写回后文件确实出现且非空、`use_caf_memory=false` 不落盘、幂等（连续两次只记一次/不重复计数）。测试用临时命名空间 + `must_not_exist`/`path_exists` 断言，**不许污染仓库根**。
7. **顺手补 `caf_dr_6`**：预写坏 JSON 记忆文件 → `model_route(dry_run=true)` 返回 `ok=true`、`warnings` 非空、不 panic。

## 四、验收标准（终审要真跑，缺一打回）

- [ ] `moon fmt --check`（改动文件）→ exit 0
- [ ] `moon check src/server` → **0 errors**（warnings 允许，但不新增 `error`）
- [ ] `moon test --target js src/server` → `Total tests: N, passed: N, failed: 0.`（判绿看汇总行，BUG-142）
- [ ] 全仓 `moon test --target js` → `Total tests: M, passed: M, failed: 0.`
- [ ] `python scripts/check_tools_sync.py`（cl3）→ PASS（**不得新增工具**，只能改已有工具行为；工具数必须仍 170）
- [ ] `check_plugin_sync`（cl7）→ **不做**（理由见边界表；终审只记录现状，不判本轮责任）
- [ ] 提交前 `git diff` 逐行审：只含本次 CAF 写回内容，无 `.mbti`、无插件、无并发行

## 五、回传格式（缺一打回，五段式）

1. **结论**：写回是否落地、落在哪个函数、commit 号
2. **证据**：四道门禁的原文汇总行（`Total tests: …`）+ `git diff --stat` + 白盒锁名列表
3. **分析**：写回位置为何是唯一正确锚点；为何失败路径不写；幂等如何保证
4. **缺口与风险**：并发 WIP 是否又动过相关文件；空 context / 无 model 的场景；CI nightly fmt 差异
5. **建议入档位置**：`docs/2026-10-15-fist-mbt-caf-acceptance-status.md` 标准 3 补「闭环后半已落地」注

## 六、不可做的（防冲突红线，违反即打回）

- 不 `git add -A`；只精确暂存本次文件。
- 不提交 `src/server/pkg.generated.mbti`（并发弄脏）。
- 不跑 `scripts/gen_plugins.py`（cl7 现红于并发方 `memory/bugs.md`）。
- 不改任何 `_js/_native.mbt` 平台分拆文件。
- 不新增 `pub fn`（只加私有 helper，保持接口面稳定）。
- 不 `moon info` 去刷 `.mbti`（会扫进并发 delta）；如必须跑，跑完**还原**该文件。
- **不 commit**：实施 + 自测后把工作树留给指挥官精确暂存提交（金条八）。

## 七、已知前置信息（省侦察成本）

- R43 已在 `model_route_impl` 加 dry_run 分支（L299-340），Star 门（收于 L298）之后、`consuming`（L344）之前。
- 读侧状态路径 `memory/model-router-caf-{safe_ns}.json`（`mr_caf_state_path`）。
- CAF 相关纯计算在 `src/router/`（`model_router_caf.mbt` / `router_caf_dryrun_json.mbt` / `router_caf_persist.mbt` / `router_caf_replay_distinct_test.mbt`）。
- `RouterConfig.use_caf_memory` 默认 `false`，`caf_default_preference`/`caf_min_evidences` 已就位。