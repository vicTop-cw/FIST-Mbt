# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## FIST 指挥官模式（默认行为）

本项目是 **FIST-Mbt** —— **AI 自驱式开发的项目管理者**：用纯 MoonBit 重写的 FIST 指挥官任务分配体系，同时作为 MCP Server 暴露给 AI 客户端。
一等的打磨对象只有两件——**自驱** 与 **递归拆解**；而本项目迭代自己所用的，正是这两件能力（工具面见「自我记忆与自进化」「开发模式与模板」两节，实证面见文末「实证伴生仓」段）。

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
> **JS 可执行产物 ESM 兼容**：moonc ≥0.10.14 对 `cmd/cli` 输出 ESM，而 `mizchi/sqlite` 的 JS 桩用 CJS `require`，
> 直接 `node main.js` 会报 `require is not defined`。`scripts/mcp_smoke.py` / `demo.ps1` 启动前会自动调
> `scripts/patch_esm_main.py` 注入 require shim（幂等）；手动跑 server 请先 `python scripts/patch_esm_main.py`。

### native 目标构建环境要求

> 全部项目 `moon.pkg` 已内置 native 链接 flag `options(link: {"native": {"cc-link-flags": "-lsqlite3"}})`，
> Linux 下直接可链接系统 SQLite；Windows 下按下列要求配置 sqlite3.h/sqlite3.lib 与 MSVC 环境即可。
> **JS 后端**：`moon test --target js` = **572/572**（2026-09-28 Windows 实测，四模式流水线自我迭代 Round 1~3 收口 + 一源四态 cl7 + 模型路由与外部执行器合并）。
> **Native 后端**：上一轮在 Windows + WSL(Linux) 通过 317/317；本轮未复跑 native，不据旧数宣称双端同版全绿。

`src/store/store_sqlite.mbt` 依赖 `mizchi/sqlite`（native stub），其 `stub.c` 用尖括号 `#include <sqlite3.h>` 并 `#pragma comment(lib, "sqlite3.lib")` 链接系统 SQLite。

- **js 目标（MCP server 默认）**：无需额外安装，`moon test --target js` 直接可用。
- **native 目标**：需要系统 SQLite 开发库（`sqlite3.h` + `sqlite3.lib`）。Windows + MSVC 下：
  1. 下载官方 amalgamation（含 sqlite3.h/sqlite3.c），把 `sqlite3.h`、`sqlite3ext.h` 放进一个目录（如 `C:\sqlite-dev\include`），用 `cl` + `lib` 把 `sqlite3.c` 编译成 `sqlite3.lib`（放 `C:\sqlite-dev\lib`）；
  2. 编译/链接前在**同一会话**加载 `Enter-VsDevShell`（VS Build Tools）并追加 `INCLUDE`/`LIB` 指向该目录（注册表 User 级环境变量会被 moon 自发现的 MSVC 环境覆盖，不生效）；
  3. 之后 `moon test --target native` 即可通过。缺失时 `stub.c` 报 `fatal error C1083: 无法打开包括文件 "sqlite3.h"` / `LNK1104: sqlite3.lib`。
  一键装载上述环境（自动探测 VS + sqlite-dev）：`pwsh ./scripts/native-env.ps1`；
  Windows native **并行**跑全量测试偶发 `0xc0000374`（堆损坏/竞态），建议 `moon test --target native -j 1` 串行（可降低但不保证消除，实测偶仍复现于 server.whitebox）；**权威稳定门槛 = JS 后端（Node ≥ 24，本轮 572/572）**，见 README「已知边界」。

## MCP Server

本项目通过 `.mcp.json` 暴露 `fist-mbt` MCP Server（**129 tools** + 3 resources + 2 prompts）：

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

### 运维（14）
| 工具 | 说明 |
|---|---|
| `task_plan_deep` | AO 式递归拆解（可选 `gradient=true` 使子任务带难度梯度与"更简单变体 → 先易后逆推"LADDER 自举提示；可选 `calibrate` 按切片给真实难度 0..5 覆盖位置档；可选 `reinject_context=true` 把父计划+剩余兄弟回注进子任务描述，防上下文漂移；可选 `boundary_probe=true` 追加一条『边界审视叶』作为全局输入域 owner，并给每条叶挂『边界四问(空输入/极值/非法输入/资源极限)』，治弱语料下的 Goodhart 下界（atgc-merge 归因报告机理 1/2）；两者默认 false 零回归） |
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
| `tx_contract` | 迁移契约检查（R109，Design by Contract 蒸馏：Meyer precondition/invariant/postcondition 三件套只读预检）——对 (task, action) 任一契约件失败 → verdict=rejected 整笔拒绝、状态 A 回稳（不落库）；全通过 → allowed。纯计算只读不写库（决策建议，执行权在调用方） |

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

