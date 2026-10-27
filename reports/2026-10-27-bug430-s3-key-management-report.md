# BUG-430 / S3 **第四段**：密钥管理 —— 公钥录入 + 端到端可用 · Lane BK · 2026-10-27

> **S3 现在真的能用了**：有公钥的 agent 能通过 `challenge` 认证拿到真角色。
> **但 BUG-430 仍 OPEN** —— 密钥分发 / 轮换 / 吊销还没做。
> **「有密码学」≠「密钥管好了」。**

---

## 一、结论

| 项 | 结果 |
|---|---|
| 选方案 | **B**（新建 MCP 工具 `agent_register_key`），**不是 A** —— 理由见 §3.1 |
| 录入公钥的 agent | **任意数量的 agent 都可经该工具录入**（不再「零个 agent 有公钥」）|
| 客户端签名工具 | **不提供服务端签名**；提供**测试夹具 + 文档说明**（见 §2.3）|
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | 全量 **1612/1612/0** |
| 门禁 | `check_tools_sync` **PASS** / `check_plugin_sync` **PASS** |
| 变异对照 | **2 个真跑**；第 2 个**第一次没抓住**，补锁后才抓住（见 §2.5）|
| BUG-430 | **仍 OPEN** |

---

## 二、证据

### 2.1 为什么选 B（不是 A）

派单说「A 首选，如果调用点已存在的话」。**实测发现 A 不成立**：

`agent_touch_first_seen` 已在（`server.mbt:692`），且**已有 `pubkey_hex~` 参数**
（`dc8ef707` 接的线）。**但它的三个调用点全在业务路径上**：
- `claim`（`server.mbt:2008` 附近）
- `execute`（`server.mbt:2103` 附近）

**在这些路径上塞 `pubkey_hex` 有致命问题**：**每次 claim/execute 都会重写公钥** ⇒
`pubkey_hex` 缺省 `""` ⇒ **每次认领都把已登记的公钥抹成空串** ⇒ 认证被自己抹掉。
⇒ **A 不仅不简单，还会主动破坏已登记的密钥。**

**⇒ 选 B**：独立工具，只在「专门登记公钥」时写，不与业务路径共用一个写口。

### 2.2 新工具 `agent_register_key`（`server.mbt`）

```moonbit
fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
  let agent_id = get_str(args, "agent_id")
  let ns = get_str(args, "namespace")
  let pubkey_hex = get_str(args, "pubkey_hex")
  if agent_id == "" || ns == "" { return Err(...) }
  // ① 形状校验：必须是 32 字节合法 hex —— **落库前拒**
  let pk = match @mooncry.hex_to_bytes_or(pubkey_hex) { Ok(b) => b ; Err(e) => return Err(...) }
  if pk.length() != 32 { return Err(...) }
  let eng = match engine_for_ns(ns) { Ok(e) => e ; Err(m) => return Err(m) }
  let fp = agent_fp(agent_id)
  // ② 复用既有首拍注册路径（ON CONFLICT 幂等）——不新造第二条「注册」真源
  agent_touch_first_seen(eng, agent_id, ns, "key-registration", "Executor", "工兵", pubkey_hex~, ts)
  // ③ 写后回读：回执不许由请求反推（BUG-145 同口径）
  let stored = ... s.agents_get(fp) ... a.pubkey_fp
  let ok = stored == pubkey_hex && pubkey_hex != ""
  Ok(... { "registered": ok, "persisted_pubkey_matches": ok, "pubkey_hex_prefix": ... })
}
```

**要点**：
- **落库前校验 32 字节形状** —— 坏公钥进库后症状是「该 agent 永远认证失败」，只有
  `challenge_failed`，极难反查到「当初公钥录错了」
- **写后回读**：`registered` 由库里读回值决定，不由请求反推
- **复用既有注册路径**：不新造第二条真源（判例-29 的反面）

### 2.3 客户端签名工具：**服务端不提供**

**服务端代签 = 自己给自己发通行证 = 绕过 S3。** 所以只提供：

**① 文档（给客户端看）**：
```
1. agent_register_key(agent_id="lane-x", namespace="default", pubkey_hex=<你的公钥hex>)
2. 取 nonce：服务端 issue_challenge_nonce(agent, counter) 产出
   "fist-s3-challenge:v1:<agent>:<counter>"
3. 用自己的**私钥**签：sig = Ed25519Sign(privkey, utf8(nonce))，转 hex
4. 调 reserve_scope / lock_acquire / claim 时带 challenge=<nonce> + challenge_sig=<sig>
```
**② 测试夹具**（`engine_bug430_s3_key_wbtest.mbt` 里，**仅供测试**）：
```moonbit
fn s3_key_sign(nonce : String) -> String {   // ⚠️ 测试专用，生产绝对不许有
  @mooncry.bytes_to_hex(@mooncry.ed25519_sign(s3_key_seed(), @utf8.encode(nonce)))
}
```

