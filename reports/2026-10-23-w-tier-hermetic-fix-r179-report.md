# R179 · W 档 hermetic 收口：`check_publish_payload.py` 与 `cleanup_artifacts.py` 改打合成夹具

日期：2026-10-23 · 副机（Fist-Mbt-r179-atom）· 分支 `slave/atomcode/w-tier-hermetic-fix-r179`（链在 R153 tip `54de6d86`）· 验收人：指挥官本人

---

## 一、结果摘要

R153 立起 hermetic 尺后现读 72 处红档（W=10 / R=48 / G=14）。本单收口 W 档里**真的往真树落件**的 8 处，并把这两个文件连带 4 处 R/G 一起清掉——因为修法是让自检不再需要现状面，不是给判据加豁免。

| 面 | 改前 | 改后 | 手段 |
|---|---|---|---|
| hermetic 红档总数 | 72（W=10 / R=48 / G=14，24 把尺） | **60（W=2 / R=46 / G=12，22 把尺）** | 本单两文件 12 处归零 |
| `check_publish_payload.py` | 6W + 1R + 1G | **0 处** | 自检改打 temp 下真 git 仓沙箱；探针名不再进仓根 |
| `cleanup_artifacts.py` | 2W + 1R + 1G | **0 处** | 同上；`_tool_registry.py` 的豁免面对象改成沙箱里的合成件 |
| DIAG 记账档 | 5（T=4 / S=1） | 5（不变） | 本单不碰这两档 |

格子数：`check_publish_payload.py` `--selftest` 4 支 → **8 支**（S0 / M4 / G1 / G2 / M1 / M2 / M3 / M5）；`cleanup_artifacts.py` 6 支 → **7 支 + 1 支变异对照**（S0 / M1 / S1 / S2 / S3 / S4 / S5 / S6）。两把尺的 `--selftest` 与主面全部实测 rc=0，跑完 `git status` 只剩我自己的三个改动文件，零探针残留。

**关键取舍（诚实标注）**：仓根经**必填形参**注入，不走带 `ROOT` 默认值的形参。hermetic 尺的 README 自述明文写着「锚点经函数**默认参**流进读原语不判」——那是它承认的漏红面。用默认参买隔离，读数一样归零，但那是把尺洗白而不是把夹具修好，属本单边界里明令禁止的「放宽尺不算修好」。

---

## 二、验收门逐条实测（C1–C10）

| 门 | 判据 | 实测 | 结论 |
|---|---|---|---|
| C1 | hermetic `[W]` 归零、总数下降由尺自己说 | 现读 60 处 / W=2 / R=46 / G=12；`grep -c "check_publish_payload\|cleanup_artifacts"` = **0** | ✅（优于原计划 72→64：R/G 同面一并消失） |
| C2 | `check_publish_payload.py --selftest` rc=0 且格子不少于改前 | rc=0；8 支（改前 4）；连跑两次同读数 | ✅ |
| C3 | `cleanup_artifacts.py --selftest` rc=0 且格子不少 | rc=0；S0-M1-S1..S6 | ✅ |
| C4 | 主面行为逐字不变 | publish rc=0「将随包公开 1329 件，其中未被 git 跟踪的 0 件（另有 26 件点号条目…）」；文案与旗标未改 | ✅ |
| C5 | 自检跑完真树零残留 | `git status --porcelain` = 3 个 `M`（两份脚本 + README），无 `zz_publish_payload_*`、无 `scripts/_cleanup_selftest_tmp.py` | ✅ |
| C6 | 沙箱形状自证 + 变异对照齐 | S0（tracked 面 + `*.log` 忽略规则各就位）；M4（非 git 仓目录必被 S0 自拒）；cleanup 侧 M1（跟踪面抽空的夹具必被 S0 自拒） | ✅ |
| C7 | `check_unit_number_unique.py` 不因本单多咬 | 违例仍是 2 条（历史 R127 / R133 撞号），R179 号未与之相碰 | ✅ |
| C8 | doc_dup 冗余不升 | 冗余 232 块 / 登记块 343 / 1151 行——与基线逐字同读数 | ✅ |
| C9 | `check_py_stdout_encoding --all` rc=0 | rc=0（CI 面 43/43；两文件保留 BUG-138 那对 reconfigure 闸） | ✅ |
| C10 | `ast.parse` + 脚本单份面 + 电池登记 | 两份 AST OK；`check_battery_count_doc` rc=0；`check_doc_surface` rc=0；`check_scripts_index`  offender 集合未变（本单不新增脚本文件）。注：记忆里那条 `check_script_single_copy.py` 在本基线上不存在（属主机更新车道），已用 `git status` 无新文件替代该证据 | ✅（附注） |

