# BUG-575/576 终审合流批 · 自述滞后残余面 + 计划治理归档分流 · 汇报

- 批次：2026-11-06 统帅终审合流批（本地两笔：`f52b7cba`（21 文件）+ `359b349ec`（删除面补落）·**均未推送**）
- 台账：`memory/bugs.md` BUG-575 / BUG-576（均 medium，本批 OPEN→FIXED 一步到位）；投影现读 `BUG-1~576 共 561 条入账：5 待修 / 515 已修 / 13 重复并入 / 28 误报`
- 判例：`docs/AGENTS-precedents.md` 新增判例-44（worktree 车道基线新鲜度）

## 1. 结果摘要

**BUG-575（§4.1「自述滞后」的残余三面，BUG-574 没修完的那半）**
两处 `pubkey_fp`「死承诺／所有写入点恒传空串／要生效还需登记入口接线」的旧断言早被 S3 第三段的真实写入点证伪；
面向客户端的 `docs/integration/s3-client-bootstrap.md` 仍写「`strict` 本版尚未真正拒绝 ⇒ 效果接近 soft」。
本批只改注释与文档（车道实测 diff 非注释行数 = 0），并**立了甄别式**：现在时否定活接线＝滞后，点名变更史＝准确
——据此判 `engine_bug476_strict_wbtest.mbt` 背景段为准确、不动。`server.mbt` 的 `pubkey_fp` 段改成双向诚实版：
**已接线，但落的不是文档承诺的 `fnv1a64` 指纹而是原始 hex，名字里的 `fp` 是误名**（只说「已接线」就是把旧低估翻成新的高估）。

**BUG-576（计划治理：文档承诺的位置与判据都不存在）**
`docs/plans/README.md:45` 承诺终态计划移入 `archived/` 而该目录此前不存在、P6 对「已驳回」只告警；
`docs/proposals/` 整面不在任何 glob 上（两份提案卡连 YAML 头部都没有）。
落地：`check_plan_location.py` 182→764 行、两面同判、新增 P7 判红 / P8 / P9，四种空宇宙形状 rc=2 自拒；
建 `docs/plans/archived/` 并把被驳回卡**逐字节**搬入（`git hash-object` == 旧 blob，正文 0 改）；
两份提案各 +4 行头部；2 处指针改指新路径不留悬空引用。
**advisory↔failing 的分档按「现网会被打红的份数」定**：整档 TERMINAL 提红会误伤 1 份已有文件（`已推迟` 的 4pools）⇒ 不提；
只提「驳回」一档 ⇒ 搬完现网 0 违例。判据面刻意窄于文档面，并把这条落差与转正路径写进 docstring（不静默）。

## 2. 资源消耗

- 工具面：`Bash`/`Read`/`Grep`/`Write`/`Edit`、`Task*`、`mcp_call`（fist-mbt 连接器）
- fist-mbt 使用面：`store_open(ns=iterate-1106)` → `dag_publish` 根任务 T0（含任务包四项）→ `publish_parallel` 追加 T0r2/T0r3/T0r4 → `dag_ascii` → `agent_acl_grant(commander)` → `claim T0`；`evolve_critic`（L4 放行 · 新颖度 100%）→ `evolve_lesson` 两条（`worktree-lane-baseline` / `battery-vs-lane-concurrency`）
- 子代理：3 条车道（stale-claims 已落地 / pubkey-fp 本批落地 / plan-governance 本批落地）+ 2 条停手或失败（S3 车道按新自检主动停手交回取证；stale_self_claim 车道 model interrupted）
- 判据实测（全部现跑，非抄数）：全量电池 `格数 160（手写 160 + 自动 0）/ 失败 0 / SKIP 0 / 缺执行面 0` `BATTERY RC=0`；
  `moon_test_env.py --target js src/engine src/server` = `Total tests: 977, passed: 977, failed: 0`；
  `check_fmt_gate.py` rc=0；`check_plan_location.py --selftest` 49/49 + 真树 rc=0；
  `check_doc_surface` / `check_tools_sync` / `check_scripts_index` / `check_battery_count_doc`（`rulers=153 ci=48 battery=113` 逐键不变）/
  `check_hardcoded_paths` / `check_selftest_hermetic` / `check_bug_ledger_shape` / `check_plugin_sync` 全 rc=0

## 3. 任务分配记录

