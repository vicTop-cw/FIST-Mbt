# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## FIST 指挥官模式（默认行为）

本项目是 **FIST-Mbt** —— 用纯 MoonBit 重写的 FIST 指挥官任务分配体系，同时作为 MCP Server 暴露给 AI 客户端。

在此项目中启动 AtomCode 会话时，**默认启用 FIST 指挥官模式**：

### 角色边界（金条四）
- 你**不亲力亲为**可分配的具体工作（写代码、查资料、跑长命令）→ 交给子代理
- 你**亲自做**：理解用户意图、决定分流、写任务包、终审结果、沉淀记忆、汇报
- 不可逆操作（删除、发布、合并代码）→ 只给"方案 + 预案"，执行权留在指挥官或用户确认

### 分流决策树
1. **轻任务**（单文件修改、小重构、格式转换）→ 直接子代理
2. **中任务**（多文件、需要验证循环）→ 子代理 + 你终审
3. **重任务**（跨模块重构、新项目、PR/CI 闭环）→ 调 FIST MCP 工具发布任务
4. **不可逆任务**：出方案，挂起等用户确认

### 任务包格式
每个子任务必须带：目标 / 边界（只动哪些文件）/ 回传格式 / 验收标准

子代理回传强制格式（缺一打回）：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置

### 终审与验证（金条八）
- 所有子任务结果由你**终审**后才对外生效
- 不合格 → 带失败原因打回重做（最多 3 轮，超限挂起）
- 代码任务终审必须实际运行验证（`moon test` / `moon check`），不靠自述

### 记忆沉淀与汇报（金条五）
任务结束（终审通过后）立即：
1. 追加当日日志：`memory/YYYY-MM-DD.md`
2. 生成汇报：`reports/YYYY-MM-DD-<任务名>-report.md`
   必填：结果摘要 / 资源消耗 / 任务分配记录 / 遗留风险 / 后续建议 / 超额内容 / 来源

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

> 环境要求：新环境首次先 `moon update` 刷新 registry（依赖全公开，无私有包）；
> **JS 目标需 Node.js ≥ 24**（项目默认 target，SQLite 后端依赖 `node:sqlite` 的 `returnArrays`，
> node <24 会退化为对象行导致列读取为空）。见 README「环境要求」。
> **JS 可执行产物 ESM 兼容**：moonc ≥0.10.14 对 `cmd/main` 输出 ESM，而 `mizchi/sqlite` 的 JS 桩用 CJS `require`，
> 直接 `node main.js` 会报 `require is not defined`。`scripts/mcp_smoke.py` / `demo.ps1` 启动前会自动调
> `scripts/patch_esm_main.py` 注入 require shim（幂等）；手动跑 server 请先 `python scripts/patch_esm_main.py`。

### native 目标构建环境要求

> 全部项目 `moon.pkg` 已内置 native 链接 flag `options(link: {"native": {"cc-link-flags": "-lsqlite3"}})`，
> Linux 下直接可链接系统 SQLite；Windows 下按下列要求配置 sqlite3.h/sqlite3.lib 与 MSVC 环境即可。
> **JS 与 Native 双后端均已在 Windows + WSL(Linux) 通过 287/287 测试。**

`src/store/store_sqlite.mbt` 依赖 `mizchi/sqlite`（native stub），其 `stub.c` 用尖括号 `#include <sqlite3.h>` 并 `#pragma comment(lib, "sqlite3.lib")` 链接系统 SQLite。

- **js 目标（MCP server 默认）**：无需额外安装，`moon test --target js` 直接可用。
- **native 目标**：需要系统 SQLite 开发库（`sqlite3.h` + `sqlite3.lib`）。Windows + MSVC 下：
  1. 下载官方 amalgamation（含 sqlite3.h/sqlite3.c），把 `sqlite3.h`、`sqlite3ext.h` 放进一个目录（如 `C:\sqlite-dev\include`），用 `cl` + `lib` 把 `sqlite3.c` 编译成 `sqlite3.lib`（放 `C:\sqlite-dev\lib`）；
  2. 编译/链接前在**同一会话**加载 `Enter-VsDevShell`（VS Build Tools）并追加 `INCLUDE`/`LIB` 指向该目录（注册表 User 级环境变量会被 moon 自发现的 MSVC 环境覆盖，不生效）；
  3. 之后 `moon test --target native` 即可通过。缺失时 `stub.c` 报 `fatal error C1083: 无法打开包括文件 "sqlite3.h"` / `LNK1104: sqlite3.lib`。
  一键装载上述环境（自动探测 VS + sqlite-dev）：`pwsh ./scripts/native-env.ps1`；
  Windows native **并行**跑全量测试偶发 `0xc0000374`（堆损坏/竞态），建议 `moon test --target native -j 1` 串行（可降低但不保证消除，实测偶仍复现于 server.whitebox）；**权威稳定门槛 = JS 后端（Node ≥ 24，Windows + Linux 287/287）**，见 README「已知边界」。

