# BUG-467：给 `verify` 加身份门 · Lane CI · 2026-10-28

> **「验收」是质量闸门。它被绕过，整个任务体系的产出都不可信。**
> 本单把「谁该验收」先定死，再加门 —— 顺序掰正了。

---

## 一、结论

| 项 | 结果 |
|---|---|
| **该由谁验收** | **候选 ①：`human_steward` / `leader-*` 级——但落点是「ns 写权限」而非「角色矩阵」**（见 §2.1）|
| 门怎么加的 | `agent_write_gate(eng, acl_claim_identity(verifier, verifier), ns)` —— **与 `execute` 同源** |
| 编译 | `moon check --target js` → **0 errors** |
| 我的改动面 | `src/server` + `src/engine` **848/848 全绿** |
| 变异对照 | **真跑**，`ci_03` 精确打红 |
| 对称性 | ✅ `execute` / `verify` 现在**同一道门、同一身份真源** |

---

## 二、证据

### 2.1 ★ 先回答「该由谁验收」（代码证据，不是拍脑袋）

**证据 1：权限矩阵里根本没有 `verify`**

```moonbit
// src/ops/audit.mbt:178  enforce()
let ok = match action {
  "publish" => can_publish(role)
  "archive" => can_archive(role)
  "delete"  => can_delete(role)
  "claim"   => can_claim(role)
  _ => false          // ← 未知 action 一律拒
}
```
⇒ **`verify` 不在矩阵里** ⇒ 若直接 `enforce("verify", …)` 会**一律拒绝（含 human_steward）**。
⇒ **不能走角色矩阵这条路**（会误伤）。

**证据 2：「验收宪兵」只是展示层标签，不是协议角色**

```moonbit
// src/display/staff.mbt:44
("验收宪兵", ["verifier", "验收", "宪兵", "门禁", "审核", "verify", "gate"]),
```
而 `staff_label_of` 的 docstring 明写：
> **参谋军职不是协议角色**，只是展示层标签；协议与存储零改动。

⇒ **候选 ②（`Verifier` 参谋军职能验收）不成立** —— 那个角色在协议层不存在。

**证据 3：`execute` 已有的门是「ns 写权限」，不是角色**

⇒ **`verify` 应与 `execute` 对齐**：判「调用方能不能在这个 ns 写」，而不是「他是不是某个军职」。

**⇒ 结论：三个候选里 ① 方向对（严），但落点要修正 —— 不是查角色矩阵（无 verify 条目），
而是查 `ns` 写权限（`agents_acl_check(write=true)`）。**
候选 ② 不存在于协议层；候选 ③（创建者能验收）**会变成「自己验收自己」**，是最坏的一种 ——
验收的意义正是**独立复核**。

### 2.2 实现（与 `execute` 同源）

```moonbit
// src/server/server.mbt  verify 工具函数体
let verifier = get_str(args, "verifier")
let ts = now_default()
// BUG-467：ns 写权限门 —— verify 此前一道门都没有
match agent_write_gate(eng, acl_claim_identity(verifier, verifier), ns) {
  Err(e) => return Err(@mcp_types.ToolError(e))
  Ok(_) => ()
}
```

**`verifier` 与身份门的关系**（派单要点）：
- `verifier` = **回执里记录的操作者名**（写进任务历史）
- 身份门判的是「**调用方是否有权在这个 ns 写**」
- 两者**可以不同**（同 `execute` 的 `executor` / `agent`，BUG-436 已定）；
  但 `verify` **没有独立的 `agent` 参数** ⇒ 把 `verifier` 同时用作两者
  （`acl_claim_identity(verifier, verifier)`）—— **不引入新参数，零回归**。

### 2.3 三格锁 + 变异（**真跑**）

| 锁 | 断言 |
|---|---|
| `ci_01` | **零回归**：内存后端放行（既有测试不受影响的依据）|
| **`ci_02`** | ★ **sqlite 双向**：显式收权 `can_write=false` ⇒ **拒**；`agents_acl_grant(can_write=true)` ⇒ **放**。两向都用**与工具实现逐字同源**的 `acl_claim_identity(verifier, verifier)` |
| **`ci_03`** | ★ **实现路径格**：`verify` handler 里**真有** `agent_write_gate(eng, acl_claim_identity(verifier, verifier), ns)` —— **`strip_ws` 归一化后比对**，防 `moon fmt` 重排假红（R24 教训 + 判例-34）|

**变异实测**：删掉 `verify` 的整段 ACL 门 ⇒ **517/518**，**`ci_03` 精确打红**。

**`ci_02` 是「门真的会拒」的证据**：它在真 sqlite 库里走完整 `agents_acl_grant` → `agents_acl_check` 链路，
不是断言源码字面。

---

## 三、分析

### 3.1 为什么 `verify` 无门比 `created_by` 自报更严重

| | BUG-464（`created_by` 自报）| BUG-467（`verify` 无门）|
|---|---|---|
| 攻击面 | 能**发起**任务 | 能**盖章通过** |
| 后果 | 塞垃圾任务进队列（可被后续流程筛掉）| **未完成的活被标成「已完成」** |
| 可逆性 | **可逆**（archive/delete 掉）| **不可逆** —— 一旦盖章，下游全按「已完成」推进 |
| 危害范围 | 单条任务 | **整个任务体系的产出可信度** |

**⇒ `created_by` 是「入口不严」，`verify` 是「出口失守」。出口失守比入口不严致命。**

### 3.2 对称性（派单要点 ⑤）

| | 修前 | 修后 |
|---|---|---|
| `execute` | ✅ `agent_write_gate`（BUG-436 定的身份链）| ✅ 不变 |
| `verify` | ❌ **无任何门** | ✅ `agent_write_gate`（与 execute 同源）|
| 身份真源 | execute: `acl_claim_identity` | verify: **同一个** `acl_claim_identity` |
| 门函数 | `agent_write_gate` | **同一个** |

**⇒ 二者现在对称**（判例-29 的正面用法：照抄已验证的接线，不新造第二条）。

---

## 四、缺口与风险

1. **`verifier` 仍是自报串**：本单加的是**「能不能在 ns 写」**，不是「你真的是验收宪兵」。
   ⇒ 这仍在 **S1 边界**内（与 `agent`/`assignee`/`created_by` 同族）。
   真正的身份锚点要等 S3 把 `challenge` 接到 `verify` —— **但那要等 `verify` 先有身份门**（本单做完了）。
2. **角色矩阵仍无 `verify` 条目**（`enforce("verify")` 恒拒）：本单**故意不走角色矩阵**
   （会误伤 human_steward）。建议后续在 `src/ops/audit.mbt` 补一条
   `"verify" => can_verify(role)`，明确「谁能验收」到角色层。
3. **全量 `moon test` rc=2**（`src/server`+`src/engine` 单独跑 **848/848 全绿**）：
   全仓级早退出，疑似其他 lane 在途包所致，非本单改动面。**已如实记录，未按绿上报。**
4. `submit` / `reject` / `retry` 等**仍未评估**是否需要同类门 —— 本单只覆盖 `verify`。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-467 修复 | 账本挂 `- fix:`，与 BUG-430（S1/S3）关联 |
| **「出口失守 > 入口不严」** | 判例集：质量闸门类缺陷的严重度分级 |
| **「`verify` 与 `execute` 对称」** | BUG-436/BUG-467 的对称性说明（派单要点 ⑤）|
| **「角色矩阵无 verify 条目」** | 建议单开：给 `ops/audit.mbt` 补 `can_verify` |
