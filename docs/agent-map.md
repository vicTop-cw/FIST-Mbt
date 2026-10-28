# FIST-Mbt Agent 项目地图（Repo Map）

> 目的：让任何一个首次进入本仓库的 AI agent **先读地图、再动代码**，不必全项目盲目探索。
> 依据：Agent Patterns Catalog「Repo Map」模式——给 agent 一张紧凑、按重要性排序的结构地图，省 context、少走弯路。

## 一、30 秒定位（对首次进入者）

`FIST-Mbt` 是**纯 MoonBit 实现的 MCP Server**：一个「AI 指挥官」式任务编排器——发布根任务，递归拆解成多层子任务，经认领/执行/提交/验收/归档闭环；含 DGM 自进化档案库（evolve）与 Omega 强验证。全栈 MoonBit，JS+Native 双后端，SQLite 持久化。

- **构建/测试**：`moon check` / `moon test --target js`（**1864 项全绿**，2026-10-28 Windows 实测）
- **跑 MCP Server**：`moon build --target js cmd/cli && python scripts/patch_esm_main.py` → `node _build/js/debug/build/cmd/cli/cli.js`
- **一键自检**：`python scripts/mcp_smoke.py`（实测 177 个工具 + publish/get 链路 + issue_scan 命中校验；这个数由 `check_doc_surface.py` 的 J14 项目地图面钉住，改工具数时这张图必须跟着改）
- **找目标项目潜问题**：`issue_scan`（MCP 工具）/ `python scripts/issue_scan.py <dir>`（CLI）/ [技能文档](issue-scan-skill.md)（skill）三处手写形态 + 插件态投影（四态），规则驱动扫描，命中喂 `report_bug` 闭环
- **多步闭环怎么转**：[组合环编排技能文档](loop-mode-skill.md)——`loop_create`/`loop_tick`/`loop_status` 管「转几轮、何时停」，`mode_list`/`mode_templates` 管「每步做什么」；[看护闭环技能文档](phi-accrual-heal-skill.md)——`phi_accrual` 概率式判活 → `heal` 回滚 → `watchdog_tick` 单入口编排
- **语言**：MoonBit；测试用 `suite`/`test` 而非 `@test def`；guard/match 冒号后换行。

## 二、src/ 各子包职责地图（谁管什么）

| 包 | 职责 | 关键文件 |
|---|---|---|
| `core` | 领域模型：`Task`/`TaskStatus`、七条金条、schema 解析 | `core_task.mbt` |
| `store` | 持久化：Memory/SQLite 双后端、call_log/heartbeats/specs/evolve_artifacts 表 | `store.mbt` `store_sqlite.mbt` |
| `engine` | 业务核心：publish/claim/plan(deep)/execute/submit/verify/archive；DAG；Omega 门禁；docs 门禁 | `engine.mbt` `omega_strong.mbt` `docs_gate.mbt` |
| `evolve` | DGM 自进化档案库：Archive/Artifact/sample_parent/查重/新颖度/谱线 | `evolve.mbt` `scoring.mbt` `self_search.mbt` |
| `omega` | Ω-check：项目结构/回传五段式校验、spec 解析/批量校验 | `check.mbt` |
| `ops` | 运维：心跳/看门狗/google 调度 | `ops_watchdog.mbt` 等 |
| `server` | MCP 层：177 个工具+3 resources+2 prompts 注册、call_log 注入、Laya/evolve MCP 封装、规则驱动源码扫描（issue_scan） | `server.mbt` `laya_js.mbt` `evolve_distill.mbt` `evolve_lesson.mbt` `issue_scan.mbt` |
| `decompose` | 递归拆解规格 | — |
| `executor` | 执行器抽象 + 能力注册表 + 能力路由（Marketplace 雏形，R30/R31）+ store 持久化 | `registry.mbt` `base.mbt` |
| `atgc-old` | 旧 ATGC 叙事子项目（保留全量） | — |
| `atgc` | 极简双链虚拟机（能力演示） | — |

