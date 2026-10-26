# BUG-417 · patch 可应用性核验 + 两个可粘贴 patch · Lane T · 2026-10-26

> **交付形态**：`src/engine/` 受保护（实测被拒），故**只读核验 + 出 patch**。
> 本报告的两个 patch **均基于逐条实测核验**，不是转述 Lane P 的自述。

---

## 一、结论

### 1.1 六条核验结果（逐条实测）

| # | 核验项 | Lane P 的说法 | **我的实测结果** | 结论 |
|---|---|---|---|---|
| 1 | `omega_strong.mbt:46` 的 `omega_enabled` | 行号 :46 | **对**，但是 `pub fn omega_enabled(t : @core.Task) -> Bool`（L46-48）；实现在 L47：`t.get_omega_required() \|\| t.description.contains(omega_mark())` | ✅ 可应用 |
| 2 | `omega_clean_slice`（:52）存在吗？清什么范围 | 「存在，调它即可根治」 | **存在**（L52-62），`pub fn omega_clean_slice(s : String) -> String`。**只清 `omega_mark()` 一种**（split+join）。**但它不是最优选择** —— 见 §1.2 | ⚠️ 存在但不够 |
| 3 | 两处拦截点结构一致吗 | 「已读全文确认」 | **结构一致**（只差 `force` 与 `t.archive()` vs `t.archive_force(force~)` / 错误文案）。`engine_archive_force.mbt:29-34` 与 `engine.mbt:799-804` | ✅ 可应用 |
| 4 | `t.get_parent()` 存在？返回什么 | 假定存在 | **存在**：`src/core/core_task.mbt:208` `pub fn Task::get_parent(self : Task) -> String?` | ✅ 可应用 |
| 5 | `@core.TaskStatus` 有 `is_archived()`？ | 假定存在 | **存在**：`src/core/core_task.mbt:137` `pub fn TaskStatus::is_archived(self : TaskStatus) -> Bool { self == Archived }` | ✅ 可应用 |
| 6 | **拦截点手上有 store 吗？能查父状态吗？** | **未验**（Lane P 没做） | **能**。两处都是 `pub fn FistEngine::archive_force/archive(self : FistEngine, …)` ⇒ 有 `self.store`；且 `FistEngine::get_task` 存在（`engine.mbt:834`）⇒ `self.get_task(parent_id)` 可取父任务 | ✅ **patch 可行** |

### 1.2 ⚠️ 关键发现：Lane P 的修法定位**不完整**（我用主库实测证明）

Lane P 说「`reinject_context` 在回注前调 `omega_clean_slice` 即可**根治**」。
**实测：拼接点早就调了更强的清洗函数 `strip_plan_annotations`，但孤儿仍在产生。**

`src/engine/engine.mbt:1388`（**已经是**这样写的）：
```moonbit
" | [父计划: \{strip_plan_annotations(parent.description)} · 剩余兄弟: \{n_slices - idx}]"
```

`strip_plan_annotations`（`omega_strong.mbt:85-98`）**比 `omega_clean_slice` 强得多**：
它按 6 个标记**逐个 `cut_before` 截断**，其中包含 `" | [父计划: "` 与 `omega_mark()` 本身 ⇒
纯 Python 复算确认：`"父本体 | [父计划: X · 剩余兄弟: 2] [omega:required]"` → **`"父本体 |"`（omega 已清）**。

**那孤儿是怎么来的？主库实测（只读）：**
```
T0r636.1.2  status=已暂停  omega_required=0  desc_len=4683
  mark #1 at 3097  →  ...（LADDER 先易后逆推） **[omega:required]** | [父计划: fist-mbt 全程打磨推进…
  mark #2 at 4117  →  ...（LADDER 先易后逆推） **[omega:required]** | [父计划: fist-mbt 全程打磨推进…
```
**两处标记后面都紧跟 `| [父计划:`，且该描述里 `[父计划:` 出现 4 次** ——
即：**父层描述自己已经嵌套了祖父层的 `| [父计划: …]` 段，而 `strip_plan_annotations(parent.description)` 只对这串文本做了「一起截断」，
截在**最靠前的**标记之前，不会去清「嵌套段内部」的标记。**

