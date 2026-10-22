# FIST-Mbt 副机（Slave Agent）任务清单

> **主机** 2026-10-20 创建。副机认领时对目标行把状态改成 `[working]` 并 commit 认领。
> **每个任务** = 一个独立分支 = 一个独立 PR = 四态闭环。
> **2026-10-22 逐行对账（副机 R122，基点 `105e6071`）**：下表 `状态` 与 `现读证据` 两列是**对账时点的仓内实读**，
> 不是计划、不是转述——每条都指到 文件:行 或跟踪面文件名，可逐条复核。
> 状态词表：`已落地` / `部分` / `未开工` / `无法取证`（后者只在确实拿不到证据时使用，必须写明缺哪一面）。
> **为什么要有这一列**：对账前 22 行全标 `[ ]`（未认领），而其中 GUARD-01/02/03、SHIP-03、POLISH-01/02/03/06、
> MISC-01 早已在主线落地并挂在 CI 上——下一个照清单认领的 agent 会重做已完成的东西。
> 本仓对这一形状早有判据（`bug_list` 的 `open_with_linked_done`：「账本说没修、任务库说修完了」），
> 清单面此前没有对表机制，所以它会红着没人读。

---

## Slice 1 · CAF 写回（读半已落地，写半只落了降级锁）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| CAF-01 | `executor_run` 成功后 `caf_memory.push` 回写 + caf_dr_6 bad-JSON 降级锁 | `feature/caf-writeback-slice-b` | `部分` | 降级锁那一半已在场：`src/server/model_router_ops.mbt:115`（`bad_json` 只计数告警、不删不覆盖）+ 白盒锁 `src/server/model_router_ops_wbtest.mbt:749`（`caf_dr_6_坏记忆JSON降级不panic`）。写回那一半未接：全仓 `mr_caf_push_evidence` 唯一调用点是 `src/server/model_router_ops.mbt:463`，即 `model_route(record_model)` 路径；`executor_run` 通道（注册与实现见 `src/server/server.mbt:7066` / `:7130`）内不出现任何 caf 调用 ⇒ 执行结果证据没有回灌 | 新 | `docs/2026-10-17-caf-writeback-task-package.md` Slice B | moon fmt/check/test 全绿；主机 MR 前 run_check |
| CAF-02 | `CafMemory::to_json` 补充原始 records 字段（R45 缺口） | `feature/caf-raw-records` | `未开工` | `src/router/router_caf.mbt:220` 的 `to_json` 只出四个键：`total_records` / `capacity` / `count` / `by_model`（后者是聚合统计），原始记录面未导出；任务点名的白盒锁 `caf_rr_1` 在 `src/` 全仓 0 命中 | 新 | `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md` L248 | 纯计算改动、零 IO；白盒锁 caf_rr_1 |

---

## Slice 2 · 守卫族（三条全部已落地并挂 CI，勿再认领）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| GUARD-01 | `check_model_auth_no_key`：config_json/HTML 输出禁止 api_key/token 值形状 | `guard/check-model-auth-no-key` | `已落地` | `scripts/check_model_auth_no_key.py` 在跟踪面；CI 步骤 `.github/workflows/ci.yml:262`（"Model-auth-no-key guard"）；电池格 `scripts/run_guards.py:153` | 新 | `docs/improvement-plan-20261010.md` §6.2 | 覆盖 ci.yml / HTML / example / default-fist.mcp.json 全扫描面 |
| GUARD-02 | `check_host_installable`：deepseek-harness 宿主侧真能装 fist-mbt 插件 | `guard/check-host-installable` | `已落地` | `scripts/check_host_installable.py` 在跟踪面；CI 步骤 `.github/workflows/ci.yml:268`（"Host-installable guard"） | 新 | 同上 | 不新增 CI 时间（一次性 smoke） |
| GUARD-03 | `check_skill_inject`：plan/claim 传 inject 时 injected_assets 非空才算命中 | `guard/check-skill-inject` | `已落地` | `scripts/check_skill_inject.py` 在跟踪面；CI 步骤 `.github/workflows/ci.yml:274`（"Skill-inject guard"）；电池格 `scripts/run_guards.py:252`（`gated`，带 `fist-mbt.db` 前置） | 新 | 同上 | 黑盒跑 fist-mbt MCP 自证 |

---

## Slice 3 · 多语言 SDK（cmd/ 下新增多语言 shim）

