# BUG-471 第 1 批：`delete` + `archive` 的身份门 · Lane CO · 2026-10-28

> **本单推翻了一个我自己的假设。**
> 上单我把 `delete` 列为「最高危（不可逆）」、`archive` 列为次之。
> **实测：`archive` 也不可逆** ⇒ 两者**同强度门**。

---

## 一、结论

| 项 | 结果 |
|---|---|
| `archive` | ✅ 加门，复用现成的 `by` 作为身份 |
| `delete` | ✅ 加门，**新增可选 `agent` 参数**（原先无任何身份参数）|
| **门强度** | **两者相同** —— 因为**都不可逆**（见 §3.1）|
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/server` + `src/engine` **857/857/0** |
| 变异对照 | **真跑**，`co_03` 精确打红 |

---

## 二、证据

### 2.1 修法（`src/server/server.mbt`）

**`archive`** —— `by` 本来就是身份参数，**不新增**：
```moonbit
let by = get_str(args, "by", default="human_steward")
let force = get_bool(args, "force")
let ts = now_default()
// BUG-471 第 1 批：ns 写权限门
match agent_write_gate(eng, acl_claim_identity(by, by), ns) {
  Err(e) => return Err(@mcp_types.ToolError(e))
  Ok(_) => ()
}
```

**`delete`** —— 新增可选 `agent`（**这正是「不能照抄 archive」的地方**）：
```diff
         "namespace": string_prop("…"),
