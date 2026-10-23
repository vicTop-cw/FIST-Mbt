# R153 · 自检 hermetic 守卫（`check_selftest_hermetic.py`）· 报告

- 轮次：**R153**（取号查过五面：远端分支 / `reports/` / 本地分支 / worktree / 当日日报；R152 已被并行 agent 占用，R154 预留给本单派给 atomcode 的那单）
- 基线：`gitcode/master` tip `788c5823`（本分支只动 `scripts/check_selftest_hermetic.py`（新增）、`scripts/run_guards.py`（+2 格）、`scripts/README.md`（新条目 + 锚点））
- 分支：`slave/feat/selftest-hermetic-guard-r153`
- 触发：持续自驱目标 —— R151 那一单查出「`--selftest` 里混真源读」这个形状之后，**没有任何常驻判据扫它**（R151 只治了那一把尺）。本单把那条口径从散文升级成机器判据。

## 一、结果摘要

1. 新增常驻判据 `scripts/check_selftest_hermetic.py`（721 行，AST 静态判定；首版 716 行没带 stdout 编码闸，被自家 `check_py_stdout_encoding --all` 当场判红后补上，见 §六·9）：**`--selftest` 只许合成夹具**；自检体（含其调用闭包）里「锚点/锚点派生局部名流进 I/O 原语（读面 + 写面，含经形参交给同文件 helper 的一跳）」逐条点名。
2. 尺子自己站得住：`--selftest` rc=0，**十六支变异全部被抓**（M1–M16）；本尺扫自己不进红面（夹具落 `tempfile.mkdtemp()`）。
3. 现读把这条口径的**存量债务变成可见**：真树红档 **72 处**（W=10 / R=48 / G=14）＋记账档 **5 处**（T=4 落约定的 gitignored `temp/`、S=1 隔离自 spawn），涉及 **24 份脚本**；其中「锚点经形参流进 helper 的 I/O 原语」这一族 **13 处、7 份脚本**。按本仓律不代修，`expected(..., 1, why=…)` 登记进电池。
4. **同批兑现（顺带结清、不冒充本单功劳）**：`BATTERY-REGISTRATION` 锚点按「新增尺同批改数」更新后，master 上那条预存红归 0 ——
   `check_battery_count_doc.py` 主面 rc=1→**rc=0**，其 `--selftest` rc=1→**rc=0**，`check_selftest_inventory_doc.py` 的 X4 失联面 **2 → 1**。

## 二、机理：为什么「自检读真源」是判据缺陷，而不是风格问题

三条后果链，每条都有实测锚点；第 4 条是立尺过程中撞出来的**判据自己的盲区**，也记在这里：

1. **红的是账，不是尺**。`check_battery_count_doc.py` 的 `R1-real-readme-vs-real-list-green` 拿真 README 对真 `run_guards --list`：锚点一落后，自检就红 —— 仓外 `git archive gitcode/master` 快照实测（基线面）：

   ```
   SELFTEST FAIL: 1/15 格红
     - R1-real-readme-vs-real-list-green：reg={'rulers': 90, …} reading={'rulers': 93, …}
   ```
   读者看到的是「夹具坏了」，实际是「登记落后」。同因两格红（主面 + 自检）在电池里长得像两条债。

2. **判据的消费者被判据自己的自检拖失联**。`check_selftest_inventory_doc.py` 的 X4 定义就是「跑那把尺的 `--selftest` 拿不到反解清单 ⇒ 判据无法自证 ⇒ rc=2」。自检因真源读而红 ⇒ X4 命中 ⇒ 整把尺的族计数对表**从判定面消失**（本轮实测：X4 从 2 处降到 1 处，就是因为锚点先对上）。

