# TASK-016 现核报告：治理主题散落 md · 指针收敛（T0r9 / iterate-1102）

- 执行车道：`lane-i-task016`（FIST 流水线 ns `iterate-1102` / task_id `T0r9`）
- 日期：2026-11-02
- 任务来源：`docs/tasks/backlog/TASK-016-docs.yaml`（P3，2026-10-22 发现，旧快照读数 21 份命中）
- 性质：只读现核 + 指针收敛；**本轮未编辑任何命中文件**（判定依据见「结论」）

## 结论

**命中面逐份现核后，c 类（讲治理规则但无真源指针）清单为空——全部命中归入 a（历史陈述面）或 b（真源本体 / 已含真源指针），无需补任何指针行，本轮未改动任何文件。**

TASK-016 盖章建议：**done**。
一句依据：现行面上不存在「自成一段治理规则却无真源指针」的文件——治理规则真源已唯一（`AI-DEVELOPMENT-STANDARD.md` + `docs/DOCS-STRUCTURE.md`），其余命中全部是 DOCS-STRUCTURE.md §「治理主题散在 19 个文件」处理口径明文豁免的历史陈述面（reports/、memory/ 日志、CHANGELOG、docs/ 归档计划），或本身已引用真源的规范文件（`docs/proposal-process.md` §6、`docs/plans/README.md` 头注）。

## 证据

### 普查方法

- 关键词（任务原文）：`治理 / governance / DOCS-STRUCTURE / 守卫族 / J 判据 / 分流转发`（大小写不敏感，`J\s?判据` 兼容无空格写法）
- 扫描面：根目录顶层 md + `docs/`（含 archive/plans 子树）+ `reports/` + `memory/`（含 research 子树）
- 排除面：`temp/`、`_archive/`、`.Fist-Mbt/`（`git ls-files` 实测 0 跟踪，属 scratch，不入普查面）；`scripts/ src/ .github/` 按边界不扫
- 工具：Python 正则逐文件扫描（本轮会话内实测执行）

### 两个口径的读数对照

| 口径 | 现读命中 | 旧快照（2026-10-22） |
|---|---|---|
| 窄口径（仅 `治理\|governance`，对齐风语者原探针） | **56 份** | 21 份（yaml `problem` 自述） |
| 任务关键词全口径（六个关键词并集） | 根 4 / docs 19 / reports 126 / memory 15 | — |

**新旧对照的可考锚点**：旧 yaml `evidence` 只留了 10 份名录（21 的完整名录不可复现），这 10 份**全部仍在本轮窄口径 56 份命中清单内**（10/10）。56 − 21 的差值主要是 2026-10-22 之后新落的报告（overnight-governance-digest、fist-dir-layout-cleanup、plan-landing 系列等）、memory 当日日志与新落的 `docs/README.md`/`docs/plans/` 子树——是**命中面自然增长**，不是旧账恶化。

### 逐份归类清单（窄口径 56 份全列）

**b 类（真源本体 / 入口面 / 已含真源指针）——9 份，无需动作：**

| 文件 | 依据 |
|---|---|
| `AGENTS.md` | 行为规范面真源本体（宽口径命中「守卫族/J 判据」自述） |
| `AI-DEVELOPMENT-STANDARD.md` | 开发规范正文真源本体 |
| `docs/DOCS-STRUCTURE.md` | 文档结构规范真源本体（本轮边界：不动） |
| `docs/README.md` | docs/ 目录索引（T0r8 刚落，含逐份指针；本轮边界：不动） |
| `docs/proposal-process.md` | 讲提案→定案→执行闭环规则，**§6 表格已显式引用** `SOP.md` / `DOCS-STRUCTURE.md` / `AI-DEVELOPMENT-STANDARD.md` 且标明「只引用，不重写」（`docs/proposal-process.md:160-165`） |
| `docs/plans/README.md` | 讲计划治理硬规则，头注已引用 `AI-DEVELOPMENT-STANDARD.md` §2 对齐（`docs/plans/README.md:6`） |
| `README.md` / `USAGE.md` / `README_EN.md` | 入口面（被 `check_doc_surface` / `check_test_sync` 钉在根，见 DOCS-STRUCTURE §根目录文件清单） |
| `项目申报书.md` | 宽口径 1 处命中为功能表「运维治理」行 + 已显式引用 `AI-DEVELOPMENT-STANDARD.md` §7（`项目申报书.md:11`）；提及非规则 |