## 三、MCP 工具分组概览（导航简写，不是注册表计数）

> **边界（BUG-123 / BUG-363）**：本表组名与组值是手写的导航简写（省略公共前缀，如`succeed status`），**不等于** `tools/list` 的注册表，也不能与真源做机械差集。逐组的权威清单在 README「功能全景」，由 `check_doc_surface.py` 的 J3 同时钉「分组数字之和 == 真源」与「标题组数 == 实际分组标题数」；这张地图自己只钉**总数主张**那一句（J14 项目地图面）。本表尚未覆盖的分组（GitHub/GitCode 同步、超级管家、六顶帽、项目助理、嵌入式 MCPCf、模型路由·外部执行器、开发模式等）记在 BUG-364，改写本表属内容决策，留裁决。

| 族 | 代表工具（省略公共前缀，如 `dag_*` 的 `*` 段） |
|---|---|
| 生命周期 | publish / plan / claim / execute / submit / verify / reject / retry / pause / resume / reopen_task / archive / delete |
| 查询 | list / get |
| 运维 | task_plan_deep / conflicts_check / heartbeat / heal / watchdog_tick / task_cleanup / phi_accrual / saga_\* / circuit_\* / tx_contract |
| 运维 · 日志 / 缺陷 / 成本 / 调度 | call_log / bug_list / bug_fix / bug_mark_status / report_bug / issue_scan / boundary_probe / eval_feedback / run_check / output_validate / schedule / pipeline_tick / cost_\* / progress_gate / project_standards / text_diff / laya_decide / rank_of / soldier_\* / staff_label_of / loop_\* |
| 自驱闭环 | selfdrive_\*（init / append / get / export_tasks / review_tick / review_ready / publish_next / parse_next_tasks / pick_next / dispatch） |
| 项目看板 / 脉冲 / 预订 / 推荐 + DAG | dag_\*（critical_path / parallelism / ascii / check / ready / sort / depend / publish / slack / schedule / cost_route / mc）/ plan_revise / goal_drift_check / board_ascii / state_flow_ascii / status_summary / project_health / health_check / reserve_\* / lock_\* / task_triage |
| 自我记忆与自进化 | memory_\*（consolidate / gc / link）/ evolve_\*（submit / sample / snapshot / distill / lesson / critic / asset_register）/ task_challenge |
| Marketplace·执行者能力路由 | executor_\*（register / route / auction / clear）/ selfdrive_dispatch |
| 审计与权限 | audit_permission / audit_log |
| 多租户命名空间 | store_open / store_list / store_close |
| Omega 强验证 | omega_\*（spec_create / spec_review / result_verify / status / verify / verify_fix） |
| 开发模式与模板 | mode_list / mode_templates |
| GitHub/GitCode 同步 · 缺陷上报通道 | github_\* / gitcode_\*（env_check / queue_status / flush_plan / flush_execute / queue_mark_sent / issue_close / issue_comment / issue_webhook_parse） |
| 模型路由 · 外部执行器 | model_auth_status / model_route / model_router_status / model_router_reset / executor_run |
| 六顶帽 · 辩论裁决 | hat_list / debate_convene / debate_register / debate_verdict / hat_run / hat_debate / hat_merge |
| 项目助理 | assistant_claim / assistant_status / assistant_sweep / assistant_resign / assistant_heartbeat |
| 超级管家专属工具 | supervisor_status / supervisor_task_tree / supervisor_kill_plan / supervisor_prompt_\* / supervisor_task_upsert / supervisor_reminder_tick |
| 嵌入式 MCPCf | mcpcf.\*（ops_init / circuit / report / review / run_batch / verify / watchdog） |
| 衍生子项目 · ATGC-old | atgc_old_compile / atgc_old_run / atgc_old_talk |

