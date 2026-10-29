# AGENTS.md · MCP 工具清单（从 AGENTS.md 搬出，内容逐字保留）

> **R212**：这份清单原先在 `AGENTS.md` 里，但 `AGENTS.md` 超过 harness 的指令预算
> （注入上限 65,244 字节），**后段对 agent 不可见**。清单是**参考材料**、不是规则，
> 故搬到此处逐字保留；规则类内容（提交纪律 / 判例 / 路径约定 / 一源四态）仍在 `AGENTS.md`，
> 并已前置到可见区。判据：`python scripts/check_instruction_budget.py`。

## MCP Server

本项目通过 `.mcp.json` 暴露 `fist-mbt` MCP Server（**140+ 个 MCP 工具** + 3 resources + 2 prompts）：

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

### 运维 · 日志 / 缺陷 / 成本 / 调度（27）
| 工具 | 说明 |
|---|---|
| `call_log` | 调用日志查询（时间戳/seq/项目分组） |
| `bug_list` | 缺陷/ BUG 列表（每行带回 `linked_task_status`，`open_with_linked_done` 一次看见「账本说没修、任务库说修完了」的矛盾） |
| `bug_fix` | 批量标 FIXED：**同一笔**改抬头 + 落一条点名整批的 `### FIXED(<盖章时间> / BUG-a, BUG-b)` 小记（evidence 必填非空；幂等重跑；终态之间不互跳）。为什么不给"只改抬头"的路：记账规则把两者做成互锁硬门，分两次调用中间态就是 gen_plugins 拒绝产出的红账本 |
| `bug_mark_status` | 改判单条抬头状态（OPEN/DUPLICATE/FALSE_POSITIVE；**FIXED 一律拒**，走 `bug_fix`）。DUPLICATE 必须带 `dup_of` 且主编号合法（禁自指/禁链）；FALSE_POSITIVE 可选 `evidence` 追加一行立据。返回含 `from_status`/`changed`（同状态幂等 no-op） |
| `report_bug` | 上报缺陷 |
| `issue_scan` | 规则驱动源码扫描（打磨收尾引入）：递归收集目录下 .mbt 文件，内建 11 条 + ocr-local 外部 20 条 = **31 条** MoonBit 高危规则逐行匹配（内建：除零/空数组下标/无保护 unwrap/unsafe_get/无保护整除/substring 越界/ignore 丢错/字符串下标/潜在溢出/空集合单例/secs 溢出；外部：result-discard/map-set-no-rebind/noop-assignment/插值转义/match 非穷尽/数组下标/unsafe_unwrap/async_main/敏感字段泄漏/路径穿越/JSON 注入/浮点相等/竞态/资源泄漏/大数溢出/abort 死代码/空 match/长函数/共享可变），产出 findings（rule/severity/file/line/code）+ by_severity/by_rule 聚合；命中可直接喂 `report_bug` 形成"扫描→上报→修复"闭环——免外部二进制、无绝对路径硬编码，MCP/CLI/skill 三态复用并随插件态分发四宿主；`rules_file` 可传外部规则 JSON（同名覆盖内建），`include_tests`（默认 false）只扫产品代码跳过 `_test/_wbtest` 以降噪；配套 `ocr_scan` 做 OCR LLM review 双轨互补 |
| `boundary_probe` | 边界输入建议生成器（档4，bugfind 寻虫第四步前置）：给定 finding（rule/code/line/file），按规则类型路由返回该位置的边界输入建议数组（空/极值/负下标/并发交错/元字符注入/路径穿越等），每条带 `confirmed=false`——调用方把 `input` 喂给 `run_check`，能触发 panic/崩溃才回写 `confirmed=true`。**纯计算不 spawn 不跑测试**，与 `issue_scan`/`ocr_scan` 形成「扫描 → 边界构造 → 真实验证」三段闭环，治弱语料下的 Goodhart 下界（atgc-merge 归因报告机理 1/2）。真源 `src/server/boundary_probe.mbt` + 15 条白盒锁 `src/server/boundary_probe_wbtest.mbt` |
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
| `text_diff` | 文本 diff（LCS 最长公共子序列）：按行对比 old/new 两段文本，返回操作序列（equal/insert/delete）。用于报告对比、测试输出 diff、AI 交付物变更审查等场景。纯计算零副作用。参数：old(必填，旧文本)、new(必填，新文本)、format(可选，unified|json|stats，默认 unified)。unified=类 git diff 格式（ +/- 前缀）；json=结构化数组 [{kind,text}]；stats={equal,insert,delete} 计数。真源 `src/diff/diff.mbt`，18 条白盒测试在 `src/diff/diff_test.mbt`。 |
| `laya_decide` | Laya 决策（冷启动选档/功能路由 + 确定性回退）：有 Laya→sidecar 决定难度/拆分数/机制选择；无 Laya→降级到内建规则式决策分支（laya_route 纯计算：按任务描述关键词对机制族打分选 feature_route + 复杂度启发式给 split_n）。研发方向「功能太多难决策 / 复杂多任务不知用哪些功能」的落点 |
| `rank_of` | 军衔体系展示层（§8.1 完整 *长 总表）：由任务层级 L 得展示军衔——L=0 司令 / L=1 军长 / L=2 师长 / L=3 旅长 / L=4 团长 / L=5 营长 / L=6 连长 / L=7 排长；越界回退士兵；叶子恒为士兵。**协议层不感知军衔**：除统帅/士兵/政委外，所有 *长 在协议层一律映射为 Leader 角色，军衔只是展示层标签，协议与存储零改动。**默认连长级**：任务 `level` 默认 6（连长），上游可显式声明 `x级`（0..7）；子任务 `level = 父级 + 1` 封顶 7（连长→排长→士兵）。`level` 与 `depth` 严格分离（depth 仍是树深/缩进/`is_leaf` 判据，不是军衔来源）；`rank_of(L)` 映射表不变。**旧库迁移**：全仓首次引入幂等 `ensure_level_column`（`PRAGMA table_info` 探测 + `ALTER TABLE ADD COLUMN level INTEGER NOT NULL DEFAULT 6`），旧库自动回填 6。参数：level(必填，任务层级 L，0..7)、role(可选，协议角色 HumanSteward/Reminder/Executor/Leader，缺省按 level 定级)、leaf(可选，true 时强制士兵)。返回 {level, role, rank, rank_index, is_officer, officer_levels, table}。真源 `src/display/rank.mbt`，9 条测试在 `src/display/rank_test.mbt` |
| `soldier_type_of` | 士兵分类展示层（§8.2 兵种 × 模型档位 × 攻坚任务类型）：把任务关键词映射到 8 兵种之一——侦查兵（情报/调研/搜索）、炮兵（重构/算法/攻坚）、特种兵（高价值/紧急/架构）、医疗兵（修复/故障/抢救）、通信兵（消息/汇报/提醒）、后勤兵（整理/分配/归档）、工兵（环境/依赖/脚本，默认）、骑兵（短平快/高频/批量）。**展示层，非协议枚举**：协议层仍只有 Executor 一个角色，兵种只是展示标签，协议与存储零改动。参数：keywords(可选，任务描述关键词，逗号/空格分隔，缺省工兵)、soldier(可选，直接指定兵种名，非空时跳过关键词匹配)。返回 {soldier, pool_label, mission, model_tier, count, types}。真源 `src/display/soldier.mbt`，9 条测试在 `src/display/soldier_test.mbt` |
| `soldier_route` | 兵种 → 路由联动（§8.3）：把任务关键词映射到 8 兵种并给出**模型池档位提示**与理由——特种兵/炮兵 → paid 池（重任务/高价值），侦查兵/骑兵/通信兵 → free 池（轻任务/便宜快速），工兵/医疗兵/后勤兵 → free 池（通用/中端）。`tier_hint` 可直接作为 `model_route(soldier=…)`/`(pool_label=…)` 的软性提示输入；配额硬约束仍强制，提示档位无容量自动回落正常逻辑。**展示层，非协议枚举**，协议与存储零改动。参数：keywords(可选，缺省工兵)、soldier(可选，非空时跳过关键词匹配)。返回 {soldier, pool_label, tier_hint, reason, mission, model_tier, count, types}。真源 `src/router/model_router.mbt`(pool_label_tier_hint / soldier_label_reason) + `src/display/soldier.mbt`；白盒锁 `src/router/soldier_route_wbtest.mbt`(sr_1~7) |
| `staff_label_of` | 参谋线展示层（§8.1 参谋线：非 *长，参谋军职，挂靠 Leader 体系）：把协议角色名/关键词映射到 6 参谋军职——侦察参谋（Searcher 情报搜集）、后勤参谋（Allocator 资源分配）、验收宪兵（Verifier 交付验收）、监察参谋（Observer 状态监察）、训练教官（SpecAuthor 规范编写）、军务文书（Recorder 记录归档，默认）。**参谋军职不是协议角色**，只是展示层标签；协议与存储零改动。参数：role(可选，协议角色名或自由文本关键词，缺省军务文书)、title(可选，直接指定参谋军职名，非空时跳过关键词匹配)。返回 {title, duty, hierarchy, count, titles}。真源 `src/display/staff.mbt`，6 条测试在 `src/display/staff_test.mbt` |
| `loop_create` | 创建组合环（Phase 6）：preset=full-iterate/fix-iterate/build-verify 或自定义 steps，注册到进程内 LoopRegistry |
| `loop_tick` | 推进一环（Phase 6）：取当前 steps[idx] → 返回 next_mode / next_round / should_stop / stop_reason |
| `loop_status` | 查询组合环状态（Phase 6）：name 空=列出所有已注册环，name 指定=单环完整 JSON |
| `mcp_config_scaffold` | MCP 配置脚手架（cl1）：把目标项目 `project_dir` + `form_json` 平铺字段（serverName/command/args/cwd/toolCallTimeoutMs/failOnStartupError/reconnect/env）交服务端校验（含 `mcp_env_whitelist` 凭据硬门）后返回**可落盘的 `fist.mcp.json` 正文**；不代写目标项目文件，落盘由 agent/安装器做。纯计算只读 + 返回 JSON，白盒锁 `src/server/mcp_config_scaffold_wbtest.mbt`。 |

