# BUG-430 第九段：有钥匙就必须出示（软强制降权）

> 2026-10-28 · Lane CF

---

## 结论

| 项 | 结果 |
|---|---|
| **规则实现** | ✅ 改 `judged_role_gated` 的 `None` 分支（**四门唯一汇聚点**）|
| **零回归证明** | ✅ 没钥匙 + 不传 ⇒ 与 `judged_role` **逐字相同**（role + role_source 都相同）|
| **降级可见** | ✅ `role_source = "challenge_required"` ⇒ `action` 带 `+challenge_required` |
| **变异对照** | ✅ **真跑**：删掉判断 ⇒ **329 → 326/3 failed**，锁 2/4/5 全红；恢复后 329/329 |
| **产品面三态** | ✅ 实测：`+challenge_verified` / `+challenge_required` / **无 action 键** |
| **BUG-430 能关吗** | ⚠️ **能关，但建议改判为「可关未关」并新增一条前置**（见 §5）|

---

## 证据

### 规则（增量，只加严不放宽）

```moonbit
// judged_role_gated 的 None 分支（四门唯一汇聚点）
None =>
  if declared_pubkey_for(eng, agent) is Some(_) {
    ("Executor", "challenge_required")   // 有钥匙却没出示 ⇒ 降级
  } else {
    judged_role(eng, agent)              // 没钥匙 ⇒ 原样（零回归）
  }
```

**为什么改这里**：`judged_role_gated` 是 `rsv_set`(428) / `rsv_try_set`(534) /
`locks_try_acquire`(673) / `judged_role_with_nonce`(341) 的**共同下游**
⇒ 一处改动覆盖四门 + `claim`，不需要四处各写一份（判例-29 的正面用法）。

### 五格锁（`engine_bug430_keyed_must_sign_wbtest.mbt`）

| 锁 | 内容 | 结果 |
|---|---|---|
| c1 | 有钥匙 + 真签名 ⇒ `challenge_verified`，且 role 是 `Leader`（未被降级）| ✅ |
| c2 | **有钥匙 + 不传 ⇒ `challenge_required` 且 role 降为 `Executor`** | ✅ |
| c3 | **没钥匙 + 不传 ⇒ 与 `judged_role` 逐字相同**（role + source 都比）| ✅ |
| c4 | ⭐ 变异对照：判断被删则 `src` 会退回 `declared`/`inferred` | ✅ |
| c5 | **降级真的掉权**：`rank_of_role(Executor) > rank_of_role(Leader)` | ✅ |
| c6 | ⚠️ **预取不消费 nonce**：`with_challenge` 连调两次都 verified；`with_nonce` 第二次必 replayed | ✅ |

**c5 是本单最硬的一格**：只证明「role 变成 Executor」不够 ——
必须证明它在**军衔门**上真的掉档，否则「降级」只是换了个字符串。

### 变异实测（真跑）

```
把 `if declared_pubkey_for(eng, agent) is Some(_)` 改成 `if false`
⇒ 328 → **325 passed, 3 failed**
  F| bug430cf_c2_keyed_without_challenge_is_downgraded
  F| bug430cf_c4_variant_removing_keyed_check_breaks_lock2
  F| bug430cf_c5_downgrade_actually_costs_authority
恢复后 329/329 全绿，grep MUTANT-CF = 0
```

### 产品面三态（真实 MCP 客户端，同一 server 进程）

```
=== 有钥匙的 agent（lane-cb-s3，已登记公钥）===
  带 challenge   ⇒ action = '+challenge_verified' | role_source = 'challenge_verified'
  不带 challenge ⇒ action = '+challenge_required' | role_source = 'challenge_required'

=== 没钥匙的对照 agent ===
  不带 challenge ⇒ action = None | role_source = None     ← 零回归
```

**⇒ 「有钥匙的人可以不用钥匙进门」这个口子堵上了，且零回归成立。**

---

## 分析：为什么「软强制降权」优于「硬拒绝」

**硬拒绝的代价（我实测推演）**：`claim` / `reserve_scope` / `lock_acquire` 都是**流水线中段**。
若改成 `Err`，一个登记过公钥但忘了带票的 agent：
- 每一步**都失败**（连只读性的 `reserve_check` 也可能被扫到）
- 而失败原因（"你有钥匙"）与它正在做的事（认领任务）**看起来无关**
- ⇒ 排查成本高，且**整条流水线停摆**，直到它想起来补票

