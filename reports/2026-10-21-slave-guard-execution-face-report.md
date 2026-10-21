# 2026-10-21 · R40 守卫执行面普查 + 仓内电池真源化 · 副机汇报

任务：T0r21 ｜ 轮次：R40 ｜ 分支：`slave/guard/execution-face` ｜ 单号：BUG-365 / BUG-366（FIXED）、BUG-367 / BUG-368（OPEN）

## 1. 结果摘要

这一单的起因不是「发现一个缺陷」，而是「发现一个缺陷为什么能活一周」。

- **修掉一把尺的形状缺陷**：`scripts/check_plan_landing.py` 把 `path:108/121/134` 这类「路径+行号后缀」点名的行号段当成路径，
  于是**一个确实存在的跟踪文件被报成 missing**；同处还把日期/变量占位（`memory/YYYY-MM-DD.md`、`model-router-caf-{ns}.json`）
  当具体路径比对，并把 `docs/archive/`、`reports/` 的**存档面**与活文档混在同一个判定数字里。
  三条修法各最小：`LINE_SUFFIX` 在 `base_ok` 之前剥后缀、`SHAPE_PLACEHOLDER` 把非具体路径形态**出数不比对**、
  `is_archive_doc` + `judge()` 第 5 元组 `face` 分面（新增 `--all-faces`）。
- **把电池做成仓内真源**：新增 `scripts/run_guards.py`（270 行，入库、进 CI）。判据三条——
  **G1** 每把尺必须在 CI **或**电池有一格，缺面 rc=1 并**逐条点名**；**G2** 电池点了不存在的脚本 rc=2；**G3** 守卫宇宙为空 rc=2。
  两侧名单**都现读真源**（CI 面正则抽 `.github/workflows/*.yml`，电池面抽 `CASES`），谁都不抄名单。
  跑格 34 格，逐格打 `rc / 期望 / 结论`，格分 `gate` / `diag` / `known-red`，**预存红必须带依据文本**才算命中。
- **门自己也进了 CI**：`ci.yml` 在 Scripts-index 之后加三步（`run_guards.py --selftest` / `--list` / `check_plan_landing.py --selftest`）。
  这条律如果只写在文档里，就正是下一单的成因。
- **用户硬要求的现状**：`moon check --target js` = **489 warnings / 0 errors**，与上一单基线**逐字节相同**（本单零 `.mbt` 改动）；
  489 里 430 条压在 `Json::value` 一族（BUG-361，等 owner 定形态），**这一族不清零，「提交前零 WARNING」就没有绕行路径**。

## 2. 实测读数（承重证据）

| 格 | 读数 | 出处 |
|---|---|---|
| 尺子改前 | 54 份文档 / 349 条点名路径 / 未落地 **56** | `temp/plan_landing_before.py`（`git show HEAD:` 版） |
| 尺子改后 | 54 份 / 354 条 / 判定面 **28** + 存档面 **17** + 形态说明 **26** | `python scripts/check_plan_landing.py --all-faces` |
| 假阳性只减不增 | `comm -23` = **11 条**、`comm -13` = **0 条**；恒等式 56 = 28+17+9+2 | `temp/before_paths.txt` / `temp/after_paths.txt` |
| 零执行面取证 | 七条工作流对 `check_plan_landing` **全 0 命中**；`temp/run_guards*.py` **11 份 0 命中**；文件仅 2 次提交（`9267572` / `0e46b2a`） | `git show HEAD:.github/workflows/*.yml`、`grep -l`、`git log --follow` |
| 面门现状 | **24 把尺 / CI 面 21 / 电池面 22 / 缺面 0**；`--selftest` 9 格 OK | `python scripts/run_guards.py --selftest` |
| G1 不是空门 | 删掉 plan_landing 那格（CI 也没有）⇒ **rc=1 且点名该文件**；改回 rc=0 | 变异实测 |
| 电池整跑 | 34 格 / **失败 0** / SKIP 0 / 缺面 0（追加账本后曾失败 2＝小记与插件态未跟上，走完 `gen_plugins` 归零） | `temp/r40_battery.log` |
| 测试 | `Total tests: 1302, passed: 1302, failed: 0` | `temp/pt28_raw.log` |
| 判据面 | 489 warnings / 0 errors，分布 `{20:448, 6:12, 2:11, 1:9, 9:3, 78:3, 7:2, 27:1}`，与 `temp/chk47.json` **逐字节相同** | `temp/chk48.json`（`cmp -s` 通过） |
| `.mbti` 面 | moon 跑完 23 份又现 `Int`→`Int32`（BUG-330 复现），`git restore -- '*.mbti'` 收回、不入提交 | `git status` |
| 索引守卫 | `check_scripts_index.py` PASS（`run_guards.py` 已登记） | 实跑 |
| 账本摘要 | `BUG-1~368 共 353 条入账：19 待修 / 313 已修 / 10 重复 / 9 误报` | `gen_plugins.py` 输出 |

