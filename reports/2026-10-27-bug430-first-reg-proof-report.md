# BUG-430 / S3 第六段：首登也验签 —— 堵抢注 · Lane BS · 2026-10-27

> **抢注是永久性身份劫持**：一旦攻击者先登记，合法持有者来接入时验的是**攻击者的公钥**
> ⇒ 他永远通不过、攻击者永远通过。本段把这条路堵死。

---

## 一、结论

| 问题 | 我的回答 |
|---|---|
| **必填 vs 可选** | **两步流程 + 第二步必填 proof**（见 §3.1）。**依据：现网零调用方** |
| **challenge 从哪来** | ★ **必须服务端签发**（`s3_issue_challenge_auto`，进程级 `Ref` 单调计数器）。**调用方自选 = 等于没验**（见 §3.2）|
| 改了什么 | `agent_register_key` 改两步；引擎加 `s3_issue_challenge_auto` + `s3_challenge_counter` |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | 全量 **1665/1665/0** |
| 变异对照 | **2 个真跑**，各自精确打红 |

---

## 二、证据

### 2.1 ★ 关键判断：现网**零调用方** ⇒ 可以严格

```
$ grep -rn "agent_register_key" --include=*.mbt --include=*.py --include=*.json .
./cmd/cli/help_topics.mbt:76   ← 只是帮助文本里的工具名
（无任何代码/测试/脚本调用）
```
⇒ **不存在「破坏零回归」的问题**：把它改严格**不会让任何现有调用方失败**。

**代价对比**：
| 方案 | 堵抢注 | 破坏现网 | 结论 |
|---|---|---|---|
| `proof_sig` 可选 | ❌ 攻击者不传就绕过 | 无 | **等于没做** |
| `proof_sig` 必填（单步） | ✅ | 无（零调用方）| 但**无法表达「先拿 challenge」** |
| **两步流程（本单）** | ✅ | 无 | **选它** |

**为什么不是「单步必填」**：`proof_sig` 必须签在**服务端刚签发的 challenge** 上，
调用方第一次调用时**还没有**那个 challenge ⇒ 单步在逻辑上不成立。**两步是必然。**

### 2.2 可粘贴 patch

**引擎（`engine_rsv.mbt`）**
```diff
+/// 进程级单调计数器（用 Ref，MoonBit 顶层不允许 `let mut`）
+let s3_challenge_counter : Ref[Int32] = Ref(1)
+
+pub fn FistEngine::s3_issue_challenge_auto(self : FistEngine, agent : String) -> String {
+  let n = s3_challenge_counter.val
+  s3_challenge_counter.val = n + 1
+  self.s3_issue_challenge(agent, n)
+}
```

**工具（`server.mbt`）** — schema 加两字段
```diff
+        "challenge": string_prop(
+          "可选：第一步返回的挑战 nonce。**第二步必须原样带回来**。不传 ⇒ 只签发挑战、不改库"),
+        "proof_sig": string_prop(
+          "可选：用**私钥**对 `challenge` 签出的 Ed25519 签名 hex（128 字符）。与 challenge 同时传才算第二步；验不过一律拒绝"),
```

**工具实现**（在「首登锁定」检查之后、写库之前插入）
```moonbit
let challenge = get_str(args, "challenge")
let proof_sig = get_str(args, "proof_sig")
if challenge == "" {
  // ① 只签发挑战，**一个字节都不写库**
  let issued = eng.s3_issue_challenge_auto(agent_id)
  return Ok(... { "mode": "challenge_issued", "challenge": issued,
                  "registered": false,
                  "note": "尚未登记。本回执只是挑战，需带 proof_sig 第二次调用才落库" })
}
if proof_sig == "" {
  return Err("…传了 challenge 却没传 proof_sig…否则任何人可替他人首登（抢注）")
}
// ② 验签：公钥 = 本次要登记的那把；消息 = challenge 原文
if !@engine.verify_challenge_sig(pubkey_hex, challenge, proof_sig) {
  return Err("**首登验签失败** …")
}
// ③ 验过才落库
agent_touch_first_seen(eng, agent_id, ns, "key-registration", "Executor", "工兵", pubkey_hex~, ts)
```

### 2.3 七格锁 + 两个变异（**都真跑**）

**工具层（`server_bug430_first_reg_proof_wbtest.mbt`）**

