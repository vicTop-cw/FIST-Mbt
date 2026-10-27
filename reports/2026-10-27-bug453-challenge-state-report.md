# BUG-453 修复报告：S3 认证态进入 `action` 面

> **病灶**（我自己在 R22 独立验证时发现）：`judged_role_with_challenge` 承诺「让认证状态显式可见」，
> 但 `rsv_try_set` / `locks_try_acquire` 的 `action` 面只映射了 `inferred` 一种，
> **且无条件追加硬编码 `+agent_self_reported`**。
> **执行人**：司令-γ · **日期**：2026-10-27

---

## 结论

| 项 | 结果 |
|---|---|
| **三个认证态可见了吗** | **✅ 可见** —— 真跑 MCP 实测：传无效签名 ⇒ `action = "unregistered+challenge_failed"` |
| **零回归** | **✅ 保持** —— 不传 challenge ⇒ `"unregistered+role_inferred+agent_self_reported"`（与修前逐字相同） |
| **`execute` 死参数** | **✅ 已删**（选 (a)） |
| **变异对照** | **✅ 实测** —— 注入变异后 L1/L2/L3/L5 四格齐红（失败数 1→5），恢复后转绿 |
| **测试** | `Total tests: 285, passed: 284, failed: 1` —— **那 1 格是既有失败，非本单引入**（见 §缺口） |

---

## 证据

### §1 实现（`src/engine/engine_rsv.mbt`）

**新增单一映射源**（`:452`）：
```moonbit
pub fn auth_tag(role_source : String) -> String {
  match role_source {
    // 三个**新增**认证态：必须可见
    "challenge_verified" => "+challenge_verified"
    "challenge_failed" => "+challenge_failed"
    "challenge_replayed" => "+challenge_replayed"
    // 既有态：**零后缀**。为什么不是 "+agent_self_reported"：
    //   该后缀在 `rsv_try_set` 里由调用点显式追加（修前就是这样，零回归）；
    //   而 `locks_try_acquire` 的 `permission_denied` / `unregistered` 有**精确相等**的
    //   既有断言（`lock_perm_wbtest.mbt:36/51/104`）⇒ 在这条门上必须保持逐字不变。
    _ => ""
  }
}
```

**`rsv_try_set`（`:489-495`）**：硬编码换成映射 + 既有态补原后缀
```moonbit
let auth = auth_tag(role_source)
let src_tag = if auth == "" { "+agent_self_reported" } else { auth }
```

**`locks_try_acquire`（`:606`）**：不再丢弃 `_role_source`
```moonbit
let (role, role_source) = judged_role_gated(self, agent, challenge_nonce, challenge_sig~)
// 四个出口（RoleDenied×2 / Unregistered / Allowed）各接 auth_tag
```
新增 `denied_tagged(role_source)`（`:446`）—— `RoleDenied` 的硬拒回执也带认证态。

### §2 ★ 端到端实测（真跑 MCP，不是「代码看起来对」）

```
$ fist.py call reserve_scope --agent va --scope v/a --challenge n1 --challenge_sig "abab…(128 hex)"
{"action":"unregistered+challenge_failed", ...}
                    ↑ ★ 修前这里是 "unregistered+agent_self_reported"，与「没传 challenge」逐字相同

$ fist.py call reserve_scope --agent vb --scope v/b          # 不传 challenge
{"action":"unregistered+role_inferred+agent_self_reported", ...}
                    ↑ 零回归：与修前逐字相同
```

**⇒ 「承诺了可见」现在兑现了：验签失败与未挑战在 `action` 面**可区分**。**

### §3 `execute` 死参数 —— 已删

