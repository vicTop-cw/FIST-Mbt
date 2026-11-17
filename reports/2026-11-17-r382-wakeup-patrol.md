# 轮 382 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 仍为**同一组 8 文件**（6 M + 2 untracked），与 r381 逐字相同、零再增长：

| 文件 | numstat | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 7/1 | M |
| memory/bugs.md | 216/0 | M（**零再增长**，r378 起冻结） |
| memory/target.md | 1/1 | M |
| scripts/README.md | 2/1 | M |
| scripts/run_guards.py | 9/0 | M |
| src/engine/engine_circuit_test.mbt | 5/0 | M（`_test.mbt`，不进入 release 构建） |
| scripts/check_mcpcf_db_isolation.py | untracked | R192 判据接线 |
| templates/pipeline_mode_loop.md | untracked | R192 模板 |

合计 **240+/3-**，与 r381 逐字相同 ⇒ WIP 冻结（r379 记「静止第 60 轮」，r380 修复轮、r381 巡检轮各计一轮 ⇒ 本轮为**静止第 63 轮**）；`src/**` 与 `run_guards.py` 仍 M ⇒ **巡检分支，Round C 三件（BUG-527 / BUG-530 / check_usage_tool_count 注册）维持过期不执行**。

## 二、换面巡检：check_sql_bind_alignment（R177）

**为何选此面**：近 20 轮换面（check_arg_face_strict / check_backlog_status_staleness / check_byte_slice_truncation / check_dead_params / check_deployment_freshness / check_doc_paths / check_doc_surface / check_effective_catch / check_esm_bundle_runnable / check_exit_code_contract / check_mbti_eol / check_mcp_stdio_purity / check_model_auth_no_key / check_plan_landing / check_precedents_doc / check_ps_encoding / check_selftest_hermetic / check_store_tables_wired / check_workflow_step_parity，另 r380 修 check_hardcoded_paths）全未覆盖 check_sql_bind_alignment ⇒ 不撞面。**精确复核**：该面最近一次换面使用为 **r359**（2026-11-16，T0r115，`memory/2026-11-16.md`），间隔 **23 轮** > 20 轮不撞窗 ⇒ 不撞面成立；且 r359 读数（selftest 7/7 + 实跑 19 处 rc=0）与本轮逐字一致 ⇒ store 层该面自 r359 起持续稳定。此面只扫 `src/store/*.mbt` 的 `INSERT` 语句，与 WIP 文件面不交叠，自包含、判据语义清晰可判。

### selftest（判据健康性，先判尺子不坏）

`selftest 7/7`，`RC=0`。七格（清单从输出反解）：

| 格 | 断言 | 作用 |
|---|---|---|
| s1 | 对齐样本判绿 | 正常路径 |
| s2 | 少一个 bind ⇒ 红 | **变异对照**（证明真能红，非恒绿） |
| s3 | 列数≠占位符 ⇒ 红 | 列面错位拦截 |
| s4 | 插值列 ⇒ 绿但计入 degraded | 诚实降级（不算静默已检） |
| s5 | bind 缺号 ⇒ 红（经计数不等表达） | bind 面错位拦截 |
| s6 | 无样本 ⇒ rc=2 | 判据无法自证归 2 不归 0 |
| s7 | 委托助手绑定 ⇒ 绿且 degraded | 委托面诚实降级 |

⇒ **判据健康，非坏尺**（能红能绿、无样本自拒、插值/委托诚实降级）。

### 实跑（现状面）

`RC=0`：**门禁 PASS，19 处 INSERT 三方对齐**（占位符 = bind 全对；其中 3 处列数为插值、仅校验占位符，计入 degraded）。

⇒ **store 层 SQL 接线面干净**：列 ↔ 占位符 ↔ bind 三方对齐全对，无「列顺序与 bind 顺序错位 ⇒ 字段互相串值、不报错、测试也未必覆盖」的本判据命名风险面。

一行小观察（**不立账、不修**）：脚本 docstring 里「仓库里还有 21 处 `INSERT`」是 R177 当时的时点计数，本轮实跑为 19——属**点名的变更史**（BUG-575 甄别式：点名变更史 = 准确），非现状面漂移，不构缺陷。

## 三、例行零漂移面

- `check_tools_sync`：rc=0（server.mbt 注册 **183** 个，AGENTS/README/deliverable/scoring_rubric 对齐；R8 分组 19 组 ΣN=183）。
- `check_instruction_budget`：rc=0（AGENTS.md **50440** 字节 / 预算 65536，全部章节可见）。
- `patch_esm_main` 探针：**10 bundle 全 up to date，total patched 0**，rc=0（ESM shim 面零漂移）。

## 四、FIST 闭环

**T0r138 六步全链 rc=0**（wd-r382 / ns watchdog / `temp/fist_r382_chain.sh` 稳健 TID 提取后台串跑，patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r138 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r382`、`assignee=wd-r382`、`deliverable=reports/2026-11-17-r382-wakeup-patrol.md`、`namespace=watchdog`、`created_at=2026-11-17T01:51:00Z` / `updated_at=2026-11-17T01:51:05Z`。

## 五、禁区与立账

- **禁区零碰**：8 个 WIP 文件（含 bugs.md）零改零提交；插件态 / 构建产物 / PATH 垫片本轮均未写。
- **无新立账**：本面实跑干净无新发现；bugs.md 属 WIP 禁区不代改。
- **后续**：r381 的 dist 刷新规格（refresh_dist → check_dist_snapshot / check_deployment_freshness 活跃面清零 → scoped 提交 dist/fist-mbt.js）仍待专门轮次执行；Round C 解禁后按队列执行（BUG-527 治本 → BUG-530 → check_usage_tool_count 注册）。

## 六、结论

本轮换面巡检（check_sql_bind_alignment，R177 SQL 三方对齐）：**判据健康**（selftest 7 格 rc=0，含变异对照与 rc=2 自拒两格）+ **实跑干净**（19 处 INSERT 三方对齐、3 处插值 degraded，rc=0）⇒ store 层 SQL 接线面无新发现、不立账。WIP 冻结第 63 轮（240+/3- 零再增长）⇒ 巡检分支、Round C 三件维持过期不执行。例行三面（tools_sync / instruction_budget / ESM 探针）零漂移。禁区零碰、无新立账、FIST 闭环全绿（见第四节）。