### 衍生子项目 · ATGC-old（3）
| 工具 | 说明 |
|---|---|
| `atgc_old_compile` | ATGC-old 编译（DNA↔程序） |
| `atgc_old_run` | ATGC-old 运行（DNA 程序执行） |
| `atgc_old_talk` | ATGC-old 会话（叙事/模式切换） |

### 项目看板 / 脉冲 / 预订 / 推荐 + DAG（28）

> worktree 三件工具的真源是 `src/server/wt_tools.mbt`：**存在性 ≠ 生命周期**。它们补的是**账**，状态由「目录 / git / 时间」三方读数裁决；七档与 `scripts/run_light_wt.py` 的 `classify` 同名同义（一源四态）。判定顺序承重：**脏先看**（已并入 + 有未提交改动 ⇒ `blocked`，先判 merged 会把没落盘的活一起销毁）、`idle` 只认账上的创建锚点（ff 合并后主线尖 == 分支尖，靠 git/年龄都会误判）、**git 读不到 ⇒ `unknown`**（绝不顺着年龄写成 fresh/stale）。
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
| `state_flow_ascii` | 状态流转 ASCII：把 Task 生命周期画成一行合法迁移图（待领取→已领取→执行中→待验收→已完成→已归档，含已暂停重派/已打回重试分支）+ 当前各状态计数 + 在流任务数；与 board_ascii/dag_ascii/status_summary 互补（namespace 可选） |
| `status_summary` | 项目脉冲：{version, total_tasks, by_status, by_difficulty(待领取难度结构 易/中/难/无), active_namespaces}，可接 namespace 过滤；by_difficulty 复用难度单一抽取来源（支柱②） |
| `project_health` | 项目健康卡（R68）：单次调用看全项目健康——聚合 in_flight(执行中+已领取+拆分中)/ready(待领取)/done(已完成)/blocked(已暂停+已打回)/reviewing(待验收)/archived 计数 + 健康等级(empty/attention/stalled/healthy) + blocked_tasks;可接 namespace 过滤（支柱①"一眼看全项目"） |
| `health_check` | 四金信号健康巡检（R102，Google SRE Book 2016「Monitoring Distributed Systems」蒸馏）：project_health 从"一个等级"升级为"四个信号"——latency（最近已完成任务完成周期 created_at→updated_at 秒，p50/p90 百分位，<3 条 insufficient，SRE 用百分位不用均值）/ traffic（活跃需求 in_flight+ready）/ errors（失败率 已打回+已暂停/总数 >0.3 attention）/ saturation（积压率 待领取/总数——SRE 先行指标：系统先积压后坏，>0.5 attention 预警）；grade=最差信号（healthy/attention/idle）；纯计算只读不写库 |
| `reserve_scope` / `reserve_check` / `reserve_release` | 作用域预订（拿来主义：Interlinked 文件预订 → 多 agent 并发编辑冲突预防） |
| `lock_acquire` / `lock_renew` / `lock_release` / `lock_status` | 分布式文件锁系统（作用域锁的持久化版，支持 TTL、续租、违例接管与状态查询；多 agent 跨进程并发编辑冲突预防） |
| `task_triage` | 下一步推荐：可领取任务按 能力匹配(want)→**skill 命中度(skill 非空时)**→优先级→重要度→深度 排行 + suggestion（agent 无需全量扫描即知下一单；want 为能力路由，Marketplookup 雏形）。每条含真实 DAG 依赖 `depends_on`（复用 dag_depend/gradient_dag 建边，"下一单"就绪前驱可见）。`skill` 可选（逗号分隔 skill 关键词，R§5.2-4）：非空时按 skill 命中度排在能力匹配之后、优先级之前，并在 suggestion 给 `skill`（命中关键词）与 `mode`（SKILL→MODE 建议的开发模式，如 `tdd`→`fix_and_merge`）；空串=不做 skill 路由零回归 |
| `wt_create` | 开沙箱 + 落一条**生命周期账**（`<project>/.fist-mbt/data/wt-<task>.json`，`created_sha` 存沙箱自己的 HEAD——base 默认 HEAD 是活参照、事后会漂）。参数：project_dir、path、branch（缺省 `wt/<task>`，与 detach 互斥）、detach、task、base、ttl_min(默认 120)、timeout_ms |
| `wt_destroy` | 三道安全：①只动**账上登记过**的路径（否则必须 `force=true`）；②分支默认不删（显式 `delete_branch=true` 才走 `git branch -d`，未并入由 git 自己拒）；③拆失败**不删账**（账留着 = 还看得见） |
| `wt_status` | 列 worktree，并给每个**登记过**的沙箱判七档 `fresh/stale/blocked/merged/idle/abandoned/unknown` + `tally` + `unregistered`（目录在但无账）；保留 `worktrees_raw` 兼容旧调用方。可回收档 = merged/stale/abandoned/idle（blocked 会丢活、unknown 会丢证据） |
| `commissar_send` | **BUG-477**：政委消息**只发送**。把一条政委信号（R1-R4 载荷）经 rhop 写入 `<project_dir>/.commissar/events/`，供接收侧**同步读取**。⚠️ **本工具只发送，当前版本不提供 watch / 订阅能力** —— 底层 `from_filesystem_with` 在 js 后端不可取消（`fs.watch(persistent:true)` 的 handle 在 `Subscription::dispose()` 后仍不释放，见 **BUG-480**），**订阅会让 server 进程永不退出** ⇒ 接收侧请同步读取（`.rhop` → `RhopEnvelope::decode` → `decrypt` → `RhopPacket::from_json_text`）。本项目**不注册** `commissar_watch`。参数：project_dir / kind / target / text（必填）、namespace（可选）。真源 `src/ops/ops_commissar.mbt`（275 行，10 处 `println` 已改 `eprintln`）+ 白盒锁 `src/ops/ops_commissar_wbtest.mbt`（3 格，含变异对照） |
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