3. **自检往真树写探针 = 电池契约被破**。实测 W 档 10 处、三份脚本：`check_publish_payload.py` 的 M1/M2/M3 往**仓根**写 `zz_publish_payload_probe.txt/.log/zz_publish_payload_secret.txt` 再删（写 3 处 + 删 3 处经形参 `_rm(path)` 各点一次名）；`cleanup_artifacts.py` 往 **`scripts/`** 写名为 `tmp_abs` 的探针再 `os.remove`——**变量名像临时、路径是跟踪面**，这一条正是「按名字猜」会漏的形状；`whisperer_patrol.py` 的 `--selftest` 直接调 `write_yaml()` 往 **`docs/tasks/backlog/`** `os.makedirs` + 落 `TASK-*.yaml`（任务池！不是临时区）。前两者是「跑电池时工作树短暂变脏」，第三者是**电池运行会改任务池状态**——下一位取单时看到的账，是上一轮电池写的。（顺带一条因果线索：电池里预存的 `cleanup_artifacts --check rc=1 = 工作树残留` 与该脚本自检往 `scripts/` 写探针同族——本单不代修，只把线索记在这里。）

4. **真源读还能藏在形参后面**（这条是判据第一版的漏红面，实测反证当场逼出第六轮定形）。终审 R154 交付时读到 `check_memory_log_dup.py --selftest` 报 `FAIL S9 仓库内一份日志都没读到`，代码是自检把 `os.path.join(REPO_ROOT, "memory")` 交给 helper `find_logs(base_dir)`，helper 体内 `os.walk`/`os.listdir` 直接读它——锚点经**形参**流入读原语，而第一版把「形参永不污点」写进了漏红面。**这就是 R151 那个形状本体，尺子却看不见它**：漏红的代价不是抽象的。补上调用点级一跳判定（只在该调用点判，同一 helper 别处用 temp 实参调用不受影响）⇒ 红档 59 → 72，其中一跳族 13 处分布在 7 份脚本（另含 `check_bug_refs.py` 的 `load_bug_ids(ROOT / "memory/bugs.md")`、`check_scripts_naming.py` 的 `read_roles(NAMING_DOC)` 等，三条已逐条开原文件核实为真阳）。
   **交单前把「master 上正红」这句重测了一遍，真形状更难看**：同一 commit 的 `--selftest` 在四棵树上给出两种 rc——仓外快照 `snap-r153-base`（`git archive gitcode/master`，盘上没有 `memory/2026-10-23.md`）rc=1、`Fist-Mbt-r154-atom`（同样没有）rc=1，而本工作树 `Fist-Mbt-r153` 与主机 `Fist-Mbt`（本地日报在盘，日报自 `788c5823` 起已不入库）rc=0 并打印 `SELFTEST OK`。单变量对照：在仓外快照手写一份合成当日日志 ⇒ rc 1→0，删掉 ⇒ 0→1。⇒ **这一格的 rc 由一个 git 不跟踪的本地文件决定**，它不是「主线恒红」而是「干净检出/CI 必红、各人本地随缘绿」——不可复现的读数比恒红更糟，因为两态都长得像结论。`FAIL`/`OK` 文本与 rc 严格绑定，先前两次「打印 FAIL 却 rc=0」的疑虑是我把不同树读成了一张表，**不存在假绿**。

## 三、判据（形状如何定形，全由实测逼出）

- **H1 锚点流进 I/O 原语**：锚点种子 = 模块级常量的值表达式引用 `__file__`，沿模块级常量互引传播到不动点；对 `selftest`/`_selftest`/`run_selftest`/`self_test` 的**调用闭包**检查 I/O 原语（读：`open`/`io.open`/`glob`/`listdir`/`walk`/`exists`/`stat`/`subprocess.*`/`read_text`…；写：`shutil.*`/`os.makedirs`/`os.remove`/`Path.write_text`/`Path.mkdir`/open 的 `w`/`a` 模式…）的**参数子树**是否吃进锚点或锚点派生局部名（一层局部污点传递；**默认参永不污点**——判它会先把「自检显式传 temp 路径」的合法用法判红）。方法调用的锚点常挂在**受体**而不是实参上（`Path(p).write_text(...)`、`(ROOT / "x").read_text()`）——只收集实参会把这一族整面漏掉，故受体也进子树。
- **H1b 锚点经形参流进同文件 helper（调用点级一跳）**：本函数体把锚点表达式作为实参交给同文件 helper 的形参，且该形参在 helper 体内直接喂给 I/O 原语 ⇒ 判违例；helper 体内再局部派生一层（`q = d + "/x"` 之后读 q）同样跟污点。保守面三条：**只在该调用点判**（同一 helper 被别处用 temp 实参调用不受影响，P2/M16 双向钉住）、**只判一跳**（helper 再交给第二个 helper 不判）、**实参只吃进临时区名时留在 T 档**（不升级成红，P4/M15 钉住）。
- **H2 裸相对字面量真源读**：`open("scripts/README.md")` 只有 CWD=仓根才成立 ⇒ 判红；该路径在本仓**不存在**则不判（合成夹具也长这形状）。
- **五档分类**：W 写（open 带 `w`/`a`、`shutil`/`os.makedirs`/`os.remove`/`Path.write_text` 写删）/ R 读现状面 / G 打真仓 / S 隔离 spawn（只记账不判红）/ T 约定临时区（命中的锚点名全是「锚点派生 + 值里带 `temp` 段」的模块级常量或其一层局部派生 ⇒ 读写落在 AGENTS/电池律明文约定的 gitignored `temp/`，只记账不判红）。

