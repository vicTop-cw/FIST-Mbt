# 轮 399 唤醒巡检报告（FIST-Mbt-ExploreWatchdog）

> 日期 2026-11-18 ｜ 轮次 r399（HEAD `90722361a`，r398 之后无新提交）｜ agent wd-r399 ｜ ns watchdog

## 一、唤醒状态

- **WIP 收口核查**：`git status --short` = 6M + 1 untracked，与 r393~r398 一致（iter-r192 车道在途：`dist/fist-mbt.js` 已暂存 M、`memory/bugs.md` +216/0、`memory/target.md`、`scripts/README.md`、`scripts/check_plan_landing.py`（车道 F：磁盘采集子串排除缺陷修复，selftest 64→71 格）、`templates/pipeline_mode_loop.md`、untracked `reports/2026-11-17-iter-r192-report.md`）⇒ iter-r192 车道仍未收口，**禁区零碰**（零改零提交，他方 WIP 一概未动）。
- **Round C 队列维持 r385 实证移交态**：BUG-527 治本已被 2026-11-02 追记3 A/B 裁决否决（摘库包 link 反断 CI native）/ BUG-530 已 FIXED（`3699f012a`）/ `check_usage_tool_count` 已注册（run_guards.py:175，selftest 13/13 真源=183）⇒ **既定目标为空**，不派单，走巡检分支（标准动作 3）。

## 二、换面巡检：`check_host_installable`（宿主可装性）

选择依据：该面守「deepseek-harness 宿主侧**真的能装上**」——cl7 `check_plugin_sync` 只判「插件态==投影」，装不装得上它看不见（AGENTS.md 守卫族明列的补位判据）。近 20 轮换面清单反解：`check_host_installable` 上次单巡在 **r387（约 12 轮前）**，且其后 R183 第②笔锚点提交（`e1ef8bbd4`）推进过电池计数面、r393 修过 `check_mbti_sync` 前缀式解析——投影面动过、宿主可装性面宜复核一次。

| 项 | 结果 |
|---|---|
| `--selftest` | **rc=0**：DSH 严格档（相对路径 / timeout_ms / reconnect 键名 / 未定义占位符）**必红**；干净 DSH + 默认模板 + 宽松档**不误红**；输入面退化自拒；字段白名单反解自真源 |
| 全量实跑 | **rc=0 PASS**：DSH manifest/patch（绝对路径 + toolCallTimeoutMs + dsh reconnect schema）合规；宽松档 MCP JSON 合规；默认模板合法性合规；moon.mod 版本 0.3.11 |
| WARN | 3 条（`.mcp.json` / `.mcp.dev.json` / `plugins/claude/.mcp.json` 的 `timeout_ms` 字段）——**信息级**（部分客户端按自身 schema 忽略该字段，是否改真源由人终审），与恒态基线一致，非漂移 |

**结论：零漂移**（宿主可装性面 12 轮来首次单巡复核，投影推进后宿主侧仍可装，WARN 面未变）。

## 三、零漂移常设面

| 判据 | 结果 |
|---|---|
| `check_tools_sync` | rc=0（server.mbt 注册 183；AGENTS/README/deliverable/scoring_rubric 对齐；R3b/R7 扫现状面 169 份、历史面豁免 25 份；R8 清单 19 组 ΣN=183） |
| `check_instruction_budget` | rc=0（AGENTS.md = 50440 / 预算 65536，全部章节可见） |
| `patch_esm_main` | rc=0（10 bundle 全 up to date / total patched 0） |

## 四、立账与禁区

- **无新发现（类型）、无新立账**（换面 + 常设面全绿零漂移）。
- **禁区零碰**：6M + 1 untracked 他方 WIP（iter-r192 车道 + 外来账 BUG-592~636）零改零提交。
- **外来账 BUG-592~636（BUG-565 族）**：`memory/bugs.md` 的 +216 行 WIP 全为 vq 项目缺陷条目（reported_by WorkBuddy P4/P5、vq-p6/p7-commander、vq 统帅 P7-3），非本仓元条目，维持冻结待 owner 裁决（搬移 vq 仓 / 带理由登记 WHITELIST kind=foreign-adjudicated）；本巡检不立新 BUG 号（防撞号，BUG-636 已两义并存）。

## 五、FIST 闭环

T0r155 六步全链 **rc=0**（wd-r399 / ns watchdog / `temp/fist_r399_chain.sh` 稳健 TID 提取后台串跑；patch_esm_main 探针先行 10 bundle up to date / 0 patched 防 MemoryError）。verify 回执：status=已完成、completed_by=wd-r399、assignee=wd-r399、deliverable=reports/2026-11-18-r399-wakeup-patrol.md、namespace=watchdog、created_at=2026-11-17T17:04:04Z / updated_at=2026-11-17T17:04:10Z。

## 六、遗留风险与后续建议

1. **外来账 BUG-592~636（BUG-565 族）冻结待 owner**：建议 owner 裁决搬移 vq 仓或登记 WHITELIST（kind=foreign-adjudicated）；根治面（server cwd 钉本树、调用方无出路）仍未落地，检测半 `check_foreign_ledger_entries` 已注册（run_guards.py:333-334）。
2. **Round C 队列空**：既定迭代目标为空，需 owner 设下一目标（与 r385 移交态一致，持续挂起）。
3. **iter-r192 车道在途 30+ 轮未收口**（dist 重构 + 外来账 +216 行 + check_plan_landing 车道 F 提交③ 就绪）：其 scoped 提交收口前本树维持「巡检分支」节奏。`dist/fist-mbt.js`（41402+/35319-）为巡检中止轮遗留、r192 报告点名「归属巡检专门轮、统帅未代收」——本巡检**不代收**（近全文件重写属他方未定稿重构面，卷入提交有风险），留待 owner 裁决或专门轮收口。

*（内容由AI生成，仅供参考）*
