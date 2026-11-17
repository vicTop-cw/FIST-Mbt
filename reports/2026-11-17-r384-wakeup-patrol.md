# 轮 384 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 由 r383 的「6 M + 2 untracked」**增至 7 M + 2 untracked**——唯一变化是 `dist/fist-mbt.js` 新变为 M：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 41402/35319 | M（**新增**：10:32:48 由中止轮再生，未提交） |
| docs/improvement-plan-20261010.md | 7/1 | M |
| memory/bugs.md | 216/0 | M（**零再增长**，r378 起冻结） |
| memory/target.md | 1/1 | M |
| scripts/README.md | 2/1 | M |
| scripts/run_guards.py | 9/0 | M |
| src/engine/engine_circuit_test.mbt | 5/0 | M（`_test.mbt`，不进入 release 构建） |
| scripts/check_mcpcf_db_isolation.py | untracked | R192 判据接线 |
| templates/pipeline_mode_loop.md | untracked | R192 模板 |

**核心 6 文件 WIP 仍冻结（240+/3-，与 r383 逐字相同、零再增长）** ⇒ 核心面**冻结第 65 轮**；`src/**` 与 `run_guards.py` 仍 M ⇒ **巡检分支，Round C 三件（BUG-527 / BUG-530 / check_usage_tool_count 注册）维持过期不执行**。

### 新发现：中止轮遗留的 dist 再生

r383（10:23:46 提交）之后的 **10:30 轮次中止**：`temp/explore_watchdog/watchdog_20261117_1030.jsonl` 尾部为
`{"type":"error","code":"reasoning_output_timeout",...}` + `{"type":"turn.completed","stop_reason":"Timeout","exit_code":1,"rounds":11,"tool_calls":18,"total_tokens":663693}`
⇒ 该轮在 11 轮 / 18 次工具调用 / 663k token 后撞 300s 推理预算上限、**未提交、未产报告**（故 r384 号空缺至本轮）。
但它已动过手：`dist/fist-mbt.js` 的 mtime = **2026-11-17 10:32:48**（该轮窗口内），diff 达 **41402+/35319-** ⇒ 中止轮**再生了 dist 交付产物却没提交**，把 WIP 面从 6 M 推到 7 M。
分类：**中止轮遗留 + r381 已记录的「刷新没自动化」缺口**，非新独立 BUG、不立新号；正确收口规格沿用 r381（`refresh_dist` → `check_dist_snapshot`/`check_deployment_freshness` 活跃面清零 → scoped 提交 `-- dist/fist-mbt.js`），留专门轮次执行（本轮不代提交他人 WIP）。

## 二、换面巡检：check_pkg_imports（本地包 import ↔ 跟踪面存在性守卫）

**为何选此面**：近 20 轮（r364~r383）换面面均未覆盖 check_pkg_imports ⇒ 不撞面。该面守的是 **2026-10-13 master 坏状态**的形状：`src/server/moon.pkg` 里 import 了一个**从未被 git add** 的本地包目录（`src/diff`），干净树 `moon check` 当场崩、CI 红在 `Migrate mooncakes dep manifests` 步（错误文本先被误读成「依赖迁移问题」）且一红 skip 其后 21 步（守卫族集体失效）。主题贴本仓最痛的接线缺口、自包含、只读、判据语义窄而清晰（只判确定性本地 import，外部依赖/模块根/`.mooncakes` 刻意不判）。

### selftest（判据健康性，先判尺子不坏）

`selftest 8/8`，`RC=0`。八格（清单从输出反解）：

