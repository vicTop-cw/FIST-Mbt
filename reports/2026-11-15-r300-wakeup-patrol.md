# 轮 300 唤醒巡检报告（ExploreWatchdog）

- 时间：2026-11-15
- 触发：Windows 计划任务 FIST-Mbt-ExploreWatchdog 例行 30 分钟唤醒
- 角色：fist-commander 非阻塞巡检（指挥官不代行 owner 裁决与清理）

## 1. WIP 收口核对

四件套逐字冻结 **第 17 轮**（r284 起连续）：

| 文件 | mtime | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 2026-11-14 10:55 | M |
| memory/bugs.md | 2026-11-14 10:47 | M（+200 行） |
| memory/target.md | 2026-11-10 10:34 | M |
| scripts/check_mcpcf_db_isolation.py | 2026-11-14 11:11 | ??（23423 B） |

- `git diff --stat` 逐字同 r284~r299：3 文件 208+/2-，相对 r299 零新增量。
- mtimes 全早于 r284 提交时刻（15:19:37）⇒ 冻结判定维持。
- r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理，不可逆操作先出方案）。

## 2. Round C 队列

维持过期不执行（既定记忆，勿重推导）：
- BUG-527 摘 cc-link-flags：owner 否决（CI A/B 实证有害，d43a06a28→8a669992d 回滚）；
- BUG-530：已 FIXED（3699f012a）；
- check_usage_tool_count：已注册（scripts/run_guards.py:175）。

## 3. 换面巡检：check_plan_location（plans/proposals 双目录纪律）

选面理由：r294~r299 未轮过；run_guards.py:251-252 已登记干净 case + `--selftest` 双格；
扫描面（docs/plans + docs/proposals 文件名/frontmatter/status 闭集/终态归档位置）完全避开 WIP 四件套，读数干净。

- `--selftest`：49/49 rc=0（含 resolve-dirs-default/pair 覆盖、arg-unknown-flag-rc2 严格参数面、enumerate-only-this-level 等格）。
- 实测：rc=0，两面 8 份文档文件名/frontmatter/status 闭集/已定案自洽/终态归档位置全部合规；
  1 条 P6 告警（docs/plans/2026-10-26-4pools-rhop-roadmap-proposal.md `status=已推迟` 是终态仍留活动目录，建议移 docs/plans/archived/）——**仅告警不判红，归档由人决定**，本轮不代行。

**无新发现、无新立账。**

## 4. 零漂移例行复跑

| 尺 | 读数 | rc |
|---|---|---|
| check_tools_sync | 183 工具（R8 分组 19 组 ΣN=183 对表） | 0 |
| check_instruction_budget | 50440/65536 字节 | 0 |

（两者每轮独立复跑，防漂移雷。）

## 5. FIST 闭环

六步串跑后台收口（node 冷启动 ~2min/发，前台 60s 上限不可行），call 落盘 `temp/fist_r300_out/`：

1. publish（ns watchdog）→ task_id T0r56，claim_ready=true，writable_agents 54→55
2. agent_acl_grant（wd-r300，can_write）→ 已落库
3. claim（assignee=wd-r300）→ status=已领取
4. execute（agent=wd-r300，deliverable=本报告）→ status=执行中
5. submit（agent=wd-r300）→ status=待验收
6. verify（verifier=wd-r300）→ status=已完成，completed_by=wd-r300

六步全链 rc=0 一发收口。

## 6. 遗留风险 / 后续建议

- WIP 四件套冻结已 17 轮（跨 11-14→11-15 两天），owner 弃置裁决仍是唯一解法；指挥官维持挂起、不代行清理。
- check_plan_location 实测发现 1 条 P6「已推迟」留活动目录（仅告警不判红）——归档由人决定，指挥官不代行移档（越权操作先出方案）。
- 换面巡检队列消耗进度：r284~r300 已轮 13 面，未轮过面（check_entry_paths / check_demo_isolation / check_release_asset_names / check_model_auth_no_key / check_template_ctrl / check_pkg_imports 真跑面等）仍有余量，后续轮次继续轮换。
- 无新立账、无新发现。

## 7. 来源

- git status / git log（会话起始快照 + 本轮复跑）
- `git diff --stat` + `stat -c '%y %n'`（冻结判定）
- `python scripts/check_plan_location.py --selftest` / 真跑（本轮首跑）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`（独立复跑）
- `temp/fist_r300_out/1~6_*.txt`（六步回执原件）