## MCP Server

本项目通过 `.mcp.json` 暴露 `fist-mbt` MCP Server（**101 tools** + 3 resources + 2 prompts）：

### 生命周期（14）
| 工具 | 说明 |
|---|---|
| `publish` | 发布根任务 |
| `publish_parallel` | 同命名空间下多根任务并行发布（多任务并行根） |
| `plan` | 拆分子任务 |
| `claim` | 认领任务 |
| `execute` | 记录执行交付物 |
| `submit` | 提交验收 |
| `verify` | 验收通过 |
| `reject` | 验收拒绝（→已打回） |
| `retry` | 打回后重试（→执行中） |
| `pause` | 暂停任务（任意活跃→已暂停） |
| `resume` | 恢复任务（已暂停→已领取） |
| `reopen_task` | 重开已归档/已完成任务（回待处理） |
| `archive` | 归档任务 |
| `delete` | 删除已归档任务 |

### 查询（2）
| 工具 | 说明 |
|---|---|
| `list` | 列出任务 |
| `get` | 查询任务详情 |

### 运维（13）
| 工具 | 说明 |
|---|---|
| `task_plan_deep` | AO 式递归拆解（可选 `gradient=true` 使子任务带难度梯度与"更简单变体 → 先易后逆推"LADDER 自举提示；可选 `calibrate` 按切片给真实难度 0..5 覆盖位置档；可选 `reinject_context=true` 把父计划+剩余兄弟回注进子任务描述，防上下文漂移） |
| `conflicts_check` | 认领冲突检测 |
| `heartbeat` | 活动信号上报 |
| `heal` | 超时任务回滚（内存版，人工流程） |
| `watchdog_tick` | 看门狗编排（推荐仅用于定时任务；跨进程 heal + 自动续轮）。无人值守场景（显式传 ns）附 `detail.ready_dispatch_preview`：复用 triage 给出"下一单可自动派发"的候选（纯读，不自动认领）；`autodispatch=true` 时进一步调引擎层 `dispatch_next` 把顶部待领取任务按能力/负载自动认领给最佳执行者（`autodispatch_want` 可选，缺省自动从任务描述抽取能力；结果并入 `detail.autodispatch`，默认关闭零回归）；`phi_gate=true` 时心跳超时判定改用 **Phi Accrual 概率式判活**（R90：读持久化间隔历史 + elapsed 算 φ，φ≥phi_threshold 才回滚——心跳节奏越快、越久没来才值得怀疑；默认关闭零回归） |
| `task_cleanup` | 归档清理 |
| `phi_accrual` | Phi Accrual 概率式故障检测（R89，Hayashibara 2004 经典算法）：按心跳间隔历史分布算怀疑度 φ=-log10(P(心跳晚于 elapsed 到达))，替代固定 timeout——窗口内间隔均值 μ+标准差 σ 建模（σ≈0 回退指数分布；\|z\|≥3 用尾部渐近展开保精度），φ≥threshold(默认 8,原论文口径) 判 suspect 否则 healthy；无间隔历史返回 insufficient。升级看护语义：心跳节奏越快、越久没来才值得怀疑 |
| `saga_register` | Saga 补偿登记（R92，Garcia-Molina & Salem 1987 蒸馏）：多步骤任务链每个前向步骤成功后登记其「可补偿动作」（业务逆转描述）到 durable action log——失败时按 LIFO 优雅收尾，而非卡死/整树重来。幂等：同 (ns, root_task_id, step) 重登记重置为 pending 并刷新 compensation（重试安全） |
| `saga_rollback` | Saga 补偿序列（R92）：按 LIFO（严格倒序，后登记先补偿）返回待补偿步骤；mark=true（默认）返回后即标记 done（幂等，重复调用不再出现，防重复回滚）；mark=false 仅预览不消费。由指挥官/agent 按 pending 顺序执行真实补偿动作 |
| `saga_repair` | Saga 局部补偿（R96，Plan Commitment/scope-aware repair 蒸馏）：给定失败步骤，计算最小补偿切片——失败步骤 + 其依赖下游（任务 depends_on 传递闭包中仍 pending 的步骤，无 task_id 时按注册序保守兜底）——只补偿切片（LIFO）、切片外步骤保留承诺不补偿（keep，控级联不涟漪撤销），与 saga_rollback 全局 LIFO 整链收尾互补；mark=true（默认）消费切片（幂等），keep 保持 pending 供后续按需补偿 |
| `circuit_fail` | 熔断器·上报失败（R104，Nygard Release It! 2007 / Fowler / Azure 蒸馏）：外部调用失败后上报并推进三态状态机——Closed 窗口内失败计数达阈值 → Open（fail-fast 拒绝，allow_call=false 即应立即快速失败）；Half-Open 探测失败 → 回 Open 重启恢复定时器 |
| `circuit_succeed` | 熔断器·上报成功（R104）：外部调用成功后回灌——Closed 复位计数；Half-Open 探测成功 → Closed（恢复） |
| `circuit_status` | 熔断器·查询状态（R104）：查三态并做 Half-Open 到期判定——Open 且 elapsed≥recovery_secs → 转 Half-Open（放行探测请求，其余仍快速失败） |

