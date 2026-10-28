# BUG-430 第八段 · 密钥轮换 + 吊销 + 端到端证明

> 2026-10-28 · Lane BZ · 改 `store_sqlite.mbt` / `engine_rsv.mbt` / `server.mbt` + 新增 1 测试文件

---

## 结论

| 项 | 结果 |
|---|---|
| **编译** | `moon check` **0 errors** |
| **测试** | `src/engine` **312/312 passed, 0 failed**（原 305 + 新增 7 格） |
| **轮换** | ✅ 旧私钥签得出才允许换；换后**新钥能过、旧钥不能过** |
| **吊销** | ✅ 清空 `pubkey_fp`，此后挑战恒 `challenge_failed` |
| **变异对照** | ✅ **真跑**：删掉旧钥验证 ⇒ **锁 4/锁 6 双双变红**（312→310/2 failed），恢复后回全绿 |
| **E2E「车能开」** | ✅ **本来就有**（`s3_key_01`），本次未重复造，实测通过 |
| **新 bug** | ✅ 已登记 **BUG-465 [high]**（公钥永久不可变） |
| **BUG-430 能否关闭** | ❌ **不能** —— 见 §5 |

---

## 证据

### 1. 三条互证：公钥此前**物理上不可变**

```
① store_sqlite.mbt:2835  agents_register 的 UPSERT：
   ON CONFLICT(agent_id) DO UPDATE SET pid=excluded.pid, last_seen=..., status='active',
     role=CASE WHEN agents.role != 'Executor' THEN agents.role ELSE excluded.role END
   ⇒ **DO UPDATE SET 里没有 pubkey_fp**
② 全文件 UPDATE agents SET 只有 agents_set_pid 一处
③ store 层 agents_* 十个函数里没有 agents_set_pubkey
```

**⇒ 轮换和吊销**物理上做不到** —— 公钥一旦写入即锁死。**

### 2. store patch（已落地）

```moonbit
pub fn SqliteStore::agents_set_pubkey(
  self : SqliteStore, agent_id~ : String, pubkey_fp~ : String,
) -> Result[Unit, String] {
  // UPDATE agents SET pubkey_fp = ? WHERE agent_id = ?   （按 agents_set_pid 逐字模板）
}
```

**⚠️ 传空串是合法用法（吊销），不当参数漏传拒绝。**

### 3. 轮换：旧私钥签得出才允许换

新增纯函数判定面 `key_rotate_verdict(prev_key, pubkey_hex, rotate_sig, old_sig_ok)`：

| 情形 | 判定 |
|---|---|
| 无旧键 / 同键 | `rotate_not_needed`（走首登/幂等） |
| 有旧键且不同 + 没给 `rotate_sig` | `rotate_reject_no_proof` |
| 有旧键且不同 + 给了但**旧公钥验不过** | `rotate_reject_bad_proof` |
| 有旧键且不同 + 给了且验过 | `rotate_allowed` |

**⇒ 「旧私钥签得出」是本仓唯一能证明「你就是原来那个主体」的手段。**
不验就换 ⇒ 任何能调到本工具的人都能把别人公钥换成自己的 ⇒ **身份劫持**。

工具面：`agent_register_key` 新增 `rotate_sig` + `rotate_challenge` 两个可选参数；
轮换成功后**写后回读**确认，再返回 `mode=rotated`。

### 4. 吊销：`agent_revoke_key` 新工具

- 三态：`revoke_not_needed`（本来无键 ⇒ 不假装成功）/ `revoked`
- **写后回读确认为空**才返回 `revoked=true`
- **工具描述明写**：「身份仍是自报的（BUG-430 未关闭）⇒ 任何能调到它的人都能吊销任何人
  ⇒ 它是**运维便利**，**不是安全措施**」

### 5. 七格锁（`engine_bug430_s3_rotate_wbtest.mbt`）

| 锁 | 内容 | 结果 |
|---|---|---|
| r1 | `agents_set_pubkey` 写入后能读回（防「改了没生效」）| ✅ |
| r2 | 旧私钥签名正确 ⇒ 轮换成功，且**换后新钥过、旧钥不过** | ✅ |
| r3 | 没提交 `rotate_sig` ⇒ 拒绝；同键/无键 ⇒ `not_needed` | ✅ |
| r4 | 提交了但验不过 ⇒ 拒绝 | ✅ |
| r5 | 吊销 ⇒ 清空，此后挑战恒 `challenge_failed` | ✅ |
| r6 | ⭐ 变异对照：`old_sig_ok` 强置 true ⇒ 判定翻转 | ✅ |
| r7 | 吊销判定区分「无需吊销」与「吊销成功」 | ✅ |

