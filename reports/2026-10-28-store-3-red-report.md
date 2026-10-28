# 3 格 `database is not open` 根因报告（全仓唯一的红）

> **执行人**：司令-γ · **日期**：2026-10-28
> **结论先说**：**是「测试假设了一个不可实现的契约」，但也暴露了实现的一条真边界** —— 两者都写了。

---

## 结论

| 格 | 判定 | 处理 |
|---|---|---|
| `t744_9`（迁移后任务可见） | **测试错**：夹具用「外部直关 `s.db`」代替 `s.close()`，而这个写法在 BUG-463 修好后**已无必要**（`close` 真关句柄了） | 改为 `s.close()` |
| `k463_8`（外部直关后 close 不抛） | **测了一个 MoonBit 上不可实现的契约** | 重写为「close 幂等」+ 新增一格钉住「不可实现」这个事实 |
| `k463_9`（同上，经 close_all） | 同上 | 改为经 `s.close()` 的正常路径 |

**修后读数**：`src/store` **111 / passed 111 / failed 0**（此前 110/107/3）。
**变异对照**：删掉 `close()` 里的 `db.close()` ⇒ **4 格齐红**（`k463_1`/`k463_3`/`k463_5`/`k463_9`）。

---

## 证据

### §1 根因（逐层定位，不是猜）

**写了一个 4 步最小复现**（`dbg_three_red_wbtest.mbt`，已删）：

| 步骤 | 做什么 | 结果 |
|---|---|---|
| D1 | 只 `db.close()`（外部直关），不调 `s.close()` | **通过** |
| D2 | 只调 `s.close()`（不外部直关） | **通过** |
| **D3** | 外部直关 → `s.close()` | **✗ 抛 `database is not open`** |
| D4 | 外部直关后什么都不做（靠 drop） | **通过** |

**⇒ 唯一失败组合是 D3：外部先关底层句柄，再调 `store.close()`。**

### §2 为什么 `close()` 里的 `catch` 拦不住

`store_sqlite.mbt:101` 现写法：
```moonbit
db.close() catch {
  _ => ()
}
```

**两轮实验证明这个 `catch` 是装饰性的**：

| 实验 | 写法 | 结果 |
|---|---|---|
| P2 | `let _r : Unit? = Some(db.close()) catch { _ => None }`（**标准 catch 写法**） | **✗ 仍抛** |
| Q1 | `try { db.close() } catch { _ => () }`（**try/catch 写法**） | **✗ 仍抛** |
| Q2 | 裸 `db.close()`（对照组） | ✗ 抛（证明 Q1 的红不是「根本没抛」） |

**根因链**：
```
daqing/sqlite  Database::close(self) -> Unit      ← **无 raise 标注**
        ↓
sqlite_js.mbt:196  self.db.close()                ← 调用 node:sqlite DatabaseSync.close()
        ↓
node:sqlite  已关闭的 DatabaseSync 再 close()      ← **抛 JS 运行时异常**
        ↓
MoonBit 的 catch / try·catch 只包住 **raise 效果** ⇒ **拦不住 JS 运行时异常**
```

**⇒ 这是一条**实现层真边界**：`store` 无法「容错关闭一个已被外部关掉的句柄」。**
不是「忘了 catch」，是**语言层的 catch 管不到 FFI 抛出的东西**。
（`Database` 也没有 `is_open` 之类状态查询 ⇒ store **无从得知**外部关过没。）

### §3 改动

**`store_migration_wbtest.mbt:122-125`（t744_9）**
```diff
-      match s.db {
-        Some(db) => db.close()
-        None => ()
-      }
+      s.close()
```
**为什么现在对**：注释原文是「产品侧 `MultiStore::close_all` 同样只从 map 里摘掉、不关底层句柄（BUG-461 附带发现）」——
**那个前提在 BUG-463 修好后已经不成立**（`close` 现在 `try`/吞异常 + 置 `None` + `closed = true`）。
夹具直关的理由消失了 ⇒ 改用它自己该用的出口。

**`store_bug463_close_wbtest.mbt`（k463_8 / k463_9）**
- `k463_8` → 重写为 **`k463_8_close_is_idempotent_and_self_discloses`**：
  断言 `close()` 后 `db == None` + `closed == true` + 重复 close 安全 + close 后操作走 `None` 分支。