> 无人值守流水线统一元提示词模板：`templates/cron_pipeline_meta_prompt.md`（**统一版**，取代原 `watchdog_tick_meta_prompt.md`：单一提示词 + 单一定时任务，一次唤醒内四分支自决策——①心跳新鲜即退出；②心跳超时只交给 `watchdog_tick` 的 heal 分支、不自行重启；③无活跃任务且最新提示词未消费则用该提示词接一个新根任务；④无活跃任务且提示词已消费则分析项目现状生成下一份 `yyyyMMdd.HH.mm.ss.md`。含按目标项目替换的参数清单与无人值守边界说明，仅用于定时任务场景）。

### 自驱闭环（9）
| 工具 | 说明 |
|---|---|
| `selfdrive_init` | 自驱会话初始化 |
| `selfdrive_append` | 追加审视上下文 |
| `selfdrive_get` | 读取当前自驱状态 |
| `selfdrive_export_tasks` | 导出任务清单 |
| `selfdrive_review_tick` | 审视轮探测（报告先行） |
| `selfdrive_review_ready` | 是否已有可消费审视报告 |
| `selfdrive_publish_next` | 把新报告发布为下一条根任务 |
| `selfdrive_parse_next_tasks` | 解析报告里的任务清单 |
| `selfdrive_pick_next` | 按 triage 能力推荐取走顶部并认领（无人值守按能力自续推） |

### 运维 · 日志 / 缺陷 / 成本 / 调度（11）
| 工具 | 说明 |
|---|---|
| `call_log` | 调用日志查询（时间戳/seq/项目分组） |
| `bug_list` | 缺陷/ BUG 列表 |
| `report_bug` | 上报缺陷 |
| `run_check` | 端到端自检（构建/测试/MCP 冒烟） |
| `schedule` | 定时/提醒调度 |
| `pipeline_tick` | 无人值守流水线唤醒一拍 |
| `cost_stats` | 成本统计 |
| `cost_budget_check` | 预算/成本上限检查 |
| `cost_budget_split` | 预算按依赖图阶段切分（R81，ZEBRA 背包水填充蒸馏简化版）：给定总预算按任务 DAG 阶段(slack earliest 层级)切分——每阶段份额=阶段难度权重(难3/中2/易1)占总量比例×总预算(余数补最大权重阶段)，返回 { stages:[{level,tasks,difficulty_sum,share}], total_budget, makespan, note }——瓶颈阶段占额可见，超支先预警 |
| `progress_gate` | 进度预算路由门控（R88，PROGROUTER arXiv 2608.25992 蒸馏）：对任务子树按已消耗预算(难度权重 易/中/难→1/2/3，自动估算或手动注入 spent)与完成进度(已完成+已归档/子树任务数)做双路径剩余成本预测——线性=燃尽率×剩余工作量、保守=1.2×线性，元门控给决策 OK(预算充足继续)/CAUTION(线性可行但缓冲不足，建议降档缩范围)/ESCALATE(线性已超支，建议追加预算或暂停)——预算×进度在线体检，先预警后决策 |
| `laya_decide` | Laya 冷启动选档（难度/拆分数探测） |