> **对账补一句以免误读**：`docs/examples/` 下**已有**五支语言调用示例（`curl/http_api.sh`、`fetch/http_api.mjs`、
> `httpclient/http_api.cs`、`python/http_client.py`、`requests/http_api.py`，见 `reports/2026-10-14-multilang-examples-*.md`），
> README:275 / AGENTS.md 自述的「五语言接入示例」指的就是这一面。
> 本 Slice 要求的不是示例，而是**可安装 shim + 四态闭环**（`pip install -e .` → `fist list` 真调 MCP）——这一面仍未开工。

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| MULTI-01 | Python shim + 四态闭环 | `feature/multilang-sdk-python` | `未开工` | `git ls-files cmd` 只有 `cmd/cli` / `cmd/commissar` / `cmd/main`；无 `sdk/`、无 Python 包骨架（根目录仅有 `pipeline_tick_cron.py` / `watchdog_tick_cron.py` 两支定时脚本，非可安装包）；`scripts/mcp_compat_shim.js` + `scripts/test_shim_handshake.py` 是 JS 兼容垫片与握手测试，不构成本任务的 Python shim | 新 | `docs/2026-10-12-fist-mbt-multilang-sdk-plan.md` | `pip install -e .` → `fist list` 能调 MCP |
| MULTI-02 | Node.js shim + 四态闭环 | `feature/multilang-sdk-node` | `未开工` | 同上：跟踪面无 Node SDK 包（`package.json` 骨架不存在于 `cmd/`/`sdk/`）；`scripts/mcp_compat_shim.js` 只解决 ESM/CJS 桩问题，非 CLI 封装 | 新 | 同上 | `npm run dev` → `fist list` 能调 MCP |
| MULTI-03 | Go shim + 四态闭环 | `feature/multilang-sdk-go` | `未开工` | 跟踪面内 Go 源文件（`*.go`）与 `go.mod` 均 0 命中；唯一非 MoonBit 语言产物是 `docs/examples/httpclient/http_api.cs`（示例，不可安装） | 新 | 同上 | `go run .` → `fist list` 能调 MCP |

---

## Slice 4 · Web Dashboard（静态前端面板）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| WEB-01 | 任务看板（board_ascii 可视化 + DAG 图） | `feature/web-dashboard-board` | `部分` | 面板已在场：`web/index.html:47` 有「任务树 / DAG · 按深度缩进」视图，渲染函数 `web/app.js:140`（`renderTaskTreeHTML`）+ `web/app.js:75`（`renderStatusBarHTML` 按状态分组，即看板分组）+ 任务详情面板 `web/app.js:333`。**缺口**：DAG 是缩进树而非图形；`web/app.js` 内 `board` 关键字 0 命中 ⇒ 未与 `board_ascii` 口径对齐（同一份分组/难度标注逻辑两处各写一份的风险还在） | 新 | `docs/2026-10-12-fist-mbt-web-dashboard-plan.md` | 纯 HTML/JS 静态页；fetch MCP HTTP 端点 |
| WEB-02 | 状态流转 + 健康卡 + 脉冲三页 | `feature/web-dashboard-health` | `未开工` | `web/app.js`（565 行）与 `web/index.html`（76 行）内 `health` / `pulse` / `state_flow` 消费点 0 命中 ⇒ `project_health` / `status_summary` / `state_flow_ascii` 三工具的面板页不存在 | 新 | 同上 | 同上 |

---

## Slice 5 · Light Worktree Isolation（代码层 git worktree 隔离）