```diff
--- a/src/server/server.mbt   (execute schema, :2085-2091)
-        // BUG-430 S3 第三段：可选挑战。不传 ⇒ 走原逻辑（零回归）
-        "challenge": string_prop("可选：S3 挑战 nonce。…"),
-        "challenge_sig": string_prop("可选：对 challenge 的 Ed25519 签名 hex…"),
+        // BUG-453：这里**曾有** challenge / challenge_sig 两个参数，但 `execute` 从不调
+        // `opt_challenge(args)` ⇒ 收下就丢（死参数，与 BUG-440「声明了但没接线」同族）。
+        // 为什么删而不是接上：`execute` 不走角色取数面（`judged_role_gated`），验签结果
+        // 无处可用 —— 接一个「验了但不影响任何判决」的参数比不声明更坏。
```

### §4 锁设计（`src/engine/engine_rsv_bug453_wbtest.mbt`，7 格）

| 锁 | 验什么 |
|---|---|
| **L1** | `auth_tag("challenge_verified") == "+challenge_verified"` |
| **L2** | `auth_tag("challenge_failed") == "+challenge_failed"` |
| **L3** | `auth_tag("challenge_replayed") == "+challenge_replayed"` |
| **L4** | 零回归：`declared` / `unauthenticated` / `inferred` / `""` / 未知值 ⇒ **空后缀** |
| **L4-b** | `rsv_try_set` 源码含 `if auth == "" { "+agent_self_reported" } else { auth }` |
| **L5** | ★变异对照：源码级断言 `auth_tag` 函数体内四个字面量齐全 + 有兜底分支 |
| **L5-b** | ★机制格：`rsv_try_set` 必须**调** `auth_tag`（判例-29：函数写好了 ≠ 接上了） |
| **L5-c** | ★机制格：全文件不许再有 `_role_source`（丢弃的语言级标记） |

### §5 ★ 变异实测（硬要求 ③：真跑，不是「设计了变异」）

```
① 注入变异：把 auth_tag 的三个认证态全部改回 "+agent_self_reported"
   预期：L1/L2/L3/L5 必红

$ python scripts/moon_test_env.py src/engine
  F| bug453_L5_auth_tag_maps_all_four_states     failed
  F| bug453_L1_verified_maps_to_tag              failed: `"+agent_self...`
  F| bug453_L2_failed_maps_to_tag                failed
  F| bug453_L3_replayed_maps_to_tag              failed
  Total tests: 285, passed: 280, failed: 5        ← 失败数 1 → 5（+4 格正是我的锁）

② 恢复：cp /tmp/engine_rsv.bak src/engine/engine_rsv.mbt
$ python scripts/moon_test_env.py src/engine
  Total tests: 285, passed: 284, failed: 1        ← 回到基线（那 1 格是既有失败）
