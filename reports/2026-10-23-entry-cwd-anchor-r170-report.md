# R170 · 把「产物路径按调用方 CWD 寻址」做成常驻判据（R3）· 2026-10-23

## 结果摘要

R159 修掉了 `scripts/fist.py` / `mcp_smoke.py` 两支入口的 CWD 依赖，但**没人保证它不再长回来**：
全仓 27 份脚本引用裸相对产物路径，其中 26 份各自用 `os.path.join(ROOT, …)` 或 `Popen(…, cwd=ROOT)` 侥幸构造正确，
**这个形状只存在于各脚本自己的写法里，不在任何尺子里**。本单把它补成判据。

落点选在既有守卫 `scripts/check_entry_paths.py`（BUG-93/101 那支入口搬家尺，本来就有电池格与 CI 步位）
新增第三条子判据 **R3**，而不是新开一支脚本——新开格子要动 `BATTERY-REGISTRATION` 锚点，
而 `check_battery_count_doc` 现在正红着（X5 登记 60 / 现读 63），不该由本单加深它。

R3 判什么：一份 .py 里若「装着裸相对产物路径（`_build/…js` / `target/…js`）的名字」被
①`os.path.exists|isfile|stat(名字)` 直接判存在、②`return 名字` 传给调用方、或
③出现在没有 `cwd=<仓库根>` 的 `Popen/subprocess.run` argv 里 ⇒ 发红。
合法形状两种都不红：消费点被 `os.path.join(ROOT|_FIST_ROOT|FIST_ROOT|REPO_ROOT|WORKDIR, …)` 包住，或起进程钉了 `cwd=<仓库根>`。

**落地即抓到第三处真实缺陷**：`scripts/pentad_fist.py:32/57` 的 `MAIN_JS = "_build/js/debug/build/cmd/cli/cli.js"`
配 `if not os.path.exists(MAIN_JS)`——与 R159 同形，本文件里 `_FIST_ROOT` 早就定义好了却没用在这条路径上。
本单一并修成绝对拼接（`os.path.join(_FIST_ROOT, …)`），于是 R3 在全仓现读为 0 处违例。

改动面：`scripts/check_entry_paths.py`（+135 行：R3 判定 + 4 格自证 + 主程序接线 + PASS 行自述补 R3）、
`scripts/pentad_fist.py`（1 行）、`scripts/README.md`（登记块补 R3 说明，并把落后的「`--selftest` 四格」改成「格子清单从执行面反解打印」）。

## 证据

- 尺自证：`python scripts/check_entry_paths.py --selftest` → rc=0，
  `SELFTEST OK（12 格：… / R3 裸相对产物必红 / R3 合法 join / cwd=ROOT 不误红 / R3 只改注释不误红 / R3 扫描面计数承重）`。
  四格新证成一组正反对照：**违例必红**（夹具就是 R159 的形状：候选列表 + `os.path.exists(p)` + `return p`）、
  **两种合法形状不误红**、**只改注释不误红**（红必须来自活代码）、**计数逻辑承重**（`r3_surface` 数错则主程序的空面自拒门形同虚设）。
- 全量现读：`python scripts/check_entry_paths.py` → rc=0，
  `PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个、R3 裸相对产物寻址 0 处（扫描面 289 份文件…）`。
- 承重证明（判据不是装饰）：接线**当时**在同一次运行里就把 `scripts/pentad_fist.py:57` 判红并点名修法，
  修掉那一行后同一把尺 rc 从 1 变 0——「能发红」是实测得到的，不是自证的夹具。
- 空面自拒：主程序在 R3 扫描面内没有任何 .py 时打印 FATAL 并回 rc=2，不冒绿。
- 家族普查（判据立项的依据）：27 份引用裸产物字面量的脚本中 26 份已有 ROOT 拼接或 `cwd=ROOT`；
  唯一缺保证的三份（`fist.py`、`mcp_smoke.py`、`pentad_fist.py`）现已全部修完。

## 资源消耗

- 零 MoonBit 改动 ⇒ `moon check` 不适用（不虚报）；测试数不变 ⇒ `check_test_sync` / `check_badge` 不受影响。
- Python 面：`python -m py_compile scripts/pentad_fist.py` rc=0；尺子本体两臂（selftest + 全量）实跑 rc=0。
- 电池格未增减（在既有脚本内加子判据）⇒ `check_battery_count_doc` 的 X5 缺口不由本单扩大。
- `scripts/README.md` 只改既有条目正文，未增删脚本 ⇒ `check_scripts_index` 读数不变。

