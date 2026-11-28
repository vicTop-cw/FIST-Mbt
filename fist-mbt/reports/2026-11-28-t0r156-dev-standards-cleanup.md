# T0r156 dev-standards 逐条扫描修（临时文件归位 + 根目录 md 定员）报告

> 依据：`fist-mbt/plans/2026-11-23-fist-project-dev-standards.md` §2.1 / §2.2 / §3
> 执行：workbuddy · 2026-11-28 · namespace=autoplan · 池任务 T0r156（管家派发）

## 结果摘要

- **扫描面**：`src/`、`docs/`（含 `docs/plans/`、`docs/proposals/`）、`fist-mbt/plans/`、`reports/`、仓库根目录，按 §2.2「临时只进 `.fist-mbt/tmp/`」与 §2.1「根目录定员」逐条对表。
- **迁移 4 项（242 个文件）→ `.fist-mbt/tmp/t0r156/`**；**删除 3 个空目录（0 文件）**；**列出 7 项不动**（活面 / 他单 WIP / 归属不明，逐条见下）。
- **根目录 .md 定员核查**：根目录全部 .md 均为守卫钉住的固定入口面 ⇒ **无散落根 .md，零 git mv，无引用需同步**。
- **门禁复跑 4 把**（publish_payload / plan_location / doc_surface / scripts_index）：全部红，逐项归因**均为他单 WIP 既有红面**，本单零引入；本单改动使 `moon publish` 泄漏面**净减 4 项**（t152.json / tmp_tools.json / scripts/README.md.tmp / tmp/ 整树移出工作树载荷面）。

## 迁移清单（→ `.fist-mbt/tmp/t0r156/`，gitignored 私有侧）

| 原路径 | 新路径 | 文件数 | 判定依据 |
|---|---|---|---|
| `/t152.json` | `t0r156/root-t152.json` | 1 | MCP JSON-RPC 响应转储（autoplan task list 查询结果），scripts/docs/reports 面零引用 |
| `/tmp_tools.json` | `t0r156/root-tmp_tools.json` | 1 | MCP `tools/list` 响应转储，零引用 |
| `/scripts/README.md.tmp` | `t0r156/scripts-README.md.tmp` | 1 | 0 字节空文件（正式版 scripts/README.md 在位），零引用；§3 规则 3 全仓面顺手件（见「超额内容」） |
| `/tmp/`（整树） | `t0r156/root-tmp/` | 239 | T0r70/T0r71 任务沙箱残留（`t0r70_msg_e2e.py` + `t0r71_sb/`：assemble1-7 脚本 + 本地 bare 远端），两任务均已验收（`reports/2026-11-25-T0r71-msg-loop-acceptance-report.md` 在位） |

## 删除清单（仅空目录，0 文件数据，git 不可见）

| 路径 | 判定依据 |
|---|---|
| `/tmp_lanej/pref/`（空）+ `/tmp_lanej/`（空） | 并发 lane 诊断目录（gitignore L43-44 点名族「tmp_lanej/ 一次性件」），内容已清空，零引用 |
| `/servicescodearts/`（空） | 无内容空目录（0 文件），零引用 |

## 列出不动（7 项 · 红线：不碰他人 WIP / 活面 / 归属不明）

| 项 | 判定 |
|---|---|
| `/temp/` | **活运行时面，禁动**：2026-11-28 当日 60 个文件改动（`butler-patrol.log`、`butler-pool-prev.json`、`explore_watchdog/watchdog_20261128_1300.jsonl`）；被 `scripts/blackbox/e2e_lock_xproc.py`（`temp/lockfix/`）、`e2e_native_heap_probe.py`（`temp/probe_*.db`）、`e2e_reserve_xproc.py`（`temp/f094/`）以 cwd 相对路径引用；迁移会打断常驻巡检进程。与 §2.2 的冲突留后续单（见后续建议 1）。存量 5389 个测试沙箱文件（b462dir_* / asvc_p0_* / b455-ns 等）留在原位 |
| `/tmp_r2draft/` | 他单 WIP 草稿（`CHANGELOG.md.new` / `ISSUES.md.new` / `moon.mod.new` / file-server 功能草稿，含 .mbt/.pkg 代码文件）——红线：不碰他人 WIP 代码文件 |
| `/website/` | 他单 WIP（未跟踪网站草稿 index.html/style.css/assets，2026-11-25） |
| `/agents/` | 他单 WIP（codearts/ + freebuff/ 服务目录，2026-11-27，与 agent-services 在途改动同族） |
| `/Nodea` | 根级符号链接 → `E:/IDEProjects/AI/Nodea`（2026-11-27 建），scripts/README/AGENTS 面零引用，归属不明 ⇒ 只列不动 |
| `/.trae-html-share-packages/` | Trae IDE 本地产物（内含 website/ 副本）。同 gitignore L279 `.trae/` 判例「只挡跟踪面，不删文件」；`.gitignore` 当前为他单 WIP（M 态），不代加条目，留后续建议 3 |
| `/.codeartsdoer/.codebase/{baseline_info,codebaseId,index_records}.json` + `.codeartsdoer/AGENTS.md` | CodeArts 工具本地状态（`upload_state.json` 为跟踪件且 M 态，同目录 WIP 面），不碰 |

