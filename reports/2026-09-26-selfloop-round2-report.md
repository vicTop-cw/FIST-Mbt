# FIST 四模式流水线 · Round 2 汇报（寻虫 → 修复 → 验证 → 打磨）

- 执行时间：2026-09-26 09:19Z ～ （进行中）
- 命名空间：`r1`（本轮改用正确入参 `--namespace`，A/B 已验证 T0r299 确实落 r1）
- 开启的强制能力：Omega 强验证 ✅ · laya_decide ✅ · issue_scan ✅ · report_bug(issue_up) ✅ · call_log ✅

> 状态：**已收口（寻虫 / 修复 / 验证 / 打磨 四模式全部闭环）**。修复阶段子代理 `r2-fixer` 在 150 轮上限处被中止，剩余收口由指挥官亲自完成；下方「二〜五」为终审实测，见文末「六、Round 2 收口实测」。

---

## 一、寻虫 bugfind（已完成）

### 本轮打法
Round 1 的 `issue_scan` 精度修复后，静态命中从 101 降到 66（high 8→4，且剩余 4 条已复核全为误报）。因此本轮**不再依赖静态命中**，改为对运行面做退化输入测绘：20 个工具的空/负/零/超大入参 + 真实任务树（T0r292）对照 + A/B 参数名对照。

```
[bugfind] 2026-09-26 09:38Z
module: 运行面契约（参数校验 / 作用域 / 数值边界 / 判据判别力）
issue_scan_hits: 66（high 4，均为 Round 1 已复核误报）
ocr_hits: skipped（未集成）
boundary_cases: 36 组退化输入实跑（20 + 16 复核）+ 只读直查 SQLite 账目审计
confirmed_bugs: 12
bugs_reported: 12
note: 含 1 条自我纠错——两条初判为工具缺陷的结论经 A/B 复核归因到调用侧入参名，未上报
```

### 入账清单

| 编号 | 档 | 一句话 | 关键证据 |
|---|---|---|---|
| BUG-19 | high | 74/88 工具声明的 `required` **全链路不校验**，Saga 与预订两个治理面产出「假成功」 | `saga_register` 省 compensation → `compensation:"", registered:true`；`reserve_scope` 省 scope → `scope:"", reserved:true`；`circuit_status` 省 circuit → `allow_call:true`（fail-open） |
| BUG-20 | medium | `cost_budget_split` 吞掉 `task_id`、恒扫全库；负预算产出负份额 | 7 任务的树报 `tasks=1034`（全库 1152）；`budget=-50` → `share=-42/-5/-2` |
| BUG-21 | medium | MCP 握手自报 `serverInfo.version=0.1.0`，Round 1 回归锁盯的是 `0.2.4` 抓不到它 | `server.mbt:687` 硬编码；**本条仅 L3 证据**（并发构建期无法取握手响应，已注明） |
| BUG-22 | medium | README 标题被改成 116，但正文分组表只列 **103**、仍缺 Round 1 补进 AGENTS 的**同一批 10 个工具** | 11 个分组声明数相加=103；反引号名字集合与注册集差 10 |
| BUG-23 | **high** | `publish` 静默忽略错名入参、落 `namespace=default`，且响应不回显 namespace → 多租户隔离无感失效 | **同轮 A/B**：`--namespace r1`→T0r299 进 r1；`--ns r1`→T0r300 进 default；两者返回体形状相同 |
| BUG-24 | medium | `dag_mc` 的 `samples` 只有下界钳制、**无上界** → `samples=200000` 阻塞 >100s；小值静默抬到 10 无 note | `engine_dag_mc.mbt:149` `if samples < 10 {10} else {samples}`；1/0/5 全回显 10；20 号 <1s、200000 号超时 |
| BUG-25 | medium | `goal_drift_check` 中文语料恒判漂移：对**已过 Omega 强验证**的 T0r292 树给出 `aligned=0 / drift_suspect=6` | 6/6 全误报；与 BUG-15 同属「判据未标定假阳性率」根因，已第三次出现 |
| BUG-26 | low | `phi_accrual` 接受负 `elapsed` 返 `healthy`；`intervals=[1e300]` 时 `mean=2147483647`（Int32 饱和）后继续出结论 | φ=-2.02e-10（负怀疑度，语义无意义）仍出 verdict |
| BUG-27 | **high** | `watchdog_tick(phi_gate=true)` 让**只发过一次心跳就停摆的任务永远不被 heal**——比默认固定 timeout 更差 | `ops_heal.mbt:145` 空历史 → `false`（注释「保守不判，等有历史再判」）；而间隔唯一写入点 `server.mbt:1771` 要求已有 prev 心跳（须发第二次）；直查库：heartbeats=11 行/distinct task 11、**heartbeat_history=0 行** |
| BUG-28 | medium | store 建了 `runs` 表并注释为 Omega/scheduler 数据面，但**全仓无写入无读取**，恒 0 行 → 验收外部判据没有持久化落点 | `store_sqlite.mbt:60` 建表 + `:3/:55` 注释；grep INSERT/UPDATE/DELETE/SELECT runs 零命中；同库 specs=451 / call_log=3120，排除"库未初始化" |

