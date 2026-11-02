# USAGE.md 工具参数列一致性审计 + 漂移修复（T0r10 · 2026-11-02）

车道：`lane-j-usagedoc` ｜ ns：`iterate-1102` ｜ 任务：`T0r10` ｜ 状态：已完成待终审

## 结果摘要

- 真源表：以**活体 tools/list**（`node cli.js serve`，182 工具）为准建立「工具名→参数名集」，
  辅以 `src/server/server.mbt` 逐工具 schema 抽样 13 件交叉自证——**两源零冲突**。
- 修复前：USAGE.md §6 参数列 **38 个工具共 62 处 b 类漏写**、a 类多写 **0 处**（历史上广告的 `now` 幽灵参数已不存在）、
  c 类 1 处（`reserve_scope` 参数列裸名无必/选标注）、结构性漂移 2 处（§6.12 四行坏表、§6.6 `store_close` 重复行）。
- 修复后：对照归零（`temp/usage_param_diff.py` 复跑：a=0、b=0）；
  `check_usage_tool_count` PASS、`check_doc_surface`（J1-J18）PASS。
- 只动 `USAGE.md`（42 insertions / 44 deletions，全是 §6 表行）；未 commit（按任务边界）。

## 真源表建立方式（可复核）

1. `python temp/usage_param_dump.py`：起 `node _build/js/debug/build/cmd/cli/cli.js serve`
   （与 `scripts/mcp_smoke.py` 同款：先 `patch_esm_main` 注入 require shim、`FIST_DB_PATH` 改道 temp/），
   发 `tools/list`，把 182 个工具的 `inputSchema.properties` 与 `required` 落盘
   `temp/usage_tool_schema.json`。
   ⚠️ 采集坑两条（都实测踩过）：不带 `serve` 参数时 server 把首行 JSON 当 CLI 命令、打印 help 横幅即退出；
   启动横幅要先跳过再读 JSON 行。
2. `python temp/usage_param_diff.py`：解析 USAGE.md §6 全部表行（剥括号内容后取裸标识符作参数名），
   与活体 schema 集合差 → a/b 清单。产物：`temp/usage_drift.txt`。

## 漂移清单（修复前全量；b=文档漏写，c=标注/结构错）

| # | 工具 | USAGE 行 | 类 | 漂移内容 |
|---|---|---|---|---|
| 1 | publish | L189 | b | 漏 `level` |
| 2 | claim | L190 | b | 漏 `agent` `namespace` `inject` `challenge` `challenge_sig` |
| 3 | plan | L191 | b | 漏 `namespace` `inject` |
| 4 | execute | L192 | b | 漏 `agent` `namespace` |
| 5 | submit | L193 | b | 漏 `agent` `namespace` |
| 6 | verify | L194 | b | 漏 `namespace` `docs_check` |
| 7 | reject | L195 | b | 漏 `namespace` |
| 8 | retry | L196 | b | 漏 `agent` `namespace` |
| 9 | pause | L197 | b | 漏 `agent` `namespace` |
| 10 | resume | L198 | b | 漏 `agent` `namespace` |
| 11 | archive | L199 | b | 漏 `namespace` `force` |
| 12 | delete | L200 | b | 漏 `agent` `namespace` |
| 13 | list | L206 | b | 漏 `namespace` `resolve_from_main` |
| 14 | get | L207 | b | 漏 `namespace` `resolve_from_main` |
| 15 | task_plan_deep | L213 | b | 漏 12 个：`namespace` `omega_strong_verify` `gradient` `gradient_dag` `boundary_probe` `calibrate` `laya_auto` `decide_by` `decide_difficulty` `decide_reason` `decide_split_n` `reinject_context` |
| 16 | conflicts_check | L214 | b | 漏 `namespace` |
| 17 | heartbeat | L215 | b | 漏 `namespace` |
| 18 | heal | L216 | b | 漏 `namespace` |
| 19 | task_cleanup | L217 | b | 漏 `namespace` |
| 20 | tx_contract | L219 | b | 漏 `namespace` `force` |
| 21 | dag_critical_path | L234 | b | 写「无」实有 `namespace` |
| 22 | dag_parallelism | L235 | b | 写「无」实有 `namespace` |
| 23 | dag_check | L237 | b | 漏 `namespace` |
| 24 | dag_sort | L239 | b | 漏 `namespace` |
| 25 | reserve_scope | L242 | b+c | 漏 `challenge` `challenge_sig` `namespace`；c：`scope, agent` 裸名无(必)标注（活体三者均 required） |
| 26 | reserve_check | L243 | b | 漏 `namespace` |
| 27 | reserve_release | L244 | c | 标点混排 `scope(必), agent(必)`；漏 `namespace` |
| 28 | store_open | L272 | b | 漏 `scratch` `migrate` |
| 29 | §6.6 | L276 | 结构 | `store_close` 行整行重复 |
| 30 | reopen_task | L402 | b | 漏 `agent` `namespace` |
| 31 | run_check | L403 | b | 漏 `namespace` |
| 32 | dag_publish | L404 | b | 漏 `level` |
| 33 | watchdog_tick | L410 | b | 漏 `mode` `selfdrive_project_dir` `selfdrive_review_every` `flush_bug_queue` |
| 34 | pipeline_tick | L411 | b | 漏 `mode` |
| 35 | selfdrive_publish_next | L423 | b | 漏 `mode` |
| 36 | §6.12 | L437-440 | 结构 | `laya_decide`/`loop_create`/`loop_tick` 三行只有 2 列（无参数列）；`loop_status` 行 4 列错位——把 `laya_decide` 的说明与参数列（context/questions/model）错挂到自己名下 |
| 37 | laya_decide | L437-440 | b | 修表时按活体补 `no_sidecar` `split_n_hint` |
| 38 | loop_create | L438 | b | 修表时按活体列全 8 参：`name`(必) + `preset` `steps` `max_rounds` `stop_on_goal` `stop_on_exceeded` `baseline_test_count` `baseline_open_bug_count` |
| 39 | loop_tick | L439 | b | 修表时按活体列全 5 参：`name`(必) + `current_test_count` `current_open_bug_count` `blocked_tasks` `project_health_grade` |
| 40 | loop_status | L440 | b | 活体参数 `name(选)`（原文档无参数列） |
| 41 | omega_spec_create | L444 | b | 漏 `namespace`（前轮漏改，复跑对照抓到后补） |
| 42 | omega_spec_review | L445 | b | 漏 `namespace` |
| 43 | omega_result_verify | L446 | b | 漏 `namespace` |
| 44 | omega_status | L447 | b | 漏 `namespace` |

