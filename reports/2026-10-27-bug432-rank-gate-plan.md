# BUG-432 + R1 · `estimate_rank` 名字前缀判军衔：误伤一格 vs 提权一格

> **日期**：2026-10-27 · **执行**：Lane AL · **所有读数本次现读**
> **边界**：未改 `src/` 任何文件

---

## 结论

**`estimate_rank` 的四档里，只有两档是「身份」语义，而它们方向相反：**

| 前缀 | rank | 与默认档 5 比 | 性质 | 现网危害 | 建议严重度 |
|---|---|---|---|---|---|
| `human_steward`/`human`（**整名**） | **0** | 更宽 | **身份特权**（有意） | — | 设计如此 |
| **`leader*`/`polish-lead*`** | **6** | **更受限** | 🔵 **误伤** | **0** | **low** |
| **`atomcode*`/`aider*`** | **4** | **更宽** | 🔴 **提权** | **0** | **low，但方向错** |
| 其余 | 5 | — | 默认 | — | — |

**🔴 R1 核心判断：`atomcode*`/`aider*` 是**可自报的身份**，不是系统写入的执行器实例名。**
**⇒ 方向是**提权**（rank 4 比默认 5 更宽），与 `leader*` 的误伤方向相反。**
**但现网危害 = 0**（rank4 与 rank5 对现网 2432 条任务结果完全相同）⇒ **low，与 BUG-432 同级。**

---

## 证据

### 1. `assignee` 从哪来：**MCP 裸入参，可自报**

```moonbit
// server.mbt:1821-1839
"claim",
schema({
  "task_id":  string_prop("任务 id（必填）"),
  "assignee": string_prop("认领人（必填）"),     ← 裸 string_prop，无 format/enum
  ...
}, ["task_id", "assignee"]),
...
let assignee = get_str(args, "assignee")
eng.claim(task_id~, assignee~, ...)             ← 裸传引擎
```

**⇒ 与 BUG-422 的 `agent` 完全同形：无校验，调用方自报。**

### 2. ⭐ 核心判断：`atomcode*` 是**可自报身份**，不是系统写入

**查「谁会把 `atomcode` 写进 `assignee`」——全仓只有 3 处提到 `atomcode`：**

```
src/engine/engine.mbt:1778           } else if assignee.has_prefix("atomcode") || ...   ← 判据本身
src/executor/cli_argv.mbt:17         ["aider", "atomcode", "ofm"]                        ← executor 白名单
src/server/model_router_ops.mbt:227  } else if executor == "atomcode" {                  ← 路由分支
```

**关键：`cli_argv.mbt` 的白名单是 `executor_run` 的 `executor` 参数** ——
那是「**调用哪个外部执行器**」，**与 `claim` 的 `assignee` 是两条无关的路**。

```
grep -n "assignee" src/server/server.mbt | grep -i executor   → 空
grep -rn "assignee=" src/engine/engine.mbt（非 fn/estimate_rank） → 空
```

**⇒ 没有任何代码把执行器名自动写进 `assignee`。**
**⇒ `assignee="atomcode-xxx"` 只能由**调用方手填**。**
**⇒ 判断：可自报身份，必须收窄（不是「设计上的合法用法」）。**

**补充佐证（现网 7 个名字）**：
```
atomcode-3(922) atomcode-glm53(37) atomcode(35) atomcode-longcat(34)
atomcode-glm(4) atomcode-1(1) atomcode-2(1)        ← 共 1034 次
```
**⇒ 形态是「型号 + 实例号」，含 `-1`/`-2`/`-3` 序号 ⇒ 人填的，不是系统生成的封闭集合。**

### 3. 若可伪造，它能认领什么（逐档）

```moonbit
fn rank_can_claim(arank : Int32, tlevel : Int32) -> Bool {
  arank == 0 || arank <= tlevel        // 数值越小权越大
}
```