### 审计与权限（6）
| 工具 | 说明 |
|---|---|
| `agent_acl_grant` | 授予/收权某 agent 在某命名空间的读写权限（**BUG-408 收口**）：ACL 拒绝后此前无任何 MCP 面可自救——`agents_acl_grant` 只是 store 方法、未暴露为工具。本工具补上这条自救路径。仅 SQLite 后端可用（内存后端显式报错，不静默成功）；`can_read`/`can_write` 缺省即授权读写（fail-open 仅限显式调用本工具，默认 ACL 仍是 fail-closed）；`pid_bound=true` 绑定当前进程实例，换进程即失效。真源 `src/server/server.mbt` + `src/engine/engine.mbt:462` + `src/store/store_sqlite.mbt:2994` |
| `agent_register_key` | **BUG-430 / S3**：为某 agent 登记 Ed25519 **公钥**（hex，64 字符 = 32 字节），登记后该 agent 才能通过 `challenge` 挑战认证（`reserve_scope` / `lock_acquire` / `claim` 的 `challenge` + `challenge_sig` 可选参数）。⚠️ **只登记公钥，不产生签名** —— 私钥由调用方自持；本服务**没有也不会有**「代签」能力（服务端代签 = 自己给自己发通行证 = 绕过 S3）。⚠️ 公钥**登记后不可静默覆盖**（与上次不同即拒绝）—— 要换请走**轮换**：带 `rotate_sig`（用**旧私钥**对服务端签发的 `rotate_challenge` 签名）+ `rotate_challenge`；私钥已丢则用 `agent_revoke_key` 吊销后重新走首登流程。（S3 第八段已实现；store 层能力是 `agents_set_pubkey`。）落库前校验 32 字节形状，坏公钥不进库；写后回读确认。参数：agent_id、namespace、pubkey_hex(均必填)、by(可选)。真源 `src/server/server.mbt`（`agent_register_key`）+ 复用 `agent_touch_first_seen` 的首拍注册路径。白盒锁 `src/server/server_bug430_s3_keytool_wbtest.mbt`(4 格，含「服务端永不代签」) + `src/engine/engine_bug430_s3_key_wbtest.mbt`(4 格端到端) |
| `agent_revoke_key` | **BUG-430 / S3 第八段 · 密钥吊销**：清空某 agent 已登记的公钥，使其退回「无密钥」状态。**私钥丢了的唯一出路** —— 没有吊销面 = 抢注成功后正主永久锁死。⚠️ 本工具**只清除「有密钥」这件事**，不把身份交给任何人：吊销后重新登记走**首登流程**（带挑战验签）。⚠️ **身份仍是自报的（BUG-430 未关闭）**：本工具不校验调用方是谁 ⇒ 任何能调到它的人都能吊销任何人 ⇒ 它是**运维便利**（私钥丢失、agent 退役），**不是安全措施**。参数：agent_id、namespace(可选)、by(可选，仅记入回执)。返回 `{agent_id, namespace, mode, revoked, had_key, ...}`。真源 `src/server/server.mbt`（`agent_revoke_key`）+ 白盒锁 `src/server/server_bug430_s3_revoke_wbtest.mbt`(4 格) |
| `agent_issue_challenge` | **BUG-466 · S3 取票窗口**：为一个**已登记公钥**的 agent 签发 Ed25519 挑战 nonce（服务端单向递增计数器签发、一次性）。拿到后用自己的**私钥**签名，把 `challenge` + `challenge_sig` 传给 `claim` / `reserve_scope` / `lock_acquire`，回执 `action` 才会出现 `+challenge_verified`（此时 `role_source` 才是真的认证过的身份）。⚠️ **只为已登记公钥的 agent 签发** —— 没有公钥的人签了也验不过（`judged_role_gated` 对 `(None,_)` 恒 false），所以直接拒绝并提示先 `agent_register_key`。⚠️ **不写业务库**，只签发并登记为「待消费」；每个 nonce **只能用一次**（重放判 `challenge_replayed`）。⚠️ **公钥按 ns 隔离** —— 在哪个 ns 登记就在哪个 ns 签发/验签，跨 ns 不互通。⚠️ 本服务**没有也不会有**「代签」能力。参数：agent_id、namespace(可选)。返回 `{agent_id, namespace, challenge, issued_at, expires_hint, pubkey_registered, pubkey_prefix, how_to_continue}`。真源 `src/server/server.mbt`（`agent_issue_challenge`）+ 白盒锁 `src/engine/engine_bug466_challenge_entry_wbtest.mbt`(6 格，含变异对照) |
| `audit_permission` | 角色权限查询（**注意**：只反映角色矩阵、不反映 ns ACL——两道独立门，见 BUG-408） |
| `audit_log` | 追加式审计日志 |

