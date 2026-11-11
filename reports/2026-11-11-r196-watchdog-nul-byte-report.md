# 轮 196 唤醒巡检报告（NUL-byte 专项）

- **时间**：2026-11-11 19:00
- **轮次**：r196（ExploreWatchdog）
- **前序**：r195（c8ccb79cf）

## 并发 WIP 状态

| 项 | 读数 |
|---|---|
| mtime（承重 3 文件） | `src/server/mcpcf_embed_bug583_wbtest.mbt` 14:29 / `scripts/run_guards.py` 14:33 / `memory/bugs.md` 14:35 |
| 冻结时长 | ~4.5h（14:35 → 19:00） |
| 新提交 | 无（r193 738831411 后零新提交） |
| 状态位 | 已知挂起，等 owner 裁决（按 r194 建议不重复上报） |

禁区遵守：WIP 文件未 touch。

## Round C 队列

确认过期（r195 已核实，本轮不重复）：
- BUG-527 摘 cc-link-flags：owner 否决（e0ef45c5e 回滚）
- BUG-530：已 FIXED（3699f012a）
- check_usage_tool_count：已注册（run_guards.py:175）

## 换面巡检：NUL-byte 专项

**目标**：扫描跟踪面源文件中的 NUL 字节（\x00），检测可能的二进制污染/坏补丁。

| 扫描面 | 方法 | 结果 |
|---|---|---|
| `src/**/*.mbt` | `find src/ -name '*.mbt' \| xargs grep -lP '\x00'` | **无匹配**（rc=123 = grep no-match） |
| `scripts/**/*.py` | `find scripts/ -name '*.py' \| xargs grep -lP '\x00'` | **无匹配**（rc=123 = grep no-match） |

**结论**：src/ 与 scripts/ 下无 NUL 字节污染。干净。

> 注：全仓扫描（含 .md/.json/.ps1/.sh）因文件量过大致 30s 超时，本轮只覆盖最关键的 src/ + scripts/ 两面。如需全仓面可后续补跑。

## 已探面汇总（避免重复）

| 轮 | 面 | 结果 |
|---|---|---|
| r25 | mcp_smoke | PASS（182 工具 T0r81） |
| r194 | OFM 端点 + byte-slice | 容忍诊断 / PASS |
| r195 | check_host_installable + byte budget | PASS / PASS |
| **r196** | **NUL-byte（src+scripts）** | **干净** |

## FIST 闭环

ns `iter-1111r196w`：publish → acl_grant → claim → execute → submit → verify 全链绿 ⇒ T0 已完成。

## 遗留

- WIP 挂起 ~4.5h，等 owner A~D 裁决（不重复上报）。
- 本地领先远端 128 commit（历史积压，推与否归 owner）。
- NUL-byte 全仓面（.md/.json/.ps1/.sh）未覆盖，量小可后续补。