### 运维 · 日志 / 缺陷 / 成本 / 调度（15）
| 工具 | 说明 |
|---|---|
| `call_log` | 调用日志查询（时间戳/seq/项目分组） |
| `bug_list` | 缺陷/ BUG 列表（每行带回 `linked_task_status`，`open_with_linked_done` 一次看见「账本说没修、任务库说修完了」的矛盾） |
| `bug_fix` | 批量标 FIXED：**同一笔**改抬头 + 落一条点名整批的 `### FIXED(<盖章时间> / BUG-a, BUG-b)` 小记（evidence 必填非空；幂等重跑；终态之间不互跳）。为什么不给"只改抬头"的路：记账规则把两者做成互锁硬门，分两次调用中间态就是 gen_plugins 拒绝产出的红账本 |
| `bug_mark_status` | 改判单条抬头状态（OPEN/DUPLICATE/FALSE_POSITIVE；**FIXED 一律拒**，走 `bug_fix`）。DUPLICATE 必须带 `dup_of` 且主编号合法（禁自指/禁链）；FALSE_POSITIVE 可选 `evidence` 追加一行立据。返回含 `from_status`/`changed`（同状态幂等 no-op） |
| `report_bug` | 上报缺陷 |
| `issue_scan` | 规则驱动源码扫描（打磨收尾引入）：递归收集目录下 .mbt 文件，内建 10 条 MoonBit 高危规则逐行匹配（除零/空数组下标/无保护 unwrap/unsafe_get/无保护整除/substring 越界/ignore 丢错/字符串下标/潜在溢出/空集合单例），产出 findings（rule/severity/file/line/code）+ by_severity/by_rule 聚合；命中可直接喂 `report_bug` 形成"扫描→上报→修复"闭环——免外部二进制、无绝对路径硬编码，MCP/CLI/skill 三态复用并随插件态分发四宿主；`include_tests`（默认 false）只扫产品代码跳过 `_test/_wbtest` 以降噪 |
| `eval_feedback` | 反馈收敛（R111，Evaluator-Optimizer schema 蒸馏：Anthropic E/O + Self-Refine 2303.17651 + Reflexion 2303.11366 + zubi.ai 四段式）——自由文本反馈归一为 Defects/Evidence/Fix/Acceptance 四段式契约 + 确定性 verdict（无缺陷且 acceptance 非空 → pass 可收敛；否则 fail + 缺证据/缺修复/缺段标注）；纯计算只读不写库，与 plan_revise 反馈修订互补 |
| `run_check` | 端到端自检（构建/测试/MCP 冒烟） |
| `output_validate` | 交付物硬门验证（R113）：对 artifacts 数组逐件验——path/check_key 二选一；path→文件存在/非空/invariant(contains/not_contains/min_chars)；check_key→external_results 字典引用，取 ok/code/stderr；返回 verdict(pass/fail)/passed/failed/checks，require_evidence=true 时强制非空 evidence |
| `schedule` | 定时/提醒调度 |
| `pipeline_tick` | 无人值守流水线唤醒一拍 |
| `cost_stats` | 成本统计 |
| `cost_budget_check` | 预算/成本上限检查 |
| `cost_budget_split` | 预算按依赖图阶段切分（R81，ZEBRA 背包水填充蒸馏简化版）：给定总预算按任务 DAG 阶段(slack earliest 层级)切分——每阶段份额=阶段难度权重(难3/中2/易1)占总量比例×总预算(余数补最大权重阶段)，返回 { stages:[{level,tasks,difficulty_sum,share}], total_budget, makespan, note }——瓶颈阶段占额可见，超支先预警 |
| `progress_gate` | 进度预算路由门控（R88，PROGROUTER arXiv 2608.25992 蒸馏）：对任务子树按已消耗预算(难度权重 易/中/难→1/2/3，自动估算或手动注入 spent)与完成进度(已完成+已归档/子树任务数)做双路径剩余成本预测——线性=燃尽率×剩余工作量、保守=1.2×线性，元门控给决策 OK(预算充足继续)/CAUTION(线性可行但缓冲不足，建议降档缩范围)/ESCALATE(线性已超支，建议追加预算或暂停)——预算×进度在线体检，先预警后决策 |
| `project_standards` | AI 项目开发规范（R116，机器投影；规范性正文真源 = `AI-DEVELOPMENT-STANDARD.md`）：通用 5 条（文档即实现/**一源四态**/确定性优先/增量零回归/自我迭代）+ FIST 专项 5 条（用自身能力迭代/**四态必须对齐**/证据梯至少 L4/重任务先拆 DAG/工具命名即文档）；附 7 项四态 checklist（cl1-mcp-exists → cl6-doc-sync → **cl7-plugin-forms-sync**），可直接喂 output_validate 当验收门禁。纯计算零依赖。白盒锁：`src/server/project_standards_wbtest.mbt`（此前该工具零覆盖）。 |
| `laya_decide` | Laya 决策（冷启动选档/功能路由 + 确定性回退）：有 Laya→sidecar 决定难度/拆分数/机制选择；无 Laya→降级到内建规则式决策分支（laya_route 纯计算：按任务描述关键词对机制族打分选 feature_route + 复杂度启发式给 split_n）。研发方向「功能太多难决策 / 复杂多任务不知用哪些功能」的落点 |
| `loop_create` | 创建组合环（Phase 6）：preset=full-iterate/fix-iterate/build-verify 或自定义 steps，注册到进程内 LoopRegistry |
| `loop_tick` | 推进一环（Phase 6）：取当前 steps[idx] → 返回 next_mode / next_round / should_stop / stop_reason |
| `loop_status` | 查询组合环状态（Phase 6）：name 空=列出所有已注册环，name 指定=单环完整 JSON |

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
| `omega_spec_create` | 语料创建者创建本轮语料并持久化到 `specs` 表 | task_id, author(默认 spec_author), content, max_rounds(可选) |
| `omega_spec_review` | 验证者审核语料：`approve` 放行，其它值为打回 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选) |
| `omega_result_verify` | 验证者复验执行成果与对应语料 | task_id, reviewer(默认 verifier), verdict, reason(可选), max_rounds(可选) |
| `omega_status` | 查询强验证进度（开关 / 轮次 / 打回数 / 升级标志） | task_id |
| `omega_verify` | 批量验证 spec JSON（schema + fingerprint 校验，accuracy < 100% 一票否决）——**不是**按 task_id 走的总入口 | specs(JSON 数组，每项 `{file_name, content}`) |
| `omega_verify_fix` | 对失败 spec 做根因分类 → 定向修复 → 回归验证（3 轮循环） | specs(JSON 数组), max_rounds(可选默认 3) |

