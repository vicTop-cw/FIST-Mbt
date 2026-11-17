# 轮 391 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r390 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 76721 变更 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 69+ 轮） |
| memory/target.md | 1/1 | M（巡检 WIP，冻结面） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途：R192 T0r2 登记同步） |
| scripts/check_plan_landing.py | 144（+/−） | M（iter-r192 车道 F 在途：:864 子串排除修复 + selftest 64→71 格） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复：run_check 示例补必填 task_id/cmd，排提交③） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**，自述车道 M/X/Y 未回传） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标**（本轮维持 r390 复核结论：`check_usage_tool_count` 仍注册 `run_guards.py:175`、18 份真实项目
moon.pkg 全保留 cc-link-flags 与 BUG-527 治本 A/B 否决裁决一致、BUG-530 已 FIXED）⇒ 本轮无既定
目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账，不代设目标、不重跑已否决动作（BUG-527
治本，重跑必红 CI native）。

## 二、换面巡检：check_ofm_endpoint（OFM 端点入库探活判据 · BUG-537 面 · 新面）

**为何选此面**：r390 跑 check_entry_paths、r389 跑 check_release_asset_names、r388 跑
check_tool_required_sync、r387 跑 check_host_installable、r386 跑 check_battery_count_doc、r385 跑
check_store_tables_wired、r383 跑 check_unit_number_unique、r382 跑 check_sql_bind_alignment ⇒ 近 2 周
换面面清单里 **check_ofm_endpoint 未覆盖** ⇒ 不撞面。该面守的是 **OFM 端点入库探活**（BUG-537）：
OFM 端点/密钥按纪律 env-only 不入库，但「无入库判据」导致端点失效只能静默发生（旧端点 18899 已
实际失效过一次），本判据只做一件事——探 `{FIST_OFM_ENDPOINT}/v1/models`，按 HTTP 状态分类报告。
退出码契约：`0`=探活成功（200，端点在线）/ `1`=端点不可达或非预期状态（有 env 却探不通 ⇒ 缺陷面必红）/
`2`=判据无法自证（401 未鉴权属配置问题不判红不判绿；判据自身异常同档）/ `3`=SKIP（FIST_OFM_ENDPOINT
未设置）。

### selftest（判据健康性，先判尺子不坏）

`SELFTEST OK: 10 checks (2 mutation controls)`，`RC=0`。格子：build_url basic / trailing slash /
strip /v1 + **M1 变异对照**（换成「不摘 /v1 的错实现」必须被检测）+ **M2 变异对照**（classify 把 500
误判成 ok 必须被检测）+ classify 200/401/404 + 退出码映射锁（ok→0 / down→1 / unauthorized&error→2 /
skip→3）+ CALLFACE（`main` 拒未知旗标 rc=2，argparse 天生即拒、解析发生在一切 IO 之前 ⇒ hermetic
干净）。末尾 stderr 那行 `error: unrecognized arguments: --definitely-not-real` 是 callface 格**故意**
喂未知旗标被 argparse 拒的预期行为，非判据异常。

⇒ **判据健康**：10 格含「干净不误红 + 变异必红」双向 + 退出码映射锁，非恒绿。

### 实跑（现状面）

env 存在：`FIST_OFM_ENDPOINT=http://127.0.0.1:18326/v1`（User 级持久设置，11-01 owner 授权 setx，
Machine 级为空）⇒ 判据走真探活分支（非 SKIP=3 档）。读数：
`OFM probe http://127.0.0.1:18326/v1/models -> down (unreachable: <urlopen error [WinError 10061] 由于目标计算机积极拒绝，无法连接。>)`，`RC=1`。

### 根因调查（Phase 1 · systematic-debugging）：环境态，非代码缺陷

- **18326 是 DSH dsh-desktop chanGateway relay**（Bearer 鉴权），见
  `reports/2026-10-31-ofm-relay-fullchain-report.md`——属 DSH 桌面 harness 进程的一部分，**非 FIST-Mbt
  常驻 daemon**（端点死活取决于 DSH 桌面进程是否在跑，该报告记「需重启 DSH，用户侧动作」）。
