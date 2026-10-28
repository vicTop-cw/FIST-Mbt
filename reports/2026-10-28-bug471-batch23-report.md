# BUG-471 批 2 + 批 3：剩 7 个工具的身份门 · Lane CT · 2026-10-28

> **14 个生命周期工具现在全部有门，无任何身份门的工具：0 个。**
> 但「有门」不等于「同强度」—— 本单的核心是**按动作性质分三档**。

---

## 一、结论

### 1.1 7 个全覆盖

| 工具 | 批次 | 身份来源 | 处理 |
|---|---|---|---|
| **`submit`** | 批2 质量闸门 | **新增 `agent`** | `agent_write_gate(eng, acl_claim_identity(agent, agent), ns)` |
| **`reject`** | 批2 质量闸门 | **复用 `by`** | `… acl_claim_identity(by, by) …` |
| **`plan`** | 批3 状态类 | **复用 `by`** | 同 reject |
| **`retry`** | 批3 状态类 | **新增 `agent`** | 同 submit |
| **`pause`** | 批3 状态类 | **新增 `agent`** | 同 submit |
| **`resume`** | 批3 状态类 | **新增 `agent`** | 同 submit |
| **`reopen_task`** | 批3 状态类 | **新增 `agent`** | 同 submit |

> ⚠️ 派单说「`reject` 有 `by`、其余 6 个需新增 `agent`」—— **实测 `plan` 也有 `by`**，
> 所以是「2 个复用 `by` + 5 个新增 `agent`」。

### 1.2 ★ 14 个的最终覆盖率（普查实测）

```
生命周期工具命中: 14 / 14
无任何身份门: 0 个
```

| 有 ACL/角色门（12）| 仅 ns 合法性门（2）|
|---|---|
| `claim` / `execute` / `verify` / `submit` / `reject` / **`plan`** / **`retry`** / **`pause`** / **`resume`** / **`reopen_task`** / `archive` / `delete` | `publish` / `publish_parallel`（**特权路径**，口子是 S1 的 `created_by` 自报，BUG-464 已定夺）|

**⇒ 12 个有身份门，2 个是特权路径（不属此类），0 个该有没有。**

### 1.3 门禁

