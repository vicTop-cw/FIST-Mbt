# `strict` 真的拒绝 + `startup_warning` 接线（BUG-476）

> 司令-γ · 2026-10-28
> **一句话**：把 `strict` 从「返回专用标签 + 降权」改成**四处门真的硬拒**，
> 并把 `auth_mode_startup_warning()` 从「实现了但零调用」接到 `run_server()` 开头。

---

## 结论

| 项 | 结果 |
|---|---|
| **四个门硬拒了吗** | **✅ 四处全部接线**（`rsv_set` / `rsv_try_set` / `locks_try_acquire` / `claim`） |
| **判断依据** | **拒在门层**，`judged_role_gated` 签名不变（§分析） |
| **startup_warning 接线** | **✅ `run_server()` 第一行**（判例-29 实现路径格） |
| **锁** | **6 格**（S1~S6），其中 **S5/S6 是双实现路径格** |
| **变异** | **5 个全部生效并恢复**（接线计数逐个验证） |

---

## 证据

### §1 设计：拒在门层，不改 `judged_role_gated` 签名

```moonbit
// engine_rsv.mbt 新增（单一真源）
pub fn strict_challenge_denial(role_source : String, action : String) -> String? {
  if role_source == "challenge_missing" { Some("...需要 S3 挑战认证...") } else { None }
}
```

**四处接线**：

| 门 | 文件:动作名 | 接线数 |
|---|---|---|
| `rsv_set`（`reserve_scope` 主路） | `engine_rsv.mbt` `"reserve_scope"` | **2** |
| `rsv_try_set`（`reserve_scope` try 路） | 同上 | ⬆ 合计 |
| `locks_try_acquire` | `engine_rsv.mbt` `"lock_acquire"` | **1** |
| `claim` | `server.mbt` `"claim"`（`judged_role_with_challenge` 预取点之后） | **1** |

**为什么 `claim` 在 server 层拒**：它的门在 `engine.mbt` 的 `judged_role_with_nonce` 之后，
而那函数签名是 `(String,String)` 不能 `Err`；**且本单边界不许改 `engine.mbt`**。
`server.mbt` 的 `judged_role_with_challenge` 预取点**已拿到 `role_source` 且不消费 nonce**
⇒ 在那里拒代价最小、语义正确（拒之前没动任何状态）。

### §2 `startup_warning` 接线（判例-29）

```moonbit
pub async fn run_server() -> Unit {
  let auth_warn = @engine.auth_mode_startup_warning()
  if auth_warn != "" { println("⚠️  [fist-mbt] " + auth_warn) }
  println("[fist-mbt] auth_mode = " + @engine.auth_mode().to_string())
  ...
```
**修前**：`auth_mode_startup_warning()` 的调用点 = **0 处**（`grep` 全仓只有定义）。

### §3 六格锁

| 锁 | 验什么 | 类型 |
|---|---|---|
| **S1** | `strict` + 无挑战 ⇒ 门层**拒**（且错误文案含 `agent_register_key` / `FIST_AUTH_MODE`，可自救） | 语义格 |
| **S2** | `strict` + `challenge_verified` ⇒ 门层**不拒** | 语义格 |
| **S3** | `soft` + 无挑战 ⇒ `challenge_required`（≠ `challenge_missing`）⇒ 门层**不拒** ⟹ **strict ≠ soft** | 语义格 |
| **S4** | `off` + 无挑战/`declared`/`inferred` ⇒ 门层**不拒**（零回归）+ `auth_mode_parse("") == Off` | 语义格 |
| **S5** | `run_server()` 里**真的调了** `auth_mode_startup_warning()`（含反脱锚：函数前不得已出现） | **实现路径格** |
| **S6** | **四处门的接线计数**（`reserve_scope`=2 / `lock_acquire`=1 / `claim`=1） | **实现路径格** |

**⚠️ S6 是本单最重要的补丁**：见 §4。

### §4 ★ 变异实测暴露了一个判据缺口（S6 因此而生）

变异清单（**真跑**，接线计数逐个验证）：

| 变异 | 动作 | 计数变化 |
|---|---|---|
| M1 | 删 `rsv_set` 的硬拒 | `reserve_scope` 2→1 ✅ |
| M2 | 删 `rsv_try_set` 的硬拒 | `reserve_scope` 2→1 ✅ |
| M3 | 删 `lock_acquire` 的硬拒 | `lock_acquire` 1→0 ✅ |
| M4 | 删 `claim` 的硬拒 | `claim` 1→0 ✅ |
| M5 | 删 `run_server` 的 startup 调用 | `startup` 2→1 ✅ |