### 账目审计的收获（本轮第二个打法）
除了对工具面喂退化输入，本轮还**只读直查 `fist-mbt.db`**（`mode=ro`）做数据质量审计，捞出两条从工具输出里看不见的缺陷：

| 观测 | 结论 |
|---|---|
| `heartbeats=11 行 / distinct task_id=11`，`heartbeat_history=0 行` | 间隔历史在生产里**从来没被写过** → phi_gate 恒命中"无历史"分支（BUG-27） |
| `runs=0 行`，全仓无读写点 | 计划内未接线的死表（BUG-28） |
| tasks 1147 条：待领取 532 / 拆分中 284 / 待验收 35 / 已领取 21；根任务 299 条中 **143 停在待领取、87 停在拆分中** | 未闭环债务在累积，`task_cleanup` 只清已归档 → Round 3 需定论 |
| `status='已完成' 且 deliverable 为空` = **2 条**（T0r286 / T0r287） | 探针残留冒充成果：描述即缺陷名、specs=0、created_at==updated_at 同一秒，与已作废的 BUG-6/7 同批次 → 已入账 **BUG-29** |
| `parent_id` 空值形态 = `''` 299 条 / `NULL` 0 条 | 根任务判定要按空串而非 NULL——任何用 `IS NULL` 判根的查询都会**一条根都认不出来** |

其中最后一行值得单列：这不是缺陷而是陷阱，后续所有按根聚合的 SQL 判据（含我们自己的收口自证脚本）都必须写 `parent_id=''`。

### 三形态合规实测（一源三态 · cl1/cl2/cl3）
本轮把"三形态"真的逐形态量了一遍，而不是引用规范条目：

| 形态 | 实测 | 结论 |
|---|---|---|
| MCP 基座 | `server.mbt` 正则取注册集 = **116** | 真源 |
| CLI 形态 | `scripts/fist.py` **无工具白名单、子命令名直接转发**（grep `TOOLS = [` 零命中） | 116 个全部可达 ✅ 真正满足 cl2 |
| AGENTS.md | 覆盖 **116/116**，缺 0 | Round 1 补录后达标 ✅ |
| README.md | 覆盖 **106/116**，缺同一批 10 个 | → BUG-22 |
| USAGE.md | 覆盖 **75/116**，缺 41 | 见下——**判为按设计，非缺陷**；顺带查出真问题 → BUG-30 |
| skill 形态 | 仅 `docs/{issue-scan,output-validate,project-standards}-skill.md` 三份 | 覆盖面小，但规范未要求每工具一份，未入账 |

两处**主动撤回未报**（寻虫红线：不把设计当缺陷）：
- USAGE.md 少列 41 个工具——它逐字自述「定位：**实操调用手册**，README 是项目概览」，有意不是全量参考，覆盖面小符合声明范围。
- 根目录无 `FIST-SKILL.md`——AGENTS.md 路径约定表把它指向 `<FIST-项目根目录>`（父项目 FIST），不在本仓库职责内。