## 任务分配记录

- 指挥官亲自做：判据设计（为何落点选既有尺而非新脚本）、R3 实现与四格自证、接线与空面自拒门、
  `pentad_fist.py` 的连带修复、README 登记块与 PASS 行自述同步、本报告。
- **本单未派 atomcode**：判据的价值恰恰在「哪些形状算合法」这一判断上——R159 那单之所以能原样采纳，
  是因为任务包里已经写死了验收探针；而这里要先决定「文件级豁免 vs 消费点级判定」，
  选错就得到一支会把 26 份正常脚本全判红的尺（那种红会被读成「判据坏了」，然后被人删掉）。

## 遗留风险

1. **消费点级判据只传一层**（`for v in NAME`）：跨函数把相对路径当参数传出去、或经 shell 字符串间接起进程的，R3 看不到。
   范围已在函数 docstring 与 README 登记块里如实写出——「不覆盖」是声明，不是「覆盖到了」的结论。
2. `cwd=<仓库根>` 这一档合法形状是**文件内任一行**级判定：一个脚本里既有钉 cwd 的启动点、又有没钉的启动点时，
   后者仍会被逐行判（判定按行做），但若违例行的 argv 段里恰好出现 `cwd=ROOT` 字样（例如注释在同一行尾部），会漏判。
   这一格由「只改注释不误红」反向对照保证不会**假红**，不保证不**假绿**。
3. `scripts/check_host_installable.py:362/375` 的产物字面量是 DSH 配置夹具（dict 里的 `"args"`，不 spawn 不 exists），
   按 R3 的消费点定义**不判**——它自己的 T1 判据正是「相对路径 args ⇒ 红」，两把尺在同一份数据上分工不同，不算缝。
4. 预存红照旧点名不代修：`check_scripts_index` rc=1（`tmp_merge_batch.sh` 未登记）、
   `check_doc_dup` rc=1（232 块冗余）、`check_battery_count_doc` rc=1（X5 60/63）、
   `check_selftest_inventory_doc` rc=2（X4 自述失联）、`check_unit_number_unique` rc=1、
   `check_slave_task_list` rc=1（D1 实算 20 条）、`whisperer.py --selftest` 电池里 600s 超时（R145 的有界化没覆盖这条路径）、
   两份 memory-log 尺在无日记工作树恒 rc=2（`788c5823` 把日记移出跟踪面后，干净树天然没样本）。
5. 取号说明：本单**没有**用 R161——历史面上存在 `2026-10-15-round163/165/167/168` 一整族 `roundNNN` 命名，
   与 `rNNN` 同号双义（R157 那次撞的就是它），故直接取整段占用带之上的 **R170**。

## 后续建议

- CI 侧无需接线：`check_entry_paths.py` 的电池格与 ci.yml 步位已存在（本单刻意复用），下一次跑电池就会带上 R3。
- 若要收口第 2 条的假绿面，可把 `cwd=` 判定从"同一行含字样"升级成"同一 Popen 调用的关键字参数"——
  那需要括号配对而非正则，建议随 `whisperer --selftest` 超时那一单一起排，不单开。
- 同类「只存在于各自写法里、没有尺」的形状还有两处值得照本单模式办：
  ①脚本必须把 `FIST_DB_PATH` 交给子进程（已有 `check_demo_isolation` 钉住，可作正面样板）；
  ②入口产物路径的「新鲜度判定」（谁负责重构建）目前散在各脚本里，没有单一真源。

## 超额内容

`scripts/pentad_fist.py` 的连带修复不在原计划里（原打算只加尺、必要时用白名单挂住已知违例）。
实测只剩一处真违例后，直接修比建白名单便宜，且不留下「登记了但没人修」的灰面——
代价是本分支同时含判据与修复，review 时按两个 commit 读。

## 来源

- 缺陷与修法：`reports/2026-10-23-find-main-cwd-r159-report.md`（R159，本分支的基座）。
- 实测读数：本单「证据」段两条 rc=0 输出，2026-10-23 本机 Windows（`F:/AI/Fist-Mbt-wt-r123`）。
- 判据落点依据：AGENTS.md「守卫族」段与 `check_battery_count_doc` 的 X5 现红（新增格子需同步锚点）。
- 取号依据：`reports/2026-10-15-round163-evolve-flush-report.md` 等 `roundNNN` 族 + 记忆「轮次号撞号」五面查法。