**锁 `s3_keytool_04` 钉住**：`server.mbt` 的代码面里**不许出现 `ed25519_sign`**。

### 2.4 端到端锁（`engine_bug430_s3_key_wbtest.mbt`，4 格）

| 锁 | 断言 |
|---|---|
| **`s3_key_01`** | ★ **有公钥 + 真签名 ⇒ `challenge_verified` 且拿到 `Leader` 角色**（端到端）|
| `s3_key_02` | 没公钥 ⇒ `challenge_failed`（fail-closed）|
| `s3_key_03` | 换别人私钥签 ⇒ `challenge_failed` |
| `s3_key_04` | `pubkey_fp` **真的落库并可逐字读回** |

**锁 1 是真的端到端**：公钥**真写进 sqlite 的 agents 表**（不是打桩），
`declared_pubkey_for` 真读回，`verify_challenge_sig` 用 `@mooncry.ed25519_verify` 真验。

### 2.5 变异实测（**第二个第一次没抓住**）

**变异 1：`declared_pubkey_for` 恒返回 `None`（公钥录入被删）**
```
273 格 passed 272 / failed 1
F| "s3_key_01_agent_with_key_can_pass_challenge"      ← 精确抓住
```

**变异 2：`agent_touch_first_seen` 里 `pubkey_fp=pubkey_hex` 改回 `""`**
```
第一次：424/424 全绿 —— **没抓住**
补锁（server_bug430_s3_keytool_wbtest.mbt）后：428 格 passed 427 / failed 1
F| "s3_keytool_02_pubkey_is_actually_written"        ← 精确抓住
```

**根因（判例-29）**：引擎层的 `s3_key_*` 证明「**有公钥就能过**」，
但**没证明「工具真的把公钥写进去了」** —— 工具本身没被测过。
补的 `s3_keytool_02` 直接查代码面 `pubkey_fp=pubkey_hex` 在场、且**无** `pubkey_fp=""`。

---

## 三、分析

### 3.1 为什么公钥录入必须走独立工具（不是顺手接在业务路径上）

`agent_touch_first_seen` 的 `pubkey_hex` **缺省 `""`**。
若在 `claim` / `execute` 路径上传它而不传值：
⇒ **每次认领都把已登记公钥抹成空串** ⇒ 认证被业务操作自己抹掉。

**这是「可选参数的缺省值会覆盖已有数据」的典型陷阱**：
`ON CONFLICT DO UPDATE` 里 `pubkey_fp=excluded.pubkey_fp` —— **没传 ≠ 不更新，是更新成空**。

**⇒ 公钥写入必须是「专门的动作」，不能挂在别人的写路径上。**

### 3.2 为什么签名工具不能在服务端

S3 的全部意义是**让「自称」变贵**。如果服务端能代签：
调用方只要说「我是 X」+ 让服务端签一下 ⇒ **等价于没有认证**。
**「签发」与「验签」分属不同主体，是 S3 唯一的安全来源。**

---

## 四、缺口与风险（S3 是否完全关闭）

**S3 骨架 + 端到端已通，但 BUG-430 仍 OPEN**：

1. **密钥分发**：公钥怎么安全送到服务端？现在 `agent_register_key` **没有任何鉴权**
   ⇒ **任何人都能登记/覆盖任何 agent 的公钥** ⇒ **可做密钥替换攻击**（把别人的公钥换成自己的）。
   **这是当前最大的安全缺口。**
2. **密钥轮换**：私钥泄露后怎么换？（本工具能覆盖，但没有「新旧并存窗口 / 通知」机制）
3. **密钥吊销**：离职 agent 怎么失效？（没有 `revoke` 面）
4. **nonce 表在进程内** ⇒ 多实例部署互不可见
5. **S2 未做** ⇒ 未登记 agent 仍可自报身份（拿到 `unauthenticated` 标注但不被拒）

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| S3 第四段 | BUG-430 挂 `- s3-keys:`，**保持 OPEN** |
| **「可选参数缺省值会覆盖已有数据」** | 判例集（`ON CONFLICT DO UPDATE` + 缺省 `""` 的陷阱）|
| **「服务端永不代签」锁** | S3 安全底线，`s3_keytool_04` 钉住 |
| **密钥替换攻击是最大缺口** | BUG-430 正文风险项**第一条** |
