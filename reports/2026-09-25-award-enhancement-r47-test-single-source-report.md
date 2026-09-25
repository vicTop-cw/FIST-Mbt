# 获奖提升 · R47 汇报：测试总数单一真源守卫

> 日期 2026-09-25 ｜ 字母轮号 R47（deliverable 功能轮第 43 行）｜ 主题：项目整洁 / 文档即实现 · 单一真源（延续）

## 结果摘要
补上"文档即实现"的最后一块盲区：既有 `check_badge.py` 只校验 README 徽章 vs 实测日志，但 AGENTS/deliverable/scoring_rubric 三处的测试总数漂移无人守卫。新增 `scripts/check_test_sync.py`，以 `moon test` 实测总数为唯一真源，跨 README/AGENTS/deliverable/scoring_rubric 校验 "N/N""N 全绿""独立 N" 任一表述一致；接入 ci.yml JS 轨。测试/工具计数不变（233/83）。

## 资源消耗
- 新文件：`scripts/check_test_sync.py`；改动：`.github/workflows/ci.yml`（JS 轨加 Test-count guard）、`docs/deliverable.md`（43 行）、`memory/2026-09-25.md`。
- 时间：单轮轻量闭环。

## 任务分配记录
- 主会话直改 + 正/负路径实测（`--total 233` PASS；`--total 999` FAIL 退出 1，四文档全缺，证明守卫对漂移敏感）。

## 遗留风险
- 守卫对"独立 N 出现即算命中"较宽松（只要文档出现实测数字即可）；若未来某文档在非测试语境错误复用该数字会漏判，但当前语义下足够且与 check_tools_sync 互补。
- 仅接入 ubuntu JS 轨（与 badge 守卫一致）；Windows 轨未加（其测试 step 未落日志文件，如需可后续 `Tee-Object` 落盘再校）。

## 后续建议
- 三守卫（徽章/工具/测试数）已构成"文档即实现"闭环；若再加，可考虑把三个脚本合并成一个 `check_doc_sync.py` 减少入口，但保持单职责亦可。
- 大项：`watchdog_tick` 无人值守接 `selfdrive_dispatch`（中改、跨包耦合）仍为可选下一目标。

## 超额内容
- 负路径测试证明守卫能正确 FAIL 而非永远 PASS，具备真实门禁价值。

## 来源
- `python scripts/check_test_sync.py --total 233` PASS；`--total 999` FAIL 退出 1；`moon test` 233/233。

*（内容由AI生成，仅供参考）*