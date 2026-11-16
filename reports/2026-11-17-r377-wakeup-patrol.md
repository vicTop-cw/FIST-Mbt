# 轮 377 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

- 日期：2026-11-17
- 轮次：377（第 58 轮 WIP 静止态）
- FIST 闭环：T0r133 / agent `wd-r377` / ns `watchdog`

## 结果摘要

WIP 非冻结增长后**静止第 58 轮**：`git status --short` 仍为同一组 8 文件
（6 个已跟踪 M + 2 个 untracked），`src/engine/engine_circuit_test.mbt` 与
`scripts/run_guards.py` 仍 M ⇒ **Round C 三件维持过期不执行**（BUG-527 治本 /
BUG-530 修复 / run_guards 注册 check_usage_tool_count 均未解禁）。

本轮走**巡检分支**，换面巡检 **`check_esm_bundle_runnable`**（R182/BUG-406
打包产物「真能跑」判据，r376 点名候选之一、**近 120 轮未用面**：B1 产物存在且
非空 / B2 垫片在场（bundle 含 `require(` 必须可见 `createRequire`）/ B3 node 真跑
`version` 看 stdout+stderr 内容不只看退出码 / B4 根因分类
ESM_CJS_REQUIRE / OTHER_CRASH / OK；覆盖面真源 = 仓库内任意层级 `moon.pkg` 反解
`pkgtype(kind: "executable")`、不硬编码（判例-16/R183）；自拒契约——bundle 不
存在 / node 不可用 / 空扫描 rc=2，判据未捕获异常 rc=4，绝不冒用 1）：

- `--selftest` **rc=0**（`SELFTEST OK（27 格：classify 5 格 / shim 3 格 / e2e 好
  bundle 与坏 bundle 与未打垫片 4 格 / e2e-missing 与空 bundle 自拒 2 格 /
  diag-real-bundle 四真 bundle 格（cmd/cli、cmd/commissar、cmd/main、tests/smoke
  全 rc=0,kind=OK）/ 覆盖面不硬编码 5 格 / entry-main-selftest-rc0 元格；格数由
  格子清单算出、不手写计数）`）⇒ **判据本身健康，不是坏尺**
- 实跑 **rc=0**（`PASS [OK]` ×4：cmd/cli / cmd/commissar（import 期自行退出、
  未触发 CJS 互操作崩溃）/ cmd/main / tests/smoke，ESM 加载正常；
  `覆盖面：executable 包 24 个 → 已验 4 / 未构建 20 / 通过 4`）

### 撞面核对

grep git log 反解近 20 轮换面巡检面（20 面各异：check_precedents_doc /
check_model_auth_no_key / check_workflow_step_parity / check_doc_paths /
check_doc_surface / check_arg_face_strict / check_mcp_stdio_purity /
check_ps_encoding / check_selftest_hermetic / check_exit_code_contract /
check_backlog_status_staleness / check_byte_slice_truncation / check_plan_landing /
check_dead_params / check_effective_catch / check_two_faces /
check_foreign_ledger_entries / check_sql_bind_alignment / check_desc_enum_sync /
check_tool_add_completeness）—— **`check_esm_bundle_runnable` 零命中**；宽窗
（近 120 轮）亦零命中，本面为本轮重新覆盖、非撞面。

例行的零漂移双核对：
- `check_tools_sync` rc=0：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐，R3b/R7 扫现状面 168 份、历史面豁免 25 份，R8 清单分组
  19 组 ΣN=183（已与实测 183 对表）
- `check_instruction_budget` rc=0：AGENTS.md 50440/65536 字节全部章节可见

## 新观察两项（记本报告待专门轮修复 · 不立新 BUG 号）

### 观察一：本判据探针在 build 目录自举 fist-mbt.db（BUG-122/124 同族 · 检测盲区）

**现象**：`_build/js/debug/build/cmd/cli/fist-mbt.db`（278528 B）与
`_build/js/debug/build/cmd/main/fist-mbt.db`（159744 B）的 mtime 精确对应本轮
两次真跑（selftest diag 格 05:03 / 后台实跑 05:05，当前 05:05 采集）。