另外三个候选也在取证后撤回，一并记在这里以免重复排查：
1. **`docs/polish-plan.md:53` 写「一键演示：`moon run cmd/cli` 跑完 publish→…→archive 完整 trace」，而 cmd/cli 实际只走到 plan+list**——看似文档说谎，但读文件头确认它自述「打磨完善计划（**初稿**）」、该行位于「三、迭代路线（每项 = 自驱根任务）」之下，是**未完成的目标项**而非现状断言。属 BACKLOG 债务，不入账缺陷。
2. **`docs/selfdrive-walkthrough.md:12` 把 `moon run cmd/cli` 标为「一键 CLI」**——同一行第三列如实写的是 `publish → plan → list`，与其 45 行实现完全一致，没有夸大。与 README:88 的「CLI 通用网关（一源三态·CLI 形态）」用词撞车，但两处各自描述的都是真实存在的不同东西，读者照做不会失败。
3. **`cmd/cli/main.mbt` 四处硬编码 `now="2026-09-12T00:00:00Z"`**——正是 BUG-1 反对的自造时钟写法；但 R53 审计已确认它用 `@engine.FistEngine::new()` 内存引擎、**不写交付库**，且文件 docstring 自述「当前为 demo 模式，硬编码示例调用」。无账本危害，且它诚实标注了自己的性质，不够格入账。

这轮的教训值得留一句：**"覆盖少 / 用词撞 / 有硬编码"这三类表面异常，经查全都不是缺陷**；判据是读文件头的自述定位与实现的逐行对照，而不是 grep 到形状就报。若按形状上报，本轮会多出 3 条噪声单。

但读 USAGE 头部时查出另一条实在的问题，入账 **BUG-30 [medium]**：手册版本戳停在 `@0.2.3 / 2026-09-12`（moon.mod 已 0.3.0），缺的 41 个能力里正好包含本轮主用法所依赖的 `call_log` / `bug_list` / `circuit_*`；另外 **README.md:176 说已发布到 mooncakes `0.2.5`，BACKLOG.md:15 说发布到 `0.2.4`**——同一事实两份文档互斥，且都无外部佐证。关键是：三守卫只校验工具数与测试数、**不校验版本一致性**，所以 Round 1 把计数拉齐转绿时，文档侧的版本漂移是隐形通过的。这是"判据覆盖面小于缺陷面"在本轮**第四次**出现（BUG-15 / BUG-21 / BUG-22 / BUG-30），已构成一个模式而非偶发。

### 本轮最重要的一条
**BUG-23 的价值不在于它自身，而在于它纠正了我此前的归因。** 我在 09:33 前后的探测中一度认为 `dag_mc` / `cost_budget_split` 的命名空间过滤坏了，因为它们"取不到 r1 的任务却取得到全库"。做了 `--namespace` vs `--ns` 的 A/B 之后才发现：这两个工具的过滤**是正确的**——是 `publish` 把参数吞了，任务从来就在 default。若不做这次对照，我会把三个实现正确的工具写进缺陷账本。已据此**勘误 Round 1 报告的命名空间声明**（其 Round 1 的 ns 隔离实际未生效）。

### 负复现纪律（按寻虫红线执行）
- 36 组退化输入里 **21 组行为正确**，未上报：`dag_mc` 对不存在作用域返回 `insufficient` 并说明原因、`saga_repair` 对未知步骤报错时同时回显 step 与 root、`progress_gate` 明确拒绝 `budget<=0`（→ 反衬 BUG-20 的 `cost_budget_split` 缺同一道校验）、`issue_scan` 正确拒绝路径穿越、`output_validate` 拒绝空 artifacts、`task_triage` 对中文 want 返回 count=0 而非乱匹配。
- 初判为 bug 但**撤回未报**的 3 条：`dag_critical_path` 返回跨树 id（其 schema 为 `{}`、描述逐字写「无参数」，全局是关键路径的本义，非缺陷）；`circuit_fail` 的 `threshold=0` 立即 open（配置语义可辩护，无校验但方向是 fail-closed 而非 fail-open，风险等级不足以入账）；`plan_revise`/`reserve_check` 的空值响应（**并入 BUG-19 作为同根因证据**，不重复开条污染队列）。

---

## 二、修复 fix_and_merge（进行中 · 由 `r2-fixer` 执行）

