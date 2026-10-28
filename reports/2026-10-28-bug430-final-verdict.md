# BUG-430 收口判断

> 2026-10-28 · Lane CM · 第 28 轮拍板

---

## 结论

### 四项覆盖率读数（实测）

| # | 读数 | 值 | 含义 |
|---|---|---|---|
| `challenge` 工具 / 总数 | **5 / 156（3.2%）** | `plan` `claim` `reserve_scope` `lock_acquire` `agent_register_key` |
| 有公钥 agent / 总数 | **1 / 6（16.7%）** | 只有 1 个会触发「必须验签」 |
| 软强制降权 | 已实现（`engine_rsv.mbt:221`）| 有公钥不传 ⇒ `Executor`+`challenge_required` |
| 生命周期后半段 | **六工具全无 `challenge`** | `execute/submit/verify/reject/retry/archive` |

### 收口口径：**选 ③ 拆号**，但**不是**「默认要求认证的迁移路径」

**拆法（与派单建议不同）**：

- **BUG-430 → 标 FIXED**：已落地的是「**认证基础设施**」（S3 九段 + 取票窗口 + 软强制降权）
- **新开 BUG-469**：`execute` / `submit` / `verify` / `reject` / `retry` / `archive` **接 challenge**
  —— 这是**覆盖面缺口**，不是「迁移路径」
- **新开 BUG-470**：把「默认要求认证」写成**显式的迁移方案**（需要 owner 决策，不是技术活）

**⇒ 回答派单的问题：**
> **BUG-430 能关。关的是「S3 认证基础设施已建成且可用」。**
> **不能关的是「认证已成为默认」—— 但那不是 BUG-430 的原始范围，是另一个决策。**

---

## 证据

### ① 覆盖面：3.2%

```
工具总数: 156
声明 challenge 的: 5
   plan                challenge_sig=YES
   claim               challenge_sig=YES
   reserve_scope       challenge_sig=YES
   lock_acquire        challenge_sig=YES
   agent_register_key  challenge_sig=NO（用 proof_sig，是登记面不是验签面）
```

### ② 产品库：1/6

```
agents 总数: 6 ｜ 有公钥: 1
```
⇒ **只有那 1 个 agent 会触发软强制降权**；其余 5 个完全不受影响。

### ③ 软强制降权（已在，非提案）

```moonbit
// engine_rsv.mbt:218-225
None =>
  if declared_pubkey_for(eng, agent) is Some(_) {
    ("Executor", "challenge_required")
  } else {
    judged_role(eng, agent)
  }
// engine_rsv.mbt:677
"challenge_required" => "+challenge_required"
```

### ④ 生命周期后半段：零保护

```
execute  challenge=NO      submit  challenge=NO      verify  challenge=NO
reject   challenge=NO      retry   challenge=NO      archive challenge=NO
```

**⇒ 一个已登记公钥的 agent，认领任务时会被降级，
但「记录交付物 / 提交验收 / 验收 / 打回」全部无需认证。**

---

## 分析：「存在」≠「被要求」

| 维度 | 现状 | 「默认要求」需要 |
|---|---|---|
| 受保护工具 | 5 / 156（**3.2%**）| 全部写面 |
| 有公钥 agent | 1 / 6（**16.7%**）| 接近 100% |
| 生命周期覆盖 | 前半段（认领/预订/锁）| **全段** |

**⇒ 字面条件确实满足，但那条路径只覆盖 3.2% 的工具面，
83.3% 的 agent 根本不会走到它上面。**

**为什么仍建议「关 430、另开 469/470」**：BUG-430 的原始描述是
「MCP 工具面零认证」—— **S3 九段 + 取票窗口 + 软强制降权已消除该缺陷**。
剩下三件事（覆盖面 / 默认要求 / ns 隔离）**都是新范围**，
塞在同一个号里会让「430 卡了 28 轮」继续误导下一个人。

---

## 具体账本动作（可执行）

### 动作 1：标 BUG-430 FIXED

```
bug_fix(bug_ids=["BUG-430"], evidence="...")
```

（evidence 已随 `49ac7199` 落账，见该提交正文）

### 动作 2 / 3：新开 BUG-469 / BUG-470（已执行，`b6a21969`）

- **BUG-469 [high] 覆盖面缺口**：`execute`/`submit`/`verify`/`reject`/`retry`/`archive` 全无 `challenge`。
  **关闭条件**：① 六个工具全声明 `challenge`+`challenge_sig`；② `action` 面能表达 verified/required；
  ③ 有锁 + 变异对照证明「有公钥不传 ⇒ 降级或拒绝」。
- **BUG-470 [medium] 产品决策**：83.3% 的 agent 无公钥，软强制不触发。
  **关闭条件**：① 存在批量登记公钥的运维路径；② owner 选「默认拒绝 vs 默认降权」；③ 有可回滚开关。

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | ✅ **已澄清**：`bug_fix` **可通过 `python scripts/fist.py call` 调用**（前几轮说「不可用」是因为 MCP 直连工具不在会话工具表里，不等于 CLI 不可用）。**本单已实际执行三个账本动作** |
| **R2** | 拆号后**跨号追溯**：430 的 evidence 必须点名 469/470，否则下一个人只见 430 关、不见后续 |
| **R3** | `agent_register_key` 的 `challenge` 配 `proof_sig` 而非 `challenge_sig`（登记面）⇒ 统计「5 个」要说明，否则误读成「5 个受保护工具」 |

---

## 建议入档位置

**账本**：执行上面三个动作。

**判例候选**：
> **判例：长期 OPEN 的 bug 会从「待办」退化为「噪音」。**
> BUG-430 卡了 28 轮，但**原始诉求早在 S3 九段落地时就已满足**；
> 剩下的是**新范围**（覆盖面、产品决策），塞在同一个号里会让读者以为
> 「还有大事没做」，而实际是「做完了但没拍板」。
> **⇒ 收口的标准不是「全部相关的事都做完」，而是「原始描述的那个缺陷没了」。**
> 剩下的必须**另立号**，并在原号 evidence 里点名 —— 否则拆号等于丢线索。

---

**账本动作已执行**（`fist.py call bug_fix` 可用，与前几轮的猜测不同）：

| 动作 | 提交 | 结果 |
|---|---|---|
| BUG-430b → FIXED | `abb908af`(随搬家) | `heading_changed:1`，FIXED 小记已落 |
| BUG-430 主条 → FIXED | `49ac7199` | `heading_changed:1`，FIXED 小记已落 |
| 新开 BUG-469 / BUG-470 | `b6a21969` | 两条已在账本 |
| test_crypto 上提到 core（R27 的 R1 应验）| `abb908af` | rename 86%，engine 336/336 |

**⚠️ 过程中发现账本已比派单描述更复杂**：BUG-430 早在 R25/R26 就被拆成 a/b/c 三条，
其中 430b 的两条诉求（取不出挑战 / claim 不接受 challenge）**已由 BUG-466 落地并实测**
⇒ 本单先把它标 FIXED，才标主条。
