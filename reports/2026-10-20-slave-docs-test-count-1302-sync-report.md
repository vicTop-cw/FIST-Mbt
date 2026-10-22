# 2026-10-20 · slave/docs/test-count-1302-sync · 现状面文档收口（测试数 1302 / 判据自检 / SOP 入口）

## 结果摘要

一发 PR 关掉三支**从未在现状面判过东西**的守卫：`check_test_sync`（121 份现状文档）、它自己的 `--selftest`（CI `ci.yml:99`，在 HEAD 上恒红）、`check_entry_paths`（`ci.yml:156`，SOP 指退役入口）。基点 `34ce658` = gitcode/master tip。

| 面 | 改前 | 改后（本机 rc） |
|---|---|---|
| 现状面声明 | 三套旧数并存：1058 / 1112 / 1260，另有徽章 1108 | 9 份文档 18 行 + 2 枚徽章 → 1302/1302 ⇒ rc=0 |
| `check_test_sync --selftest` | **rc=2**（HEAD 上就坏，8 个对照变体一个没跑） | rc=0 `SELFTEST PASS 8 个变体` |
| `check_badge README.md` | rc=1 `BADGE-STALE 1108 ≠ 1302` + `SELFCHECK-STALE` | rc=0（徽章面与自检注释面双 PASS） |
| cl7 插件态三支 | rc=1（13 文件漂移，含 README 本身） | 重生成后 `--check` / `--selftest` / `check_plugin_sync` 三支 rc=0 |
| `check_entry_paths`（SOP 的退役入口） | **rc=1** `R1 docs/SOP.md:44 引用退役入口 cmd/main` | rc=0 `PASS R1 退役入口引用 0 处…`（BUG-341） |

实测真源：`moon test --target js -j 1` = `Total tests: 1302, passed: 1302, failed: 0`（BUG-329 打通工具链后本仓第一次拿到这条基线）。

账本：BUG-339（现状面三套旧数并存，high，FIXED）、BUG-340（判据自检门在 HEAD 恒红，medium，FIXED）、BUG-341（SOP 部署路径指退役入口，medium，FIXED），各带 `### FIXED(...)` 小记——`gen_plugins` 的「标 FIXED 必须有小记点名」这条硬门已过。

## 证据

1. 判据读数逐字：`PASS 测试总数单一真源一致：实测 1302；扫描现状面 121 份文档，17 条声明全部等于实测；must-carry 5 份齐全；豁免 22 条全部有效`；改前同一命令是 `FAIL … 0 条声明一致` + 24 条 R1 + 5 条 R2 + 1 条 R3。
2. BUG-340 的取证法是把 HEAD 版本抽出来单跑：`git show HEAD:scripts/check_test_sync.py > temp/cts_head.py && python temp/cts_head.py --selftest` → rc=2，红话点名 5 条「豁免条目已失效」（BACKLOG 807、BACKLOG 50、atgc-selfdrive-demo 807、evolve 807、F094 的 12），逐字与我改后的红话同形 ⇒ 判定为既存缺陷，不是本轮引入。
3. 为什么不是「改改文档就好」：`selftest()` 的注释（行 280/291）写明 EXEMPT 表每一条必须在手写夹具里各有声明，否则 R4 判失效；`baseline-clean` 不绿时 `selftest()` 直接 `return 2`，后面的 R1/R2/R3/R4/假阳性/「自洽的谎」/D-日志回显 7 个变体全部不执行。这就是「现状面守卫的绿没有自检背书」的确切含义。
4. 夹具补齐 8 条声明（BACKLOG 两行、atgc、evolve、F094、SHIP-PLAN、README 一行同载 77 与 162），**没有**动 `judge()`、正则或退出码口径 ⇒ 判据范围自述与实现仍一致。
5. cl7 投影内容实测差异：`version=0.3.8 → 0.3.9`（真源 `moon.mod`）与 `ledger=BUG-1~323 共 323 条：12 待修/290 已修 → BUG-1~341 共 326 条：10 待修/295 已修`（最终态；每追加一条 FIXED 都须再重生成一次，本轮共两次）。
6. BUG-341 的取证与分辨：`check_entry_paths` 的红落在 `docs/SOP.md:44`，而 `git diff --stat -- docs/SOP.md` 显示本轮只改了 :38 一行，`cmd/main` 字样在 HEAD 的 SOP 里已在 ⇒ 既存红。修法只换路径不动工序（`patch_esm_main.py` → Copy-Item 到 AppData 保留），因为真源清单里 `cmd/main` 已退役、`build_release.ps1` 走的是 `cmd/cli`。

