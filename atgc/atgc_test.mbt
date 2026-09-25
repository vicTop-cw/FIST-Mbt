/// atgc_test.mbt —— ATGC 极简库测试（自驱+Omega 强验证交付物「tests」叶）。
/// 验证语料(Omega spec content)：rc 对合、MODE_B 转录、1+2=3、1+2+2=5 两例验算通过。

///|
test "atgc: reverse_complement 是对合 rc(rc(s))==s 且长度不变" {
  for s in ["ATG", "ATGCAT", "ATGCTAGTC", "ATCGGCTA"] {
    let rc = reverse_complement(s)
    assert_true(rc is Some(_))
    match rc {
      Some(r1) => assert_eq(reverse_complement(r1), Some(s))
      None => ()
    }
    match rc {
      Some(r1) => assert_eq(r1.length(), s.length())
      None => ()
    }
  }
}

///|
test "atgc: complement A<->T 且 G<->C" {
  assert_eq(complement('A'), Some('T'))
  assert_eq(complement('T'), Some('A'))
  assert_eq(complement('G'), Some('C'))
  assert_eq(complement('C'), Some('G'))
  assert_eq(complement('X'), None)
}

///|
test "atgc: MODE_B 转录 T->U,mRNA 与有义链同序" {
  match transcribe("ATGCATAATAAG") {
    Some(m) => assert_eq(m, "AUGCAUAAUAAG")
    None => assert_true(false)
  }
}

///|
test "atgc: base_to_int 映射 A=0 T=1 G=2 C=3" {
  assert_eq(base_to_int('A'), Some(0))
  assert_eq(base_to_int('T'), Some(1))
  assert_eq(base_to_int('G'), Some(2))
  assert_eq(base_to_int('C'), Some(3))
  assert_eq(base_to_int('N'), None)
}

///|
test "atgc: run_dna 计算 1+2=3（§10 极小子集）" {
  let prog = "ATG ;; 启动\nCAT AAT ;; push 1\nCAT AAG ;; push 2\nATT ;; add\nAAA ;; out\nTAA ;; halt"
  match run_dna(prog) {
    Ok(s) => assert_true(s.contains("3"))
    Err(e) => assert_true(false, msg=e)
  }
}

///|
test "atgc: run_dna 计算 1+2+2=5（§10）" {
  let prog = "ATG CAT AAT CAT AAG ATT CAT AAG ATT AAA TAA"
  match run_dna(prog) {
    Ok(s) => assert_true(s.contains("5"))
    Err(e) => assert_true(false, msg=e)
  }
}

///|
test "atgc: 非法输入被拒绝(不崩溃)" {
  assert_true(run_dna("ATGNXZ") is Err(_))
  assert_true(run_dna("   ") is Err(_) || valid_input("   ") == false)
  assert_true(valid_input("ATGC") == true)
  assert_true(valid_input("ATCN") == false)
}