- 打回上限 `max_rounds` 默认 3（最大 10），超限自动写入升级记录、暂停任务转人工裁决，禁止死循环。
- `execute` 与 `verify` 在开启强验证的任务上分别受语料门禁与成果复验门禁约束；未开启该开关的任务完全不受影响，既有生命周期语义不变。

### 开发模式与模板（2）
| 工具 | 说明 |
|---|---|
| `mode_list` | 返回 7 种自驱开发模式的完整信息（mode / name / description / constraints / template_path / forbidden_tools），纯计算只读，供 AI 选模式 |
| `mode_templates` | 检查 `templates/pipeline_mode_*.md` 全部存在性，返回 `{templates:{advance:true,...}, missing:[...]}`；`pipeline_tick`/`watchdog_tick` 的 `mode` 参数预检用 |

7 种自驱开发模式（真源 `src/ops/ops_modes.mbt` 的 `PipelineMode`（R117）；`mode_list` 下发的 name/constraints/forbidden_tools 都出自该文件；模板文件名由 `mode_template_path` 拼为 `templates/pipeline_mode_<mode>.md`）：

| mode | 中文名（mode_display_name 实测） | 约束为真的键 / 禁用工具 |
|---|---|---|
| advance | 持续开发新功能 | 无强制门禁键（默认模式） |
| polish | 打磨完善（不加新功能） | forbid_new_features；禁用 `publish` / `publish_parallel` / `dag_publish` |
| verify | API 枚举与完备性验证 | require_api_enum + require_doc_check |
| bugfind | 寻虫：issue_scan + 边界语料 | require_issue_scan + require_test_corpus + require_ocr |
| fix_and_merge | 修复 issues + 合并分支 | require_github_token |
| tidy | 项目打扫清整 | forbid_new_code；禁用 `publish` / `publish_parallel` / `dag_publish` |
| explore | 探索：按复杂度自选模式 | require_complexity_scoring + allow_parallel_modes + require_disjoint_files；唯一**不亲自开发**的模式——先量目标复杂度，再从其余 6 个单模式里选一个跑；要并行跑几个模式，前提是它们申报的文件作用域两两不相交（先过 `reserve_scope` 预订 + `conflicts_check` 查重，重叠即退回串行） |