| 格 | 断言 | 作用 |
|---|---|---|
| clean-no-false-positive | 1 条本地 import、0 违例 | 干净输入**不误红**（非恒红） |
| synthetic-violation-caught | P1 src/server/moon.pkg import `…/src/nonexistent`、跟踪面无 | **合成违例必红** |
| real-shape-src-diff-caught | 复刻 master 坏状态原形 | **真实形状必红**（非只认合成） |
| alias-form-ok | `@diff` 别名形式 | 别名**不误红** |
| external-deps-ignored | 外部依赖（moonbitlang/… 等） | 外部依赖**不判**（窄口径） |
| module-root-ignored | 模块根自身（无子路径） | 模块根**不判** |
| emit-fatal-returns-2 | `emit_fatal` 返 2 | 判据失灵归 2 不归 1（BUG-369 形状） |
| fatal-unusable-git-rc-is-really-2 | 子进程实测 rc=2 | git 不可用时**真 rc=2**（改前只给 1） |

⇒ **判据健康，非坏尺**（干净不误红 + 合成/真实两方向必红 + 窄口径不误伤 + 判据空转两格真 rc=2）。

### 实跑（现状面）

`RC=0`：**29 份 moon.pkg 的 40 条本地 import 指向的目录都在跟踪面**。

⇒ **本地包 import 存在性面干净**：全仓跟踪的 moon.pkg 里每条本地 import 都有对应包目录，无「改了 moon.pkg 却没 add 新包目录」的坏状态，无新发现。

## 三、例行零漂移面

- `check_tools_sync`：rc=0（server.mbt 注册 **183** 个，AGENTS/README/deliverable/scoring_rubric 对齐；R8 分组 19 组 ΣN=183）。
- `check_instruction_budget`：rc=0（AGENTS.md **50440** 字节 / 预算 65536，全部章节可见）。
- `patch_esm_main` 探针：**10 bundle 全 up to date，total patched 0**，rc=0（ESM shim 面零漂移，亦是 FIST 链路前置）。

## 四、FIST 闭环

**T0r140 六步全链 rc=0**（wd-r384 / ns watchdog / `temp/fist_r384_chain.sh` 稳健 TID 提取后台串跑，patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r140 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r384`、`assignee=wd-r384`、`deliverable=reports/2026-11-17-r384-wakeup-patrol.md`、`namespace=watchdog`、`created_at=2026-11-17T03:21:41Z` / `updated_at=2026-11-17T03:21:47Z`。

## 五、禁区与立账

- **禁区零碰**：9 个 WIP 文件（含 bugs.md、dist/fist-mbt.js、两个 untracked）零改零提交；插件态 / 构建产物 / PATH 垫片本轮均未写。
- **无新立账**：本面实跑干净无新发现；bugs.md 属 WIP 禁区不代改。dist 发现归为「中止轮遗留 + r381 已记录缺口」，非新独立 BUG、不立新号（同 BUG-636 临时立账口径）。
- **后续**：① dist 刷新规格（r381：refresh_dist → check_dist_snapshot/check_deployment_freshness 活跃面清零 → scoped 提交 `-- dist/fist-mbt.js`）仍待专门轮次执行，且**须先由 owner 确认中止轮再生的 dist 是否为正确投影 HEAD**（避免提交半成品）；② Round C 解禁后按队列执行（BUG-527 治本 → BUG-530 → check_usage_tool_count 注册）。

## 六、结论

本轮换面巡检（check_pkg_imports，本地包 import ↔ 跟踪面存在性守卫）：**判据健康**（selftest 8 格 rc=0，含干净不误红、合成/真实两方向必红、窄口径不误伤与判据空转两格真 rc=2）+ **实跑干净**（29 份 moon.pkg / 40 条本地 import 全在跟踪面，rc=0）⇒ import 存在性面无新发现、不立账。核心 WIP 冻结第 65 轮（240+/3- 零再增长）⇒ 巡检分支、Round C 三件维持过期不执行。**新发现**：r383 后的 10:30 轮次撞 300s 推理预算中止（exit_code=1，未提交），遗留 dist/fist-mbt.js 再生（41402+/35319-，10:32:48）未提交 ⇒ WIP 面 6M→7M，已按 r381 规格挂专门轮次、不代提交。例行三面（tools_sync / instruction_budget / ESM 探针）零漂移。禁区零碰、无新立账、FIST 闭环见第四节。