> **前置条件**：多租户数据隔离（`store_open` + `FIST_DB_PATH` + `scratch=true`）**已实现**，副机只做**代码隔离层**（git worktree + sparse cone + diff-scope CI 守卫）。
> 对账补：`src/claimguard/` 库本体（5 个 .mbt）确实在跟踪面，但**没有任何生产调用点**——见 WT-01 行。

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| WT-01 | claimguard 挂 claim/publish 钩子（已有 src/claimguard/ 库） | `feature/claimguard-hook` | `未开工` | 库在、钩子不在：`may_proceed_full` 的命中面只有 `src/claimguard/claimguard.mbt` 与其 wbtest，另有两处**字符串字面量**（`src/server/bugreport_status_wbtest.mbt:480` / `:507` 的 evidence 文本，非调用）⇒ claim/publish 路径 0 个调用点 | 新 | `docs/plan-light-worktree-isolation.md` L33 + L208 | claim/publish 前走 may_proceed_full 预检 |
| WT-02 | `wt_create` / `wt_status` / `wt_destroy` 三工具（git worktree 生命周期） | `feature/wt-lifecycle-tools` | `未开工` | `wt_create` / `wt_status` / `wt_destroy` 在 `src/` 全仓 0 命中；`src/server/wt_tools.mbt` 不在跟踪面 | 新 | 同上 L158-160 | 纯 git 命令封装 + src/server/wt_tools.mbt |
| WT-03 | sparse cone worktree 创建 + `light-wt` / `light-wt-teardown` shell 脚本 | `feature/wt-sparse-scripts` | `未开工` | `git ls-files` 内 `light-wt*` 0 命中（bash/pwsh 双轨都不存在） | 新 | 同上 L147-149 | bash + pwsh 双轨可用 |
| WT-04 | e2e_assistant_xproc.py（两进程并发 claim 恰好一成一拒） | `feature/e2e-assistant-xproc` | `部分` | 脚本在跟踪面且判据可跑：`scripts/blackbox/e2e_assistant_xproc.py:8`「并发 N 进程同时抢主，跑多轮，任一轮出现 >1 行 is_primary=1 即 FAIL」。**语义差**：它判的是**助理选举互斥**（`assistant_claim`），不是本任务点名的「同一任务并发 claim 一成一拒」；相邻的 `e2e_lock_xproc.py` / `e2e_reserve_xproc.py` 已存在，缺的正是 task-claim 那一格 | 新 | 同上 L135 | Python 脚本 + 自动化判据 |
| WT-05 | diff-scope 越界检测 + drift-check + merge-predict（CI 守卫） | `guard/check-diff-scope` | `未开工` | `scripts/check_diff_scope.py` 不在跟踪面；`drift.check` / `merge.predict` 相关命中面只有 `memory/research/20260926.goal-drift-check.md` 与对应报告（研究文档，非尺子） | 新 | 同上 L186-189 + L214 | scripts/check_diff_scope.py |
| WT-06 | lock_acquire 带 worktree_id + lock_status 视图补全 | `feature/lock-wt-bind` | `未开工` | `worktree_id` 在 `src/` 全仓 0 命中（`lock_acquire` / `lock_status` 存在但无该参数面） | 新 | 同上 L170-173 + L212 | lock_acquire 新增 worktree_id 参数 |
| WT-07 | collector 定时回收 + 磁盘水位告警 + watchdog 接线 | `feature/wt-collector` | `未开工` | `git ls-files` 内 collector 面 0 命中（跟踪面无回收脚本/水位告警）；`watchdog_tick` 的现有分支是 heal + 自动续轮，不含 worktree 回收 | 新 | 同上 L199-201 + L217 | 定时任务 + watchdog_tick 集成 |

---

## Slice 6 · Ship Plan Blackbox（安装/发布缺口）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| SHIP-01 | GitCode Releases API 端点探测 + 接入 | `ci/gitcode-releases-api` | `未开工` | `releases` 在 `src/server/*.mbt` 0 命中；`gitcode_queue_status` 读的是本地 pending 队列（`bugs_pending_github.jsonl`），不含 Releases 端点探测；命中 `releases` 的只有安装侧脚本（`scripts/blackbox/install*` / `upgrade_install.ps1`）与 `src/claimguard` 无关文本 | 新 | `docs/SHIP-PLAN-BLACKBOX-v2.md` G3 | gitcode_queue_status 拉通 |
| SHIP-02 | CI release.yml 加 GitCode upload step | `ci/gitcode-release-upload` | `未开工` | `.github/workflows/release.yml` 内 `gitcode` / `GitCode` 0 命中 | 新 | 同上 G7 | 每次 tag 自动发 GitCode |
| SHIP-03 | install.ps1 加 Node.js 自检 + winget install 提示 | `fix/install-node-check` | `已落地` | 关键字 `winget` 与 `OpenJS.NodeJS` 同时命中安装三面：`scripts/blackbox/install.ps1`、`scripts/blackbox/install.sh`、`scripts/blackbox/install_onecmd.ps1` ⇒ 无 Node 时给出 winget 提示（安装器随 release 资产打包分发） | 新 | 同上 L238 | 无 Node 时提示 winget OpenJS.NodeJS.LTS |