## 分析

- 三套旧数并存不是疏忽叠加，而是**扫描面口径**问题：旧文档同步是逐份手改，`check_test_sync` 的 R3（现状面必须至少命中一条等于实测的声明）本就是为这种形状设计，但它自己的自检坏了 ⇒ 这道门形同虚设一整轮。本轮把自检与现状面同时修绿，才是这条链路的闭环。
- 「合法历史数」与「落后的现状数」的分辨标准是**同格是否自带日期或是否局部读数**：`README.md` 的 `77/77` 挂在「开发进度」表 M8（2026-09）行、`162/162` 是 `moon test --target js src/engine` 单包读数、SHIP-PLAN 的 `1058` 在自述「2026-09-28 实量」的审计节里。三者按 docstring 规定登记 EXEMPT；把它们改成 1302 等于伪造一次当时没发生的测量——那才是真的「文档即实现倒退」。
- 本轮第二次在现场复现 BUG-337 的结构：投影嵌 `moon.mod 版本 + 账本状态计数`，所以**只动台账或只动 README 的 PR 必然让 cl7 重新漂**。我在本 PR 内自带重生成（13 文件）把门修绿，代价是与 `slave/misc/plugin-state-sync` 那发在同一批文件上必然冲突。

## 任务分配记录（金条四）

- 指挥官亲自做：判据读数取证（HEAD 抽版本单跑这一格必须亲自确认，否则会把既存缺陷认领成自己的）、EXEMPT 逐条性质分类（改 vs 登记）、夹具补齐、cl7 重生成与三支复跑、账本与日志/报告。
- 未下发子代理：本单是「一份实测数 + 一组机械替换 + 一支判据自检修复」，边界小且要求逐字读数可回溯，并行的协调成本高于收益。
- 不可逆面：本 PR 只推分支、不合并、不动 CI 配置；合并与主干写权仍在用户。

## 资源消耗

- `moon test --target js -j 1` 一次**未重跑**：本轮复用前一轮的真源日志 `temp/test_run1.utf8.txt`（该数已被 `-j 1` 串行复验过）。Python 判据 22 次调用（现状面/selftest/badge/tools_sync/entry_paths/doc_surface 各含对照，加 `gen_plugins` 的生成 + `--check` + `--selftest` 共 4 轮、`check_plugin_sync` ×2）；辅助 grep/read 约 20 次，含把 HEAD 版判据抽出来单跑那一次。
- 改动面：10 份文档（含 `docs/SOP.md`）+ `scripts/check_test_sync.py` + 13 份插件态投影 + 账本 3 条 + 当日日志 + 本报告；零 MoonBit 业务码改动，故 `moon check` / `moon test` 未重跑（无源码面，读数仍取前一轮真源日志）。
- 零提交副作用：`temp/` 下 8 个临时件（`sync_docs.py`、`add_exempt.py`、`fix_fixture.py`、`cts_head.py` 与 4 份判据日志）全部在 gitignore 内，未进提交。

## 遗留风险

1. 本 PR 交出时仍有两格门是红的，都非本单引入、也都不在本单边界：① `ci.yml:116` `check_doc_surface.py` rc=1 `USAGE.md 自述版本 0.3.8 != moon.mod 0.3.9`（BUG-326 那一族）；② `ci.yml:103` `check_scripts_index.py` rc=1 `run_check_t0r21.py 未在 scripts/README.md 登记`（BUG-327 那一族；`git ls-files` 已确认该脚本在 HEAD 就入库）。只如实标注，不顺手改。
   注：BUG-341 那格（SOP 退役入口）与它们同型，但因为它落在**本 PR 已经在改的同一份文档**、且修法是路径逐字对齐真源清单，才并进来一起做；判断依据写在「证据」第 6 条。