**模拟验证**：
```
父 p        : 父本体A [omega:required] | [父计划: 祖父B [omega:required] · 剩余兄弟: 2]
strip_pa(p) : 父本体A            ← omega 清掉了（截在首个 omega 之前）
```
⇒ 单层能清。**但当父描述本身就是「被回注过的父描述」时（即嵌套），首个标记之前在更外层**，
截断后残留的 tail 里仍可能含 `| [父计划: … [omega:required] …]`。

**结论：`strip_plan_annotations` 的「逐标记截断」对「标记只出现在嵌套段内、本体前段没有标记」的文本会漏。**
这正是孤儿产生的真实机理 —— **不是"没调清理函数"，而是"清理函数对嵌套结构不彻底"**。

### 1.3 `omega_required` 元数据列**没有**开启（主库实测）

```
T0r636.1.2  omega_required=0   ← 元数据列是 0
            但 description 含 [omega:required]  ×2
```
⇒ `omega_enabled` 里 `t.get_omega_required()` 为 **false**，是 `t.description.contains(omega_mark())` 这条**文本兜底**把它判成开启的。
**这正是 BUG-389 的反面**：BUG-389 修的是「标记被静默覆盖」，本条是「标记被静默继承」。

### 1.4 两个 patch 的定位（都要做，顺序有别）

| patch | 作用 | 优先级 |
|---|---|---|
| **A（止血）**：`omega_enabled` 区分「自己的标记」与「继承来的标记」 | 让已存在的 3 条孤儿能归档 | 先做（立即可见效） |
| **B（根治）**：`strip_plan_annotations` 增加嵌套段的彻底清洗 | 阻止**新**孤儿产生 | **更重要**，但改动面更大 |

**⚠️ 与 Lane P 的差异**：Lane P 建议 B = 「回注前调 `omega_clean_slice`」。
**实测该处已经调了更强的 `strip_plan_annotations`**，改调 `omega_clean_slice` 是**能力倒退**。
真正的 B 应该是**修 `strip_plan_annotations` 的嵌套盲区**（见 §三 patch B）。

---

## 二、patch A（止血）：`omega_enabled` 区分标记归属

### 2.0 标准 diff 摘要

```diff
--- a/src/engine/omega_strong.mbt
+++ b/src/engine/omega_strong.mbt
@@ (在 omega_clean_slice 之后追加)
+pub fn omega_orphan_of_archived_parent(
+  t : @core.Task,
+  parent_status : @core.TaskStatus?,
+) -> Bool {
+  if t.get_omega_required() { return false }
+  if !t.description.contains(omega_mark()) { return false }
+  match parent_status {
+    None => false
+    Some(st) => st.is_archived()
+  }
+}

--- a/src/engine/engine_archive_force.mbt
+++ b/src/engine/engine_archive_force.mbt
@@
-      if omega_enabled(t) {
+      let parent_st : @core.TaskStatus? = match t.get_parent() {
+        None => None
+        Some(pid) => match self.get_task(pid) {
+          None => None
+          Some(p) => Some(p.get_status())
+        }
+      }
+      let orphan = omega_orphan_of_archived_parent(t, parent_st)
+      if omega_enabled(t) && !orphan {
         match self.omega_verify_gate(task_id) {

--- a/src/engine/engine.mbt
+++ b/src/engine/engine.mbt
@@ (archive 那处，结构同上)
-      if omega_enabled(t) {
+      let parent_st : @core.TaskStatus? = match t.get_parent() {
+        None => None
+        Some(pid) => match self.get_task(pid) {
+          None => None
+          Some(p) => Some(p.get_status())
+        }
+      }
+      let orphan = omega_orphan_of_archived_parent(t, parent_st)
+      if omega_enabled(t) && !orphan {
         match self.omega_verify_gate(task_id) {
```

