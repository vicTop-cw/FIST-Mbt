# `FIST_AUTH_MODE` 三档开关落地

> 2026-10-28 · Lane CZ · owner 已批准「策略 B」

---

## 结论

| 项 | 结果 |
|---|---|
| **三档实现** | ✅ `off` / `soft` / `strict`，真源 `src/engine/auth_mode.mbt` |
| **`off` 零回归** | ✅ 两格锁（有钥匙 / 无钥匙各一），逐字比对 |
| **非法值回退** | ✅ `garbage` ⇒ `off` + warning（**不是** `strict`、不 panic）|
| **变异对照** | ✅ **真跑两处**：默认值 `off→soft` ⇒ 锁红；非法值回退 `off→strict` ⇒ 锁红 |
| **测试** | `src/engine` **341/341 passed**（新增 5 格）|
| **回滚实测** | ✅ **0.95 秒**（承诺 <10 秒，实测远低于）|

---

## 证据

### ① 先核实了派单的理解 —— **你的理解是对的**

现状（修前）`judged_role_gated` 的 `None` 分支：

```moonbit
None =>
  if declared_pubkey_for(eng, agent) is Some(_) {
    ("Executor", "challenge_required")   // 有钥匙不出示 ⇒ 降权（S3 第九段，已有）
  } else {
    judged_role(eng, agent)              // 无钥匙不出示 ⇒ 自报
  }
```

⇒ **`off` 的定义「只关对无钥匙者的降权那一层」成立**。有钥匙的软强制降权在 `off` 下仍生效。

### ② 实现（`src/engine/auth_mode.mbt`，单一真源）

```moonbit
pub enum AuthMode { Off, Soft, Strict } derive(Eq, Debug)

pub fn auth_mode_parse(raw : String) -> AuthMode   // 纯函数，唯一判定面
pub fn auth_mode_warning(raw : String) -> String   // 非法值才非空
pub fn auth_mode() -> AuthMode                     // **唯一** env 读取点（进程内缓存）
```

**接入 `judged_role_gated`：**

```moonbit
None =>
  match auth_mode() {
    Off    => if declared_pubkey_for(eng, agent) is Some(_) {
                ("Executor", "challenge_required")   // 逐字保持修前行为
              } else { judged_role(eng, agent) }
    Soft   => ("Executor", "challenge_required")     // 无钥匙也降
    Strict => ("Executor", "challenge_missing")      // 见下
  }
```

**⚠️ `strict` 为什么不是 `Err`**：`judged_role_gated` 返回 `(String, String)`，
改签名会波及 5 处调用点（其中 `rsv_set` 的上层签名是 `Result[String,String]`，
`engine_rsv.mbt:602` 已有一段注释解释过同一个决策）。
⇒ 沿用**同一手法**：专用 `role_source = "challenge_missing"`，
与 `challenge_required` 区分（前者「你连公钥都没有」，后者「你有钥匙但没出示」）。

**两个制作过程中踩到的 MoonBit 限制**（已规避）：
- 顶层 `let mut` 不支持（`Error [4074]`）⇒ 用单元素 `Array[String]` 当可变槽（本仓 `s3_pending_nonces` 同族手法）
- `trim()` 返回 `StringView` ⇒ 需 `.to_string()` 才能 `to_lower()`

### ③ 五格锁（`engine_bug470_auth_mode_wbtest.mbt`）

| 锁 | 内容 | 结果 |
|---|---|---|
| A | 解析规则 + **非法值回退 `off`**（`garbage`/`true`/`1`/`sof` 全回 `Off`）| ✅ |
| B | 非法值才有 warning；合法值/未设为空 | ✅ |
| C ⭐ | **`off` 逐字零回归**：有钥匙 ⇒ `("Executor","challenge_required")`；无钥匙 ⇒ 与 `judged_role` 两字段全等 | ✅ |
| D | `soft ≠ off` 且差别只在无钥匙支；两个 tag 可区分 | ✅ |
| E | `strict` 用专用 `challenge_missing`，与 `required` 可区分 | ✅ |

### ④ 变异实测（真跑两处）

**变异 1**：默认值 `off → soft`
```
341 → **340 passed, 1 failed**
  F| bug470_parse_and_invalid_fallback（未设值时代码应回 Off）
```

**变异 2**：非法值回退 `off → strict`
```
341 → **340 passed, 1 failed**
  F| bug470_parse_and_invalid_fallback（garbage 应回 Off，实际 Strict）
```

