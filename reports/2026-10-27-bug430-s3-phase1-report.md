# BUG-430 / S3 **第一段**：挑战-签名-验签骨架 · Lane BE · 2026-10-27

> **第一段做完 = 骨架通了。BUG-430 仍然 OPEN。**
> 还需要：握手 + 客户端签名 + 密钥管理 —— 那三件才是真正改变安全属性的部分。
> 本段证明的是「**挑战确实接进了角色取数面**」，不是「系统安全了」。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 加了什么 | 3 个纯函数 + 2 个辅助函数；`engine/moon.pkg` 加 2 个依赖 |
| **`s3_min_01`** | ✅ **通过** —— `(Executor, "unauthenticated")` |
| 变异对照 | **2 个变异都真跑**，各自**单独**打红对应格 |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/engine` **258/258/0**；全量 **1589/1589/0** |
| 零回归 | ✅ **`judged_role` 未改**（4 个现有调用点不受影响）|
| BUG-430 状态 | **仍 OPEN** |

---

## 二、证据

### 2.1 三个纯函数 + 两个辅助

```moonbit
/// ① nonce：纯函数、确定性（不用 @random —— moonbitlang/x 无独立 random 包）。
///    nonce 绑定 agent ⇒ 换主体即失效。
pub fn issue_challenge_nonce(agent : String, counter : Int32) -> String {
  "fist-s3-challenge:v1:" + agent + ":" + counter.to_string()
}

/// ② 验签：hex 解码复用 @mooncry.hex_to_bytes_or；
///    验签复用 @mooncry.ed25519_verify —— **与 star_gate.mbt:301 同一个函数**。
///    fail-closed：hex 坏 / 公钥≠32B / 签名≠64B / 验签失败 ⇒ 一律 false。
pub fn verify_challenge_sig(pubkey_hex : String, msg : String, sig_hex : String) -> Bool {
  let pk = match @mooncry.hex_to_bytes_or(pubkey_hex) { Ok(b) => b ; Err(_) => return false }
  let sig = match @mooncry.hex_to_bytes_or(sig_hex) { Ok(b) => b ; Err(_) => return false }
  if pk.length() != 32 || sig.length() != 64 { return false }
  @mooncry.ed25519_verify(pk, @utf8.encode(msg), sig)
}

/// ③ 带挑战的角色取数（本段核心 —— 挑战接进了取数面）
pub fn judged_role_with_challenge(
  eng : FistEngine, agent : String, challenge_nonce : String?,
) -> (String, String)
```
辅助：`declared_pubkey_for`（走**与 `declared_role_for_judgment` 完全相同的取数路径**，
不新造第二条面 —— BUG-432 的教训）+ `s3_last_sig_probe`（**签名来源占位**，见 §四）。

### 2.2 `moon.pkg` 改动（2 个依赖）

```diff
   "moonbitlang/x/fs",
+  "moonbitlang/core/encoding/utf8",
+  "cc06b/mooncry/lib" @mooncry,
 }
