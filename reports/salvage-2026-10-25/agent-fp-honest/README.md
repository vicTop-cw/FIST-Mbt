# `fix/agent-fp-honest` 增量保全（BUG-403 / BUG-404 诚实化）

> **来源分支**：`origin/fix/agent-fp-honest`（`a3740ecf`）
> **蒸馏时间**：2026-10-25 · 司令-γ
> **性质**：**纯注释诚实化**，不改任何逻辑。**代理商（判例-54「删对远端 = 目标已达成」不适用）**。

---

## 1. 判定：增量**未落地 main**

```
$ git diff main...origin/fix/agent-fp-honest -- src/server/server.mbt | grep -cE '^\+.*非密码学|^\+.*BUG-403'
3            ← 分支加了 3 行「非密码学 / BUG-403」，main 没有
$ grep -c 'BUG-403' memory/bugs.md
1            ← main 只有 1 处（分支加的是 BUG-403/404 完整条目）
```

**⇒ 这是真内容，不是过期读数。** 与 `test-sync-doc-1413` 型（把旧数改成另一个旧数）**不同类**。

---

## 2. 保全内容

### 2.1 `src/server/server.mbt` — `agent_fp` 的诚实边界

分支把原来这句**误导性承诺**：

```
/// agent 指纹：把调用方自述的 `agent_id` 原文映射为不可逆指纹，
/// 指纹只认原文（fnv1a64("agent_id:" ++ raw)）；`pubkey_fp` 另行
/// 用 fnv1a64("pubkey:" ++ hex) 派生（T0r5：密钥指纹面）。
```

改成：

```
/// agent 指纹：把调用方自述的 `agent_id` 原文映射为**非密码学**短标识，
///
/// **诚实边界（BUG-403）**：`fnv1a64` 是 FNV-1a 64 位，**非密码学哈希**——
/// 乘奇素数 + 异或的链条**可逆**，短 `agent_id` 可反解原文，也可对任意目标值
/// 直接构造前像。因此它**不承诺单向性/防碰撞攻击**，只做**定长短标识 + 去原文污染**。
/// 调用方不得把它当「不可逆指纹 / 身份认证」用；要身份认证用 `pubkey_fp`（见下）。
///
/// **`pubkey_fp` 当前未接线（BUG-403）**：原注释称「pubkey_fp 另行用
/// fnv1a64("pubkey:" ++ hex) 派生」，但全仓无任何代码真正派生它，
/// 所有写入点恒传 `pubkey_fp=""`——那是**死承诺**：若未来按注释接入
/// 「公钥钉身份」，会静默绑定到空串（等于没有键位绑定）。
```

### 2.2 `memory/bugs.md` — 三条完整条目

**BUG-403 [medium]**：`agent_fp` 注释冒称「不可逆指纹」，实现却是裸 FNV-1a（可逆/可伪造）+ `pubkey_fp` 幻影（无代码派生）。
> 影响：agent_id 是自报名字、本身非机密，「指纹泄漏原文」杀伤有限；但「不可逆」承诺**误导安全判断**，「密钥指纹面」是**实打实的死承诺**——一旦接入会静默失效。
> 修法：诚实降级注释 + 标注 `pubkey_fp` 未接线、不得在安全断言里依赖。

**BUG-404 [low]**：`agents_register` 注释称「并落一条 fail-closed 的默认 ACL」，实现只 INSERT `agents` 表、无 `agent_acl` INSERT。
> 实证旁路：`agents_heartbeat` 直连 `agents_register`，产生「有 agent 身份、无 ACL 行」中间态。
> **仍 fail-closed，不是安全洞**；但「注释承诺的默认 ACL 自动落」在直连 store 路径上从不发生。

**系统缺口（同源，附在 BUG-401/403/404 三单共同）**：
> `store_sqlite_agents_wbtest.mbt` 是这条新安全代码的唯一覆盖，**全用硬编码 pid**
> （`:22 pid=1001` / `:43 pid=2002` / `:80 pid=777` / `:118 current_pid=123` / `:170 current_pid=999` / `:231 pid=1`）；
> `grep "current_pid_token|agent_fp" src/*test*.mbt src/*wbtest*.mbt` = 空
> ⇒「进程启动即固定一次」这类注释承诺**在测试里恒真**（因为喂的是常量），**实现怎么漂移都绿着**——BUG-401 的逃逸形状。
> 修法：用真实 `current_pid_token()` 而非字面量驱动一次 register→acl_grant(pid_bound=true)→acl_check。

### 2.3 `src/store/store_sqlite.mbt` — `agents_register` 职责边界

注释改为诚实描述：本函数只写 `agents` 表，ACL 由 server 层 `agents_acl_ensure` 落；
如需「注册即落 ACL」原子语义，把 ACL ensure 并入 register 或让 `agents_heartbeat` 先 ensure。

---

## 3. 为什么这份保全有价值

这三条不是「功能增量」，是**「注释承诺 vs 实现」的失配记录**：

| 单 | 承诺 | 现实 | 危险 |
|---|---|---|---|
| BUG-403 | 「不可逆指纹」 | 裸 FNV-1a，可逆 | 误导安全判断 |
| BUG-403 | 「pubkey_fp 另行派生」 | 全仓零派生，写入点恒 `""` | **若按注释接线 ⇒ 静默绑空串** |
| BUG-404 | 「并落一条 fail-closed 的默认 ACL」 | 只 INSERT agents | 直连 store 路径上从不发生 |

**同族判例：** 判例-5（判据存在但没接线 = 没判据）、判例-16（判据面 < 修复面）、判例-19（`assert_true(true)` 最危险）。
**这份保全记录的正是「注释也是一份承诺，承诺没接线就是死承诺」。**

---

## 4. 若将来要重做

按 `honesty-comments.diff`（79 行）逐处应用即可——**纯注释改动，零逻辑风险**。
⚠️ 但应用前先 `git log main -- src/server/server.mbt` 看是否已有人做过同类诚实化（避免重复）。

---

## 5. 来源

- 分支：`origin/fix/agent-fp-honest` @ `a3740ecf`
- 判据：`git diff main...origin/...` + `grep -c`（**判 rc 不判输出**，判例-10）
- 相关：BUG-401 / BUG-403 / BUG-404 / 判例-5 / 16 / 19 / 54