a 类（文档多写、活体没有）：**0 条**（改进型提取器先剥括号内容再取裸标识符，`now` 幽灵参数确认已绝迹）。

## 抽样自证（修后 USAGE 参数名 ↔ server.mbt schema，13 件 >10 件）

publish/level（server.mbt:2052）、claim/inject+challenge+challenge_sig、archive/force（server.mbt:2863 段）、
verify/docs_check、store_open/scratch+migrate（server.mbt:8378-8391）、list+get/resolve_from_main（server.mbt:2929/3002 段）、
task_plan_deep/omega_strong_verify+laya_auto+gradient 等、watchdog_tick/flush_bug_queue+selfdrive_project_dir+mode、
run_check/namespace、dag_critical_path/namespace、reserve_scope/challenge+challenge_sig、pipeline_tick/mode（server.mbt:4097 段）、
publish/level——全部在对应工具 schema 里找到，两源（活体 tools/list ↔ server.mbt 源码 grep）零冲突。

## 缺口与风险（交统帅裁决，未动手）

1. **AGENTS 摘要面同类漂移**（`docs/AGENTS-mcp-inventory.md`，按边界只列不动）：
   - `wt_create`（L135）散文参数列多写 3 个：`task` `base` `ttl_min`（活体只有 branch, detach, path, project_dir, timeout_ms）——a 类；
   - `agent_register_key`（L168）参数清单漏写 4 个：`challenge` `proof_sig` `rotate_challenge` `rotate_sig`（b 类；rotate 两参散文上文提到但未入参数行）。
   - 抽查其余 8 个散文参数自述（text_diff/rank_of/soldier_type_of/soldier_route/staff_label_of/commissar_send/commissar_read/agent_revoke_key）与活体一致。
2. **src 侧 schema/描述不一致**：`pipeline_tick` 活体 inputSchema `required=[]`，但工具描述与运行时（`get_str(args,"project_dir")` 无 default）都按必填写——USAGE 保留 `project_dir(必)`；建议 src 侧把 `project_dir` 加进 required 数组（未动 src/）。
3. **§6.15 五个模型路由工具**（model_route/model_auth_status/model_router_status/model_router_reset/executor_run）在 USAGE 无参数表行（该节自述只讲接线配置、工具调用指 §6 与 AGENTS.md）；参数面如需入册是新增表，超出「修漂移」边界，未动。
4. **参数列仍无守卫面**：本轮把清单归零，但参数列依旧没有 `check_*` 判据盯防（J2 只比工具名、J8 只比 templates），下一轮加参数即再漂移。建议立项把 `check_usage_tool_count.py` 升格为「工具名+参数名集」双向对表（真源可用 `scripts/_tool_registry.py` 同款解析面）。
5. USAGE.md L183「参数表取自本机 tools/list 返回的真实 Schema」的承诺只有本轮人工兑现，机器面同缺口 4。

## 资源消耗

一轮会话内完成：2 支临时判据（temp/，已 gitignore）+ 1 轮活体采集（3 次试错：缺 `serve` 参数、横幅拦路）+ 8 组 Edit + 2 次复跑对照 + 2 道既有守卫复验全绿。
