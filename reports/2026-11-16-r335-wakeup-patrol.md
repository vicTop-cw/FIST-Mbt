# 轮 335 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r335
**执行者**：wd-r335（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 16 轮（numstat 与 r326~r334 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r334 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r334**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_skill_inject`（BUG-139 同族：「plan/claim 的 `inject` 真的能命中资产」守卫——
`evolve_asset_register` 把外部资产注册进 DGM 档案库、plan/claim 的 `inject` 按关键词子串检索，
若匹配逻辑退化则 `inject` 恒空而无人认领；本守卫只做**静态可测命中 + 落库资产反查**、
**不黑盒真调 MCP**。扫描面 `src/server/server.mbt`〔注入匹配真源 `lookup_injected_assets_in`〕+
`src/server/memory_test.mbt`〔白盒锁〕+ `fist-mbt.db` 的 `evolve_artifacts` 表〔**只读**〕，
**完全避开 WIP 面 `src/engine/`**）selftest **rc=0**（可红可绿反解：合规 `[asset]` 条目不误红 /
匹配逻辑缺失或退化必红 / 档案面空与输入面退化必自拒 `exit 2` / 合规 temp 夹具真源与白盒锁不误红）
+ 实测 **PASS rc=0**（`lookup_injected_assets_in` 按 `goal`/`note` 子串匹配〔真源 `server.mbt`、
**匹配键 `goal`+`note` 不含 `code`**——`code` 只在命中结果回传、不作匹配键，判据如实自述不吹成
三面都配〕、白盒锁 `memory_13_lookup_injected_assets_hit_and_empty` 在位、已注册 **16 条 `[asset]`**
资产**全部 `asset_id` 可反查且 `note`/`code` 非空可注入**）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**无新发现（类型）、无新立账**（vq 外来账队列规模与 r326~r334 持平，全挂 owner
裁决，同 BUG-565 持续模式）。**FIST 闭环 T0r91 六步全链 rc=0**（wd-r335，ns watchdog，verify
status=已完成、completed_by=wd-r335，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r334）：
   - `memory/bugs.md` **216+/0-**（与 r326~r334 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r334**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 16 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 静止第 10；r330 静止第 11；r331 静止第 12；r332 静止第 13；r333 静止第 14；r334 静止第 15；
     r335 本轮 = 静止第 16）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_skill_inject`**（BUG-139 同族注入路径守卫；静态可测命中 + 落库反查、不黑盒调 MCP，
   扫描面与 WIP 面零交集、读库只读）：
   - 自检：`--selftest` **rc=0**（可红可绿反解：合规 `[asset]` 条目不误红 / 匹配逻辑缺失或退化必红 /
     档案面空与输入面退化必自拒 `exit 2` / 合规 temp 夹具真源与白盒锁不误红；现状真源/锁的断言归主面 S1/S2）；
   - 实测：**PASS rc=0** —— 三判全绿：
     · **S1** 注入匹配逻辑在位：`lookup_injected_assets_in`（真源 `src/server/server.mbt`）存在、
       把 `inject` 按 `,` 分割成关键词数组、对每个 Artifact 用 `.contains(k)` 子串匹配 `art.goal`
       **或** `art.note`（匹配键 `goal`+`note`、不含 `code`）；
     · **S2** 白盒锁在位：`src/server/memory_test.mbt` 的 `memory_13_lookup_injected_assets_hit_and_empty`
       （命中/空关键词/无关词三态都有断言）；
     · **S3** 落库资产反查：`fist-mbt.db` 的 `evolve_artifacts` 表已注册 **16 条 `[asset]`** 资产、
       全部 `asset_id` 可反查且 `note`/`code` 非空（可注入）；
   - 判据工作结论：**无漂移** —— 注入匹配逻辑、白盒锁、落库资产面自 r334 未变，无退化。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r91 六步全链一发收口**（wd-r335，ns watchdog）：
   - 链脚本 `temp/fist_r335_chain.sh`（沿 r321~r334 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r335**、deliverable=
     `reports/2026-11-16-r335-wakeup-patrol.md`（回盘 `temp/fist_r335_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_skill_inject selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r335 FIST 闭环 T0r91 六步全链**（wd-r335，ns watchdog）：`temp/fist_r335_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r335_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r335）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r334
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 16 轮静止）。
- **owner 裁决件**（同 r321~r334，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：34 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。
- **`check_arg_face_strict.py` 头注释「已知债」段文档滞后**（r332 新发现·非缺陷）：27 把债已消解、
  注释仍写现状，留专门轮次更新（注释属该尺本体、非 WIP 面）。
- **R192 在飞 WIP 的发布载荷暴露**（r334 check_publish_payload 实测确认）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 两 untracked 文件会在下一次 `moon publish` 被公开（P1）。R192 车道收口时
  应 `git add` 入库（属真交付物、不该 ignore）；在那之前若有人 `moon publish`，会把这两份在飞稿公开——
  发布前须先收口 R192 车道。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r334 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- **`check_arg_face_strict.py` 头注释「已知债」段更新**（r332 新发现·轻微文档滞后）。
- **R192 车道收口时 git add 两份在飞交付物**（check_publish_payload P1 点名）：`check_mcpcf_db_isolation.py`
  + `pipeline_mode_loop.md` 属真交付物应入库而非 ignore。
- 换面巡检下轮候选：`check_mcp_stdio_purity`（MCP server 的 stdout 纯 JSON 面守卫——spawn server 的
  常驻入口若往 stdout 打 notice/日志会破坏 MCP 协议帧解析，纯静态只读、`--selftest` 反解、扫描面
  避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r334；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r334-wakeup-patrol.md`（r334 WIP 基线 + per-file 拆分）
- `python scripts/check_skill_inject.py --selftest`（rc=0，可红可绿反解）+ 同判据实测
  （PASS rc=0：S1 匹配逻辑在位 goal/note 子串 / S2 白盒锁在位 / S3 落库 16 条 [asset] 全可反查且可注入）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r335_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r91，verify status=已完成）
