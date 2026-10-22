# 交付报告 · 副机任务清单逐行对账（R122）

- 日期：2026-10-22
- 分支：`slave/docs/slave-tasks-reconcile-r122`（基点 = 主线 `08e540bf`，本支已叠其上）
- 提交：`84fd556e`（首轮对账）→ `9ba07382`（叠主线，0 冲突）→ `1c521925`（取证复核改判）→ 本报告所在提交
- 性质：**副机自立项，文档单**——只改 `docs/2026-10-20-slave-tasks.md` + 报告 + 当日日志，不改代码、不改 CI、不动 `memory/bugs.md` 账本（编号归主机）
- 认领来源：目标「持续拉主仓自己找任务提 PR … 你自己觉得不好用那就按你的思路去改」。这一单不是在做一个清单任务，而是在修**清单本身作为认领入口不可信**这件事——它是下一个 agent 的第一输入面。

## 结果摘要

`docs/2026-10-20-slave-tasks.md` 28 行认领入口对账前全标 `[ ]`。逐行按仓内实读改判并新增「现读证据」列：

| 状态 | 行数 | 含义 |
|---|---|---|
| 已落地 | 8 | GUARD-01/02/03、WT-04、SHIP-03、POLISH-01、POLISH-06、MISC-01（CI 与电池双接线） |
| 部分 | 8 | CAF-01、CAF-02、WEB-01、WT-05、SHIP-01、POLISH-02、POLISH-03、POLISH-05 |
| 未开工 | 9 | WEB-02、WT-01/02/03/06/07、SHIP-02、POLISH-04、MISC-02 |
| 作废 | 3 | MULTI-01/02/03——与已定案 plan v0.2 正面冲突 |

三件要紧的：

1. **Slice 3 整段作废**（防重复劳动的最高价值一格）。`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md:27` 逐字「❌ 为每门语言手写 SDK 客户端（Python/TS/C#/Scala/Elixir……）→ 维护地狱，用户量≈1，**不成立**」、`:33`「因此本计划不再产出任何"语言 SDK 矩阵"」、`:57`「不产出任何语言 SDK / 桥接包」。清单却把三行挂着让人认领 shim——**照字面做的下一位会去写 `pyproject.toml`**。已登记进文末作废表 ❌0，并把裁决写成规则：**清单与已定案 plan 相反时，plan 赢**。
2. **`部分` 的分界必须是语义差，不是"有相关文件"**。例：CAF-01 的 CAF 回写点唯一在路由侧 `src/server/model_router_ops.mbt:463`（取模型/记账时刻），而 `executor_run` 通道体内（`src/server/server.mbt:7067`/`:7131`，扫 7100-7260 段）0 个 `caf` 引用 ⇒ CAF 记的是"选了哪个模型"，不是"这次执行成没成"；`caf_dr_6` 降级锁反而早已在场（`src/server/model_router_ops_wbtest.mbt:749`）。
3. **行数自述也是账实不符**：建单口头计数 22，`grep -cE '^\| (CAF|GUARD|MULTI|WEB|WT|SHIP|POLISH|MISC)-[0-9]+ \|'` 实读 **28**。本单把自己这条纠正也写进清单更新日志——**登记文字自身是被检面**。

## 证据

