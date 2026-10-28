# BUG-472 / BUG-473：两个「死参数」的定夺 · Lane CR · 2026-10-28

> **一个成立、一个误报。**
> BUG-472（`plan` 的 `challenge`）**成立** ⇒ 已**摘掉**（不接线）。
> BUG-473（`execute` 的 `agent`）**不成立** ⇒ `agent` **真的被读**，Gamma 的探针漏了辅助函数。

---

## 一、结论

| Bug | 派单说法 | 核实结果 | 处理 |
|---|---|---|---|
| **BUG-472** `plan.challenge` | schema 声明了但 handler 不读 | ✅ **成立** | **摘掉 schema 字段** + 注释说明为何不接线 |
| **BUG-473** `execute.agent` | schema 声明了但 handler 字面量 0 次 | ❌ **误报** | **不改**（已正确读取）+ 加锁钉住 |

| 项 | 结果 |
|---|---|
| **`plan` 走不走角色取数面** | **不走** —— `FistEngine::plan` 里 `judged_role*` **0 次** ⇒ 摘掉 schema（同 R23 `execute` 定夺）|
| **`execute.agent` 该不该读** | **该读，而且已经在读** —— `execute_write_identity` 第 844 行 `get_str(args, "agent")` |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/server` + `src/engine` **860/860/0** |
| 变异对照 | **真跑**，`cr_01` 精确打红 |

---

## 二、证据

### 2.1 BUG-472：`plan` 不经过角色取数面 ⇒ **摘掉**

```moonbit
// src/engine/engine.mbt:93  FistEngine::plan
let st = parent.get_status()
if ... { return Err("非法拆分: 任务处于 [...]") }
match self.store.update_task(p2) { ... }     // 建子任务
```
**`judged_role(` / `judged_role_gated(` / `judged_role_with_nonce(` 出现 0 次。**
⇒ `challenge` 传进来**没有任何读者** ⇒ 与 R23 对 `execute` 的定夺**同一结论：死参数**。

**处理（`src/server/server.mbt` plan 的 schema）**：
```diff
         "namespace": string_prop("…"),
-        // BUG-430 S3 第三段：可选挑战…
-        "challenge": string_prop("可选：S3 挑战 nonce。⚠️ 须配合 challenge_sig…"),
-        "challenge_sig": string_prop("可选：对 challenge 的 Ed25519 签名 hex…"),
+        // BUG-472：**这里曾声明 `challenge` / `challenge_sig`，但 handler 从未读取**
+        // —— 那是死参数（判例-29 的第三种「假接线」）。
+        // 为什么**摘掉**而不是接线：`FistEngine::plan` **不经过角色取数面**…
+        // ⚠️ 若将来 `plan` 真加了角色门，那时才该按 `claim` 的做法接 challenge ——
+        //    顺序是**先有身份门，再谈认证**。
```

### 2.2 BUG-473：`execute.agent` **真的被读**（误报）

Gamma 的判据是「handler 里 `agent` 字面量 0 次」。但身份解析在**辅助函数**里：

```moonbit
// src/server/server.mbt:833  execute_write_identity
fn execute_write_identity(eng, args, task_id, executor) -> AclIdentity {
  let task_assignee = ... t.get_assignee() ...
  acl_execute_identity(
    get_str(args, "agent"),     // ← ★ 这里真的读了
    executor, acl_arg_given(args, "executor"), task_assignee,
  )
}
```
而 `execute` 的 handler **确实调了它**，并把结果 `who` 传进了门：
```moonbit
let who = execute_write_identity(eng, args, task_id, executor)   // handler:53
...
agent_touch_first_seen(eng, who.raw, ns, "execute", ...)
match agent_write_gate(eng, who, ns) { ... }                      // 门真的用了 who
```

**⇒ BUG-473 不成立。** 实现与 BUG-436 描述的推断链**完全一致**（显式 `agent` > 显式非 manual 的 `executor` > 任务 assignee）。

### 2.3 三格锁（`server_bug472_deadparam_wbtest.mbt`）

| 锁 | 断言 | 防的是什么 |
|---|---|---|
| **`cr_01`** | `plan` 的 schema **不许**声明 `challenge` | 变异（加回）⇒ 红 |
| **`cr_02`** | `FistEngine::plan` 里**不许**出现 `judged_role*` | 若将来真加了角色门 ⇒ 红 ⇒ 提醒「现在该接 challenge 了」|
| **`cr_03`** | `execute` handler **调了** `execute_write_identity`，**且**该辅助函数里**有** `get_str(args,"agent")` | 断言**两段** —— 只看 handler 会漏（gamma 的探针就是这么漏的）|

**变异实测**：`plan` schema 加回 `challenge` ⇒ **523/524**，**`cr_01` 精确打红**。

---

## 三、分析

### 3.1 「声明了但不验」为什么比「没有认证」严重

| | 没有认证 | **声明了但不验** |
|---|---|---|
| 调用方看到 | schema 里没有认证参数 ⇒ 知道没受保护 | **schema 里有**，文案还写「须配合 xxx」|
| 调用方行为 | 不传 | **传了签名/身份，以为受保护** |
| 失败形态 | — | **静默降级**：无错误、无警告、回执正常 |
| 修复触发 | 加认证 | **没人知道要修**（看起来已经做了）|

**⇒ 这是「假绿」在人类侧的对应物**：判据绿了、回执绿了、调用方也以为自己安全了。

**本单的 `plan` 正是这个形态**：文案写「⚠️ 须配合 challenge_sig」——**这句话本身在撒谎**。

### 3.2 22 处（本仓实为 27 处）死参数的三分类判据

派单要求给分类判据。**核心判据是「引擎有没有读者」**：

| 类别 | 判据 | 处理 | 本仓实例 |
|---|---|---|---|
| **① 该接线** | 引擎**有**消费点（如 `judged_role_gated` 读 challenge、`agent_write_gate` 读身份），但 handler 没把参数传下去 | **接线**（照抄已验证的接线）| 若有 ⇒ 真 bug |
| **② 该摘掉 schema** | 引擎**没有**消费点（该参数对实现的语义无关） | **摘 schema** + 注释说明为何不接 | **`plan.challenge`**（本单）|
| **③ 设计如此** | 参数存在但**被服务端覆盖/规范化**，schema 的承诺是「你传了也不算」 | **保留**，但描述必须写清「会被服务端覆盖」 | **`lock_acquire.ts`**（BUG-33：时间戳服务端盖章）、`now` 类参数 |

**本单普查（按工具块逐块扫，跳注释）实际读数**：
```
有身份/挑战参数的工具: 27 个
其中存在死参数: 0 个
```
⇒ **派单说的「22 处」，在本仓当前 HEAD 上已无实例**（`plan` 是本单摘掉的那一个；
`execute.agent` 是误报；`lock_acquire.ts` 属类别 ③ 设计如此，
且我的探针把它判为 OK 是因为代码面里确实出现了 `ts`）。

> ⚠️ **口径说明**：我的普查只覆盖**身份/挑战类**参数
> （`challenge`/`challenge_sig`/`agent`/`by`/`verifier`/`executor`/`created_by`/`ts`/`now`）。
> 其它参数（`split_n`、`meta`、`model`…）不在本单面内。

---

## 四、缺口与风险

1. **本单只处理了身份/挑战类**死参数；其余参数类未普查。
2. **`plan` 仍无身份门**（BUG-471 第 3 批的 5 个之一）——
   摘掉 `challenge` 只是让它「不撒谎」，**不代表 plan 受保护**。
   ⇒ 若第 3 批给 `plan` 加了身份门，那时应**同时**把 `challenge` 按 `cr_02` 的提示接回来。
3. **Gamma 的探针方法有系统性缺陷**：只扫 handler 本体、不跟辅助函数 ⇒ 会误报
   （`execute.agent` 就是这么来的）。**建议其判据加「辅助函数闭包」扫描面**
   —— 我的 `cr_03` 把「两段都断言」写进了锁。
4. **本单第一次自查也犯过同类错**：用「起始行 +230」窗口扫 `agent_register_key`，
   漏掉 270 行处的 `get_str(args,"proof_sig")`，**一度把正确实现判成死参数**
   ⇒ 改用**工具块边界**切分（判例-32 同族：探针先在新样本上标定）。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-472 修复 / BUG-473 判 FALSE_POSITIVE | 账本分别处理；473 附本报告 §2.2 的证据 |
| **「声明了但不验」= 假绿的人类侧对应** | 判例集（与判例-29/30 同族）|
| **死参数三分类判据（接线 / 摘 schema / 设计如此）** | 判例集 —— 可直接作为后续普查的判定标准 |
| **「探针必须跟辅助函数」** | 判例-32 补充：只扫 handler 会漏掉身份解析链 |
| `plan` 的角色门 | BUG-471 第 3 批（加门时同批把 challenge 接回）|
