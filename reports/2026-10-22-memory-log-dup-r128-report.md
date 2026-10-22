# 交付报告 · 当日日志整块重复守卫 + 无损去重（R128）

- 日期：2026-10-22
- 分支：`slave/fix/memory-log-dup-r128`
- 基点：`dcefdeb8`（交单时现读 `gitcode/master`；R123 / R124 / R125 三条均已并线）
- 提交：`b1a401cf`（新尺 + 两份日志无损修复 + README 条目与电池两格 + 登记锚点 + 当日日志段）+ 本报告所在提交
- 性质：副机自立项（现读主仓盘面时发现，非主机任务池指派）
- 单位编号：**一天三次撞号，每次都让号**。开工时现读 R122 空闲 ⇒ 命名 R122；交单前复核被在飞支 `slave/docs/slave-tasks-reconcile-r122` 取走 ⇒ 改 R123；切到 `5666efbc` 复核，R123 已被**已并线**的 `slave/fix/backlog-stale-branch-r123` 取走、R124 被在飞支占 ⇒ 改 R125；切到 `ede53f30` 后再次复核，**R125 已被并发 agent 的 `slave/fix/moon-spawn-shim-r125` 取走并已并入主线（就是本单的基点 `dcefdeb8`），R126 / R127 又各有在飞支** ⇒ 本单终取 **R128**（三面现读全空：远端分支名 / 主线 `reports/` / 当日日志与 `BACKLOG.md` 文本）。`git grep R128` 命中的只有 2026-10-15「四模式流水线自我迭代 roundNNN」旧系列的引用，与本轮次编号不是同一根数轴——这一族编号需要认领面这件事写进「后续建议」第 1 条。

## 结果摘要

1. **立新尺 `scripts/check_memory_log_dup.py`**（332 行）：被检面 `memory/**/YYYY-MM-DD.md`（金条五的追加面）。判据 D1 = 同一份日志里**逐字相同的 `## ` 块 ≥2 份** ⇒ 违例。抬头同、正文不同只作诊断不判红——删任一份就是删信息，本尺无权那么判；而 union 式「两边都保留」的解冲突留下的恰好是整块逐字复制，判这一形既抓得住成因，又允许修复无损。
2. **同批无损修复两份重灾日志**（基点 `dcefdeb8` 的现读尺寸）：`memory/2026-10-22.md` 91,870,860 → 244,628 字节（块 25769 → 53；并入本单日志段后 250,204 字节 / CR==LF==1102），`memory/2026-10-21.md` 1,209,035 → 334,027 字节（块 319 → 100）。两份修复前合计 93,079,895 字节里 **98.8% 是同一块的副本字节**（91,073,300 + 868,966 = 91,942,266），删除的逐字重复副本共 **25935 份**（25716 + 219）；单块最多被复制 1155 份。落盘 diff 现读 `+1017 / −533696` 行。
3. **同一份日志在同一天里给出六个基点读数**（本单最强论据，提交数与合并数分别由 `git rev-list --count` / `--count --merges` 现读，不拿提交数冒充合并数）：`ccca1db6` 3434 块 / 12.24 MB → `a522b6e6`（其后 11 个提交 / 4 次合并）5151 块 / 18.37 MB → `cd697333`（再 14 个提交 / 5 次合并）8588 块 / 30,619,058 字节 → `5666efbc`（再 6 个提交 / 1 次合并）仍 8588 块 / 30,621,219 字节 → `ede53f30`（再 16 个提交 / 7 次合并）**25768 块 / 91,868,987 字节** → 交单终基点 `dcefdeb8`（再 3 个提交 / 1 次合并）25769 块 / 91,870,860 字节，唯一内容始终只有 53 种 ⇒ 体积随合并次数单调增长、没有上限，且 `5666efbc → ede53f30` 那一步（7 次合并）把体积从 30.6 MB 直接吹到 91.9 MB。只手工删一次而不立常驻判据，下一轮合并就会吹回来。
4. **执行面与登记同批落**：`run_guards.py` 挂两格（裸跑 + `--selftest`），`scripts/README.md` 的 `BATTERY-REGISTRATION` 锚点同批 `rulers=88 ci=41 battery=50 missing=0 gate=58 exempt=27 unclassified=5` → `rulers=89 ci=41 battery=51 missing=0 gate=59 exempt=27 unclassified=5`（现读 `python scripts/run_guards.py --list`，增量恰好等于本单新增的那一把尺）；条目正文的 `--selftest 13 格` 自述由 `check_selftest_inventory_doc.py` 与实现反解行对表（该守卫本单现读判定族 44 条）。
5. **退出码契约按 BUG-369 执行**：0=无违例 / 1=有逐字重复块 / 2=判据无法自证（宇宙为空、或全部日志解析不到块）/ 4=尺子自己坏了。空面（整篇叙事文法的日志，真例 `memory/2026-10-10.md`）不判红但必须点名，也不许掩护另一面的真违例。