> **本表的承诺只到「族」这一层，不承诺逐工具穷举**（2026-10-24 定点修，BUG-364）：
> 旧表在组名后缀手写计数（12 行带计数、和=100），其中约四成的族根本没列——读者会把"和=100"当成
> "全量"，而真源是 **177 个工具**（本行是唯一允许出现工具数的地方，由 `check_doc_surface.py` J14 钉住）。计数是抄来的、工具是长出来的，两者必然漂；所以本表**去掉所有计数**，
> 只保留族与代表工具，并把"全量"交给单一真源：
> · 全量清单：`python scripts/fist.py list-tools`（= `tools/list` 实测）
> · 工具数与文档/插件/徽章对齐：`python scripts/check_tools_sync.py`（判据守，不靠人抄）
>
> ## 四、入口引导（agent 该怎么走）

1. **想懂业务流** → 读 `README.md`、`ARCHITECTURE.md`、`USAGE.md`。
2. **想改某层逻辑** → 见上表定位到 `src/<包>`，再读该包 `pkg.generated.mbti` 看公开接口。
3. **想加/改 MCP 工具** → `src/server/server.mbt` 用 `.tool(name, desc, schema, handler)`，handler 经 `_instrument` 包装（自动 call_log）。
4. **想动存储** → `src/store/store_sqlite.mbt`（表结构在 `moon.pkg` 初始化处）。
5. **想跑通即走** → `python scripts/mcp_smoke.py` / `scripts/enrich_selfdrive.py`。
6. **提交前想确认守卫面** → `python scripts/run_guards.py`（仓内电池真源，逐格行首是判定列
   `PASS`/`FAIL`，其后才是 rc/期望/口径/结论行，`grep ^FAIL` 直接捞红格；格数从汇总行现读，
   不在这抄数）。预存红按声明的期望值命中、不算失败，但行内仍带 `预存红` 口径标注。**别在 `temp/` 里另写一份电池**：
   历轮 11 份手写电池的格数是 13 → 30 → 37 全靠回忆，漏的那格永远不会被发现漏了（BUG-366）。

## 五、约定与雷区（别踩）