**已作废项**：SHIP-PLAN G4（后台 hidden shim）—— 与 stdio 协议冲突，主机判定作废，**不要做**。

---

## Slice 7 · Polish Plan（打磨冲刺）

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| POLISH-01 | README 顶部 3 行内落死一句话卖点 | `docs/polish-readme-slogan` | `已落地` | `README.md:3-4`：首屏 blockquote 两行即为卖点（"AI 自驱式开发的项目管理者……一等的打磨对象只有两件——自驱与递归拆解"），位于徽章行之前、前 12 行内 | 新 | `docs/polish-plan.md` A | README 前 20 行可见 |
| POLISH-02 | docs/selfdrive-walkthrough.md 真实运行 trace | `docs/selfdrive-walkthrough` | `已落地` | `docs/selfdrive-walkthrough.md` 在跟踪面（65 行），`:3-4` 自述「全部命令/JSON 均为本机 + WSL 实机执行过的真实 trace，非虚构」，§1 起为逐条真实调用回放 | 新 | 同上 B | 从主机跑完的 trace 复制（副机无 FIST-Mbt MCP server 活库） |
| POLISH-03 | CI native job 去掉 continue-on-error（BUG-133 闭环） | `fix/native-ci-green` | `已落地` | `.github/workflows/ci.yml:409` 的 `Test (native)` 步**无** `continue-on-error`，`:410` 逐字写明「退出码照原样退出（exit `$rc`，不加 continue-on-error）」，红只补 `::error::` 注解。仓内残留的 `continue-on-error` 分属另三处：`.github/workflows/ci.yml:57`/`:171`（计划落点棘轮观测臂）、`.github/workflows/ci.yml:114`（fmt 门）、`.github/workflows/ci.yml:469`（`e2e_irm_line` 公网观测臂）、`.github/workflows/release.yml:105`/`:140`（native 资产可选）——都不是本任务点名的 native 测试格 | BUG-133 | 同上 C | 干净树 `moon test --target native -j 1` 全绿 |
| POLISH-04 | 环境要求（Node≥24 / moon ≥0.1.20261016）移到 README 最显眼处 | `docs/readme-env-bold` | `未开工` | 两格都不满足：① `README.md:216` 的「环境要求」仍在正文中段（第 216 行，非最显眼处、无 ⚠️）；② **版本地板自相矛盾**——`README.md:220` 写「MoonBit ≥ 0.1.20260827」，而 AGENTS.md「Tooling」与本仓钉版要求 **≥ 0.1.20261016**（`is` 模式匹配表达式依赖此版）。照 README 装环境的 agent 会拿到一个编不过 d799f56 之后代码的工具链 | 新 | 同上 D | README "环境要求"节加 ⚠️ + 版本号 |
| POLISH-05 | docs/known-boundaries.md 主动自曝 node:sqlite 实验警告 + native 配置复杂度 | `docs/known-boundaries` | `未开工` | `docs/known-boundaries.md` 不在跟踪面（`git ls-files docs` 无命中）；同类内容目前散在 README.md:222-227 与 `AI-DEVELOPMENT-STANDARD.md` §7，但没有可点名的独立自曝文件 | 新 | 同上 E | 新文件 30-50 行 |
| POLISH-06 | **拳头 Logo** + assets/ + gen_plugins 加 assets 拷贝步骤 | `feature/fist-logo-assets` | `已落地` | `assets/fist-logo.svg` + `assets/README.md` 在跟踪面；`scripts/gen_plugins.py:316` `copy_assets()`（按字节复制、不做占位符渲染）并在 `:521` 作为投影末步调用；产物面 `plugins/{atomcode,claude,codearts,...}/assets/fist-logo.svg` 已入库 | 新 | `docs/improvement-plan-20261010.md` §2.2 | assets/fist-logo.svg 存在 + plugins/*/assets/ 拷贝 |

---

## Slice 8 · 其他

| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 `105e6071`） | 主机账本 bug_id | 参考 plan | 验收标准 |
|---|---|---|---|---|---|---|---|
| MISC-01 | **多租户命名空间 skill 文档**（原判定「已存在但内容薄」） | `docs/multi-tenant-skill-enhance` | `已落地` | 验收三要素齐备（150 行）：`docs/multi-tenant-mode-skill.md:3` 点名三工具 + 真源 `src/store/multi_store.mbt`；`:39` `data_dir` **只接受相对 server 进程 cwd 的相对路径**、库落 `{data_dir}/{ns}.db`；`:40` `scratch=true` 强制 `data_dir=temp/`；`:18` `store_list` 清点 / `store_close` 收尾；`:32` 起为逐工具用法段 | 新 | AGENTS.md §多租户命名空间 | 补齐：scratch=true / data_dir 相对 cwd / store_open/store_list/store_close 三工具用法 |
| MISC-02 | **plan-light-worktree claimguard 已落地但未接** | `feature/claimguard-hook` | `未开工`（同 WT-01） | 见 WT-01：库在、生产调用点 0 | 新 | docs/plan-light-worktree-isolation.md L33 | claim/publish 走 may_proceed_full |

---

## 主机不做、副机也不做（已判定作废/不推荐）

| # | 作废项 | 原因 |
|---|---|---|
| ❌1 | SHIP-PLAN G4（后台 hidden shim） | 与 stdio 协议冲突，plan 自身建议作废 |
| ❌2 | Star 门服务端网关（强门禁） | 需 FIST-Mbt 自备服务器，超出本仓范围 |
| ❌3 | 多账号平台托管 | 涉及厂商条款边界 + 合规审查，必须用户拍板 |
| ❌4 | 远程 agent 自动 selfdrive_publish_next 推进 PR | 主机 MR 前要做一次性收口，自动推进会把并发 WIP 带进来 |
| ❌5 | 任何涉及并发 agent 当前 WIP 文件的改动 | 副机从对账时点主线起分支，并发 WIP 在副机不可见 |

---

## 对账后仍缺的一面（本清单自己给出的建议，不是任务认领）

1. **清单面没有对表机制**：`docs/tasks/backlog/*.yaml` 有两把尺（`check_backlog_yaml_integrity.py` /
   `check_backlog_status_staleness.py`），而这份 markdown 清单同时被人和 AI 当输入面，却没有任何尺把
   「状态」与「跟踪面实读」对表——所以它能长期全标 `[ ]` 而底下 10 项已落地。建议下一单：
   给清单加一把 `check_*`（状态列 ↔ 证据列指向的文件是否存在 / commit 是否在主线），红面写法照 R119 的
   `UNPROVEN-DONE 不许无据`。
2. **`部分` 与 `未开工` 的分界必须写语义差**，不许只写「有相关文件」：本表 WT-04、WEB-01、CAF-01 三行
   就是靠这一条才没被误判成 `已落地`（`e2e_assistant_xproc.py` 判选举不判任务 claim；web 面板有树没 board_ascii 口径；
   CAF 有降级锁没执行回写）。
3. **POLISH-04 的版本地板是活口风险**，不属于打磨级别：README 教的工具链版本低于本仓代码实际要求的版本，
   任何按 README 起新环境的 agent 第一发 `moon check` 就崩。建议优先级高于本 Slice 其余项。

---

## 主机 MR 前统一收口（主机自己做，副机等）

1. 所有副机 PR 合入后，主机跑一次完整 `gen_plugins.py` → `check_plugin_sync.py` 逐字节 diff PASS
2. 主机跑一次完整 `check_doc_surface.py`（J6/J7 文档同步）
3. 主机跑一次完整 `check_test_sync.py`（cl6 文档计数）
4. 主机跑一次 CI 全量（守卫族绿面——格数从 `run_guards --list` 汇总行现读，不在此抄数）
5. 主机 commit `merge: slave PRs (CAF writeback + multilang-sdk + light-worktree)`

---

## 更新日志

- **2026-10-22** 副机 R122 逐行对账（基点 `105e6071`）：22 行全部改判并逐行落 文件:行 证据；新增「现读证据」列与
  状态词表（`已落地` / `部分` / `未开工` / `无法取证`）；Slice 3 补「示例面 ≠ shim」防误读段；新增「对账后仍缺的一面」
  建议节。本单不改代码、不改 CI、不动 `memory/bugs.md` 账本（编号归主机）。
- **2026-10-20** 主机创建。覆盖 improvement-plan-20261010.md / polish-plan.md / SHIP-PLAN-BLACKBOX-v2.md / plan-light-worktree-isolation.md / multi-agent-lock-v3.md / caf-p2c-wiring.md / caf-acceptance-status.md / caf-writeback-task-package.md / 多语言 SDK plan / Web Dashboard plan / OCR local integration plan / router-enhancement-plan / router-caf-learning-plan。
