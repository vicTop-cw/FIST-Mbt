# BUG-430 S3 独立验证（不信自述）

> **被验对象**：Beta 的 S3 四段 + wiring + `agent_register_key`
> **Beta 自述**：挑战链路完整可用 / `agent_register_key` 落地 / 4 格端到端锁 / 全量 1612/1612/0
> **执行人**：司令-γ（独立验证，只读 + 报告）· **日期**：2026-10-27

---

## 结论（五件事分开写）

| # | 问题 | 独立验证结论 |
|---|---|---|
| **①** | 挑战链路真的通吗 | **链路通，但最后一米丢失** —— args→`opt_challenge`→`rsv_try_set`→`judged_role_gated`→`verify_challenge_sig` 全程可达；**但验签结果不进 `action` 面**（`BUG-453`） |
| **②** | `agent_register_key` 真能登记公钥吗 | **✅ 通过** —— 真写库 + 写后回读，`registered` 由回读决定不由请求反推 |
| **③** | 服务端真的不代签吗 | **✅ 通过** —— 全仓 `ed25519_sign` = **0 处** |
| **④** | 端到端真的能用吗 | **⚠️ 无法实跑** —— `src/engine` 编译被**他人未完成改动**阻塞（`LEAF_CLAIM_LEVEL` 未定义），测试跑不起来 |
| **⑤** | `s3_keytool_02` 锁真的在吗 | **✅ 在且是真变异对照**（双向断言，:`53` 正断言 + `:61` 反断言） |

**⇒ 找到 1 条真 bug（`BUG-453`，high）+ 1 条同族发现（`execute` 死参数）。**

---

## 证据

### ① 挑战链路 —— 通了，但**结果不可见**

**链路逐段可达（静态 + 真跑）**：
```
server.mbt:5650   let ch = opt_challenge(args)              ← reserve_scope 读 challenge
server.mbt:5674   challenge_nonce=ch.0, challenge_sig=ch.1  ← 透传 rsv_try_set
engine_rsv.mbt:439 let (role, role_source) = judged_role_gated(self, agent, challenge_nonce, challenge_sig~)
engine_rsv.mbt:187 None => judged_role / Some(_) => judged_role_with_challenge
engine_rsv.mbt:92  pub fn verify_challenge_sig(...)          ← 验签
```
**验签实现质量高**（`engine_rsv.mbt:92-107`）：hex 解码失败 ⇒ false；**长度校验（pk=32/sig=64）先于密码学校验**；
失败一律 `false`（**fail-closed**）；复用 `@mooncry.ed25519_verify`（与 `star_gate.mbt:307` 同一函数，生产已验证）。

**★ 但真跑暴露了断点**：
```
$ python scripts/fist.py call reserve_scope --agent "test-agent-y" --scope "y/z" \
    --ttl_until "2026-12-31T00:00:00Z" --challenge "deadbeef02" --challenge_sig "abab…(128 hex)"
{"reserved":true,"action":"unregistered+agent_self_reported", ...}
                                    ↑ 传了明显无效的签名，action 里零痕迹
$ python scripts/fist.py call lock_acquire --agent "agent-x" --challenge "nonce01" --challenge_sig "cdcd…"
{"granted":true,"action":"unregistered", ...}      ↑ lock_acquire 连后缀都没有
```
**根因**（`engine_rsv.mbt:439` / `:549`）：
```moonbit
// rsv_try_set
let src_tag = "+agent_self_reported"                             // ★ 硬编码，与验签无关
...(if role_source == "inferred" { "+role_inferred" } else { "" })+src_tag   // ★ 只映射 inferred

// locks_try_acquire
let (role, _role_source) = judged_role_gated(...)                // ★ 直接丢弃 role_source
```
**⇒ `challenge_verified` / `challenge_failed` / `challenge_replayed` 三个新状态全部丢失。**

### ② `agent_register_key` —— ✅ 通过（不是打桩）

