# R19 · 未实现计划检查 + BUG-430 S3 方案细化

> 2026-10-27 · Lane AY · 未改 `src/` `scripts/` `docs/` · **任务1=§1；任务2=§2**

---

# 任务 1：未实现计划检查

## 1.1 `docs/plans/` 全部提案（4 份）

| 提案 | status | decisions |
|---|---|---|
| `2026-10-22-fist-dir-layout-governance` | **已定案** | ✅ DEC-001 |
| `2026-10-22-rx-mbt-lightweight` | **已定案** | ✅ DEC-002 |
| `2026-10-24-wt03-sparse-scripts` | **提案中** | ❌ 无 |
| `2026-10-26-4pools-rhop-roadmap` | **提案中** | ❌ 无 |

**⇒ 2 份已定案、2 份提案中；decisions 与已定案一一对应，无缺失。**

## 1.2 ⭐ 未实现计划清单

### ① `rx-mbt-lightweight` —— **0/4，全部未实现**

提案裁决顺序 **A1 限速 → A2 轮询改事件 → A3 递归用 Itor → B1 熔断时钟复用**，每项 100~500 行。

**决定性读数**：
```
$ grep -rn "@rx\." src/ --include=*.mbt | grep -v _test/_wbtest
src/ops/ops_commissar.mbt → @rx.Observer        ← 全仓**只有 1 处**
```
**⇒ 与定案时（DEC-002 记「全仓仅 1 处使用」）完全相同 ⇒ 5 天未动。**

| 项目 | 实现状态 |
|---|---|
| A1 限速换库（`model_router` 5h 窗口 → `rate_limit`/`throttle`） | ❌ 零实现 |
| A2 轮询改事件（`ops_watchdog`/`ops_heal`/`ops_heartbeat` → `interval`+`TriggerRegistry`） | ❌ 零实现 |
| A3 递归用 Itor（`task_plan_deep` → `Itor.send_value`） | ❌ 零实现 |
| B1 熔断时钟复用（保留三态+`probe_limit`，底层换 `Clock`） | ❌ 零实现 |

#### ⭐ R1 实测：`rx-mbt-governance` 命名空间**根本不存在**

DEC-002 后续动作 1：「以功能 F 发布到 `rx-mbt-governance` 命名空间，前置依赖功能 C」。
**遍历全部 db 查 `ns LIKE '%rx%' OR description LIKE '%rx-mbt%' OR '%功能 F%'` → **0 条命中**。**

**⇒ 不是「等前置功能 C 而阻塞」，是「定案后从未排期」——任务都没建。**
**⇒ 遗忘的机制：定案记录写了归属，但**归属动作本身没执行**。**

### ② `fist-dir-layout-governance` —— **部分实现，1/6**

提案 §3.1 规定 `.fist-mbt/` 下 6 个子目录，实测：
```
✅ .fist-mbt/data
❌ pool / state / logs / tmp / cache    ← **5 个都不存在**

根目录污染仍在：*.db 85 个（提案 §一.2：「95 个 *.db 不该进主仓」）
                temp_*/build*.log 35 个；杂目录 6 个
```
**⇒ 只建了 `data/` 一个；清理根目录那部分完全没做 —— 而那恰是提案的核心动机。**

## 1.4 `reports/` 里 20 份计划类文档

**其中 15 份本身是「检查计划落地」的产物 ⇒ 被遗忘的只有 §1.2 两份。**

---

# 任务 2：BUG-430 S3 方案细化

## 2.1 `pubkey_fp` 接线 —— 字段在，链路没接

```
store_sqlite.mbt:133    agents 表 ... pubkey_fp TEXT NOT NULL DEFAULT ''   ← 字段在
store_sqlite.mbt:2731   结构体字段；2756 参数；2808 落盘 SqlValue::Text
server.mbt:711          pubkey_fp=""                                       ← **恒传空串**
```

**⭐ `server.mbt:646-653` 注释自承**：
> **`pubkey_fp` 当前未接线（BUG-403）** …… 所有写入点恒传 `pubkey_fp=""`——**那是死承诺**……
> `pubkey_fp` 必须视为占位，**不得在安全断言里依赖**。

**四段链路**：生成 ❌（全仓无 `sign`/`verify`/`nonce`；`challenge_strategies` 是**任务进阶变体**，与身份无关）｜ 登记 ⚠️ 通道通但恒空串 ｜ 挑战 ❌ ｜ 验签 ❌

## 2.2 MCP 启动流程 —— 无 per-connection 上下文、无握手

```
server.mbt:296-311   priv struct DebateSession { sessions: Map[String, DebateSession] }
                     ← **六顶帽辩论**的会话，与 MCP 连接无关
```
**⇒ 全仓 `session` 只有这一种；MCP 连接与 `agent` 标识零绑定；没有挑战握手。**

## 2.3 S3 可行吗 —— **可行（协议不阻碍），建议先 S3-lite**