+        "agent": string_prop(
+          "可选：操作者身份（ACL 判定用）。⚠️ 缺省空 ⇒ 视为 manual；" +
+          "内存后端放行，sqlite 面需该身份在本 ns 有 can_write=1，否则拒绝",
+        ),
       },
       ["task_id"],
     ),
     fn(args : Json) -> Result[@mcp.ToolResult, @mcp.MCPError] {
       ...
+      let agent = get_str(args, "agent")
+      match agent_write_gate(eng, acl_claim_identity(agent, agent), ns) {
+        Err(e) => return Err(@mcp_types.ToolError(e))
+        Ok(_) => ()
+      }
       to_unit_result(eng.delete_task(task_id))
```

### 2.2 ★ 关键证据：`archive` **不可逆**（推翻了直觉）

```moonbit
// src/core/core_task.mbt:545
pub fn Task::reopen(self : Task) -> Result[Task, String] {
  match self.status {
    Archived => Err("已归档任务不可 reopen，请重新发布")   // ← 明确拒绝
    Rejected => Ok({ ..self, status: Claimed, ... })
    Paused   => Ok({ ..self, status: Claimed, })
    _        => Ok({ ..self, status: Claimed, })
  }
}
```
**⇒ 归档后无法恢复原任务**（只能重新发布，丢掉历史 id 与子树关联）。

再核 `delete_task`：
```moonbit
// src/engine/engine.mbt:1257
if t.get_status().is_archived() { self.store.delete_task(task_id) }
```
⇒ `delete` **只在 `archive` 之后**，且物理删行。

**⇒ 两条路都通向「回不去」：`archive` 丢失可恢复性，`delete` 丢失全部数据。**

### 2.3 三格锁 + 变异（**真跑**）

| 锁 | 断言 |
|---|---|
| `co_01` | **零回归**：内存后端 + 未传身份（delete 空串 / archive 缺省 `human_steward`）⇒ 放行 |
| **`co_02`** | ★ **sqlite 双向**：显式收权 `can_write=false` ⇒ **拒**；`agents_acl_grant(can_write=true)` ⇒ **放**。走完整 grant→check 真链路 |
| **`co_03`** | ★ **实现路径格**：`delete` 期望 `agent_write_gate(eng,acl_claim_identity(agent,agent),ns)`、`archive` 期望 `…acl_claim_identity(by,by)…` —— **两者身份来源不同，不能用同一个模式串**（这正是断言点）；`strip_ws` 归一化防 `moon fmt` 假红 |

**变异实测**：删掉 `delete` 的整段 ACL 门 ⇒ **520/521**，**`co_03` 精确打红**。

---

## 三、分析

### 3.1 「`delete` 该比 `archive` 更严吗？」—— **不该，因为两者都不可逆**

派单问：「`delete` 是物理删除，`archive` 是状态转移 —— 危害不对称，门强度可能也不该对称。」

**实测答案是：危害确实不对称，但「可逆性」相同 ⇒ 门强度应当相同。**

| | `archive` | `delete` |
|---|---|---|
| 数据层 | **任务行还在**（可查、可审计）| **行没了**（什么都不剩）|
| 状态层 | `Archived`，**无法 reopen** | 不存在 |
| 能否恢复 | ❌ 不能（只能重新发布）| ❌ 不能 |
| **可逆性** | **不可逆** | **不可逆** |

**⇒ 危害程度不同（delete 更彻底），但「不可逆」这一属性相同 ⇒ 同一道 ACL 写门即可。**

**真正的「更严」不该靠「多加一道门」，而该靠操作序列**：
`delete` 只允许已归档（`is_archived()` 已在引擎强制）——
**先归档、再删除**这个两步序列，本身就是「更严」的约束。

**给 delete 单独加强制角色门（如只允许 human_steward）会是错的**：
它与 `archive` 的可逆性相同，凭什么删除比归档更要角色？
若要更严，应该**同时**提高两者的门槛（那是政策决策，不是本单能定的）。

### 3.2 为什么 `delete` 必须新增参数而 `archive` 不用

- `archive` 有 `by`（操作者，缺省 `human_steward`）—— 现成
- `delete` **只有 `task_id` + `namespace`** —— 没有任何身份参数

**⇒ 若「照抄 archive」，会写成 `acl_claim_identity(<不存在的东西>, …)`，编译不过。**
上单我预测「7 个连身份参数都没有」——`delete` 正是其中之一。

### 3.3 零回归 vs 加严（**两者都成立，方向不同**）

| 场景 | 修前 | 修后 | 性质 |
|---|---|---|---|
| 内存后端 + 未传身份 | 放行 | **放行** | **零回归** |
| sqlite + 未传身份 | 放行 | **拒绝（`manual` 无 `can_write`）** | **加严（有意）** |
| sqlite + 已授权身份 | 放行 | **放行** | 无变化 |

**⇒ 默认不传 = 更安全**（sqlite 面 fail-closed），这是**加严**不是**破坏**。

---

## 四、缺口与风险

1. **第 2/3 批还剩 7 个**：`plan` / `submit` / `reject` / `retry` / `pause` / `resume` / `reopen_task`
   - **`reject` 有 `by`** ⇒ 同 `archive`，直接复用
   - **其余 6 个无身份参数** ⇒ 同 `delete`，需新增可选 `agent`
2. **`agent` / `by` 仍是自报串** —— 本单加的是「能不能在 ns 写」，不是「你真的是谁」，
   仍在 **S1 边界**内（与 `created_by` / `verifier` 同族）。
3. **本次未做「回执可见性」**（派单步骤 3 提到的 `+acl_denied` 标注）：
   门在工具层直接 `return Err`，回执是 MCP 错误而非 `action` 字符串，
   **没有 action 面可拼**。若需要，应在错误文案里带上身份来源（已带 `acl_gate_fail_message`）。
4. **本单期间三次构建受阻**（`temp/` 并发目录被删、`index.lock`），均等待收口后重跑，
   **未使用 `--no-verify`**。

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-471 第 1 批 | 账本挂 `- fix:`，关联 BUG-467 / BUG-471 普查单 |
| **「archive 也不可逆」** | **判例集** —— 推翻「只有 delete 不可逆」的直觉，证据 `core_task.mbt:547` |
| **「门强度按可逆性定，不按危害程度定」** | 同判例（危害不对称 ≠ 门强度应不对称）|
| 「delete 需新增参数、archive 可复用 `by`」 | 第 2/3 批任务包输入 |
