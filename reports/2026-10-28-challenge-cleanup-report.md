# challenge 表清理接线（BUG-467）

> **执行人**：司令-γ · **日期**：2026-10-28
> **一句话**：`challenge_cleanup` 从「存在但没人调」变成「**签发时顺带清**」——
> 清理的触发条件与表的增长条件是同一件事，所以「表在长但没人清」这个状态不可能出现。

---

## 结论

| 项 | 结果 |
|---|---|
| **选了哪个调度点** | **③ 签发时清理**（不是 `watchdog_tick`，不是 `task_cleanup`）—— 论证见 §分析 |
| **清理策略** | **保守档 + 24h**：只删 `issued_at < now−24h` 的行，**保留审计证据** |
| **过期未消费的票删掉可接受吗** | **可接受** —— 论证见 §分析（只会让本来要失败的请求继续失败） |
| **变异对照** | **2 个真跑**：清理不删 ⇒ 3 格红；去掉接线 ⇒ 1 格红 |
| **测试** | store **121/121** · engine **333/333** · 全量 **1797/1797** |

---

## 证据

### §1 ★ 先修了一个策略缺陷（旧实现会丢审计证据）

旧 SQL：
```sql
DELETE FROM agent_challenges WHERE consumed = 1 OR issued_at < ?
```

**问题**：`consumed = 1 OR ...` 会**无条件删掉所有已消费的票** —— 哪怕它 1 秒前刚被用掉。
两个后果：
1. **审计证据丢失**：`consumed=1` 是「这张票被用过」的**唯一记录**；
2. **与 BUG-466 的设计自相矛盾** —— 当初留标记而非删行，就是为了审计，结果清理时又把它删了。

**⇒ 改成两档**：

| 档 | SQL | 用途 |
|---|---|---|
| **保守档 `challenge_cleanup_conservative`（默认）** | `DELETE ... WHERE issued_at < ?` | **保留 cutoff 内的全部审计证据**，表仍受时间上界约束 |
| 激进档 `challenge_cleanup_aggressive` | `DELETE ... WHERE consumed = 1 OR issued_at < ?` | 只在需要压表大小时用（**接受丢历史**） |

### §2 接线：签发时顺带清

```moonbit
// engine_rsv.mbt — s3_issue_challenge 内
let _ = self.store.challenge_issue(ns, k, nonce, issued_at)
// BUG-467：签发时顺带清理（返回值丢弃 —— 维护动作失败不该让「取票」失败）
if cleanup_cutoff != "" {
  ignore(self.challenge_cleanup_on_issue(cleanup_cutoff))
}
```
```moonbit
// server.mbt — 三处签发点
eng.s3_issue_challenge_auto(
  agent_id, ns~, issued_at=now_default(),
  cleanup_cutoff=iso_minus_secs(now_default(), 86400),   // ★ 24h
)
```

**`cleanup_cutoff` 由调用方算**（engine 不依赖 `@ops`，不为一时间戳引依赖）；
**engine 只负责策略**（保守档）。

### §3 清理策略的四个参数（硬要求 ①）

| 参数 | 取值 | 理由 |
|---|---|---|
| **cutoff 多久** | **24h** | challenge 生命周期是**分钟级**（签发→签→提交）；24h 给足重试/排队容错 |
| **删不删已消费的** | **默认不删**（保守档） | 那是审计证据，且旧实现在这点上自相矛盾 |
| **删不删过期的未消费** | **删** | 见下 |
| **失败是否阻塞签发** | **不阻塞**（`ignore`） | 维护动作出错不该把可恢复的维护问题变成不可用的鉴权面 |

**⚠️ 「过期未消费的票删掉 = 那些票作废」—— 可接受吗？可以，三条理由**：
1. 本仓 challenge **没有 TTL 强制语义**（`expires_hint` 只是回执里的提示字符串）
   ⇒ 「过期」完全是清理侧的定义，24h 是**保守**值不是紧箍咒；
2. 未消费的票**只对签发它的调用方有用**，而调用方拿票后立刻签、立刻提交
   ⇒ 超过 24h 还没用的票，调用方**早就放弃了**；
3. **万一真有人在 24h 后拿旧票来用 ⇒ `challenge_consume` 返回 `false`**
   ⇒ 走 fail-closed 的 `challenge_failed`（**不是放行**）。
   **⇒ 作废的票只会让本来就会失败的请求继续失败，不会让它们意外成功。**

### §4 表大小可观测（硬要求 ③）

```moonbit
pub fn FistEngine::challenge_table_stats(self) -> (Int32, Int32, Int32)  // (total, consumed, pending)
```
**三个数一起看才知道状态**：
- `pending` 高 ⇒ 签发了但没人用（正常，票有时效）
- **`consumed` 高而 `total` 不降 ⇒ 清理没跑**（本单要暴露的形态）

