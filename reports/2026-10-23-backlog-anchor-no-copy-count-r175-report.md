# R175 · BACKLOG 锚点行去掉三个陈旧计数，改成只指真源（不再抄数）· 2026-10-23

## 结果摘要
`BACKLOG.md` 文首「锚点事实」行自述 **`120 工具 / 442 测试 / JS+Native 双后端 / CI 三绿`**。本单现读对表：
工具面真源 `src/server/server.mbt` 注册 **170** 个（`check_tools_sync` PASS）、测试面 README 徽章/`moon test --target js`
汇总行为 1387/1387 量级（差近千条），而 **native 轨按 BUG-133 的关闭条件从未达成「双端同版全绿」**、
CI 的 `Test (native…` 臂红着带 `::error::` 注解——所以那三个数加那句「CI 三绿」里有**四条**断言与现状不符。

改法不是把数抄成新的（那只是把同一颗雷重新埋一遍，且 **全仓没有一把尺扫 `BACKLOG.md` 的计数面**——
`check_test_sync` 的 MUST_CARRY 只含 README/AGENTS/deliverable/agent-map/scoring_rubric，
`check_tools_sync` 只对 AGENTS/README/deliverable/scoring_rubric），而是**把计数从现状面撤成指针**：
工具数 → 注册表 + `check_tools_sync.py`；测试数 → README 徽章行 + 汇总行 + `check_test_sync.py` / `check_badge.py`；
后端与门槛 → `AI-DEVELOPMENT-STANDARD.md` §7 + 账本 BUG-133，并明确「本仓不写 JS+Native 双端同版全绿、不写 CI 三绿」。
这一条与 R160（`docs/selfdrive-walkthrough.md` 的「148 项测试双端全绿」）同型、同处置，是本会话第二次把
**假绿自述**换成**指真源**，区别只在 R160 落在 docs/ 评估面、这一条落在 selfdrive 的**净拉取源**上。

## 证据
- 现读对表：`check_doc_surface` rc=**0**（含 J4「注册表发布版本只在 BACKLOG.md 一处自述」与分组和=170）/
  `check_tools_sync` rc=**0**（170 工具）/ `check_publish_payload` rc=**0**（BACKLOG 已跟踪，1329 件载荷干净）
- `check_doc_dup` rc=1（232 块冗余）＝**预存红**，与基点同成因，本单未新增块级重复
- **本单未跑的两把尺（不冒认成绿）**：`check_badge` 与 `check_test_sync` 的调用面要 `moon test` 日志作参数
  （`python scripts/check_badge.py <moon_test_log> <README.md>`）。我按无参形式跑，得到的是
  `rc=1 用法:…` 与 `rc=1 FAIL 无法从参数/日志解析测试总数`——**这是调用方式缺参数，不是本单的违例读数**，
  也不是"这两把尺在 master 上红"。要判这两格需要真跑 `moon test --target js`（本机受 BUG-380 垫片坑，
  走 `python scripts/moon_test_env.py`），本单未付这个时间，故在此点名而不写进 PASS 行
- 零 MoonBit 改动 ⇒ 无 `moon fmt` / `moon check` 面

## 分析（为什么"撤成指针"而不是"改数"）
抄数的失效模式不是"数错了"，而是**没有任何消费方会去复核它**：BACKLOG 是 selfdrive 审视环的净拉取源，
下一轮 planner 读到「120 工具」就按 120 的规模决定拆单粒度与门禁强度；而尺面恰好不管这份文件 ⇒
错数只会被继承、不会被抓。改数把这颗雷的引信延长一个版本周期，撤成指针让**唯一真源成为唯一读数来源**，
代价是读者要多跳一次——对一个消费者是 AI 的仓库，多一跳比多一次错判便宜。

## 遗留风险
1. 计数面仍**无人扫 BACKLOG**：本单撤掉了陈旧断言，但没有尺保证以后没人再往这一行抄数。
   可做的判据是「BACKLOG.md 现状段里出现 `N 工具` / `N 测试` 字面量即红，除非该行同时点名真源」——
   这是新格，受 `check_battery_count_doc` X5（登记 60 / 现读 63）的红面牵连，**本单不开新格**，写在这里给下一轮。
2. `docs/polish-plan.md` 标题自述「初稿」快照 148 条测试仍走 EXEMPT 豁免（合法历史数），与本单无关。
3. `check_test_sync.py` 第 88 行的注释把「收窄/放宽正则」显式留给 owner，故 R160 建议的
   「认 `N 项测试` / `N 工具` 形状」那条**本单没做**——那是 owner 的判据影响面决定，不是我该覆盖的车道。
4. 预存红照旧点名不代修：`check_doc_dup`(1) / `check_scripts_index`(1) / `check_battery_count_doc`(1) /
   `check_selftest_inventory_doc`(2) / `check_unit_number_unique`(1，R127/R133 未收紧，属 R134/owner) /
   `check_slave_task_list`(1) / 两份 memory-log 尺在无日记工作树恒 rc=2。

## 建议入档位置
`memory/2026-10-23.md` 同日续段（R160 的后续落账）；若要立 BACKLOG 计数面守卫，挂在 `check_doc_surface` 里加 J 条
比开电池新格便宜（J4 已经证明该尺读得到 BACKLOG.md）。

## 资源消耗
1 份文档改动、6 把尺现读（其中 2 把因缺参数未得结论，已点名）；无网络、无 MoonBit 改动。

## 任务分配记录
指挥官亲自做：对表取真值、判断「撤数 vs 改数」、写自述、终审尺面读数。
**未派 atomcode**：本单的取舍是「这份文件该不该携带计数」，属治理面裁决，不是可外包的执行面。

## 超额内容
无（未动 `check_test_sync` 的正则口径、未开电池新格、未替 owner 收紧任何基线）。

## 来源
`BACKLOG.md` 文首锚点行原文；`scripts/check_tools_sync.py` / `check_doc_surface.py` 现读；
`reports/2026-10-23-selfdrive-walkthrough-false-green-r160-report.md`（同型处置与"本文不抄数"口径）；
AGENTS.md「已知边界」与账本 BUG-133（native 轨关闭条件）。