**a 类（历史陈述面——reports/ 34 份，只读证据，永不回写，DOCS-STRUCTURE 处理口径明文豁免）：**

reports/2026-09-20-pipeline-watchdog-state-machine.md · 2026-09-25-award-enhancement-r15-cleanup · 2026-09-25-r75-dag-schedule-load · 2026-09-25-r76-r77-gate-fail-cost-route-pass · 2026-09-25-r79-r80-count-sync-trust-axis · 2026-09-25-r81-budget-split · 2026-09-26-r100-goal-drift-check · 2026-09-26-r102-health-check · 2026-09-26-r104-circuit-breaker · 2026-09-26-r106-english-readme · 2026-09-26-r107-quickcheck · 2026-09-26-r108-gate-reconfirm · 2026-09-26-r109-transactional-transition · 2026-09-26-r110-gate-reconfirm · 2026-09-26-r111-evaluator-optimizer-schema · 2026-09-26-r112-gate-reconfirm · 2026-09-26-r87-agora-auction · 2026-09-26-r88-progress-gate · 2026-09-26-r89-phi-accrual · 2026-09-26-r90-phi-gate · 2026-09-26-r91-gate-reconfirm · 2026-09-26-r92-saga-compensation · 2026-09-26-r94-dag-mc · 2026-09-26-r96-local-compensation · 2026-09-26-r98-plan-revise · 2026-09-26-devstandard-align · 2026-09-26-polish-issue-scan · 2026-09-26-router-merge · 2026-09-26-selfloop-3round-summary · 2026-09-26-selfloop-round2 · 2026-09-26-selfloop-round3 · 2026-09-27-round4 · 2026-09-27-round5 · 2026-09-28-installed-cli-tour · 2026-09-28-open-clearing · 2026-09-29-final-review-prep · 2026-09-29-mooncakes-publish · 2026-10-01-bug130-native-heap-rootcause · 2026-10-02-bug130-ruling3-native-gate · 2026-10-02-bug134-resolved-path-absolute · 2026-10-07-bug132-nightly-dead-gate · 2026-10-07-bug135-release-status-phrase · 2026-10-07-bug136-137-138-reserve-caller-encoding · 2026-10-10-p2-guards · 2026-10-11-r12-cycle10 · 2026-10-11-r12-cycle11 · 2026-10-11-r12-followup · 2026-10-11-r12-followup2-leftovers · 2026-10-11-r14-goal-round4 · 2026-10-11-r15-goal-round5 · 2026-10-11-r17-goal-round7 · 2026-10-13-ci-format-int32-diagnosis · 2026-10-13-ci-guard-clean-tree-two-reds · 2026-10-13-ci-js-track-predict-hidden-drift · 2026-10-13-http-contract-selftest · 2026-10-13-master-broken-src-diff-diagnosis · 2026-10-13-multilane-lock-mechanism · 2026-10-13-native-arms-green-bug133 · 2026-10-13-pkg-imports-guard · 2026-10-13-second-breakage-20-errors · 2026-10-13-simulate-head-commit · 2026-10-14-j14-template-count-face · 2026-10-14-lock-acquire-mutex · 2026-10-14-template-control-char-guard · 2026-10-14-test-green-and-backlog-convergence · 2026-10-14-test-sync-1051 · 2026-10-15-bug156-fix-and-refactor-verify · 2026-10-15-cl7-unlock-and-toolsync-166 · 2026-10-15-round150-milestone · 2026-10-15-round151-governance · 2026-10-15-round43-min-evidence-boundary · 2026-10-16-round262-plugin-forms-and-verify · 2026-10-17-marvis-junxian-soldier · 2026-10-19-fist-mbt-round17-guard-enumeration-fix · 2026-10-19-round18-guard-selftest-bug332 · 2026-10-19-round19-cleanup-scan-bug333 · 2026-10-19-round5-adversarial-guard-lock · 2026-10-19-round8-gates-and-badge-stale · 2026-10-20-r2-verify-sweep · 2026-10-20-r3-entry-path-guard · 2026-10-20-r4-plugin-sync · 2026-10-20-r5-full-verify · 2026-10-20-r6-ci-audit · 2026-10-20-r7-guard-resweep · 2026-10-20-r8-bug333-denoise · 2026-10-20-slave-docs-test-count-1302-sync · 2026-10-21-r25-health-baseline-evidence · 2026-10-21-r27-guard-family-all-green · 2026-10-21-r28-contract-probes-and-guard-selftests · 2026-10-21-r29-ci-guard-wiring-gap-fix · 2026-10-21-r30-issue-scan-fp-corpus-on-clean-code · 2026-10-21-r31-test-gate-green-and-fmt-drift-cleared · 2026-10-21-r32-regression-verify-and-fix-patch-esm-help · 2026-10-21-r36-bugbear-scan-and-guard-verify · 2026-10-21-slave-task005-gate-scan-r83 · 2026-10-21-slave-task006-docs-structure-r85 · 2026-10-21-slave-task009-whisperer-r86 · 2026-10-22-backlog-reconcile-r119 · 2026-10-22-backlog-status-reconcile-r111 · 2026-10-22-guards-inline-verdict-r121 · 2026-10-22-memory-log-dup-r133 · 2026-10-22-merge-backlog-clear · 2026-10-22-moon-spawn-shim-r125 · 2026-10-22-slave-r94-main-cef1e9c-integration · 2026-10-22-slave-r95-scripts-naming · 2026-10-22-slave-task009-whisperer-write-side-r90 · 2026-10-23-backlog-anchor-no-copy-count-r175 · 2026-10-23-entry-cwd-anchor-r170 · 2026-10-23-toolchain-floor-guard-r141 · 2026-10-23-write-gate-T0r3 · 2026-10-24-asset-preservation-proof · 2026-10-24-branch-cleanup-execution · 2026-10-24-merge-precedents · 2026-10-24-structure-gap-analysis · 2026-10-25-overnight-governance-digest · 2026-10-25-scout-audit-single-value-hardcode · 2026-10-26-plan-landing-judge-improvement · 2026-10-26-plan-landing-p0-execution · 2026-10-26-plan-landing-triage · 2026-10-27-backend-equiv-locks-landing · 2026-10-27-bug433-ns-fallback-plan · 2026-10-27-fist-dir-layout-cleanup · 2026-10-27-r18-two-faces-broad-scan · 2026-10-27-r19-unimplemented-plans-and-s3 · 2026-11-02-r121-crlf-precedents-ruler · **reports/INDEX.md**（纯报告索引，指向报告标题，不含自创规则）