两处恢复后 **341/341 全绿**，`grep MUTANT-CZ` = 0。

### ⑤ 回滚实测（硬要求⑥）

```
FIST_AUTH_MODE=soft（切到 B）    8.69 秒  OK
★ FIST_AUTH_MODE=off（回滚）     0.95 秒  OK
不设（走 launcher 默认 off）      0.85 秒  OK
```

**⇒ 回滚真实成本 0.95 秒**（首次 8.69 秒含构建缓存冷启，非回滚稳态成本）。

**⚠️ 这不只是「改 env」**：`fist.py` 每次调用都是新进程（node 冷启 + 一次工具调用），
所以这 0.95 秒 = **「改 env 到确认恢复」的真实墙钟**，不是估算。

### ⑥ 启动器注入（决策单硬要求）

`%LOCALAPPDATA%\FIST-Mbt\serve-launcher.cjs`（**已备份** `.bak-bug470`）：

```js
const DEFAULT_AUTH_MODE = 'off';
function authEnv() {
  const explicit = process.env.FIST_AUTH_MODE;
  const mode = (explicit && explicit.trim()) || DEFAULT_AUTH_MODE;
  return { FIST_AUTH_MODE: mode };
}
// 网关 spawn：env: Object.assign({}, process.env, { FIST_NODE: ... }, authEnv())
```

**验证**：`node -c` 语法通过；`DEFAULT_AUTH_MODE = 'off'`；网关 env 已含 `authEnv()`。

**为什么默认值必须写在启动器**：回滚时人要「想起来该设什么」——
写在这里后，**回滚 = 改回 `'off'` 或显式传 `off`**，不需要翻文档。

**`.mcp.json` 不加 `env`**：它走 launcher，launcher 已注入 ⇒ 加了两处就是两个真源。

---

## 分析：为什么 `off` 是「关一层」而不是「全关」

`off` 若真「全关」，意味着**关掉 S3 第九段**（有钥匙不出示 ⇒ 降权）——那是一段**已交付并锁住**的行为。
把它塞进开关里，「上线开关」就变成了「上线一个能回退已交付特性的能力」，那是倒车不是开关。

**本开关的职责是「是否把要求扩展到无钥匙者」** —— 那才是 BUG-470 要 decision 的那件事。

**⇒ 这也让 `off` 的零回归有了明确边界**：`off` 下**必须**逐字保持修前行为，
因为这个档位就是「我还没决定要不要 B」的状态。任何一点差异都等于「上线开关」本身引入了回归。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 🔴 **`strict` 尚未在门层生效**：`judged_role_gated` 只返回 `challenge_missing` 标签，**各门的消费者还没据此拒绝**（`rsv_set`/`rsv_try_set`/`locks_try_acquire`/`claim`）。⇒ **`strict` 当前 = 「降权 + 专用标签」，不是真拒绝。启用前必须补这一步**（决策单也写明 strict 不默认启用）|
| **R2** | `auth_mode()` 进程内缓存 ⇒ 测试切模式需 `auth_mode_reset_cache_for_test()`；生产**不要调** |
| **R3** | `auth_mode_startup_warning()` 已实现但**未在 server 启动处调用** —— 非法值目前只会被缓存成 `off`，warning 打不出来。建议在 `run_server()` 开头加一行 |
| **R4** | `serve-launcher.cjs` **不在 repo 里**（用户目录）⇒ 本单的启动器改动**无法提交到 git**，只能靠本报告与备份留痕 |
| **R5** | 未加 `FIST_AUTH_MODE` 的端到端测试（真实 MCP 调用）—— 现有锁在引擎层，`fist.py` 层的 env 传递已由回滚实测间接验证 |

---

## 建议入档位置

**账本 BUG-470**：保持 OPEN（owner 已批准 B，但 R1「strict 未在门层生效」与 R3「warning 未接线」是剩余项）。

**判例候选**：
> **判例：开关的 `off` 档必须逐字保持修前行为，否则「上线开关」本身就是回归。**
> 尤其当 `off` 是首次默认值时 —— 任何一点差异都意味着**所有用户都被静默改了行为**。
> **⇒ 装开关的第一步不是写新档位的代码，是把 `off` 的现有行为钉成锁。**

> **同族**：与判例-29「机制格 ≠ 实现路径格」互补 ——
> 本条说的是「**加可配置性时，默认值那条路必须被证明没动**」。

---

**提交**：`feat(authz)`。启动器改动在用户目录，**未入 git**（已备份 `.bak-bug470`）。