| 项 | 读数 |
|---|---|
| 锚点自证（结构级） | 从清单正文反解 `文件:行` 锚点 **41 条 / 失配 0**（文件存在 + 行号不越界） |
| 锚点自证（内容级） | 点名断言 **40 条 / 失配 0**：每一行确实含所声称记号（行号对上不等于内容对上） |
| 为何要两级 | 首轮把 `server.mbt:7066`/`:7130` 写进清单后叠了主线 `08e540bf`（BUG-354 改 `server.mbt`），行号漂到 `:7067`/`:7131`；`README.md:220` 实为 `:218`。内容级断言当场抓到 3 条失配，全部按现行号重写 |
| 状态分布计数 | 状态列机器计数 = 已落地 8 / 部分 8 / 未开工 9 / 作废 3；编号行 28 |
| `run_guards.py --list`（三把守卫） | `check_model_auth_no_key.py` / `check_host_installable.py` / `check_skill_inject.py` 均 `CI=CI 电池=电池` ⇒ GUARD 三行不是"脚本存在"而是"真在跑" |
| 与取证代理的复核 | 派只读代理逐行取证（边界：只读、只动 `Fist-Mbt-wt-r121`、不跑全量电池），回传 28 行判定表。**终审结果：采纳其 8 处改判**（MULTI×3→作废、WT-04→已落地、WT-05/SHIP-01/POLISH-02/03/05→部分、CAF-02→部分），**驳回 1 处**（其判 CAF-01 `done`：`caf_dr_7`/`caf_dr_10` 证的是路由侧回写，不是 `executor_run` 结果回灌——代理自己引的 `model_router_ops.mbt:463` 唯一点用即反证），另纠正其"行数 28"为顺带发现而非我的结论 |
| 文档面四把尺 | `check_doc_surface.py` rc=0、`check_scripts_index.py` rc=0、`check_bug_reference_integrity.py` rc=0、`check_battery_count_doc.py` rc=0 |
| `check_doc_surface.py --selftest` | rc=0（真源解析到 170 个工具，J3-J15 对照在位） |
| 主干门 | `moon check --target js` = **`ran 146 tasks, 508 warnings, 0 errors`**（合入硬门） |
| 主干测试 | `moon test --target js` = `Total tests: 1387, passed: 1387, failed: 0.`（叠入主线 BUG-354 代码改动后复跑，非继承 R121 读数） |
| 交单 | `git push gitcode slave/docs/slave-tasks-reconcile-r122` rc=0，新分支落地；MR 入口交 owner：`https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/docs/slave-tasks-reconcile-r122` |
| 合入门 | `python scripts/whisperer.py --fast` **rc=1 预存红（主线现状码）**：逐字 `⚠️ 本地 HEAD 与远端 main 不一致（篡改）/ → 跑 --scan-only 恢复，或手动 git reset --hard 08e540b`。本单是 feature 分支，领先/落后是常态形状，不采纳其处方（金条四；R120 的修法仍在 MR 里未进主线） |
| 预存红（不代修，逐条点名） | `check_badge.py` rc=1（README 徽章 1382/1382 ≠ 实测 1387/1387）；`check_test_sync.py` rc=1（R2 三面缺 1387 声明 + R3 防空转）；`check_scripts_naming.py` 在电池里按 `known-red` 记账 |
| 工作树 | 本单跟踪面只有 `docs/2026-10-20-slave-tasks.md` + 报告 + 当日日志；`memory/whisperer-head.txt` 被 `whisperer --fast` 写脏，提交前 `git checkout -f --` 还原 |

## 资源消耗

- 分支 1 条、提交 4 笔（对账 1 + 叠线 1 + 复核改判 1 + 报告/日志 1）。
- `moon check` 1 次（约 2 分钟）、`moon test --target js` 1 次（约 3 分钟）、`run_guards.py` 全量 2 次（推送前 1 次 rc=0；推送后权威读数 1 次 rc=0：格数 60——该读数属于 `5364eb75` 那一版推送态；本报告在其上又追加了一笔追记提交（只改本节这一行与「遗留风险」第 8 条），纯文档、不重跑全量电池 / 失败 0 / SKIP 5 / 缺执行面 0，`grep -c '^FAIL'` = 0。其中 2 条 SKIP 恰好是我上面点名的两把预存红尺——见「遗留风险」第 8 条）。
- 只读取证子代理 1 个（51 次工具调用、约 44 分钟、3.67M 子代理 token）——这是本单最贵的一项，见「任务分配记录」。
- 文档尺 4 把 + `check_doc_surface --selftest` 各 1 次（秒级）。

## 任务分配记录（金条四）

- **派了**：一个只读取证代理做 28 行×多面的存在性/接线对表（`git ls-files`、跨目录 `grep`、plan 裁决句定位）。理由：这是可并行、可验收的取证体力活，不是裁决。
- **没派**：改判与改写全文由指挥官本人做。理由：状态词表与"语义差分界"是裁决类内容，交出去就会退化成"有文件即 done"。
- **终审真实结果**：代理表 28 行中 8 处改判被我采纳（我逐条复跑它给的 文件:行 后确认），1 处被我驳回并给出反证（CAF-01），1 处被我降级表述（WT-04 的"claim"语义注意）。**代理自述"全部取证在 r121 树、该树另有未提交 WIP 已排除"——我另在叠线后的 r122 干净树重跑全部锚点，读数以上表为准。**
- 代理另外纠正了我一处错误：清单编号行是 28 不是 22。我没有自查到。

## 遗留风险

