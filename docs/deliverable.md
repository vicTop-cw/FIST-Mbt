# FIST-Mbt 参赛交付说明（评审速览）

> 定位：**纯 MoonBit 实现的 MCP Server**——AI 指挥官式任务编排，同时是"更好的 AI 项目管理工具"。
> 一次自检即验证核心链路，其余为逐项证据索引。2026-09-25 状态。

## 一、10 秒自检（评审用这个）
```bash
# ① 构建 + 拉起 MCP server 并自检（需 Node ≥ 24）
moon build --target js cmd/main
python scripts/mcp_smoke.py
# 期望输出：PASS tools/list → 83 个工具 / PASS publish / PASS get → MCP-SMOKE PASS
```

## 二、硬指标（快照）
| 项 | 值 |
|---|---|
| MCP 工具 | **83**（+ 3 resources + 2 prompts） |
| 测试 | **`moon test --target js` 240/240**（Windows + WSL(Linux) 双端实测全绿） |
| 回归 | 0（既有语义不破坏，增强默认关闭零回归） |
| 依赖 | 全公开，`moon update` 即可构建，无私有包/登录/vendor |
| Env | Node ≥ 24；`moon info && moon fmt` 后测试（AGENTS.md / 环境要求） |

## 三、核心能力（评审点）
1. **任务编排闭环**：发布→认领→拆分(plan_deep 递归)→执行→提交→验收→归档；父任务自动上卷。
2. **AI 自驱式**：selfdrive_*（审视→自我派活）；自驱脚本见 `scripts/*_selfdrive.py`。
3. **Omega 强验证**：语料创建→审核→成果复验门禁，不达标记打回、超限升级人工（防死循环）。
4. **DGM 自进化**：档案库 + 多样采样 + 蒸馏 principle + **失败回流 lesson**（见探索性闭环脚本）。
5. **DAG 编排**：显式依赖 `dag_depend`、关键路径/并行度/ASCII 图/topo 排序。
6. **多租户**：命名空间物理隔离（`store_open`，`scratch` 临时区不污染根）。
7. **项目地图**：`fist://map` resource——agent 首读即有，避免全项目乱找（docs/agent-map.md）；`board_ascii` 实时任务看板，一眼看全貌。

