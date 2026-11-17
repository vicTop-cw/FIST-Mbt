# 轮 408 唤醒巡检——换面 check_workflow_step_parity

**时间**：本地 2026-11-18 ~05:38 / UTC 2026-11-17T21:38
**HEAD**：`f443dd7b2`（r407）
**WIP**：6M（全 unstaged）+ 1 untracked（他方 `reports/2026-11-17-iter-r192-report.md`），与 r393~r407 一致，暂存面为空。bugs.md mtime 2026-11-15 23:40:40 未动（冻结第 15 轮）。

## 换面：check_workflow_step_parity

CI 硬门判据（R87 · BUG-490 家族）：同源 workflow（`ci.yml` 测试面 / `release.yml` 发布面）之间「跑 moon 的 job」必须先 `migrate_mooncakes_modjson`——依赖惰性解包，漏 migrate 即 `Failed to resolve the module dependency graph`。S1 跑 moon 的 job 必须**前序**有 migrate（顺序错等于没做）；S2 覆盖面对表；S3 读不到/枚举不到/零 moon 步骤 ⇒ rc=2 自拒。

- **selftest**：rc=0 `7 格通过`（可红可绿：干净不误红 / 缺 migrate 必红 / 顺序错必红 / 空 job 自拒 / 空 moon 自拒 / 未豁免的静默 job 必报 / 同步合规）
- **实跑**：rc=0 `扫描面 ci.yml + release.yml；跑 moon 的 job 6 个 / 有 migrate 的 job 6 个；PASS：全部「跑 moon」的 job 都先 migrate；不跑 moon 的 job 已逐条点名理由`
- 近 21 轮未单巡（r387~r407 覆盖面史查无此面），输入面（`.github/workflows/*.yml`）零 WIP 触碰，回面复核有效。

## 零漂移常设面

| 面 | 读数 | 状态 |
|---|---|---|
| `check_tools_sync` | 183 工具 R8 19 组 ΣN=183 | PASS |
| `check_instruction_budget` | 50440/65536 | PASS |
| `patch_esm_main` | 0/10 bundles up to date | up to date |

全 rc=0 零漂移。

## 立账

无新发现（类型）、无新立账。

## Round C 队列

空态确认（r385 2026-11-17 逐项实证，后续轮不重核）：
- BUG-527 治本：owner 否决严禁重跑（2026-11-02 A/B 裁决：摘库包 cc-link-flags 反断 CI native）
- BUG-530：FIXED（`3699f012a`）
- check_usage_tool_count：已注册 run_guards.py:175
- check_tool_coverage：延后至 bugs.md 解冻（BUG-636 中危判据缺陷）

⇒ 既定目标为空，不派单，走巡检分支。

## FIST 闭环

T0r164 六步（publish/agent_acl_grant/claim/execute/submit/verify）全 rc=0（wd-r408 / ns watchdog / `temp/fist_r408_chain.sh` 后台串跑 job bg-1），`get` 终审 `status=已完成`、`completed_by=wd-r408`、`assignee=wd-r408`、deliverable=本报告、created_at=2026-11-17T21:40:37Z / updated_at=2026-11-17T21:40:42Z。（本轮连上常驻热 server，秒级收口，未复现内存压力 transient MemoryError——patch_esm_main 探针先行 0/10 已确认环境干净。）

## 禁区

他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零碰；`dist/fist-mbt.js` 巡检中止轮遗留不代收，留 owner/专门轮。

## 后续建议

- Round C 队列空态持续，待 owner 设下一目标。
- WIP iter-r192 车道持续冻结（r393 起 ≥15 轮未动），建议 owner 确认该车道状态（收口 / 放弃 / 继续）。