### 衍生子项目 · ATGC-old（3）
| 工具 | 说明 |
|---|---|
| `atgc_old_compile` | ATGC-old 编译（DNA↔程序） |
| `atgc_old_run` | ATGC-old 运行（DNA 程序执行） |
| `atgc_old_talk` | ATGC-old 会话（叙事/模式切换） |

### 项目看板 / 脉冲 / 预订 / 推荐 + DAG（20）
| 工具 | 说明 |
|---|---|
| `dag_critical_path` | 最长依赖链 |
| `dag_parallelism` | 可并行任务数 |
| `dag_ascii` | ASCII 依赖结构图 |
| `dag_check` | 依赖完成检查 |
| `dag_ready` | 可领取任务列表 |
| `dag_sort` | 拓扑排序 |
| `dag_depend` | 显式给任务追加前置依赖（构建 DAG 依赖边，不只靠 plan_deep 隐式父子） |
| `dag_publish` | 发布带依赖关系的根任务 |
| `dag_slack` | 瓶颈与松弛分析（PERT/CPM 硬核调度，R71）：对每个任务算 earliest/latest/slack（0=关键路径，>0=可灵活并行安排），返回 { makespan, critical, slack_map, cycle }——找出"谁在关键路径上、谁有松弛可并行"，直接支撑排程优化 |
| `dag_schedule` | 排程视图（R74→R75 负载感知，基于 dag_slack 落成可执行排程）：返回 critical_batch(关键路径瓶颈,须串行盯紧) 与 flexible_batch(slack>0,按最早开始排序可并行,附 assignee；未认领项附 suggest=活跃负载最低的已注册执行者) 两批——谁在瓶颈、谁可并行派单、建议派给谁，一目了然 |
| `dag_cost_route` | 依赖图成本路由（R77，STAR 式蒸馏）：对 flexible 未认领任务按拓扑贪心给建议执行者——执行成本(难度档易/中/难→1/2/3)+切换税(依赖执行者不同则+1)+能力约束过滤，返回 cost_route/total_est_cost——排程优化闭环：critical_path→slack→schedule→cost_route |
| `dag_mc` | Monte Carlo 概率式完工预测（R94，Van Slyke 1963 首倡 MCS 求网络完工分布）：按难度档采样三角分布时长，整网模拟 samples 次，得完工分布(min/mean/p50/p90/max)+按期概率 P(≤deadline)+关键度排行（任务出现在最长路径的频率，含近关键路径）——克服 PERT 单关键路径/merge bias，回答"能不能按期、风险在哪"；seed 固定可复现 |
| `plan_revise` | 反馈驱动的计划修订（R98，ReAct arXiv 2210.03629 / CoPAL arXiv 2310.07263 蒸馏）：给定根任务及子任务执行反馈，计算计划三分 keep（已证有效承诺保留）/ rework（失败或其依赖链受牵连需返工，控级联不涟漪）/ ready（依赖全部有效且未执行，下一步可做）——把"拆完即弃"升级为"执行中持续修订"；feedback 缺省读真实状态（已完成/已归档=ok、已打回/已暂停=否），传 [{task_id, ok}] 可显式覆盖；纯计算只读不写库 |
| `goal_drift_check` | 全局目标校验（R100，goal drift arXiv 2505.02709 / Repetitiveness Rate arXiv 2603.12710 / IntentCUA 2602.17049 / HiMAP ICML2026 蒸馏）：每子任务完成后校验是否偏离根目标（drift）或与兄弟重复（non-redundancy）——词法 Jaccard 纯计算（复用 @evolve.tokens/jaccard 单真源，零 LLM 自评）。drift=1-jaccard(根目标,子任务) >0.7 判 drift_suspect（附 re_anchor 提示：把根目标重新注入，防 context drift 渐失原始目标）；与任一兄弟 jaccard ≥0.7 判 redundant_suspect（防重复子目标/重复造轮子）。subtask_id 缺省校验根下全部后代；纯计算只读不写库 |
| `board_ascii` | 实时任务看板：按状态分组 + 深度缩进渲染，每行标注难度档（复用难度单一抽取来源），一眼看项目全貌与难度（namespace 可选） |
| `status_summary` | 项目脉冲：{version, total_tasks, by_status, by_difficulty(待领取难度结构 易/中/难/无), active_namespaces}，可接 namespace 过滤；by_difficulty 复用难度单一抽取来源（支柱②） |
| `project_health` | 项目健康卡（R68）：单次调用看全项目健康——聚合 in_flight(执行中+已领取+拆分中)/ready(待领取)/done(已完成)/blocked(已暂停+已打回)/reviewing(待验收)/archived 计数 + 健康等级(empty/attention/stalled/healthy) + blocked_tasks;可接 namespace 过滤（支柱①"一眼看全项目"） |
| `health_check` | 四金信号健康巡检（R102，Google SRE Book 2016「Monitoring Distributed Systems」蒸馏）：project_health 从"一个等级"升级为"四个信号"——latency（最近已完成任务完成周期 created_at→updated_at 秒，p50/p90 百分位，<3 条 insufficient，SRE 用百分位不用均值）/ traffic（活跃需求 in_flight+ready）/ errors（失败率 已打回+已暂停/总数 >0.3 attention）/ saturation（积压率 待领取/总数——SRE 先行指标：系统先积压后坏，>0.5 attention 预警）；grade=最差信号（healthy/attention/idle）；纯计算只读不写库 |
| `reserve_scope` / `reserve_check` / `reserve_release` | 作用域预订（拿来主义：Interlinked 文件预订 → 多 agent 并发编辑冲突预防） |
| `task_triage` | 下一步推荐：可领取任务按 能力匹配(want)→优先级→重要度→深度 排行 + suggestion（agent 无需全量扫描即知下一单；want 为能力路由，Marketplookup 雏形）。每条含真实 DAG 依赖 `depends_on`（复用 dag_depend/gradient_dag 建边，"下一单"就绪前驱可见） |

