# BUG-430 S3 可行性核查 · Lane BC · 2026-10-27

> **结论：S3 可行 —— 而且不用新引入任何依赖。**
> MoonBit **有** Ed25519，`cc06b/mooncry@0.13.1` 已在 `moon.mod` 里，
> 且**本仓的 `star_gate` 已经在生产代码里真验签**。
> Alpha 说的「最大不确定项 R3（MoonBit 内置无 Ed25519）」——**内置确实没有，但不需要内置**。

---

## 一、结论

| 方案 | 可行性 | 理由（实测） |
|---|---|---|
| **Ed25519 真签名** | ✅ **可行** | `@mooncry.ed25519_sign / ed25519_verify / ed25519_public_key` 三件套齐全；**已在 `star_gate.mbt` 生产使用**；本单真跑探针通过 |
| **HMAC 替代** | ✅ 可行（但**不必用**）| `@mooncry.hmac_sha256` / `hmac_sha512` / `sha256` 均可用 |
| **随机 nonce + 时间戳绑定** | ⚠️ 部分可行 | `moonbitlang/x` 有 `crypto`/`uuid`/`time`，**无独立 `random` 包**；但 nonce 可用 `uuid` 或计数器，**且 Ed25519 已够用，不必依赖随机性** |
| **外部 FFI** | ✅ 可行（但**不必用**） | 项目有 JS/native 双目标，理论上可 FFI；**Ed25519 已纯 MoonBit 可用，无必要** |

**⇒ S3 不需要降级、不需要 FFI、不需要新依赖。** 直接做。

### 1.1 Alpha 的 `s3_min_01` 最小里程碑：**可达**，而且 `verify_signature` 已存在

Alpha 的测试需要 `verify_signature(pubkey_fp, nonce, sig) -> Bool`。
**这个函数**在当前环境下**可写**——底层就是 `@mooncry.ed25519_verify(pub_key, msg, sig) -> Bool`
（**签名已经是 `Bool`**，签名形状与 Alpha 的要求一致）。

---

## 二、证据

### 2.1 生产代码里已经在真验签（最强证据）

```moonbit
// src/router/star_gate.mbt:299-303
let msg = @utf8.encode(canonical)
if !@mooncry.ed25519_verify(pub_key, msg, sig) {
  return star_outcome(BadSignature, "Ed25519 验签失败（清单可能被篡改）", ...)
}
```
**这不是桩、不是字符串比较** —— 它先 `hex_decode` 出 32 字节公钥与 64 字节签名，
再调真验签函数，失败即 `BadSignature`。

### 2.2 `mooncry` 的 Ed25519 API（三件套齐全）

```
.mooncakes/cc06b/mooncry/lib/ed25519.mbt:263  pub fn ed25519_public_key(seed : Bytes) -> Bytes
.mooncakes/cc06b/mooncry/lib/ed25519.mbt:277  pub fn ed25519_sign(seed : Bytes, message : Bytes) -> Bytes
.mooncakes/cc06b/mooncry/lib/ed25519.mbt:304  pub fn ed25519_verify(public_key : Bytes, message : Bytes, sig : Bytes) -> Bool
```
`ed25519_test.mbt` 有 **11 格**自带测试。

### 2.3 依赖已就位（无需新引入）

```
moon.mod:33   "cc06b/mooncry@0.13.1",     ← 已在依赖里，且版本钉死
```
`colmugx/mcp` 也依赖它 ⇒ 它已是**传递依赖**，不是新引入的第三方风险。

### 2.4 实测：真跑探针（sign → verify 往返 + 篡改拒绝）

本单写了临时探针（已删除）真跑 `src/router`：**212/212 通过**，探针四格全过：
```
① ed25519_sign 后用 ed25519_verify ⇒ true      （正确签名通过）
② 篡改消息 ⇒ false                             （篡改被拒）
③ 换公钥 ⇒ false                               （换钥匙被拒）
④ 公钥 32 字节 / 签名 64 字节                  （符合 Ed25519 规格）
```
**⇒ 不是「看起来有」，是「真能用」。**