- 新增 **`k463_8b_external_raw_close_then_store_close_throws_by_design`**：
  把「二次 close 会抛」钉成**可执行的事实** —— 将来某个 sqlite 版本让 `close` 真幂等，**本格会红**，
  那时才应该恢复「容忍外部直关」那条契约。
- `k463_9` → 改用 `s.close()` 的正常路径（保留 `close_all` 的可删 `.db` 断言）。

### §4 变异对照（真跑）

```
注入：把 store_sqlite.mbt 的 close() 里 `db.close()` 整段删掉（退回 BUG-463 原状）
  F| k463_1_close_releases_handle                            failed
  F| k463_3_close_all_closes_every_ns                        failed
  F| k463_5_close_ns_releases_only_that_ns                   failed
  F| k463_9_close_all_tolerates_external_raw_close           failed
  Total tests: 111, passed 107, failed 4

恢复：cp /tmp/ss.bak → Total: 111, passed 111, failed 0；git diff 行数 = 0
```

---

## 分析：为什么 `database is not open` 出现在 close 相关测试里

**这不是「close 写错了」，是「两个 owner 对 close 语义的假设不同」**：

| 谁 | 假设 | 依据 |
|---|---|---|
| **BUG-463 的实现** | `close()` 是唯一出口，天然幂等（`db == None` 就跳过） | 合理 |
| **旧夹具（BUG-461 时代）** | `close()` **不关句柄** ⇒ 为了删 `.db` 必须**绕过它**直关 `s.db` | 当时是真的 |

**⇒ 夹具的「绕过」写法**在 BUG-463 修好前是**必要**的，修好后**变成了冲突源**：
它制造的「外部直关」状态恰恰是 `close()` 无法处理的那个状态。

**而 `k463_8` / `k463_9` 两格是有人**意识到**这个冲突后写的**防御性锁**——
但他们假设「`close()` 应该能容忍」，而**这个假设在 MoonBit 上做不到**（§2 实测）。
**⇒ 这两格测的不是 bug，是一个理想。**

---

## 缺口与风险

### 1. `close()` 里的 `catch` 应当删掉或改注释，否则是「假防线」

`store_sqlite.mbt:101` 的 `db.close() catch { _ => () }` **拦不住任何东西**（§2 实测）。
**建议**：要么删掉（明说「不做容错」），要么改成注释说明「这里 catch 无效，仅为表达意图」。
**⚠️ 我没改** —— `store_sqlite.mbt` 是 BUG-463 owner 面，且这需要他裁决是删还是留。

### 2. 同一类「无效 catch」可能全仓还有

`catch` 对**非 raise 的 FFI 调用**无效 ⇒ 任何「包住 FFI 调用防崩溃」的 `catch` 都是装饰。
**建议**：扫一遍 `catch {` 出现在 `db.` / `fs.` 等 FFI 调用后的地方（**不在本单边界**）。

### 3. 全量仍有 3 格红，**在 `src/server`**，与本单无关

```
F| server_bug430_keypin_wbtest.mbt:300       kp_05_tool_uses_the_pin_verdict_before_any_write
F| server_bug430_first_reg_proof_wbtest.mbt:44  bs_01_phase1_issues_challenge_without_writing
F| server_bug430_first_reg_proof_wbtest.mbt:98  bs_03_proof_is_verified_before_write
```
`git status` 显示 `server_bug430_first_reg_proof_wbtest.mbt` 是 **`M`（他人未提交的在途改动）**。
**⇒ 那 3 格不是本单引入，也不在 `src/store`。本单目标（`src/store` 全绿）已达成。**

**全量读数**：`Total tests: 1765 / passed 1762 / failed 3`（那 3 格属 BUG-430 在途）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-store-3-red-report.md` |
| 改动 | `src/store/store_migration_wbtest.mbt`（1 处）、`src/store/store_bug463_close_wbtest.mbt`（3 格重写/新增） |
| **建议后续** | ① 删/改 `store_sqlite.mbt:101` 的无效 `catch`（交 BUG-463 owner）② 全仓扫「无效 catch」③ 那 3 格 `src/server` 的红交 BUG-430 lane |
| **未做** | **未改 `store_sqlite.mbt` / `multi_store.mbt`**（变异已 `cp` 还原，`git diff` 0 行）· 未碰 `src/server` |