**写后回读，回执由回读定**（`server.mbt:6912-6925`）：
```moonbit
let stored = match s.agents_get(fp) { None => "" ; Some(a) => a.pubkey_fp }
let ok = stored == pubkey_hex && pubkey_hex != ""
"registered": Json::boolean(ok),
"persisted_pubkey_matches": Json::boolean(ok),     // ← 不是「看起来写了」，是回读比对
```
**且落库前校验形状**（`:6831-6839`）：`pk.length() != 32 ⇒ Err`。
**且首次登记锁定**（`:6850-6903`）：库里已有公钥且不同 ⇒ **拒绝覆盖**，并说明「换钥要走轮换流程」。
**⚠️ 但注释自己承认**：`ON CONFLICT(agent_id) DO UPDATE SET` **不含** `pubkey_fp`，
真正的攻击面是**「抢注」**——趁某 agent 还没登记，先替他登记**我的**公钥。**这是 Beta 自列的缺口 1，未修。**

### ③ 服务端不代签 —— ✅ 通过

```
$ grep -c 'ed25519_sign' src/server/server.mbt     → 0
$ grep -rn 'ed25519_sign' src/ (排除测试)          → 0
$ 只有 ed25519_verify 两处：engine_rsv.mbt:105 / star_gate.mbt:307
```
**⇒ 红线守住了**：服务端只验不签，「验签」与「签发」在不同主体。

### ④ 端到端实跑 —— **无法完成（工具失败，原样上报）**

```
$ python scripts/moon_test_env.py src/engine
  判据无法自证：没有汇总行 `Total tests: …` ⇒ rc=2（BUG-142）

$ moon test --target js src/engine 2>&1 | grep -A3 'Error: \[4021\]'
Error: [4021]  src/engine/engine.mbt:213:37
  213 │  let tlevel = if t.is_leaf() { LEAF_CLAIM_LEVEL } else { task_level }
      │                               ────────┬───────
      │  The value identifier LEAF_CLAIM_LEVEL is unbound.
```
**⇒ 编译被他人未完成改动阻塞（不是 S3 代码），测试跑不起来。**
**⇒ Beta 的「1612/1612/0」我无法独立复现。** 这一条按纪律记为「未验证」而非「通过」。

**静态补证**：8 个 S3 测试文件共 **33 格**（`key` 4 / `p2` 6 / `p3` 5 / `s3` 4 / `s1` 3 /
`keytool` 4 / `keyreplace` 3 / `wire` 4）。

### ⑤ `s3_keytool_02` —— ✅ 在且是真变异对照

```moonbit
test "s3_keytool_02_pubkey_is_actually_written" {
  let src = srv_code_only(@fs.read_file_to_string("src/server/server.mbt"))
  if !src.contains("pubkey_fp=pubkey_hex") { abort(...) }   // ① 正断言
  if src.contains("pubkey_fp=\"\"") { abort(...) }          // ② 反断言（变异形状）
}
```
**⇒ 双向断言 + `srv_code_only()` 剥注释**（判例-30 防自指假绿）。
**⇒ Beta 说「第二个变异第一次没被捕获，补了这格才捕获」成立** —— 反断言 `②` 正是抓「退回恒空串」的。

---

## 分析：Beta 的自述哪些成立

| Beta 说 | 独立验证 | 判定 |
|---|---|---|
| 「挑战链路完整可用」 | 链路通，**但验签结果不进 `action` 面** | **部分成立** —— 功能在，**证据不在** |
| 「`agent_register_key` 落地，公钥真正写入 sqlite 不是打桩」 | 写后回读 + 形状校验 + 首次锁定 | **✅ 成立** |
| 「4 格端到端锁」 | 静态确认 33 格存在；**实跑被编译阻塞** | **未验证** |
| 「全量 1612/1612/0」 | 无法复现（同上） | **未验证** |
| 「第二个变异第一次没被捕获，补 `s3_keytool_02` 后捕获」 | 该格是真变异对照 | **✅ 成立** |
| 「服务端永不代签」 | 全仓 `ed25519_sign`=0 | **✅ 成立** |