| 锁 | 断言 |
|---|---|
| `bs_01` | 第一步只签发挑战、`mode=challenge_issued`、**`registered: false`**、签发在写库之前 |
| `bs_02` | 传 challenge 不传 proof ⇒ 拒绝 |
| **`bs_03`** | ★ **验签硬门**：`verify_challenge_sig(pubkey_hex, challenge, proof_sig)` + 拒绝文案 + **验签在写库之前** |
| **`bs_04`** | ★ **challenge 服务端签发**：用 `s3_issue_challenge_auto` + 引擎侧 `Ref` 计数器**有递增** |

**引擎层（`engine_bug430_first_reg_proof_wbtest.mbt`）**

| 锁 | 断言 |
|---|---|
| **`bs_v1`** | ★ **攻击者不能替受害者首登**：用攻击者私钥签 ⇒ 对受害者公钥验**不过**；受害者自己签 ⇒ 通过 |
| `bs_v2` | 空签名 / 坏 hex / 换 challenge ⇒ 全 fail-closed |
| `bs_v3` | 两次签发 **nonce 不同**、绑定 agent、可一次性消费、二次消费失败 |

**变异实测**：

| 变异 | 结果 |
|---|---|
| **M1** 删掉验签硬门（`if !verify { return Err }` 整段）| **455/456**，**只有 `bs_03` 红** |
| **M2** `challenge` 改成接受调用方自选 | **454/456**，`bs_01` + `bs_04` 红 |

---

## 三、分析

### 3.1 为什么抢注比「没有认证」更糟

**没有认证**：攻击者只能**当场**自称 X。X 一接入，冒充就露馅，且**每次都要重试**。

**抢注**：攻击者先替 X 登记**自己的**公钥 ⇒
- X 真来接入时，服务端验的是**攻击者的公钥** ⇒ **X 永远通不过**
- 攻击者**永远通过**
- 且第五段的「首登锁定」让 **X 自己也没法改回来** ⇒ **永久劫持**

**⇒ 这是不可逆的**：没有认证是「每次都能试」，抢注是「**一次得手，永久占用**」。

### 3.2 为什么 challenge **必须**服务端签发

`issue_challenge_nonce(agent, counter)` 是**纯函数** —— 同输入必同输出。

⇒ 若 counter 由调用方给：攻击者可以**离线预计算** `fist-s3-challenge:v1:X:1`，
**提前签好**，然后任何时候提交都验得过。
**「挑战」退化成固定字符串 ⇒ 验签形同虚设**，而所有「验签代码都在」的检查**依然全绿**。

⇒ 所以计数器必须由服务端**单调递增地选**（`s3_issue_challenge_auto`），
且 `bs_04` 专门钉「引擎侧计数器真的在递增」——
**这条不钉住，前面几条锁都可以在「验签失效」的情况下保持绿色。**

---

## 四、缺口与风险

1. **nonce / 计数器都是进程内的** ⇒ 多实例部署时：
   - 各实例各发各的 challenge，**只在签发它的实例上可验**（调用方需重试到同一实例）；
   - **真正的分布式唯一性需要落库**（`store_sqlite.mbt`，HumanSteward 面）。
2. **首次登记后仍不能换钥**（第五段的首登锁定）⇒ 私钥丢失 = 该 agent 永久锁死。
   **轮换仍需做**：现在首登有验签了，轮换可以复用同一套（新钥签「旧钥+新钥」或「nonce」）。
3. **无吊销面**：被盗私钥无法吊销（且因首登锁定，也换不了）。
4. **本单未改 `server_bug455_pure_wbtest.mbt` 等他人文件**；期间多次遇并发 lane 编译中断，
   均等待收口后重跑，**未使用 `--no-verify`**。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| S3 第六段 | BUG-430 挂 `- s3-first-reg-proof:`，**保持 OPEN** |
| **「抢注 = 不可逆身份劫持」** | 判例集：与「错误结论 > 查不到」并列的**不可逆性**分级 |
| **「challenge 必须服务端签发，否则验签全绿而无效」** | 判例集（`bs_04` 是这条的锁）|
| **「现网零调用方 ⇒ 可以改严格」** | 本单 §3.1 的决策依据，建议写进 BUG-430 正文 |
| 下一步：轮换（复用首登验签） | 优先级仅次于 nonce 落库 |