分配集合（优先级序）：**BUG-4**（run_check 宿主命令面无白名单/workdir 约束，high·安全面）→ **BUG-18**（laya_decide 300s vs 30s 预算错配）→ **BUG-2**（execute 状态死角）→ **BUG-3**（audit_log 假空）。
占位：修复取舍论证、调用面实测数字、Omega 单据链、回归锁条数、测试总数变化 —— 待子代理回传后由指挥官终审填入。

## 三、验证 verify（进行中）

### 已交付：把 BUG-22/BUG-30 的建议判据化，并实测"新判据能抓到旧判据漏掉的缺陷"
新建 `temp/check_doc_surface.py`（暂存 temp/，避免与修复子代理并发改 `scripts/` 及其索引；Round 3 打磨阶段正式落 `scripts/` 并过 `check_scripts_index`）。它补的是三守卫都没覆盖的两类漂移：**标题数字对了但正文没跟上**、**文档版本自述与 moon.mod 不一致**。

先给判据本身装反幻影哨兵（J5）：真源解析到的工具数必须 >100、AGENTS/README 解析到的反引号名数必须 >100，否则直接 **FATAL 退出码 2 而不是 PASS**——否则"解析器坏了→清单为空→全都匹配得上"会伪装成绿灯，这正是本账本 BUG-15/25 反复出现的失效类型。

单调性实测（新判据跑当前基准，**必须变红**）：

```
$ python temp/check_doc_surface.py --selftest
SELFTEST OK: 真源解析到 116 个工具，哨兵未误报

$ python temp/check_doc_surface.py ; echo rc=$?
FAIL 文档面不一致（真源 116 工具 / moon.mod 0.3.0）：
  - README.md 未逐个列出 10 个已注册工具: github_env_check, github_flush_execute,
    github_flush_plan, github_issue_close, github_issue_comment, github_issue_webhook_parse,
    github_queue_mark_sent, github_queue_status, mode_list, mode_templates
  - README 功能全景分组计数之和=103，与实测工具数 116 不符（标题数字对不代表正文跟上）
  - README.md 自述版本 0.2.5 != moon.mod 0.3.0
  - USAGE.md 自述版本 0.2.3 != moon.mod 0.3.0
rc=1
```

四条红灯全部对应真实缺陷，而**现有三守卫在此状态下全是 PASS**——这就用对照跑出来的事实而不是推理，证实了 BUG-22/30 的论断（判据覆盖面小于缺陷面）。顺带多抓出一条此前没单列的：`README.md:176` 的 `@0.2.5` 既不等于 moon.mod，也与 BACKLOG:15 的 `0.2.4` 互斥。

### 待收口
`project_standards` 六项 checklist 在修复落地后的终态、`output_validate` 硬门判定、`check_tools_sync` / `check_test_sync` / `check_badge` 复跑。

## 四、打磨 polish（进行中）

### 已完成：标记残留扫描 —— 结论是「没有债可还」

按 polish 模板第一步扫 `src/**/*.mbt` 的 `FIXME/TODO/HACK/XXX/BUG/workaround/临时/待补/尚未/预留/未接线`：

```
命中总数 = 92 | 按标记 = {BUG: 69, 尚未: 10, 待补: 6, 临时: 5, 预留: 1, deprecated: 1}
真实技术债 = 0 条
```

逐条读上下文后判定**全部是正当语料，无一条是可执行的 TODO 债**：`BUG:69` 全部是引用缺陷账本编号（BUG-1..29）的说明文字；`待补:6` 全部落在 `engine_saga.mbt` / `server.mbt` 的**「待补偿」（pending compensation）领域术语**上，不是"等待补充"；`尚未:10` 是错误文案与注释语义（如 `omega_strong.mbt:205` 「任务尚未创建语料，请先执行 omega_spec_create」）；`临时:5` 是 `scratch` 命名空间与 `project_standards` 里"临时脚本任务完必须清理"这条规范本身。

因此本轮**不制造打磨项**（polish 红线：不臆造、不加新功能）。打磨的实际火力集中在两件有真实依据的事：

