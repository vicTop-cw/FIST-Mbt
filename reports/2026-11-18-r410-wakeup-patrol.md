# 轮 410 唤醒巡检——换面 check_ci_step_position

**时间**：本地 2026-11-18 06:40 / UTC 2026-11-17T22:40
**HEAD**：`73273bb5c`（r409）
**WIP**：6M（全 unstaged，本轮暂存面空、无 flux）+ 1 untracked（他方 `reports/2026-11-17-iter-r192-report.md`）。bugs.md mtime 2026-11-15 23:40:40 未动（冻结第 17 轮）。

## 换面：check_ci_step_position

CI 硬门判据（TASK-003 / R84「gate 步骤位置纪律」，CI #275 实证）：`Migrate mooncakes dep manifests` 一步失败会 skip 其后全部步骤——CI #98/#99 起是两次 master 级坏状态的公共放大器。本判据把「位置纪律」机械化：对每个含 `Migrate mooncakes` 步骤的 job，凡被分类为 gate 的步骤（name 命中 gate/guard/守卫/门禁，或 run 块引用 `scripts/check_*.py`）位置在 Migrate **之后**且步骤块内无 `position-why:` 锚点 ⇒ 违例。锚点必须在步骤块内（该步 `- name:` 行到下一 `- name:` 行之间）——放块外前一行属上一步的块，判不到。F2 continue-on-error 步骤（不限 gate 名）只报不判、防「降门」悄悄蔓延成默认；F3 无 Migrate 步骤的 workflow 里的 gate 步骤豁免位置纪律、只出数。棘轮：违例总数（只含 F1）≤ POSITION_WHY_CEILING，只许降不许升（BUG-362/367 先例）。

- **selftest**：rc=0 `T1–T9 九格`（可红可绿含变异对照：T1 后置无锚必红 F1=1 / T2 后置有锚不红 F1=0 / T3 前置无锚不红 F1=0 / T4 无 Migrate 豁免 F1=0 / T7 非 gate 步骤不抓 F1=0 / T8 check_ 脚本引用也算 gate F1=1 / T5 continue-on-error 出数不判红 F1=0,coe=1 / T6 空文本零步骤 steps=0 / T9 真源现状 rc=0 上限内=0）
- **实跑**：rc=0 `position-why 锚点面：8 份 workflow / 133 步骤 / 8 个 Migrate 基准；缺锚点违例 29（上限 34，只许降）` + `PASS gate 步骤位置纪律在棘轮上限内`。F2 continue-on-error 步骤 6 处（只报不判：ci.yml check-and-test-js Plan-landing 观测臂×2 / Format check、ci.yml check-windows-js Public install line e2e、fist-ci.yml test-js Format check、release.yml build-native-windows Refresh registry）；F3 无 Migrate workflow 的 gate 步骤 2 处（gate.yml Run unified gate chain / Branch-ancestry gate R66/BUG-398，豁免位置纪律只出数）。
- **近未单巡**：近 15 轮（r395 ns_write_gate / r396 doc_surface / r397 sql_bind / r398 battery_count / r399 host_installable / r400 mbti_sync / r401 precedents_doc / r402 two_faces / r403 release_asset / r404 doc_surface / r405 model_auth / r406 store_tables / r407 mcp_stdio / r408 workflow_step_parity / r409 doc_dup）换面清单反解不含 `check_ci_step_position`，且其输入面 `.github/workflows/*.yml` 本轮零 WIP 触碰，一次干净的「CI gate 位置纪律」回面复核，不属重复空转。

**无新发现（类型）、无新立账**（换面 + 常设面全绿零漂移）。

## 零漂移常设面

| 面 | 读数 | 状态 |
|---|---|---|
| `check_tools_sync` | 183 工具 R8 19 组 ΣN=183 | PASS |
| `check_instruction_budget` | 50440/65536 | PASS |
| `patch_esm_main` | 0/10 bundles up to date | up to date |

全 rc=0 零漂移。

## Round C 队列

空态确认（r385 2026-11-17 逐项实证，后续轮不重核）：
- BUG-527 治本：owner 否决严禁重跑（2026-11-02 A/B 裁决：摘库包 cc-link-flags 反断 CI native）
- BUG-530：FIXED（`3699f012a`）
- check_usage_tool_count：已注册 run_guards.py:175
- check_tool_coverage：延后至 bugs.md 解冻（BUG-636 中危判据缺陷）

⇒ 既定目标为空，不派单，走巡检分支。

## FIST 闭环

T0r166 六步（publish/agent_acl_grant/claim/execute/submit/verify）全 rc=0（wd-r410 / ns watchdog / `temp/fist_r410_chain.sh` 后台串跑 job bg-1），`get` 终审 `status=已完成`、`completed_by=wd-r410`、`assignee=wd-r410`、deliverable=本报告、created_at=2026-11-17T22:39:14Z / updated_at=2026-11-17T22:39:20Z（后台串跑秒级收口；patch_esm_main 探针先行 0/10 防 transient MemoryError，未复现）。

## 提交纪律实证（本轮）

本轮暂存面空（他方 WIP 6M 全 unstaged + 1 untracked，无 flux），scoped 提交策略：`git add` 新报告 → `git commit -F msg -- <报告>`，只提交本报告 pathspec 的 working-tree 版本，不扫入他方未暂存件（r409 已实证局部提交不扫入他方已暂存件）。

## 禁区

他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零碰；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 后续建议

- Round C 队列空态持续，待 owner 设下一目标。
- WIP iter-r192 车道持续冻结 ≥17 轮（r393 起未动），建议 owner 确认该车道状态（收口 / 放弃 / 继续）。
