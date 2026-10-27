# BUG-430 / S3 **第二段**：四条门接入 + nonce 防重放 · Lane BG · 2026-10-27

> **第二段做完，S3 骨架**接进了四条门**且 nonce 不可重放。但 BUG-430 仍 OPEN** ——
> 因为 `pubkey_fp` 仍是**死承诺**（无公钥 ⇒ 线上没有任何 agent 能通过挑战）。
> 这是**正确的 fail-closed 行为**，不是 bug。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 接了几条门 | **4 / 4**（`rsv_set` / `rsv_try_set` / `locks_try_acquire` / `claim`）|
| nonce 防重放 | ✅ **一次性消费**（消费即删除；重复提交 ⇒ `challenge_replayed`）|
| 变异对照 | **3 个变异全部真跑**，各自精确打红 |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/engine` **264/264/0**；全量 **1595/1595/0** |
| **零回归** | ✅ 不传 challenge ⇒ **行为完全不变**（`rank_gate` 3 格关键验证）|
| BUG-430 | **仍 OPEN**（缺：公钥登记 + 客户端签名回传）|

---

## 二、证据

### 2.1 四条门（逐条，`文件:行`）

| # | 门 | 位置 | 改动 |
|---|---|---|---|
| 1 | `rsv_set` | `engine_rsv.mbt:378` | 加 `challenge_nonce~ : String? = None`，改调 `judged_role_gated` |
| 2 | `rsv_try_set` | `engine_rsv.mbt:429` | 同上 |
| 3 | `locks_try_acquire` | `engine_rsv.mbt:538` | 同上 |
| 4 | `claim` | `engine.mbt:182` | 加同参数，改调 `judged_role_with_nonce`（**带 nonce 消费**）|

### 2.2 ⚠️ 关键设计修正：`judged_role_gated` vs `judged_role_with_challenge`

第一段的 `judged_role_with_challenge` 在 `None` 时返回 `"unauthenticated"`。
**把它直接接到四道门上 ⇒ 实测立刻打红 3 格 `rank_gate`**——
因为那 3 格的文案断言 `role_source=inferred`，而 `declared`/`inferred` 是**现网语义**。

**⇒ 第二段新增 `judged_role_gated`，`None` 分支原样返回 `judged_role` 结果（零回归）**：

```moonbit
pub fn judged_role_gated(eng, agent, challenge_nonce) -> (String, String) {
  match challenge_nonce {
    None => judged_role(eng, agent)          // ← 原样返回，一个字节都不改
    Some(_) => judged_role_with_challenge(eng, agent, challenge_nonce)
  }
}
```

**语义：加严不放宽** —— 不传挑战 = 维持现状；传了挑战 = **必须验过才给真角色**。
真正「没挑战就不给高权」是**第三段（全量切换）**，本段刻意不做，以免半途改坏现网。

### 2.3 nonce 存储与一次性消费

```moonbit
// 进程内表：key = agent 归一化 fp，value = 已签发未消费的 nonce 数组
pub let s3_pending_nonces : Map[String, Array[String]] = Map([])

// 签发：登记为待消费
pub fn FistEngine::s3_issue_challenge(self, agent, counter) -> String