六轮定形（每一轮都是「先假红/假绿，再收紧」）：

| 轮次 | 首版口径 | 实测反证 | 收口 |
|---|---|---|---|
| 1 | 「自检体提到锚点即红」 | 现读 67 处，一大半是 `os.path.relpath(p, ROOT)`、`cwd=ROOT` 这类不读盘引用 | 改成「锚点**流进 I/O 原语**」⇒ 67 → 40 |
| 2 | 「subprocess 带 `cwd=`/`env=` 即算隔离（S 不判红）」 | 11 处 S 里 **9 处写的是 `cwd=ROOT` / `cwd=cwd or ROOT`（`git ls-files` 打真仓）**——白名单反成豁免口，连 R151 的动机案例都被洗白 | 判**值**不吃锚点才算隔离 ⇒ S 11 → 2 |
| 3 | 「任一 `cwd`/`env` 干净即算隔离」 | `whisperer.py` L26 是 `cwd=cwd or ROOT … env=moon_env()`——无关的 `env=` 替被污染的 `cwd=` 买了豁免 | **污染优先**：任一 `cwd`/`env` 吃锚点即 G ⇒ S 2 → 1、红 49 → 50 |
| 4 | 扫描面只 `listdir(scripts/)` 顶层 | R55/R82 的律：「零执行面的尺=坏着的尺」那条普查对**子目录**正是盲的——`scripts/blackbox/` 里的尺天然漏出判定面 | 改递归全集（含 `blackbox/`，只剔 `__pycache__`）⇒ 当场多抓 5 处、红 50 → 52 |
| 5 | 写原语只认 `open` 的 `w` 模式与 `shutil` | 补面时两头同时暴露：① `e2e_native_heap_probe.py` 用 `Path(SELFTEST_DIR / "x").write_text(...)` 落盘**一条都不报**（漏红）；② 一把它抓出来就把 `SELFTEST_DIR = ROOT / "temp" / …` 判成 W **假红**（那是本仓明文约定的 gitignored 临时区） | 写面补 `Path.*`/`os.makedirs`/`os.remove` 并加**受体子树**；同时立 **T 档**（只认「落成锚点常量」的 `temp` 段，内联拼的不给豁免，故意保守）⇒ 红 52 → 59（W 6→7、R 34→40），记账 T=4 / S=1 |
| 6 | 「形参永不污点」写进漏红面 | 终审 R154 时读到 `check_memory_log_dup.py --selftest` 报 `FAIL S9`，走的正是 `find_logs(os.path.join(REPO_ROOT, "memory"))` → helper 体内 `os.walk`——R151 的形状本体停在盲区里，尺子看不见（该格更硬的一层：rc 取决于**未被跟踪的本地日报**，干净树 1、本地有日报 0，见 §二·4 的单变量对照） | 立 **H1b 调用点级一跳**（只在调用点判、只判一跳、临时区实参留 T）⇒ 红 59 → **72**（W 7→10、R 40→48、G 12→14），一跳族 13 处 / 7 份脚本 |

另有三处假红防线由自证格钉住：局部把锚点名重新赋值（`ROOT = tempfile.mkdtemp()`）不算命中（R8 格）；主面读锚点不污染自检（R7 格）；同一 helper 被 **temp 实参**调用不受一跳判定影响（P2 格）——把这道闸摘掉（变异 M16）反向对照格当场红。

