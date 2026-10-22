# 2026-10-14 工具计数自述漂移清零 + 锁定机制审计

## 结果摘要

**问题**：`check_tools_sync.py` 报 17 处自述漂移（4 处反幻影「缺少」+ 13 处精确值不符）。根因是文档写死精确工具数，工具一增一减就腐烂。

**修复**：判据新增下限式声明支持（`140+ 个 MCP 工具`），语义为「实测 ≥ 下限即过」，下限超过实测即虚报判红。13 处叙事面统一改下限式，2 处三元组哨兵面（`server.mbt:1` 头注释 + `README_EN.md:101`）保留精确值 148。

**效果**：17 → 0 违例。`check_tools_sync` / `check_doc_surface` / `check_plugin_sync`（cl7）三守卫全绿。

## 设计决策：为什么 140+ 不是 150+ 也不是 148

用户原话「写成 150+、160+ 等，不要明确」。但 **148 < 150**，写 150+ 是虚报——这正是 BUG-139/BUG-114 抓的那类病。本仓零容忍过报，所以下限选 140（148 ≥ 140 为真），而非用户举例的 150。

判据正则 `RE_TOOL_CLAIM` 新增 `\+?` 标记捕获，`surface_claims` 返回 `(num, is_floor, ln, snippet)`，`check_r3b_r7` 分流：
- 精确式 → `num != n` 判红（保留，不删，兼容现有文档）
- 下限式 → `n < num` 判红（虚报），`n >= num` 放行

反幻影「缺少工具总数」门同步改为接受一致的下限声明。新增 4 格 selftest（下限达标必绿 / 下限超实测必红 / 边界相等必绿 / 两种形状混存独立判）。selftest 从 8 格增至 12 格，全绿。

另外修正了一处假阳性：`RE_TOOL_CLAIM` 的 `\d+` 能吃「5.3」的小数尾（`docs/2026-10-12-fist-mbt-hexamind-design.md:120` 的章节号「5.3」被当工具数 3）。加 `(?<!\.)` 负向前视修复。

## CLI 帮助面补齐

`check_doc_surface` J14 顺带抓到 CLI 帮助面（`cmd/cli/help_topics.mbt`）的计数搬家：分组和=146 但真源=148，差 2 个工具。提取差异确认为 `ocr_scan` + `boundary_probe`（档3/档4 OCR 系列，已注册但未入帮助表）。补入 Ops-Log-Bug-Cost 组（22→24），总数 146→148。`ARCHITECTURE.md:93` 的「146 工具分组」同步改 148。

## 锁定机制审计发现（顺带看看）

`reports/2026-10-13-multilane-lock-mechanism-report.md`（860 行，并发 WIP）§4 已含 `[R25 勘误]`，核心结论：

1. **预订层**：`rsv_action`（`store_rsv.mbt:77-88`）是 RESERVATIONS 的单一真源——`None→(true,"reserved"); owner==agent→(true,"renewed"); ttl<now→(true,"taken_over"); else→(false,"conflict")`。预订层能拒（conflict 返回 false）。

2. **锁层**：`locks_upsert`（`store_rsv.mbt:176-191` + `store_sqlite.mbt:1058`）各持一份分叉谓词，谓词 `old.status=="active" && old.agent!=lock.agent && old.ttl_until>=lock.ts` 返回 `Unit`（丢弃裁决），`lock_acquire`（`server.mbt:4441`）恒回 success。锁层不能拒。

3. **语义对立**：`rsv_action` 的 `taken_over` = 旧锁**过期**（`ttl < now`，合法接管）；锁层的 `lock_taken_over` = 旧锁**仍活**（`ttl_until >= ts`，非法抢占）。两者语义相反，不可复用 `rsv_action`。

4. **漂移风险**：分叉谓词存于 memory + SQLite 两处，返回 Unit 丢弃裁决，`lock_acquire` 恒回 active。这是设计意图（allow+audit）而非纯 bug，但分叉谓词是真实的漂移雷。

**建议修复（未执行）**：提取独立共享谓词 `lock_verdict(prev, lock, now) -> (Bool, String)`，memory 与 SQLite 两处复用，`lock_acquire` 返回裁决。配套白盒锁。此修复不改变 allow-on-conflict 行为，只消除分叉。

## 阻塞项

**fist-mbt 自身迭代暂不可用**：`scripts/fist.py call publish` 触发 JS target 构建，但 `src/engine/probe_doctor_loop.mbt`（并发 WIP，未跟踪文件）有 10 个编译错误（[3001]/[4020]/[3800]/[4139]），构建失败。待该 WIP 收口后重试。

`moon check src/server` 的 10 个 error 全在 probe_doctor_loop.mbt，与本轮改动无关（本轮仅改注释行 152→148）。

## 遗留风险

1. **下限式判据的新边界**：下限 140 意味着工具数降至 139 以下才会触发判据。若未来大量删除工具，下限式可能掩盖问题。建议在工具数跌破 145 时人工复核下限是否仍合理。

2. **三元组哨兵面仍钉精确值**：`server.mbt:1` 和 `README_EN.md:101` 的三元组必须精确（判据硬哨兵）。每次加工具必须手动同步这两处，这是唯一仍会腐烂的面。

3. **CLI 帮助分组和**：`help_topics.mbt` 的分组计数是硬编码字符串，J14 只查总和。若只在组间移动工具而不改总数，总和不变但分组内数字不准。建议未来改判据逐组校验。

## 后续建议

1. 锁定机制的 `lock_verdict` 提取是独立 PR，建议单独开任务（已在 FIST 中拟发布，因构建阻塞未执行）。
2. CLI 帮助分组和改为从真源自动生成（`gen_plugins.py` 已能提取工具名，可顺带投影分组表），彻底消除手工分组计数。
3. 三元组哨兵面可考虑引入 floor 语义（如 `140+ tools`），但需同步改判据的 R7 三元组规则——这是下一步。

## 来源

- `scripts/check_tools_sync.py`：R3b/R7 判据实现 + 12 格 selftest
- `scripts/check_doc_surface.py`：J14 分组和 ↔ 真源对表
- `scripts/check_plugin_sync.py`：cl7 一源四态逐字节 diff
- `reports/2026-10-13-multilane-lock-mechanism-report.md` §4 `[R25 勘误]`：锁定机制审计
- `memory/bugs.md`：BUG-139（历史豁免）、BUG-136（CLI 帮助面计数搬家）
