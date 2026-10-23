# FIST-Mbt 副机（Slave Agent）任务清单

> **主机** 2026-10-20 创建。副机认领时对目标行把状态改成 `[working]` 并 commit 认领。
> **每个任务** = 一个独立分支 = 一个独立 PR = 四态闭环。
>
> **2026-10-22 逐行对账（副机 R122，对账时点 = 主线 `08e540bf`）**：`状态` 与 `现读证据` 两列是**对账时点的仓内实读**，
> 不是计划、不是转述——每条都指到 文件:行 或跟踪面文件名，可逐条复核。本次自证读数（脚本从本文反解锚点）：
> **结构级 41 条**（文件存在 + 行号不越界）失配 0；**内容级 40 条**（那一行确实含所声称的记号）失配 0。
> 状态词表：`已落地` / `部分` / `未开工` / `作废` / `无法取证`（最后一词只在确实拿不到证据时使用，必须写明缺哪一面）。
>
> **为什么要对账**：对账前 28 行全标 `[ ]`（未认领），而改判后的分布是 **已落地 9 / 部分 8 / 未开工 8 / 作废 3**
> （从状态列机器计数，非手抄：`grep -cE '^\| (CAF|GUARD|MULTI|WEB|WT|SHIP|POLISH|MISC)-[0-9]+ \|'` = 28）。
> 已落地那 9 行（GUARD-01/02/03、WT-04、SHIP-03、POLISH-01/04/06、MISC-01）：其中 POLISH-04 由副机 R127 本分支落地（待合入），其余早已进主线并挂进 CI 与电池。
> 本仓对这一形状早有判据（`bug_list` 的
> `open_with_linked_done`：「账本说没修、任务库说修完了」），但清单面此前没有任何对表机制，所以它能红着没人读。
> 行数顺带纠正：建单时的口头计数是 22，`grep` 实读编号行是 **28**（Slice 1..8 = 2+3+3+2+7+3+6+2）。

---

## Slice 1 · CAF 写回（读半已落地；写半只落了降级锁与「路由侧」回写）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| CAF-01 | `executor_run` 成功后 `caf_memory.push` 回写 + caf_dr_6 bad-JSON 降级锁 | `feature/caf-writeback-slice-b` | `部分` | **降级锁 + 路由侧回写已在场**：`src/server/model_router_ops.mbt:115`（`bad_json` 只计数告警、不删不覆盖）+ 白盒锁 `src/server/model_router_ops_wbtest.mbt:749`（caf_dr_6）、`:798`（caf_dr_7 真消耗回写闭合读写环）、`:950`（caf_dr_10 失败执行污染锁）。**执行结果那一半未接**：全仓 `mr_caf_push_evidence` 唯一点用是 `src/server/model_router_ops.mbt:463`（`model_route_impl` 的取模型/记账时刻），而 `executor_run` 通道体内（`src/server/server.mbt:7067` 注册、`:7131` 实现调用，扫 7100-7260 段）出现 0 个 `caf` 引用 ⇒ CAF 记的是「选了哪个模型」，不是「这次执行成没成」 | 新 | `docs/2026-10-17-caf-writeback-task-package.md` Slice B | moon fmt/check/test 全绿；主机 MR 前 run_check |
| CAF-02 | `CafMemory::to_json` 补充原始 records 字段（R45 缺口） | `feature/caf-raw-records` | `部分` | 指定改动未落：`src/router/router_caf.mbt:220` 起的 `to_json` 只出四个键（`total_records` / `capacity` / `count` / `by_model` 聚合），原始记录面不导出；任务点名的白盒锁 `caf_rr_1` 在 `src/` 全仓 0 命中。**但能力已有旁路**：`src/router/router_caf_persist.mbt:33` 的 `caf_memory_dump` 逐条输出 `"records"` 数组（持久化往返用）⇒ 缺口是展示/快照面，不是数据面，动手前先定「to_json 与 dump 是否该合一」 | 新 | `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md` L248 | 纯计算改动、零 IO；白盒锁 caf_rr_1 |

---

