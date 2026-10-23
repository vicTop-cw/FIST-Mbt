# R172 · `fist doctor` 的三层遮罩收口：退出码 / 体检库改道 / 检查 4 闭环（BUG-391、BUG-392、BUG-393 FIXED + BUG-394 立案）

- 轮次：R172（副机自立项，起点是「所有开关开启地 dogfood 自己的 CLI」）
- 分支：`slave/fix/doctor-rc-and-db-isolation-r172`
- 基点：`gitcode/master` = `788c5823`（开工前 fetch 过；现读待合链见「来源」§台账）
- 交付态终读：**见文末「交付态终读（推后补）」**——推分支后重跑权威电池，只有推后读数算数

## 结果摘要

`fist doctor` 是本仓 README/AGENTS 指定给用户的安装自检面，也是 `scripts/blackbox/e2e_irm_line.py` 的 `doctor=0` 判据对象。
一次 dogfooding 把它自己揭出三层问题，本单把三层一起收口，并顺手把"入口与判据的格式缝"立案：

| 编号 | 缺陷 | 状态 | 本单动作 |
|---|---|---|---|
| BUG-391 | `doctor` 出现 `❌` 仍 `rc=0`（`Doctor` 臂从不接 `cli_exit`） | **FIXED** | `run_doctor()` 返回判决 + `Doctor => if !run_doctor() { cli_exit(1) }` + 纯函数 `doctor_failed_count` |
| BUG-392 | 体检库写死相对名，`FIST_DB_PATH` 改道针对它无效，135 KB 库裸落进程 cwd | **FIXED** | 新增纯函数 `doctor_db_path(env_value)`，检查 5 改走它 |
| BUG-393 | 检查 4（七态机闭环）缺 `verify(根)` ⇒ `archive(根)` 必被拒 ⇒ `[4/5]` 恒红；且每步 `Err` 被吞成 `Bool`，只印「闭环失败」 | **FIXED** | 抽成 `doctor_closed_loop() -> Result[Unit, String]`，补 `verify(根)`，`❌` 行打印 `<步名>: <原文>` |
| BUG-394 | 常驻测试入口的汇总行形状（`Total tests N / passed N`）不被 `check_test_sync`/`check_badge` 的 `RX_LOG`（`Total tests: N, passed: N`）读取 | **OPEN** | 只立案并给两条出路，本单不动那一支尺（避开 R178 车道同文件） |

关键读数（全部实测，非自述）：

- `python scripts/moon_test_env.py cmd/cli` → `Total tests 10 / passed 10 / failed 0`
- `python scripts/moon_test_env.py`（全量 JS）→ `Total tests 1415 / passed 1415 / failed 0`
- 修复产物 `node cli.js doctor` → `5/5 checks 通过` / `🎉 全部通过 ✅` / **rc=0**
- 变异对照（同一产物只差 `verify(root)` 那 4 行）→ `❌ [4/5] 七态机闭环失败：archive(root): 仅已完成任务可归档，当前状态: 待验收` / `⚠️ 有 1 项失败` / **rc=1**
- 发货产物 v0.3.10 对照 → 同一条 `4/5 checks 通过 / ⚠️ 有 1 项失败` 而 **rc=0**（BUG-391 的形态实锤）
- 隔离对照 → 修复前 scratch cwd 留 `_fist_doctor_check.db`(135,168 B)；修复后 scratch cwd **为空**，两份库同落 `FIST_DB_PATH` 目录
- 插件态四宿主重投影：`gen_plugins` → `170 工具 / v0.3.10 / BUG-1~394 共 379 条入账：16 待修 / 343 已修 / 11 重复并入 / 9 误报`；`check_plugin_sync` rc=0

## 证据

