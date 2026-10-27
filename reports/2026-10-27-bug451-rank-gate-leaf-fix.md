# BUG-451 修复 · `claim` 的 RANK_GATE 必须认叶子

> **日期**：2026-10-27 · **执行**：Lane BM
> **改的文件**：`src/engine/engine.mbt`（2 处）+ 新增 `src/engine/engine_leaf_rank_gate_wbtest.mbt`

---

## 结论

**改了什么**：`claim` 的 Gate 1 里，准入档从恒取 `t.get_level()` 改为
**`is_leaf()` ⇒ 满档 7（排长档，最宽）；否则原样 `t.get_level()`**。

**叶子任务现在可认领了吗**：**能 —— 实测全绿**。
`Total tests: 277, passed: 277, failed: 0`（`src/engine` 全包），四格锁含两端到端格。

**变异对照结果**：**真跑了**。
把 `if t.is_leaf() { leaf_claim_level() } else { task_level }` 改回 `let tlevel = task_level`
⇒ **`277 → 276 passed, 1 failed`，红的确是我要钉的那一格**：
```
F| engine_leaf_rank_gate_wbtest.mbt:25 ("bug451_lock1_executor_can_claim_level2_leaf") failed: Error
```
撤回变异后 `277/277` 恢复全绿，`grep MUTANT-BM451` = 0。

---

## 证据

### 病灶（修复前）

```moonbit
// engine.mbt claim Gate 1（修复前）
let task_level = t.get_level()
...
if !rank_can_claim(arank, task_level) {          // ← 只读 level，**从不看 is_leaf**
  return Err("RANK_GATE: ... level={tlevel_s} (task_rank={tname}) ...")
}
```

配合 `rank_can_claim` 的语义（**数值越小权越大**）：
```moonbit
fn rank_can_claim(arank : Int32, tlevel : Int32) -> Bool {
  arank == 0 || arank <= tlevel
}
```
**⇒ Executor(5) ≤ 2 为假 ⇒ 永久拒。** 而现网只剩 `Executor(5)` / `Leader(4)` /
`HumanSteward(0)` 三档（BUG-432 后 `rank_of_role` 就是这三档）**⇒ 只有 human_steward 能领。**

### 修复（逐字）

```moonbit
// engine.mbt:213
let tlevel = if t.is_leaf() { leaf_claim_level() } else { task_level }
let tlevel_s = tlevel.to_string()
let tname = level_to_rank(tlevel)
if !rank_can_claim(arank, tlevel) { ... }
```

```moonbit
// engine.mbt:1831（新增，引擎层私有）
fn leaf_claim_level() -> Int32 {
  7
}
```

**为什么在引擎层自己算而不调 `@display.leaf_label`**：
`leaf_label` 在 `src/display/rank.mbt:101`（**展示层**），引擎层 import 展示层是**依赖方向反了**。
⇒ 就地取满档常量，**语义由注释 + 锁 4 与展示层对齐**（不是"两处各写一份没人管"）。

### 四格锁（`engine_leaf_rank_gate_wbtest.mbt`）

| 格 | 内容 | 实测 |
|---|---|---|
| **锁 1** | level=2 的**叶子**（`depth=1`）⇒ Executor **能**认领（`Ok`） | ✅ 绿 |
| **锁 2** | level=2 的**非叶子**（`depth=3`）⇒ Executor **仍被拒**，文案含 `RANK_GATE` + `level=2` | ✅ 绿 |
| **锁 3** | `human_steward`(rank 0) 叶子/非叶子**都能领**（例外通吃） | ✅ 绿 |
| **锁 4** | 纯函数级：`leaf_claim_level()==7`、`rank_can_claim(5,7)==true`、`rank_can_claim(5,2)==false`、边界 `rank_can_claim(2,2)==true` | ✅ 绿 |

**锁 1 自带夹具自检**：`if !t.is_leaf() { abort("夹具失效") }` —— 防「测的不是叶子」。

### 零回归证据

- **`src/engine` 全包**：`277/277 passed, 0 failed`
- **非叶子行为**：锁 2 直接断言 `level=2` 非叶子对 Executor 仍拒，文案档位仍是 `level=2`（未被叶子规则污染成 7）
- **全量**：`1619 tests, 1618 passed, 1 failed` —— 那 1 个失败**与本条无关**（见 §缺口 R1）