**漏红面（照实标注，不冒充已覆盖）**：锚点经**默认参**流进 I/O 原语不判；形参只判**一跳**（helper 再把值交给第二个 helper 不判）；`cwd='.'` 这类不含锚点的字符串算隔离（要看穿需常量求值）；跨模块 import 的 helper 不判；三跳以上拼装不判；子进程内部再读盘不判；内联 `temp` 字面量段不给 T 豁免（`os.path.join(ROOT, "temp", …)` 仍按 W/R 判红）。要扩必须先拿实测形状。

## 四、改动

| 文件 | 改动 | 说明 |
|---|---|---|
| `scripts/check_selftest_hermetic.py` | 新增 721 行 | 判据 + 29 格自检（格数不写进 README，见 §九） |
| `scripts/run_guards.py` | +2 格（锚在 `check_merge_loss.py --selftest` 之后） | `case(..., "--selftest")` 门禁格 + `expected(..., 1, why=…)` 预存红格 |
| `scripts/README.md` | 新条目 1 行 + `BATTERY-REGISTRATION` 锚点改数 | 锚点 `90/42/52/60` → `94/43/56/64`（exempt 27 / unclassified 5 / missing 0 不变） |

## 五、before / after 实测

| 判据 | 基线（`git archive gitcode/master` 仓外快照） | 本单后（r153 工作树） |
|---|---|---|
| `check_battery_count_doc.py` 主面 | rc=1，漂移 4 处：登记 90/42/52/60 ↔ 现读 93/43/55/63 | **rc=0** 逐键一致 94/43/56/64/missing 0/exempt 27/unclassified 5 |
| `check_battery_count_doc.py --selftest` | rc=1（`R1-real-readme-vs-real-list-green` 格红） | **rc=0**（15 格） |
| `check_selftest_inventory_doc.py` | rc=2，X4 失联 **2** 处 | rc=2，X4 失联 **1** 处（只剩 `check_unit_number_unique.py`，其自检自身红，归后续单） |
| `check_scripts_index.py` | rc=1，FAIL 5 项 | rc=1，FAIL **4** 项——少的那一项是 `check_memory_log_dup.py`，**成因不是本单替它登记**：本尺的 H1b 反证正文里提到了这个文件名，而 `check_scripts_index` 的登记判据是「README 出现文件名或基名即算登记」。因果已用仓外快照验过（往快照 README 随便一处塞进这个文件名 ⇒ FAIL 从 5 变 4，删掉 ⇒ 回 5）。这是**那把尺自己的漏判面**（提及 ≠ 登记），记进 §八·9；R154 那单的正经登记条目照旧要写。 |
| `check_doc_dup.py` | 342 登记块 / 冗余 232 | 343 登记块 / 冗余 **232 不变**（新条目是唯一块，未造重复） |
| `check_doc_surface.py` | rc=0 | **rc=0**（J1–J15 未退化） |
| `check_py_stdout_encoding.py` | rc=0 | rc=0（该带闸 43 / 已带 43） |
| `check_exit_code_contract.py` | rc=0 | rc=0（判定面 0 条） |
| `run_guards.py --selftest` | rc=0（37 格） | rc=0（37 格） |
| `check_selftest_hermetic.py --selftest` | 尺不存在 | rc=0，29 格 |
| `check_selftest_hermetic.py` 主面 | — | rc=1，红档 **72 处**（W10/R48/G14，24 份脚本）+ 记账 **5 处**（T4/S1） |

## 六、验收（逐条实跑，非自述）