| 项 | 结果 |
|---|---|
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/server` + `src/engine` **869/869/0** |
| 变异对照 | **2 个真跑**，都精确打红 `ct_01` |

---

## 二、证据

### 2.1 实现（两类身份来源，**不能一刀切**）

**5 个新增 `agent`**（schema + handler 各一处）：
```moonbit
"agent": string_prop(
  "可选：ACL 判定身份（缺省空 ⇒ manual；内存后端放行，sqlite 面需该身份在本 ns 有 can_write=1，否则拒绝）",
),
...
let agent = get_str(args, "agent")
match agent_write_gate(eng, acl_claim_identity(agent, agent), ns) {
  Err(e) => return Err(@mcp_types.ToolError(e))
  Ok(_) => ()
}
```

**2 个复用 `by`**（`reject` / `plan`，**不新增参数**）：
```moonbit
match agent_write_gate(eng, acl_claim_identity(by, by), ns) { ... }
```

### 2.2 三格锁（`server_bug471_b23_wbtest.mbt`）

| 锁 | 断言 |
|---|---|
| **`ct_01`** | ★ **实现路径格**：7 个 handler 各自接了门，且**身份来源正确** —— 用**两组不同的期望串**（`acl_claim_identity(by,by)` vs `(agent,agent)`）分别断言 |
| **`ct_02`** | ★ **sqlite 双向**：收权 ⇒ 拒；授权 ⇒ 放（走完整 `agents_acl_grant` → `agents_acl_check` 真链路）|
| `ct_03` | **零回归**：内存后端 + 未传身份 ⇒ 放行 |

**变异实测（都真跑）**：

| 变异 | 结果 |
|---|---|
| **M1** 删掉 `submit` 的整段门 | **527/533**，**`ct_01` 精确打红** |
| **M2** 删掉 `reopen_task` 的整段门 | **532/533**，**`ct_01` 精确打红** |

（M1 那次的 6 个失败里另有 5 格来自并发 lane 的 `server_wt_wbtest.mbt`；
M2 时那 5 格已修好，只剩我的 1 格 —— **两轮都确认是我的锁在红**。）

### 2.3 过程中我自己踩的两个坑（如实记录）

**坑 1：门插在身份变量之前**
第一版脚本把门插在 `let eng = match engine_for_ns(ns) { … }` 之后，
但 `by` 在那之后才定义 ⇒ **编译报 `by` unbound（4021）**。
**修法：门必须插在身份 `let` 之后。**

**坑 2：`submit` 的写法与其余 6 个不同**
`submit` 用的是 `let eng = match\n  engine_for_ns(get_str(args, …)) {`（跨行 + 内联读 ns），
其余是 `let eng = match engine_for_ns(ns) {` ⇒ 脚本正则**匹配不到它**（报 SKIP）。
**手工补的时候又误写了一个不存在的 `ns_of_task_submit(args)`** ⇒ 编译报未绑定。
**修法：先 `let ns = get_str(args, "namespace", …)` 再传 `ns`**（与其余工具同形）。

---

## 三、分析

### 3.1 为什么 `submit` / `reject` 该与 `verify` 对称

三者都是**质量闸门**，都在**对任务结论负责**：

| 工具 | 盖章的含义 | 后果 |
|---|---|---|
| `submit` | 「我做完了，请验收」| 任务进入待验收，**下游验收者会基于它判断** |
| `verify` | 「验收通过」| 任务→已完成，**结论外溢到整个子树** |
| `reject` | 「验收不通过，打回」| 任务→已打回，**执行者被迫重做** |

**⇒ 三者的输出都是「对别人有约束力的结论」⇒ 同一道 ACL 写门**（`agent_write_gate`）。

### 3.2 为什么状态类可以「有门但不同强度」

`plan` / `retry` / `pause` / `resume` / `reopen_task` 改变的是**流转状态**：
- 它们**不产出「质量结论」**（没人会因为 pause 就说这个任务做得好）
- 它们的错误**可被后续动作纠正**（`pause` 错 → `resume`；`retry` 错 → 再 `reject`）
- 与 `archive`/`delete` 的**不可逆**不同（后者已按批 1 加门并按可逆性定强度）

**⇒ 同一道 ACL 写门即可，但不需要附加「K of N」「双人复核」这类更强约束。**

**这不是「弱保护」而是「按危害配门」**：
给 `pause` 加双人复核会比给 `delete` 加更严的规则更离谱 ——
**门强度应对齐「错了以后能不能挽回」，而不是「这个动作听起来重不重要」。**

### 3.3 与「真正的更严靠操作序列」的一致性

批 1 我说过：**真正的「更严」不该靠多加一道门，而该靠操作序列。**

本单沿用同一口径：
- `submit`→`verify` 的**两段序列**本身就是「交付与验收分离」的约束；
- `archive`→`delete` 的两步（批 1）是「先归档再删」的约束；
- 状态类工具**没有这样的序列需求** ⇒ 单道门足够。

---

## 四、缺口与风险

1. **所有门判的都是「能不能在 ns 写」，不是「你是不是那个人」**
   —— `agent` / `by` 仍是自报串，仍在 **S1 边界**内。
2. **BUG-469（六工具接 `challenge`）与本单重叠 3 个**（`submit`/`reject`/`retry`）：
   那 3 个现在**已有身份门**，接 `challenge` 的前提**已具备**（顺序：先门后认证）。
   其余 3 个要核对各自引擎是否经过角色取数面 —— **不经过就不该接**（BUG-472 的判据）。
3. **`plan` 的角色门**：本单加的是 **ACL 写门**，不是**角色门**（`judged_role`）。
   若将来要「只有 Leader 能拆」，那才是角色门 —— **届时才该接 `challenge`**（`cr_02` 会提醒）。
4. **本单期间多次构建受阻**（`temp/` 并发目录、`server_wt_wbtest.mbt` 在途），
   均等待收口后重跑，**未使用 `--no-verify`**。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-471 批 2+3 | 账本挂 `- fix:`；**BUG-471 至此可关**（9 个已全部处理）|
| **「门强度对齐『错了能不能挽回』，不是『听起来重不重要』」** | 判例集（与批 1 的「按可逆性定强度」同族）|
| **「质量闸门三件套（submit/verify/reject）同强度」** | 判例集 |
| 「脚本批量改多工具时必须按块边界 + 各自身份来源断言」 | 本单两处坑的教训（门插在 let 前 / submit 形状不同）|
| BUG-469 的 `challenge` 接线 | 前 3 个（submit/reject/retry）前提已备；后 3 个先核引擎 |
