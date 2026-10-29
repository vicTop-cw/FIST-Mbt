# 批 3 三分类清单（Lane DM）· 15 处 · **等确认后动手**

> **纪律**：每条「依据」都是 grep 读数，不是判断。
> **重号说明**：`atgc-old/codon.mbt` / `atgc/vm.mbt` 属**衍生子项目**（不计入 `src/` 主工程）。

---

## 一、总表

| # | 符号 | 文件:行 | 分类 | 依据（grep 读数）|
|---|---|---|---|---|
| 1 | `Codon::Load` | atgc-old/codon.mbt:56 | **② 预留** | 构造 0；match 分支 3（`:192`/`:204`）；自身注释「**占位**，idea.md Q2 未分配密码子」|
| 2 | `Codon::Store` | atgc-old/codon.mbt:58 | **② 预留** | 构造 0；match 分支 3（`:193`/`:205`）；注释「**占位**，Q2 未分配」|
| 3 | `Codon::Mod` | atgc-old/codon.mbt:60 | **② 预留** | 构造 0；match 分支 2（`:194`/`:204`）；注释「**占位**，Q2 与 START 双义悬而未决」|
| 4 | `Inst::Num` | atgc/vm.mbt:23 | **③ 本该构造** | **构造 0**；match 分支 1（`:42` `Num(_) => Err("vm: 数据语境值不应作为指令执行")`）——**有专门的错误分支却永不触发** |
| 5 | `WorldState` | src/constraint/constraint.mbt:28 | **③ 本该构造** | **生产构造 0**；**测试构造 1**（`constraint_wbtest.mbt:111` `mk_world`）；生产消费 **5 处**（`eval_known_agent`/`eval_no_overlap` 等的参数）|
| 6 | `ActiveReservation` | src/constraint/constraint.mbt:35 | **③ 本该构造** | **生产构造 0**；**测试构造 1**（`constraint_wbtest.mbt:121`）；生产消费 2（`WorldState.reservations` 字段 + `find_active` 返回类型）|
| 7 | `PlannedAction` | src/constraint/constraint.mbt:43 | **③ 本该构造** | **生产构造 0**；**测试构造 1**（`constraint_wbtest.mbt:130` 等）；生产消费 **6 处** |
| 8 | `MutationKind::Combine` | src/evolve/curriculum.mbt:123 | **③ 本该构造** ⚠️**最强** | 构造 0；match 分支 **2**（`:158` `mutation_prompt` / `:279` 字符串化）；**`:168` 注释明写「高分（L4）：偏向 Specialize / Combine」而 `select_mutation` 的 `r>=0.85` 分支只返回 `Specialize`** |
| 9 | `LtlFormula::And` | src/ltl/ltl.mbt:17 | **③ 本该构造** | 构造 0；match 分支 **4**（`:133` evaluate / `:202` eval_end / `:253` eval_const / `:294` formula_to_string）|
| 10 | `LtlFormula::Next` | src/ltl/ltl.mbt:19 | **③ 本该构造** | 构造 0；match 分支 **4**（`:157`/`:204`/`:275`/`:296`）|
| 11 | `LoopStatus::Active` | src/ops/ops_loop.mbt:22 | **① 真死（整组）** | 见 #12 说明 |
| 12 | `LoopStatus::MaxRoundsHit` | src/ops/ops_loop.mbt:23 | **① 真死（整组）** | 全仓 `LoopStatus` 命中仅 **5 处**：定义(`:21`) + `loop_status_str`(`:307`) + `.mbti` 2 + 本组；**构造 0、调用方 0** ⇒ 整个枚举 + 其唯一函数都是孤立件 |
| 13 | `LoopStatus::GoalReached` | src/ops/ops_loop.mbt:24 | **① 真死（整组）** | 同上 |
| 14 | `LoopStatus::Exceeded` | src/ops/ops_loop.mbt:25 | **① 真死（整组）** | 同上 |
| 15 | `LoopStatus::NoSteps` | src/ops/ops_loop.mbt:26 | **① 真死（整组）** | 同上 |

---

## 二、分类汇总

| 分类 | 数 | 符号 |
|---|---|---|
| **① 真死** | **5** | `LoopStatus` 全 5 个变体（整组孤立）|
| **② 预留** | **3** | `Codon::Load` / `Store` / `Mod`（注释自证「占位」）|
| **③ 本该构造** | **7** | `Inst::Num` / `WorldState` / `ActiveReservation` / `PlannedAction` / `MutationKind::Combine` / `LtlFormula::And` / `LtlFormula::Next` |

---

## 三、需要你拍板的三件事

### 🔴 A. `src/ops/ops_loop.mbt` 在你的禁区里

派单写「`src/ops/` 你不要动（Alpha 在改 `ops_commissar.mbt`）」。
但 **5 处 `① 真死` 全在 `src/ops/ops_loop.mbt`**（不是 `ops_commissar.mbt`）。

**⇒ 请确认**：我可以动 `ops_loop.mbt` 吗？还是等你协调 Alpha 后再动？

### 🔴 B. 7 处「③ 本该构造」怎么处置？

**我倾向一律先报不改**（派单要求）。但其中三类性质不同：

| 组 | 符号 | 我看到的性质 |
|---|---|---|
| **B1 测试夹具专用** | `WorldState` / `ActiveReservation` / `PlannedAction` | 生产消费 13 处、构造 0，**测试构造 3 处**。⇒ 这三者**不是死代码**，而是「**本该由调用方构造、但生产代码尚无调用方**」。**建议保留 + 加注释**，而非删除（删了 `constraint` 整个引擎就没了 API 面）。|
| **B2 设计-实现脱节** ⚠️ | `MutationKind::Combine` | **注释说要返回它，代码不返回** ⇒ 这是**真 bug**，建议修 `select_mutation` 加一个分支（但那是**行为变更**，需要你定阈值）|
| **B3 语义缺失** | `LtlFormula::And` / `Next` / `Inst::Num` | 求值器**完整支持**（match 分支齐全），但**无构造入口** ⇒ 用户写不出 `φ ∧ ψ`。**建议补构造辅助函数**（`and_()` / `next_()`），而非删 |

### 🟡 C. 是否需要我同时处理剩余的非批 3 warning？

当前 69 个里还剩 `implicit_impl_as_method` 5 / `unused_package` 4 / `result_error_return` 4 / `core_package_not_imported` 2 / `missing_priv` 1 / `deprecated_syntax` 1 = **17 个**（另 23 deprecated + 14 unused_value 待 R35 批 1/2 收尾）。

---

## 四、我**没有**动的（等确认）

- 一行代码都没改。
- 唯一写操作：`temp/audit/lane_dm_syms.py`（取清单用）、本清单。

**⚠️ 一处必须说清**：批 1（54 处机械替换）已在**上一轮完成并全量 1888/1888/0**，但**尚未提交**（等你这次确认后一并提交，或你要求我立即提交批 1）。