1. `python scripts/check_selftest_hermetic.py --selftest` → rc=0，逐字行见 §十一上方运行记录（`SELFTEST OK: 29 格（反解：F×7 / G×2 / P×4 / R×9 / S×1 / T×2 / W×4，族名取自已执行格子名首段的字母，不手写计数）`）。
2. 十六支变异探针（`temp/mut_r153.py`，temp 已 ignore）：M1–M16 全 rc=1，且每支点名到具体格子（不是「整体红」这种没法归因的读数）。新增各对应一道闸：M8 扫描面退回顶层 / M9 取消 T 档 / M10 摘掉 `Path` 写方法面 / M11 方法调用不收集受体 / M12 摘掉 `os` 族写删 / M13 临时区名不走局部派生 / **M14 摘掉形参一跳面（P1、P4 一起空转）/ M15 临时区实参也升级成红（P4 红）/ M16 摘掉「实参不含锚点不判」这道闸（P2 红）**。
3. 主面读数可从输出复算：`grep -c "^  - \[W\]" = 10`、`[R] = 48`、`[G] = 14`、`[T] = 4`、`[S] = 1`（合计 77 条，逐条带 `文件 :: 函数() 行号 原语 吃进的名字 链`）；红档 72 条=W+R+G，涉及 24 份脚本；首行自述「FAIL 自检体读/写仓库现状面 72 处」与 grep 分项相加一致。
4. W 档 10 处与 T 档 4 处**逐条人工核实**（§二·3 列出实际写入路径；T 档核到 `SELFTEST_DIR` 的定义行）——没有一处是靠名字猜的，`tmp_abs` 那一处正是「名字像临时、路径是跟踪面」的反例。
5. 形参一跳的 13 处中抽 3 处开原文件核实为真阳：`check_bug_refs.py` L258 `bugs_path = ROOT / "memory/bugs.md"` 交给 `load_bug_ids()`；`check_scripts_naming.py` L125 `read_roles(NAMING_DOC)`；`check_publish_payload.py` L139 `_rm(probes[0])` 删的是仓根探针。
6. 本尺不进红面（自证）：`grep check_selftest_hermetic temp/r153_herm6.log` 零命中（夹具落 `tempfile.mkdtemp()`）。
7. 电池里 `expected(..., 1, …)` 的 `why` 写的数=现读数（红 72 / W10 R48 G14 / 24 份脚本 / 记账 T4 S1），不许留旧数。
8. `check_battery_count_doc.py` rc=0 且锚点键序完整（7 键全在）。
9. **本尺被自家另一把闸判红过一次，且在提交前就红了**（这条是本轮最该记的自证）。首版 716 行的 `check_selftest_hermetic.py` 会 `print` 中文结论（含 `⇒`）却没带 BUG-58/138 的 stdout UTF-8 重配 ⇒ 电池两格当场红：`check_py_stdout_encoding.py --all` 报 `E1 scripts/check_selftest_hermetic.py 会 print 非 ASCII 却没有 BUG-58/138 的 stdout UTF-8 重配`（rc=1），并连带把同一把尺的 `--selftest` 打成 rc=2（M6 那格跑 `--all` 拿不到 PASS 行）。补上四行重配（现读 721 行）后两格各自转绿：`--all` rc=0、E1 计数 0、`--selftest` rc=0。**修复是否真的顶用不由 rc 说话**：`env -u PYTHONIOENCODING` 跑主面 ⇒ rc=1、77 条违例逐条打印完整、`grep -c "Traceback\|UnicodeEncodeError"` = **0**（本机 cp936 下重定向到文件正是崩点）。⇒ 一个新尺的「红能不能被看见」在这仓里是另一条既有闸的判定面，本尺立项抓的是别人读真源，自己却先犯了 print 崩在结论前这一格。
10. **对主机在飞的新尺做独立交叉验证**（不靠自述）：`git archive gitcode/fix/branch-ancestry-guard` 导出仓外快照，用本尺 `--root` 打一发 ⇒ rc=1、77 条（W=10 / R=48 / G=14 / T=4 / S=1，涉及 24 份脚本），与本树逐项同数，而主机那支 198 行的新尺 `check_branch_ancestry.py` **在判定面零命中**。⇒ 判据不是「只抓旧账的摆设」，也不是「新写的尺一定过不了」：它给的是逐条可核对的形状，新尺能干净、旧尺的红点得出具体行号。

## 七、任务分配记录（金条五）