| assignee | arank | 能认领 | 拒 |
|---|---|---|---|
| `human_steward`/`human`（整名） | 0 | **任意 level** | 无 |
| **`atomcode*` / `aider*`** | **4** | **level ≥ 4** | level 0~3 |
| 其余（默认） | **5** | level ≥ 5 | level 0~4 |
| `leader*` / `polish-lead*` | 6 | level ≥ 6 | level 0~5 |

**⇒ `atomcode*` 比默认档多认领 **level 4（团长级）** —— 这是**真·提权**。**

### 4. ⭐ 现网危害量化：**0**

```
现网 level 分布：level=1 有 1 条 / level=6 有 2431 条 / 合计 2432

逐档判读：
  level=6：rank4 可领(4<=6) | rank5 可领(5<=6)  ⇒ **相同**
  level=1：rank4 拒(4>1)    | rank5 拒(5>1)     ⇒ **相同**
```

**⇒ rank 4 与 rank 5 对现网全部 2432 条任务结果完全相同 ⇒ 现网危害 = 0，与 BUG-432 同性质：潜伏型。**

**但两者方向相反，这才是本单的核心区分：**
> **`leader*` 是「本该更宽的被收窄了」⇒ 误伤**
> **`atomcode*` 是「本该默认的被放宽了」⇒ 提权**
> **⇒ 同样现网危害 0，但 `atomcode*` 更该修：它是将来会开出一个等级的口，而不是关掉别人的口。**

---

## 合并 patch（`src/engine/engine.mbt`）

```diff
--- a/src/engine/engine.mbt
+++ b/src/engine/engine.mbt
@@ fn estimate_rank(assignee : String) -> Int32 {
 fn estimate_rank(assignee : String) -> Int32 {
   if assignee == "human_steward" || assignee == "human" {
     0
-  } else if assignee.has_prefix("leader") || assignee.has_prefix("polish-lead") {
+    // BUG-432（误伤型）：`leader*` 前缀拿 rank 6，比默认档 5 **更受限**
+    // （`rank_can_claim = arank == 0 || arank <= tlevel`，数值越小权越大）
+    // ⇒ 会把 `leader-tools-bot` 这类普通 agent 误判成连长。改**整名精确**。
+  } else if assignee == "leader" || assignee == "lead" || assignee == "polish-lead" {
     6
-  } else if assignee.has_prefix("atomcode") || assignee.has_prefix("aider") {
+    // R1（提权型，方向相反）：`atomcode*`/`aider*` 拿 rank 4，比默认档 5 **更宽**
+    // ⇒ 任何调用方 `claim(assignee="atomcode-anything")` 就能多认领 **level 4（团长级）** 任务。
+    // 实测：全仓**没有**任何代码把执行器名自动写进 assignee（`executor_run` 的 `executor`
+    // 白名单在 `cli_argv.mbt`，与 claim 的 assignee 是两条无关的路）⇒ **该前缀可被调用方自报**。
+    // ⇒ 改**整名精确**：真实实例名 `atomcode-3`/`atomcode-glm53` 退回默认档 5，
+    //    与「未声明身份的普通 agent」同等 —— 这正是它应有的档位。
+    // ⚠️ 硬约束：此处**不得**再有两个 `has_prefix` 加回来 —— 判据见 wbtest 锁 1/4。
+  } else if assignee == "atomcode" || assignee == "aider" {
     4
   } else {
     5
   }
 }
```

**影响面（改后谁变档）**：

| assignee | 现→改 | 变化 |
|---|---|---|
| `leader` / `lead` / `polish-lead`、`atomcode` / `aider`、`human_steward` / `human`（**全部整名**） | 不变 | — |
| `leader_a` / `leader-run` / `leader-buffy`（前缀，13 次） | 6 → **5** | **放宽** |
| **`atomcode*` 前缀（7 名字 1034 次）** | 4 → **5** | **收紧**（少认领 level 4）← 正是要修的 |

**⇒ 变差的只有 `atomcode*` 前缀，而那正是本单要修的那一格。现网 level 全是 6 ⇒ 实际影响 = 0。**

---

## 4 格锁