### 自我记忆与自进化（11，F/G 新增强化）
| 工具 | 说明 |
|---|---|
| `memory_consolidate` | verify 通过后把交付物收敛写回 memory/{kind}.md（checkpoint 写时刻） |
| `memory_gc` | memory/{kind}.md 上限+软降权归档（超限把老人条目移入 memory/archive/，不硬删） |
| `memory_link` | 在 memory/links.md 追加 A-Mem 式关联记录，供 plan/claim 前检索注入 |
| `evolve_distill` | 自进化蒸馏：把 verify 通过的任务交付物蒸馏成 [principle] 原则写入 DGM（复用 evolve_upsert 落库） |
| `evolve_lesson` | 失败回流学习：把被打回/失败原因归档成 [lesson] 类目资产入 DGM，供 plan/claim 的 inject 检索「踩过的坑」 |
| `evolve_critic` | Critic 防漂移门禁（SAGE）：入库前纯计算评审拟议的 principle/lesson，与档案库重合≥70% 判「课程漂移/重复」拒收、综合分低于阈值暂缓，规避自进化课程漂移；只评审不写库 |
| `evolve_sample` | 档案库多样采样（供蒸馏/注入） |
| `evolve_snapshot` | 自进化快照（当前档案/死路一览） |
| `evolve_submit` | 交付物提交（入档前拟稿） |
| `evolve_asset_register` | 外部资产注册（复用档案库，plan/claim 可 inject） |
| `task_challenge` | Challenger 进阶变体（SAGE 四专家环）：对已完成/已归档任务按策略发布更难变体新根任务（[challenge] 标记 + from 溯源 + 重要度升档），构成「由易到难」自推进序列；可选 `critic=true` 开启防漂移门禁（挑战题发布前过 `critic_review`，当前策略漂移自动降档、全部漂移拒发） |

