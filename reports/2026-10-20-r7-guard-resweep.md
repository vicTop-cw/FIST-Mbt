# 报告：R7 组合模式（并发 churn 后守卫族复扫 + BUG-333 落点定性）

## 结果摘要
- **并发 churn 后守卫族复扫：12 个守卫全部 PASS**，无新引入的红 —— 并发 agent 活跃改写 `src/server` 期间，工具数（170）/版本（0.3.9）/入口路径/`.mbti`/schema 接线/插件态/文档面/编码闸全部一致，CI 主面稳定。
- **BUG-333 落点定性（本轮新增判据）**：`issue_scan` 的 `rules_file` 同名覆盖**只支持 severity 覆盖**（`scan_load_external_rules` 仅读 `severity`），**无 `enabled`/抑制位** ⇒ 无法在调用侧不产 `match-exhaustive` 等噪音项。故 BUG-333 的「默认降噪」（match-exhaustive 不产 + 高噪音项 info-only）**必须在 `src/server/issue_scan.mbt` 内实现**，而该文件属并发 agent WIP（`src/server` 36 行 dirty）——本回合不代改。
- **BUG-327 复核**：账本追记确认部分 1（双假绿分支 fail-closed）已落地，部分 2（`require_ocr` 接线）仍阻塞于 `src/server/server.mbt` WIP，保持 OPEN 合理。

## 证据
- 守卫复扫回执：check_plugin_sync（4 宿主/64 文件/170 工具/v0.3.9）、check_scripts_index、check_store_tables_wired（26 表=25 写点+1 预留）、check_ps_encoding（9 个 .ps1）、check_desc_enum_sync、check_doc_surface（J6~J15 全对表）、check_entry_paths（R1 0 处/R2 0 个，扫描面 220 份）、check_pkg_imports（26 份 moon.pkg 34 条 import）、check_mbti_sync（24 份 .mbti 656 条 pub）、check_py_stdout_encoding --all（应带闸 82/已带 82）—— 全部 rc=0。
- 中途 3 个 rc=2 为调用方多传空尾参（`unrecognized arguments`），无参重跑即 PASS，非产品红。

## 变更内容
- 无源码/文档写入（本轮纯只读审计 + 判据定性）。

## 并发协调
- 仅只读；未触碰他方 WIP，未代改 3 个未跟踪 cron 临时件（仍指退役入口，留观察）。

## 遗留风险
- **BUG-333**（medium OPEN）：降噪必须在 `src/server/issue_scan.mbt` 内做（加 `match-exhaustive` 抑制位 / 默认 info），等待并发 WIP 收敛。
- **BUG-327 部分 2**（medium OPEN）：`require_ocr` 接线到 `.mbt` 非可审查性，阻塞于 `src/server/server.mbt`。
- 3 个未跟踪 cron 临时件仍指退役入口 `cmd\main\main.js`；守卫按设计豁免。

## 来源
- `scripts/check_*.py` 守卫族实跑回执、`src/server/issue_scan.mbt`（rules_file severity 覆盖实现，:1747）、`memory/bugs.md` BUG-327/BUG-333 条目。