（另有 `.commissar/`（§2.3 规范指定位置）、`.freebuff/`、`.freebuff-services/`、`.fist/` 等规范/ignore 面内的运行时目录，本就不属违规面，未列入。）

## 根目录 .md 定员核查（§2.1）

守卫钉住的固定入口面（代码证据）：

- `scripts/check_doc_surface.py`：`CANON = AI-DEVELOPMENT-STANDARD.md`（L135）、`AGENTS.md`（L143）、`README.md`（L144）、`USAGE.md`（L145）、`BACKLOG.md`（L146）、`CHANGELOG_MD`（L716）
- `FLOOR_REQUIRED_MOONBIT = (README.md, README_EN.md, USAGE.md, AGENTS.md)`（L1167）⇒ `README_EN.md` 为规范面
- `check_test_sync` 守卫族点名 `README.mbt.md` / `ARCHITECTURE.md`（AGENTS.md「守卫族」段）

根目录现状 .md 全量（`ls -1A` 2026-11-28 实测）：`AGENTS.md` / `AI-DEVELOPMENT-STANDARD.md` / `ARCHITECTURE.md` / `BACKLOG.md` / `CHANGELOG.md` / `README.mbt.md` / `README.md` / `README_EN.md` / `USAGE.md` —— **9 份全部落在固定面**。唯一隐藏 .md 件 `.aider.chat.history.md` 已被 `/.aider*`（gitignore L279）挡住，非公开面散落件。根目录无 `PLAN-*.md` / `ISSUE_*.md` / `项目申报书.md`（后两者在 ignore 名单但当前不存在）。

⇒ **零散落根 .md，零 git mv，无文档引用需同步。**

## 引用断链核查

- 活动引用扫描（scripts/ + docs/ + reports/ 面，grep `t152.json` / `tmp_tools.json` / `"tmp/` / `'tmp/` / `Nodea` / `servicescodearts` / `tmp_lanej`）：**零活动脚本引用**。
- 唯一指向已迁移沙箱的引用：`reports/2026-11-25-T0r71-msg-loop-acceptance-report.md` 三处指 `tmp/t0r71_sb/`（L7/L31/L158）。该报告已完稿 ⇒ 按 §3 规则 2「报告只追加、永不回写」**不回写**；新旧位置映射留档：`tmp/t0r71_sb/` → `.fist-mbt/tmp/t0r156/root-tmp/t0r71_sb/`（本机私有侧，gitignored）。
- `temp/` 面相关脚本引用（blackbox 三支 + 巡检面）：temp/ 未迁移 ⇒ 引用完好。
- `scripts/README.md.tmp`：0 字节空文件，`scripts/README.md` 正式版在位且无脚本引用 .tmp 件。

## 门禁复跑（rc 证据落盘 `.fist-mbt/tmp/t0r156/guard_*.txt`）

| 守卫 | rc | 红面归因（逐项核对） |
|---|---|---|
| `check_publish_payload` | 1 | 全部 P1 = 他单未跟踪 WIP（`src/index/*` 5 件、`website/*` 3 件、`services/fist-web-agent/pool_contact.go`、`scripts/{pool_contact,test_plan_guards}.py`、`scripts/*_hidden.vbs`/`*_wrapper.ps1`、`templates/provider-onboarding-prompt.md` 等）；本单 4 件已移出载荷面（**净减 4**） |
| `check_plan_location` | 1 | 唯一违例 `[P9] docs/proposals/2026-11-22-longrun-upgrade-proposal.md 缺强制字段 status`（他单新提案，untracked） |
| `check_doc_surface` | 1 | 他单新增 9 个 `agent_service_*` 工具后计数面漂移（真源 197 vs 自述 188：help_topics.mbt×4 + ARCHITECTURE.md + agent-map.md×3 + tool_use_rubric.md）+ `USAGE.md` 自述 0.3.15 ≠ moon.mod 0.3.16 + J7 项目申报书旧口径 + J16 漏列 9 工具名 |
| `check_scripts_index` | 1 | `pack_exe_to_md.py` 未登记 scripts/README.md —— **HEAD 既有**（`git show HEAD:scripts/README.md` 同样 0 命中，`pack_exe_to_md.py` 在 HEAD 已跟踪），非本单引入 |