电池（本单**提交前**那一发，权威 push 后读数见 §六）：`格数 77（手写 77 + 自动 0）/ 失败 9 / SKIP 6 / 缺执行面 0 / BATTERY rc=1`。

---

## 三、任务分配记录（含执行器死亡账）

| 单 | 派给 | 内容 | 结果 |
|---|---|---|---|
| R161 | atomcode 外部执行器 | W 档 10 处归零（首选 `whisperer_patrol.py`） | **执行器 0 改动死掉**（6 发 600s 模型超时），且首选目标的立单前提被我自己推翻（见 §四·1）⇒ 整单作废重派为 R179 |
| R179 | atomcode 外部执行器（重派，工作树 `Fist-Mbt-r179-atom`） | `check_publish_payload.py` 6W + `cleanup_artifacts.py` 2W 归零，10 条门 | **执行器再次 0 改动死掉**（同样 600s 超时，死前已完成基线归档与命中定位，其读数与本报告 §一 一致）⇒ 按金条四「指挥官亲自做判据定形」由我本人执行 |
| R179 本体 | 指挥官（本代理） | 夹具设计 + 沙箱自证 + 变异对照 + README 抄本 + 报告 | 本单 |

派给外部执行器的两发都栽在同一档模型侧超时上，但**立单质量是可用的**：执行器留下的基线命中（publish 8 处、cleanup 4 处）与我复测逐条相同，说明任务包的边界与判据没有歧义。连续两发同因死亡 ⇒ 这条车道在 atomcode 侧的可用度需另立单查（不在本单面）。

---

## 四、归因与自我更正（两处）

**1. 「whisperer 自检往任务池写假账」那条 W 档不成立。**
R153 §八·2 原本断言 `whisperer_patrol.py --selftest` 每跑一轮就往 `docs/tasks/backlog/` 落 yaml。仓外快照对照实测（`git archive` 出干净树跑电池前后比 mtime/md5 集合）：`23 份 / 6b4f650a9985 / mtime 逐字节相同`，`real-pool-untouched=True`。静态 `[W]` 命中是保守判定——它运行时用 `globals()["TASKS_DIR"] = tdir` 把真源目录整体换掉再 `finally` 还原，AST 面看不见这层重绑。教训已入副机坑档：**静态命中 ≠ 运行时污染**。因此 W 档的真目标改为本单这两份——它们确实直接写仓根。

**2. 我误跑了一次删除面。**
取证时我跑了不带旗的 `python scripts/cleanup_artifacts.py`（本意是 `--check`），它按契约清掉了 `temp/`，连带删掉我自己归档在 `temp/` 的 5 份 R179 基线件与执行器的任务包。损失面：`temp/` 是 gitignored、无一件被 git 跟踪、无真源损失；hermetic 与判据读数在 `$HOME` 下各有一份副本，本报告的每一条实测都能重放。已把「不带旗那一发是删除面」写进 README 那条自述——这类坑只有写进工具自己的说明才拦得住下一个人。

---

## 五、资源消耗

- turns：本单占目标预算约 4 拍（执行器死亡排查 2 拍、夹具实现与门复跑 2 拍）。
- 墙钟：电池一发约 4–6 分钟（本单跑了 1 次提交前）；hermetic 全树扫描秒级；两次外部执行器各跑了 6 发 600s 超时代价（≈ 无产出消耗，记在执行器侧）。
- 文件面：改动 3 份（`scripts/check_publish_payload.py`、`scripts/cleanup_artifacts.py`、`scripts/README.md`），新增 1 份（本报告）。零删除、零移动、零新增脚本。

---

## 六、遗留风险