### GitHub/GitCode 同步 · 缺陷上报通道（12）
| 工具 | 说明 |
|---|---|
| `github_env_check` | 检查同步环境变量配置（读 `FIST_GITHUB_ENABLED`/`FIST_GITHUB_REPO`/`FIST_GITHUB_TOKEN`），返回 enabled/repo/token_present/ready 四元组。纯计算只读，不碰网络——外部 AI 开发前先查此工具判断能否自动上报 bug |
| `github_queue_status` | 查看待同步 GitHub issue 队列状态——总数/pending/sent/最老条目/按严重度分布。纯计算读 JSONL 队列，不碰网络 |
| `github_flush_plan` | 为每条 pending bug 生成一条 curl 命令（含 `FIST_GITHUB_TOKEN` 占位符），**不执行任何网络调用**；外部拿到后手动/脚本执行，成功后调 `github_queue_mark_sent` 回写 |
| `github_flush_execute` | 一键执行 `github_flush_plan` 生成的 curl，直接在队列上发 issue。硬门控——`force` 必须显式为 `true`；JS target 真实执行 curl，native target 返回跳过提示，成功后自动回写 sent（从响应解析 `issue.number`） |
| `github_queue_mark_sent` | 标记一批 `bug_ids` 已同步（写 sent_at + github_issue_number），幂等安全 |
| `github_issue_close` | 按 bug_id→issue_number 映射批量关闭 issue（PUT state=closed）。硬门控——`force` 必须为 `true`；通常在 FIST 任务归档/完成后触发 |
| `github_issue_comment` | 给指定 bug_id 对应的 issue 追加评论（POST comments API）。硬门控——`force` 必须为 `true`；该 bug 须已 flush 成功过 |
| `github_issue_webhook_parse` | 解析 GitHub issue comment webhook payload，提取 `@fist-bot` 指令（reopen / challenge / close / blocked），返回结构化 action 供 FIST 闭环消费。纯计算正则匹配，零 LLM 零网络 |
| `gitcode_env_check` | 检查 GitCode 同步环境变量配置（读 `FIST_GITCODE_TOKEN`/`FIST_GITCODE_PROJECT_ID`），返回 enabled/repo/token_present/ready 四元组。纯计算只读，不碰网络 |
| `gitcode_queue_status` | 查看待同步 GitCode issue 队列状态——复用 `bugs_pending_github.jsonl`，含 `gitcode_project_id`/`gitcode_issue_iid` 字段。纯计算读 JSONL 队列，不碰网络 |
| `gitcode_flush_plan` | 为每条 pending bug 生成一条 curl 命令（GitCode API v4 + `PRIVATE-TOKEN` header），**不执行任何网络调用**；外部拿到后手动/脚本执行，成功后调 `gitcode_queue_mark_sent` 回写 |
| `gitcode_queue_mark_sent` | 标记一批 `bug_ids` 已同步 GitCode（写 sent_at + gitcode_issue_iid），幂等安全 |

