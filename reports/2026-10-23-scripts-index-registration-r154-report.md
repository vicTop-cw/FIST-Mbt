# R154 · `scripts/README.md` 登记缺口收口（外部执行器交付 · 指挥官终审）

- 轮次：**R154**（取号查过五面；R153 是同窗口并行的立尺单，本单预留在先）
- 基线：`gitcode/master` tip `788c5823`
- 分支：`slave/atomcode/scripts-index-registration-r154`
- 执行者：**atomcode（外部执行器，`executor_run` 派发）**；终审：指挥官（本代理）
- 任务包：目标=把 `check_scripts_index.py` 现读的 5 项 FAIL 登记进 `scripts/README.md`；边界=**只改 README**、不许改 `.py`、不许写族计数自述、不许 commit

## 一、结果摘要

1. 交付 = `scripts/README.md` **+3 行**（`check_memory_log_dedupe.py` / `check_memory_log_dup.py` / `check_merge_loss.py` 各一条登记），`git status` 干净（只有 README 一处 M、无 commit、无其他文件被动）。
2. 验收达成：**`check_scripts_index.py` 的 FAIL 从 5 项缩到 2 项**，剩下的两项正是 `tmp_merge_batch.ps1` / `tmp_merge_batch.sh`——这两项的处置**不在本单裁决范围**（见 §四·1）。
3. 边界守住了：三条新条目**没有任何 `--selftest` 格数自述**（`git diff` 里 grep 不到「N 格」形状）——这条是任务包明文禁止项，实测通过，不是靠自述。
4. 未造成新的文档债：`check_selftest_inventory_doc.py` 仍 rc=2、X4 **2 处**，两处都是 master 上的预存（`check_battery_count_doc.py` 因 README 锚点落后其自检正红、`check_unit_number_unique.py` 其自检自身红），**本单一条都没新增**；`check_doc_dup.py` 冗余 232 不变。

## 二、终审逐条核（不采信执行器自述）

| 核什么 | 怎么核 | 读数 |
|---|---|---|
| 边界=只动 README | `git status --short` + `git diff --stat` | `M scripts/README.md`，`1 file changed, 3 insertions(+)` |
| 不许 commit | `git log --oneline -1` | `788c5823`（=基线 tip，执行器没提交） |
| 登记真生效 | `python scripts/check_scripts_index.py` | FAIL 5 → **2**（只剩 `tmp_merge_batch.ps1/.sh`） |
| 不许写格数自述 | `git diff -U0 \| grep "^+" \| grep -o "[0-9]\+ 格\|九格\|C[0-9]"` | 空（零命中） |
| 不新增文档债 | `check_selftest_inventory_doc.py` / `check_doc_dup.py` | X4 2 处（全为预存）/ 冗余 232 不变 |

## 三、一处我差点写错的终审（记下来，防止下次同样手法）

初读时我以为交付里有「`check_memory_log_dedupe.py` 的 `--selftest` 九格含 C9 真面变异」这条**假自述**（该尺实测只反解 8 格：C1–C8）。复核方式是 `python scripts/check_memory_log_dedupe.py --selftest`（确实 8 格、无 C9）——但**那句「九格含 C9」根本不在本单的 diff 里**：`git show HEAD:scripts/README.md` 里它已经存在，挂在 `check_backlog_yaml_integrity.py`（line 800）名下，是我用全文 grep 把它错配到了新条目上。

教训：审「谁写了假自述」必须按 **diff 行**取证，不能按 README 全文 grep——否则会把 master 的存量内容算成执行者的错，打回单就成了冤案。本单因此**不改判、不打回**。

## 四、遗留与归属（照实点名，不代修）