| 单 | 派给 | 内容 | 状态 |
|---|---|---|---|
| R153 | 指挥官（本代理）亲自 | 新尺设计 + 判据定形 + 变异自证 + 接线 + 报告 | 本单 |
| R154 | **atomcode（外部执行器）** | `scripts/README.md` 登记 5 项 FAIL（`check_memory_log_dedupe.py` / `check_memory_log_dup.py` / `check_merge_loss.py` / `tmp_merge_batch.ps1/.sh`），边界=只改 README、不许改 .py、不许写族计数自述、不许 commit | **已终审通过并推分支**（`slave/atomcode/scripts-index-registration-r154`，commit `72ae8540`）：3 条登记落地、FAIL 5→2、边界逐条实测守住；剩下 2 项 `tmp_merge_batch.*` 经终审改判为**不该登记、该处置**（一次性批量合并脚本、`.sh` 里硬编码主机绝对路径），删除属不可逆动作，留 owner 确认。终审差点误判一次：把 master 上 `check_backlog_yaml_integrity.py` 名下的「九格含 C9」当成执行器写的假自述——按 diff 行取证后澄清，教训写进 R154 报告 §三 |
| — | 未派 | 72 处红档预存的逐条修复（W 档 10 处优先） | 归后续单（本单律：预存红不代修） |

判据：R153 是「形状判定 + 反例定形」密集的活，实测反证要当场改规则，外包给执行器会把六轮定形的因果丢掉；R154 是纯登记抄写（机械、边界清楚、可验收），适合派发。

## 八、遗留风险

1. **72 处红档只是可见，不是修好**。电池那一格现在期望 rc=1；被检面归零后它自己翻红，逼下一位把期望改回 0（本仓「显式」律）。R 档 48 处最密的三把尺：`check_release_asset_names.py`（13）、`run_guards.py`（5）、`check_host_installable.py` / `check_scripts_naming.py` / `whisperer_patrol.py`（各 3）——这些自检都拿真账当输入，修法同 R151（把该格移出 `--selftest` 或改合成夹具），但那是逐条核实的活，不属本单。
2. **`whisperer_patrol.py --selftest` 会往 `docs/tasks/backlog/` `os.makedirs` + 落 `TASK-*.yaml`**——本单没修，但这是最该优先归零的一条：电池跑一轮 = 任务池多行账，与「电池只读且快」直接冲突。
3. **T 档是「约定豁免」，不是「证明安全」**：它成立的前提是 AGENTS/电池律把 `temp/` 明文写成 gitignored 临时区。若哪天有人把 `temp/` 纳入跟踪面，这一档就变成漏红面——所以判据里把它单独打 `[T]` 记账、逐条点名，不许静默吞掉。
4. **静态判定的固有盲区**（§三 漏红面）：默认参传递、**形参两跳以上**、`cwd='.'` 这类常量、跨模块 helper、子进程内部再读盘、内联 `temp` 段不给豁免。要扩必须先拿实测形状（本仓律），不凭空加规则——本轮就是这条律的现场演示：形参一跳本是写进漏红面的「已知不管」，是终审 R154 时撞出一条**正在红的账停在这个盲区里**才补的，补完红档 +13。
5. **锚点更新会让「谁在等锚点」的判断变化**：master 上 `check_battery_count_doc --selftest` 由红转绿，R151 单（删掉那一格）与本单在**症状**上重叠。R151 的裁决仍成立——那一格的形状正是本尺现在常驻抓的（现读 `[R] …L194 io.open` + `[G] …read_counts L105`，同一形状两处点名）。合序不分先后，两单都合即收敛。
6. **README 同文件并发**：本单动 262 行锚点 + 807 行新条目；R154 动 800 行区间的登记条目。不同行，但同一文件——合并时若产生冲突，按 `check_merge_loss.py` 现读逐侧核对，别裸解。
7. `check_selftest_inventory_doc.py` 仍 rc=2（X4 剩 `check_unit_number_unique.py`，其自身自检红）。本单不代修。
8. **主面是「现读型诊断」，故意不入 CI 门禁**（主面恒红会把 CI 永久拉红）：本尺入电池的是 `--selftest` 那一格（纯 temp 夹具、只读且快），主面读数由电池 `expected()` 记账。`ci.yml` 本单没动，列在 §九后续建议。
9. **顺手实测出 `check_scripts_index.py` 自己的漏判面：「提及 = 登记」**。它的判据是「README 里出现文件名或去扩展名基名」即算登记，于是**任何一处顺带提到都销掉一条 FAIL**——本单在 H1b 的反证正文里提到 `check_memory_log_dup.py`，那一项 FAIL 就自己消失了（仓外快照验过因果：塞一次文件名 ⇒ 5 项变 4 项，删掉 ⇒ 回 5 项）。这不是本单该修的（预存红不代修），但值得单开一判据：登记应当要求「条目形状」（`- \`name\` — 说明`），而不是子串出现；否则 README 越写越长、FAIL 越读越少。归后续单。