2. cl7 冲突面：本 PR 自带 13 份投影重生成，与 `slave/misc/plugin-state-sync` 改的是同一批文件。两支不可能都干净落地，见「后续建议」第 1 条。
3. `memory/2026-10-20.md` 与 `slave/memory/skill-inject-ci-face` 的新建同名文件是 add/add 冲突（金条五规定的文件名，不能改名回避）。
4. 本机副作用如实记：`~/.moon/lib/core/_build/js/release/bundle/core.core` 是本轮工具链可用的前提，属机器级产物、不在任何 PR 里；换机或重装工具链后需按 BUG-329 的 3 步配方重做。

## 后续建议

1. **合并顺序有硬约束**：涉及投影的分支按「文档/代码 → 台账 → `plugin-state-sync`」的顺序合，最后合的那发负责重生成一次并把 cl7 留在绿态；若采纳 BUG-337 的备选方案（CI 里重生成 + `git diff --exit-code`），这条约束就自动消解，不再需要人排顺序。
2. `memory/2026-10-20.md` 的 add/add 冲突建议这样解：保留两份叙述、按小时分节（本分支那条题为「现状面测试总数收口…」，另一支题为「判据可达性取证…」），不要为一场冲突删掉任何一格的读数。
3. 建议给 `check_test_sync` 的 docstring 补一句**登记规程**：「新增 EXEMPT 必须同时在 `selftest()` 夹具里补一条对应声明，否则 `--selftest` 判 baseline-clean 不绿」。本轮 BUG-340 的根因就是这条约束只写在代码注释里、没写在契约里，下一批登记仍会撞。
4. 零 WARNING 这条目标仍未达成，且现在才可测量：`moon check` 报 1920 warnings / 0 errors，族谱已在账本记为 deprecated 904、test_unqualified_package 803、implicit_impl_as_method 63 等。建议按族下发，一支 PR 清一族（先 `unused_*` 与 `reserved_keyword` 这类低风险族，再碰 `deprecated` 904），别在一发 PR 里混清。

## 超额内容

- 多做的三格都为本单结论服务：① 把 HEAD 版本抽出来单跑（不这么做就会误认领既存缺陷）；② cl7 重生成（不动它，本 PR 自己就把 `ci.yml:108` 判红，「提交面无红」这条宣称不成立）；③ 守卫族全量复跑一遍（不这么跑就逮不到 BUG-341，`ci.yml:156` 会继续以「文档面守卫」的名义红着而无人归因）。
- 无扩张：未改判据口径、未动 CI、未动 MoonBit 源码、未清 `.db`/USAGE.md 那些别人名下的面。

## 来源

- 判据实现与契约：`scripts/check_test_sync.py`（docstring 的 R1/R2/R3/R4 与「历史数必须逐条点名」、`EXEMPT` 表、`selftest()` 夹具与 `baseline-clean` 早退）；`scripts/check_badge.py:24-88`（徽章面 + `# → Total tests:` 自检注释面）；`scripts/check_entry_paths.py`（退役入口 R1 / 缺 serve R2）。
- 流水线：`.github/workflows/ci.yml:87`（badge）、`:95`（现状面）、`:99`（selftest）、`:103`（scripts_index）、`:108-110`（cl7 三支）、`:116`（doc_surface）、`:155-156`（entry_paths）。
- 文档面：`README.md:8/13/35/106/222`、`README_EN.md:9/14/26/110/112/131`、`AGENTS.md:105`、`ARCHITECTURE.md:81`、`README.mbt.md:9`、`docs/SOP.md:38/44`、`docs/agent-map.md:10`、`docs/deliverable.md:18`、`scripts/scoring_rubric.md:8`、`docs/SHIP-PLAN-BLACKBOX-v2.md:34/219/377`。
- 账本：BUG-339 / BUG-340 / BUG-341（本单三条 FIXED）、BUG-329（工具链前提与实测基线来源）、BUG-328（0.10.16 迁移那一支；1302 是其后的现状面实测，与文档旧值 1112/1260 之差本轮**未逐笔归因**，只认定「现状面从未跟上」这一条）、BUG-337（投影结构，本单第二次现场复现）、BUG-326（USAGE.md 版本面，本单未动）、BUG-338（同族「判据在场但从不判」）。
- 实测日志：`temp/test_run1.utf8.txt`（`Total tests: 1302, passed: 1302, failed: 0`）。
