# 轮 385 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 由 r384 的「7 M + 2 untracked」**收敛为 5 M + 2 untracked**——核心 6 文件 WIP 中 `scripts/run_guards.py` / `src/engine/engine_circuit_test.mbt` / `scripts/check_mcpcf_db_isolation.py` / `templates/pipeline_mode_loop.md` / `docs/improvement-plan-20261010.md` **五件已由 iter-r192 三连提交落库**（`4a9c7a0af` / `e1ef8bbd4` / `2d920a71e`）。当前未收口面仅剩：

| 文件 | 状态 | 归属 |
|---|---|---|
| dist/fist-mbt.js | M（41402/35319，中止轮再生） | 巡检专门轮，待 owner 确认是否 HEAD 正确投影 |
| memory/bugs.md | M（+216，外来账 65+ 轮冻结） | 禁区，待 owner 解冻 |
| memory/target.md | M（1/1） | 禁区 |
| scripts/README.md | M（2/1） | iter-r192 在途 |
| scripts/check_plan_landing.py | M | iter-r192 车道 F 在途 |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 报告在途（车道 M/X/Y 未回传） |
| reports/2026-11-17-r384-wakeup-patrol.md | untracked | r384 报告（上一轮未代收） |

**关键判定**：`src/**` 与 `scripts/run_guards.py` **均不在未收口面** ⇒ 二者**已解禁**。按标准动作第 2 条本应「按 Round C 队列执行」——但经本轮逐项核实，**Round C 队列三件已全部落地或被权威裁决否决（见第二节）**，队列实际为空。

## 二、核心发现：Round C 队列（既定迭代目标）已全消

Round C 队列源自 `reports/2026-10-31-explore-r2-roundb-report.md`「遗留风险」第 2 条（等 `src/**` 解禁）：**BUG-527 治本 → BUG-530 修复 → run_guards 注册 check_usage_tool_count + USAGE 同批提交**。本轮逐项核实其终态：

| # | 队列项 | 终态 | 证据（本轮实证） |
|---|---|---|---|
| 1 | **BUG-527 治本**（13 份库包 moon.pkg 摘 cc-link-flags，集中到 3 份可执行包） | **已被权威裁决否决（治本不可执行）** | AGENTS.md「native 目标构建环境要求」段 **2026-11-02 追记3**（改判：与版本无关，单仍 OPEN）明记：A/B 实证「摘 link 的 `d43a06a28` 测试 exe 链接即死 `undefined reference to sqlite3_*`（runs 41305804775/54）」⇒ **摘 link 反而打断 CI native**。现行正确态 = **库包保留 cc-link-flags**，唯一主行动是「出路② 上游 issue（文本已备）」。本轮真实现态核查：**全部 18 份实际工程 moon.pkg 均带 cc-link-flags**（atgc / atgc-old / omega / moon.pkg / cmd/cli / cmd/main / src×9 / tests×2）⇒ 与 AGENTS.md 裁决一致，**无需任何改动**。 |
| 2 | **BUG-530 修复**（model_route 播种落盘 + executor_run 路由 config 接线） | **已 FIXED** | bugs.md :14772 `## BUG-530 ... [medium] FIXED`；修复提交 **`3699f012a`** `fix(router): BUG-530 收尾 + 播种读回锁 + custom executor argv 修通`（实证存在，动 `src/router/router_state.mbt` +104 / `src/server/model_router_ops.mbt` +48）。历史面 round10/18 多次独立确认。 |
| 3 | **run_guards.py 注册 check_usage_tool_count** + USAGE 同批 | **已落地** | `scripts/run_guards.py:175` `case("check_usage_tool_count.py")` 为**活动 case**（非注释，R59 判据面）；本轮实跑 `--selftest` = **13/13 PASS，真源=183**。 |

⇒ **结论：Round C 队列无任何可执行项。** 这是**计划指针漂移**——既定迭代目标（用户唤醒指令 + roundb「遗留风险」）仍指向一个已空队列，需要 owner 设下一目标。本轮**不代设**新目标（属 owner 决策），也不重跑已否决的 BUG-527 治本（那会直接打断 CI native，违反「FIX, DON'T HIDE」与 AGENTS.md 现行裁决）。

