# 报告：R2 组合模式（验证 + 清整，守卫族体检）

## 结果摘要
- 用 fist-mbt MCP 工具驱动（`reserve_scope` / `reserve_check` / `reserve_release` / `bug_fix` / `issue_scan`）。
- **销账 BUG-342 + BUG-343**（各 1 heading，共 2）：并发 agent 引入的回归经实测已收敛。
- **守卫族体检抓到并修掉 1 处 CI 真红**：`check_scripts_index` FAIL —— 并发 agent 新加 `scripts/commit_bug335_lock.ps1` 未登记进 `scripts/README.md`（R62 索引漂移）。
- `issue_scan dir=src/executor`：无新可修 bug（全启发式噪音）。

## 证据
- `moon test --target js -p src/ops` = **Total tests 217, passed 217, failed 0**（含 ops_heal_wbtest 的 BUG-240 文本锁 + rhop 锁）。
- `moon test --target js -p src/engine` = **Total tests 174, passed 174, failed 0**。
- `ops_heal_wbtest.mbt` 现在同时计数 `delete_failed_ids?`（count_q）与 `delete_failed_ids~`（count_t）—— BUG-342 方案 B 已落地；`engine_dag_ext.mbt` 已不再出现 `ids~`/`ids?`。
- 守卫体检（修复前后）：`check_scripts_index` FAIL→**PASS（rc=0）**；`check_doc_surface` rc=0、`check_ps_encoding` rc=0、`check_desc_enum_sync` rc=0、`check_pkg_imports` rc=0、`check_py_stdout_encoding --all` PASS（R1 成果保持）。

## 变更内容
- `scripts/README.md`：在 `native-env.ps1` 条目后新增 `commit_bug335_lock.ps1` 登记条目（说明其 BUG-339 commit-pairing 职责、`git commit --only` 单文件守规、幂等、`-SkipTest` 边界、纯 ASCII BUG-88 要求）。未改其他。

## 并发协调
- `scripts/README.md` 首次 `reserve_scope` 返回 conflict，但 `reserve_check` 显示持有者即 `host-sensenova-r1`（本人先前已持有，自冲突）→ 直接编辑；编辑后 `reserve_release`。
- 其余守卫只读，无写入。

## 遗留风险
- BUG-342 源码仍保留 `~`（borrow）写法且在本机钉版 moon 0.1.20261016 下编译通过；若后续 moon 升级语义分歧，按方案 A（回退 `?`）处理——已在 FIXED 小记注明为观察项。
- BUG-343 依赖 `rn_clean` tear-down 清场，若并发 agent 的 commissar 继续往同 `temp/` 目录写 `.rhop` 可能复现，留意复跑。
- `scripts/ns_route_probe.py` 实跑 `OSError [Errno 22]`（多租户探针域，R1 已记）。

## 后续建议
- 下一轮候选：BUG-327（剩余部分：`require_ocr` 门禁接线到 `.mbt` 非可审查性，阻塞在 src/server/server.mbt）、BUG-333（issue_scan 降噪）。
- 建议并发 agent 侧：新增 `scripts/*.py|*.ps1` 后立即在 `scripts/README.md` 登记，避免 R62 守卫持续红。

## 来源
- 账本 `memory/bugs.md`：`### FIXED(2026-10-20T12:05:04Z / BUG-342, BUG-343)`。
- 判据 `scripts/check_scripts_index.py`（R62）、`moon test --target js`。