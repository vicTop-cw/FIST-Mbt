# 轮 329 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r329
**执行者**：wd-r329（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 10 轮（numstat 与 r326~r328 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r328 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py` 545 行、`pipeline_mode_loop.md` 211 行）**逐字同 r328**；
R192 车道自 r318 后持续停摆。`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**
（Round C 三件仍锁）。

换面巡检 `check_precedents_doc`（判例库 `docs/AGENTS-precedents.md` 形态尺：R1 编号连续无跳号 /
R2 `AGENTS.md` 指针对表 / R3 日期戳；纯静态只读，扫描面 `docs/AGENTS-precedents.md` + `AGENTS.md`
**完全避开 WIP 面**）selftest **rc=0**（20 格反解：形 6 + 双形 6 + 变异 4 + 旗标 4，变异 4 格
**只读本尺自身源码 `RE_HEADING` 真代码行**——非注释，判例-30 自指假绿口径）+ 实测 **PASS rc=0**
（判例-**32..47 连续 16 条**，抬头按语义取数〔1~6 个 `#` + `判例-<编号>`，分隔符不参与判定〕
两种排版形都进 R1/R2、日期戳齐、`AGENTS.md` 指针对表一致）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件
维持过期不执行。**FIST 闭环 T0r85 六步全链 rc=0**（wd-r329，ns watchdog，verify status=已完成、
completed_by=wd-r329，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r328）：
   - `memory/bugs.md` **216+/0-**（与 r326~r328 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r328**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` 545 行 / `pipeline_mode_loop.md` 211 行）未变。
   - 结论：**WIP 非冻结增长后静止第 10 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 静止第 8；r328 静止第 9；
     r329 本轮 = 静止第 10）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_precedents_doc`**（判例库形态尺·R121 立；纯静态只读，扫描面
   `docs/AGENTS-precedents.md` + `AGENTS.md`，与 WIP 面零交集）：
   - 自检：`--selftest` **rc=0**（20 格反解打印：形 6〔R1 跳号/重号/围栏伪抬头/散文提及不算/
     语义抬头取数/日期戳缺失〕+ 双形 6〔两种排版形都进取数面〕+ 变异 4〔改坏 `RE_HEADING` 真代码行必红，
     行首锚定 + 行内数针〕+ 旗标 4〔未知旗标/位置参数必 rc=2〕；格数由格子清单算出、不手写计数）；
   - 实测：**PASS rc=0** —— 判例-**32..47 连续 16 条**，抬头按语义取数（1~6 个 `#` + `判例-<编号>`，
     分隔符 `：/:/·/—/-`/换行一律不算身份）两种排版形（`### 判例-N：` 与 `## 判例-N ·`）都进 R1/R2、
     日期戳齐（每条含 `（20xx-`）、`AGENTS.md`「判例-32~N 已搬出」指针 N 与实测最大编号对表一致；
   - 落库核对：判例-45（2026-11-07 立）/ 46（2026-11-09 立 · 轮 182 车道 E）/ 47（2026-11-09 立 ·
     轮 183 车道 H）均在已提交面（`git log -- docs/AGENTS-precedents.md` 最近提交 cb4a77c64 及更早），
     **非 WIP 面**，尺对表一致无漂移。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；
     R3b/R7 扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r85 六步全链一发收口**（wd-r329，ns watchdog）：
   - 链脚本 `temp/fist_r329_chain.sh`（沿 r321~r328 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r329**、deliverable=
     `reports/2026-11-16-r329-wakeup-patrol.md`（回盘 `temp/fist_r329_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_precedents_doc selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + 判例库落库来源核对 1 支 + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r329 FIST 闭环 T0r85 六步全链**（wd-r329，ns watchdog）：`temp/fist_r329_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r329_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r329）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r326~r328
  持平，同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 10 轮静止）。
- **owner 裁决件**（同 r321~r328，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：28 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r328 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 换面巡检下轮候选：`check_entry_paths`（BUG-93/101 现状面命令与产物路径不指退役入口，
  从 `cmd/*/moon.pkg` 与 build_release.ps1 反解入口清单不硬编码，纯静态只读、扫描面避开 WIP 面）；
  继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r328；2 untracked 未变：check_mcpcf_db_isolation.py 545 行 / pipeline_mode_loop.md 211 行）
- `reports/2026-11-16-r328-wakeup-patrol.md`（r328 WIP 基线 + per-file 拆分）
- `python scripts/check_precedents_doc.py --selftest`（rc=0，20 格反解）+ 同判据实测
  （PASS rc=0：判例-32..47 连续 16 条 / 日期戳齐 / AGENTS.md 指针对表一致）（本轮）
- `git log --oneline -3 -- docs/AGENTS-precedents.md` + 判例-45/46/47 抬头实读（确认落库面非 WIP 面）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r329_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r85，verify status=已完成）