## 九、超额内容（本单多做/主动收紧的）

- 自检格从首版 15 扩到 **29**：G1/G2（`cwd=ROOT` 不算隔离、无关 `env=` 不买豁免）、F3/F5（`blackbox/` 子目录件同判、扫描面递归）、W2/W3/W4（`Path.write_text` 落盘、内联 `temp` 段不买豁免、`os` 族写删）、T1/T2/F6（约定 `temp/` 的读写、局部派生、T 档单独成面必须判绿）、P1–P4（形参一跳判红、temp 实参不误判、形参不喂 I/O 原语不误判、临时区实参留 T）；变异探针从 5 支扩到 **16 支**（新增的每一支都对应这一轮加的一道闸，逐支点名格子，见 §六·2）。
- **扫描面改成递归全集**（`scripts/**/*.py`，只剔 `__pycache__`）：不是顺手加的，是 R55/R82 那条律的必然推论——「零执行面的尺=坏着的尺」这条普查只扫顶层时，对 `scripts/blackbox/` 里的尺正是盲的。
- **I/O 面补写侧 + 方法调用的受体子树**：`Path(p).write_text(...)` 这类锚点挂在受体而非实参上的调用，原判据整面看不见；补上之后当场抓到 `cleanup_artifacts.py` 的 `os.remove`、`whisperer_patrol.py` 的 `os.makedirs` 等，并立刻暴露出「约定 `temp/` 被误判」的假红 ⇒ T 档由这两条同时逼出。
- **形参一跳（H1b）是在终审别人的单时撞出来的**：不是「想到就加一条规则」，是读到一条正在红的账停在漏红面里。这一条也顺带把 R151 的裁决钉成机器判据——那一格（`selftest` → helper → `subprocess.run` 吃锚点）现在正是 P 族格子常驻的形状。
- 反解族名从「一格一族」（`R1×1 / R2×1 …` 15 族）改成按首段字母归族（`F×7 / G×2 / R×9 / S×1 / T×2 / W×4`）——留序号在族名里，那份清单就不是覆盖面视图了。
- **README 条目刻意不写族计数自述**：写死数字就是下一颗漂移雷（本仓已为它返工过一次），`--selftest` 自己打反解行。
- 顺带把 master 预存的锚点落后结清（§一·4），并留了仓外快照的 before 读数当证据。
- **后续建议**：① 把本尺 `--selftest` 接进 `ci.yml` 的守卫面（主面继续留在电池记账，不入门禁）；② 归零顺序建议 W 档 10 处 → `whisperer_patrol.py` 那 2 处最优先（电池写任务池）；③ R 档 48 处可按「哪把尺的自检红过」排序，先修红过的——`check_memory_log_dup.py` 的 S9 是现成的第一个，而且它不属「红过」而属「红绿由本地未跟踪文件决定」（单变量对照见 §二·4），改法是把那一格换成合成夹具目录，修完在 CI 上才有一个可复现读数；④ 单开一判据治 `check_scripts_index` 的「提及即登记」（§八·9）；⑤ 本尺一跳已覆盖，两跳以上的实测形状若再出现，按同一手法扩（先拿实测反证，再加规则）。

## 十、来源

