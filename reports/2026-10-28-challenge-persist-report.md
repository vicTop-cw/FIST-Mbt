# challenge nonce 落库 —— S3 从「单机能用」到「部署能用」（BUG-466）

> **执行人**：司令-γ · **日期**：2026-10-28
> **一句话**：Alpha 连续三轮报的 R1 风险（进程内 nonce）**已解除** ——
> A 进程签发、B 进程消费，**真跨进程实测通过**。

---

## 结论

| 项 | 结果 |
|---|---|
| **落库怎么做的** | 新增 `agent_challenges` 表（主键 `(ns, agent_fp, nonce)`）+ 三个操作 + 内存后端**真实现** |
| **跨进程真的能消费吗** | **✅ 是** —— 独立 node 进程实测：A 签发 ⇒ B 消费 `changes=1` ⇒ C 重放 `changes=0` |
| **内存后端怎么处理** | **真实现（非占位）+ 如实披露** `challenge_persisted()=false`（判例-35） |
| **变异对照** | **2 个真跑**：不落库 ⇒ 5 格红；consume 恒 true ⇒ 4 格红 |
| **清理** | `challenge_cleanup(cutoff)` 删已消费 + 过期，返回删除行数 |
| **测试** | `src/store` **118/118**；全量 **1786/1786** |

---

## 证据

### §1 表定义

```sql
CREATE TABLE IF NOT EXISTS agent_challenges (
  ns        TEXT    NOT NULL DEFAULT 'default',
  agent_fp  TEXT    NOT NULL DEFAULT '',
  nonce     TEXT    NOT NULL DEFAULT '',
  issued_at TEXT    NOT NULL DEFAULT '',
  consumed  INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ns, agent_fp, nonce)
);
```

**三处设计决策**：
1. **`ns` 进主键** ⇒ ns 隔离（锁 `c466_l2d` 钉住「在 ns-A 签发的票在 ns-B 消费不掉」）
2. **`agent_fp` 进主键** ⇒ 按 agent 归档（与 `judged_role_gated` 的 `agent_fp_of` 同口径）
3. **`consumed` 用标记而不是删行** ——
   删行后**无法区分「从未签发」与「已消费」**；更关键：并发下
   `DELETE ... WHERE nonce=?` 若删 0 行，无法判断是「不存在」还是「已被别人删」；
   而 `UPDATE ... WHERE consumed=0` 的 **rowcount 精确表达「我是那个把它从 0 变 1 的人」**。

### §2 三个操作（`src/store/store_sqlite_challenge.mbt`）

```moonbit
// 签发：INSERT OR IGNORE ⇒ 重复签发同 nonce 幂等（不覆盖 issued_at）
pub fn SqliteStore::challenge_issue(self, ns, agent_fp, nonce, issued_at) -> Result[Unit, String]

// 原子一次性消费：UPDATE ... AND consumed = 0 ⇒ 判 changes() > 0
pub fn SqliteStore::challenge_consume(self, ns, agent_fp, nonce) -> Bool

// 清理：删已消费 或 早于 cutoff，返回删除行数
pub fn SqliteStore::challenge_cleanup(self, cutoff) -> Int32
```

**内存后端**（`store_challenge.mbt`）：三个操作**都真读写** `MemoryStore.challenges`，
**不是占位**（BUG-439/441 的教训）。但 `challenge_persisted()` 对内存后端**如实报 `false`**：
```
同一个 +challenge_verified 在两种后端下**可信度不同** —— 内存后端换进程就失效。
调用方拿到 persisted=false 就知道「这次验签只在本次进程内成立」。
```

### §3 ★ 跨进程实测（硬要求 ①，判例-31：不用 sleep 抢时序）

`temp/audit/lane_cg_xproc.py`：同一个 db 文件，**三个独立进程**按顺序 spawn：

```
[进程A] 签发完成，pending = 1
[进程B] 独立 node 进程消费 ⇒ {'changes': 1}
  ⇒ 跨进程消费成功？ ✅ 是
[进程C] 独立 node 进程重复消费同一票 ⇒ {'changes': 0}
  ⇒ 一次性消费跨进程生效？ ✅ 是
[库内终态] consumed = 1 · 未消费数 = 0

✅ BUG-466 跨进程实测通过：A 签发 ⇒ B 消费成功 ⇒ C 重放被拒
```

**⇒ 票真的在库里，不在任何进程的内存里。**

### §4 六格白盒锁（`store_challenge_bug466_wbtest.mbt`）

| 锁 | 验什么 |
|---|---|
| `c466_l1` | **A 实例签发 ⇒ B 实例（独立句柄、同一文件）消费成功** ← 跨进程核心 |
| `c466_l2a` | 同一实例消费两次 ⇒ 第二次 false |
| `c466_l2b` | A 签发 + B 消费 ⇒ **C 重放同一票 ⇒ false**（库级一次性） |
| `c466_l2c` | 从未签发过的 nonce ⇒ false（fail-closed） |
| `c466_l2d` | **ns 隔离**：ns-A 的票在 ns-B 消费不掉，在 ns-A 成功 |
| `c466_l3` | 内存后端**真实现** + `challenge_persisted()=false` 如实披露 |
| `c466_l5` | cleanup 删已消费 + 过期，保留新鲜 |

### §5 变异对照（2 个，真跑）