**降级的代价则精确**：
| 操作 | 硬拒绝 | 软降级 |
|---|---|---|
| 发布任务 | 失败 | 正常 |
| 领任务（Executor 级）| 失败 | **正常**（Executor 本来就能领）|
| 领高等级任务（RANK_GATE）| 失败，原因不明 | **失败，但正是该失败的地方** |
| 高权操作（Leader 级）| 失败 | **被拒，且 `+challenge_required` 明示原因** |

**⇒ 降级把「失败」推迟到「真正需要那个权限的那一刻」**，
而在那一刻，`+challenge_required` 让原因**自解释**。

**关键前提**：降级必须**可见**。若静默降权，调用方只看到「我怎么突然领不了了」——
那比硬拒绝更糟。所以 `auth_tag` 专门给 `challenge_required` 加了 `+challenge_required`。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | ✅ **已修（本单发现的真 bug）**：`claim` 曾在 schema 处先调 `judged_role_with_nonce` 渲染标签 —— 而它**验签通过就消费 nonce**。实测：`pre=challenge_verified` 但 `claim=challenge_replayed` ⇒ **回执说认证通过、行为却是未认证（假绿回执）**。已改为 `judged_role_with_challenge`（只验签不消费），并由锁 6 钉死 |
| **R2** | **challenge 表进程内** ⇒ 多实例部署不互通（既有限制）|
| **R3** | **公钥按 ns 隔离** ⇒ 在 ns-A 登记的钥匙在 ns-B 不算「有钥匙」，不触发降级 |
| **R4** | `execute` / `verify` 仍不接受 challenge ⇒ 这两条路径上「有钥匙不传」不会被降级（它们不走 `judged_role_gated`）|
| **R5** | ⚠️ **`@mooncry` 短 seed 不自洽（第二次踩到）**：`b"\x3a\x7f\x21\xb4"` 这类 <32 字节 seed，`ed25519_public_key` 与 `ed25519_sign` 生成的对**验签不过**。本单与 BUG-466 各踩一次，各耗 ~10 分钟。**建议上报**，并在测试里统一用 32 字节 seed |

---

## 关于「BUG-430 能关吗」

**技术层面：能关。** AGENTS.md 的关闭条件是
> 「存在至少一条『调用方无法自报』的路径」

现在满足，且比上一单更强：
- 有钥匙的 agent **不能再靠自报**（不传就降级）
- 承接路径产品面可达（BUG-466 的取票窗口）
- 失败/降级**可见**（`+challenge_required`）

**但我建议不关，改判为「S3 路径已完成，认证仍非默认」**，理由三条：

1. **R3 ns 隔离**：跨 ns 场景下「有钥匙」不被识别 ⇒ 降级不触发
2. **R4 两条路径未覆盖**：`execute` / `verify` 不走这条门
3. **默认仍不是 challenge**：没登记公钥的 agent（**当前绝大多数**）完全不受影响
   ⇒ 「认证」是**可选加入**的，不是**默认要求**

**⇒ 建议拆两步收口**：
- **BUG-430a / 430b 可标 FIXED**（路径存在 + 产品可达 + 有钥匙必须验签）
- **新开 BUG-430c**：`execute`/`verify` 接 challenge + ns 隔离下的钥匙识别 + 「默认要求认证」的迁移路径

---

## 建议入档位置

**判例候选**：
> **判例：软强制（可见降权）优于硬拒绝，前提是降级必须被看见。**
> 对「有资格却不按规矩来」的调用方，`Err` 会让整条流水线停摆且原因难查；
> **降权让失败精确地发生在「真正需要那个权限」的那一刻**。
> **但只有降级可见时才成立** —— 静默降权比硬拒绝更糟（"我怎么突然不行了"）。

**同族**：与 BUG-466「能力存在 ≠ 能力可达」一脉 ——
本条是「**能力可达 ≠ 能力被要求**」。

---

**提交**：`feat(authz)`。`AGENTS.md` 同批补 `+challenge_required` 说明。