### 多租户命名空间（3）
| 工具 | 说明 |
|---|---|
| `store_open` | 打开命名空间（`data_dir` 缺省落 `<target>/.fist-mbt/data/`，不落 server cwd 根；`scratch=true` 落 temp/ 临时区，不污染仓库根）。真源 `src/server/write_gate.mbt` + `src/server/memory.mbt` |
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

### 模型路由 · 外部执行器（5，合并自兄弟项目 fist-model-router 与 FIST 的 aider/atomcode 执行器）
| 工具 | 说明 |
|---|---|
| `model_auth_status` | 只读查模型路由的认证/Star 门状态（**零副作用**：不改配额、不落盘、不推进轮询游标、不 pick）：`gate` 三态（`gate_enabled`/`free_pool_unlocked`/`verdict`）+ `pinned_key_configured`/`attestation_present`/`user_login_configured`（env **只回显"配没配"，绝不回显密钥本体**）+ `ttl_seconds`/`attestation_age_seconds` + `pools`（复用 `model_router_status` 的返回 JSON 原样嵌入，它 Err 时 `pools={"error":…}` 但整体仍 `ok=true`）。默认未配置 Star 门 → `gate_enabled=false`/`free_pool_unlocked=true` 零回归。参数：`project_dir`(必填)、`namespace`(可选默认 default)。真源 `src/router/star_gate.mbt` + `src/server/model_router_ops.mbt`。白盒锁 `src/server/model_router_ops_wbtest.mbt`(ma_1~4，含默认零回归/fail-closed/坏 attestation 不崩溃/零副作用四锁) |
| `model_route` | 模型配额路由决策（免费优先 + 达 `threshold_pct`(默认95%) 自动切付费 + 付费耗尽回退免费 + 每模型独立 5h 滚动窗口）。参数：`project_dir`(必填，相对、拒绝对称/盘符/`..`)、`namespace`(可选默认 default，**每个 ns 一份独立配额账**)、`record_model`(可选：给名则 `used+1` 后再决策，留空=只问不消耗)、`config_json`(可选：RouterConfig JSON 文本覆盖池定义，同名模型已用配额保留；**非法 JSON 直接报错不静默回落**)。状态落盘 `{project_dir}/memory/model-router-{ns}.json` 跨进程复现；**只问不消耗＝零副作用**（不记账/不推进游标/`persisted=false`；给了 config_json 池定义时只播种定义不播种用量，BUG-62）；`namespace` 只允许字母数字`_`-`-`，非法值显式拒绝（BUG-64）；**时间戳服务端盖章，调用面无 `now` 参数**（BUG-33 政策）；两池皆不可用 → `ok=false` 显式失败，绝不静默改用别的模型。**Star 门（D1=A 完整接入）**：默认未配置即不设门（`star_gate.gate_enabled=false`，零回归）；要启用设 server 进程环境变量 `FIST_STAR_GATE_PUBKEY_HEX`（钉死 Ed25519 公钥 hex）/`FIST_STAR_GATE_ATTESTATION_JSON`（GitHub Pages 拉到的 attestation 正文）/`FIST_STAR_GATE_USER_LOGIN`（授权名单内 login）；启用未验签通过 → `ok=false` + `star_gate.free_pool_unlocked=false`（fail-closed，不 pick/不记账）。回执恒带 `star_gate` 字段。真源 `src/router`（纯计算零 IO，含 `star_gate_policy` 三态判定）+ `src/server/model_router_ops.mbt`（IO 层只做 env 读取 + 短路）。白盒锁 `src/router/model_router_wbtest.mbt`(rt_1~15，含 rt_14 越界游标点名、rt_15 池内环形扫描) / `router_state_wbtest.mbt`(rs_1~6，rs_6 补 rs_3 的假绿) / `src/router/star_gate_wbtest.mbt`(星门 9 锁，含 pinned 四锁 + `star_gate_policy` 三态五锁) / `src/server/model_router_ops_wbtest.mbt`(mo_1~10，mo_6/mo_8/mo_9 钉查询零副作用、mo_7 钉 ns 校验、mo_10 钉 Star 门默认未启用零回归) / `src/server/server_r3_wbtest.mbt`(BUG-63 config_json 对象形态) / `src/server/issue_scan_wbtest.mbt`(BUG-72 字面量/注释降噪成对锁) |
| `model_router_status` | 只读查当前路由状态：每模型 `used/limit/usage_pct/share_pct/over_threshold/exhausted` + 当前档位 + 切换次数 + 状态文件路径与 `exists`。不改配额、不落盘 |
| `model_router_reset` | 清窗口：所有模型 `used`/`window_start` 归零（等价"这 5 小时重新开始"），档位与游标保持；`hard=true` 连档位/游标/切换计数一起复位 |
| `executor_run` | 把任务真交给外部执行器（宿主命令能力，**默认收紧**）：`executor` 只接受登记表 `aider \| atomcode \| ofm`。aider/atomcode 走本地 CLI spawn，argv 形状固定在 `src/executor/cli_argv.mbt`（不经 shell ⇒ 提示词里的 `;` `$()` 反引号都只是**一个** argv 元素），可执行文件名由登记表推导 ⇒ 调用方无法注入任意命令；**`ofm` 走并存 HTTP 通道**（`executor_run_impl` 按 `executor` 分流，不经 `build_command`）：真 POST `{ofm_endpoint}/chat/completions`，端点 env `FIST_OFM_ENDPOINT` 优先、`config.ofm_endpoint` 兜底，`Authorization: Bearer` 的 key 只在 server 进程环境变量里读、**回执绝不回显**，失败按 `classify_ofm_failure` 归因（网络/401/5xx/其他，回执 `failure_kind`）。`model` 留空则先向路由器要一个模型并记账（路由↔执行器接线点）；`dry_run=true`（新增可选参数）只回显 argv（CLI）或将发送的请求体+URL（ofm）、**一个进程/一个网络请求都不起**；native 构建返回明确拒绝。密钥只来自 server 进程环境变量，本仓库不读 `.env`、不回显 key。参数：`project_dir`(必填)、`executor`(必填)、`prompt`(必填非空且不含 NUL)、`model`(可选)、`namespace`(可选)、`timeout_ms`(可选默认 180000)、`dry_run`(可选默认 false) |

