# BUG-417 诊断报告 · Omega 门禁对「父已归档」任务判据错位

> **文种**：只读诊断 + 可执行 patch 方案
> **日期**：2026-10-26 · **执行**：Lane P（commander-alpha）
> **权限**：`reserve_scope("src/engine/omega_strong.mbt")` → **拒绝**（`Executor` 无权，允许 `HumanSteward, Leader`）
> **边界**：**未改 `src/` 任何文件**。本报告是提案，执行权在 HumanSteward。
> **所有行号、库读数均为本次现读**

---

## 结论

**判定链落在 `src/engine/omega_strong.mbt:46` 的 `omega_enabled()`，我无权改（engine 层受角色保护）。**
**本报告给出精确 patch，由 HumanSteward 应用。**

| 项 | 值 |
|---|---|
| **根因层** | `src/engine/omega_strong.mbt:46`（`omega_enabled` 的文本兜底分支） |
| **拦截点** | `src/engine/engine_archive_force.mbt:29-34`（`if omega_enabled(t)`） |
| **我的权限** | 🔴 **拒绝** —— `src/engine/` 需 HumanSteward / Leader |
| **patch 形态** | 改 `omega_enabled` 调用方（`engine_archive_force.mbt` 与 `engine.mbt:797`），**不改 `omega_enabled` 本体** |

**⇒ 3 条孤儿**（`T0r636.1.2` / `.2.2` / `.3.2`）**本次未归档**（我无权改代码，归档前置条件不成立）。

---

## 1. 根因链（逐条带 文件:行）

### 1.1 判定式（真源）

```
src/engine/omega_strong.mbt:46-48
pub fn omega_enabled(t : @core.Task) -> Bool {
  t.get_omega_required() || t.description.contains(omega_mark())
}
```

**两个分支取或**：
- 分支① `get_omega_required()` —— 元数据列（BUG-389 方向②引入的权威面）
- 分支② `description.contains(omega_mark())` —— **旧数据文本兜底**

**BUG-417 的病灶在分支②**：它对「描述里**任何位置**出现 `[omega:required]`」都返回 true，
**不区分这个标记是「本任务自己的」还是「从父任务/兄弟切片文本里继承来的残留」**。

### 1.2 拦截点

```
src/engine/engine_archive_force.mbt:27-34
      // Omega 门（验收项：archive 不得绕过验收门）：强验证任务必须先过成果复验门，
      // force 也不能放行——归档即"了账"，未通过 Omega 门就是假了账。
      if omega_enabled(t) {
        match self.omega_verify_gate(task_id) {
          Err(e) => return Err("Omega 门禁拦截归档: \{e}")
          Ok(_) => ()
        }
      }
```

**同一判定在 `src/engine/engine.mbt:796-800`（普通 archive 路径）也有一份** ——
**两处都必须改，否则 force 路径修好了、普通路径还会拦**。

### 1.3 数据侧实读（`fist-mbt.db`，2026-10-26 现读）

```
=== 3 条目标的元数据 ===
  T0r636.1.2     status=已暂停  parent=T0r636.1  omega_required=0  描述含标记=True
  T0r636.2.2     status=已暂停  parent=T0r636.2  omega_required=0  描述含标记=True
  T0r636.3.2     status=已暂停  parent=T0r636.3  omega_required=0  描述含标记=True

=== 其父任务状态 ===
  T0r636.1   已归档   ← 父已归档
  T0r636.2   已归档   ← 父已归档
  T0r636.3   已归档   ← 父已归档
  T0r636     已完成

=== 交付物 ===
  T0r636.1.2 的 specs 条数 = 0   ← 从未有交付物
```

**⇒ 与 Lane I 的诊断完全一致：`omega_required=0` 但描述含标记 ⇒ 走文本兜底 ⇒ 被拦。**

### 1.4 ⭐ 关键补充：标记出现在**哪个位置**（这条决定了修法）

```
描述长度 4683，标记出现 2 次：
  位置 3097: …「…子任务单元 2」做成可独立验证的最小可行片；由易到难——先完成该
             更简单变体，再推广/逆推到本任务目标（LADDER 先易后逆推） [omega:required]
             | [父计划: fist-mbt 全程打磨推进（组合模式[打磨,寻虫,修复,验…」
  位置 4117: …（同上结构，子任务单元 1）…[omega:required] | [父计划: …]
描述尾部: …· 剩余兄弟: 1] [边界四问:…] [边界四问:…]
```

**⇒ 这两个标记不是本任务的标记，是「本任务描述里引用了父计划下某个 Omega 子任务的文本」时带进来的残留。**
**它们出现在「子任务单元」的说明里，且紧跟着 `| [父计划: …]` 的上下文拼接。**

