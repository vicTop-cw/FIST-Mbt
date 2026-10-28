# BUG-468：`@mooncry` seed 契约与测试密钥统一

> 2026-10-28 · Lane CJ

## 结论

### ① 行为事实表（探针实测，非推测）

| seed 长度 | `ed25519_public_key` | `ed25519_sign` | 说明 |
|---|---|---|---|
| **1 / 4 / 8 / 16 / 31 / 33 / 64** | ❌ **abort** | ❌ abort | 非 32 一律 abort（含差 1 字节）|
| **32** | ✅ **OK** | ✅ OK | **唯一可用长度** |
| ↑ **16 字节是我两次踩的** | | | |

### ② 根因（精确，纠正我原报告的措辞）

**不是我原报的「签名/验签不自洽」，而是 `abort`。**

```moonbit
// .mooncakes/cc06b/mooncry/lib/ed25519.mbt:263
pub fn ed25519_public_key(seed : Bytes) -> Bytes {
  if seed.length() != 32 {
    abort("ed25519_public_key: seed must be 32 bytes")   // ← 硬 abort
  }
```

`ed25519_sign` 同样有 `if seed.length() != 32 { abort(...) }`。

**⇒ `@mooncry` 的契约是明确且正确的**（32 字节 = RFC 8032 的 canonical seed 长度）。

**真正的问题是「错误信息的可见性」**：
MoonBit 的 `abort` 在测试汇总里**只显示 `Error`，不回显 abort 消息**
⇒「seed 长度错」被伪装成「被测代码坏了」，这才是每次烧 10 分钟的原因。

### ③ 常量：已建，且真测过能用

```moonbit
// src/engine/test_crypto.mbt
pub const TEST_ED25519_SEED_A : Bytes = ...   // 32 字节
pub const TEST_ED25519_SEED_B : Bytes = ...   // 32 字节，与 A 不同
pub fn test_ed25519_pub_hex(seed : Bytes) -> String
pub fn test_ed25519_sign_hex(seed : Bytes, msg : String) -> String
```

**自检格 `test_crypto_seeds_are_usable` 实测通过**：A、B 都 32 字节；导出**不同**公钥（否则「换钥」测试会假通过）；A 的 sign→verify 通过；B 签的用 A 公钥验**必须失败**

### ④ 普查与改动

| 项 | 数量 | 处理 |
|---|---|---|
| 手写 `b"\x.."` 字面量 | 16 处 | 15 处已 32 字节；1 处（`star_gate_wbtest.mbt:79` 的 `\xde\xad\xbe\xef`）是 **hex 编解码数据非 seed**，不改 |
| 自写 `*_seed()` 函数 | **3 处** | ✅ 全改为引用 `TEST_ED25519_SEED_A` |
| 现存短 seed | **0 处** | 两次踩坑后已就地修正，本单是**防复发** |

---

## 证据

### 探针（逐长度独立格，哪格红说明哪步 abort）

```
probe_len_1/4/16/31/33/64 → F（abort）    probe_len_32 → pass
Total: 336, passed: 330, failed: 6
```

### 32 字节全链路（sign → verify）

```
sign(seed32, "hello") → verify(pk, "hello", sig) = true   ✅
verify(pk, "hello2", sig)                        = false  ✅（负路径也对）
```

### 三处统一（保留函数名，只换函数体）

```moonbit
改前: fn cf_seed() -> Bytes { b"\x3a\x7f...\xb7\x95" }   // 各自复制字面量
改后: fn cf_seed() -> Bytes { TEST_ED25519_SEED_A }
```
`cf_pub_hex`/`cf_sign` 同步改调 `test_ed25519_pub_hex`/`test_ed25519_sign_hex`。
**涉及**：`engine_bug430_keyed_must_sign_wbtest.mbt`、`engine_bug430_s3_key_wbtest.mbt`、
`engine_bug466_challenge_entry_wbtest.mbt`。

### 验证

```
moon check --target js  → 0 errors
src/engine              → 333/333 passed, 0 failed
```

---

## 分析：为什么短 seed 会「不自洽」

**它其实自洽 —— 只是没人看得见原因。**

`@mooncry` 对 `seed.length() != 32` 直接 `abort`：
**正确**（RFC 8032 的 seed 就是 32 字节；静默补零会造出假钥匙），
**但** abort 在 MoonBit 测试汇总里**丢失消息文本**，只剩 `Error`。

症状链：`短 seed → abort → 测试红，只有 "Error" → 排查者先怀疑被测代码（它刚被改过）
→ 10 分钟后才发现是夹具`

**⇒ 这是「错误信息不可见」型 bug，不是「库有缺陷」型。**
我原报的「签名/验签不自洽」**是错的** —— 那是从症状倒推的猜测，本单探针纠正为「abort + 消息不可见」。

**统一常量为何能根治**：不是约束了什么，而是**移除了「手写 seed」这个动作本身**。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 常量放在 `src/engine/` ⇒ **只能被 engine 包内的测试用**。`src/server` / `src/router` 的测试若需要 seed，要么复制（又回到老路），要么把常量上提到 `src/core`（更广的共享面） |
| **R2** | 本单**只约束了「不手写」**，没有机制**阻止**新人再手写。真正根治要在 `run_guards.py` 加一条静态检查：`*_test/_wbtest.mbt` 里出现 `b"\x.."` 字面量且紧邻 `ed25519_` ⇒ 判红 |
| **R3** | `test_crypto.mbt` 是**非 `_test` 后缀**的测试辅助文件 ⇒ 会进入产品包编译。建议确认这不违反「一源四态」的产物面约定（目前 0 errors，无实际影响） |
| **R4** | 常量值沿用了历史 32 字节序列，**未经独立验证是随机/安全的** —— 但它**仅供测试**，报告与注释均已写明「生产绝不用」 |

---

## 建议入档位置

**账本**：BUG-468 建议改判——
> 原 `[medium] OPEN`，措辞为「签名/验签不自洽」。
> **本单根因修正为「`@mooncry` 对非 32 字节 seed 正确 abort，但 abort 消息在测试汇总中不可见」**，
> 修复为「统一常量 + 自检格」。可标 **FIXED**（防复发已落地），R1/R2 另计。

**判例候选**：
> **判例：`abort` 在测试汇总里丢消息 ⇒ 「夹具错了」会被读成「被测代码坏了」。**
> 一个正确的硬约束（seed 必须 32 字节）因为**错误信息不可见**，
> 变成了每次 10 分钟的排查成本，且**同一个坑一天内被两个人各踩一次**。
> **⇒ 断言夹具自身的合法性（并在失败时给出可读原因），比断言业务逻辑更容易被忽略，但收益更高。**
> 同族：本条是「**错误信息的可见性**」问题，与判例-34「报错指向 ≠ 病因所在」互为表里。

---

**提交**：`test(crypto)`。新增 `src/engine/test_crypto.mbt`（2 个常量 + 2 个辅助函数 + 2 格自检）。
