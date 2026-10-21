# R77 报告 — BUG-373 出路② 批2：测试标题面错号收口（192→194 / 189→172）

- 日期：2026-10-21
- 分支：`slave/docs/bug373-title-refs-r77`（叠 `slave/fix/issue-scan-min-severity-r71`；与 r76 零文件重叠，可并行合并）
- 基点：r71（320b1c5）；开工前 fetch gitcode/master 确认未前进（仍 259b56a）

## 1. 结果摘要

BUG-373 ②⑥ 点名的「测试标题批」按取证收口，7 处改号、4 文件、零行为变化：

| 文件:行 | 原引 | 改为 | 依据 |
|---|---|---|---|
| src/server/get_int_wbtest.mbt:1 | BUG-192 | BUG-194 | 真身 BUG-194（get_int 对超 Int32 域饱和，账本 L3702，summary 逐句吻合） |
| src/server/get_int_wbtest.mbt:15（测试标题） | BUG-192 | BUG-194 | 同上 |
| src/server/get_int_wbtest.mbt:31（测试标题） | BUG-192 | BUG-194 | 同上 |
| src/server/server.mbt:532（注释） | BUG-192 | BUG-194 | 同上；BUG-26 饱和实测出处保留；:3026 同义注释本就引 BUG-194 |
| src/decompose/decompose.mbt:83（注释） | BUG-189 | BUG-172 | 真身 BUG-172（difficulty_label split_n=4 难档不可达，L3404；一号三义之第三义归还） |
| src/decompose/probe_difficulty_wbtest.mbt:2（标题） | BUG-189 | BUG-172 | 同上；BUG-172 的 FIXED 小记正好点名本 wbtest 两条回归 |
| src/decompose/probe_difficulty_wbtest.mbt:27（标题） | BUG-189 | BUG-172 | 同上 |

**不改的**：router 一族 4 处 BUG-192（router_config.mbt:168/251、router_config_wbtest.mbt:146、router_state.mbt:41）——BUG-192 真身就是 router_config 的 `.to_int()` 无上界，这些引用是对的（BUG-373 ④ 已裁定 router_state 那条为反向对照）。

## 2. 资源消耗

单代理执行；取证（真身定位 + 全仓 BUG-192 引用面分类）+ 全量 moon test 1 轮。无返工。

## 3. 任务分配记录

指挥官（本会话）亲自完成取证、改号、验证、收尾。无子任务分发。

## 4. 遗留风险

- 本分支基于 r71，判据 J1 维持基线 9 条悬空（engine.mbt:231 BUG-147 等）——由 **r76 分支**收口；两分支合并后 J1=0（r76 棘轮已降到 0）。预存红成因：基点选择（一单一分支、r76/r77 零重叠并行）。
- `check_scripts_index` rc=1（三条登记在 r73 分支）——基点预存红，合 r73 自愈。
- 测试标题改号会改 `moon test` 输出面：本轮实测无 snapshot 失配（1351/1351 一次全绿）；若下游有依赖测试名字符串的判据需在合并后复跑（test_sync 已复跑 PASS）。

## 5. 后续建议

- BUG-373 出路② 至此注释面（r76）+ 标题面（r77）双批收口；剩 S1 字面量悬空（合成语料）与 S2 疑似无归属（192→本轮读数下降）仍按「先有执行面再谈门禁」只报不判。
- 账本世系分叉（BUG-328 双义、374~385 未回 master）仍待 owner 裁决（见 r76 报告 §4）。

## 6. 超额内容

无计划外改动。

## 7. 来源

- BUG-373（出路①②③立案，①③ 点名本单两个错号）、BUG-194、BUG-172、BUG-189（symbolic.mbt DPLL，真主）、BUG-192（router_config，真主）
- 判据：`scripts/check_bug_reference_integrity.py`（J1 基线对表）

## 验证读数（金条八）

- `moon test --target js` = **Total tests: 1351, passed: 1351, failed: 0**
- moonfmt 四个触碰文件输出逐字一致
- `check_test_sync.py temp/r77_test.log` PASS（1351；131 份文档 19 条声明全等）
- `check_bug_reference_integrity.py`：J1 = 9（= r71 基线，零新增；改号目标 BUG-194/BUG-172 均有抬头）
- `moon fmt` 本机 rc=127（ICE，已知），moonfmt 逐文件对照替代