## Slice 2 · 守卫族（三条全部已落地，CI 与电池双接线，勿再认领）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| GUARD-01 | `check_model_auth_no_key`：config_json/HTML 输出禁止 api_key/token 值形状 | `guard/check-model-auth-no-key` | `已落地` | `scripts/check_model_auth_no_key.py` 在跟踪面；CI 步骤 `.github/workflows/ci.yml:262`（"Model-auth-no-key guard"）；电池格 `scripts/run_guards.py:153`；`run_guards.py --list` 现读该行 `CI=CI 电池=电池` | 新 | `docs/improvement-plan-20261010.md` §6.2 | 覆盖 ci.yml / HTML / example / default-fist.mcp.json 全扫描面 |
| GUARD-02 | `check_host_installable`：deepseek-harness 宿主侧真能装 fist-mbt 插件 | `guard/check-host-installable` | `已落地` | `scripts/check_host_installable.py` 在跟踪面；CI 步骤 `.github/workflows/ci.yml:268`（"Host-installable guard"）；`--list` 现读 `CI=CI 电池=电池`（电池面由 `discover_scripts` 自动收录，不是漏接线） | 新 | 同上 | 不新增 CI 时间（一次性 smoke） |
| GUARD-03 | `check_skill_inject`：plan/claim 传 inject 时 injected_assets 非空才算命中 | `guard/check-skill-inject` | `已落地` | `scripts/check_skill_inject.py` 在跟踪面；CI 步骤 `.github/workflows/ci.yml:274`（"Skill-inject guard"）；电池格 `scripts/run_guards.py:252`（`gated`，带 `fist-mbt.db` 前置）；`--list` 现读 `CI=CI 电池=电池` | 新 | 同上 | 黑盒跑 fist-mbt MCP 自证 |

---

## Slice 3 · 多语言 SDK —— **整段作废**（与已定案 plan v0.2 正面冲突）

> 建单时这一 Slice 按字面是「三行未开工」，但**方案早已裁决过**：
> `docs/2026-10-12-fist-mbt-multilang-sdk-plan.md:17`「状态：计划 v0.2（收窄版：**砍掉 SDK 矩阵**，改为 MoonBit 原生 + HTTP 协议）」、
> `:27`「❌ 为每门语言手写 SDK 客户端（Python/TS/C#/Scala/Elixir……）→ 维护地狱，用户量≈1，**不成立**」、
> `:33`「因此本计划不再产出任何"语言 SDK 矩阵"」、`:57`「**不产出任何语言 SDK / 桥接包**」。
> 语言侧现读到的对应物是**示例面**（`docs/examples/{curl,fetch,httpclient,python,requests}`，见 `reports/2026-10-14-multilang-examples-*.md`），
> 非可安装包。**下一个照本 Slice 认领的 agent 会去写 `pyproject.toml`，而那正是 plan 判为不成立的路**——所以这三行改判 `作废`，
> 不是 `未开工`。（同步登记进文末「主机不做、副机也不做」表。）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| MULTI-01 | Python shim + 四态闭环 | `feature/multilang-sdk-python` | `作废` | plan v0.2 `:27`/`:33`/`:57` 三条裁决句点名不产出 SDK；跟踪面无 `pyproject.toml`、无 Python 包骨架（`cmd/` 仅 `cli`/`commissar`/`main`）；`scripts/mcp_compat_shim.js` 是 ESM/CJS 垫片，与本任务无关 | 新 | `docs/2026-10-12-fist-mbt-multilang-sdk-plan.md` | `pip install -e .` → `fist list` 能调 MCP（**plan 判不成立**） |
| MULTI-02 | Node.js shim + 四态闭环 | `feature/multilang-sdk-node` | `作废` | 同上裁决；`docs/examples/fetch/http_api.mjs` 是 fetch 示例，非 `npm run dev` 可跑的包 | 新 | 同上 | `npm run dev` → `fist list` 能调 MCP（**plan 判不成立**） |
| MULTI-03 | Go shim + 四态闭环 | `feature/multilang-sdk-go` | `作废` | 同上裁决；跟踪面 Go 源文件（`*.go`）与 `go.mod` 均 0 命中（`.mooncakes/` 第三方不算） | 新 | 同上 | `go run .` → `fist list` 能调 MCP（**plan 判不成立**） |