*（以上均带 `.md` 后缀、位于 `reports/`；计数 126 份含上列与仅宽口径命中的报告。）*

**a 类（docs/ 历史归档/计划/提案/定案留痕——9 份）：**

| 文件 | 命中内容性质 |
|---|---|
| `docs/2026-10-11-multi-agent-lock-design-v3.md` | 历史设计稿（1 处命中为 SQL 注释） |
| `docs/2026-10-21-fist-governance-tier2-plan.md` | 历史升级计划（Tier 2 治理能力规划，2026-10-21，docs/ 归档面） |
| `docs/2026-10-20-slave-dev-playbook.md` / `docs/2026-10-20-slave-tasks.md` | 历史任务包/手册（守卫族引用） |
| `docs/improvement-plan-20261010.md` | 历史计划集合 |
| `docs/archive/` 5 份（upgrade-plan-v2、multi-agent-lock-design v1/v2、improvement-plan-20260929、improvement-proposals-20260928） | 归档 |
| `docs/plans/2026-10-22-fist-dir-layout-governance-proposal.md`、`plans/2026-10-22-rx-mbt-lightweight-proposal.md`、`plans/2026-10-26-4pools-rhop-roadmap-proposal.md` | 提案留痕（已定案，定案记录在 decisions/） |
| `docs/plans/decisions/2026-10-22-001/002` | 定案记录留痕 |

