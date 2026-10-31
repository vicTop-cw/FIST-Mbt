///|
/// omega_acc_fix_test.mbt — 评委拒收项「自动修复三轮 · 错误指纹修复返回零修复」的正身锁。
///
/// 钉三件事，缺一条都算没修：
///   ① 坏指纹走完整链路后 `fixes_applied` **非空**（旧实现恒为空数组，就是评委读到的读数）；
///   ② 修复后的 spec 全文被回传（`fixed_specs`），且拿它再跑一次 batch_verify 真的通过
///      —— 「修好了」必须可复用，不能只是一条动作日志；
///   ③ 未知根因**不许**重算指纹盖章（旧 default 分支会把「不知道哪儿坏了」变成
///      「校验项自动变绿」，那是把验收门改成橡皮图章）。

///|
/// 一份本身合法、只差指纹的语料（指纹取 good 版后手工改坏 ⇒ 命中 fp_mismatch 一类）
const GOOD_FP_SPEC : String = "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:dd1bc62c4d988913\"}"

///|
const BAD_FP_SPEC : String = "{\"op\":\"report\",\"version\":\"1.0\",\"definition\":{\"sig\":\"a\"},\"preconditions\":[\"x\"],\"laws\":[\"L\"],\"tests\":[{\"input\":{\"a\":\"1\"},\"expected\":\"ok\"}],\"fingerprint\":\"fnv1a64:0000000000000000\"}"

///|
fn acc_str(j : Json, key : String) -> String {
  match jget(j, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn acc_len(j : Json, key : String) -> Int32 {
  match jget(j, key) {
    Some(Array(a)) => a.length()
    _ => -1
  }
}

///|
fn acc_num(j : Json, key : String) -> Double {
  match jget(j, key) {
    Some(Number(n, ..)) => n
    _ => -1.0
  }
}

///|
fn acc_bool(j : Json, key : String) -> Bool {
  match jget(j, key) {
    Some(True) => true
    _ => false
  }
}

///|
test "I2/坏指纹被真修掉：fixes_applied 非空、veto 解除、回执带修好的全文" {
  let r = @omega.verify_fix_with_evidence(
    [("a.json", BAD_FP_SPEC)],
    max_rounds=3,
  )
  // ① 非零修复
  assert_true(acc_len(r, "fixes_applied") >= 1, msg=r.stringify())
  assert_eq(acc_num(r, "final_accuracy"), 100.0)
  assert_true(!acc_bool(r, "veto"))
  assert_true(acc_bool(r, "repair_ok"))
  assert_true(acc_num(r, "total_rounds") >= 1.0)
  // ② 修好的东西可复用：拿 fixed_specs 的 content 再验一次，必须真的通过
  assert_eq(acc_len(r, "fixed_specs"), 1)
  let fixed_content = match jget(r, "fixed_specs") {
    Some(Array(a)) => acc_str(a[0], "content")
    _ => ""
  }
  assert_true(fixed_content != "", msg="<fixed_specs.content 是空>")
  let again = @omega.batch_verify([("a.json", fixed_content)])
  assert_eq(acc_num(again, "passed"), 1.0)
  assert_true(!acc_bool(again, "veto"))
  // 人工兜底必须清空 —— 能修的不该再挂在人工名单上
  assert_eq(acc_len(r, "needs_human_review"), 0)
}

///|
test "I2/一份好语料不误伤：无失败就不产生修复动作，也不报错" {
  let r = @omega.verify_fix_with_evidence(
    [("ok.json", GOOD_FP_SPEC)],
    max_rounds=3,
  )
  assert_eq(acc_len(r, "fixes_applied"), 0)
  assert_eq(acc_num(r, "final_accuracy"), 100.0)
  assert_true(!acc_bool(r, "veto"))
  assert_eq(acc_len(r, "needs_human_review"), 0)
}

///|
test "I2/未知根因不重盖章洗指纹（default 分支已摘）" {
  let spec = match @omega.parse_spec(BAD_FP_SPEC) {
    Ok(j) => j
    Err(e) => abort("夹具本身解析失败：" + e)
  }
  let fp_before = acc_str(spec, "fingerprint")
  for rc in ["unknown", "", "totally_new_root_cause"] {
    let after = @omega.apply_fix(spec, rc)
    // 指纹一个字都没动 ⇒ 没有「不知道坏哪儿就把校验项刷绿」这条路
    assert_eq(acc_str(after, "fingerprint"), fp_before)
    // 且整份内容逐字原样返回
    assert_eq(after.stringify(), spec.stringify())
  }
  // 对照：真按 fp_mismatch 修时指纹**必须**变（否则上一段的"没变"就没信息量）
  let fixed = @omega.apply_fix(spec, @omega.ROOT_CAUSE_FP_MISMATCH)
  assert_true(acc_str(fixed, "fingerprint") != fp_before)
}

///|
test "I2/max_rounds 传到引擎并被夹紧" {
  let r0 = @omega.verify_fix_with_evidence(
    [("a.json", BAD_FP_SPEC)],
    max_rounds=0,
  )
  assert_eq(acc_num(r0, "max_rounds"), 1.0)
  let r9 = @omega.verify_fix_with_evidence(
    [("a.json", BAD_FP_SPEC)],
    max_rounds=999,
  )
  assert_eq(acc_num(r9, "max_rounds"), 10.0)
  let rd = @omega.verify_fix_with_evidence([("a.json", BAD_FP_SPEC)])
  assert_eq(acc_num(rd, "max_rounds"), 3.0)
}
