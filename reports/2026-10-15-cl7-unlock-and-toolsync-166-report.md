# Round 121 报告 · 发布版缺 18 工具 + cl7 解锁 + 插件态重生成

- **日期**：2026-10-15
- **任务**：接 Round 120（发布版校验 + BUG-163 上报），继续把发现落地：确认 BUG-155、解锁 cl7 硬门
- **HEAD 基线**：`b8c24b5`（本轮插件重生成提交）

## 结果摘要

| 项 | 结果 |
|---|---|
| **BUG-155 坐实** | 发布版 `fist help` 报 **148 tools**，真源 `server.mbt:1` 明写「166 tools」，`gen_plugins.py` 回执 166 ⇒ **dist 旧快照，发布版缺 18 工具** |
| **cl7 解锁** | `check_plugin_sync` FAIL → **PASS**（4 宿主 / 64 生成文件 / 166 工具 / v0.3.8） |
| **BUG-161 账本纠错** | 抬头 FIXED 与 小记「留在 OPEN」矛盾 ⇒ `bug_mark_status` 纠回 OPEN |
| **插件重生成** | `gen_plugins.py` rc=0，9 个插件文件对齐 166 工具，已提交 `b8c24b5` |
| **moon test** | ⚠ **1054/1060**，6 条失败全在并发 agent 的 `src/server/issue_scan_*.mbt` WIP（BUG-156 收紧规则未同步测试） |
| **守卫族** | tools_sync / test_sync / badge / template_ctrl / doc_surface / plugin_sync **全 PASS** |

## 核心发现

### 1. BUG-155 坐实：发布版缺 18 工具

- 发布版 `fist version` → `v0.3.8`（可用）。
- 发布版 `fist help` → `(148 MCP tools)`。
- 真源 `src/server/server.mbt:1` →「暴露 166 tools + 3 resources + 2 prompts」。
- `gen_plugins.py` 回执 →「166 工具 / v0.3.8」。
- 发布版 sha256 与 dist 一致（`C6FFF717...`）⇒ **发布版 == dist，dist 是旧快照**。src 已前进到 166 工具，但 dist 未 rebuild，仍停 148。
- **结论**：用户装的发布版功能可用，但缺 18 个 src 最新工具。修法（交 owner）：等并发 agent 收口后 `moon build --target js` 更新 `dist/fist-mbt.js`；或按 BUG-155 原建议 `git rm --cached dist/fist-mbt.js dist/patch_esm_main.py` 交付 Release 流水线接管。

### 2. cl7 解锁根因：BUG-161 账本自相矛盾

- `gen_plugins.py --check` 先报 **exit 2 FATAL**：「1 条标 FIXED 却无小记点名：BUG-161」。
- 根因：BUG-161 抬头 `FIXED`，但 `### FIXED(2026-10-15 修复模式 / BUG-155...BUG-160)` 小记**明说「BUG-161 留在 OPEN」**（协议问题未修）。抬头与叙述矛盾。
- 修：`bug_mark_status` BUG-161 → OPEN（`from_status=FIXED`），抬头与叙述对齐，FATAL 消。

### 3. 真·插件漂移 → gen_plugins.py 重生成

- FATAL 消后剩 **exit 1 FAIL**：9 个文件与真源投影不一致。
- 原因：真源变了（工具 148→166、README 1058、账本 161 条）但插件未重生成。
- 这 9 个文件 git 状态全 clean（非并发 WIP）⇒ 安全重生成。
- `python scripts/gen_plugins.py` rc=0，`check_plugin_sync` 复跑 **PASS**。

### 4. 6 条测试瞬态红（并发 agent 的 BUG-156 WIP）

- `moon test --target js` = 1054/1060，6 条失败：
  - `issue_scan_test.mbt:30` lint_1_scan_hits_high_risk
  - `issue_scan_test.mbt:131` lint_5_comment_lines_are_not_matched_bug15
  - `issue_scan_test.mbt:219` lint_8_guard_filter_keeps_real_hits_drops_guarded
  - `issue_scan_test.mbt:300` lint_9_substring_guard_filter
  - `issue_scan_secs_overflow_test.mbt:6` secs-overflow 规则存在且可统计
  - `issue_scan_wbtest.mbt:54` scan_match_lines_整行注释与字面量两道降噪同时生效
- 全在 `src/server/issue_scan*.mbt`（并发 agent WIP，未提交）。BUG-156 收紧 `map-set-no-rebind` 规则未同步测试。
- **非我引起**：本轮未触碰任何 src 文件。我提交的 plugins/ 与守卫族不受影响。

## 资源消耗

- `moon test --target js` × 2（一发全绿复验 + 一发抓 6 条红定位）
- `python scripts/gen_plugins.py` × 1（重生成插件）
- `python scripts/check_plugin_sync.py` × 3（解锁前/后/复验）
- `bug_mark_status` BUG-161 → OPEN × 1
- 守卫族 × 6

## 任务分配记录

| 子任务 | 执行者 | 结果 |
|---|---|---|
| 发布版 CLI 实测（version/help） | 我 | ✅ v0.3.8 / 148 tools |
| BUG-155 坐实（真源 166 vs 发布版 148） | 我 | ✅ 差 18 工具 |
| BUG-161 账本纠错 → OPEN | 我 | ✅ 抬头与叙述对齐 |
| gen_plugins.py 重生成 | 我 | ✅ rc=0，9 文件 |
| cl7 复跑 | 我 | ✅ PASS |
| 守卫族复跑 | 我 | ✅ 6/6 PASS |
| issue_scan 6 条红定位 | 我 | ✅ 全在并发 WIP |

## 遗留风险

1. **moon test 1054/1060**：6 条红在并发 agent 的 issue_scan WIP，等其收口自愈。
2. **BUG-155**：dist 旧快照，发布版缺 18 工具。需 owner 决策 rebuild 或 `git rm --cached dist/`。
3. **BUG-161 / BUG-163 同根**：协议版本 `2026-07-28` 激进。修复在并发 agent 的 `stdio_js.mbt` 区，仍待收口。
4. **README 测试数**：本轮实测 1060（+2 来自并发 agent），文档仍写 1058。等并发 agent 收口后再同步。
5. **BUG-163 建议并入 BUG-161**（同根）避免双记账；bugs.md 是并发 WIP，等其收口再动。

## 后续建议

1. **提醒并发 agent**：issue_scan 收紧规则时要同步 `issue_scan_*.mbt` 测试，否则瞬态红会混进他人读数。
2. **owner 拍板 BUG-155**：rebuild dist vs 交付 Release 流水线接管。若走 Release，先 `git rm --cached dist/fist-mbt.js dist/patch_esm_main.py`。
3. **BUG-161 协议兼容**是最高优先级打磨项：让 `fist serve` 讲标准 MCP 协议（`2025-06-18`），否则主流客户端连不上发布版。

## 来源

- 本会话 Round 120/121 工具调用记录
- `src/server/server.mbt:1`、`src/server/issue_scan.mbt`（并发 WIP）
- `memory/bugs.md` BUG-161/163 条目
- 守卫族回执（tools_sync / test_sync / badge / template_ctrl / doc_surface / plugin_sync）