---

## Slice 4 · Web Dashboard（静态前端面板）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| WEB-01 | 任务看板（board_ascii 可视化 + DAG 图） | `feature/web-dashboard-board` | `部分` | 面板已在场：`web/index.html:47`「任务树 / DAG · 按深度缩进」，渲染 `web/app.js:140`（`renderTaskTreeHTML`）+ `web/app.js:75`（`renderStatusBarHTML` 状态分组 = 看板分组）+ `web/app.js:333`（详情面板）。**缺口**：DAG 只到文本行（`web/app.js:370`「DAG 依赖」标题 + `web/app.js:371` 上下游 `depends_on` 列表），未渲染 `dag_ascii`；`web/app.js` 内 `board` 关键字 0 命中 ⇒ 与 `board_ascii` 的分组/难度标注口径各写一份，未收口 | 新 | `docs/2026-10-12-fist-mbt-web-dashboard-plan.md` | 纯 HTML/JS 静态页；fetch MCP HTTP 端点 |
| WEB-02 | 状态流转 + 健康卡 + 脉冲三页 | `feature/web-dashboard-health` | `未开工` | `web/` 只有 4 个跟踪文件（`index.html` 76 行 / `app.js` 565 行），`index.html` 只有 2 个 `<h2>`（任务树、任务详情）；`app.js` 无 `state_flow_ascii` / `project_health` / `health_check` 视图，`:234` 只是防御式取 `status_summary` 计数 ⇒ 三页全无 | 新 | 同上 | 同上 |

---

## Slice 5 · Light Worktree Isolation（代码层 git worktree 隔离）

> **前置条件**：多租户数据隔离（`store_open` + `FIST_DB_PATH` + `scratch=true`）**已实现**，副机只做**代码隔离层**（git worktree + sparse cone + diff-scope CI 守卫）。

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| WT-01 | claimguard 挂 claim/publish 钩子（已有 src/claimguard/ 库） | `feature/claimguard-hook` | `未开工` | 库在、钩子不在：`may_proceed_full` 命中面只有 `src/claimguard/claimguard.mbt` 与其 wbtest，另有两处**字符串字面量**（`src/server/bugreport_status_wbtest.mbt:480` / `:507` 的 evidence 文本，非调用）；`src/*/moon.pkg` 无一依赖 `claimguard` ⇒ claim/publish 路径 0 个调用点 | 新 | `docs/plan-light-worktree-isolation.md` L33 + L208 | claim/publish 前走 may_proceed_full 预检 |
| WT-02 | `wt_create` / `wt_status` / `wt_destroy` 三工具（git worktree 生命周期） | `feature/wt-lifecycle-tools` | `未开工` | `wt_create` / `wt_status` / `wt_destroy` 在 `src/`、`scripts/`、`.github/` 三面 0 命中；`src/server/wt_tools.mbt` 不在跟踪面；唯一提及处是 plan 正文 `docs/plan-light-worktree-isolation.md` L158-160 | 新 | 同上 L158-160 | 纯 git 命令封装 + src/server/wt_tools.mbt |
| WT-03 | sparse cone worktree 创建 + `light-wt` / `light-wt-teardown` shell 脚本 | `feature/wt-sparse-scripts` | `未开工` | `git ls-files` 内 `light-wt*` 0 命中；`sparse` 关键字在 `scripts/`、`src/`、`.github/` 三面 0 命中 ⇒ bash/pwsh 双轨都不存在 | 新 | 同上 L147-149 | bash + pwsh 双轨可用 |
| WT-04 | e2e_assistant_xproc.py（两进程并发 claim 恰好一成一拒） | `feature/e2e-assistant-xproc` | `已落地` | 脚本在跟踪面且已进电池登记：`scripts/blackbox/e2e_assistant_xproc.py:8`「并发 N 进程同时抢主，跑多轮，任一轮出现 >1 行 is_primary=1 即 FAIL」+ 退出码契约 `:8-12`；`scripts/run_guards.py:451` 登记为跨进程端到端探针。**读法注意**：它判的是 `assistant_claim` 抢主互斥（清单原文的 "claim" 即此），若主机要的是**同一任务**并发 claim 一成一拒，那是另一格，需点名再开 | 新 | 同上 L135 | Python 脚本 + 自动化判据 |
| WT-05 | diff-scope 越界检测 + drift-check + merge-predict（CI 守卫） | `guard/check-diff-scope` | `部分` | 三件里有一件有对应物：`scripts/check_slave_mergeability.py:4-10` 给出 OK / CONFLICT(文件) / CONTAINED / EMPTY 四档（= merge-predict，且在临时 worktree 里真跑 `cherry-pick --no-commit`）。**缺**：`scripts/check_diff_scope.py` 不在跟踪面；drift-check 无对应尺（`goal_drift_check` 是任务语义层，不是文件作用域层）；`run_guards.py --list` 现读该尺 `CI=-` ⇒ 未进 CI | 新 | 同上 L186-189 + L214 | scripts/check_diff_scope.py |
| WT-06 | lock_acquire 带 worktree_id + lock_status 视图补全 | `feature/lock-wt-bind` | `未开工` | `worktree_id` 在 `src/` 全仓 0 命中 ⇒ `lock_acquire` / `lock_status` 存在但无该参数面 | 新 | 同上 L170-173 + L212 | lock_acquire 新增 worktree_id 参数 |
| WT-07 | collector 定时回收 + 磁盘水位告警 + watchdog 接线 | `feature/wt-collector` | `未开工` | `collector` / `watermark` / `disk_usage` 在 `src/`、`scripts/`、`.github/` 三面 0 命中；`watchdog_tick` 现有分支是 heal + 自动续轮 + ready_dispatch/autodispatch，不含 worktree 回收 | 新 | 同上 L199-201 + L217 | 定时任务 + watchdog_tick 集成 |