- **DSH 未在跑**：tasklist 无 dsh/harness/relay 进程（仅有的 3 个 node.exe 是 FIST MCP server 等）；
  `%APPDATA%/dsh-desktop/logs/harness.log` mtime = **Nov 3 13:52**（距本轮 2026-11-17 20:36 已
  **14 天未活动**）。
- ⇒ headless 无窗 watchdog 会话里 DSH 未起 ⇒ 18326 连接被拒是**环境态**，非 FIST-Mbt 代码缺陷。
- **与 r387、2026-11-01 同态**：r387 已探此面（`curl rc=7 + netstat 无 18326/18899 监听`，与 2026-11-01
  同态，「是否查启动方式」属 owner 待答项，不新立 BUG 号）⇒ 本轮读数与已知态一致、非新回归，按巡逻立账
  纪律**不新立 BUG 号**、记录读数。若 DSH 在跑而 relay 仍拒连，那才是 BUG-537 同族端点失效（缺陷面，
  红才对）——本轮不命中该分支。

### WIP-robust 判定

本判据**不读任何文件**（只读 `FIST_OFM_ENDPOINT` env + 网络探 `{base}/v1/models`）⇒ 结构上
WIP-robust（对 7 个 WIP 文件零读取），比 r388~r390 的换面面（读 scripts/templates/ 内容面但只读）更弱。

## 三、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R3b/R7 扫现状面 169 份，历史面豁免 25 份（CHANGELOG 历史段/旧版 improvement-plan）；
  R8 清单分组 19 组 ΣN=183（已与实测 183 对表）`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536（实际注入上限 50440）`，
  `PASS 指令文件在预算内（全部章节可见）`，`RC=0`。
- `patch_esm_main` 探针：10 bundle 全 `up to date`，`total patched: 0`，`RC=0`（防 BUG-380 垫片转发 +
  r287 型 patch 读整 bundle MemoryError）。

## 四、FIST 闭环

**T0r147 六步全链 rc=0**（wd-r391 / ns watchdog / `temp/fist_r391_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r147 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r391`、`assignee=wd-r391`、
`deliverable=reports/2026-11-17-r391-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T12:38:31Z` / `updated_at=2026-11-17T12:38:37Z`。

## 五、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；本轮所有巡检面（patch_esm_main
  probe / check_ofm_endpoint / check_tools_sync / check_instruction_budget）均 WIP-robust 只读，不写
  插件态 / 构建产物 / WIP 文件。check_ofm_endpoint 结构上不读任何文件；patch_esm_main 探针只读 `_build/`
  （gitignore 面），不碰 dist/ WIP。
- **无新立账**：换面（check_ofm_endpoint selftest 10 格健康 + 真探活 rc=1 环境态，与 r387/2026-11-01
  同态）+ 零漂移两面（check_tools_sync 183 / check_instruction_budget 50440/65536）无新代码缺陷；
  OFM down 属「headless 会话 DSH 未起」环境态，按巡逻立账纪律**不新立 BUG 号**（同 BUG-380 垫片 /
  r287 MemoryError 环境态档：非代码缺陷不立账）；bugs.md 属 WIP 冻结面不代改；Round C 队列空属
  「既定目标完成/过时、非代码缺陷」，不立 BUG 号（同 BUG-636 临时立账口径逆向）。

## 六、结论

本轮巡检分支四面：**check_ofm_endpoint**（新面，selftest 10 格 + 2 变异对照 rc=0 判据健康；真探活 rc=1——
relay 18326 down，根因调查坐实 headless watchdog 里 DSH 桌面进程未起（harness.log 14 天未活动），
**环境态、与 r387/2026-11-01 同态、不新立 BUG 号、记录读数**）⇒ OFM 端点面无新代码缺陷；**零漂移常设面**
check_tools_sync 183 / check_instruction_budget 50440/65536 / patch_esm_main 10 bundle 0 patch 均 rc=0。
WIP 面 6M+1untracked 与 r390 一致 ⇒ **iter-r192 收口进行中**、禁区零碰。既定迭代目标（Round C 队列）
维持 r385 移交态：不代设、不重跑已否决动作（BUG-527 治本）。FIST 闭环见第四节。