1. **BUG-391 三档对照**：`/tmp` 空目录里分别跑 `dist/fist-mbt.js doctor`（v0.3.10，发货面）与 `_build/js/release/build/cmd/cli/cli.js doctor`（本单产物）。两条命令的**文本输出**只相差 `[4/5]` 那一行，退出码差在 `0` vs `1` ⇒ 坏的是接线，不是产物/打包。
2. **BUG-392 双目录对照**：`FIST_DB_PATH=<dir>/fist.db` + `cd <scratch>` 跑 doctor，跑完分别 `ls <dir>` 与 `ls <scratch>`。修复后 `<scratch>` 为空、`<dir>` 内同时有 `fist.db` 与 `_fist_doctor_check.db`。
3. **BUG-393 单变量变异**：`cp cmd/cli/main.mbt /tmp/main_r172.bak` → 用行级 CRLF 锚点删掉 `verify(root)` 那 4 行 → `moon build cmd/cli --target js --release` + `patch_esm_main.py` → 跑 doctor 拿到 `archive(root): 仅已完成任务可归档，当前状态: 待验收` 与 rc=1 → 还原 → 重建 → `5/5` / rc=0。这一格同时证两件事：**根因是缺 `verify(根)`**，以及**新的步名面真的能读出是哪一步拦下的**。
4. **demo 臂旁证**：`moon run cmd/cli/main -- demo` 7/7 全绿，其第 7 步本来就是 `verify(根)→archive(根)`；同一探针在 `src/engine/engine_doctor_closed_loop_test.mbt` 里也带 `verify(根)`。⇒ 引擎门（`archive` 前置 `is_completed()`）自洽，只有 doctor 少了一步。
5. **失基分支取证**：`git log --all -S'task_id=root_id' -- cmd/cli/main.mbt` 抓到 `32e9881c`（本机分支 `slave/fix/doctor-check4-root-verify`，2026-10-20），`git branch -a --contains` 显示**只有那一条本地分支**——既未推送也未合入 master ⇒ BUG-393 是"修好又丢"，不是新缺陷。本单把它按当前基点重做并采纳了该分支的"步名上抛"设计。
6. **判据面**：`check_plugin_sync` / `check_bug_reference_integrity`（J1 悬空-注释面 0 条，上限 0）/ `check_doc_surface` / `check_tools_sync` / `check_entry_paths` 全 rc=0；`check_test_sync`（喂归一化日志）rc=0，`PASS … 扫描现状面 136 份文档，23 条声明全部等于实测`；`check_badge` rc=0，`README tests-1415%2F1415 == 实测 1415/1415`。

## 分析

- **两层遮罩是一条链**：BUG-391（rc 撒谎）把 BUG-393（闭环恒红）锁在「绿着没人问」里——`e2e_irm_line.py` 的 `doctor=0` 判据因此是空门，CI/安装线读到的"自检通过"其实是"自检不回话"。只修任一层都会把另一层留在暗处：先修 rc 才会让 `[4/5]` 第一次以红露头，先修闭环则 rc 仍会把下一次回归再次吞掉。本单同批收两层，正是本仓「红着没人读等于没锁」那条定律的对称面。
- **为什么没采用立案时设想的三档契约**（0 全过 / 1 有 `❌` / 2 有跳过）：`e2e_irm_line.py` 逐字要求 `doctor=0`，把"工具链不给量（`open_sqlite` 返回 None）"判成"安装坏了"就是 BUG-142 那格反向的错。所以跳过留在 `0` 档并改印 `⏭️ 有 N 项跳过（不计失败）`，`doctor_failed_count = total - ok - skip` 把"跳过"与"失败"分箱，且这条判决有白盒锁（`run_doctor` 自己要在真引擎上跑，测不到这一格）。
- **为什么判据只修到"跟着改道针走"而不重定义默认面**：BUG-90 定的口径是 `FIST_DB_PATH` 为运维侧改道针（与 `FIST_RUN_CHECK_ALLOW` 同族，调用方传参不能自我扩权）。doctor 的错不在"用了相对名"，而在"显式相对路径绕过了改道针"。没设 env 时体检库仍落 cwd——这与 `SqliteStore::new()` 的默认面同口径，本单不越界改它，并把"探针后删库 + 给 `check_demo_isolation.py` 增『同进程显式路径』一格"如实留在遗留风险里（别只修不锁）。
- **`check_scripts_index` 的 rc=1 与本单无关**（单变量对照）：那 5 份未登记脚本（`check_memory_log_dup.py`/`check_memory_log_dedupe.py`/`check_merge_loss.py`/`tmp_merge_batch.ps1`/`tmp_merge_batch.sh`）**在 `788c5823` 上就存在**，而基点的 `scripts/README.md` 对它们**声明数为 0**（`git show gitcode/master:scripts/README.md | grep -cE …` → `0`）。本单对 `scripts/README.md` 的唯一改动是测试总数那一行（`1 / 1`）。⇒ 预存红，按纪律只点名不代修。