### 六顶帽 · 辩论裁决（4，R118 P1-b，`src/ops/ops_hats.mbt` 真源）
| 工具 | 说明 |
|---|---|
| `hat_list` | 列出六顶思考帽（White/Red/Black/Yellow/Green/Blue）的 role/color/forbid/output_keys 与默认三帽（White/Black/Yellow）。纯计算只读 |
| `debate_convene` | 发起一次六顶帽辩论（in-memory 会话）：`topic`(必填)、`hats`(可选，缺省 white,black,yellow)、`threshold`(可选，缺省 0.6)；返回 `session_id`（`debate-<yyyyMMdd>-<nnn>`）+ 已注册帽子。会话态进程内保存、重启即失（诚实标注） |
| `debate_register` | 给指定 session 注册一条帽子判决：`session_id`/`hat_id`/`verdict`(pass/reject/abstain)/`evidence`(必填非空，`valid_verdict` 拒绝空值)；返回该 session 已注册判决列表 + 当前 rate/pass |
| `debate_verdict` | 对指定 session 做收敛判决：`rate` = 帽子中 agree 的比例（agree = verdict 为 pass 的帽子数），`pass = rate >= threshold`（缺省 0.6）。**终态门是用户**——本工具只给收敛读数，不自动判定议题通过/否决。返回 summary（含 `terminal_gate=user` 与 `anti_drift` 清单） |
| `hat_run` | 跑一顶帽子：按 hat_id（white/red/black/yellow/green/blue）对该议题产出单帽判决，register 进同一 session。与会话态 debate_convene 配套（in-memory，重启即失） |
| `hat_debate` | 一轮完整六帽辩论：对 `topic` 依序跑所选帽子（缺省三帽）并汇总分歧/一致项；`threshold` 控制收敛。与 debate_convene 的差别是**一步到底**（convene+register 两次调用，本工具一次调用） |
| `hat_merge` | 合并多 session 的帽子判决为裁决视图：按 `session_id` 取多轮判决，给出合并后的 rate/pass 与 anti_drift 清单。供多轮辩论后收敛 |

