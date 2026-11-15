# 轮 343 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r343
**执行者**：wd-r343（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 24 轮（numstat 与 r326~r342 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r342 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r342**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_plugin_sync`（cl7「**一源四态·插件态一致性**」守卫：四态 = MCP（`src/server`）/
CLI（`scripts/fist.py`）/ Skill（`plugins/source`）/ Plugin（`plugins/<host>`）。插件态最容易腐烂——
它是**投影**、投影一旦改成手写就会长期落后于真源〔外部 moonbit-skills 里的旧 skill 曾把工具数写成
41，正是 BUG-22/30 那一类〕。本守卫把「投影必须等于生成结果」变成硬门：**J1 漂移**（子进程重跑
`gen_plugins.py --check` 逐字节 diff、生成器与守卫分开防止自证自）/ **J2 四宿主齐全**（atomcode /
codearts / deepseek-harness / claude 入口文件存在且非空）/ **J3 无残留占位符**（`plugins/` 下任何文件
不得含 `{{`）/ **J4 版本一致**（claude 两 manifest 的 version == `moon.mod`）/ **J5 启动参数单一真源**
（`plugins/claude/.mcp.json` 与仓库根 `.mcp.dev.json` 逐字相等——BUG-131 真源按「跟踪面优先」解析、
本机那份未跟踪 `.mcp.json` 残留不得决定基线）/ **J6 计数一致**（每个生成 SKILL.md 的 stamp 里
`tools=` == `server.mbt` 实测工具数）/ **J7 反幻影哨兵**（实测工具数 <=100 直接 FATAL 退出 2、解析
失败绝不报 PASS）。严格参数面 R66：未知旗标不再被静默忽略。扫描面为 `plugins/` 生成投影 +
`server.mbt` + `moon.mod`，**完全避开 WIP 面 `src/engine/`**）selftest **rc=0**（合成克隆路径两判都对、
真实生成集合 **64** 个文件、J1 变异对照已钉住〔假命令 rc=7 ⇒ 报 J1 插件态漂移〕、J 面覆盖对表通过
**6 个面 J1/J2/J3/J4/J5/J6**）+ 全量 **FAIL rc=1 = J1 插件态漂移**（**9 个文件**与真源投影不一致：
`README.md` 内容不一致 + `atomcode\skills\fist-commander\SKILL.md` + `atomcode\skills\fist-mbt\SKILL.md`
+ `claude\skills\fist-commander\SKILL.md` + `claude\skills\fist-mbt\SKILL.md` 等 9 处；处置 =
`python scripts/gen_plugins.py` 重新生成后复跑本守卫）。

**判读（只读核验钉死）= 在飞 WIP 真源投影、非本仓已提交回归**：
- `git diff HEAD --stat -- plugins/` **为空** ⇒ `plugins/` 处于**已提交态**（无未提交改动、用 HEAD 真源
  生成）；
- `git diff HEAD --numstat -- memory/bugs.md` = **216/0** ⇒ **WIP 真源与 HEAD 不同**（账本 +216 行）；
- 生成器 `gen_plugins.py` 消费的**真源含 `memory/bugs.md`（账本）** ⇒ 用 **WIP 真源**重投影 ≠ 用
  **HEAD 真源**生成的已提交 `plugins/` ⇒ **J1 漂移 = 在飞 WIP 真源投影**。
- **R192 车道义务**（AGENTS.md 提交门禁）：「改 `memory/bugs.md` 或任何计数面 ⇒ 同批重投影插件态：
  `python scripts/gen_plugins.py` 必须与账本/计数改动进**同一笔提交**」⇒ R192 车道提交 `bugs.md` 时须
  同批重跑 `gen_plugins.py`，漂移即消解。
- **指挥官不代行**（`gen_plugins.py` 会往 `plugins/` 写新 WIP、污染工作树、且改 `plugins/` 非本轮巡检
  授权面）、**不立新账**（属既有提交门禁规则管辖的在飞态、2026-11-02 一日两实证皆由 CI 兜底抓到）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**新发现（WIP 在飞·非本仓已提交缺陷）**：J1 插件态漂移 9 文件 = WIP `bugs.md` 真源
投影（R192 车道收口时同批重跑 `gen_plugins.py` 即消解）。**无新立账**（属既有提交门禁规则管辖）。
**FIST 闭环 T0r99 六步全链 rc=0**（wd-r343，ns watchdog，verify status=已完成、completed_by=wd-r343，
deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交、`plugins/` 零改）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r342）：
   - `memory/bugs.md` **216+/0-**（与 r326~r342 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r342**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 24 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 静止第 21；
     r341 静止第 22；r342 静止第 23；r343 本轮 = 静止第 24）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**；`plugins/` 零改。

2. **换面巡检 `check_plugin_sync`**（cl7 一源四态·插件态一致性守卫；J1~J7 硬门、严格参数面 R66、
   扫描面为 `plugins/` 生成投影 + `server.mbt` + `moon.mod`、完全避开 WIP 面）：
   - 自检：`--selftest` **rc=0**（合成克隆路径两判都对、真实生成集合 **64** 个文件、**J1 变异对照已
     钉住**〔假命令 rc=7 ⇒ 报 J1 插件态漂移〕、J 面覆盖对表通过 **6 个面 J1/J2/J3/J4/J5/J6**）；
   - 全量：**FAIL rc=1 = J1 插件态漂移**（真源 **183** 工具 / v0.3.11）：
     · **J1**：`gen_plugins.py --check` 退出码 1 —— **9 个文件**与真源投影不一致（`README.md` 内容
       不一致 + `atomcode\skills\fist-commander\SKILL.md` + `atomcode\skills\fist-mbt\SKILL.md` +
       `claude\skills\fist-commander\SKILL.md` + `claude\skills\fist-mbt\SKILL.md` 等 9 处）；
     · 处置：`python scripts/gen_plugins.py` 重新生成后复跑本守卫；
   - **判读（只读核验钉死）**：
     · `git diff HEAD --stat -- plugins/` **空** ⇒ `plugins/` 处于**已提交态**（无未提交改动）；
     · `git diff HEAD --numstat -- memory/bugs.md` = **216/0** ⇒ WIP 真源与 HEAD 不同；
     · 生成器真源含 `memory/bugs.md` ⇒ WIP 真源重投影 ≠ HEAD 真源生成的已提交 `plugins/` ⇒
       **J1 漂移 = 在飞 WIP 真源投影、非本仓已提交回归**；
     · R192 车道按 AGENTS.md 提交门禁义务：提交 `bugs.md` 时须**同批重跑 `gen_plugins.py`**（漂移即
       消解）；指挥官**不代行**（会污染工作树、非本轮授权面）、**不立新账**（既有提交门禁规则管辖）。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r99 六步全链一发收口**（wd-r343，ns watchdog）：
   - 链脚本 `temp/fist_r343_chain.sh`（沿 r321~r342 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r343**、deliverable=
     `reports/2026-11-16-r343-wakeup-patrol.md`（回盘 `temp/fist_r343_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_plugin_sync selftest + 全量 + 2 零漂移）+ WIP numstat 核验 1 支
  + plugins/ 只读核验 1 支 + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r343 FIST 闭环 T0r99 六步全链**（wd-r343，ns watchdog）：`temp/fist_r343_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r343_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r343）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r342
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 24 轮静止）。
- **owner 裁决件**（同 r321~r342，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解——r341 已确认其 README 登记面
  自洽、注册面归 R192 收口时核）。
- **R192 车道收口清单（本轮 +1 项）**：① git add 两份在飞交付物（check_publish_payload P1 点名）+
  ② **修 `pipeline_mode_loop.md:86` 的 `run_check` 示例补 `cmd`+`task_id` 必填参数**（r342 J8 点名）+
  ③ 核 `check_mcpcf_db_isolation.py` 注册面（r341 确认 README 登记自洽、注册面归 R192 核）+
  ④ **U 面 5 条脚本补 `N=` 契约块**（r337 点名）+ ⑤ **提交 `bugs.md` 时同批重跑 `gen_plugins.py` 重投影
    插件态**（本轮 J1 点名 9 文件、AGENTS.md 提交门禁既有义务，漂移即消解）。同属「专门轮次」批处理面。
- **FIST 链提取鲁棒性（r318 遗留）**：42 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **判据自述格子数/注释文档滞后**（r332 起累计·非缺陷）：`check_arg_face_strict.py`「已知债」段
  （27 把已消解、注释仍写现状）+ r338 `check_sql_bind_alignment.py` docstring「6 格」实跑 7/7 格，
  留专门轮次批量更新（均属各尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r342 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口清单**（本轮 +1 项、共 5 项）：git add 两份在飞交付物 / 修 pipeline_mode_loop.md:86
  run_check 示例 / 核 check_mcpcf_db_isolation.py 注册面 / U 面 5 条脚本补 N= 契约块 / 提交 bugs.md 同批
  重跑 gen_plugins.py 重投影插件态。
- 换面巡检下轮候选：`check_demo_isolation`（BUG-122/124 凡 Popen 起 serve 的脚本必须把 FIST_DB_PATH
  交给子进程否则裸跑命令往仓库根自举台账塞演示行，纯静态只读、`--selftest` 反解、扫描面避开 WIP 面）；
  继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r342；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `git diff HEAD --stat -- plugins/`（空 ⇒ plugins/ 处于已提交态）+ `git diff HEAD --numstat --
  memory/bugs.md`（216/0 ⇒ WIP 真源与 HEAD 不同）（本轮只读核验，钉死 J1 漂移=WIP 真源投影判读）
- `reports/2026-11-16-r342-wakeup-patrol.md`（r342 WIP 基线 + per-file 拆分）
- `python scripts/check_plugin_sync.py --selftest`（rc=0：合成克隆路径两判都对、真实生成集合 64 个文件、
  J1 变异对照已钉住、J 面覆盖对表通过 6 个面 J1/J2/J3/J4/J5/J6）+ 同判据全量（**FAIL rc=1 = J1 插件态
  漂移 9 文件**：README.md + atomcode/claude 的 fist-commander/fist-mbt SKILL.md 等；判读 = WIP bugs.md
  真源投影非回归、R192 车道收口时同批重跑 gen_plugins.py 即消解）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r343_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r99，verify status=已完成）
