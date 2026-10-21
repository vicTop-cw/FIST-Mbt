# R80 报告 · slave/docs/bug373-ref-integrity-r80 — J1 悬空收口搬运到新 master 基点

## 1. 结果摘要

把 r76 的「BUG-373 出路② J1 悬空收口」整套搬到 r79 基点（新 master 9299611 线首个可编译树），并在搬运过程中发现主机账本重写丢的条目比 r76 修的更多，一并 verbatim 补账至 **J1 = 0**。

改动面（7 个文件组）：

| 面 | 内容 |
|---|---|
| `scripts/check_bug_reference_integrity.py` | 整文件取 r76 blob：`DANGLING_COMMENT_CEILING = 0` + R76 收口 docstring |
| `src/engine/engine.mbt:231` | `（BUG-147）`→`（BUG-176）`（错号改判，r76 同款） |
| `memory/bugs.md` | **纯插入 +104 行**，verbatim 补账 5 条：BUG-327 / BUG-336（r76 blob）、BUG-384 / BUG-385（commit 606dd33，385 尾带合并 `### FIXED(… / BUG-384, BUG-385)` 小记）、**BUG-333**（39d251a blob，新发现——主机重写账本 33x 段只剩 330/336，issue_scan 4 条注释悬空） |
| `scripts/README.md` | 两条 bugref 条目同步 r76 版（ceiling 0 + 收口段） |
| `gen_plugins.py` 重投影 | 361 条入账（21 待修/321 已修/10 重复/9 误报），四宿主 9 生成文件同步 |
| `memory/2026-10-21.md` | R80 小节 |

## 2. 资源消耗

会话内约 35 分钟（含 EOL 伪影两轮诊断）；1 次 `moon test --target js` 全量（1347/1347）；守卫电池 7 把尺各 1 发。

## 3. 任务分配记录

副机单干（R 系列收尾单，无子任务拆分）；账本块来源：r76 blob（slave/docs/bug373-ref-integrity-r76）、606dd33（主机 BUG-384/385 原始落账）、39d251a（BUG-333 原始落账）。

## 4. 遗留风险

- **`check_scripts_index` rc=1（预存红，master 自带，本单不代修）**：主机 454aea3 落的 `scripts/fist-gate.py`（统一门链 merge_markers/fmt/build/ps_encoding/store_path）未在 scripts/README.md 登记。属 docs/tasks/ TASK-003/004 施工面，主机正在办，不抢。
- 主机账本重写（9299611）丢失的条目可能不止这 5 条——本次只补了「有代码注释/测试标题引用」的悬空面（bugref J1 判据能看见的）；**没有被引用的静默丢失条目无法用这把尺发现**，建议 owner 对 259b56a 旧账本与 9299611 新账本做一次全量抬头 diff。
- 合序建议：**r79（可编译）→ r80（本单）**；r76 分支可弃——其面被 r80 完全覆盖且更全（多补 BUG-333/384/385）。

## 5. 后续建议

- docs/tasks/ 五单（风语者）按 TASK-001(P0)→005/002(P1)→003(P2)→004(P3) 顺序开工，均从最新 master 开新分支。
- TASK-002「rhop_poll.mbt 是 poison」持有反证（master 无 rhop_native.mbt，现状是缺定义而非重复定义，r79 已补）——执行前需与 owner 对表。

## 6. 超额内容

- BUG-333 补账（超出 r76 搬运范围）：全量跑 bugref 时标定格现读 4 条，追因发现主机账本重写连 33x 段也丢了。
- EOL 工艺固化：ledger 追加改为「HEAD blob + LF 空间插入 + 纯 LF 写盘」一次成型，diff +104 纯插入，消除了上单 6099+/6028- 的整文件重写伪影。

## 7. 来源

- 验证读数：`moon test --target js` = Total tests: 1347, passed: 1347, failed: 0（temp/r80_test.log）；bugref `--selftest` 10 格 PASS / 全量 rc=0 / J1=0（宇宙 303 份 .mbt / 账本 361 编号 / 引用点 1008）；check_merge_markers（blackbox 路径）rc=0 / 1228 文件；check_plugin_sync rc=0 / 4 宿主 64 生成文件 / 170 工具 / v0.3.9；check_doc_surface rc=0（J1~J15）；check_test_sync rc=0（19 条声明==1347）；check_badge rc=0。
- 账本块原件：`git show 39d251a:memory/bugs.md`（BUG-333）、`git show 606dd33:memory/bugs.md`（BUG-384/385 + 合并 FIXED 小记）、`slave/docs/bug373-ref-integrity-r76` blob（327/336）。
