# R27 · 守卫族全绿权威锚点（11/11）+ BUG-339 复核

- 日期：2026-10-21
- 性质：验证/清整（verify/tidy）
- 结论：**文档化守卫族 11/11 全绿（首次）**；BUG-339 经复核**仍未解除**（我的 R26 gitignore 未动提交配对）

---

## 守卫族全绿（11/11，2026-10-21 09:45 实测）

一次性跑全 AGENTS.md「守卫族」列出的判据，**无一红**：

| # | 守卫 | 覆盖 |
|---|---|---|
| 1 | check_tools_sync | 工具单一真源一致（170） |
| 2 | check_plugin_sync（cl7） | 插件态一致：4 宿主 / 64 生成文件 / 170 工具 / v0.3.9 |
| 3 | check_doc_surface | 文档面一致（J6–J15 全过） |
| 4 | check_scripts_index | 工具类辅助代码单一索引完整 |
| 5 | check_store_tables_wired | 库表接线（26 表） |
| 6 | check_publish_payload | 发布载荷面干净（1131 件、未跟踪泄露 0） |
| 7 | check_demo_isolation | spawn 面隔离（34 脚本） |
| 8 | check_ps_encoding | .ps1 BOM/ASCII |
| 9 | check_entry_paths | 入口清单（224 份扫描面） |
| 10 | check_release_asset_names | 分发面同源（R1–R14） |
| 11 | check_template_ctrl | 模板无裸控制字符 |

**PASS=11 / RED=0 / SKIP=0。**

这是文档化守卫族**首次全绿**——此前 cl7（check_plugin_sync）与 check_publish_payload 长期红。两个红已分别由并发提交 `80bfd48`（重生成投影）与我的 `a15ab01`（堵 P1 泄露）解除。

## 权威测试门（R27 新鲜重跑）

`moon test --target js` 后台全量，汇总行：

```
Total tests: 1347, passed: 1347, failed: 0.
[status: completed, exit code: 0]
```

与 R25 基线一致，**守卫族全绿 + 测试门全绿**构成强零回归锚点。

## 资源消耗

- 1 次后台 `moon test --target js`（全量）
- 1 次守卫族 11 判据批量扫描
- 1 次 BUG-339 复核（git ls-files + git show HEAD:server.mbt）

## 任务分配记录

- 无新派单。src/server 36 脏（R14→R27 十四轮），issue_scan 家族 6 条修复面全在脏区。

## BUG-339 复核（重要纠偏）

R26 我把 `src/server/bug335_ns_route_wbtest.mbt` 加进 `.gitignore`（随包公开面 7 条点名之一）。**但 gitignore 不等于提交**，本轮复核：

- `git ls-files src/server/bug335_ns_route_wbtest.mbt` → **tracked=0**（仍未跟踪）
- `git show HEAD:src/server/server.mbt | grep publish_parallel_route` → **0 命中**（HEAD 不含 BUG-335 三函数）
- `src/server/server.mbt` → 仍 ` M`（未提交）

⇒ **BUG-339（commit 成对性）未解除**。我的 R26 修复只堵了 publish 泄露面（把地雷文件挡在发布包外），不替代 BUG-335 三函数 + 锁文件的成对提交。此项须等持有方处理，我不代提交。

## 遗留风险

1. **BUG-339 仍 OPEN**：BUG-335 三函数 + `bug335_ns_route_wbtest.mbt` 未成对提交 ⇒ HEAD 不含修复，单独提交锁会引入 src/server 编译红（Error 4021 unbound ×6）。
2. **issue_scan 家族 6 条 OPEN**（327/333/345/346/347/348）：全在脏的 `issue_scan.mbt`，等 src/server 清空 + R23 裁决授权后按 347→345→346→348 落地。
3. **BUG-341**（src/parser/stmt.rs 元组嵌套解构）：便利性缺口，越界。
4. 组合环 `r21-rule-layer-fix` 会话态重启即失。

## 后续建议

1. src/server 清空后：按 R23 六顶帽工件单批落地，预派 exec-scan-rules；cl7 已绿，落地后复跑 `check_plugin_sync` 确认投影未漂。
2. BUG-339 成对提交须在同一 commit（server.mbt + bug335 锁），避免单独提交锁引入编译红。
3. 守卫族 11/11 全绿可作后续任何改动的**零回归锚点**。

## 超额内容

- 纠偏 R26 的一个易误读点：`.gitignore` 点名 ≠ 提交，BUG-339 的成对提交门仍未过。
- 首次把文档化守卫族全绿状态钉成单份可复跑清单（上文表格），可直接喂 `output_validate` 当验收门禁。

## 来源

- `scripts/check_*.py` 11 个判据实跑（2026-10-21 09:45）
- `git ls-files` / `git show HEAD:src/server/server.mbt` / `git status --porcelain -- src/server`
- `memory/bugs.md`：BUG-339 / BUG-340（FALSE_POSITIVE）/ BUG-341
- 本会话 R22/R24/R25/R26 提交：`c7934f3` / `b4665e2` / `fea6839` / `a15ab01`