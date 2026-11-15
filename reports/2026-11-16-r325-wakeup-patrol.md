# 轮 325 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r325
**执行者**：wd-r325（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 6 轮（numstat 与 r324 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r324 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py`、`pipeline_mode_loop.md`）**逐字同 r324**；R192 车道自 r318 后持续停摆。
`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**（Round C 三件仍锁）。

换面巡检 `check_model_auth_no_key`（BUG-127 凭据形状红线·**r317 列名候选首跑**，扫描面
fist-config / `*.mcp.json` / `plugins/**/.mcp.json` / `mcp_config_scaffold` 常量 / `src/router` /
docs / README* **完全避开 WIP 面**）selftest **rc=0**（违例必红 / 占位符与键名不误红 / base64
长令牌限键值上下文 / 输入面退化自拒）+ 实测 **PASS rc=0**（扫描 **146 份**，文件面无真凭据值形状）。
判据工作结论：**无漂移**（凭据红线面自 r317 列名以来首次复跑，守卫与真源对齐）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件维持
过期不执行。**FIST 闭环 T0r81 六步全链 rc=0**（wd-r325，ns watchdog，verify status=已完成、
completed_by=wd-r325，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r324）：
   - `memory/bugs.md` **216+/0-**（与 r324 报告记的 **216/0 逐字同** ⇒ **零增长**；grep 核账本无
     BUG-637+ / BUG-64x 新条目，尾部仍至 BUG-636 FIXED 段）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r324**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` / `pipeline_mode_loop.md`）未变。
   - 结论：**WIP 非冻结增长后静止第 6 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2 轮；
     r323 静止第 4 轮；r324 静止第 5 轮；r325 本轮 = 静止第 6 轮）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_model_auth_no_key`**（BUG-127 凭据形状红线守卫；r317「下一轮候选」点名首跑，
   上次实跑在 r317 之前；扫描面与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（SELFTEST OK：真凭据值形状判据可红可绿——违例必红 /
     占位符与键名不误红 / base64 长令牌限键值上下文 / 输入面退化自拒）；
   - 实测：**PASS rc=0** —— 扫描 **146 份**（fist-config / `*.mcp.json` / `plugins/**/.mcp.json` /
     `mcp_config_scaffold` 常量 / `src/router` / docs / README*），**无真凭据值形状**
     （`api_key` / `Bearer` / `sk-` 值形状）；
   - 判据工作结论：**无漂移**——凭据红线面干净，插件态投影（`plugins/**/.mcp.json`）与
     `default-fist.mcp.json` 启动参数面均无真凭据泄漏形状；
   - 选面理由：r317「下一轮候选」队列第一把（`check_model_auth_no_key` / `check_dead_params`），
     r318~r324 七轮按余下点名候选与近 15 轮未轮过优先消耗（effective_catch / ns_write_gate /
     desc_enum / store_tables / host_installable / foreign_ledger），本把自列名后首次轮换；
     扫描面 config/mcp.json/plugins/HTML 完全避开 WIP 面，且凭据红线是发布面安全底线
     （`moon publish` 打包面 = 工作树 − .gitignore，真凭据一旦落盘即随包公开）。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7
     扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r81 六步全链一发收口**（wd-r325，ns watchdog）：
   - 链脚本 `temp/fist_r325_chain.sh`（沿 r321~r324 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r325**、deliverable=
     `reports/2026-11-16-r325-wakeup-patrol.md`（回盘 `temp/fist_r325_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_model_auth_no_key selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + 账本尾部 grep 核验 1 支 + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r325 FIST 闭环 T0r81 六步全链**（wd-r325，ns watchdog）：`temp/fist_r325_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r325_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r325）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r324 持平，
  同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 6 轮静止）。
- **owner 裁决件**（同 r321~r324，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：24 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r324 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 换面巡检下轮候选：`check_dead_params`（r317 列名候选余下第二把）；继续按注册面轮换，
  优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r324；2 untracked 未变）
- `reports/2026-11-16-r324-wakeup-patrol.md`（r324 WIP 基线：bugs.md **216/0** + per-file 拆分）
- `memory/bugs.md` grep 尾部核验（无 BUG-637+ / BUG-64x 新条目）
- `python scripts/check_model_auth_no_key.py --selftest`（rc=0）+ 同判据实测（PASS rc=0，146 份）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r325_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r81，verify status=已完成）