## 四、自驱增强证据（git 4994aae → HEAD，47 轮）
| 轮 | 增强 | 验证脚本 |
|---|---|---|
| 1 项目地图 | `fist://map` + docs/agent-map + 调研纪要 | `map_verify.py` |
| 2 失败回流 | `evolve_lesson` | `lesson_verify.py` |
| 3 DAG 显式 | `dag_depend` + to_json 修复 | `dag_depend_verify.py` |
| 4 双端复现 | WSL 199/199 复核 | —（实机） |
| 5 临时隔离 | `store_open(scratch)` | `scratch_verify.py` |
| 6 回流闭环演示 | lesson 归档→dead_ends 可见 | `lesson_chain_selfdrive.py` |
| 7 Omega自动落lesson | auto-lesson + 进程内可见 | `omega_lesson_verify.py` |
| 8 看板 | `board_ascii` 实时任务看板 | `board_ascii_test.mbt` |
| 9 脉冲 | `status_summary` + fix `fist://overview`(version/9态) | 单测 + E2E |
| 10 作用域预订 | `reserve_scope/check/release`（Interlinked 拿来主义） | 双后端单测 + E2E |
| 11 预订整洁 | `clear()` 一并清空 reservations（防跨次残留） | 单测 |
| 12 难度梯度 | `task_plan_deep gradient=true`：拆解子任务带「难度梯度 序号/总数:易/中/难」+「更简单变体」提示（LADDER 信号） | `plan_gradient_verify.py` |
| 13 Critic防漂移 | `evolve_critic` 门禁（SAGE）：入库前纯计算评审拟议 principle/lesson，重合≥70% 判课程漂移拒收、综合分低暂缓 | `evolve_critic_verify.py` |
| 14 Challenger进阶 | `task_challenge`：对已完成/已归档任务发布更难变体新根任务（[challenge] 溯源 + 重要度升档，SAGE 四专家环补齐） | `task_challenge_verify.py` |
| 15 生成物清理 | `cleanup_artifacts.py`：除交付库 fist-mbt.db 外清理 *.db/-shm/-wal 与 temp/；--check 作 CI 干净度守卫 | 实跑 74+63 移除 + CLEAN |
| 16 自驱 DEMO | `award_demo.py`：一条命令串演 map→拆解(gradient)→验收→Challenger→Critic→预订→脉冲/看板 | `python scripts/award_demo.py` |
| 17 难度校准 | `task_plan_deep gradient+calibrate`：按切片给真实难度 0..5 覆盖位置档（LADDER 补真实难度） | `plan_gradient_verify.py`（含 calibrate） |
| 18 文档一致 | agent-map 分组对齐 77 工具、fist://map 文案 76→77（文档即实现扫尾） | 全仓 grep 计数审计 |
| 19 native 证据 | `moon check --target native` 0 错误；Windows native 竞态(0xc0000374)文档如实修正，权威门槛=JS 后端双端+Linux native | 实机验证 + cleanup CLEAN |
| 20 交付完整化 | deliverable 轮证据补齐/遗留如实化（native 竞态、已实现的失败回流不误列） | 文档核对 |
| 21 下一步推荐 | `task_triage`：可领取任务按 优先级→重要度→深度 排行 + suggestion（agent 无需全量扫描即可决定下一单） | `engine_triage_test.mbt` + award_demo ⑨ |
| 22 CI/计数收尾 | CI 三轨道复核（js/native-Linux/js-Win，native 只在 Linux 跑规避竞态）+ 补漏 4 处 77→78 工具计数 | ci.yml 核对 + 全仓 grep |
| 23 能力路由 | `task_triage want`：描述/id 命中能力关键词的可领取任务排头部，suggestion 标注能力匹配（Marketplace 雏形） | `engine_triage_test.mbt` + award_demo ⑨(want=编排) |
| 24 轮表对账 | deliverable 轮证据表 R1..R23 连续（修正错位/补缺/追新） | 文档核对 |
| 25 自检门禁 | README「一键完整自检(评审用)」+ 修正 Tools(61→78) 超陈旧计数，期望逐条实跑核对 | `moon test`+`mcp_smoke`+`award_demo` |
| 26 自驱取单 | `selfdrive_pick_next`：按 triage 能力推荐自动取走顶部并认领（待领取→已领取，无人值守按能力自推进） | `engine_triage_test.mbt` + award_demo ⑩ |
| 27 自驱闭环演示 | award_demo ⑪ 推荐→取单→执行→验收→再推荐整圈跑通 | `award_demo.py` |
| 28 脚本整洁 | 清临时残留(`_score_probe/_probe_result`) + rubric 正式化(`_ai_prompt→scoring_rubric`) + 陈旧计数修正（项目整洁支柱） | `git rm/mv` + `score_gate.py` py_compile |
| 29 挑战题防漂移门禁 | `task_challenge critic=true`：挑战变体发布前过 `critic_review`（与 evolve_critic 同一单一真源），当前策略漂移自动降档、全部漂移拒发（防"由易到难"退化成同质坍缩，SAGE Critic 过滤题目 + R-Few） | `engine_challenge_test.mbt`(+3) + `task_challenge_verify.py` |
| 30 能力路由 | `executor_register`/`executor_route`：执行者登记能力标签，按 { 能力覆盖率 desc → 负载 asc } 路由最佳执行者（Marketplace/Dynamic 范式，按专长+负载分配） | `registry_test.mbt`(+4) + `executor_route_verify.py` |
| 31 能力注册持久化 | `executor_*` 落 store executors 表（双后端）+ `executor_clear` 重置：能力注册跨进程可复现（进程A注册→进程B路由读到→clear 消失） | `executor_store_test.mbt`(+3) + `executor_route_verify.py`（跨进程三段） |
| 32 能力自动派单 | `selfdrive_dispatch`：triage 取顶部 → executor_route 按 want 找最佳执行者 → 直接认领给该执行者（待领取→已领取，把"推荐"落成动作） | `dispatch_verify.py` E2E |
| 33 派单免手传 | `selfdrive_dispatch` 不传 want 时从任务描述自动抽取已注册能力标签（need_auto） | `dispatch_verify.py`（免 want 用例） |
| 34 徽章守卫 | `check_badge.py` + ci.yml JS 轨 Badge guard：README 徽章 ≠ 实测测试数即 FAIL（杜绝计数手改漏同步） | `python scripts/check_badge.py`（正/负路径） |
| 35 LADDER 深化 | `gradient` 提示补"先易后逆推"自举闭环（先完成更简单变体再推广/逆推到本体） | `simpler_variant_hint` + decompose_test 断言 |
| 36 地图同步 | `fist://map` tool_groups 全量同步到 83 工具 10 分组（补 看板/脉冲/预订/推荐+M、Marketplace·能力路由、pick_next/critic/lesson/challenge），map_verify 加断言 | `map_verify.py` E2E |
| 37 gradient真实DAG | `task_plan_deep gradient_dag=true`：把 LADDER「更简单变体→先易后逆推」由提示文本升级为**真实 DAG 前驱链**——每层兄弟切片按由易到难连 depends_on，更难切片须等前驱完成后才可认领，经 `dag_ready/dag_ascii/topo_sort` 可见；仅显式开启，默认零回归、工具数不变 | `decompose_test.mbt`「gradient_dag 真实 DAG 前驱链」用例 |
| 38 执行计划视图 | `task_plan_deep` 返回新增 `exec_order`：拆解后即给出整棵子树的**按 DAG 拓扑序、附难度档/依赖/深度的扁平执行清单**，agent 拿到即可照单执行（纯读无副作用，不加工具）；与 gradient_dag 协同——依赖先于被依赖，"先易后逆推"可见可执行 | `decompose_test.mbt`「plan_exec_order DAG 序执行计划」用例 |
| 39 推荐带依赖 | `task_triage` 每条推荐任务新增输出 `depends_on`（复用 R39 DAG 边）：走 `dag_depend`/`gradient_dag` 建的依赖，"下一单"不光看难度/优先级，还能看到它就绪的前驱是谁（DAG→推荐纵向闭合，复用/拿来主义支柱） | `engine_triage_test.mbt`「task_triage 暴露 depends_on」用例 |
| 40 难度抽取单一化 | `task_triage` 的难度标签改复用 R40 的 `extract_difficulty` 单一抽取来源（去重 `triage_label_of` 的 `:易]` 后缀粗匹配，并支持 calibrate 真实难度 `难 d=5`→难 归一；空回退叶/分支兜底不变）——消除两处难度解析重复，落实支柱②复用/避重复 | `engine_triage_test.mbt`「task_triage 返回可领取排行并带难度标签」既有用例回归 |
| 41 脉冲难度分布 | `status_summary` 新增 `by_difficulty`（待领取任务按 易/中/难/无 分布）：`extract_difficulty` 升为 pub 跨包复用（server 包），项目脉冲一眼看"待办难度结构"（支柱①＋②） | `board_ascii_test.mbt`「status_summary … by_difficulty 不变量」用例 |
| 42 工具单一真源 | `scripts/check_tools_sync.py` + ci.yml 两轨：唯一真源=server.mbt 实际注册名，校验 AGENTS 表格工具名 ⊆ 真源、真源全部入 AGENTS、四文档工具总数==83（双向防幽灵/漏写）。守卫发现 AGENTS 只列 54/83 后补齐 29 个（新增 自驱闭环/运维杂项/ATGC-old 三组，生命周期14、自进化11、Omega补2），PASS | `python scripts/check_tools_sync.py`（PASS）+ `moon test` 233/233 |
| 43 测试数单一真源 | `scripts/check_test_sync.py` + ci.yml JS 轨：补 check_badge 盲区，跨 README/AGENTS/deliverable/scoring_rubric 校验测试总数==实测（N/N、N 全绿、独立 N 任一），正路径 PASS、负路径 FAIL=1 | `python scripts/check_test_sync.py --total 233`（PASS） |
| 44 地图补全 | `fist://map` tool_groups 补齐 R46 新工具家族（生命周期 publish_parallel/reopen_task、强验证 verify/verify_fix、新增「运维·日志/缺陷/成本/调度」「衍生·ATGC-old」分组、自驱补 selfdrive_dispatch）；map_verify 加断言锁住关键补漏——agent 首读地图即全概（支柱①） | `python scripts/map_verify.py`（PASS 12 分组）+ `moon test` 233/233 |
| 45 看门狗派发预览 | `watchdog_tick` 在显式 ns 无人值守场景新增 `detail.ready_dispatch_preview`：复用 engine.triage 给出"下一单可自动派发"的候选（纯读不认领，避免 ops 仓与 server 进程内 exec_reg 耦合；自治派单的前置信号） | `ops_watchdog_test.mbt`「watchdog R51 派发预览」用例（+1） |
| 46 看板难度标注 | `board_ascii` 每行任务附自身难度档（复用 pub `extract_difficulty` 单一来源）——实时看板一眼看任务难度结构（支柱①"一目了然"＋②"复用"） | `board_ascii_test.mbt`「board_ascii 每行标注难度档」用例（+1） |
| 47 引擎层自治派单 | 新增 `FistEngine::dispatch_next`（engine 层 store-backed 自治派单 primitive，R56）：读 store 持久化执行者能力注册 + executor 包 `route_pick` 按能力/负载路由 → 把 triage 顶部任务直接认领给最佳执行者（无注册回退 agent）。纯增量、零回归、不经 server 进程内 exec_reg——是看门狗自治派单的地基（未起 watchdog，仅 engine primitive + 单测） | `engine_dispatch_test.mbt`「dispatch_next」用例（+2） |
| 48 看门狗自治派单 | `watchdog_tick` 新增 `autodispatch`/`autodispatch_want`（R57，默认关闭零回归）：显式 ns 无人值守且无活跃任务时调 engine `dispatch_next` 把顶部待领取任务按能力/负载认领给最佳执行者，结果并入 `detail.autodispatch`——自治闭环闭环：派单 primitive + 看门狗驱动全打通（引擎层派单下沉、不经 server 进程内 exec_reg） | `ops_watchdog_test.mbt`「watchdog R57」用例（+2） |
| 49 派单能力自动抽取 | `dispatch_next` 在 `want` 为空时从顶部任务描述自动抽取所需能力标签（R58，store-backed 复用 R33「免手传」思路、不依赖 server exec_reg）：扫描述里出现的 store 持久化执行者能力标签取最长命中，返回 `want` 字段——「零参数自动派单」达成，watchdog `autodispatch_want` 可缺省 | `engine_dispatch_test.mbt`「want 自动抽取路由」用例（+1） |