1. **`tmp_merge_batch.ps1` / `tmp_merge_batch.sh` 不该登记，该处置**：两份是历史一次性批量合并脚本——`.ps1` 里硬编码一串 `gitcode/slave/...` 分支名，`.sh` 里硬编码 `cd /e/IDEProjects/AI/FIST-Mbt`（**主机的绝对路径**，副机上也跑不通）。把它们写进 `scripts/README.md` 等于给垃圾桶发索引号。**处置=删除或移出跟踪面，属不可逆动作，留 owner 确认**；本单不代删。
2. **`check_scripts_index.py` 自己的判据缺口（两条，同一把尺）**：① 「README 里出现文件名或去扩展名基名」即算登记 ⇒ **任何一处顺带提到都销掉一条 FAIL**（R153 报告 §八·9 用仓外快照做过因果实验：塞一次文件名 ⇒ 5 项变 4 项，删掉 ⇒ 回 5 项）；② 它把 `tmp_` 前缀的一次性脚本当「正式辅助脚本」要求登记。合起来的形状是：FAIL 数可以被散文稀释，而真垃圾要靠 owner 删——判据把力气花在了错的一边。归后续单。
3. **`check_memory_log_dup.py --selftest` 的 S9 那一格，红绿由一个不被 git 跟踪的本地文件决定**：报的是 `FAIL S9 仓库内一份日志都没读到`，根因是 `788c5823` 把 `memory/YYYY-MM-DD.md` 移出跟踪面，而它的自检 `find_logs(os.path.join(REPO_ROOT, "memory"))` 读的是**工作树现状面**。实测（交单前补做，防止把「本地红」写成「主线红」）：仓外快照 `git archive gitcode/master`（盘上无当日日志）rc=1、本工作树（无当日日志）rc=1，而 `Fist-Mbt-r153` 与主机 `Fist-Mbt`（本地日报在盘）rc=0 且打印 `SELFTEST OK`；单变量对照＝在快照里手写一份合成当日日志 ⇒ rc 1→0，删掉 ⇒ 0→1。⇒ 它是**不可复现读数**，不是恒红；`FAIL`/`OK` 文本与 rc 严格绑定，没有假绿。登记条目没写这条（任务包没要求），但下一条相关单必须写：**它正是 R153 那把新尺 `check_selftest_hermetic.py` 现在常驻抓的形状**——本单交付后重跑该尺，`check_memory_log_dup.py` 会以 `[R] … 经形参 \`base_dir\` 交给 find_logs()` 出现在红档里；改法是把 S9 换成合成夹具目录，修完 CI 上才有一个可复现的读数。
4. **与 R153 的 README 同文件并发**：R153 动 line 262 的 `BATTERY-REGISTRATION` 锚点 + line 807 区的新条目；本单动 line 800 前的三行登记。行不同、文件同一，合并时按 `check_merge_loss.py` 现读逐侧核对（别裸解）。

## 五、验收清单（本单口径）

- [x] 三条登记条目内容与各自脚本文件头的判据口径一致（逐条开 `.py` 对表，未采信抄写）
- [x] `check_scripts_index.py` FAIL 项从 5 缩到 2
- [x] 未改 `.py`、未 commit、未新增格数自述
- [x] 未新增 X4 / 冗余块
- [ ] `tmp_merge_batch.*` 处置 —— **不在本单范围**，等 owner（§四·1）

## 六、资源与消耗

- 派发：1 次 `executor_run`（atomcode，产物 3 行 README）；终审实测：6 条命令（`git status` / `git diff --stat` / `git log -1` / `check_scripts_index` / `check_selftest_inventory_doc` / `check_doc_dup` / 被审尺的 `--selftest`），全部只读，未写仓库状态。

## 七、来源

- 任务包与派发记录：R153 报告 §七（同窗口并行）
- 判据现读：`scripts/check_scripts_index.py`（登记面）、`scripts/check_selftest_inventory_doc.py`（X4 定义）、`scripts/check_selftest_hermetic.py`（R153 立尺，红档点名 `check_memory_log_dup.py`）
- 被登记尺的真源：`scripts/check_memory_log_dedupe.py` / `scripts/check_memory_log_dup.py` / `scripts/check_merge_loss.py` 文件头