---

## 分析

### 为什么「叶子恒为士兵」是设计意图（硬要求 ⑤）

**真源**：`src/display/rank.mbt:18` 的模块级约定与 `:99-101` 的实现：

```moonbit
/// 展示层约定（本模块不变）：叶子任务无论 level 一律显示"士兵"（`leaf_label`）。
/// leaf_label：叶子原子任务固定为士兵（无论层级）。
pub fn leaf_label(_level : Int32) -> String {
```

**⇒ 注意 `_level` 是**弃用参数**——这个函数**故意不读 level**。这是最强的"设计意图"证据：
不是"没考虑层级"，是"**明确决定不看层级**"。

**为什么**：`task_plan_deep` 拆出的叶子是**可独立认领的最小执行单元**，它的 `level`
是 `子任务 level = 父级 + 1` **继承**来的（反映它在计划树里的深度），**不代表它的执行难度**。
把继承来的深度当作准入军衔，等于「**任务拆得越细，越没人能领**」—— 恰好与拆解目的相反。

### 为什么之前漏了 `is_leaf`

**P0-2 军衔门（`c03d78ce`，2026-10-22）加门时，`level` 是它唯一想到的输入。**
而 `leaf_label` 活在展示层（`src/display`）、`rank_can_claim` 活在引擎层（`src/engine`）——
**两个模块各自跑测试，谁都没跑"叶子 × 认领"这个组合**。

**⇒ 这是判例-29 的又一实例（机制格 ≠ 实现路径格）**：
展示层有 `leaf_label` 的锁，引擎层有 `rank_can_claim` 的锁，
**但"引擎层用不用展示层的叶子语义"这件事没有任何一格在管**。

---

## 缺口与风险

| # | 项 |
|---|---|
| **R1** | **全量有 1 个失败，与本条无关**：`src/server/server_bug430_s3_keyreplace_wbtest.mbt:86` (`bl_03_tool_rejects_key_replacement`)，属 Lane BL 在 `1c349106` 刚落的 S3 第五段。**严格证明**：该文件对 `claim`/`rank_can_claim`/`is_leaf` 的引用数 = **0**；把 `engine.mbt` 还原到 HEAD 后**仍然 433/435 (2 failed)**；恢复我的改动后不变 |
| **R2** | **满档 7 是硬编码常量**。若将来军衔体系扩到 8 档，`leaf_claim_level()` 要同步改。**缓解**：锁 4 显式断言 `== 7`，改挡位会立刻红 |
| **R3** | **`level=0` 的叶子现在可被任何非 0 军衔认领** —— 已实测对拍：修复前 `rank_can_claim(5,0)=False`、`rank_can_claim(4,0)=False` ⇒ **level=0 叶子连 Executor/Leader 都拒**（只有司令能领），这是同一 bug 的**最极端形态**；修复后 `rank_can_claim(*,7)=True`。**⇒ 放宽方向正确**（`level=0` 叶子意味着根任务本身是叶子，`depth<=1`，语义上就该可领） |
| **R4** | 未核 `task_plan_deep` 的实际 `depth` 分布 —— 我按 `is_leaf() = depth <= 1` 判据修，**未统计现网有多少叶子是 `depth=1` vs `depth>=2`**（报告里"深度≥2 的叶子"来自派单实测，我未独立复核） |

---

## 建议入档位置

**账本**：BUG-451 可标 FIXED（代码 + 四格锁 + 变异实测 + 零回归齐备）。

**判例候选**：
> **判例-XX：语义分居两个模块时，「组合」本身需要一格锁。**
> `leaf_label`（展示层）说"叶子恒为士兵"，`rank_can_claim`（引擎层）说"arank <= tlevel"——
> **两句话都对，两句都有锁，而"引擎该不该用叶子的语义"没人测**
> ⇒ 深度≥2 的叶子对全部现网执行体永久不可认领，**拆解失去意义**。
> **⇒ 一个概念（叶子）的定义在一个模块、使用在另一个模块时，
> 必须有至少一格**跨模块组合锁**，否则两边各自的锁绿得毫无意义。**

**跨模块常量的记法**：引擎层不能 import 展示层 ⇒ 就地取常量 + 一格
「断言它等于展示层语义的数值」的锁（锁 4），比注释可靠。

---

**只改了派单允许的两个文件面。未调 `bug_fix`。**
