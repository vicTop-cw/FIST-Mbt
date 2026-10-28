# R1 + R3 收口（Lane BZ 第九段）

> 2026-10-28 · `fix(test)` + `fix(authz)`

---

## 结论

| 项 | 结果 |
|---|---|
| **R1 修了几处** | **1 处**（`s3_p2_02` 的 `n_gated` 断言；R22 修过的那处早已用 `strip_ws`，无需再动） |
| **fmt 后还红吗** | ✅ **不红了** —— `moon fmt` 连跑 + 测试**两次连发 314/314** |
| **R3 怎么改的** | 轮换改**两阶段**：① 不带 `rotate_sig` ⇒ 服务端 `s3_issue_challenge_auto` 签发挑战（不写库）；② 带回 ⇒ **先 `s3_consume_nonce`（一次性）再验签** |
| **变异对照** | ✅ **真跑**：把 `s3_consume_nonce` 改成恒 true ⇒ **314 → 308/6 failed**，`r8`/`r9` 双双红；恢复后 314/314 |

---

## 证据

### R1：尺子不再跟 fmt 打架

**改前**（`engine_bug430_s3_p2_wbtest.mbt`）：
```moonbit
let n_gated = count_of(
  strip_ws(src_rsv),
  "judged_role_gated(self,agent,challenge_nonce,challenge_sig~)",   // ← 带右括号
)
```
**`moon fmt` 会把长调用折行并补尾随逗号** ⇒ 实际产物是 `...challenge_sig~,` ⇒
**精确匹配计数 3 → 0 ⇒ 锁红**。

**改后**：
```moonbit
"judged_role_gated(self,agent,challenge_nonce,challenge_sig~",      // ← 去掉右括号
```

**⇒ `challenge_sig~)` 与 `challenge_sig~,` 两种形态都命中**，
而「函数名 + 四个参数顺序」这个**代码形态**仍被钉住
（判例-30 防护不变：注释里的同名串不带 `(self,agent,...)` 这个参数序列仍不会命中）。

**这是第三次同类**（注释记着 R22/R23，前两次只修了 `engine.mbt` 那处、漏了 `engine_rsv.mbt` 这三处）。

**fmt 实测（裁决特别要求）**：
```
$ moon fmt          → Finished
$ moon check        → 0 errors
$ 测试 第 1 次       → Total tests: 314, passed: 314, failed: 0
$ 测试 第 2 次       → Total tests: 314, passed: 314, failed: 0
```
**⇒ 修完跑 fmt 真的不再红（连发两次确认）。**

### R3：轮换也走服务端签发的挑战

**改前**：`rotate_challenge` 由调用方传 ⇒ 服务端**只验签、不校验它是不是自己签发的**。

**改后（两阶段，与首登同形）**：

```
① pin == reject_different 且 rotate_sig == ""（= 调用方在要挑战）
   ⇒ eng.s3_issue_challenge_auto(agent_id) 签发（进程级单调递增计数器）
   ⇒ 回执 mode="rotate_challenge_issued"，**一个字节都不写库**
   ⇒ 回执里给 how_to_continue（用旧私钥签、连同 challenge 再调一次）

② 带回 rotate_sig + rotate_challenge
   ⇒ **先 s3_consume_nonce(agent_id, rotate_challenge)**（一次性消费）
       · 不是本服务签发 / 已消费过 ⇒ false ⇒ 一律不认（fail-closed）
   ⇒ 再 verify_challenge_sig(旧公钥, rotate_challenge, rotate_sig)
```

### 新增两格锁

| 锁 | 内容 |
|---|---|
| **r8** | 服务端签发的 nonce ⇒ 消费第 1 次 true、**第 2 次 false（防重放）**、**自造 nonce ⇒ false（不认）** |
| **r9** | 端到端：`s3_issue_challenge_auto` 签发 → 旧私钥签 → 消费 → 重放必拒 → 换钥落地 |

### 变异实测（真跑）

```
把 s3_consume_nonce 改成恒 return true（= 不校验签发/一次性）
⇒ 314 → **308 passed, 6 failed**
  F| bug430_r8_rotate_challenge_must_be_server_issued
  F| bug430_r9_rotate_consumes_server_issued_challenge
恢复后 314/314 全绿，grep MUTANT-BZ = 0
```

---

## 分析：为什么「挑战必须服务端签发」要用在自己的轮换上

**上一轮我在首登那段写了这条原则**：

> `issue_challenge_nonce(agent, counter)` 是**纯函数** ⇒ 调用方能离线预计算 nonce、
> 提前签好，任何时候提交都成立 ⇒「挑战」退化成固定字符串 ⇒ **验签形同虚设**。
> 所以计数器由 `s3_issue_challenge_auto` 在服务端单调递增地选。

**而我自己写轮换时，却让 `rotate_challenge` 由调用方传。** 同一个漏洞：

```
攻击者：离线算出 nonce N，用旧私钥签好 sig（或骗取一次签名）
      ⇒ 之后任何时刻提交 (N, sig) 都成立
      ⇒ 「旧私钥证明」被架空
      ⇒ 轮换通道形同虚设（攻击者拿到了旧私钥的一次签名就能永久换钥）
```

**⇒ 这不是「漏了个校验」，是「同一原则没在自己身上执行」。**
写安全原则时最容易犯的错是：**给别人写规则时想得很细，轮到自己实现时忘了同一条**。

**另一层：`s3_consume_nonce` 的「一次性」还额外挡住重放** ——
即使 challenge 是服务端签发的，不消费它就可以无限次用同一份签名重试。
**「服务端签发」防预计算，「一次性消费」防重放，两条缺一不可。**

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 已修并有 fmt 后连发验证。**但同类风险仍在**：其他测试文件里若还有「精确匹配调用形」的断言，下次 fmt 仍会咬。本次只修了 `s3_p2_02` 的 `n_gated`（R22 已修 `judged_role_with_nonce` 那处）。**建议后续把「源码形状锁」统一改成 `strip_ws` + 去尾括号口径** |
| **R2** | `agents_set_pubkey` 不鉴权（有意，避免规则两份实现），但直接调 store 的代码可绕过判定面 |
| **R5** | 轮换的 pending nonce 表是**进程内**的（与首登同）⇒ 多实例部署时 A 实例签发的 challenge 在 B 实例消费不掉。这是既有限制，本段未扩大也未修复 |
| **R6** | **未核**「吊销后再登记」的完整链路（吊销 ⇒ 空 key ⇒ 再登记走首登，需新私钥带 proof_sig）—— 逻辑上成立，但没有专门锁 |

---

## 建议入档位置

**判例候选**：
> **判例-XX：给别人的安全规则，必须同样用在自己身上。**
> 我在首登那段写下「挑战必须服务端签发，否则验签形同虚设」，
> 紧接着自己实现轮换时却让调用方传 `rotate_challenge` —— **同一个漏洞，隔了 30 行**。
> **⇒ 写安全原则时立刻问一句：「这条规则，我自己刚写的这个新分支满足吗？」**
> 凡在注释里写下「必须 X 否则 Y」的地方，都要在同一笔里检查新代码是否违反它。

**另一条（R1 的教训）**：
> **判据不要钉「格式化后的字面形状」，要钉「语义形态」。**
> 源码形状锁写死带右括号的调用形 ⇒ `moon fmt` 一补尾随逗号就红。
> 同一个坑咬过三次（R22/R23/R24）⇒ **写形状锁时就按「fmt 会怎么改」来设计**。

---

**提交**：`fix(test)`（R1）+ `fix(authz)`（R3）。
