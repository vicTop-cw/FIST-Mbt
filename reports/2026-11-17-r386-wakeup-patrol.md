# 轮 386 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 由 r385 的「7 M + 2 untracked」→ 本轮「**6 M + 1 untracked**」：iter-r192 三连提交
（`4a9c7a0af` / `e1ef8bbd4` / `2d920a71e`）收口了部分 WIP（improvement-plan / run_guards.py /
engine_circuit_test.mbt / check_mcpcf_db_isolation.py 落库），但**车道 F 在途**新起
`scripts/check_plan_landing.py`（+144，:864 子串排除修复）+ r192 收口报告未提交（untracked）
⇒ **iter-r192 收口进行中**。

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 76721 变更 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起） |
| memory/target.md | 1/1 | M |
| scripts/README.md | 1/1 | M |
| scripts/check_plan_landing.py | 144（+/−） | M（**新起**：iter-r192 车道 F 在途·子串排除修复） |
| templates/pipeline_mode_loop.md | 1/1 | M |
| reports/2026-11-17-iter-r192-report.md | untracked | r192 收口报告（**在途**，未提交） |

⇒ **`src/**` 与 `scripts/run_guards.py` 已解禁**（r385 确认），但 **Round C 队列（既定迭代目标）已由
r385 逐项核实全消并移交 owner 设下一目标** ⇒ 本轮无既定目标可执行，走**巡检分支**：非阻塞换面 +
FIST 闭环记账，不代设目标、不重跑已否决动作（BUG-527 治本）。WIP 面从 r384「7M+2untracked」收敛到
本轮「6M+1untracked」是三连收口 + 车道 F 在途新起的叠加，属 **iter-r192 收口进行中** 的在途 WIP
增长，非冻结面异常。

## 二、换面巡检：check_battery_count_doc（电池计数面 ↔ README 登记一致性守卫）

**为何选此面**：近 ~20 轮（r367~r385）换面面均未覆盖 check_battery_count_doc ⇒ 不撞面。该面守的是
「电池计数面与 README 登记逐键一致」——rulers / ci / battery / missing / gate / exempt /
unclassified 七键任一漂移即红。主题贴本仓最痛的计数面漂移（r192 收口② `e1ef8bbd4` 刚推进
rulers 155→156 / battery 116→117 / gate 127→128，正是这把尺守的面），只读、判据语义窄而清晰。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK: 15 格（反解：G×3 / M×11 / R，族名取自已执行格子名首段首字母，不手写计数）`，`RC=0`。

⇒ **判据健康**：15 格从已执行格子名反解（G=绿向/不误伤对照、M=机制/必红方向、R=反向/边界），
非恒红、计数不手写。

### 实跑（现状面）

`PASS 电池读数与 README 登记逐键一致：rulers=156 ci=49 battery=117 missing=0 gate=128 exempt=23 unclassified=0`，`RC=0`。

⇒ **电池计数面干净**：七键与 r192 收口②（`e1ef8bbd4`）推进后的读数逐键一致（rulers 156 /
battery 117 / gate 128），missing=0 / unclassified=0，无新发现。

## 三、例行零漂移面

- `check_tools_sync`：rc=0（server.mbt 注册 **183** 个，AGENTS/README/deliverable/scoring_rubric 对齐；R8 分组 19 组 ΣN=183）。
- `check_instruction_budget`：rc=0（AGENTS.md **50440** 字节 / 预算 65536，全部章节可见）。
- `patch_esm_main` 探针：**10 bundle 全 up to date，total patched 0**，rc=0（ESM shim 面零漂移，亦是 FIST 链路前置）。

## 四、FIST 闭环

**T0r142 六步全链 rc=0**（wd-r386 / ns watchdog / `temp/fist_r386_chain.sh` 稳健 TID 提取后台串跑，patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r142 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r386`、`assignee=wd-r386`、`deliverable=reports/2026-11-17-r386-wakeup-patrol.md`、`namespace=watchdog`、`created_at=2026-11-17T06:08:50Z` / `updated_at=2026-11-17T06:08:57Z`。

## 五、禁区与立账

- **禁区零碰**：7 个 WIP 文件（含 bugs.md、dist/fist-mbt.js、iter-r192 在途的 check_plan_landing.py 与
  untracked 报告）零改零提交；插件态 / 构建产物 / PATH 垫片本轮均未写。patch_esm_main 只动
  `_build/`（gitignore 面），不碰 dist/ WIP。
- **无新立账**：本面实跑干净无新发现；bugs.md 属 WIP 禁区不代改；Round C 队列空属「既定目标
  完成/过时、非代码缺陷」，不立 BUG 号（同 BUG-636 临时立账口径逆向）。

## 六、结论

本轮换面巡检（check_battery_count_doc，电池计数面 ↔ README 登记一致性守卫）：**判据健康**（selftest
15 格 rc=0，G×3 / M×11 / R 反解）+ **实跑干净**（七键逐键一致 rulers=156 / battery=117 / gate=128，
missing=0 / unclassified=0，rc=0）⇒ 电池计数面无新发现、不立账。WIP 面 7M+2untracked →
6M+1untracked（iter-r192 三连收口 + 车道 F 在途新起 check_plan_landing.py）⇒ **iter-r192 收口进行中**、
禁区零碰。**既定迭代目标（Round C 队列）已由 r385 移交 owner 设下一目标**，本轮不代设、不重跑已否决
动作（BUG-527 治本）。例行三面（tools_sync / instruction_budget / ESM 探针）零漂移。FIST 闭环见第四节。