### 模型路由 · 外部执行器（4，合并自兄弟项目 fist-model-router 与 FIST 的 aider/atomcode 执行器）
| 工具 | 说明 |
|---|---|
| `model_route` | 模型配额路由决策（免费优先 + 达 `threshold_pct`(默认95%) 自动切付费 + 付费耗尽回退免费 + 每模型独立 5h 滚动窗口）。参数：`project_dir`(必填，相对、拒绝对称/盘符/`..`)、`namespace`(可选默认 default，**每个 ns 一份独立配额账**)、`record_model`(可选：给名则 `used+1` 后再决策，留空=只问不消耗)、`config_json`(可选：RouterConfig JSON 文本覆盖池定义，同名模型已用配额保留；**非法 JSON 直接报错不静默回落**)。状态落盘 `{project_dir}/memory/model-router-{ns}.json` 跨进程复现；**只问不消耗＝零副作用**（不记账/不推进游标/`persisted=false`；给了 config_json 池定义时只播种定义不播种用量，BUG-62）；`namespace` 只允许字母数字`_`-`-`，非法值显式拒绝（BUG-64）；**时间戳服务端盖章，调用面无 `now` 参数**（BUG-33 政策）；两池皆不可用 → `ok=false` 显式失败，绝不静默改用别的模型。真源 `src/router`（纯计算零 IO）+ `src/server/model_router_ops.mbt`（IO 层）。白盒锁 `src/router/model_router_wbtest.mbt`(rt_1~15，含 rt_14 越界游标点名、rt_15 池内环形扫描) / `router_state_wbtest.mbt`(rs_1~6，rs_6 补 rs_3 的假绿) / `src/server/model_router_ops_wbtest.mbt`(mo_1~9，mo_6/mo_8/mo_9 钉查询零副作用、mo_7 钉 ns 校验) / `src/server/server_r3_wbtest.mbt`(BUG-63 config_json 对象形态) / `src/server/issue_scan_wbtest.mbt`(BUG-72 字面量/注释降噪成对锁) |
| `model_router_status` | 只读查当前路由状态：每模型 `used/limit/usage_pct/share_pct/over_threshold/exhausted` + 当前档位 + 切换次数 + 状态文件路径与 `exists`。不改配额、不落盘 |
| `model_router_reset` | 清窗口：所有模型 `used`/`window_start` 归零（等价"这 5 小时重新开始"），档位与游标保持；`hard=true` 连档位/游标/切换计数一起复位 |
| `executor_run` | 把任务真交给外部编码执行器（宿主命令能力，**默认收紧**）：`executor` 只接受登记表 `aider \| atomcode`，argv 形状固定在 `src/executor/cli_argv.mbt`（不经 shell ⇒ 提示词里的 `;` `$()` 反引号都只是**一个** argv 元素），可执行文件名由登记表推导 ⇒ 调用方无法注入任意命令。`model` 留空则先向路由器要一个模型并记账（路由↔执行器接线点）；`dry_run=true`（新增可选参数）只回显 argv、**一个进程都不起**；native 构建返回明确拒绝。密钥只来自 server 进程环境变量，本仓库不读 `.env`、不回显 key。参数：`project_dir`(必填)、`executor`(必填)、`prompt`(必填非空且不含 NUL)、`model`(可选)、`namespace`(可选)、`timeout_ms`(可选默认 180000)、`dry_run`(可选默认 false) |

Resources: `fist://map`, `fist://principles`, `fist://overview`
### 一源四态 · 插件态（生成投影，非手写）

> **开发规范正文真源 = [`AI-DEVELOPMENT-STANDARD.md`](AI-DEVELOPMENT-STANDARD.md)**（R116）。`project_standards` 工具是它的机器投影，README/AGENTS/skill 只做摘要；三者一致性由 `check_doc_surface.py` J6/J7 拦（缺任一规则 id、版本不符或残留旧口径即红）。目标项目照该文件的 §2 文档集骨架开工。

每个功能的第四种形态是**宿主插件目录**，由 `scripts/gen_plugins.py` 从单一真源投影，顺序固定：
**atomcode → codearts → deepseek-harness → claude**（真源 = `plugins/source/` 正文 + `server.mbt` 工具数 + `moon.mod` 版本 + `memory/bugs.md` 账本 + 根 `.mcp.dev.json` 启动参数——候选按**跟踪面优先**解析，本机连接器在读的那份 `.mcp.json` 已被根锚定 `/.mcp.json` 挡在 ignore 面，不得决定投影正文，BUG-131 + 同日 owner 裁决）。