---

## Slice 6 · Ship Plan Blackbox（安装/发布缺口）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| SHIP-01 | GitCode Releases API 端点探测 + 接入 | `ci/gitcode-releases-api` | `部分` | **下载侧接了、发布侧没接**：GitCode Releases 直链已进安装器 fallback（`scripts/blackbox/install.ps1:92` 拼 `releases/download/v$Version/$Filename`、`scripts/blackbox/install.sh:118` 同形）。plan 自评逐字在 `docs/SHIP-PLAN-BLACKBOX-v2.md:65`（G3「已闭合（安装器侧）」）并同行标注「实测该直链回 **403**……"接入"≠"能用"」；`:63`（G5 附带）记「主源其实一直取不到，全靠 fallback GitHub 兜住」。**端点探测仍空**：`src/server/github_gitcode.mbt:145` 只有 `POST /api/v4/projects/{id}/issues`，全仓 `releases` 在 `src/server/*.mbt` 0 命中 | 新 | `docs/SHIP-PLAN-BLACKBOX-v2.md` G3 | gitcode_queue_status 拉通 |
| SHIP-02 | CI release.yml 加 GitCode upload step | `ci/gitcode-release-upload` | `未开工` | `grep gitcode .github/workflows/release.yml` 0 命中；release 作业只有 `softprops/action-gh-release@v2`。**且 plan 自己给了不落这条的理由**：`docs/SHIP-PLAN-BLACKBOX-v2.md:64`（G7）「仍未实现，且刻意不盲落」——只读探测 `api.gitcode.com/api/v5/*` 的 project/release 端点全 404，「不在 release.yml 加"每 tag 必跑、未实测、不可逆"的发布步」，等 API 事实与 owner 拍板 ⇒ **认领前先看这一行**，别补一条不可逆的未实测发布步 | 新 | 同上 G7 | 每次 tag 自动发 GitCode |
| SHIP-03 | install.ps1 加 Node.js 自检 + winget install 提示 | `fix/install-node-check` | `已落地` | 关键字 `winget` 与 `OpenJS.NodeJS` 同时命中安装三面：`scripts/blackbox/install.ps1`、`scripts/blackbox/install.sh`、`scripts/blackbox/install_onecmd.ps1`（后者逐字为 `❌ 需要 Node.js >=24 (winget install OpenJS.NodeJS.LTS)` 并紧随 `&lt;24` 版本校验） | 新 | 同上 L238 | 无 Node 时提示 winget OpenJS.NodeJS.LTS |

