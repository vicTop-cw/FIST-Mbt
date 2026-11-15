# 轮 324 唤醒巡检报告

**日期**：2026-11-16
**轮次**：r324
**执行者**：wd-r324（FIST-Mbt-ExploreWatchdog）

## 结果摘要

**WIP 非冻结增长后静止第 5 轮（numstat 与 r323 逐字同）** —— `memory/bugs.md` 维持 **216/0**
（r323 后零再增长、无 BUG-637+ 新外来账），其余 5 个已跟踪 WIP 文件（`improvement-plan` 7/1、
`target.md` 1/1、`README` 2/1、`run_guards` 9/0、`engine_circuit_test` 5/0）与 2 个 untracked
（`check_mcpcf_db_isolation.py`、`pipeline_mode_loop.md`）**逐字同 r323**；R192 车道自 r318 后持续停摆。
`src/**` + `scripts/run_guards.py` 仍 M ⇒ **巡检分支**（Round C 三件仍锁）。

换面巡检 `check_foreign_ledger_entries`（BUG-565 外来账检测守卫·**r281 后首次复跑**，扫描面
`memory/bugs.md` 为 WIP 面之一但本判据纯只读）selftest **15/15 PASS rc=0** + 脏树实测 **rc=1**：
账本 **621 条**、外来信号命中 **63 条**（白名单内 **40** / 白名单外 **23**）——白名单外 23 条为
**BUG-613~635** 全 vq 项目缺陷逐条点名（P3 生命周期批 613~624 + P5/P7 批 625~635），较 r281 实跑
的 12 条（BUG-613~624）**增 11 条**，增量全部为 P5/P7 批落账（FIXED 段戳 2026-11-14T02:47 / 2026-11-15T03:18），
**同已知持续模式（BUG-565 族）、无新发现（类型）、无新立账**。BUG-636（gnu/MinGW 环境批）summary/detail
不含外来路径信号 ⇒ 不命中（判据契约：只扫 summary/detail、不扫 evidence/勘误引用），维持 owner 裁决。

零漂移 `check_tools_sync` **183** / `check_instruction_budget` **50440/65536** 均 rc=0。Round C 三件维持
过期不执行。**FIST 闭环 T0r80 六步全链 rc=0**（wd-r324，ns watchdog，verify status=已完成、
completed_by=wd-r324，deliverable=本报告）。禁区零碰（8 WIP 文件含 bugs.md 零改零提交）。

## 巡检明细

1. **WIP 状态**（`git status --short` + `git diff --numstat`，本轮实读，逐文件对表 r323）：
   - `memory/bugs.md` **216+/0-**（与 r323 报告记的 **216/0 逐字同** ⇒ **零增长**；账本尾部实读至
     BUG-636 FIXED 段，无 BUG-637+ 新条目）；
   - 其余 5 个已跟踪 WIP 文件**逐字同 r323**：`improvement-plan` 7/1、`target.md` 1/1、`README` 2/1、
     `run_guards` 9/0、`engine_circuit` 5/0 ⇒ R192 车道面**仍静止**（自 r318 后无再推进）；
   - 2 个 untracked（`check_mcpcf_db_isolation.py` / `pipeline_mode_loop.md`）未变。
   - 结论：**WIP 非冻结增长后静止第 5 轮**（r321 记非冻结增长第 1 轮 = vq BUG-636 落账；r322 静止第 2 轮；
     r323 静止第 4 轮；r324 本轮 = 静止第 5 轮）。
   - 禁区处置：8 个 WIP 文件（含 bugs.md）**本轮零改、零提交**。

2. **换面巡检 `check_foreign_ledger_entries`**（BUG-565 外来账检测守卫·检测半；r281 后首次复跑，
   上次实跑读数 12 条白名单外 = BUG-613~624）：
   - 自检：`--selftest` **15/15 格 PASS rc=0**（含 MUT 变异对照：外来 summary/detail 必红且点名 id、
     同文非白名单 id 必红、meta 条目形不误红、报告人署名/证据引用/ns cwd 上下文不误红、
     零条目/空文本/缺文件 rc=2 自拒、未知旗标与 `--self-test` 拼错必拒 rc=2、
     `regex-parity-with-gen_plugins` 机器对表、正文内坏抬头不裂条目）；
   - 实测（脏树）：**rc=1** —— 账本 621 条、外来信号命中 63 条 = 白名单内 40 + 白名单外 23。
     白名单外 23 条逐条点名：**BUG-613~635**，命中信号以 `crates/,vq-cli/core/pyo3` 为主（21 条），
     其余 `apps/`（613 兼 / 623）、`apps/,data/`（614）、`packages/`（624）——全部为 vq 项目缺陷
     （缺陷位置 `E:/IDEProjects/AI/vq`），**无一条指向本仓树内的缺陷位置**（逐条核过：无本仓元条目误伤）；
   - 增量归因：r281（12 条）→ 本轮（23 条）+11 = **BUG-625~635**，落账戳 2026-11-14/15（P5 生命周期批 +
     P7 批），与 `### FIXED(2026-11-14T02:47…)` / `### FIXED(2026-11-15T03:18…)` 两段勘误批对应；
   - 判据工作结论：**无漂移**——自 r281 落账以来守卫的白名单/信号面未变，增量全部如实点名、无误报、
     无漏点名（BUG-636 按契约不命中已在明细 3 说明）；脏树 rc=1 = **冻结 WIP 的投影，非回归**
     （CI 干净检出 HEAD 账本至 BUG-591，全绿不受影响）；
   - 选面理由：r319~r323 五把（stale_self_claim / ns_write_gate / desc_enum / store_tables /
     host_installable）均已轮换，本判据自 r281 后未在唤醒轮复跑，且直接量化当前最大开放风险
     （vq 外来账队列）的规模，扫描面对 WIP 面纯只读。