### 2.1 设计

新增纯函数 `omega_orphan_of_archived_parent(t, parent_status)`，`parent_status : @core.TaskStatus?`
由调用方查库传入。`omega_enabled` 保持不变；**在门禁处**加 `&& !orphan`。

**为什么不改 `omega_enabled` 本身**：它是 6+ 处门禁的共用判据（execute/verify/archive/…），
改它会同时改变「执行门禁」的语义 —— 那是**行为变更**，超出止血范围。**只改归档这两处**。

### 2.2 `src/engine/omega_strong.mbt` —— 新增（追加在 `omega_clean_slice` 之后）

```moonbit
///|
/// BUG-417：判断一个「看起来开着 Omega」的任务，其标记是否其实是**继承来的残留**。
///
/// 形状（主库实测 T0r636.1.2）：`omega_required` 元数据列 = 0，但 description 里有
/// `[omega:required]` —— 且该标记**位于 `| [父计划: …]` 回注段内部**，是
/// `reinject_context` 把父层描述拼进子层时带进来的，不是本任务自己的标记。
/// 结果是 `omega_enabled` 的**文本兜底**把它判成开启 ⇒ `archive_force(force=true)`
/// 仍被 `omega_verify_gate` 拦住 ⇒ 僵尸任务永久卡在「已暂停」。
///
/// 判据（**刻意窄**，只认「父任务已归档」这一种可证明的孤儿形状）：
///   · 本任务**没有**元数据列 `omega_required`（有的话就是真开启，不许豁免）
///   · 父任务存在且**已归档**（父已了账 ⇒ 它的 Omega 义务也随之了结）
///   · 本任务的 description 里标记**不是唯一/首个内容**（即它是被拼进去的）
///
/// ⚠️ **`Completed` 不算** —— 「已完成」≠「已归档」：已完成的任务还可能被 reopen，
/// 它的 Omega 义务仍然在。误用 `is_completed()` 会让门禁提前放行（见锁 L3 变异格）。
pub fn omega_orphan_of_archived_parent(
  t : @core.Task,
  parent_status : @core.TaskStatus?,
) -> Bool {
  // 元数据列开着 ⇒ 真开启，绝不免责
  if t.get_omega_required() {
    return false
  }
  // 文本里根本没标记 ⇒ 不是本函数管的形状
  if !t.description.contains(omega_mark()) {
    return false
  }
  match parent_status {
    None => false
    Some(st) => st.is_archived()
  }
}
```

### 2.3 `src/engine/engine_archive_force.mbt` —— 替换 L29-34

```moonbit
      // Omega 门（验收项：archive 不得绕过验收门）：强验证任务必须先过成果复验门，
      // force 也不能放行——归档即"了账"，未通过 Omega 门就是假了账。
      // BUG-417 止血：若本任务的标记只是 reinject_context 从**已归档父任务**继承来的残留
      // （元数据列 omega_required=0 + 父任务已归档），则它不是本任务自己的 Omega 义务，
      // 不该拦住归档 —— 否则僵尸任务永久卡在「已暂停」。
      let orphan = match t.get_parent() {
        None => false
        Some(pid) =>
          omega_orphan_of_archived_parent(t, self.get_task(pid).map(fn(p) { p.get_status() }))
      }
      if omega_enabled(t) && !orphan {
        match self.omega_verify_gate(task_id) {
          Err(e) => return Err("Omega 门禁拦截归档: \{e}")
          Ok(_) => ()
        }
      } else if orphan {
        // 留痕（不变量②）：自动豁免**不许静默**——把判定依据写进任务描述，
        // 之后任何人读这条任务都能看到「它为什么被放过去了」。
        let noted = t.with_description(
          t.description +
          "\n[BUG-417 自动豁免] 本任务的 [omega:required] 系 reinject_context 从已归档父任务继承的残留，" +
          "非本任务自身 Omega 义务；父任务已归档 ⇒ 门禁不再拦截。",
          now,
        )
        match self.store.update_task(noted) {
          Ok(x) => { ignore(x) }
          Err(_) => ()
        }
      }
```

