# `test_crypto` 上提 + 手写 seed 静态判据（BUG-468 R1/R2）

> **执行人**：司令-γ · **日期**：2026-10-28
> **一句话**：`test_crypto.mbt` 从 `src/engine` **上提到 `src/core`**（各包都能用，本单完成/并入 `abb908af`），
> 并把手写 seed 从「靠自觉」变成 **判据**（`check_handwritten_seed.py`，10 格 selftest、5 个变异对照）。
>
> ⚠️ **归属澄清**：R1（上提）在本单进行期间由另一 lane 以 `abb908af` 一并完成
> （`src/core/test_crypto.mbt` 新增、`src/engine/test_crypto.mbt` 删除、各测试改 `@core.`）。
> 本单**提交的只有 R2 判据**；R1 的读数（含 +262 字节体积实测）是我在**同一工作区实测**的。

---

## 结论

| 项 | 结果 |
|---|---|
| **上提了吗** | **✅** `src/engine/test_crypto.mbt` → `src/core/test_crypto.mbt`；3 个 engine 测试改用 `@core.` |
| **判据怎么写的** | 三层筛：① `b"\x??..."` 字节字面量 ② 长度 ∈ {32,64} ③ 同文件有 ed25519/seed 上下文 |
| **误报数** | **0**（全仓 224 个测试文件；命中 12 处**全部是真手写 seed**） |
| **变异对照** | **5 格**，含「往已豁免文件新增 seed ⇒ 必红」 |
| **测试** | 全量 **1802/1802**；`moon check` 0 error |

---

## 证据

### §1 上提（R1）

| 项 | 前 | 后 |
|---|---|---|
| 位置 | `src/engine/test_crypto.mbt` | `src/core/test_crypto.mbt` |
| 依赖 | `@mooncry` + `@utf8` + **`verify_challenge_sig`（engine）** | `@mooncry` + `@utf8`（**去掉了对 engine 的反向依赖**） |
| 用法 | 裸引用 `TEST_ED25519_SEED_A` | `@core.TEST_ED25519_SEED_A` |

**关键改动**：原 `test_crypto` 的 selftest 调 `verify_challenge_sig`（engine 的函数）——
**core 不能反向依赖 engine** ⇒ 改用 `@mooncry.ed25519_verify`（它正是 `verify_challenge_sig` 内部调的那个）。
`src/core/moon.pkg` 新增 `cc06b/mooncry/lib` 与 `moonbitlang/core/encoding/utf8`。

**产品包体积（Alpha 的 R3 担忧）实测**：
```
上提前 cli.js: 5556207 bytes
上提后 cli.js: 5556469 bytes   →  +262 bytes (0.005%)
```
⇒ **不显著**。常量在 CLI 不被引用，被 tree-shake。

### §2 判据设计（R2）—— 三层筛，全仓标定

**全仓普查实测（2026-10-28，13 处 `b"\x.."` 字面量）**：

| 候选判法 | 读数 | 结论 |
|---|---|---|
| 只找 `b"\x.."` | 13 处 | **13 处全是误报**（含 4 字节的 hex 编解码数据） |
| 只找「16/64 字节」 | **0 处** | **全漏**（真实手写 seed 全是 32 字节） |
| 只找「长度 != 32」 | **1 处** | 误报 1（`star_gate_wbtest.mbt:79` 的 `\xde\xad\xbe\xef` 是 hex 数据） |
| **①+②+③（本判据）** | **命中 12 处真 seed，误报 0** | ✅ |

**核心洞察**：**Ed25519 的 seed 合法长度只有 32** ⇒
「32 字节字面量 + ed25519 上下文」**几乎不可能是别的东西**；
而「长度 != 32」在 ed25519 上下文里**反而不是 seed**。

### §3 判据的「按行豁免」—— 这是本单最重要的自我纠错

第一版 `INTENTIONAL` **按文件**豁免。**变异实测发现它漏**：
往 `star_gate_wbtest.mbt`（已豁免）末尾新增一枚手写 seed ⇒ **判据照样 rc=0**（整个文件被跳过）。

**⇒ 改成按 (文件, 行号) 豁免**：
```python
INTENTIONAL = {
    "src/router/star_gate_wbtest.mbt": {7: "sg_seed 00..1f —— RFC 已知向量的输入…"},
    ...
}
```
**重做变异 ⇒ `rc=1`，精确报 `star_gate_wbtest.mbt:365`**（已豁免文件里的**未登记行**）。

**行号漂移是有意的**：漂移后判据报红，逼人重新确认那行是否仍合法 ——
这比「静默放过一个挪了位置的 seed」安全。另附 `stale_registrations()` 报「登记了但已不是 seed」。

