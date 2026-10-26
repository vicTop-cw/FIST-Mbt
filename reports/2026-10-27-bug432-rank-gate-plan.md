# BUG-432 · `claim` 的 RANK_GATE 按名字前缀判军衔

> **日期**：2026-10-27 · **执行**：Lane AL · **所有读数本次现读**
> **边界**：未改 `src/` 任何文件（`engine.mbt` 受保护）

---

## 结论

| 问题 | 读数 |
|---|---|
| **判据** | `engine.mbt:1773` `estimate_rank(assignee)`：整名 `human_steward`/`human` ⇒ **0**；`has_prefix("leader")`/`polish-lead` ⇒ **6**；`has_prefix(atomcode/aider)` ⇒ **4**；else **5** |
| **连长（rank=6）能干什么** | 🔴 **是硬门**（`return Err`），但**方向反了**：`rank_can_claim = arank==0 \|\| arank<=tlevel`，**数值越小权越大** ⇒ **rank 6 比默认档 5 更受限** |
| **严重度** | **应降为 low** —— 现网 **100% 任务是 level=6**，rank5/rank6 **结果完全相同 ⇒ 危害为零**（潜伏型） |
| **选 (a) 还是 (b)** | **(b) 只收窄**（整名精确）—— (a) 合并会丢失 `atomcode*` 的 rank 4 档，是「用一个语义覆盖另一个」 |
| **掉级人数** | **0**（13 次前缀调用反而从 6 放宽到 5） |

---

## 证据

### 1. 判据全文 + 消费面（唯一消费点）

```moonbit
// engine.mbt:1773
fn estimate_rank(assignee : String) -> Int32 {
  if assignee == "human_steward" || assignee == "human" { 0 }
  else if assignee.has_prefix("leader") || assignee.has_prefix("polish-lead") { 6 }
  else if assignee.has_prefix("atomcode") || assignee.has_prefix("aider") { 4 }
  else { 5 }
}
// engine.mbt:1786
fn rank_can_claim(arank : Int32, tlevel : Int32) -> Bool {
  arank == 0 || arank <= tlevel
}
```

```moonbit
// engine.mbt:150-173 —— claim 的 RANK_GATE（唯一消费点）
let arank = estimate_rank(assignee)
if !rank_can_claim(arank, task_level) {
  return Err("RANK_GATE: assignee {assignee} (rank={arank_s}) cannot claim task level={tlevel_s} ...")
}
```

**逐条：拒什么、放什么**

| assignee | arank | 能认领 | 拒 |
|---|---|---|---|
| `human_steward`/`human`（**整名**） | **0** | 任意 level | 无 |
| `leader*` / `polish-lead*` | **6** | 仅 level ≥ 6 | **level 0~5** |
| `atomcode*` / `aider*` | 4 | level ≥ 4 | level 0~3 |
| 其余（**含 `commander*`**） | **5** | level ≥ 5 | level 0~4 |

**⇒ 🔴 `leader` 前缀拿 rank 6 不是提权，是自降一级（默认档 5 更宽）。**
**⇒ `commander*`/`optimization*` 不在本表，走默认档 5。**

### 2. ⭐ level 分布实测 —— 决定实际危害

```
SELECT level, COUNT(*) FROM tasks GROUP BY level
  level=1:     1 条 (0.0%)
  level=6:  2431 条 (100.0%)
```

| level | 条数 | rank5（默认） | rank6（leader*） |
|---|---|---|---|
| 1 | 1 | 拦 | 拦 |
| **6** | **2431（100%）** | **可领** | **可领** |

**⇒ 现网 2431/2432 是 level 6，两个档位结果**完全相同** ⇒ **RANK_GATE 现网几乎不生效。**
**⇒ BUG-432 现网危害 ≈ 0。**
**⇒ 但 level 是**可变**的（`task_plan_deep` 会产 level 0~7）⇒ 一旦任务 level 分化，误伤立刻发作。**
**⇒ 定性：潜伏型缺陷，低严重度但不该留。**

### 3. 影响面（`call_log.params_json`，1947 条带 assignee 的 claim）

```
atomcode*   861 次（ok=0: 587）      ← 执行器实例名，不是身份
leader*      37 次（ok=0:  4）      ← 本单相关
human        12 次（ok=0:  0）      ← 整名，不受影响
polish*       1 次（ok=0:  0）

会受影响的精确清单：
  leader          ok=1  24 次  ← **整名，改后仍 rank 6**
  leader_a        ok=1   8 次  ← 前缀 ⇒ 改后 rank 5（**放宽**）
  leader-run      ok=0   4 次  ← 前缀 ⇒ 同上
  leader-buffy    ok=1   1 次  ← 前缀 ⇒ 同上
  polish-lead     ok=1   1 次  ← **整名，需保留**
```

**⇒ 掉级人数 = 0**（整名保持 6；13 次前缀从 6→5，是**放宽**）。