> 注：内存日志/汇报用字母轮号（含若干纯文档/CI 非功能行，不入上表）；本表仅计功能轮。

## 五、文档即实现
- 工具/资源/测试数均与实测一致（README/AGENTS/ARCHITECTURE/agent-map 已同步）。
- 过程日志 `memory/2026-09-25.md`；综合汇报 `reports/2026-09-25-award-enhancement-5rounds-report.md`。
- 调研：`memory/research/20260925.enrich-roadmap.md`（Repo Map / DALIA / TURA / AgentX / MoonBit 新特性）、`memory/research/ecosystem-borrow.md`（§五 二轮调研：SAGE/R-Few/SPICE/SEP-1686/RepoMap）。
- 遗留如实：Windows native 竞态、`node:sqlite` 实验性警告、测试落盘 `temp/`（cleanup --check 兜底）见 §六。

## 六、遗留（诚实自曝）
- Windows native 测试偶发 `0xc0000374`（堆损坏/竞态，`-j 1` 可降但不保证消除；权威稳定门槛 = JS 后端双端 + Linux native，产品单进程不受影响，README「已知边界」）。
- `node:sqlite` 打实验性警告（功能正常）。
- 测试落盘目前在仓库 `temp/`（gitignore），由 `cleanup_artifacts.py --check` 作干净度门禁；`@fs.tmpdir` 在本工具链未暴露，"收敛到系统 tmp" 作为可选后续。
- Dynamic/Marketplace 能力路由（executor 抽象层朝"能力注册+按负载/专长分配"）为远期项。

*（内容由AI生成，仅供参考）*