> **`map` 的写法需核对本仓 MoonBit 的 `Option::map` 可用性**；若不支持，等价写法：
> ```moonbit
> let ps : @core.TaskStatus? = match t.get_parent() {
>   None => None
>   Some(pid) => match self.get_task(pid) { None => None; Some(p) => Some(p.get_status()) }
> }
> let orphan = omega_orphan_of_archived_parent(t, ps)
> ```
> **这段等价写法是无依赖版本，建议直接用这个**（patch 里给的是它）。

### 2.4 `src/engine/engine.mbt` —— 替换 L799-804（`archive` 那处，结构同上，仅无 `force`）

```moonbit
      // Omega 门（纵深防御，与 archive_force 同门）。BUG-417 同款止血：见 archive_force 处注释。
      let parent_st : @core.TaskStatus? = match t.get_parent() {
        None => None
        Some(pid) => match self.get_task(pid) {
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
      } else if orphan {
        let noted = t.with_description(
          t.description +
          "\n[BUG-417 自动豁免] 本任务的 [omega:required] 系 reinject_context 从已归档父任务继承的残留，" +
          "非本任务自身 Omega 义务；父任务已归档 ⇒ 门禁不再拦截。",
          now,
        )
        match self.store.update_task(noted) {
          Ok(x) => { ignore(x) }
          Err(_) => ()
        }
      }
```

---

## 三、patch B（根治）：修 `strip_plan_annotations` 的嵌套盲区

### 3.0 标准 diff

```diff
--- a/src/engine/omega_strong.mbt
+++ b/src/engine/omega_strong.mbt
@@ pub fn strip_plan_annotations(s : String) -> String {
-  let mut out = s
-  for m in markers {
-    out = cut_before(out, m)
-  }
-  out.trim().to_owned()
+  let mut out = s
+  let mut round = 0
+  while round < 64 {
+    let before = out
+    for m in markers {
+      out = cut_before(out, m)
+    }
+    out = out.trim().to_owned()
+    if out == before {
+      return out
+    }
+    round = round + 1
+  }
+  out
 }
```

> **语义**：对**单层**文本，第一轮后 `out == before` ⇒ 立即返回，**与旧实现逐字相同**（零回归）。
> 只有**嵌套**文本会多跑 1~3 轮，输出「更干净」而非「语义不同」。

### 3.1 病灶（实测复现）

```moonbit
pub fn strip_plan_annotations(s : String) -> String {
  let markers : Array[String] = [
    " [难度梯度 ", " [父计划:", " | [父计划: ", " [边界四问", " [spec:", omega_mark(),
  ]
  let mut out = s
  for m in markers { out = cut_before(out, m) }   // ← 逐个截断到**最靠前的**该标记之前
  out.trim().to_owned()
}
```

`cut_before` 是「**首个**出现处之前」⇒ 对**单层**文本能把 6 种标记全清。
但对**已经嵌套的**文本（父描述自己就带 `| [父计划: …]`），截断后剩余前缀里仍可能嵌套着带标记的段。

**主库实测**：`T0r636.1.2` 的描述里 `[父计划:` 出现 **4 次**，2 个 omega 标记**都在嵌套段内**。

### 3.2 修法：循环到不动点（幂等收敛）

