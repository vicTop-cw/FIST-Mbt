# 报告：R5 组合模式（全量验证 + 自动路由实测 + 剩余守卫判绿）

## 结果摘要
- **全量验证**：`moon test --target js` = **Total tests 1346, passed 1346, failed 0**（连跑两次一致）—— 与文档基线 1346 完全持平，并发 agent 活跃 WIP 下零回归。
- **澄清 R3 两条「红」实为调用姿势**：`check_badge` / `check_test_sync` 需喂全量测试日志（之前喂的是部分包 217）。喂全量日志后两者 **PASS** ⇒ 非产品红，CI JS 轨守卫族现已全绿。
- **自动路由功能面实测**：`executor_route need=编排,json` 正常返回 17 个已注册执行者、best=`polish-lead`（trust=1）；`task_triage` 当前 default ns 0 条就绪（无积压）。

## 证据
- `moon test --target js` 两次均 1346/1346、failed 0、exit 0。
- `python scripts/check_badge.py temp/moon_test_r5full.log README.md` → **PASS 徽章一致：README tests-1346%2F1346 == 实测 1346/1346**；自检注释一致（rc=0）。
- `python scripts/check_test_sync.py temp/moon_test_r5full.log` → **PASS 测试总数单一真源一致：实测 1346；扫描现状面 127 份文档，16 条声明全部等于实测；must-carry 5 份齐全；豁免 25 条全部有效**（rc=0）。
- 本轮守卫累计绿：check_doc_surface / check_scripts_index / check_ps_encoding / check_py_stdout_encoding / check_pkg_imports / check_mbti_sync / check_store_tables_wired / check_desc_enum_sync / check_entry_paths / check_plugin_sync / check_badge / check_test_sync。

## 变更内容
- 仅新增临时测试日志 `temp/moon_test_r5.log` / `temp/moon_test_r5full.log`（gitignore 区，非交付物）；无源码/文档改动。

## 并发协调
- 本轮仅只读验证 + 只读路由查询，无写入，未触碰他方 WIP。

## 遗留风险
- `task_triage` default ns 无就绪任务 ⇒ 自驱派单暂无候选；如需压测自动路由可显式 `publish` 后再 `selfdrive_dispatch`。
- 账本待修 15 条仍以子项目域为主（fist-mbt-scope 仅 BUG-327 / BUG-333）；BUG-327 剩余部分阻塞于并发 agent 的 `src/server/server.mbt`。

## 来源
- `moon test --target js` 实跑、`scripts/check_badge.py`、`scripts/check_test_sync.py`、`executor_route` / `task_triage` MCP 工具。