- 插件目录**禁止手改**：`scripts/check_plugin_sync.py`（cl7）子进程重跑生成器做逐字节 diff，另查四宿主入口齐全、无残留 `{{占位符}}`、manifest 版本==moon.mod、`plugins/claude/.mcp.json` 与根 `.mcp.dev.json` 逐字相等、生成 SKILL.md 的 `tools=` == 实测工具数；实测 <=100 直接 FATAL(2)（判据无法自证绝不报绿）。
- 守卫族（13 个，全在 ci.yml JS 轨）：`check_tools_sync` / `check_test_sync` / `check_badge` / `check_scripts_index` / **`check_plugin_sync`（cl7）** / `check_doc_surface` / **`check_store_tables_wired`（BUG-28：库内每张表要么有写入点、要么在 store 源文件里 `schema-reserved:` 点名预留，两个方向都发红）** / **`check_publish_payload`（BUG-127：`moon publish` 的打包面是「工作树 − .gitignore」而不是 git 跟踪面，且点号文件不进包——未被 ignore 又未跟踪的文件会被公开点名，红面里出现凭据形状另判 P2 事故级；空扫描必自拒）** / **`check_demo_isolation`（BUG-122 起、BUG-124 收全：凡 `Popen` 起 `serve` 的脚本必须把 `FIST_DB_PATH` 交给子进程，否则 README/USAGE 教人的那条裸跑命令就在往仓库根自举台账 `fist-mbt.db` 里塞演示行；豁免项必须锚点成立，扫描面空即自拒；现状面 29 个 spawn 脚本全合规 = 27 个带默认改道针 + 2 个显式子句，另有 1 项豁免且锚点成立）** / **`check_ps_encoding`（BUG-88：.ps1 要么纯 ASCII 要么带 UTF-8 BOM，否则 PS5.1 按 ANSI 读会解析期即炸）** / **`store_isolation_probe`（BUG-90：`FIST_DB_PATH` 必须真的改道——同一 cwd 两格只差这个环境变量，且带合成违例格） / **`check_entry_paths`（BUG-93/101：现状面的命令与产物路径不得指退役入口，`Popen([node, cli.js])` 的 argv 必须带 serve——入口搬家漏掉的另一半；判据从 `cmd/*/moon.pkg` 的 `pkgtype(kind:"executable")` 与 build_release.ps1 反解入口清单，不硬编码） / **`check_release_asset_names`（BUG-103/105/107/109：发布资产名 ↔ 安装器 ↔ moon.mod 三处同源；安装器禁写死默认版本、版本解析为空必须 exit 1——用户跑不带参数的 `irm | iex` 是否在装一个不存在的资产名，CI 看不见这条；R5 再钉「命令名两类 shell 都可见」——Windows 侧除 `.cmd` 外必须有**无扩展名**的 `#!/bin/sh` shim ＋「四件齐否则 exit 1」的门，WSL/Linux 侧必须 `cat` 出无扩展名 shim 并 `chmod +x`（POSIX shell 不解析 PATHEXT ⇒ 只给 `.cmd` 就是「装成功了但 bash 里 `fist` 不存在」）；**R6 再钉「200 不等于拿到文件」**（BUG-107 实测：GitCode 三种 raw 形状匿名 GET 全回 HTTP 200 + HTML 页，GitHub 侧 `main` 取不到、`master` 才是可达线）——文档首选安装线必须指 GitHub master raw，且安装器必须做 HTML 形状检查 + zip 魔数 `PK` 检查；**R7 再钉「装完的自检不许假绿」**（BUG-109，由 `scripts/blackbox/e2e_mirror_install.py` 端到端跑出来的：`$ErrorActionPreference="Stop"` 下原生命令的 stderr 经 `2>&1` 变终止错误，而 node:sqlite 每次启动都打 `ExperimentalWarning` ⇒ 旧自检的 `try{}catch{}` 必吞错、`✅ fist-mbt.js 可执行` 却无条件打印，`& fist version` 的 catch 还把「shim 跑通了」报成「当前会话 PATH 未刷新」；三支子判据＝禁空 catch／原生调用必须「临时降 EAP + `2>$null`」封装／✅ 必须挂在版本回执的 `if ($jsVer)` 分支上；`--selftest` 十四格 R1×2/R2/R3×2/R4/R5×2/R6×3/R7×3；**R8 再钉「发布作业不许顶掉分发」**（BUG-111，release run 1 实测失败且 Release 零资产，而本机快照复跑 JS 三步全绿 ⇒ 根因在 `release.yml` 的 `release` 作业：引用 `needs.meta.outputs.version` 却没把 `meta` 放进自己的 needs，又把**可选的** `build-native-linux` 当一票否决项）——判据打 release.yml：needs 必须含 meta、不得含 native、native-linux 必须带 `continue-on-error: true`；**R9 再钉「工具链 bootstrap 与 CI 同源」**（BUG-112，从匿名 `/actions/runs/<id>/jobs` 的**失败步骤名**反解出来的真最后一格：`build-js` 红在 `Build JS target`、`build-native-linux` 红在 `Build native`、`release` 是 `skipped` ⇒ runner 上根本没有 `moon`——`release.yml` 用 `install/unix`（少 `.sh`）且从不 `echo "$HOME/.moon/bin" >> "$GITHUB_PATH"`，而同仓跑通过的 `ci.yml` 两条都有）——判据只看**去掉 `#` 注释行之后**的代码面（第一版被自家注释里的 "GITHUB_PATH" 喂回针，那格变异不红，`--selftest` 当场抓到）：跑 moon 的 workflow 必须有 moon 进 `GITHUB_PATH`、安装 URL 必须是 `install/unix.sh`；**R10 再钉「文档那条线必须 BOM 安全」**（BUG-113 实测：`irm <GitHub master raw> | iex` 当场报「At line:22 char:22 赋值表达式的左侧无效」——含中文的 .ps1 按 BUG-88 必须带 UTF-8 BOM，而 `irm` 把 BOM 留成首字符 U+FEFF ⇒ `iex` 认不出 `param()` 是首语句；同一个脚本 `-File` 跑却正常 ⇒ 之前所有走 -File 的 e2e 照不出这一格）——安装器文档线与 README 的 Windows 线都必须含 `TrimStart([char]0xFEFF)`（正确形是 `.ToString().TrimStart(…)`，`.Content` 那条路上是 null），README 从此进判据面，常驻入口 `scripts/blackbox/e2e_irm_line.py` 的特点是**命令从 README 反解、不硬编码**。同一 e2e 也是 BUG-108 的镜像入口（安装器 `-BaseUrl` / `install.sh` `FIST_BASE_URL`）的常驻判据——没有公网 Release 时让「真的走下载」这一段可跑；**R11 再钉「源码版本常量不许落后于 moon.mod」**（BUG-114：moon.mod 已经前进之后 `src/server/server.mbt` 的 `project_version` 还停在上一个版本号 ⇒ 公网装出来的全局命令 `fist version` 回旧版，而安装横幅、README、插件态都说新版；文档面守卫只比「文档 ↔ moon.mod」，看不见源码这一格，而 `src/server/fist-mbt_wbtest.mbt` 里那条常驻锁在 master 上**一直红着、没人读**——红着没人读等于没锁）——`let project_version` 与 `cmd/cli` 侧扫到的任何 `const *VERSION*` 必须 == moon.mod：读不到基线即自拒，该可选面不存在时不误红。**调用面另有常驻判据** `scripts/cli_flag_probe.py`（CI 起真产物 `node cli.js <arm>` 看真 rc、读真首行：三档缺一不可——版本旗 rc=0 且首行回显 moon.mod 版本 / 帮助旗 rc=0 且不落「未知子命令」/ 未知参数 rc≠0，即 BUG-106 与 BUG-114 的入口锁；白盒测试钉的是纯函数 `parse_subcmd`，入口被改回字符串 match 它照样全绿）。`--selftest` 的格子清单与 PASS 行的判据范围**一律从实现反解**，不手写计数（本轮顺手拆掉一处幻影：R5 那格因「变异只改注释」被循环跳过，自述里却照写 `R5×2`）；**R12 再钉「下载重试只许对准传输层错误」**（BUG-116 实测：本机走系统代理时 `raw.githubusercontent.com` / `release-assets…` 会瞬时抛"基础连接已经关闭"，而同一时刻 curl 取同一 URL 得 200 + `PK` ⇒ 一失败就换源会把抖动放大成"装不上"；但 404/403/"给的不是 zip" 是确定性结论，重试只是拖慢用户）——两条子判据：必须保留"拿到 HTTP 响应就 break"的闸、重试必须带退避间隔。另外常驻 e2e 的沙箱**每次清场**、探针**点名跑沙箱那一份产物**（不这样，判据会红在"上一轮的旧安装"上，见 BUG-117）；**R13 再钉「文档离线线的资产名版本字面量不许落后于 moon.mod」**（BUG-120，BUG-116 车道的交接缺口：README 的 `-LocalZip …\fist-mbt-js-v0.3.4.zip` 落在 R1（只扫安装器、禁写死默认值）与 J4（只认 `@x.y.z` 式版本声明）**两面守卫之间无人认领** ⇒ 版本一前进，照抄离线/内网线就指向一个不存在的资产）——README 里以数字开头的 `fist-mbt-js-v<版本>.zip` 字面量必须 == `moon.mod`，无基线即自拒；模板形态 `v$VERSION` 不是字面量、不误红（两支自证：漂移必红 + 模板不红，`--selftest` 反解出 `R13×2`）；**R14 再钉「安装器内部两发取数也要有第二条 TLS 栈」**（BUG-125，即 BUG-116 的**内部半**：车道把 `install_onecmd.ps1` 取回来后红在内部那一发——「基础连接已经关闭」+「无法从 moon.mod 解析版本号」，因为 R12 判的是 zip 那一发的**重试纪律**、文档线两臂由 `e2e_irm_line` 判，「内部取数能不能换栈」两版守卫都不看 ⇒ 与 BUG-120 同族的另一道两面缝）——四条子判据：兜底臂 `function Get-UrlTo` 注册在 / 调用点≥2 处（moon.mod 与 zip 各一）/ 「只对没有 HTTP 响应的传输层错误换栈」的闸在（404/403 仍直接换源）/ curl 旗带重试上限且**针必须带次数**（单独 `--retry` 子串会被自家 `--retry-delay` 喂绿，这一手有自证格）；`--selftest` 反解 `R14×5`，承重件 `scripts/blackbox/e2e_transport_stack_fallback.py` 三格实测（A 换栈装通且回执带 `curl-fallback` / B 把 `$script:CurlExe` 置空必拿到**一个真非零整数** rc——`rc is None` 也算判据坏，否则"这一格根本没起跑"会被读成"如预期红" / C 干净安装不误伤；用户 PATH 逐字还原、真产物 sha256 跑前跑后必须相同）（文档面 J1-J10：逐个工具可查 + 分组和==实测 + 自述版本==moon.mod + 反幻影哨兵 + **J4 子判据：注册表发布版本只在 `BACKLOG.md` 一处自述** + **J6 规范正文↔机器投影一致** + **J7 规范性表面禁旧口径** + **J8 模板调用参数==真源 schema** + **J9 工具描述返回契约（必查清单 + 歧义键分工 + 棘轮只许升）** + **J10 判据范围自述==实现（少写=声明滞后、多写=幻影判据）**；`--selftest` 用合成违例证明 J4/J6/J7/J8/J9/J10 能发红（自检正文里没写对照，`SELFTEST OK` 那行就不会报它——那份清单从正文反解，不手写），J9/J10/J4 各配反向对照（干净输入/两面一致不误红），且 ci.yml 的文档面那一步先跑 `--selftest` 再跑全量（BUG-89：本轮之前 ci.yml 里只有 `check_test_sync` 的自检被执行，文档面守卫的自检崩了也报绿），不是装饰）。

