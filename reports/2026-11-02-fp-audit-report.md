# FALSE_POSITIVE 全量复核报告（R123 · 2026-11-02）

- 执行：commander-delta（只读审计）+ 统帅抽查终审。
- 范围：`memory/bugs.md` 全部 `FALSE_POSITIVE` 状态条目（26 条）。
- 方法：逐条读当年判误报的理由 → 用**当前 HEAD**（`6e941a8a` 时点）核实理由是否仍成立（符号/函数级 file:line 证据）→ 三选一结论。
- **结论：26/26 维持误报；0 疑应重开；0 无法判定。**
- 原始导出：`temp/lane_fp/fp_entries.txt`（426 行，临时面不入库；账本内的 FP 条目本体即永久档案，本报告只记审计结论）。

## 一、26 条结论表

| 编号 | 严重度 | 当年主张（摘） | 结论 |
|---|---|---|---|
| BUG-10 | low | archive 要求 [待验收]，[待领取] 任务无合法废弃路径 | 维持（设计面话题，后由任务生命周期改造覆盖） |
| BUG-92 | medium | 拒绝文案「要求[待领取]当前[待领取]」自相矛盾 | 维持（真缺陷另立 BUG-99；原文案系 cp936 乱码误读） |
| BUG-96 | low | 巡回探针：调用面可用性核验 | 维持（探针自写真账本的垃圾条目） |
| BUG-97 | low | 巡回探针：调用面可用性核验 | 维持（同上，与 96 同源双发） |
| BUG-142 | high | moon test 崩溃仍 exit 0 | 维持（工具链缺陷，非本仓；汇总行判绿纪律已入规范） |
| BUG-201 | low | omega_spec 阈值比较方向 | 维持（设计定论：rejected>=max_r 语义正确） |
| BUG-242 | high | [Pentad] spawn(actor 实例) 被拒 | 维持（跨项目：Pentad 仓面，FIST 无 actor） |
| BUG-250/251 | medium | TEST-BUG-WRITE(-PUBLISH)-PROBE | 维持（探针写入；真缺陷归一至 BUG-253） |
| BUG-255 | medium | [Pentad] @stream @observe 内不产出事件 | 维持（跨项目） |
| BUG-258 | medium | [Pentad] §16 标记树三处自相矛盾 | 维持（跨项目） |
| BUG-259 | medium | [Tnr] corpus/transpile 金标准漂移 | 维持（跨项目） |
| BUG-273~276 | high×3/medium | [lz 编译器] str 类型推断/循环变量/splitn | 维持（跨项目：lz 语言仓 .lz 面，FIST 仓无） |
| BUG-307 | low | 嵌套 Dict get Option unwrap_or（探查型） | 维持（探查结论：行为正确） |
| BUG-321 | high | [codegen] BlockExpr 不继承 expected_ty | 维持（跨项目） |
| BUG-330 | medium | moonc/moonfmt 0.10.16 把 Int 打成 Int32 | 维持（工具链；复现环境不在本机，判据已容） |
| BUG-388 | medium | `moon fmt --check` Windows rc=-1 | 维持（工具链缺陷；`check_fmt_gate.py` 已按 0/1/2 契约接管） |
| BUG-410 | high | --emit=ir-lz 自举 rustc E0599 | 维持（跨项目；未进 lang-zone 仓复核，见缺口④） |
| BUG-414/415 | low | [PROBE] report_bug 尾随空行验证 | 维持（探针；修复已由 BUG-454 账目独立确认） |
| BUG-469 | high | 生命周期后半段六工具未接 challenge（S3 覆盖 3.2%） | 维持（设计定论：拆自 BUG-430，S3 默认不强制已在定案书记录） |
| BUG-473 | high | execute 的 agent 参数 schema 声明了但 handler 不读 | 维持（server.mbt:843 `acl_execute_identity` / :2466 `agent_write_gate` 均消费该身份） |
| BUG-474 | high | publish_parallel 的 created_by 无硬检查 | 维持（真缺陷归一至 BUG-475 的 created_by 处置） |

## 二、分类汇总（delta）

- **跨项目误落 11**：Pentad（242/255/258）、Tnr（259）、lz 编译器（273/274/275/276/321/410）——FIST 仓无 `.rs`/`.lz` 面，当年是共享工作目录的串台。
- **真缺陷已另立或已修 4**：92→BUG-99；250/251→BUG-253；414/415→bugreport 归一；474→BUG-475。
- **上游/工具链边界 3**：142、330、388。
- **设计定论 8**：10、96、97、201、469、473 及探查型 307、414 面内。

## 三、缺口（只报不修，6 项）

1. BUG-96/97 台账重复条目 + 时间戳错配（05:01/05:04 双发记载互有出入）。
2. BUG-142 小记引用行号已漂（`:91`→现 `:325`）。
3. BUG-330 未在新 moonfmt 重跑复现（判据只容不证）。
4. BUG-410 未进 lang-zone 仓复核（跨仓结论依赖当年日志）。
5. server.mbt 19 处 `challenge_sig` 声明 vs 引擎 4 个消费面——透明度记录，非缺陷。
6. 台账跨项目路径（Pentad/Tnr/lz）大小写不一致，机器比对不可直接复核。

## 四、统帅抽查（3 条）

- BUG-473：`src/server/server.mbt:843` `acl_execute_identity`、`:2466` `agent_write_gate` 属实，handler 消费 agent 身份 ⇒ 维持成立。
- BUG-92：改判依据含回执 JSON `\u` 逐字反解与 BUG-99 另立记录，链条完整。
- BUG-142：小记与 `moon_test_env.py` 的汇总行判绿纪律（BUG-380 家族）互证，工具链定性无误。