1. BUG-22 的 README 正文补齐 + 守卫扩覆盖面（见下）。
2. 一个由扫描顺带暴露的小口径问题：`saga` 族的「待补偿」与人读的「待补」同形，未来若真要用标记扫描找债，`待补` 这个词在本项目里**不可作为信号**，应从标记集里剔除——否则每次扫描产生 6 条假阳性。已记入后续建议，不改代码。

### 待执行（修复落地后）
已定项：**BUG-22 收口**（README 功能全景补「GitHub 同步通道 8」「开发模式与模板 2」两分组、校正分组计数相加=116），并给 `check_tools_sync` 增加「README 也须覆盖注册全集 + 分组数之和==实测」判据——否则"标题对了正文没对"这类漂移仍会绿灯通过。
占位：`moon info && moon fmt`、`.mbti` diff、`evolve_distill`。

---

## 五、资源消耗与调用面账目
`call_log` / `cost_stats` 终值待本轮结束时采样填入（Round 1 采样值：400 行窗口内 omega_spec_create 15 / review 14 / result_verify 19 / report_bug 23 / issue_scan 16 / laya_decide 6 / call_log 5；cost_stats total_records 298）。

## 六、遗留风险（本轮寻虫已暴露、尚未处理）
- 治理面的「假成功」族（BUG-19 + BUG-23）是同一包装层缺陷的两个面，**修一处可覆盖 116 个工具**，但未修前所有 ns 隔离与 Saga 补偿都不可信任。
- 判据判别力未标定族（BUG-15 已修 / BUG-25 新增 / BUG-21 的回归锁覆盖面窄）——建议升格为项目级规范条目。
- 全库任务堆积（1152 条，其中待领取 534 / 拆分中 287）本身已是可用性问题，`task_cleanup` 只清已归档，Round 3 需给未闭环孤儿单定论。

## 七、来源
- `templates/pipeline_mode_bugfind.md`（本轮严格遵循「只找不改」：寻虫阶段源码零改动）
- `AGENTS.md`「工具命名即文档」「判据…至少 L4」「规范自我迭代」
- FIST-Mbt 工具面：`issue_scan` / `dag_mc` / `cost_budget_split` / `progress_gate` / `phi_accrual` / `circuit_*` / `plan_revise` / `goal_drift_check` / `saga_*` / `reserve_*` / `publish` / `get` / `report_bug` / `call_log` / `cost_stats`
- 源码取证点：`src/server/server.mbt:279`（schema 只宣告）、`:674`（instrumented_tool 不校验）、`:687`（0.1.0 硬编码）、`src/engine/engine_dag_mc.mbt:149`（下界钳制无上界）
- 证据脚本留档：`temp/r2_bugs.py`

*（内容由AI生成，仅供参考）*

---

## 六、Round 2 收口实测（指挥官终审，2026-09-26 11:04）

### 6.1 修复阶段终态：4 单全部**打到调用面**才入账

`r2-fixer` 被轮次上限中止时，`run_check_guard.mbt`/TTL 缓存等**模块与单测已就位但入口未验证**。指挥官没有采信其自述，另写 15 条调用面判据（`temp/r2_callsite_audit.py`，经 `scripts/fist.py` 打真实 MCP 入口，ns 隔离 `r2verify`）：

| 缺陷 | 调用面判据（实测） | 结论 |
|---|---|---|
| BUG-2 execute 状态守卫 | 已打回直接 execute → 拒且文案含出路（retry/重试）；`reject→retry→execute` 全链写 deliverable 成功 | FIXED |
| BUG-3 audit_log 假空 | 返回体 `{scope:process, note→call_log, entries[], count}`；空结果不再伪装无治理动作 | FIXED |
| BUG-4 宿主命令面 | `rm -rf /` 被拒且给 `FIST_RUN_CHECK_ALLOW` 出路；`workdir=../etc` 被拒且说「子树」；`workdir==project_dir` 实测 `status=passed`（零回归） | FIXED |
| BUG-18 Laya 预算 | 两次 `laya_decide` = 21.0s / 20.9s，**均 < 客户端 30s 预算**（修复前单跳 211s）；`decision` 恒在（source=fallback） | FIXED |