### §4 selftest 10 格（5 格变异对照）

```
[OK] 4-byte-hex-data-not-reported             ← 不误伤 hex 数据
[OK] scan-sees-file
[OK] ★MUTATION-32byte-seed-reported           ← 加 seed ⇒ 报
[OK] ★MUTATION-names-file
[OK] 32byte-without-context-not-reported      ← 无 ed25519 上下文 ⇒ 不报
[OK] 16-byte-not-in-scope
[OK] allow-file-exempt                        ← core/test_crypto.mbt 豁免
[OK] ★byline-registered-line-allowed          ← 登记行放过
[OK] ★byline-unregistered-line-reported       ← 未登记行必报（按行 vs 按文件的反证）
[OK] empty-scan-self-reject
[selftest] 10/10
```

### §5 全仓实跑

```
[扫描] 测试文件 224 个
[豁免] 有意保留 6 文件 / 8 行（INTENTIONAL，每条带理由）
[结论] 无手写 seed。rc=0
```

**8 处保留的为什么不能换成 A/B**（都在 `INTENTIONAL` 逐条写明）：

| 处 | 为什么必须保留 |
|---|---|
| `bs_seed` 0x5a../0xa5.. | 测「A 签 + B 冒认必须失败」，需两把**与标准夹具不同**的钥匙避免串扰 |
| `other_seed` 0x99../0xaa.. | 就是「另一把私钥」 |
| `seed` 00..1f / `seed2` ff..f6 | 连续/反序字节便于人工核对 |
| `sg_seed` 00..1f | **RFC 已知向量的输入**——种子本身是测试向量 |
| `kp_seed_b` 0x99.. | pin 的对立面钥匙 |

另 **4 处是 A/B 的复制粘贴**（值完全相同）⇒ 已改为 `@core.TEST_ED25519_SEED_A/B`。

---

## 分析：为什么这个判法可靠，「白名单豁免」为什么不如它

**可靠，因为它不是「猜」而是「标定」**：
- 三种候选判法**都在全仓真样本上量过**（13 处字面量的真实分布）；
- 选定判法的**误报 0 / 漏报 0**（12 处全部确认是手写 seed，逐处查过上下文）；
- 判据的覆盖面**写在运行时输出里**，不只在 docstring。

**「白名单豁免」不如「精确判法」，三条**：

1. **白名单要名字，精确判法要理由**。
   本判据的 `INTENTIONAL` **每条都带一段为什么**（上表）。白名单只要文件名，
   下一个人看到 `star_gate_wbtest.mbt` 在豁免表里，**不知道那里面能不能再加 seed**。

2. **白名单会扩大到吞掉判据本身**。
   实测：按文件豁免 ⇒ 已豁免文件里**新增 seed 全部放过** ⇒ 判据在最该抓的场景失效。
   **按行豁免后，同文件新增必然报红** —— 这是 selftest 里 `byline-*` 两格钉住的。

3. **白名单不防腐烂**。
   `stale_registrations()` 会在「登记了但已不是 seed」时报出来，
   白名单没有这个方向。

---

## 缺口与风险

1. **不判「通过变量传递的 seed」** —— `let s = SOME_CONST; ed25519_public_key(s)`
   已不是字面量，本判据的靶子是字面量。
2. **不判 `[0x3a, 0x7f, ...]` 数组写法** —— 全仓普查确认当前无此形态；将来出现则看不见。
3. **行号漂移会误报** —— 有意设计（见 §3），但会带来「改文件后判据红、需人工更新登记」的成本。
4. **`core` 现在依赖 `@mooncry`** —— 5 个依赖 core 的包会间接拿到它（实际只新增 2 个，
   因 engine/router/server 本就有）。**这是上提的代价，已由 +262 字节实测确认可接受。**
5. **未跑 `moon fmt`**（本机 BUG-388 不可用），格式门权威面在 CI。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-test-crypto-and-seed-guard.md` |
| 上提 | `src/core/test_crypto.mbt`（新）· `src/core/moon.pkg`（+mooncry/+utf8）· `src/engine/test_crypto.mbt`（删） |
| 用法 | `src/engine/engine_bug430_{keyed_must_sign,s3_key,s3_p3,s3_rotate,first_reg_proof}_wbtest.mbt` · `src/server/server_bug430_keypin_wbtest.mbt` 等改用 `@core.` |
| 判据 | `scripts/check_handwritten_seed.py`（10 格 selftest） |
| 执行面 | `scripts/run_guards.py`（两格 gate）· `scripts/README.md` 锚点 |
| **建议后续** | ① 把 `INTENTIONAL` 的行号登记改成「内容指纹」（抗漂移）② 若出现数组写法，扩判据 |