> 为什么 BUG-527 治本「看起来该做却绝不能做」：队列写于 2026-10-31，当时 2026-11-01 并发 agent 确实摘过一次（round14/15/16 逐核 13 库包摘净），但 CI 实测红在 `undefined reference to sqlite3_*`，2026-11-02 追记3 据此**回退**为「库包保留 link」。若本轮照旧队列再摘一次 = 重复一个已被 A/B 证伪的动作，必红 CI。这正是「读错误信息、查现行裁决」而非「照清单机械执行」的价值。

## 三、换面巡检：check_store_tables_wired（BUG-28 库内表写入点/预留守卫）

**为何选此面**：近轮换面已覆盖 check_pkg_imports（r384）、check_tools_sync / check_instruction_budget / check_battery_count_doc / check_arg_face_strict 等 ⇒ 不撞面。该面守的是「库内每张表要么有写入点、要么在 store 源文件里 `schema-reserved:` 点名预留，两个方向都发红」——主题贴本仓「接线完整性」主线，只读、自包含、纯静态。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK`，RC=0：判据对「死 schema」（有表无写入点也无预留）与「声明滞后」（预留声明与实际不符）两个方向都发红，干净输入不误红，表名解析口径可证。

### 实跑（现状面）

`PASS`，RC=0：**32 张表 = 31 张有写入点 + 1 张显式预留（runs）**。

⇒ **store schema 接线面干净**：无「建了表却没人写、也没点名预留」的死 schema，无预留声明与实际脱节的漂移，无新发现。

## 四、例行零漂移面

- `check_tools_sync`：rc=0（server.mbt 注册 **183** 个，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 169 份、历史面豁免 25 份；R8 分组 19 组 ΣN=183）。
- `patch_esm_main` 探针：**10 bundle 全 up to date，total patched 0**，rc=0（ESM shim 面零漂移，亦是 FIST 链路前置）。

## 五、FIST 闭环

**T0r141 六步全链 rc=0**（wd-r385 / ns watchdog / `temp/fist_r385_chain.sh` 稳健 TID 提取后台串跑，patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r141 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r385`、`assignee=wd-r385`、`deliverable=reports/2026-11-17-r385-wakeup-patrol.md`、`namespace=watchdog`、`created_at=2026-11-17T05:45:13Z` / `updated_at=2026-11-17T05:45:19Z`。

## 六、禁区与立账

- **禁区零碰**：7 个 WIP 文件（dist/fist-mbt.js、bugs.md、target.md、README.md、check_plan_landing.py、两个 untracked 报告）零改零提交；插件态 / 构建产物 / PATH 垫片本轮均未写。
- **无新立账**：本面实跑干净无新代码缺陷；「Round C 队列已空」是**计划指针漂移**（既定目标完成/过时），非代码 BUG、不立 BUG 号（同 BUG-636 临时立账口径的逆向——这是「无事可做」而非「有缺陷」）。
- **后续（移交 owner）**：① 设下一迭代目标（Round C 已空，既定指令与 roundb「遗留风险」指针需更新）；② dist/fist-mbt.js 刷新规格（r381：refresh_dist → check_dist_snapshot/check_deployment_freshness 活跃面清零 → scoped 提交 `-- dist/fist-mbt.js`）仍待专门轮次，且**须先由 owner 确认中止轮再生的 dist 是否为 HEAD 正确投影**；③ BUG-527 唯一主行动「出路② 上游 issue」是外部动作（moonbitlang 上游仓），属 owner/代码面项，不在巡检轮代办。

## 七、结论

本轮核心发现：**既定迭代目标（Round C 队列）已全消**——三件分别为「BUG-527 治本被 2026-11-02 A/B 裁决否决（摘 link 反断 CI，现行态=库包保留 link，已核实 18 份 moon.pkg 一致）」「BUG-530 已 FIXED（`3699f012a`）」「check_usage_tool_count 已注册（run_guards.py:175，selftest 13/13）」⇒ 属计划指针漂移，需 owner 设下一目标，本轮不代设、不重跑已否决动作。换面巡检 check_store_tables_wired：**判据健康**（selftest 双向发红 + 干净不误红）+ **实跑干净**（32 表 = 31 写入 + 1 预留，rc=0）⇒ store 接线面无新发现。例行两面无漂移（tools_sync 183 / ESM 探针 10 bundle）。`src/**` 与 `run_guards.py` 已解禁但队列空 ⇒ 无重活可派。禁区零碰、无新立账、FIST 闭环见第五节。
