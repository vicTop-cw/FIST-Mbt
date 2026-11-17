# 轮 381 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务 T0r137 的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 仍为**同一组 8 文件**（6 M + 2 untracked），与 r378 逐字相同、零再增长：

| 文件 | numstat | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 7/1 | M |
| memory/bugs.md | 216/0 | M（**零再增长**，r378 起冻结） |
| memory/target.md | 1/1 | M |
| scripts/README.md | 2/1 | M |
| scripts/run_guards.py | 9/0 | M |
| src/engine/engine_circuit_test.mbt | 5/0 | M（`_test.mbt`，不进入 release 构建） |
| scripts/check_mcpcf_db_isolation.py | untracked | R192 判据接线 |
| templates/pipeline_mode_loop.md | untracked | R192 模板 |

合计 **240+/3-**，与 r378 逐字相同 ⇒ WIP 冻结，`src/**` 与 `run_guards.py` 仍 M ⇒ **巡检分支，Round C 三件（BUG-527 / BUG-530 / check_usage_tool_count 注册）维持过期不执行**。

## 二、换面巡检：check_deployment_freshness（BUG-428）

**为何选此面**：近 60+ 轮 r358~r380 换面面全未覆盖 check_deployment_freshness（`grep reports/` 全库近 25 轮换面清单零命中）⇒ 本轮首次覆盖，不撞面。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK：48 格`，`RC=0`。清单从已执行格子反解：`A×6 / D×6 / F×18 / P×6 / R×6 / S×6`。
⇒ **判据健康，非坏尺**（能红能绿，覆盖面真源=moon.pkg 反解 executable 不硬编码）。

### 实跑（现状面）

`RC=1`（检出 3 条活跃面违规）——**真发现，非误报**：

| 面 | 产物 | mtime / lag | 内容面 | 判定 |
|---|---|---|---|---|
| PATH 垫片（经 serve-launcher.cjs 跳转） | `_build\js\release\build\cmd\cli\cli.js` | 2026-11-09 21:22 / +123.8h | 3/3 | **FAIL 时间面** |
| 运行产物（release，launcher 实际执行） | 同上 | 同上 | 3/3 | **FAIL 时间面** |
| 仓内快照 | `dist\fist-mbt.js`（**tracked**） | 同上 | 3/3 | **FAIL 时间面** |
| 部署副本（旧位，BUG-437 后非运行路径） | `%LOCALAPPDATA%\FIST-Mbt\fist-mbt.js` | +469.2h | 2/3 | WARN（informational） |
| release 产物（发布包快照） | `_release\js\fist-mbt.js` | +372.8h | 3/3 | WARN（informational） |
| PATH 垫片 .cmd | `~/.local/bin/fist-mbt.cmd` | — | — | UNPROVABLE（形状不在词表） |

源码基线 `max(mtime) = cmd/cli/help_topics.mbt @ 2026-11-15 01:10`（338 份：src/cmd 的 .mbt + moon.pkg + moon.mod）。

## 三、根因取证（系统调试 Phase 1~3）

**时间面漂移是真漂移，非 mtime churn 假红**：
- 构建时间 **2026-11-09 21:22**；其后 **13 个 src 语义提交**落地，最新 **98a4111e5 @ 2026-11-15 02:07**（`fix(doc-surface): 轮 292 … 工具计数漂移 182→183`）。
- 13 提交含：commissar_gc 接线 182→183（8b1a0fd11）、BUG-470 soft flip（cfc84b616）、db_path_from_env trim（1e25dea64）、JS-FFI Array→FixedArray（4d90503c5）、mcpcf 时钟注入（75f77ffc7）等 ⇒ **构建产物确实落后 13 个语义提交**。
- **内容面 3/3**（BUG-417 稳定性标记 omega_orphan_of_archived_parent / strip_plan_annotations 等均在）⇒ 属「**没刷新**」的陈旧，非「**代码错**」；`dist/fist-mbt.js` 若现跑会报 **182 工具而非 183**（1 工具计数显示偏差，用户可感但低危）。
- **本面是近 60+ 轮首次暴露**（r358~r380 全未跑 check_deployment_freshness）⇒ 新暴露、非复发误报；陈旧已累积 ~5 天无人认领。

**已知上下文（非新独立缺陷）**：
- 账本 line 8112：BUG-428 已 **FIXED**（判据 + dist 刷新双落地）；本判据是**诊断格** `tolerant((0,1,2))`，**不挡门禁**（rc 反映本机部署状态）。
- 账本 line 15576/15621：`refresh_dist.py` **刻意不进 CI**（moonc 每次重编整体挪 ~7984 行生成标识符，「要求 dist==build(HEAD)」的门每次 src 改动都红八千行 = 恒红没人读）⇒「**刷新没自动化**」是已记录的运维缺口，「忘了刷」已被本判据当场点名。

**⇒ 分类**：真、新暴露、低危（诊断面 + 内容 3/3 + 1 工具计数显示偏差）的**部署漂移**；属 **BUG-428 残留运维面 + 已记录的「刷新没自动化」缺口**，**非新独立 BUG，不立新号**。

## 四、修复决策：留专门轮次（不立账、不空转）

**可修性核查**：WIP 唯一 src 文件 `engine_circuit_test.mbt` 为 `_test.mbt`（**不进入** `moon build --release cmd/cli`），其余 WIP 均为 docs/memory/scripts/templates（非构建路径）⇒ **此刻刷 dist 会正确投影到 HEAD 源码、不会把未完成 WIP 打进快照**（账本 line 8112 ③ 的「须在 engine/* WIP 提交后刷」约束在本树实际满足）。

**为何不在本轮巡检执行**：
1. 刷新 = `moon build --target js --release cmd/cli` + patch_esm_main + 拷贝 = **长构建 + 大 churn 提交**（~千行标识符挪位），超巡检轮 scope（step 3 标准=巡检+立账+简短收尾，不空转）；
2. **子代理无 shell 不可委派构建**（task / team 均只读）⇒ 只能指挥官亲跑 ⇒ 按金条四「跑长命令」留专门轮次作焦点，不在巡检轮顺手跑；
3. 与近 60+ 轮巡检「发现→立账→留专门轮」的稳定模式一致；
4. 低危（不挡门禁、内容 3/3），无紧迫性。

**修复规格（专门轮次照此一步到位）**：
```
python scripts/refresh_dist.py        # moon build --target js --release cmd/cli → patch_esm_main → 拷贝
# 验收：
python scripts/check_dist_snapshot.py           # rc=0（内容面 3/3）
python scripts/check_deployment_freshness.py --root .   # 活跃面 FAIL 清零
git commit -F msg.txt -- dist/fist-mbt.js       # scoped，churn 提交预期，勿带其它路径
```
前置：刷新时复核 `git status` 无非 test src WIP（当前仅 `engine_circuit_test.mbt` 脏 = 安全）；与 Round C 解禁后可同批。

## 五、例行零漂移面

- `check_tools_sync`：rc=0（server.mbt 注册 **183** 个，AGENTS/README/deliverable/scoring_rubric 对齐；R8 分组 19 组 ΣN=183）。
- `check_instruction_budget`：rc=0（AGENTS.md **50440** 字节 / 预算 65536，全部章节可见）。
- `patch_esm_main` 探针：**10 bundle 全 up to date，total patched 0**，rc=0（ESM shim 面零漂移）。

## 六、FIST 闭环

**T0r137 六步全链 rc=0**（wd-r381 / ns watchdog / `temp/fist_r381_chain.sh` 稳健 TID 提取后台串跑）：
publish rc=0 → TID=T0r137 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r381`、`deliverable=reports/2026-11-17-r381-wakeup-patrol.md`、`namespace=watchdog`。

