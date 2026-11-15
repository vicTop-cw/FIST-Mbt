# 轮 338 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r338
**执行者**：wd-r338（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 19 轮（numstat 与 r326~r337 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r337 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r337**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_sql_bind_alignment`（R177「SQL `INSERT` 的**列 ↔ 占位符 ↔ bind 次数**三方对齐」
守卫：R176 人工核了 `store_sqlite_executions.insert_execution` 一处〔11 列 / 11 个 `?` / 11 次
`stmt.bind` 逐位对齐〕，但仓库里还有 21 处 `INSERT`（`src/store/*.mbt`）——这类**错位**的失效形态
极隐蔽：列顺序与 bind 顺序错位 ⇒ 字段互相串值、**不报错、测试也未必覆盖**（同族 R148 的
`from_db` 位置参数、判例-16 的「同一套判定的多份实现」）。口径**诚实分级**、不假装全覆盖：
① 占位符 `?` 数必须等于**该语句之后、同函数内** `stmt.bind(` 数 / ② 列数 vs 占位符**仅当列表是
字面量**时校验、写成插值（`\{...}`）时**跳过并如实计入 `degraded`**——「列数是算出来的」静态
看不出来、不能静默算作已检（判例-33 同族）/ ③ bind 序号必须 **1..N 连续**（缺号/重号 ⇒ 线上必然
绑不上或覆盖）。rc 契约 `0` 全对齐 / `1` 有不对齐 / `2` 判据无法自证（扫描面空或零命中）。扫描面
`src/store/*.mbt` **完全避开 WIP 面 `src/engine/`**）selftest **rc=0**（实跑 **7/7 格**含变异对照：
s3 列数≠占位符必红 / s4 插值列绿但计 `degraded` / s5 bind 缺号经计数不等表达必红 / s7 委托助手
绑定绿且 `degraded` / s6 无样本 `rc=2` 不自证归 2 不归 0 等）+ 实测 **PASS rc=0**（门禁 **19 处
`INSERT` 三方对齐**：占位符 = bind 全对、其中 **3 处列数为插值**仅校验占位符、如实计 `degraded`）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。**新发现
（非缺陷·轻微文档漂移）**：docstring 用法行写「`--selftest` # **6 格**（含变异对照）」而实跑
**7/7 格**——自述格子数**落后于实现**（同 r332 `check_arg_face_strict`「已知债」注释滞后一族），
不立新账、留专门轮次把 6 改成 7。Round C 三件维持过期不执行。**无新发现（类型）、无新立账**
（vq 外来账队列规模与 r326~r337 持平，全挂 owner 裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r94
六步全链 rc=0**（wd-r338，ns watchdog，verify status=已完成、completed_by=wd-r338，deliverable=
本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r337）：
   - `memory/bugs.md` **216+/0-**（与 r326~r337 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r337**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 19 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 静止第 16；r336 静止第 17；r337 静止第 18；r338 本轮 = 静止第 19）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_sql_bind_alignment`**（R177 SQL INSERT 三方对齐守卫；静态正则 + 顶层逗号切分、
   口径诚实分级、不假装全覆盖，扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（实跑 **7/7 格**含变异对照：s3 列数≠占位符 ⇒ 红 / s4 插值列 ⇒
     绿但计入 `degraded` / s5 bind 缺号 ⇒ 红〔经计数不等表达〕/ s7 委托助手绑定 ⇒ 绿且 `degraded` /
     s6 无样本 ⇒ `rc=2`〔不自证归 2 不归 0〕等）；
     ⚠️ **docstring 与实跑不一致**：用法行写「`--selftest` # 6 格」，实跑 **7/7** 格 ⇒ 自述格子数
     落后于实现（轻微文档漂移，同 r332 一族），不立新账、留专门轮次更新；
   - 实测：**PASS rc=0** —— **门禁 19 处 `INSERT` 三方对齐**：
     · **占位符 vs bind 次数**：每处 `INSERT` 的 `?` 数 == 该语句之后、同函数内 `stmt.bind(` 数，**全对**；
     · **列数 vs 占位符**：字面量列表逐位对齐；**3 处列数为插值**（`\{...}`，如 `SqliteStore::task_columns()`）
       ⇒ 仅校验占位符、**如实计 `degraded`**（不静默算已检）；
     · **bind 序号**：1..N 连续、无缺号/重号；
   - 判据工作结论：**无漂移** —— 19 处 INSERT 对齐面自 r337 未变，无错位。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r94 六步全链一发收口**（wd-r338，ns watchdog）：
   - 链脚本 `temp/fist_r338_chain.sh`（沿 r321~r337 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r338**、deliverable=
     `reports/2026-11-16-r338-wakeup-patrol.md`（回盘 `temp/fist_r338_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_sql_bind_alignment selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r338 FIST 闭环 T0r94 六步全链**（wd-r338，ns watchdog）：`temp/fist_r338_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r338_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r338）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r337
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 19 轮静止）。
- **owner 裁决件**（同 r321~r337，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：37 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **判据自述格子数/注释文档滞后**（r332 起累计·非缺陷）：`check_arg_face_strict.py`「已知债」段
  （27 把已消解、注释仍写现状）+ 本轮 `check_sql_bind_alignment.py` docstring「6 格」实跑 7/7 格，
  留专门轮次批量更新（均属各尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。
- **U 面 5 条脚本补 `N=` 契约块**（r337 check_exit_code_contract 只报不判面点名）：`run_fist_mbt_http.py`
  / `run_fist_mbt_web.py` / `run_mcp_bug_loop.py` / `tmp_audit_preservation_scan.py` /
  `whisperer_patrol.py`——非红线、属文档完备性，留专门轮次补齐。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r337 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **判据自述格子数/注释批量更新**（r332 `check_arg_face_strict`「已知债」段 + 本轮
  `check_sql_bind_alignment` docstring「6 格」→ 实跑 7 格）：属轻微文档滞后、非缺陷，可一并批量修。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）+ **U 面 5 条脚本补
  `N=` 契约块**（r337 点名）：同属「专门轮次」批处理面。
- 换面巡检下轮候选：`check_store_tables_wired`（BUG-28 库内每张表要么有写入点、要么在 store 源文件
  里 `schema-reserved:` 点名预留，两向都发红，纯静态只读、`--selftest` 反解、扫描面避开 WIP 面）；
  继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r337；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r337-wakeup-patrol.md`（r337 WIP 基线 + per-file 拆分）
- `python scripts/check_sql_bind_alignment.py --selftest`（rc=0，实跑 7/7 格含变异对照；docstring
  写 6 格与实跑 7 格不一致 = 轻微文档漂移）+ 同判据实测（PASS rc=0：门禁 19 处 INSERT 三方对齐、
  占位符=bind 全对、3 处列数插值仅校验占位符计 degraded）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r338_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r94，verify status=已完成）