**恢复确认：5 个变异全部恢复，计数回到基准 ✅**

**⚠️ 但 M1~M4 揭示了一个判据缺口**：
**S1~S4 只测门层函数 `strict_challenge_denial` 的语义，删掉四处接线后它们全绿** ——
因为函数本身没变。**这正是判例-29「机制格 ≠ 实现路径格」**：
函数对了 ≠ 门调了它。

**⇒ 因此补 S6**：直接读源码数接线点。
**且必须是计数不是 contains** —— `reserve_scope` 有两处门（`rsv_set` + `rsv_try_set`），
只断言 `contains` 会在删掉其中一处时仍然绿。

---

## 分析：为什么「在门消费者判」优于「改 `judged_role_gated` 返回值」

| 方案 | 改动面 | 风险 |
|---|---|---|
| **A 改 `judged_role_gated` 返回 `Result`** | 函数签名 + **5 处消费点**（`rsv_set`/`rsv_try_set`/`locks_try_acquire`/`judged_role_with_nonce`/`judged_role_with_challenge`）+ **工具面 3 处调用方** | 每处都要改 match 形态；`judged_role_with_nonce` 自身返回 `(String,String)`，改它又波及其消费点（`claim`） |
| **B 在门消费者判（本单选的）** | 新增 1 个纯函数 + 4 处各加 5 行 | `judged_role_gated` 保持纯净；判定**单一真源** |

**决定性理由**：**`judged_role_gated` 的职责是「算出身份」，不是「决定拒不拒」。**
- 它已经被 5 处消费，其中 `judged_role_with_nonce` 还要在验签通过后**消费 nonce** 并可能返回 `challenge_replayed` —— 这些逻辑都要 `role_source` 原样流出。
- 若它自己 `Err`，「验签失败」与「strict 未提供」会被压成同一种错误，**调用方无法区分该去登记公钥还是该去调 auth_mode**。
- **与既有 `RoleDenied` 完全同一手法**：`judged_role` 返回角色，`check_scope_permission` 在门层判拒 —— 本单照抄这个范式。

**⚠️ 唯一的代价**：4 处接线，**任何一处漏接就是一处门不拒** ⇒ 这正是 S6 存在的原因。

---

## 缺口与风险

- **R1 `strict` 目前只覆盖 4 个门** —— `execute` / `verify` / `submit` / `archive` 等**没有挑战门**，
  在 `strict` 下它们**完全不受影响**（它们本来就不看 challenge）。
  ⇒ **设了 `strict` 的人仍不能说「所有写操作都要认证」**，只能说「这 4 个要」。
  这是 BUG-430c 的范围，不在本单。
- **R2 `claim` 的拒在 server 层** —— 若将来有别的入口直接调 `eng.claim`（绕过 server），
  那道入口不受 `strict` 约束。**判据 S6 只能数 server 的接线。**
- **R3 `startup_warning` 只在 `run_server()` 里打印** —— 走 `fist.py` 网关或其它入口起服务时**不经此路径**。
- **R4 读数已补跑（本单收口时）**

```
python scripts/moon_test_env.py src/engine
  汇总：Total tests 347 / passed 337 / failed 10
```

**六格锁 S1~S6 全部通过**（`failed: 10` 里**零个**属于 `bug476`）。
那 10 个失败在 `engine_contract_test` / `engine_execute_r2_test` / `fist-mbt_test` /
`omega_strong_test`，**均零处引用本单改动**（`strict_challenge_denial` / `auth_mode_startup` /
`judged_role_gated` 在这些文件里出现 0 次），但都涉及 `core` / `deliverable` / `待领取` ——
是并发的 `src/core/core_task.mbt` 改动（BUG-475）引起的连带失败。
- **R5 `strict` 的错误文案是英文+中文混排**，与仓内风格一致但可望统一。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-bug476-strict-enforce-report.md` |
| 实现 | `src/engine/engine_rsv.mbt`（`strict_challenge_denial` + 3 处接线）· `src/server/server.mbt`（claim 接线 + startup 接线） |
| 锁 | `src/engine/engine_bug476_strict_wbtest.mbt`（S1~S6） |
| 变异脚本 | `temp/audit/lane_dd_mutation.py` |
| **该记** | 判例-29 的新实例：**「门层函数有语义锁」不等于「门真的调了它」** —— S6 是补丁 |
