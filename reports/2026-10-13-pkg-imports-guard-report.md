# 2026-10-13 · 新增 check_pkg_imports 判据报告（master 坏状态判据化）

## 结果摘要

**一句话**：上轮诊断到的 master 坏状态（`src/server/moon.pkg` import `src/diff` 但 `src/diff/` 未被跟踪）
**此前无任何判据认领**——本轮把它判据化：新增 `scripts/check_pkg_imports.py`，
并用**坏 rev vs 好 rev 成对实测** + **三处变异**证明它真会红；已挂进 CI、登记进 README。

| 项 | 读数 |
|---|---|
| `--selftest` | **rc=0，6 格全过** |
| **对坏状态 rev `e7a1d0e`** | **rc=1**，逐字点名 `P1 src/server/moon.pkg 里 import 了 'vicTop-cw/fist-mbt/src/diff'，但跟踪面里没有 src/diff/ 目录下的任何文件` |
| **对已修 rev `7079e9d`** | **rc=0** PASS（21 份 moon.pkg / 30 条本地 import 全指向跟踪面） |
| 变异实测 | **3/3 被自检抓住**（判定恒 False / 去掉外部依赖跳过 / 去掉模块根跳过），还原后 rc=0 |
| CI | `ci.yml` JS 轨新增「Package-import guard」步（`--selftest` 再全量），挂于 Entry-list guard 之后 |

提交：我的三项（判据脚本 + CI 步 + README 登记）**随 `348c5e7` 入库**（见「一处必须如实说明的入库方式」），
已推送 origin + gitcode。

## 判据设计（窄口径，只判确定性问题）

**P1**：全仓跟踪的 `moon.pkg` 里，凡 import `"vicTop-cw/fist-mbt/<sub>"`（可带 `@alias`），
`<sub>` 非空时**跟踪面必须存在 `<sub>/` 下的文件**；否则红，错误信息点名"该包目录没被 git add
（master 坏状态形状：改了 moon.pkg 却漏 add 新包）"。

**刻意不判**（避免过度拦截）：
- 外部依赖（`moonbitlang/` `colmugx/` `mizchi/` `Tigls/`等）——它们不在本仓跟踪面，归 moon registry 管
- 模块根自身（`"vicTop-cw/fist-mbt"` 无子路径）——指向模块根，无需目录检查
- `.mooncakes/`（gitignored）——天然不在跟踪面

**防空转**：一份 `moon.pkg` 都枚举不到、或全仓零条本地 import ⇒ `SystemExit(2)` FATAL，不报绿
（与 `check_entry_paths` / `check_test_sync` 同口径：「判据空转 ≠ 没有问题」）。

**为什么值得单立一支**：现状 CI 会因这类问题红，但红在 `Migrate mooncakes dep manifests` 步且
错误文本（`Failed to calculate build plan`）**先被读成"依赖迁移问题"**，同时该步一红就
**skip 其后 21 步**（守卫族集体失效）⇒ 发现得晚、定位得绕。本判据把"哪个包目录没进库"
直接点名在**独立一步**里，且挂在守卫族中间（不被后续步 skip 影响前的位置）。

## L4 实测（金条八：不靠自述）

**成对对照**（同一支脚本，两侧树各跑一发）：

| rev | 状态 | 判据读数 |
|---|---|---|
| `e7a1d0e`（坏） | `src/diff` 不在跟踪面 | **rc=1**，点名 `src/diff` |
| `7079e9d`（好） | `src/diff` 已入库 | **rc=0** PASS |

**变异实测 3/3**（证明"能红"不是自述）：把 P1 判定改恒 False ⇒ 自检抓 `synthetic-violation-caught`；
去掉"外部依赖前缀跳过" ⇒ 抓 `clean-no-false-positive`；去掉"模块根跳过" ⇒ 抓 `module-root-ignored`。
变异后还原、还原后 rc=0。

**当前 HEAD 全量**：`PASS 本地包 import 存在性一致：21 份 moon.pkg 的 30 条本地 import 指向的目录都在跟踪面`。

## 一处必须如实说明的入库方式（并发面实录）

我的三项**不是由我自己的提交入库的**，而是**随并发会话的 `348c5e7`（ocr_scan 提交）一起进去的**：

- 我把三项推进了 **index**（`git hash-object -w` + `update-index --cacheinfo`，精确只推进自己的内容）
- 期间并发会话在同一 index 上也有 24 项 staged；他们做 `git commit` 时把**整个 index** 一起提交了
- 结果：我的三项随 `348c5e7` 入库，**我自己的 `git commit -F ... -- <paths>` 没成功**（rc=1 静默）
- 核实：`git log -1 -- scripts/check_pkg_imports.py` ⇒ `348c5e7`；HEAD 上三项齐备、干净树实测可用

**这不是理想的入库路径**（我的提交意图被并进他人提交），但**结果正确**：三项内容逐字正确、
CI 步在位、判据在 HEAD 干净树实测 PASS + selftest PASS。已如实记录，供后续会话参考：
**共享 index 的多会话下，"精确 add"不足以保证"我的提单独占一笔提交"**。