1. **权威读数尚未登记**。本单只交「提交前」那一发；按副机律「交付态红不登记期望，只有 push 后读数算数」，push 后的电池读数随交单行给出。
2. **失败 9 条相对 R153 的 8 条 +2/−1，两条新增都不是本单造成的**：`check_memory_log_dedupe.py` 与 `check_memory_log_dup.py` 都 `got=2`（FATAL 扫描面为空——`memory/` 下枚举不到 `YYYY-MM-DD.md`）。根因是 `788c5823` 之后日报不再入库，而本工作树 `F:/AI/Fist-Mbt-r179-atom/memory/` 上没有本地日报；同一把尺在**有**日报的树上 rc=0。⇒ 这两格的红由「工作树有没有一份未跟踪文件」决定，正是 hermetic 律要抓的 R 档形状（也是 §三 H1b 记过的同一族）。−1 那条是 `check_slave_mergeability.py` 的 TIMEOUT 这次没复现（并发跑时才出现，按律不登记）。预存红不代修。
3. **`run_guards.py` 里 hermetic 那格的 `why` 文本仍写「红档 72 处」**，现读 60。该文件同时在 10 条未合车道的改动面里，且这一段本身属 R153 车道 ⇒ 依「不编辑未合并并发工作所属的文件」不在本单改，归 R153 下一次推送收口。
4. **W 档还剩 2 处**（`whisperer_patrol.py`）。它不是「写脏了」而是「靠运行时全局重绑买隔离」——静态不可见意味着将来任何人删掉那层还原，判据不会响。这一岔口（改脚本让隔离静态可见 / 还是让判据认全局重绑）需要设计裁决，不是执行活。
5. **README L807 那句「真树红档 60 处（W=2 / R=46 / G=12，分布在 22 把尺）」是手抄读数**，没有任何常驻判据对表它。写死一个数就是下一颗漂移雷——本仓已经为这类雷返工过一次。

---

## 七、后续建议（按性价比排序）

1. **给 hermetic 尺补「锚点经默认参流进 I/O」那一格**，并配一支自证对照（默认参 = `ROOT` 的读原语调用必须发红）。本单用必填形参绕开了这条漏红面，但漏红面本身仍然开着：任何人把 `scan(root)` 改回 `scan(root=ROOT)` 并让自检不传实参，读数照样「归零」。**这是本单最需要兑现的一条**。
2. R 档 46 / G 档 12 逐条核实归后续单；优先挑「自检 rc 由未跟踪文件决定」那一族（§六·2 是本族第 2、3 条成员），因为它们在最脏的树上给出最像绿的读数。
3. 把 §六·5 的手抄读数改成从尺自己的输出反解（hermetic 已打反解行，README 只指路不抄数）。
4. atomcode 车道在长任务上的 600s 超时需要裁决：是缩短任务包，还是换 `ofm` 通道——连续两发同因死亡不该用「重跑」搪塞。

---

## 八、超额内容（本单多做了一格，已计入验收）

- `G2 带未跟踪件时逐件点名且无幻影红`：旧版这一格寄生在真工作树的脏净上，树干净时整格跳过；换成合成夹具后恒可验，等于把「有时才验」的格子变成常驻。
- `M5 拆件后夹具回到干净形状`：幂等自证——探针没拆干净会喂给后续格子，旧版只复核盘上无残留、不复核判据回到干净读数。
- README 里 `cleanup_artifacts.py` 那条自述补了「不带旗那一发是删除面，先看 `--check` 再跑」。

---

## 九、来源

- 基线读数：`$HOME/r179_scan_before.txt`（72 处）、`$HOME/r179_scan_mid.txt`（64 处，publish_payload 修完后）、`$HOME/r179_scan_after.txt`（60 处）。
- 门读数：`$HOME/r179_check_selftest_inventory_doc.txt`（X4 仍 1 处，未升）、`$HOME/r179_check_doc_dup.txt`（232 块）、`$HOME/r179b_*.txt`（README 改后复跑）。
- 电池：`$HOME/r179_battery_pre.log`（格数 77 / 失败 9 / SKIP 6 / rc=1）；对照基线 `$HOME/battery_r153_post.log`（失败 8）。
- 判据真源：[scripts/check_selftest_hermetic.py](file:///F:/AI/Fist-Mbt-r179-atom/scripts/check_selftest_hermetic.py)（五档分类 L266-301、默认参漏红面自述见其 README 登记条）。
- 被改文件：[scripts/check_publish_payload.py](file:///F:/AI/Fist-Mbt-r179-atom/scripts/check_publish_payload.py)、[scripts/cleanup_artifacts.py](file:///F:/AI/Fist-Mbt-r179-atom/scripts/cleanup_artifacts.py)、[scripts/README.md](file:///F:/AI/Fist-Mbt-r179-atom/scripts/README.md)。
- 上位单：R153 报告 §七/§八（派发的优先级前提与归因两处更正）、R163 报告 §三（归因更正）。
