# 轮 392 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r391 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | 状态 |
|---|---|
| dist/fist-mbt.js | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | M（外来账冻结，r378 起） |
| memory/target.md | M（巡检 WIP，冻结面） |
| scripts/README.md | M（iter-r192 车道 F 提交③在途：R192 T0r2 登记同步） |
| scripts/check_plan_landing.py | M（iter-r192 车道 F 在途：子串排除修复 + selftest 扩格） |
| templates/pipeline_mode_loop.md | M（J8 修复：run_check 示例补必填 task_id/cmd，排提交③） |
| reports/2026-11-17-iter-r192-report.md | untracked（iter-r192 收口报告，**在途**） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标**（BUG-527 治本被 2026-11-02 追记3 A/B 裁决否决、BUG-530 已 FIXED 3699f012a、
check_usage_tool_count 已注册 `run_guards.py:175` selftest 13/13 真源=183）⇒ 本轮无既定目标
可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账，不代设目标、不重跑已否决动作（BUG-527
治本，重跑必红 CI native）。

## 二、换面巡检（两面）

### 2.1 check_store_tables_wired（BUG-28 面：store 库表接线双向判据）

r385 跑过此面、本轮复跑作近 7 轮内的接线回归面。判据语义：store 库内**每张表**要么有写入点、
要么在 store 源文件里 `schema-reserved:` 点名预留，两个方向都发红（写入点消失 / 预留消失 / 表
无人认领都红）。

实跑：`PASS store schema 接线一致：32 张表 = 31 张有写入点 + 1 张显式预留（runs）`，`RC=0`。
与 r385 同读数 ⇒ 接线面 7 轮零漂移（期间无任何 src/store/** 改动落库）。

### 2.2 check_demo_isolation（BUG-122/124 面：spawn serve 必须改道 FIST_DB_PATH）

**为何选此面**：r391 ofm_endpoint / r390 entry_paths / r389 release_asset_names / r388
tool_required_sync / r387 host_installable / r386 battery_count_doc / r385 store_tables_wired /
r383 unit_number_unique / r382 sql_bind_alignment ⇒ 近 10 轮换面清单里 **check_demo_isolation 未
覆盖** ⇒ 不撞面。该面守的是：凡 `Popen` 起 `serve` 的脚本必须把 `FIST_DB_PATH` 交给子进程，
否则 README/USAGE 教人的裸跑命令就在往仓库根自举台账 `fist-mbt.db` 里塞演示行；豁免项必须锚点
成立；扫描面空即自拒（判据坏不报绿）。

实跑：`PASS spawn 面隔离一致：36 个脚本 spawn serve 时都把 FIST_DB_PATH 交给了子进程（显式子句
2 项 + 豁免 1 项锚点均成立）`，`RC=0`。
⚠️ 面数读数变化：**36 个 spawn 脚本**（AGENTS 摘注里写的旧数是 29 = 27 带默认改道针 + 2 显式子句
——那是摘注时的计数，随后续加脚本自然增长；摘注属历史面豁免、不在 check_demo_isolation 与
check_doc_surface 的漂移判红面内）⇒ **非缺陷、非新回归**，判据自读现状面自洽，不立账、不改摘注
（摘注改写属文档打磨面，留 owner 统一轮）。

WIP-robust：两判据均只读（store 源 / scripts 内容面），对 7 个 WIP 文件零读零写。

## 三、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R3b/R7 扫现状面 169 份，历史面豁免 25 份；R8 清单分组 19 组 ΣN=183（已与
  实测 183 对表）`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536（实际注入上限 50440）`，
  `PASS 指令文件在预算内（全部章节可见）`，`RC=0`。
- `patch_esm_main` 探针：10 bundle 全 `up to date`，`total patched: 0`，`RC=0`（防 BUG-380 垫片
  转发 + r287 型 patch 读整 bundle MemoryError；FIST 链首发前先行，非环境态）。

## 四、FIST 闭环

**T0r148 六步全链 rc=0**（wd-r392 / ns watchdog / `temp/fist_r392_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r148 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r392`、`assignee=wd-r392`、
`deliverable=reports/2026-11-17-r392-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T13:01:48Z` / `updated_at=2026-11-17T13:01:54Z`。

## 五、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；本轮所有巡检面
  （check_store_tables_wired / check_demo_isolation / check_tools_sync / check_instruction_budget /
  patch_esm_main probe）均 WIP-robust 只读。
- **无新立账**：两面换面均 PASS 零漂移；demo_isolation 的 29→36 面数增长属判据自读现状面的正常
  增长（摘注旧数为历史面，不在漂移判红面内），非代码缺陷不立账；Round C 队列空属「既定目标
  完成/过时、非代码缺陷」，不立 BUG 号（同 r385 移交态）。

## 六、结论

本轮巡检分支四面：check_store_tables_wired（32 表接线零漂移，与 r385 同读数）+
check_demo_isolation（真新面，36 脚本 spawn 隔离一致，面数 29→36 属正常增长不立账）+ 零漂移常设面
（check_tools_sync 183 / check_instruction_budget 50440/65536 / patch_esm_main 0 patch）均 rc=0。
WIP 面 6M+1untracked 与 r391 一致 ⇒ **iter-r192 收口进行中**、禁区零碰。既定迭代目标（Round C
队列）维持 r385 移交态：不代设、不重跑已否决动作（BUG-527 治本）。FIST 闭环见第四节。