```

**⇒ 锁真的在看着，不是恒绿。**

---

## 分析：为什么之前漏了这一步

### 直接原因：`judged_role_gated` 的结果在**两个消费点**被分别处理

`judged_role_gated` 返回 `(role, role_source)`：
- `role` 被**全部**消费点用（权限判定必须用它）
- `role_source` **只有 `rsv_try_set` 用了一半**（只判 `== "inferred"`），
  `locks_try_acquire` 则**直接 `_role_source` 丢弃**

**⇒ 这是「返回值的一个分量被丢」的经典形态**：编译器不报（`_` 前缀是显式声明「我要丢」），
调用方不疑（回执字段齐全）。**与 `BUG-439`/`BUG-441`（占位返回值是合法值）同族但更隐蔽**：
那两条是「返回值本身是占位」，这条是「返回值的一半被忽略」。

### 为什么「承诺了可见」这句话是承重的

`judged_role_with_challenge` 的注释（`engine_rsv.mbt:124-126`）写：
> 「**`role_source` 的取值扩展（调用方可见的变化）**……**这不是改语义，是让「认证状态」显式可见。**」

**⇒ 这不是普通注释，这是一条**对调用方的契约**。** 而契约的两端：
- **生产端**（`judged_role_with_challenge`）兑现了 —— 返回值里确实有四个态
- **消费端**（两个门的 `action`）**没兑现** —— 只透出了一种

**⇒ 「承诺了可见」的含义是：契约跨越了函数边界，而本仓的验证方式是「函数内自测」，
所以两头各自都测过、中间的断点没人测。** 这与 R12 的 `check_two_faces` 判据要防的正是同一件事。

### 一个反直觉的设计点：两条门的默认态**不能统一**

修的过程中我发现：`rsv_try_set` 的既有态要 `+agent_self_reported`，
但 `locks_try_acquire` 的既有态必须**零后缀** —— 因为：
- `rsv_try_set` 的旧锁用 `contains("+agent_self_reported")`（宽松）
- `locks_try_acquire` 的旧锁用 `assert_eq(o.action, "permission_denied")`（**精确相等**，`lock_perm_wbtest:36/51/104`）

**⇒ 第一次改完 5 格红，其中 3 格就是这个原因。** 这说明：
**「零回归」不是设计出来的，是跑出来的** —— 见 §缺口 1。

---

## 缺口与风险

### 1. ⚠️ 剩余 1 格失败**不是本单引入的**（已核实）

```
F| src/engine/engine_bug430_s3_p2_wbtest.mbt:73 ("s3_p2_02_four_gates_wire_the_challenge")
```
它断言 `src_eng.contains("judged_role_with_nonce(self, assignee, challenge_nonce, challenge_sig~)")`（**单行**），
而 `src/engine/engine.mbt:184` 的实际调用是**多行格式**。
```
$ git diff --stat src/engine/engine.mbt   → 空（我没改过这个文件）
```
**⇒ 这是另一个 lane 格式化 `engine.mbt` 后留下的既有失败。**
**⚠️ 但我**确实**在实现过程中踩过同一个坑**：我一度把 `locks_try_acquire` 的调用拆成多行，
导致这个锁红；发现后**恢复成单行**（现在 `grep -c` = 3 处单行）。
**建议：这个锁改成容忍多行**（否则每次 `moon fmt` 都可能打红它）—— 不在本单边界。

### 2. `challenge_verified` 路径没有端到端实测

我实跑验证了 **`challenge_failed`**（传无效签名）与**零回归**（不传），
**但没实跑 `challenge_verified`** —— 那需要一个已登记公钥 + 匹配私钥签名，
生成 Ed25519 密钥对超出本单工具面能力。
**⇒ `auth_tag("challenge_verified")` 由 L1 单测钉住（纯函数零 IO），
端到端那一段由既有的 `engine_bug430_s3_key_wbtest.mbt` 4 格负责。**

### 3. `challenge_replayed` 同样只有单测

重放需要「同一 nonce 用两次」，而 `s3_pending_nonces` 是进程内状态，跨 `fist.py` 调用不共享
（每次是新进程）⇒ **MCP 面无法构造重放**。**L3 单测覆盖映射，链路实测留给进程内集成测试。**

### 4. 我没跑全量（`src/server` 因他人探针文件编译不过）

```
Error: [4021] src/server/zz_probe_bo_test.mbt:3:9  The value identifier engine_for_ns is unbound.
```
**⇒ `src/server` 包当前无法编译**（别人的临时探针）。**我对 `server.mbt` 的改动只做了 `moon check src/engine` 之外的静态核**
（删两个 schema 字段，不影响任何代码路径）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-bug453-challenge-state-report.md` |
| 实现 | `src/engine/engine_rsv.mbt`（`auth_tag` :452 / `denied_tagged` :446 / 两个门） |
| 锁 | `src/engine/engine_rsv_bug453_wbtest.mbt`（7 格，含 3 个变异/机制格） |
| `server.mbt` | `execute` schema 删两个死参数（:2085-2091） |
| `BUG-453` | **可标 FIXED**（待你终审）；建议同批记「`s3_p2_02` 单行断言脆弱」为新缺口 |