| 车道 | 结果 |
|---|---|
| lane-stale-claims（BUG-574 两处） | 终审通过，已落地 `dcea736c5`（上一批） |
| lane-pubkey-fp（三处 + 一处判定为准确） | 本批落地；车道边界外发现的 `server.mbt:7734` 工具描述串另挂 T0r3 |
| lane-plan-governance | 本批落地；其「暂时性棘轮超限」预警在 `check_publish_payload` 上如实兑现（rc=1→add 后 0） |
| lane-stale-S3（工具描述串） | **按新派单自检主动停手**（基线落后 216 笔）并交回可用取证 ⇒ 判例-44 的正向实证 |
| lane-check-stale-self-claim | model interrupted 未完成；旧基线参照稿在 `14fed5fe` |

## 4. 遗留风险

1. **`server.mbt:7734` 工具描述串仍写「需走轮换，尚未实现」**：它是运行时代码串、随 `dist/fist-mbt.js` 发货、
   每个客户端 `tools/list` 都读到；纯散文判据对它全盲，J9 只审返回契约不审叙事时态 ⇒ 两面缝里没人认领（挂 T0r3）。
2. **本批的文档面断言否决**：任务书写「`reserve_scope`/`lock_acquire` 重放不拦 ⇒ 改成都拦」，我按现读
   `judged_role_with_nonce` 调用点 = 2（非任务书假设的 3）触发 fail-closed，**该文件零写入**。
   这一行仍未改，需要按真调用点重测后再定；宁可留一条已知滞后，不写一条没测过的主张。
3. **`archived/` 是完全不进判定面的墓地**：「把红卡片塞进 archived/ 就静音」在这一面可做到；堵它需给 archived/
   开「头部仍可解析但不判位置」的次级面。两侧墓地也不统一（plans→`plans/archived/`，proposals→`docs/archive/`）。
4. **`check_plan_landing.py` 那一瞬间的棘轮超限**（26 > 26 基线，多出的正是搬入的 `[on-disk]` 条目）随本批 `git add`
   自然回到基线；它是 known-red 格、rc 不变，不构成本批红。
5. **统帅自造并发风险（已立 lesson）**：我把三条车道（含跑 `moon check`/`moon fmt` 的）与 9 分钟全量电池并发跑，
   电池在第 87 格后输出冻结 3+ 分钟——这份读数仍收绿，但**顺序错了**：应当先派完车道、再起电池。
6. **本地领先 `origin/main` 约 41 笔未推送**（owner 红线；推送后按 40 位全 SHA 逐条核双臂 CI，
   staleness 判据只扫 `gitcode/main`，推送前本地红是预期）。

## 5. 后续建议

- 把「worktree 车道起手自检基线」从纪律升级成**硬门**（`git rev-list --left-right --count HEAD...main` 非 `N 0` 即退出）：
  本轮 7 个 worktree 全钉在同一个过期切点，说明靠人记得跑不成立（S3 车道原话）。
- 收 `check_stale_self_claim`（T0 主线）：它能把本批两类形状（注释滞后 / 描述串滞后）钉成常驻门；
  注意与既有 J 规则的缝——工具描述面需要单独取数，别复用文档面解析。
- `docs/plans/README.md:45` 应补一句「尺子现硬判『驳回』一档，推迟/完成仍告警」，否则下一位读文档会以为三档都已拦。

## 6. 超额内容

- 落地时发现并当场修掉一处**合流形状缺陷**：pathspec 式提交对 rename（旧路径删除 + 新路径新增）只落了新增那一半，
  HEAD 一度同时存有两份被驳回卡——`359b349ec` 补上删除面并 `git ls-tree` 双面核对；该形状已写进提交消息（判据未覆盖，属流程债）。
- 两条 lesson 经 `evolve_critic` 查重后入库（新颖度 100% / L4 放行），并为本批建了 fist-mbt 真任务树
  （ns `iterate-1106`，T0 + T0r2/T0r3/T0r4，T0 已 claim）——任务台账不再是会话内的临时表。

## 7. 来源

- `memory/bugs.md` BUG-575 / BUG-576 及其 `### FIXED` 证据段；`docs/AGENTS-precedents.md` 判例-44
- 三条车道回传原文（逐字 before/after + 各自实测读数）；`temp/lane-pubkey.patch` / `temp/lane42.patch`（合流用补丁）
- §2 所列判据当跑结果；全量电池日志 `temp/battery-574.log`
- fist-mbt 连接器现读：`status_summary`（`total_tasks: 0` ⇒ 本会话此前未走流水线，本批补上）/ `dag_ascii` / `evolve_critic` / `evolve_lesson`
