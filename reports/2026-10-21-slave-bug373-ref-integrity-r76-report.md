# R76 报告 — BUG-373 出路② 收口：注释面悬空引用归零 + 主机账本补账 + 棘轮降档

- 日期：2026-10-21
- 分支：`slave/docs/bug373-ref-integrity-r76`（叠在 `slave/fix/issue-scan-min-severity-r71` 之上，一单一分支）
- 基点：r71（320b1c5）；开工前已 fetch gitcode/master 确认未前进（仍 259b56a）

## 1. 结果摘要

BUG-373 出路②（注释面引用改正）按取证结果收口为三件事：

1. **BUG-147 是真错号**：`src/engine/engine.mbt:231` 注释「预执行审计门禁必须真正前置（BUG-147）」——全远端（gitcode 全部分支）账本均无 BUG-147 抬头；语义逐句核对真身 = **BUG-176**（execute_with_meta 先写元数据后执行 → 幽灵记录，L3476 起账本原文吻合「空 deliverable 被 audit gate 拒绝时 executions 已写入一行幽灵元数据，cost_stats double-count」）。已改注 BUG-147→BUG-176。
2. **BUG-327×7 / BUG-336×1 不是错号，是账本滞后**：两号抬头在主机分支账本逐字在案（`gitcode/slave/fix/bugfind-ocr-gate-honesty` 等 20+ 分支；BUG-336 四分支逐字一致，BUG-327 有新旧两版、取含「部分2 收口 FIXED 小记」的最新版）。已把两条条目（含 `### FIXED` 小记）**verbatim** 搬入 master 账本时间序位置（BUG-327 插在 BUG-328 前、BUG-336 插在 BUG-342 前，升序保持；39 行纯新增，工作树 CRLF 保持）。
3. **判据棘轮降档**：`check_bug_reference_integrity.py` 的 `DANGLING_COMMENT_CEILING` 1→0；docstring 与 `scripts/README.md` 两处登记同步（R48 立案口径 → R76 改判收口口径）。判据的 selftest 标定格（悬空数==上限常数）自动对表通过。

最终读数：**J1 悬空-注释面 0 条（上限 0）/ 实跑 rc=0 / --selftest 10 格 PASS**。

## 2. 资源消耗

- 单代理执行；主要耗时在远端取证（全分支账本扫描 ×3 轮）与全量 `moon test`（2 轮，其一为产 test_sync 日志）。
- 中途返工一次：gen_plugins FATAL 抓到首版块提取误边界（BUG-336 detail 内嵌 `## 现象`/`## 根因` markdown 小标题被当作条目边界，截掉了 `### FIXED` 小记）→ 还原账本、改用 `^## BUG-\d+` 唯一边界重插。生成器的账本自证门当场接住了一次会进库的坏补账，值得记一笔。

## 3. 任务分配记录

指挥官（本会话）亲自完成：取证、改注、补账、棘轮降档、验证、收尾。无子任务分发（单点修改 + 高取证密度，拆分无收益）。

## 4. 遗留风险

- **账本世系分叉（owner 裁决项，最重要）**：master+副机线与主机分支线对**同号 BUG-328 已双义**——master 的 BUG-328 = moonc 0.10.16 `Result::is_ok/is_err` 迁移（副机线 2026-10-20），主机线的 BUG-328 = check_demo_isolation NEEDLE_RE 第 5 形状（2026-10-19）。且主机线 BUG-374~385 条目（任务 #37-#51 对应）全部未回 master。两条世系合并前必须统一裁决（哪条重编号），否则 gen_plugins 编号唯一门与 bugs.md 文本冲突会双爆。本单只搬了判据 docstring 期望基线内的 327/336 两条（master 无同号占用、无冲突），未代同步 374~385。
- **check_scripts_index rc=1（r71 基点预存红）**：缺 check_doc_surface.py / commit_bug335_lock.ps1 / slave-branch-merge.ps1 三条登记——r73 分支已补齐，本基点不带；合并 r73 后自愈。
- S2 疑似无归属 202 处 / S1 字面量悬空 35 处仍只报不判（BUG-373 出路①的既定次序）。

## 5. 后续建议

- owner 裁决账本世系统一方案后再合并主机分支批量账本条目（374~385）。
- 判据 J1 已归零且棘轮到 0：后续任何注释面新引用必须先入账再引用（判据会当场红）。
- 出路②的测试标题批（server.mbt:2827/2933 若涉及字符串面）随下次 `moon test --update` 同批处理。

## 6. 超额内容

- 无计划外功能。远端全分支账本扫描与 BUG-328 双义发现属取证衍生，已转为遗留风险上报。

## 7. 来源

- 判据：`scripts/check_bug_reference_integrity.py`（BUG-373 出路①，R48）
- 账本：BUG-373（出路①②③立案）、BUG-165/248（OCR 假绿族）、BUG-176（幽灵元数据）、BUG-327/BUG-336（主机分支 verbatim 补账）
- 代码：`src/engine/engine.mbt:231`（改注）；`scripts/check_bug_reference_integrity.py`（棘轮+docstring）；`scripts/README.md`（两处登记同步）；插件投影面 14 文件（gen_plugins 重跑：BUG-1~373 共 358 条入账）

## 验证读数（金条八）

- `moon test --target js` = **Total tests: 1351, passed: 1351, failed: 0**（零新增测试，零回归）
- moonfmt `src/engine/engine.mbt` 输出与现文件逐字一致
- `check_bug_reference_integrity.py --selftest` 10 格 PASS；实跑 J1=0/rc=0
- `check_test_sync.py temp/r76/test.log` PASS（1351；131 份文档 19 条声明全等）
- `check_plugin_sync.py` rc=0（cl7 逐字节一致）；`check_doc_surface.py` rc=0
- `moon fmt` 本机 rc=127（ICE，已知），以 moonfmt 逐文件对照替代（AGENTS 允许的替代口径）