## 证据

| 项 | 读数 |
|---|---|
| 修复前违例规模 | `MEMLOG=violate 违例 89 条（逐字相同的块重复=89 族 / 日志 22 份）`；`2026-10-22.md` 块 25769 / 唯一 53 / 重复族 47 / 同抬头多正文 5 / 重复占 91,073,300 字节；`2026-10-21.md` 块 319 / 唯一 100 / 重复族 42 / 同抬头多正文 38 / 重复占 868,966 字节 |
| 无损对表（三面对照全等） | 唯一块集合相同=True、行集合相同=True、preamble 相同=True（两份各自），`LOSSLESS=OK`；删除的 25935 份逐字等于各自保留份（同批快照 `~/r128_before.json` / `~/r128_after.json`，仓外） |
| 修复后现状面 | `MEMLOG=clean 日志 22 份 / 块 563 份逐一对表无逐字重复（空面 1 份已点名）`，rc=0 |
| 本尺自检 | `SELFTEST OK（13 格：S1×1 / … / S13×1，清单从已执行格子反解，不手写计数）`，rc=0。修复前同一命令 rc=1，红在 S9「真源现状面必须绿」那一格——这一格是活格，本尺不是装饰 |
| 登记与普查守卫（全部 rc=0） | `check_battery_count_doc`（逐键一致 89/41/51/0/59/27/5）；`check_selftest_inventory_doc`（INVENTORY_SYNC=clean 判定族 44 条）；`check_scripts_index`；`check_doc_surface`（170 工具逐个可查、自述版本 0.3.10）；`check_py_stdout_encoding`（该带闸 41 / 已带 41）；`check_doc_dup`（`scripts/README.md` 1147 行无重复长条目）；`check_text_control_chars`；`blackbox/check_merge_markers`（1350 个跟踪文件无冲突标记） |
| EOL 与字节面 | 修复后 `2026-10-21.md` CR==LF==1938、`2026-10-22.md`（并入本单日志段后）CR==LF==1102、`scripts/README.md` CR==LF==1147、`scripts/run_guards.py`（含本单 7 行）CR==LF==943；四份除 0x0d 外 C0 控制字节逐字节实测 0 个；两端都以换行收尾 ⇒ 追加不产生「删除」行 |
| 电池（报告提交前） | 格数 68（手写 68 + 自动 0）/ 失败 1 / SKIP 5 / 缺执行面 0，rc=1（日志 `~/r128_battery2.log`，仓外）。唯一 FAIL = `check_delivery_gap.py` rc=1（`HEAD 领先、pushed=False` 的如实读数），推送即消 |
| 预存红（不代修，照实点名 rc 与成因） | 四条都在电池里以 `expected()` 形式显示为 PASS，非本单引入：`check_ci_step_position.py` rc=1（棘轮超限 35 > 34，只许降）、其 `--selftest` rc=2（T9 真源现状 rc=1 不在棘轮上限内）、`check_scripts_naming.py` rc=1（判定面 2 条 > 棘轮上限）、`fist-gate.py` rc=2（成因现读为 `DEGRADED fmt: 格式化器未预热（缺 _build/wasm-gc/release/format/）`，本机 moon 工具链状态，不是代码红）。**上一基点的红一条已自行结清**：`check_backlog_status_staleness.py` 在 `dcefdeb8` 现读 rc=0（`落差 0 条 <= 上限 0`），主线把 TASK-013 的 status 改真了，本单不再代它记账 |
| SKIP 明细（不构成「这格过了」的证据） | 5 格全部因缺 `temp/pt27.log`、`temp/chk47.json` 前置（历史一次性进料件），与本单无关 |
| 根因取证 | `.gitattributes` 无 `merge=union`；`git check-attr -a memory/2026-10-22.md` 空 ⇒ 重复来自「解冲突时两侧都留」的操作习惯，不是仓库配置；`core.autocrlf=true` 只解释盘上字节 > blob 字节（`dcefdeb8` 的 blob 实测 91,342,559 字节 vs 盘上 91,870,860），与重复无关 |
| 本单自伤事故（已恢复，如实入账） | 一次仓外补丁脚本先用通用换行 `read()` 把 CRLF 拍平、再按 `\r\n` 切行做过滤 ⇒ 整份 `scripts/run_guards.py` 被写成 **0 字节**；靠 `git checkout -- scripts/run_guards.py` 无损还原（当时该文件除我的 7 行插入外无其他改动），随后用 `newline=''` 读写 + `crlf==lf` 断言重做。本单的每一次仓外改写都带 `len>200` 与 `crlf==lf` 两道自断言：`ast.parse` 对空文件也返回 OK，不能当存活证明 |

## 资源消耗