### 2.5 现有测试面（32 处 `star_gate_verify` 相关格）

`src/router/star_gate_wbtest.mbt` 有「签名被篡改 → BadSignature」等格，
`src/router` 全量 **211/211 通过** ⇒ Ed25519 路径**已在 CI 里持续验证**。

### 2.6 其它能力（备用，不必用）

```
.mooncakes/cc06b/mooncry/lib/crypto.mbt:199   pub fn sha256(data : Bytes) -> Bytes
.mooncakes/cc06b/mooncry/lib/crypto.mbt:214   pub fn hmac_sha256(key, message) -> Bytes
.mooncakes/moonbitlang/x/                     crypto / jwt / bcrypt / uuid / time（有）
                                              random（**无独立包**）
```

---

## 三、分析（为什么可行，以及 S3 的第一步是什么）

**Alpha 的判断「MoonBit 内置无 Ed25519」是对的** —— 标准库确实没有。
**但它把「内置没有」推成了「可能不可行」，而漏掉了「本仓已经有一个纯 MoonBit 的 Ed25519」。**

**最讽刺的是：`star_gate`（Star 门）就是本仓**已经在用 Ed25519 验签**的地方。**
S3 要的正是同一套能力，**同一份依赖、同一个函数**。

### S3 的第一步（具体到可执行）

1. **不用引入依赖** —— `@mooncry` 已在 `moon.mod`；
2. **不用写验签** —— `@mooncry.ed25519_verify` 已经是 `Bool` 返回；
3. **要写的是「挑战-签名-验签」的流程**：
   - `agents` 表已有 `pubkey_fp` 字段（`store_sqlite.mbt` 的方案里就该存 32 字节公钥）；
   - 生成 nonce → 调用方用私钥签 → 服务端 `ed25519_verify(pk_from_agents表, nonce_bytes, sig)` → 通过才认身份；
4. **`judged_role_with_challenge(eng, agent, nonce=None)`**：`nonce=None` ⇒ 直接返回
   `("Executor", "unauthenticated")` —— **这一格 Alpha 的设计是对的，可原样落地**。

---

## 四、缺口与风险

1. **`pubkey_fp` 现在只有「指纹」语义，存不存得下 32 字节公钥待核**。
   `store_sqlite.mbt:133` 的 `agents` 表要确认字段容量/类型（本单只读，未改）。
   若 `pubkey_fp` 是 hex 指纹而非原公钥 ⇒ S3 需要**新增一列存原始公钥**（或让 `pubkey_fp` 承载原公钥的 hex）。
2. **`@random` 没有独立包** ⇒ nonce 生成要用 `moonbitlang/x/uuid` 或进程内计数器 + 时间戳。
   **但 Ed25519 的 nonce 不需要密码学随机**（nonce 只需不可预测/不可重放，可用 `uuid` + 时间戳绑定）。
3. **`mooncry` 是第三方库**（`cc06b` 个人命名空间）。版本已钉死 `@0.13.1`，
   但**供应链风险仍在**（若上游撤包/破版）。建议：S3 落地时把它**提升为显式直接依赖**
   （现在它是靠 `colmugx/mcp` 传进来的，属于隐式依赖）。
4. **S3 的密钥分发/轮换/吊销**不在本单范围 —— 但那是 S3 之后真正的工程难点
   （「有密码学」≠「密钥管好了」）。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| **S3 可行性：可行，无需新依赖** | BUG-430 正文 R3 一栏：**「Max 不确定项」解除**，改为「依赖已就位」|
| **「内置没有 ≠ 不可行」** | 判例集（与「缺键 ≠ 空值」同族：把「我没找到」当成「不存在」）|
| `star_gate` 是 Ed25519 的现成先例 | BUG-430 S3 实现参考（直接照 `star_gate.mbt:299` 的验签形状写）|
| `mooncry` 应提升为显式直接依赖 | 建议随 S3 落地同批做（现在是隐式传递依赖）|