1. **锚点会漂**：清单里的 文件:行 是 `08e540bf` 时点的读数。任何改动 `server.mbt`/`ci.yml`/`web/app.js` 的合入都会让清单行号失真——本仓唯一抗漂形式是把"锚点可解析"做成常驻尺（清单「仍缺的一面」§1 已给判据设计）。不建这把尺，这份清单会在几轮内重新变红。
2. **自证脚本未入库**：`fist_r122_anchor_all.py` 在本机、一次性。文首那两个数（41/40）目前是手抄的读数——这正是本仓 J10「声明滞后 / 幻影判据」点名的形状。入库后必须由尺自己给出。
3. **`部分` 的 8 行仍需人裁决其收口条件**：POLISH-03 的 release 臂被 `check_release_asset_names.py:257`（R8）**反向要求**保留 `continue-on-error`，"清单字面"与"另一把尺"互斥；POLISH-05 的内容其实已在 `AI-DEVELOPMENT-STANDARD.md:104` §7，再建 `docs/known-boundaries.md` 有造第二个真源的风险。这两行**不建议直接认领**。
4. **SHIP-02 认领前必须读 plan G7**：`docs/SHIP-PLAN-BLACKBOX-v2.md:64` 逐字「仍未实现，且刻意不盲落」，GitCode 的 project/release 端点只读探测全 404。清单原状会让 agent 去补一条"每 tag 必跑、未实测、不可逆"的发布步。
5. **验收未证的行仍标着 `部分`/`未开工`**：POLISH-03 的字面验收「干净树 `moon test --target native -j 1` 全绿」需 `git archive HEAD` 实跑，本单未跑；SHIP-01 的"能用"未证（GitCode 直链实测 403，靠 GitHub fallback 兜住）。这些不是我能在此单关闭的。
6. **清单外两处陈旧自述**（点名不代修）：`README.md:218` 版本地板 0.1.20260827 落后于 AGENTS.md 要求的 0.1.20261016（按 README 起环境必崩）；`docs/selfdrive-walkthrough.md:56` 仍写「148 项测试」。
7. **运行时状态文件仍在跟踪面**：`memory/whisperer-head.txt` 每次跑 `whisperer` 就脏（R121 已记，仍未解决）。
8. **电池里的 `失败 0` 藏着两个没跑的判定面**：post-push 权威读数 5 条 SKIP 中有 2 条正是`check_badge.py` / `check_test_sync.py`（缺前置 `temp/pt27.log`），而这两把尺单独跑是 rc=1 预存红。「缺前置而跳过」把红从读数里抹掉，`失败 0` 因此不等于「这两格过了」——SUMMARY 那行已经写了「SKIP 明细（不计失败，但也不构成'这格过了'的证据）」，方向对，但它不认识SKIP 里混着 known-red 家族。出路：电池先造前置（`temp/pt27.log` 由 `moon test` 产出）再跑，或把「SKIP ∩ known-red」单印一行的点名格。本单未改电池本体。

## 后续建议

1. 建 `scripts/check_slave_task_list.py`（判据已在清单「仍缺的一面」§1 写死）：锚点可解析 + 那一行含声称记号 + 状态列改判必须带证据；无证据的 `已落地` 按 R119 的 `UNPROVEN-DONE 不许无据` 判红。挂进电池与 CI。
2. 把「版本地板」纳入文档面判据：`check_doc_surface` 现在只比「文档自述版本 == `moon.mod`」，看不见「环境要求里的版本下限」与 AGENTS.md 冲突这一格（POLISH-04 的根因）。
3. 清单与 plan 冲突时的裁决顺序应写进 `AI-DEVELOPMENT-STANDARD.md`：**plan 赢，且作废登记回清单文末表**——本轮是本仓第一次把这条实际执行出来。
4. 主机合入本单后，`docs/2026-10-20-slave-tasks.md` 里 9 行 `未开工` 才是真缺口；建议下一批副机单从 WT-01（claimguard 挂钩，库已在、只差接线）与 POLISH-04（版本地板，用户可崩）起。
5. 轮次标签仍会撞号（本轮 R122 起支前已逐条 `git ls-remote --heads gitcode | grep r12` 核对无占用）；`docs/rounds.md` 台账建议仍然未落。

## 超额内容（本单边界外，未动）

- 纠正了自己首轮的行数自述（22 → 28）与三处漂移锚点——这是返工，不是新功能。
- 把 `run_guards.py --list` 的接线面（`CI=CI 电池=电池`）引进证据列，作为"脚本存在"之外的第二级证据；未改电池本体。
- 未派生第二份清单、未新建 `docs/` 文件（避免 `check_doc_dup` 型重复与 J15 命名面波及）。

## 来源

- `docs/2026-10-20-slave-tasks.md`（本单改写对象，28 行）
- `docs/2026-10-12-fist-mbt-multilang-sdk-plan.md`（:17 / :27 / :33 / :57 裁决句）
- `docs/SHIP-PLAN-BLACKBOX-v2.md`（:63 G5 附带 / :64 G7 / :65 G3）
- `docs/plan-light-worktree-isolation.md`（WT 全 Slice 参考面）
- `src/server/model_router_ops.mbt` / `src/server/model_router_ops_wbtest.mbt` / `src/router/router_caf.mbt` / `src/router/router_caf_persist.mbt`
- `src/server/server.mbt`（executor_run 注册与实现调用行）
- `.github/workflows/ci.yml`（:262/:268/:274 守卫步骤、:409-410 native 测试臂）
- `scripts/check_slave_mergeability.py`、`scripts/check_release_asset_names.py:257`、`scripts/run_guards.py:153/:252/:451`
- `reports/2026-10-22-backlog-reconcile-r119-report.md`（机器任务池对账先例，判据口径沿用）
- 只读取证子代理回传的 28 行判定表（其取证树 `F:\AI\Fist-Mbt-wt-r121`，本单读数已在叠线后的 r122 干净树复核）