**顺带修掉的连带问题**：`check_scripts_index` 一度报 FAIL（新脚本未登记）——因为我把登记行只推进了
**index**，而该守卫**读工作树**。提醒到位后我把工作树 README 也同步（在他人 WIP 版上插入我这一行，
保持其 WIP 完整），该守卫转 **PASS**。这条经验也适用于本轮：**index-only 的改动对"读工作树的守卫"无效**。

## 资源消耗

- 判据脚本 219 行；`--selftest` 跑 5 次（初跑 + 3 变异 + 还原）；
- 两棵 `git archive` 树（坏/好 rev）各跑判据 1 次；当前 HEAD 干净树跑判据 2 次；
- 守卫链复跑 2 轮（含 `check_scripts_index` / `check_entry_paths` / `check_py_stdout_encoding`）；
- 本链零 `.mbt` 源码改动、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：判据设计（含"刻意不判"三类）→ 实现 → selftest 六格 → 坏/好 rev 成对实测 →
  变异实测 → CI 挂点 → README 登记（含工作树同步）→ 报告。
- **未派子代理**：本链要害是"判据口径取舍" + "并发 index 归属判定"，外包会引入误判。
- 边界：`git add` / `cacheinfo` 只推进我自己的内容；未改任何 `.mbt`；未连带提交他人其它 WIP（虽然 index 被他人整体提交过，见上）。

## 遗留风险

1. **判据覆盖面是"目录存在"而非"包可编译"**：本判据只保证 import 指向的目录在跟踪面存在，
   **不保证**该包内容自洽（如 package 内符号缺失、循环依赖）。后者由 `moon check` 负责。
   两者互补，不可互替。
2. **`moon.pkg` 之外的悬空引用面无守卫**：本轮只判了 `moon.pkg` 的本地 import。
   同类面还有：`moon.mod` 的 deps↔registry、`@alias` 与实际包名一致、插件 manifest 的路径等——
   **未逐一认领**（`check_release_asset_names` / `check_plugin_sync` 已覆盖其中一部分）。
3. **共享 index 的多会话下"精确 add"不保证独占提交**（本轮实录）：我的三项被并入他人提交。
   结果是好的，但**提交信息与意图会错位**（`348c5e7` 的信息写的是 ocr_scan，没提本判据）。
   建议后续会话：**重要交付物尽量在同一轮内 commit + push**，缩短"只 staged 未 commit"的窗口。
4. **`check_scripts_index` 读工作树而非 index**：这意味着"只推进 index 的登记"会被它判 FAIL。
   本轮已知并处理；建议在 `scripts/README.md` 的相关描述里点明这条（该守卫的扫描面口径）。

## 后续建议

1. **给 `check_pkg_imports` 加一格"@alias 与实际包名一致性"**：现状只判目录存在；
   `@diff` 这类别名若与实际包名不符（moon 会报错）本判据看不出来 —— 可扩展但需先定口径（可选）。
2. **把本判据的失败信息接进 `Migrate` 步的解释**：现状 `Migrate` 步失败时会打印
   `Failed to calculate build plan`（易被读成依赖问题）；建议在该步的失败分支里加一句
   "若错误含 `Cannot find import <本地包>` ⇒ 先跑 `check_pkg_imports.py`"。
3. **重要交付物当轮 commit+push**（针对本轮的 index 竞争教训）：缩短 staged 窗口，
   避免"我的内容被并入他人提交"这种意图错位。
4. **给"读工作树 vs 读 index"的守卫口径做一次盘点**：本轮踩到 `check_scripts_index` 读工作树；
   建议列出全部守卫各自的读取面（工作树 / index / 跟踪清单），避免后来者再踩。

## 超额内容

- 顺带**把上轮报告里的守卫缺口落地成判据**（上轮只提了建议，本轮实现并实证）。
- 顺带**发现并修正了"只推进 index 不够"这个操作陷阱**（`check_scripts_index` 读工作树 ⇒ 一度 FAIL；
  同步工作树后转 PASS）。
- 顺带**如实记录了"我的提交被并入他人提交"**这一并发面事实——它既是风险（意图错位），
  也说明本仓多会话共享 index 的协作现状。
- 顺带在 CI 挂点里把"为什么需要这一步"的现场（坏状态 + 21 步 skip）写进注释，供后来者读。

## 来源

- 判据实现：`scripts/check_pkg_imports.py`（117 行主体 + selftest 六格）。
- 成对实测原件：`temp/verify_pkg_guard.py`（坏 rev `e7a1d0e` rc=1 点名 src/diff；好 rev `7079e9d` rc=0）；
  输出落 `E:\temp\vpkg.txt`。
- 力学依据：上轮报告 `reports/2026-10-13-master-broken-src-diff-diagnosis-report.md`；
  CI #300 的 `Migrate` 步日志（`temp/ci300_fail.log`）。
- 入库提交：`348c5e7`（并发会话的 ocr_scan 提交，连带我的三项）——`git log -1 -- scripts/check_pkg_imports.py` 可核。
- 登记面：`scripts/README.md` 的 `check_pkg_imports.py` 条目；CI 步名 `Package-import guard`。
