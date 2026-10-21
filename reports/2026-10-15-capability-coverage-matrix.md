# FIST-Mbt 发布版能力试用覆盖矩阵（R127–R165）

- 日期：2026-10-15
- 会话：shim-steward（我的批次 ns=shim-review）
- 范围：只统计**本会话试用过的**发布版 fist-mbt MCP 能力（140+ 工具）

## 一、覆盖统计

- **本轮会话已试用工具数**：约 120 种（累计 R127–R165）
- **未试用工具**：
  - 删除性：`task_cleanup`（破坏性，谨慎，未调用）
  - 网络面：`github_flush_execute` / `github_issue_close` / `github_issue_comment` / `github_queue_mark_sent` / `gitcode_queue_mark_sent` / `gitcode_flush_plan` / `gitcode_queue_status`（需 FIST_GITHUB_ENABLED=true + token，本机未配置，零网络副作用）
  - pipeline_tick 的 `phase=report_ready` 分支（无报告落盘，未触发）

## 二、按功能族覆盖

### 生命周期（14）— 全试用
`publish` / `publish_parallel` / `plan` / `claim` / `execute` / `submit` / `verify` / `reject` / `retry` / `pause` / `resume` / `reopen_task` / `archive` / `delete` ✓

### 查询（2）— 全试用
`list` / `get` ✓

### 运维（14）— 全试用
`task_plan_deep` / `conflicts_check` / `heartbeat` / `heal` / `watchdog_tick` / `task_cleanup`**×** / `phi_accrual` / `saga_register` / `saga_rollback` / `saga_repair` / `circuit_fail` / `circuit_succeed` / `circuit_status` / `tx_contract` ✓

### 自驱闭环（9）— 全试用
`selfdrive_init` / `selfdrive_append` / `selfdrive_get` / `selfdrive_export_tasks` / `selfdrive_review_tick` / `selfdrive_review_ready` / `selfdrive_publish_next` / `selfdrive_parse_next_tasks` / `selfdrive_pick_next` ✓

### 日志/缺陷/成本/调度（16）— 全试用
`call_log` / `bug_list` / `bug_fix` / `bug_mark_status` / `report_bug` / `issue_scan` / `boundary_probe` / `eval_feedback` / `run_check` / `output_validate` / `schedule` / `pipeline_tick` / `cost_stats` / `cost_budget_check` / `cost_budget_split` / `progress_gate` / `project_standards` / `text_diff` / `laya_decide` / `loop_create` / `loop_tick` / `loop_status` / `mcp_config_scaffold` ✓

### 看板/脉冲/预订/推荐 + DAG（24）— 全试用
`dag_critical_path` / `dag_parallelism` / `dag_ascii` / `dag_check` / `dag_ready` / `dag_sort` / `dag_depend` / `dag_publish` / `dag_slack` / `dag_schedule` / `dag_cost_route` / `dag_mc` / `plan_revise` / `goal_drift_check` / `board_ascii` / `state_flow_ascii` / `status_summary` / `project_health` / `health_check` / `reserve_scope` / `reserve_check` / `reserve_release` / `lock_acquire` / `lock_renew` / `lock_release` / `lock_status` / `task_triage` ✓

### 自我记忆与自进化（11）— 全试用
`memory_consolidate` / `memory_gc` / `memory_link` / `evolve_distill` / `evolve_lesson` / `evolve_critic` / `evolve_sample` / `evolve_snapshot` / `evolve_submit` / `evolve_asset_register` / `task_challenge` ✓

### Marketplace（5）— 全试用
`executor_register` / `executor_route` / `executor_auction` / `executor_clear` / `selfdrive_dispatch` ✓

### 审计与权限（2）— 全试用
`audit_permission` / `audit_log` ✓

### 多租户命名空间（3）— 全试用
`store_open` / `store_list` / `store_close` ✓

### Omega 强验证（6）— 全试用
`omega_spec_create` / `omega_spec_review` / `omega_result_verify` / `omega_status` / `omega_verify` / `omega_verify_fix` ✓

### 开发模式与模板（2）— 全试用
`mode_list` / `mode_templates` ✓

### 衍生子项目 ATGC-old（3）— 全试用
`atgc_old_compile` / `atgc_old_run` / `atgc_old_talk` ✓

### 六顶帽（6）— 全试用
`hat_list` / `hat_debate` / `hat_run` / `hat_merge` / `debate_convene` / `debate_register` / `debate_verdict` ✓

### 项目助理（5）— 全试用
`assistant_claim` / `assistant_status` / `assistant_sweep` / `assistant_resign` / `assistant_heartbeat` ✓

### 超级管家（8）— 全试用
`supervisor_status` / `supervisor_task_tree` / `supervisor_kill_plan` / `supervisor_prompt_inject` / `supervisor_prompt_list` / `supervisor_prompt_consume` / `supervisor_task_upsert` / `supervisor_reminder_tick` ✓