**⇒ 这是 `task_plan_deep` 递归下钻 + `reinject_context` 回注的副产物：**
父层切片文本被拼进子层描述，**连同父层的 `[omega:required]` 标记一起拼进来了**。

---

## 2. 修法：(b) 语义修正 —— 但**修在调用方，不修 `omega_enabled` 本体**

### 2.1 为什么不改 `omega_enabled`

`omega_enabled(t)` 是**单一判据真源**（`core_task.mbt:765` 注释明写「不要引第 5 种判法」）。
**它的签名里没有「父任务」信息** —— 要让它感知父已归档，必须给它加 `store` 参数，
**那会破坏「纯函数单一判据」的设计**，且所有调用点都要改。

### 2.2 正确做法：在**调用方**加一层「孤儿豁免」

```moonbit
// 新增纯函数（放 omega_strong.mbt，与 omega_enabled 同文件、同层）
///|
/// BUG-417：父已归档的孤儿叶子不适用 Omega 门。
///
/// 语义依据：`omega_strong_verify` 的语义是「**这棵任务树**的成果要被验证」。
/// 父任务已归档 ⇒ 那棵树的验收语境已终结 ⇒ 让一个没有父亲的叶子继续满足 Omega 门
/// 是**判据错位**，不是任务的问题。
///
/// 只回答一个问题：`t` 的**直接父任务**是否存在且已归档。
/// 注意：只判直接父（非整条祖先链）—— 直接父归档即该叶子的验收语境终结，
/// 祖辈归档而直接父未归档时，验收责任仍在直接父身上。
pub fn omega_orphan_of_archived_parent(
  t : @core.Task,
  parent_status : @core.TaskStatus?,
) -> Bool {
  match t.get_parent() {
    None => false                       // 根任务无父 ⇒ 不豁免
    Some(_) =>
      match parent_status {
        None => false                   // 父取不到 ⇒ 保守不豁免（fail-closed）
        Some(st) => st.is_archived()
      }
  }
}
```

**⚠️ 关键设计：`parent_status` 由调用方查库传入，不在本函数里查** ——
保持纯函数、可单测、不引 IO。

### 2.3 调用方改动（两处，必须都改）

```moonbit
// engine_archive_force.mbt:29 现：
      if omega_enabled(t) {
// 改为：
      // BUG-417：父已归档 ⇒ 验收语境已终结 ⇒ 不适用 Omega 门（语义修正，非逃生口）。
      // 留痕：跳过时写入归档回执，不许静默跳过（不变量②）。
      let parent_st = match t.get_parent() {
        None => None
        Some(pid) => match self.store.get_task(pid) {
          None => None
          Some(p) => Some(p.get_status())
        }
      }
      let orphan = omega_orphan_of_archived_parent(t, parent_st)
      if omega_enabled(t) && !orphan {
        match self.omega_verify_gate(task_id) {
          Err(e) => return Err("Omega 门禁拦截归档: \{e}")
          Ok(_) => ()
        }
      }
      // 不变量②：留痕。orphan=true 时把豁免写进归档后的任务描述/账本。
      let omega_note = if omega_enabled(t) && orphan {
        " [BUG-417: 父任务已归档，Omega 门禁按语义豁免（父=\{(t.get_parent() ?? "")}）]"
      } else {
        ""
      }
```

**`engine.mbt:795-802` 已读全文核实**（原 R4 已消解）：

```moonbit
      // Omega 门（验收项：archive 不得绕过验收门）：强验证任务必须先过成果复验门，
      // 归档即"了账"，未通过 Omega 门就是假了账（纵深防御，与 archive_force 同门）。
      if omega_enabled(t) {
        match self.omega_verify_gate(task_id) {
          Err(e) => return Err("Omega 门禁拦截归档: \{e}")
          Ok(_) => ()
        }
      }
```

**与 `engine_archive_force.mbt:29-34` 结构完全相同（缩进也一致）⇒ patch 3 可直接照 patch 2 的形态写。**

**留痕落地：`Task::with_description` 已确认存在**（`src/core/core_task.mbt:744`）：
```moonbit
pub fn Task::with_description(...)   // :744  ← 已核实，非推测
```

**⇒ patch 2 的最后一步可写成精确代码**：

```moonbit
      let c2 = c.with_updated_at(now)
      // 不变量②：留痕。豁免不许静默。
      let c2 = if omega_note == "" {
        c2
      } else {
        c2.with_description(c2.description + omega_note)
      }
```

**⚠️ 注意**：上面两个 `let c2 =` 需合并成一个（MoonBit 允许遮蔽，但为清晰建议写成
`let c3 = if omega_note == "" { c2 } else { c2.with_description(...) }` 再 `update_task(c3)`）。

---

## 3. 三个不变量的锁法（含变异对照设计）