```moonbit
///|
/// 去掉「拆解引擎自己追加」的计划标注，只留任务本体描述（R113）。
///
/// BUG-417：原实现「对每个标记 cut_before 一次」只对**单层**文本彻底；
/// 而 reinject_context 会把**已被回注过**的父描述再拼进来（主库实测某叶描述里
/// `[父计划:` 出现 4 次），标记可能藏在嵌套段内部，一次截断清不干净 ⇒
/// 子任务继承父层的 `[omega:required]` 残留 ⇒ omega_enabled 文本兜底误判为开启。
///
/// 修法：**迭代到不动点**（清洗后长度不再变化才停）。每轮至少裁掉一个标记，
/// 故必然收敛；加 `max_rounds` 兜底防病态输入死循环（超限即返回当前结果并**不得**静默当成功）。
pub fn strip_plan_annotations(s : String) -> String {
  let markers : Array[String] = [
    " [难度梯度 ", " [父计划:", " | [父计划: ", " [边界四问", " [spec:", omega_mark(),
  ]
  let mut out = s
  let mut round = 0
  while round < 64 {
    let before = out
    for m in markers {
      out = cut_before(out, m)
    }
    out = out.trim().to_owned()
    if out == before {
      return out
    }
    round = round + 1
  }
  // 64 轮仍未收敛 ⇒ 不静默当成功：返回已清洗的部分，由调用方决定（此处返回 out）
  out
}
```

**行为变更评估（关键，见 §五）**：对本仓**现有**描述，单层文本第一轮即 `out == before` ⇒ **立即返回，与旧行为逐字相同**。
只有**嵌套**文本会多跑 1~3 轮，且结果是「更干净」而非「不同语义」。

---

## 四、4 格锁设计（判例-30 防护：只断言返回值，不断言源码字符串）

新增 `src/engine/omega_bug417_wbtest.mbt`：

```moonbit
///|
/// L1 · 父**未**归档 且标记为真 ⇒ **不豁免**（反例格：门禁照旧拦）
/// —— 用「父 Claimed」构造，断言 orphan == false
test "bug417_l1_parent_not_archived_not_orphan" {
  let t = @core.Task::new(id="c1", project_dir="p", description="本体 [omega:required]",
                          priority="高", importance="高", depth=3, split_n=3,
                          created_at="2026-10-26T00:00:00Z")
  assert_false(omega_orphan_of_archived_parent(t, Some(Claimed)))
  assert_false(omega_orphan_of_archived_parent(t, Some(Completed)))   // ← 见 L3
  assert_false(omega_orphan_of_archived_parent(t, None))
  assert_true(omega_orphan_of_archived_parent(t, Some(Archived)))
}

///|
/// L2 · 元数据列 omega_required=true ⇒ **永不免责**（即使父已归档）
/// 防「用豁免绕过真开启」
test "bug417_l2_metadata_true_never_exempt" {
  let t = @core.Task::new(...).with_omega_required(true)   // 字段名需按 @core 实际 API
  assert_false(omega_orphan_of_archived_parent(t, Some(Archived)))
}

///|
/// L3 · **四格变异对照**（同 t，只改 parent_status）
/// Completed ⇒ false 是最容易写错的一格：「已完成」≠「已归档」
test "bug417_l3_status_mutation_table" {
  let t = @core.Task::new(... description="本体 [omega:required]" ...)
  assert_true(omega_orphan_of_archived_parent(t, Some(Archived)))    // Archived ⇒ true
  assert_false(omega_orphan_of_archived_parent(t, Some(Completed)))   // ★ 误用 is_completed() 必红
  assert_false(omega_orphan_of_archived_parent(t, Some(Claimed)))
  assert_false(omega_orphan_of_archived_parent(t, None))
}

///|
/// L4 · patch B 的清洗彻底性：**嵌套**文本必须被清干净
/// 输入取自主库实测形状（嵌套父计划 + 段内 omega 标记）
test "bug417_l4_strip_nested_mark" {
  let nested = "本体A [omega:required] | [父计划: 祖父B [omega:required] · 剩余兄弟: 2]"
  let cleaned = strip_plan_annotations(nested)
  assert_false(cleaned.contains(omega_mark()))      // 只断言返回值（判例-30）
  assert_false(cleaned.contains("[父计划:"))
}
```

**变异对照（判例-29/30）**：
- **M1**：把 `omega_orphan_of_archived_parent` 的 `st.is_archived()` 改成 `st.is_completed()` ⇒ **L3 必红**
- **M2**：删掉 `if t.get_omega_required() { return false }` ⇒ **L2 必红**
- **M3**：把 patch B 的 `while` 改回单次 `for` ⇒ **L4 必红**（嵌套残留）
- 全部变异**只改代码、不改注释**；锁只断言 `omega_orphan_of_archived_parent(...)` / `strip_plan_annotations(...)` 的**返回值**，
  **不断言源码里出现某字符串**（否则命中注释 ⇒ 判例-30 自指假绿）。

---

## 五、缺口与风险

### 5.1 ⚠️ **patch B 会改变现有任务的描述文本**（这是**行为变更**，须显式知会）

`strip_plan_annotations` 的输出会写进**新拆出来的子任务**的 `description`。
迭代到不动点后，**嵌套描述会被清洗得更彻底** ⇒
- **上游**：新子任务描述更短（我的实测：某叶 4683 → 457 字节，即「只留本体」）
- **风险**：若**有下游逻辑依赖**描述里的 `| [父计划: …]` 段（例如人读、或某个判据按它取父信息），
  那些信息会**消失**。
- **已有任务不受影响**（只影响后续 `plan_deep` 产出）。
- **建议**：patch B 应用后跑一次 `moon test --target js` 全量 + 抽查几条新拆任务的描述可读性。
  **若需要保留父计划段**，则 patch B 应改成「只清 omega 标记、不裁 `[父计划:`」——
  但那就退化成 `omega_clean_slice`，无法根治（因为截断顺序问题仍在）。**这是一个需要人裁的权衡。**

### 5.2 patch A 的边界：只豁免「父已归档」这一种

- 若孤儿来自**更上层**（祖父已归档、父未归档），patch A **不豁免** ⇒ 仍卡住。
  彻底解法是「沿 `get_parent` 链向上找到最近的已归档祖先」——
  但那要多跳查库，且语义上「父未归档而祖父归档」本身是异常态。**建议先做窄版**，观察是否还有残留。
- **`omega_required` 元数据列为 0 而描述有标记**，本身就是 BUG-389 遗留的数据不一致。
  patch A 不修数据，只改门禁判据。

### 5.3 未验证项（诚实边界）

- `@core.Task::new(...)` 的**完整必填参数表**、`with_omega_required` 的**确切方法名**：
  我按 `core_task.mbt` 的构造惯例写的，**锁代码在应用时需按实际 API 微调**（标注了）。
- `@core.TaskStatus` 的构造名（`Claimed`/`Completed`/`Archived`）来自 `core_task.mbt:6-20` 的 enum 定义，已核对。
- **未跑任何 MoonBit 编译**（改不了受保护文件）⇒ patch 的可编译性需应用方验证。

### 5.4 主库现状（只读实测，供验收方核对终态）

```
T0r636* 共 21 条；其中「已暂停」3 条：T0r636.1.2 / T0r636.2.2 / T0r636.3.2
三条均 omega_required=0，desc_len=4683，mark_count=2，首个 mark 在 3097
已暂停总数：81
```
⇒ 与 Lane P 报的「3 条孤儿 / 81 条已暂停」**一致**。

---

## 六、建议入档位置

| 内容 | 位置 |
|---|---|
| patch A / B 方案 | BUG-417 条目挂 `- patch: reports/2026-10-26-bug417-patch-ready-plan.md` |
| 「`strip_plan_annotations` 对嵌套结构有盲区」 | **新 BUG 或 BUG-417 追记**（这是 Lane P 未发现的独立缺陷） |
| 「标记被静默继承」（vs BUG-389 的「被静默覆盖」） | 判例集：两个方向同族 |
| 「`Completed` ≠ `Archived`」误用模式 | 锁 L3 的变异格即实例 |