- R151 报告：`reports/2026-10-23-battery-count-doc-hermetic-selftest-r151-report.md`（§八「立自检 hermetic 尺」即本单）
- 本仓律：`scripts/run_guards.py` 文件头「预存红照写期望值 + 依据」「SKIP 不构成通过证据」；`AGENTS.md`「一源四态 / cl6 doc-sync」
- 实测证据：`temp/r153_herm6.log`（77 条逐条点名：W10/R48/G14/T4/S1，红档 72 条涉及 24 份脚本）、`temp/mut_r153.py`（十六支变异）与 `temp/r153_mut.log`（逐支 rc + 点名格子）、`/f/AI/snap-r153-base/`（`git archive gitcode/master` 仓外基线快照，含 `bcd.log` / `selftest_base.log` / `docdup_base.log`；§八·9 的「提及即登记」因果也在这份快照里做过并逐字还原）
- 依赖判据：`check_selftest_inventory_doc.py`（X4 定义）、`check_battery_count_doc.py`（锚点七键文法）、`check_doc_surface.py` J10（判据范围自述==实现）

## 十一、电池终读

**提交前那一次**（`python scripts/run_guards.py`，日志 17780 字节）：**格数 77（手写 77 + 自动 0）/ 失败 10 / SKIP 6 / 缺执行面 0 / BATTERY rc=1**。十条失败逐条归属（不许把别人的红算在本单账上，也不许把自己的红算成预存）：

| 失败格 | got/expect | 归属 |
|---|---|---|
| `check_py_stdout_encoding.py --all` | 1/0 | **本单文件造成**：E1 点名 `scripts/check_selftest_hermetic.py` 会 print 非 ASCII 却没带 BUG-58/138 的 stdout 重配。已修（§六·9），修后 rc=0 |
| `check_py_stdout_encoding.py --selftest` | 2/0 | 同一因连带（M6 那格实调 `--all`，拿不到 PASS 行）。修后 rc=0 |
| `check_publish_payload.py` | 1/0 | **交付态红**：P1 点名我的新尺「未被 `.gitignore` 挡住又没被 git 跟踪 ⇒ `moon publish` 会把它公开出去」——提交即归零。按本仓律**不给 `expected()`**（登记期望＝把「还没交付」洗成常态） |
| `check_slave_task_list.py` | 1/0 | 预存：D1「文首写『失配 0』，尺实算失配 21 条」——主机任务清单与仓内实况的账，不属本单 |
| `check_scripts_index.py` | 1/0 | 预存：未登记面（R154 就是为它开的单，现读 FAIL 4 项）。**本单README 正文顺带提到 `check_memory_log_dup.py` 会额外销掉一项 FAIL**——那把尺「提及即登记」的漏判面，见 §八·9 |
| `check_doc_dup.py` | 1/0 | 预存：232 块冗余（合并把旧快照整段拼回，`--fix` 归后续单） |
| `whisperer.py --selftest` | TIMEOUT(600s)/0 | 预存：`git diff --stat gitcode/master -- scripts/whisperer.py` **空**（与主线逐字相同）⇒ 非本单引入。**本单不猜因**：其 G1 格跑 `python scripts/fist-gate.py --scan`（`cwd=ROOT`），600s 未结束；一条现读线索供下一位起手的——本机 `refs/remotes/gitcode/*` 113 条（扣 main/master/HEAD 还有 110 条），而 `--scan` 的分支宇宙正是从这里取。归因与耗时面留给专门单 |
| `check_unit_number_unique.py` | 1/0 | 预存（撞号/基线面） |
| `check_unit_number_unique.py --selftest` | 1/0 | 预存：`SELFTEST FAIL（11 格…）` |
| `check_selftest_inventory_doc.py` | 2/0 | **与上一格同一因**：X4 定义就是「跑那把尺的 `--selftest` 拿不到反解清单」⇒ 那把尺自检红把对表拖成 rc=2（本仓律：同因多格不算多条债，此处三格一条账） |

SKIP 6 格全是「缺前置产物」（`temp/pt27.log` ×2、`temp/chk47.json` ×3、`fist-mbt.db` ×1）——按本仓律 **SKIP 不构成通过证据**，故逐条点名而不计入绿。

**推后权威读数**：（commit→push 之后复跑同一条电池，日志写到**仓库外** `$HOME/battery_r153_post.log`（本仓律：判据日志不落 `temp/`，`cleanup_artifacts` 那一格会清 scratch 区，电池曾把自己的日志删掉过）；交付态那格 `check_publish_payload` 应以推后读数归零。数字以那一次为准。）