### 项目助理（5，multi-agent-lock v3 阶段2 精简版，`src/store/store_assistant.mbt` 真源）
| 工具 | 说明 |
|---|---|
| `assistant_claim` | 项目助理选举：无 active 主助理则当选(elected)；本人重复调用则续任(renewed)；主助理心跳陈旧则接管(taken_over，旧主记 `lock_violations` force_takeover)；主助理心跳新鲜则拒绝(conflict)。参数：`agent`(必填)、`heartbeat_ttl_sec`(可选，默认 300)。裁决单一真源 `store.assistant_claim_action` |
| `assistant_status` | 查询助理全景：现任主助理 + 全部登记 + 锁违例统计（纯读不写） |
| `assistant_sweep` | 清扫拍：释放 TTL 过期文件锁（复用 `locks_sweep`）+ 心跳陈旧超 `stale_secs`(默认600) 的助理标 dead |
| `assistant_resign` | 助理主动退位（status=resigned；锁不阻塞，靠 TTL + 清扫拍兜底） |
| `assistant_heartbeat` | 助理心跳：刷新自己的 `heartbeat_at`（未注册者显式报错） |

### 超级管家专属工具（8，`src/server/supervisor_tools.mbt` 真源）
| 工具 | 说明 |
|---|---|
| `supervisor_status` | 全项目/按 ns 的任务全景：by_status / by_ns / active / 进度百分比。超级管家（human_steward 对外入口）查看项目状态的唯一入口 |
| `supervisor_task_tree` | 以 `root_id` 出任务树：节点含 id/状态/描述/子任务完成度 + 聚合 summary。复用 task_plan_deep 的树聚合口径 |
| `supervisor_kill_plan` | 终止**方案**（只出方案不执行）：`task_id`/`by`/`reason` 经六门链（身份/目标存在/不可杀根任务/终态/force+reason/补偿建议）逐门评估，`apply_pause=true` 时执行唯一可逆动作 `pause_task`。真 kill 由指挥官按方案人工执行 |
| `supervisor_prompt_inject` | 向 `target`（agent 或项目）注入引导提示词，落进程内 registry + call_log 双写（跨进程可回读、幂等） |
| `supervisor_prompt_list` | 列出待投递/已消费的引导（`target` 可选过滤，`include_consumed` 可选）。进程内优先、回灌 store recent_call_logs |
| `supervisor_prompt_consume` | 取走一条引导并标记已消费（`guidance_id` 必填）。重复调用不重复返回（幂等） |
| `supervisor_task_upsert` | 更新目标项目任务列表：`items[]` 带 `task_id` 则更新描述/优先级/依赖，无则追加新任务（复用 `engine.publish` 的 human_steward 硬门）。per-item created/updated/failed 逐项回执 |
| `supervisor_reminder_tick` | 提醒者（Reminder）轮询一拍：扫描 plan 目标 vs task_tree 实际的偏离（目标未拆解/节点长期 pending/产出物缺失），产出待投递提醒。跑法见 `docs/2026-10-12-fist-mbt-reminder-role-plan.md` |

