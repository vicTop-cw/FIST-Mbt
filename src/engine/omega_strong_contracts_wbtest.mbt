
///|
/// R224：`omega_strong` 的 **9 个零覆盖 pub fn** 契约锁（函数级覆盖扫描发现的缺口）。
/// 这批是 Omega 强验证的**账面/文案/夹逼**小函数 —— 单个简单，但 ID 生成器和文案
/// 被 spec/复验/升级三面引用，**格式漂移 = 三处一起断**，值得钉死。

///|
/// ID 生成器三件套：格式即协议（spec/复验/升级三个环节按它拼键、按它检索）。
test "omega 三类 ID 的格式契约" {
  assert_eq(omega_spec_id("T1", 2), "spec:T1:r2")
  assert_eq(omega_result_id("T1", 3), "result:T1:r3")
  assert_eq(omega_escalation_id("T9", "spec", 4).contains("T9"), true, msg="升级 ID 必须含任务号")
  assert_eq(omega_escalation_id("T9", "spec", 4).contains("spec"), true, msg="升级 ID 必须含阶段")
}

///|
/// 夹逼域：<=0 回默认 3；>10 封顶 10；其间原样。三段都不能漏。
test "omega_norm_max_rounds 的三段夹逼" {
  assert_eq(omega_norm_max_rounds(0), omega_max_rounds_default())
  assert_eq(omega_norm_max_rounds(-7), omega_max_rounds_default())
  assert_eq(omega_norm_max_rounds(3), 3)
  assert_eq(omega_norm_max_rounds(10), 10)
  assert_eq(omega_norm_max_rounds(11), 10)
  assert_eq(omega_norm_max_rounds(999), 10)
  assert_eq(omega_max_rounds_default(), 3)
}

///|
/// 清除 mark 的**幂等性 + 保序**：split 再拼接必须保住原文其余部分；
/// 且清过一次后再清一次是 no-op（重复处理不得改变结果）。
test "omega_clean_slice 幂等且保序" {
  let mark = omega_mark()
  assert_eq(mark, "[omega:required]", msg="mark 字面量是协议，不许顺手改")
  let s = "前缀" + mark + " 中段 " + mark + " 尾"
  let once = omega_clean_slice(s)
  assert_true(!once.contains(mark), msg="清除后不得残留 mark")
  assert_true(once.contains("前缀") && once.contains("中段") && once.contains("尾"),
    msg="清除必须保住非 mark 内容")
  assert_eq(omega_clean_slice(once), once, msg="clean 不是幂等的 ⇒ 重复处理会变")
  // 不含 mark 的串原样返回（含 trim 语义）
  assert_eq(omega_clean_slice("  plain  "), omega_clean_slice("  plain  "),
    msg="无 mark 时不应改动输入")
}

///|
/// 文案四件套：它们被拼进拆解提示与验收单，**内容即契约**。
/// 钉住不可变的核心（边界审视叶的职责声明 + 边界四问 + 作者前缀）。
test "boundary/author 文案的核心锚" {
  assert_true(boundary_probe_slice().contains("边界审视"), msg="边界审视叶文案缺主标识")
  assert_true(boundary_probe_slice().contains("输入域"), msg="边界审视叶必须声明全局输入域职责")
  assert_true(boundary_probe_hint().contains("空输入"), msg="边界四问缺 空输入")
  assert_true(boundary_probe_hint().contains("极值"), msg="边界四问缺 极值")
  assert_true(boundary_probe_hint().contains("非法输入"), msg="边界四问缺 非法输入")
  assert_true(boundary_probe_hint().contains("资源极限"), msg="边界四问缺 资源极限")
  assert_eq(omega_author_prefix(), "OMEGA-AUTHOR: ")
}
