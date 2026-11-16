# 轮 350 唤醒巡检报告（ExploreWatchdog · 2026-11-16）

## 结果摘要

- **WIP 冻结判定**：`git status --short` = 6 M + 2 untracked（8 件），numstat 与 r326~r349 **逐字同**
  （bugs.md 216/0 零再增长、improvement-plan 7/1、target.md 1/1、README.md 2/1、
  run_guards.py 9/0、engine_circuit_test.mbt 5/0；untracked：check_mcpcf_db_isolation.py +
  pipeline_mode_loop.md，逐字同 r349）⇒ **WIP 非冻结增长后静止第 31 轮**，
  R192 车道自 r318 后持续停摆、src/** + run_guards.py 仍 M ⇒ **巡检分支**。
- **Round C 三件**（BUG-527 治本 / BUG-530 修复 / check_usage_tool_count 注册）维持**过期不执行**（src/** 未解禁）。
- **换面巡检 `check_stale_self_claim`**（AI-DEVELOPMENT-STANDARD §4.1「自述滞后现状」常驻门：
  源码里对**具名符号**的「能力不存在」断言若该符号在仓内**真有代码级消费者** ⇒ 滞后 ⇒ 红。
  两式取数面刻意分开报码——**S1 注释面**（`///`/`//` 文档注释写「`foo` 尚未实现」而 foo 早被调用）+
  **S2 运行时字面量面**（`"..."` 里同一句式，随 tools/list / 启动横幅**发货**，纯散文判据看不见——
  BUG-577 的 agent_register_key 描述串就是这一面）。
  **甄别式（BUG-575 立规）**：现在时否定活接线 = 滞后；点名变更史 = 准确。判定须①按子句切分，
  ②子句出现变更史标记（此前/当初/旧口径/已改/已被…推翻）即跳过，③只认带**反引号符号名**的断言
  （无具名对象的泛指不判，那是修辞不是契约）。豁免表逐条点名 (文件,符号,原句,理由) 且**反查陈旧豁免**
  （条目在文件里已找不到 ⇒ 幻影豁免红）；真未实现（符号全仓找不到）不报红（有意宽松侧，判据恒红=没人读=没锁）。
  - `--selftest` **rc=0**（**20/20 格**：fixture-four-files / stale-claim-is-red / past-tense-not-red /
    genuinely-missing-not-red / test-face-not-consumer / history-only-face-is-clean-not-blind /
    empty-universe-refuses / claims-counted / phrase-hits-counted / runtime-string-face-S2 /
    mutation-history-skip-anchor-exactly-one / mutation-history-skip-really-fires /
    mutation-consumer-gate-anchor-exactly-one / mutation-consumer-gate-really-fires /
    stale-exemption-is-red / exemption-pointing-nowhere-is-red / call-face-violation-rc1 /
    call-face-clean-rc0 / call-face-empty-refuses-rc2 / call-face-unknown-flag-rc2——含 2 变异对照锚点 +
    1 历史陈述反证 + 1 真未实现反证）
  - 实跑 **rc=0**（**421 份 .mbt**、负面句式 **6 处**、具名负面主张 **0 条**——其余为无具名对象修辞或变更史陈述）
- **零漂移判据**：`check_tools_sync` rc=0（183 工具真源一致、R8 清单 19 组 ΣN=183）/
  `check_instruction_budget` rc=0（AGENTS.md 50440/65536 全章节可见）。
- **无新发现（类型）、无新立账**（换面到 check_stale_self_claim，该面自述滞后 0 条、尺子自证 20/20 全绿）。
- **禁区零碰**：8 WIP 文件（含 bugs.md）零改零提交。
- **FIST 闭环**：T0r106 六步全链 rc=0（publish → agent_acl_grant → claim → execute → submit → verify，
  wd-r350 / ns watchdog / verify status=已完成、completed_by=wd-r350 / deliverable=本报告，后台串跑收口）。

## 资源消耗

| 项 | 读数 |
|---|---|
| 判据自跑 | check_stale_self_claim --selftest rc=0（20/20 格）+ 实跑 rc=0；check_tools_sync rc=0；check_instruction_budget rc=0 |
| FIST 闭环 | 1 任务（T0r106）六步 |
| 提交 | 1（本报告，scoped `--` 路径） |

## 任务分配记录

| 角色 | 动作 |
|---|---|
| 统帅（本实例） | git status/log/numstat 冻结判定、换面巡检选面与执行、零漂移复跑、报告撰写、FIST 闭环、scoped 提交 |
| 子代理 | 未派（巡检分支、全部为单命令判据、无并发收益） |

## 遗留风险

1. WIP 8 件仍冻结（第 31 轮），Round C 三件过期——需 owner/R192 车道收口 WIP 后才可执行。
2. **外来账检测面**（沿用 r348 判定）：白名单外外来账 23 条（BUG-613~635）悬待 owner 裁决，
   属 BUG-565「跨项目误落账持续模式」；检测半在线、每次冻结 WIP 重跑必红属预期。
   本轮未复跑该面（换面到 check_stale_self_claim），规模维持 r348 读数。
3. 换面巡检队列余量：mcp_smoke / OFM 端点探活 / 其余未巡 `check_*` 面（同源收敛面短收尾即可，勿空转）。

## 后续建议

- 下轮继续巡检分支，换面队列推进（避免与 r340~r350 已巡面重复）。
- R192 车道若恢复，优先收口 Round C 三件。
- 外来账 23 条（BUG-613~635）建议 owner 一次性裁决（搬移 vq 仓 / 登记 WHITELIST）。

## 超额内容

无。

## 来源

- `git status --short` / `git log --oneline -5` / `git diff --numstat`（2026-11-16 本机）
- `python scripts/check_stale_self_claim.py --selftest` / 实跑
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`
- FIST 闭环 `temp/fist_r350_chain.sh`（后台串跑，回盘 `temp/fist_r350_out/`，task_id=T0r106）