- **测试**：JS 目标已支持；native 需系统 SQLite + VS 环境（见 AGENTS.md）。
- **Node ≥ 24**：JS 目标依赖 `node:sqlite` 的 returnArrays，<24 会导致列读空。
- **时间戳用 Int64**：`@env.now().to_int()` 对 UInt64 做 32 位截断会产生 1969 假时间戳——务必用 `@env.now().reinterpret_as_int64()`（`UInt64::to_int64` 自 BUG-359 起已由 core 弃用，仓内 11 处调用全部改名；写 `.to_int64()` 会给 `moon check` 新增一条 0020 warning）。注意 `to_int64` 是重载名：`Double::to_int64()` / `Int::to_int64()` 是**饱和转换**、未弃用，不要跟着改。
- **勿改共享 fist-mbt.db 测试**：测试用独立内存/SQLite（见 call_log_wbtest）。
- **无硬编码路径**：分隔符跟随输入，路径不硬编码盘符。
- **一把尺不跑就等于一把坏尺**：本仓的守卫只在 CI 有红门，本地提交面是空的（`.githooks/pre-commit` 只跑 `moon check`，而且 `core.hooksPath` 未设置 ⇒ 连这一条都不生效）。新写或改 `scripts/check_*.py` 时，**同时给它一个执行面**（挂 CI 或进 `run_guards.py` 的 `CASES`），否则它会像 `check_plan_landing` 那样带着虚报缺陷躺一周（BUG-365/366）。
- **自述的退出码必须实测**：`raise SystemExit("FATAL …")` 给的是 **1**，不是 2 —— 带字符串的 SystemExit 只打印文本。ast 普查真调用点：3 份尺自述「2=判据无法自证」而代码里一条 2 都给不出（`check_mbti_sync` 7 处串式 FATAL / `check_pkg_imports` 6 处 / `check_template_ctrl` 1 处），另 1 份是**半形**（`simulate_head_commit`：moon 超时走 `return 2` 真给 2，其余 4 处 FATAL 给 1，其中一条文案自己写着「（rc=2）」）⇒ BUG-369。要承诺 rc=2 就写 `SystemExit(2)` 或 `return 2`，并在 `--selftest` 留一格锁「FATAL 那条出口的码真是 2」。
- **数站点要用 ast，不要用正则**：同一份普查，正则版把 docstring 里的 `SystemExit("…")` 字样当调用点（数字虚高到 33），又把 `sys.exit(main())` 这种**正常透传**当「已有整式出口」（家族漏判）——两条缺陷都在同一轮现形。凡是「数代码里的某种形状」的判据，先问一句：读的是站点面还是文本面？
- **修尺会改变站点形状，判定面与让位面之间会搬家**（R43 变异台实测，方向与我预测相反）：把 `raise SystemExit("FATAL …" % r.returncode)` 改成 `raise SystemExit(emit_fatal("FATAL …" % r.returncode))` 之后，站点不再「带字符串」而含 `returncode` ⇒ R1 从判红转成**让位留名**（外部件透传）。所以「判定面少了 N 条」必须回头对一遍 O/S/U 三面：条数搬家不是条数消失。
- **新尺入场会把自己算进宇宙，登记数字必须同一批采样**（R43 现形）：R42 报告写「85 份 .py 里 31 份有 `N=` 契约块（U 面 38）」，真源现读是 **85 份里 32 份、U 面 37**——宇宙数是判据入场后重跑的，契约块与 U 面却是入场前那次采样。写进台账的每一组数字要么一次跑齐，要么标清各自时刻（同 `cleanup_artifacts` 读数那条计时口径）。
- **自测格子里的每个数字要么来自常量、要么来自实测**（R44 现形，方向是它自己咬我）：把 `CONTRACT_GAP_CEILING` 从 8 降到 1 那一步，两条老格子当场变 FAIL —— 一条硬编码「合成 4 条仍在上限内」，另一条硬编码 `hint(3, 上限)` 里必须出现「收紧」而它读到了「FAIL」。判据没错，是**格子在替上一轮的存量说话**：降棘轮的人不该被要求同时记住哪些格子里冻了旧数字。出路是断言全部从常量推导（`at = CONTRACT_GAP_CEILING`，合成量取 `at` 与 `at+1`）并给 `at == 0` 留一条独立分支，反例由 `temp/r44_mutation.py` 的 N3 那一支钉住（按旧写法在 1 的上限下必然红）。
- **判定面的条数不衡量一份坏到什么程度**（R45 变异台实测，方向同样与我预测相反）：`simulate_head_commit` 在 R42 的标定面里只有 **1 条**（R3），把 4 处串式站点全改回去**仍是 1 条**——因为别处那条 `return 2` 顶着 R1、承诺句「2=前置不满足」里没有判据失灵类关键词所以 R2 不响。反过来把那条 `return 2` 一起抽掉，R1 与 R3 **同时**现形变成 2 条。教训两条：① 「半形」不是修辞，是结构，**按条数估工作量会系统性低估**（这份的存量再大也只算一条）；② 一条判据绿可能是被另一处的真 2 顶着，归零面只说「此刻不红」，不说「这里没坏」——所以要问的是「**2 从哪来**」（`fixed-ruler-gives-two-in-impl-face` 那格考的就是实现面），不是「条数小没小」。
- **变异台得先证明「变异发生了」**（R45 现场抓过自己一次）：M 支靠字符串替换合成违例，替换串少写一个空格（`）/ 2=` 前我写成 `" / 2="`）就一个字没改，而**基线本来就是 0 条**的格子在这种情况下必然打印「ok」——那不是判据绿，是我以为我考过了。现在 `check()` 里装了自动闸：变异文本与工作树逐字相同即判 FAIL，不靠人眼对 diff。同律的另一种踩法见「一把尺不跑就等于一把坏尺」：**空转的自测长得和通过的自测一模一样**，能区分两者的只有"变异是否改变输入"这一格。
- **模式互斥不是洁癖**：同一把尺的两种模式若共享一个「按某面标定的上限」，允许它们同时打开就是在未标定的宇宙上比数。实测 `check_plan_landing.py --gate --all-faces` 去掉互斥闸后：同一份存量从 25 跳到 38，门禁反而给 **0** —— 红是假的、绿也是假的，而「绿得莫名」比红更坏。
- **副机推送只认 `gitcode` 这个 remote**：`git remote -v` 实况是 `origin → https://github.com/vicTop-cw/FIST-Mbt.git`（本机 443 不可达，`git push -u origin …` 必挂 rc=128 且**不会**留下 upstream，容易误判成「分支没建对」），`gitcode → git@gitcode.com:VictorTop/FIST-Mbt.git`（可用，但仓库已改名 `Fist-Mbt`，每次 push 都会回一条 "This repository moved" 提示——是提示不是失败）。正确写法 `git push -u gitcode slave/<类>/<单名>`，MR 入口由远端回显给出 `https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=<分支>`；**MR 由 owner 开，副机只交链接**（R45 现场踩过一次 `origin`）。
- **印在同一句里的「总数」与它的分解必须同集合同一次算出**（R46 现读撞到，记 BUG-370）：`gen_plugins.py` 的账本摘要一句里有两个分母——总数按 `## BUG-` 抬头**出现次数**（354），四态计数按**唯一编号**装进 dict（352），差的 2 条是 BUG-183 / BUG-192 被两条不同缺陷串号后被静默去重。它上方的门是 `len(heads) != len(ids)`，只考「抬头能不能解析」，串号时两侧各加 2 ⇒ **门绿着，文案却自相矛盾**。教训两句话：① 去重/合并这类「集合收缩」发生在门之后，就等于没被考过，凡取数用了 dict 的计数都要另数一次原始条数；② 结案、改名、搬家这类「只改一侧」的动作最容易留这种假绿——同轮的另一半证据是变异台 M4：小记里把编号多打一个字符，**门①与门②同时响**（真 FIXED 失去点名 + 不存在的编号被点名），所以互锁门的价值恰恰在于「写错时它响两声」，别把「一条违例」当成「一处坏」。
- **门必须站在「集合收缩」之前，而不是在它旁边补一次数**（R47 把上一条教训落成代码，BUG-370 的判据侧出路）：上一轮说的是"凡用 dict 取数要另数一次原始条数"，这一轮做的是**把校验挪到 `st = {id: …}` 那行之前**——新增门④「抬头编号必须唯一」，串号当场 FATAL(2)。位置为什么是重点：变异 M3b 实测「同样的判据、后置到 dict 之后」⇒ **违例恒为 0**，而四态之和照样少 2，一台"永远绿"的门比没有门更坏，因为它给了读数一个合法的形状。总数也从这里改：`total = sum(counts.values())`，恒等式「总数 == 四态之和」由结构保证，不再依赖"此刻恰好对上"（M4b 那一支就是钉这个的：旧口径配新账本会"恰好对上"，所以它当初没被发现）。
- **编号迁移走「追加一条点名小记」，不走改写旧抬头**（R47 重编号 BUG-183/192 串号时的做法）：账本的叙述面只追加、不改写、不删除（`memory/bugs.md` 文首记账规则），所以给被吞的那条换新号时，2026-10-15 那两条 `### FIXED` 原文**一个字不动**，改由一条新的 `### FIXED(… 编号迁移 / BUG-371, BUG-372)` 小记点名收口，条目正文里加 `- 编号迁移:` 字段写明"先出现者保留原号"。代价要如实记账：旧小记点的号从此指向另一条缺陷（同号两义的历史留下了），这类失配已在账 **BUG-373**（代码注释与测试标题引用的 `BUG-N` 与账本编号零闭环，现读错号/悬空/一号三义三类，本单只立案不修）。为什么本单不顺手修它：改测试标题会动 `moon test` 的快照输出面，必须与快照刷新同批——同一条互锁定律第二次拦住"顺手"。

