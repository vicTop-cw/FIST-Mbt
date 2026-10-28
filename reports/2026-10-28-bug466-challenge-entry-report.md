# BUG-466：S3「取票窗口」+ claim 接 challenge

> 2026-10-28 · Lane CE

---

## 结论

| 项 | 结果 |
|---|---|
| **`agent_issue_challenge`** | ✅ **新增**，只给已登记公钥的 agent 签发；未登记 ⇒ `Err` |
| **`claim` 接 challenge** | ✅ **schema 已补**（引擎层本来早就接了，只是没声明）|
| **产品面真能走吗** | ✅ **用真实 MCP 客户端走通**：`claim` 回 `action = '+challenge_verified'` |
| **零回归** | ✅ 不带 challenge ⇒ 回执**无 `action` 键**（与修前逐字相同）|
| **变异对照** | ✅ **真跑**：删掉验签 ⇒ **320 → 316/4 failed**，锁 5 必红；恢复后 320/320 |
| **测试** | engine **320/320** ｜ server **515/515** |

---

## 证据

### 关键发现：`claim` 的引擎层**早就接了**

```moonbit
// engine.mbt:153  FistEngine::claim 签名里已有：
challenge_nonce~ : String? = None,
challenge_sig~ : String? = None,
// 内部：judged_role_with_nonce(challenge_nonce, challenge_sig)
```

**⇒ 缺的只是 schema 声明**（`fist.py` 依据 inputSchema 拒收）+ `action` 面。
这解释了为什么「引擎层能过、产品面用不了」——**接口声明与实现分叉**。

### 三处改动

**① 新工具 `agent_issue_challenge`**
- 校验 `agents_get(fp).pubkey_fp` 非空，**否则直接 Err**（签了也验不过）
- 复用 `s3_issue_challenge_auto`（与首登/轮换**同源**，服务端单调递增）
- **不写业务库**，只签发并登记「待消费」

**② `claim` schema 补两个参数** + 回执加 `action` / `role_source`
- 复用 `opt_challenge(args)`（与 `reserve_scope`/`lock_acquire` **同一套**）
- 用 `@engine.auth_tag` 渲染标签（BUG-453 已有的单一真源）

**③ 消 `unregistered+` 误读** —— 选 **(b) 拆维度**

```moonbit
"unregistered" + ... + src_tag +
  (identity 维度段: +identity_verified / +identity_unverified / +identity_self_reported)
```

**为什么追加而不改写**：`unregistered` 前导词有**精确相等**的既有断言
（`lock_perm_wbtest.mbt:104`），改写会打红那些门。追加自解释段既消误读又零回归。

### 六格锁（`engine_bug466_challenge_entry_wbtest.mbt`）

| 锁 | 内容 | 结果 |
|---|---|---|
| c1 | 已登记 ⇒ 拿到的 challenge 能验签通过 | ✅ |
| c2 | 未登记 ⇒ 签了也 `challenge_failed`（fail-closed）| ✅ |
| c3 | **一次性**：消费后重放 ⇒ `challenge_replayed` | ✅ |
| c4 | 无 challenge ⇒ 原逻辑（与 `judged_role_gated(None)` 逐字相同）| ✅ |
| c5 | ⭐ **变异对照**：错签名必 `challenge_failed` | ✅ |
| c6 | identity 维度三态映射互不相同 | ✅ |

### 变异实测（真跑）

```
把 `(Some(pk), Some(sig)) => verify_challenge_sig(pk, msg, sig)`
改成 `=> true`（= 删掉验签）
⇒ 320 → **316 passed, 4 failed**
  F| bug466_c5_variant_removing_verify_flips_result
恢复后 320/320 全绿，grep MUTANT-CE = 0
```

### 产品面真跑（同一 server 进程，`temp/ce/e2e_full.py`）

```
① store_open              ⇒ opened
②-1 agent_register_key    ⇒ challenge_issued
②-2 带 proof_sig          ⇒ registered, persisted_pubkey_matches=true
③ agent_acl_grant         ⇒ can_write=true
④ agent_issue_challenge   ⇒ challenge + pubkey_registered=true   ← 取票窗口
⑤ publish                 ⇒ T0
⑥ claim(带 challenge)     ⇒ action = '+challenge_verified'  ← S3 真活了
⑦ claim(不带 challenge)   ⇒ action = None，回执无 action 键     ← 零回归
```

**⇒「手工拼 nonce」不再是唯一方式。真实客户端现在能取票。**

---

## 分析：为什么「取票窗口」是 S3 可用的最后一环

S3 的验证链是 **签发 → 签名 → 验签 → 消费**。
前八段把「签名/验签/消费」都做完了，**唯独「签发」只有内部调用者够得着**
（`agent_register_key` 首登/轮换分支）。对已登记 agent，签发端是**死路**：

```
已登记 agent 想认证
  ⇒ 需要 challenge
  ⇒ 只有 agent_register_key 能签发
  ⇒ 但对已登记者它只回 already_registered
  ⇒ 只能自己构造 nonce（我上一单就是这么过的）
```

**⇒ 这不是「可选 vs 默认」的问题，是「可选也不可选」。**
一条安全路径如果**只有知道内情的人手工构造输入才能走**，它在工程上等于不存在。

装上取票窗口后，链条才完整：**任何人都能让服务端签发一个只有自己私钥能用的票**。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 🔴 **challenge 表是进程内的** ⇒ A 进程签发的票 B 进程消费不掉。多实例部署需落库（既有限制，本单未扩大）|
| **R2** | **公钥按 ns 隔离**：在 ns-A 登记的公钥，在 ns-B 签不出票。这是我实测踩到的真实约束，已在工具文案写明 |
| **R3** | `execute` / `verify` **仍不接受 challenge** —— 本单只做了 `claim`（派单范围）。它们是否该认证需另判 |
| **R4** | `identity_*` 维度段只在 `rsv_try_set` 的 `unregistered` 分支；`reserved`/`renewed` 等路径未加（避免扩大改动面）|
| **R5** | 首次 E2E 出现过 `registered:false` 但 `mode=registered` —— 根因是**测试夹具**（我手删了表行但没清 `pubkey_fp`），不是产品 bug；已用全新库复测两轮确认 |

---

## 建议入档位置

**账本**：**BUG-466** 可标 FIXED（两个工具面缺口都补上，产品面实测走通）。

**判例候选**：
> **判例：接口声明与实现分叉 —— 「引擎层接了」不等于「工具面能用」。**
> `claim` 的引擎层**早在第二段就接了** `challenge_nonce` / `challenge_sig`，
> 但 tool `schema` **没有声明这两个参数** ⇒ `fist.py` 依据 inputSchema 直接拒收
> ⇒ 调用方**永远够不到**那段已实现的逻辑。
> **⇒ 加参数必须改两处：引擎签名 + schema**。只改前者，功能「存在但不可达」；
> 只改后者，参数「收下就丢」（BUG-440「声明了但没接线」的反向形态）。

**同族**：与 BUG-466 的「取票窗口」是同一枚硬币 ——
**「能力存在」与「能力可达」是两件事**（延续判例-29/32/33/34 一脉）。

---

**提交**：`feat(authz)`。同批改 `AGENTS.md` 工具表（审计与权限 5→6，新增一行）+ 格数。