```moonbit
/// 锁 1（BUG-432 误伤型）：`leader` 前缀不再拿连长档
test "bug432_leader_prefix_gets_default_rank" {
  assert_eq(estimate_rank("leader-fake"), 5)
  assert_eq(estimate_rank("leader-tools-bot"), 5)
}

/// 锁 2（R1 提权型 ⭐ 本单核心）：`atomcode` 前缀不再拿团长档
test "r1_atomcode_prefix_gets_default_rank" {
  assert_eq(estimate_rank("atomcode-anything"), 5)
  assert_eq(estimate_rank("atomcode-fake"), 5)
  assert_eq(estimate_rank("aider-xxx"), 5)
}

/// 锁 3（防修过头）：整名与特权档全部保留
test "bug432_r1_exact_names_unchanged" {
  assert_eq(estimate_rank("leader"), 6)
  assert_eq(estimate_rank("polish-lead"), 6)
  assert_eq(estimate_rank("atomcode"), 4)
  assert_eq(estimate_rank("human_steward"), 0)
}

/// 锁 4（⭐ 变异对照，判例-29/30）：撤回任一改动 ⇒ 对应锁必红。
/// **不 grep 源码字符串**（会命中注释里的 has_prefix ⇒ 自指假绿），只断言行为翻转。
test "bug432_r1_variant_prefix_rules_would_break_locks" {
  assert_eq(estimate_rank("leader"), 6)
  assert_eq(estimate_rank("leader-fake"), 5)          // ← 锁 1 的变异控制
  assert_eq(estimate_rank("atomcode"), 4)
  assert_eq(estimate_rank("atomcode-anything"), 5)    // ← 锁 2 的变异控制
}
```

---

## 分析（≤300 字）

**本单真正的产出是「两格方向相反」。** `leader*` ⇒ rank 6（比默认 5 更受限）⇒ 误伤；
`atomcode*` ⇒ rank 4（比默认 5 更宽）⇒ 提权。**同样现网危害 0，但性质相反。**

**核心判断**：`atomcode*` **是可自报身份**，证据链三条 —— ① 全仓只有 3 处提到 `atomcode`，
`cli_argv.mbt` 的白名单属 `executor_run`、与 `claim` 的 `assignee` 是两条无关的路；
② `grep assignee` 在 engine/server 里**无执行器自动写入点**；③ 现网 7 个名字含 `-1`/`-2`/`-3` 序号 ⇒ 人填的。

**⇒ 该前缀必须收窄**（不是我前一版担心的「可能合法」）。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | ~~`atomcode*`/`aider*` 未核伪造面~~ ✅ **已核：可自报，必须收窄**（见 §2） |
| **R2** | `params_json` 只覆盖部分调用（3000 条取 1947 条带 assignee） |
| **R3** | **`atomcode-3` 有 639 次 ok=0** —— 失败率高，**未核是否与 RANK_GATE 有关**（若 level 分化，这可能是它在拦） |
| **R4** | `polish-lead` 仅 1 次调用，**未核是否真实在用** |

---

## 建议入档位置

**判例（按统帅补完）**：
> **判例-XX：术语别名会遮蔽普查。**
> `role` 与 `rank` 是同一语义（身份 → 权限级别）的两个名字，只 grep 一个必然漏掉另一个。
> **⇒ 搜「名字前缀判角色」时，要搜的是 `has_prefix` / `starts_with` 这类**判定形状**，
> 而不是「role」「rank」「身份」这些**术语**。**
> **术语是作者起的名字，判定形状是代码的实际形状 —— 前者会变，后者不会。**

**账本建议**：
- **BUG-432**（`leader*`）：**medium → low**（误伤型、现网危害 0、潜伏）
- **R1**（`atomcode*`）：**新立，severity = low**（提权型、现网危害 0、潜伏）
  - 现网危害与 BUG-432 同为 0；但**方向是提权** —— 将来 level 分化时**开出的口比关掉的口更危险**
  - **⇒ 两者应同批修，R1 的理由更强**

**报告**：`reports/2026-10-27-bug432-rank-gate-plan.md`

---

**未改 `src/` 任何文件。未调 `bug_fix`。**
