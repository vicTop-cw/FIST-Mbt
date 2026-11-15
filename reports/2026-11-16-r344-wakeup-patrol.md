# 轮 344 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r344
**执行者**：wd-r344（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 25 轮（numstat 与 r326~r343 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r343 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r343**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_demo_isolation`（BUG-122 常驻判据面「**spawn server 的脚本必须把 `FIST_DB_PATH`
交给子进程**」守卫：仓库根的 `fist-mbt.db` 是**自举台账**〔`.gitignore` 挡着 ≠ 可脏〕、JS 服务端只认
一个隔离出口 = spawn 进程环境里的 `FIST_DB_PATH`〔`store_open(scratch=true)` 实测连隔离手段都不是 ⇒
BUG-90/96 改判〕。所以任何一个 `Popen([node, cli.js, "serve"])` 却不把 `FIST_DB_PATH` 交给子进程的
脚本，都是在往真实台账里写演示行；而 README/USAGE/agent-map/deliverable 四处正是教人**裸跑**这类脚本
〔BUG-122 成因〕。判据两个方向都发红：**I1** `scripts/**.py` 里 spawn `serve` 的脚本必须同文件出现
「把 `FIST_DB_PATH` 交给子进程」的五种形状之一〔`os.environ` 下标赋值 / `setdefault` /
`env.setdefault` / `env=dict(… FIST_DB_PATH …)` / `env = {… "FIST_DB_PATH": …}` 再传 `Popen`〕，
**缺针 = 红**（这个脚本一裸跑就污染真实台账）；**I2** `EXEMPT` 每一项必须 (a) 文件真实存在 (b) 理由
非空 (c) **锚点成立**——该文件确实 spawn `serve`，或属于两份**显式子句**（守卫自身、把 `"serve"`
当正则字面量读的 `check_entry_paths`）；把豁免扩到既不 spawn 也不是显式子句的文件 = 红 ⇒ 否则豁免面
可以随便扩；**I3** 扫描面为空（一个 spawn 脚本都没抓到）⇒ FATAL(2)：判据看不见样本就等于没判
（J10/BUG-118 同族）；**I0** 任一被检文件读不到 ⇒ 整笔自拒，不报绿。`--selftest` 六支：G1 干净不误红 /
M1 摘掉一个真 spawn 脚本的改道针必红 / M1b 只加一行注释不许误红 / M2 把豁免扩到一个根本不 spawn 的
文件必红 / M3 空扫描必自拒 / M3b 入口级空扫描自拒（**BUG-351**：M3 用 `scan(files=[])` 真构造空扫描、
并走 main 与自检共用的 `judge()` 断言 FATAL(2)——旧版 `scan({})` 仍枚举真实文件（恒非空）、M3 只测了
不可达分支，是自证式假绿）。格子清单从已执行对照反解打印、不手写计数。扫描面 `scripts/**.py` 含
untracked WIP `check_mcpcf_db_isolation.py`，但**只读、不触碰禁区**）selftest **rc=0**（干净不误红 +
变异必红 + 空扫描自拒；格子从已执行对照反解：G1 / M1 / M1b / M2 / M3 / M3b；**spawn 面 36 个脚本**、
显式子句 2 项 / 豁免 1 项）+ 实测 **PASS rc=0**（**spawn 面隔离一致：36 个脚本 spawn `serve` 时都把
`FIST_DB_PATH` 交给了子进程**〔显式子句 2 项 + 豁免 1 项锚点均成立〕——含 untracked WIP
`check_mcpcf_db_isolation.py` 的 spawn 面合规或未 spawn `serve`）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r343 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r100 六步全链 rc=0**（wd-r344，ns watchdog，verify
status=已完成、completed_by=wd-r344，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r343）：
   - `memory/bugs.md` **216+/0-**（与 r326~r343 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r343**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 25 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 静止第 19；r339 静止第 20；r340 静止第 21；
     r341 静止第 22；r342 静止第 23；r343 静止第 24；r344 本轮 = 静止第 25）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_demo_isolation`**（BUG-122 常驻判据面；I1~I3 + I0、两向都发红、selftest 六支、
   格子从已执行对照反解、扫描面 `scripts/**.py` 只读含 untracked WIP 不触碰禁区）：
   - 自检：`--selftest` **rc=0**（干净不误红 + 变异必红 + 空扫描自拒；**G1 干净不误红 / M1 摘改道针必红 /
     M1b 加注释不误红 / M2 豁免面漂移必红 / M3 空扫描必自拒 / M3b 入口空扫描必自拒**；spawn 面
     **36 个脚本**、显式子句 2 项 / 豁免 1 项）；
   - 实测：**PASS rc=0** —— **spawn 面隔离一致：36 个脚本 spawn `serve` 时都把 `FIST_DB_PATH` 交给了
     子进程**（显式子句 2 项 + 豁免 1 项锚点均成立）；
   - 判读：untracked WIP `check_mcpcf_db_isolation.py` 的 spawn 面**合规或未 spawn `serve`**（36 个脚本
     全部隔离一致 ⇒ 未引入 I1 违例）⇒ WIP 在飞面在 spawn 隔离面上**无新增风险**。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r100 六步全链一发收口**（wd-r344，ns watchdog）：
   - 链脚本 `temp/fist_r344_chain.sh`（沿 r321~r343 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r344**、deliverable=
     `reports/2026-11-16-r344-wakeup-patrol.md`（回盘 `temp/fist_r344_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_demo_isolation selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r344 FIST 闭环 T0r100 六步全链**（wd-r344，ns watchdog）：`temp/fist_r344_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r344_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r344）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r343
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 25 轮静止）。
- **owner 裁决件**（同 r321~r343，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解——r341 已确认其 README 登记面
  自洽、注册面归 R192 收口时核；本轮 check_demo_isolation 进一步确认其 spawn 隔离面合规或未 spawn
  serve）。
- **R192 车道收口清单（维持 5 项）**：① git add 两份在飞交付物（check_publish_payload P1 点名）+
  ② **修 `pipeline_mode_loop.md:86` 的 `run_check` 示例补 `cmd`+`task_id` 必填参数**（r342 J8 点名）+
  ③ 核 `check_mcpcf_db_isolation.py` 注册面（r341 确认 README 登记自洽、注册面归 R192 核）+
  ④ **U 面 5 条脚本补 `N=` 契约块**（r337 点名）+ ⑤ **提交 `bugs.md` 时同批重跑 `gen_plugins.py` 重投影
    插件态**（r343 J1 点名 9 文件、AGENTS.md 提交门禁既有义务，漂移即消解）。同属「专门轮次」批处理面。
- **FIST 链提取鲁棒性（r318 遗留）**：43 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
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
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r343 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + r338
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口清单**（维持 5 项）：git add 两份在飞交付物 / 修 pipeline_mode_loop.md:86 run_check
  示例 / 核 check_mcpcf_db_isolation.py 注册面 / U 面 5 条脚本补 N= 契约块 / 提交 bugs.md 同批重跑
  gen_plugins.py 重投影插件态。
- 换面巡检下轮候选：`check_entry_paths`（BUG-93/101 现状面命令与产物路径不得指退役入口、
  `Popen([node, cli.js])` 的 argv 必须带 serve——入口搬家漏掉的另一半，纯静态只读、`--selftest`
  反解、扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r343；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r343-wakeup-patrol.md`（r343 WIP 基线 + per-file 拆分）
- `python scripts/check_demo_isolation.py --selftest`（rc=0：G1/M1/M1b/M2/M3/M3b 六支、spawn 面 36 个
  脚本、显式子句 2 项/豁免 1 项）+ 同判据实测（PASS rc=0：spawn 面隔离一致 36 个脚本都把 FIST_DB_PATH
  交给子进程、含 untracked WIP check_mcpcf_db_isolation.py 的 spawn 面合规或未 spawn serve）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r344_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r100，verify status=已完成）
