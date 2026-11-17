# 轮 390 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r389 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 76721 变更 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 68+ 轮） |
| memory/target.md | 1/1 | M（巡检 WIP，冻结面） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途：R192 T0r2 登记同步） |
| scripts/check_plan_landing.py | 144（+/−） | M（iter-r192 车道 F 在途：:864 子串排除修复 + selftest 64→71 格） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复：run_check 示例补必填 task_id/cmd，排提交③） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**，自述车道 M/X/Y 未回传） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标**（本轮维持 r389 复核结论：`check_usage_tool_count` 仍注册 `run_guards.py:175`、18 份真实项目
moon.pkg 全保留 cc-link-flags 与 BUG-527 治本 A/B 否决裁决一致、BUG-530 已 FIXED）⇒ 本轮无既定
目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账，不代设目标、不重跑已否决动作（BUG-527
治本，重跑必红 CI native）。

## 二、换面巡检：check_entry_paths（入口/产物路径面 · 新面）

**为何选此面**：r389 跑 check_release_asset_names、r388 跑 check_tool_required_sync、r387 跑
check_host_installable、r386 跑 check_battery_count_doc、r385 跑 check_store_tables_wired、r383 跑
check_unit_number_unique、r382 跑 check_sql_bind_alignment、r381 跑 check_deployment_freshness、
r380 跑 check_hardcoded_paths、r378 跑 check_mbti_eol ⇒ 近 2 周换面面清单里 **check_entry_paths
未覆盖** ⇒ 不撞面。该面守的是**现状面命令与产物路径不得指退役入口**（BUG-93/101）——用户 clone
下来会照跑的那批文件里，命令与产物路径必须指向现役入口、`Popen([node, cli.js])` 的 argv 必须带
serve、不得用裸相对路径寻址产物。入口清单从 `cmd/*/moon.pkg` 的 `pkgtype(kind: "executable")` 反解
（cmd/cli, cmd/commissar, cmd/main）、发布入口从 `scripts/blackbox/build_release.ps1` 的 `moon build`
反解（cmd/cli）、退役入口 = 入口 − 发布 = {cmd/commissar, main}。判据「全部只看文本形状，不联网」，
输入面 = SCAN_ROOTS（scripts / docs / .github / templates / stories / plugins/source / cmd）+ 仓库根
.md / .mcp* / **已入库**的 .py（未入库的根 .py 按「是否入库」门放下并点名，避免本机红 CI 绿两套口径），
历史面（memory/ reports/ docs/superpowers/ CHANGELOG.md）与守卫自身豁免。

### WIP-robust 判定

SCAN_ROOTS 含 `scripts/` 与 `templates/`（WIP 所在目录）⇒ 本判据**会读到 3 个 WIP 文件的正文**，但
它是**只读**（`io.open` 读，零写），且本轮 3 个 WIP 改动——`check_plan_landing.py` 的 disk_set 子串→
路径段修复、`scripts/README.md` 的登记行、`pipeline_mode_loop.md` 的 run_check 示例补参——**均不引入
任何退役入口的可执行指向**（判据只认命令/产物路径形状，散文与整行注释/docstring 豁免）⇒ 读数不被
WIP 污染，与 r389 同口径成立 WIP-robust（读内容面但 WIP 改动不命中判据面）。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK（17 格）`，`RC=0`。格子清单从输出反解（不手写计数）：R1 夹具命中 2 / 干净不误红 / 空清单
报空转 / R2 成对 / 根 .py 选取（入库留·未入库点名）/ 根 .py 入面且活代码必红 / 根 .py 只改注释不误红 /
取不到 git 反向兜底 / R3 裸相对产物必红 / R3 合法 join / cwd=ROOT 不误红 / R3 只改注释不误红 / R3 扫描面
计数承重 / e2e 退役入口 5 格（comment-not-flagged / code-flagged / docstring-exempt-does-not-weaken-code-face /
user-face-still-flagged / docstring-line-splitter）。

⇒ **判据健康**：17 格含「干净不误红 + 变异必红」双向 + e2e 真实形状对照，非恒绿。

### 实跑（现状面）

`入口清单：cmd/cli, cmd/commissar, cmd/main｜发布 cmd/cli｜退役 cmd/commissar, main｜扫描面 391 份（历史面
除外）` + `注：仓库根另有 1 份未入库的 .py 未判（本机临时件，CI 检出里不存在）：execute_cron.py`
+ `PASS R1 退役入口引用 0 处、R2 缺 serve 启动器 0 个、R3 裸相对产物寻址 0 处（扫描面 391 份文件，历史面
与守卫自身除外）`，`RC=0`。

⇒ **零漂移**：391 份现状面文件里退役入口可执行指向 0 处、缺 serve 启动器 0 个、裸相对产物寻址 0 处；
入口清单（cmd/cli·commissar·main）与发布入口（cmd/cli）同源、退役面 {cmd/commissar, main} 零误用，
无新发现。

## 三、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R3b/R7 扫现状面 169 份，历史面豁免 25 份；R8 清单分组 19 组 ΣN=183（已与实测
  183 对表）`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536（实际注入上限 50440）`，
  `PASS 指令文件在预算内（全部章节可见）`，`RC=0`。

## 四、FIST 闭环

**T0r146 六步全链 rc=0**（wd-r390 / ns watchdog / `temp/fist_r390_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r146 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r390`、`assignee=wd-r390`、
`deliverable=reports/2026-11-17-r390-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T11:42:22Z` / `updated_at=2026-11-17T11:42:30Z`。

## 五、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；本轮所有巡检面（patch_esm_main
  probe / check_entry_paths / check_tools_sync / check_instruction_budget）均 WIP-robust 只读，不写
  插件态 / 构建产物 / WIP 文件。patch_esm_main 探针只读 `_build/`（gitignore 面），不碰 dist/ WIP。
- **无新立账**：换面（check_entry_paths 391 份现状面 R1/R2/R3 全 0）+ 零漂移两面（check_tools_sync
  183 / check_instruction_budget 50440/65536）全零漂移、无新发现；bugs.md 属 WIP 冻结面不代改；
  Round C 队列空属「既定目标完成/过时、非代码缺陷」，不立 BUG 号（同 BUG-636 临时立账口径逆向）。

## 六、结论

本轮巡检分支四面全干净：**check_entry_paths**（新面，selftest 17 格 + 真跑 PASS rc=0，391 份现状面
R1 退役入口引用 0 / R2 缺 serve 启动器 0 / R3 裸相对产物寻址 0，入口·发布·退役三面同源）⇒ 入口/产物
路径面无新发现；**零漂移常设面** check_tools_sync 183 / check_instruction_budget 50440/65536 均 rc=0。
WIP 面 6M+1untracked 与 r389 一致 ⇒ **iter-r192 收口进行中**、禁区零碰。既定迭代目标（Round C 队列）
维持 r385 移交态：不代设、不重跑已否决动作（BUG-527 治本）。FIST 闭环见第四节。
