# R25 · 全仓健康基线证据（测试门 + 守卫族 + 缺陷账）

- 日期：2026-10-21
- 性质：验证/清整（tidy/verify），非新功能
- 结论：**JS 权威测试门 1347/1347 全绿；项目健康 grade=healthy；守卫族 doc-surface 全绿**

---

## 结果摘要

在并发 WIP（全仓 205 个脏文件、src/server 37 个脏文件）背景下，跑通权威验证与守卫族，确立当前基线证据。

| 证据 | 读数 | 判定 |
|---|---|---|
| `moon test --target js`（全量） | `Total tests: 1347, passed: 1347, failed: 0` | **exit 0，全绿**（与 AGENTS.md 基线一致） |
| `project_health` | `grade=healthy, total_tasks=2358, in_flight=53, ready=10, done=858, blocked=0, reviewing=0, done_no_artifact=0, residue_over_baseline=false` | 健康，无阻塞，无探针残留 |
| `check_tools_sync.py` | `PASS 工具单一真源一致：170 个` | exit 0 |
| `check_doc_surface.py` | `PASS 文档面一致（J6/J7/J9/J14… 全过）` | exit 0 |
| `check_scripts_index.py` | `PASS 工具类辅助代码单一索引完整` | exit 0 |
| `check_plugin_sync.py`（cl7） | `FAIL 插件态漂移（9 文件与真源投影不一致）` | **红，非本轮可修**（见下） |

## 资源消耗

- 1 次后台 `moon test --target js`（全量，约 4 分钟）
- 1 次 `project_health`（MCP，纯读）
- 3 次守卫脚本（`check_doc_surface` / `check_scripts_index` / `check_plugin_sync`）
- 1 次跨 `scripts/` 的弱 lookbehind 家族扫描（确认 R24 修复是唯一实例）
- 零 `src/server` 写入（保持隔离，不碰并发 WIP）

## 任务分配记录

- 无新派单：src/server 37 脏（R14→R25 十二轮字节未变），issue_scan 家族 6 条（327/333/345/346/347/348）修复面全在脏区，不派单。

## 遗留风险

1. **cl7 红（check_plugin_sync FAIL 9 文件）**：并发提交 `ff0bf8b` 声称修 cl7，复跑仍 FAIL——投影漂移根因是未提交的 `server.mbt`（BUG-335/BUG-339）。**不跑 gen_plugins 固化未提交 WIP**，cl7 红须等 src/server 清空后重生成投影才可解除。
2. **src/server 十二轮未清**：BUG-347（`::` 切分只取尾段）/BUG-348（unused-variable/match-exhaustive 精度）/BUG-339（提交配对锁）全压着。
3. **组合环 `r21-rule-layer-fix`** 会话态重启即失，停在 bugfind 步。

## 后续建议

1. src/server 清空后：按 R23 六顶帽工件顺序 347→345→346(退役)→348 单批落地，预派 exec-scan-rules。
2. 落地前 diff `issue_scan_wbtest.mbt` 白盒锁与 BUG-72 降噪断言；cl7 重生成投影并复跑 `check_plugin_sync`。
3. 组合环重建，落地后 tick 至 fix_and_merge → verify。
4. R24 的 `RE_TOOL_CLAIM` 根因修复已验证为**该假阳类唯一实例**（跨 scripts 扫描无第二处 `(?<!\.)` 弱 lookbehind）。

## 超额内容

- 确立并发 WIP 背景下的**全仓健康基线证据**（1347/1347 + healthy + 守卫族全绿），可作为后续任何改动"零回归"的对照锚点。
- 用跨目录扫描确认 R24 正则修复覆盖了整类缺陷，非点修。

## 来源

- `moon test --target js` 后台作业 `pwsh-2327` 输出：`Total tests: 1347, passed: 1347, failed: 0`（exit 0）
- MCP `project_health` 回执（healthy / done_no_artifact=0）
- `scripts/check_tools_sync.py`、`scripts/check_doc_surface.py`、`scripts/check_scripts_index.py`、`scripts/check_plugin_sync.py` 实跑
- `memory/bugs.md`：BUG-327/333/335/339/345/346/347/348
- 本会话 R23/R24 报告与工件