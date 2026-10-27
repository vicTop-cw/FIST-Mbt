# BUG-430 / S3 **第三段**：删 probe + 签名由调用方提交 · Lane BH · 2026-10-27

> **S3 骨架三段全通** —— 但 **`pubkey_fp` 的录入入口与 MCP `challenge` 入参仍在
> `server.mbt`（HumanSteward 面），我没改**。
> **⇒ S3 的「密码学骨架」通了，「接线到生产」还差两步。**
> 而且：**「有密码学」≠「密钥管好了」**。

---

## 一、结论

| 项 | 结果 |
|---|---|
| **`s3_last_sig_probe` 删了吗** | ✅ **已删**（代码里不存在；只剩注释里的历史说明）|
| **签名来源** | ✅ 改为**调用方提交**（`challenge_sig` 参数，透传到四门）|
| **公钥录入接线** | ⚠️ **部分**：`engine.agents_register` 早已收 `pubkey_fp~`，但**唯一写入点 `server.mbt:706` 恒传 `""`**（HumanSteward 面）⇒ **出 patch** |
| **MCP `challenge` 入参** | ❌ **未暴露**：四门 schema 全在 `server.mbt`（HumanSteward 面）⇒ **出 patch** |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | 全量 **1600/1600/0** |
| 变异对照 | **2 个变异真跑**，第 2 个**第一次没抓住**，补锁后才抓住（见 §3）|

---

## 二、证据

### 2.1 删掉 probe（不是填真签名）

```diff
-fn s3_last_sig_probe(eng : FistEngine, agent : String, nonce : String) -> String {
-  ignore(eng); ignore(agent); ignore(nonce)
-  ""
-}
```
**为什么不填真签名**：若服务端自己生成一个能验过的签名，等于**服务端自己给自己发通行证** ——
任何人都能过。**签名只能来自调用方私钥，服务端只负责验。**
这是 S3 的命门：**「签发」与「验签」必须在不同主体**。

### 2.2 签名由调用方提交（`challenge_sig`）

```moonbit
pub fn judged_role_with_challenge(
  eng : FistEngine, agent : String, challenge_nonce : String?,
  challenge_sig~ : String? = None,          // ← 第三段新增
) -> (String, String) {
  ...
  let verified = match (pubkey, challenge_sig) {
    (None, _) => false                       // 没登记公钥 ⇒ fail-closed
    (_, None) => false                       // 调用方没交签名 ⇒ fail-closed
    (Some(pk), Some(sig)) => verify_challenge_sig(pk, msg, sig)   // ← 真验
  }
```
**四门全部透传**：`rsv_set` / `rsv_try_set` / `locks_try_acquire` / `claim`
各加 `challenge_sig~ : String? = None`，逐级传到 `judged_role_gated` → `judged_role_with_challenge`。

### 2.3 五格锁

| 锁 | 断言 |
|---|---|
| `s3_p3_01` | **probe 已从代码消失**（只查非注释行 —— 见 §3 第一处踩坑）|
| `s3_p3_02` | 无签名/无公钥 ⇒ `challenge_failed`（fail-closed）|
| `s3_p3_03` | 底层真签真验：对签 true / 错钥 false / 换 nonce false |
| `s3_p3_04` | **零回归契约**：不传 `challenge_sig` ⇒ 与第二段行为一致；无挑战 ⇒ 原样返回 |
| **`s3_p3_05`** | ★ **实现路径格**：`judged_role_with_challenge` 必须把解出的 `sig` 传给 `verify_challenge_sig`（不许恒传空串）|

### 2.4 变异实测（第二个**第一次没抓住**，补锁后才抓住）

**变异 1：把 probe 加回代码**
```
汇总：Total tests 268 / passed 267 / failed 1
F| "s3_p3_01_sig_probe_is_gone"          ← 精确抓住
```

**变异 2：让上层忽略调用方签名（恒传空串）**
```
第一次尝试：268/268 全绿 —— **没抓住**
补锁 5 后重试：269 格 passed 268 / failed 1
F| "s3_p3_05_upper_layer_really_forwards_the_sig"   ← 精确抓住
```

---

## 三、分析 —— 两处我自己的实测教训

### 3.1 锁 1 第一次失败：**全文 contains 会命中注释**（判例-30 的反面）

我第一版写 `assert_false(src.contains("s3_last_sig_probe"))` ⇒ **红**。
因为**注释里还在讲「s3_last_sig_probe 已删除」这段历史** ——
**全文匹配把注释也算了**。