```
**依赖方向安全**：`store` 不依赖 `engine`，`engine` 加 `mooncry` 不成环。

### 2.3 `s3_min_01` —— 本段的核心断言

```moonbit
test "s3_min_01_no_nonce_no_leader" {
  let e = s3_eng()
  let (role, source) = judged_role_with_challenge(e, "fist-mbt", None)
  assert_eq(role, "Executor")
  assert_eq(source, "unauthenticated")
}
```
**它断言的是返回值，不是「某个函数存在」** —— 这就是判例-29 要求的「实现路径格」。

配套 3 格：
| 格 | 断言 |
|---|---|
| `s3_min_02` | 有 nonce 但**公钥未登记** ⇒ `challenge_failed`（fail-closed）|
| `s3_min_03` | nonce 确定性（同输入同输出、counter/agent 不同则不同、串里绑定 agent）|
| `s3_min_04` | **验签真的在工作**：真签真验 true / 篡改 false / 换钥 false / 坏 hex false |

### 2.4 变异实测（**真跑**，两个各自单独打红）

**变异 1：把 `None` 分支退回 `judged_role` 原样（= 挑战没接进取数面）**
```
汇总：Total tests 258 / passed 257 / failed 1
F| "s3_min_01_no_nonce_no_leader"          ← 只有它红
```

**变异 2：把 `verify_challenge_sig` 改成恒 `true`（验签被掏空）**
```
汇总：Total tests 258 / passed 257 / failed 1
F| "s3_min_04_verify_challenge_sig_really_verifies"   ← 只有它红
```

**⇒ 两格都精确指向各自的实现路径，不是泛红。**

---

## 三、分析（为什么从纯函数开始而不是从握手开始）

**握手的失败原因分不清。** 一趟握手牵扯：MCP 传输层 → 客户端实现 → nonce 分发 →
签名回传 → 服务端取公钥 → 验签 → 角色映射。任何一处没通，现象都是「认证失败」，
而**你无法从「认证失败」反推是哪一层坏了**。

**纯函数段可以用「一条编译命令 + 一个 test」把「挑战接进了取数面」这件事单独证明**，
且：
- **零回归**（`judged_role` 一个字没改，4 个调用点不受影响）；
- **可变异**（改坏哪段，哪格红 —— 本段两个变异都精确打红）；
- **可复用**（第二段把 `s3_last_sig_probe` 换成真实签名来源，前面全不用改）。

**换句话说：先把「骨架是否接通」与「运输是否可靠」解耦。**
握手阶段出问题时，你至少能确定「不是骨架的问题」。

---

## 四、缺口与风险

1. **`s3_last_sig_probe` 是明写的占位**：纯函数段**拿不到**调用方提交的签名 ⇒
   任何 `Some(nonce)` 调用在**第一段**都会走 `challenge_failed`。
   **这是有意的**，且代码注释写清了「第二段必须**删掉**本函数，而不是让它返回真签名」。
   若有人把它改成返回一个能验过的签名 ⇒ **等于绕过 S3**。
2. **`judged_role_with_challenge` 尚未接入四条门**：`rsv_set` / `rsv_try_set` /
   `locks_try_acquire` / `claim` 的 RANK_GATE 仍调 `judged_role`。
   **所以本段对现网行为零影响** —— 这既是「零回归」的原因，也是「还没生效」的原因。
3. **`pubkey_fp` 存的是公钥 hex（64 字符）还是指纹，未最终确认**。
   可行性核查已指出：`agents` 表该列是 `TEXT NOT NULL DEFAULT ''`，**存得下** 64 字符 hex；
   但**现有数据里存的是什么**需要核（若历史数据是短指纹 ⇒ 会在验签时因长度不是 32 字节而 fail-closed，
   表现为「所有老 agent 都 challenge_failed」）。
4. **nonce 不落库 ⇒ 无法防重放**。第一段里 nonce 是纯函数算出来的，
   **服务端没有「已用 nonce」集合** ⇒ 同一个 nonce 可以被重复使用。
   **第二段必须加 nonce 存储 + 一次性消费**（否则「挑战」变成「长期通行证」）。
5. **`@mooncry` 是新增的直接依赖**（此前 `engine` 包不直接依赖它）。
   供应链风险已在可行性报告登记。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| S3 第一段 | BUG-430 挂 `- s3-phase1:`，**状态保持 OPEN** |
| **「先纯函数后握手：把骨架与运输解耦」** | 判例集（握手类功能的通用推进法）|
| **`s3_last_sig_probe` 必须删而不是填** | S3 第二段的**硬约束**，建议写进 BUG-430 正文 |
| `pubkey_fp` 历史数据语义待核 | BUG-430 风险项（若存的是短指纹 ⇒ 老 agent 全部 challenge_failed）|
