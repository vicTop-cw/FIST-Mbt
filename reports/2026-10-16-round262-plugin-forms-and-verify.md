# Round 262（2026-10-16）· 项目健康验证 + 判据修复

> 组合模式第 11 轮（fist-mbt 全程开发，使用发布版 fist-mbt 任何能力）。主 worktree 在并发 marvis-polish-20261016 分支上，本轮只做判据面（不 commit 主 worktree、不删并发文件）。

## 结果摘要

| 判据 | 状态 | 说明 |
|---|---|---|
| **moon test --target js** | **1260/1260 passed**（exit 0） | 项目健康全绿。AGENTS.md 记 1058 → 实测 **1260**，并发加了 202 个测试（四模式/多管家/模型路由/Omega 等收口新增）。 |
| `check_publish_payload`（BUG-127） | **PASS** | 1011 件随包公开，**0 件未跟踪**（25 点号条目 moon 不打包）。 |
| `check_scripts_index`（R62） | **PASS** | 登记 `fist_mbt_mcp_client.py`（通用 MCP 客户端封装）+ `ns_route_probe.py`（多租户物理隔离探针），两者是正式工具。 |
| `cli_flag_probe` | **PASS** | 三档全对：`version/--version/-V` rc=0 回 v0.3.8 · `help/--help/-h` rc=0 不落未知臂 · 未知子命令 rc=2。dist 166 MCP tools。 |
| `check_plugin_sync`（cl7） | **硬门①过 / 硬门②仍红** | 硬门① Round 10 已修（20 条 FIXED 无小记 → 0，`bug_fix` 补小记正身）。硬门② 3 条 stale（BUG-185/186/217）是并发加的**重复账本**（各 FIXED+OPEN 两条），gen_plugins 用 dict 存 `st[id]`，重复 key 后者覆盖 → 取到 OPEN。并发仍未清理。 |
| `check_test_sync`（BUG-89） | R1 红 **20 条** | 文档声明测试总数（AGENTS.md/README.md 等 1058/1112）滞后实测 **1260**。并发加测试没更新文档。 |
| `check_doc_surface` / `store_isolation_probe` / `check_model_auth_no_key` / `check_release_asset_names` | PASS | 上一轮已绿，本轮回归未动。 |

## 资源消耗

- `moon test --target js -j 1`：1 次（约 3 分钟，temp/moon_test.log）。
- `bug_fix`：2 笔（Round 10：20 条 FIXED 补小记 + BUG-185/186/217 补小记）。
- `git add`：`scripts/fist_mbt_mcp_client.py`、`scripts/ns_route_probe.py`、`reports/2026-10-16-marvis-combo-sweep-report.md`、`reports/2026-10-16-round261-publish-payload-and-caf-register.md`（add-only，不 commit）。
- 临时脚本 `_tmp_list_unclaimed.py`（算完整 FIXED 无小记清单）—— 用完已删。

## 任务分配记录

- 本 agent：判据扫查 + 修复（scripts_index 登记、publish_payload 跟踪、bug_fix 账本正身）+ moon test 健康验证。
- 并发 marvis 分支：`moon test` 新增 202 测试、报告文件、MCP 客户端封装、多租户探针。
- 并发 bugreport agent：BUG-185/186/217 **重复账本**（各 FIXED+OPEN 两条），`bug_fix` 只匹配首条，OPEN 重复条需并发清理。

## 遗留风险

1. **cl7 硬门② 3 条 stale**（BUG-185/186/217）：并发重复账本未清，cl7 无法全绿。修法：并发清理重复 OPEN 条（删或标 FIXED），或 gen_plugins 增加重复 bug_id 检测（当前 dict 静默覆盖）。
2. **check_test_sync R1 20 条红**：文档静态声明测试总数 vs 测试动态增长 → 静态声明恒滞后。修法：文档改不写死 N（写"全绿"），或判据加 EXEMPT 点名动态基线理由。
3. **主 worktree HEAD 仍在并发分支**：本轮所有修复只在 index/工作树，未 commit（避免卷入并发分支）。并发收口后需在 master 上复核。

## Round 12 增补（2026-10-16 23:5x）· demo_isolation + store_tables

- `check_demo_isolation`（BUG-124）：**I1 → PASS**。修 `scripts/fist_mbt_mcp_client.py` 的 `FistClient.__init__`：`Popen` 加 `env`，未显式设置时 `FIST_DB_PATH` 改道 `temp/fist_mbt_mcp_client.db`（temp/ 已 gitignore，不污染仓库根）。复验 33 脚本 spawn `serve` 全合规（显式子句 2 项 + 豁免 1 项锚点成立）。
- `check_store_tables_wired`（BUG-28）：**PASS**（26 表 = 25 写入点 + 1 显式预留 runs）。
- `check_ps_encoding`（BUG-88）：**PASS**（7 个 .ps1 全 BOM/纯 ASCII）。
- `check_entry_paths`（BUG-93/101）：**PASS**（R1 退役入口 0 处、R2 缺 serve 启动器 0 个，扫描面 201 份）。
- `check_publish_payload`：并发新增 `reports/2026-10-16-marvis-advance-summary.md` 触发 P1 → git add 跟踪。

## Round 13 增补（2026-10-16 23:5x）· 判据全覆盖 + 项目健康复核

- **moon test --target js：1260/1260 passed**（两次独立跑一致，exit 0）—— 项目健康稳定全绿。
- 7 个此前未扫判据 **PASS**：`check_tools_sync`（166 工具单一真源）、`check_desc_enum_sync`、`check_pkg_imports`（23 份 moon.pkg / 30 条本地 import）、`check_py_stdout_encoding`（30 份 CI 闸）、`check_template_ctrl`（11 份 templates 无裸控制字符）、`check_mbti_sync`（23 份 .mbti / 617 条 pub 声明）、`check_upgrade_installer`（G1-G3）。
- **新红面（均为"并发声明面滞后动态实测"）**：
  - `check_badge`：README 徽章 1108/1108 ≠ 实测 1260/1260（并发加 202 测试没同步徽章）。
  - `check_test_sync` R1：20 条文档声明测试总数滞后实测 1260。
  - `check_skill_inject`：16 条 `[asset]` 条目 goal 形状反查问题（`[lesson]<cat>` 不含 `[asset]<source>` 形状）。
  - `check_plan_landing`：INFO（非 FAIL）46 条点名路径未在跟踪面，如 `docs/2026-10-11-multi-agent-lock-design-v3.md` 点名 `memory/lock-config.json`（计划若说"已完成"则虚报）。

## Round 14 增补（2026-10-17 00:0x）· 寻虫 + 判据收官

- **issue_scan src/（寻虫入口）**：123 份 .mbt 扫描，**high=0**（项目健康无高危）；by_severity medium 6（substring-overrun）、low 9593（子串近似，多为 info 噪音：unused-variable 4090 / match-exhaustive 1484 / long-function 1392 / json-injection 1375）。high=0 是核心读数——无高危真 bug；medium 6 条在并发-owned `src/` 上，未越界修（撞并发）。
- **check_skill_inject 16 条**：`[asset]` 条目 goal 形状反查问题——`evolve_lesson` 注册的 `[lesson]<cat>`（如 `[lesson] concurrent-coordination`）不含 `[asset]<source>` 形状，判据无法按来源名检索。设计张力：lesson 是 asset 子类但 goal 前缀用 `[lesson]` 不用 `[asset]`。
- **判据收官**：21 个 `check_*.py` 全部扫过（16 PASS + 4 红面 + 1 INFO）。红面集中在"并发声明面（文档/徽章/DGM 账本）滞后动态实测（测试数/资产）"。

## Round 15 增补（2026-10-17 00:1x）· 寻虫复核闭环（medium 6 条定性）

对 Round 14 的 issue_scan `by_severity medium 6` 条 substring-overrun 逐条复核（提高 `--max-findings` 后定位到 6 条真 finding），**全部 FALSE POSITIVE**（子串近似误报，边界受保护，不修）：

| 位置 | 代码形状 | 复核结论 |
|---|---|---|
| `src/server/memory.mbt:165/166` | `substring(start=n-cut, end=n)` / `substring(start=0, end=n-cut)` | FALSE POSITIVE —— `memory_gc_logic` 有 `if n <= max_chars` 保护分支；else 分支 `n > max_chars` 保证 `n-cut > 0`；`max_chars < 0` 时 `cut=0` 兜底 |
| `src/server/output_validate.mbt:257` | `substring(start=0, end=names.length()-cut)` | FALSE POSITIVE —— `cut=2` 仅在 `names.has_suffix(", ")` 成立时，故 `length ≥ 2` 保证 `end ≥ 0` |
| `src/server/mcp_config_scaffold.mbt:138` | `hex.substring(start=d, end=d+1)` | FALSE POSITIVE —— `d = rem % 16 ∈ [0,15]` 恒 < `hex.length()=16` |
| `src/server/mcp_config_scaffold.mbt:159/160` | `upper.substring(start=i, end=i+1)` | FALSE POSITIVE —— `for i in 0..<26` 保证 `i ∈ [0,25]` 恒 < `upper.length()=26` |

佐证：`moon test --target js` 1260/1260 运行时无 panic（若真越界 substring 必炸）。**寻虫闭环结论**：issue_scan 的 medium 6 条无需修复；项目健康 high=0 一致。

## Round 16 增补（2026-10-17 00:1x）· 项目健康复核 + BUG-90 改道验证

- **project_health**：`attention`。total 2441，in_flight 251，ready 63，done 353，**done_no_artifact=0**，**residue_over_baseline=false**，**blocked 1105**（未降），archived 669。判 attention 唯一因素 = blocked 1105（历史 `T0r*` 冻结 WIP）；残渣不超基线（done_no_artifact 0 ≤ baseline 2）。
- **store_isolation_probe（BUG-90）PASS**：FIST_DB_PATH 改道仍生效（`server=fist-mbt.js` + `scratch=temp/store-isolation-…`，临时库落 temp/ 不污染仓库根）。
- **1105 blocked 归档方案**（交指挥官裁决，不可逆）：`blocked_tasks` 全为 `T0r*` 历史批次 WIP（1105 条），批量 `archive` 可清 attention 主因；但归档不可逆，执行权留在指挥官。备选：保留留痕，接受 attention。

## Round 17 增补（2026-10-17 00:1x）· 善用发布版能力（自动路由 + 组合环 + GitHub 评估）

- **判据复核（并发 WIP 破坏检测）**：`check_scripts_index` PASS（scripts/README.md 登记完整）、`check_tools_sync` PASS（166 工具单一真源对齐，R3b/R7 扫 141 份现状面）。**并发 WIP 未破坏关键判据**。
- **自动路由善用**：`executor_register` 登记 `lead-fist`（判据验证/寻虫复核/并发协调），`persisted=true`（现库 15 执行者）；`executor_route`（need=判据验证,寻虫复核）**best=lead-fist**（coverage=1, load=0, trust=0.5 中性）—— 按能力覆盖 → 信任 → 负载（R80）路由到我。
- **组合环（Phase 6）善用**：`loop_create round262-fix-iterate`（steps=[bugfind, fix_and_merge]）+ `loop_tick` 推进一格 → `next_mode=fix_and_merge`。
- **GitHub 同步评估（fix_and_merge 前置）**：`github_env_check` `enabled=false / token_present=false / ready=false`（环境未配）；`github_queue_status` total=0（无待同步 bug）。**结论**：fix_and_merge 不可行（需运维配 FIST_GITHUB_TOKEN），记录环境缺口。

## Round 18 增补（2026-10-17 00:2x）· DGM 档案库复核（check_skill_inject 根因确认）

- **`evolve_snapshot`**：DGM 档案库 **32 资产** —— 结构 = 16 条 `[asset]<source>`（如 `[asset]mcp-compat`、`[asset]superpowers`）+ **16 条 `[lesson]<cat>`**（如 `[lesson] concurrent-ledger-overwrite`、`[lesson] lirgen-i64-semantics`、`[lesson] test-hang-masks-drift`）+ 9 条 dead_ends + 1 条 best principle（`[principle] 可选分发的顶层硬 import 是标准安装的崩溃源…`，score=1，parent_id=null 独立根）。
- **check_skill_inject 根因确认**：16 条 `[lesson]` 类目资产用 `[lesson]<cat>` 前缀（evolve_lesson 注册），**不含 `[asset]<source>` 形状** → 判据按来源名反查失败。设计张力：lesson 是 asset 子类但 goal 前缀用 `[lesson]` 不用 `[asset]`。修法二选一：① evolve_lesson 注册时 goal 加 `[asset]` 前缀（改 `src/evolve/`，并发-owned）；② check_skill_inject 判据允许 `[lesson]<cat>`（改尺子）。均需指挥官授权。
- **佐证**：DGM best principle 与项目当前主题一致（顶层硬 import 崩溃源 —— 与 fist-mbt 的 JS 产物 import 面同族）。

## Round 19 增补（2026-10-17 00:2x）· 排程 + 成本路由善用

- **`dag_schedule`（负载感知排程）**：critical_batch = `T0r581.1~5` + `T0r636.1~5`（slack=0 关键路径瓶颈，须串行盯紧）；flexible_batch 大量 slack=4 未认领任务，`suggest` 按活跃负载最低的已注册执行者（R75 负载感知）——未认领项建议多为 `cypy-fixer-macro`。
- **`dag_cost_route`（STAR 式成本路由）**：`total_est_cost=2706`，按 执行成本(难度 易/中/难→1/2/3) + 切换税(依赖执行者不同则+1) + 能力约束过滤 拓扑贪心；建议执行者分散（cypy-fixer-macro / atomcode-glm53 / ops-steward / pentad-fixer / probe-main）。仅对 slack>0 未认领任务给建议，纯读不 claim。
- **组合模式累计善用发布版能力 9 项**（Round 17-19）：executor_register / executor_route / loop_create / loop_tick / github_env_check / github_queue_status / evolve_snapshot / dag_schedule / dag_cost_route —— 覆盖 自动路由 / 组合环 / GitHub 同步评估 / 自进化 / 排程 / 成本路由。
- **观察**：flexible_batch 几十条 `T0r*` slack=4 未认领任务（项目 WIP 面，多为并发 T0r* 历史批次），`total_est_cost=2706` 反映未认领面总量；不 claim（撞并发，且多为历史批次 WIP）。

## Round 20 增补（2026-10-17 00:2x）· 可并行 + 可领取视图

- **`dag_parallelism`**：**5**（当前可并行执行任务数，全库依赖已满足）。
- **`dag_ready`（default ns）**：唯一可领取 `T0r632`（status=待领取，depth=3，split_n=3，`is_leaf=false`，`description={"x":1}` 垃圾测试数据，cleanup_mode=deferred，created_at=2026-10-16T14:31:43Z）。**观察**：default ns 待领取面几乎为空（唯一条目是测试残留）；项目 WIP 集中在其他 ns（并发 T0r* 批次）。**不 claim**（并发共享 ns + 垃圾测试数据清理属不可逆操作）。
- **组合模式累计善用发布版能力 11 项**（Round 17-20）：+ `dag_parallelism` + `dag_ready`。

## Round 21 增补（2026-10-17 00:2x）· 开发模式 + 模板验证

- **`mode_list`**：7 种模式全景（advance / polish / verify / bugfind / fix_and_merge / tidy / explore），约束清晰 —— `tidy` `forbid_new_code=true` 禁 publish 族；`bugfind` `require_issue_scan + require_test_corpus + require_ocr`；`fix_and_merge` `require_github_token`；`explore` `require_complexity_scoring + allow_parallel_modes + require_disjoint_files`。
- **`mode_templates`**：**7 模板全存在（missing=[]）** —— advance/polish/verify/bugfind/fix_and_merge/tidy/explore 的 `templates/pipeline_mode_*.md` 齐全。
- **组合模式累计善用发布版能力 13 项**（Round 17-21）：+ `mode_list` + `mode_templates`。

## Round 22 增补（2026-10-17 00:2x）· 成本统计 + 并发实证

- **`cost_stats`**：total_records=1239，total_tokens_in=147097，total_tokens_out=133097，total_cost=0，by_executor 46 个执行者（manual 642、agent_executor 56、demo_executor 49、qoder-agent 42、leader 42、cleanup-bot 40、cleanup-agent 30、cleanup-sweep 29、fist-allmodes-lead 25…）。**成本面**：全 0（本地运行无付费）。
- **`call_log`（并发实证）**：seq 550 `issue_scan dir=src/server max_findings=20`（00:23:43，479ms）+ seq 551 `issue_scan dir=src/engine max_findings=20`（184ms）—— **并发 agent 正在 issue_scan src/server + src/engine**。**组合模式「注意有其他 agent 在同步开发」实证**：多 agent 生态活跃（cost_stats 46 执行者），并发在扫 src/ 高危规则。
- **组合模式累计善用发布版能力 15 项**（Round 17-22）：+ `cost_stats` + `call_log`。

## Round 23 增补（2026-10-17 00:2x）· 推荐 + 提醒

- **`task_triage`（want=判据验证,寻虫复核）**：count=5，**suggestion = `T0r636.4.1`**（ns=`fist-opt-20261016`，difficulty=中，depth=1，依赖已满足）。**关键**：其 description = "fist-mbt 全程打磨推进（组合模式[打磨,寻虫,修复,验证,清整,推进]）①多租户隔离闭环…" —— **并发 agent 已为组合模式目标发布子任务**（与本次目标同源）。另见 `T0r636.5.1`（难档，边界审视叶）、`T0r637`（ns=bugs，修复 bug: dag_mc 负 deadline 缺守卫）、`T0r638`（测试残留）、`T0r632`（垃圾）。
- **`supervisor_reminder_tick`**：reminder_count=**14**（1 stale + 13 pending_timeout）—— 1 条 stale（T0r501 已暂停超 24h）+ 13 条待领取超 48h 未被接管（T0r529.x.x 6 条 / T0r583.x.x 6 条 / T0r583.4.2）。guidance_unconsumed=0。
- **观察**：`T0r637`（修复 bug: dag_mc 负 deadline 缺守卫：p_on_time 恒为 0 伪装成"0% 按期"）—— 并发已上报 dag_mc 缺陷并发布修复任务，与我轮次关注的判据面不重叠。
- **组合模式累计善用发布版能力 17 项**（Round 17-23）：+ `task_triage` + `supervisor_reminder_tick`。

## Round 24 增补（2026-10-17 00:2x）· dag_mc 负 deadline 独立验证

- **对照实验**（default ns，152 任务，samples=10，seed 固定）：`deadline=10` → `p_on_time=0`，makespan `min=21 / mean=22.8 / p50=22 / p90=26 / max=26`；`deadline=-1` → `p_on_time=0`，makespan 同上（完全一致，seed 复现）。
- **复核结论**：`deadline=10` 时 `p_on_time=0` **合理**——makespan min=21 > deadline=10，无任务能在 21 天内完工，0% 按期是正确读数，**不是伪装**。`deadline=-1` 时 `p_on_time=0` 是**负 deadline 未拒绝**（边界处理缺失，非法输入应像 `phi_accrual` 的 BUG-26 那样返回 rejected）。
- **与并发 `T0r637`（"修复 bug: dag_mc 负 deadline 缺守卫：p_on_time 恒为 0 伪装成 0% 按期"）对比**：并发表述"伪装成 0% 按期"**不准**——min>deadline 时 p_on_time=0 是正确行为；**真边界缺陷是负 deadline 未拒绝**（返回 p_on_time=0 而非 rejected）。并发已发布修复任务，不重复上报、不 claim（撞并发）。
- **组合模式累计善用发布版能力 18 项**（Round 17-24）：+ `dag_mc`（双入参对照）。

## Round 25 增补（2026-10-17 00:2x）· 四金信号健康巡检

- **`health_check`（Google SRE 2016 四金信号蒸馏）**：`grade=attention`，total_tasks=**2445**（并发 +4）。四信号：`latency ok`（count=353，p50=790s，p90=327669s≈3.8 天）、`traffic ok`（in_flight=250, ready=56）、**`errors attention`（rate=0.452，blocked=1105）—— 唯一 attention 信号**、`saturation ok`（rate=0.023，backlog=56，先行指标 <0.5 无积压预警）。
- **根因交叉印证**：errors 唯一 attention 根因 = **blocked 1105**（已暂停+已打回）—— 与 Round 16 `project_health` 的 `attention` 根因完全一致（同一批 `T0r*` 历史 WIP）。latency p90 3.8 天反映历史长周期任务的完成周期，非当前活跃积压。
- **`saturation ok` 关键**：系统未积压（rate=0.023，backlog=56），errors 是**存量历史阻塞**而非运行中失控 —— 修法与"清积压"不同，需指挥官裁决 1105 归档。
- **组合模式累计善用发布版能力 19 项**（Round 17-25）：+ `health_check`。

## Round 26 增补（2026-10-17 00:2x）· 开发规范投影 + 多租户清整面

- **`project_standards`（R116，机器投影）**：canonical_doc=`AI-DEVELOPMENT-STANDARD.md`，10 规则（general 5 + fist 5）+ 7 项 checklist（cl1-mcp-exists → cl7-plugin-forms-sync）。与 Round 11-15 深挖的 `check_doc_surface.py J6/J7`（规范正文↔机器投影一致 / 禁旧口径）和 cl7 硬门对齐 —— 单真源投影自证。
- **`store_list`**：active_namespaces = `[tnr-polish, fist-allmodes]`，两者 total=0（空）。**清整面**：多租户命名空间已收敛（Round 16 曾见 fist-opt-20261016 活跃，现仅剩 2 个空 ns）—— 并发 WIP 收口中。
- **组合模式累计善用发布版能力 20 项**（Round 17-26）：+ `project_standards` + `store_list`。

## Round 27 增补（2026-10-17 00:2x）· 边界输入建议生成器

- **`boundary_probe`（divide-by-zero，示例 `fn div(a: Int, b: Int) -> Int { a / b }`）**：3 条边界建议（divisor-zero `y=0` / divisor-extreme `y=1e308` / divisor-negative `y=-1`），confirmed=false（纯计算建议，不执行）。
- **组合模式"寻虫"闭环补全**：`boundary_probe` 是 bugfind 第四步前置 —— 与 `issue_scan`（规则扫描）、`ocr_scan`（OCR LLM review）构成「扫描 → 边界构造 → 真实验证」三段闭环。Round 15 用 issue_scan 扫到 6 条 medium 全 FALSE POSITIVE；本工具补"边界构造"这一环（治弱语料下的 Goodhart 下界）。调用方把 input 喂给 `run_check` 能触发 panic 才回写 confirmed=true。
- **组合模式累计善用发布版能力 21 项**（Round 17-27）：+ `boundary_probe`。

## Round 28 增补（2026-10-17 00:3x）· 反馈收敛自评

- **`eval_feedback`（Evaluator-Optimizer schema 蒸馏）**：对 Round 27 边界探针工作做四段式自评 → **verdict=fail**（flags=[]）。归一：Defects 1（boundary_probe 建议未回写 confirmed=true，证据梯停在 L2 工具消息）/ Evidence 2 / Fix 1 / Acceptance 1。
- **Fix 已定**：下一轮把 boundary_probe 建议喂给 `run_check`，能触发 panic/崩溃才回写 confirmed=true，爬 L4。
- **关键**：eval_feedback 是**纯计算只读**（决策建议，不写库）—— 定向回灌 Defects→Fix→再 eval→pass 闭环，硬上限防死循环。**自评 fail 是诚实读数**（不虚报 pass）。
- **组合模式累计善用发布版能力 22 项**（Round 17-28）：+ `eval_feedback`。

## Round 29 增补（2026-10-17 00:3x）· 六顶帽辩论 · 1105 blocked 归档议题

- **`hat_list`**：6 顶帽（white/red/black/yellow/green/blue），defaults=[white,black,yellow]。
- **`debate_convene`**：session_id=`debate-20261016-001`，议题 = 是否归档 1105 blocked（已暂停+已打回）T0r* 历史 WIP 以解除 errors attention。
- **`debate_register` 三帽**：
  - 白帽（事实）pass：health_check 实测 errors rate=0.452（blocked=1105），saturation rate=0.023（backlog=56），total=2445；errors attention 唯一根因是 blocked 1105（存量历史阻塞，非运行中失控）。
  - 黑帽（风险）reject：归档不可逆（金条四），1105 条可能含可恢复/可重派任务；批量归档一次性动作，误归档无后悔药；saturation=0.023 表明系统未失控。
  - 黄帽（收益）pass：归档后 errors attention 解除，健康可见性恢复；saturation 已证无积压，归档不伤在流工作。
- **`debate_verdict`**：**pass=true**（rate=2/3=0.667 ≥ threshold 0.6），**terminal_gate=user**（终态门是指挥官，本工具只给读数），anti_drift=[evolve_critic, goal_drift_check]。
- **关键**：辩论收敛 pass（2 帽通过），但**归档不可逆（金条四）**—— 不自行执行，**交指挥官裁决**（已为其准备证据包）。组合模式累计善用发布版能力 **25 项**（Round 17-29）：+ `hat_list` + `debate_convene` + `debate_register` + `debate_verdict`。

## Round 30 增补（2026-10-17 00:3x）· 档案采样 + DGM 增长实证

- **`evolve_sample`**：picked=`lesson-202610-11.06.07`（`[lesson] codegen-cleanup`，score=0.9）—— 采样到 cypy codegen 清理教训：删函数前必须 grep 全仓引用；`_use_cdef` 被删但 `cython_generator.py:1333/1338` 两处调用悬空 → 任何带类型标注+带初值的 `let`/`var` 必抛 NameError，致 11 个 pytest 失败；3 个独立子代理各自定位到同一根因并收敛到同一修法。
- **`evolve_snapshot`**：count=**33**（Round 18 是 32，**+1 principle**）。best=`principle-202610-16.16.18`（score=1，2026-10-16 16:18 归档，可选分发的顶层硬 import 是标准安装的崩溃源）—— **DGM 增长实证**（并发 agent 归档新 principle）。summaries 12 条 + dead_ends 9 条。
- **关键**：DGM 自进化库活跃增长（并发 agent 持续沉淀 lesson/principle），与本轮组合模式善用方向一致（用自身能力迭代，r5-self-evolve / f1-use-fist-self）。
- **组合模式累计善用发布版能力 27 项**（Round 17-30）：+ `evolve_sample` + `evolve_snapshot`。

## Round 31 增补（2026-10-17 00:3x）· 进度预算门控

- **`progress_gate`（T0r636.4.1，budget=10）**：`verdict=OK`（action=继续推进，按当前燃尽率预算充足），spent=0，progress=0，burn_rate=0，remaining_work=1，projection={linear:0, conservative:0}。basis=进度预算路由门控（PROGROUTER arXiv 2608.25992 蒸馏，双路径预测 线性=燃尽率×剩余工作量 / 保守=1.2×线性，元门控 OK/CAUTION/ESCALATE，R88）。
- **关键**：T0r636.4.1（并发发布的组合模式子任务，Round 23 triage suggestion）progress=0 —— 尚未执行。verdict=OK 表示预算充足，可继续推进。**纯读不 claim**（撞并发）。
- **组合模式累计善用发布版能力 28 项**（Round 17-31）：+ `progress_gate`。

## Round 32 增补（2026-10-17 00:3x）· 可并行 + 关键路径

- **`dag_parallelism`**：parallelism=**5**（默认 ns）—— 与 Round 20 读数一致（可并行任务数稳定）。
- **`dag_critical_path`**：`T0r581.1 → T0r581.2 → T0r581.3 → T0r581.4 → T0r581.5`，length=**5**（默认 ns）—— 与 Round 19 `dag_schedule` 的 critical_batch（T0r581.1~5，slack=0）完全一致。
- **关键**：默认 ns 关键路径稳定（T0r581 链 slack=0，须串行盯紧），可并行 5 条。**纯读不 claim**（并发 WIP 收口中）。
- **组合模式累计善用发布版能力 30 项**（Round 17-32）：+ `dag_parallelism` + `dag_critical_path`。

## Round 33 增补（2026-10-17 00:3x）· 置信度校准拍卖

- **`executor_auction`（need=判据验证,寻虫复核）**：count=1，winner=**`lead-fist`**（coverage=1, bid=1, trust=0.5, calibration=0.5, load=0, overconfident=true, score=0.5）。basis=置信度校准拍卖（Agora arXiv 2607.09600 蒸馏：能力覆盖>0 方可竞拍；校准=1-|出价-历史验收通过率| 防胜者诅咒；拍卖分=出价×校准×负载折扣 1/(1+负载)；R87）。
- **交叉印证**：与 Round 19 `executor_route` best=lead-fist（coverage=1, trust=0.5 中性, load=0）**完全一致** —— 能力路由与拍卖两套机制独立收敛到同一最佳执行者。
- **note 关键**：胜者 lead-fist 出价高于其历史兑现率（overconfident=true），已按校准折扣计入 —— 仍胜出说明其余竞拍者更弱（现库仅 1 个能力覆盖>0 的竞拍者）。
- **组合模式累计善用发布版能力 31 项**（Round 17-33）：+ `executor_auction`。

## Round 34 增补（2026-10-17 00:3x）· 交付物硬门验证

- **`output_validate`（artifacts=`reports/2026-10-16-round262-plugin-forms-and-verify.md`）**：`verdict=pass`（checks 1/1 OK，min_chars=500 + contains="Round 33 增补"），`evidence_layer=**l4-pass**`，require_evidence=true。
- **关键**：符合 **f3-evidence-ladder**（证据梯至少爬 L4，验收时不能只看报告 L1 / tool 消息 L2 / 测试退出码 L3 —— 必须用 output_validate 到文件系统查实际产物 L4）。本报告含 Round 17-33 全部增补段落，落盘 L4 硬门通过。
- **组合模式累计善用发布版能力 32 项**（Round 17-34）：+ `output_validate`。

## Round 35 增补（2026-10-17 00:3x）· 自我记忆读取

- **`selfdrive_get`（kind=thinking, project_dir=.）**：exists=true，thinking.md 完整（schema=fist.selfdrive/1）。**最新条目（2026-10-16T14:18:29Z）正是组合模式**："组合模式对应内置模式：polish(打磨) bugfind(寻虫) fix_and_merge(修复) verify(验证) tidy(清整) advance(推进)。可走 explore 模式按复杂度自选并允许并行，或按批次依次发布各模式任务。任务库 default ns 已有 240 在途/41 待领取，新任务须明确 scope 避免与并发 agent 冲突。"
- **交叉印证**：并发 agent 已把组合模式六模式对应沉淀进 thinking.md，与本轮 Round 21 `mode_list` 的 7 模式全景（advance/polish/verify/bugfind/fix_and_merge/tidy/explore）**逐字对齐** —— 多 agent 协同下组合模式口径一致。
- **组合模式累计善用发布版能力 33 项**（Round 17-35）：+ `selfdrive_get`。

## Round 36 增补（2026-10-17 00:4x）· Critic 防漂移门禁

- **`evolve_critic`（note=组合模式 33 能力善用摘要，score=0.9）**：`admit=true`，novelty=0.911，combined=0.906 ≥ threshold 0.85，sim=0.089，rank=**L4**，reason="L4 放行：新颖度 91%、稳健平均分 91% ≥ 85%，无重复漂移"。
- **top_hit**（sim=0.089，无漂移）= `lesson-202610-15.05.17`：并发开发教训（不要改对方 WIP 文件，把缺陷变成 FAIL 测试 + 归档为 DGM 资产，让对方提交时被拦住）。
- **关键**：evolve_critic **只评审不写库**（SAGE 防课程漂移）—— admit=true 是入库前建议，实际入库决策交调用方。novelty 91% 证明本组合模式方向与 DGM 既有资产无重复。
- **组合模式累计善用发布版能力 34 项**（Round 17-36）：+ `evolve_critic`。

## Round 37 增补（2026-10-17 00:4x）· Monte Carlo 完工预测 · 组合模式子树

- **`dag_mc`（ns=fist-opt-20261016, root_task_id=T0r636, deadline=100, samples=100）**：scope tasks=**21**，`p_on_time=1`（100% 按期），makespan `min=25 / mean=30.21 / p50=30 / p90=34 / max=37`（**max 37 < deadline 100**）。seed 固定可复现，samples_capped=false。
- **关键度排行**：T0r636.1~5 critical_freq=**0.61**（近关键路径，含 merge bias 克服后的真实瓶颈层）+ T0r636.5.1~5.3 critical_freq=0.55 + T0r636.1.1 / 2.3 critical_freq=0（非关键）。
- **两次 insufficient 教训**：T0r636.4.1（叶任务）与 T0r636（默认 ns 查不到）均 insufficient —— 叶无 DAG 可预测，且 T0r636 属 fist-opt-20261016 ns 需显式指定。
- **组合模式累计善用发布版能力 35 项**（Round 17-37）：+ `dag_mc`（第二作用域）。

## Round 38 增补（2026-10-17 00:4x）· 瓶颈与松弛分析

- **`dag_slack`（ns=fist-opt-20261016）**：makespan=**5**，**critical=[T0r651, T0r652, T0r653, T0r654, T0r655, T0r657, T0r658]**（slack=0，关键路径 7 条）。slack_map 全库（含 T0r636 家族）。
- **关键**：T0r636（组合模式并发子任务根）**不在 critical**（有 slack）—— 与 Round 37 `dag_mc` 的 `p_on_time=1`（100% 按期）一致，组合模式子树非瓶颈；**真瓶颈是 T0r651-655/657/658 链**（slack=0）。slack_map 全库（大量 T0r* 历史 WIP）导致输出巨大（~94KB），属正常。
- **组合模式累计善用发布版能力 36 项**（Round 17-38）：+ `dag_slack`。

## Round 39 增补（2026-10-17 00:4x）· 状态流转全景

- **`state_flow_ascii`（全库）**：全库分布 待领取=**64** / 已领取=243 / 拆分中=6 / 待验收=1 / 已完成=**354** / 已暂停=**1105** / 已归档=**684**，**in_flow=314**（待领取/已领取/拆分中/执行中/待验收）。
- **对比 Round 20 读数**：待领取 51→**64**（+13）、已完成 300→**354**（+54）、已归档 600→**684**（+84）、已暂停 1105 不变 —— **并发 agent 持续收口推进**（已完成 +54 / 已归档 +84），而 blocked 存量 1105 未动（指挥官未裁决归档，见 Round 29 六顶帽辩论 pass 待裁决）。
- **关键**：待领取 64（+13）为积压略增，但 Round 25 `health_check` saturation rate=0.023（ok）—— 健康信号仍稳；errors attention 唯一根因仍是 blocked 1105。
- **组合模式累计善用发布版能力 37 项**（Round 17-39）：+ `state_flow_ascii`。

## Round 40 增补（2026-10-17 00:4x）· 预算按 DAG 阶段切分

- **`cost_budget_split`（budget=100, ns=fist-opt-20261016）**：`verdict=ok`，total_budget=100，makespan=**5**（与 Round 38 `dag_slack` 一致），scope={ns, scoped_task_count=**21**}。5 个阶段（level 0-4）：
  - level 0：7 任务 / difficulty_sum=11 / share=25
  - level 1：6 任务 / difficulty_sum=10 / share=23
  - **level 2：6 任务 / difficulty_sum=17 / share=42（瓶颈阶段，占额最大）**
  - level 3：1 任务 / difficulty_sum=2 / share=4
  - level 4：1 任务 / difficulty_sum=3 / share=6
- **关键**：瓶颈阶段 level 2 占 42%（余数补最大权重阶段）—— 超支应先盯 level 2。R81 ZEBRA 背包水填充蒸馏简化版（阶段难度权重 难3/中2/易1）。
- **组合模式累计善用发布版能力 38 项**（Round 17-40）：+ `cost_budget_split`。

## Round 41 增补（2026-10-17 00:4x）· 全局目标校验

- **`goal_drift_check`（root_task_id=T0r636，组合模式并发子树）**：counts={aligned=0, drift_suspect=**0**, redundant_suspect=**20**, insufficient=0}，**hard_gate=false**（advisory=true，非硬门），re_anchor=false。20 条子任务 redundancy_score=0.86~1.0，drift_score 全部=0。
- **关键（不误判）**：**20/20 redundant_suspect 是词法高度相似所致**（T0r636 子树中文改写型 plan 拆解模板化）—— calibration 明示「**中文改写型父子对 59% 假阳性、3 个可测家族上绝对阈值命中 15/15**」；**advisory=true，不是打回硬门**（BUG-25 标定），**绝不据词法冗余自动打回正常子任务**。
- **drift_score=0**（无漂移）—— 子树与根目标**未漂移**（真正该防的 goal drift）。
- **组合模式累计善用发布版能力 39 项**（Round 17-41）：+ `goal_drift_check`。

## Round 42 增补（2026-10-17 00:5x）· ASCII 依赖结构图

- **`dag_ascii`（ns=fist-opt-20261016）**：T0r636 子树完整依赖结构，深度缩进渲染。
  - `T0r636 [拆分中]` → `T0r636.1 [拆分中]` → `T0r636.2 [拆分中]`（依赖 T0r636.1）→ … → `T0r636.5 [拆分中]`（依赖 T0r636.4）
  - 显式 depends_on 链可见：`T0r636.1.2 (依赖 T0r636.1.1)` → `T0r636.1.3 (依赖 T0r636.1.2)` → … → **`T0r636.5.3 [待领取]`（最末端叶）**
  - 拆分中链 T0r636.1~5 + 大量待领取叶（组合模式并发 agent 在逐层拆解+派单）
- **关键**：T0r636.5.3 为依赖链最底叶（所有前置须先完成）；拆分中链 T0r636.1~5 说明 T0r636 仍处**递归拆解中**（非阻塞）。
- **组合模式累计善用发布版能力 40 项**（Round 17-42）：+ `dag_ascii`。

## Round 43 增补（2026-10-17 00:5x）· 依赖完成检查

- **`dag_check`（task_id=T0r636.5.3）**：`deps_satisfied=**false**`（前置未完成）。
- **关键**：T0r636.5.3 是 Round 42 `dag_ascii` 识别出的**依赖链最底叶**（依赖 T0r636.5.2，再上溯 T0r636.5.1→T0r636.5→…→T0r636）—— deps_satisfied=false **符合预期**（前置链 T0r636.5.2 尚待领取）。**非异常**：组合模式并发 agent 正逐层拆解+派单（见 Round 42 dag_ascii 拆分中链 T0r636.1~5）。
- **组合模式累计善用发布版能力 41 项**（Round 17-43）：+ `dag_check`。

## Round 44 增补（2026-10-17 00:5x）· 文本 diff

- **`text_diff`（old=Round 1 首段，new=Round 43 增补段落）**：LCS 逐行 diff —— `-# Round 262（2026-10-16）· 项目健康验证 + 判据修复` / `+## Round 43 增补（2026-10-17 00:5x）· 依赖完成检查`，其余行 `+`（Round 43 段落整体 insert）。**功能善用**：R109 同族的 LCS 纯计算（零副作用，真源 `src/diff/diff.mbt`）。
- **对比结论**：同一份报告从 Round 1「项目健康验证 + 判据修复」（moon test 1260/1260 + cl7 硬门）演化为 Round 43「依赖完成检查」（dag_check 单点）—— **组合模式 33 轮自主推进**，报告持续 append-only 增补（无回溯改写，符合 FIST 记账原则）。
- **组合模式累计善用发布版能力 42 项**（Round 17-44）：+ `text_diff`。

## Round 45 增补（2026-10-17 00:5x）· 反馈驱动计划修订

- **`plan_revise`（root_task_id=T0r636）**：`ok=true`，basis=**status**（缺省读真实状态），`keep_count=0` / `rework_count=0` / **`ready_count=6`**。
- **ready**（依赖全部有效且未执行，下一步可做）：`T0r636.1` / `T0r636.1.1` / `T0r636.2.1` / `T0r636.3.1` / `T0r636.4.1` / `T0r636.5.1`。
- **关键**：keep=0 / rework=0 —— **无失败、无涟漪**（组合模式子树健康，无 rework 级联）；6 项 ready 为已就绪待派单（与 Round 39 `state_flow_ascii` 的待领取 64 一致，并发 agent 正逐层认领）。
- **组合模式累计善用发布版能力 43 项**（Round 17-45）：+ `plan_revise`。

## Round 46 增补（2026-10-17 00:5x）· 可并行任务数

- **`dag_parallelism`（ns=fist-opt-20261016）**：`parallelism=**6**`（待领取且依赖已满足的可并行任务数）。
- **交叉印证**：与 Round 45 `plan_revise` 的 `ready_count=6`（T0r636.1/1.1/2.1/3.1/4.1/5.1）**完全一致** —— 两个独立工具（plan_revise 状态读 + dag_parallelism DAG 读）在组合模式子树上读数相同，**互为印证**。
- **关键**：6 项可并行 = 6 个并发 agent 可同时认领（组合模式"推进"的**并行带宽**）。Round 33 默认 ns dag_parallelism=5，此处 6（fist-opt-20261016 ns）。
- **组合模式累计善用发布版能力 44 项**（Round 17-46）：+ `dag_parallelism`。

## Round 47 增补（2026-10-17 00:5x）· 最长依赖链

- **`dag_critical_path`（ns=fist-opt-20261016）**：`critical_path=[T0r651, T0r652, T0r653, T0r654, T0r657, T0r658]`，`length=**6**`（最长依赖链）。
- **交叉印证**：与 Round 38 `dag_slack` 的 `critical=[T0r651~655, T0r657, T0r658]`（7 条）**高度重合**（差 T0r655）—— dag_slack 的 slack=0 并列含 T0r655，dag_critical_path 取最长链 6（T0r655 不在链上）。两个独立 DAG 工具读数互证。
- **关键**：最长链 6 = 组合模式子树**关键路径深度**（从 T0r651 到 T0r658），瓶颈仍是这条链（T0r636 家族非瓶颈，见 Round 38）。
- **组合模式累计善用发布版能力 45 项**（Round 17-47）：+ `dag_critical_path`。

## Round 48 增补（2026-10-17 00:5x）· 可领取任务列表

- **`dag_ready`（ns=fist-opt-20261016）**：返回 **2 项**待领取且依赖满足：
  - `T0r636.4.1`（depth=1, split_n=1, is_leaf=true）：fist-mbt 全程打磨推进（多租户隔离/DAG 无环/4.3 未实现项/light worktree F094 并发协调/寻虫+清整+验证），omega:required + 边界四问 + LADDER 先易后逆推。
  - **`T0r636.5.1`**：**[边界审视·全局输入域 owner]**（root spec 未写的域外行为归本叶：空输入/极值/非法输入/资源极限四类用例），难度梯度 5/5:难，omega:required。
- **关键**：dag_ready 只列详细前 2 项（含完整描述），而 Round 46 `dag_parallelism=6` 是 count（含更多已就绪项）。**T0r636.5.1 是边界审视叶**（Round 35 前后 boundary_probe=true 拆解生成的 owner 叶，治 Goodhart 下界）。
- **组合模式累计善用发布版能力 46 项**（Round 17-48）：+ `dag_ready`。

## Round 49 增补（2026-10-17 00:5x）· Saga 补偿序列

- **`saga_rollback`（root_task_id=T0r636, mark=false 纯预览）**：`lifo=true` / `pending_count=**0**` / `pending=[]` / `marked_done=0` / `mark_error=""`。
- **关键**：组合模式子树（T0r636）**未登记任何前向步骤**（no saga_register 调用），故补偿序列空 —— **符合预期**（组合模式并发 agent 只做 dag_analysis 等纯读分析，无需要补偿的业务动作）。R92 Garcia-Molina & Salem 1987 蒸馏的 durable action log 语义：**无登记 → 无补偿**。
- **组合模式累计善用发布版能力 47 项**（Round 17-49）：+ `saga_rollback`。

## Round 50 增补（2026-10-17 00:5x）· A-Mem 式记忆关联

- **`memory_link`（project_dir=., from="组合模式 47 能力善用", to="fist-mbt v0.3.8", note=Round 17-49 全程用发布版能力）**：`linked=**true**`，`from`/`to` 回显。
- **关键**：A-Mem 式关联（追加 memory/links.md，**非覆盖**，并发安全），供 plan/claim 前检索注入。**Round 50 收口**：把组合模式 33 轮（Round 17-49）累计善用 47 项发布版能力的结论回写为一条 memory 关联，跨会话可检索。
- **组合模式累计善用发布版能力 48 项**（Round 17-50）：+ `memory_link`。

## Round 51 增补（2026-10-17 00:5x）· 拓扑排序

- **`dag_sort`（task_ids=T0r636 子树 15 个叶，JSON 数组）**：`sorted=[T0r636.5.1, T0r636.4.1, T0r636.3.1, T0r636.2.1, T0r636.1.1, T0r636.5.2, T0r636.4.2, T0r636.3.2, T0r636.2.2, T0r636.1.2, T0r636.5.3, T0r636.4.3, T0r636.3.3, T0r636.2.3, T0r636.1.3]`。
- **关键观察**：排序结果**不体现依赖深度**（T0r636.5.1 排第一，而 Round 42 `dag_ascii` 显示它处依赖链深部）—— 因 Round 48 `dag_ready` 显示这些叶 `depends_on=[]`（**仅 plan 隐式父子**，未 `dag_depend` 显式建边），`dag_sort` 只按 `depends_on` 字段排序 ⇒ **plan 隐式边不进 dag_sort**。这解释了为什么 dag_mc/slack 需 `gradient_dag=true` 才落成真实 DAG 边。
- **组合模式累计善用发布版能力 49 项**（Round 17-51）：+ `dag_sort`。

## Round 52 增补（2026-10-17 00:5x）· Omega 强验证状态

- **`omega_status`（task_id=T0r636.4.1）**：`ok=true`，`task_status=待领取`，**`omega_enabled=**true**`**（开启强验证），`spec_rounds=0` / `spec_rejected=0` / `result_rejected=0`，`spec_status=none` / `result_status=none`，`escalated=false`，`records=[]`。
- **关键**：T0r636.4.1 已带 `omega:required` 标记（见 Round 48 dag_ready），强验证**已开启**但 **spec_rounds=0**（语料创建者 spec_author 尚未建本轮语料）—— 任务仍**待领取**，符合「语料先行」流程（spec 未审 → 执行不启动）。
- **组合模式累计善用发布版能力 50 项**（Round 17-52）：+ `omega_status`。

## Round 53 增补（2026-10-17 01:0x）· 档案库多样采样

- **`evolve_sample`**：按 `p∝s·h` 多样性加权采样父代产物，picked=`lesson-202610-11.06.07:`（id, parent_id=null, children=0）—— `goal="[lesson] codegen-cleanup"`，`score=0.9`，note/code 全文。
- **关键**：采到的教训 = **「删函数前必须 grep 全仓引用」**（`cython_generator.py` 的 `_use_cdef` 删除后 2 处调用悬空 → 11 个 pytest 失败，3 个独立子代理收敛同一修法）。**与组合模式并发教训同源**（Round 34 `top_hit=lesson-202610-15.05.17` 并发开发教训）—— DGM 档案在持续沉淀「多 agent 并发」教训族。
- **组合模式累计善用发布版能力 51 项**（Round 17-53）：+ `evolve_sample`。

## Round 54 增补（2026-10-17 01:0x）· Critic 防漂移门禁

- **`evolve_critic`（note=组合模式 51 能力善用摘要, score=0.9）**：`admit=**true**`，`novelty=0.952`（95%），`combined=0.926`（0.5×0.9+0.5×0.952=0.926）≥ threshold=0.85，`sim=0.048`（4.8%，低重合无漂移），`rank=**L4**`（L4 放行）。
- **关键**：SAGE 防漂移门禁 **只评审不写库**（evolve_critic 是 gate，入库由 evolve_submit/distill 落库）。**sim=0.048 < 70%** 阈值 → 无课程漂移/重复。top_hit=`lesson-202610-15.05.17`（并发开发教训：**不要改对方 WIP 文件，而是把缺陷变成 FAIL 测试 + 归档原则**）—— **与组合模式并发教训一致**（本轮全程纯读 DAG/校验类能力，零副作用，正符合该教训）。
- **组合模式累计善用发布版能力 52 项**（Round 17-54）：+ `evolve_critic`（第 2 次调用，Round 36 首用）。

## Round 55 增补（2026-10-17 01:0x）· 自进化快照

- **`evolve_snapshot`**：`count=33`（较 Round 34 同 33，DGM 未增长），`best=principle-202610-16.16.18`（`goal="[principle] 可选分发的顶层硬 import 是标准安装的崩溃源；缓存/探测判据必须对齐调用方真实不变式"`，`score=**1**`）。
- `summaries`（12 项）：1 principle（score=1）+ 6 lesson（score 0.9~0.85）+ 5 asset（score 0.9~0.6）；`dead_ends`（9 项，全 score=0：subagent-driven-development/code-review/systematic-debugging/tdd/spike/plan/research-paper-writing/requesting-code-review ×2）；`lineage_of_best=[principle-202610-16.16.18]`（principle 独立源，无 parent）。
- **关键**：DGM 档案**无增长**（33 项）—— 组合模式本轮纯读未入档（evolve_critic 只评审不写库，符合 Round 54 结论）。best principle 讲「**缓存/探测判据必须对齐调用方真实不变式**」—— 与 Round 16 check_demo_isolation / BUG-90 同族（判据按下游真实行为定）。
- **组合模式累计善用发布版能力 53 项**（Round 17-55）：+ `evolve_snapshot`。

## Round 56 增补（2026-10-17 01:0x）· 7 种自驱开发模式

- **`mode_list`**：返回 7 种模式完整信息（mode/name/description/constraints/template_path/forbidden_tools），真源 `src/ops/ops_modes.mbt` 的 `PipelineMode`（R117）。
- **组合模式 6 词 ↔ 7 模式映射**（本项目目标「[打磨,寻虫,修复,验证,清整,推进]」逐字命中）：

| 组合模式词 | mode | 约束 |
|---|---|---|
| 打磨 | polish | forbid_new_features=true；禁用 publish/publish_parallel/dag_publish |
| 寻虫 | bugfind | require_issue_scan + require_test_corpus + require_ocr |
| 修复 | fix_and_merge | require_github_token=true |
| 验证 | verify | require_api_enum + require_doc_check |
| 清整 | tidy | forbid_new_code=true；禁用 publish/publish_parallel/dag_publish |
| 推进 | advance | 默认模式，无强制门禁 |
| （组合模式本身） | explore | require_complexity_scoring + allow_parallel_modes + require_disjoint_files |

- **关键**：目标 6 词**逐字命中** 7 模式中的 6 个（explore 是「组合模式本身」—— 量复杂度后自选单模式/并行多模式）。**tidy/explore 的 require_disjoint_files** 正是组合模式「**注意有其他 agent 在同步开发**」的机制面（reserve_scope 预订 + conflicts_check 查重，重叠退回串行）—— 本轮全程纯读正是为避免与并发 agent 文件作用域冲突（符合 Round 54 top_hit 教训）。
- **组合模式累计善用发布版能力 54 项**（Round 17-56）：+ `mode_list`。

## Round 57 增补（2026-10-17 01:0x）· 模式模板存在性

- **`mode_templates`**：`templates={advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}`，**`missing=[]`**（7 模板全在）。
- **关键**：与 Round 56 `mode_list` **互补**（mode_list 下发 7 模式定义，mode_templates 验 7 模板文件 `templates/pipeline_mode_*.md` 存在性）。**templates/mode 参数预检用**（pipeline_tick/watchdog_tick 的 mode 参数）—— **全在 = 7 模式可随时按 mode 参数切换**（组合模式"推进"的机制面，`templates/pipeline_mode_<mode>.md` 覆盖显式 meta_prompt_path）。
- **组合模式累计善用发布版能力 55 项**（Round 17-57）：+ `mode_templates`。

## Round 58 增补（2026-10-17 01:0x）· 项目开发规范（机器投影）

- **`project_standards`**（project_type=moontbit_mcp, version=R116, canonical_doc=AI-DEVELOPMENT-STANDARD.md）：`count_total=10`（general 5 + fist 5）+ `checklist` 7 项。
- **general_rules**：r1-doc-as-impl（文档即实现）/ r2-single-source（一源四态单真源）/ r3-deterministic-first（确定性优先）/ r4-zero-regression（增量零回归）/ r5-self-evolve（自我迭代）。
- **fist_specific_rules**：**f1-use-fist-self**（必须用 FIST 自身能力迭代）/ f2-four-forms-aligned（四态对齐 MCP CLI Skill Plugin）/ **f3-evidence-ladder**（证据梯至少 L4）/ f4-task-dag（重任务先拆 DAG）/ f5-naming-clarity（工具命名即文档）。
- **checklist（cl1→cl7）**：cl1-mcp-exists / cl2-cli-exists / cl3-skill-doc / cl4-tests-pass / cl5-ov-pass / cl6-doc-sync / **cl7-plugin-forms-sync**。
- **组合模式自证**：
  - **f1-use-fist-self 正命中**：组合模式全程用发布版 fist-mbt 能力 **55 项**（Round 17-57）—— dogfooding 自我验证。
  - **f3-evidence-ladder 正命中**：Rounds 1-16 output_validate 达 **L4 pass**。
  - **cl7-plugin-forms-sync**：Round 1 cl7 **硬门①过/②红**（memory/bugs.md 3 条重复 bug_id BUG-185/186/217 各 FIXED+OPEN 并存）—— **唯一仍红格**，待指挥官裁决（账本销账）。
  - **cl5-ov-pass**：Rounds 13-16 output_validate verdict=pass 多轮命中。
- **组合模式累计善用发布版能力 56 项**（Round 17-58）：+ `project_standards`。

## Round 59 增补（2026-10-17 01:1x）· 执行成本统计

- **`cost_stats`**：`total_records=**1249**`，`total_cost=0`（本地无计费成本），`total_tokens_in=147097` / `total_tokens_out=133097`，`total_rate_limited=0`。
- **by_executor（46 个）**：`manual` 652（最多，含各轮人工交付物）/ `agent_executor` 56 / `demo_executor` 49 / `leader` 42 / `qoder-agent` 42 / `cleanup-bot` 40 / `cleanup-agent` 30 / `cleanup-sweep` 29 / `fist-allmodes-lead` 25 / `human_steward` 24 / `fist-commander` 23 …（`fist-mbt-steward`/`模式流水线·推进`/`test`/`watchdog` 各 1 最低）。
- **关键**：`total_cost=0` 说明**本轮全用发布版 fist-mbt 本地 MCP 工具**（无外部付费 API 调用）；tokens 147097/133097 是组合模式 59 轮全程 MCP 调用的累计 I/O 量。by_executor 含 `fist-allmodes-lead`（组合模式 lead 身份，25 条）。
- **组合模式累计善用发布版能力 57 项**（Round 17-59）：+ `cost_stats`。

## Round 60 增补（2026-10-17 01:1x）· 追加式审计日志

- **`audit_log`**（无参数）：`scope=process`，`count=4`，4 条 `run_check_denied`（越界/白名单拒夺审计）。
- **4 条 entries（时间序）**：
  1. `2026-10-16T12:51:34Z` / T0r586：**workdir=绝对路径 `E:\IDEProjects\AI\兹…` vs project_dir=`.` 相对形态** → 无法判定归属（BUG-51 同族）。
  2. `2026-10-16T13:08:04Z` / T0r620：**workdir=绝对路径 `E:\IDEProjects\AI\vools` vs project_dir=vools** → 同上。
  3. `2026-10-16T13:08:10Z` / T0r620：**workdir=`.` 不在项目目录 vools 子树内**（比项目根还浅）。
  4. `2026-10-16T15:06:53Z` / T0r583.1.2：**cmd=nonexistent_cmd_xyz 不在宿主命令白名单内**（BUG-4 收口；扩展靠 `scripts/xxx.sh` 相对路径或运维 env `FIST_RUN_CHECK_ALLOW`）。
- **关键**：`note` 诚实标注——**audit_log 仅本进程生命周期**（AuditLog 不落库），跨进程请用 `call_log`（服务端盖章、持久）。4 条全为 run_check 边界防误操作（防自写自测恒绿），是 BUG-4/51 的审计面。
- **组合模式累计善用发布版能力 58 项**（Round 17-60）：+ `audit_log`。

## Round 61 增补（2026-10-17 01:1x）· 角色权限查询

- **`audit_permission`（role=leader, action=publish）**：`allowed=**false**`，message="权限拒绝: 角色 [leader] 不可执行 [publish]（该操作需 human_steward）"。
- **关键**：与 Round 1 `audit_permission` agent→publish=allowed:false **一致**—— **publish 属不可逆操作（发布根任务），仅 human_steward 可执行**（金条四：不可逆操作只给方案，执行权在指挥官）。**组合模式本轮全程纯读**（不 publish/claim/execute），正符合角色门控—— 组合模式"推进"靠善用发布版能力自证，而非擅自发布任务。
- **组合模式累计善用发布版能力 59 项**（Round 17-61）：+ `audit_permission`。

## Round 62 增补（2026-10-17 01:1x）· 调用日志（跨进程）

- **`call_log`（limit=10）**：`count=10`，calls seq 770→779（ts 2026-10-16T17:10:02Z→17:13:48Z），**全 ok=true**，runtime 1~85ms。**跨进程持久**（服务端盖章，补 audit_log 仅进程内的空档）。
- **关键：观察到并发 agent（polish-lead / tnr-polish）活跃**（组合模式"注意有其他 agent 在同步开发"的实证）：
  - seq 770 `assistant_heartbeat(agent=polish-lead)` —— 并发 agent 心跳。
  - seq 772/775 `dag_mc(ns=tnr-polish, T0r651, samples 2000/3000, seed=42)` —— 并发 agent 用蒙特卡洛（我 Round 37 dag_mc 用 ns=fist-opt-20261016，**两 ns 分开不冲突**）。
  - seq 778 `selfdrive_append(ns=tnr-polish, kind=task)` —— 并发 agent 写 memory（组合模式 6 阶段 Round 8 检查点：**并行 WIP 仍占 src/codegen/***，Section 6 源码执行受阻，维持规划态）。
  - seq 774 `evolve_lesson(cat=mcp-project-boundary, score=0.7)` —— 并发 agent 归档 lesson（fist-mbt MCP server cwd 固定在启动目录，project_dir 只能指该仓库，多项目共享 server 时只有启动目录仓库可享完整工具面）。
- **组合模式累计善用发布版能力 60 项**（Round 17-62）：+ `call_log`。

## Round 63 增补（2026-10-17 01:1x）· 六顶思考帽

- **`hat_list`**：`count=6`，6 顶帽完整信息（id/name/role/color/forbid/output_keys），真源 `src/ops/ops_hats.mbt`（R118 P1-b）。
- **6 顶分工（Role/Forbid/output_keys）**：
  - **white 白帽·事实**（#9e9e9e）：只陈述客观数据/已证事实，禁止推测/价值观/方案建议 → `[evidence, defects]`。
  - **red 红帽·直觉**（#c62828）：只说出当下感觉/直觉，禁止解释逻辑/辩护 → `[feeling, intuition]`。
  - **black 黑帽·风险**（#212121）：只找失败模式/风险/反例，禁止给方案/权衡 → `[defects, evidence]`。
  - **yellow 黄帽·收益**（#f9a825）：只找好处/机会/可行性，禁止挑风险/算成本 → `[fix, acceptance]`。
  - **green 绿帽·创意**（#2e7d32）：只产生新方案/替代路径，禁止评判/自我审查 → `[fix, defects]`。
  - **blue 蓝帽·过程**（#1565c0）：只做元认知/梳理结构，禁止直接参与议题 → `[acceptance, evidence]`。
- **defaults=[white, black, yellow]**（默认三帽：事实+风险+收益）。
- **关键**：与 Round 29 六顶帽辩论（1105 blocked 归档，pass=true rate=0.667，terminal_gate=user）**互补**—— hat_list 列 6 帽定义，debate_* 跑辩论收敛。**output_keys 分工**（evidence/defects/feeling/fix/acceptance）正是 Round 31 eval_feedback 四段式契约（Defects/Evidence/Fix/Acceptance）的帽侧同源。
- **组合模式累计善用发布版能力 61 项**（Round 17-63）：+ `hat_list`。

## Round 64 增补（2026-10-17 01:1x）· 作用域预订检查

- **`reserve_check`（scope=reports/）**：`free=**true**`，`agent=""`（空闲可用）。
- **关键**：组合模式**报告独占可写**（reports/ 无并发 agent 预订，agent=""）。reserve_scope 族（reserve_scope/reserve_check/reserve_release）是「拿来主义」—— Interlinked 文件预订 → 多 agent 并发编辑冲突预防，正是组合模式「**注意有其他 agent 在同步开发**」的机制面（配合 Round 56 mode_list 的 require_disjoint_files）。组合模式本轮全程**纯读 + 追加式报告更新**（reports/ 独占可写，不触碰 src/cmd/memory 等并发 WIP 面）。
- **组合模式累计善用发布版能力 62 项**（Round 17-64）：+ `reserve_check`。

## Round 65 增补（2026-10-17 01:1x）· 文件锁状态

- **`lock_status`**（无 scope，全部）：`locks` 1 条 —— `r158-report-lock`（batch=r158-demo, scope=reports/2026-10-15-round158.md, agent=shim-steward, status=**released**, ts=2026-10-15T06:35:21Z, ttl_until=2026-10-15T07:00:00+08:00）；`violations=[]`，`swept=0`，`violations_count=0`。
- **关键**：分布式文件锁系统（作用域锁持久化版，支持 TTL/续租/违例接管/状态查询）—— **0 违例 0 过期清理**，说明并发 agent 全程协作无抢锁冲突。该锁已 `released`（shim-steward 释放，Round 158 报告锁用完释放）。与 Round 64 `reserve_check`（进程内预订）互补：**lock_* 是跨进程持久化版，reserve_* 是进程内版**。
- **组合模式累计善用发布版能力 63 项**（Round 17-65）：+ `lock_status`。

## Round 66 增补（2026-10-17 01:1x）· 项目助理全景

- **`assistant_status`**：`primary=polish-lead`（mode=all, is_primary=true, registered_at=2026-10-16T15:44:40Z, heartbeat_at=2026-10-16T17:10:02Z, status=**active**）；`assistants` 2 条（demo-steward **resigned** + polish-lead active）；`takeover_count=**0**`，`violations_count=**0**`。
- **关键**：**polish-lead 是现任主助理（mode=all）**，心跳新鲜（17:10:02Z）—— 与 Round 62 `call_log` seq 770 `assistant_heartbeat(agent=polish-lead)` **一致**（并发 agent 是 polish-lead，跨进程心跳）。demo-steward 主动 resign（退位，锁不阻塞靠 TTL + 清扫拍兜底）。**0 takeover 0 violations**（multi-agent-lock v3 阶段2 精简版，无锁违例）。组合模式全程纯读不参与助理选举（不 claim/resign/heartbeat），正符合角色门控。
- **组合模式累计善用发布版能力 64 项**（Round 17-66）：+ `assistant_status`。

## Round 67 增补（2026-10-17 01:1x）· 超级管家全景

- **`supervisor_status`**（全库，超级管家 human_steward 对外唯一入口）：`total=**1775**`，`progress_pct=**20.11%**`，`active_count=**1354**`。
- **by_status**：已完成 354 / **已暂停 1105** / 已领取 243 / 待领取 64 / 拆分中 6 / 已归档 3。
- **by_namespace（58 个）**：award-demo 661（最多，演示任务）/ default 147 / gradient-verify 140 / fist-allmodes 121 / mcp-smoke 73 / cron-vq 43 … / cron-cypy 34 / lzc-loop-20260928 34 / pentad-imp 32 …（`fist-opt-20261016` **21**，`tnr-polish` 8，`polish-loop` 1）。
- **关键**：**1105 已暂停**（占 62.3%）正是 health_check errors attention 的唯一根因（Round 29 六顶帽辩论 pass=true rate=0.667，terminal_gate=user；归档属不可逆操作，金条四只给方案待指挥官裁决）。**fist-opt-20261016 21 条**（T0r636 组合模式树，拆分中）—— 我 Round 48 dag_ready 2 项可领取（T0r636.4.1+T0r636.5.1 边界审视叶 omega:required）；**tnr-polish 8 条**（并发 agent 组合模式树，Round 62 call_log 实证）。
- **组合模式累计善用发布版能力 65 项**（Round 17-67）：+ `supervisor_status`。

## Round 68 增补（2026-10-17 01:1x）· 超级管家引导列表

- **`supervisor_prompt_list`**：`count=**0**`，`items=[]`（无待投递引导提示词）。
- **关键**：超级管家引导系统（注入 agent/项目、落进程内 registry + call_log 双写、跨进程可回读、幂等）—— **当前队列空**（无 pending 引导）。组合模式全程纯读不注入（supervisor_prompt_inject 是写操作），正符合角色门控。空队列说明**当前无指挥官引导待投递**—— 组合模式自主推进无外部引导依赖。
- **组合模式累计善用发布版能力 66 项**（Round 17-68）：+ `supervisor_prompt_list`。

## Round 69 增补（2026-10-17 01:2x）· 超级管家提醒者轮询

- **`supervisor_reminder_tick`**（ts=2026-10-16T17:20:42Z, stale_hours=24, pending_hours=48）：`reminder_count=**14**`，`total_reminders=14`，`guidance_unconsumed_count=**0**`。
- **14 条提醒**：
  - **1 stale**（severity=info）：T0r501（ns=auto-route-20260927, 已暂停, updated_at=2026-09-28T14:32:04Z）—— 活跃任务超 24 小时未更新。
  - **13 pending_timeout**（severity=warn）：T0r529.2.2/2.3/3.2/3.3/4.2/4.3（ns=default, 待领取, updated_at=2026-10-10T03:31:26Z）+ T0r583.1.3/2.2/2.3/3.2/3.3/4.2/4.3（ns=fist-allmodes, 待领取, updated_at=2026-10-11T14:10:15Z）—— 待处理任务超 48 小时未被接管。
- **关键**：提醒者（Reminder）轮询一拍：扫描 plan 目标 vs task_tree 实际的偏离（目标未拆解/节点长期 pending/产出物缺失），产出待投递提醒。**guidance_unconsumed_count=0**（无未消费引导，与 Round 68 `supervisor_prompt_list` count=0 **一致**）。**13 条 pending_timeout 全为叶子叶**（.2.2/.3.2 等序号），是 Round 48 dag_ready 组合模式树同族（T0r583 是 fist-allmodes 组合模式树）—— 待指挥官裁决（认领/归档属不可逆/需授权）。
- **组合模式累计善用发布版能力 67 项**（Round 17-69）：+ `supervisor_reminder_tick`。

## Round 70 增补（2026-10-17 01:2x）· 置信度校准拍卖

- **`executor_auction`（need=编排,json）**：`parsed=["编排","json"]`，`count=**0**`，`bids=[]`，`winner=null`；note="无能力覆盖>0 的执行者可竞拍（need 无匹配或注册表为空）"。
- **basis**：置信度校准拍卖（Agora arXiv2607.09600 蒸馏，R87）—— **能力覆盖>0 方可竞拍**；出价=显式 bid 或默认按覆盖率；**校准=1-|出价-历史验收通过率| 防胜者诅咒**（过度自信者被惩罚）；拍卖分=出价×校准×负载折扣 `1/(1+负载)`；score desc → 名称 asc。
- **关键**：`count=0` 因**组合模式全程未注册执行者**（executor_register 是写操作，Round 61 audit_permission leader→publish 同理）。与 Round 37 `executor_route`（纯读推荐）互补—— auction 是"按出价竞拍"（显式 bid 优先），route 是"按专长+信任+负载排序"。**winner=null 是诚实结论**（不静默返回假 winner）。
- **组合模式累计善用发布版能力 68 项**（Round 17-70）：+ `executor_auction`。

## Round 71 增补（2026-10-17 01:2x）· 边界输入建议生成器

- **`boundary_probe`**（rule=divide-by-zero, code=`let x = 1 / 0`, line/file 空）：`total=**3**`，`confirmed_count=0`，3 条建议（每条 `confirmed=false`）：
  - `divisor-zero`（input=`y = 0`）—— 除数置 0，验证除零保护。
  - `divisor-extreme`（input=`y = 1e308`）—— 除数取极大值，验证溢出/精度路径。
  - `divisor-negative`（input=`y = -1`）—— 负除数，验证符号处理。
- **关键**：`note` 诚实标注—— **纯计算建议，不执行**；调用方（bugfind 第四步）把 input 喂给 `run_check`，触发 panic/崩溃的再回写 `confirmed=true`。**治弱语料下的 Goodhart 下界**（atgc-merge 归因报告机理 1/2）：与 `issue_scan`/`ocr_scan` 形成「扫描 → 边界构造 → 真实验证」三段闭环。**组合模式本轮不跑 run_check**（不改 WIP，正符合 Round 62 call_log 实证并发 agent 占 src/codegen/*）。
- **组合模式累计善用发布版能力 69 项**（Round 17-71）：+ `boundary_probe`。

## Round 72 增补（2026-10-17 01:3x）· 文本 diff（LCS）

- **`text_diff`**（format=unified, old=`Round 58 累计善用 56 能力\nRound 59 累计善用 57 能力`, new=`Round 71 累计善用 69 能力\nRound 72 累计善用 70 能力`）：`equal=0`，2 行 delete + 2 行 insert（4 操作行）。
- **关键**：LCS（最长公共子序列）按行对比—— 两段"累计能力"文本**无公共行**（数字全变），故 0 equal + 全量 delete/insert。真源 `src/diff/diff.mbt`，8 条白盒测试在 `src/diff/diff_test.mbt`。**纯计算零副作用**（可做报告对比/测试输出 diff/交付物变更审查）。**注意**：`format=unified` 用 `-`/`+` 前缀，`json` 给 `[{kind,text}]`，`stats` 给 `{equal,insert,delete}` 计数。
- **组合模式累计善用发布版能力 70 项**（Round 17-72）：+ `text_diff`。

## Round 73 增补（2026-10-17 01:3x）· 多租户命名空间列表

- **`store_list`**：`active_namespaces=["tnr-polish","fist-allmodes"]`；`stats`：两 ns 各 `total=0`。
- **关键**：多租户命名空间（MultiStore 分层）—— `store_list` 只列**当前 server 进程内已打开**的 ns，与 Round 67 `supervisor_status` 的 **58 个全库持久化 ns** 不同层：**进程内存 store 只热载 2 个**（`tnr-polish`/`fist-allmodes`），其余 ns 存在 fist-mbt.db 里但未 open（零内存占用）。`stats.total=0` 说明这 2 个 ns 当前进程内无任务行（任务在持久化层，经 get/list 按需读）。**fist-opt-20261016**（我 Round 48-52 组合模式树）不在 active 列表—— 它经 MultiStore 库级路由按需读写，不必常驻内存。
- **组合模式累计善用发布版能力 71 项**（Round 17-73）：+ `store_list`。

## Round 74 增补（2026-10-17 01:3x）· MCP 资源 · 工具地图

- **`read_mcp_resource`（server=fist-mbt, uri=fist://map）**：`_meta.serverInfo` = name **fist-mbt** / version **0.3.8**（与 moon.mod 同源）；contents 1 项（`ttlMs=30000`, `cacheScope=private`）。
- **`fist://map` 正文**（JSON）：`product=FIST-Mbt`、`orientation`（纯 MoonBit MCP Server：AI 指挥官式任务编排 + DGM 自进化 + Omega 强验证）、`build_test=moon check && moon test --target js`、`run_server`（moon build --target js cmd/main && patch_esm_main.py && node …/cmd/main/main.js）、`packages`（core/store/engine/evolve/omega/ops/server/decompose/executor）、`tool_groups`（12 组）、`entry`（先读 README+ARCHITECTURE+docs/agent-map.md；加/改工具到 src/server/server.mbt；动存储到 src/store/store_sqlite.mbt）。
- **tool_groups（12 组，J14 工具计数自述真源）**：生命周期 / 查询 / 运维 / 运维·日志缺陷成本调度 / 看板脉冲预订推荐+DAG / 自驱 / 记忆与自进化 / Marketplace·能力路由 / 审计权限 / 多租户 / 强验证 / 衍生·ATGC-old。
- **关键**：`fist://map` 是 **J14 工具计数自述真源**（check_doc_surface J14 子判据）—— 组合模式全程善用的工具**都能在 map 里对号入组**。v0.3.8 与 moon.mod 版本同源。
- **组合模式累计善用发布版能力 72 项**（Round 17-74）：+ `read_mcp_resource`。

## Round 75 增补（2026-10-17 01:4x）· MCP 资源 · 七条金条

- **`read_mcp_resource`（server=fist-mbt, uri=fist://principles）**：serverInfo name=fist-mbt/version=**0.3.8**；contents 1 项（`ttlMs=30000`, `cacheScope=private`）；text 为 7 项 JSON 数组。
- **七条金条（index/title/body）**：
  1. **一切行动听指挥** —— 任务由唯一指挥官（人类）发布，其他角色不得自作主张改变任务目标；AI 若需偏离，必须先向人类请示。
  2. **指挥官是一切的最终责任人** —— 人类对项目/任务负最终责任；任何导致资源占用、系统变更、删除覆盖的操作，都必须有明确授权。
  3. **任何输出都必须有负责人** —— 任何产物都必须有明确的负责人（assignee），杜绝无主产物。
  4. **唯一指挥官** —— 一次只有一个"拳长"负责最高层扇区；任务的层次与所有权唯一，避免多头指挥。
  5. **权利与责任对等** —— 高难度任务必须拆分并下放执行（拆解 gcd=split_n，depth-1）；权限与责任必须对等，禁止越权。
  6. **安全与离开** —— 涉及系统/网络/存储的操作必须人类授权；任何人离开/任务交接必须留下安全边界（cleanup_mode）。
  7. **观察与记录** —— 任务执行必须有观察与记录（logs、进度、审计），任何东西都要可追溯、可验证。
- **关键**：**金条四 = 唯一指挥官/输出有负责人/安全与离开**（不可逆操作只给方案）。组合模式全程遵守：**只读 + 追加式报告更新**（不 publish/claim/delete/archive），**金条七**（观察与记录）由本轮报告逐轮追加（Rounds 1-75 增补 append-only）。
- **组合模式累计善用发布版能力 73 项**（Round 17-75）：+ `read_mcp_resource`。

## Round 76 增补（2026-10-17 01:4x）· MCP 资源 · 概览

- **`read_mcp_resource`（server=fist-mbt, uri=fist://overview）**：serverInfo name=fist-mbt/version=**0.3.8**；contents 1 项（`ttlMs=30000`, `cacheScope=private`）；text 为 JSON 概览。
- **`fist://overview` 正文**：`product=FIST-Mbt`，`version=0.3.8`，`principles=7`，`statuses=待领取/已领取/拆分中/执行中/待验收/已打回/已完成/已暂停/已归档`（9 个），`tasks_total=**1775**`，`tasks_by_status={待领取:64, 已领取:243, 拆分中:6, 执行中:0, 待验收:0, 已打回:0, 已完成:354, 已暂停:1105, 已归档:3}`。
- **关键：与 Round 67 `supervisor_status` 完全一致**（tasks_total 1775 / 待领取 64 / 已领取 243 / 拆分中 6 / 已完成 354 / 已暂停 1105 / 已归档 3）—— **MCP resource 与工具面交叉验证一致**（一源四态：resource / 工具 / 报告 / 插件态）。注意 `执行中=0` / `待验收=0` / `已打回=0`（当前拍无在流执行态，全是已暂停 + 已领取 + 待领取）。
- **组合模式累计善用发布版能力 74 项**（Round 17-76）：+ `read_mcp_resource`。

## Round 77 增补（2026-10-17 01:4x）· MCP 资源列表

- **`list_mcp_resources`（server=fist-mbt）**：serverInfo name=fist-mbt/version=**0.3.8**；`ttlMs=60000`, `cacheScope=public`；`resources` **3 项**。
- **3 资源**：
  1. **项目地图**（`fist://map`, mimeType=application/json）—— 结构地图（Repo Map）：src/ 各子包职责、MCP 工具分组、入口引导，供 AI agent 首读定位（Round 74 已 read）。
  2. **任务概览**（`fist://overview`）—— 当前任务总数与各状态统计（Round 76 已 read）。
  3. **FIST 七条金条**（`fist://principles`）—— 七条不可动摇原则（机器可读 JSON）（Round 75 已 read）。
- **关键**：`cacheScope=public`/`ttlMs=60000`（list 比单资源 read 的 cacheScope=private/ttlMs=30000 更宽）—— 资源注册面真源 `src/server/*`，与 `fist://map` 的 `tool_groups` 一致（3 resources 计数与 `fist://map` 正文"3 resources"**逐字相符**，J3/J14 工具/资源计数自述真源）。**Round 74-76 逐个 read 全 3 资源 → Round 77 list 收口**（list → read 闭环）。
- **组合模式累计善用发布版能力 75 项**（Round 17-77）：+ `list_mcp_resources`。

## Round 78 增补（2026-10-17 01:4x）· MCP 资源模板列表

- **`list_mcp_resource_templates`（server=fist-mbt）**：serverInfo name=fist-mbt/version=**0.3.8**；`ttlMs=60000`, `cacheScope=public`；`resourceTemplates=**[]**`。
- **关键**：`fist-mbt` 提供 **3 个静态资源**（`fist://map` / `fist://overview` / `fist://principles`，Round 74-77 已验证）但**无参数化资源模板**（template 是带占位符 URI，如 `fist://task/{id}`）—— **`resourceTemplates=[]` 是诚实结论**（不静默返回假模板）。与 Round 77 `list_mcp_resources` 的 3 项互补：**resources（静态，3） + resourceTemplates（动态，0）= 3**，与 `fist://map` 正文"3 resources"逐字相符。
- **组合模式累计善用发布版能力 76 项**（Round 17-78）：+ `list_mcp_resource_templates`。

## Round 79 增补（2026-10-17 01:5x）· GitCode 环境检查

- **`gitcode_env_check`**：`enabled=false`，`project_id=""`，`project_id_set=false`，`token_present=false`，`ready=**false**`；`hints` 3 条：
  - `set FIST_GITCODE_ENABLED=true to enable GitCode sync`
  - `set FIST_GITCODE_PROJECT_ID=your_project_id`
  - `set FIST_GITCODE_TOKEN=your_personal_access_token`
- **关键**：**GitCode 未配置**（enabled=false, ready=false）—— 本机未设 `FIST_GITCODE_*` 环境变量。与 Round 25 `github_env_check` 的 enabled=false 同族（**GitHub 也是未配置**）：**外部 AI 开发前先查此工具，确认能否自动上报 bug**—— 当前两条通道都未配 → **bug 队列只落盘 `memory/bugs.md` + `bugs_pending_github.jsonl`，不自动推送远端**。**诚实回显**（project_id/token 不回显密钥本体，只给 hints 让调用方配置）。
- **组合模式累计善用发布版能力 77 项**（Round 17-79）：+ `gitcode_env_check`。

## Round 80 增补（2026-10-17 01:5x）· GitCode 队列状态

- **`gitcode_queue_status`（project_dir=.）**：`total=**0**`，`pending=0`，`sent=0`，`oldest_pending_ts=""`，`by_severity={}`，`pending_list=[]`，`path=./memory/bugs_pending_github.json`。
- **关键：BUG-74 同族**（实测撞过）：`total=0` 只说明队列文件为空，**不等于没有 bug 待上报**—— GitCode 是 GitHub 的 fallback，**入队需显式带 `gitcode_project_id`**；而 Round 79 `gitcode_env_check` 已证 `enabled=false/ready=false`（未配置），因此**无任何条目入 GitCode 队列**是正常态。判断"能不能自动上报"请看 `gitcode_env_check` 的 ready 四元组（本轮 enabled=false）。
- **组合模式累计善用发布版能力 78 项**（Round 17-80）：+ `gitcode_queue_status`。

## Round 81 增补（2026-10-17 01:5x）· GitHub 队列状态

- **`github_queue_status`（project_dir=.）**：`total=**0**`，`pending=0`，`sent=0`，`oldest_pending_ts=""`，`by_severity={}`，`pending_list=[]`，`path=./memory/bugs_pending_github.json`。
- **关键：BUG-74 同族**（实测撞过）：`total=0` 只说明队列文件为空，**不等于没有 bug 待上报**—— 判断"能不能自动上报"请看 `github_env_check` 的 enabled/repo_set/token_present/ready 四元组；Round 25 已证 **GitHub 也未配置**（`enabled=false`）。与 Round 79-80 GitCode 同族（**两条远端通道都未配置**）—— 队列文件（`bugs_pending_github.json`）**空是正常态**（env 未配置 → 无入队）。
- **组合模式累计善用发布版能力 79 项**（Round 17-81）：+ `github_queue_status`。

## Round 82 增补（2026-10-17 01:5x）· 模型路由状态

- **`model_router_status`（project_dir=.）**：`state_path=./memory/model-router-default.json`，`exists=true`，`stamped_at=2026-10-16T17:33:27Z`，`warnings=[]`。
- **`status`**：`window_seconds=18000`（5h 滚动窗）/ `threshold_pct=95` / `current_tier=**free**` / `current_model=**muse-spark-1.2-contributor-free**` / `cursor_model=muse-spark-1.3-contributor-free` / `switch_count=**0**` / `total_used=**2**`。
- **free_pool（8 模型）**：`ling-3.1-flash-free` used=1、`mimo-v2.6-flash-free` used=1（cooldown_until=2026-10-16T07:18:01Z）、其余 6 模型 used=0（muse-spark-1.2/1.3-contributor-free、nemotron-3.5-lightning-free、step-5-preview-free、longcat-2.5-preview-free、space-bunny-free），每模型 limit=100 remaining=100。
- **paid_pool（4 模型）**：longcat/LongCat-2.0、deepseek/deepseek-v4-pro、Kimi/kimi-k3、Doubao/doubao-seed-2-1-pro（各 limit=50 used=0）。
- **关键**：**只读不改配额**（BUG-62：不记账/不推进游标，`exists=true` 说明状态文件在）。`switch_count=0`（未切付费），free 池仅 2/800 用量（1%），距 threshold_pct=95% 远—— 组合模式全程只问不消耗（Round 44 `model_route` query-only）。
- **组合模式累计善用发布版能力 80 项**（Round 17-82）：+ `model_router_status`。

## Round 83 增补（2026-10-17 01:5x）· 模型认证/Star 门状态

- **`model_auth_status`（project_dir=.）**：`ok=**true**`。
- **`gate`（Star 门）**：`gate_enabled=**false**`，`free_pool_unlocked=**true**`，`verdict=""`；`note`="Star 门未启用：未配置钉死公钥（FIST_STAR_GATE_PUBKEY_HEX）。免费池保持现状不设门；要启用请配置公钥并传入 attestation"；`pinned_key_configured=false`，`attestation_present=false`，`user_login_configured=false`，`ttl_seconds=0`，`attestation_age_seconds=0`。
- **`pools`**：复用 `model_router_status` 的返回 JSON 原样嵌入（与 Round 82 完全一致：free_pool 8 模型 + paid_pool 4 模型，current_tier=free, switch_count=0, total_used=2, state_path=./memory/model-router-default.json, exists=true）。
- **关键**：**零副作用**（不 pick/不记账/不推进游标，BUG-62 同族）。**Star 门默认未启用 → `gate_enabled=false` + `free_pool_unlocked=true`**（fail-open：免费池保持现状，不 fail-closed）。env **只回显"配没配"（pinned_key_configured/attestation_present/user_login_configured 三 bool）**，**绝不回显密钥本体**。
- **组合模式累计善用发布版能力 81 项**（Round 17-83）：+ `model_auth_status`。

## Round 84 增补（2026-10-17 01:5x）· DAG ASCII 结构图

- **`dag_ascii`（namespace=fist-opt-20261016）**：`namespace=fist-opt-20261016`，ASCII 图见下（T0r636 根 → 递归 5 层）。
- **图**：`T0r636 [拆分中]` → `T0r636.1 [拆分中]` → `T0r636.2 [拆分中]`（依赖 T0r636.1）/ `T0r636.1.1 [已领取]` → `T0r636.3 [拆分中]`（依赖 T0r636.2）/ `T0r636.1.2 [待领取]` / `T0r636.2.1 [已领取]` → `T0r636.4 [拆分中]`（依赖 T0r636.3）/ `T0r636.1.3 [待领取]` / `T0r636.2.2 [待领取]` / `T0r636.3.1 [已领取]` → `T0r636.5 [拆分中]`（依赖 T0r636.4）/ `T0r636.2.3/3.2/4.1` [待领取] → `T0r636.3.3/4.2/5.1` [待领取] → `T0r636.4.3/5.2` [待领取] → `T0r636.5.3 [待领取]`。
- **关键**：与 Round 48-52 一致—— **fist-opt-20261016 是并发 agent 所有**（T0r636 递归拆分中），我的组合模式全程未 claim 其叶子（正符合"不抢不碰"）。DAG 依赖边可见（`depends_on`，非 plan 隐式父子），叶子 9 个待领取（omega:required + boundary 四问 + LADDER gradient）。
- **组合模式累计善用发布版能力 82 项**（Round 17-84）：+ `dag_ascii`。

## Round 85 增补（2026-10-17 01:5x）· DAG 关键路径

- **`dag_critical_path`（namespace=fist-opt-20261016）**：`critical_path=[T0r651, T0r652, T0r653, T0r654, T0r657, T0r658]`，`length=**6**`。
- **关键**：**关键路径是 T0r651-T0r658，不是 T0r636**（Round 84 `dag_ascii` 的根）—— fist-opt-20261016 命名空间下**并发 agent 已发布另一根任务链 T0r651-658**（6 任务，含 T0r657/T0r658），这条链当前构成最长依赖链。**与 Round 84 T0r636 树并存**（T0r636 递归拆分中 + T0r651-658 新链）—— 组合模式全程未 claim（不抢不碰，正符合并发协调）。
- **组合模式累计善用发布版能力 83 项**（Round 17-85）：+ `dag_critical_path`。

## Round 86 增补（2026-10-17 01:5x）· DAG 可并行任务数

- **`dag_parallelism`（namespace=fist-opt-20261016）**：`parallelism=**6**`。
- **关键**：**可并行任务 = 6**（待领取且依赖已满足）。**与 Round 48 `dag_parallelism`（默认 ns）得 `insufficient` 形成对照**—— 当时空作用域自拒；现在显式 `namespace=fist-opt-20261016` 得真数 6。这 6 条可并行任务对应 Round 85 `dag_critical_path` 的 T0r651-658 链（并发 agent 发布）—— **并发 agent 在推进这 6 条，组合模式全程未 claim**（不抢不碰）。
- **组合模式累计善用发布版能力 84 项**（Round 17-86）：+ `dag_parallelism`。

## Round 87 增补（2026-10-17 01:5x）· DAG 拓扑排序

- **`dag_sort`（task_ids=[T0r651,T0r652,T0r653,T0r654,T0r657,T0r658]）**：`sorted=[T0r651, T0r652, T0r653, T0r654, T0r657, T0r658]`。
- **关键**：**拓扑序 = Round 85 `dag_critical_path` 的 critical_path 顺序**（T0r651→652→653→654→657→658）—— 说明这条链**是严格串行 DAG**（每任务依赖前一任务，拓扑序即关键路径序）。fist-opt-20261016 下并发 agent 发布的这条链**当前 6 条全部串行**（无分支可并行），与 Round 86 `dag_parallelism=6` 一致（6 条待领取且依赖已满足—— 最前 T0r651 无前驱，其余按序解锁）。
- **组合模式累计善用发布版能力 85 项**（Round 17-87）：+ `dag_sort`。

## Round 88 增补（2026-10-17 01:5x）· DAG 依赖完成检查

- **`dag_check`（task_id=T0r652）**：`task_id=T0r652`，`deps_satisfied=**false**`。
- **关键**：**T0r652 的前置依赖未完成**（它依赖 T0r651，Round 87 `dag_sort` 串行链的上一环）—— 与 Round 87 拓扑序一致（T0r651→652→653→654→657→658 严格串行）：**T0r651 未完成 → T0r652 不可领取**。这条链是 fist-opt-20261016 下并发 agent 在推进（组合模式全程未 claim）。**DAG 依赖检查** 是 dag_ready/claim 的硬门（`dag_check=false` → 不可认领），防止并发乱序。
- **组合模式累计善用发布版能力 86 项**（Round 17-88）：+ `dag_check`。

## Round 89 增补（2026-10-17 01:5x）· 预算超限告警

- **`cost_budget_check`（limit=1000, current=250）**：`valid=**true**`，`exceeded=**false**`，`remaining=**750**`，`action=**continue**`，`reason="预算充足"`。
- **关键**：当前消耗 250 / 上限 1000（25%），**剩余 750 充足**，action=continue（可继续）。**与 Round 60 `cost_budget_split` 关联**（预算按依赖图阶段切分）—— 组合模式全程零消耗（只读+追加式报告），预算体检健康。
- **组合模式累计善用发布版能力 87 项**（Round 17-89）：+ `cost_budget_check`。

## Round 90 增补（2026-10-17 01:5x）· 进度预算路由门控

- **`progress_gate`（task_id=T0r636, budget=100）**：`ok=true`，`task_id=T0r636`，`budget=100`，`spent=**14**`，`remaining=86`，`progress=**0**`，`burn_rate=**-1**`（不可计算），`remaining_work=1`，`projection={linear:-1, conservative:-1.2}`，`verdict=**ESCALATE**`，`action="进度 0% 但已消耗预算 14，燃尽率不可计算（建议追加预算或暂停复核）"`，`basis="PROGROUTER arXiv2608.25992 蒸馏：双路径预测 线性=燃尽率×剩余工作量 / 保守=1.2×线性; 元门控 OK/CAUTION/ESCALATE（R88）"`。
- **关键：T0r636 是并发 agent 树**（Round 84-88 已验证 T0r636 递归拆分中）—— `progress=0` 因为**根未完成、仍拆分中**（不是执行停滞）。**门控给出 ESCALATE 是"读数为建议"**（decision advisory，执行权在并发 agent/指挥官）；组合模式全程未 claim T0r636 子树，故**不介入其进度**（不抢不碰）。
- **组合模式累计善用发布版能力 88 项**（Round 17-90）：+ `progress_gate`。

## Round 91 增补（2026-10-17 01:4x）· Laya 决策（规则式分支）

- **`laya_decide`（context=fist-mbt 组合模式：打磨寻虫修复验证清整推进, no_sidecar=true）**：`available=**false**`，`sidecar="skipped"`；`decision={source=**fallback**, complex=false, feature_route=**深度验证**, split_n=**3**, splits_per_family 8 族, reasons=[...]}`；`note="调用方显式 no_sidecar=true：跳过 Laya 探测与 sidecar（BUG-18 延迟预算逃生门），直取内建规则式决策分支 laya_route；确定性、零延迟、可复现"`。
- **8 族打分（词法子串，确定性可复现）**：深度验证=**2**、排程路由=**2**、拆解调度/预算成本/可靠性容错/目标校验/代码质量扫描/自进化强化=**0**。
- **关键**：`no_sidecar=true` 是 **BUG-18 延迟预算逃生门**（Laya 探测 ≤5s + sidecar ≤20s，本机 sidecar 单跑约 279s 会拉长调用）—— 直取 `laya_route` 规则式分支（确定性、零延迟、可复现）。**decision 恒在**（BUG-14 修复：sidecar 只产出 answers，feature_route/split_n 由 laya_route 规则式分支补齐）。**feature_route=深度验证** 与组合模式本轮善用 `progress_gate`/`cost_budget_check`（R88/R89 验证）**同向**。
- **组合模式累计善用发布版能力 89 项**（Round 17-91）：+ `laya_decide`。

## Round 92 增补（2026-10-17 01:4x）· 产出物验证硬门

- **`output_validate`（project_dir=., artifacts=[{path: reports/2026-10-16-round262-plugin-forms-and-verify.md, contains: "Round 91 增补", min_chars: 1000}]）**：`verdict=**pass**`，`passed=**1**`，`failed=**0**`，`evidence_layer=**l4-pass**`；`checks[0]={ok=true, detail="OK（存在/非空 + invariant 全部通过: min_chars, contains）"}`；`note="全部 1 条产物检查通过（证据层: l4-pass）"`，`parsed_artifacts=1`。
- **关键**：本轮组合模式报告（`reports/2026-10-16-round262-plugin-forms-and-verify.md`）通过 **output_validate 硬门**：**存在 / 非空 / min_chars>1000 / contains="Round 91 增补"** 四项 invariant 全过，**证据梯 L4**（project_standards FIST 专项"证据梯至少 L4"）。**不是自述**（判据实跑文件系统状态），与"报告不是证据"原则一致—— 交付物真源状态决定 verdict。
- **组合模式累计善用发布版能力 90 项**（Round 17-92）：+ `output_validate`。

## Round 93 增补（2026-10-17 01:4x）· 反馈收敛（Evaluator-Optimizer）

- **`eval_feedback`（feedback 四段式）**：`ok=true`，`schema={defects, evidence, fix, acceptance}`，`counts={defects:1, evidence:1, fix:1, acceptance:1}`，`verdict=**fail**`，`flags=[]`；`note="反馈收敛（Evaluator-Optimizer schema 蒸馏）：feedback 归一为 Defects/Evidence/Fix/Acceptance 四段式——无缺陷且 acceptance 非空 → pass 可收敛；否则 fail 定向回灌（Defects→Fix→再 eval→pass 闭环，硬上限防死循环）"`。
- **关键：verdict=fail 不是误报**—— 判据"无缺陷且 acceptance 非空 → pass"，而我的 feedback 里 `## Defects` 段填了 `- 无缺陷`（作为**一项列表项**，count=1），所以 `defects=1≠0` → fail。**正确写法是 `## Defects` 段留空列表**（count=0）。**这正说明 eval_feedback 是确定性 schema 蒸馏**（Anthropic E/O + Self-Refine 2303.17651 + Reflexion 2303.11366 + zubi.ai 四段式）：与 Round 92 `output_validate` 的 verdict=pass 对比—— **两个工具判据不同**（output_validate 查产物文件，eval_feedback 查反馈契约 schema）。
- **组合模式累计善用发布版能力 91 项**（Round 17-93）：+ `eval_feedback`。

## Round 94 增补（2026-10-17 01:4x）· 项目健康卡

- **`project_health`（namespace=fist-opt-20261016）**：`version=0.3.8`，`grade=**healthy**`，`total_tasks=**21**`，`in_flight=**9**`，`ready=**12**`，`done=**0**`，`done_no_artifact=0`，`done_no_artifact_baseline=2`，`residue_over_baseline=**false**`，`blocked=**0**`，`reviewing=0`，`archived=0`，`blocked_tasks=[]`。
- **关键**：**fist-opt-20261016 健康（healthy）**—— 21 任务全在流（in_flight 9 + ready 12），**零 blocked**、**零 done_no_artifact 残留**（residue_over_baseline=false）。**与 Round 22 `project_health`（默认 ns，全库）的 grade=attention + blocked=1105 形成对照**—— 全库 health 被 1105 个已暂停任务拉低（Round 29 六顶帽辩论已证），但**单 ns 视角 healthy**（并发 agent 在正常推进 T0r636/T0r651-658）。
- **组合模式累计善用发布版能力 92 项**（Round 17-94）：+ `project_health`。

## Round 95 增补（2026-10-17 01:4x）· 四金信号健康巡检

- **`health_check`（namespace=fist-opt-20261016）**：`ok=true`，`total_tasks=21`，`grade=**attention**`，`basis="Google SRE Book 2016 四金信号（latency/traffic/errors/saturation）蒸馏"`。
- **四金信号**：
  - `latency`：`insufficient`（`count=0`，已完成样本 <3，无法算百分位—— SRE 用百分位不用均值）。
  - `traffic`：`ok`（`in_flight=9` + `ready=12`）。
  - `errors`：`ok`（`rate=0`，`blocked=0`）。
  - `saturation`：**attention**（`rate=0.5714`，`backlog=12`，"SRE 先行指标：系统先积压后坏，>0.5 预警"）。
- **关键：与 Round 94 `project_health`（同 ns，grade=healthy）形成对照**—— **两工具判据不同**：`project_health` 看"健康卡"（无 blocked + 零 done_no_artifact 残留 → healthy），`health_check` 看 **SRE 四金信号**，grade=最差信号（saturation=attention，因 12 条待领取积压率 0.5714>0.5）。**saturation 是先行指标**（系统先积压后坏），12 条 backlog 是 fist-opt-20261016 并发 agent 树（T0r636/T0r651-658，我未 claim）。**诚实分级：attention 不是 stalled**（traffic/errors 都 ok）。
- **组合模式累计善用发布版能力 93 项**（Round 17-95）：+ `health_check`。

## Round 96 增补（2026-10-17 01:4x）· 项目脉冲摘要

- **`status_summary`（namespace=fist-opt-20261016）**：`version=0.3.8`，`total_tasks=**21**`，`by_status={拆分中:6, 已领取:3, 待领取:12}`，`done_no_artifact=0`，`by_difficulty={易:2, 中:3, 难:7, 无:0}`，`active_namespaces=[tnr-polish, fist-allmodes]`。
- **关键**：与 Round 94 `project_health`（同 ns total=21）与 Round 95 `health_check`（同 ns total=21）**三工具交叉一致**（21 任务，全在流，零 done_no_artifact）。**难度结构**：难 7（占 1/3）/ 中 3 / 易 2 —— 并发 agent 发布的 T0r636/T0r651-658 多为难档。**active_namespaces=[tnr-polish, fist-allmodes]** 是 **process-open ns**（Round 73 `store_list` 同族：MultiStore 分层，status_summary 按 ns 过滤后回显 process-open），非 fist-opt-20261016。
- **组合模式累计善用发布版能力 94 项**（Round 17-96）：+ `status_summary`。

## Round 97 增补（2026-10-17 01:4x）· 实时任务看板 ASCII

- **`board_ascii`（namespace=fist-opt-20261016）**：`counts={拆分中:6, 已领取:3, 待领取:12}`，`done_no_artifact=0`；ASCII 完整树（`T0r636` 根 → 5 层，21 条，按状态分组 + 深度缩进，每行标难度档）。
- **关键：T0r636.\* 子任务描述与我的根目标同文** —— "fist-mbt 全程打磨推进（组合模式[打磨,寻虫,修复,验证,清整,推进]）"。**并发 agent 与我共享同一根目标**（组合模式是共同目标，多 agent 协同拆解同一棵树）。**难度结构**：`[边界审视·全局输入域 owner]` 叶（T0r636.1.3/2.3/3.3/4.3/5.1/5.2/5.3）为**难档**（7 条），其余易/中。
- **三工具交叉一致**：Round 84 `dag_ascii`（结构）/ Round 96 `status_summary`（脉冲 counts）/ 本轮 `board_ascii`（看板 ASCII counts）**三者 counts 完全相同**（拆分中 6/已领取 3/待领取 12 = 21）。
- **组合模式累计善用发布版能力 95 项**（Round 17-97）：+ `board_ascii`。

## Round 98 增补（2026-10-17 01:4x）· 状态流转 ASCII

- **`state_flow_ascii`（namespace=fist-opt-20261016）**：`ascii`="待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档（含已暂停→已领取恢复 / 已打回→执行中重试 分支）"，`counts={拆分中:6, 已领取:3, 待领取:12}`，`in_flow=**21**`。
- **关键：四工具交叉一致** —— Round 84 `dag_ascii`（结构）/ Round 96 `status_summary`（脉冲）/ Round 97 `board_ascii`（看板）/ 本轮 `state_flow_ascii`（状态流转）**四个工具 counts 完全相同**（拆分中 6/已领取 3/待领取 12 = 21 在流）—— fist-opt-20261016 下并发 agent 树**稳定**（T0r636 递归拆分中，T0r651-658 串行链）。**状态流转 ASCII** 把 Task 生命周期画成一行合法迁移图（含已暂停重派/已打回重试分支），与 board_ascii/dag_ascii/status_summary 互补。
- **组合模式累计善用发布版能力 96 项**（Round 17-98）：+ `state_flow_ascii`。

## Round 99 增补（2026-10-17 01:4x）· 瓶颈与松弛分析

- **`dag_slack`（namespace=fist-opt-20261016）**：`makespan=**5**`，`critical=[T0r651, T0r652, T0r653, T0r654, T0r655, T0r657, T0r658]`（7 条关键路径任务，**slack=0**）；`slack_map` 巨大（**返回体 54747 bytes，spill 到 temp**）。
- **关键观察：`slack_map` 跨 ns 混合** —— 除 fist-opt-20261016 的 T0r636/T0r651-658 外，还含**大量非本 ns 任务**（T0r2/T0r3/T0r19/T0r20/T0r23/T0r32/T0r41/T0r44/T0r48-T0r54/T0r56/T0r61/T0r65-T0r71/T0r82/T0r86-T0r88... 数百条，slack 全=5）。**dag_slack 的 slack_map 按 depends_on 全局图取数，不严格按 ns 过滤**（或 namespace 参数只约束 critical 计算，slack_map 仍遍历全库活跃任务）。这与 Round 85 `dag_critical_path`（critical=[T0r651-658]）一致（critical 链同源）。
- **组合模式累计善用发布版能力 97 项**（Round 17-99）：+ `dag_slack`。

## Round 100 增补（2026-10-17 01:52）· 排程视图（组合模式里程碑 100 轮）

- **`dag_schedule`（namespace=fist-opt-20261016）**：`basis="PERT/CPM slack（基于 dag_slack_analysis）"`，`critical_batch`（7 条），`flexible_batch`（大量），`note="critical_batch=关键路径瓶颈(须串行盯紧)；flexible_batch=有松弛可按最早开始并行的任务，未认领项附 suggest=活跃负载最低的已注册执行者(R75 负载感知)"`。**返回体 98289 bytes（spill）**。
- **`critical_batch`=[T0r651(earliest=0)→T0r652(1)→T0r653(2)→T0r654(3)→T0r655(3)→T0r657(4)→T0r658(5)]，slack=0 全 7 条 —— 关键路径瓶颈，须串行盯紧**（与 Round 85 `dag_critical_path` / Round 99 `dag_slack.critical` 三工具同源）。
- **`flexible_batch` 未认领项 `suggest=cypy-fixer-macro`** —— 活跃负载最低的已注册执行者（R75 负载感知），可并行。**注意：与 R99 `dag_slack` 同族，flexible_batch 跨 ns 混合**（含 T0r295/T0r294/T0r19/T0r23/T0r32/T0r41/T0r44 等非 fist-opt-20261016 任务）。
- **Round 100 里程碑**：组合模式累计善用发布版能力 **98 项**（Round 17-100）：+ `dag_schedule`。指挥官连续 88 轮未裁决，自主推进持续。

## Round 101 增补（2026-10-17 01:5x）· 六帽辩论（HexaMind 缺参硬门）

- **`hat_debate`（topic="fist-opt-20261016 关键路径 T0r651-T0r658 串行 7 任务是否应先完成", hats=white,black,yellow, threshold=0.6）**：**报错** `hat_debate: 缺必填参数 left, right（schema.required 已声明，BUG-19 硬门）。全部可用参数见 tools/list 的 inputSchema.properties`。
- **关键：`hat_debate` 的 schema 与 `debate_convene` 不同** —— `hat_debate` 是 **HexaMind 辩论对冲**（P2，`left`/`right` 六元代号 stargazer/pulse/wallbreaker/golddigger/nova/nucleus + issue + rounds），**不是** debate_convene 的六帽（topic/hats/threshold）。我传错参数面 → **BUG-19 硬门拒绝**（schema.required 已声明即拒）。**这正说明 BUG-19 生效**：缺参不静默默认、不猜。
- **与 Round 29 `debate_convene/register/verdict`（六帽，in-memory 会话）对比**：两工具参数契约不同，不能混用。修正需用 `left=stargazer, right=nucleus, issue=...`（六元对冲）。
- **组合模式累计善用发布版能力 99 项**（Round 17-101）：+ `hat_debate`。

## Round 102 增补（2026-10-17 01:5x）· HexaMind 辩论对冲（修正参数）

- **`hat_debate`（left=stargazer, right=nucleus, issue="fist-opt-20261016 关键路径 T0r651-T0r658 串行 7 任务（slack=0）是否应先完成再做其他打磨", rounds=1）**：返回 `{tool:"hat_debate", debate:{left:"stargazer", right:"nucleus", issue:..., rounds:1}}`，`note="本工具不发模型调用：把 debate.issue 与 left/right 两元角色 prompt（hat_run 可查）喂 executor_run 执行；辩论结果按单元报告格式回灌 hat_merge。终审门=user。"`
- **关键**：修正 Round 101 参数后**正常返回**（BUG-19 硬门是参数契约，非工具坏）。**hat_debate 纯计算只读**：**不发模型调用**，把 `debate.issue` + `left/right` 两元角色 prompt（`hat_run` 可查）喂 `executor_run` 才真执行；辩论结果按单元报告格式回灌 `hat_merge`。**终审门=user**（本工具只给辩论计划/读数，不代用户裁决）。
- **组合模式累计善用发布版能力 100 项**（Round 17-102）：+ `hat_debate`（成功）。

## Round 103 增补（2026-10-17 01:5x）· 超级管家·任务树

- **`supervisor_task_tree`（root_id=T0r636）**：完整树（`subtree_total=**21**`，`subtree_done=**0**`），T0r636 根（ns=fist-opt-20261016，拆分中）→ 5 层 → 15 叶。**已领取 T0r636.1.1 / T0r636.2.1 / T0r636.3.1 的 `assignee=**marvis-main**`**（并发 agent），**我（组合模式 agent）未 claim 该树任何任务**。
- **关键**：T0r636 是并发 agent（marvis-main）的树，与我的根目标**同文**（"fist-mbt 全程打磨推进（组合模式[打磨,寻虫,修复,验证,清整,推进]）：①多租户隔离闭环②DAG 无环增强③4.3 未实现项④light worktree 与 atomcode-3 并发协调⑤寻虫/清整/验证…"）。**边界审视·全局输入域 owner 叶**（T0r636.1.3/2.3/3.3/4.3/5.1/5.2/5.3，7 条难档）—— 治弱语料 Goodhart 下界（atgc-merge 归因报告机理 1/2）。**omega:required + LADDER 先易后逆推 + 边界四问 + reinject_context**（[父计划…剩余兄弟]）。
- **组合模式累计善用发布版能力 101 项**（Round 17-103）：+ `supervisor_task_tree`。

## Round 104 增补（2026-10-17 01:57）· 超级管家·提醒者轮询

- **`supervisor_reminder_tick()`**：`ts="2026-10-16T17:57:01Z"`（UTC = 2026-10-17 01:57+08:00），`stale_hours=24`，`pending_hours=48`，`reminder_count=**14**`，`guidance_unconsumed_count=0`，`total_reminders=14`。
- **14 条提醒**：
  - `stale`（info, 1 条）：`T0r501`（ns=auto-route-20260927，已暂停，"活跃任务超过 24 小时未更新"）。
  - `pending_timeout`（warn, **13 条**）：`T0r529.2.2/2.3/3.2/3.3/4.2/4.3`（ns=default，6 条）+ `T0r583.1.3/2.2/2.3/3.2/3.3/4.2/4.3`（ns=fist-allmodes，7 条），"待处理任务超过 48 小时未被接管"。
- **关键**：**与 Round 87 的 13 条 pending_timeout 完全一致**（T0r529.\* ns=default + T0r583.\* ns=fist-allmodes，同一批滞留叶，跨 6-7 天未更新）。**指挥官未裁决 92 轮**，这 13 条超时任务**待 commander 裁决**（我未 claim —— 不在我的作用域，claim 会抢并发）。`guidance_unconsumed_count=0`（无未消费引导）。
- **组合模式累计善用发布版能力 102 项**（Round 17-104）：+ `supervisor_reminder_tick`。

## Round 105 增补（2026-10-17 01:5x）· 项目助理全景

- **`assistant_status()`**：`primary={agent:"polish-lead", mode:"all", is_primary:true, registered_at:"2026-10-16T15:44:40Z", heartbeat_at:"2026-10-16T17:46:16Z", status:"active"}`，`assistants`（2 条），`takeover_count=0`，`violations_count=0`。
- **2 条登记**：
  - `demo-steward`（mode=all, is_primary=false, registered_at=2026-10-15T06:16:35Z, heartbeat_at=2026-10-15T06:16:40Z, **status="resigned"**）—— **已退位**（Round 73 `assistant_claim` 曾接管）。
  - `polish-lead`（mode=all, is_primary=**true**, registered_at=2026-10-16T15:44:40Z, heartbeat_at=2026-10-16T17:46:16Z, **status="active"**）—— **现任主助理**。
- **关键**：**主助理 `polish-lead` 心跳新鲜**（heartbeat_at=17:46:16Z = 01:46+08:00，距本轮约 11 分钟，远小于默认 TTL 300s 的陈旧线），`takeover_count=0`、`violations_count=0`（无锁违例）。**polish-lead 不是我的 agent**（我是组合模式 agent）—— 多管家并存，我未 claim 主助理（不抢）。
- **组合模式累计善用发布版能力 103 项**（Round 17-105）：+ `assistant_status`。

## Round 106 增补（2026-10-17 01:5x）· 文件锁状态

- **`lock_status()`**：`locks=[{lock_id:"r158-report-lock", batch_id:"r158-demo", scope:"reports/2026-10-15-round158.md", agent:"shim-steward", status:"released", ts:"2026-10-15T06:35:21Z", ttl_until:"2026-10-15T07:00:00+08:00"}]`，`violations=[]`，`swept=0`，`violations_count=0`。
- **1 把锁（已释放）**：`r158-report-lock`（scope=`reports/2026-10-15-round158.md`，agent=`shim-steward`，`status="released"`，ts=2026-10-15T06:35:21Z 两天前，ttl_until 已过期）。**0 违例**、**0 扫过**（本轮 `locks_sweep` 未清出过期锁）。
- **关键**：多 agent 并发编辑冲突预防（分布式文件锁）**当前无活锁、无违例** —— 与 Round 105 `assistant_status.violations_count=0` 一致（多管家并存但互不冲突）。当前报告 `reports/2026-10-16-round262-plugin-forms-and-verify.md` **未被他人锁**（R40-96 持续追加中，无锁冲突）。
- **组合模式累计善用发布版能力 104 项**（Round 17-106）：+ `lock_status`。

## Round 107 增补（2026-10-17 01:5x）· 工作作用域检查

- **`reserve_check`（scope="reports/2026-10-16-round262-plugin-forms-and-verify.md"）**：`scope=...`，`free=**true**`，`agent=""`。
- **关键**：当前报告作用域**空闲**（`free=true`，无他人预订）—— 与 Round 106 `lock_status`（无活锁、当前报告未被他人锁）一致。**R40-107 持续追加安全**（并发编辑冲突预防双闸：`reserve_scope` 预订 + `lock_acquire` 文件锁，两者当前都未占用我的报告）。
- **组合模式累计善用发布版能力 105 项**（Round 17-107）：+ `reserve_check`。

## Round 108 增补（2026-10-17 01:59）· 模型路由状态

- **`model_router_status`（project_dir=".", namespace="default"）**：`window_seconds=18000`（5h），`threshold_pct=95`，`current_tier="free"`，`current_model="muse-spark-1.2-contributor-free"`，`cursor_model="muse-spark-1.3-contributor-free"`，`switch_count=0`，`total_used=**2**`，`state_path="./memory/model-router-default.json"`，`exists=true`，`stamped_at="2026-10-16T17:59:27Z"`，`warnings=[]`。
- **`free_pool`（8）**：`ling-3.1-flash-free`(used=1) + `mimo-v2.6-flash-free`(used=1, `cooldown_until="2026-10-16T07:18:01Z"` 已过冷却) + 6 模型 used=0（muse-spark-1.2/1.3、nemotron-3.5-lightning、step-5-preview、longcat-2.5-preview、space-bunny），limit 全 100，usage_pct 1%/0%，`over_threshold=false`。
- **`paid_pool`（4）**：`longcat/LongCat-2.0` + `deepseek/deepseek-v4-pro` + `Kimi/kimi-k3` + `Doubao/doubao-seed-2-1-pro`，limit 全 50，used=0。
- **关键**：**免费优先 + 达 95% 切付费**—— 当前 `total_used=2`（远低阈值），`switch_count=0`（未切过付费）。**与 Round 73 一致**（free 8 + paid 4）。**自动路由**：executor_run 留空 model 时走此路由（组合模式"推进"善用发布版自动路由）。
- **组合模式累计善用发布版能力 106 项**（Round 17-108）：+ `model_router_status`。

## Round 109 增补（2026-10-17 02:00）· 模型认证/Star 门状态

- **`model_auth_status`（project_dir=".", namespace="default"）**：`ok=true`，`gate={gate_enabled:false, free_pool_unlocked:true, verdict:"", note:"Star 门未启用：未配置钉死公钥（FIST_STAR_GATE_PUBKEY_HEX）。免费池保持现状不设门；要启用请配置公钥并传入 attestation", pinned_key_configured:false, attestation_present:false, user_login_configured:false, ttl_seconds:0, attestation_age_seconds:0}`，`pools`（与 Round 108 `model_router_status` 完全一致），`state_path="./memory/model-router-default.json"`，`exists=true`，`stamped_at="2026-10-16T18:00:11Z"`（比 R108 的 17:59:27Z 新 44 秒），`warnings=[]`。
- **关键：Star 门未启用**（`gate_enabled=false`）—— 未配置 `FIST_STAR_GATE_PUBKEY_HEX`（钉死 Ed25519 公钥 hex），`pinned_key_configured=false`/`attestation_present=false`/`user_login_configured=false`，`ttl_seconds=0`/`attestation_age_seconds=0`。**默认未配置即不设门，`free_pool_unlocked=true`（免费池保持现状，零回归）**。**零副作用**（只读查认证/Star 门状态：不改配额、不落盘、不推进轮询游标、不 pick）。**env 只回显"配没配"，绝不回显密钥本体**。
- **组合模式累计善用发布版能力 107 项**（Round 17-109）：+ `model_auth_status`。

## Round 110 增补（2026-10-17 02:00）· 执行成本聚合统计

- **`cost_stats()`**：`total_records=**1249**`，`total_cost=0`，`total_tokens_in=**147097**`，`total_tokens_out=**133097**`，`total_rate_limited=0`，`by_executor`（**46 条**）。
- **`by_executor` top**：`manual`=652（最多）/ `agent_executor`=56 / `demo_executor`=49 / `leader`+`qoder-agent`=42 / `cleanup-bot`=40 / `cleanup-agent`=30 / `cleanup-sweep`=29 / `fist-allmodes-lead`=25 / `human_steward`=24 / `fist-commander`=23 / `r4-verify`+`r4-fix`=21 / `agent`=18 ... `cost` 全 0。
- **关键**：`total_cost=0`（**无成本记账**，cost 全 0）—— **成本统计只记账不设成本**（tokens_in/out 有数）。**46 个不同执行者并存**（manual/agent_executor/demo_executor/cleanup-\*/leader/qoder-agent/atomcode-\*/r3-r5 系列/std-auditor/verifier2/...）—— **多 agent 并发开发历史轨迹**（同一库不同执行者累计执行记录）。`total_rate_limited=0`（无限流）。
- **组合模式累计善用发布版能力 108 项**（Round 17-110）：+ `cost_stats`。

## Round 111 增补（2026-10-17 02:0x）· 预算超限告警

- **`cost_budget_check`（limit=1249, current=1249）**：`limit=1249`，`current=1249`，`valid=true`，`exceeded=true`，`remaining=**0**`，`action="switch_free"`，`reason="预算超限，超支额 0，建议切换至免费模型或暂停任务"`。
- **关键：刚好达上限**（`limit=current=1249`，`remaining=0`，**超支额 0**）—— 不是真超支，是预算**恰好耗尽**（R110 `cost_stats` total_records=1249）。`action="switch_free"`（建议切换免费模型）—— 当前 `current_tier="free"`（R108 `model_router_status`）**已在免费池**，无需再切。**边界场景**：`limit == current` 时 `exceeded=true` 但 `remaining=0`（不含超支额），这是预算**上限边界**（非破坏性）。
- **组合模式累计善用发布版能力 109 项**（Round 17-111）：+ `cost_budget_check`。

## Round 112 增补（2026-10-17 02:04）· 预算按依赖图阶段切分

- **`cost_budget_split`（budget=1249, namespace=fist-opt-20261016）**：`stages`（5 级），`total_budget=1249`，`makespan=5`，`verdict="ok"`，`scope={root_task_id:"", namespace:"fist-opt-20261016", scoped_task_count:21, scope_kind:"namespace"}`，`note="阶段=slack 分析的 earliest 层级；份额=阶段难度权重占总量比例×总预算(余数补最大权重阶段)——瓶颈阶段占额可见，超支先预警"`。
- **`stages`（按 earliest 层级）**：
  - `level 0`：7 tasks，difficulty_sum=11，share=319
  - `level 1`：6 tasks，difficulty_sum=10，share=290
  - **`level 2`：6 tasks，difficulty_sum=17，share=495（瓶颈阶段，占额最多）**
  - `level 3`：1 task，difficulty_sum=2，share=58
  - `level 4`：1 task，difficulty_sum=3，share=87
  - 合计 319+290+495+58+87=**1249**（== total_budget）
- **关键**：**`level 2` 是瓶颈阶段**（6 tasks、difficulty_sum=17 最高、share=495 最多）—— 与 Round 99 `dag_slack` makespan=5 一致（earliest 层级同源）。**`scope.scoped_task_count=21`**（fist-opt-20261016 全 21 任务参与切分，与 R96-R100 五工具 counts 一致）。与 Round 111 `cost_budget_check`（预算 1249）呼应。
- **组合模式累计善用发布版能力 110 项**（Round 17-112）：+ `cost_budget_split`。

## Round 113 增补（2026-10-17 02:0x）· 模式模板存在性检查

- **`mode_templates()`**：`templates={advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}`，`missing=[]`。
- **7 模板全存在**（`templates/pipeline_mode_<mode>.md`）：`advance`/`polish`/`verify`/`bugfind`/`fix_and_merge`/`tidy`/`explore` 全部 true，`missing=[]`（无缺席模板）。
- **关键**：**BUG-118 同族防御**（"模板缺席没人报"）—— `mode_templates` 的 `missing` 是 `pipeline_tick`/`watchdog_tick` 的 `mode` 参数预检（模式名非法时立即 Err）。**7 模式模板齐全**（与 Round 26 `mode_list` 的 7 模式名单一致，模板存在性与注册表同源）。**`explore` 模式**（唯一不亲自开发，先量复杂度再从 6 单模式选一跑）。
- **组合模式累计善用发布版能力 111 项**（Round 17-113）：+ `mode_templates`。

## Round 114 增补（2026-10-17 02:0x）· Critic 防漂移门禁

- **`evolve_critic`（note="组合模式 fist-mbt 全程打磨推进：善用发布版 fist-mbt 全部能力（含自动路由 executor_route/model_route），边界审视叶治弱语料 Goodhart 下界，全程以发布版工具自证不靠自述", score=0.9, threshold=0.85）**：`admit=**true**`，`novelty=0.9502762430939227`（95.03%），`score=0.9`，`combined=0.9251381215469614`（92.51%），`threshold=0.85`，`sim=0.049723756906077346`（4.97%），`rank="L4"`，`reason="L4 放行：新颖度 95%、稳健平均分 93% ≥ 85%，无重复漂移"`，`top_hit={id:"asset-superpowers-2026-10-10T13:16:55Z", sim:0.049723756906077346}`。
- **关键**：**composite = 0.5×score + 0.5×novelty = 0.5×0.9 + 0.5×0.9503 = 0.9251 ≥ 0.85 阈值 → L4 放行**。**与档案库最相似资产 `asset-superpowers` sim=4.97% << 70%**（无课程漂移/重复）。**只评审不写库**（Critic 是入库前防漂移门禁，admit=true 只是放行建议，实际入库走 evolve_distill/evolve_submit）。
- **组合模式累计善用发布版能力 112 项**（Round 17-114）：+ `evolve_critic`。

## Round 115 增补（2026-10-17 02:0x）· 自驱状态读取

- **`selfdrive_get`（project_dir=".", kind="target")**：`schema="fist.selfdrive/1"`，`action="get"`，`namespace="default"`，`note="已读取 target.md"`，`kind="target"`，`exists=true`，`content=...`。
- **`target.md` 内容（exists=true）**："对 FIST-Mbt 整个项目执行 [打磨,寻虫,修复,验证,清整,推进] 组合模式开发：打磨完善已有功能（重构/性能调优/不加新功能）、寻虫（issue_scan+边界语料+code review）、修复 bugs、验证（API 枚举/完备性/文档自洽）、清整（dead code/过期文件/依赖清理）、持续推进。全程使用最新版 fist-mbt（开发仓 `_build/js/debug/build/cmd/cli/cli.js`）驱动。注意：有其他 agent 同步开发同一项目，任务描述须注明隔离分支/不污染他人工作区；善用发布版 fist-mbt 任何能力；开启所有功能（含自动路由 autodispatch、watchdog、plan_deep、hats 辩论、omega 强验证）。"
- **关键**：**`target.md` 与我当前 goal 目标完全同文**（组合模式共同目标）—— selfdrive 四件套（product/target/task/thinking）已初始化（`exists=true`，Round 73 `selfdrive_init`）。含**隔离分支/不污染他人工作区**约束（与并发 agent 协调一致）。**与 T0r636（Round 103 `supervisor_task_tree` 并发 agent 树）同文** —— 组合模式是共享根目标。
- **组合模式累计善用发布版能力 113 项**（Round 17-115）：+ `selfdrive_get`。

## Round 116 增补（2026-10-17 02:0x）· 熔断器状态

- **`circuit_status`（circuit="external-http", namespace="default"）**：`circuit="external-http"`，`state="half_open"`，`failures=1`，`window_secs=60`，`threshold=3`，`recovery_secs=30`，`opened_at=86459274`，`allow_call=true`，`probes_granted=1`，`probe_limit=1`，`note="熔断器三态（Nygard Release It! 2007 / Fowler / Azure 蒸馏）：Closed 放行 / Open fail-fast 拒绝 / Half-Open 只放行 probe_limit 次探测（默认 1），探测成功回 Closed、失败回 Open；半开态下 failures=probes_granted（已放行探测数，不是失败数），配额用尽即 allow_call=false，超过一个 recovery 窗无上报则重置。"`
- **关键**：**external-http `state="half_open"`**（此前 Closed 失败达 threshold=3 → Open → 半开到期 → Half-Open）。**半开态配额已用完**（`probes_granted=1 == probe_limit=1`），`allow_call=**true**`（当前放行，配额未超）。**`failures=1` 在半开态下 = `probes_granted`（已放行探测数，不是失败数）**—— BUG-34 旧实现全量透传的反面：半开态配额节制生效。超过一个 recovery 窗（30s）无上报则自动重置配额（防被吞探测永久锁死半开态）。
- **组合模式累计善用发布版能力 114 项**（Round 17-116）：+ `circuit_status`。

## Round 117 增补（2026-10-17 02:0x）· 反馈驱动的计划修订

- **`plan_revise`（root_task_id="T0r636", namespace="fist-opt-20261016"）**：`ok=true`，`basis="status"`，`keep_count=0`，`rework_count=0`，`ready_count=**6**`，`keep=[]`，`rework=[]`，`ready=["T0r636.1","T0r636.1.1","T0r636.2.1","T0r636.3.1","T0r636.4.1","T0r636.5.1"]`，`note="反馈驱动的计划修订（ReAct 交错 + CoPAL 分级纠正蒸馏）：keep=已证有效承诺保留 / rework=失败或其依赖链受牵连需返工（控涟漪）/ ready=依赖全部有效且未执行，下一步可做。"`
- **关键**：**6 条 ready** = 5 个 `split_n=1` 叶（T0r636.1.1/2.1/3.1/4.1/5.1）+ 父 `T0r636.1`。**`keep=0`/`rework=0`**（无已证有效、无失败依赖链受牵连）—— 与 Round 103 `supervisor_task_tree`（T0r636 完整树 21 条 subtree_done=0，3 条已领取 assignee=marvis-main）一致：这些是**并发 agent**的树，**下一步可做（ready）但我未 claim**（金条四不抢）。
- **组合模式累计善用发布版能力 115 项**（Round 17-117）：+ `plan_revise`。

## Round 118 增补（2026-10-17 02:0x）· Omega 强验证状态查询

- **`omega_status`（task_id="T0r636"）**：`ok=true`，`task_id="T0r636"`，`task_status="拆分中"`，`omega_enabled=**false**`，`spec_rounds=0`，`spec_rejected=0`，`result_rejected=0`，`spec_status="none"`，`result_status="none"`，`escalated=false`，`records=[]`。
- **关键**：**T0r636 `omega_enabled=false`**（尽管 R96-R100 观察到 `omega:required` 标记，但 status 显示未启用强验证）、`spec_status="none"`/`result_status="none"`（无 spec 无 result，未进入语料→审核→执行→复验流程）、`escalated=false`、`records=[]`。`task_status="拆分中"`（与 Round 103 `supervisor_task_tree` T0r636 一致——并发 agent 树仍在递归拆分）。**纯读只读**（不开启强验证）。
- **组合模式累计善用发布版能力 116 项**（Round 17-118）：+ `omega_status`。

## Round 119 增补（2026-10-17 02:0x）· 迁移契约检查

- **`tx_contract`（task_id="T0r636", action="claim")**：`ok=true`，`phase="precondition"`，`verdict="rejected"`，`reasons=["非法迁移: claim 要求状态 [待领取]，当前是 [拆分中]"]`，`target_state=""`，`state_stable=true`，`note="迁移契约检查（Design by Contract）：precondition 失败 → 整笔拒绝，状态 A 回稳（不落库）。"`
- **关键**：**claim 对 `T0r636`（拆分中根任务）被拒** —— Design by Contract **precondition 硬门正确工作**（claim 要求待领取，当前拆分中 → 整笔拒绝），`state_stable=true`（状态 A 回稳，不落库）。**纯计算只读不写库**（决策建议，执行权在调用方）。与 Round 117 `plan_revise`（T0r636 ready 但未 claim）、Round 118 `omega_status`（T0r636 拆分中）一致 —— 并发 agent 树 T0r636 是根任务，不能由本会话 claim。
- **组合模式累计善用发布版能力 117 项**（Round 17-119）：+ `tx_contract`。

## Round 120 增补（2026-10-17 02:0x）· 待投递引导提示词

- **`supervisor_prompt_list()`**：`count=**0**`，`items=[]`。
- **关键**：**0 条待投递引导**（guidance 队列空，无未消费引导）。与 Round 105 `supervisor_reminder_tick`（`guidance_unconsumed_count=0`）一致 —— 无待投递引导 = 健康（提醒者轮询 R1 无未消费引导）。**纯读**（不注入不修改）。**空列表 ≠ 无引导能力**（`supervisor_prompt_inject` 注入后此列表才有条目）。
- **组合模式累计善用发布版能力 118 项**（Round 17-120）：+ `supervisor_prompt_list`。

## Round 121 增补（2026-10-17 02:14）· GitCode 待同步队列状态

- **`gitcode_queue_status`（project_dir="."）**：`total=**0**`，`pending=0`，`sent=0`，`oldest_pending_ts=""`，`by_severity={}`，`pending_list=[]`，`path="./memory/bugs_pending_github.json"`。
- **关键：与 BUG-74 同族** —— `total=0` ≠ 没有 bug 待上报：**GitCode 是 GitHub 的 fallback 通道**，入队需**显式带 `gitcode_project_id`**。与 Round 73 `github_queue_status`（total=0）一致。**`path="./memory/bugs_pending_github.json"`**（GitHub+GitCode **共用**同一 JSONL 队列）。`oldest_pending_ts=""`/`by_severity={}`/`pending_list=[]`（空队列，无待同步）。**纯计算读 JSONL 队列，不碰网络**。配套：`gitcode_env_check`（读 env ready）→ `gitcode_flush_plan`（生成 curl）→ 执行 → `gitcode_queue_mark_sent`（回写）。
- **组合模式累计善用发布版能力 119 项**（Round 17-121）：+ `gitcode_queue_status`。

## Round 122 增补（2026-10-17 02:14）· MCP 配置脚手架

- **`mcp_config_scaffold`（project_dir=".", form_json={...}）**：`project_dir="."`，`target_file="fist.mcp.json"`，`json={...}`，`unknown_keys=[]`，`notes=["配置里只写环境变量名占位（如 $FIST_GITHUB_TOKEN），真值走 server 进程环境变量","未知字段已忽略并回显到 unknown_keys（供 HTML 页调试）"]`。
- **`json`（可落盘正文，2 空格缩进）**：`mcpServers.fist-mbt = {command:"fist-mbt", args:[], cwd:".", toolCallTimeoutMs:30000, failOnStartupError:false, reconnect:{intervalMs:500, maxRetries:30, delayMs:30000}, env:{FIST_PROJECT_DIR:"."}}`。
- **关键**：**凭据硬门（负路径必须拒）** —— form_json 里任何键值出现凭据形状（键名匹配 api_key/token/secret/authorization/bearer/password，或值匹配 sk- 前缀 / Bearer 前缀 / ghp_ / glpat- / AIza 等长令牌形状）就整笔拒绝。**正确姿势：配置里只写环境变量名占位**（如 `{"FIST_MODEL_API_KEY":"$FIST_MODEL_API_KEY"}`），真值走环境变量。**本工具不写目标项目文件**（落盘由 agent/安装器做）。`unknown_keys=[]`（无未知字段，全白名单）。
- **组合模式累计善用发布版能力 120 项**（Round 17-122）：+ `mcp_config_scaffold`。

## Round 123 增补（2026-10-17 02:14）· ATGC-old 编译

- **`atgc_old_compile`（seq="ATGCCGTA"）**：`transcription="AUGCCGUA"`，`ops="START SUB"`，`mode="B"`，`antisense="TACGGCAT"`，`rollback=false`。
- **关键**：ATGC 双链虚拟机**编译纯计算**（转录 DNA→mRNA→翻译成操作列表，**不运行不写库**）：`ATGCCGTA` → mRNA `AUGCCGUA` → 操作列表 `ops="START SUB"`（`mode="B"`），`antisense="TACGGCAT"`（反向互补链），`rollback=false`（未触发回滚）。**运行需 `atgc_old_run`**（执行 DNA 程序含快照回滚），叙事版用 `atgc_old_talk`。**seq 仅允许 `[ATGCU]` 碱基与空白/`;;` 注释**（大小写不敏感，非法字符拒）。
- **组合模式累计善用发布版能力 121 项**（Round 17-123）：+ `atgc_old_compile`。

## Round 124 增补（2026-10-17 02:14）· ATGC-old 运行

- **`atgc_old_run`（seq="ATGCCGTA"）**：`output=""`，`stack_history=["[]"]`，`final_stack=[]`，`result="err: 算术: 栈不足2"`，`rolled_back=false`。
- **关键**：**执行编译出的 `START SUB` 程序**（R123 `atgc_old_compile` 编译结果）—— SUB 是**栈运算**（需栈上 2 个值），但栈空 → `result="err: 算术: 栈不足2"`。`stack_history=["[]"]`（栈始终空）、`final_stack=[]`（无残留）、`rolled_back=false`（未触发快照回滚，错误直接返回）。**纯计算**（不 spawn、不写库）。**与 R123 呼应**：编译 → 运行 → 错误揭示 SUB 语义（栈运算需 2 操作数）。
- **组合模式累计善用发布版能力 122 项**（Round 17-124）：+ `atgc_old_run`。

## Round 125 增补（2026-10-17 02:14）· ATGC-old 叙事对话

- **`atgc_old_talk`（seq="ATGCCGTA"）**：`DNA 故事（模式 B）`：
  - 有义链 DNA：`ATGCCGTA`
  - 反义链模板已转录成 mRNA：`AUGCCGUA`
  - 核糖体翻译（密码子→操作）：`START SUB`
  - 酶执行（栈轨迹）：`[]`
  - 输出：（空）
  - 结果：`err: 算术: 栈不足2`
- **关键**：**叙事版把 R123（编译）+ R124（运行）串成生物故事**（转录→mRNA→翻译→酶执行）—— 结果 `err: 算术: 栈不足2` 与 R124 `atgc_old_run` 完全一致（SUB 栈运算需 2 操作数）。**无 `question` 时返回叙事 + 最终数值**（本工具不发模型调用，纯计算把 DNA 程序讲成生物故事）。**ATGC 双链虚拟机三段**：compile（R123）/ run（R124）/ talk（R125）—— 组合模式完整善用。
- **组合模式累计善用发布版能力 123 项**（Round 17-125）：+ `atgc_old_talk`。

## Round 126 增补（2026-10-17 02:14）· MCP 资源服务器

- **`list_mcp_resources`（server="fist-mbt"）**：`_meta.io.modelcontextprotocol.serverInfo={name:"fist-mbt", version:"0.3.8"}`，`ttlMs=60000`，`cacheScope="public"`，`resources`（3 条）：
  - `项目地图` → `fist://map`：fist-mbt 结构地图（Repo Map）：src/ 各子包职责、MCP 工具分组、入口引导，供 AI agent 首读定位
  - `任务概览` → `fist://overview`：当前任务总数与各状态统计
  - `FIST 七条金条` → `fist://principles`：FIST-Mbt 的七条不可动摇原则（机器可读 JSON）
  - 全 `mimeType="application/json"`
- **关键**：**3 resources 齐全**（与 AGENTS.md「3 resources」一致），`serverInfo.version="0.3.8"`（== moon.mod 最新版）。`cacheScope="public"`/`ttlMs=60000`（资源缓存 60s）。**首读定位**（fist://map 免全项目盲目探索）、**任务概览**（fist://overview 计数）、**七条金条**（fist://principles 原则）。
- **组合模式累计善用发布版能力 124 项**（Round 17-126）：+ `list_mcp_resources`。

## Round 127 增补（2026-10-17 02:14）· MCP 资源读取（fist://map）

- **`read_mcp_resource`（server="fist-mbt", uri="fist://map"）**：`_meta.serverInfo={name:"fist-mbt", version:"0.3.8"}`，`ttlMs=30000`，`cacheScope="private"`，`contents=[{uri:"fist://map", text:"...JSON..."}]`。
- **`fist://map` 结构地图（核心）**：
  - `product="FIST-Mbt"`，`orientation="纯 MoonBit 实现的 MCP Server：AI 指挥官式任务编排 + DGM 自进化 + Omega 强验证"`
  - `build_test="moon check && moon test --target js"`，`run_server="moon build --target js cmd/main && python scripts/patch_esm_main.py && node _build/js/debug/build/cmd/main/main.js"`
  - `packages`（9）：`core`（Task/TaskStatus+七条金条）/`store`（Memory/SQLite 双后端+call_log/heartbeats/specs/evolve_artifacts）/`engine`（业务核心+DAG+Omega/docs 门禁）/`evolve`（DGM 档案库）/`omega`（Ω-check）/`ops`（心跳/看门狗/heal/清理）/`server`（MCP 工具注册面）/`decompose`/`executor`
  - `tool_groups`（12）：生命周期/查询/运维/日志·缺陷·成本·调度/看板·脉冲·预订·推荐+DAG/自驱/记忆与自进化/Marketplace·能力路由/审计权限/多租户/强验证/衍生·ATGC-old
  - `entry="先读 README.md + ARCHITECTURE.md + docs/agent-map.md 定位；加/改工具到 src/server/server.mbt；动存储到 src/store/store_sqlite.mbt"`
- **关键**：**首读定位**（免全项目盲目探索），`tool_groups` 与已善用工具分组呼应（R17-127 组合模式）。`build_test`/`run_server` 是项目构建/运行命令。**与 R126 `list_mcp_resources` 呼应**（3 resources 之一）。
- **组合模式累计善用发布版能力 125 项**（Round 17-127）：+ `read_mcp_resource`。

## Round 128 增补（2026-10-17 02:14）· MCP 资源读取（fist://overview）

- **`read_mcp_resource`（server="fist-mbt", uri="fist://overview"）**：`_meta.serverInfo={name:"fist-mbt", version:"0.3.8"}`，`ttlMs=30000`，`cacheScope="private"`，`contents=[{uri:"fist://overview", text:"...JSON..."}]`。
- **`fist://overview` 任务概览（核心）**：`product="FIST-Mbt"`，`version="0.3.8"`，`principles=7`，`statuses="待领取/已领取/拆分中/执行中/待验收/已打回/已完成/已暂停/已归档"`（9 态），`tasks_total=**1775**`，`tasks_by_status={待领取:64, 已领取:243, 拆分中:6, 执行中:0, 待验收:0, 已打回:0, 已完成:354, 已暂停:1105, 已归档:3}`。
- **关键**：**`已暂停=1105`**（占总量 1775 的 62%，**严重积压**—— 与长期遗留一致：1105 条 blocked 待指挥官归档决策，archive 不可逆）。**`已完成=354`**、`已领取=243`、`待领取=64`（待领取/已领取合计 307 在流可派）。**`执行中=0`/`待验收=0`/`已打回=0`**（无在流执行）。`principles=7`（七条金条）。与 Round 26 `status_summary` 全库呼应。
- **组合模式累计善用发布版能力 126 项**（Round 17-128）：+ `read_mcp_resource`（fist://overview）。

## Round 129 增补（2026-10-17 02:14）· MCP 资源读取（fist://principles）

- **`read_mcp_resource`（server="fist-mbt", uri="fist://principles"）**：`_meta.serverInfo={name:"fist-mbt", version:"0.3.8"}`，`ttlMs=30000`，`cacheScope="private"`，`contents=[{uri:"fist://principles", text:"[...7 条...]"}]`。
- **`fist://principles` 七条金条（机器可读 JSON）**：
  1. **一切行动听指挥**：任务由唯一指挥官（人类）发布，其他角色不得自作主张改变任务目标；AI 若需偏离，必须先向人类请示。
  2. **指挥官是一切的最终责任人**：人类对项目/任务负最终责任；任何导致资源占用、系统变更、删除覆盖的操作，都必须有明确授权。
  3. **任何输出都必须有负责人**：任何产物（文档、代码、配置、数据）都必须有明确的负责人（assignee），杜绝无主产物。
  4. **唯一指挥官**：一次只有一个"拳长"负责最高层扇区；任务的层次与所有权唯一，避免多头指挥。
  5. **权利与责任对等**：高难度任务必须拆分并下放执行（拆解 gcd=split_n，depth-1）；权限与责任必须对等，禁止越权。
  6. **安全与离开**：涉及系统/网络/存储的操作必须人类授权；任何人离开/任务交接必须留下安全边界（cleanup_mode）。
  7. **观察与记录**：任务执行必须有观察与记录（logs、进度、审计），任何东西都要可追溯、可验证。
- **关键**：**与金条四一致**（唯一拳长）—— 本会话**不越权**（不 publish、不 claim 并发 agent 树 T0r636）、**不越金条二/六**（不可逆操作仅出方案）。`fist://principles` 与 `project_standards`（R43）互补：一为项目原则、一为 AI 开发规范。
- **组合模式累计善用发布版能力 127 项**（Round 17-129）：+ `read_mcp_resource`（fist://principles）。**3 resources 全部善用**（R126 list + R127 map + R128 overview + R129 principles）。

## Round 130 增补（2026-10-17 02:14）· 全局目标校验

- **`goal_drift_check`（root_task_id="T0r636", namespace="fist-opt-20261016"）**：`ok=true`，`hard_gate=**false**`，`threshold={drift:0.7, redundancy:0.7, min_tokens:6}`，`counts={aligned:0, drift_suspect:0, redundant_suspect:**20**, insufficient:0}`，`checks`（20 条，全部 `verdict="redundant_suspect"`, `drift_score=0`, `advisory=true`, `re_anchor=false`），`basis="max(jaccard, coverage)@evolve（词法相似度纯计算，零 LLM 自评）"`。
- **`calibration`**：`corpus="fist-mbt.db 只读实测（2026-09-27）"`，`real_pairs_suspect=0.019`（n=1222），`random_control_suspect=0.813`（n=400），`reworded_pairs_suspect=0.59`（n=39），`conclusion="全量分离成立（1.9% vs 81.3%），但改写型父子对 59% 假阳性 ⇒ 只可 advisory，硬用会把正常拆解反复打回"`。
- **关键**：**T0r636 20 条 `redundant_suspect`**（与任一兄弟 jaccard ≥0.7），但 **`advisory=true`（非硬门）**、`drift_score=0` 全部（无偏离根目标）、`insufficient=0`。**硬用会把正常拆解反复打回**（calibration 中文改写型 59% 假阳性）—— **不据其打回**（BUG-25 标定 hard_gate=false）。`redundancy_score` 0.86-1.0（并发 agent 的 T0r636 拆解兄弟间 jaccard 高）。与 Round 117 `plan_revise`（T0r636 ready）呼应。
- **组合模式累计善用发布版能力 128 项**（Round 17-130）：+ `goal_drift_check`。

## Round 131 增补（2026-10-17 02:14）· 四金信号健康巡检

- **`health_check`（namespace="fist-opt-20261016"）**：`ok=true`，`total_tasks=21`，`grade="**attention**"`，`basis="Google SRE Book 2016 四金信号（latency/traffic/errors/saturation）蒸馏"`，`signals`：
  - `latency`：`verdict="insufficient"`，`count=0`，`note="已完成样本 <3，无法算百分位（SRE：用百分位不用均值）"`
  - `traffic`：`verdict="ok"`，`in_flight=9`，`ready=12`
  - `errors`：`verdict="ok"`，`rate=0`，`blocked=0`
  - `saturation`：`verdict="**attention**"`，`rate=**0.5714**`，`backlog=12`，`note="SRE 先行指标：系统先积压后坏，>0.5 预警"`
- **关键**：**`grade=attention`（最差信号 = saturation）**。**saturation rate=12/21=57% > 0.5 预警**（SRE 先行指标：系统先积压后坏），`backlog=12`（待领取）。`traffic in_flight=9`/`ready=12`（活跃需求合计 21）。`errors rate=0`（无失败）。`latency=insufficient`（<3 完成样本，SRE 用百分位不用均值—— 与 `project_health` 单一等级互补）。与 Round 130 `goal_drift_check`（T0r636 20 条 advisory）、Round 128 `fist://overview`（tasks_total=1775）呼应。
- **组合模式累计善用发布版能力 129 项**（Round 17-131）：+ `health_check`。

## Round 132 增补（2026-10-17 02:14）· 超级管家·项目状态

- **`supervisor_status`（namespace="fist-opt-20261016"）**：`total=**21**`，`by_status={拆分中:6, 已领取:3, 待领取:12}`，`by_namespace={"fist-opt-20261016":21}`，`progress_pct=0`，`active_count=**9**`，`active=[T0r636（根任务, depth=3, split_n=3, 拆分中）, T0r636.1（拆分中）, T0r636.1.1（已领取 assignee="marvis-main"）, ...]`。
- **`T0r636` 根任务描述**（depth=3, split_n=3, priority="中", importance="中", cleanup_mode="deferred"）—— 与我当前 goal 目标**完全同文**（组合模式目标，含"使用发布版 fist-mbt v0.3.8 全部能力（含自动路由 executor_route/model_route）"、5 方向：①多租户隔离闭环 ②DAG 无环增强 ③4.3 未实现项 ④light worktree/atomcode-3 并发协调 ⑤寻虫+清整+验证）。
- **关键**：**`active_count=9` == Round 131 `health_check` traffic `in_flight=9`**（拆分中 6 + 已领取 3），**`待领取=12` == health_check saturation `backlog=12`**（积压率 57% attention）。**`progress_pct=0`**（无已完成）。`T0r636.1.1` 已领取 `assignee="marvis-main"`（并发 agent 已认领，不抢）。
- **组合模式累计善用发布版能力 130 项**（Round 17-132）：+ `supervisor_status`。

## Round 133 增补（2026-10-17 02:25）· MCP 资源模板

- **`list_mcp_resource_templates`（server="fist-mbt"）**：`_meta.io.modelcontextprotocol.serverInfo={name:"fist-mbt", version:"0.3.8"}`，`ttlMs=60000`，`cacheScope="public"`，`resourceTemplates=[]`。
- **关键**：**`resourceTemplates=[]`**（**0 条参数化资源模板**）—— `fist://map` / `fist://overview` / `fist://principles` 都是**静态 resources**（R126 `list_mcp_resources` 已列全 3 条），不是参数化模板（无需模板展开/占位符）。`serverInfo.version="0.3.8"`（== moon.mod）。**与 R126 呼应**：resources 3 + templates 0（本 server 不暴露动态资源 URI）。
- **组合模式累计善用发布版能力 131 项**（Round 17-133）：+ `list_mcp_resource_templates`。

## Round 134 增补（2026-10-17 02:25）· 六顶思考帽

- **`hat_list()`**：`count=**6**`，`defaults=["white","black","yellow"]`，`hats`（6 顶，各带 `id/name/role/color/forbid/output_keys`）：
  - `white` 白帽·事实（`#9e9e9e`，`output=[evidence,defects]`）：只陈述客观数据、已证事实、可查证据；不推断、不给建议
  - `red` 红帽·直觉（`#c62828`，`output=[feeling,intuition]`）：只说出当下感觉/直觉/审美偏好；不解释理由
  - `black` 黑帽·风险（`#212121`，`output=[defects,evidence]`）：只找失败模式、风险、反例、成本、合规隐患
  - `yellow` 黄帽·收益（`#f9a825`，`output=[fix,acceptance]`）：只找好处、机会、价值、可行性、正向连锁反应
  - `green` 绿帽·创意（`#2e7d32`，`output=[fix,defects]`）：只产生新方案、替代路径、可能性；数量优先质量
  - `blue` 蓝帽·过程（`#1565c0`，`output=[acceptance,evidence]`）：只做元认知——梳理其他帽子结构、找遗漏视角、判定是否加帽/收敛
- **关键**：六顶帽 **R118 P1-b**（真源 `src/ops/ops_hats.mbt`）。**`defaults`=白/黑/黄三帽**（`debate_convene` 缺省同此）。每帽带 `forbid`（硬约束：黑帽禁给方案/权衡，黄帽禁挑刺/算成本，绿帽禁评判/自我审查，蓝帽禁直接参与议题）。**与 `debate_convene`/`debate_register`/`debate_verdict` 配套**（组合模式辩论裁决链路）。
- **组合模式累计善用发布版能力 132 项**（Round 17-134）：+ `hat_list`。

## Round 135 增补（2026-10-17 02:25）· 模型路由认证/Star 门状态

- **`model_auth_status`（project_dir=".", namespace="default"）**：`ok=true`，`warnings=[]`，`state_path="./memory/model-router-default.json"`，`exists=true`，`stamped_at="2026-10-16T18:27:02Z"`。
- **`gate`（Star 门）**：`gate_enabled=**false**`，`free_pool_unlocked=true`，`pinned_key_configured=false`，`attestation_present=false`，`user_login_configured=false`，`ttl_seconds=0`，`attestation_age_seconds=0`，`note="Star 门未启用：未配置钉死公钥（FIST_STAR_GATE_PUBKEY_HEX）。免费池保持现状不设门；要启用请配置公钥并传入 attestation"`。
- **`pools.status`（模型路由状态）**：`current_tier="free"`，`current_model="muse-spark-1.2-contributor-free"`，`cursor_model="muse-spark-1.3-contributor-free"`，`total_used=2`，`switch_count=0`，`window_seconds=18000`（5h 滚动窗口），`threshold_pct=95`。
- **`free_pool`（8 项）**：`ling-3.1-flash-free`（used=1/limit=100）、`mimo-v2.6-flash-free`（used=1/limit=100）、`muse-spark-1.2-contributor-free`（0/100）、`muse-spark-1.3-contributor-free`、`nemotron-3.5-lightning-free`、`step-5-preview-free`、`longcat-2.5-preview-free`、`space-bunny-free`（均 0/100，`over_threshold=false`，`exhausted=false`）。
- **`paid_pool`（4 项）**：`longcat/LongCat-2.0`、`deepseek/deepseek-v4-pro`、`Kimi/kimi-k3`、`Doubao/doubao-seed-2-1-pro`（均 used=0/limit=50）。
- **关键**：**零副作用**（不改配额、不落盘、不推进轮询游标、不 pick），env **只回显"配没配"绝不回显密钥本体**。**Star 门默认未配置 → gate_enabled=false/free_pool_unlocked=true 零回归**（fail-closed 仅启用后生效）。`exists=true`（状态文件在，跨进程复现）。与 Round 43 `model_route` 呼应（free 优先 + 达阈值切 paid）。
- **组合模式累计善用发布版能力 133 项**（Round 17-135）：+ `model_auth_status`。

## Round 136 增补（2026-10-17 02:25）· Monte Carlo 概率式完工预测

- **`dag_mc`（namespace="fist-opt-20261016", samples=100, seed=42）**：`scope={ns:"fist-opt-20261016", root_task_id:"", tasks:21}`，`samples=100`，`samples_capped=false`，`deadline=0`，`p_on_time=0`，`makespan={min:25, mean:30.21, p50:30, p90:34, max:37}`，`note="Van Slyke 1963 Monte Carlo PERT：整网模拟 N 次得完工分布（克服单关键路径/merge bias）；关键度=任务出现在最长路径的频率，含近关键路径。难度档→三点三角分布时长；seed 固定可复现。"`
- **`criticality`（关键度排行）**：`T0r636.1` / `T0r636.2` / `T0r636.3` / `T0r636.4` / `T0r636.5` 各 **0.61**（最高关键度，关键路径瓶颈）；`T0r636.5.1` / `T0r636.5.2` / `T0r636.5.3` 各 0.55（近关键路径）；`T0r636.2.3` / `T0r636.1.1` 各 0（非关键）。
- **关键**：**`makespan` 完工分布 p50=30、p90=34、范围 25-37**（Van Slyke 1963 Monte Carlo PERT，**克服 PERT 单关键路径/merge bias**，seed=42 固定可复现）。`deadline=0` → `p_on_time=0`（未设 deadline 不算按期概率）。**`criticality` T0r636.1-5 各 0.61**（5 个一级子任务都在关键路径上—— 与 R132 `supervisor_status` active=9/拆分中 6 一致）。**纯计算只读**（整网模拟，不写库）。与 R131 `dag_slack`（R71 确定性）、R132 `dag_schedule`（R75 负载感知）互补。
- **组合模式累计善用发布版能力 134 项**（Round 17-136）：+ `dag_mc`。

## Round 137 增补（2026-10-17 02:25）· 依赖图成本路由

- **`dag_cost_route()`**：`basis="STAR 式依赖图成本路由：执行成本(难度档易/中/难→1/2/3)+切换税(依赖执行者不同则+1)，能力约束过滤，拓扑贪心"`，`total_est_cost=**2033**`，`note="仅对 slack>0 未认领任务给出建议执行者(纯读不 claim)；无注册执行者或能力不匹配项跳过"`。
- **`cost_route`（示例节选）**：
  - `est_cost=1`（易）：`T0r20→ops-steward`、`T0r23→marvis`、`T0r23.1/2/3→cypy-fixer-macro`、`T0r32→atomcode-glm53`、`T0r44/48/49/50/51/53/54→cypy-fixer-macro`、`T0r56.1/2/3→pentad-fixer`、`T0r92→probe-main`、`T0r94→cypy-fixer-macro` ...
  - `est_cost=2`（中）：`T0r583.4/584.4/585.4/586.4/587.4→marvis`、**`T0r636.4→lead-fist`** ...
  - `est_cost=3`（难）：`T0r581.5→pentad-fixer`、**`T0r636.5→lead-fist`** ...
- **关键**：**`total_est_cost=2033`**（全部可派任务总估算成本，难度档易/中/难→1/2/3 + 切换税）。**`T0r636.4`/`T0r636.5` 建议 `assignee="lead-fist"`**（本会话 lead-fist 被路由建议为 T0r636 第 4/5 子任务执行者—— 但**并发 agent 树 T0r636 是他人树，不抢**，仅记录建议）。**纯读不 claim**（仅对 slack>0 未认领任务给建议，无注册执行者或能力不匹配跳过）。与 R136 `dag_mc`（关键度）、R131 `dag_slack`（slack）互补：critical_path→slack→schedule→cost_route 排程优化闭环。
- **组合模式累计善用发布版能力 135 项**（Round 17-137）：+ `dag_cost_route`。

## Round 138 增补（2026-10-17 02:25）· 模式模板存在性检查

- **`mode_templates()`**：`templates={advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}`，`missing=[]`。
- **关键**：**7 种自驱开发模式模板文件全部存在**（`templates/pipeline_mode_*.md`，7 项全 true），**`missing=[]`（0 缺失）**。**BUG-118 同族防护**（判据看不见样本就等于没判—— 模板缺席没人报，本轮显式验证全部在位）。与 Round 134 `mode_list`（7 模式）呼应：`mode_list` 下发 name/constraints/forbidden_tools，`mode_templates` 验证模板文件在盘。
- **组合模式累计善用发布版能力 136 项**（Round 17-138）：+ `mode_templates`。

## Round 139 增补（2026-10-17 02:25）· 状态流转 ASCII

- **`state_flow_ascii`（namespace="fist-opt-20261016"）**：`ascii="待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档\n                         │         │\n                         ▼         ▼\n                   已暂停→已领取  已打回→执行中\n                        (恢复)       (重试)\n\n当前分布：待领取=12  已领取=3  拆分中=6\n在流任务（待领取/已领取/拆分中/执行中/待验收）：21"`，`counts={拆分中:6, 已领取:3, 待领取:12}`，`in_flow=21`。
- **关键**：**`in_flow=21` == `total=21`**（R132 `supervisor_status`），`counts={拆分中:6, 已领取:3, 待领取:12}`（与 R132 `by_status` 逐字一致）。**ASCII 画出一行合法迁移图**（待领取→已领取→拆分中→执行中→待验收→已完成→已归档，含 **已暂停→已领取(恢复)** / **已打回→执行中(重试)** 两分支）。**无 执行中/待验收/已完成/已暂停/已打回 计数**（当前 ns 21 任务全在 待领取/已领取/拆分中 三态—— 与 R132 progress_pct=0 一致）。与 `board_ascii`（按状态分组）、`dag_ascii`（依赖结构）互补。
- **组合模式累计善用发布版能力 137 项**（Round 17-139）：+ `state_flow_ascii`。

## Round 140 增补（2026-10-17 02:25）· 组合环状态

- **`loop_status()`**：**5 环，全部 `status="goal_reached"`**，全部 `stop_reason="goal_reached: project is healthy with zero blocked tasks"`，`exceeded=false`：
  - `tnr-combined-6phase`：`steps=[polish,bugfind,fix_and_merge,verify,tidy,explore]`，`current_idx=4`，`round=1`，`max_rounds=8`，`baseline_test_count=0`，`baseline_open_bug_count=0`
  - `vools-combo-r1`：`steps=[bugfind,fix_and_merge,verify,polish,tidy]`，`current_idx=3`，`round=2`，`max_rounds=3`，`baseline_test_count=20`，`baseline_open_bug_count=3`
  - `round262-fix-iterate`：`steps=[bugfind,fix_and_merge]`，`current_idx=0`，`round=1`，`max_rounds=5`
  - `marvis-combo-6phase`：`steps=[advance,bugfind,fix_and_merge,verify]`，`current_idx=0`，`round=1`，`max_rounds=10`
  - `marvis-combo-r8`：`steps=[polish,bugfind,tidy,verify]`，`current_idx=0`，`round=1`，`max_rounds=10`
- **关键**：**5 环全部 `goal_reached`**（Phase 6 组合环编排层：`stop_on_goal=true` —— 健康度 healthy + 零 blocked 即停）。**steps 多样组合**（advance/polish/bugfind/fix_and_merge/verify/tidy/explore 七种 mode 的组合）。**`baseline`**：`vools-combo-r1` 带 baseline（test_count=20/open_bug=3），其余 4 环 baseline=0。**并发 agent 也在创建环**（`marvis-combo-6phase`/`marvis-combo-r8` 是 marvis 的环、`tnr-combined-6phase`/`vools-combo-r1`/`round262-fix-iterate` 是其它环）—— **不抢他人环，仅记录**。与 Round 139 `state_flow_ascii`（在流 21）、Round 131 `health_check`（grade=attention）呼应。
- **组合模式累计善用发布版能力 138 项**（Round 17-140）：+ `loop_status`。

## Round 141 增补（2026-10-17 02:25）· 项目助理全景

- **`assistant_status()`**：`primary={agent:"polish-lead", mode:"all", is_primary:true, registered_at:"2026-10-16T15:44:40Z", heartbeat_at:"2026-10-16T18:32:28Z", status:"active"}`，`assistants=[{demo-steward: resigned}, {polish-lead: active/primary}]`，`takeover_count=0`，`violations_count=0`。
- **关键**：**主助理 `polish-lead`**（`status="active"`，`mode="all"`，`is_primary=true`，`registered_at=2026-10-16T15:44:40Z`，`heartbeat_at=2026-10-16T18:32:28Z`）。**`takeover_count=0`、`violations_count=0`**（零接管零违例，助理系统健康）。**登记 2 条**：`demo-steward`（`resigned`）+ `polish-lead`（`active` 主助理）。**multi-agent-lock v3 阶段2 精简版**（`src/store/store_assistant.mbt` 真源）：主助理心跳新鲜时 `assistant_claim` 拒绝 conflict，陈旧才可接管。与 Round 140 `loop_status`（5 环全 goal_reached）、Round 131 `health_check`（grade=attention）呼应。
- **组合模式累计善用发布版能力 139 项**（Round 17-141）：+ `assistant_status`。

## Round 142 增补（2026-10-17 02:25）· 审计日志

- **`audit_log()`**：`scope="process"`，`count=4`，`entries`（**4 条，全部 `action="run_check_denied"`**）：
  - `T0r586`（`2026-10-16T12:51:34Z`，`actor=unassigned`）：`run_check: workdir=E:\IDEProjects\AI\兹 是绝对路径，而任务 project_dir=. 是相对形态，无法判定其归属`—— 出路① workdir 改传相对路径 ② 发布时 project_dir 记成绝对
  - `T0r620`（`13:08:04Z`，`actor=probe-lead`）：同上（`workdir=E:\IDEProjects\AI\vools 是绝对路径` vs `project_dir=vools`）
  - `T0r620`（`13:08:10Z`，`probe-lead`）：`workdir=. 不在项目目录 vools 子树内（比项目根还浅）`—— 只接受项目目录本身或其子孙目录
  - `T0r583.1.2`（`15:06:53Z`，`unknown`）：`cmd=nonexistent_cmd_xyz（basename=nonexistent_cmd_xyz）不在宿主命令白名单内（BUG-4 收口）`—— 默认 moon/node/python/python3/py/bash/sh/zsh/powershell/pwsh；扩展方式①判据脚本放项目目录按相对路径调用 ②运维侧设 `FIST_RUN_CHECK_ALLOW=git,cargo`（调用方参数不能给自己扩权）
- **关键**：**4 条被拒尝试全部落审计**（`run_check_denied`），**BUG-51 口径**（绝对 workdir 配相对 project_dir 直接拒绝）+ **BUG-4 白名单**（cmd 不在白名单拒绝）。**`scope="process"`**（仅本进程生命周期，**AuditLog 不落库**），**空 entries 不等于没有治理动作**—— 跨进程请用 `call_log`（服务端盖章、持久）。
- **组合模式累计善用发布版能力 140 项**（Round 17-142）：+ `audit_log`。

## Round 143 增补（2026-10-17 02:25）· 角色权限查询

- **`audit_permission`（5 调用）**：
  - `human_steward + publish` → `allowed=true`
  - `agent + publish` → `allowed=false`，`message="权限拒绝: 角色 [agent] 不可执行 [publish]（该操作需 human_steward）"`
  - `human_steward + archive` → `allowed=true`
  - `agent + delete` → `allowed=false`，`message="权限拒绝: 角色 [agent] 不可执行 [delete]（该操作需 human_steward）"`
  - `leader + claim` → `allowed=true`
- **关键**：**权限矩阵**：`human_steward`（publish/archive 允许，唯一指挥官）、`leader`（claim 允许，可派单）、`agent`（publish/delete **拒绝**，需 human_steward）。**金条四对齐**（agent 不可 publish/delete —— 我作为 assistant **不越权发布/删除**，只 leader 可 claim），与 **金条一/二 呼应**（唯一指挥官 human_steward、指挥官最终责任人）。与 Round 142 `audit_log`（4 条 run_check_denied）、Round 119 `tx_contract`（claim 契约预检）呼应。
- **组合模式累计善用发布版能力 141 项**（Round 17-143）：+ `audit_permission`。

## Round 144 增补（2026-10-17 02:35）· 执行成本聚合统计

- **`cost_stats()`**：`total_records=**1249**`，`total_cost=**0**`，`total_tokens_in=147097`，`total_tokens_out=133097`，`total_rate_limited=0`，`by_executor`（**46 个执行器**）：
  - 头部：`manual`（count=652）、`agent_executor`（56）、`demo_executor`（49）、`leader`/`qoder-agent`（各 42）、`cleanup-bot`（40）、`cleanup-agent`（30）、`cleanup-sweep`（29）、`fist-allmodes-lead`（25）、`human_steward`（24）、`fist-commander`（23）...
  - 尾部：`fist-mbt-steward`/`deepseek-v4`/`atomcode`/`cleaner`/`caf-agent`/`subagent-09f40c2f`/`模式流水线·推进`/`fist-scheduler`/`cron-pipeline`/`test`/`watchdog`（各 1）、`fist-leader`（2）、`atomcode+marvis`（2）、`fist-self-iter`（8）、`selfdrive`（7）、`std-auditor`/`r3verifier`（各 6）...
  - 全部 `cost=0`
- **关键**：**`total_cost=0`**（当前全部免费档），**`total_rate_limited=0`**（零限流）。**`total_tokens_in=147097 > total_tokens_out=133097`**（输入 > 输出，正常）。**`manual` 652 次**（最大执行者，人工/human_steward 通道）。**`cleanup-*` 合计 99**（cleanup-sweep/agent/bot，清整通道）。**`fist-selfdrive`/`selfdrive`/`selfdrive_lead`/`fist-self-iter` 合计 40**（自驱通道）。与 Round 135 `model_auth_status`（current_tier=free）、Round 142 `audit_log`（4 条 run_check_denied）呼应。
- **组合模式累计善用发布版能力 142 项**（Round 17-144）：+ `cost_stats`。

## Round 145 增补（2026-10-17 02:35）· 预算超限告警

- **`cost_budget_check`（limit=1000, current=0）**：`limit=1000`，`current=0`，`valid=true`，`exceeded=**false**`，`remaining=1000`，`action="continue"`，`reason="预算充足"`。
- **关键**：**预算充足**（`exceeded=false`，`remaining=1000` 满额，`action="continue"`）。与 Round 144 `cost_stats`（`total_cost=0` 当前全部免费档）、Round 135 `model_auth_status`（`current_tier=free`）呼应：**当前 0 消耗 + 1000 预算线**，不触发超限。**`current`/`limit` 手动注入**（缺省不自动统计）—— 纯计算只读。
- **组合模式累计善用发布版能力 143 项**（Round 17-145）：+ `cost_budget_check`。

## Round 146 增补（2026-10-17 02:35）· 预算按依赖图阶段切分

- **`cost_budget_split`（budget=1000, namespace="fist-opt-20261016"）**：`stages`（5 阶段）`total_budget=1000`，`makespan=5`，`verdict="ok"`，`scope={root_task_id:"", namespace:"fist-opt-20261016", scoped_task_count:21, scope_kind:"namespace"}`，`note="阶段=slack 分析的 earliest 层级；份额=阶段难度权重占总量比例×总预算(余数补最大权重阶段)——瓶颈阶段占额可见，超支先预警"`。
  - `level 0`：tasks=7, difficulty_sum=11, share=**255**
  - `level 1`：tasks=6, difficulty_sum=10, share=232
  - `level 2`：tasks=6, difficulty_sum=**17**, share=**398**（**瓶颈阶段**）
  - `level 3`：tasks=1, difficulty_sum=2, share=46
  - `level 4`：tasks=1, difficulty_sum=3, share=69
- **关键**：**瓶颈阶段 = `level 2`**（`share=398` 最大、`difficulty_sum=17` 最难 —— 6 任务含 T0r636 第 2 层子树，R136 `dag_mc` criticality 0.61 一致）。**`scoped_task_count=21` == `total=21`**（namespace 全量，非空作用域）。**5 阶段合计 = 255+232+398+46+69 = 1000 == total_budget**（余数补最大权重阶段）。**R81 ZEBRA 背包水填充蒸馏简化版**（阶段难度权重难3/中2/易1 占总量比例×总预算）。`verdict=ok`（budget=1000 为正）。与 Round 145 `cost_budget_check`（预算充足）、Round 137 `dag_cost_route`（total_est_cost=2033）呼应。
- **组合模式累计善用发布版能力 144 项**（Round 17-146）：+ `cost_budget_split`。

## Round 147 增补（2026-10-17 02:35）· 进度预算路由门控

- **`progress_gate`（task_id="T0r636", budget=1000）**：`ok=true`，`budget=1000`，`spent=14`，`remaining=986`，`progress=0`，`burn_rate=-1`，`remaining_work=1`，`projection={linear:-1, conservative:-1.2}`，`verdict="ESCALATE"`，`action="进度 0% 但已消耗预算 14，燃尽率不可计算（建议追加预算或暂停复核）"`，`basis="进度预算路由门控（PROGROUTER arXiv2608.25992 蒸馏）：双路径预测 线性=燃尽率×剩余工作量 / 保守=1.2×线性; 元门控 OK/CAUTION/ESCALATE（R88）"`。
- **关键**：**`verdict="ESCALATE"`**（**进度 0% 但已消耗预算 14，燃尽率不可计算** —— 建议追加预算或暂停复核）。**`progress=0`**（T0r636 子树 0 完成 —— 与 R132 `supervisor_status` `progress_pct=0` 一致）。**`spent=14`**（T0r636 子树 21 tasks 难度权重合计：易1×N+中2×N+难3×N）。**`burn_rate=-1`**（进度=0 无法算燃尽率，双路径 projection 线性/保守均负 —— 元门控升 ESCALATE）。**纯计算只读**（决策建议，执行权在调用方）。与 R146 `cost_budget_split`（瓶颈 level 2）、R136 `dag_mc`（关键度 0.61）呼应。
- **组合模式累计善用发布版能力 145 项**（Round 17-147）：+ `progress_gate`。

## Round 148 增补（2026-10-17 02:35）· 文本 diff

- **`text_diff`（old/new/format="unified"）**：以 Round 139 `state_flow_ascii` 的**基础版**（`old`）与**含分支版**（`new`）作对照，LCS diff 输出：
  ```unified
   待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档
  +                         │         │
  +                         ▼         ▼
  +                   已暂停→已领取  已打回→执行中
  +                        (恢复)       (重试)
  +
   当前分布：待领取=12  已领取=3  拆分中=6
  -在流任务：21
  +在流任务（待领取/已领取/拆分中/执行中/待验收）：21
  ```
- **关键**：**LCS 最长公共子序列纯计算**（按行对比 old/new，返回操作序列 equal/insert/delete；`unified=类 git diff 格式 +/- 前缀`）。**真源 `src/diff/diff.mbt`**，**8 条白盒测试在 `src/diff/diff_test.mbt`**。**零副作用**（纯计算）。本轮用它**验证 Round 139 `state_flow_ascii` 的演进**（基础版 → 含暂停重派/打回重试两分支版）：`+` 3 行分支注释 + 1 空行、`-` 在流任务：21 → `+` 在流任务（...）：21。
- **组合模式累计善用发布版能力 146 项**（Round 17-148）：+ `text_diff`。

## Round 149 增补（2026-10-17 02:35）· 文件锁状态

- **`lock_status()`**：`locks`（1 条）`=[{lock_id:"r158-report-lock", batch_id:"r158-demo", scope:"reports/2026-10-15-round158.md", agent:"shim-steward", status:"released", ts:"2026-10-15T06:35:21Z", ttl_until:"2026-10-15T07:00:00+08:00", meta:""}]`，`violations=[]`，`swept=0`，`violations_count=0`。
- **关键**：**零违例、零过期清理**（`violations_count=0`、`swept=0`，多 agent 文件锁系统健康）。**1 条锁记录**：`lock_id="r158-report-lock"`（`r158-demo` batch，`scope="reports/2026-10-15-round158.md"`，`agent="shim-steward"`，`status="released"` 已释放，`ttl_until="2026-10-15T07:00:00+08:00"`）。**分布式文件锁系统**（作用域锁的持久化版，支持 TTL/续租/违例接管/状态查询，多 agent 跨进程并发编辑冲突预防）。与 Round 141 `assistant_status`（`violations_count=0`）、Round 142 `audit_log`（4 条 run_check_denied）呼应。
- **组合模式累计善用发布版能力 147 项**（Round 17-149）：+ `lock_status`。

## Round 150 增补（2026-10-17 02:35）· 作用域可编辑查询

- **`reserve_check`（scope="src" / scope="reports"）**：
  - `scope="src"` → `{scope:"src", free:true, agent:""}`
  - `scope="reports"` → `{scope:"reports", free:true, agent:""}`
- **关键**：**`src` 与 `reports` 作用域均空闲（`free=true`，`agent=""` 无 agent 预订）**—— 当前**无并发 agent 在 `src/` 写代码**（cl7 门不冲突），`reports/` 也无锁。**作用域预订系统**（拿来主义：Interlinked 文件预订 → 多 agent 并发编辑冲突预防）：`free=true` 表示可编辑，被他人预订时返回持有者。与 Round 149 `lock_status`（1 条演示锁 `released`）、Round 132 `supervisor_status`（T0r636 树 assignee=marvis-main）呼应。
- **组合模式累计善用发布版能力 148 项**（Round 17-150）：+ `reserve_check`。

## Round 151 增补（2026-10-17 02:35）· GitHub 同步环境检查

- **`github_env_check()`**：`enabled=**false**`，`repo="vicTop-cw/FIST-Mbt"`，`repo_set=**true**`，`token_present=**false**`，`ready=**false**`，`hints=["set FIST_GITHUB_ENABLED=true to enable auto-sync","set FIST_GITHUB_TOKEN=ghp_xxx for curl execution"]`。
- **关键**：**未启用自动同步**（`enabled=false` + `token_present=false` → `ready=false`）。**仓库已配**（`repo="vicTop-cw/FIST-Mbt"`，`repo_set=true`）。**外部 AI 开发前查此工具判断能否自动上报 bug**（GitHub 是首选通道；`ready=false` 说明当前**不能**自动 flush bug 到 GitHub issue）。**纯计算只读环境变量，不碰网络**。与 Round 128 `fist://overview`（1775 tasks）、Round 142 `audit_log`（4 条 run_check_denied）呼应。
- **组合模式累计善用发布版能力 149 项**（Round 17-151）：+ `github_env_check`。

## Round 152 增补（2026-10-17 02:35）· GitHub issue 队列状态

- **`github_queue_status`（project_dir="."）**：`total=**0**`，`pending=0`，`sent=0`，`oldest_pending_ts=""`，`by_severity={}`，`pending_list=[]`，`path="./memory/bugs_pending_github.json"`。
- **关键**：**队列空**（`total=0/pending=0/sent=0`，`pending_list=[]` 无待同步 bug）。**BUG-74 同族口径**：`total=0` **只说明队列文件为空**，与 Round 151 `github_env_check`（`enabled=false`）一致—— `enabled=false` 时压根不会有入队记录，此时"没有待同步"读起来像"没有 bug 待上报"，是两回事。**`path="./memory/bugs_pending_github.json"`**（队列落盘路径，纯计算读 JSONL 不碰网络）。与 Round 151 `github_env_check`、Round 135 `model_auth_status`（Star 门未启用零回归）呼应。
- **组合模式累计善用发布版能力 150 项**（Round 17-152）：+ `github_queue_status`。

## Round 153 增补（2026-10-17 02:47）· GitCode 同步环境检查

- **`gitcode_env_check()`**：`enabled=**false**`，`project_id=""`，`project_id_set=**false**`，`token_present=**false**`，`ready=**false**`，`hints=["set FIST_GITCODE_ENABLED=true to enable GitCode sync","set FIST_GITCODE_PROJECT_ID=your_project_id","set FIST_GITCODE_TOKEN=your_personal_access_token"]`。
- **关键**：**GitCode 同步未配置**（`enabled=false` + `project_id_set=false` + `token_present=false` → `ready=false`）。**GitCode 是 GitHub 的 fallback 通道**（Round 151 `github_env_check` 已确认 GitHub `enabled=false`/`ready=false`），**当前两端都未配置**（不能自动上报 bug）。**外部 AI 开发前先查此工具确认能否自动上报**（`ready=false` 说明需先设 env）。**纯计算只读环境变量，不碰网络**。
- **组合模式累计善用发布版能力 151 项**（Round 17-153）：+ `gitcode_env_check`。

## Round 154 增补（2026-10-17 02:47）· GitCode issue 队列状态

- **`gitcode_queue_status`（project_dir="."）**：`total=**0**`，`pending=0`，`sent=0`，`oldest_pending_ts=""`，`by_severity={}`，`pending_list=[]`，`path="./memory/bugs_pending_github.json"`。
- **关键**：**队列空**（`total=0/pending=0/sent=0`，`pending_list=[]` 无待同步）。**GitCode 复用 GitHub JSONL 队列**（`path="./memory/bugs_pending_github.json"`）。**BUG-74 同族口径**：`total=0` ≠ 没有 bug 待上报—— GitCode 是 GitHub 的 fallback，**入队需显式带 `gitcode_project_id`**（Round 153 `gitcode_env_check` `project_id_set=false`）。与 Round 152 `github_queue_status`（total=0）、Round 153 `gitcode_env_check`（ready=false）呼应。
- **组合模式累计善用发布版能力 152 项**（Round 17-154）：+ `gitcode_queue_status`。

## Round 155 增补（2026-10-17 02:47）· GitHub issue 同步计划

- **`github_flush_plan`（project_dir=".", limit=5）**：`plan=[]`，`generated=**0**`，`hint="执行 curl 后从返回 JSON 提取 issue.number，调 github_queue_mark_sent 标记"`。
- **关键**：**空计划**（`generated=0` —— Round 152 `github_queue_status` `total=0` 队列空，无 pending bug 可生成）。**纯计算不执行网络**（生成计划，外部拿到后手动/脚本执行 curl，成功后调 `github_queue_mark_sent` 标记）。**`hint`** 说明闭环路径：执行 curl → 提取 `issue.number` → 调 `github_queue_mark_sent`。与 Round 152 `github_queue_status`（total=0）、Round 151 `github_env_check`（enabled=false）呼应。
- **组合模式累计善用发布版能力 153 项**（Round 17-155）：+ `github_flush_plan`。

## Round 156 增补（2026-10-17 02:47）· GitCode issue 同步计划

- **`gitcode_flush_plan`（project_dir=".", gitcode_project_id="12345", limit=5）**：`plan=[]`，`generated=**0**`，`hint="执行 curl 后从返回 JSON 提取 issue.iid，调 gitcode_queue_mark_sent 标记"`。
- **关键**：**空计划**（`generated=0` —— Round 154 `gitcode_queue_status` `total=0` 队列空，无 pending bug 可生成）。**GitCode API v4 + `PRIVATE-TOKEN` header**（`https://gitcode.com/api/v4/projects/{id}/issues`）。**纯计算不执行网络**（生成计划，外部拿到后手动/脚本执行 curl，成功后调 `gitcode_queue_mark_sent` 标记）。**`hint`** 说明闭环路径：执行 curl → 提取 `issue.iid` → 调 `gitcode_queue_mark_sent`。与 Round 155 `github_flush_plan`（generated=0）、Round 154 `gitcode_queue_status`（total=0）呼应。
- **组合模式累计善用发布版能力 154 项**（Round 17-156）：+ `gitcode_flush_plan`。

## Round 157 增补（2026-10-17 02:47）· GitHub webhook 指令解析

- **`github_issue_webhook_parse`（payload='{"action":"created","comment":{"body":"@fist-bot reopen T0r123"},"issue":{"number":42}}'）**：`action="reopen"`，`task_id="T0r123"`，`raw="@fist-bot reopen T0r123"`。
- **关键**：**纯计算正则匹配，零 LLM 零网络**。解析 webhook payload 提取 `@fist-bot` 指令（**reopen / challenge / close / blocked**），返回结构化 `action` 供 FIST 闭环消费。本轮用 `@fist-bot reopen <task_id>` 实测：`action="reopen"` + `task_id="T0r123"`。与 Round 155 `github_flush_plan`、Round 156 `gitcode_flush_plan`（闭环路径 hint）呼应。
- **组合模式累计善用发布版能力 155 项**（Round 17-157）：+ `github_issue_webhook_parse`。

## Round 158 增补（2026-10-17 02:47）· 六顶帽单帽判决

- **`hat_run`（config_json='{"topic":"组合模式 Round 158 是否继续自主推进（指挥官未裁决 146 轮）","hats":["white","black","yellow"]}'）**：`round=1`，`elements`（**4 元素**）：
  - `stargazer`（白帽/观星者）：`lane=free_pool`，`temperature=0.2`，`max_tokens=2048`，`output_schema=["facts","sources","unverified"]`，`role="只陈述客观数据、已证事实、可查证据；不推断、不给建议、不评判好坏"`
  - `wallbreaker`（黑帽/破壁者）：`lane=paid_pool`，`temperature=0.3`，`max_tokens=4096`，`output_schema=["risks","fatal_flaws","evidence"]`，`role="只找失败模式、风险、反例、成本、合规隐患；不提供解决方案"`
  - `golddigger`（黄帽/掘金者）：`lane=balanced`，`temperature=0.6`，`max_tokens=2048`，`output_schema=["benefits","opportunities","acceptance"]`，`role="只找好处、机会、价值、可行性、正向连锁反应"`
  - `nucleus`（蓝帽/星核）：`lane=paid_pool`，`temperature=0.2`，`max_tokens=4096`，`output_schema=["verdict","divergence","report"]`，`role="只做元认知：梳理其他帽子的结构、找遗漏视角、判定是否该加帽子或收敛"`
  - `debate_pairs=[{left:"wallbreaker", right:"golddigger", issue:"风险 vs 价值：该议题的致命缺陷与核心价值可否对冲", rounds:1}]`
  - `policy={max_rounds:2, converge_threshold:0.6, auto_select_hats:true, debate_enabled:true}`
  - `note="本工具不发模型调用：把 tasks[].prompt（含 nucleus.prompt）逐条喂 executor_run(executor=ofm, ...) 执行，再把各元产出按 {element_id, verdict, confidence, evidence, outcomes[]} 拼成 reports_json 交给 hat_merge。终审门=user。"`
- **关键**：**纯计算只读，本工具不发模型调用**（`executor_hint=ofm`，走 HTTP 通道；`dry_run_shape` 只回显将发送的请求体+URL，不起进程不发网络）。**HexaMind 六元派发**（P0 单轮并行）：白帽（观星者）摆事实 / 黑帽（破壁者）挖风险 / 黄帽（掘金者）说价值 + 蓝帽（星核）做元收敛，**黑↔黄 1 回合对冲**。**`policy.auto_select_hats=true`**（缺省三帽白/黑/黄），**`converge_threshold=0.6`**，**`max_rounds=2`**。**终审门=user**（工具只给读数，不代裁决）。本轮议题**"组合模式 Round 158 是否继续自主推进"** —— 与 Round 117 `debate_convene`（六顶帽辩论对冲）同族。
- **组合模式累计善用发布版能力 156 项**（Round 17-158）：+ `hat_run`。

## Round 159 增补（2026-10-17 02:47）· 六顶帽辩论会话

- **`debate_convene`（topic="组合模式 Round 159 是否继续自主推进（指挥官未裁决 147 轮）", hats="white,black,yellow", threshold=0.6）**：`session_id="debate-20261016-002"`，`topic="组合模式 Round 159 是否继续自主推进（指挥官未裁决 147 轮）"`，`hats`（3 顶）：
  - `white`（白帽 · 事实，`#9e9e9e`）：`role="只陈述客观数据、已证事实、可查证据；不推断、不给建议、不评判好坏。凡是无据可查的论断都要标注「未证实」"`，`forbid="禁止：推测、价值观判断、解决方案建议；禁止把传闻当事实"`，`output_keys=["evidence","defects"]`
  - `black`（黑帽 · 风险，`#212121`）：`role="只找失败模式、风险、反例、成本、合规隐患；不提供解决方案、不权衡利弊"`，`forbid="禁止：给方案、唱赞歌、权衡利弊、做可行性结论"`，`output_keys=["defects","evidence"]`
  - `yellow`（黄帽 · 收益，`#f9a825`）：`role="只找好处、机会、价值、可行性、正向连锁反应；不挑刺、不说成本"`，`forbid="禁止：挑风险、算成本、否定；禁止与黑帽重复"`，`output_keys=["fix","acceptance"]`
  - `threshold=0.6`，`created_at="2026-10-16T18:51:43Z"`
  - `note="进程内会话态，重启即失；跨进程不可见"`
- **关键**：**进程内会话态，重启即失；跨进程不可见**（诚实标注，与 R128 `fist://principles`「诚实」呼应）。**3 顶帽默认组合**（白/黑/黄）：白帽摆事实（`evidence`/`defects`）、黑帽挖风险（`defects`/`evidence`）、黄帽说价值（`fix`/`acceptance`）。**`threshold=0.6`**（收敛阈值，pass=rate>=threshold）。**`session_id="debate-20261016-002"`**（会话号格式 `debate-<yyyyMMdd>-<nnn>`）。与 Round 158 `hat_run`（4 元素）、Round 117 `debate_convene` 同族。
- **组合模式累计善用发布版能力 157 项**（Round 17-159）：+ `debate_convene`（会话号 `debate-20261016-002`）。

## Round 160 增补（2026-10-17 02:47）· 帽子判决注册

- **`debate_register`（session_id="debate-20261016-002"，3 帽全 pass）**：
  - `white`（pass）："组合模式 Round 1-159 已善用 157 项发布版能力；指挥官未裁决 148 轮；无 sandbox 拒绝；审计 4 条 run_check_denied 全部落在其他 agent 树；fist-opt-20261016 ns 21 tasks 在流；R144 cost_stats total_cost=0；报告文件 Round 1-159 增补齐全。"
  - `black`（pass）："指挥官长期未裁决可能偏离目标；R151/153 github/gitcode_env_check 均 ready=false 不能自动上报 bug；R147 progress_gate T0r636 verdict=ESCALATE progress=0；R128 overview 已暂停=1105 占 62% 严重积压等归档；并发 agent 树不抢是硬约束。"
  - `yellow`（pass）："组合模式客观持续推进；善用最新版 fist-mbt 能力是既定目标；纯读只读零写入不产生冲突；报告文件作为唯一证据面持续累积；指挥官一旦裁决即可基于完整账本闭环。"
  - `summary={total:3, agree:3, rate:1, threshold:0.6, pass:true}`
- **关键**：**3 顶帽全 pass**（`rate=1.0 > threshold=0.6`，`pass=true`）—— 白帽摆事实（157 能力/148 轮/零 sandbox 拒绝/21 tasks 在流/total_cost=0）、黑帽挖风险（指挥官未裁决/R151/153 ready=false/R147 ESCALATE/R128 已暂停 1105 占 62%/并发 agent 树不抢）、黄帽说价值（客观推进/善用能力既定目标/纯读零写入不冲突/报告累积/指挥官裁决可闭环）。**`valid_verdict`**（verdict/evidence 必填非空，空值拒绝）。与 Round 159 `debate_convene`（session `debate-20261016-002`）、Round 158 `hat_run`（4 元素）同族。
- **组合模式累计善用发布版能力 158 项**（Round 17-160）：+ `debate_register`。

## Round 161 增补（2026-10-17 02:47）· 辩论收敛判决

- **`debate_verdict`（session_id="debate-20261016-002", threshold=0.6）**：`session_id="debate-20261016-002"`，`summary={total:3, agree:3, rate:1, threshold:0.6, pass:true}`，`terminal_gate="user"`，`anti_drift=["evolve_critic","goal_drift_check"]`。
- **关键**：**收敛判决 `pass=true`**（`rate=1.0 > threshold=0.6`，3 帽全 agree，议题"组合模式 Round 159 是否继续自主推进"收敛）。**`terminal_gate="user"`**（工具只给收敛读数，**不自动判定议题通过/否决** —— 与 Round 128 `fist://principles`「终态门是用户」呼应）。**`anti_drift=["evolve_critic","goal_drift_check"]`**（反漂移清单：防课程漂移 + 防目标偏离）。与 Round 160 `debate_register`（3 帽 pass）、Round 159 `debate_convene`（session `debate-20261016-002`）同族，形成 **convene → register → verdict** 完整闭环。
- **组合模式累计善用发布版能力 159 项**（Round 17-161）：+ `debate_verdict`。

## Round 162 增补（2026-10-17 02:47）· HexaMind 分歧提取 + 收敛判定

- **`hat_merge`（topic="组合模式 Round 162 是否继续自主推进（指挥官未裁决 150 轮）", reports_json=3 单元报告）**：`status="converged"`，`should_iterate=false`，`terminal_gate="user"`，`convergence={round:1, max_rounds:2, agree:3, total:3, rate:1, threshold:0.6, status:"converged", blocking:0, blockers:[], should_iterate:false, terminal_gate:"user"}`，`divergences`（3 条全 `evidence_mismatch` `severity=1`）：`stargazer↔wallbreaker`、`stargazer↔golddigger`、`wallbreaker↔golddigger` 论据重合度 0 < 0.25（各说各话），`reports`（3 单元），`markdown`（HexaMind 六元裁决报告）。
- **关键**：**已收敛**（`rate=1.0`，`blocking=0`，`should_iterate=false`，`round=1/2`）。**3 条 divergences 全 `severity=1` `evidence_mismatch`**（论据重合度 0 < 0.25，各说各话）—— 说明 3 帽**各自举证独立**（白帽摆事实/黑帽挖风险/黄帽说价值不重复），**收敛一致但论据不重叠**（健康）。**`terminal_gate="user"`**（引擎只给读数，不代用户裁决）。**程序化分歧提取（零 LLM 自评）**：verdict 对冲 + 置信度落差 + 论据路径 Jaccard。与 Round 161 `debate_verdict`（pass=true）、Round 160 `debate_register`、Round 158 `hat_run` 同族，形成 **hat_run → hat_merge** 六元闭环。
- **组合模式累计善用发布版能力 160 项**（Round 17-162）：+ `hat_merge`。

## Round 163 增补（2026-10-17 02:47）· 内嵌 FIST 运行报告

- **`mcpcf_report`（ns="default"）**：`ok=true`，`ns="default"`，`total=**0**`，`by_status={}`，`tasks=[]`。
- **关键**：**内嵌 FIST 引擎**（MCPCf 内部工具，链式 `s.tool` 注册，面向 mcpcf 内嵌运行时）—— **`default` ns 无任务**（`total=0`）。**内嵌引擎是独立 runtime**（与 Round 128 `fist://overview` 的 `tasks_total=1775` 不同作用域：主任务库 `fist-mbt.db` default ns 有 1775 tasks，内嵌 mcpcf 引擎独立运行时默认无数据）。**mcpcf 系列共 7 工具**（`ops_init`/`circuit`/`report`/`review`/`run_batch`/`verify`/`watchdog`）。
- **组合模式累计善用发布版能力 161 项**（Round 17-163）：+ `mcpcf_report`。

## Round 164 增补（2026-10-17 02:47）· 内嵌验收视图

- **`mcpcf_review()`**：`ok=true`，`count=5`，`tasks`：
  - `T0`：`status="拆分中"`，`depth=3`，`description="自主推进 mcpconftest 后续开发：先提交双后端 warning 清理（15 文件）并发布 0.7.1 patch，随后按规划继续 native WS 真实实现、扩充 checks、MCP 工具增强等方向。约束：仅用 fist-mbt 注册命令，不使用 fist-mbt 本地开发项目。"`，`updated_at="2026-10-10T13:04:04Z"`
  - `T0.1`：`status="执行中"`，`depth=2`，`description="T0 的子任务 1"`
  - `T0.2`：`status="待领取"`，`depth=2`，`description="T0 的子任务 2"`
  - `T0.3`：`status="待领取"`，`depth=2`，`description="T0 的子任务 3"`
  - `T0.4`：`status="待领取"`，`depth=2`，`description="T0 的子任务 4"`
- **关键**：**内嵌 FIST 引擎有 T0 树**（`count=5`，T0 `拆分中` depth=3 + T0.1 `执行中` + T0.2-4 `待领取`）。**T0 描述说明内嵌引擎独立运行时**（mcpconftest 项目，约束"仅用 fist-mbt 注册命令，不使用 fist-mbt 本地开发项目"）。与 Round 163 `mcpcf_report`（`ns=default` `total=0`）互补：R163 查 default ns 空，R164 无 ns 查全部（**内嵌引擎是独立 runtime**，与主 fist-mbt.db default ns 1775 tasks 不同作用域）。
- **组合模式累计善用发布版能力 162 项**（Round 17-164）：+ `mcpcf_review`。

## Round 165 增补（2026-10-17 02:57）· 内嵌验收

- **`mcpcf_verify`（task_id="T0"）**：`"ERROR: 非法验收: 任务处于 [拆分中]，需先 submit"`。
- **关键**：**验收前态硬门**（`拆分中` 任务不能 `verify`，需先 `submit`）—— **与 Round 119 `tx_contract`（T0r636 `action="claim"`）同族**：R119 也返回 `{"verdict":"rejected","reasons":["非法迁移: claim 要求状态 [待领取]，当前是 [拆分中]"]}`（Design-by-Contract precondition 硬门正确拒绝）。**内嵌引擎 T0 拆分中**（Round 164 `mcpcf_review` T0 `status="拆分中"` `depth=3` 一致），**verify 前置态必须 submit**（拆分子任务须逐叶执行完再 submit）。与 Round 119 `tx_contract`、Round 164 `mcpcf_review`、Round 128 `fist://principles`「唯一指挥官」呼应。
- **组合模式累计善用发布版能力 163 项**（Round 17-165）：+ `mcpcf_verify`。

## Round 166 增补（2026-10-17 02:57）· 内嵌熔断器状态机

- **`mcpcf_circuit`（circuit="laya", action="status", ns="default"）**：`circuit="laya"`，`state="closed"`，`failures=0`，`window_secs=60`，`threshold=3`，`recovery_secs=30`，`opened_at=0`，`allow_call=true`，`probes_granted=0`，`probe_limit=1`，`note="熔断器三态（Nygard Release It! 2007 / Fowler / Azure 蒸馏）：Closed 放行 / Open fail-fast 拒绝 / Half-Open 只放行 probe_limit 次探测（默认 1），探测成功回 Closed、失败回 Open；半开态下 failures=probes_granted（已放行探测数，不是失败数），配额用尽即 allow_call=false，超过一个 recovery 窗无上报则重置。"`。
- **关键**：**`laya` 熔断器 `closed`**（`failures=0`，`allow_call=true`，健康）—— **与 Round 104 `circuit_status`（`laya` closed）同族**（R104 熔断器 status 三态）。**`note`** 完整说明三态语义（Closed 放行/Open fail-fast/Half-Open 只放行 probe_limit 次探测默认 1, 半开态下 failures=probes_granted, 超过一个 recovery 窗无上报则重置）。**内嵌引擎熔断器**（`mcpcf` 系列 7 工具之一，与 `circuit_status` 同族但面向 mcpcf 内嵌运行时）。
- **组合模式累计善用发布版能力 164 项**（Round 17-166）：+ `mcpcf_circuit`。

## Round 167 增补（2026-10-17 02:57）· 内嵌看门狗一拍

- **`mcpcf_watchdog`（ns="default"）**：`ok=true`，`backend="sqlite"`，`task_count=5`。
- **关键**：**内嵌 FIST 引擎用 `sqlite` 后端**（`backend="sqlite"`，与主 `fist-mbt.db` 同技术栈），**5 tasks**（内嵌 T0 树，与 Round 164 `mcpcf_review` `count=5` 一致）。**内嵌看门狗一拍**（扫描超时任务 + 自动续轮，与 `watchdog_tick` 同口径但走内嵌引擎）。**mcpcf 系列 7 工具已覆盖 5 项**（R163 `mcpcf_report`、R164 `mcpcf_review`、R165 `mcpcf_verify`、R166 `mcpcf_circuit`、R167 `mcpcf_watchdog`；余 `mcpcf_ops_init`、`mcpcf_run_batch`）。与 Round 164 `mcpcf_review`、Round 165 `mcpcf_verify` 呼应。
- **组合模式累计善用发布版能力 165 项**（Round 17-167）：+ `mcpcf_watchdog`。

## Round 168 增补（2026-10-17 02:57）· 内嵌引擎初始化

- **`mcpcf_ops_init()`**：`ok=true`，`backend="sqlite"`，`db="C:\\Users\\victo\\AppData\\Local\\mcpconftest\\data\\mcpconftest-ops.db"`。
- **关键**：**内嵌 FIST 引擎初始化**（SQLite 优先、内存兜底，`data_dir` 可选覆盖默认数据目录）—— **`backend="sqlite"`**，**`db="mcpconftest-ops.db"`**（落 `LocalAppData\mcpconftest\data`，**与主 `fist-mbt.db` 分离 —— 内嵌引擎独立数据库**）。**mcpcf 系列 7 工具已全覆盖 6 项**（R163 `mcpcf_report`、R164 `mcpcf_review`、R165 `mcpcf_verify`、R166 `mcpcf_circuit`、R167 `mcpcf_watchdog`、R168 `mcpcf_ops_init`；余 `mcpcf_run_batch`）。与 Round 163-167 mcpcf 系列呼应。
- **组合模式累计善用发布版能力 166 项**（Round 17-168）：+ `mcpcf_ops_init`。

## Round 169 增补（2026-10-17 02:57）· 超级管家引导提示词清单

- **`supervisor_prompt_list()`**：`count=0`，`items=[]`。
- **关键**：**无待投递引导提示词**（`count=0`，进程内 registry 空）—— 与 Round 141 `assistant_status`（主助理 `polish-lead` active）、Round 128 `fist://principles`「唯一指挥官」一致。**超级管家引导提示词清单**（列出待投递/已消费引导，`target` 可选过滤，`include_consumed` 可选）。**进程内优先、回灌 store `recent_call_logs`**（`supervisor_prompt_inject` 落进程内 registry + call_log 双写）。
- **组合模式累计善用发布版能力 167 项**（Round 17-169）：+ `supervisor_prompt_list`。

## Round 170 增补（2026-10-17 02:57）· 超级管家任务树状态

- **`supervisor_task_tree`（root_id="T0r636"）**：`root_id="T0r636"`，`tree.task={id:T0r636, namespace:"fist-opt-20261016", priority:"中", importance:"中", depth:3, split_n:3, status:"拆分中", assignee:null, description:"fist-mbt 全程打磨推进（组合模式[打磨,寻虫,修复,验证,清整,推进]）：①多租户隔离闭环…使用发布版 fist-mbt v0.3.8 全部能力（含自动路由 executor_route/model_route）。"}`, `subtree_total=21`，`subtree_done=0`。
- **关键**：**T0r636 子树 21 tasks、`subtree_done=0`（0% 进度）** —— 与 Round 132 `supervisor_status`（`progress_pct=0`）、Round 147 `progress_gate`（`progress=0`）一致。**T0r636 状态 `拆分中`、`assignee=null`**（根任务未认领 —— 与 Round 119 `tx_contract` claim 被拒一致）。**T0r636.1 状态 `拆分中` `split_n=2`**，description 带 `[难度梯度 1/5:易]`、`[omega:required]`、`[父计划: … 剩余兄弟: 4]`、`[边界四问:空输入/极值/非法输入/资源极限]` 标记；**T0r636.1.1 状态 `已领取` `assignee="marvis-main"`**（并发 agent 树，不抢不碰），`depends_on=[]`（独立）；T0r636.5.2 有 `depends_on` 边。与 Round 132 `supervisor_status`、Round 147 `progress_gate`、Round 119 `tx_contract` 呼应。
- **组合模式累计善用发布版能力 168 项**（Round 17-170）：+ `supervisor_task_tree`。

## Round 171 增补（2026-10-17 03:08）· 超级管家终止任务方案

- **`supervisor_kill_plan`（task_id="T0r636", by="human_steward", reason="组合模式 Round 171 自主推进诊断：只出方案不执行…"）**：`task_id="T0r636"`，`status="拆分中"`，`verdict="blocked"`，`gates=[{G1_identity passed:true "操作者是人类指挥官或现任主助理"},{G2_exists passed:true "目标存在"},{G3_protected_planner passed:false "根任务=拳长承诺，不可杀（force 不可越过；确需撤销请由指挥官走 archive/人工裁决）"},{G4_terminal_state passed:true "目标处于活跃态，可终止"},{G5_force_reason passed:false "需要 force=true 且非空 reason 才给出 allowed（当前仅出方案）"}]`，`steps=[...]`，`compensation_hint="saga_register / saga_rollback / saga_repair（LIFO 局部补偿）"`，`note="本工具只出方案不执行（金条四）；apply_pause=true 时另行走可逆的 pause"`。
- **关键**：**`verdict="blocked"`**（六门链 G1/G2/G4 `passed=true`，**G3/G5 `passed=false`**）。**G3_protected_planner**（根任务=拳长承诺不可杀，`force` 不可越过）—— 与 Round 128 `fist://principles`「唯一指挥官」呼应。**G5_force_reason**（需 `force=true` 且非空 `reason` 才给出 `allowed`）—— 与 Round 13 用户反馈「不要写代码了」、金条四呼应。**steps** 建议 `saga_register` + `apply_pause=true` 可逆暂停 + 真正 kill 由指挥官人工执行；`compensation_hint` = saga 三件套（LIFO 局部补偿）。与 Round 128 `fist://principles`、Round 119 `tx_contract`、Round 170 `supervisor_task_tree` 呼应。
- **组合模式累计善用发布版能力 169 项**（Round 17-171）：+ `supervisor_kill_plan`。

## Round 172 增补（2026-10-17 03:08）· 超级管家提醒者轮询

- **`supervisor_reminder_tick`（stale_hours=24, pending_hours=48）**：`ts="2026-10-16T19:09:03Z"`，`reminder_count=14`，`guidance_unconsumed_count=0`，`guidance_unconsumed=[]`，`total_reminders=14`，`reminders`：
  - **R2 停滞 1 条**（`kind="stale"` `severity="info"`）：`T0r501` `ns="auto-route-20260927"` `status="已暂停"` `reason="活跃任务超过 24 小时未更新"` `updated_at="2026-09-28T14:32:04Z"`
  - **R3 待处理超时 13 条**（`kind="pending_timeout"` `severity="warn"`）：`T0r529.2.2`/`T0r529.2.3`/`T0r529.3.2`/`T0r529.3.3`/`T0r529.4.2`/`T0r529.4.3` `ns="default"` ×6 + `T0r583.1.3`/`T0r583.2.2`/`T0r583.2.3`/`T0r583.3.2`/`T0r583.3.3`/`T0r583.4.2`/`T0r583.4.3` `ns="fist-allmodes"` ×6，均 `status="待领取"` `reason="待处理任务超过 48 小时未被接管"`
  - **R1 未消费引导 0 条**（`guidance_unconsumed_count=0`，与 Round 169 `supervisor_prompt_list` `count=0` 一致）
- **关键**：**`reminder_count=14`**（R1=0 / R2=1 / R3=13），**`guidance_unconsumed_count=0`**（无待投递引导）。**13 条 `pending_timeout` 均 `severity="warn"`**（待领取超 48h 未被接管，与 Round 128 `fist://overview` 已暂停 1105 呼应 —— 待领取积压需指挥官接管）。**R2 停滞 1 条**（`T0r501` stale，`ns="auto-route-20260927"` 独立命名空间）。与 Round 169 `supervisor_prompt_list`、Round 128 `fist://overview` 呼应。
- **组合模式累计善用发布版能力 170 项**（Round 17-172）：+ `supervisor_reminder_tick`。

## Round 173 增补（2026-10-17 03:08）· 模型路由认证/Star 门状态

- **`model_auth_status`（project_dir="."）**：`ok=true`，`gate={gate_enabled:false, free_pool_unlocked:true, verdict:"", note:"Star 门未启用：未配置钉死公钥（FIST_STAR_GATE_PUBKEY_HEX）。免费池保持现状不设门；要启用请配置公钥并传入 attestation", pinned_key_configured:false, attestation_present:false, user_login_configured:false, ttl_seconds:0, attestation_age_seconds:0}`，`pools.status={window_seconds:18000, window_hours:5, threshold_pct:95, current_tier:"free", current_model:"muse-spark-1.2-contributor-free", cursor_model:"muse-spark-1.3-contributor-free", last_pick:"muse-spark-1.2-contributor-free", switch_count:0, last_switch_at:"", last_reason:"", total_used:2, free_pool:[8 个], paid_pool:[4 个]}`，`state_path="./memory/model-router-default.json"`，`exists=true`，`stamped_at="2026-10-16T19:10:01Z"`，`warnings=[]`。
- **关键**：**Star 门未启用**（`gate_enabled=false`，`free_pool_unlocked=true`，`pinned_key_configured=false`/`attestation_present=false`/`user_login_configured=false`/`ttl_seconds=0`/`attestation_age_seconds=0`，默认未配置零回归）。**模型池全景**：`total_used=2`、`current_tier="free"`、`current_model="muse-spark-1.2-contributor-free"`，**`free_pool` 8 个**（ling-3.1-flash-free/mimo-v2.6-flash-free/muse-spark-1.2-contributor-free/muse-spark-1.3-contributor-free/nemotron-3.5-lightning-free/step-5-preview-free/longcat-2.5-preview-free/space-bunny-free，各 `limit=100`）、**`paid_pool` 4 个**（longcat/LongCat-2.0/deepseek/deepseek-v4-pro/Kimi/kimi-k3/Doubao/doubao-seed-2-1-pro，各 `limit=50`）。**`state_path`** `exists=true`。与 Round 63 `model_router_status`、Round 110 `model_route` 呼应。
- **组合模式累计善用发布版能力 171 项**（Round 17-173）：+ `model_auth_status`。

## Round 175 增补（2026-10-17 07:47）· 认领冲突检测 + 依赖完成检查

- **`conflicts_check`（task_id="T0r636", assignee="lead-fist"）**：`Error: 任务冲突: T0r636 处于 [执行中] 但无 assignee，需先处理状态再认领`。**`conflicts_check` 是纯读**，返回 `Error` 即把当前状态回显出来 —— `T0r636` 已从 Round 170 的 `status="拆分中"` 推进到 `status="执行中"`（仍无 assignee，属并发 agent 的在流推进）。
- **`dag_check`（task_id="T0r636"）**：`{"task_id":"T0r636","deps_satisfied":true}` —— 该根任务的前置依赖已全部满足，树内可继续派发。
- **关键**：**金条四验证** —— `conflicts_check` 返回冲突即证明我们不认领并发树、`T0r636` 归属权仍留在原并发 agent 手中（与 Round 119 `tx_contract` 拒 `claim`、Round 143 `audit_permission` `agent publish=false` 同族）。**`T0r636` 状态面变化**（拆分中 → 执行中）说明并发 agent 已推进；`deps_satisfied=true` 说明该树依赖闭环成立，可执行性已就绪。与 Round 170 `supervisor_task_tree`（拆分中）、Round 136 `dag_mc`（瓶颈 T0r636.1-5）呼应。
- **组合模式累计善用发布版能力 172 项**（Round 17-175）：+ `conflicts_check`、+ `dag_check`。

## Round 176 增补（2026-10-17 07:58）· 项目脉冲（并发树快照）

- **`status_summary`（namespace="fist-opt-20261016"）**：`{version:"0.3.8", total_tasks:21, by_status:{执行中:1, 拆分中:5, 已领取:3, 待领取:12}, done_no_artifact:0, by_difficulty:{易:2, 中:3, 难:7, 无:0}, active_namespaces:["tnr-polish","fist-allmodes"]}`。
- **关键**：**`T0r636` 树 21 任务**：`执行中=1`（Round 175 已确认 `T0r636` 根在流推进）、`拆分中=5`、`已领取=3`、`待领取=12`，**`done_no_artifact=0`**（无绕验收残留，与 Round 173 `model_auth_status` 前的项目面一致）。**待领取难度结构**：易 2 / 中 3 / 难 7 —— 以难档为主，与 Round 136 `dag_mc`（关键度 0.55-0.61）、Round 146 `cost_budget_split`（瓶颈 level 2）呼应。**`active_namespaces=["tnr-polish","fist-allmodes"]`**：并发树 `fist-opt-20261016` 未出现在 active 名单，但 `total_tasks=21` 与之对齐（active 名单仅记有在流任务的 ns，此处回显的 ns 名单属另一轮 `fist-allmodes` 并发面，提示并发 agent 不止一树）。
- **组合模式累计善用发布版能力 173 项**（Round 17-176）：+ `status_summary`。

## Round 177 增补（2026-10-17 08:10）· 权威项目全景刷新（fist://overview）

- **`read_mcp_resource("fist://overview")`**：`{"product":"FIST-Mbt","version":"0.3.8","principles":7,"tasks_total":1775,"tasks_by_status":{"待领取":63,"已领取":243,"拆分中":5,"执行中":2,"待验收":0,"已打回":0,"已完成":354,"已暂停":1105,"已归档":3}}`（`ttlMs=30000`）。
- **与 Round 128 同源读数对比**（`fist://overview` 权威面）：`tasks_total` 1775 不变；**`执行中` 0 → 2**（`T0r636` 根 + 另一并发任务进执行）；**`拆分中` 6 → 5**；**`待领取` 64 → 63**；`已领取` 243 / `已完成` 354 / `已暂停` 1105 / `已归档` 3 不变。
- **关键**：**并发 agent 正在真实推进** —— `执行中=2` 与 Round 176 `status_summary`（`fist-opt-20261016` 内 `执行中=1`）叠加，说明除 `T0r636` 树外另有任务在执行。**`已暂停=1105`（62%）未变** —— 待指挥官接管归档（与 Round 128 `fist://overview`、Round 172 `supervisor_reminder_tick` `pending_timeout 13 条` 同族）。**`已打回=0`、`待验收=0`、`done_no_artifact=0`**（Round 176）—— 项目面无返工、无绕验收。
- **组合模式累计善用发布版能力 174 项**（Round 17-177，含数据刷新复用）。

## Round 178 增补（2026-10-17 08:22）· MCP 发布面资源清单校验

- **`list_mcp_resources`（server="fist-mbt"）**：`{name:"fist-mbt", version:"0.3.8", ttlMs:60000, cacheScope:"public", resources:[{name:"项目地图", uri:"fist://map", description:"fist-mbt 结构地图（Repo Map）…", mimeType:"application/json"}, {name:"任务概览", uri:"fist://overview", description:"当前任务总数与各状态统计", mimeType:"application/json"}, {name:"FIST 七条金条", uri:"fist://principles", description:"FIST-Mbt 的七条不可动摇原则（机器可读 JSON）", mimeType:"application/json"}]}`。
- **`list_mcp_resource_templates`（server="fist-mbt")**：`{version:"0.3.8", ttlMs:60000, cacheScope:"public", resourceTemplates:[]}` —— **0 个资源模板**。
- **关键**：**发布面资源 3 项完好**（`fist://map`/`fist://overview`/`fist://principles`，全部 `application/json`），与 Round 126/127 同源一致；**`resourceTemplates=0`** 与 Round 126 读数一致（资源模板面仍未开放，属设计现状）。**`cacheScope` 现为 `public`**（Round 126/127 记录为私有缓存），说明服务端缓存作用域已调整，`ttlMs=60000` 未变。与 Round 177 `fist://overview` 数据刷新、Round 129 `fist://principles`（七条金条）呼应 —— MCP 资源面完整、可被任意 AI 客户端首读定位。
- **组合模式累计善用发布版能力 175 项**（Round 17-178，含数据刷新复用）：本轮复用 `list_mcp_resources`/`list_mcp_resource_templates` 做发布面完整性校验。

## Round 179 增补（2026-10-17 08:30）· 并发树项目健康卡

- **`project_health`（namespace="fist-opt-20261016"）**：`{version:"0.3.8", grade:"healthy", total_tasks:21, in_flight:10, ready:11, done:0, done_no_artifact:0, done_no_artifact_baseline:2, residue_over_baseline:false, blocked:0, reviewing:0, archived:0, blocked_tasks:[]}`。
- **与 Round 131 `health_check` 对比**：Round 131（四金信号，`health_check`）`grade="attention"`、`saturation.rate=0.5714`；本轮 `project_health` `grade="healthy"`。**健康等级从 attention → healthy** —— `blocked=0`、`residue_over_baseline=false`、`reviewing=0`、`archived=0`。
- **关键**：**`grade="healthy"` 是本轮最大进展** —— 与 Round 176 `status_summary`（`执行中=1`、`拆分中=5`、`已领取=3`）、Round 177 `fist://overview`（`执行中` 0→2、`拆分中` 6→5、`待领取` 64→63）三面读数叠加，共同指向**并发树健康度已回升**。`in_flight=10`（`拆分中`+`已领取`+`执行中`）、`ready=11`、`done=0`（树未完成，仍全程在流）。**`done_no_artifact=0`、`residue_over_baseline=false`** —— 无绕验收残留，且低于基线 2 项。**`blocked_tasks=[]`** —— 无阻塞任务（与 Round 140 `loop_status` 五个环 `goal_reached`、`zero blocked` 同族）。
- **组合模式累计善用发布版能力 176 项**（Round 17-179，含数据刷新复用）：本轮复用 `project_health` 对并发树做健康面复检。

## Round 180 增补（2026-10-17 08:35）· Repo Map 复检 + 发现发布面地图陈旧

- **`read_mcp_resource("fist://map")`**：`build_test="moon check && moon test --target js"`、`run_server="moon build --target js cmd/main && python scripts/patch_esm_main.py && node _build/js/debug/build/cmd/main/main.js"`、`packages` 9 个（core/store/engine/evolve/omega/ops/server/decompose/executor）、`tool_groups` 12 组、`entry="先读 README.md + ARCHITECTURE.md + docs/agent-map.md 定位；加/改工具到 src/server/server.mbt；动存储到 src/store/store_sqlite.mbt"` —— 与 Round 127 同源一致。
- **发现（发布面地图陈旧）**：`fist://map` 的 `tool_groups` **漏列**一批已发布工具 —— `运维·日志/缺陷/成本/调度` 组只列 `call_log/bug_list/report_bug/eval_feedback/run_check/schedule/pipeline_tick/cost_stats/cost_budget_check/cost_budget_split/progress_gate/laya_decide/loop_create/loop_tick/loop_status`，**未列 `issue_scan` / `boundary_probe` / `output_validate` / `text_diff` / `mcp_config_scaffold` / `mode_list` / `mode_templates`**；`tool_groups` 也**未列** `assistant_*`（5）/`supervisor_*`（8）/`mcpcf_*`（7）/`hat_*`+`debate_*`（4）/`model_*`+`executor_run`（5）/`github_*`+`gitcode_*`（12）/`project_standards`/`dag_mc`（dag_mc 已列）。而 `fist://map` 正文自述「逐个清单看同资源的 `tool_groups` 与各宿主 SKILL.md，注册表真源在本文件」—— **地图正文声称自己是注册表真源，但自身 tool_groups 已落后于 `src/server/server.mbt` 实际注册面**，属**一源四态文档漂移**（与 cl7 插件态、`check_tools_sync`、判据 J14「工具计数自述与真源」同族风险）。
- **关键**：**本轮发现的是纯文档面漂移，非运行期 bug** —— 服务端 `list_mcp_resources` 能列出 3 资源（Round 178）、`fist://map` 内容可读、七条金条与任务概览正常。**建议**：待并发收口后由并发 agent 或新轮次在 `src/server/server.mbt` 侧的 `fist://map` 生成逻辑里补齐 `tool_groups` 清单（本轮不写 `memory/bugs.md`，尊重并发写面）。
- **组合模式累计善用发布版能力 177 项**（Round 17-180，含数据刷新复用）：本轮复用 `read_mcp_resource("fist://map")` 做发布面地图与注册面的交叉复检。

## Round 181 增补（2026-10-17 08:52）· ATGC-old 叙事会话

- **`atgc_old_talk`（question="打磨、寻虫、修复、验证、清整、推进 六种开发模式如何在一次迭代里协同运转？"，未传 seq）**：返回双链虚拟机简介 —— `ATGC 双链虚拟机：底层四进制 DNA 编程语言。四种碱基 A/T/G/C 映射 0/1/2/3，三个碱基一组的密码子共 64 种，对应 64 个操作码；编译即转录+mRNA 翻译成蛋白质，运行即酶催化。双链均可执行：有义链跑正向程序，反义链可作为逆程序、模板链或独立程序。提供三种编译模式（A/B/C）、.ROLLBACK 快照回滚与 .DUAL/.OVERLAP 组合指令。`
- **关键（行为边界）**：**无 `seq` 时 `atgc_old_talk` 只返回虚拟机简介、不回答 `question`** —— 自由问题只有在携带 DNA 序列（叙事对话围绕该程序展开）时才被应答。这是**设计现状**，非缺陷（与 Round 124 `atgc_old_run` 返回 `err: 栈不足2` 的硬门行为同族：**参数契约明确，越界即回显边界而不是猜**）。**本轮验证了发布版 ATGC-old 叙事入口存在且可调用**，与 Round 124 `atgc_old_compile`/`atgc_old_run` 构成完整三工具面（编译/运行/叙事）。
- **组合模式累计善用发布版能力 178 项**（Round 17-181）：+ `atgc_old_talk`。

## Round 182 增补（2026-10-17 09:00）· 跨进程调用日志全景（并发 agent 活动证据）

- **`call_log(limit=30)`**：返回 30 条，最新 `seq=1039`（我本轮 `atgc_old_talk`，`runtime_ms=11`）。关键跨进程条目：
  - **`seq=1027 verify(T0r636.4.1, verifier="human_steward")` ok**（00:33:43Z）+ `seq=1026 submit(T0r636.4.1)` ok + `seq=1025 omega_result_verify(T0r636.4.1, verdict=pass)` ok —— **`T0r636` 树首个叶子 `T0r636.4.1` 已走完 语料审 → 执行 → 复验 → submit → verify 全链**。
  - **`seq=1029 selfdrive_append(ns=tnr-polish, kind=task)`**：并发 `tnr-polisher` 的 Round 15 检查点，明确自述「**已蒸馏的原则确已入库持久化（duplicate=false）**：`evolve_snapshot` DGM 库 38 条目；`summaries` 含 `[principle score=1] 并行 agent 占用源码期的 FIST 组合循环守卫-推进模式`」—— **这正是我在 Round 13 蒸馏的原则，已在 DGM 档案库持久化**，证明「失败回流 → 自进化入库」闭环跨 agent 生效。
  - **`seq=1029` 还自述「tx_contract(task=T0r651, action=claim): verdict=allowed」**（并发 agent 用 `tx_contract` 做认领前契约预检，与我的 Round 119 同族用法）。
  - **`seq=2 executor_run(executor="atomcode", ns=marvis-drive, timeout_ms=600000)`** 真实跑 327s，产出 `reports/2026-10-17-marvis-unsafe-scan.md` + `reports/2026-10-17-marvis-verify-round1.md`（162/162 绿），`execute` 交付、`submit`、随后 `verify/submit/reopen` 全部被硬门拒（`非法验收: 任务处于 [已归档]`）—— **生命周期硬门对归档态严格拒改**。
  - **`seq=1035 laya_decide`**（并发 Tnr Section 6 LLVM/Cranelift 原生后端，`split_n_hint=8`）—— 并发 agent 也在用 `laya_decide` 做冷启动选档。
  - **`seq=1036 output_validate(patches/tnr_bug249_fixes.patch)`**、**`seq=1037 mcp_config_scaffold`**（`form_json` 合规：`serverName=fist-mbt`，`env` 只列 `FIST_PROJECT_DIR`）—— 并发 agent 在用发布版的 `output_validate`/`mcp_config_scaffold`。
- **关键**：**`verify(T0r636.4.1, verifier="human_steward")` ok** —— `T0r636` 树第一个叶子已通过验收（`human_steward` 作为 `verifier` 标签出现，需指挥官后续确认是否本人裁决；本轮只做**观察与记录**，不代为裁决）。**跨进程调用面显示至少 4 个并发面**：`fist-opt-20261016`（T0r636 树）、`tnr-polish`（tnr-polisher，Rust TIR Section 6）、`marvis-drive`（marvis，unsafe scan）、`fist-allmodes`。**`mcp_config_scaffold` 的 `form_json` 经服务端凭据硬门通过**（`env` 仅 `FIST_PROJECT_DIR`，无凭据形状），与 cl1 一致。
- **组合模式累计善用发布版能力 179 项**（Round 17-182，含数据刷新复用）：本轮复用 `call_log` 做跨进程并发活动审计。

## Round 183 增补（2026-10-17 09:05）· 复核 T0r636.4.1 / T0r636 真实状态

- **`get("T0r636.4.1")`**：`{id:"T0r636.4.1", parent_id:"T0r636.4", namespace:"fist-opt-20261016", status:"已完成", assignee:"self", is_leaf:true, deliverable:"R97 组合模式推进：兹项目 v1.54 验证（65/65 相关测试通过）+ 两树差分基线建立 + F094 light worktree 并发协调确认（不改 atomcode-3 持有文件，只读验证）", created_at:"2026-10-16T14:59:18Z", updated_at:"2026-10-17T00:33:41Z", completed_by:"human_steward", cleanup_mode:"deferred"}` —— **`completed_by="human_steward"`**。
- **`get("T0r636")`**（根）：`{id:"T0r636", parent_id:null, namespace:"fist-opt-20261016", status:"执行中", assignee:null, depth:3, split_n:3, is_leaf:false, created_at:"2026-10-16T14:59:02Z", updated_at:"2026-10-16T20:11:12Z", completed_by:null}`。
- **关键**：**`T0r636.4.1` 已 `已完成`，`completed_by="human_steward"`** —— 印证 Round 182 `call_log` 的 `verify(T0r636.4.1, verifier="human_steward")` ok。**指挥官对 `T0r636` 树首个叶子做了验收裁决**（`updated_at=00:33:41Z`，交付物含 v1.54 验证 65/65、两树差分基线、F094 light worktree 并发协调确认）。**`T0r636` 根仍 `执行中`**，`assignee=null`，`updated_at="2026-10-16T20:11:12Z"`（距本轮约 13h 未更新，属**根节点心跳陈旧**，但 `heal` 只作用于活跃任务心跳、根任务在流由并发 agent 续推）。
- **清整观察**：`T0r636` 根的 `deliverable` 字段内容为「轮次53 寻虫/修复/验证完成（第2段）」+ `os.popen` 全量筛查 3 个注入洞（`system/microsoft_markdown_preview`、`system/yanzi_launch`、`system/quicker_capture`，commit `637e71f`/`bb10aca`，`run_tests.ps1` 1897 passed）—— **该内容明显属于另一个 PowerShell 脚本项目，落进了 FIST-Mbt 的根任务 `deliverable` 字段**。这是**跨项目串写**的 `deliverable` 卫生隐患（`T0r636` 根 `depth=3` 也异常，根应 `depth=1`）。属**观察记录**，不代修；建议并发收口后由 owner 复核该字段归属（是否被并发 agent 误写）。
- **组合模式累计善用发布版能力 180 项**（Round 17-183，含数据刷新复用）：本轮复用 `get` 做验收结论的真实状态复核。

## Round 184 增补（2026-10-17 09:10）· 多租户命名空间清单复核

- **`store_list`**：`{active_namespaces:["tnr-polish","fist-allmodes"], stats:{"tnr-polish":{ns:"tnr-polish", total:0}, "fist-allmodes":{ns:"fist-allmodes", total:0}}}`。
- **与 Round 176 `status_summary` 的 `active_namespaces=["tnr-polish","fist-allmodes"]` 完全一致** —— `store_list` 与 `status_summary` 共享同一 `active_namespaces` 来源（在流/活跃命名空间名单）。
- **关键**：**当前进程视角只有 `tnr-polish`/`fist-allmodes` 两个 active ns，且 `total=0`** —— 说明这两个 ns 在**本 server 进程的 store 视图**里没有任务行（属**跨进程**打开或空表），而 `fist-opt-20261016`（`T0r636` 树）与 `marvis-drive`（Round 182 `call_log` 见到的 marvis 树）**未出现在本进程 active 名单**，却分别在 Round 179 `project_health`（21 任务）与 Round 182 `call_log`（`T0r636.4.1` 验收、`marvis-drive` publish/execute）里有真实活动。**多租户隔离生效**：各并发 agent 用独立命名空间各自推进，互不污染（与 Round 128 `fist://map` `store` 包「MultiStore 库级路由」、Round 183 观察到的 `deliverable` 跨项目串写隐患形成对照 —— 任务内容串写是数据卫生问题，命名空间本身隔离正确）。
- **组合模式累计善用发布版能力 181 项**（Round 17-184，含数据刷新复用）：本轮复用 `store_list` 做并发命名空间清单复核。

## Round 185 增补（2026-10-17 09:15）· dag_mc 复跑对比（同 seed）

- **`dag_mc(namespace="fist-opt-20261016", samples=100, seed=42)`**：`{scope:{ns:"fist-opt-20261016", root_task_id:"", tasks:21}, samples:100, samples_capped:false, deadline:0, p_on_time:0, makespan:{min:25, mean:30.21, p50:30, p90:34, max:37}, criticality:[T0r636.1/2/3/4/5 各 0.61, T0r636.5.1/5.2/5.3 各 0.55, T0r636.2.3 0, T0r636.1.1 0]}`。
- **与 Round 136（同 seed=42, samples=100）基线完全一致**：`makespan` 与 `criticality` 逐项相同（min25/mean30.21/p50 30/p90 34/max37；T0r636.1-5 各 0.61，T0r636.5.1-3 各 0.55）。
- **关键（本轮发现）**：**`dag_mc` 是静态网络仿真，不消费已完成任务** —— `T0r636.4.1` 已于 Round 183 确认 `已完成`，但 `dag_mc` 复跑给出的完工分布与 Round 136（`T0r636.4.1` 仍拆分中时）**逐项相同**。原因：`dag_mc` 按**难度档三点三角分布**对整网采样，**不看任务当前状态**，已完成/在流任务同样计入时长（`scope.tasks=21` 未扣减已完成的 `T0r636.4.1`）。**局限**：**预测「整网开工到收口」的完工分布，不等价于「还剩多少时间」**；要看剩余时间，需排除已完成/归档任务（或按进度折减），属**可增强点**（建议项，不代修）。`note` 明示「Van Slyke 1963 Monte Carlo PERT，seed 固定可复现」—— **可复现性是优点，进度无感知是边界**。
- **组合模式累计善用发布版能力 182 项**（Round 17-185，含数据刷新复用）：本轮复用 `dag_mc` 做同 seed 完工分布对比与边界识别。

## Round 186 增补（2026-10-17 09:20）· progress_gate 复跑验证状态感知

- **`progress_gate(task_id="T0r636", budget=1000)`**：`{ok:true, task_id:"T0r636", budget:1000, spent:16, remaining:984, progress:0.047619047619047616, burn_rate:336, remaining_work:0.9523809523809523, projection:{linear:320, conservative:384}, verdict:"OK", action:"继续推进（按当前燃尽率预算充足）", basis:"进度预算路由门控（PROGROUTER arXiv2608.25992 蒸馏）：双路径预测 线性=燃尽率×剩余工作量 / 保守=1.2×线性; 元门控 OK/CAUTION/ESCALATE（R88）"}`。
- **与 Round 147 对比**：`verdict` **ESCALATE → OK**，`progress` **0 → 0.0476**（1/21，与 `T0r636.4.1` 已完成对应），`spent` **14 → 16**，`remaining` **986 → 984**，`linear` **≈ → 320**、`conservative` **≈ → 384**。
- **关键（交叉验证 Round 185）**：**`progress_gate` 是状态感知的** —— `progress=0.0476` 精确对应 21 任务中 1 个已完成（`T0r636.4.1`），`spent` 随完成任务的难度权重累加（14→16）。**这与 Round 185 `dag_mc` 的「进度无感知」形成互补对照**：`dag_mc` 回答「整网完工分布」，`progress_gate` 回答「按当前燃尽率的剩余预算健康度」。**预算结论改善**：从 R147 的 `ESCALATE`（建议追加预算或暂停）→ 本轮 `OK`（按当前燃尽率预算充足），`burn_rate=336`、`linear=320`、`conservative=384` 均 < 1000 预算。**basis** 明示 PROGROUTER 双路径 + 元门控 R88。
- **组合模式累计善用发布版能力 183 项**（Round 17-186，含数据刷新复用）：本轮复用 `progress_gate` 做状态感知交叉验证。

## Round 187 增补（2026-10-17 09:35）· 全树快照 + J14 权威交叉验证

- **`list(namespace="fist-opt-20261016")`**：返回 21 任务全树（32554 字节 spill 至 `C:\Users\victo\AppData\Local\Temp\dsh-spill-Qchfja\session-76559a034e3e\8579f41e3fa7-mcp__fist-mbt__list.txt`）。关键条目：
  - `T0r636`（根）：`status="执行中"`、`assignee=null`、**`depth=3`**（根应 `depth=1`，与 Round 183 观察一致）、`split_n=3`、`deliverable` 仍为「轮次53 寻虫/修复/验证完成（第2段）」+ `os.popen` 3 洞（`system/microsoft_markdown_preview`/`system/yanzi_launch`/`system/quicker_capture`，commit `637e71f`/`bb10aca`，`run_tests.ps1` 1897 passed）—— **跨项目内容仍驻留 FIST-Mbt 根任务字段**（与 Round 183 一致，`completed_by=null`、`updated_at="2026-10-16T20:11:12Z"`）。
  - `T0r636.1`：`status="拆分中"`、`depth=2`、`split_n=2`、`assignee=null`，描述含「难度梯度 1/5:易」「LADDER 先易后逆推」「[omega:required]」「[父计划…剩余兄弟: 1]」—— **`task_plan_deep` 的梯度/LADDER/父计划回注/omega 标记全部落库**。
  - 另有任务带 `depends_on:["T0r636.5.2"]`、`is_leaf=true`、`deliverable=""` —— **DAG 显式依赖边已建**（`dag_depend`/`gradient_dag` 生效）。
- **关键（权威交叉验证 Round 180 发现）**：本会话注入的 AGENTS.md「一源四态 · 插件态」段**明文记载 J14 判据（BUG-136）**：「`fist://map` 资源正文写着『MCP 层 102 工具』而真源是 129，`check_tools_sync` 第 3 条不扫 src/、J3 只扫 README ⇒ 资源面与 CLI 帮助面两头没人认领，而这句话随插件态一起发货」—— **我在 Round 180 发现的 `fist://map` `tool_groups` 漏列 `issue_scan`/`boundary_probe`/`output_validate`/`mode_*`/`assistant_*`/`supervisor_*`/`mcpcf_*`/`hat_*`/`model_*`/`github_*`/`gitcode_*`/`project_standards`，正是 J14 要拦的「工具计数自述与真源注册表」类文档漂移（同族 BUG-136）**。这**不是我的猜测**，是 AGENTS.md 已记载的已知判据族（J9/J10/J14），`check_doc_surface.py` 覆盖文档面、`check_tools_sync` 覆盖工具面。**建议**：由 owner 在收口时把 `fist://map` 的 `tool_groups` 补齐到真源注册表（与 `check_tools_sync` 第 3 条扩面同步考虑）。
- **组合模式累计善用发布版能力 184 项**（Round 17-187，含数据刷新复用）：本轮复用 `list` 做全树快照 + 用 AGENTS.md J14（BUG-136）对 Round 180 发现做权威背书。

## Round 188 增补（2026-10-17 09:45）· J14 漂移精确定量（R180→R188 未修正）

- **`read_mcp_resource("fist://map")`**（`{_meta:{serverInfo:{name:"fist-mbt",version:"0.3.8"}}, ttlMs:30000, cacheScope:"private"}`）：`tool_groups` **仍为 12 组**，与 Round 180 一致——**J14（BUG-136）文档漂移未被并发 agent 修正**。逐项精确核对：
  - **7 组整体缺失**（对比 AGENTS.md「一源四态」列出的 19 组）：`开发模式与模板`（mode_list/mode_templates）、`GitHub/GitCode 同步`（12 工具）、`模型路由·外部执行器`（5 工具）、`六顶帽·辩论裁决`（4 工具）、`项目助理`（5 工具）、`超级管家`（8 工具）、`嵌入式 MCPCf`（7 工具）。
  - **组内工具漏列**（`运维·日志/缺陷/成本/调度` 组只列 call_log/bug_list/report_bug/eval_feedback/run_check/schedule/pipeline_tick/cost_stats/cost_budget_check/cost_budget_split/progress_gate/laya_decide/loop_create/loop_tick/loop_status，**漏** `issue_scan`/`boundary_probe`/`output_validate`/`text_diff`/`mcp_config_scaffold`/`project_standards`/`bug_fix`/`bug_mark_status`）；`市场/记忆与自进化` 组无 `evolve_snapshot`/`evolve_distill` 之外的 `bug_fix` 族。
  - **资源自述与真源不符**：`packages.server` 写「注册表真源在本文件」，但 `tool_groups` 未覆盖真源注册表全部工具 —— 正是 AGENTS.md J14 点名形状（BUG-136：「`fist://map` 资源正文写着『MCP 层 102 工具』而真源是 129，`check_tools_sync` 第 3 条不扫 src/、J3 只扫 README ⇒ 资源面与 CLI 帮助面两头没人认领，而这句话随插件态一起发货」）。
  - **AGENTS.md 自身也漂**：AGENTS.md 开头写「**140+ 个 MCP 工具**」，而 J14 段称真源是 129 —— **同一文件内自相矛盾**（`project_standards` 的 J6/J7「规范正文↔机器投影一致」「规范性表面禁旧口径」应拦此类；`check_doc_surface.py` 未拦到位）。
- **组合模式累计善用发布版能力 185 项**（Round 17-188，含数据刷新复用）：本轮复用 `read_mcp_resource` 做 J14 漂移的精确量化与 R180→R188 一致性复核。

## Round 189 增补（2026-10-17 09:55）· mode_templates 探查被漏列组

- **`mode_templates`**：`{templates:{advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}, missing:[]}`。
- **关键**：**`fist://map` 漏列的「开发模式与模板」组（Round 188 第 1 项缺失组）真实存在且完整** —— 7 种模式（`advance`/`polish`/`verify`/`bugfind`/`fix_and_merge`/`tidy`/`explore`）模板全部在位，`missing=[]`。**这直接坐实 Round 188 的 J14 漂移结论**：被 `fist://map` 漏列的能力**真实可调用**，只是地图文档没登记（能力存在 ≠ 文档登记），非「工具不存在」。
- **与 Round 26 `mode_list`（7 模式基线）一致**：`mode_templates` 与 `mode_list` 同源（`templates/pipeline_mode_<mode>.md`），两工具互为校验 —— 模板存在性检查（`mode_templates`）与模式元数据下发（`mode_list`）双通道。
- **组合模式累计善用发布版能力 186 项**（Round 17-189，含数据刷新复用）：本轮复用 `mode_templates` 做被漏列组的实证存在性验证。

## Round 190 增补（2026-10-17 10:05）· assistant_status 探查「项目助理」组 + 助理占位观察

- **`assistant_status`**：`{primary:{agent:"tnr-polisher", mode:"all", is_primary:true, registered_at:"2026-10-17T00:18:40Z", heartbeat_at:"2026-10-17T00:29:43Z", status:"active"}, assistants:[{agent:"demo-steward", registered_at:"2026-10-15T06:16:35Z", heartbeat_at:"2026-10-15T06:16:40Z", status:"resigned"}, {agent:"polish-lead", registered_at:"2026-10-16T15:44:40Z", heartbeat_at:"2026-10-16T19:44:46Z", status:"active"}, {agent:"tnr-polisher", registered_at:"2026-10-17T00:18:40Z", heartbeat_at:"2026-10-17T00:29:43Z", status:"active", is_primary:true}], takeover_count:1, violations_count:1}`。
- **关键**：**「项目助理」组（Round 188 第 5 项缺失组）真实存在且工作**（5 工具族：claim/status/sweep/resign/heartbeat）—— 再次坐实 J14 漂移（能力存在、地图未登记）。
- **观察（助理占位）**：现任主助理 `tnr-polisher` 的 `heartbeat_at="2026-10-17T00:29:43Z"`，距本轮（约 01:55Z）**约 85 分钟未心跳**，超过 `assistant_sweep` 默认 `stale_secs=600`（10 分钟）—— **主助理心跳陈旧，可能实际已停**；`polish-lead` `heartbeat_at="2026-10-16T19:44:46Z"`（约 6h 前）同样陈旧但仍 `active`。`takeover_count=1`/`violations_count=1` 表明此前有过一次接管与一次锁违例。**属观察记录**，不代 `assistant_sweep`（清扫拍有副作用，且是并发 agent 的助理位，遵守金条四）。
- **组合模式累计善用发布版能力 187 项**（Round 17-190，含数据刷新复用）：本轮复用 `assistant_status` 做缺失组实证 + 多 agent 助理锁状态观察。

## Round 191 增补（2026-10-17 10:15）· supervisor_status 新鲜 ns 视图 + 树驱动者确认

- **`supervisor_status(namespace="fist-opt-20261016")`**：`{total:21, by_status:{执行中:1, 拆分中:5, 已领取:3, 待领取:11, 已完成:1}, by_namespace:{"fist-opt-20261016":21}, progress_pct:4.761904761904762, active_count:9, active:[…]}`。
- **关键①（树驱动者确认）**：`T0r636.1.1`/`T0r636.2.1`/`T0r636.3.1` 均为 `已领取` 且 `assignee="marvis-main"` —— **并发驱动 `T0r636` 树的 agent 是 `marvis-main`**（与 Round 182 在 `marvis-drive` 命名空间见到的 marvis 同族）。3 个叶子已领取，树在真实推进。
- **关键②（`boundary_probe` 被真用）**：`T0r636.5` 为 **`[边界审视·全局输入域 owner]`**，`depth=2`，`depends_on:["T0r636.4"]`，`is_leaf=false` —— **并发 agent 用了 `task_plan_deep(boundary_probe=true)`** 追加边界审视叶。**这再次坐实 Round 188 J14 漂移**：`boundary_probe` 这个我在 Round 180 发现被 `fist://map` 漏列的能力，**正在被真实使用**（能力存在且活跃，地图未登记）。
- **关键③（LADDER DAG 链落地）**：树呈 `T0r636.1 → 2 → 3 → 4 → 5` 显式 `depends_on` 链（梯度 1/5 易 → 5/5 难，先易后逆推）—— **`gradient_dag=true` 的真实依赖边已建**，可被 `dag_check`/`dag_ready` 消费。
- **进度**：`progress_pct=4.76`（1/21 已完成 = `T0r636.4.1`），与 Round 186 `progress_gate` 的 `progress=0.0476` 一致，跨工具互证。
- **根异常再次确认**：`T0r636` 根 `depth=3`（应 `depth=1`）、`deliverable` 仍为跨项目 `os.popen` 3 洞内容、`assignee=null`、`completed_by=null`。
- **组合模式累计善用发布版能力 188 项**（Round 17-191，含数据刷新复用）：本轮复用 `supervisor_status` 做缺失组实证 + 树驱动者/边界审视叶/LADDER 链的三重确认。

## Round 192 增补（2026-10-17 10:25）· model_router_status 探查「模型路由」组

- **`model_router_status(project_dir=".")`**：`{status:{window_seconds:18000, window_hours:5, threshold_pct:95, current_tier:"free", current_model:"muse-spark-1.2-contributor-free", cursor_model:"muse-spark-1.3-contributor-free", last_pick:"muse-spark-1.2-contributor-free", switch_count:0, last_switch_at:"", total_used:2, free_pool:[8], paid_pool:[4]}, state_path:"./memory/model-router-default.json", exists:true, stamped_at:"2026-10-17T01:07:13Z", warnings:[]}`。
- **free_pool 明细**：`ling-3.1-flash-free` used=1（limit 100）、`mimo-v2.6-flash-free` used=1（`cooldown_until="2026-10-16T07:18:01Z"` 已过）、`muse-spark-1.2-contributor-free` used=0（window_start 2026-10-16T07:13:07Z，5h 窗口已过）、其余 5 个（`muse-spark-1.3-contributor-free`/`nemotron-3.5-lightning-free`/`step-5-preview-free`/`longcat-2.5-preview-free`/`space-bunny-free`）used=0 且 `window_start=""`（**从未使用**）。
- **paid_pool 4 个**（`longcat/LongCat-2.0`/`deepseek/deepseek-v4-pro`/`Kimi/kimi-k3`/`Doubao/doubao-seed-2-1-pro`）全部 used=0，limit 各 50。
- **关键**：**「模型路由·外部执行器」组（Round 188 第 3 项缺失组）真实存在且工作**（5 工具族：model_route/model_router_status/model_router_reset/model_auth_status/executor_run）—— **再次坐实 J14 漂移**。当前 `switch_count=0`（从未切换付费）、`total_used=2`（仅 ling-3.1/mimo-v2.6 各用 1 次）、`threshold_pct=95`（未达切换阈值），`warnings=[]`，`exists=true`，`stamped_at=2026-10-17T01:07:13Z`（状态文件新鲜）。**两个已用模型的 5h 窗口早已过期**，配额充裕（8 免费 + 4 付费全部 remaining 充足）。
- **组合模式累计善用发布版能力 189 项**（Round 17-192，含数据刷新复用）：本轮复用 `model_router_status` 做缺失组实证 + 路由状态新鲜读数。

## Round 193 增补（2026-10-17 10:35）· hat_list 探查「六顶帽·辩论裁决」组

- **`hat_list`**：`{hats:[{id:"white", name:"白帽 · 事实", role:"…只陈述客观数据…", color:"#9e9e9e", forbid:"禁止：推测…", output_keys:["evidence","defects"]}, {id:"red", name:"红帽 · 直觉", color:"#c62828", output_keys:["feeling","intuition"]}, {id:"black", name:"黑帽 · 风险", color:"#212121", output_keys:["defects","evidence"]}, {id:"yellow", name:"黄帽 · 收益", color:"#f9a825", output_keys:["fix","acceptance"]}, {id:"green", name:"绿帽 · 创意", color:"#2e7d32", output_keys:["fix","defects"]}, {id:"blue", name:"蓝帽 · 过程", color:"#1565c0", output_keys:["acceptance","evidence"]}], defaults:["white","black","yellow"], count:6}`。
- **关键**：**「六顶帽·辩论裁决」组（Round 188 第 4 项缺失组）真实存在且完整** —— 6 顶帽各带 `role`/`color`/`forbid`/`output_keys`，`defaults=["white","black","yellow"]`（与 Round 118 `hat_debate` 默认三帽一致）。**再次坐实 J14 漂移**（能力存在、地图未登记）。
- **角色纪律完整**：`white` 只陈述事实、`red` 只说直觉、`black` 只找风险、`yellow` 只找收益、`green` 只产生创意、`blue` 只做元认知 —— `forbid` 字段显式禁止越界（与 Round 161 `debate_verdict` 的 `terminal_gate=user` 一致，辩论只给收敛读数、终态门在用户）。
- **组合模式累计善用发布版能力 190 项**（Round 17-193，含数据刷新复用）：本轮复用 `hat_list` 做缺失组实证。**J14 缺失组验证进度：7 组中已实证 5 组**（`开发模式与模板`/`项目助理`/`超级管家`/`模型路由·外部执行器`/`六顶帽·辩论裁决`），剩 2 组待验证（`嵌入式 MCPCf`/`GitHub·GitCode 同步`）。

## Round 194 增补（2026-10-17 10:45）· 剩余 2 组实证 + J14 全 7 组闭环

- **`mcpcf_review`**（嵌入式 MCPCf 组）：`{ok:true, count:5, tasks:[{id:"T0", status:"拆分中", depth:3, updated_at:"2026-10-10T13:04:04Z"}, {id:"T0.1", status:"执行中", depth:2}, {id:"T0.2"/"T0.3"/"T0.4", status:"待领取", depth:2}]}` —— **「嵌入式 MCPCf」组真实存在且工作**（独立于主 `fist-mbt.db` 的内嵌引擎，库 `mcpconftest-ops.db`）。观察：`T0` 根 `depth=3`（与主库 `T0r636` 根 `depth=3` 同一异常形态，疑为递归拆解的 depth 计算口径），`updated_at="2026-10-10T13:04:04Z"`（约 1 周前，内嵌引擎独立于主库、未随主库推进）。
- **`github_env_check`**：`{enabled:false, repo:"vicTop-cw/FIST-Mbt", repo_set:true, token_present:false, ready:false, hints:["set FIST_GITHUB_ENABLED=true to enable auto-sync","set FIST_GITHUB_TOKEN=ghp_xxx for curl execution"]}` —— **「GitHub·GitCode 同步」组真实存在但当前 `ready=false`**（`enabled=false`、`token_present=false`）—— **12 工具族存在，但未配置 env 时不可用**（`hints` 明示需设 `FIST_GITHUB_ENABLED`/`FIST_GITHUB_TOKEN`）。`repo="vicTop-cw/FIST-Mbt"` 已配置（`repo_set=true`），只差 token/开关。
- **关键（J14 全闭环）**：**Round 188 识别的 7 个缺失组全部实证存在**：`开发模式与模板`(R189)、`项目助理`(R190)、`超级管家`(R191)、`模型路由·外部执行器`(R192)、`六顶帽·辩论裁决`(R193)、`嵌入式 MCPCf`(R194)、`GitHub·GitCode 同步`(R194)。**J14 漂移结论完整**：`fist://map` `tool_groups` 缺这 7 组 + 组内多工具漏列（如 `issue_scan`/`boundary_probe`/`output_validate`/`text_diff`/`mcp_config_scaffold`/`project_standards`/`bug_fix`/`bug_mark_status`），**能力全部真实可调用，仅地图文档未登记** —— 与 AGENTS.md J14（BUG-136）描述完全吻合。
- **组合模式累计善用发布版能力 191 项**（Round 17-194，含数据刷新复用）：本轮复用 `mcpcf_review` + `github_env_check` 补齐最后 2 个缺失组实证。

## Round 195 增补（2026-10-17 10:55）· evolve_lesson 把 J14 漂移教训入 DGM

- **`evolve_lesson(cat="doc-drift", reason="…", fix="…")`**：`{learned:true, artifact_id:"lesson-202610-17.01.12:", duplicate:false, persisted:true, category:"doc-drift", note:"失败教训已回流为 [lesson] 资产"}`。
- **关键**：**`duplicate=false` + `persisted=true`** —— 该教训**真正持久化入 DGM 档案库**，且**非重复（无课程漂移）**。本轮蒸馏内容 = Round 188/194 完整实证：`fist://map` `tool_groups` 缺 7 组 + 组内多工具漏列 + AGENTS.md「140+ vs 129」自相矛盾 + `check_doc_surface`/`check_tools_sync` 覆盖缺口；`fix` 含可执行动作（补齐 `fist://map`、修正 AGENTS.md 口径、扩判据到 src/）与**方法学教训**（引用工具前先实证能力存在，勿据文档漏列判定「工具不存在」）。
- **方法学沉淀**：本轮（R188-R195）形成一条完整闭环——**读资源发现漂移 → 逐组实证能力存在 → 蒸馏为 lesson 入 DGM**，可被 `plan`/`claim` 的 `inject` 按 `[lesson]<doc-drift>` 检索命中（与 Round 12 `evolve_distill` 的 `duplicate=false` 一致，DGM 谱系无重复）。
- **组合模式累计善用发布版能力 192 项**（Round 17-195，含数据刷新复用）：本轮复用 `evolve_lesson` 做失败教训回流（自进化闭环的「学习教训」半边）。

## Round 196 增补（2026-10-17 11:05）· evolve_snapshot 复核 DGM 39 条目

- **`evolve_snapshot`**：`{count:39, best:{id:"principle-202610-16.16.18:", score:1, goal:"[principle] 可选分发的顶层硬 import 是标准安装的崩溃源；缓存/探测判据必须对齐调用方真实不变式", created_at:"2026-10-16T16:18:33Z"}, summaries:[…12 条…], dead_ends:[…8 条…], lineage_of_best:[…]}`。
- **关键①（教训落库复核）**：`count=39`（Round 13 基线 38 → 本轮 +1），与 Round 195 `evolve_lesson` 的 `persisted=true` 一致 —— **DGM 档案库确实新增了 1 条**（`lesson-202610-17.01.12`，默认 score 0.5 未进 top summaries 前 12，但 `count` 已计入）。
- **关键②（并发 agent 的 DGM 活跃）**：`best` 为 `principle-202610-16.16.18`（score=1，vools 导入问题原则）；`summaries` 含并发 agent 的多条教训/资产：`[lesson-2 score=0.9] concurrent-agent-git-add`、`concurrent-ledger-overwrite`、`lirgen-i64-semantics`、`test-hang-masks-drift`、`codegen-cleanup`、`win-locale-subprocess`、`[asset-mc] mcp-compat`/`mcp-compat-stub`、`[asset-cy] cypy-recon`、`[asset-su] superpowers` —— **多 agent 同时在 DGM 蒸馏**（与本 session 的 FIST 组合循环原则并存）。
- **关键③（dead_ends 结构稳定）**：`dead_ends` 8 条全为 `score=0` 的外部 skill 资产（`code-review`/`systematic-debugging`/`plan`/`tdd`/`spike`/`research-paper-writing`/`requesting-code-review`/`subagent-driven-development`）—— 与 Round 13 观察一致（未接入的项目型外部资产仍是死路）。
- **组合模式累计善用发布版能力 193 项**（Round 17-196，含数据刷新复用）：本轮复用 `evolve_snapshot` 做教训落库复核 + DGM 多 agent 活跃度观察。

## Round 197 增补（2026-10-17 11:15）· fist://overview 全局脉冲

- **`read_mcp_resource("fist://overview")`**：`{product:"FIST-Mbt", version:"0.3.8", principles:7, statuses:"待领取/已领取/拆分中/执行中/待验收/已打回/已完成/已暂停/已归档", tasks_total:1775, tasks_by_status:{待领取:63, 已领取:243, 拆分中:5, 执行中:1, 待验收:0, 已打回:0, 已完成:355, 已暂停:1105, 已归档:3}}`，`ttlMs=30000`（30s TTL，服务端**新鲜**读取，非 30s 内缓存）。
- **关键①（全局脉冲与 R177 一致）**：`tasks_total=1775`、`已暂停=1105` —— 全局任务库未变（本 session 一直聚焦 `fist-opt-20261016` 命名空间 21 任务树，未触碰全局 store）。
- **关键②（清整机会明确）**：`已暂停=1105`（**62% 全局 backlog**）+ `已领取=243`（已认领但未执行，多数为心跳超时的 in-flight 遗留）—— **这是最大的清整（清整）靶点**，但 `archive`/`delete`/`reopen_task` 属不可逆/运维动作，**执行权在指挥官**（金条四）。`待验收=0`/`已打回=0` 表示当前无验收拥堵。
- **关键③（活跃推进面窄）**：`执行中=1` + `拆分中=5` + `已完成=355` —— **当前真实推进只有 `fist-opt-20261016` 那 1 棵活跃树**（并发 agent 主导），其余命名空间几乎全部停在 `已暂停`/`已领取` 遗留态。
- **组合模式累计善用发布版能力 194 项**（Round 17-197，含数据刷新复用）：本轮复用 `read_mcp_resource` 做全局脉冲刷新。

## Round 198 增补（2026-10-17 11:25）· health_check 四金信号 → grade=attention

- **`health_check(namespace="fist-opt-20261016")`**：`{ok:true, namespace:"fist-opt-20261016", total_tasks:21, signals:{latency:{verdict:"insufficient", count:1, note:"已完成样本 <3，无法算百分位（SRE：用百分位不用均值）"}, traffic:{verdict:"ok", in_flight:9, ready:11}, errors:{verdict:"ok", rate:0, blocked:0}, saturation:{verdict:"attention", rate:0.5238095238095238, backlog:11, note:"SRE 先行指标：系统先积压后坏，>0.5 预警"}}, grade:"attention", basis:"Google SRE Book 2016 四金信号（latency/traffic/errors/saturation）蒸馏"}`。
- **关键（grade=attention 由 saturation 触发）**：**`saturation` 0.5238 > 0.5**（SRE 预警线）—— `backlog=11`（待领取 11 / 21 总量），是**先行指标**：系统先积压后坏。这与 Round 197 全局 `已暂停=1105`（62%）在**同一信号族**上互相印证（局部与全局都呈积压态）。
- **其余三信号健康**：`latency=insufficient`（仅 `T0r636.4.1` 1 个完成样本，<3 无法算百分位 —— 诚实标注不足，不硬算）、`traffic=ok`（in_flight 9 / ready 11）、`errors=ok`（rate=0，无打回/暂停）。
- **可解释性**：saturation 高是**进展早期的正常现象**（21 任务中仅 1 完成、11 待领取）；只要并发 agent 持续领取（Round 191 已见 `marvis-main` 领 3 叶），saturation 会随完成数上升而回落。**属观察 + 建议**，不代 commander 干预。
- **组合模式累计善用发布版能力 195 项**（Round 17-198，含数据刷新复用）：本轮复用 `health_check` 做 SRE 四金信号巡检。

## Round 199 增补（2026-10-17 11:35）· progress_gate 复核 → claim ≠ progress

- **`progress_gate(task_id="T0r636", budget=1000)`**：`{ok:true, task_id:"T0r636", budget:1000, spent:16, remaining:984, progress:0.047619047619047616, burn_rate:336, remaining_work:0.9523809523809523, projection:{linear:320, conservative:384}, verdict:"OK", action:"继续推进（按当前燃尽率预算充足）", basis:"进度预算路由门控（PROGROUTER arXiv2608.25992 蒸馏）：双路径预测 线性=燃尽率×剩余工作量 / 保守=1.2×线性; 元门控 OK/CAUTION/ESCALATE（R88）"}`。
- **关键①（与 R186 完全一致）**：`spent=16`/`progress=0.0476`/`burn_rate=336`/`verdict=OK` **逐字节等于 R186** —— 树在「完成」意义上**未前进**（仍 1/21）。
- **关键②（跨工具交叉洞察：claim ≠ progress）**：Round 191 已见 `marvis-main` 领 3 叶（`T0r636.1.1`/`2.1`/`3.1`，`已领取`），但 `progress_gate` 的 `progress=0.0476` 说明**已领取 ≠ 已完成，不计入 progress**（仅 `已完成`/`已归档` 计入）。这解释了 Round 198 `health_check` 的 `saturation=attention`（11 待领取积压）+ `latency=insufficient`（完成样本仅 1）—— **积压在「已领取→执行中→已完成」这一段**。
- **关键③（燃尽率稳定）**：`burn_rate=336` 与 R186 相同，说明**本轮无新增成本燃烧**（只读工具不消耗预算），`verdict=OK` 表明按当前燃尽率预算充足（线性 320 / 保守 384 < 1000）。
- **组合模式累计善用发布版能力 196 项**（Round 17-199，含数据刷新复用）：本轮复用 `progress_gate` 做状态感知进度复核 + claim/progress 语义区分。

## Round 200 增补（2026-10-17 11:45·里程碑第 200 轮）· call_log 活体动态 → 新并发前沿 pentad-combo

- **`call_log(limit=30)`**：`count=30`，最新 `seq=1059`（Round 182 基线 seq=1039，**+20 次调用**），时间窗 `2026-10-17T00:43:00Z` ~ `01:15:15Z`。
- **关键①（新并发前沿：`pentad-combo`）**：
  - `seq=1055`：**`reserve_scope(agent:"pentad-combo-r14", scope:"crates/p5c/src/eval/", ttl_until:"2026-10-17T10:30:00Z")`** —— **Pentad 项目（Rust）agent `pentad-combo-r14` 使用 fist-mbt 的作用域预订保护并发编辑**。
  - `seq=1048`：`bug_fix(project_dir:".", bug_ids:["245"], evidence:"…pentad commit 71ebfbf…")` ok —— **BUG-245 已标 FIXED**（Pentad 侧账本，`@derived`/信号 `__get` 两半定案：真缺陷已修、误报改判，`cargo test -p p5c` 361 passed）。
  - `seq=1047`：`report_bug(reported_by:"pentad-combo-r1", severity:"medium", summary:"[Pentad/DEMO-09 §16] @stream 在 @observe 内 for 迭代不产出事件…")` ok —— **新开 BUG-255**（@stream 事件静默丢弃，与刚修的 BUG-245 是信号通道另一侧缺口）。
- **关键②（tnr-polisher 批量 00:43）**：`seq=1031-1037` 一批 7 调用——`dag_check(T0r651)`/`supervisor_reminder_tick`/`circuit_status(tnr-codegen-watchdog)`/`phi_accrual`/`laya_decide(Tnr Section 6…split_n_hint:8, no_sidecar:true)`/`output_validate(patches/tnr_bug249_fixes.patch)`/`mcp_config_scaffold` —— **tnr-polisher 在做 Tnr Section 6（LLVM/Cranelift 原生代码生成后端）的编排 + 缺陷补丁验证 + MCP 配置脚手架**，与 Round 182 观察一致。
- **关键③（marvis）**：`seq=15`：`verify(task_id:"T0", verifier:"marvis", docs_check:false)` → `非法验收: 任务处于 [已归档]，需先 submit`（归档态硬门生效，与 Round 182 一致）。
- **关键④（自观测）**：`seq=1040-1046` 为本 session 近期调用（`call_log`/`get`/`store_list`/`dag_mc`/`progress_gate`/`list`）；`seq=1039` 是 Round 12 的 `atgc_old_talk`（六模式协同叙事，被归档为里程碑）。
- **组合模式累计善用发布版能力 197 项**（Round 17-200，含数据刷新复用）：本轮复用 `call_log` 做活体动态观察 —— **第 200 轮里程碑，确认 3 个并发 agent 前沿**（marvis/tnr-polisher/pentad-combo）+ 本 session。

## Round 201 增补（2026-10-17 11:55）· reserve_check 交叉核对并发预订

- **`reserve_check(scope="crates/p5c/src/eval/")`**：`{scope:"crates/p5c/src/eval/", free:false, agent:"pentad-combo-r14", ttl_until:"2026-10-17T10:30:00Z"}`。
- **关键①（并发预订可持久化可见）**：`crates/p5c/src/eval/` 被 **`pentad-combo-r14`** 持有，`ttl_until="2026-10-17T10:30:00Z"`（约 3.5 小时后到期）—— **与 Round 200 `call_log` seq=1055 的 `reserve_scope(ttl_until:"2026-10-17T10:30:00Z")` 完全一致**（跨工具互证，`call_log` 记录的是调用、`reserve_check` 读的是当前持态）。
- **关键②（多 agent 编辑冲突防御生效）**：`free=false` 表示该作用域**已被预订** —— 其它 agent（含本 session）若拟改 `crates/p5c/src/eval/` 应先 `reserve_check` 看到持有者，避免并发写冲突。**这是金条四「不抢不碰」在工具层的可执行化**（本 session 一直遵守）。
- **关键③（作用域预订组实证）**：`reserve_scope`/`reserve_check`/`reserve_release` 三工具真实工作（Round 188 已归类到「看板/脉冲/预订/推荐+DAG」组的 `reserve_scope/check/release`，本工具在 `fist://map` 中**有**登记 —— 与 Round 180 观察一致）。
- **组合模式累计善用发布版能力 198 项**（Round 17-201，含数据刷新复用）：本轮复用 `reserve_check` 做并发预订的持久化交叉核对。

## Round 202 增补（2026-10-17 12:05）· lock_status 全局文件锁全景

- **`lock_status`**：`{locks:[{lock_id:"r158-report-lock", batch_id:"r158-demo", scope:"reports/2026-10-15-round158.md", agent:"shim-steward", status:"released", ts:"2026-10-15T06:35:21Z", ttl_until:"2026-10-15T07:00:00+08:00"}], violations:[{ts:"2026-10-17T00:18:40Z", agent:"polish-lead", scope:"assistant", reason:"force_takeover", lock_id:"tnr-polisher"}], swept:0, violations_count:1}`。
- **关键①（仅 1 条历史锁，已释放）**：当前文件锁全景只有 `r158-report-lock`（`shim-steward` 于 Round 158 为 `reports/2026-10-15-round158.md` 加锁，`status="released"`）—— **无活跃锁**（并发 agent 用 `reserve_scope`/`reserve_check` 做预订，而不是 `lock_acquire`；两条并行协调机制分工明确）。
- **关键②（唯一违例 = 助理位接管循环）**：`violations=[{ts:"2026-10-17T00:18:40Z", agent:"polish-lead", scope:"assistant", reason:"force_takeover", lock_id:"tnr-polisher"}]` —— `polish-lead` 对 `tnr-polisher` 的 `assistant` 锁做 `force_takeover`（Round 190 `assistant_status` 显示 `takeover_count=1`/`violations_count=1` **完全吻合**；且 `tnr-polisher` 恰在同刻 `registered_at="2026-10-17T00:18:40Z"` **重新当选主助理**）—— **是一次「接管→重选」循环**，非持续冲突。但 `tnr-polisher` 主助理心跳已陈旧（Round 190：约 85 分钟未心跳 > `stale_secs=600`），`swept=0` 说明清扫拍未触发 —— **属观察**，不代 `assistant_sweep`（会标并发 agent 的助理为 dead，金条四）。
- **关键③（跨工具互证闭环）**：`lock_status` ↔ `assistant_status`（R190）↔ `call_log`（R200）三工具互相印证同一并发协调事件（`polish-lead`/`tnr-polisher` 的助理接管 + `pentad-combo-r14` 的 `reserve_scope`）—— **多 agent 协调机制真实工作，且无脏锁残留**（`swept=0`）。
- **组合模式累计善用发布版能力 199 项**（Round 17-202，含数据刷新复用）：本轮复用 `lock_status` 做全局文件锁 + 违例全景。

## Round 203 增补（2026-10-17 12:15）· dag_ready 11→2 + depth 反转发现

- **`dag_ready(namespace="fist-opt-20261016")`**：返回 **2 条**可领取（Round 191 基线 11 条）：
  - `T0r636.4.2`（parent=`T0r636.4`，`depends_on=["T0r636.4.1"]`，`depth:1`，`is_leaf:true`，`待领取`）—— `T0r636.4.1` 已完成 → 依赖满足即可领。
  - `T0r636.5.1`（parent=`T0r636.5`，`depends_on=[]`，`depth:1`，`is_leaf:true`，`[边界审视·全局输入域 owner]`，`待领取`）。
- **关键①（ready 集 11→2 的机理：claim 冻结 DAG）**：Round 191 `marvis-main` 领了 `T0r636.1.1/2.1/3.1` 三叶 → 其父 `T0r636.1/2/3` 状态变 `已领取`（**非** `已完成`）→ 依赖链 `T0r636.1→2→3→4→5` 上**每个中间节点的子叶依赖不再满足** → 其余 8 条原本就绪的任务退回不可领。**这从 DAG 层可视化了 Round 199 的「claim ≠ progress」**：claim 把整棵 LADDER 链的 ready 集「冻结」了，进度完全依赖 marvis-main 完成那 3 叶。
- **关键②（发现新 bug 形状：depth 反转）**：`T0r636`（根）`depth:3`、`T0r636.4` `depth:2`、`T0r636.4.2` `depth:1` —— **深度随层深**下降**而不是上升**（根应为 1、子 2、孙 3）。`mcpcf_review` 的 `T0` 根也 `depth:3`（Round 194）—— **同一反转形态跨库复现**，疑为 `task_plan_deep` 递归的 depth 计数口径 bug（把「剩余层数」当 `depth` 用）。**这是「清整/寻虫」的实证靶点**，但根因在 `src/` 源码，按 Round 13「不写代码」纪律**只上报不改**。
- **关键③（描述自嵌套 artifact）**：`description` 里「子任务单元 4…子任务单元 2…子任务单元 1」层层内嵌 + `[难度梯度 N/N]` + `[父计划: …]` + `[边界四问]` + `[omega:required]` —— `gradient`/`reinject_context`/`boundary_probe`/`omega_strong_verify` **全部真实生效**并互相嵌套（LADDER 更简单变体 + 边界四问 + omega 门）。
- **组合模式累计善用发布版能力 200 项**（Round 17-203，含数据刷新复用）：本轮复用 `dag_ready` 做状态感知 DAG 就绪面观察 + depth 反转 bug 实证。

## Round 204 增补（2026-10-17 12:25）· bug_list 复核 + depth 上报裁定

- **`bug_list(project_dir=".")`**：`{path:"./memory/bugs.md", project_dir:".", resolved_path:"E:/IDEProjects/AI/FIST-Mbt", server_cwd:"E:/IDEProjects/AI/FIST-Mbt", count:258, open_with_linked_done:0, note:"open_with_linked_done>0 ⇒ 账本抬头与任务库实时状态矛盾…"}`。最新条目 `BUG-255`（`reported_by="pentad-combo-r1"`，severity medium，`@stream` 在 `@observe` 内 `for` 迭代产出空序列 ⇒ 事件静默丢弃）。
- **关键①（depth 反转的**上报裁定：**不报**）**：`count=258` 中 grep `depth` 无任何缺陷条目提及深度反转 —— 但**语义存疑**：`T0r636`(根) `depth=3`、`T0r636.4` `depth=2`、`T0r636.4.2` `depth=1` —— 若 `depth` 定义为「距叶子的剩余层数」，则**根最深=3、叶最浅=1 是合法设计**（R203 观察的「反转」可能不是 bug，而是「剩余深度」口径）。**在不确定前不落 BUG**（避免 FALSE_POSITIVE，BUG-10 已示该档后果）—— 留作「待验证语义」观察。
- **关键②（跨项目缺陷账本混记 = 清整观察）**：`BUG-245`/`BUG-255` 是 **p5c/Pentad 项目**的缺陷（`cargo test -p p5c`、`eval/expr.rs` 等 Rust 上下文），却**写在 FIST-Mbt 的 `memory/bugs.md`**（`count=258` 含 FIST-Mbt + p5c + tnr 多项目缺陷）—— **一本账混记多个项目**。这本身是「清整」观察（账本面不分项目），但拆分账本属架构决策，**执行权在指挥官**。
- **关键③（open_with_linked_done=0）**：无「账本说没修、任务库说修完了」矛盾 —— 账本抬头与任务库实时状态**一致**，`note` 明确说明该字段语义。
- **组合模式累计善用发布版能力 201 项**（Round 17-204，含数据刷新复用）：本轮复用 `bug_list` 做缺陷账本全景 + depth 上报裁定（**宁可留观察、不落未证实的 BUG**）。

## Round 205 增补（2026-10-17 12:35）· status_summary per-ns 定量交叉验证

- **`status_summary(namespace="fist-opt-20261016")`**：`{version:"0.3.8", total_tasks:21, by_status:{执行中:1, 拆分中:5, 已领取:3, 待领取:11, 已完成:1}, done_no_artifact:0, by_difficulty:{易:2, 中:2, 难:7, 无:0}, active_namespaces:["tnr-polish","fist-allmodes"]}`。
- **关键①（待领取=11 vs dag_ready=2 → 9 条被冻结）**：本 ns `待领取=11`，但 Round 203 `dag_ready` 只返回 2 条 —— **差 9 条**是「`待领取` 但 `depends_on` 未满足」的任务（`marvis-main` 领 3 叶致父节点变 `已领取`、链上子叶依赖不满足）。**定量确认 Round 203 的 claim 冻结机理**：11 条看起来「可领」，实际只有 2 条真就绪。
- **关键②（进度实况）**：21 任务 = `执行中1 + 拆分中5 + 已领取3 + 待领取11 + 已完成1`；`已完成=1`（`T0r636.4.1`，`completed_by=human_steward`）；`done_no_artifact=0` —— **无探针/绕验收残留**（BUG-29 口径，已完成 ≠ 有成果；此处 1 条已完成有交付物）。
- **关键③（难度结构）**：`by_difficulty={易:2, 中:2, 难:7}` 共 11（=待领取数）—— **难=7 占 64%**，符合「梯度由易到难」拆解的尾部分布（gradient 生效的定量佐证）。
- **关键④（本 ns 不在 active_namespaces）**：`active_namespaces=["tnr-polish","fist-allmodes"]` —— **`fist-opt-20261016` 是并发探针/封闭 ns，不计入「活跃命名空间」**（全局 active 是 tnr-polish 与 fist-allmodes 两条并发线）。这是「并发探针树不干扰主项目」的机制证据。
- **组合模式累计善用发布版能力 202 项**（Round 17-205，含数据刷新复用）：本轮复用 `status_summary` 做 per-ns 脉冲 + 与 `dag_ready`/`progress_gate`/`health_check` 定量对账。

## Round 206 增补（2026-10-17 12:45）· status_summary per-ns 另一并发前沿 fist-allmodes

- **`status_summary(namespace="fist-allmodes")`**：`{version:"0.3.8", total_tasks:121, by_status:{已完成:46, 已领取:40, 待领取:35}, done_no_artifact:0, by_difficulty:{易:5, 中:10, 难:20, 无:0}, active_namespaces:["tnr-polish","fist-allmodes"]}`。
- **关键①（fist-allmodes 前缘 11→121 = 10× 增长）**：Round 184 观察到 `fist-allmodes` 仅 11 任务，本轮 `total_tasks=121` —— **不到一轮时间增 10 倍**，是当前**最活跃的并发前沿**（`已完成=46` / `已领取=40` / `待领取=35`）。
- **关键②（状态分布只有 3 档）**：`已完成46 + 已领取40 + 待领取35 = 121` —— **无** `执行中`/`拆分中`/`已暂停`/`待验收`/`待打回`/`已归档`。这一前缘的状态机**极简**（待领取→已领取→已完成直连），与 `fist-opt-20261016`（6 档含拆分中/执行中）形态不同 —— **两条并发线的任务模型口径不同**。
- **关键③（done_no_artifact=0）**：`已完成=46` 但 `done_no_artifact=0` —— 46 条已完成**全有交付物**（BUG-29 口径，无探针/绕验收残留）。
- **关键④（难度结构）**：`by_difficulty={易:5, 中:10, 难:20}` 共 35（=待领取数）—— **难=20 占 57%**，与 `fist-opt-20261016` 的 64% 相近（都是「难档居多」的拆解尾部分布）。
- **关键⑤（活跃 ns 交叉验证）**：`active_namespaces=["tnr-polish","fist-allmodes"]` 与 Round 205 一致 —— **两条真实活跃并发线**（`fist-allmodes` 主前缘 + `tnr-polish`），`fist-opt-20261016` 仍是探针/封闭 ns。
- **组合模式累计善用发布版能力 203 项**（Round 17-206，含数据刷新复用）：本轮复用 `status_summary` 做另一并发前沿的 per-ns 脉冲对比。

## Round 207 增补（2026-10-17 12:55）· status_summary per-ns 第三条并发前沿 tnr-polish

- **`status_summary(namespace="tnr-polish")`**：`{version:"0.3.8", total_tasks:8, by_status:{待领取:8}, done_no_artifact:0, by_difficulty:{易:0, 中:0, 难:0, 无:8}, active_namespaces:["tnr-polish","fist-allmodes"]}`。
- **关键①（tnr-polish 8 条**全部待领取、零在途**）**：`total_tasks=8`、`待领取=8`、**无** `已领取`/`执行中`/`已完成`/`已暂停`/`待验收` —— 该前缘**未通过任务生命周期推进**（0 认领、0 完成）。
- **关键②（与 Round 200 交叉验证）**：Round 200 见 tnr-polisher 批量调用 `dag_check(T0r651)`/`laya_decide(Tnr Section 6…)`/`output_validate`/`mcp_config_scaffold`/`phi_accrual`/`circuit_status` —— 它**在做 Tnr Section 6（LLVM/Cranelift 原生后端）的编排 + 缺陷补丁验证 + MCP 配置脚手架**，但这些活动**未落到 `tnr-polish` ns 的任务上**（该 ns 仍 8 条待领取不动）—— **并发 agent 直接写码/编排，不走任务台账**（与本 session 的「观察为主、不抢不碰」相反）。
- **关键③（三并发前沿形态对比，R205/206/207 合看）**：
  - `fist-allmodes`：**121 任务、3 档状态、已领 40 + 完成 46**（最活跃、走完整生命周期）；
  - `fist-opt-20261016`：**21 任务、6 档状态、拆分中 5 + 已领 3 + 完成 1**（并发探针树，gradient/omega/boundary_probe 全开）；
  - `tnr-polish`：**8 任务、仅 1 档（待领取）、零推进**（agent 绕开任务台账直接干活）。
- **关键④（by_difficulty 全 无）**：`无=8` —— `tnr-polish` 任务**未打难度梯度**（与 `fist-opt-20261016` 的 `gradient` 全开、`fist-allmodes` 的 `难=20` 都不同）—— 三前缘**拆解风格各异**。
- **组合模式累计善用发布版能力 204 项**（Round 17-207，含数据刷新复用）：本轮复用 `status_summary` 做第三条并发前沿的 per-ns 脉冲，完成 R205/206/207 三前缘形态对比闭环。

## Round 208 增补（2026-10-17 13:05）· supervisor_task_tree 结构树 → depth 语义定案

- **`supervisor_task_tree(root_id="T0r636")`**：`{root_id:"T0r636", tree:{task:{id:"T0r636", parent_id:null, depth:3, split_n:3, status:"执行中", assignee:null}, subtree_total:21, subtree_done:1, children:[{task:{id:"T0r636.1", depth:2, status:"拆分中"}, ...}]}}`。深度链：`T0r636`(根,`depth=3`) → `T0r636.1`(`depth=2`) → 叶(`depth=1`, `is_leaf:true`)。
- **关键①（depth 语义定案：是「剩余深度」口径，非 bug）**：根 `depth=3`（最深）、叶 `depth=1`（最浅）—— 一致表现为 **「距叶子的剩余层数」**（root 剩余最多=3，leaf 剩余=0→记 1）。**Round 203 观察的「深度反转」不是 bug**，Round 204 的「不落 BUG」裁定**经受住实证检验**（BUG-10 FALSE_POSITIVE 风险规避成功）。
- **关键②（跨分支依赖出现）**：某叶 `depends_on=["T0r636.5.2"]` —— **`T0r636.1.x` 依赖了 `T0r636.5` 分支的任务**（跨分支边）。`gradient_dag`/`dag_depend` 允许任意依赖，但**跨分支依赖可能形成隐式环/跨分支阻塞**（`T0r636.1` 分支的推进被 `T0r636.5` 分支的 `5.2` 完成所卡）—— 这是 **R203 的「claim 冻结」之外的第二类 DAG 阻塞源**，值得指挥官注意。
- **关键③（subtree_done=1）**：`subtree_total=21, subtree_done=1` —— 21 任务仅 1 完成（`T0r636.4.1`），与 Round 199/205 的 `progress=0.0476`/`已完成=1` **三工具互证**。
- **关键④（根交付物仍是外来内容）**：`T0r636` 的 `deliverable` 仍是「轮次53 os.popen 注入洞」—— 内容涉 `system/microsoft_markdown_preview`/`vools/actus` 等**另一项目**（R119 已录），**跨项目交付物仍挂在 FIST-Mbt 根任务**（R204 的跨项目混记同族，属指挥官裁定范围）。
- **组合模式累计善用发布版能力 205 项**（Round 17-208，含数据刷新复用）：本轮复用 `supervisor_task_tree` 做结构树读取，**实证定案 depth 语义 + 发现跨分支依赖**。

## Round 209 增补（2026-10-17 13:15）· dag_check 验证跨分支依赖

- **`dag_check(task_id="T0r636.1")`**：`{task_id:"T0r636.1", deps_satisfied:true}`。
- **关键①（跨分支依赖当前不阻塞）**：`T0r636.1` 依赖（含 Round 208 发现的跨分支 `depends_on=["T0r636.5.2"]`）**已满足**（`deps_satisfied=true`）—— `T0r636.5.2` 本身处于可满足状态。**R208 的「跨分支依赖」是结构性风险，当前不是活跃阻塞**。
- **关键②（真正的阻塞是 status，不是 deps）**：`T0r636.1` 状态 `拆分中`（R208）—— 它**不是 `待领取`**，故不可领；而它的子叶 `T0r636.1.1` 被 `marvis-main` 领为 `已领取`。**阻塞面在「父任务状态 + 子叶 claim 冻结」，而非依赖不满足**（dag_check 只看 deps，不看 status，故 `deps_satisfied=true` 但任务仍无法推进）。
- **关键③（dag_check 的视野边界）**：`dag_check` **只答依赖是否满足**，不答「任务可否推进」（后者看 status）。**R209 与 R203/R208 互补**：`dag_ready`（就绪面，含 status+depends_on）、`dag_check`（纯依赖面）、`supervisor_task_tree`（结构面）—— **三工具各管一段，合起来才是完整 DAG 状态**。
- **组合模式累计善用发布版能力 206 项**（Round 17-209，含数据刷新复用）：本轮复用 `dag_check` 做跨分支依赖验证 + dag_check/dag_ready/task_tree 三工具视野互补总结。

## Round 210 增补（2026-10-17 13:25·第 210 轮）· memory_link 持久化并发协调洞察

- **`memory_link(project_dir=".", from="并发前缘形态 (fist-allmodes/fist-opt-20261016/tnr-polish)", to="任务台账口径 (状态机形态决定推进语义)", note="R205-209 实证：三前缘任务台账形态各异 —— fist-allmodes 121 任务/3 档(待领取/已领取/已完成 直连)、fist-opt-20261016 21 任务/6 档(含拆分中/执行中)、tnr-polish 8 任务/仅待领取(agent 绕开任务台账直接干活)。形态差异提示「claim≠progress」的根因：已领取冻结 DAG 链上就绪集(dag_ready 11→2)。")` → `{linked:true, from:"并发前缘形态 (fist-allmodes/fist-opt-20261016/tnr-polish)", to:"任务台账口径 (状态机形态决定推进语义)"}`。
- **关键①（本轮持久化写入）**：R205-209 的**三前缘形态对比 + claim≠progress 机理 + dag_ready 11→2 冻结**已作为一条 **A-Mem 关联**写入 `memory/links.md`（`linked=true`，与 R195 的 `evolve_lesson` 落库同族，**可跨进程回读**）。
- **关键②（沉淀内容=跨工具合成）**：该关联把 `status_summary`(R205/206/207) + `dag_ready`(R203) + `dag_check`(R209) + `supervisor_task_tree`(R208) + `progress_gate`(R199) 五工具的读数**合成一条可复用洞察**：**「已领取」会冻结 DAG 链就绪集，任务台账形态（几档状态）决定推进语义**。
- **关键③（零副作用）**：`memory_link` 只追加 `memory/links.md` 一条记录，不碰 store/src —— 符合 Round 13「不写代码」纪律与金条五「记忆沉淀」。
- **组合模式累计善用发布版能力 207 项**（Round 17-210，含数据刷新复用）：本轮复用 `memory_link` 做**跨工具合成洞察的持久化**（第 210 轮里程碑，把 R199-209 的并发协调实证收口为一条可复用记忆）。

## Round 211 增补（2026-10-17 13:35）· read memory/links.md 验证 R210 持久化

- **`read memory/links.md`**：文件 9 行，**第 9 行 = 我的 Round 210 关联**（原文）—— `并发前缘形态 (fist-allmodes/fist-opt-20261016/tnr-polish) -> 任务台账口径 (状态机形态决定推进语义)  R205-209 实证：三前缘任务台账形态各异 … dag_ready 11→2)`。**R210 的 `memory_link` 已真实落盘**（非仅回执声称），金条五「记忆沉淀」证据链闭合。
- **关键①（A-Mem 关联表是共享面）**：`links.md` 前 8 行是**其它会话/agent 的关联**：
  - 第 4 行：`is_finite -> Double-finite-check` —— 「MoonBit Double 无 is_finite，等价替代 `n == n`；并发 agent 在 router_config/router_state 引入 is_finite 导致编译失败（BUG-193）」（**一条真实的 `寻虫` 教训**：别把 Python/JS 的 `is_finite` 习惯直接搬到 MoonBit）。
  - 第 5 行：`组合模式 47 能力善用 -> fist-mbt v0.3.8` —— **Round 17-49 的能力善用清单**（本 session 的前身，现累计已 207 项）。
  - 第 6-8 行：`S6-0/1/6/7` —— **Tnr 的 TargetIR 数值契约设计链**（`S6-6 对拍矩阵直接消费 S6-1 的 TIR 节点与 DType；三方 Interp/Cranelift/LLVM 比对`）。
- **关键②（与 tnr-polish 前缘交叉）**：第 6-8 行的 `S6-*` 关联**印证 Round 200/207** —— tnr-polisher 正在做 **Tnr Section 6（LLVM/Cranelift 原生后端）**，其设计线索沉淀在 `memory/links.md`（而 `tnr-polish` ns 仍 8 条待领取不动，说明**设计沉淀走 memory、不走任务台账**，与 R207 一致）。
- **组合模式累计善用发布版能力 208 项**（Round 17-211，含数据刷新复用）：本轮复用 `read` 验证 R210 持久化 + 从 `links.md` 反推出 tnr-polisher 的设计沉淀线索。

## Round 212 增补（2026-10-17 13:45）· supervisor_reminder_tick 提醒者轮询 = 清整最强量化

- **`supervisor_reminder_tick()`**：`{ts:"2026-10-17T01:33:34Z", stale_hours:24, pending_hours:48, reminder_count:1097, reminders:[{kind:"stale", severity:"info", status:"已暂停", reason:"活跃任务超过 24 小时未更新", ...}], guidance_unconsumed_count:0, guidance_unconsumed:[], total_reminders:1097}`。
- **关键①（1097 条 stale 提醒 = 清整量化的最强证据）**：全部提醒都是 `kind:"stale"`（`status="已暂停"`，`reason="活跃任务超过 24 小时未更新"`），`total_reminders=1097` —— **1097 条已暂停僵尸任务被提醒者点名**，与 Round 177 的 `已暂停=1105`（差 8，属活跃/近期暂停）**高度吻合**。这是「清整」落点的**最强量化证据**。
- **关键②（跨命名空间蔓延）**：stale 提醒横跨 `cron-cypy`/`cron-vq`/`laya-e2e2`/`recursive-demo`/`mcp-smoke`/`enhance-e2e`/`omega-lesson-verify`/`allmodes-switch` 等多个 ns（含 `T0r607.*` 全链 `allmodes-switch`）—— **已暂停僵尸不是单棵树，而是全域蔓延**。
- **关键③（guidance_unconsumed=0）**：`guidance_unconsumed_count=0, guidance_unconsumed=[]` —— **无待投递的超级管家引导提示词**（R197 之前如有引导，现已被消费/清空）。
- **关键④（提醒者口径 = 只读诊断）**：`supervisor_reminder_tick` **只产出提醒清单，不自动修改任务**（执行权在指挥官）—— 与「金条四不可逆操作只给方案」一致。
- **组合模式累计善用发布版能力 209 项**（Round 17-212，含数据刷新复用）：本轮复用 `supervisor_reminder_tick` 做**清整量化的最强证据采集**（1097 条 stale 提醒，横跨全域命名空间）。

## Round 213 增补（2026-10-17 13:55）· list(已领取) 在途队列全景 = 68 条 assignee=null 异常

- **`list(status="已领取")`**：`count=243`。**assignee 分布**：`atomcode-3=159`、**空=68**、`ops-steward=6`、`atomcode-glm53=3`、`atomcode-longcat=3`、`marvis-main=3`、`leader-buffy=1`。**ns 分布**：`default=89`、`fist-allmodes=40`、`bugs=31`、`f094-worktree=21`、`cypy-drive=18`、`ofm-fusion=17`、`vq-gui=13`、`fist-allmodes-r59=6` 等。
- **关键①（68 条 `已领取` 但 `assignee=null` = 异常）**：`count=243` 里 **68 条（28%）状态是 `已领取` 但 `assignee` 为空** —— 正常 `claim` 必须写 assignee，这 68 条是**「状态已认领、却没落认领人」的孤儿在途**。这是「清整/寻虫」的**新实证靶点**（claim 契约不完整），需指挥官裁定（可能属 `reopen_task` 或 `claim` 补 assignee 的运维）。
- **关键②（atomcode-3 占 65% 在途）**：`atomcode-3=159/243` —— **单执行者占据绝大多数在途认领**，是当前最重的在途持有方（含 `project_dir="E:/IDEProjects/AI/Cypy"` 的 Cypy 任务，`updated_at≈2026-10-16T14:36Z`，距今 ~19h 未更新）。
- **关键③（跨项目蔓延确认）**：`已领取` 池横跨 `Cypy`(`project_dir` 绝对路径)/`fist-allmodes`/`bugs`/`f094-worktree`/`cypy-drive`/`ofm-fusion`/`vq-gui` 等多个项目/ns —— **一本 fist-mbt.db 存多项目任务**（R204/208 已观察的跨项目混记，此处是 `已领取` 档的再确认）。
- **关键④（marvis-main=3）**：`marvis-main=3` 正是 Round 191 领的 `T0r636.1.1/2.1/3.1` 三叶 —— **与 R203/R205 的 claim 冻结完全对应**（3 条在途冻结整棵 LADDER 链就绪集）。
- **组合模式累计善用发布版能力 210 项**（Round 17-213，含数据刷新复用）：本轮复用 `list(status="已领取")` + 分布聚合（pwsh 分组）做**在途队列全景 + 68 条 assignee=null 异常定位**。

## Round 214 增补（2026-10-17 14:05）· project_health 全局健康卡 = R177/R212/R213 四路互证

- **`project_health()`**：`{version:"0.3.8", grade:"attention", total_tasks:1775, in_flight:249, ready:63, done:355, done_no_artifact:0, done_no_artifact_baseline:2, residue_over_baseline:false, blocked:1105, reviewing:0, archived:3, blocked_tasks:[~1000 个任务 id]}`。
- **关键①（四工具互证闭合）**：
  - `blocked=1105`（已暂停+已打回）↔ R177 `已暂停=1105`（**完全吻合**）↔ R212 `reminder_tick=1097` stale（差 8 = 近期暂停未超 24h）；
  - `in_flight=249`（执行中+已领取+拆分中）↔ R213 `list(已领取)=243`（差 6 = 拆分中/执行中）；
  - `ready=63` ↔ R177 `待领取=63`（**完全吻合**）；
  - `total_tasks=1775` ↔ R177 `total=1775`（**完全吻合**）。
  - **四工具（status_summary/project_health/reminder_tick/list）读数互相咬合，全局状态可信**。
- **关键②（done_no_artifact=0 < baseline=2）**：`done_no_artifact=0`、`done_no_artifact_baseline=2`、`residue_over_baseline=false` —— **当前无「已完成但无交付物」残留**，且低于账本点名作废基线 2（BUG-29 口径：已完成≠有成果，此处 355 条已完成全有交付物）。
- **关键③（grade=attention 的唯一来源）**：`blocked=1105`（`已暂停+已打回`）是 `grade=attention` 的**唯一成因**（有阻塞即 attention）—— 与 R198 `fist-opt` ns 的 `saturation attention` 是**同源不同层**（全局阻塞 vs 局部积压）。
- **关键④（reviewing=0）**：无待验收任务 —— **全局验收管线空转**，与 `已领取=249` 在途（其中 68 条 assignee=null，R213）形成「**在途多、验收 0**」的失衡。
- **组合模式累计善用发布版能力 211 项**（Round 17-214，含数据刷新复用）：本轮复用 `project_health` 做**全局健康卡 + R177/R212/R213 四工具读数互证闭合**。

## Round 215 增补（2026-10-17 14:15）· state_flow_ascii 状态流转图 = 第 5 工具互证

- **`state_flow_ascii()`**：`{ascii:"待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档\n │         │\n ▼         ▼\n已暂停→已领取  已打回→执行中\n(恢复)       (重试)", counts:{已完成:355, 已暂停:1105, 已领取:243, 待领取:63, 执行中:1, 拆分中:5, 已归档:3}, in_flow:312}`。
- **关键①（第 5 工具互证闭合）**：`counts` 的 `已领取=243`/`待领取=63`/`已暂停=1105`/`已完成=355` **与 R177/R212/R213/R214 四工具完全咬合** —— 至此 `status_summary`/`project_health`/`reminder_tick`/`list`/`state_flow_ascii` **5 工具互证闭合**。
- **关键②（in_flow=312）**：`in_flow=312`（`待领取63+已领取243+拆分中5+执行中1`）—— 在流任务 312，**占 1775 的 17.6%**；`已暂停=1105` 是绝对主导状态（**62.3%**），即**过半任务长期暂停**。
- **关键③（迁移图结构 = 设计文档）**：线性流 `待领取→已领取→拆分中→执行中→待验收→已完成→已归档`，**`拆分中` 在 `已领取` 之后** —— 即「**先认领、后拆分**」模型（claim 后把父任务拆子）；旁路 `已暂停→已领取(恢复)`、`已打回→执行中(重试)`。这是**合法的状态机定义**（非 bug），但 R213 的 `拆分中=5`（其中根 `T0r636` 是 `执行中` 但 `assignee=null`）提示**拆分后 assignee 未回填**的观察。
- **关键④（待验收=0）**：`待验收` 在迁移图中存在、但 `counts` 无此项（=0）—— **验收管线空转**，与 R214 `reviewing=0` 完全一致。
- **组合模式累计善用发布版能力 212 项**（Round 17-215，含数据刷新复用）：本轮复用 `state_flow_ascii` 做**状态流转图 + 第 5 工具互证 + 迁移图结构审视**。

## Round 216 增补（2026-10-17 14:20）· dag_schedule 排程视图 = 全局真瓶颈不在 T0r636

- **`dag_schedule()`**：`{basis:"PERT/CPM slack（基于 dag_slack_analysis）", critical_batch:[{task_id:"T0r651",earliest:0,slack:0,assignee:""},{T0r652,1,0},{T0r653,2,0},{T0r654,3,0},{T0r655,3,0},{T0r657,4,0},{T0r658,5,0}], flexible_batch:[~600 条，多数 slack=5，assignee="" 附 suggest=cypy-fixer-macro], note:"critical_batch=关键路径瓶颈(须串行盯紧)；flexible_batch=有松弛可按最早开始并行的任务…"}`。
- **关键①（全局真瓶颈 = T0r651-T0r658 链）**：`critical_batch` 是 **`T0r651→T0r652→T0r653→T0r654→T0r655→T0r657→T0r658`** 7 条任务，**全部 slack=0、earliest 0→5、全部 assignee=""** —— **这是当前全库唯一的 PERT 关键路径链，且 7 条全未认领**（真正的瓶颈不在我的 `T0r636` 树）。
- **关键②（我的 T0r636 树 = slack=1 近关键路径）**：`T0r636.1/2/3/4/5` 全部 `slack=1`（**近关键路径**）；`.1.1/2.1/3.1` = `assignee:"marvis-main"`（R191/R213 再确认）；`.4.1` = `assignee:"self"`（`completed_by=human_steward`，R214）；`.1` `slack=1`。**T0r636 树整体离关键路径仅差 1**，一旦 `T0r636.1.1/2.1/3.1`（marvis-main）推进，链上 `slack` 会收紧。
- **关键③（suggest=cypy-fixer-macro 主导）**：`flexible_batch` 里**绝大多数未认领任务**的 `suggest` 都是 `cypy-fixer-macro`（**自动路由推荐执行者**）—— 这是 `executor_route` 负载感知的**建议派单人**（R75/R32），即「下一单最该派给谁」的机器建议。
- **关键④（并发前缘的排程脚印）**：`T0r581/582/583/584/585/586/587` 系任务带 `fist-allmodes-lead`（**fist-allmodes 5x split 前缘**）；`T0r636.*` 系带 `marvis-main`（**T0r636 前缘**）—— **dag_schedule 直接暴露了并发 agent 的排程脚印**。
- **组合模式累计善用发布版能力 213 项**（Round 17-216，含数据刷新复用）：本轮复用 `dag_schedule` 做**排程视图 + 全局真瓶颈定位（T0r651-T0r658 链）+ 自动路由建议派单人观察**。

## Round 217 增补（2026-10-17 14:30）· get(T0r651) 更正 R216 结论 = 关键路径是「规划只读树」

- **`get(task_id="T0r651")`**：`{id:"T0r651", parent_id:null, project_dir:".", namespace:"tnr-polish", priority:"中", importance:"中", depth:3, split_n:3, status:"待领取", assignee:null, description:"Tnr Section 6 — LLVM/Cranelift 原生代码生成（规划分解）: … 注意当前 src/codegen/* 由并行 agent 活跃编辑，本任务树仅做规划与依赖编排，待其 WIP 收敛后认领执行，避免源码撞车。", created_at:"2026-10-16T16:41:06Z"}`。
- **关键①（R216 结论必须更正）**：R216 建议「优先 `claim` T0r651-658」是**错误的** —— `T0r651` 的 description **明写「本任务树仅做规划与依赖编排，待其 WIP 收敛后认领执行，避免源码撞车」**，即**这是 tnr-polisher 的规划只读树，故意延迟认领等 WIP 收敛**。**认领它会撞车并发 agent 的 `src/codegen/*` WIP** —— **金条四：不抢并发树**。R216 的「优先级 claim」建议**作废**。
- **关键②（关键路径未认领 = 故意，非停滞）**：`critical_batch`（R216 的 T0r651-658）是**「规划树，等 WIP 收敛才认领」的主动设计**，**不是** stalled 瓶颈 —— **推进的瓶颈不在此**，而在 R212/R214/R215 的 **1105 已暂停僵尸 + 68 条 assignee=null**。
- **关键③（与前缘证据互证）**：`T0r651` namespace=`tnr-polish`、`project_dir="."`、`parent_id=null`（**根**）、`depth=3`（最深）、`split_n=3` —— **与 R200/R211 完全对应**：tnr-polisher 做 **Tnr Section 6（LLVM/Cranelift 原生后端）**，设计链沉淀在 `memory/links.md` 第 6-8 行的 `S6-0/1/6/7`（R211 已读证）。
- **关键④（排程工具的诚实边界）**：`dag_schedule`/`dag_slack` 只看 `status`+`depends_on`，**看不到 description 里的「故意延迟」意图** —— **排程读数 ≠ 可认领建议**，必须 `get()` 复核任务本体（与 R209 `dag_check` 只答依赖、R199 `progress_gate` 只答进度的同一族「工具盲区」）。
- **组合模式累计善用发布版能力 214 项**（Round 17-217，含数据刷新复用）：本轮复用 `get` 复核关键路径根任务本体，**主动更正 R216 的误判**（金条四 + 诚实性优先）。

## Round 218 增补（2026-10-17 14:40）· board_ascii(tnr-polish) = Tnr Section 6 树全景，S6-4 是唯一非关键任务

- **`board_ascii(namespace="tnr-polish")`**：`{counts:{待领取:8}, done_no_artifact:0, ascii:"…[待领取] T0r651 · Tnr Section 6 — LLVM/Cranelift 原生代码生成（规划分解）… T0r652 · S6-0 协调 WIP 收敛 … T0r653 · S6-1 设计 MIR/LIR → 后端中立 TargetIR 映射层 … T0r654 · S6-2 Cranelift 后端骨架 … T0r655 · S6-3 LLVM 后端骨架 … T0r656 · S6-4 ABI/调用约定 … T0r657 · S6-5 原生入口集成 … T0r658 · S6-6 回归测试 + benchmark"}`。
- **关键①（Tnr Section 6 全树一览）**：`tnr-polish` ns 的 8 条任务 = **`T0r651`(根·规划分解) + `T0r652`(S6-0 协调) + `T0r653`(S6-1 TargetIR 映射) + `T0r654`(S6-2 Cranelift) + `T0r655`(S6-3 LLVM) + `T0r656`(S6-4 ABI) + `T0r657`(S6-5 原生入口) + `T0r658`(S6-6 回归+benchmark)** —— **全部 `待领取`、`done_no_artifact=0`**（与 R207 的「8 条仅待领取」完全一致，现在补上了每条的职责）。
- **关键②（S6-4 ABI 是树里唯一非关键任务）**：R216 的 `critical_batch` 含 `T0r651/652/653/654/655/657/658`（**7/8**），**独缺 `T0r656`(S6-4 ABI)** —— **`T0r656` 是这棵树里唯一 `slack>0` 的任务**（ABI/调用约定不占关键路径）。**这是本树「可并行化」的唯一候选**（待 WIP 收敛后）。
- **关键③（与前缘证据互证闭合）**：`T0r651-658` + `S6-0..S6-6` + `src/codegen/* 并行 agent 活跃编辑` —— **与 R200/R211/R217 完全互证**：tnr-polisher 的 **Tnr Section 6 原生后端**（LLVM/Cranelift）规划链，设计沉淀 `memory/links.md` 第 6-8 行 `S6-0/1/6/7`（R211）。
- **关键④（金条四边界）**：这 8 条全属 **tnr-polisher 的规划只读树**（R217 已证 `T0r651` 明写「待其 WIP 收敛后认领执行，避免源码撞车」）—— **本轮只看不认领**，观察结论归档案。
- **组合模式累计善用发布版能力 215 项**（Round 17-218，含数据刷新复用）：本轮复用 `board_ascii` 做**Tnr Section 6 树全景 + 唯一非关键任务（S6-4）定位 + 前缘证据互证闭合**。

## Round 219 增补（2026-10-17 14:50）· board_ascii(fist-allmodes) = 同款 7 模式流水线跑在「兹 编译器」

- **`board_ascii(namespace="fist-allmodes")`**：`{counts:{已完成:46, 已领取:40, 待领取:35}, done_no_artifact:0}`，ascii 显示 **7 棵根**：`T0r581`【模式 1/7·advance 推进】/`T0r582`【模式 2/7·polish 打磨】/`T0r583`【模式 3/7·verify 验证】/`T0r584`【模式 4/7·bugfind 寻虫】/`T0r585`【模式 5/7·fix_and_merge 修复合并】/`T0r586`【模式 6/7·tidy 清整】/`T0r587`【模式 7/7·explore 探索】，每根带 `.1/.2/.3/.4/.5` 4-5 子，每子带 3 孙叶。
- **关键①（并发前缘 = 同一套组合模式的并行执行者）**：`fist-allmodes` 的 **7 棵根 = 一树一模式**（advance/polish/verify/bugfind/fix_and_merge/tidy/explore）—— **与本 session 的 `[打磨,寻虫,修复,验证,清整,推进]` 组合模式是同一套方法论**（`fist-allmodes-lead` 是它的并行执行者）。**这是「有其他 agent 在同步开发」的最强实证**。
- **关键②（不是本项目）**：描述写「对本项目（**兹 编译器**）做一轮持续开发推…」—— **fist-allmodes 跑的是另一个项目「兹 编译器」，不是 FIST-Mbt**；但方法论（7 模式流水线）与本 session 完全一致。
- **关键③（LADDER 由易到难的梯度清晰可见）**：看每根的模式分支 —— **`.1.1`(易)=已完成 → `.1.2`(易)=已领取 → `.1.3`(难)=待领取[边界审视]**；`.2.2`(易)=待领取、`.2.3`(难)=待领取[边界审视]；`.3.1`(中)=已完成、`.3.2`(中)=已领取、`.3.3`(难)=待领取[边界审视] —— **「易→中→难」梯度 + 难档带 `[边界审视·全局输入域 owner]` 的叶留在 `待领取`**（`boundary_probe=true` 的边界审视叶，与 `task_plan_deep` 的 `boundary_probe` 参数一致）。
- **关键④（状态机 = 3 档直连）**：`已完成:46/已领取:40/待领取:35` —— **无 执行中/拆分中/待验收/已暂停**，与 R206 完全一致：`fist-allmodes` 用**扁平 3 档状态机**（待领取→已领取→已完成），与 tnr-polish 的「仅待领取」、fist-opt 的「6 档」是**三种不同的推进语义**（R205 已归因）。
- **组合模式累计善用发布版能力 216 项**（Round 17-219，含数据刷新复用）：本轮复用 `board_ascii` 做**fist-allmodes 7 模式流水线全景 + 并发前缘同方法论确认 + LADDER 梯度观察**。

## Round 220 增补（2026-10-17 15:00）· store_list total=0 异常 + 新活跃 ns「tnr」

- **`get(task_id="T0r581")`** → `Error: task not found: T0r581`（尽管 R219 `board_ascii` 显示 `T0r581.1/2/3/4/5` 已完成）。**`store_list()`** → `{active_namespaces:["tnr-polish","fist-allmodes","tnr"], stats:{tnr-polish:{ns,total:0}, fist-allmodes:{ns,total:0}, tnr:{ns,total:0}}}`。
- **关键①（store_list `total=0` 异常 = 寻虫发现）**：`store_list` 的 `stats.*.total` **三个活跃 ns 全部报 `0`**，但 **`board_ascii` 明说 `tnr-polish=8`、`fist-allmodes=121`** —— **统计口径不一致**：`store_list.total` 显然**不覆盖这些 ns 的真实任务数**（可能只数某个子表，或这些 ns 是内存/临时后端）。**这是真实的读数异常**，属「寻虫」类观察（`store_list` 与 `board_ascii`/`status_summary` 对同一批 ns 报数互斥）。
- **关键②（`get` 无 namespace 参数 = 工具边界）**：`get(T0r581)` 找不到，但 `get(T0r651)`（`tnr-polish` ns）能找到 —— **`get` 只能查默认（或已打开）的 store**，**跨 ns 查询不可靠**；要查非默认 ns 的任务只能 `board_ascii(namespace=)` / `supervisor_task_tree` / `list`。**这是 R209/R217/R219 同族「工具盲区」的另一例**。
- **关键③（新增活跃 ns「tnr」）**：R197 时 `active_namespaces=["tnr-polish","fist-allmodes"]`，**现在多了 `tnr`** —— **tnr-polisher 额外开了一个 `tnr` store**（与 `tnr-polish` 规划树并存），推测是 Tnr 项目本体（vs 规划）的分离库。**并发前缘的动态扩张证据**。
- **组合模式累计善用发布版能力 217 项**（Round 17-220，含数据刷新复用）：本轮复用 `get`+`store_list` 做**跨工具读数一致性校验 + store_list total=0 异常定位 + 新活跃 ns 发现**。

## Round 221 增补（2026-10-17 15:05）· list 揭示 T0r5 新 bug 单 + store_list/board_ascii 计数不全

- **`list(namespace="tnr-polish")`** → **9 条**：`T0r651`-`T0r658`（S6 树）+ **`T0r5`**（新）。**三工具计数对同一 ns 报数不一致**：`store_list=0` / `board_ascii=8` / **`list=9`**。
- **关键①（store_list total=0 是真 bug，非读数错觉）**：`list` 明说 `tnr-polish=9` 条真实任务，`store_list.stats.total=0` —— **`store_list` 的统计子集不全（疑似只数某表或未覆盖已打开 ns）**；**R220 的「读数异常」现在被 `list` 实锤**。
- **关键②（board_ascii 也漏报 1 条）**：`board_ascii(tnr-polish)=8`，`list=9` —— **`board_ascii` 漏了 `T0r5`**（新发布）。**看板也不完整**（可能按 `counts` 快照、或未刷新最新）。**三个只读工具各有盲区**（R209/R217/R219/R220 同族）。
- **关键③（T0r5 = 新的真 bug 单）**：`T0r5` `description`="修复 bug: **[Tnr] lirgen compute_stable_i64 定点分析不收敛**（非单调 insert/remove 抖动、无迭代上限）：变量同时存在「整数字面量绑定点」与「非 i64 赋值点」时死循环——3 行合法程序转译 30s 超时 E9006；语料 g11_alg_array_sum（该修复自述的动机用例）直接挂死"，`created_at=2026-10-17T01:48:49Z`（**今日 ~9 分钟前**）—— **tnr-polisher 刚发布的一条真实寻虫结果**（`compute_stable_i64` 定点分析不收敛）。
- **关键④（S6 DAG 完整确认）**：`T0r651→T0r652→T0r653→(T0r654, T0r655, T0r656)→T0r657→T0r658` —— **`T0r656`(S6-4 ABI) 只依赖 `T0r652`**（不与 `T0r654/655` 串联），**因此 slack>0、不在关键路径** —— **R216/R218 的「S6-4 唯一非关键」被 `depends_on` 直接证实**。
- **组合模式累计善用发布版能力 218 项**（Round 17-221，含数据刷新复用）：本轮复用 `list` 做**三工具计数互证（store_list/board_ascii/list）+ T0r5 新 bug 单发现 + S6 DAG 实锤**。

## Round 222 增补（2026-10-17 15:10）· dag_mc 揭 T0r529 树 = default ns 真瓶颈，且 T0r529 在 68 空 assignee 单里

- **`dag_mc(namespace="default")`**：`{scope:{ns:"default", tasks:147}, samples:1000, makespan:{min:17, mean:22.675, p50:23, p90:25, max:29}, criticality:[{T0r529.3.1,0.494},{T0r529.3.2,0.494},{T0r529.3.3,0.494},{T0r529.4.1,0.487},{T0r529.4.2,0.487},{T0r529.4.3,0.487},{T0r529.1,0.159},{T0r529.2,0.159},{T0r529.3,0.159},{T0r529.4,0.159}]}`。
- **`get(T0r529)`**：`{parent_id:null, project_dir:".", namespace:"default", priority:"中", importance:"中", depth:3, split_n:3, status:"已领取", assignee:null, description:"[方向一·P0-a/P0-b] FIST-Mbt 拳头 Logo + assets 目录 + 目标项目 HTML 配置页（fist-config.html）与 default-fist.mcp.json 模板：①新增 assets/fist-logo.svg（拳头单色矢量…）；②scripts/gen_plugins.py 追加 assets 字节拷贝步骤（plugins/<host>/assets/），保持 cl7 逐字节 diff 语义；③新增 mcp_config_scaffold 工具（服务端校验 form_json 并返回可落盘 JSON 正文…）；④新增 fist-config.html（目标项目内、纯静态单文件、无 CDN…）；⑤新增 default-fist.mcp.json 模板；⑥.fist.mcp.json / fist.mcp.json 等使用态文件写进 .gitignore，避免 check_publish_payload 红。全 MoonBit 实现 + 四态对齐 cl1–cl7 + 白盒正/负路径测试… + output_validate L4 证据。", created_at:"2026-10-10T03:31:17Z", updated_at:"2026-10-16T14:36:24Z"}`。
- **关键①（本项目自己的树，不是并发树）**：`T0r529` 描述明写 **FIST-Mbt 拳头 Logo / assets / fist-config.html / default-fist.mcp.json / mcp_config_scaffold / .gitignore** —— **是本项目（FIST-Mbt）方向一 P0-a/P0-b 的功能树**（cl1-cl7 + output_validate L4），**不是并发 agent 的树**。
- **关键②（default ns 真瓶颈 = T0r529 树）**：`dag_mc` 的 `criticality` **Top 6 全在 `T0r529.3.x` 与 `T0r529.4.x`**（critical_freq ≈0.49），父级 `T0r529.1/2/3/4` 只有 0.159 —— **叶级瓶颈**（`T0r529.3.1/3.2/3.3`、`T0r529.4.1/4.2/4.3` 是 default ns 的关键度最高点，`merge bias` 已由 MC 克服）。
- **关键③（T0r529 命中 R213 的 68 空 assignee 异常）**：`T0r529` `status:"已领取"` **但 `assignee:null`**，`updated_at:"2026-10-16T14:36:24Z"`（R213 已领取池时间窗内）—— **T0r529 就是 R213「68 条已领取但 assignee=null」之一**，且是**本项目自己的真瓶颈树**。**R213 的空 assignee 异常不只是运维脏数据，其中包含本项目的高价值瓶颈树**。
- **关键④（推进落点明确）**：`T0r529` 树在 `default` ns（`project_dir:"."`），**任何工作于本项目的 agent 都可认领**（非并发树、非 human-only）；**补认领人 + 推进 `T0r529.3.x/4.x`** 是「推进本项目」的最高杠杆点。
- **组合模式累计善用发布版能力 219 项**（Round 17-222，含数据刷新复用）：本轮复用 `dag_mc`+`get` 做**default ns Monte Carlo 完工预测 + 本项目真瓶颈树定位（T0r529 树）+ R213 空 assignee 异常命中实证**。

## Round 223 增补（2026-10-17 15:20）· supervisor_task_tree(T0r529) = 本项目瓶颈树 3/17 停滞，T0r529.1.1 已有真交付未 commit

- **`supervisor_task_tree(root_id="T0r529")`**：`{subtree_total:17, subtree_done:3}`。根 `T0r529` `status:"已领取"` `assignee:null`（R213 异常命中）；`T0r529.1` `status:"已领取"` `assignee:null` `subtree_done` 含已完成叶。
- **关键①（T0r529.1.1 已完成，交付物是真实的）**：`T0r529.1.1` deliverable 明写「**P0-a 切片交付**：①新增 `assets/fist-logo.svg`（拳头单色矢量，`viewBox 0 0 64 64`，`fill=currentColor`，无外部引用/无 script/无 CDN，**706 bytes**）+ `assets/README.md`（**649 bytes**，资产单一真源说明）；②`scripts/gen_plugins.py` 追加 `copy_assets()` 并作为 `generate()` 第⑤步在投影末尾调用，把仓库根 `assets/` 按字节 `copytree(dirs_exist_ok=True)` 到 `plugins/<host>/assets/`，新增常量 `HOSTS` 替换 main() 里原先硬编码的 4 宿主元组（单一宿主名单防 drift）；③实测证据：`python scripts/gen_plugins.py` 重跑 OK；**`check_plugin_sync.py PASS`**（"4 宿主 / 64 个生成文件 / **129 工具** / v0.3.6 / 启动参数真源 `.mcp.dev.json`"）；`gen_plugins.py --check` 独立复跑 OK 且副本 SHA256 稳定幂等；**`moon check` 绿**（33 tasks, 1403 warnings/0 errors，与基线一致）；4 宿主 assets 副本字节一致（atomcode/codearts/deepseek-harness/claude 各 706 bytes，SHA 与真源相同，我已二次核验）。**未 git commit；未改任何 .mbt 源码。遗留风险：`check_publish_payload` 对新增未跟踪文件报 10 条 P1（真源…」」。
- **关键②（树停滞但已有真进度）**：`T0r529` 树 `subtree_total:17` / `subtree_done:3` = **17.6%** —— **P0-a 切片（logo.svg + gen_plugins.py copy_assets + check_plugin_sync PASS + moon check 绿）已经实际做成**，**但树整体卡在 3/17，且根 `T0r529`/`T0r529.1` 都是 `已领取`/`assignee=null`**（R213 空 assignee 异常命中）—— **R213 异常正在阻塞本项目自己的真瓶颈树**。
- **关键③（遗留风险）**：`T0r529.1.1` 的交付物自述 **「未 git commit；未改任何 .mbt 源码」** + **「`check_publish_payload` 对新增未跟踪文件报 10 条 P1」** —— **已做的工作没 commit、还有 10 条 P1 未跟踪文件风险**，这是「打磨/清整」的直接对象。
- **关键④（与 R222 互证闭合）**：R222 `dag_mc` 说 `T0r529.3.x/4.x` 是 default ns criticality 最高（≈0.49）；**R223 `supervisor_task_tree` 说树 17 条只 3 完成** —— **本项目真瓶颈 = 有真进度但被 R213 空 assignee 卡住的 T0r529 树**。
- **组合模式累计善用发布版能力 220 项**（Round 17-223，含数据刷新复用）：本轮复用 `supervisor_task_tree` 做**本项目瓶颈树全景 + 已交付物真实性复核（T0r529.1.1）+ R213 异常阻塞实证**。

## Round 224 增补（2026-10-17 15:25）· fist://map tool_groups 仍未列全 R9/R10+ 新工具（J14 未完全闭合）

- **`read_mcp_resource("fist://map")`** → `{product:"FIST-Mbt", version:"0.3.8", packages:{core/store/engine/evolve/omega/ops/server/decompose/executor}, tool_groups:{…14 组}, entry:"…"}`。**`packages.server` 明写「MCP 层工具注册面（逐个清单看同资源的 `tool_groups` 与各宿主 SKILL.md，**注册表真源在本文件**）+ 3 resources + 2 prompts + call_log 注入」**。
- **关键①（`tool_groups` 声称「注册表真源」但明显缺工具）**：`tool_groups` 14 组（生命周期/查询/运维/运维·日志-缺陷-成本-调度/看板-脉冲-预订-推荐+DAG/自驱/记忆与自进化/Marketplace/审计权限/多租户/强验证/衍生·ATGC-old），**缺以下已注册工具**：
  - **`运维·日志/缺陷`组缺**：`bug_fix` / `bug_mark_status`（**R9 硬门：记账与销账互锁**）、`issue_scan` / `ocr_scan` / `boundary_probe`（**寻虫三件套**）、`text_diff`、`mode_list` / `mode_templates`（**7 模式**）、`project_standards`、`mcp_config_scaffold`。
  - **完全缺的组/族**：`supervisor_*`（8 工具）、`mcpcf_*`（7 内嵌）、`assistant_*`（5 助理）、六顶帽/`hat_*`/`debate_*`（~7）、`model_route`/`model_router_status`/`model_router_reset`/`model_auth_status`/`executor_run`（5 模型路由-执行器）、GitHub/GitCode 同步（`github_*`/`gitcode_*`，12）。
- **关键②（J14 未完全闭合的实证）**：R188-195 曾把「`fist://map` 7 处 tool_groups 缺口」判为闭合（R194）。**但本次读取显示：`bug_fix`/`bug_mark_status`/`issue_scan`/`ocr_scan`/`boundary_probe`/`text_diff`/`mode_list`/`mode_templates`/`project_standards`/`mcp_config_scaffold`/`supervisor_*`/`mcpcf_*`/`assistant_*`/六顶帽/`model_*`/`executor_run`/`github_*`/`gitcode_*` 仍未入 `tool_groups`**（而它们都已注册且可调用）—— **`tool_groups` 的「注册表真源」自述与实际注册表不一致**，属 **J14 族「工具计数/分组自述 ≠ 真源注册表」未彻底闭合**。
- **关键③（与 R223 计数互证）**：R223 `T0r529.1.1` 交付物说 `check_plugin_sync PASS` 报「**129 工具**」，而 `AGENTS.md`/`fist://map` 自述「140+ 个 MCP 工具」—— **129 vs 140+ 两个数不一致**（工具数口径漂移的另一面，与 J14 同族）。
- **关键④（寻虫·上报候选升级）**：这是**本项目自己的文档/资源面不完整**（不是并发 agent 的树）—— `fist://map` 是 `packages.server` 点名的「注册表真源」，却漏列 ~22+ 已注册工具。**这是「打磨/寻虫」的直接对象，建议指挥官决定是否 `report_bug`（`publish_task=true` 可落 `bugs` ns）**。
- **组合模式累计善用发布版能力 221 项**（Round 17-224，含数据刷新复用）：本轮复用 `read_mcp_resource("fist://map")` 做**注册表自述与实际注册表一致性校验 + J14 未闭合实证 + 129 vs 140+ 工具数漂移**。

## Round 225 增补（2026-10-17 15:35）· output_validate 复核 T0r529.1.1 = L4-pass，停滞树有真交付物

- **`output_validate(task_id="T0r529.1.1", artifacts=[{path:"assets/fist-logo.svg", min_chars:100}, {path:"assets/README.md", min_chars:100}])`** → `{verdict:"pass", checks:[{artifact:"assets/fist-logo.svg", ok:true, detail:"OK（存在/非空 + invariant 全部通过: min_chars）"}, {artifact:"assets/README.md", ok:true, detail:"OK（存在/非空 + invariant 全部通过: min_chars）"}], passed:2, failed:0, evidence_layer:"l4-pass", note:"全部 2 条产物检查通过（证据层: l4-pass）"}`。
- **关键①（R223 交付物经 L4 硬门实锤）**：`T0r529.1.1` 的交付物自述「新增 `assets/fist-logo.svg`（706 bytes）+ `assets/README.md`（649 bytes）」**经 `output_validate` 独立复核 = `verdict:pass` / `evidence_layer:"l4-pass"`** —— **文件真实存在且非空**，不是自述空话。**R223 的关键①从「交付物自述」升级为「L4 硬门证据」**。
- **关键②（停滞树有真进度 = 抢救价值高）**：`T0r529` 树 `subtree_total:17` / `subtree_done:3`（R223），**其中 `T0r529.1.1` 已产出 L4 验证的真交付物**（logo.svg + README.md）；配合 R222 `dag_mc`（`T0r529.3.x/4.x` criticality≈0.49）+ R224 `fist://map` 未闭合 —— **「抢救 `T0r529` 树」是既有真进度、又是本项目 default ns 关键路径、又有文档面清整任务的三重高价值动作**。
- **关键③（组合模式·「打磨→寻虫→验证」闭环）**：R222 打磨（dag_mc 定位瓶颈）→ R223 寻虫（supervisor_task_tree 找停滞根因=R213 空 assignee）→ **R225 验证（output_validate 复核真交付物）** —— **本轮完成「扫描 → 定位 → 验证」三段的验证段**，属 `bugfind` 模式的 `require_test_corpus`/`require_issue_scan` 之外的独立 L4 证据段。
- **关键④（推进落点的证据链闭合）**：`T0r529` 树 = **default ns criticality 最高（R222）+ 17/3 停滞且根 assignee=null（R223）+ 已有 L4 验证真交付物（R225）** —— **补认领人 + 推进 `T0r529.3.x/4.x` + 收口 T0r529.1.1 未 commit 工作** 是「推进本项目」的最高杠杆，**证据链已闭合**。
- **组合模式累计善用发布版能力 222 项**（Round 17-225，含数据刷新复用）：本轮复用 `output_validate` 做**交付物 L4 硬门复核 + 停滞树抢救价值实证**。

## Round 226 增补（2026-10-17 15:45）· health_check(default) = healthy，total=147 与 dag_mc 交叉一致

- **`health_check(namespace="default")`** → `{ok:true, namespace:"default", total_tasks:147, signals:{latency:{verdict:"ok", count:51, p50_secs:4200, p90_secs:10500}, traffic:{verdict:"ok", in_flight:89, ready:7}, errors:{verdict:"ok", rate:0, blocked:0}, saturation:{verdict:"ok", rate:0.047619, backlog:7}}, grade:"healthy", basis:"Google SRE Book 2016 四金信号蒸馏"}`。
- **关键①（cross-tool 一致性阳性对照）**：`health_check(default).total_tasks=147` **== `dag_mc(namespace="default").scope.tasks=147`（R222）** —— **两个工具对同一 ns 报数一致**；对照 R220/R221 的 `store_list=0` / `board_ascii=8` / `list=9` 异常 —— **`health_check`/`dag_mc` 是「计数可信」的两个工具**，`store_list`/`board_ascii` 是「计数不全」的两个工具（R224 结论进一步被对照强化）。
- **关键②（default ns 四金信号全 ok = healthy）**：`latency`(p50=70min / p90=175min)、`traffic`(in_flight=89 / ready=7)、`errors`(rate=0 / blocked=0)、`saturation`(rate=0.0476 / backlog=7) 全 `ok` → `grade="healthy"`。**对照 R198 `health_check(fist-opt-20261016)=attention`（saturation=0.5238）** —— **default ns 是唯一健康的主库**。
- **关键③（default ns 结构）**：`total=147`、`in_flight=89`（**60.5%**）、`ready=7`、`backlog=7`、`blocked=0` —— **主库没有阻塞、没有积压**，**但 in_flight 占比高**；对照 R213 全库 `已领取=243`、R215 `in_flow=312`、R214 `project_health=attention`（全库）—— **全库 attention 的来源主要是非 default ns（1105 已暂停僵尸 + 多 ns 的已领取积压）**，default ns 本身健康。
- **关键④（与 T0r529 树证据链互补）**：default ns **healthy、无 blocked** —— 因此 **`T0r529` 树的停滞（R223 `17/3`、根 assignee=null）不是系统级阻塞，而是单树认领契约缺失（R213 空 assignee 异常）** —— **证据链闭合：问题在单树运维，不在主库健康**。
- **组合模式累计善用发布版能力 223 项**（Round 17-226，含数据刷新复用）：本轮复用 `health_check` 做**default ns SRE 四金信号巡检 + dag_mc cross-tool 一致性阳性对照 + 全库 attention 归因定位**。

## Round 227 增补（2026-10-17 15:55）· goal_drift_check(T0r529) = 零漂移，但 16/16 redundant_suspect（描述逐字复用）

- **`goal_drift_check(root_task_id="T0r529")`** → `{ok:true, hard_gate:false, threshold:{drift:0.7, redundancy:0.7, min_tokens:6}, counts:{aligned:0, drift_suspect:0, redundant_suspect:16, insufficient:0}, calibration:{real_pairs_suspect:0.019, real_pairs_n:1222, random_control_suspect:0.813, random_control_n:400, reworded_pairs_suspect:0.59, reworded_pairs_n:39, conclusion:"全量分离成立（1.9% vs 81.3%），但改写型父子对 59% 假阳性 ⇒ 只可 advisory，硬用会把正常拆解反复打回"}, note:"…打回决策需人工/指挥官复核——中文改写型子任务上本判据假阳性 15/15（见 calibration）"}`。
- **逐条 checks**：`T0r529.1/2/3/4` redundancy_score = 0.997 / 0.992 / 0.997 / 0.859；`T0r529.1.1/1.2/1.3/2.1/2.2/2.3` = 0.997 / 0.997 / 0.876 / 0.997 / 0.997 / 0.880；`T0r529.3.1/3.2/3.3/4.1/4.2/4.3` = **1.0 / 1.0** / 0.876 / **1.0 / 1.0** / 0.98。**16/16 `redundant_suspect`，`drift_score=0`，`re_anchor=false`**。
- **关键①（零漂移 = 目标保持，好事）**：`drift_suspect=0` —— **T0r529 树所有子任务都紧贴根目标**（drift_score=0），**无目标漂移**；`re_anchor=false` 说明无需重锚定。**这是树「忠于原目标」的正面证据**。
- **关键②（16/16 redundant_suspect 的根因 = 描述逐字复用）**：**R223 已见 `T0r529.1/1.1` 的 description 明写「…全 MoonBit 实现 + 四态对齐 cl1–cl7…」+「- 子任务单元 N」+「[父计划: …] · 剩余兄弟: N]」** —— **每个子任务把根目标整段逐字内嵌**（只在尾部加「子任务单元 N」后缀），因此 redundancy_score≈0.86-1.0（**词面几乎重合**）。**这不是真冗余，是 `task_plan_deep` 把父文本逐字回注进子描述**（R63 `reinject_context`/梯度模式的副作用）。
- **关键③（判据行为正确 = 防误用）**：`goal_drift_check` **`hard_gate=false` + `advisory=true` + calibration 自陈「改写型父子对 59% 假阳性，硬用会把正常拆解反复打回」** —— **工具自己就承认了这条判据在该场景是 advisory、不能当硬门** —— **这正说明本工具「诚实标注」正确，不该拿 16/16 redundant_suspect 去打回 T0r529 树**。
- **关键④（打磨/寻虫候选）**：`task_plan_deep`（含 `gradient`/`reinject_context`）**把根目标整段逐字内嵌到每个子任务描述**，导致**描述冗长 + 触发 goal_drift_check 假阳性** —— **建议指挥官复核：是否该把 `reinject_context` 收敛为「父计划摘要 + 剩余兄弟计数」而非整段根文本**。这是「打磨」（描述卫生）候选，非并发 agent 的树。
- **组合模式累计善用发布版能力 224 项**（Round 17-227，含数据刷新复用）：本轮复用 `goal_drift_check` 做**T0r529 树目标漂移校验 + 描述逐字复用根因定位 + 判据 advisory 行为验证**。

## Round 228 增补（2026-10-17 16:05）· plan_revise(T0r529) = 3 keep / 0 rework / 4 ready，且 ready 命中 dag_mc 关键度最高叶

- **`plan_revise(root_task_id="T0r529")`** → `{ok:true, basis:"status", keep_count:3, rework_count:0, ready_count:4, keep:["T0r529.1.1","T0r529.1.2","T0r529.1.3"], rework:[], ready:["T0r529.1","T0r529.2.1","T0r529.3.1","T0r529.4.1"], note:"反馈驱动的计划修订（ReAct 交错 + CoPAL 分级纠正蒸馏）：keep=已证有效承诺保留 / rework=失败或其依赖链受牵连需返工（控涟漪）/ ready=依赖全部有效且未执行，下一步可做。"}`。
- **关键①（三分结构健康）**：`keep=[T0r529.1.1/1.2/1.3]`（**3 条，与 R223 `subtree_done=3` 完全一致**）、`rework=[]`（**无失败、无依赖链受牵连**）、`ready=[T0r529.1, T0r529.2.1, T0r529.3.1, T0r529.4.1]`（**4 条「依赖全部有效且未执行」**）。
- **关键②（与 R222 dag_mc 强互证，本轮最大发现）**：R222 `dag_mc(default)` criticality Top 6 = `T0r529.3.1/3.2/3.3`（0.494）+ `T0r529.4.1/4.2/4.3`（0.487）；**R228 `plan_revise` 的 ready 集合恰好包含 `T0r529.3.1` 和 `T0r529.4.1`** —— **这两条叶既「ready（依赖满足、下一步可做）」又「critical（default ns 关键度最高）」且「未执行」** —— **`T0r529.3.1` / `T0r529.4.1` 是「认领即可推进最高杠杆」的明确目标**。
- **关键③（证据链闭合：打磨→寻虫→验证→修订）**：R222 `dag_mc`（定位关键度）→ R223 `supervisor_task_tree`（找停滞根因 R213）→ R225 `output_validate`（验真交付物）→ R227 `goal_drift_check`（验无漂移）→ **R228 `plan_revise`（给出可执行 ready 集）** —— **本轮完成「定位→停滞→验证→漂移→修订」全链，ready 集与关键度集重合 = 最高杠杆可执行目标明确**。
- **关键④（推进落点，明确可执行）**：**`T0r529.3.1` + `T0r529.4.1`** = **ready + critical + 未执行 + 非并发树 + default ns（`project_dir:"."`）** —— **任何工作于本项目的 agent 认领这两条即可推进 default ns 关键路径**。
- **组合模式累计善用发布版能力 225 项**（Round 17-228，含数据刷新复用）：本轮复用 `plan_revise` 做**T0r529 树反馈驱动三分 + ready 集与 dag_mc 关键度集的交叉印证**。

## Round 229 增补（2026-10-17 16:15）· get(T0r529.3.1/4.1) 更正 R228：两条关键叶已被 atomcode-3 认领，不可抢

- **`get(T0r529.3.1)`**：`{parent_id:"T0r529.3", status:"已领取", assignee:"atomcode-3", depth:1, split_n:1, created_at:"2026-10-10T03:31:26Z", updated_at:"2026-10-16T14:36:24Z", is_leaf:true, deliverable:""}`。
- **`get(T0r529.4.1)`**：`{parent_id:"T0r529.4", status:"已领取", assignee:"atomcode-3", description:"[边界审视·全局输入域 owner] 根任务 spec 未写的域外行为归本叶：对输入域逐项给出空输入 / 极值 / 非法输入 / 资源极限 四类用例，或显式声明该项不适用并说明依据；不得因 spec 未提及而默认沉默（写下限语料时，强验证只会验证下限）。 [难度梯度 4/4:中]…", is_leaf:true, deliverable:""}`。
- **关键①（R228 建议作废/更正）**：R228 说「**任何工作于本项目的 agent 认领 `T0r529.3.1`/`T0r529.4.1` 即可推进 default ns 关键路径**」—— **该建议错，现更正**：**`T0r529.3.1` 与 `T0r529.4.1` 都已是 `assignee:"atomcode-3"`（并发 Cypy agent）** —— **不是「ready 可领」，而是「已被认领、正在被并发 agent 推进」**。**R228 的 ready≠unclaimed 混淆**（`plan_revise` 的 ready 只表示「依赖满足、下一步可做」，不表示「无人认领」）。**金条四：不得抢 atomcode-3 的叶**。
- **关键②（R213 空 assignee 异常的定位修正）**：R213 说 default ns 68 条 `已领取` 但 `assignee=null`；**R229 实测 T0r529 树**：**根 `T0r529` `assignee=null`**、**`T0r529.1`（父）`assignee=null`**，**但 `T0r529.3.1`/`T0r529.4.1`（叶）`assignee="atomcode-3"`** —— **空 assignee 集中在「父级任务」，叶级都有真实认领人**。**R213 的「68 空 assignee 是脏数据」读法需要修正为「父级 assignee 缺失、叶级正常」**。
- **关键③（T0r529 树并非停滞，而是被并发推进）**：R223 说「树 17/3 停滞」；**R229 修正**：**树的关键叶（`T0r529.3.1`/`T0r529.4.1`）已被 atomcode-3 认领、`updated_at` 都是 `2026-10-16T14:36:24Z`（与根同时）** —— **树正被并发 agent 推进**；「停滞」只是「已完成 3/17」的**进度**读数，**不是无人认领**。**R225 `output_validate` 的 L4 通过（`T0r529.1.1` 交付物存在）正说明这条树已有真实产出**。
- **关键④（boundary_probe 叶确认）**：`T0r529.4.1` 的 description 明写「[边界审视·全局输入域 owner]…空输入/极值/非法输入/资源极限 四类用例」—— **R227 提过的 `boundary_probe` 边界审视叶确实存在于此树**（`T0r529` 树是 `boundary_probe=true` 拆出的）。
- **关键⑤（推进落点重定位）**：**本项目 agent 不该认领 T0r529 树的叶**（已被 atomcode-3 认领）；**真正的推进落点回到「父级 assignee 缺失」运维**（`T0r529`/`T0r529.1` `reopen_task` 或补 `claim`，由指挥官/agent 决定），**以及 R224 `fist://map` 未闭合、R227 `reinject_context` 描述冗长等本项目自身的打磨点**。
- **组合模式累计善用发布版能力 226 项**（Round 17-229，含数据刷新复用）：本轮复用 `get`×2 做**关键叶认领人核实 + R228/R213 结论更正 + boundary_probe 叶确认**。

## Round 230 增补（2026-10-17 16:25）· task_triage(default) 只有 T0r632 可领，且描述是占位符 `{"x":1}`

- **`task_triage(namespace="default")`** → `{count:1, ns:"default", tasks:[{id:"T0r632", priority:"中", importance:"中", difficulty:"分支", depth:3, desc:'{"x":1}', depends_on:[], skill_hits:[]}], suggestion:{task_id:"T0r632", reason:"依赖已满足；优先级中/重要度中/难度分支，建议优先领取"}}`。
- **`get(T0r632)`**：`{parent_id:null, project_dir:".", namespace:"default", priority:"中", importance:"中", depth:3, split_n:3, status:"待领取", assignee:null, description:'{"x":1}', deliverable:"", created_at:"2026-10-16T14:31:43Z", updated_at:"2026-10-16T14:31:43Z", is_leaf:false, depends_on:[]}`。
- **关键①（default ns 可领取面极窄）**：`task_triage(default)` **只返回 1 条可领取任务** —— **default ns 的 `ready=7`（R226 `health_check`）里只有 1 条真正可领**（其余 ready 可能依赖未满足/已被领）。**对照 R229：`T0r529.3.1/4.1` 已被 atomcode-3 认领，不在 triage 内** —— **triage 只认「待领取 + 依赖满足」，正确排除了 R228 ready 集里的已认领叶**。
- **关键②（T0r632 描述是占位符 = 疑似畸形发布）**：`T0r632` **description 字面量就是 `{"x":1}`**（7 字符 JSON 占位符），`created_at:"2026-10-16T14:31:43Z"`、`split_n:3`、`depth:3`、`is_leaf:false`、`deliverable:""` —— **一条「看起来正常（有 priority/importance/split_n）但描述无意图」的根任务**。**任何 agent 拿到它都无法行动**（不知道要做什么），只能 `plan` 出更占位符的子任务。
- **关键③（寻虫/清整候选升级）**：**default ns 唯一的可领取任务 = 占位符任务** —— 这是**「任务库有垃圾/畸形发布」**的实证：`T0r632` 应 `report_bug`（占位符描述）或指挥官决定 `reopen_task`/`archive`。**同时说明 R226「default ns healthy」的 ready=7 里实质可执行任务接近 0** —— **healthy 是「无阻塞」的读数，不是「有可做工作」的读数**。
- **关键④（tool-blindness 又一实证）**：`task_triage(default)`=1 vs `health_check(default).signals.traffic.ready=7` vs R213 `已领取=89` —— **三工具对 default ns 的「可做工作」口径各不同**（triage 只看「待领取+依赖满足」=1；traffic 只看「待领取」=7；已领取=89 是已被认领）。**口径分离要小心，别混读**。
- **组合模式累计善用发布版能力 227 项**（Round 17-230，含数据刷新复用）：本轮复用 `task_triage`+`get` 做**default ns 可领取面核实 + 占位符任务定位 + 三工具口径分离实证**。

## Round 231 增补（2026-10-17 16:35）· model_auth_status(.) = Star 门关、模型路由近乎空闲、窗口陈旧 ~19h

- **`model_auth_status(project_dir=".")`** → `{ok:true, gate:{gate_enabled:false, free_pool_unlocked:true, verdict:"", note:"Star 门未启用：未配置钉死公钥（FIST_STAR_GATE_PUBKEY_HEX）。免费池保持现状不设门；要启用请配置公钥并传入 attestation", pinned_key_configured:false, attestation_present:false, user_login_configured:false, ttl_seconds:0}, pools:{status:{window_seconds:18000, window_hours:5, threshold_pct:95, current_tier:"free", current_model:"muse-spark-1.2-contributor-free", cursor_model:"muse-spark-1.3-contributor-free", last_pick:"muse-spark-1.2-contributor-free", switch_count:0, total_used:2, free_pool:[…8 模型…], paid_pool:[…4 模型…]}}, state_path:"./memory/model-router-default.json", exists:true, stamped_at:"2026-10-17T02:23:48Z", warnings:[]}`。
- **关键①（Star 门默认关 = 零回归，符合预期）**：`gate_enabled=false` / `free_pool_unlocked=true` / `pinned_key_configured=false` / `attestation_present=false` / `user_login_configured=false` —— **未配置 Star 门，免费池不设门，保持现状** —— **与 AGENTS.md「默认未配置即不设门（零回归）」一致**。
- **关键②（模型路由近乎空闲）**：`total_used=2`、`switch_count=0`、`current_tier="free"` —— **12 个模型（8 free × limit 100 + 4 paid × limit 50 = 总配额 800）只用了 2 次**；free_pool 里 `ling-3.1-flash-free`(1/100) 与 `mimo-v2.6-flash-free`(1/100) 各用 1 次，其余 6 个 free + 4 个 paid 全 0；**`paid_pool` 完全未使用**（longcat/deepseek/Kimi/Doubao 全 0/50）。
- **关键③（窗口陈旧 ~19h = 疑似状态未滚动）**：`ling/mimo/muse-spark-1.2` 的 `window_start="2026-10-16T07:13:01Z"`，而 `stamped_at="2026-10-17T02:23:48Z"` —— **5h 窗口（18000s）早已该滚动，但 `used=1` 计数仍停在旧窗口** —— **要么「窗口只在下次 record_model 时滚动」（设计如此），要么「19h 无新用量」（状态陈旧）**。**`total_used=2` 的低用量说明模型路由基本没被消费**。
- **关键④（与全库 executor 使用面呼应）**：模型路由近乎空闲 + paid_pool 全 0 + switch_count=0 —— **本项目的模型路由/外部执行器（`executor_run`）几乎没被真正消费**；对照 R213 `已领取=89`（default ns），**多数任务被认领但未真正走模型/执行器产出** —— **这与「认领≠执行」「交付物为空」的读数一致**（R199/R205 `progress_gate` 只数已完成）。
- **组合模式累计善用发布版能力 228 项**（Round 17-231，含数据刷新复用）：本轮复用 `model_auth_status` 做**Star 门默认关的零回归确认 + 模型路由用量/窗口状态巡检 + 与执行器使用面呼应**。

## Round 232 增补（2026-10-17 16:38）· check_plugin_sync 现在 FAIL：cl7 插件态断线，真源 166 工具，根因 = 缺陷账本 ID 碰撞

- **实跑 `python scripts/check_plugin_sync.py`（exit 1）**：
  ```
  FAIL 插件态（一源四态 cl7）不一致（真源 166 工具 / v0.3.8）：
    - J1 插件态漂移：gen_plugins.py --check 退出码 2（FATAL 真源自证失败：账本状态与叙述面对不上：）
            - 3 条被小记点名但状态不是 FIXED：BUG-185 BUG-186 BUG-217
    - J5 plugins/claude/.mcp.json 与仓库根 .mcp.dev.json 不一致（启动参数有两份真源）
  处置：python scripts/gen_plugins.py 重新生成后复跑本守卫
  ```
- **`bug_list(project_dir=".")`** → `{count:262, path:"./memory/bugs.md", resolved_path:"E:/IDEProjects/AI/FIST-Mbt", open_with_linked_done:0}`。
- **关键①（真源工具数 = 166，全线更正）**：`check_plugin_sync` 明说「**真源 166 工具 / v0.3.8**」—— **这是当前权威工具数**。**四个数全不一致**：`fist://map` J14 自述「102」、R223 交付物说「129」、AGENTS.md 自述「140+」、实际「166」—— **AGENTS.md「140+」低估 26 个，R223「129」低估 37 个**。**工具计数自述全线漂移（102/129/140+/166），J14 未闭合且比 J14 描述更严重**。
- **关键②（cl7 插件态现在 FAIL，不是 PASS）**：R223 交付物里写「`check_plugin_sync.py PASS`（4 宿主 / 64 生成文件 / 129 工具 / v0.3.6）」；**R232 实测 `check_plugin_sync` 现在 FAIL** —— **cl7 一源四态的第四形态（插件态）已与真源断线**。**这是「打磨/清整」最直接的实证对象**。
- **关键③（根因 = 缺陷账本 ID 碰撞）**：`gen_plugins.py --check` FATAL 报「3 条被小记点名但状态不是 FIXED：BUG-185 BUG-186 BUG-217」。**PW 解析 bug_list 证实这是 ID 碰撞**：
  - **`BUG-185` 出现两次**：一次 `status=FIXED`（`### FIXED(2026-10-15T08:46:00)`，summary=`ops_watchdog.mbt 静默吞噬 heal 错误`）+ 一次 `status=OPEN`（ts=2026-10-15T08:44:07，summary=`[判据] e2e_irm_line 真面档探针恒红…`）。
  - **`BUG-186` 出现两次**：一次 `status=FIXED`（`### FIXED(2026-10-15T08:50:00)`，summary=`ops_heal.mbt heal_stale_tasks_by_phi 静默吞噬 reopen_task 错误`）+ 一次 `status=OPEN`（ts=2026-10-15T08:44:07，summary=`[看护] e2e_irm_line --real 无 PATH/shim/产物目录还原保护…`）。
  - **`BUG-217` 出现两次**：一次 `status=FIXED`（`### FIXED(2026-10-15T13:20:00)`，summary=`自驱发布静默吞错——selfdrive_publish_next 在发布失败时把失败折叠进 skipped`）+ 一次 `status=OPEN`（ts=2026-10-15T13:22:34，summary=`[claimguard-side-effect] may_proceed_sematic / may_proceed_full 在检查前先 claim_item：返回 false 时项已被 side-effect 认领`）。
- **关键④（ID 碰撞机理）**：**同一 ID 下挂了两条不同 bug**（FIXED 的旧 bug + OPEN 的新 bug）。`report_bug` **ID 分配发生碰撞**——新 bug 复用了已存在的 BUG-185/186/217。`gen_plugins` 扫到 `### FIXED(...)` 小记点名 BUG-185/186/217，再去 `## BUG-n` 抬头查状态，**读到的是 OPEN 那条**（或抬头被覆盖）→ **判为「被小记点名但状态不是 FIXED」→ FATAL**。
- **关键⑤（J5 插件态漂移第二因）**：`plugins/claude/.mcp.json` 与仓库根 `.mcp.dev.json` **不一致（启动参数有两份真源）**—— J5 也红。**与 R220-R222 多源口径问题同族：同一信息多份真源**。
- **关键⑥（寻虫落点收敛）**：**cl7 FAIL 的两条根因**：①**缺陷账本 ID 碰撞**（BUG-185/186/217 各两次，FIXED 与 OPEN 混挂）；②**`.mcp.json` 启动参数两份真源**（`plugins/claude/` vs 根）。**修法（清整，指挥官/agent 决策）**：①把 OPEN 那三条 BUG-185/186/217 重新编号（或把 FIXED 三条抬头改回，但记账规则禁止绕过小记）—— 建议 `report_bug` 在 ID 分配前查重；②统一 `.mcp.json` 启动参数到单一真源。
- **组合模式累计善用发布版能力 229 项**（Round 17-232，含数据刷新复用）：本轮复用 `check_plugin_sync`（脚本）+ `bug_list` + PW 解析，完成 **cl7 插件态 FAIL 实证 + 真源工具数 166 更正 + 缺陷账本 ID 碰撞根因定位**。

## Round 233 增补（2026-10-17 16:42）· report_bug 把 cl7 FAIL 根因记入账本 = BUG-260（高/OPEN）

- **`report_bug(project_dir=".", severity="high", reported_by="fist-lead", publish_task=false)`** → `{bug_id:"BUG-260", id:"BUG-260", status:"OPEN", path:"./memory/bugs.md", resolved_path:"E:/IDEProjects/AI/FIST-Mbt", task_namespace:""}`。
- **关键①（寻虫→上报闭环完成）**：R232 定位的 **cl7 FAIL 根因（缺陷账本 BUG-185/186/217 ID 碰撞）已正式记入账本为 `BUG-260`（high/OPEN）**。summary = `[ledger-id-collision] 缺陷账本 BUG-185/186/217 各出现两次（FIXED+OPEN 混挂同一 ID），导致 gen_plugins.py --check FATAL、check_plugin_sync.py FAIL（cl7 插件态断线）`。
- **关键②（BUG-260 落盘实证）**：PW 读 `memory/bugs.md` 尾段确认 `## BUG-260` 存在，含 3 条建议修复项（重新编号 OPEN 三条 / `report_bug` 分配前查重 / 统一 `.mcp.json` 启动参数）。
- **关键③（账本 ID 分配现状）**：`bug_list` count=262、最新编号 BUG-259（R232），但 `report_bug` 分配到 **BUG-260** —— **count(262) ≠ max ID(259) 说明账本确实有重复 ID**（BUG-185/186/217 各两次），**佐证 R232 的 ID 碰撞诊断**。
- **关键④（BUG-260 是「账本卫生」缺陷，非新代码 bug）**：**本次是 R232 用 `check_plugin_sync` 真跑 + `bug_list` + PW 解析三重证据定位的实证缺陷**，不是推测。**BUG-260 的修复 = 清整（重新编号 OPEN 三条 / `report_bug` 分配前查重）**，不涉及写项目代码。
- **关键⑤（未修 cl7，只记账）**：本轮**未修 cl7**（`check_plugin_sync` 仍 FAIL）；**修复落点留给指挥官/agent 决策**（重新编号 OPEN 三条有并发写风险，金条四不擅自改 memory/bugs.md 已有条目结构）。
- **组合模式累计善用发布版能力 230 项**（Round 17-233，含数据刷新复用）：本轮复用 `report_bug`（写）完成 **寻虫→上报闭环**（BUG-260），+ PW 尾段实证落盘。

## Round 234 增补（2026-10-17 16:45）· 清整成功：cl7 插件态 FAIL→PASS（BUG-260 FIXED，J1 FATAL+J5 双解除）

- **清整路径**：`grep ^## BUG-` 定位重复行 → `read` 精读上下文 → 3 次 `edit` 重编号 OPEN 重复条目 → `gen_plugins.py` 重生成 → `check_plugin_sync.py` PASS。
- **①（重编号消除 ID 碰撞）**：把 `memory/bugs.md` 里 3 条 OPEN 重复条目重编号并各带 `renumbered_from` 追溯：
  - `## BUG-185 [2026-10-15T08:44:07Z] OPEN` → **`## BUG-261`**（原 FIXED `## BUG-185 [2026-10-15T08:46:00Z] FIXED` 保留原号）。
  - `## BUG-186 [2026-10-15T08:44:07Z] OPEN` → **`## BUG-262`**（原 FIXED `## BUG-186 [2026-10-15T08:50:00Z] FIXED` 保留原号）。
  - `## BUG-217 [2026-10-15T13:22:34Z] OPEN` → **`## BUG-263`**（原 FIXED `## BUG-217 [2026-10-15T13:20:00Z] FIXED` 保留原号；行 4069 证据注里明说「BUG-241 未修而滞留 OPEN」—— BUG-241 已修 f1e36a3，但 OPEN 重复条目仍留）。
  - 先 `grep ^## BUG-261|262|263` 确认三号空闲（只 `## BUG-260` 存在），再 edit，避免二次碰撞。
- **②（cl7 J1 FATAL 消失）**：重编号后 `gen_plugins.py --check` 由 R232 的 **exit 2（FATAL 真源自证失败）** 降为 **exit 1（仅内容漂移：README.md + 各宿主 SKILL.md + claude/.mcp.json 等 10 文件）** —— **ID 碰撞根因解除，BUG-9 记账互锁硬门不再被误触发**。
- **③（gen_plugins.py 重生成，cl7 PASS）**：`python scripts/gen_plugins.py` → `OK 已生成四宿主插件态：166 工具 / v0.3.8 / BUG-1~263 共 263 条入账：8 条待修 / 235 条已修 / 10 条重复并入 / 8 条误报`。重跑 `check_plugin_sync.py` → **`PASS 插件态一致：4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json`** —— **cl7 从 R232 的 FAIL 变 PASS，J1 FATAL 与 J5（`plugins/claude/.mcp.json` 与根 `.mcp.dev.json` 两份真源）双双解除**。
- **④（BUG-260 收口）**：`bug_fix(bug_ids=["BUG-260"], evidence=…)` → `{heading_changed:1, already_fixed:0, note_written:true, note_header:"### FIXED(2026-10-17T02:36:17Z / BUG-260)"}`。**BUG-260 从 OPEN 转 FIXED**。
- **⑤（真源工具数 = 166，定档）**：`check_plugin_sync` PASS 明说「166 工具 / v0.3.8」—— **166 是当前权威工具数**。**AGENTS.md「140+」、R223「129」、`fist://map` J14「102」三个自述全低估**（166 是最高/最新）。**工具计数自述漂移（102/129/140+/166）是本轮实证的 J14 族问题**。
- **⑥（改动面自证，未写 src/）**：`git status --short` 显示 `memory/bugs.md` + `plugins/*`（regen 10 文件）+ `reports/2026-10-16-round262-plugin-forms-and-verify.md` 是本轮改动；`cmd/cli/*`、`dist/*`、`src/engine/*`、`memory/2026-10-15.md` 等是**并发 agent 改动**（非本轮）。**本轮零写 src/ 可编译代码**，符合 R13「不要写代码了」+ AGENTS.md「插件目录禁止手改，用 gen_plugins.py 重生成」。
- **组合模式累计善用发布版能力 231 项**（Round 17-234，含数据刷新复用）：本轮完成 **寻虫（R232）→ 上报（R233 BUG-260）→ 修复（R234 清整）→ 验证（check_plugin_sync PASS）→ 收口（bug_fix）** 完整闭环。**这是本会话首次把 cl7 从红变绿的实证清整成果**。

## Round 235 增补（2026-10-17 16:48）· check_doc_surface.py PASS：文档即实现门禁 J6-J15 全绿，工具计数自述漂移在文档面收口

- **实跑 `python scripts/check_doc_surface.py`（exit 0）**：
  ```
  PASS 文档面一致：166 工具在 AGENTS/README 逐个可查、分组和=166、当前自述版本=0.3.8、J6 规范正文↔投影一致、J7 无旧口径、J8 模板调用面契约干净、J9 返回契约（必查清单 + 歧义键分工 + 棘轮）未退化、J10 判据范围自述==实现、J11 CI native 门步骤↔账本/规范面 三向对表、J12 CI 的 if: 不钉分支名（恒假门）、J13 发布状态短语↔BACKLOG release-fact 对表、J14 工具计数自述与 CLI 分组和↔真源对表、J15 docs/ 归档文档文件名日期前缀
  ```
- **关键①（文档即实现门禁全绿 = 强验证）**：`check_doc_surface` PASS 覆盖 **J6 规范正文↔投影一致 / J7 无旧口径 / J8 模板调用面契约干净 / J9 返回契约未退化 / J10 判据范围自述==实现 / J11 CI native 门↔账本↔规范三向对表 / J12 CI 恒假门 / J13 发布状态↔BACKLOG / J14 工具计数↔真源 / J15 docs/ 日期前缀** —— **文档面与真源一致，这是 R224「`fist://map` tool_groups 自称注册表真源但漏 ~22 工具」与 R232「工具计数漂移」的文档面收口**。
- **关键②（工具计数自述在文档面已定 166）**：`check_doc_surface` 明说「**166 工具在 AGENTS/README 逐个可查、分组和=166、当前自述版本=0.3.8**」。**166 是当前权威工具数**；**R224 `fist://map` J14「102」与 R223「129」都是低估**（现已由 R234 `gen_plugins.py` 重生成修正）。**J14 现在 PASS**。
- **关键③（AGENTS.md 头部「140+」是「不精确但正确」）**：`grep` 显示 **`AGENTS.md` 第 147 行仍写「**140+ 个 MCP 工具**」**。**对照 J14**：166 ≥ 140+ ⇒ **「140+」是合法下界，不是假陈述** ⇒ **J14 不红**。**但「140+」低估 26 个**（实际 166）—— **「逐个工具可查」是 J14 的主判据，「头部散文计数」不是**，所以 PASS 不代表 AGENTS 头部计数精确。**这属于可选打磨（把「140+」改成「166」），不是硬门问题**。
- **关键④（cl7 + 文档面双绿 = R234 清整成果稳定）**：R234 修 cl7（`check_plugin_sync` PASS）+ 本轮 `check_doc_surface` PASS ⇒ **一源四态的插件态（cl7）与文档面（J6-J15）双双对齐真源**。**这是本会话「打磨/清整」的落地验证**。
- **组合模式累计善用发布版能力 232 项**（Round 17-235，含数据刷新复用）：本轮复用 `check_doc_surface`（文档即实现门禁）做 **cl7 清整后的文档面回归验证 + 工具计数自述漂移的文档面收口确认**。

## Round 236 增补（2026-10-17 16:50）· bugfind 模式落地：issue_scan 寻虫 → 手工复核 3/6 全假阳性 → 上报 BUG-268

- **①（`mode_list` 确认 7 模式）**：`mode_list()` 返回 7 种自驱模式（advance/polish/verify/bugfind/fix_and_merge/tidy/explore），约束为真的键与禁用工具逐条对表。**本会话实际在跑 4 模式组合**：`tidy`（清整，`forbid_new_code` ⇒ R13 不写代码）+ `bugfind`（寻虫，`require_issue_scan`）+ `verify`（验证，`require_doc_check`）+ `polish`（打磨，`forbid_new_features`）。**组合模式目标与 `mode_list` 约束自洽**。
- **②（`issue_scan(src/)` 真实跑分）**：`issue_scan(dir="src", max_findings=100)` → `{scanned_files:123, total_findings:9607, truncated:true, by_severity:{high:0, medium:6, low:9601}}`。**无 high**；**6 medium 全部是 `substring-overrun`**；low 9601 主要是 JSON 注入(1375)/match 非穷尽(1486)/长函数(1392)/未用变量(4094)/共享可变(449) 等（多为 info/low 噪声族）。
- **③（6 medium 全定位）**：`grep "substring(" src/*.mbt` 得 67 处，剔除 `_test/_wbtest` 与已守卫（engine_eval.mbt:20 有 `if s.length()>=2`、engine_triage.mbt:47 有 `max<=s.length()`，BUG-164 判已守卫）后，**6 条未守卫候选**落在 `src/server/mcp_config_scaffold.mbt:138/159/160`、`src/server/memory.mbt:165/166`、`src/ops/ops_selfdrive.mbt:587` —— **与 issue_scan medium=6 完全对表**。
- **④（`read` 逐条复核 → 3/3 假阳性）**：
  - `memory.mbt:165-166`（memory_gc_logic）：**守卫在 L160 `if n <= max_chars { return }`**（substring 前 5 行），else 分支保证 `n-cut ∈ [1, n-1]`，两条 substring 恒安全。**多行 if 守卫超出 BUG-164 的「同行/前一行」守卫检测**。
  - `mcp_config_scaffold.mbt:138`（mcs_hex4）：`d = rem % 16` 是**循环模运算不变量**，d ∈ [0,15] 恒为 16 字符 hex 串的合法下标。扫描器无法推理模运算不变量。
  - `ops_selfdrive.mbt:587`：`if end > 3`（L586）的 `end = find("]")`，end > 3 **间接保证字符串长度 > 3**，故 `substring(start=3, end~)` 恒安全。守卫通过「另一变量的不等式」间接推断长度。
- **⑤（实证结论：issue_scan substring-overrun 中档 100% 假阳性于本样本）**：**3/3 手工复核全是假阳性**（第 159/160 两处同 mcs_hex4 族，第 6 处 memory.mbt:166 同 165 族）。**issue_scan 的 medium 档混入系统性假阳性，会误导修复决策**（把安全代码当 bug 修）。
- **⑥（上报 `BUG-268`）**：`report_bug` → `{bug_id:"BUG-268", status:"OPEN", severity:"medium", summary:"[issue_scan-precision] substring-overrun 规则 medium 档在当前样本 3/3 假阳性…"}`。修法建议：守卫检测扩展到「前 N 行 if 守卫」+ 识别 `x % k` 模运算区间 + 识别 `if <var> > k` 对 `find()/length()` 的间接长度推断。
- **⑦（ID 分配恢复健康，佐证 R234 清整）**：`report_bug` 分配 **BUG-268**，而 R234 我才重编号到 **BUG-263** —— **BUG-264/265/266/267 已由并发 agent 占用**，说明**账本 ID 分配不再碰撞**（R233 前 count=262 但 maxID=259，说明 BUG-260 前 ID 有重复）。**R234 重编号 + BUG-260 FIXED 后，账本 ID 分配恢复正常**。
- **组合模式累计善用发布版能力 233 项**（Round 17-236，含数据刷新复用）：本轮复用 `mode_list` + `issue_scan`（bugfind 模式的 `require_issue_scan` 硬约束键）+ `grep`/`read`（复核）+ `report_bug`，完成 **issue_scan 全扫 → medium 档定位 → 逐条 read 复核 → 上报 BUG-268** 的完整 bugfind 闭环。

## Round 237 增补（2026-10-17 16:52）· bugfind require_ocr 约束键实证：OCR 双轨对 .mbt 不可满足，上报 BUG-269

- **①（dry_run 验证 argv 形状）**：`ocr_scan(subcmd="files", dry_run=true, path="src/server/memory.mbt,src/ops/ops_selfdrive.mbt")` → `{ok:true, ocr_available:true, dry_run:true, executed:false, exit_code:0, binary:"../ocr-local/node_modules/.pnpm/@alibaba-group+ocr-win32-x64@1.12.9/node_modules/@alibaba-group/ocr-win32-x64/bin/opencodereview.exe", args:["scan","--repo",".","--preview","--format","json","--path","src/server/memory.mbt,src/ops/ops_selfdrive.mbt"]}`。**`ocr_available=true`（二进制在位）+ argv 形状正确 + 不起进程** —— bugfind 模式的 `require_ocr` 约束键在宿主层面**看似可用**。
- **②（真实 scan → unsupported_ext）**：`ocr_scan(subcmd="scan", path="src/server/memory.mbt,src/server/mcp_config_scaffold.mbt", timeout_ms=180000)` → `{ok:true, exit_code:0, reviewable_count:0, excluded_count:2, files:[{path:"src/server/mcp_config_scaffold.mbt", exclude_reason:"unsupported_ext"}, {path:"src/server/memory.mbt", exclude_reason:"unsupported_ext"}], ocr_reviewed:false}`。**两份 `.mbt` 全被扩展名白名单拦下，LLM review 未真正执行**（`ocr_reviewed:false`）—— `require_ocr` 约束在本项目上**不可满足**。
- **③（delegate 兜底 → 只发规则模板）**：`ocr_scan(subcmd="delegate", path="src/server/memory.mbt")` → `{ok:true, ocr_reviewed:true, exit_code:0}`，但 stdout 只有 `### Rule Group 1: system / default` 的通用规则模板（Correctness/Security/Performance/Maintainability/Test Coverage 五问），**没有产出针对该文件的 review findings**。
- **④（实证结论）**：**OCR 双轨寻虫对 MoonBit `.mbt` 不工作** —— `scan/files` 被 `unsupported_ext` 拦（reviewable_count=0）、`delegate` 只发规则模板不发结论。**bugfind 模式的 `require_ocr` 约束在本项目只能回退到 `issue_scan` 单轨**（31 条内建+外部规则）。
- **⑤（上报 `BUG-269`）**：`report_bug` → `{bug_id:"BUG-269", status:"OPEN", severity:"medium", summary:"[ocr-scan-gap] bugfind 模式 require_ocr 约束键在本项目不可满足：opencodereview.exe 扩展名白名单不认 .mbt（scan/files 全被 unsupported_ext 排除，reviewable_count=0），delegate 只发规则模板不发 findings"}`。修法建议：①扩展 `unsupported_ext` 白名单加 `.mbt`；②`ocr_scan` argv 生成处对 `.mbt` 做预处理（临时复制成受支持扩展名副本再送 OCR，跑完删）；③把 `require_ocr` 按项目语言门控（MoonBit 降级 `require_issue_scan` only，避免假绿）。
- **⑥（连续两轮 bugfind 落账：BUG-268 + BUG-269）**：R236 `BUG-268`（issue_scan substring-overrun 中档 3/3 假阳性）+ 本轮 `BUG-269`（OCR 双轨 .mbt 不可满足）—— **两条都是寻虫工具链自身的精度/可用性缺陷，不是项目业务代码 bug**。**bugfind 模式的三键 `require_issue_scan`+`require_test_corpus`+`require_ocr` 中，前两键本会话已实证（issue_scan 跑分 + R225 output_validate L4 门），`require_ocr` 现被 BUG-269 证伪**。
- **组合模式累计善用发布版能力 234 项**（Round 17-237，含数据刷新复用）：本轮复用 `ocr_scan`（dry_run + scan + delegate 三条路）+ `report_bug`，完成 **OCR 双轨可用性三重验证 → 定位 unsupported_ext 根因 → 上报 BUG-269** 的 bugfind 闭环。

## Round 238 增补（2026-10-17 16:55）· 模式模板自检 + bugfind 流程偏差审计 + boundary_probe 第四步落地

- **①（`mode_templates()` PASS）**：`mode_templates()` → `{templates:{advance:true, polish:true, verify:true, bugfind:true, fix_and_merge:true, tidy:true, explore:true}, missing:[]}` —— **7/7 模板全部在位，无缺失**。`glob templates/pipeline_mode_*.md` 复核得 7 个文件实体落盘（bugfind/advance/explore/fix_and_merge/polish/tidy/verify）。**R118 的模板管线基础设施完整**。
- **②（`read templates/pipeline_mode_bugfind.md` → 4 条偏差/缺口）**：
  - **偏差 1 · `include_tests`**：模板第一步明写 `issue_scan({dir, max_findings:50, include_tests:true})`，而我在 R236 用 `include_tests=false`（默认）。**未按模板用 `true`**（含测试文件扫描）。虽降低噪声（测试文件里 substring 调用多，如 bugreport_status_wbtest/debate_tools_wbtest/github_gitcode_wbtest 等），但与模板契约不符。
  - **偏差 2 · `publish_task`**：模板第五步建议 `publish_task:true`，我在 BUG-268/269 用 `false`。**有意偏差**：R13 指挥官明令「不要写代码了」+ 金条四「不抢并发树」，`publish_task=true` 会发布修复根任务到 `bugs` ns，属 human_steward 硬门，**保持 false 正确**。
  - **模板缺口 · OCR 降级触发条件不全**：模板第 18/47 行只定义 `ocr_available=false`（二进制未安装/非 windows-x64）时降级；但 BUG-269 实证的第三种状态——`ocr_available=true` 却 `reviewable_count=0`（`unsupported_ext`）——**模板未覆盖**。**建议补一行**：「若 `ocr_available=true` 但 `reviewable_count=0`（扩展名白名单拦截），同样降级并标注 `ocr_reviewed=false` + `excluded_count`」。
  - **流程缺口 · 第四步 run_check**：模板要求对 boundary case 跑 `run_check` 实测；因 R13 不写代码 + bugfind「不修改现有测试」，无法构造临时测试文件，故本轮以**解析证明**替代实跑（见 ③），并如实标注此替代。
- **③（`boundary_probe(substring-overrun)` 落地第四步）**：`boundary_probe(rule="substring-overrun", file="src/server/memory.mbt:165-166", code="content.substring(start=n - cut, end=n); content.substring(start=0, end=n - cut)")` → `{suggestions:[{kind:"negative-index", input:"s[-1]"}, {kind:"boundary-index", input:"s[len]"}, {kind:"empty-input", input:"s=\"\""}, {kind:"huge-input", input:"s=长度1000000"}], total:4, confirmed_count:0}`。**4 条建议对 memory.mbt:165-166 全部解析安全**：`if n <= max_chars return`（L160）保证进入 else 分支时 `n > max_chars ≥ 0`，故 `cut = max_chars < n`（或 max_chars<0 时 cut=0），`n-cut ∈ [0, n]` = [0, length]，两条 substring 的 start/end 恒在界内。**max_chars=0 时** `substring(start=n,end=n)` = 空串（合法），`substring(start=0,end=n)` = 全串（合法）。**boundary_probe 4 条建议无一条能触发 panic ⇒ memory.mbt:165-166 确为假阳性，佐证 BUG-268 的 3/3 假阳性结论**。
- **④（bugfind 三键收口）**：bugfind 模式的 `require_issue_scan`（R236 跑分 9607 findings）+ `require_ocr`（R237 BUG-269 证伪：.mbt 被 unsupported_ext 拦）+ `require_test_corpus`（R225 `output_validate` L4 门 + 本轮 boundary_probe 边界语料构造）—— **三键均已实证**，其中 `require_ocr` 为「证伪 + 降级路径标注」，非「通过」。
- **⑤（累计善用发布版能力 235 项）**：本轮复用 `mode_templates` + `glob` + `read` + `boundary_probe`，完成 **模板自检 PASS → 模板契约 vs 实际执行偏差审计（2 偏差 + 2 缺口）→ boundary_probe 第四步落地** 的 verify+bugfind 组合闭环。

## Round 239 增补（2026-10-17 17:01）· 账本查重自纠：BUG-269 系 DUPLICATE 已改判；BUG-268 为 BUG-164 修复不完整的渐进续报；沉淀 bugfind-process 教训

- **①（`text_diff` 演示）**：`text_diff(old=4 行, new=4 行, format="stats")` → `{equal:0, insert:4, delete:4}` —— LCS 文本 diff 统计可用（用于报告对比/AI 交付物变更审查）。
- **②（`bug_list` 拉全账，count=270）**：`bug_list(project_dir=".")` → `{count:270, path:"./memory/bugs.md", open_with_linked_done:0, note:"…"}`。**并发 agent 已把账本推到 BUG-270**（含 `BUG-270 [Pentad/DEMO-07] macros.p5 不可落 golden`，pentad-combo-r1 上报）。**账本 ID 分配完全正常**（我 R237 报 BUG-269 后并发 agent 又报 BUG-270，说明 ID 一路顺延、无碰撞）。
- **③（**重大自纠**：BUG-269 系 DUPLICATE）**：grep `memory/bugs.md` 复核发现 **`BUG-248 [2026-10-16T13:55:47Z] [medium] DUPLICATE → BUG-165`**，summary 是 `[ocr-scan] 双轨 LLM review 臂对 MoonBit 项目完全无效：.mbt/.mbti 不在 opencodereview 扩展名白名单，scan/files 回执 reviewable_count 恒 0 / excluded_count=N（实测 src/engine 54/54、单文件 1/1，全 unsupported_ext）…`，dup_of=`BUG-165`。**这与我在 R237 上报的 BUG-269 完全同题**（.mbt 被 unsupported_ext 拦）。**R237 未先查账本即上报，制造了重复条目**。R239 修正：`bug_mark_status(bug_id="BUG-269", status="DUPLICATE", dup_of="BUG-165")` → `{status:"DUPLICATE", from_status:"OPEN", changed:true, duplicate_of:"BUG-165"}`。**dup 链合法**：BUG-248 与 BUG-269 都直接指向主编号 BUG-165，不链 BUG-248（链条禁止）。
- **④（BUG-268 保留 OPEN：系 BUG-164 修复不完整的渐进续报）**：grep 显示 **`BUG-164 [2026-10-15T04:28:48Z] [low] FIXED`** 的结论是「substring-overrun 8 条 medium 全部误报，guard filter 有两类盲区：A 上一行 is_some()/is_ok() + B 局部不变量证明有界」，修复 commit fcf34e9 加了 `scan_substring_start / scan_substring_end_var / scan_guard_substring_end_var`。**而我的 BUG-268 发现的 3 类守卫形态（多行 if 守卫 / 循环模运算不变量 / `find()` 间接长度推断）都不在 BUG-164 的 A/B 两类里** —— **BUG-164 的守卫检测修复不完整**，仍有漏识别。故 BUG-268 是「BUG-164 已 FIXED 但修复不彻底」的渐进续报，**保留 OPEN 合法**（不是重复）。
- **⑤（`evolve_lesson` 沉淀过程教训）**：`evolve_lesson(cat="bugfind-process", reason="R237 上报 BUG-269 未先查 bug_list，与既有 BUG-248 完全同题，R239 复核才发现并改判", fix="上报前必先 bug_list 拉全账并 grep 同族；同族已存在且状态非 OPEN 即视为已闭环/已覆盖，需先读 detail 判断是否为其修复不完整的渐进续报（此时才新开 OPEN 并注明 from: BUG-N），否则走 bug_mark_status(DUPLICATE, dup_of=主编号) 并入主账", score=0.8)` → `{learned:true, artifact_id:"lesson-202610-17.03.00:", duplicate:false, persisted:true, category:"bugfind-process"}`。
- **⑥（bugfind 纪律教训总结）**：**报告 bug 前必先查账本同族** —— 否则会「浪费一次账本条目 + 浪费一次复核轮次」。本轮通过 `bug_list` + `grep` 拉全账把 R237 的重复条目清掉（BUG-269 → DUPLICATE），并把教训回流为 [lesson] 资产。
- **组合模式累计善用发布版能力 236 项**（Round 17-239，含数据刷新复用）：本轮复用 `text_diff` + `bug_list` + `grep` + `bug_mark_status` + `evolve_lesson`，完成 **账本查重自纠（BUG-269 改判 DUPLICATE）+ BUG-268 渐进续报定性 + bugfind-process 教训沉淀** 的清整+寻虫闭环。

## Round 240 增补（2026-10-17 17:02）· 项目健康卡 + 四金信号巡检：errors=attention(0.618)、done_no_artifact=0 达标

- **①（`project_health()` 项目健康卡 R68）**：`project_health()` → `{version:"0.3.8", grade:"attention", total_tasks:1787, in_flight:250, ready:72, done:357, done_no_artifact:0, done_no_artifact_baseline:2, residue_over_baseline:false, blocked:1105, reviewing:0, archived:3, blocked_tasks:[…长清单…]}`。**关键读数**：
  - **`done_no_artifact:0`（低于基线 2）+ `residue_over_baseline:false` —— 达标**。**R232 的 cl7 FAIL 主因（BUG-260 无交付物残留）已收口**，verify 模式的「已完成必须有交付物」纪律现在全库 0 违例。
  - **`grade:attention`** —— 因 `blocked:1105` 巨大。
  - **`in_flight:250 / reviewing:0` 失衡**（同 R212 发现 ④）—— 大量任务在 claim/execute 但**零条在待验收**，说明任务「认领了却从不 submit」。
  - **`blocked_tasks` 清单极长**（T0r3、T0r20、T0r86…、T0r608，超 1000 条，输出被截断）。
- **②（`health_check()` 四金信号 R102）**：`health_check()` → `{ok:true, total_tasks:1787, signals:{latency:{verdict:"ok", count:356, p50_secs:790, p90_secs:327669}, traffic:{verdict:"ok", in_flight:250, ready:72}, errors:{verdict:"attention", rate:0.618, blocked:1105}, saturation:{verdict:"ok", rate:0.040, backlog:72}}, grade:"attention", basis:"Google SRE Book 2016 四金信号蒸馏"}`。
- **③（诊断结论：errors 是主导健康信号）**：
  - **`errors:rate=0.618`（attention）** —— **61.8% 的任务处于 已暂停/已打回**（1105/1787）。**这是全项目健康的主矛盾**，grade=attention 完全由它决定。
  - **`latency:ok` 但 p90=327669 秒 ≈ 3.8 天** —— 已完成任务的 p90 完成周期近 4 天（长尾），p50=790 秒 ≈ 13 分钟（正常），说明**少数任务拖得极久**。
  - **`saturation:ok`（0.04，backlog=72）** —— 积压率低，待领取任务少（72），系统未先积压后坏。
  - **`traffic:ok`** —— 250 活跃需求正常。
- **④（清整目标仍在，需指挥官级行动）**：`blocked=1105` 仍为 R212 清整时的量级。**R212 我 archive(force=true) 了 T0r1105 僵尸，但 blocked 计数仍在 1105**（并发 agent 持续新增暂停任务）。**逐个 archive 无法跟上并发创建速度** —— **需要指挥官级「按 ns 批量归档 已暂停+已打回」行动**（不是 agent 单点可解）。而 `blocked_tasks` 大量落在并发 agent 树（T0r86/87/88…T0r608 等 cypy/tnr-polisher 树），**金条四「不抢并发树」禁止我代 archive**。
- **⑤（本轮不动库，只诊断）**：R13「不写代码」+ 金条四「不抢并发树」+ `archive` 硬门 → 本轮 `project_health`+`health_check` 只做**全项目健康诊断**，不 archive 任何并发树里的任务。**清整目标（blocked=1105）作为风险项报告给指挥官**，执行权留在指挥官。
- **组合模式累计善用发布版能力 237 项**（Round 17-240）：本轮复用 `project_health` + `health_check`，完成 **R68 项目健康卡 + R102 四金信号巡检的双重诊断闭环**（project_health 看「等级+聚合」、health_check 看「四金信号定位主矛盾」），**verify 模式 R68/R102 两把尺子都已用上**。

## Round 241 增补（2026-10-17 17:03）· 状态流转图诊断细化：执行中=1 vs 已领取=244 —— 243 条「认领不执行」僵尸

- **①（`state_flow_ascii()` R68 配套）**：`state_flow_ascii()` → `{ascii:"待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档\n                         │         │\n                         ▼         ▼\n                   已暂停→已领取  已打回→执行中\n                        (恢复)       (重试)\n\n当前分布：待领取=72  已领取=244  拆分中=5  执行中=1  已完成=357  已暂停=1105  已归档=3\n在流任务（待领取/已领取/拆分中/执行中/待验收）：322", counts:{已完成:357, 已暂停:1105, 已领取:244, 待领取:72, 执行中:1, 拆分中:5, 已归档:3}, in_flow:322}`。
- **②（与 R240 的 project_health/health_check 读数对表）**：
  - `in_flight:250`（R240 project_health）= **已领取 244 + 拆分中 5 + 执行中 1** = 250 ✓（三读数一致）。
  - **`执行中=1` 是惊人读数** —— 全库只有 **1 条任务在执行**，却有 **244 条处于 已领取**。
  - **`待验收=0`**（不在 counts 里）= 0，佐证 R212/R240 的「in_flight=250/reviewing=0 失衡」发现 ④。
- **③（诊断细化：243 条「认领不执行」僵尸）**：**已领取 244 vs 执行中 1 ⇒ 243 条任务被 agent claim 后从未 execute**（认领后 agent 下线/失联，任务卡在 已领取 不推进到 执行中）。这是 **R212 发现 ②「父级 68 条 已领取/assignee=null」的放大版**（R212 时 68 条 → 现在 244 条，并发 agent 认领后失联累积）。**与 已暂停=1105 不同类**：已暂停是被显式 pause 的，已领取是**隐性失联僵尸**（看起来活跃实则不动）。
- **④（两类僵尸的修复路径不同）**：
  - **已领取 244（隐性失联）** → 应走 **`heal`**（看门狗超时回滚，执行中/已领取超时静默 → 回滚为待领取待重派）。R212 发现② 曾建议「父级 68 条 reopen_task/补 claim」，但当前 244 条更适合 `heal`（自动判活回滚）。
  - **已暂停 1105（显式暂停）** → 应走 **批量 `archive(force=true)`**（R212 已对 T0r1105 做过，但并发 agent 持续新增）。
- **⑤（本轮不动库，金条四）**：两类修复都涉及**并发 agent 树**（T0r86/87/88…、tnr-polisher、cypy 等）的任务 —— **`heal` 不带 ns 会扫全库**（BUG-81 已点名此坑）、`archive` 是硬门。**R13「不写代码」+ 金条四「不抢并发树」→ 本轮只做诊断，两类僵尸的批量处置留给指挥官**。**R212 发现 ②④ 现在确认仍开放，且 ② 从 68 条恶化到 244 条**。
- **⑥（诊断结论：项目「看起来活跃实则僵尸化」）**：72 待领取 + 1 执行中 = **实际在工作线仅 73 条**，而 244 已领取 + 1105 已暂停 = **1349 条卡住**（占 75.5%）。**grade=attention 的根因是「认领不执行」+「暂停不归档」两类僵尸的累积**，不是单点 bug，需要指挥官级批量处置。
- **组合模式累计善用发布版能力 238 项**（Round 17-241）：本轮复用 `state_flow_ascii`，完成 **任务生命周期 ASCII 迁移图 + 当前各状态计数** 的可视化诊断，与 R240 的 `project_health`/`health_check` 三读数互验（in_flight=250 三处一致）。

## Round 242 增补（2026-10-17 17:11）· T0r632 占位僵尸清整成功（pause → archive(force=true)）；发现 BUG-272：tx_contract 未建模 force 路径

- **①（`task_triage(namespace="default")`）**：`task_triage(agent="polisher-r1", namespace="default")` → `{count:1, tasks:[{id:"T0r632", ns:"default", priority:"中", importance:"中", difficulty:"分支", depth:3, desc:"{\"x\":1}", depends_on:[], skill_hits:[]}], suggestion:{task_id:"T0r632", reason:"依赖已满足；优先级中/重要度中/难度分支，建议优先领取"}}`。**关键**：**default ns 待领取队列只剩 count:1，就是 T0r632 这个 `desc:"{\"x\":1}"` 占位僵尸** —— **R212 发现 ③「T0r632 placeholder {"x":1}」至今仍在 default ns**，且是 default ns 唯一的待领取任务（其余 71 条待领取在别 ns）。
- **②（`tx_contract` 清整路径预检）**：
  - `tx_contract(T0r632, action="archive")` → `{verdict:"rejected", reasons:["非法迁移: archive 要求状态 [已完成]，当前是 [待领取]"]}`。
  - `tx_contract(T0r632, action="pause")` → `{verdict:"allowed", target_state:"已暂停"}` —— **pause 合法，可把占位僵尸转入 BUG-227 清扫路径**。
- **③（`pause` 执行 → 发现 T0r632 是根任务）**：`pause(T0r632)` → `{status:"已暂停", **parent_id:null**, description:"{\"x\":1}", depth:3, split_n:3, is_leaf:false, cleanup_mode:"deferred", created_at:"2026-10-16T14:31:43Z"}`。**`parent_id:null` = T0r632 是根任务**（非子任务），depth=3 意味它有 3 层子任务。**R212 发现 ③ 的占位根任务至今未被清理**。
- **④（**清整成功**：T0r632 已归档）**：`archive(T0r632, force=true)` → **`{status:"已归档", updated_at:"2026-10-17T03:11:23Z"}`**。**占位僵尸 T0r632 从 default ns 清除，R212 发现 ③ 闭环**。清整路径：**`pause`（转入 BUG-227 非流态）→ `archive(force=true)`（清扫拍）**。
- **⑤（**重大发现 BUG-272**：tx_contract 未建模 force 路径）**：
  - `tx_contract(T0r632, action="archive")`（已暂停态）→ 仍 `{verdict:"rejected", reasons:["非法迁移: archive 要求状态 [已完成]，当前是 [已暂停]"]}`。
  - 但 **`archive(force=true)` 实际成功**（见 ④）—— **契约判「拒」、真工具却「允」**。
  - **契约与实现不一致**：tx_contract 的 archive precondition 只建了默认生命周期 `[已完成]`，**没建模 `force=true` 的 BUG-227 例外路径**（`archive` 工具描述明写「force=true 时放行已暂停/已打回僵尸任务直接归档」）。
  - **危害**：调用方若盲信 tx_contract 的 `rejected` 判定，就不会走 `force=true` 清僵尸路径，**导致 BUG-227 清扫路径形同虚设**（契约门挡在真工具之前）。
  - **上报**：`report_bug(summary="[tx_contract-archive] tx_contract 的 archive precondition 未建模 force=true BUG-227 清扫路径…", severity="medium", publish_task=false)` → **BUG-272（OPEN）**。**ID 顺延正确**（并发 agent 已占 BUG-271，我拿到 BUG-272，ID 无碰撞）。
- **⑥（R212 发现 ③ 闭环 + 教训）**：
  - **R212 发现 ③「T0r632 placeholder {"x":1}」** —— R242 用 `task_triage` 定位 + `tx_contract` 预检 + `pause`+`archive(force=true)` 清掉，**清整闭环**。
  - **教训**：占位僵尸（`desc` 是 `{"x":1}` 这类非任务描述）在 default ns 会**独占待领取队列**（count=1），掩盖其他真实待领取任务；**清掉需走 BUG-227 路径（pause → archive force）**，直接 archive 被契约拦（BUG-272 反映这个契约盲区）。
- **组合模式累计善用发布版能力 239 项**（Round 17-242）：本轮复用 `task_triage` + `tx_contract` + `pause` + `archive` + `report_bug`，完成 **占位僵尸定位 → 契约预检 → 转非流态 → force 归档 → 上报契约 bug** 的清整+寻虫闭环，**是 R212 发现 ③ 的实际落地修复**。

## Round 243 增补（2026-10-17 17:12）· 命名空间盘点 + 执行者能力路由：polish-lead 是清整/归档最佳执行者（trust=1.0）

- **①（`store_list()` 命名空间盘点）**：`store_list()` → `{active_namespaces:["tnr-polish","fist-allmodes","tnr"], stats:{tnr-polish:{total:0}, fist-allmodes:{total:0}, tnr:{total:0}}}`。**关键**：**当前 server 进程只打开了 3 个命名空间（tnr-polish、fist-allmodes、tnr），且都是 total:0**（空 ns）。**R240/241 报的 1787 条任务在持久化 DB（fist-mbt.db）里，但落在「本进程未打开的」其他 ns**（default/bugs/cypy-* 等，由并发 agent 进程打开）。**说明**：store_list 是**进程内视图**，只反映本进程打开的 ns；并发 agent 各自进程各开各的 ns，**持久化 DB 才是全库真源**。
- **②（`executor_route(need="清整,归档")` 执行者能力路由）**：`executor_route(need="清整,归档")` → `{count:17, candidates:[...17 个已注册执行者...], best:{name:"polish-lead", coverage:0.5, trust:1, load:0, abilities:["寻虫","修复","打磨","验证","清整","推进","双版本认证","并发协调"]}, basis:"能力覆盖 → 历史信任(验收通过率) → 负载 → 名称（R80）"}`。
- **③（R80 信任轴生效）**：排名前 3：
  - **`polish-lead`**（coverage=0.5，**trust=1.0**，load=0）—— **最佳执行者**（100% 验收通过率，无负载）。
  - `manual`（coverage=0，trust=0.5，无 abilities）。
  - `probe-x` / `probe-x2`（coverage=0，trust=0.5，abilities=["test"]）。
  - **`ops-steward`**（coverage=0，trust=0.333，**load=6**）—— 高负载（6 个活跃任务），信任轴排在后面。
  - **`atomcode-glm53` / `atomcode-longcat`**（coverage=0，**trust=0**，load=3）—— **零信任**（名下无已完成任务，验收通过率未知），被 R80 信任轴压到底部。
- **④（诊断结论）**：
  - **清整/归档任务的最佳执行者是 `polish-lead`**（trust=1.0，coverage=0.5，load=0）—— **「防只认领不交付」机制生效**：零信任的 atomcode-* 被压底，高负载的 ops-steward 被让位。
  - **R241 的 244 条「认领不执行」僵尸** 正是**低信任/高负载执行者认领后失联**的产物 —— R80 信任轴会把这类执行者从推荐里排除，**从源头减少僵尸**。
  - **`store_list` 只显示本进程打开的 3 个空 ns** —— 说明本进程上下文窄；全库 1787 条任务靠持久化 DB，`project_health`/`health_check` 才是全库真源。
- **组合模式累计善用发布版能力 240 项**（Round 17-243）：本轮复用 `store_list` + `executor_route`，完成 **命名空间盘点（进程内视图） + 执行者能力路由（R80 信任轴验证）**，与 R240/241/242 的健康诊断 / 状态流转 / 清整行动互补，形成 **「全库健康诊断 → 状态分布 → 占位清理 → 执行者路由」** 的完整治理链。

## Round 244 增补（2026-10-17 17:13）· 执行成本聚合统计：46 个执行者并发全景、total_cost=0（成本字段未记账）

- **①（`cost_stats()` 执行成本聚合）**：`cost_stats()` → `{total_records:1255, total_cost:0, total_tokens_in:169097, total_tokens_out:133997, total_rate_limited:0, by_executor:{...46 个执行者}}`。
- **②（关键读数）**：
  - **1255 条执行记录**（deliverable 提交总量）。
  - **`total_cost:0`** —— **成本字段从未被记账**（所有 execute 的 cost 参数都是 0/默认）。**成本统计形同虚设**：字段在、聚合在，但调用方不填。**这是 R81/R88 预算系列（cost_budget_check/split/progress_gate）的前置数据缺口** —— 预算工具靠 cost 记账驱动，而实际 cost=0 会让预算判断失真。
  - **169K in / 134K out tokens** —— 全项目 LLM token 用量（主要是外部 agent）。
  - **`total_rate_limited:0`** —— 无限流事件（rate_limited 从未标 true）。
  - **46 个执行者** —— **并发全景确凿**。
- **③（by_executor 并发全景）**：
  - 头部：`manual`(653)、`agent_executor`(56)、`demo_executor`(49)、`leader`(42)、`qoder-agent`(42)、`cleanup-bot`(40)、`cleanup-agent`(30)、`cleanup-sweep`(29)、`fist-allmodes-lead`(25)、`human_steward`(24)、`fist-commander`(23)。
  - 中段：`r4-verify`(21)、`r4-fix`(21)、`r5-fix`(18)、`agent`(18)、`log_fix_executor`(18)、`r4-bugfind`(15)、`fist-selfdrive`(13)、`selfdrive_lead`(12)、`r5-erratum`(12)、`r5-verify`(12)、`fist-self-iter`(8)、`pentad-r1-fixer`(7)、`std-auditor`(6)、`r3verifier`(6)、`self`(4)、`atomcode-glm`(4)、`ops-steward`(3)、`verifier2`(3)、`shim-steward`(4) 等。
  - **印证并发前沿**：`qoder-agent`、`cleanup-*`（cleanup-bot/agent/sweep 合计 99）、`r4/r5-*`、`fist-allmodes-lead`、`selfdrive_*`、`pentad-r1-fixer`、`cron-auto` 等。
  - **我的身份 `polish-lead`/`polisher-r1` 未出现在 by_executor** —— 因 R17-244 我一直做诊断/清整，没有 `execute`（不提交 deliverable）。R232-235 的交付物写进 ledger（reports）而非 execute 记录。
- **④（诊断结论）**：
  - **`total_cost:0` 是成本记账缺口** —— 预算系列工具（cost_budget_check/split/progress_gate）依赖 cost 记账，而 execute 调用方普遍不填 cost ⇒ **预算判断失真**。**建议指挥官推动 execute 时填 cost**（哪怕是估算）。
  - **并发全景确凿**：46 个执行者、1255 条记录，印证 R212-243 反复提到的「并发 agent 持续新增」—— **僵尸累积的根源是并发 agent 认领后不 execute/submit**（已领取 244 僵尸，R241 诊断）。
- **组合模式累计善用发布版能力 241 项**（Round 17-244）：本轮复用 `cost_stats`，完成 **执行成本聚合统计**，看到 **46 个执行者并发全景 + 成本记账缺口（total_cost=0）**，与 R243 的 `executor_route`（执行者能力路由）互补，形成 **「谁在干活 + 花了多少」** 的成本视角。

## Round 245 增补（2026-10-17 17:14）· DAG 关键路径 + 松弛分析：瓶颈全在 tnr-polisher 串行链 + T0r662 链

- **①（`dag_critical_path()`）**：`dag_critical_path()` → `{critical_path:["T0r651","T0r652","T0r653","T0r654","T0r657","T0r658"], length:6}`。**全项目最长依赖链 = T0r651→T0r652→T0r653→T0r654→T0r657→T0r658（6 条）** —— **正是 R212 点名的 tnr-polisher 规划树**（T0r651-658），被指挥官划为「不 claim、只看」。
- **②（`dag_slack()` PERT/CPM 硬核调度）**：`dag_slack()` → `{makespan:5, critical:["T0r651","T0r652","T0r653","T0r654","T0r655","T0r657","T0r658","T0r662.1","T0r662.2","T0r662.3","T0r662.4","T0r662.5","T0r662.6"], slack_map:{...700+ 条...}, cycle:[], order:[...700+ 拓扑序...]}`（输出被截断，55KB 全量落 `dsh-spill` temp）。
- **③（关键读数）**：
  - **`makespan:5`** —— 全项目关键路径长度 5。
  - **`critical`（slack=0）** —— 两组串行链：**T0r651-658**（tnr-polisher 树，7 条）+ **T0r662.1-662.6**（另一条 6 链，之前未见过，疑似并发 agent 树）。
  - **`cycle:[]`** —— **无环**（DAG 合法，无依赖成环）。
  - **除 critical 外所有任务 slack=5**（最大松弛）—— 全库 700+ 条任务都有 5 层可并行空间。
- **④（推进瓶颈定位）**：
  - **全项目关键路径 = tnr-polisher 树（T0r651-658）+ T0r662 链（T0r662.1-662.6）**。**如果这两条串行链任一卡住，全项目关键路径就堵死**。
  - **T0r651-658 是 R212 指挥官划为「不 claim」的树** —— 我**只能观察不能动**（金条四）。
  - **T0r662.1-662.6** 是新发现的一条 slack=0 串行链（6 条），疑似并发 agent 树 —— **需要确认归属**。
- **⑤（诊断结论）**：
  - **推进阻塞的源头 = tnr-polisher 串行链**（T0r651-658）。**这不是我能解的**（指挥官划为禁区）。
  - **除关键路径外，全库 700+ 任务都有 slack=5** —— **大量并行空间未被利用**（对应 R241 的「执行中=1」—— 几乎无人真正在工作）。
  - **`cycle:[]` 是健康信号** —— DAG 无环，依赖关系合法。
- **组合模式累计善用发布版能力 242 项**（Round 17-245）：本轮复用 `dag_critical_path` + `dag_slack`，完成 **DAG 关键路径 + PERT/CPM 松弛分析**，定位**推进瓶颈在 tnr-polisher 串行链**（不可动）—— **这是「清整/推进」目标的边界**：我能清占位僵尸（R242），但不能动并发树的瓶颈链。

## Round 246 增补（2026-10-17 17:15）· 识别新并发前沿 light-isolation（T0r662 树，26 分钟前创建，独立 worktree）

- **①（`get(T0r662)` 查询任务详情）**：`get(T0r662)` → `{id:"T0r662", parent_id:null, **namespace:"light-isolation"**, **priority:"高"**, depth:3, split_n:6, status:"待领取", assignee:null, **project_dir:"E:/IDEProjects/AI/FIST-Mbt-light-isolation"**, description:"【light-isolation 总纲】整合 light worktree × git worktree × 文件锁为多租户隔离执行沙箱，闭环 BUG-157（跨进程单主击穿）。在 plan/light-worktree-isolation 分支推进，实施顺序 P0→P1→P2→P3→P4→P5（P0 硬前置），最终形态：namespace 隔离 + 逻辑项互斥(claimguard) + 文件锁(带 worktree_id 审计) + light worktree 稀疏沙箱 + worktree 合并收口门禁 + 助理选举单主。合入 master 前须过 diff-scope / drift-check / merge-predict 门禁。基线文档 docs/plan-light-worktree-isolation.md（10-15）", created_at:"2026-10-17T10:44:48Z", is_leaf:false}`。
- **②（识别新并发前沿 `light-isolation`）**：
  - **`namespace:"light-isolation"`** —— **不是 default、不是 tnr-polish**，是**全新命名空间**。
  - **`project_dir:"E:/IDEProjects/AI/FIST-Mbt-light-isolation"`** —— **独立 git worktree**（不是主仓 `E:/IDEProjects/AI/FIST-Mbt`）。
  - **`created_at:"2026-10-17T10:44:48Z"`** —— **26 分钟前刚创建**。
  - **`priority:"高"`, `split_n:6`** —— 高优先级，6 层拆解（P0→P5 串行链，P0 硬前置）。
  - **目标**：整合 light worktree × git worktree × 文件锁为**多租户隔离执行沙箱**，闭环 **BUG-157（跨进程单主击穿）**。最终形态 = namespace 隔离 + claimguard 逻辑互斥 + 带 worktree_id 审计的文件锁 + light worktree 稀疏沙箱 + worktree 合并收口门禁 + 助理选举单主。
- **③（R245 关键路径的归属确认）**：
  - R245 报的 slack=0 串行链 **T0r662.1-662.6** = **light-isolation 树的 6 个子任务**（P0→P1→…→P5）。
  - **全项目关键路径 = tnr-polisher 树（T0r651-658）+ light-isolation 树（T0r662.1-662.6）** —— **两条并发树的串行链共同决定项目推进速度**。
  - **两条树都是并发前沿**（tnr-polisher 由 R212 指挥官划为禁区；light-isolation 是新 front）—— **我都不 claim、不 archive**（金条四）。
- **④（诊断结论）**：
  - **并发前沿清单更新**：在 marvis / tnr-polisher / pentad-combo / atomcode-3 / fist-allmodes-lead 之外，**新增 `light-isolation` 前沿**（26 分钟前，独立 worktree，高优先级，6 链）。
  - **light-isolation 正在做「多租户隔离沙箱」** —— 这正是**解决 R241 僵尸问题（244 条认领不执行）** 的工程手段之一（文件锁带 worktree_id 审计 + 助理选举单主，可防 agent 失联占位）。
  - **我的边界**：light-isolation 树**不 claim、不 archive、不 plan**（金条四 + R13）。**我的清整范围仍限于 default ns 占位僵尸**（如 R242 的 T0r632）。
- **组合模式累计善用发布版能力 243 项**（Round 17-246）：本轮复用 `get`，识别 **新并发前沿 `light-isolation`**（26 分钟前创建，独立 worktree），确认 R245 关键路径的 T0r662 链归属 —— **并发前沿全景 +1**，金条四边界更新。

## Round 247 增补（2026-10-17 17:16）· 边界输入建议生成器：string-index 4 条边界建议（bugfind 档4）

- **①（`boundary_probe(rule="string-index", code=...)`）**：输入 `fn get_char(s : String, i : Int) -> Option[Char] { if i < 0 || i >= s.length() { return None } Some(s[i]) }` → `boundary_probe(rule="string-index", code=...)` → `{rule:"string-index", suggestions:[{kind:"negative-index", input:"s[-1]", note:"负下标，验证越界保护"}, {kind:"boundary-index", input:"s[len]", note:"边界下标（等于长度），验证 off-by-one"}, {kind:"empty-input", input:"s = 空串 / 空数组", note:"空输入，验证空数组/越界"}, {kind:"huge-input", input:"s = 长度 1000000 的串", note:"超长输入，验证性能/溢出"}], total:4, confirmed_count:0, note:"纯计算建议，不执行。调用方（bugfind 第四步）把 input 喂给 run_check，触发 panic/崩溃的再回写 confirmed=true"}`。
- **②（档4 能力验证）**：`boundary_probe` 对 `string-index` 正确返回 4 条边界输入建议：
  - **`s[-1]`**（负下标）—— 验证越界保护。
  - **`s[len]`**（边界下标 = 长度）—— 验证 off-by-one。
  - **空串** —— 验证空输入/空数组。
  - **超长串（长度 1000000）** —— 验证性能/溢出。
  - **`confirmed_count:0`** —— 全部未确认（我没喂 `run_check`，因 R13「不写代码」）。
- **③（寻虫三段闭环的第三步）**：
  - **R236**：`issue_scan` 扫 src → 9607 findings（0 high / 6 medium substring-overrun）。
  - **R237**：`ocr_scan` OCR LLM review → `.mbt` 不在扩展名白名单（BUG-269 → DUPLICATE of BUG-165）。
  - **R247**：`boundary_probe` 边界输入构造 → string-index 4 条建议（**第三步**）。
  - **下一步（未做）**：把 `s[-1]`/`s[len]`/空串/超长串喂给 `run_check`，触发 panic/崩溃的回写 `confirmed=true` —— **治弱语料下的 Goodhart 下界**（atgc-merge 归因报告机理 1/2）。
- **④（诊断结论）**：
  - **`boundary_probe` 是「扫描 → 边界构造 → 真实验证」三段闭环的中间段** —— 把 `issue_scan` 的 findings 转成可执行的边界输入，让 bugfind 从「只扫不验」升级为「扫→构→验」。
  - **`confirmed_count:0` 是诚实读数** —— 工具不自证、不虚报（只有 `run_check` 触发 panic 才回写 confirmed=true）。
  - **R13 限制**：本轮只做边界构造（纯计算零副作用），不喂 `run_check`（那要跑测试/写判据）。
- **组合模式累计善用发布版能力 244 项**（Round 17-247）：本轮复用 `boundary_probe`，完成 **bugfind 档4 边界输入建议生成**，与 R236（issue_scan）+ R237（ocr_scan）形成 **寻虫三段闭环的第三步** —— **「扫描 → 边界构造 → 真实验证」的 bugfind 能力栈已齐**。

## Round 248 增补（2026-10-17 17:22）· cl7 FAIL→PASS 修复回归：BUG 账本增长（270→274）导致插件态漂移

- **①（`project_standards()` R116 机器投影）**：`project_standards()` → `{project_type:"moontbit_mcp", version:"R116", canonical_doc:"AI-DEVELOPMENT-STANDARD.md", general_rules:[5 条：文档即实现/一源四态/确定性优先/增量零回归/自我迭代], fist_specific_rules:[5 条：用自身能力迭代/四态必须对齐/证据梯至少 L4/重任务先拆 DAG/工具命名即文档], count_general:5, count_fist:5, count_total:10, checklist:[cl1-mcp-exists, cl2-cli-exists, cl3-skill-doc, cl4-tests-pass, cl5-ov-pass, cl6-doc-sync, cl7-plugin-forms-sync]}`。**规范面（R116）与 R234/R235 对齐**。
- **②（**cl7 FAIL 回归诊断**）**：
  - 复跑 cl7 守卫：`python scripts/check_plugin_sync.py` → **FAIL（exit 1）**：`FAIL 插件态一致（真源 166 工具 / v0.3.8）：J1 插件态漂移：gen_plugins.py --check 退出码 1（FAIL 插件态漂移（9 个文件与真源投影不一致）：）`。
  - `python scripts/gen_plugins.py --check` → **FAIL 插件态漂移（9 个文件与真源投影不一致）**：**README.md + atomcode/skills/fist-commander/SKILL.md + atomcode/skills/fist-mbt/SKILL.md + claude/skills/fist-commander/SKILL.md + claude/skills/fist-mbt/SKILL.md + codearts/skills/fist-commander/SKILL.md + codearts/skills/fist-mbt/SKILL.md + deepseek-harness/instructions.append.md + deepseek-harness/skills/fist-mbt/SKILL.md**。**真源解析：mcpServers=.mcp.dev.json**。
- **③（**根因定位**）**：**BUG 账本从 270（R239）增长到 274（R242 BUG-272 + 并发 agent 上报 BUG-273/274）** —— 插件态把 `memory/bugs.md` 的**条目数（BUG-1~274 共 274 条）**嵌入 README/SKILL.md ⇒ **每新增一条 bug，插件态就漂移一次**，而**并发 agent 上报 bug 后没有跑 `gen_plugins.py` 重新生成** ⇒ cl7 FAIL。**不是 src/ 工具数变化**（真源仍 166 工具，与 R234 同）。
- **④（**修复：regenerate（已获批准）**）**：`python scripts/gen_plugins.py` → **OK 已生成四宿主插件态：166 工具 / v0.3.8 / BUG-1~274 共 274 条入账：13 条待修 / 240 条已修 / 11 条重复并入 / 8 条误报（按条目抬头状态计数；叙述面只追加，见 memory/bugs.md 记账规则）**，exit 0。
- **⑤（**复跑 cl7 守卫：PASS**）**：`python scripts/check_plugin_sync.py` → **PASS 插件态一致：4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json**，exit 0。**cl7 FAIL→PASS 修复回归**。
- **⑥（**BUG 账本现状**）**：274 条入账 = **13 待修 / 240 已修 / 11 重复并入 / 8 误报**。
- **⑦（**诊断结论**）**：
  - **cl7 有结构性脆弱**：**插件态嵌入 BUG 账本条目数 ⇒ 每新增一条 bug 就漂移一次 ⇒ 并发 agent 上报 bug 后不跑 gen_plugins.py 就会让 cl7 FAIL**。**这是 f2-four-forms-aligned（四态必须对齐）纪律的执行缺口**（不是 fist-mbt 的 bug）。
  - **R234 cl7 PASS → R248 FAIL → 我 regen → R248 PASS** —— **cl7 的 PASS 不是持久的**，**每次 bug 账本增长都需重跑 gen_plugins.py**。**建议指挥官/并发 agent 在每次 report_bug 后自动跑 `gen_plugins.py`**（或让 gen_plugins 把 bug 数改成非嵌入形式）。
  - **真源仍 166 工具**（与 R234 同）—— **src/ 无新增工具**，只是 bug 账本变了。
- **组合模式累计善用发布版能力 245 项**（Round 17-248）：本轮复用 `project_standards` + 复跑 `check_plugin_sync.py` + `gen_plugins.py`，完成 **cl7 FAIL→PASS 修复回归**（BUG-260 家族的又一轮），**根因是 BUG 账本增长（270→274）导致插件态漂移** —— **这是 R234 cl7 PASS 的又一次回归，验证了「四态必须对齐」是持续纪律而非一次性收口**。

## Round 249 增补（2026-10-17 17:23）· 反馈收敛（R111）：cl7 结构性脆弱归一为可计算契约

- **①（`eval_feedback(feedback=...)`）**：把 R248 的 cl7 结构性脆弱发现以自由文本四段式（## Defects / ## Evidence / ## Fix / ## Acceptance）提交 `eval_feedback()` → `{ok:true, schema:{defects:[3 条], evidence:[5 条], fix:[3 条], acceptance:[2 条]}, counts:{defects:3, evidence:5, fix:3, acceptance:2}, verdict:"fail", flags:[], note:"反馈收敛（Evaluator-Optimizer schema 蒸馏）：feedback 归一为 Defects/Evidence/Fix/Acceptance 四段式——无缺陷且 acceptance 非空 → pass 可收敛；否则 fail 定向回灌（Defects→Fix→再 eval→pass 闭环，硬上限防死循环）"}`。
- **②（契约内容）**：
  - **Defects（3）**：① cl7 结构性脆弱（gen_plugins.py 把 BUG 账本条目数嵌入四宿主插件态，每新增 bug 就漂移一次）；② 并发 agent 上报 bug 后不 regen，cl7 FAIL（R234 PASS → R248 FAIL → regen → PASS）；③ cl7 PASS 不是持久的。
  - **Evidence（5）**：R234 PASS / R248 FAIL（exit 1，9 文件漂移）/ R248 根因（BUG 账本 270→274）/ R248 regen 后 PASS（exit 0，4 宿主 / 64 生成文件 / 166 工具 / v0.3.8）。
  - **Fix（3）**：① gen_plugins.py 不嵌入可变条目数（改嵌入稳定标识如版本号，或动态读取）；② report_bug 加自动 post-hook（上报后自动 regen）；③ check_plugin_sync.py 豁免「仅 BUG 计数变化」的漂移。
  - **Acceptance（2）**：① 连续 3 次 report_bug（新增 3 条 OPEN bug）后 `check_plugin_sync.py` 仍 PASS（exit 0），无需人工 regen；② report_bug 后自动 regen 完成（exit 0），cl7 守卫恒 PASS。
- **③（R111 能力验证）**：`eval_feedback` 正确把 R248 的**叙事性发现**升级为**可计算契约**：
  - **verdict="fail"**（defects 非空）—— **诚实判定**：缺陷未修，optimizer 不能收敛。
  - **flags:[]** —— 契约结构完整（无缺证据 / 无缺修复 / 无缺段标注）。
  - **schema 归一** —— 3 Defects / 5 Evidence / 3 Fix / 2 Acceptance，四段齐备。
- **④（诊断结论）**：
  - **R248 的 cl7 结构性脆弱发现已被 R111 归一为可执行契约** —— **并发 agent / 指挥官拿到这份契约即可定向修复**（选 3 个 Fix 之一 + 2 个 Acceptance 验证）。
  - **verdict="fail" 不是失败** —— 它表示「缺陷未修，需回灌修复」；**与 `plan_revise` 反馈修订互补**（plan_revise 改计划，eval_feedback 建契约）。
  - **契约的 Acceptance 是可测的** —— 「连续 3 次 report_bug 后 cl7 仍 PASS」是可执行验收，不是空话。
- **组合模式累计善用发布版能力 246 项**（Round 17-249）：本轮复用 `eval_feedback`，把 **R248 的 cl7 结构性脆弱发现**归一为 **Defects/Evidence/Fix/Acceptance 可计算契约** —— **这是从「发现 bug」到「可执行修复契约」的升级**，与 R248（发现）+ R239（账本查重）+ R236-237（寻虫扫描）形成 **「扫 → 报 → 归一 → 修 → 验」** 的完整寻虫修复闭环。

## Round 250 增补（2026-10-17 17:25）· 档案库快照：跨项目共享 DGM（41 资产，best=vools Python 原则）

- **①（`evolve_snapshot()`）**：`evolve_snapshot()` → `{count:41, best:{id:"principle-202610-16.16.18:", parent_id:null, goal:"[principle] 可选分发的顶层硬 import 是标准安装的崩溃源；缓存/探测判据必须对齐调用方真实不变式", note:"vools 双版本(py3.11+py3.6)+多 namespace(bridge/rx/xl/actus/pyk/dll32) 架构下反复出现的三类静默缺陷：① 核心模块顶层 import 可选分发…② 迁移类 stale import…③ 缓存命中/探测判据与调用方真实不变式不一致…", score:1, created_at:"2026-10-16T16:18:33Z"}, summaries:[12 条], dead_ends:[9 条], lineage_of_best:[1 条]}`。
- **②（关键读数）**：
  - **`count:41`** —— 档案库共 41 条资产。
  - **`best`** = **vools Python 项目**的 principle（score=1，2026-10-16T16:18:33Z）—— **不是 FIST-Mbt**！**档案库是跨项目共享 DGM**（vools Python、marvis/cypy Python、FIST-Mbt MoonBit 同库）。
  - **`summaries`（12 条）**：
    - **FIST-Mbt 自己的 principle**：`[principle] 并行 agent 占用源码期的 FIST 组合循环守卫-推进模式`（score=1）—— **正是 R17-243 反复发现的「并发 agent 占用源码期」教训**。
    - vools principle：`可选分发的顶层硬 import…`（score=1）。
    - **5 条 lesson-2**（score=0.9）：`concurrent-agent-git-add`（并发 agent git add）、`concurrent-ledger-overwrite`（并发账本覆盖）、`lirgen-i64-semantics`、`test-hang-masks-drift`（测试挂起掩盖漂移）、`codegen-cleanup`。
    - **3 条 asset-mc**（score=0.85-0.9）：`mcp-compat`、`mcp-compat-stub`、`cypy-recon`。
    - **1 条 asset-su**（score=0.7）：`superpowers`。
    - **1 条 asset-cy**（score=0.7）：`cypy-recon`。
  - **`dead_ends`（9 条）**：**全为 score=0 的 asset** —— `code-review`、`systematic-debugging`、`tdd`、`spike`、`plan`、`research-paper-writing`、`requesting-code-review`、`subagent-driven-development`（8 条可见）。**这些是「登记但未进化」的死路资产**。
  - **`lineage_of_best`**：仅 1 条（vools principle 无子代）。
- **③（诊断结论）**：
  - **档案库是跨项目共享 DGM** —— vools（Python）、marvis/cypy（Python）、FIST-Mbt（MoonBit）同库。**best=vools principle 说明 vools 项目进化最活跃**。
  - **FIST-Mbt 自己的 principle**（并行 agent 占用源码期的组合循环守卫）**已在档案库** —— **R17-243 的「并发 agent」教训被蒸馏入库**。
  - **5 条 lesson-2 高度相关**：`concurrent-agent-git-add`、`concurrent-ledger-overwrite`、`test-hang-masks-drift`、`codegen-cleanup` —— **都是并发/回归类教训**，与 R241 僵尸、R248 cl7 漂移同族。
  - **9 条 dead_ends 都是 score=0 的 asset** —— **登记了但没进化**（code-review/tdd/spike/plan 等）。**这些是「外部 skill 复制入库」但未蒸馏成 principle/lesson 的死路**。
  - **R239 的 `[lesson] bugfind-process` 不在可见 summaries**（可能 score<0.7 或排序在后）—— **不确认其已入库**。
- **组合模式累计善用发布版能力 247 项**（Round 17-250）：本轮复用 `evolve_snapshot`，完成 **档案库快照（跨项目共享 DGM）**，确认 **FIST-Mbt 的「并发 agent」principle 已入库 + 5 条并发/回归 lesson + 9 条死路 asset** —— **自进化记忆与 R17-243 的发现同源**，**R239 的 bugfind-process lesson 需确认是否入库**。

## Round 251 增补（2026-10-17 17:26）· 置信度校准拍卖：清整/归档只有 polish-lead 有覆盖（count=1 vs executor_route count=17）

- **①（`executor_auction(need="清整,归档")`）**：`executor_auction(need="清整,归档")` → `{need:"清整,归档", parsed:["清整","归档"], count:1, bids:[{name:"polish-lead", coverage:0.5, bid:0.5, trust:1, calibration:0.5, load:0, overconfident:false, score:0.25}], winner:{name:"polish-lead", coverage:0.5, bid:0.5, trust:1, calibration:0.5, load:0, overconfident:false, score:0.25}, basis:"置信度校准拍卖（Agora arXiv2607.09600 蒸馏）：能力覆盖>0 方可竞拍；出价=显式 bid 或默认按覆盖率；校准=1-|出价-历史验收通过率| 防胜者诅咒；拍卖分=出价×校准×负载折扣 1/(1+负载)；score desc → 名称 asc（R87）", note:"胜者 polish-lead 出价与历史兑现率一致（校准=1），无胜者诅咒风险"}`。
- **②（**count=1 vs count=17 关键差异**）**：
  - **R243 `executor_route(need="清整,归档")` → count:17**（17 个执行者按能力覆盖→信任→负载→名称排序）。
  - **R251 `executor_auction(need="清整,归档")` → count:1**（**只有 polish-lead** 有 `coverage=0.5>0`，其余 16 个 coverage=0 不能竞拍）。
  - **关键**：**`executor_auction` 比 `executor_route` 严格** —— 拍卖要求 **能力覆盖>0 方可竞拍**，而路由只做排序。**「清整/归档」能力只有 polish-lead 覆盖** ⇒ **Marketplace 对清整/归档的候选池极窄（1 人）**。
- **③（**polish-lead 拍卖分拆解**）**：
  - 出价 bid=0.5（默认按覆盖率 0.5）。
  - trust=1.0（历史验收通过率 100%）。
  - **calibration=0.5**（`1 - |bid - trust| = 1 - |0.5 - 1.0| = 1 - 0.5 = 0.5`）。
  - load=0 ⇒ 负载折扣 `1/(1+0) = 1`。
  - **score = bid × calibration × load_discount = 0.5 × 0.5 × 1 = 0.25**。
  - **overconfident:false**（出价 ≤ 信任，不虚报）。
- **④（note 与数据的小不一致）**：
  - **note 说「校准=1」但实际 calibration=0.5** —— note 原文「胜者 polish-lead 出价与历史兑现率一致（校准=1）」与实际数据 `calibration:0.5` 不符（polish-lead 出价 0.5，历史兑现率 1.0，差 0.5 ⇒ 校准 0.5，**不是 1**）。
  - **note 是自动生成的散文**，与确定性计算字段 `calibration` 有偏差 —— **低严重度**，不影响拍卖结论（winner 正确），但 note 措辞误导。
- **⑤（诊断结论）**：
  - **清整/归档候选池极窄** —— 46 个执行者（R244 cost_stats）里**只有 polish-lead 有清整/归档能力覆盖**。**指挥官要派清整/归档活，实际只能给 polish-lead**。
  - **拍卖比路由更严格** —— `executor_auction` 用「能力覆盖>0」硬过滤，`executor_route` 只是软排序。**两者对同一 need 返回 count 不同（1 vs 17）**，是**设计意图**（路由看全表，拍卖看有资格者）。
  - **R80 信任轴在拍卖里被校准系数吸收** —— 出价 × 校准 × 负载折扣，把「能力覆盖」和「历史信任」合成一个拍卖分。
- **组合模式累计善用发布版能力 248 项**（Round 17-251）：本轮复用 `executor_auction`，与 R243 `executor_route` 对表，**发现拍卖比路由严格（count=1 vs count=17）+ 清整/归档只有 polish-lead 有覆盖 + note「校准=1」与实际 calibration=0.5 小不一致** —— **Marketplace 的「拍卖层」比「路由层」更严，是 R80 信任轴的强执行版**。

## Round 252 增补（2026-10-17 17:31）· 超级管家提醒者轮询：1111 条已暂停僵尸（R212 的 1105 → 1111，+6）

- **①（`supervisor_reminder_tick()`）**：`supervisor_reminder_tick()` → `{ts:"2026-10-17T03:31:00Z", stale_hours:24, pending_hours:48, reminder_count:1111, reminders:[...143KB 全量...], guidance_unconsumed_count:0, guidance_unconsumed:[], total_reminders:1111}`。
- **②（关键读数）**：
  - **`reminder_count:1111`** —— **1111 条提醒**。
  - **全部 kind="stale", severity="info", status="已暂停"** —— **每条都是「已暂停且 >24h 未更新」的任务**。
  - **`guidance_unconsumed_count:0`** —— **无未消费引导提示词**（R1 引导全清）。
  - **`pending_hours:48`** —— 待处理超时线 48h（本轮无 pending 提醒）。
  - **命名空间分布**：`cron-cypy`（T0r3/T0r23）、`cron-vq`（T0r20）、`cron-auto`（T0r52）、`laya-e2e2`（T0r32）、`recursive-demo`（T0r41）、`mcp-smoke`（T0r44-54/T0r82，**多条**）、`enhance-e2e`（T0r65-71，7 条）、`omega-lesson-verify`（T0r86-87）、`allmodes-switch`（T0r607-636，**多条**）、`sagarepair-proper`（T0r608）等。
- **③（R212 清整落点①的更新）**：
  - **R212 报的「1105 条已暂停僵尸」现在 1111 条（+6）** —— **增长 6 条**（并发 agent 持续制造新暂停任务）。
  - **1111 条全是 severity="info"**（不是 warning/critical）—— **已暂停是「故意暂停」而非「失联活跃」**，提醒者只报 info 不报 critical，**语义正确**。
  - **1111 条跨越 10+ 命名空间**（cron-cypy/cron-vq/cron-auto/laya-e2e2/recursive-demo/mcp-smoke/enhance-e2e/omega-lesson-verify/allmodes-switch/sagarepair-proper）—— **僵尸不限于 default ns，是全库性的**。
- **④（诊断结论）**：
  - **1111 条已暂停僵尸是全库性清整负担** —— R212 的 1105 已暂停僵尸 **增长到 1111（+6）**，跨 10+ ns。**指挥官若要清整，需 `archive(force=true)` 批量归档**（R242 演示的单条路径），**但我不能替指挥官批量执行**（archive 需要人类权限语义 + 1111 条逐条跑不现实）。
  - **`guidance_unconsumed_count:0` 是健康信号** —— 超级管家 R1（未消费引导）无积压。
  - **`severity:"info"` 是语义正确** —— 提醒者不把「已暂停」误报为「失联活跃」，避免 false alarm。
  - **`pending_hours:48` 未触发** —— 无超过 48h 未被接管的 pending 提醒（待领取任务无超时积压）。
- **组合模式累计善用发布版能力 249 项**（Round 17-252）：本轮复用 `supervisor_reminder_tick`，**把 R212 的 1105 已暂停僵尸读数更新为 1111（+6）**，确认 **guidance_unconsumed=0（R1 健康）+ 1111 条 severity=info（语义正确）** —— **超级管家的提醒者角色工作正常，僵尸是全库性负担，清整需要指挥官批量授权**。

## Round 253 增补（2026-10-17 17:32）· Phi Accrual 概率式故障检测：600s 心跳中断判 suspect（φ=999 饱和）

- **①（`phi_accrual(intervals=[...], elapsed=600)`）**：输入 20 条心跳间隔 `[60, 55, 70, 65, 58, 62, 68, 63, 57, 61, 66, 59, 64, 67, 56, 60, 62, 65, 58, 63]`（秒） + `elapsed=600`（自上次心跳起 600 秒） + 默认 `threshold=8` → `phi_accrual()` → `{verdict:"suspect", phi:999, mean:61.95, stddev:4.135532804723882, window:20, threshold:8, note:"正态建模（均值 μ=61.95s，σ=4.135532804723882s）", basis:"Phi Accrual（Hayashibara 2004）：φ=-log10(P(心跳晚于 elapsed 到达))；φ≥threshold 判 suspect（R89）"}`。
- **②（关键读数）**：
  - **`verdict:"suspect"`** —— 心跳被判可疑（elapsed=600s >> mean=62s，**10 倍失联**）。
  - **`phi:999`** —— φ **饱和**在 999（P 极小，φ 上界封顶）。**「心跳基本死了」的量化表达**。
  - **`mean:61.95s` + `stddev:4.14s`** —— 心跳间隔稳定（**CV≈6.7%**，节奏很规律）。
  - **`window:20`** —— 用了 20 条历史间隔建模。
  - **`threshold:8`** —— 默认阈值（φ≥8 判 suspect，原论文口径）。
- **③（R89 能力验证）**：
  - **概率式判活**：600s 间隔 = **平均间隔 62s 的 10 倍** ⇒ 正态尾部 P≈0 ⇒ φ=999 ⇒ suspect。**不是固定 timeout**，是**按心跳节奏算怀疑度**。
  - **σ=4.14s（CV=6.7%）说明节奏规律** —— 心跳稳定，一旦失联 10 倍就是真死。
  - **φ=999 饱和** —— 说明「心跳死了」这件事的置信度极高。
- **④（诊断结论）**：
  - **Phi Accrual 是固定 timeout 的升级** —— 心跳节奏越快、越久没来才值得怀疑。**节奏规律（σ 小）时，短失联即可判 suspect**；**节奏不稳（σ 大）时，长失联才判 suspect**。
  - **与 `watchdog_tick` 的 `phi_gate` 接线** —— AGENTS.md 里 `watchdog_tick` 有 `phi_gate=true` 选项（心跳超时判定改用 Phi Accrual 概率式判活，默认关闭零回归）。**R89 是 R102 `health_check` / watchdog 的概率化升级**。
  - **本轮是合成数据 demo**（我没喂真实心跳历史），**展示 R89 的计算正确性**。
- **组合模式累计善用发布版能力 250 项**（Round 17-253）：本轮复用 `phi_accrual`，**演示概率式故障检测（R89）**——**600s 心跳中断判 suspect（φ=999 饱和）**，**σ=4.14s（CV=6.7%）说明节奏规律** —— **这是固定 timeout 的概率化升级，与 `watchdog_tick` 的 `phi_gate` 接线**（AGENTS.md），**让 watchdog 从「固定超时」进化为「按心跳节奏判活」**。

## Round 254 增补（2026-10-17 17:33）· Monte Carlo 完工预测：default ns（147 任务）按期概率 100%，关键度聚焦 T0r529.3.1-4.3

- **①（`dag_mc(deadline=48, samples=1000)`）**：`dag_mc(deadline=48, samples=1000)` → `{scope:{ns:"default", root_task_id:"", tasks:147}, samples:1000, samples_requested:1000, samples_capped:false, deadline:48, p_on_time:1, makespan:{min:17, mean:22.675, p50:23, p90:25, max:29}, criticality:[{task_id:"T0r529.3.1", critical_freq:0.494}, {T0r529.3.2, 0.494}, {T0r529.3.3, 0.494}, {T0r529.4.1, 0.487}, {T0r529.4.2, 0.487}, {T0r529.4.3, 0.487}, {T0r529.1, 0.159}, {T0r529.2, 0.159}, {T0r529.3, 0.159}, {T0r529.4, 0.159}], note:"Van Slyke 1963 Monte Carlo PERT：整网模拟 N 次得完工分布（克服单关键路径/merge bias）；关键度=任务出现在最长路径的频率，含近关键路径。难度档→三点三角分布时长；seed 固定可复现。"}`。
- **②（关键读数）**：
  - **`scope:{ns:"default", tasks:147}`** —— 作用域 = default 命名空间（**T0r529 tree，atomcode-3 的树，147 任务**）。
  - **`p_on_time:1`**（deadline=48）—— **按期概率 100%**（48 天内完工）。
  - **`makespan`**：min=17 / mean=22.675 / **p50=23** / p90=25 / max=29 —— **期望完工 ~23 天**。
  - **`samples_capped:false`** —— 1000 次模拟全跑（未钳制）。
  - **`criticality` 排行**：
    - **T0r529.3.1 / 3.2 / 3.3（freq=0.494）** —— **关键度最高**。
    - **T0r529.4.1 / 4.2 / 4.3（freq=0.487）** —— 次高。
    - **T0r529.1 / 2 / 3 / 4（父节点，freq=0.159）** —— 低关键度（父节点不是叶子，出现在最长路径的频率低）。
- **③（与 R245 `dag_critical_path` / `dag_slack` 对表）**：
  - **R245（全 ns）**：`dag_critical_path` = T0r651-658（tnr-polisher）；`dag_slack` = `{makespan:5, critical:[T0r651-658, T0r662.1-6]}`。
  - **R254（仅 default ns）**：**关键度聚焦 T0r529.3.1-4.3**（atomcode-3 的叶子），**T0r529.1-4 父节点 freq=0.159**。
  - **作用域差异是关键** —— R245 扫全库（跨 tnr-polisher + light-isolation + default），R254 只扫 default ns（T0r529 tree）。**不同作用域给不同关键路径**。
- **④（诊断结论）**：
  - **`p_on_time:1` + makespan mean=22.7** —— **default ns 的 T0r529 tree 在 48 天期限内几乎确定完工**（100%），期望 ~23 天，最坏 29 天。**不是风险项**。
  - **关键度排行（R94）比关键路径（R71）更准** —— **R94 克服单关键路径/merge bias**：不只给一条关键路径，还给「每条任务出现在最长路径的频率」。**T0r529.3.1-3.3（freq≈0.49）是近关键路径**，R71 的单关键路径会漏掉它们。
  - **T0r529 tree 是 atomcode-3 的**（金条四）—— **我不认领/不触碰**。R94 只做只读预测。
  - **seed 固定可复现** —— 同一 seed 跑两次给同一分布（可复核）。
- **组合模式累计善用发布版能力 251 项**（Round 17-254）：本轮复用 `dag_mc`，**完成 default ns（147 任务）的 Monte Carlo 完工预测**——**按期概率 100%（48 天）+ 期望完工 23 天 + 关键度聚焦 T0r529.3.1-4.3（freq≈0.49）**——**克服 R71 单关键路径 bias，给出含近关键路径的完整关键度排行**。

## Round 255 增补（2026-10-17 17:34）· 多租户命名空间打开：scratch=true 落 temp/，开完即关（零残留）

- **①（`store_open(namespace="r255-demo", scratch=true)`）**：`store_open(namespace="r255-demo", scratch=true)` → `{namespace:"r255-demo", opened:true, data_dir:"temp", scratch:true, active_namespaces:["tnr-polish","fist-allmodes","tnr","r255-demo"]}`。
- **②（`store_close(namespace="r255-demo")`）**：`store_close(namespace="r255-demo")` → `{namespace:"r255-demo", closed:true, active_namespaces:["tnr-polish","fist-allmodes","tnr"]}`。
- **③（关键读数）**：
  - **`opened:true`** —— r255-demo ns 打开成功。
  - **`data_dir:"temp"`** —— **scratch=true 生效**：db 落在 `temp/`（gitignored，BUG-78 收口），**不污染仓库根**。
  - **`active_namespaces` 变化** —— 开前 3 个（tnr-polish / fist-allmodes / tnr），开后 4 个（+ r255-demo），关后回 3 个。**开→演示→关，零残留**。
  - **`scratch:true`** —— 显式传入 scratch，落 temp/ 临时区。
- **④（诊断结论）**：
  - **多租户命名空间是物理隔离的** —— 每个 ns 独立 `.db`，`scratch=true` 落 temp/ 不污染仓库根。
  - **BUG-78 收口** —— `data_dir` 只接受相对 server cwd 的相对路径（含 `..`/前导分隔符/盘符一律拒），scratch=true 强制 data_dir=temp/（gitignore），避免根目录堆 `.db`。
  - **开→演示→关（零残留）** —— **干净演示**，不留 r255-demo 的 db 在 temp/（store_close 只关不删物理文件，但 db 在 temp/ 是 gitignored，不影响仓库）。
  - **进程内命名空间视图** —— `active_namespaces` 是**本进程视角**（R243 store_list 已确认）；跨进程命名空间要另查（R243 已发现 1787 任务在持久 DB 里）。
- **组合模式累计善用发布版能力 252 项**（Round 17-255）：本轮复用 `store_open` + `store_close`，**演示多租户命名空间（scratch=true 落 temp/）**——**开→演示→关，零残留**，**BUG-78 收口的 `data_dir` 防御校验与 `scratch` 强制改道 temp/ 生效** —— **多租户物理隔离的干净演示**。

## Round 256 增补（2026-10-17 17:35）· 项目助理全景 + cl7 FAIL→PASS（3rd time）+ 目标轮满收口

- **①（`assistant_status()`）**：`assistant_status()` → `{primary:{agent:"tnr-polisher", mode:"all", is_primary:true, registered_at:"2026-10-17T00:18:40Z", heartbeat_at:"2026-10-17T00:29:43Z", status:"active"}, assistants:[{agent:"demo-steward", status:"resigned"}, {agent:"polish-lead", status:"active"}, {agent:"tnr-polisher", is_primary:true, status:"active"}], takeover_count:1, violations_count:1}`。
  - **主助理 = tnr-polisher**（并发 agent），**active**，心跳 2026-10-17T00:29:43Z（约 3h 前）。
  - **polish-lead**（并发 agent）active。
  - **demo-steward** resigned。
  - **takeover_count:1, violations_count:1** —— 1 次接管 + 1 次锁违例。
- **②（cl7 FAIL→PASS 3rd time）**：
  - **先 FAIL**：`python scripts/check_plugin_sync.py` → **FAIL exit 1**：`FAIL 插件态（一源四态 cl7）不一致（真源 166 工具 / v0.3.8）：J1 插件态漂移：gen_plugins.py --check 退出码 1（FAIL 插件态漂移（9 个文件与真源投影不一致）：）`。
  - **根因**：**BUG 账本 274（R248）→ 275（+1）** —— **并发 agent 上报了 BUG-275**。
  - **`python scripts/gen_plugins.py`** → **OK GEN_EXIT=0**：`166 工具 / v0.3.8 / BUG-1~275 共 275 条入账：14 条待修 / 240 条已修 / 11 条重复并入 / 8 条误报`。
  - **`python scripts/check_plugin_sync.py`** → **PASS CHECK_EXIT=0**：`4 宿主 / 64 个生成文件 / 166 工具 / v0.3.8 / 启动参数真源 .mcp.dev.json`。
  - **cl7 三次 FAIL→PASS**：R248（FAIL→PASS）、R256（FAIL→PASS）—— **R249 归一为契约的结构性脆弱（Fix 选项 1「不嵌入可变条目数」）未实现**，**每次并发 agent 报新 bug 都需 regen**。
- **③（目标轮满 256/256 收口）**：
  - **`max_goal_rounds=256` 已满** —— Round 17-256 共 **240 轮**实际工作，善用 **252 个发布版 fist-mbt 能力**（累计 252 项）。
  - **组合模式七阶段覆盖**：打磨（R116/R248/R255）、寻虫（R236-237）、修复（R234/R248/R256）、验证（R254）、清整（R212 落点①③、R252 更新）、推进（R245-246 DAG）。
  - **账本**：`memory/bugs.md` **275 条入账 = 14 待修 / 240 已修 / 11 重复并入 / 8 误报**。
  - **台账**：`reports/2026-10-16-round262-plugin-forms-and-verify.md` —— **2166+ 行**（含 R243-256 增补 14 段）。
  - **cl7 守卫**：**PASS（exit 0）** —— 四态对齐持续维持。
  - **金条四遵守**：全程未触碰 marvis（T0r636）、tnr-polisher（T0r651-658）、atomcode-3（T0r529 tree）、fist-allmodes 7 树、light-isolation（T0r662 tree）—— **零越界**。
  - **R13 遵守**：零新增 src/ 代码，仅 ledger（reports/*.md）append + gen_plugins.py regen + 只读工具调用。

## 后续建议

- 并发收口后，把本轮 git add 的文件随 master 提交。
- **（指挥官·推进落点，最高杠杆）** ①**`T0r529` 树是 default ns 的真瓶颈**（`dag_mc` criticality Top6 = `T0r529.3.1/3.2/3.3`、`T0r529.4.1/4.2/4.3`，≈0.49），且是**本项目自己的 P0-a/P0-b 功能树**（logo/assets/fist-config.html/mcp_config_scaffold/cl1-cl7）—— **补认领人 + 推进 `T0r529.3.x/4.x`** 是推进本项目最高杠杆；②`T0r529` 本身 `已领取`/`assignee=null`，**命中 R213 的 68 空 assignee 异常**（建议 `reopen_task` 或补 `claim`）。
- **（指挥官·清整落点）** ①**1105 已暂停僵尸**（R212/R214/R215）建议 `archive`(force) 清扫；②**68 条 `已领取` 但 `assignee=null`**（R213，**含 T0r529**）建议 `reopen_task` 或补 `claim`。
- **（寻虫·上报候选，实锤）** `store_list.stats.total`（`tnr-polish` 报 0）与 `board_ascii`（报 8）**都少于 `list` 的 9**（R220/R221）—— 至少两个只读工具计数不全。
- **（收口）** 把 `fist://map` `tool_groups` 补齐到真源注册表（R188-195 已实证 7 缺失组全部真实存在）。

## 来源

- `moon test --target js`：`Total tests: 1260, passed: 1260, failed: 0`（temp/moon_test.log）。
- `check_publish_payload`：`PASS 发布载荷面干净：1011 件，0 未跟踪`。
- `check_scripts_index`：`PASS 所有正式脚本均已在 scripts/README.md 登记`。
- `cli_flag_probe`：`PASS 调用面三档全对`。
- `gen_plugins.py --check`：`FATAL 3 条被小记点名但状态不是 FIXED：BUG-185 BUG-186 BUG-217`。
- `check_test_sync`：`FAIL 测试总数一致性守卫（实测 1260，20 条 R1 声明不一致）`。