- 会话：副机单会话；主要开销在 91 MB 级日志的读写（修复前后各一次全量解析 × 本基点，另五基点各一次）与全量电池复跑两遍（68 格）。
- 网络：`git fetch gitcode master` 六次；基点六次换代 `7b1dba95`→`ccca1db6`→`a522b6e6`→`cd697333`→`5666efbc`→`ede53f30`→`dcefdeb8`，其中本单实现面在六个基点上各做了一遍；`ls-remote --heads` 复核编号占用 × 4。
- 工具链：只用 python（本单不碰 `.mbt`，故 `moon fmt / moon test / moon check` 面不涉及；本机 `moon fmt` 仍 rc=127、`fist-gate` 的 fmt 段恒 DEGRADED，与本单无关）。电池日志、无损快照、`FIST_DB_PATH` 全部落仓外（`~/r128_*`、`~/fist_r128.db`、`~/fist_r128b.db`）。
- 写盘范围：新增 `scripts/check_memory_log_dup.py` + 本报告；修改 `memory/2026-10-21.md`、`memory/2026-10-22.md`（去重 + 本单日志段）、`scripts/README.md`（条目 + 锚点）、`scripts/run_guards.py`（两格）。未动 `src/`、未动 CI workflow、未动插件态与账本 `memory/bugs.md`。

## 任务分配记录

- 本单为副机自立项，指挥官侧未做递归拆解（单文件新增 + 同批登记，属轻/中任务边界内的直做面）。
- 与并发 agent 的隔离：交单前现读 `gitcode/master` 与 `ls-remote --heads`。文件作用域与本日在飞支只可能在 `memory/2026-10-22.md` 的尾追加处相遇；`scripts/README.md` 与 `scripts/run_guards.py` 与 R121 / R123 / R124 / R125（均已并线）同文件不同段，重贴后逐格复跑确认。
- **重切支五次**（`ccca1db6` → `a522b6e6` → `cd697333` → `5666efbc` → `ede53f30` → `dcefdeb8`）：每次走「先把未并线面备份到仓外 → `git checkout -B` 到新 tip → `--fix` 幂等重跑 → 锚点与全部读数重测」，没有手工解过一次那 53 万行日志冲突；报告里没有一处抄旧值。

## 遗留风险

1. **合并顺序风险（本单最大的一条）**：`memory/2026-10-22.md` 本单 diff 现读 `−527618 / +419` 行，任何在飞支往同一文件尾追加新段都会在追加处与「我删掉的副本」相遇。建议**先合本支**，在飞支随后在去重后的日志上重贴自己那一段；若反过来先合在飞支，本支需要重跑一次 `--fix`（幂等，已在本日六个基点上各验一次），不要手工解。
2. **只判「逐字相同」的沉默面**：同抬头、正文不同的块（本单读数 5 / 38 族）本尺只出诊断不判红。这是为了让 `--fix` 保证无损而做的设计取舍——代价是「同一结论被改写成两份」不会被拦住。
3. **根因不在尺子上**：重复来自解冲突习惯，本尺只保证「再长回来会红」。若日后有人改用 `merge=union`，本尺会立刻红，但 git 层的做法仍需 owner 决定。
4. **修复不覆盖历史归档面**：`memory/archive/` 与 `reports/` 不在被检面内（日志宇宙按文件名 `YYYY-MM-DD.md` 收）；未测这两面是否也有同形毁伤，不据本单读数宣称「仓内重复已清」。
5. **本尺读数依赖盘上字节**：`core.autocrlf=true` 下工作树是 CRLF、blob 是 LF（本基点该文件 blob 91,342,559 vs 盘上 91,870,860），报告里的修复前后读数都是工作树现读。跨面比数先核对这一条，否则会把 EOL 差读成内容差。
6. **R126 / R127 两条在飞支与本单同文件面**：`slave/fix/mcp-server-moon-env-r126`、`slave/fix/issue-scan-prefix-guard-r127` 若先并线，本支的 `scripts/README.md` 锚点与 `run_guards.py` 位置都要重测——锚点是现读派生的，重测是机械动作，但不是零成本。

## 后续建议