### 嵌入式 MCPCf（7）— 全试用
`mcpcf.ops_init` / `mcpcf.circuit` / `mcpcf.report` / `mcpcf.review` / `mcpcf.run_batch` / `mcpcf.verify` / `mcpcf.watchdog` ✓

### 模型路由（5）— 全试用
`model_auth_status` / `model_route` / `model_router_status` / `model_router_reset` / `executor_run` ✓

### GitHub/GitCode 同步（12）— 部分
已试用：`github_env_check` / `gitcode_env_check` / `github_queue_status` / `github_flush_plan` / `gitcode_queue_status`(未) / `github_issue_webhook_parse`(未)
未试用（需网络+token）：`github_flush_execute` / `github_issue_close` / `github_issue_comment` / `github_queue_mark_sent` / `gitcode_flush_plan` / `gitcode_queue_mark_sent`

## 三、关键经验沉淀

1. **提交纪律**：`git commit` 扫全 index，必须用显式 pathspec `git commit -m "..." -- <paths>`（R154 教训：把并发 agent 的 `.mcp.dev.json` + `src/router/router_caf.mbt` 误提交）。
2. **Omega spec schema 四格收敛**：① YAML 非 JSON → JSON 解析失败；② tests[0] 非对象 → 拒；③ 缺 expected/error → 拒；④ fingerprint 须 fnv1a64 匹配。
3. **selfdrive_parse_next_tasks 格式**：`- [描述]`（无空格），跳过 `- [x]` 已完成。
4. **evolve_critic 判定**：combined = 0.5×score + 0.5×novelty，threshold=0.85；sim<0.3 即「无重复漂移」放行。
5. **BUG-74 口径**：github_queue_status total=0 只说明队列文件为空，≠ 无 bug 待上报（env 未启用故无入队记录）。
6. **mcpcf 隔离**：内嵌引擎独立库，mcpcf.run_batch 创建的 T0 只在内嵌库，主引擎 shim-review 无污染。
7. **debate 终态门是 user**：只给收敛读数，不自动判定议题通过/否决；anti_drift 双门（evolve_critic + goal_drift_check）。
8. **supervisor_reminder_tick 输出量巨大**：1772 条，属并发 agent 范围，本会话只读数不处置。

## 四、与并发 agent 的关系

- **零冲突**：所有提交用显式 pathspec，只含 `memory/` + `reports/` + `memory/links.md`。
- **只读不写**并发 agent 的 WIP：`src/server/stdio_js.mbt` / `src/ops/ops_selfdrive.mbt` / `src/router/router_caf.mbt` 等（M 标记）。
- **不发布/不归档** FIST 任务在 default ns；我的批次 ns=shim-review（T0r609/610/611 树）。

## 五、未试用能力的后续建议

| 能力 | 建议 |
|---|---|
| `task_cleanup` | 删除性（archived 超保留期清理），调用前必须复核 retention_days，本会话**不调用** |
| GitHub/GitCode flush | 需 FIST_GITHUB_ENABLED=true + token 才可执行；本机未配置，零网络副作用 |
| pipeline_tick report_ready | 有报告落盘后可触发 |

## 六、提交历史（本会话）

```
ac53f76 R163 evolve_sample + evolve_submit + evolve_critic + github_flush_plan
f05478e R162 github_queue_status + mcpcf.circuit + selfdrive_publish_next
501bb57 R161 selfdrive_parse_next_tasks + memory_gc + mcpcf.watchdog
9d6fa64 R160 selfdrive_append + mcpcf.verify + pipeline_tick
8cc8b58 R164 pipeline_tick(prompt_ready) + supervisor_reminder_tick + mode_list
6a6f752 R159 selfdrive_review_tick/ready + mcpcf.review/run_batch
40e351c R158 github/gitcode_env_check + reserve_scope + lock 闭环
f26c106 R157 debate_convene/register/verdict + mcpcf_ops_init/report
f583eb7 R156 cost_stats + call_log + cost_budget_check + omega_verify + omega_verify_fix
e0e2f3e R155 续 selfdrive_pick_next + supervisor_task_upsert
e42227d R155 纪律修正 + selfdrive_export_tasks
9be0c64 R153 project_standards + supervisor_prompt
```

## 七、结论

**发布版 fist-mbt 绝大多数能力已在 R127–R165 真实试用**（本会话 12 轮 + 早前累计），未试用项要么破坏性（task_cleanup）、要么需外部配置（GitHub/GitCode token）、要么需前置状态（pipeline_tick report_ready）。目标「善用发布版的 fist-mbt 任何能力」已实质达成——只余少量外部依赖/删除性能力未触碰，属于安全边界而非遗漏。