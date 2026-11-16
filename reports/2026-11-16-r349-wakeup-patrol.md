# 轮 349 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：`git status --short` = 6 M + 2 untracked（8 件），numstat 与 r326~r348 **逐字同**
  （bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
  run_guards.py 9/0、engine_circuit_test.mbt 5/0；untracked：check_mcpcf_db_isolation.py 24993B
  + pipeline_mode_loop.md 15433B）⇒ **WIP 非冻结增长后静止第 30 轮**，
  R192 车道自 r318 后持续停摆、src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_selftest_hermetic`**（R153 自检 hermetic 守卫：`--selftest` 只许读合成夹具、
  **不许读仓库现状面**——R151 的根因面：自检里混一格读真源（真 README / `run_guards.py --list` / 真仓 git），
  账一落后尺子就红；本判据是「没有任何常驻判据扫这个形状」的补位。两条形机械可定：
  **H1** 自检体调用闭包里 I/O 原语（open/os.listdir/os.walk/glob/subprocess/Path.write 族）的参数子树
  流进「仓根派生锚点」或其局部派生名（含形参流进同文件 helper 的一跳）；
  **H2** 自检体 open 族首参是仓根相对路径字面量且本仓存在。
  分档 **W/R/G 判红** + **S/T 记账**（自 spawn 跑真尺子 / 读写约定 gitignored `temp/`）+ **C 校准档**
  （BUG-516 走路②，显式 `HERMETIC_CALIBRATION` 声明、只豁免点名锚点的读、不进棘轮）：
  - `--selftest` **rc=0**（**51 格**反解：A×3 / B×3 / C×9 / F×7 / G×2 / N×2 / P×4 / R×11 / S×1 / T×5 / W×4，
    族名取自已执行格子名首段字母、不手写计数）
  - 实跑 **PASS rc=0**（**182 份带自检脚本**，棘轮 **W=8/8 R=87/92 G=34/34** 全在基线内）
  - 读数注：**R 档 87 < 基线 92**——棘轮只许升不许降，基线保持 92 不动。这是**账面下降非回归**
    （① 真还了债 / ② BUG-516 走路②校准档重分类），`--bless-baseline` 会拒绝下调；**PASS 语义 = 没比基线更差**，
    非「零违例」。记账档 10 处（S/T：e2e_native_heap_probe/check_exit_code_contract/check_plugin_sync/
    check_t0r21/whisperer）+ 校准档 8 处（C：check_scripts_naming 的 HERMETIC_CALIBRATION 声明锚点）均已点名。
- **零漂移判据**：`check_tools_sync` rc=0（183 工具真源一致、R8 清单 19 组 ΣN=183）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **无新发现（类型）、无新立账**（R 档账面下降为棘轮既有语义的数据点，非新类型、非回归）。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r105 六步全链（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r349 / ns watchdog / deliverable=本报告，后台串跑收口）。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_selftest_hermetic --selftest rc=0（51 格）+ 实跑 PASS rc=0；check_tools_sync rc=0；check_instruction_budget rc=0 |
| FIST 闭环 | 1 任务（T0r105）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log/numstat 冻结判定、换面巡检选面与执行、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 30 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. **外来账检测面**（沿用 r348 判定）：白名单外外来账 23 条（BUG-613~635）悬待 owner 裁决，
   属 BUG-565「跨项目误落账持续模式」；检测半在线、每次冻结 WIP 重跑必红属预期。
   本轮未复跑该面（换面到 check_selftest_hermetic），规模维持 r348 读数。
3. **hermetic 棘轮 R 档账面下降**（87<92）：属 BUG-516 走路②既有语义，非回归、无需动作；
   若后续要收口账面须走 `--bless-baseline` 且理由充分，不在本巡检范围。
4. 换面巡检队列余量：mcp_smoke / OFM 端点探活 / 其余未巡 `check_*` 面（同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（避免与 r340~r349 已巡面重复）。
- R192 车道若恢复，优先收口 Round C 三件。
- 外来账 23 条（BUG-613~635）建议 owner 一次性裁决（搬移 vq 仓 / 登记 WHITELIST）。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -3` / `git diff --numstat`（2026-11-16 本机）
- `python scripts/check_selftest_hermetic.py --selftest` / 实跑
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`
- FIST 闭环 `temp/fist_r349_chain.sh`（后台串跑，回盘 `temp/fist_r349_out/`）