1. **轮次编号要有认领面，不能靠快照**：本单实测一天三次撞号（R122 被在飞支取走、R123 被已并线支取走、R125 被并发 agent 并线取走，且 R126 / R127 在我复核时已在飞）。建议把轮次号纳入 `reserve_scope` / 任务池认领，或新增一把「`reports/*-rNNN-report.md` + 当日日志抬头 + 远端分支名」三面唯一性尺，撞号即红——这比多写一条纪律条文便宜且常驻。附带一格：`git grep R128` 撞到的是 2026-10-15「四模式流水线自我迭代 roundNNN」旧系列，两条数轴共用 `R\d+` 字面形状，新尺要判红必须先分区。
2. 把本尺接进 `fist-gate.py` 门禁链——当日日志是 AI 每轮必读的注入面，体积失控的代价是每轮上下文；属门禁强度变更，留给 owner，本单不自作主张加段。
3. 「同抬头多正文」若要判红，需要另立无损口径（例如只出清单不删），不要塞进本尺 D1。
4. 若要根治而非兜底，下一单应改的是**合入流程**（`slave-branch-merge.ps1` / whisperer 的解冲突分支对 `memory/*.md` 应走专用路：先合入再重贴，或直接在合入后跑 `python scripts/check_memory_log_dup.py --fix`）。本单六个基点的读数序列就是这条路的报价单。
5. **把「不可测机器」这一档做进电池，别让新尺自带恒红**：`check_fmt_gate.py` 在副机如实返回 `DEGRADED(2)`（本机 moon 的 `moon fmt --check` 管线写 `_build/…/format/` 后比对缺失文件）。`dcefdeb8` 的电池只挂了它的 `--selftest` 一格（`grep -c 'case("check_fmt_gate.py")' scripts/run_guards.py` 现读 = 0，裸跑格不在电池面上），所以本单看不见这一格；但 `cd697333` 基点上它曾是 `exp=0` 的 FAIL ⇒ **一旦有人把裸跑格接回电池，任何 `moon fmt --check` 量不出来的机器都会恒红**。出路是 owner 二选一：按 BUG-388 把这格登记成 `expected(2)` 并写明哪个平台可测，或修工具链让 2 号档不再出现；本单两条都不代做。
6. 当日日志的**注入面体积**值得单独一把尺：本尺判「重复」，不判「总量」。`dcefdeb8` 修复前 25769 块里只有 53 种唯一内容——去重后 53 块 / 244 KB 才是真实信息量。若 owner 愿意，可以加一条「单份日志唯一块字节 > N MB 即预警」的软门，与体积失控对上账。

## 超额内容

- 修掉了自尺内部三处缺陷并各自固化为格子：`scan()` 遇解析为空即 `return`（MB 级违例面会被读成 clean，S10）；把「无 `## ` 块」误判成违例（红在别人的文法上，真例 `memory/2026-10-10.md`，S12/S13 两格钉住分界）；缺 BUG-58/138 的 stdout UTF-8 重配（由电池抓到，不是自查抓到的）。
- 额外取证了根因归属（gitattributes / `check-attr` 排除法 + blob/盘上字节对照），把「配置问题」和「EOL 问题」这两个便宜但错误的答案一起排除在结论之外。
- 三次让号并全批改写文本面（R122 → R123 → R125 → R128），没有留下半改状态；并把本单踩的三条工具坑（管道后 `echo $?` 读的是 `tail` 的 rc、证据脚本复用旧基点快照、仓外补丁毁掉 CRLF 文件写成 0 字节）写进当日日志段，供下一单直接引用。
- 顺手把主线已经自行结清的一条红从「预存红」账上摘掉（`check_backlog_status_staleness` 现读 rc=0），并把 `fist-gate` rc=2 的成因从「既有面」精确到「fmt 段 DEGRADED：格式化器未预热」。
- 未做：不动 `scripts/README.md` 的条目抄本面（归 `check_doc_dup.py`）；不动 `memory/archive/` 与 `reports/`；不改 CI workflow；不改判据强度以外的任何既有尺；不代修四条预存红。

## 来源

- 本单实测读数全部列在「证据」表；命令与 rc 同批记录在会话内，电池日志与无损快照均在仓外（`~/r128_battery.log`、`~/r128_battery2.log`、`~/r128_before.json`、`~/r128_after.json`、`~/r128_scan_before.log`、`~/r128_fix.log`、`~/r128_selftest2.log`、逐守卫日志 `~/r128_<guard>.log`）。
- 分支基点 `dcefdeb8` = 交单时现读 `gitcode/master`；过程存档 `bank/r122-v1`（`ccca1db6` 态）、`bank/r123-v1`（`390b74e0`）、`bank/r123-v2`（`cd697333` 态）、`bank/r125-v3`（`00fc2bde`，尺+报告）、`bank/r125-v4`（`f2f31942`，报告）仅本地留存，不推送。
- 规范依据：`AI-DEVELOPMENT-STANDARD.md` 通用律「增量零回归」「文档即实现」与 BUG-369 退出码契约；金条五（日志追加面）；AGENTS.md「守卫族登记律」。
- 撞号对象原件：`reports/2026-10-22-backlog-stale-branch-r123-report.md`、`reports/2026-10-22-moon-test-env-moonc-shim-r124-report.md`、`reports/2026-10-22-moon-spawn-shim-r125-report.md`（三者均已并线）；在飞支 `slave/fix/mcp-server-moon-env-r126`、`slave/fix/issue-scan-prefix-guard-r127`（`git ls-remote --heads` 现读）。