**根因链**（缺一环都不成立）：
1. `run_bundle` / `run_esm_probe` 两处 `subprocess.run(["node", …],
   cwd=os.path.dirname(path))` **无 `env=` 参数** ⇒ 继承调用方环境；电池/唤醒轮
   调用 `--selftest` 时 `FIST_DB_PATH` 未设（`scripts/fist.py:47-48` 的默认改道
   只在 fist.py 自己进程里生效，不下传给探针）；
2. bundle 进程启动即初始化 store ⇒ 默认路径台账按 cwd 自举（BUG-122 同型：
   不带 FIST_DB_PATH 裸跑会在 cwd 落 `fist-mbt.db`）；
3. 覆盖面含 4 个真 bundle × 电池 `case("check_esm_bundle_runnable.py",
   "--selftest")`（run_guards.py:543）每次 commit 都跑 ⇒ **每次 commit 都在
   build 目录重写台账**。

**为什么现有守卫照不出来**：`check_demo_isolation`（BUG-122/124）只扫
`Popen` 起 **`serve`** 的脚本；本判据跑的是 **`version`** 探针、且是
`subprocess.run` 不是 Popen-serve ⇒ 两面盲区叠加。

**后果定级**：低。`_build/` 在 .gitignore（:2）⇒ 不进 git 面、不进
`check_publish_payload` 发布面、不脏 `git status`；纯本机磁盘噪声 + 纪律面
破口（「凡初始化 store 的进程必须带 FIST_DB_PATH」的仓内纪律被本仓自己的判据
破了头）。

**修复规格**（专门轮执行，本文件不在 WIP 组、无需等收口）：
1. `run_bundle` / `run_esm_probe` 两处补 `env={**os.environ,
   "FIST_DB_PATH": <temp 下隔离库>}`（探针库一次性合成即可，如
   `temp/esm_bundle_probe.db`）；
2. `--selftest` 补一格**隔离锁**：合成 fixture bundle（JS 在 `version` 时读
   `process.env.FIST_DB_PATH`：未设则向 cwd 写标记文件再退出 0），断言探针跑完
   fixture 目录无标记文件（修前必红、修后必绿，变异对照同 R192 纪律）；
3. 存量两份 build 目录 db 属 gitignore 面可选清理——**建议修复落地前不清**
   （清了下次 commit 电池还会写回来，清了也证明不了什么）。

### 观察二：覆盖面剪枝面漏 `.qoder/worktrees`（20 份 UNBUILT 噪声）

实跑 `覆盖面：executable 包 24 个`：4 个本仓真源包 + **20 个
`.qoder/worktrees/agent-general-purpose-*/` 下其他 agent 的 worktree 副本**
（agent-general-purpose-04625cfe / 14fed5fe / 773233d4 / bb4c9125 / ff4ebfe9
各 4 包）。`executable_pkg_dirs` 只剪 `.agents/worktrees`（`parts[:2] ==
[".agents", "worktrees"]`）不剪 `.qoder/worktrees` ⇒ 他仓副本混进覆盖面、
每份都报 `DIAG [UNBUILT] 该 executable 包没有产物，跳过真验`。

**后果定级**：极低（rc 不受影响、UNBUILT 是诚实的 DIAG 档不是红），但
「覆盖面真源 = 本仓 moon.pkg」的口径被他仓副本污染——与 `.agents/worktrees`
当年被剪的理由（docstring 原话「是各分支的副本，不是本仓真源 ⇒ 一并跳过」）
完全同构。**修复规格**：剪枝条件从 `parts[:2] == [".agents", "worktrees"]` 放宽为
「任意第一层目录下名为 `worktrees` 的第二层」或显式并集
`{".agents", ".qoder"}`，同批补一格 e2e（合成 `.qoder/worktrees/x/moon.pkg`
不进覆盖面）。两观察同属本判据，**建议同一笔提交修全**。

## 资源消耗

- 唤醒巡检一轮；bash 调用约 10 次 + FIST 六步链 1 次（后台串跑）+ 后台判据
  实跑 1 次
- 零文件改动（换面巡检只读 + 记录，禁区 WIP 零碰），无新依赖安装

## 任务分配记录