3. **零漂移双检**：
   - `check_tools_sync` rc=0（server.mbt 注册 183，AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7
     扫现状面 168 份、历史面豁免 25 份；R8 清单分组 19 组 ΣN=183 对表一致）；
   - `check_instruction_budget` rc=0（AGENTS.md 50440 / 65536 字节，全部章节可见）。

4. **Round C 三件**：维持过期不执行——BUG-527 摘 cc-link-flags 已 owner 否决（CI A/B 实证有害）、
   BUG-530 已 FIXED（3699f012a）、`check_usage_tool_count` 已注册（run_guards.py:175）；`src/**` +
   `run_guards.py` 仍 M ⇒ 队列仍锁。

5. **FIST 闭环 T0r80 六步全链一发收口**（wd-r324，ns watchdog）：
   - 链脚本 `temp/fist_r324_chain.sh`（沿 r321~r323 稳健 TID 提取，逐行取能解析为 JSON 的那行）；
   - 六步 `publish / agent_acl_grant / claim / execute / submit / verify` 全 rc=0（后台一发收全，
     node server 温热，链路 <60s），verify 回执 **status=已完成、completed_by=wd-r324**、
     deliverable=`reports/2026-11-16-r324-wakeup-patrol.md`（回盘 `temp/fist_r324_out/`）。

## 资源消耗

- 判据 4 支（1 换面巡检 check_foreign_ledger_entries selftest 15 格 + 脏树实测 + 2 零漂移）
  + WIP numstat 核验 1 支 + FIST 六步链 1 发（后台串跑一次收全，本轮 node server 温热，链路快于 60s）；
- 本轮无子代理（巡检判据为轻量命令执行 + 只读核验 + FIST 链为网关记账，命令结果需指挥官亲阅终审，故直跑）。

## 任务分配记录

- **r324 FIST 闭环 T0r80 六步全链**（wd-r324，ns watchdog）：`temp/fist_r324_chain.sh`（稳健 TID 提取，
  六步全 rc=0），回盘 `temp/fist_r324_out/`（`1_publish..6_verify.txt` / `chain.log` / `task_id.txt`；
  verify status=已完成、completed_by=wd-r324）。

## 遗留风险

- **vq 外来账队列规模确认扩大**：白名单外 **23 条（BUG-613~635）** 待 owner 裁决（搬移 vq 仓 /
  带理由登记 WHITELIST kind=foreign-adjudicated），较 r281 的 12 条增 11 条（P5/P7 批）；
  指挥官不代行清理、不立新账（同 BUG-565 持续模式）。BUG-636（gnu/MinGW 环境批，`[high] FIXED`）
  按契约不命中信号面，同队列裁决。
- **WIP 非冻结增长后持续静止**：`memory/bugs.md` 216/0 无再增长；四件套核心 R192 车道面自 r318 后
  无再推进（连续第 5 轮静止）。
- **owner 裁决件**（同 r321~r323，本轮无增减）：① WIP 四件套弃置 ③ r302 落账方式 ④ 外来账处置
  （BUG-613~636，规模确认 23+1）⑤ BUG-636（FIST 自留临时号）known-red 登记口径（②
  check_mcpcf_db_isolation.py 缺执行面/未注册已被 R192 车道推进消解）。
- **FIST 链提取鲁棒性（r318 遗留）**：23 份 `temp/fist_r*_chain.sh` 同形脆弱提取（本轮 +1）；
  durable 修复在 `scripts/fist.py`（notice→stderr / stdout 纯 JSON）或 tracked 链脚本模板稳健取
  JSON 行，留专门轮次。本轮稳健提取是**临时绕过**，非 durable 修复。

## 后续建议

- **最高优先仍为 BUG-636（FIST 自留临时号·check_tool_coverage 盲区修复规格）**：待 `memory/bugs.md`
  WIP 解禁后专门轮次委派（含「加进 `_tool_registry.consumers()` 收口格」最易漏环节）。
- **vq 外来账队列（BUG-613~636）owner 裁决**：本轮已给出精确规模（白名单外 23 条 + 契约不命中 1 条），
  裁决面完整，可一次批了。
- **FIST 链提取鲁棒性专门轮次修复**（口径见遗留风险）。
- 继续按注册面轮换；Round C 三件维持过期（owner 已裁决面），唤醒轮继续非阻塞巡检。

## 超额内容

无。

## 来源

- `git status --short` / `git diff --numstat`（2026-11-16 本轮实读：bugs.md **216/0**、其余 5 文件逐字同
  r323；2 untracked 未变）
- `reports/2026-11-16-r323-wakeup-patrol.md`（r323 WIP 基线：bugs.md **216/0** + per-file 拆分）
- `python scripts/check_foreign_ledger_entries.py --selftest`（15/15 PASS rc=0）+ 同判据脏树实测
  （rc=1：621 条 / 命中 63 = 白名单内 40 + 外 23，BUG-613~635 逐条点名）（本轮）
- `memory/bugs.md` 尾部实读（至 BUG-636 FIXED 段，无 BUG-637+）
- `python scripts/check_tools_sync.py`（183 PASS）/ `python scripts/check_instruction_budget.py`
  （50440/65536 PASS）（本轮）
- `temp/fist_r324_out/`（六步回执 + `chain.log` + `task_id.txt`，TID=T0r80，verify status=已完成）