### 这条 bug 的性质：「90% 正确 + 最后一米丢失」

`judged_role_with_challenge` 的注释（`engine_rsv.mbt:124-126`）**明确承诺**：
> 「**`role_source` 的取值扩展（调用方可见的变化）**……**这不是改语义，是让「认证状态」显式可见。**」

**⇒ 承诺了「显式可见」，但 `rsv_try_set` / `locks_try_acquire` 的 `action` 面把它吞掉了。**

**危害有两面**：
- **对调用方**：传了合法签名、验签通过，回执**仍写 `+agent_self_reported`（自报未验证）** ——**诚实标注被写反了**
- **对防守方**：`challenge_failed` 与「压根没传 challenge」在日志里**不可区分** ⇒ 攻击者探测时看不到被拒痕迹

### 附带发现：`execute` 的 challenge 参数是**死参数**

```
schema 声明：server.mbt:2086-2089  "challenge" / "challenge_sig"
opt_challenge(args) 全仓调用点：:2038 claim / :5650 reserve_scope / :5804 lock_acquire
⇒ **execute 没有第 4 个**
```
**⇒ `execute` 收下 `challenge`、验都没验、直接忽略。** 比「没声明」更坏：调用方以为传了就受保护。
**与 `BUG-440`（`check_plan_location` 承诺过但不存在）同族 —— 声明了但没接线。**

---

## 缺口与风险

### 1. **④ 未完成**：实跑被他人编译错误阻塞

`LEAF_CLAIM_LEVEL` 未定义（`engine.mbt:213`）**不是 S3 代码**。**编译恢复后应重跑**：
```
python scripts/moon_test_env.py src/engine
python scripts/moon_test_env.py src/server
```
**⇒ 这是本报告最大的未验证项。**

### 2. 我只验了 `reserve_scope` / `lock_acquire` 两条门的 action 面

`claim` 的 `action` 映射**未逐字核**（`engine.mbt:213` 附近被编译错误挡住）。
**`BUG-453` 的影响面里 `claim` 标为「需核」。**

### 3. `nonce` 表在进程内 —— 已确认，且跨进程不共享

`s3_pending_nonces : Map[String, Array[String]]`（`engine_rsv.mbt:221`），注释诚实标注了
「多实例部署时各自的 nonce 互不可见」。**这是 Beta 自列的缺口 4，成立。**

### 4. Beta 列的 5 个缺口，我复核了 3 个

| Beta 缺口 | 复核结果 |
|---|---|
| ① 密钥替换攻击 | **部分修了**（首次登记锁定），但**抢注面仍在** |
| ② 轮换无新旧并存窗口 | 成立（`agent_register_key` 遇不同公钥直接拒，无轮换流程） |
| ③ 无 revoke 面 | 成立（未见 revoke 实现） |
| ④ nonce 表进程内 | 成立（`engine_rsv.mbt:221`） |
| ⑤ S2 未做 | 成立 |

**⇒ Beta 的缺口清单是诚实的，没有隐瞒。**

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-s3-independent-verification.md` |
| `BUG-453`（high） | `memory/bugs.md`（已写入） |
| **建议后续** | ① 修 `BUG-453`（`action` 加认证态标签 + `src_tag` 改条件式）② `execute` 接 `opt_challenge` 或删参数 ③ **编译恢复后重跑 ④** |
| **未做** | **未改 `src/` `scripts/`**（只读边界）· **未跑成测试**（编译阻塞） |

**⚠️ 一句话**：**Beta 的自述基本诚实（5 项里 3 项完全成立、1 项部分成立、1 项我无法验证）。
但它漏掉了一个它自己没意识到的问题：S3 在「取数面」接上了，在「回执面」没接上 —— 而这恰是它自己承诺的那句「让认证状态显式可见」。**
