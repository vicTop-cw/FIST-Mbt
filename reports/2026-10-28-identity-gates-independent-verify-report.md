# 独立验证：「14/14 生命周期工具有身份门」成立吗（Lane CX）

> 司令-γ · 2026-10-28 · **只读验证**（未改 `src/`，未碰 `server.mbt`）
> **结论：14/14 成立** —— 三种假门形态**全部 0 命中**，`Err` 分支**全部真 `return Err``。
> **但「14/14」有一个必须写明的条件：只在 sqlite 后端成立**（§5），
> 且 `publish` / `publish_parallel` 的「特权路径」理由**只对 `publish` 成立**（§6 更正）。

---

## 结论

| 问题 | 答案 |
|---|---|
| **14/14 成立吗** | **✅ 成立**（14 个工具都有门调用，且门在执行路径上、返回值被用、入参是变量） |
| **有几处假门** | **0 处**（①不可达 / ②丢弃 / ③常量 全 0；④空 Err 也 0） |
| **判据差异** | Beta = **文本包含**（机制格）；我 = **结构判定**（执行路径 + 返回值 + 入参来源 + Err 分支） |
| **⚠️ 必须补充的条件** | `agent_write_gate` 对**非 sqlite 后端直接 `Ok(())` 放行** ⇒ 14/14 **只在 sqlite 成立** |

---

## 证据

### §1 Beta 的判据路径（先看清他怎么判的）

`server_bug471_b23_wbtest.mbt:ct_01_seven_handlers_wired`：
```moonbit
let flat = ct_strip_ws(blk)
if not(flat.contains("agent_write_gate(eng,acl_claim_identity(by,by),ns)")) {
  abort(tool + " 没接门（或身份来源不是 by）")
}
```
**⇒ 只做字符串包含检查** = 判例-29 的「机制格」。它能证明「这串文字出现了」，
**不能**证明它在执行路径上、返回值被用、入参是真身份。

### §2 我的四种假门形态排查结果

| 工具 | 门 | ①不可达 | ②丢弃 | ③常量 | ④空 Err | 身份来源 |
|---|---|---|---|---|---|---|
| `publish` | `ns_write_gate` | - | - | - | - | （仅 ns） |
| `publish_parallel` | `ns_write_gate` | - | - | - | - | （仅 ns） |
| `plan` | `agent_write_gate` | - | - | - | - | `by` |
| `claim` | `agent_write_gate` | - | - | - | - | `who` |
| `execute` | `agent_write_gate` | - | - | - | - | `who` |
| `submit` / `retry` / `pause` / `resume` / `reopen_task` / `delete` | `agent_write_gate` | - | - | - | - | `agent` |
| `verify` | `agent_write_gate` | - | - | - | - | `verifier` |
| `reject` / `archive` | `agent_write_gate` | - | - | - | - | `by` |

**⇒ ①②③④ 全部 0 命中。** 标准形态（12 处一致）：
```moonbit
match agent_write_gate(eng, acl_claim_identity(agent, agent), ns) {
  Err(e) => return Err(@mcp_types.ToolError(e))   // ← 真 return Err
  Ok(_) => ()                                     // ← 真放行
}
```
`publish` 用的是 `if g is Err(ge) { return Err(...) }`（`is` 模式），**语义等价**。

身份来源全部是变量（`agent`/`by`/`verifier` 从 `get_str` 取出），**无一处是常量** ⇒ ③不命中。

### §3 门的内核也是 fail-closed

```moonbit
// store_sqlite.mbt:agents_acl_check
None => Err("sqlite store 未打开")            // ← 库没打开也拒
match db.prepare(sql) { None => Err(...)      // ← prepare 失败也拒
  ... if pid_bound != 0 && bound_pid != current_pid { Err(...) }   // ← pid 绑定不匹配拒
```
**⇒ 门内核无「查不到就放行」漏洞。**

---

## §5 ⚠️ 必须写明的条件：「14/14」只在 **sqlite** 后端成立

```moonbit
// server.mbt:805
fn agent_write_gate(eng, id, ns) -> Result[Unit, String] {
  if eng.heartbeat_backend() != "sqlite" {
    return Ok(())        // ← 非 sqlite 后端**直接放行**
  }
  ...
}
```

**不是 bug** —— 刻意的**零回归设计**（内存后端无持久化 ACL 面）。**但它让「14/14」成为**条件性结论**：**

| 后端 | 门是否拦人 |
|---|---|
| **sqlite**（生产，`server.mbt:10/137` 确证） | **✅ 拦** |
| memory（默认 `FistEngine::new()`，`engine.mbt:20`） | **❌ 不拦**（直接 `Ok`） |

**⇒ Beta 的「14/14 无任何身份门：0 个」在生产环境成立；
但若有谁用内存后端跑（CLI 直调 / 测试），14 个门**全部不拦**。**
**这与我的 `opaque` 同族：结论正确，但**前提条件不可省**。

---

## §6 更正：「特权路径」的理由**只对 `publish` 成立**

Beta 说 `publish` / `publish_parallel` 只有 `ns_write_gate`（不看调用者），是**特权路径**。

**`publish` 的理由完整成立**（`server.mbt:1917-1934` 有长注释 + 代码可证）：
- `engine.publish` 开头硬检查 `if created_by != "human_steward" && != "human" ⇒ Err`（`engine.mbt:46`）
- 有 BUG-411 配套预警（`claim_ready` / `writable_agents`）
- BUG-464 已明确记录「刻意不加 ACL」，理由是「加强制 ACL 会削掉指挥官跨 ACL 发任务能力」

**⚠️ 但 `publish_parallel` 不同**：

```moonbit
// server.mbt:2009
let created_by = get_str(args, "created_by", default="selfdrive")
// engine.mbt:1090  publish_parallel 里：只检查 ns，created_by 被 **ignore**
if ns == "" || ns == "default" {
  return Err("并行发布仅限定时任务/自驱命名空间…")
}
// 续轮发起者仅作审计用途（Task 无 created_by 字段），非法值不阻断。
ignore(created_by)
```

**⇒ `publish_parallel` 既无 ACL 门、也无 `created_by` 特权校验**，
只有「ns 不得为 default」一道。**⇒ 不是遗漏，是显式设计（有注释为证），但比 `publish` 弱一档。**

**实际风险**：`created_by` 默认 `"selfdrive"` ⇒ 任何调用方都能在任意非 default ns 并行发布，
无身份约束。这是 BUG-430/S1（自报）同族，但**比 `publish` 更宽**（`publish` 至少要求 `human_steward` 字样）。

---

## 分析：为什么「有门」也是判据的结论

**与「死参数」完全同构**：

| 说法 | 判据 | 它能证明什么 | **它不能证明什么** |
|---|---|---|---|
| 「有死参数」 | 词在 schema 里但 handler 不读 | 文本层面 | 参数是否被**别处**读（透传） |
| 「有身份门」 | 门调用文本在工具块里 | 文本层面 | 门是否在**执行路径**上、返回是否被用、入参是否是真身份 |

**⇒ 两者的正确性都取决于「判据覆盖了多少种真实形态」。**
我把「死参数」判据推到第 3 层（知道自己哪里判不了）；
本单把「有门」判据也推到第 3 层：**明确列出「非 sqlite 后端不拦」这个前提**。

**判例-29 完整形态**：机制格（文本里有门）→ 实现路径格（在 handler 执行路径上）→ **生效格**（返回值被用/Err 真 return/入参是真身份）→ **条件格**（什么后端下才真拦人 ← 本单新增）。
**Beta 停在第 1 层；我做到第 3 层（0 假门）并显式给出第 4 层（sqlite 前提）。**

---

## 缺口与风险

- **R1** 「14/14」的**条件性**必须写进任何引用它的地方 —— 内存后端下 14 个门全不拦。
  建议表述为「**sqlite 后端下 14/14 有生效的身份门**」。
- **R2** `publish_parallel` 的 `created_by` 无硬检查（`engine.mbt:1090`）⇒
  与 `publish`（`engine.mbt:46` 有硬检查）**不对称**。**建议补**，或明确记录为「设计上更宽松」。
- **R3** 本单未测「门**在数据库层面**真的拒」—— 那是 Beta 的 `ct_02` / `co_02` 干的
  （走 `agents_acl_grant` → `agents_acl_check` 真链路）。**两项合起来才完整**：
  我证「门接线且形态正确」，他证「门在 sqlite 下真的拒」。
- **R4** `dag_publish`（`server.mbt:5223`）也自报 `created_by`，本单未细查其 engine 路径。
- **R5** ①不可达对 `plan` 曾误报（`if split_n<1 { return Err }` 在 if 块内），已人工核正 —— **本单第三个「判据自己会误报」实例**。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | 本文件 |
| 只读脚本 | `temp/audit/lane_cx_{gates,strict,final,context}.py` |
| **该补** | `publish_parallel` 的 `created_by` 硬检查（与 `publish` 对齐） |
| **该改表述** | 「14/14 有身份门」→「**sqlite 后端下 14/14 有生效的身份门**」 |
| 互补 | Beta 的 `ct_02`/`co_02`（门在 sqlite 真拒）+ 我的结构验证 = 完整结论 |
