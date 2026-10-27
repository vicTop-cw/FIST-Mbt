# BUG-430 / S3 **收尾**：四门工具实现读 challenge 并透传 · Lane BJ · 2026-10-27

> **改的是「读了但没用」这一环。** schema 已加（`dc8ef707`），但工具实现没读
> ⇒ 调用方传了挑战也白传。
> 改完后：**调用方可以经 MCP 提交挑战了**。但 BUG-430 仍 **OPEN**。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 改了几道门 | **3 道**（`reserve_scope` / `lock_acquire` / `claim`）|
| 为什么不是 4 道 | **`execute` 不属于四门** —— 它走 `execute_with_meta`，**不调 `judged_role`**（实测 grep 计数 = 0）⇒ 接了也没用 |
| 零回归 | ✅ **空串 ⇒ None ⇒ 走原逻辑**（`s3_wire_02` 钉住）|
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/server` **424/424/0**；全量 **1604/1604/0** |
| 变异对照 | **2 个真跑**，各自精确打红 |

---

## 二、证据

### 2.1 统一读取入口 `opt_challenge`

```moonbit
fn opt_challenge(args : Json) -> (String?, String?) {
  let ch = get_str(args, "challenge")
  let sig = get_str(args, "challenge_sig")
  let c = if ch == "" { None } else { Some(ch) }
  let s = if sig == "" { None } else { Some(sig) }
  (c, s)
}
```

**为什么抽成一个函数而不是三门各写一份**：BUG-432 的教训 ——
同一语义长第二个实现必翻车。**一处判空，三处共用。**

### 2.2 三门改动（`server.mbt`）

| 门 | 改动 |
|---|---|
| `reserve_scope` | `let ch = opt_challenge(args)` → `engine.rsv_try_set(..., challenge_nonce=ch.0, challenge_sig=ch.1)` |
| `lock_acquire` | 同上 → `engine.locks_try_acquire(lock, challenge_nonce=ch.0, challenge_sig=ch.1)` |
| `claim` | 同上 → `eng.claim(..., challenge_nonce=ch.0, challenge_sig=ch.1)` |

### 2.3 ⚠️ 一处对派单的纠正：`execute` **不在四门内**

派单列的四门含 `execute`。**实测 `execute_with_meta` 里 `judged_role` 出现次数 = 0**
—— 它不走角色取数面，**不参与 `judged_role` 裁决**。
⇒ 给它接 `challenge` 是**死参数**（无消费方）。

**锁 `s3_wire_04` 把这个事实钉住**：断言 `execute_with_meta` 函数体里**没有** `judged_role`；
若将来有人给它加了角色门，本格会红并提醒「四门清单需要更新」。
**这比硬接一个没用的参数诚实。**

### 2.4 四格锁 + 两个变异（**都真跑**）

| 锁 | 断言 |
|---|---|
| `s3_wire_01` | `opt_challenge` 存在 + 真读 `challenge` / `challenge_sig` + 三门各调过一次（≥3）|
| `s3_wire_02` | **空串 ⇒ `(None,None)`**；真值 ⇒ `Some`；只传 challenge 不传 sig ⇒ `(Some,None)` |
| `s3_wire_03` | **透传格**：`challenge_nonce=ch.0` 与 `challenge_sig=ch.1` 各出现 ≥3 次 |
| `s3_wire_04` | `execute_with_meta` **不调** `judged_role`（故不需要接挑战）|

**变异实测**：

| 变异 | 改了什么 | 结果 |
|---|---|---|
| **M1** | `opt_challenge` 不读 challenge（恒 None）| **422/424**，`s3_wire_01` + `s3_wire_02` 红 |
| **M2** | 读了但**不透传**（`ch.0/ch.1` 换成 `None`）| **423/424**，**只有 `s3_wire_03` 红** |

**M2 是关键**：它证明「读」与「传」是**两个不同的格**，
只测「读了」的锁不会抓到「读了忘传」（判例-29）。

---

## 三、分析

### 3.1 为什么空串必须等价于「没传」

MCP 协议层**区分不了**「optional string 没传」与「传了空串」——
`get_str` 两者都返回 `""`。

若把空串当 `Some("")`：**所有旧调用方**会突然进入验签分支
⇒ 无公钥 ⇒ 全部 `challenge_failed` ⇒ **灾难性回归**（现网全部写操作被拒）。
**⇒ 空串必须等价于「没传」，这是零回归的唯一实现方式。**

### 3.2 为什么「读了」和「传了」要分开锁

`opt_challenge` 读对了但工具实现忘了把 `ch.0/ch.1` 传给引擎 ⇒
**挑战读了、丢了** ⇒ 行为与没接一样。
这种「半接线」在只看 normal path 的测试里**完全看不出来**（因为不传挑战时两边都是 None）。
⇒ `s3_wire_03` 专门锁「透传」这一步（M2 实测精确打红）。

---

## 四、缺口与风险（S3 是否完全生效）

**挑战链路现在完整可用了**：
```
MCP args.challenge → opt_challenge → 工具实现 → 引擎 challenge_nonce/sig
  → judged_role_gated → verify_challenge_sig(@mooncry.ed25519_verify) → 角色
```

**但 BUG-430 仍 OPEN，因为「能用」≠「有密钥」**：

1. **没有任何 agent 有公钥** —— `server.mbt` 的 `agents_register` 调用点
   （`dc8ef707` 已接线 `pubkey_hex`，但**上游没有传值的地方**）
   ⇒ 传挑战一律 `challenge_failed`。**这是正确且期望的 fail-closed。**
2. **没有客户端签名工具** —— 调用方需要自己持有私钥并签名。
   本仓只提供验签面，**不提供签发面**（也不能提供 —— 那等于绕过 S3）。
3. **密钥分发 / 轮换 / 吊销** —— **这才是真正的工程难点**。
   「有密码学」≠「密钥管好了」：公钥怎么登记？私钥丢了怎么换？离职 agent 怎么吊销？
4. **nonce 表在进程内** ⇒ 多实例部署互不可见。
5. **S2 未做** ⇒ 未登记 agent 仍可自报身份（只是拿到 `unauthenticated` 标注）。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| S3 收尾 | BUG-430 挂 `- s3-wiring:`，**状态保持 OPEN** |
| **`execute` 不在四门内** | BUG-430 正文「四门」定义旁标注（防后人对齐错清单）|
| **「读」与「传」要分开锁** | 判例-29 的又一实例（M2 实测）|
| **空串 ⇒ None 是零回归的唯一实现** | MCP 可选参数接线的通用口径 |
