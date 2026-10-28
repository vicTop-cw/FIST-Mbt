# BUG-430 收口：产品层登记 + 生产路径验证

> 2026-10-28 · Lane CB · 产出 `reports/` + 账户报告

---

## 结论

| 项 | 结果 |
|---|---|
| **① 产品库登记公钥** | ✅ **成功** —— `fist-mbt.db` 的 `agents` 表 **1/6 非空**（`4fb5d1353487b451`） |
| **② 生产路径走通 challenge** | ✅ **成功** —— `reserve_scope` 返回 **`unregistered+challenge_verified`** |
| **③ 关闭口径** | **选 ③ 部分关闭**（拆 BUG-430a 已关 / BUG-430b 仍 OPEN），**并追加一条新前置** |

**一句话**：**产品路上有车了**（能登记、能验签、能拿到 `challenge_verified`），
**但这辆车只能由我自己手动推上去** —— 产品面上**没有任何渠道**让一个已登记的 agent 拿到服务端签发的挑战。

---

## 证据

### 1. 先发现一个陷阱：`fist.py` 默认**不写产品库**

```python
# scripts/fist.py:44-48
# BUG-122 同型收口：不带 FIST_DB_PATH 裸跑会把演示数据写进仓库根的自举台账 fist-mbt.db。
if not (os.environ.get("FIST_DB_PATH") or "").strip():
    os.environ["FIST_DB_PATH"] = os.path.join(_FIST_ROOT, "temp", "fist.db")
```

**我第一次登记时工具回 `registered: true`，但产品库读到 0/5** —— 因为数据去了 `temp/fist.db`。
**⇒ 「工具回执说成功」与「产品库真的变了」是两件事**（判例-29 的又一形态）。
**必须显式设 `FIST_DB_PATH=fist-mbt.db` 才是产品登记。**
（这是设计如此的保护，不是 bug —— 但它让「以为登记了其实没有」成为默认结果。）

### 2. 产品库真的有了公钥

```sql
SELECT agent_id, role, pubkey_fp FROM agents ORDER BY agent_id;
```
```
305ab0571c8193e8  Executor  <空>
4a311de70f78894a  Executor  <空>
4fb5d1353487b451  Executor  443688424a7a270b8dd1ebd192d8521073cf7e12dd2027d88e9c659c308ecb38  ← 非空
b2acdbf4c6cea9fe  Leader    <空>
c335207187d95324  Executor  <空>
e58321ba3709c5b3  Executor  <空>
```
**⇒ pubkey_fp 非空：1 / 6**

**登记走的是真两步流程**（不是直接写库）：
```
① agent_register_key（不带 challenge）⇒ mode=challenge_issued, challenge="fist-s3-challenge:v1:lane-cb-s3:1"
② 私钥签 ⇒ proof_sig（128 hex）
③ agent_register_key（带 challenge + proof_sig）⇒ mode=registered, persisted_pubkey_matches=true
```

### 3. 生产路径三组对照（`reserve_scope`，`FIST_DB_PATH=fist-mbt.db`）

| 场景 | 回执 `action` | 判读 |
|---|---|---|
| **A** 带 challenge + **真签名** | **`unregistered+challenge_verified`** | ✅ **验签通过** |
| **B** 不传 challenge | `unregistered+agent_self_reported` | 自报（未认证） |
| **C** 带 challenge + **错签名** | `unregistered+challenge_failed` | fail-closed |

**三条预占都真的落库**（`reservations` 表 3 行），事后已清理。

**⚠️ 诚实修正**：`action` 前缀是 `unregistered+`，因为该 agent 的 `agent_type` 是 `executor`、
不在某些「已登记类型」白名单里 —— 但 **`challenge_verified` 段是真的验签通过**，
与 `challenge_failed` / `agent_self_reported` 形成明确三态区分。

### 4. ⚠️ 产品层的**真缺口**（本单最重要的发现）

```
agent_register_key(已登记 agent, 不带 challenge)
  ⇒ {"mode":"already_registered", ...}      ← **回执里没有 challenge 字段**

claim 工具接受参数：agent, assignee, inject, namespace, task_id
  ⇒ **不接受 challenge / challenge_sig**

只有 reserve_scope / lock_acquire 接受 challenge
```