## 交付面

| 文件 | 变更 |
|---|---|
| `cmd/cli/main.mbt` | `Doctor` 臂接 `cli_exit`；`run_doctor() -> Unit` 改 `-> Bool` + `ref_skip` + 汇总三态；检查 4 的 8 层嵌套 match 抽成 `doctor_closed_loop() -> Result[Unit, String]` 并补 `verify(根)`；检查 5 走 `doctor_db_path` |
| `cmd/cli/subcmd.mbt` | 新增 `doctor_failed_count` / `DOCTOR_DB_NAME` / `last_path_sep` / `doctor_db_path`（目标中立块，与 `cli_exit` 的 `#cfg` 腿分离） |
| `cmd/cli/subcmd_wbtest.mbt` | `subcmd-3`（跳过不计失败，5 格）+ `subcmd-4`（改道针派生，6 格，含「纯相对名不许造出 `/_…` 越界路径」反向对照） |
| `memory/bugs.md` | BUG-391/392 转 **FIXED**（处置建议改写为实际修复 + 未覆盖面）、新增 BUG-393 **FIXED**（含失基分支取证）、新增 BUG-394 **OPEN**；批量小记 `### FIXED(2026-10-23T08:38:00Z / BUG-391, BUG-392, BUG-393)` |
| `plugins/**`（8 份） | `gen_plugins.py` 重投影：账本读数 `BUG-1~394 共 379 条 / 16 待修` |
| `AGENTS.md` `ARCHITECTURE.md` `README.md` `README.mbt.md` `README_EN.md` `docs/SOP.md` `docs/agent-map.md` `docs/deliverable.md` `scripts/README.md` `scripts/scoring_rubric.md` `scripts/moon_test_env.py` | 测试总数现状面联动 `1387 → 1415`（23 条声明 + 徽章 + 日志回显行），并把计数所在行的"实测日期/归属"短语一并改正为 2026-10-23 本机 |

历史面**未动**：`reports/2026-10-2*` 与 `dist/fist-mbt.js` 里的 `1387` 保持原样（历史面豁免，改它等于伪造当时的读数）。

## 资源消耗

- 本单会话工具调用约 45 次；`moon build cmd/cli --target js --release` 5 次（含变异对照来回 2 次）、`moon check`/`moon info` 各 1 次、全量 JS 测试 2 次（1414 → 1415，第二次是加 `subcmd-4` 后的权威读数）、判据运行 11 支。
- 时间线：07:57 立案两单 → 08:23 rc 修复实测 → 08:31 体检库改道实测 → 08:36 变异对照 → 08:39 账本 + 插件重投影 → 09:56 测试总数联动 → 09:59 全量读数收口。全程未用 `whisperer --fast`（它会写远端，见记忆）。
- 计算资源全本地，未消耗外部执行器额度；未派子代理（本单是"三层遮罩需同一人串因果"的中任务，按分流树走「子代理=0、指挥官终审+实测」）。

## 任务分配记录

- 指挥官亲自做：意图归并（把"立案"升级为"收口"）、三层因果串联、变异对照设计、账本改写与判据对表。
- 未派发：`cmd/cli` 的 MoonBit 改动需要同一批次内 `moon build` 现场验证，且 BUG-393 的正确形状要靠 `demo` 臂旁证才能定——委派外部执行器（`executor_run`）会把取证留在回执里而不是盘上。
- 主机任务面：WT-05 已由 R158 交付（`check_diff_scope.py`，本基点尚不含，故本单跑它 rc=2「文件不存在」而非判红）；WT-01/MISC-02 归 owner 裁决；WT-03 需 `pwsh`，本机无。

## 遗留风险