| 步骤 | 工具 | 结果 |
|---|---|---|
| 唤醒巡检 | git status/log | WIP 静止第 58 轮，Round C 不执行 |
| 换面选面 | ls check_*.py × 近 20 轮 + 近 120 轮撞面反解 | 选 check_esm_bundle_runnable（近 120 轮未用 / r376 点名候选 / B3 真跑面价值高） |
| 换面巡检 | check_esm_bundle_runnable selftest | rc=0（27 格含 entry-main 元格与四真 bundle diag 格，判据健康非坏尺） |
| 换面巡检 | check_esm_bundle_runnable 实跑（后台） | **rc=0**（4/4 PASS [OK]；覆盖面 24 包 = 4 真源 + 20 worktree 副本噪声） |
| 新发现取证 | ls -la 时间线 + 探针调用面 read + 电池注册 grep + 既往报告 grep | 观察一/二根因链闭合、既往 120 轮报告未记过此面 |
| 零漂移核对 | check_tools_sync / check_instruction_budget | 均 rc=0（183 / 50440/65536） |
| FIST 闭环 | T0r133 六步 | 见文末核实格 |

## 遗留风险

1. **Round C 三件持续过期**：src/** 仍被 WIP 占用，BUG-527/BUG-530/USAGE 注册
   均不能落地——取决于另一 agent 收口 WIP，非本巡检可解除。
2. **第 58 轮静止**：WIP 自 r318 起无增长无收口（R192 车道自 r318 停摆），已跨
   半个自然月余；owner 可裁决接管收口或回滚该 WIP（不可逆操作，需明确授权，
   巡检不代行，同 r374/r375 定性）。
3. **r372 真发现待 WIP 收口方修**（WIP 模板 `templates/pipeline_mode_loop.md:86`
   的 run_check 示例缺必填 cmd/task_id）：严重度低（untracked 文件，CI 无此面），
   收口方应一并修全，否则收口后 `check_doc_surface` 实跑仍会 rc=1 红。
4. **本轮观察一/二待专门轮修**（`scripts/check_esm_bundle_runnable.py`，不在
   WIP 组、不阻塞也不被阻塞）：观察一为纪律面破口（每次 commit 电池都在
   build 目录重写台账）+ `check_demo_isolation` 检测盲区（只扫 Popen-serve，
   对 subprocess-run-version 探针失明）；观察二为覆盖面口径污染。修复规格见
   上文，建议同一笔提交修全 + 同批自测。

## 后续建议

- **下轮候选**：观察一/二修复轮（本判据同批修全，规格已备）；或继续轮换
  未巡检面（check_release_asset_names / check_publish_payload /
  check_entry_paths / check_mbti_eol 等，check_esm_bundle_runnable 本轮已用、
  check_plugin_sync 脏树必现 WIP 投影漂移暂避）。
- WIP 收口后按 Round C 队列执行（BUG-527 治本 → BUG-530 → run_guards 注册
  check_usage_tool_count 同批），并**顺带修全 loop.md:86 的 run_check 示例**
  （r372 真发现）。
- 基线外外来条目 BUG-613~635 继续待 owner 裁决搬移 vq 仓 / WHITELIST 登记
  （`check_foreign_ledger_entries` 脏树必红 = WIP 投影，非回归）。

## 超额内容

无。

## 来源

- git status --short / git log --oneline（唤醒巡检，只读实测）
- scripts/check_esm_bundle_runnable.py --selftest / 实跑输出（本轮实测，实跑
  后台 bg 作业收口）
- scripts/check_esm_bundle_runnable.py 源码 read（run_bundle / run_esm_probe /
  executable_pkg_dirs 剪枝面）+ ls -la 时间线取证 + grep 电池注册
  （run_guards.py:543）+ 既往 120 轮报告撞面 grep
- scripts/check_tools_sync.py / check_instruction_budget.py 输出（本轮实测）
- memory 注入（FIST 链后台收口法 / 健壮 TID 提取 / BUG-122/124 纪律 /
  r376 静止第 57 轮与点名候选）

## FIST 闭环核实格（终审回填）

- TID = **T0r133**（task_id.txt 与 verify 回执一致）
- STEP1 publish rc=0 / STEP2 acl rc=0 / STEP3 claim rc=0 / STEP4 execute rc=0 /
  STEP5 submit rc=0 / STEP6 verify rc=0 / CHAIN_DONE
- verify 回执：status=**已完成**、completed_by=**wd-r377**、assignee=wd-r377、
  deliverable=reports/2026-11-17-r377-wakeup-patrol.md、namespace=watchdog、
  created_at=2026-11-16T21:09:01Z / updated_at=2026-11-16T21:09:11Z