**MCP stdio 是双向 JSON-RPC，可在 `initialize` 后、首次工具调用前插 challenge/response
⇒ 不是「协议不支持」，是「没实现」。**

### 真签名版要新建的 5 处

| # | 新建/改 | 关键点 |
|---|---|---|
| 1 | **新表 `agent_challenges`** = `(agent_id, nonce, issued_at, consumed)` | **现有 schema 无此位** |
| 2 | `issue_challenge(agent_id) -> nonce` | 随机 nonce 落表 |
| 3 | `verify_signature(pubkey_fp, nonce, sig) -> Bool` | 🔴 **MoonBit 内置无 Ed25519** ⇒ **最大不确定项 R3** |
| 4 | 客户端生成 keypair、私钥签名 | — |
| 5 | MCP 握手 + 回退策略 | `pubkey_fp=""` 旧 agent 怎么办（**决定向后兼容是否断裂**） |

**⇒ 第 3 项是整个方案的成败点。**

### ⭐ 最小可验证里程碑

**不从握手开始，从纯函数开始。第一格**：
```
test "s3_min_01_no_nonce_no_leader"
  assert_eq(judged_role_with_challenge(eng, "fist-mbt", nonce=None),
            ("Executor", "unauthenticated"))
```
**⇒ 它证明「挑战真的接进了角色取数面」，而不是「写了个 verify 没人调」**（判例-29）。

**第二段**：`s3_min_02_wrong_sig_rejected` + `s3_min_03_correct_sig_allowed`（防修过头）
+ **`s3_min_04` 变异对照**（verify 恒 true ⇒ 格 2 必红）。

**⇒ `s3_min_01` 落地 = 骨架通了；`s3_min_02/03` 落地 = 真验签生效。**

### S3-lite（建议先做）

**不引入真密码学**：server 启动生成**随机** `session_token`（`@random`，非时间戳）写
`%LOCALAPPDATA%\FIST-Mbt\session.token`；客户端读它并每次带上；`judged_role` 校验。
**能挡**跨机器冒充与重放；**不能挡**同机器冒充（读同一文件即得）。**成本 ~1-2 天，不需新表。**
**⇒ 它能让 `s3_min_01` 先绿** —— 「没 token 就拿不到高权」这条结构性结论与是否真密码学无关。

---

## 分析（≤300 字）

**两份计划没实现，答案不同，共性都是「定案 ≠ 排期」。**

`rx-mbt-lightweight`：DEC-002 把归属定为「纳入 `rx-mbt-governance` 作为功能 F」，
**但该命名空间与任务都不存在** ⇒ 归属动作从未执行。**它不是阻塞，是「从未进入任何待办列表」**——
最危险的遗忘形态：文件写着「已批准」，系统里查不到任何痕迹。

`dir-layout-governance`：只建 `data/` 一个，**核心动机「清理根目录 85 个 db」完全没做** ⇒ 部分执行后停手。

**S3**：协议不阻碍，但验签是硬技术依赖（R3）。**建议 S3-lite 先行**。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | ~~未核 `rx-mbt-governance` 有无功能 F~~ ✅ **已核：命名空间与任务都不存在 ⇒ 从未排期** |
| **R2** | `reports/` 那 20 份只做分类判读，未逐份读 status |
| **R3** | 🔴 **MoonBit 是否有可用 Ed25519/签名库未核** —— 直接决定真签名版可行与否 |
| **R4** | 未核两份提案中提案内容（按派单只要求「列出」，已列） |
| **R5** | S3-lite 的 token 随机源未核（`@random` 可用性/种子问题） |

---

## 建议入档位置

**直接回答用户目标「使得未实现的计划落地」**：
> **有，2 份。**
> ① **`rx-mbt-lightweight`** —— 已批准 5 天，A1/A2/A3/B1 **四项全部零实现**（`@rx.` 仍为 1 处），
>    **且 `rx-mbt-governance` 命名空间与功能 F 任务都不存在 ⇒ 从未排期。**
> ② **`dir-layout-governance`** —— 6 个子目录只建了 `data/` 1 个；根目录仍有 85 `*.db` + 35 log + 6 杂目录。
> 另 2 份（`wt03-sparse-scripts`、`4pools-rhop-roadmap`）**提案中**，不属「未实现」。

**账本建议**：新立 2 条 `[plan]` 落地账；**BUG-430 维持 OPEN**。

**判例候选**：
> **「已定案」不等于「已排期」。** 定案记录很完整（三点裁决、四阶段顺序、验收硬门），
> **但归属推给了「依赖功能 C」—— 于是它变成「等人的计划」，谁也不记得它还没动。**
> **⇒ 定案记录必须带可核的排期锚点（任务 id / 命名空间），否则「已批准」就只是存档。**

---

**未改 `src/` `scripts/` `docs/`。未调 `bug_fix`。**
