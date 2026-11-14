# 轮 301 唤醒巡检报告（ExploreWatchdog）

- 时间：2026-11-15
- 触发：Windows 计划任务 FIST-Mbt-ExploreWatchdog 例行 30 分钟唤醒
- 角色：fist-commander 非阻塞巡检（指挥官不代行 owner 裁决与清理）

## 1. WIP 收口核对

四件套逐字冻结 **第 18 轮**（r284 起连续）：

| 文件 | mtime | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 2026-11-14 10:55 | M |
| memory/bugs.md | 2026-11-14 10:47 | M（+200 行） |
| memory/target.md | 2026-11-10 10:34 | M |
| scripts/check_mcpcf_db_isolation.py | 2026-11-14 11:11 | ??（23423 B） |

- `git diff --stat` 逐字同 r284~r300：3 文件 208+/2-，相对 r300 零新增量。
- mtimes 全早于 r284 提交时刻（15:19:37）⇒ 冻结判定维持。
- r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理，不可逆操作先出方案）。

## 2. Round C 队列

维持过期不执行（既定记忆，勿重推导）：
- BUG-527 摘 cc-link-flags：owner 否决（CI A/B 实证有害，d43a06a28→8a669992d 回滚）；
- BUG-530：已 FIXED（3699f012a）；
- check_usage_tool_count：已注册（scripts/run_guards.py:175）。

## 3. 换面巡检：check_entry_paths（入口清单守卫）

选面理由：r284~r300 未轮过（r300 报告的未轮过面清单首项）；run_guards.py:432 已登记干净 case；
扫描面（脚本/文档/CI/根 .md/.mcp*.json/根入库 .py，历史面除外）完全避开 WIP 四件套，读数干净。

- `--selftest`：17/17 rc=0（R1 夹具命中 2 / 干净不误红 / 空清单报空转 / R2 缺 serve 成对 / 根 .py 选取与入面成对 / R3 裸相对产物必红·合法 join 不误红·注释不误红 / e2e 五格含 docstring 豁免不弱化代码面）。
- 实测：rc=0。入口清单 cmd/cli, cmd/commissar, cmd/main｜发布 cmd/cli｜退役 cmd/commissar, main；
  扫描面 390 份（历史面除外）：退役入口引用 0 处 / 缺 serve 启动器 0 个 / 裸相对产物寻址 0 处。
- 附带观察：仓库根有 1 份未入库 .py `execute_cron.py`（68731 B，mtime 2026-09-18 15:49，
  .gitignore:36 命中）——系 gitignore 本机旧件，非新 WIP，CI 检出里不存在，判据按「未入库不判」正确放行，无需立账。

**无新发现、无新立账。**

## 4. 零漂移例行复跑

| 尺 | 读数 | rc |
|---|---|---|
| check_tools_sync | 183 工具（R8 分组 19 组 ΣN=183 对表） | 0 |
| check_instruction_budget | 50440/65536 字节 | 0 |

（两者每轮独立复跑，防漂移雷。）

## 5. FIST 闭环

六步串跑后台收口（node 冷启动 ~2min/发，前台 60s 上限不可行），call 落盘 `temp/fist_r301_out/`：

1. publish（ns watchdog）→ task_id T0r57，claim_ready=true，writable_agents 55→56
2. agent_acl_grant（wd-r301，can_write）→ 已落库（granted_rows 1 行）
3. claim（assignee=wd-r301）→ status=已领取
4. execute（agent=wd-r301，deliverable=本报告）→ status=执行中
5. submit（agent=wd-r301）→ status=待验收
6. verify（verifier=wd-r301）→ status=已完成，completed_by=wd-r301

六步全链 rc=0 一发收口。

## 6. 遗留风险 / 后续建议

- WIP 四件套冻结已 18 轮（跨 11-14→11-15 两天），owner 弃置裁决仍是唯一解法；指挥官维持挂起、不代行清理。
- 换面巡检队列消耗进度：r284~r301 已轮 14 面，未轮过面（check_demo_isolation / check_release_asset_names / check_model_auth_no_key / check_template_ctrl / check_pkg_imports 真跑面等）仍有余量，后续轮次继续轮换。
- 无新立账、无新发现。

## 7. 来源

- git status / git log（会话起始快照 + 本轮复跑）
- `git diff --stat` + `ls -la`（冻结判定）
- `python scripts/check_entry_paths.py --selftest` / 真跑（本轮首跑）
- `python scripts/check_tools_sync.py` / `python scripts/check_instruction_budget.py`（独立复跑）
- `temp/fist_r301_out/1~6_*.txt`（六步回执原件）
