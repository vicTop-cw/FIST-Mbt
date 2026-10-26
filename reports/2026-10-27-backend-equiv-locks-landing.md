# 双后端等价性锁落地（BUG-431 / Lane AJ）· 2026-10-27

## 一、结论

| 项 | 读数 |
|---|---|
| 落地位置 | `src/store/store_rsv_test.mbt`（**追加，未新建第三个 `_test.mbt`**）|
| 新增 test | **5 格**（2 等价锁 + 2 变异对照 + 1 `locks_sweep` 等价锁）|
| `MemoryStore` 覆盖 | **0 → 6**（盲区已闭）|
| store 测试数 | **80 → 85** |
| 连跑 3 次 | **3/3 全绿**（85/85/0 三次逐字相同）|
| 变异实测 | **3 个变异全部被抓到**（见 §二.3）|

---

## 二、证据

### 2.1 汇总行

```
落地前：Total tests: 80, passed: 80, failed: 0.
落地后：Total tests: 85, passed: 85, failed: 0.

连跑 3 次：
  第 1 次: rc=0  汇总：Total tests 85 / passed 85 / failed 0
  第 2 次: rc=0  汇总：Total tests 85 / passed 85 / failed 0
  第 3 次: rc=0  汇总：Total tests 85 / passed 85 / failed 0
```

`moon check --target js` → **57 warnings, 0 errors**

### 2.2 落的 5 格（每格自造库，不依赖上一格）

| # | test 名 | 测哪一格 |
|---|---|---|
| 1 | `rsv 双后端等价：B1~B4 四分支 + ttl/now 边界 + agent 三态` | rsv_action 四分支 4/4 · ttl 三态 3/3 · agent 三态 3/3 = **10 组** |
| 2 | `rsv 双后端等价：锁层无锁/有锁 + status 四种 + ttl 边界` | 无锁/有锁 2/2 · status 4 种 · ttl 边界 = **10 组** |
| 3 | `rsv 双后端等价：locks_sweep 清扫数（Int32）一致` | 种 4 条锁（2 过期 / 1 个 `ttl==now` / 1 未过期），断言**清扫数相等且 == 2** |
| 4 | `rsv 变异对照：strict_lt 在 ttl==now 边界上可分辨` | 证明「严格 <」被真测到 |
| 5 | `rsv 变异对照：锁 status 折叠条件可分辨` | 证明「非 active 折成 None」被真测到 |

**隔离保证**：每格内部 `MemoryStore::new()` / `SqliteStore::open(":memory:")` **各新建一次**
⇒ `:memory:` 每次 open 都是**新的独立库**（SQLite 语义保证），无状态泄漏。
连跑 3 次全绿即为该保证的实证。

**`locks_sweep` 断言的是返回数而非「都成功」**（Lane AH 的缺口项）：
只断言不 panic 会让「清 3 条 vs 清 0 条」这种真分歧溜过去。

### 2.3 ⭐ 判别力证据（**真跑变异，不是推演**）

三个变异都**实际改生产代码 → 跑 → 恢复**（`git diff` 已确认复原，无残留）：

| 变异 | 改了什么 | 结果 | 抓它的 test |
|---|---|---|---|
| **M1** | `store_rsv.mbt:104` `ttl < now` → `ttl <= now` | **85/82/3** rc=1 | ①②④ 三个都红 |
| **M2** | `lock_prev_for_action` 去掉 `status == "active"` 折叠 | **85/79/6** rc=1 | ② 与既有 3 格共 6 个红 |
| **M3** | `store_sqlite.mbt` SQL 谓词 `ttl_until < excluded.created_at` → `<=` | **85/84/1** rc=1 | **只有 ① 红** |

**M3 是本单最有价值的一条**：它只改 **SQLite 侧**的 SQL 谓词，
内存侧不动 ⇒ **只有「双后端等价」这一格能看见它**。
这正是 `store_rsv.mbt:110-112` 注释警告的形状：「两后端必须同一形状，
否则**单测永远绿而 SQLite 红**」—— 落地前**没有任何一格能抓 M3**，现在有了。

---

## 三、分析（≤200 字）

这单的价值不在「加 5 格」，而在**把只覆盖一个后端的测试面变成覆盖两个**。
落地前 `MemoryStore` 出现 0 次，M3 那种「只坏 SQLite 侧」的变异**必然漏网**——
测试会全绿而线上红。三个变异里 M3 是关键证据：它只能被等价锁抓到。
`locks_sweep` 断言返回数而非「都成功」，是因为 `Int32` 的分歧形态就是**数字不同**。

---

## 四、缺口与风险

1. **本单未覆盖的等价比对面**：`assistant_*`（助理选举）、`agents_*`（ACL）等表的双后端一致性仍未锁
   —— 与 rsv/lock 同族，建议后续按同一形状补。
2. **`locks_sweep` 只测了一个时刻**（`now="t1"`）；多时刻交错（先 sweep 一半再种新的）未测。
3. **变异 M3 动了 `store_sqlite.mbt`**（HumanSteward 独占）—— 已**精确恢复并 `git diff` 校验无残留**，
   但那是一时的越界动作；**若将来要把它做成常驻自检，必须走 `check_*` 的 selftest 形态而不是改生产码**。
4. **`:memory:` 每次新建**依赖 SQLite 语义；已在连跑 3 次中实证，但跨进程/并发未测。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | BUG-431 条目挂 `- landing:` |
| **M3 的判别力** | 判例-29 正面实例：「只有双后端锁能抓到的变异」是最强盲区证据 |
| `MemoryStore` 零覆盖 | 已在 AGENTS/README 的守卫族说明处补一句「rsv/lock 面已双后端锁定」|