1. **`e2e_irm_line.py` 的 `doctor=0` 现在才是真门**：本单之后 `doctor` 的 rc 可信，任何未来把检查项做坏的车道都会在安装线红。这是想要的效果，但它把"曾经空门"变成"从此咬人"——首条红会显得像新问题，实际是遮罩撤除。
2. **BUG-392 的未覆盖面**：未设 `FIST_DB_PATH` 时体检库仍落 cwd；探针结束后不删库。两者本单都只标注不修（默认面口径不该由一支自检改）。
3. **判据缺口仍在**：`check_demo_isolation.py` 只扫 `Popen` spawn 面，看不见"同进程显式路径"这一形状 ⇒ 同类污染再来一次仍无人报。已写进 BUG-392 的收口建议，本单未加那一格。
4. **`moon fmt` 本机量不出来（BUG-388）**：`check_fmt_gate` rc=2 DEGRADED，本单格式是手写对齐（`///|` 块边界、参数换行照现成风格）。格式门权威面仍在 CI（Linux nightly），推后若 CI 红在 fmt，那是本仓已知的世代差，不是新增违例。
5. **`check_scripts_index` rc=1**：基点预存红（成因见「分析」最后一节，本单已给单变量对照），交 owner/那一支车道补登记。
6. **待合链很长**：`gitcode/master` 仍是 `788c5823`，本单与 R145…R178 那批分支同基线。账本面（`memory/bugs.md` 尾部）与文档面（测试总数 1415）是高概率合冲突点——`memory/bugs.md` 的追加面若别人先合，`1415` 这一格必须按合入后的实测重跑（测试数是别人的分支 + 我的分支之和）。

## 后续建议

1. 按 BUG-394 的 A 案（常驻入口补一行机器可读汇总）优先，它不动尺、不与 R178 撞文件；B 案留作那一支合入后的收尾。
2. 给 `check_demo_isolation.py` 增"同进程显式路径"一格：判据形状 = 扫 `open_sqlite(` 的实参是否来自 `SqliteStore::default_db_path()` / `FIST_DB_PATH` 派生，而不是硬编码字面量。
3. 把"失基分支"做成常驻巡检：`git log --all -S<关键改动>` + `git branch -a --contains` 两句话就能抓到"修好又丢"。本单的 BUG-393 就是这一格抓的，值得进 `fist-gate` 的收口面。
4. `doctor` 若要升级三档契约（0/1/2），先改 `e2e_irm_line.py` 的 `doctor=0` 期望，否则会把自己判红——顺序不能反。
5. 主机清单里若要有"CLI 自检面"这一族，`cli_flag_probe.py` 的三档旗与 `doctor` 的 rc 应该并成一格判据（现在只钉了版本旗/帮助旗/未知参数）。

## 超额内容（相对"立案两个缺陷"的原任务）

- 原任务只是把两个 dogfooding 缺陷写进账本；实际交付包含：三缺陷的代码修复 + 一个回归取证（失基分支）+ 一个新立案（BUG-394）+ 11 格白盒锁 + 12 份文档的测试总数联动 + 四宿主插件态两次重投影。
- 未经用户确认未做任何不可逆动作：不删分支、不开/关 MR、不动远端除本单分支的 push 之外。

## 来源

- 代码：`cmd/cli/main.mbt`（`doctor_closed_loop` / `run_doctor` / `Doctor` 臂 / 检查 5）、`cmd/cli/subcmd.mbt`（`doctor_failed_count` / `doctor_db_path` / `last_path_sep` / `DOCTOR_DB_NAME`）、`cmd/cli/subcmd_wbtest.mbt`（subcmd-3/4）
- 账本：`memory/bugs.md` 的 BUG-391 / BUG-392 / BUG-393 / BUG-394 + 批量 `### FIXED(2026-10-23T08:38:00Z / BUG-391, BUG-392, BUG-393)`
- 取证：commit `32e9881c`（本地分支 `slave/fix/doctor-check4-root-verify`，2026-10-20，未推送未合入）；`git show gitcode/master:memory/bugs.md`（BUG-389/390 不在 master，389/390 属别车道）；`scripts/blackbox/e2e_irm_line.py`（`doctor=0` 要求）
- 判据读数：`/tmp/gr_check_*.log`、`/tmp/g2_check_*.log`、`/tmp/mtfull_r172b.log`（全量 1415/1415）
- 当日日志：`memory/2026-10-23.md`（不入库面，见记忆「memory 日日志已不入库」）

## 交付态终读（推后补）

（推分支后重跑权威电池 `python scripts/run_guards.py`，此处只登记推后读数与逐格归因。）
