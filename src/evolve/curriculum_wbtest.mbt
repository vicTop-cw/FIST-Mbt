// curriculum 自进化课程模块白盒测试（L41 核心组件）

///|
test "next_level 低分=L1" {
  assert_eq(next_level(0.3), L1)
}

///|
test "next_level 中分=L2" {
  assert_eq(next_level(0.6), L2)
}

///|
test "next_level 较高=L3" {
  assert_eq(next_level(0.75), L3)
}

///|
test "next_level 高分=L4" {
  assert_eq(next_level(0.9), L4)
}

///|
test "standard_curriculum 四阶段" {
  let c = standard_curriculum()
  assert_eq(c.length(), 4)
  assert_eq(c[0].min_score, 0.55)
  assert_eq(c[3].min_score, 0.95)
}

///|
test "can_graduate 各阶段" {
  assert_true(can_graduate(0.55, L1))
  assert_false(can_graduate(0.54, L1))
  assert_true(can_graduate(0.70, L2))
  assert_true(can_graduate(0.85, L3))
  assert_true(can_graduate(0.95, L4))
}

///|
test "curriculum_progress 映射" {
  assert_eq(curriculum_progress(0.3), 0.0)
  assert_eq(curriculum_progress(0.6), 0.33)
  assert_eq(curriculum_progress(0.75), 0.66)
  assert_eq(curriculum_progress(0.95), 1.0)
}

///|
test "select_mutation 低分=Simplify" {
  assert_eq(select_mutation(0.3), Simplify)
}

///|
test "select_mutation 中分=Rewrite" {
  assert_eq(select_mutation(0.6), Rewrite)
}

///|
test "select_mutation 较高=Generalize" {
  assert_eq(select_mutation(0.75), Generalize)
}

///|
test "select_mutation 高分=Specialize" {
  assert_eq(select_mutation(0.9), Specialize)
}

///|
test "mutation_prompt 包含目标" {
  let p = mutation_prompt(Rewrite, "实现排序", "用快排")
  assert_true(p.contains("实现排序"))
  assert_true(p.contains("重写"))
}

///|
test "is_distillable 高分非空=true" {
  assert_true(is_distillable(0.9, "有用的设计笔记"))
}

///|
test "is_distillable 低分=false" {
  assert_false(is_distillable(0.5, "有用的设计笔记"))
}

///|
test "is_distillable 空笔记=false" {
  assert_false(is_distillable(0.9, "   "))
}

///|
test "distill_skill 可蒸馏返回 Some" {
  let s = distill_skill("a1", "实现缓存", "LRU 策略", 0.9)
  assert_true(s is Some(_))
}

///|
test "distill_skill 不可蒸馏返回 None" {
  let s = distill_skill("a1", "实现缓存", "", 0.5)
  assert_true(s is None)
}

///|

///|
/// R150：**多个空格必须全替** —— 原实现用 `replace` 只替首个 ⇒ skill 名里残留空格
/// （skill 名是要给下游当标识符用的，含空格就废了）。
test "derive_skill_name 多空格全替" {
  let name = derive_skill_name("g", "a b c d e")
  assert_true(!name.contains(" "))
  assert_true(name.has_prefix("skill_"))
}

///|
test "derive_skill_name 前缀截取" {
  let name = derive_skill_name("goal", "一二三四五六七八九十")
  assert_true(name.contains("skill_"))
}

///|
test "evolve_decision 高分可蒸馏" {
  let (level, _mutation, distillable) = evolve_decision(0.9)
  assert_eq(level, L4)
  assert_true(distillable)
}

///|
test "evolve_decision 低分不可蒸馏" {
  let (_, _, distillable) = evolve_decision(0.3)
  assert_false(distillable)
}

///|
test "decision_to_string 非空" {
  let s = decision_to_string(L3, Generalize, false)
  assert_true(s.contains("L3"))
  assert_true(s.contains("泛化"))
}

// ══════════════════════════════════════════════════════════════════════════
// BUG-479（Lane DM）：`MutationKind::Combine` 从「文档承诺但永不产出」
// 变成「有前置条件、可达、且能说清为什么」。
//
// 病灶：`mutation_prompt`（:158）与字符串化（:279）**都为 Combine 写了分支**
// （消费面建好了），但 `select_mutation` 的 4 个分支**只返回其它四个**
// （生产面没接）⇒ 判例-29 的又一实例。
//
// 修法按**语义**不按**阈值**：`Combine` = 「融合两个父代」⇒ 前置是「≥2 个父代」，
// 而旧签名只有 `score`、**结构上就拿不到父代数** ⇒ 加 `parents~` 参数（缺省 1 = 零回归）。
// ══════════════════════════════════════════════════════════════════════════

///|
/// 【BUG-479·锁 1】★ **新能力可达**：高分 + 多父代 ⇒ `Combine`。
///
/// 这是「修复真的生效」的正面锁：若有人把 `Combine` 分支删掉，本格必红。
test "dm_01_combine_reachable_with_multiple_parents" {
  assert_eq(select_mutation(0.9, parents=2), Combine)
  assert_eq(select_mutation(1.0, parents=5), Combine)
  // 边界：0.85 恰好在「高分」起点
  assert_eq(select_mutation(0.85, parents=2), Combine)
}

///|
/// 【BUG-479·锁 2】★★ **零回归**：不传 `parents` ⇒ 行为与修前**逐字相同**。
///
/// 这条是本单最重要的锁 —— 派单明确要求「现有调用方（只传 score）行为不变」。
/// 逐档验证：三个旧档位的返回值必须与修前的 if-else 链**完全一致**，
/// 尤其是 `>= 0.85` 仍返回 `Specialize`（**不是** `Combine`）。
test "dm_02_zero_regression_without_parents" {
  // 低分档
  assert_eq(select_mutation(0.0), Simplify)
  assert_eq(select_mutation(0.54), Simplify)
  // 中分档
  assert_eq(select_mutation(0.55), Rewrite)
  assert_eq(select_mutation(0.69), Rewrite)
  // 较高分档
  assert_eq(select_mutation(0.70), Generalize)
  assert_eq(select_mutation(0.84), Generalize)
  // ★ 高分档：不传 parents ⇒ 仍是 Specialize（**零回归的关键一格**）
  assert_eq(select_mutation(0.85), Specialize)
  assert_eq(select_mutation(0.9), Specialize)
  assert_eq(select_mutation(1.0), Specialize)
  // 显式传 1 也必须等同缺省
  assert_eq(select_mutation(0.9, parents=1), Specialize)
}

///|
/// 【BUG-479·锁 3】**语义前置**：`parents >= 2` 但**分数不高**时不产出 `Combine`。
///
/// 防「只要多父代就 Combine」的过度修正 —— `Combine` 仍是「追求极致」档的算子。
test "dm_03_combine_requires_high_score_too" {
  assert_eq(select_mutation(0.3, parents=5), Simplify)
  assert_eq(select_mutation(0.6, parents=5), Rewrite)
  assert_eq(select_mutation(0.75, parents=5), Generalize)
  assert_eq(select_mutation(0.84, parents=5), Generalize)
}