### 4. `assignee` 来源：**MCP 入参可自报**（同 BUG-422 形）

```moonbit
// server.mbt:1823-1845
"assignee": string_prop("认领人（必填）"),   ← 裸 string_prop
let assignee = get_str(args, "assignee")
eng.claim(task_id~, assignee~, ...)          ← 裸传引擎
```

---

## 可粘贴 patch（`src/engine/engine.mbt`）

```diff
--- a/src/engine/engine.mbt
+++ b/src/engine/engine.mbt
@@ fn estimate_rank(assignee : String) -> Int32 {
   if assignee == "human_steward" || assignee == "human" {
     0
-  } else if assignee.has_prefix("leader") || assignee.has_prefix("polish-lead") {
+    // BUG-432：改**整名精确**（与 BUG-421 收窄后的 infer 白名单同族）。
+    // `has_prefix("leader")` 会把 `leader-tools-bot` 这类普通 agent 误判为连长（rank 6），
+    // 而 rank 6 比默认档 5 更受限（rank_can_claim 是 arank <= tlevel）⇒ 这是**误伤**不是越权。
+    // ⚠️ 硬约束：此处**不得**再把 has_prefix 加回来 —— 判据见 wbtest 锁 1/3。
+  } else if assignee == "leader" || assignee == "lead" || assignee == "polish-lead" {
     6
   } else if assignee.has_prefix("atomcode") || assignee.has_prefix("aider") {
```

**⚠️ `atomcode*`/`aider*` 保留前缀** —— 它们是**执行器实例名**（`atomcode-3`/`atomcode-glm53`，861 次），不是身份参数。列为 R1。

---

## 3 格锁

```moonbit
/// 锁 1（本缺陷核心）：前缀名不再拿连长档
test "bug432_leader_prefix_gets_default_rank" {
  assert_eq(estimate_rank("leader-fake"), 5)
  assert_eq(estimate_rank("leader-tools-bot"), 5)
}

/// 锁 2（防修过头）：整名仍拿连长档
test "bug432_exact_leader_names_keep_rank_6" {
  assert_eq(estimate_rank("leader"), 6)
  assert_eq(estimate_rank("lead"), 6)
  assert_eq(estimate_rank("polish-lead"), 6)
  assert_eq(estimate_rank("human_steward"), 0)   // 特权不受影响
  assert_eq(estimate_rank("human"), 0)
}

/// 锁 3（⭐ 变异对照，判例-29/30）：撤回改动 ⇒ 锁 1 必红
/// **不 grep 源码字符串**（那会命中注释里的 has_prefix ⇒ 自指假绿），只断言行为翻转。
test "bug432_variant_prefix_rule_would_break_lock1" {
  assert_eq(estimate_rank("leader"), 6)        // 整名
  assert_eq(estimate_rank("leader-fake"), 5)   // 前缀 ⇒ 必须不同；若退回 has_prefix 两者都是 6 ⇒ 必红
}
```

---

## 分析（≤300 字）

**方向反了**：`leader` 前缀拿 rank 6，比默认档 5 **更受限** ⇒ 这是**误伤，不是越权**。

**因此 BUG-432 从「medium 越权」降为「low 误伤」** —— 加上 §2 的 level 分布实测（100% 是 level 6，两档结果相同），**现网危害为零**。它是**潜伏型**：任务 level 一旦分化就发作。

**`estimate_rank` 不该合并到 `resolve_agent_role`**：前者 4 档军衔（0/4/5/6），后者只有 3 个角色名。合并丢失 `atomcode*` 的 4 档 ⇒ **用一套语义覆盖另一套**，代价不是掉级人数而是语义丢失。**⇒ 选 (b)。**

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | `atomcode*`/`aider*` 保留 `has_prefix` 未动 —— 它们是执行器实例名（861 次），**未核是否有伪造面** |
| **R2** | `params_json` 只覆盖部分调用（3000 条取 1947 条带 assignee） |
| **R4** | `polish-lead` 只 1 次调用，**未核是否为真实在用品名** |

---

## 建议入档位置

**给后来人的一句话（本单最重要产出）**：

> **收窄一条路径时，必须普查「同一个判据语义在别处有没有第二个实现」。**
> 我们修了 `reserve_scope` 的角色门三轮，`claim` 的 `estimate_rank` 一直躺着 ——
> **因为它叫「军衔」不叫「角色」，所以 grep `role` 搜不到它。**

**判例候选**：
> **判例-XX：术语别名会遮蔽普查。** `role` 与 `rank` 是同一语义（身份 → 权限级别）的两个名字，
> 只 grep 一个必然漏掉另一个。**⇒ 按「判定形状」而非「术语名」搜索**：
> `has_prefix("leader")` / `== "human_steward"` / `agents.role` 这类**判定表达式**本身。

**报告**：`reports/2026-10-27-bug432-rank-gate-plan.md`

---

**未改 `src/` 任何文件。未调 `bug_fix`。**