**⇒ 产品面上，一个已登记的 agent 没有任何渠道拿到服务端签发的挑战。**
我这次能验签成功，是因为**手工拼出了 nonce 形态**
（`fist-s3-challenge:v1:<agent>:<counter>`，纯函数、可复现）。

**⇒ 这意味着：`challenge_verified` 在生产上**可以**被触发，但触发它需要调用方**自己构造** nonce。**

---

## 分析：为什么「路径存在」不等于「默认走」，以及这里更糟一层

**派单的选项 ② 说得对**：S3 是**可选**的 —— 不传 challenge 就走原逻辑（证据 B）。

**但真实情况比 ② 描述的更糟**：

| 层次 | 状态 |
|---|---|
| 引擎层 | ✅ S3 八段全落地，验签正确 |
| 测试层 | ✅ `s3_key_01` 端到端有车 |
| **产品库** | ✅ **已有真公钥**（本单成果） |
| **产品调用面** | ❌ **没有「拿挑战」的通道**，也没有工具的 challenge 是**默认**参数 |

**⇒ 不是「有路没人走」，是「路上缺一个收费站」** ——
车（客户端）到了入口，但**没有取票窗口**，只能自己伪造一张票。

**为什么这仍然是真进展**：
- 证明 `agents.pubkey_fp` → `verify_challenge_sig` → `reserve_scope` 这条**代码路径在生产库上真的通**
- 证明了 fail-closed（错签名 `challenge_failed`）
- 证明了「不传 challenge ⇒ 明确标注 `agent_self_reported`」而非静默

**但不能据此说「S3 可用了」** —— 一个真实客户端**无法从工具面取得挑战**。

**关于关闭口径，我选 ③，但理由与派单不同**：

- ✅ **BUG-430a 可关**：S3 骨架 + 八段 + 产品库有真公钥 + 存在「调用方无法自报」的**判定路径**
  （`challenge_verified` vs `challenge_failed` 三态已实测）
- ❌ **BUG-430b 必须 OPEN**：**产品面缺「签发挑战」的入口**，且 `claim` 不接受 challenge
  —— 这比「默认不走」更基础：**连"可选地走"都做不到**

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | 🔴 **产品面无挑战签发入口**：已登记 agent 调 `agent_register_key` 只得 `already_registered`（无 challenge）。**需新增独立工具**（如 `agent_issue_challenge`）或让 `agent_register_key` 对已登记者也签发 |
| **R2** | 🔴 **`claim` 不接受 `challenge`/`challenge_sig`**（只有 `reserve_scope`/`lock_acquire` 接受）⇒ 最重要的生命周期工具无法认证 |
| **R3** | `fist.py` 默认写 `temp/fist.db` ⇒ **极易误判「登记成功」**。建议它回执里明示实际写的是哪个库 |
| **R4** | `action` 前缀 `unregistered+` 的语义：该 agent `agent_type=executor` 未进白名单。**不验证不影响验签结论**，但会让调用方误读成「没注册」 |
| **R5** | 私钥在 `temp/cb/agent.key`（gitignore 覆盖）。**已确认未进 repo**，但**没有备份/轮换预案** |

---

## 建议入档位置

**账本**：
- **BUG-430a**（新拆）：S3 路径存在 + 产品库有真公钥 → **可标 FIXED**
- **BUG-430b**（新拆）：产品面缺挑战签发入口 + `claim` 不接受 challenge → **OPEN**

**判例候选**：
> **判例：`FIST_DB_PATH` 默认改道 ⇒「回执说成功」与「产品库真的变了」分叉。**
> `fist.py` 为防污染把默认库改到 `temp/fist.db`，于是 `agent_register_key` 回 `registered: true`
> 而产品库仍是 0 行。**⇒ 任何「写产品状态」的操作，回执必须带上「写到哪个库」，否则成功不可信。**

---

**私钥**：生成在 `temp/cb/agent.key`（已 gitignore），**未进 repo，报告不贴内容**。
**生产库测试预占已清理**（`s3prod-*` 3 条已删），**只保留公钥登记这一项成果**。