## 3. 三条非显然判定

1. **「有钩子」≠「钩子会跑」**：`.githooks/pre-commit` 内容只有 `moon check` 一行，而 `git config core.hooksPath` **未设置**（rc=1）
   ⇒ 连这一格在本地都不生效。接线是机器级动作、代价是每次提交慢几十秒，按金条四不自作。
2. **白名单差点给自己造免检牌**：首版把 `docs/superpowers/` 划进存档面，随即否掉——那两份计划点名的 `scripts/_ai_prompt.md`、
   `_score_probe.py` 是真未落地；按「看起来像历史」豁免＝按颜色放行，而本工具存在的唯一理由就是抓「计划写了没做」。
   边界钉成反夹具 `archive-prefix-not-overbroad`。
3. **期望红的依据不可核对＝半开的门**（BUG-368）：`cleanup_artifacts --check` 把已跟踪的真源 `scripts/_tool_registry.py`
   数成「`_` 临时脚本」，且只给档数不给文件名 ⇒ 数字从上一单 608 漂到 623 没人看得出来。这条是 G1 的下一层。

## 4. 资源消耗

- 工具调用：约 28 次（读/检索 11、Bash 取证 9、写盘 5、生成与复跑 3）。
- 长跑命令：`moon test --target js -j 1`（≈40s）、`moon check --target js --json`（≈35s）、电池 34 格（≈90s）。
- 写盘：`memory/bugs.md` +78 行（3 条新单 + 1 条 FIXED 小记）、`memory/2026-10-21.md` +44 行、`scripts/README.md` 2 条、
  `docs/agent-map.md` 2 条、`.github/workflows/ci.yml` +1 步、新增 `scripts/run_guards.py` 270 行、本报告。
- 无新增依赖、无 `.mbt` 改动、无接口变更。

## 5. 任务分配记录

- 指挥官（副机本单）：判定分流（先判尺子再判被测）、面门判据设计（G1/G2/G3）、存档面白名单边界的否决与回退、终审。
- 未派子代理：本单是「尺子的尺子」，取证与判据设计强依赖跨文件上下文（11 份历史电池、7 条工作流、账本耦合），
  拆开反而会把结论写成转述；因此按轻任务直办 + 实跑终审。
- 交回主机的问题（不自行推进）：BUG-367 四档裁决（A 补做/作废、B 外部面口径、C 历史一次性件、D 是否给尺子加 `[moved]` 第四态）、
  BUG-368 修法三档、`core.hooksPath` 接线与否、BUG-361 的 430 条形态。

## 6. CI 与预存红

- CI 新增一步（三条命令）：`run_guards.py --selftest`、`run_guards.py --list`、`check_plan_landing.py --selftest`。
- 电池 34 格分类：门禁格按 exp=0 判；**预存红 3**（`check_py_stdout_encoding --selftest` rc=2、`--all` rc=1，同 9 份历史脚本；
  `cleanup_artifacts --check` rc=1，623 件残留）；**诊断 1**（`check_plan_landing` rc=1＝判定面 28 条待裁，BUG-367）。
- **没有把整把电池搬进 CI**：那 3+1 格需要 `continue-on-error`，等于把「期望红要带依据」降级成「红都放行」，故留裁。
- 本单未新增任何红；`moon check` 489/0 与基线逐字节相同，`moon test` 1302/1302/0。

## 7. 遗留风险

1. **G1 只钉「有没有一格」，不钉「那一格跑的是什么目标」**：本机 native 面不可用 ⇒ 24 把尺的 native 行为仍零读数。
2. **`gated()` 两格依赖本机 `temp/chk47.json` / `temp/pt27.log`**：跨环境读 SKIP（不判绿也不判红，但也就没跑）；CI 已现产 dump，
   仓内电池却读本机 temp ⇒ 不可复现，建议下一单改为读 CI 产物。