- 自述面判据（BUG-104，与上面守卫族里那些 `check_*` 并列的 CI 一步，但它刻意不是 `check_*`——数目会随族增减，写死一个数就是下一颗漂移雷）：`scripts/mcp_tool_tour.py` 的 `surface_probe()` 把 AGENTS.md 自述的 resources / prompts 两面与 `serverInfo.version ↔ moon.mod` **打到调用面双向对表**（少一条 / 多一条 / 读回空文本 / prompt 零消息 / 版本不符 / 验收位为空 ⇒ 巡回退出码非 0；文档反解不出条目 ⇒ 判据自拒不报绿）。为什么它不是 `check_*`：这两面必须真跑 MCP 协议才观测得到，离线脚本只能验文档自述、验不到服务端实回——而 tools 面早已被 `check_tools_sync` 钉住，恰好剩这两面没人认领（J10 型缺口）。CI 跑的是它的 `--surface-selftest`（12 支对照：10 违例必红 + 干净必绿 + 无声明行必自拒，桩 server 不起 node、不碰库）；真协议巡回要 node + 产物，用法与两面记账口径见 `scripts/README.md` 同名条目。

Prompts: `fist:check_in`, `fist:verify`

> **术语注记（2026-09-26 立，防误读）**：本仓日志/账本里出现的 `pentad-r1/r2/r3` 是
> **FIST-Mbt 自身「四模式流水线自我迭代」的轮次标签**（ns 名与 `reported_by` 署名已入库，不改写历史），
> 与衍生项目 **Pentad**（`scripts/pentad_fist.py`、模板里「Pentad 无人值守流水线」正文）不是一回事：
> 那些地方 Pentad 是被 FIST-Mbt 驱动的**另一个项目**。写文档/报告标题一律用「四模式流水线自我迭代 · Round N」，
> 不要把 Pentad 当本仓特性名（本轮已把 4 份报告与三处文档计数口径改回本仓术语）。

> **实证伴生仓（fist-evidence，2026-09-27 公开）**：本系统的受控实验证据链在独立仓库
> https://github.com/vicTop-cw/fist-evidence —— 三组实验（`selfdrive-ab-20260926` 编排 vs 裸跑 /
> `atgc-merge-20260926` 三方合并裁决含归因自我修正 / `core-split-ladder-20260927` 核心拆解最小内核 +
> 裸跑幻觉实锤）+ 十份真实项目驱动实例总表，原始报告/日志/裁判测试一字可回溯。
> 本仓「证据梯至少 L4（实测才算数）」的对外展示面即该仓库；引用实验结论时以 `stories/evidence/` 原件为准。

## 路径约定

| 项 | 值 |
|---|---|
| FIST 根 | `<FIST-项目根目录>` |
| FIST SKILL 全文 | `<FIST-项目根目录>/FIST-SKILL.md` |
| FIST-Mbt 根 | `<FIST-Mbt-项目根目录>` |
*（内容由AI生成，仅供参考）*