### 不变量①：真需要复验的任务不受影响

**锁 1：父**未**归档 + 有交付物 ⇒ 仍被拦**
```moonbit
test "bug417_parent_active_still_gated" {
  // 夹具：父 已领取（未归档）；子 omega_required=1
  // 断言：omega_orphan_of_archived_parent(child, Some(Claimed)) == false
  //      且 archive_force 返回 Err 含 "Omega 门禁拦截归档"
}
```

### 不变量②：动作留痕

**锁 2：豁免时描述含留痕标记**
```moonbit
test "bug417_orphan_exemption_is_traced" {
  // 夹具：父 已归档；子 omega_required=0 但描述含 [omega:required]
  // 断言：archive_force 成功，且归档后 description 含 "BUG-417" 与 "父任务已归档"
}
```

### 不变量③：成对回归锁

**锁 3（正例）：父已归档的叶子 ⇒ 可归档**
```moonbit
test "bug417_orphan_leaf_archivable" {
  // 同锁 2 夹具，断言 Ok
}
```

**锁 4（⭐ 变异对照，判例-29）**
```moonbit
test "bug417_variant_parent_archived_check_is_real" {
  // 【变异对照】证明 omega_orphan_of_archived_parent 真在读状态，而不是恒返回 true/false。
  // 同一 t、只改 parent_status：
  //   Some(Archived)   ⇒ true   （豁免）
  //   Some(Completed)  ⇒ false  （不豁免 —— 已完成但未归档，验收语境仍在）
  //   Some(Claimed)    ⇒ false
  //   None             ⇒ false  （父取不到 ⇒ fail-closed）
  // 若有人把函数改成 `true`（恒豁免）⇒ 后三格必红
  // 若有人把函数改成 `false`（恒不豁免）⇒ 第一格必红
}
```

**⚠️ 锁 4 的设计要点**：`Some(Completed)` 这一格是**最容易写错的**——
「已完成」不等于「已归档」。若实现里误用 `is_completed()`，这一格必红。

**⚠️ 判例-30（自指假绿）防护**：锁 4 只断言**函数返回值**，不断言源码里有某个字符串。
若将来有人写「断言源码含 `is_archived`」，那会命中注释里的字面量 ⇒ 假绿。

---

## 4. 精确 diff 草案

**⚠️ 以下 diff 落在 `src/engine/` —— 我无权应用。未暂存、未提交。**

### patch 1：`src/engine/omega_strong.mbt`（新增纯函数）

```diff
--- a/src/engine/omega_strong.mbt
+++ b/src/engine/omega_strong.mbt
@@ -48,6 +48,30 @@ pub fn omega_enabled(t : @core.Task) -> Bool {
   t.get_omega_required() || t.description.contains(omega_mark())
 }

+///|
+/// BUG-417：父已归档的孤儿叶子不适用 Omega 门。
+///
+/// 语义依据：`omega_strong_verify` 的语义是「这棵任务树的成果要被验证」。
+/// 父任务已归档 ⇒ 那棵树的验收语境已终结 ⇒ 让一个没有父亲的叶子继续满足
+/// Omega 门是**判据错位**，不是任务的问题。
+///
+/// 只判**直接父**（非整条祖先链）：直接父归档即该叶子的验收语境终结；
+/// 祖辈归档而直接父未归档时，验收责任仍在直接父身上。
+///
+/// `parent_status` 由调用方查库传入（保持本函数纯、可单测、无 IO）。
+/// 父取不到（None）⇒ **保守不豁免**（fail-closed，与全仓 ACL 口径一致）。
+pub fn omega_orphan_of_archived_parent(
+  t : @core.Task,
+  parent_status : @core.TaskStatus?,
+) -> Bool {
+  match t.get_parent() {
+    None => false
+    Some(_) =>
+      match parent_status {
+        None => false
+        Some(st) => st.is_archived()
+      }
+  }
+}
+
 ///|
 /// 去掉切片文本中已存在的强验证标记（避免递归下钻时标记逐层累积）。
 pub fn omega_clean_slice(s : String) -> String {
```

### patch 2：`src/engine/engine_archive_force.mbt`（拦截点）

