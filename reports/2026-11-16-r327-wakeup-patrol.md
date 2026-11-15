# 轮 327 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r327
**执行者**：wd-r327（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 8 轮（numstat 与 r326 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r326 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py`、`pipeline_mode_loop.md`）**逐字同 r326**；R192 车道自 r318 后持续停摆。
`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**（Round C 三件仍锁）。

换面巡检 `check_tool_required_sync`（续19 required 矛盾面普查立尺·**源↔源双向对表**，扫描面锚定
`src/server/server.mbt` **完全避开 WIP 面 `src/engine/`**；r300~r326 窗内未轮换本轮首跑）selftest
**14/14 rc=0**（漏写必红 / 多写必红两形 / 干净不误红 / 条件必填不在 required 不误红 / 白名单抑制面双向 /
白名单过期三向 / `bug_fix.evidence` 具体对照 / 零工具失锚自拒 / 未知旗标 rc=2）+ 实测 **PASS rc=0**
（解析 **168** 工具，`required` 数组与必填描述**零漂移**；条件必填 **2** 处 / 白名单 **3** 条三向未过期）。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件维持
过期不执行。**FIST 闭环 T0r83 六步全链 rc=0**（wd-r327，ns watchdog，verify status=已完成、
completed_by=wd-r327，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r326）：
   - `memory/bugs.md` **216+/0-**（与 r326 逐字同 ⇒ **零增长**；无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r326**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit_test` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` / `pipeline_mode_loop.md`）未变。
   - 结论：**WIP 非冻结增长后静止第 8 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2；
     r323 静止第 4；r324 静止第 5；r325 静止第 6；r326 静止第 7；r327 本轮 = 静止第 8）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_tool_required_sync`**（续19 required 矛盾面普查立尺；r300~r326 窗内未轮换本轮首跑，
   扫描面锚定 `src/server/server.mbt`，与 WIP 面 `src/engine/` 零交集）：
   - 自检：`--selftest` **14/14 格 rc=0**（漏写必红〔描述说必填但 `required` 未列〕/ 多写必红
     〔可选 + 条件必填两形〕/ 干净不误红 / 条件必填不在 `required` 不误红 / 白名单抑制面双向 /
     白名单过期三向 / `bug_fix.evidence` 具体对照〔缺 evidence 红、补 evidence 绿〕/ 零工具失锚自拒 /
     未知旗标 rc=2）；
   - 实测：**PASS rc=0** —— 解析 **168** 工具，`required` 数组与必填描述**零漂移**；条件必填 **2** 处
     （白名单 3 条〔`file_release.reason` / `bug_mark_status.dup_of` / `ocr_scan.path`〕，三向未过期）；
   - 判据工作结论：**无漂移** —— required↔必填描述面自 r326 未变，白名单三向未过期；
   - 选面理由：r300~r326 窗内未轮换的判据之一；扫描面锚定 `src/server/server.mbt`（**源↔源对表**，
     直接解析文本、不起 server、不 build，CI 可裸跑）与 WIP 面 `src/engine/engine_circuit_test.mbt`
     零交集，纯静态只读、快；required 数组（客户端硬门）↔「必填」描述（给人看的软约束）是
     「客户端不拦 / 合法调用被误拒」两类漂移的常驻守卫（本仓第一例 = `bug_fix.evidence`）。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7
     扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r83 六步全链一发收口**（wd-r327，ns watchdog）：
   - 链脚本 `temp/fist_r327_chain.sh`（沿 r321~r326 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全），
     verify 回执 **status=已完成、completed_by=wd-r327**、deliverable=
     `reports/2026-11-16-r327-wakeup-patrol.md`（回盘 `temp/fist_r327_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_tool_required_sync selftest + 实测 + 2 零漂移）+ WIP numstat 核验 1 支
  + FIST 六步链 1 发（后台串跑一次收全）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r327 FIST 闭环 T0r83 六步全链**（wd-r327，ns watchdog）：`temp/fist_r327_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r327_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r327）。

## 遗留风险

- **vq 外来账队列**：白名单外 **23 条（BUG-613~635）** + 契约不命中 1 条（BUG-636）待 owner 裁决
  （搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本轮账本零增长，规模与 r325/r326 持平，
  同 BUG-565 持续模式，指挥官不代行清理、不立新账。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 8 轮静止）。
- **owner 裁决件**（同 r321~r326，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：26 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：规模与 r326 持平（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 换面巡检下轮候选：`check_precedents_doc`（docs/AGENTS-precedents.md 判例库形态尺，纯静态只读、
  `--selftest` 反解正文，扫描面避开 WIP 面）；继续按注册面轮换，优先近期未轮过且有 `--selftest` 的判据。
- Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r326；2 untracked 未变）
- `reports/2026-11-16-r326-wakeup-patrol.md`（r326 WIP 基线 + per-file 拆分）
- `python scripts/check_tool_required_sync.py --selftest`（14/14 rc=0）+ 同判据实测（PASS rc=0：168 工具 /
  required↔必填描述零漂移 / 条件必填 2 处 / 白名单 3 条三向未过期）（本轮）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r327_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r83，verify status=已完成）