⇒ 改成**跳过注释行**再查。这是判例-30 的镜像：
判例-30 说「模式串自己就在文件里 ⇒ 恒绿」；这里是「**历史说明在注释里 ⇒ 恒红**」。
**两者同源：不分代码与注释的文本匹配都不算数。**

### 3.2 变异 2 第一次没抓住：**测了底层，没测上层接线**（判例-29）

我只写了锁 3（测底层 `verify_challenge_sig` 真签真验），
然后变异「让上层忽略 `challenge_sig`」⇒ **268/268 全绿**。

**根因**：内存引擎没有 sqlite ⇒ `declared_pubkey_for` 恒返回 `None`
⇒ **上层根本走不到验签分支** ⇒ 忽略签名也看不出来。

**⇒ 这正是判例-29「机制格 ≠ 实现路径格」**：测了 `verify_challenge_sig` 不等于测了
`judged_role_with_challenge` 有没有把它接上。
补 **锁 5（实现路径格）** 后，变异精确打红。

**这条比补锁本身更值钱**：如果一个 bug 我**先写变异、发现没红**，那就说明锁有洞 ——
**先跑变异再宣布完成，比设计完就交更有用。**

---

## 四、可粘贴 patch（两处，`server.mbt` 是 HumanSteward 面）

### 4.1 公钥录入（`server.mbt:706` 附近）

```diff
 ) -> Unit {
   let fp = agent_fp(raw_agent_id)
   ignore(eng.agents_acl_ensure(agent_id=fp, ns~, now~))
   ignore(
     eng.agents_register(
       agent_id=fp,
       agent_type~,
       role~,
       soldier~,
-      pubkey_fp="",
+      // BUG-430 S3 第三段：接线公钥录入（此前恒传 ""，是死承诺 —— BUG-403）
+      // 传空串 ⇒ 保持现有行为（该 agent 无法通过挑战认证，fail-closed）
+      pubkey_fp=pubkey_hex,
       pid=current_pid_token(),
       now~,
     ),
   )
 }
```
**配套**：该函数的签名加 `pubkey_hex~ : String = ""`（**可选，默认空 ⇒ 零回归**）。

### 4.2 四门 MCP schema 加 `challenge`（可选字段）

```diff
 # reserve_scope（server.mbt:5558 附近）
         "ttl_until": string_prop("TTL 截止时间戳（ISO-8601，必填）"),
+        // BUG-430 S3 第三段：可选挑战。不传 ⇒ 走原逻辑（零回归）
+        "challenge": string_prop(
+          "可选：S3 挑战 nonce。⚠️ 须配合 challenge_sig；不传则行为与旧版完全一致",
+        ),
+        "challenge_sig": string_prop(
+          "可选：对 challenge 的 Ed25519 签名 hex（128 字符）。⚠️ 服务端无法伪造，必须由调用方私钥产生",
+        ),
```
**四处同样处理**：`reserve_scope` / `lock_acquire` / `claim` / `execute`。
工具实现里从 `args` 取 `challenge` / `challenge_sig`，透传给对应引擎函数。

---

## 五、缺口与风险（S3 是否完全生效）

**S3 骨架三段全通，但「接线到生产」还差两步（都在 HumanSteward 面）**：

1. **公钥录入入口**（§4.1）—— 不做则**线上没有任何 agent 有公钥** ⇒ 传 challenge 一律 `challenge_failed`
2. **MCP `challenge` 入参**（§4.2）—— 不做则**调用方无法提交挑战** ⇒ 挑战机制形同虚设

**即使两步都做完，仍不是「完全关闭」**：
- **客户端签名**：调用方必须真持有私钥并签名（本仓只提供验签面）
- **密钥分发 / 轮换 / 吊销**：**这是之后真正的工程难点** ——
  「有密码学」≠「密钥管好了」。公钥泄露怎么办？私钥丢了怎么换？离职 agent 的密钥怎么吊销？
- **nonce 表是进程内的** ⇒ 多实例部署互不可见
- **`pubkey_fp` 若是历史短指纹** ⇒ 老 agent 全部 `challenge_failed`（需迁移方案）

---

## 六、建议入档位置

| 内容 | 位置 |
|---|---|
| S3 第三段 | BUG-430 挂 `- s3-phase3:`，**状态保持 OPEN** |
| **「签发与验签必须在不同主体」** | 判例集（本段删 probe 的核心理由）|
| **「全文 contains 会命中注释 ⇒ 自指假红」** | **判例-30 的镜像**（它是恒绿，这是恒红）|
| **「先跑变异再宣布完成」** | 本段 §3.2 的教训：变异 2 第一次没红，暴露了锁的洞 |
| 公钥录入 + MCP 入参两处 patch | BUG-430 正文「剩两步」，HumanSteward 应用 |