### 嵌入式 MCPCf 内部工具（7，`src/server/mcpcf_embed.mbt` 真源，链式 `s.tool` 注册）
| 工具 | 说明 |
|---|---|
| `mcpcf.ops_init` | 初始化内嵌 FIST 引擎（SQLite 优先、内存兜底），data_dir 可选（覆盖默认数据目录）；返回 backend 与库路径 |
| `mcpcf.circuit` | 内嵌熔断器状态机查询/推进（closed/open/half-open 三态 + 恢复定时），与 `circuit_status` 同族但面向 mcpcf 内嵌运行时 |
| `mcpcf.report` | 内嵌运行报告：按 ns 汇总任务/调用/门禁读数，输出机器可读 JSON |
| `mcpcf.review` | 内嵌验收视图：列待验收任务及其交付物与门禁结果 |
| `mcpcf.run_batch` | 内嵌批量执行：按给定的任务批次串行推进 claim→execute→submit，遇门禁失败即停并回执已推进到哪一条 |
| `mcpcf.verify` | 内嵌验收：对指定 task 跑 verify 同款校验（语料门禁/成果复验），verdict 直接回执 |
| `mcpcf.watchdog` | 内嵌看门狗一拍：scan 超时任务 + 自动续轮，与 `watchdog_tick` 同口径但走内嵌引擎 |

Resources: `fist://map`, `fist://principles`, `fist://overview`
