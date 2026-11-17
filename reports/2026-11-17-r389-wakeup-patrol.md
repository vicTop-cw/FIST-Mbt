# 轮 389 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r388 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 76721 变更 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 67+ 轮） |
| memory/target.md | 1/1 | M（巡检 WIP，冻结面） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途：R192 T0r2 登记同步） |
| scripts/check_plan_landing.py | 144（+/−） | M（iter-r192 车道 F 在途：:864 子串排除修复 + selftest 64→71 格） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复：run_check 示例补必填 task_id/cmd，排提交③） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**，自述车道 M/X/Y 未回传） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标**（本轮现读复核：`check_usage_tool_count` 仍注册 `run_guards.py:175`、18 份真实项目
moon.pkg 全保留 cc-link-flags 与 BUG-527 治本 A/B 否决裁决一致、BUG-530 已 FIXED）⇒ 本轮无既定
目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账，不代设目标、不重跑已否决动作（BUG-527
治本，重跑必红 CI native）。

## 二、换面巡检：check_release_asset_names（分发面同源 R1~R16 · 新面）

**为何选此面**：r388 跑 check_tool_required_sync、r387 跑 check_host_installable、r386 跑
check_battery_count_doc、r385 跑 check_store_tables_wired；近 2 周（r373~r388）换面面清单里
check_release_asset_names **未覆盖** ⇒ 不撞面。该面守的是**分发面同源**——用户按文档敲的那条命令、
发布链产出的那个文件名、那条命令实际拿回来的字节，三者必须说的是同一件事（BUG-103/105/107/109/
111/112/113/114/116 一族）：资产名三处一致、版本真源 moon.mod、空值即失败、命令名两类 shell 都
可见、200/HTML/魔数检查、安装自检不假绿、发布作业不顶掉分发、工具链 bootstrap 与 CI 同源、文档线
BOM 安全、源码版本常量与 moon.mod 同源。判据「全部只看文本形状，不联网」，输入面 =
install_onecmd.ps1 / install.sh / build_release.ps1 / README.md / moon.mod / .github/workflows/，
**全避开 6 个 WIP 文件**（读的是项目 README.md，非 WIP 的 scripts/README.md）⇒ WIP-robust，CI 可
裸跑。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK（干净不误红 + 变异必红；清单从已执行格子反解：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 /
R7×3 / R8×3 / R9×6 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7）`，`RC=0`。

⇒ **判据健康**：16 条 R 判据的格子从已执行格反解，含干净不误红 + 变异必红双向，非恒绿。

### 实跑（现状面）

`PASS 分发面同源（判据范围从正文反解：R1~R16）：资产名三处一致 + 版本真源 moon.mod + 空值即失败 +
命令名两类 shell 都可见 + 200/HTML/魔数检查 + 安装自检不假绿 + 发布作业不顶掉分发 + 工具链
bootstrap 与 CI 同源 + 文档线 BOM 安全 + 源码版本常量与 moon.mod 同源 + windows 臂安装形状与
ci.yml 同源 + 发布后资产逐名比对步在位（BUG-513 出路③）`，`RC=0`。

⇒ **零漂移**：16 条 R 判据全过，分发面（文档命令 ↔ 发布资产名 ↔ 实际取回字节）完全自洽，无新发现。

## 三、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R3b/R7 扫现状面 169 份，历史面豁免 25 份（CHANGELOG 历史段/旧版
  improvement-plan）；R8 清单分组 19 组 ΣN=183（已与实测 183 对表）`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536（实际注入上限 50440）`，
  `PASS 指令文件在预算内（全部章节可见）`，`RC=0`。

## 四、FIST 闭环

**T0r145 六步全链 rc=0**（wd-r389 / ns watchdog / `temp/fist_r389_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r145 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r389`、`assignee=wd-r389`、
`deliverable=reports/2026-11-17-r389-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T10:49:54Z` / `updated_at=2026-11-17T10:50:00Z`。

## 五、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；本轮所有巡检面（patch_esm_main
  probe / check_release_asset_names / check_tools_sync / check_instruction_budget）均 WIP-robust
  只读，不写插件态 / 构建产物 / WIP 文件。patch_esm_main 探针只读 `_build/`（gitignore 面），不碰
  dist/ WIP。
- **无新立账**：换面（check_release_asset_names R1~R16）+ 零漂移两面（check_tools_sync 183 /
  check_instruction_budget 50440/65536）全零漂移、无新发现；bugs.md 属 WIP 冻结面不代改；Round C
  队列空属「既定目标完成/过时、非代码缺陷」，不立 BUG 号（同 BUG-636 临时立账口径逆向）。

## 六、结论

本轮巡检分支四面全干净：**check_release_asset_names**（新面，selftest 16 条 R 判据 + 真跑 PASS
rc=0，分发面同源 R1~R16 零漂移）⇒ 分发面（文档命令↔发布资产名↔取回字节）无新发现；**零漂移常设面**
check_tools_sync 183 / check_instruction_budget 50440/65536 均 rc=0。WIP 面 6M+1untracked 与 r388
一致 ⇒ **iter-r192 收口进行中**、禁区零碰。既定迭代目标（Round C 队列）维持 r385 移交态：不代设、
不重跑已否决动作（BUG-527 治本）。FIST 闭环见第四节。
