/// ATGC 双链虚拟机 · 验收测试（atgc/atgc_test.mbt）。
/// 覆盖 5 个硬性验收点：
///   1) rc 对合（§4.4：32 对、rc(rc(c))==c、无自反）；
///   2) §10.6 计算 (1+2)*3 = 9；
///   3) §10.1 计算 1+2+2 = 5 且开启 ROLLBACK、无回滚触发；
///   4) MODE_B 编译/运行产出正确 mRNA 与输出；
///   5) 除零返回错误不崩溃；HALT_ERR/错误在 ROLLBACK 下触发 rolled_back 并恢复最后 checkpoint。

///|
fn rc(s : String) -> String {
  match reverse_complement(s) {
    Some(x) => x
    None => abort("rc: 非法序列 \{s}")
  }
}

///|
/// 验收 1：rc 对合 —— 64 密码子划分成 32 个 rc 互补对，rc(rc(c))==c，无自反。
test "rc 对合 §4.4：32 对 / 对合 / 无自反" {
  let pairs = rc_pairs()
  assert_eq(pairs.length(), 32)
  for (lo, hi) in pairs {
    if lo == hi {
      abort("rc 自反异常: \{lo}")
    }
    assert_eq(rc(lo), hi)
    assert_eq(rc(hi), lo)
    assert_eq(rc(rc(lo)), lo)
    assert_eq(rc(rc(hi)), hi)
  }
  // 对配对正确性的一个抽查：ATG ↔ CAT、TAA ↔ TTA、GCA ↔ TGC（idea.md §4.4）
  assert_eq(rc("ATG"), "CAT")
  assert_eq(rc("TAA"), "TTA")
  assert_eq(rc("GCA"), "TGC")
}

///|
/// 验收 2：§10.6 示例 —— 计算 (1+2)*3，输出 9。
/// 注：idea.md line562 汇总串漏写规则后多一碱基，此处采用 §10.6 程序清单
/// （ATG CAT AAT CAT AAG ATT CAT AAC TTT AAA TAA）连写的正链本体，自洽计算 9。
test "§10.6：(1+2)*3 = 9（输出 9，无回滚）" {
  let prog = "ATGCATAATCATAAGATTCATAACTTTAAATAA"
  let cld = compile_dna(prog)
  let r = run(cld.program, cld.rollback)
  assert_eq(r.output, "9")
  assert_eq(r.result, "ok")
  assert_eq(r.rolled_back, false)
  // 装配后共 8 条指令（START/2×PUSH/ADD/PUSH/MUL/OUT/HALT），每条记录一次栈轨迹
  assert_eq(r.stack_history.length(), 8)
  assert_eq(r.stack_history[1], "[1]")
  assert_eq(r.stack_history[3], "[3]")
  assert_eq(r.stack_history[5], "[9]")
}

///|
/// 验收 3a：§10.1 计算 1+2+2 = 5，默认模式 B 下输出 5、无回滚。
/// 为自洽得到 5，正链本体采用两处 ADD（1、2、2 三次入栈 + ADD + ADD + OUT）。
test "§10.1：1+2+2 = 5（默认模式，输出 5）" {
  let prog = "ATGCATAATCATAAGCATAAGATTATTAAATAA"
  let r = run_dna(prog)
  assert_eq(r.output, "5")
  assert_eq(r.result, "ok")
  assert_eq(r.rolled_back, false)
}

///|
/// 验收 3b：§10.1 全序列（含 MODE_B + MODE_A + ROLLBACK 指令区）输出 5、开启回滚且无回滚触发。
test "§10.1：ROLLBACK 开启、输出 5、rolled_back=false" {
  let header = "ATGTAATAGATGCAATAATAATAA" // 指令区：MODE_B+TAG + MODE_A+ATG + ROLLBACK+CAA
  let body = "ATGCATAATCATAAGCATAAGATTATTAAATAA"
  let cld = compile_dna(header + body)
  assert_eq(cld.rollback, true)
  assert_eq(cld.mode.contains("A"), true)
  assert_eq(cld.mode.contains("B"), true)
  let r = run(cld.program, cld.rollback)
  assert_eq(r.output, "5")
  assert_eq(r.rolled_back, false)
}

