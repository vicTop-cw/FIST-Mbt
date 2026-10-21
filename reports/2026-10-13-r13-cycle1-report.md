# R13 · 四模式流水线自我迭代 · Round 1 报告

- **日期**：2026-10-13
- **命名空间**：`r13-pipeline`（根任务 `T0`）
- **模式**：bugfind → fix_and_merge → polish → verify（第 1 环起步，聚焦 bugfind 实证 + fix）
- **执行方式**：**fist-mbt 本机发布版**（`python scripts/fist.py call <tool>` 走本机 server，非源码依赖）
- **开关状态**：`task_plan_deep` **全部开启**——`gradient=true` / `calibrate=true` / `reinject_context=true` / `boundary_probe=true` / `omega_strong_verify=true`

---

## 结果摘要

按用户指令「用 fist-mbt 本机发布版执行，实现计划里未实现的计划，开关类全部开启」，本轮完成 R13 启动 + 第 1 环 bugfind→fix 实证闭环：

1. **R13 流水线就绪**：`publish` 根任务 `T0`（ns=`r13-pipeline`）→ `claim` → `task_plan_deep`（开关全开）→ 拆出 **4 中 × 3 叶 = 12 叶任务**，难度梯度 易→中→难，每条叶挂 `[omega:required]` 强验证标记 + 边界四问 + LADDER「先易后逆推」提示。
2. **bugfind 实证命中（非假阳性）**：全量 `moon test --target js` 初跑 = **810/811**，红在 `src/store/store_assistant_test.mbt:55`（L123 `assert_eq(b.assistant_list().length(), 0)` 得 2）。指挥官独立定位真根因（见下），**不采纳子代理静态自述**。
3. **修复闭环（2 处单行，均实测）**：
   - `src/store/store_sqlite.mbt` `clear()` 补 `ignore(db.exec("DELETE FROM assistant_reg"))`
   - `src/store/store_assistant_test.mbt` L123 前补 `ignore(b.clear()) // 先清旧`
   - **终审实跑**：`moon test --target js src/store` = **37/37/0**；全量 = **811/811/0**（RC=0）
4. **BUG-151 入账（OPEN）**：SqliteStore::clear 双后端语义不一致——MemoryStore 清 `file_locks`/`lock_violations` 而 SQLite 漏清。

## 根因分析（指挥官终审定位）

**双重缺陷 + 测试非幂等，三点连环**：

1. **SqliteStore::clear 漏 `assistant_reg`**（store_sqlite.mbt L685-706 DELETE 清单原为 9 张，漏该表）。
2. **双后端 clear 语义不一致**：`MemoryStore::clear`（store.mbt L333）**有** `assistant_reg.clear()`，SQLite 端没有。multi-agent-lock v3 引入 `assistant_reg` 表（store_sqlite.mbt L109 CREATE TABLE）时只改内存后端、漏改 SQLite 后端——违反 clear 注释里"防测试/scratch 注册跨次残留"精神（R31/R90/R92 均为此加过表）。
3. **测试本身非幂等**：`temp/assistant_store_test.db` 持久化，L123 未先清旧就断言空表（对照 `executor_store_test.mbt` L47 `ignore(b.executor_clear()) // 先清旧` 既有模式）。缺这一行会「首跑绿、次跑红」。

**两处修复互为必需**：补 clear 语义解决后端遗漏；补测试清旧解决测试幂等。缺一仍可能翻车。

## 资源消耗

| 资源 | 说明 |
|---|---|
| fist-mbt 本机发布版 | `scripts/fist.py call`：`publish` / `claim` / `task_plan_deep`（开关全开）/ `reserve_scope` ×2 / `report_bug` |
| 子代理 1 | 聚焦 bugfix：store_sqlite.mbt + store_assistant_test.mbt 各 1 行 + 只读审计建表清单 vs clear 清单 |
| 指挥官 | 终审定位真根因（读 store.mbt clear / store_sqlite.mbt clear / CREATE TABLE 清单 / executor_store_test 对照）+ 独立复跑 src/store 与全量判据 + 作用域预订 + BUG-151 上报 + memory 沉淀 |
| `moon test --target js src/store` | 37 测试 |
| 全量 `moon test --target js` | 811 测试（初跑 810/811，收口 811/811） |

## 任务分配记录