```diff
--- a/src/engine/engine_archive_force.mbt
+++ b/src/engine/engine_archive_force.mbt
@@ -27,11 +27,29 @@ pub fn FistEngine::archive_force(
       // Omega 门（验收项：archive 不得绕过验收门）：强验证任务必须先过成果复验门，
       // force 也不能放行——归档即"了账"，未通过 Omega 门就是假了账。
-      if omega_enabled(t) {
+      // BUG-417 语义修正：父已归档 ⇒ 该叶子的验收语境已终结 ⇒ 不适用 Omega 门。
+      // 这不是逃生口——真需要复验的任务（父未归档）照旧被拦（见 wbtest 锁 1）。
+      let parent_st = match t.get_parent() {
+        None => None
+        Some(pid) =>
+          match self.store.get_task(pid) {
+            None => None
+            Some(p) => Some(p.get_status())
+          }
+      }
+      let orphan = omega_orphan_of_archived_parent(t, parent_st)
+      if omega_enabled(t) && !orphan {
         match self.omega_verify_gate(task_id) {
           Err(e) => return Err("Omega 门禁拦截归档: \{e}")
           Ok(_) => ()
         }
       }
+      // 不变量②：留痕。豁免不许静默（否则下一次没人知道这单为什么能过）。
+      let omega_note = if omega_enabled(t) && orphan {
+        " [BUG-417: 父任务(\{(t.get_parent() ?? "")})已归档，Omega 门禁按语义豁免]"
+      } else {
+        ""
+      }
       let c = match t.archive_force(force~) {
         Ok(x) => x
         Err(e) => return Err(e)
       }
-      let c2 = c.with_updated_at(now)
+      let c2 = c.with_updated_at(now)
+      // omega_note 非空时追加进描述（最小留痕面；若有专属字段更佳）
```

**⚠️ 最后那行我只写到「追加进描述」的意图** —— 因为 `with_description` 的确切名字我没核
（`core_task.mbt` 的 setter 命名需确认）。**不给伪精确代码，胜过给一个编不过的 patch。**

### patch 3：`src/engine/engine.mbt:796-800`（普通 archive 路径，同族）

```diff
       // 归档即"了账"，未通过 Omega 门就是假了账（纵深防御，与 archive_force 同门）。
-      if omega_enabled(t) {
+      // BUG-417：与 archive_force 同一条语义修正（父已归档 ⇒ 不适用），
+      // 否则 force 路径修好了、普通路径还会拦同一个任务。
+      let parent_st = match t.get_parent() {
+        None => None
+        Some(pid) =>
+          match self.store.get_task(pid) {
+            None => None
+            Some(p) => Some(p.get_status())
+          }
+      }
+      if omega_enabled(t) && !omega_orphan_of_archived_parent(t, parent_st) {
```

---

## 5. 缺口与风险

| # | 项 | 说明 |
|---|---|---|
| **R1** | **我无权改 `src/engine/`** | `reserve_scope` 明确拒绝（`Executor` 无权，允许 `HumanSteward, Leader`）。**本报告只出 patch** |
| **R2** | **3 条孤儿本次未归档** | 前置条件（代码修好）不成立。**库读数仍 81 条已暂停**（非目标 78） |
| **R3** | ~~`with_description` 的名字未核~~ | ✅ **已消解**：`Task::with_description` 存在于 `src/core/core_task.mbt:744`，patch 2 已给精确代码 |
| **R4** | ~~`engine.mbt:796` 我未读全文~~ | ✅ **已消解**：已读 `:790-811`，结构与 `engine_archive_force.mbt:29-34` 完全一致，patch 3 可直接套用 |
| **R5** | **为何标记会进描述（根因的上游）未修** | §1.4 查明标记来自「父层切片文本被 `reinject_context` 拼进子层」。**这是上游问题**（`task_plan_deep` 的回注逻辑），本次 patch 只做「归档时的语义豁免」，**没有阻止新孤儿产生**。建议另开一单 |
| **R6** | **`omega_enabled` 的文本兜底仍是隐患** | 它对「任意位置的标记」敏感。本次在调用方兜住，**真源没动**。长期看应在 `omega_clean_slice` 之外再有一个「标记归属」判据，但那是大改 |

---

## 6. 建议入档位置

1. **本报告**：`reports/2026-10-26-bug417-omega-orphan-fix-report.md`
2. **判例候选**：
   > **判例-XX：文本兜底判据必须区分「自身的标记」与「继承的标记」。**
   > `omega_enabled` 的 `description.contains(mark)` 分支不区分标记归属，
   > 于是一个 `omega_required=0` 的任务，只因描述里引用了父层文本（含标记）就被判为强验证任务。
   > **⇒ 任何「扫描文本找标记」的兜底判据，都要回答「这个标记是谁留下的」。**
   > 回答不了，就只该在「没有权威面」时才用它（这里权威面 = `get_omega_required()` 列，明确为 0）。
3. **上游单**（R5）：`task_plan_deep` 的 `reinject_context` 在把父层切片拼进子层描述时，
   应**先 `omega_clean_slice` 清理标记**（该函数已存在！`omega_strong.mbt:52`），
   而非让标记随上下文一起回注。**这是根治，比归档时豁免更根本。**

---

**本报告未修改 `src/` 任何文件。未 commit。所有 diff 均为提案。**