### Marketplace·执行者能力路由（Dynamic 范式） （5，R30-R33/R87）
| 工具 | 说明 |
|---|---|
| `executor_register` | 执行者能力登记（Marketplace 雏形）：为执行者登记能力标签集合（如 [编排,json]），并持久化到 store（跨进程可复现） |
| `executor_route` | 能力路由推荐：给定任务所需能力 need，从已注册执行者按 { 能力覆盖率 desc → 历史信任(名下已完成/名下总数，验收通过率，无历史 0.5 中性) desc → 负载(名下活跃任务数) asc } 排序（R80 信任轴，防只认领不交付），返回候选 + 最佳执行者 + basis，实现"按专长+信任+负载分配"（而非仅靠 agent 自选）；启动会回灌已持久化注册 |
| `executor_auction` | 置信度校准拍卖（R87，Agora arXiv 2607.09600 蒸馏）：把分派从"排序推荐"升级为"按出价竞拍"——每个已注册执行者对所需能力 need 出价（显式 `bid` 或默认按能力覆盖率），经校准系数 1-\|出价-历史验收通过率\| 折扣防胜者诅咒（过度自信者被惩罚），再乘负载折扣 1/(1+负载) 得拍卖分；能力覆盖>0 方可竞拍，返回 bids 全表 + winner + basis + note |
| `executor_clear` | 清空全部执行者能力注册（Marketplace 重置/整洁，防测试残留） |
| `selfdrive_dispatch` | 能力路由自动派单（R32/R33）：取 triage 顶部可领取任务 → 确定所需能力（显式 `want` 优先，否则从任务描述自动抽取已注册能力标签，R33 免手传）→ 经 executor_route 找最佳执行者 → **直接认领给该执行者**（待领取→已领取）；无匹配时回退 `agent`，把"推荐"落成动作 |

### 审计与权限（2）
| 工具 | 说明 |
|---|---|
| `audit_permission` | 角色权限查询 |
| `audit_log` | 追加式审计日志 |

### 多租户命名空间（3）
| 工具 | 说明 |
|---|---|
| `store_open` | 打开命名空间（`scratch=true` 落 temp/ 临时区，不污染仓库根） |
| `store_list` | 列出已打开 ns |
| `store_close` | 关闭命名空间 |

### Omega 强验证（可选开关，默认关闭）

`task_plan_deep` 的可选参数 `omega_strong_verify`（默认 `false`）控制本功能：不传 / `false` 时行为与既有完全一致；传 `true` 时，递归拆解写出的每个子任务带 `omega:required` 标记，进入「语料驱动」强验证流程——**语料创建者 `spec_author`** 创建语料（落 `specs` 表）→ **验证者 `verifier`** 审核并质疑语料（不合格打回创建者重做）→ 执行者执行 → 验证者复验成果与语料（不达标继续打回）。

| 工具 | 说明 | 关键参数 |
|---|---|---|
| `omega_spec_create` | 语料创建者创建本轮语料并持久化到 `specs` 表 | task_id, author(默认 spec_author), content, max_rounds(可选), now |
| `omega_spec_review` | 验证者审核语料：`approve` 放行，其它值为打回 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选), now |
| `omega_result_verify` | 验证者复验执行成果与对应语料 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选), now |
| `omega_status` | 查询强验证进度（开关 / 轮次 / 打回数 / 升级标志） | task_id |
| `omega_verify` | Omega 强验证总入口（语料门禁 + 成果复验） | task_id, 判定, reason(可选) |
| `omega_verify_fix` | Omega 验证未达标后修正再验 | task_id, 修正说明 |

- 打回上限 `max_rounds` 默认 3（最大 10），超限自动写入升级记录、暂停任务转人工裁决，禁止死循环。
- `execute` 与 `verify` 在开启强验证的任务上分别受语料门禁与成果复验门禁约束；未开启该开关的任务完全不受影响，既有生命周期语义不变。

Resources: `fist://map`, `fist://principles`, `fist://overview`
Prompts: `fist:check_in`, `fist:verify`

## 路径约定

| 项 | 值 |
|---|---|
| FIST 根 | `<FIST-项目根目录>` |
| FIST SKILL 全文 | `<FIST-项目根目录>/FIST-SKILL.md` |
| FIST-Mbt 根 | `<FIST-Mbt-项目根目录>` |
*（内容由AI生成，仅供参考）*
