# Round 115 · BUG-156 修复 + 并发 agent 大重构验证（金条五）

**日期**：2026-10-15
**HEAD**：`adebe2b`（BUG-156 修复）

## 结果摘要

| 项 | 结论 | 证据 |
|---|---|---|
| **BUG-156 修复** | ✅ 已提交 `adebe2b` | `moon test` 1051/1051 零回归；`moon fmt --check` rc=0 |
| 并发 agent 重构（`starts_with`→`has_prefix`） | ✅ 编译 + 测试均干净 | `moon check` rc=0；`moon test --target js` = **1051/1051** |
| 守卫（4 PASS） | check_tools_sync / doc_surface / template_ctrl / test_sync | 重构未破坏工具数 166 / 文档面 / 模板 / 测试数 |
| 守卫（2 FAIL，并发 WIP 所致） | check_plugin_sync / check_scripts_index | 详见下 |

## BUG-156 修复内容

`moonbit-map-set-no-rebind` 规则的 `why` 原文「Map.set() 返回新 Map，未重绑定则变更丢失」是**事实错误**：

- MoonBit 核心 `Map` 是**可变 map**，`.set()` 原地变更并返回 `Unit`。
- 实证锁 `src/executor/map_probe_test.mbt`（已提交仓内）：`m.set("k",42); m.get("k")` = `Some(42)`，`m.keys().length()` = 2。
- 旧 `hint`「`let map2 = map.set(k, v)` 并重绑定使用」给可变 Map 提的是**无效/误导**建议（绑到 `Unit`）。

**修复**：改写 `why` 为诚实陈述（启发式提示、需读上下文确认、非确定性缺陷检测器，标注 BUG-156）；`hint` 改为「忽略返回值（原地变更），防误当函数式 API」。**未改 `pattern`（`.set(`）**——收窄是独立语义决策，留 owner（本轮只修事实前提，BUG-156 本体）。

## 并发 agent 状态（重要）

并发 agent 在推**大范围机械重构** `starts_with()` → `has_prefix()`（MoonBit API 迁移），工作树 **36 文件 / ~2323 处改动**未提交。我已验证：

- `moon check` rc=0（编译通过，仅警告）
- `moon test --target js` = **1051/1051**（零失败，测试数未变——纯机械改名不增删测试）
- 我的 BUG-156 修复在 `src/server/issue_scan.mbt` L190-196，**未被其重构波及**（其改动在 L349 起，是 `scan_is_comment_line` 等无关处）

## 2 个守卫 FAIL 的归因（并发 WIP 直接产物，非我造成）

1. **`check_plugin_sync` FAIL**：`memory/bugs.md` 含并发 agent 的 BUG-157 报告（未提交）+ 其改了 `AGENTS.md`/`README.mbt.md`。gen_plugins 以 bugs.md + README 为投影源 → 需重生成。**我此刻重生成会嵌入其未提交账本 → CI 干净树必红**，故不动，等并发 agent 提交 bugs.md 后由生成器一次性收敛。
2. **`check_scripts_index` FAIL**：并发 agent 新增 `scripts/warn_stats.py`（未跟踪）未登记进 `scripts/README.md` 索引。属其脚本，我不擅自登记（可能只是临时工具）。

## 任务分配记录

- **本 agent**：修 BUG-156（`issue_scan.mbt` L190-196，已提交 `adebe2b`）；只读验证并发 agent 重构（moon check + moon test + 守卫链）；不掺和其 36 文件 WIP。
- **并发 agent**：`starts_with`→`has_prefix` 全仓迁移（36 文件）+ BUG-157 报告（bugs.md WIP）+ `scripts/warn_stats.py`（新脚本）。

## 遗留风险

1. **BUG-157（OPEN high）**：`assistant_claim` 跨进程并发「单主」不变量击穿——5 进程同时 `elected`，库内 5 行 `is_primary=1`。`assistant_upsert` 的 `INSERT ... ON CONFLICT(agent)` 冲突键只有 agent，结构上无法表达「同时只许一个主」。与 BUG-154 同族（锁层修了、选举层漏了）。**建议优先排期修复**，补 `e2e_assistant_xproc.py` 跨进程回归锁。
2. **BUG-155（OPEN low）**：`dist/fist-mbt.js` 148 vs 166，owner 裁决（重建/退役/扩 J14）——**待用户确认**（删除为不可逆操作，按金条四只出方案+预案）。
3. **2 守卫 FAIL**：随并发 agent 收口收敛（提交 bugs.md + 重生成插件 + 登记 warn_stats.py）。
4. **BUG-156 收窄 pattern 未做**：本轮只修事实前提，`.set(` 仍会报 62 条 low 档启发式命中（现 `why` 已诚实标注需读上下文，非确定性缺陷）。

## 后续建议

1. **等并发 agent 收口**：其提交 bugs.md + 重构后，立即重生成插件（修 check_plugin_sync）+ 登记 warn_stats.py（修 check_scripts_index），把 6 守卫归绿。
2. **BUG-157 优先修**：照并发 agent 的 fix_options ①（`assistant_upsert` 升级为原子裁决原语，照 `rsv_try_set`/`locks_try_acquire` 形状），SQL 侧原子性是唯一可靠路径。
3. **BUG-155 请用户裁决**：dist/fist-mbt.js 零代码/脚本/守卫依赖，退役（git rm --cached）最干净。
4. **BUG-156 收窄**：若要消除 62 条 low 噪声，可后续收窄 pattern 为 `.set(` 的「表达式位置」形态（本轮未做，独立决策）。

## 来源

- `src/server/issue_scan.mbt` L190-196（规则 why/hint）
- `src/executor/map_probe_test.mbt`（实证锁）
- `memory/bugs.md` BUG-155/156/157
- 守卫族 6 项实测
- `moon test --target js` = 1051/1051