3. **BUG-367 判定面 28 条常驻**：工具退出码仍是 1（设计如此，只读诊断不判门禁），读汇总的人若把「非零」都当「待修门」会误判。
4. **D 类「搬家后旧引用」3 条**是工具缺第四态，不是文档错；本轮不实现（会改判据语义与 selftest 期望）。
5. **489 warnings 里 430 条不动**：用户「提交前零 WARNING」这条硬要求在 BUG-361 定案前无法达成，属已知阻塞而非本单新增。

## 8. 后续建议

1. 先裁 BUG-367 四档与 BUG-368 三档，再考虑给 `check_plan_landing` 加棘轮（`gap_ceiling` 手法），让「裁决慢」不至于让盲区长回来。
2. 电池格数按**尺数**棘轮：写档抄 `--list` 首句（24/21/22/0），不要再抄 `temp/` 里某份手写脚本的格数。
3. 把 `gated()` 的两格改成 CI 内产物（CI 现产 dump），消除「本机 temp」这一跨环境不可复现面。
4. 若要把 `known-red` 也搬进 CI：先给每条 `why` 补「构成 + 已知虚报」，否则红门一旦被忽略一次，整把尺就废。
5. `core.hooksPath` 若接线，建议只接 `moon check` 而不接电池（电池已在 CI，本地重复跑代价是每次提交几十秒）。

## 9. 超额内容（自审）

- **超出「修一把尺」的范围**：做了 `run_guards.py` 这把新尺（含 9 格 selftest）。理由是 BUG-365 的成因就是零执行面，只修读数等于留下同一失效路径。
- **否掉的两条**：① 把整把电池塞进 CI（需开 `continue-on-error`，会削弱刚立的依据律）；② 给 `check_plan_landing` 加 `[moved]` 第四态（改判据语义，越出本单声明边界）。
- **自伤并当场修掉**：`### FIXED(...)` 抬头最初写成 `… R40 / BUG-365 / BUG-366`，被 `gen_plugins.py` 的真源自证拒生成
  （`RE_FIXED_IDS` 的 `[^)]*` 吞掉第一段 ⇒ 只有最后一个 id 被认领，报「1 条标 FIXED 却无小记点名：BUG-365」）。
  按文法改成逗号形式后通过。**这条恰好是本单主题的小复刻：判据不点名，就没人知道自己少做了一半。**
- **取证纪律**：before/after 用 `git show HEAD:` 的同树对照 + `comm` 集合差，不靠叙述；所有数字来自实跑日志。

## 10. 来源

- 本单产物：[scripts/run_guards.py](file:///F:/AI/Fist-Mbt/scripts/run_guards.py)、[scripts/check_plan_landing.py](file:///F:/AI/Fist-Mbt/scripts/check_plan_landing.py)、
  [.github/workflows/ci.yml](file:///F:/AI/Fist-Mbt/.github/workflows/ci.yml)、[scripts/README.md](file:///F:/AI/Fist-Mbt/scripts/README.md)、
  [docs/agent-map.md](file:///F:/AI/Fist-Mbt/docs/agent-map.md)、[memory/bugs.md](file:///F:/AI/Fist-Mbt/memory/bugs.md)、[memory/2026-10-21.md](file:///F:/AI/Fist-Mbt/memory/2026-10-21.md)
- 取证件（`temp/`，未跟踪）：`plan_landing_before.py`、`before_paths.txt` / `after_paths.txt`、`pt28_raw.log`、`chk48.json`、`r40_battery.log`
- 判据真源：`git show HEAD:.github/workflows/*.yml`（七条工作流的 `scripts/*.py` 调用面）、`git ls-files "*.mbt"`（守卫宇宙）
- 历史单：BUG-357（绿着的谎）、BUG-344（收口口径）、BUG-362/363（判据面 vs 文本面、文档面盲区）、BUG-330（`.mbti` 漂移）
- 上一单收尾：`5246a61` + 回填 `fc8ce7e`（分支 `slave/guard/doc-surface-blindspot`，MR 入口已由 owner 侧持有）