⇒ **本单未引入任何路径引用断链 / 新红面**；四把守卫红面全部归属他单（工具计数同步单 / 新提案单 / WIP 入库单）。

## 任务分配记录

- 派发：管家 → workbuddy（池任务 T0r156，ns=autoplan，2026-11-28）
- 执行：workbuddy 单代理直接执行（轻任务：文件归位 + 核查，无跨模块代码改动）
- 终审：无子代理 ⇒ 验证证据 = 4 把守卫 rc（归因逐项）+ 引用 grep 零命中 + 迁移/删除前后 `ls` 复核

## 遗留风险

1. **`temp/` 活面与 §2.2「唯一临时落点」的冲突仍在**：blackbox 三脚本 + 常驻巡检（butler-patrol / explore-watchdog）以 cwd 相对 `temp/` 写盘；按规范收敛须先改脚本路径再迁旧沙箱（涉及 5389 文件）。
2. **`.fist-mbt/` 是「可随意删」的私有侧** ⇒ T0r71 沙箱证据（报告指认 `tmp/t0r71_sb/`）现仅存本机；跨机回溯若需，应先把关键读数归档到公开侧 reports/（可选，owner 定夺）。
3. **check_publish_payload 的 P1 面会随他单 WIP 持续生长**（本轮 13 条）——他单收口（入库或 ignore）前该守卫恒红，非本单可修。

## 后续建议

1. 立单：`temp/` → `.fist-mbt/tmp/` 路径迁移（改 `e2e_lock_xproc.py` / `e2e_native_heap_probe.py` / `e2e_reserve_xproc.py` + butler_patrol / explore_watchdog 巡检面，改后迁移旧沙箱 5389 文件）。
2. 计数面同步单（他单 WIP 持有方）：`cmd/cli/help_topics.mbt` / `ARCHITECTURE.md` / `docs/agent-map.md` / `templates/tool_use_rubric.md` / `USAGE.md` 的 188→197 与版本 0.3.15→0.3.16 漂移（check_doc_surface J3/J7/J14/J16 红面）。
3. `.gitignore` 补 `.trae-html-share-packages/`（同 `.trae/` 判例 L274-279）；`/website/`、`/agents/`、`/tmp_r2draft/`、`/Nodea` 归属各 WIP 单自行收口（入库或删除，勿留根级悬空）。
4. `docs/proposals/2026-11-22-longrun-upgrade-proposal.md` 补 frontmatter `status` 字段（check_plan_location P9 红面，提案单持有方）。

## 超额内容

- 附带迁移 `scripts/README.md.tmp`（0 字节）：任务扫描面列的是 src/docs/plans/reports/根目录，`scripts/` 不在列；但 §3 规则 3「临时只进 .fist-mbt/tmp/」是全仓面，0 字节空文件零风险，判为顺手件。
- 4 份守卫 rc 证据落盘 `.fist-mbt/tmp/t0r156/guard_{publish,planloc,docsurf,scriptsidx}.txt`。
- 未动 `moon test` / 编译面：本单零 .mbt 改动，无需跑测试（任务项 5 以守卫族代替 pytest 面）。

## 来源

- `fist-mbt/plans/2026-11-23-fist-project-dev-standards.md` §2.1 / §2.2 / §3（2026-11-28 通读）
- `scripts/check_doc_surface.py` L135-146 / L716 / L1167（固定面证据）；`scripts/check_plan_location.py` / `check_publish_payload.py` / `check_scripts_index.py` 2026-11-28 实测输出
- `git ls-files` / `git status` 跟踪面快照（2026-11-28，worktree dirty：大量他单 WIP）
- `reports/2026-11-25-T0r71-msg-loop-acceptance-report.md`（`tmp/t0r71_sb/` 沙箱指认）
- 管家派发任务文本（T0r156，2026-11-28）