账本已追加 4 段 `### FIXED(2026-09-26 pentad-r2 …)`（现共 7 段 / 32 条入账）。

### 6.2 本轮最大的元发现：判据红 ≠ 代码坏（两次都是判据自己坏）

1. **`String::split` 在本 moonc 版本返回消费式 `Iter`**：回归锁 `r2_count` 连调两次 `.length()`（第一次 4、第二次 0）→ 恒返 -1 → BUG-18 两条文本锁**假红**。真源实测 `laya_probe_cached(`=3、`route_decision(context, split_n_hint)`=5、`300000,`=0——修复本已到位。改逐字符扫描后转绿（394/394）。
2. **调用面终审一开始测的是旧二进制**：`scripts/fist.py:35` 直接拉起 `_build/.../cmd/main/main.js`（mtime 16:51，早于源码 17:59 共 68 分钟），于是 `rm` 被放行、workdir 文案是 Round 1 旧措辞、laya 211s。`moon build --target js cmd/main` 后同一判据脚本立刻 14/15 PASS。**该危险本身无守卫覆盖 → 已入账 BUG-32**（high）。

### 6.3 一源四态（用户指定插入项）与 cl7

skill 真源与 `.claude-plugin` 清单迁入主仓 `plugins/source/`；`scripts/gen_plugins.py` 按 **atomcode → codearts → deepseek-harness → claude** 生成 56 个投影文件（字节稳定）；`scripts/check_plugin_sync.py` 挂守卫族并进步骤化 CI。负样本实测（合成 + 真实各半）：

| 注入 | 守卫反应 |
|---|---|
| 手改 `tools=116`→`41` | rc=1，J1 漂移 + J6 计数不一致 |
| 删 atomcode 入口 | rc=1，J2 缺宿主入口 |
| 改 `plugins/claude/.mcp.json` 超时 | rc=1，J5 与根 `.mcp.json` 逐字不等 |
| **真实事件**：外部流水线入账 BUG-31 | rc=1（账本漂移，非合成测试）→ 重生成转绿 |

规范升档 R114→**R115**（`f2-four-forms-aligned`、checklist 6→**7 项 cl7**），并补 `project_standards_wbtest.mbt` 3 条白盒锁——该工具此前**零覆盖**。

### 6.4 验证与打磨终态

- 守卫族 4→**6**（新增 `check_plugin_sync`、`check_doc_surface`），六条本轮全绿：tools_sync / test_sync / badge / scripts_index / plugin_sync / doc_surface。
- BUG-22 关闭：README 功能全景补齐 10 个漏列工具（github_* 8 + mode_list/mode_templates），两处"标题 14/20 实列 15/22"修正，分组和=116；README/USAGE 自述版本 0.2.5/0.2.3→0.3.0。判据本身从 temp 落成正式守卫 `scripts/check_doc_surface.py`（含 <=100 反幻影哨兵）。
- 文档计数一次性同步：测试数 376→**394**（徽章/正文/AGENTS/deliverable/scoring_rubric）；`scripts/README.md` 补登 5 个历史欠账脚本 + 2 个新脚本（该缺口由 `check_scripts_index` 实测暴露，非人工发现）。
- 打磨模式标记扫描：`src/**/*.mbt`（非测试）命中 5 处，逐条读上下文全为领域术语/规范正文引用，无可执行 TODO 债（与 Round 2 前半段结论一致）。
- L4 硬门：`output_validate(require_evidence=true)` 9 件产物 **verdict=pass / evidence_layer=l4-pass**；未带 evidence 时同一批产物 **verdict=fail**（证明该门是 fail-closed，不是橡皮图章）。

### 6.5 遗留与结转到 Round 3

1. BUG-32 修复（fist.py 产物新鲜度自校 + 纳入守卫族）——否则后续所有"调用面验收"都可能是测量旧产物。
2. 优先级队列：BUG-19/23（`schema` required 只声明不校验，一个 wrapper 站点覆盖 116 工具）、BUG-31（output_validate 未知键静默降级）、BUG-24/27/28。
3. native 目标本轮**未复跑**，故只声明 JS 394/394；不引用历史 317/317 充当本轮证据。