**变异 1：`challenge_issue` 不落库**
```
注入：INSERT 前 `return Ok(())`（模拟 BUG-466 原状）
  F| c466_l1 … failed   ← 跨实例消费失败（核心锁）
  F| c466_l2a … failed
  F| c466_l2b … failed
  F| c466_l2d … failed
  F| c466_l5  … failed
  Total: 118, passed 113, failed 5
```

**变异 2：`challenge_consume` 不判 rowcount（恒 true）**
```
注入：`db.changes() > 0` → `db.changes() >= 0`
  F| c466_l2a … failed   ← 同实例重放被接受
  F| c466_l2b … failed   ← 跨实例重放被接受
  F| c466_l2c … failed   ← 未知票被接受
  F| c466_l2d … failed   ← 跨 ns 就算消费失败也返回 true
  Total: 118, passed 114, failed 4
```

**⇒ 两个变异各自打中不同的锁集合，说明锁真的在看。**

### §6 过程中踩到的两个坑（值得记）

**坑 1：建表清单有**两份**，而只有一份真执行**
`store_sqlite.mbt` 里 `CREATE TABLE` 出现两处：:174 是**声明式清单**（看起来是唯一真源），
:919 是 `db.exec(...)` 序列（**真正执行的那份**）。我先改了 :174 ⇒ 表**没建出来**，
现象是 `issue` 成功但 `pending_count=0`、`consume` 恒 false。
**⇒ 与 R12 `check_two_faces.py` 要找的「同一规则两份实现」是同一形态。**

**坑 2：`Statement::step()` 不能用来执行 UPDATE/INSERT/DELETE**
`daqing/sqlite` 的 `Statement::step()` 语义是「**有没有下一行结果**」。
对写语句它**恒返回 false**（没有结果行）⇒ 我最初把 `if !ok { return false }` 当成失败判断，
导致表里**数据插进去了但函数报错、consume 恒 false**。
**⇒ 写语句必须用 `Statement::execute()`；rowcount 用 `Database::changes()`。**

---

## 分析：为什么进程内 nonce 是多实例的硬阻碍

**不是「功能弱一点」，是「部署即不可用」**：
```
A 进程 agent_issue_challenge 签发票 → 客户端拿票请求
  → 负载均衡打到 B 进程 → B 的 Map 里没有这张票
  → challenge_replayed（把**有效票**误判成**重放**）
```
**⇒ 只要起两个实例，S3 就随机失败。** 而「随机失败」比「稳定失败」更难诊断 ——
单实例测试永远绿，一上多实例就间歇性红。

Alpha 连续三轮报这条，而它一直躺在「§缺口」里 —— **这正是「既有限制」变成「永久限制」的路径**。

---

## 缺口与风险

### 1. `challenge_cleanup` **没有调用点**

本单只提供了函数（+ 白盒锁 `c466_l5`），**没有任何定时任务在调它**。
⇒ 表会随签发量**无限增长**（每张票约 100 字节，一天几千张票 = 几百 KB，不致命但会累积）。
**建议**：挂到 `watchdog_tick` 或 `task_cleanup` 旁边（`cutoff` 建议 `now - 24h`）。
**⚠️ 明确未做，因为那是另一个工具的接线，需你裁。**

### 2. `s3_challenge_counter` 仍是**进程级**

多实例部署时不同实例可能发出**相同 nonce 文本**。
**但现在不会误放了**：主键 `(ns, agent_fp, nonce)` 会 `INSERT OR IGNORE` 吞掉重复，
且**两个实例的票各自独立可消费**（各自一行）。**⇒ 唯一性由库保证，计数器只负责「不复用」这一弱属性。**
若要全局唯一，需把计数器也落库（**不在本单边界**）。

### 3. `server.mbt` 的三处签发点已传 `ns~`，但 `issued_at` 用 `now_default()`

**⇒ 签发时间戳是服务端盖章的**（符合 BUG-33 政策）。若将来有人改成由调用方传 `issued_at`，
清理逻辑（按 `issued_at < cutoff` 删）就可能被利用 —— **`issued_at` 只能是服务端值**。

### 4. 未跑 `moon fmt`

`moon fmt` 在本机因 BUG-388 不可用。删改的 5 个文件我按现有风格手写，
但**未验证格式门**（权威面在 CI）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-challenge-persist-report.md` |
| 表定义 | `src/store/store_sqlite.mbt`（**`db.exec` 那份**，:919 附近） |
| SQLite 实现 | `src/store/store_sqlite_challenge.mbt`（issue / consume / cleanup / pending_count） |
| 后端分发 | `src/store/store_challenge.mbt`（真实现 + `challenge_persisted` 披露） |
| 内存字段 | `src/store/store.mbt`（`MemoryStore.challenges` + `challenge_key`） |
| 引擎 | `src/engine/engine_rsv.mbt`（`FistEngine::s3_consume_nonce` / `challenge_persisted` / `challenge_cleanup`） |
| 接线 | `src/server/server.mbt`（3 处签发传 `ns~` + 1 处消费改 engine 版） |
| 锁 | `src/store/store_challenge_bug466_wbtest.mbt`（7 格） |
| 跨进程探针 | `temp/audit/lane_cg_xproc.py` + `b466_consume.cjs` |
| **建议后续** | ① `challenge_cleanup` 接定时任务 ② 计数器落库（全局唯一 nonce）③ 把「建表清单有两份」做成判据 |