// 消费：查到即删除（原子）；第二次查必空 ⇒ 防重放
pub fn s3_consume_nonce(agent : String, nonce : String) -> Bool
```

**为什么是「消费即删除」而不是「标记 consumed」**：表不会无限增长，且**不存在
「标记了但没生效」的中间态**（那正是 BUG-439/441 的病态形状）。

**验签失败不烧 nonce**：`judged_role_with_nonce` 只在**验签通过后**才消费 ⇒
合法调用方不会因为一次失败就白白重试。

**新增 `role_source` 取值：`"challenge_replayed"`。**

### 2.4 六格锁 + 三个变异（**全部真跑**）

| 锁 | 断言 |
|---|---|
| `s3_p2_01` | 四条门都接受 `challenge_nonce` 参数（行为不崩）|
| `s3_p2_02` | **实现路径格**：源码里 `judged_role_gated(self, agent, challenge_nonce)` 出现 ≥3 次 + `claim` 用 `judged_role_with_nonce` |
| `s3_p2_03` | **nonce 不可重放**（第二次消费必 false）|
| `s3_p2_04` | 不同 nonce 互不影响 |
| `s3_p2_05` | 没签发过的 nonce 消费必失败 |
| `s3_p2_06` | **零回归契约**：`judged_role_gated(…, None) == judged_role(…)` |

**变异实测**：

| 变异 | 改了什么 | 结果 |
|---|---|---|
| **M1** | 一道门（`rsv_set`）改回裸 `judged_role` | **263/264**，**只有 `s3_p2_02` 红** |
| **M2** | `s3_consume_nonce` 不真消费（恒 true）| **262/264**，`s3_p2_03` + `s3_p2_04` 红 |
| **M3** | `judged_role_gated` 的 `None` 改标 `unauthenticated` | **260/264**，`s3_p2_06` **+ 3 格 `rank_gate`** 红 |

**M3 最有价值**：它复现了我中途踩的真实后果 ——
**改 `None` 语义会打红 3 格现网测试**。现在有锁守着，下一个人不会重蹈。

---

## 三、分析

### 3.1 为什么四条门都要接

**只接一个门 = 没接。** 四道门各自独立判定身份，承接不同攻击面：
- `rsv_set` / `rsv_try_set` ⇒ 占位（scope 预订）
- `locks_try_acquire` ⇒ 文件锁
- `claim` ⇒ 任务认领

若只给 `claim` 接挑战，攻击者改用 `reserve_scope(agent="leader")` 照样能占住 Leader 的工作面 ——
**而 scope 预订是「改文件」的前置**。**四道门是四个独立的越权入口**，接漏一个就漏一个面。

### 3.2 为什么 nonce 必须一次性消费

**不消费的 nonce = 长期通行证。** 攻击者只要截获过一次 `(nonce, sig)` 对，
就能无限重放 —— 而**签名本身是长期有效的**（Ed25519 签名不绑定时间）。
nonce 的唯一作用就是**让每次认证只能用一次**；不消费，等于挑战机制形同虚设。

---

## 四、缺口与风险（第三段要做什么）

1. **`pubkey_fp` 是死承诺（BUG-403）** —— `server.mbt:649` 明写「全仓无任何代码真正派生它，
   所有写入点恒传 `pubkey_fp=""`」。
   **⇒ 线上没有任何 agent 有公钥 ⇒ 传 challenge 的调用一律 `challenge_failed`。**
   **第三段必须做**：给 `agents_register` 接线公钥录入入口（`server.mbt`，HumanSteward 面）。
2. **`s3_last_sig_probe` 仍是占位**（返回空串）⇒ 即使有公钥也验不过。
   **第三段必须删掉它**，换成「调用方提交的签名」真实来源（**删，不是填** —— 填了等于绕过 S3）。
3. **nonce 表是进程内的** ⇒ 多实例部署时各自的 nonce 互不可见（跨进程不共享）。
   单实例 OK；多实例需落库（`store_sqlite.mbt`，HumanSteward 面）。
4. **`challenge_nonce` 尚未暴露到 MCP 工具入参** ⇒ 现网调用方**无法**传挑战
   （`server.mbt` 是 HumanSteward 面）。这使本段**对现网零影响**——
   既是零回归的原因，也是**还没生效**的原因。
5. **`pubkey_fp` 若历史数据是短指纹** ⇒ 会因长度 ≠ 32 字节而 fail-closed
   ⇒ 表现为「所有老 agent 都 challenge_failed」。第三段要给「老 agent 怎么办」的方案。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| S3 第二段 | BUG-430 挂 `- s3-phase2:`，**状态保持 OPEN** |
| **「加严不放宽」的设计取舍** | 判例集：本段刻意不改 `None` 语义，因为那是第三段的事 |
| **M3 变异（改 `None` ⇒ 打红 3 格现网测试）** | 判例实例：「改语义前先看谁依赖它」 |
| `pubkey_fp` 死承诺是 S3 的真正阻塞 | BUG-430 正文**风险项第一条**（比握手更难，因为在 HumanSteward 面）|
