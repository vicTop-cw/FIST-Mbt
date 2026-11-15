# 轮 334 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r334
**执行者**：wd-r334（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 15 轮（numstat 与 r326~r333 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r333 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r333**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_publish_payload`（BUG-127 发布载荷面守卫：`moon publish` 打包面 = **工作树 −
.gitignore**、**不是** git 跟踪面，且点号文件/目录一律不进包——「扫了 git 面」≠「扫了公开面」；
离线可跑、不联网不起进程，`--selftest` 全打 **temp 合成仓根**、真树一字节未动〔R153 hermetic 律〕，
扫描面 = 真仓工作树、与 WIP 面**零写入交集**）selftest **rc=0**（8 格反解：S0 沙箱形状自证
〔tracked + 忽略规则都在场〕/ M4 变异：非 git 仓夹具必被 S0 自拒 / G1 干净夹具不误红 /
G2 带未跟踪件逐件点名且无幻影红 / M1 未跟踪未忽略必红 / M2 被 `.gitignore` 挡住必不红 /
M3 红面凭据形状必点名 P2 / M5 拆件后夹具回干净形状〔幂等〕）+ 实测 **rc=1 = 2 条 P1**：
点名的**恰是 2 个 R192 在飞 WIP**（`scripts/check_mcpcf_db_isolation.py` +
`templates/pipeline_mode_loop.md`）⇒ **在飞投影非回归**（docstring 口径：未跟踪 + WIP = 在飞，
指挥官**不抢、不 `git add`**、入库归 R192 车道；同 R205 观察「P1 命中多为新写交付物忘 `git add`」）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r333 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r90 六步全链 rc=0**（wd-r334，ns watchdog，verify
status=已完成、completed_by=wd-r334，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r333）：
   - `memory/bugs.md` **216+/0-**（与 r326~r333 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r333**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 15 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 本轮 = 静止第 15）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_publish_payload`**（BUG-127 发布载荷面守卫；离线、不联网不起进程，
   扫描面与 WIP 面零写入交集）：
   - 自检：`--selftest` **rc=0**（8 格反解，全打 temp 合成仓根、真树一字节未动：S0 沙箱形状自证
     〔tracked + 忽略规则都在场，证「不误红」非白给〕/ M4 变异对照：非 git 仓的目录必被 S0 拒 /
     G1 干净夹具不误红 / G2 带未跟踪件时逐件点名且无幻影红 / M1 造未跟踪未忽略文件必红 /
     M2 造被现成 `*.log` 规则挡住的未跟踪文件必不红 / M3 红面塞凭据形状必点名 P2 /
     M5 拆件后夹具回干净形状〔幂等〕）；
   - 实测：**rc=1 = 2 条 P1** —— `scripts/check_mcpcf_db_isolation.py` 与 `templates/pipeline_mode_loop.md`
     均「未被 `.gitignore` 挡住又没被 git 跟踪」⇒ 下一次 `moon publish` 会公开出去；
   - 判定：**在飞投影非回归** —— 两个被点名文件正是当前 2 个 untracked WIP（R192 车道在飞交付物），
     按 docstring 口径「未跟踪 + WIP = 在飞，别抢」，指挥官不 `git add`、不 ignore（ignore = 让该公开
     的交付物永远进不了发布载荷）、入库归 R192 车道收口时处置；本轮零触碰。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r90 六步全链一发收口**（wd-r334，ns watchdog）：
   - 链脚本 `temp/fist_r334_chain.sh`（沿 r321~r333 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r334**、deliverable=
     `reports/2026-11-16-r334-wakeup-patrol.md`（回盘 `temp/fist_r334_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_publish_payload selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r334 FIST 闭环 T0r90 六步全链**（wd-r334，ns watchdog）：`temp/fist_r334_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r334_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r334）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r333
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 15 轮静止）。
- **owner 裁决件**（同 r321~r333，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：33 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **`check_arg_face_strict.py` 头注释「已知债」段文档滞后**（r332 新发现·非缺陷）：27 把债已消解、
  注释仍写现状，留专门轮次更新（注释属该尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（本轮 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r333 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **`check_arg_face_strict.py` 头注释「已知债」段更新**（r332 新发现·轻微文档滞后）。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 属真交付物应入库而非 ignore。
- 换面巡检下轮候选：`check_skill_inject`（evolve_asset_register 注入路径可测命中：plan/claim 传
  `inject` 时返回的 `injected_assets` 非空才算命中；纯静态/轻量、`--selftest` 反解、扫描面避开 WIP 面）；
  继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r333；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r333-wakeup-patrol.md`（r333 WIP 基线 + per-file 拆分）
- `python scripts/check_publish_payload.py --selftest`（rc=0，8 格 hermetic 反解）+ 同判据实测
  （rc=1：2 条 P1 = 2 个 R192 在飞 WIP，在飞投影非回归）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r334_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r90，verify status=已完成）