### §5 五格锁

| 锁 | 验什么 | 包 |
|---|---|---|
| `c467_c1` | 过期票被删、新鲜票留下（**确定性注入** `2020` vs `2099` 时间戳） | store |
| **`c467_c2`** | **硬要求 ②**：清完之后**未过期的票仍能消费成功**；过期票消费 `false`（fail-closed） | store |
| `c467_c3` | 保守档**保留**审计证据、激进档**丢掉** | store |
| `c467_c4` | `table_stats` 三数如实 | engine |
| **`c467_c5`** | **接线格**（判例-29）：走真实签发路径，断言过期票被顺带清掉 | engine |

**判例-31：全程不用 `sleep`** —— 过期与否由显式 `issued_at` 决定（`2020-01-01` / `2099-01-01`），与真实时钟无关。

### §6 变异对照（2 个，真跑）

**变异 1：保守档不删（模拟「没清理」）**
```
注入：DELETE → SELECT
  F| c467_c1 … failed    ← 过期票没被删
  F| c467_c2 … failed    ← 过期票仍能消费（本该 false）
  F| c467_c3 … failed    ← 激进档计数不对
  Total: 121, passed 118, failed 3
```

**变异 2：去掉签发时接线（= BUG-467 原状：函数存在但没人调）**
```
注入：if cleanup_cutoff != "" → if false && ...
  F| c467_c5_cleanup_is_wired_into_issue … failed
  Total: 333, passed 332, failed 1
```

**⇒ 变异 2 正是判例-29 的形态：`challenge_cleanup_conservative` 本身全绿，
但「它有没有被接线」只有 `c467_c5` 测得出。**

---

## 分析：为什么「签发时清」是最好的调度点

| 候选 | 优点 | 致命缺点 |
|---|---|---|
| `watchdog_tick` | 已是定时入口 | **没人跑 watchdog 就永远不清**；且依赖 host 定时器 |
| `task_cleanup` | 语义接近 | **手工调用**，不是定时 —— 没人调一样不清 |
| **签发时清** | **无外部依赖**；**天然节流**；签发少时表也不增长 | 签发少时不清（但那时表也不长） |

**决定性理由**：
> **清理的触发条件与表的增长条件是同一件事（签发）。**
> 把两者绑在一起 ⇒ **「表在长但没人清」这个状态不可能出现** ——
> 而这正是 BUG-466/467 要消灭的状态。

换成外部调度器就多了一个「调度器没跑」的失效面 —— **而本仓的定时任务本来就靠人**（`watchdog_tick` 要没人配 cron 就不跑）。
**本单的教训正是「只增不减的表会在某个时刻出事」—— 而「靠人定时清」是同一类依赖。**

**代价**：签发少时不清（表也不长）⇒ **不构成问题**。

---

## 缺口与风险

### 1. 表**仍会随签发量增长**（只是有上界）

保守档保留 24h 内的全部票。若一天签发 N 张，表里稳定持有约 N 行。
**N 很大时**（比如每秒签发）需要激进档或更短 cutoff —— **当前未做自适应**。

### 2. `challenge_total_count` 等是**全表**计数，不分 ns

多 ns 部署时看不到「哪个 ns 的表在长」。
**⇒ 若将来需要，得加 `challenge_count_in(ns)`**（不在本单）。

### 3. `cleanup_cutoff` 由 `server.mbt` 传 —— **三处签发点必须都传**

我只改了现有三处。**将来新增签发点时若忘了传 `cleanup_cutoff` ⇒ 那条路径不清**。
**⇒ 建议把 `cleanup_cutoff` 从「可选参数」改成「必填」，或做成 engine 内部默认。**

### 4. 未跑 `moon fmt`（本机 BUG-388 不可用）

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-challenge-cleanup-report.md` |
| 清理策略 | `src/store/store_sqlite_challenge_cleanup.mbt`（两档 + 两个计数） |
| 后端分发 | `src/store/store_challenge.mbt`（两档的内存实现） |
| 接线 | `src/engine/engine_rsv.mbt`（`challenge_cleanup_on_issue` / `challenge_table_stats`）· `src/server/server.mbt`（三处传 `cleanup_cutoff`） |
| 锁 | `src/store/store_challenge_cleanup_wbtest.mbt`（3 格）· `src/engine/engine_bug467_cleanup_wbtest.mbt`（2 格） |
| **建议后续** | ① `cleanup_cutoff` 改必填或内置默认 ② 加 `challenge_count_in(ns)` ③ 表超阈值时自动切激进档 |