## 七、禁区与立账

- **禁区零碰**：8 个 WIP 文件（含 bugs.md）零改零提交；插件态 / 构建产物 / PATH 垫片本轮均未写。
- **无新立账**：部署漂移属 BUG-428 残留运维面 + 已记录缺口，非新缺陷；bugs.md 属 WIP 禁区不代改。
- **后续**：专门轮次执行第四节刷新规格（刷新 + 复跑 check_deployment_freshness 确认活跃面清零）；Round C 解禁后把「刷新随收口自动跑」纳入考虑（当前刻意不自动化，见账本 line 15621）。

## 八、结论

本轮换面巡检（check_deployment_freshness，近 60+ 轮首跑）**判据健康**（selftest 48 格 PASS），**暴露 1 个真部署漂移**（3 活跃面时间面落后 5.2 天、落后 13 个 src 语义提交、内容面 3/3、tracked dist 会报 182 而非 183）——属 BUG-428 残留运维面 + 已记录的「刷新没自动化」缺口，**低危不挡门禁**，修复留专门轮次（规格已给）。例行三面（tools_sync / instruction_budget / ESM 探针）零漂移。WIP 冻结（240+/3- 零再增长）⇒ Round C 维持过期不执行。禁区零碰、无新立账、FIST 闭环 T0r137 全绿。