**a 类（memory/ 历史陈述面——15 份）：** `memory/2026-10-23.md`、`2026-10-28.md`、`2026-10-31.md`、`2026-11-02.md`（追加式日志）、`memory/bugs.md`（缺陷账本）、`memory/research/` 9 份研究摘录与 `_snapshot.md`、`memory/selfdrive-modes.md`（1 处命中为功能表「治理面」行——提及非规则）。

**a 类（根目录历史陈述面）：** `CHANGELOG.md`（28 处宽口径命中全是「守卫族/J 判据」历史记述；DOCS-STRUCTURE 处理口径点名 CHANGELOG 属历史陈述面，不算债）。

**c 类：空。**

### 验收判据实测

- `python scripts/check_doc_paths.py` → `PASS 文档路径引用全部存在（8 份文档 / 47 处引用）`，**rc=0**（本轮零编辑，基线即终态；本轮会话内实测）。
- 工具状态机：T0r9 已 claim（assignee=lane-i-task016）→ execute（状态=执行中）→ 本报告落盘后 submit。

## 分析

1. **旧 21 的定性已被真源自己裁定**：`docs/DOCS-STRUCTURE.md` §「治理主题散在 19 个文件」的处理口径（R85 落地）明确：规范性表面只有 `AI-DEVELOPMENT-STANDARD.md` 一处真源，其余命中是历史陈述面，**历史面不追改、不算债**。本轮逐份现核证实该口径在现状面无遗漏——没有任何一份「讲规则」的文件游离在真源指针之外。
2. **两份「讲规则」的规范文件（proposal-process.md / plans/README.md）落笔时就带了真源指针**，属于 b 类；且二者的目录落位（docs/ 平铺、plans/ 子树）本身已符合 DOCS-STRUCTURE 的 T0r8 增补分流表。
3. **命中面 21 → 56 的增长是良性的**：增量全部是 reports/ 轮次报告与 memory 日志（第 3 类定位，允许出现治理字样），以及治理收敛动作自身留下的文档（docs/README.md、plans/ 子树）——收敛动作没有制造新的第二真源。

## 缺口与风险

- **旧 21 完整名录不可复现**：`TASK-016-docs.yaml` 的 evidence 只留 10 份（10/10 仍命中）。新旧对照以名录锚点 + 两个口径读数呈现，无法逐份对 21——这是旧证据自述滞后（BUG-514 同族形状），不是本轮缺口。
- **`docs/plans/README.md` 属 b/c 边界**：其「硬规则」4 条本身无内联指针，真源引用在头注（2026-10-24 追记）。本轮按任务定义（文件内已有真源引用即 b）不改动；若统帅希望指针更醒目，可在「硬规则」节前补一行——属可选打磨，非债务。
- **reports/ 126 份命中会继续增长**：这是第 3 类文档的常态，不需要任何动作；唯一的防线是真源唯一性本身（已由 `check_doc_surface` J6/J7 守卫）。

## 后续建议

1. TASK-016 盖 **done**（或直接归档），backlog 技术项清零；`docs/tasks/backlog/TASK-016-docs.yaml` 的状态位由统帅终审时更新（本车道按边界未动 yaml）。
2. 不建议为「历史报告里的治理字样」立任何新守卫——J7 已守住规范性表面唯一性，扫历史面只会制造假红。
3. 若未来出现新的治理规则文档，按 `docs/DOCS-STRUCTURE.md` T0r8 分流表落位并在正文引用真源（proposal-process.md 已是范式）。

## 超额内容

无（零文件编辑，普查面外扩到全口径关键词属任务①的应有之义）。

## 来源

- 任务全文：fist-mbt 流水线 ns `iterate-1102` / T0r9（描述原文）
- 旧证据：`docs/tasks/backlog/TASK-016-docs.yaml`（discovered_at 2026-10-22T01:10:13Z）
- 真源：`docs/DOCS-STRUCTURE.md`（含 T0r8 增补）、`AI-DEVELOPMENT-STANDARD.md`、`AGENTS.md`
- 实测：`python scripts/check_doc_paths.py` rc=0（本轮会话内）；Python 正则普查（关键词与排除面见「证据」节）