| 环节 | 承担者 | 交付 |
|---|---|---|
| R13 启动 | 指挥官（fist-mbt 本机发布版） | T0 发布 + 认领 + 开关全开拆解 16 任务 |
| bugfind 命中 | 全量判据 + 指挥官定位 | 810/811 → 锁定 store_assistant_test:55 |
| 修复执行 | 子代理 | 2 处单行 + 只读审计（clear 未纳入 4 表） |
| 终审验证 | 指挥官 | 独立复跑 src/store 37/37 + 全量 811/811 + 独立核查 CREATE TABLE vs clear DELETE |
| bug 上报 | 指挥官 | BUG-151（OPEN，medium） |
| 沉淀 | 指挥官 | memory/2026-10-13.md 追加 + 本报告 |

## 遗留风险

1. **BUG-151 OPEN（本轮未修）**：`file_locks`/`lock_violations` 双后端 clear 不一致。**不修原因**：`store_sqlite.mbt` 正被他方 WIP 占用（git ` M`，工作树有未提交的 assistant_reg 建表/lock_violations_push），并发改会覆盖。留给该面 owner 收口。
2. **测试盲区**：`store_backend_semantics_test` 只调用 clear() 取干净后端，**未锁**"clear 清哪些表"的双后端一致性——双后端差异一直没被发现。建议后续加锁。
3. **`clear()` 未纳入 4 表待定性**：`evolve_artifacts` / `file_locks` / `lock_violations` / `runs`。其中 file_locks/lock_violations 属真不一致（MemoryStore 清、SQLite 不清）；evolve_artifacts/runs 可能有意保留，需逐一定性。
4. **R13 活风险（他方面）**：README 资产名字面量 `fist-mbt-js-v0.3.6.zip` ≠ moon.mod 0.3.8（R13 判据漂移雷）；属并发会话 `M` 占用面，本轮未动。
5. **SHIP-PLAN G7「CI 自动发布接 GitCode」** 确未实现，卡点=外部 API 事实（GitCode v5 项目/release 端点形状未知或 token 无 scope），留给 owner。
6. **归属诚实**：`DELETE FROM assistant_reg` 为子代理所加；`assistant_reg` 建表/upsert/list/lock_violations_push 是他方 WIP，**非本轮贡献**。

## 后续建议

1. **BUG-151 由 store_sqlite.mbt 的 owner 收口**（他方 WIP 合并时一并补 `DELETE FROM file_locks` / `DELETE FROM lock_violations`，与 MemoryStore 对齐）。
2. **补"clear 清哪些表"一致性锁**：在 `store_backend_semantics_test` 加一条双后端同构断言，锁死 clear 语义，防再漂移。
3. **R13 第 2 环**换面：README 资产名漂移（需 README owner 协作）+ G7 GitCode 发布（需 owner 决策）+ `clear()` 剩余 2 表定性。
4. **12 叶任务后续**：T0.1~T0.4 其余叶任务按 DAG 拓扑依次 claim → 执行 → `omega_spec_create/review` → `execute` → `omega_result_verify` → `submit` → `verify`（`omega_strong_verify=true` 门禁生效）。

## 超额内容

- **bugfind 零误报纪律保持**：本轮命中非假阳性（有实测 810/811 支撑 + 双后端代码可证），延续 R5 起的零误报传统。
- **他方 WIP 避让是新一轮关键纪律**：本轮差点让子代理继续改 `store_sqlite.mbt`，终审发现 ` M` 状态后果断止损。**「预订作用域」≠ 实际独占**——他方不遵守预订时，靠 `git status` 的 ` M`/`??` 判断占用面才是可靠手段。
- **一源四态/增量零回归**：本次修复只动 store 包 2 行，全量 811/811 零回归，未触发 gen_plugins（未改工具描述/schema）。

## 来源

- 缺陷定位：`src/store/store.mbt` L322-334（MemoryStore::clear）、`src/store/store_sqlite.mbt` L685-706（SqliteStore::clear）、L93-118（CREATE TABLE 清单）、`src/store/store_assistant_test.mbt` L55-158、`src/store/store_assistant.mbt`（untracked）、`src/store/store_backend_semantics_test.mbt` L21、`src/store/executor_store_test.mbt` L47（先清旧模式）
- 判据：全量 `moon test --target js` = **811/811/0**（收口后）；src/store = **37/37/0**
- 缺陷账本：`memory/bugs.md`（BUG-151，OPEN）
- 当日日志：`memory/2026-10-13.md`（R13 段）
- 子代理回传：2 处单行 diff + 只读审计（clear 未纳入 4 表）
- 前序计划：`reports/2026-10-11-r12-cycle1~12-report.md`（R12 闭环）、`memory/2026-10-13.md`（v0.3.8 Release、R13 活风险、G7）