///|
/// 验收 4：MODE_B 编译/运行 —— 转录出规则 mRNA、操作列表正确、输出正确。
test "MODE_B：编译产出 mRNA 与正确输出" {
  let header = "ATGTAATAGTAATAATAA" // MODE_B + 指令区结束
  let prog = "ATGCATAATCATAAGATTCATAACTTTAAATAA"
  let cld = compile_dna(header + prog)
  assert_eq(cld.mode, "B")
  assert_eq(cld.rollback, false)
  // mRNA = 正链 T→U
  assert_eq(cld.mrna, "AUGCAUAAUCAUAAGAUUCAUAACUUUAAAUAA")
  // 操作列表（上下文 1/2 数据、ADD、3 数据、MUL、OUT、HALT）
  assert_eq(
    cld.ops,
    "START PUSH_IMM 1 PUSH_IMM 2 ADD PUSH_IMM 3 MUL OUT_NUM HALT",
  )
  let r = run(cld.program, cld.rollback)
  assert_eq(r.output, "9")
}

///|
/// 验收 4b：atgc_compile / atgc_run 的 JSON 字符串接口形态。
test "MCP JSON：atgc_compile / atgc_run" {
  let prog = "ATGCATAATCATAAGATTCATAACTTTAAATAA"
  let cd = atgc_compile(prog)
  match cd {
    Err(m) => abort("compile 应成功: \{m}")
    Ok(s) => {
      assert_eq(s.contains("\"mode\":\"B\""), true)
      assert_eq(s.contains("\"transcription\":\"AUG"), true)
      assert_eq(s.contains("\"rollback\":false"), true)
    }
  }
  let rd = atgc_run(prog)
  match rd {
    Err(m) => abort("run 应成功: \{m}")
    Ok(s) => {
      assert_eq(s.contains("\"output\":\"9\""), true)
      assert_eq(s.contains("\"result\":\"ok\""), true)
      assert_eq(s.contains("\"rolled_back\":false"), true)
    }
  }
  // 非法输入被拒绝（不崩溃）
  match atgc_run("ATGCX") {
    Err(m) => assert_eq(m.contains("无效输入"), true)
    Ok(_) => abort("非法输入应当被拒绝")
  }
}

///|
/// 验收 5a：除零返回错误而非崩溃（无回滚时 result=err:*）。
test "除零：返回错误不崩溃（DIV by zero）" {
  let r = run_dna("CATAATCATAAATGG") // push1, push0, div
  assert_eq(r.output, "")
  assert_eq(r.result.contains("除以零"), true)
  assert_eq(r.rolled_back, false)
}

///|
/// 验收 5b：HALT_ERR 在 ROLLBACK 下触发 rolled_back 并恢复最后 checkpoint。
test "ROLLBACK：HALT_ERR 回滚恢复最后 checkpoint" {
  let header = "ATGTAACAATAATAATAA" // 指令区：ROLLBACK(CAA)
  let body = "CATAATTAG" // push1, HALT_ERR
  let cld = compile_dna(header + body)
  assert_eq(cld.rollback, true)
  let r = run(cld.program, cld.rollback)
  assert_eq(r.rolled_back, true)
  assert_eq(r.result.contains("HALT_ERR"), true)
  assert_eq(r.output, "")
  // 恢复到最后 checkpoint：HALT_ERR 之前栈仍为 [1]
  assert_eq(r.final_stack.length(), 1)
  assert_eq(r.final_stack[0], 1)
}

///|
/// 验收 5c：除零错误在 ROLLBACK 下同样触发回滚并恢复 checkpoint。
test "ROLLBACK：除零回滚" {
  let header = "ATGTAACAATAATAATAA" // ROLLBACK
  let body = "CATAATCATAAATGG" // push1, push0, div
  let cld = compile_dna(header + body)
  assert_eq(cld.rollback, true)
  let r = run(cld.program, cld.rollback)
  assert_eq(r.rolled_back, true)
  assert_eq(r.result.contains("除以零"), true)
  assert_eq(r.final_stack.length(), 2) // 恢复到 [1,0]
}

///|
/// 附加：atgc_talk 叙事对话（无序列→简介；有序列→生物故事+问答）。
test "atgc_talk 叙事对话" {
  let intro = atgc_talk("", "")
  assert_eq(intro.contains("ATGC 双链虚拟机"), true)
  let n = atgc_talk("ATGCATAATCATAAGATTCATAACTTTAAATAA", "它算了什么？")
  assert_eq(n.contains("mRNA"), true)
  assert_eq(n.contains("输出：9"), true)
  assert_eq(n.contains("问题「它算了什么？"), true)
}