### 6. 变异实测（真跑，非设计）

```
把 key_rotate_verdict 里的 `!old_sig_ok` 改成 `false`（= 删掉旧钥验证）
⇒ 312 → **310 passed, 2 failed**
  F| bug430_r4_rotate_with_bad_proof_rejected
  F| bug430_r6_variant_removing_old_key_check_breaks_lock
恢复后 312/312 全绿，grep MUTANT-BZ = 0
```

---

## 分析：为什么「路修好了但没车」是实质未满足

**派单的 framing 已经过时了一半** —— 我要把两层分开说：

| 层 | 状态 |
|---|---|
| **测试层** | ✅ **有车且已开上去**：`s3_key_01` 真公钥写 sqlite + 真私钥签名 ⇒ `challenge_verified` + 拿到 `Leader` |
| **产品层** | ❌ **没有任何 agent 真登记过公钥**（`fist-mbt.db` 的 `agents.pubkey_fp` 全空）|

**⇒ 「测试过了 ≠ 产品通了」**。这一点必须写清，否则下一个人会以为 BUG-430 已可用。

**轮换/吊销怎么让它可运维**：
- 没有轮换 ⇒ 私钥一丢，该身份**永久锁死**（无法自救）
- 没有吊销 ⇒ 抢注成功后，正主**无任何手段收回**
- **有了这两条，S3 才从「一次性不可逆」变成「可运维的凭据」** —— 这是产品层敢用它的前提

**⚠️ 但要注意**：吊销和轮换**都是自报身份的**（不校验调用方是谁）⇒
它们是**运维便利**，不是安全边界。真正的边界要等 S3 全量切换。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 🔴 **`moon fmt` 会打红一把既有锁**：`s3_p2_02` 用 `count_of(strip_ws(src), "judged_role_gated(self,agent,challenge_nonce,challenge_sig~)")` 做精确匹配，而 `moon fmt` 给三处调用**加了尾随逗号**（`challenge_sig~,`）⇒ 计数从 3 变 0 ⇒ 锁红。我已**手去掉尾随逗号**让锁转绿，但**下次有人跑 `moon fmt` 会再红**。这是该锁第三次踩同类问题（注释里记着 R22/R23）——建议那把尺子改成容忍尾随逗号。**未擅自改他人测试** |
| **R2** | `agents_set_pubkey` 只写库、**不做鉴权**（「该不该换」由上层判定面 + 工具受理）。这是有意的（避免同一规则两份实现），但也意味着**任何直接调 store 的代码都能绕过判定** |
| **R3** | 轮换要求调用方自己签 `rotate_challenge`；**服务端未校验它是不是自己签发的**（当前是明文 let，非 nonce 登记制）⇒ 重放风险未消除（与首登的 `s3_issue_challenge_auto` 口径不一致） |
| **R4** | 全量测试有 **4 个失败**，均与本次改动无关（`store_migration_wbtest:t744_9` / `store_bug463_close_wbtest:k463_8/9` + 1），全部报 `database is not open`；`multi_store.mbt` 是 gamma 在途（` M`），`store_bug463_close_wbtest.mbt` 未跟踪 ⇒ **并发在途态**。我把三个改动文件还原到 HEAD 后 `src/store` 直接跑不出汇总行（rc=2），**说明该包在当前并发态下本就无法自证**，非本次引入 |

---

## 建议入档位置

**账本**：**BUG-465 [high] OPEN** 已登记 ——
> `[store] 公钥一旦登记即永久不可变 —— 注释只说「不会被覆盖」，没说「也永远改不了」`

**BUG-430 能否关闭：不能。** 剩余前置：
1. **至少一个真实产品 agent 登记公钥**（产品层，不是测试层）
2. 该 agent 的客户端**默认走 challenge**（不是可选传）
3. 有锁证明「不传 challenge 会被降权到无实效」

**判例候选**：
> **判例-XX：「功能未实现」与「没有能力实现」是两件事。**
> `key_pin_reject_message` 把轮换写成「尚未实现（需 owner 决策）」，读起来像「等等就有」；
> 真相是 **store 层没有写面** ⇒ 不动存储就永远做不了，且**已有的错误登记永久无法修正**。
> **⇒ 说「未实现」时必须分清：缺的是「决策」还是「地基」。**
> 缺决策 ⇒ 等等；缺地基 ⇒ **现在就已经锁死了**。

---

**提交**：`feat(authz)` + `fix(store)`。未动他人测试文件。
