# 轮 298 唤醒巡检报告（ExploreWatchdog）

- 时间：2026-11-15
- 触发：Windows 计划任务 FIST-Mbt-ExploreWatchdog 例行 30 分钟唤醒
- 角色：fist-commander 非阻塞巡检（指挥官不代行 owner 裁决与清理）

## 1. WIP 收口核对

四件套逐字冻结 **第 15 轮**（r284 起连续）：

| 文件 | mtime | 状态 |
|---|---|---|
| docs/improvement-plan-20261010.md | 2026-11-14 10:55 | M |
| memory/bugs.md | 2026-11-14 10:47 | M（+200 行） |
| memory/target.md | 2026-11-10 10:34 | M |
| scripts/check_mcpcf_db_isolation.py | 2026-11-14 11:11 | ??（23423 B） |

- `git diff --stat` 逐字同 r284~r297：3 文件 208+/2-，相对 r297 零新增量。
- mtimes 全早于 r284 提交时刻（15:19:37）⇒ 冻结判定维持。
- r287 提请的 owner 弃置裁决维持挂起（指挥官不代行清理，不可逆操作先出方案）。

## 2. Round C 队列

维持过期不执行（既定记忆，勿重推导）：
- BUG-527 摘 cc-link-flags：owner 否决（CI A/B 实证有害，d43a06a28→8a669992d 回滚）；
- BUG-530：已 FIXED（3699f012a）；
- check_usage_tool_count：已注册（scripts/run_guards.py:175）。

## 3. 换面巡检：check_ns_write_gate_coverage（BUG-459）

选面理由：电池仅登记 `--selftest` 一格、真跑面无人认领；扫描面
（src/server/write_gate.mbt + src/server/server.mbt）完全避开 WIP 四件套，读数干净。

- `--selftest`：9/9 rc=0（干净三支 rc=0 / 变异删代码行必红 / 注释冒充不接线必红 /
  文档多声称必红 / 代码多一门必红 / 文档清单缺失自拒 rc=2 / 注册块缺失自拒 rc=2 /
  门挪出块外必红；清单从已执行格子反解，不手写）。
- 实测：rc=0，文档声称 == 实际调用点（3 支：publish / publish_parallel / dag_publish）。

**无新发现、无新立账。**

## 4. 零漂移例行复跑

| 尺 | 读数 | rc |
|---|---|---|
| check_tools_sync | 183 工具 | 0 |
| check_instruction_budget | 50440/65536 字节 | 0 |

（两者每轮独立复跑，防漂移雷。）

## 5. 遗留风险 / 后续建议

- WIP 四件套冻结第 15 轮，owner 弃置裁决仍挂起；若下轮 mtimes/diff 仍逐字同，
  建议 owner 尽快裁决（继续冻结 or 接管收口），指挥官维持不代行。
- memory/bugs.md WIP +200 行属外来账检测面（check_foreign_ledger_entries 守卫在列）；
  脏树跑全量电池必红 = 冻结 WIP 投影，非回归。
- scripts/check_mcpcf_db_isolation.py 未跟踪 ⇒ 若 owner 决定收口，按仓库纪律
  同批给执行面（电池 case / expected / EXEMPT_RULES 三选一，或 `_` 前缀共享模块豁免）。

## 6. 来源

- git status / git diff --stat / git log --oneline -5（本轮实测）
- scripts/check_ns_write_gate_coverage.py --selftest 与实测输出（本轮实跑）
- scripts/check_tools_sync.py / scripts/check_instruction_budget.py（本轮独立复跑）
