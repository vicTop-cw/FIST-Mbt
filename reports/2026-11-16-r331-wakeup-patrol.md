# 轮 331 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r331
**执行者**：wd-r331（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 12 轮（numstat 与 r326~r330 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r330 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r330**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_release_asset_names`（分发面同源守卫：BUG-103/105/107/109/111/112/113/114/116/513
一族——用户按文档敲的那条命令、发布链产出的文件名、那条命令实际拿回的字节三者必须说同一件事；
纯文本形状判定、不联网，扫描面安装器/CI workflow/README/moon.mod **完全避开 WIP 面**）
selftest **rc=0**（42 格反解：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 / R7×3 / R8×3 / R9×6 / R10×2 /
R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7，清单从已执行格子反解、不手写计数）+ 实测 **PASS rc=0**
（**R1~R16 十六判全绿**：R1 安装器不写死版本字面量 / R2 真从 moon.mod 取版本 / R3 资产名三处一致 /
R4 解析失败显式失败 / R5 命令名两类 shell 都可见 / R6 200 不等于拿到文件〔HTML 形状 + zip 魔数〕/
R7 装完自检不假绿 / R8 发布作业不顶掉分发 / R9 工具链 bootstrap 与 CI 同源 / R10 文档线 BOM 安全 /
R11 源码版本常量==moon.mod / R12 下载重试只许对准传输层 / R13 / R14 / R15 windows 臂安装形状 /
R16 发布后资产逐名比对步在位〔BUG-513 出路③〕）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**FIST 闭环 T0r87 六步全链 rc=0**（wd-r331，ns watchdog，verify status=已完成、
completed_by=wd-r331，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r330）：
   - `memory/bugs.md` **216+/0-**（与 r326~r330 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r330**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 12 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 本轮 = 静止第 12）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_release_asset_names`**（分发面同源守卫·BUG-103~116+513 一族；纯文本形状判定、
   不联网，扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（42 格反解打印，不手写计数：R1×2 / R2 / R3×2 / R4 / R5×2 / R6×3 /
     R7×3 / R8×3 / R9×6 / R10×2 / R11×5 / R12×2 / R13×2 / R14×5 / R15×5 / R16×7；干净不误红 +
     变异必红两向，R9 只判**去掉注释行之后的代码面**〔第一版被自家注释里的 GITHUB_PATH 喂回针〕、
     被检面从 `.github/workflows/` 目录派生不硬编码名单）；
   - 实测：**PASS rc=0** —— **R1~R16 十六判全绿**（判据范围从正文反解）：
     资产名三处一致（install_onecmd.ps1 / install.sh / build_release.ps1 均 `fist-mbt-js-v<版本>.zip`）+
     版本真源 moon.mod + 空值即失败（exit 1）+ 命令名两类 shell 都可见（Windows 无扩展名 `#!/bin/sh`
     shim + 四件齐 exit 1 门 / WSL `cat > fist` + `chmod +x`）+ 200/HTML/魔数检查（GitHub master raw 直链 +
     HTML 形状检查 + zip 魔数 `PK`）+ 安装自检不假绿（禁空 catch / 临时降 EAP + `2>` 封装 / ✅ 挂条件分支）+
     发布作业不顶掉分发（needs 含 meta 不含 native / native 带 continue-on-error）+ 工具链 bootstrap 与
     CI 同源（moon 进 GITHUB_PATH / install URL `install/unix.sh`）+ 文档线 BOM 安全（TrimStart U+FEFF）+
     源码版本常量与 moon.mod 同源 + windows 臂安装形状与 ci.yml 同源 + 发布后资产逐名比对步在位
     （BUG-513 出路③）。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r87 六步全链一发收口**（wd-r331，ns watchdog）：
   - 链脚本 `temp/fist_r331_chain.sh`（沿 r321~r330 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r331**、deliverable=
     `reports/2026-11-16-r331-wakeup-patrol.md`（回盘 `temp/fist_r331_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_release_asset_names selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r331 FIST 闭环 T0r87 六步全链**（wd-r331，ns watchdog）：`temp/fist_r331_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r331_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r331）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r330
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 12 轮静止）。
- **owner 裁决件**（同 r321~r330，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：30 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r330 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 换面巡检下轮候选：`check_arg_face_strict`（行为级真门——真跑每把判据、按结果判未知旗标是否被拒，
  与 A3 advisory 分工互补；需确认其运行时长后定是否入轮）；继续按注册面轮换，优先近期未轮过且
  有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r330；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r330-wakeup-patrol.md`（r330 WIP 基线 + per-file 拆分）
- `python scripts/check_release_asset_names.py --selftest`（rc=0，42 格反解）+ 同判据实测
  （PASS rc=0：R1~R16 十六判全绿）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r331_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r87，verify status=已完成）