---

## Slice 7 · Polish Plan（打磨冲刺）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| POLISH-01 | README 顶部 3 行内落死一句话卖点 | `docs/polish-readme-slogan` | `已落地` | `README.md:3` 起的首屏 blockquote 即卖点（"AI 自驱式开发的项目管理者……一等的打磨对象只有两件——**自驱**与**递归拆解**"），位于徽章行之前、前 20 行内 | 新 | `docs/polish-plan.md` A | README 前 20 行可见 |
| POLISH-02 | docs/selfdrive-walkthrough.md 真实运行 trace | `docs/selfdrive-walkthrough` | `部分` | 文档在跟踪面（65 行），`:3` 自述「全部命令/JSON 均为本机 + WSL 实机执行过的真实 trace，非虚构」，§1 有 `selfdrive_*` 真实序列、§2 九态链。**两处不合格**：① 它创建于 `88a781f7`（2026-09-24，早于本清单），不是「从主机跑完的 trace 复制」这一单；② `docs/selfdrive-walkthrough.md:56` 仍写「**148 项测试** JS+Native 双端全绿」，而实测总数早已前进 ⇒ 这份 trace 的读数陈旧，属"文档即实现"律下的活口 | 新 | 同上 B | 从主机跑完的 trace 复制（副机无 FIST-Mbt MCP server 活库） |
| POLISH-03 | CI native job 去掉 continue-on-error（BUG-133 闭环） | `fix/native-ci-green` | `部分` | **测试臂已收紧**：`.github/workflows/ci.yml:409` 的 `Test (native)` 无 `continue-on-error`，`:410` 逐字写「退出码照原样退出（exit `$rc`，不加 continue-on-error）」，红只补 `::error::` 注解；`fist-ci.yml` 同规按 rc 分档退出。账本侧 `memory/bugs.md:2595` BUG-133 抬头已是 `FIXED`。**release 臂不能摘**：`scripts/check_release_asset_names.py:257` 的 R8 判据**反向要求** `build-native-linux` 必须带 `continue-on-error: true`（`.github/workflows/release.yml:105`/`:140`），摘了那把尺就红。其余残留 `continue-on-error`（`.github/workflows/ci.yml:57`/`:114`/`:171`/`:469`）分属计划落点棘轮观测臂、fmt 门、公网安装 e2e 观测臂，都不是本单点名对象 ⇒ 字面「CI native job 去掉 coe」只能达成一半，验收「干净树 `moon test --target native -j 1` 全绿」需 `git archive HEAD` 真跑才能判，本单未跑 | BUG-133 | 同上 C | 干净树 `moon test --target native -j 1` 全绿 |
| POLISH-04 | 环境要求（Node≥24 / moon ≥0.1.20261016）移到 README 最显眼处 | `docs/readme-env-bold` | `已落地` | 三格已按验收落地：① 环境要求节前移到首屏引言之后、`一源四态`之前（`README.md:20`「环境要求」）；② 节标题带 ⚠️（全文仅此一处）；③ 版本地板改为 `README.md:22`（「MoonBit ≥ 0.1.20261016」），并写明 `is` 模式匹配表达式与 `is_ok`/`is_err` 被移除的由来，与 AGENTS.md「Tooling」一致。同批补两条照 README 装环境会踩的坑：Node ≥ 24 的 `returnArrays` 退化、Windows 上 `node.cmd` 垫片吞引号（BUG-380）。顺带把测试读数 1382 同步到实测 1387（19 条声明，`check_test_sync` 现读 rc=0） | 新 | 同上 D | README "环境要求"节加 ⚠️ + 版本号 |
| POLISH-05 | docs/known-boundaries.md 主动自曝 node:sqlite 实验警告 + native 配置复杂度 | `docs/known-boundaries` | `部分` | 指定文件不在跟踪面（`git ls-files docs` 无 `known-boundaries`）。**内容其实已在规范面**：`AI-DEVELOPMENT-STANDARD.md:104` 的 `## 7. 已知边界`（含 native/BUG-133/Node≥24 权威门槛）+ `README.md:27`（「JS 后端」）+ `README.md:28`（「Native 后端」）的同款自曝 ⇒ 本单剩的是「独立可点名的文件 + 30-50 行摘要」这一层，不是从零写自曝；动手前先裁决是否该由 §7 拆分，别造第二个真源 | 新 | 同上 E | 新文件 30-50 行 |
| POLISH-06 | **拳头 Logo** + assets/ + gen_plugins 加 assets 拷贝步骤 | `feature/fist-logo-assets` | `已落地` | `assets/fist-logo.svg` + `assets/README.md` 在跟踪面；`scripts/gen_plugins.py:316` 定义 `copy_assets()`（按字节复制、不做占位符渲染）并在 `:521` 作为投影末步调用；产物四宿主齐全：`plugins/{atomcode,claude,codearts,deepseek-harness}/assets/fist-logo.svg` | 新 | `docs/improvement-plan-20261010.md` §2.2 | assets/fist-logo.svg 存在 + plugins/*/assets/ 拷贝 |

---

## Slice 8 · 其他

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `08e540bf`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| MISC-01 | **多租户命名空间 skill 文档**（原判定「已存在但内容薄」） | `docs/multi-tenant-skill-enhance` | `已落地` | 验收三要素逐项在位（150 行）：`docs/multi-tenant-mode-skill.md:3` 点名三工具与真源 `src/store/multi_store.mbt`；`:39` `data_dir` **只接受相对 server 进程 cwd 的相对路径**、库落 `{data_dir}/{ns}.db`；`:40` `scratch=true` 强制 `data_dir=temp/`；`:32` 起为逐工具参数表与调用样例，`:18` 覆盖 `store_list` 清点 / `store_close` 收尾 ⇒ 「内容薄」这一判定已过时 | 新 | AGENTS.md §多租户命名空间 | 补齐：scratch=true / data_dir 相对 cwd / store_open/store_list/store_close 三工具用法 |
| MISC-02 | **plan-light-worktree claimguard 已落地但未接** | `feature/claimguard-hook` | `未开工`（与 WT-01 同一件事） | 见 WT-01：库在、生产调用点 0。**注意这不是第二份工作**：与 WT-01 同分支名、同验收标准，认领任一即覆盖两者 | 新 | docs/plan-light-worktree-isolation.md L33 | claim/publish 走 may_proceed_full |

---

## 主机不做、副机也不做（已判定作废/不推荐）

| # | 作废项 | 原因 |
|---|---|---|
| ❌0 | **Slice 3 全部三行（MULTI-01/02/03，多语言 SDK shim）** | 2026-10-22 对账改判：plan v0.2 已裁决「砍掉 SDK 矩阵 / 不产出任何语言 SDK / 桥接包」（`docs/2026-10-12-fist-mbt-multilang-sdk-plan.md:27`/`:33`/`:57`），语言侧统一走 HTTP 协议 + `docs/examples/` 示例 |
| ❌1 | SHIP-PLAN G4（后台 hidden shim） | 与 stdio 协议冲突，plan 自身建议作废 |
| ❌2 | Star 门服务端网关（强门禁） | 需 FIST-Mbt 自备服务器，超出本仓范围 |
| ❌3 | 多账号平台托管 | 涉及厂商条款边界 + 合规审查，必须用户拍板 |
| ❌4 | 远程 agent 自动 selfdrive_publish_next 推进 PR | 主机 MR 前要做一次性收口，自动推进会把并发 WIP 带进来 |
| ❌5 | 任何涉及并发 agent 当前 WIP 文件的改动 | 副机从对账时点主线起分支，并发 WIP 在副机不可见 |
| ❌6 | POLISH-03 中「release 的 native 构建臂去掉 continue-on-error」 | `scripts/check_release_asset_names.py:257`（R8）**反向要求**该臂必须带 `continue-on-error`，摘了就是把另一条已修缺陷（BUG-111）放回去 |

---

## 对账后仍缺的一面（本清单对自己给出的建议，不是任务认领）

1. **清单面没有对表机制**：`docs/tasks/backlog/*.yaml` 有两把尺（`scripts/check_backlog_yaml_integrity.py`、
   `scripts/check_backlog_status_staleness.py`），而这份 markdown 同时被人和 AI 当认领入口，却没有任何尺把
   「状态」与「跟踪面实读」对表——所以它能长期全标 `[ ]` 而底下 8 行已落地、8 行只做了一半。建议下一单：
   加一把 `check_slave_task_list.py`，判据 = 每行 `现读证据` 列的 文件:行 锚点必须可解析且那一行含声称记号
   （本单用一次性本机脚本跑通这一判据，读数为文首那两行：结构级 41/41、内容级 40/40；脚本未入库，
   入库后这一数字必须由尺自己给出，不许再手抄），行号越界或文件缺失即红；状态列改判必须带证据，
   无证据的 `已落地` 按 R119 的 `UNPROVEN-DONE 不许无据` 判红。
2. **`部分` 与 `未开工` 的分界必须写语义差**，不许只写「有相关文件」：本表 CAF-01/CAF-02/WT-04/WT-05/WEB-01/
   SHIP-01/POLISH-02/POLISH-03/POLISH-05 九行全靠这一条才没被误判——回写点在路由不在执行结果、`e2e_assistant_xproc`
   判助理抢主不判任务 claim、`check_slave_mergeability` 只兑现 merge-predict 一档、web 有树无 `board_ascii` 口径、
   GitCode 直链接进 fallback 但实测 403、release 臂被 R8 钉住不许摘 coe。
3. **`作废` 也必须带裁决出处**：Slice 3 三行若只写「未开工」，下一位 agent 就会去建 `pyproject.toml`——
   清单与已定案 plan 相反时，**plan 赢**，并在文末作废表登记一行。
4. **POLISH-04 的版本地板不是打磨级缺陷**：README 教的工具链版本低于本仓代码实际要求的版本，
   任何按 README 起新环境的 agent 第一发 `moon check` 就崩；建议提级并纳入文档面判据（现 `check_doc_surface`
   只比「文档自述版本 == `moon.mod`」，看不见「环境要求里那条版本下限」这一格）。

---

## 主机 MR 前统一收口（主机自己做，副机等）

1. 所有副机 PR 合入后，主机跑一次完整 `gen_plugins.py` → `check_plugin_sync.py` 逐字节 diff PASS
2. 主机跑一次完整 `check_doc_surface.py`（J6/J7 文档同步）
3. 主机跑一次完整 `check_test_sync.py`（cl6 文档计数）
4. 主机跑一次 CI 全量（守卫族绿面——格数从 `run_guards --list` 汇总行现读，不在此抄数）
5. 主机 commit `merge: slave PRs (CAF writeback + light-worktree + task-list guards)`

---

## 更新日志

- **2026-10-22** 副机 R122 逐行对账（对账时点主线 `08e540bf`）：28 行全部改判并逐行落 文件:行 证据
  （自证读数：结构级锚点 41/41 可解析、内容级 40/40 那一行含声称记号，均失配 0）；
  新增「现读证据」列与状态词表（`已落地` / `部分` / `未开工` / `作废` / `无法取证`）；Slice 3 整段改判 `作废` 并登记进作废表 ❌0；
  POLISH-03 补 release 臂的 R8 反向约束；SHIP-02 补 plan G7「刻意不盲落」的认领前置警告；顺带纠正建单时的行数自述（22 → 实读 28）。
  本单不改代码、不改 CI、不动 `memory/bugs.md` 账本（编号归主机）。
- **2026-10-20** 主机创建。覆盖 improvement-plan-20261010.md / polish-plan.md / SHIP-PLAN-BLACKBOX-v2.md / plan-light-worktree-isolation.md / multi-agent-lock-v3.md / caf-p2c-wiring.md / caf-acceptance-status.md / caf-writeback-task-package.md / 多语言 SDK plan / Web Dashboard plan / OCR local integration plan / router-enhancement-plan / router-caf-learning-plan。
