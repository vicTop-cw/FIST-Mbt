/// cli_argv_test.mbt —— 外部执行器 argv 的回归锁（黑盒：只经公开接口）
///
/// 钉三件事：① argv 形状与 FIST Python 版一致（迁移不得改语义）；② 非法输入必须 Err
/// 且不产出"看起来能跑"的参数；③ 未知执行器不猜测、不降级。

///|
fn ca_unwrap(r : Result[Array[String], String]) -> Array[String] {
  match r {
    Ok(a) => a
    Err(e) => abort("应成功，实际 Err: " + e)
  }
}

///|
test "ca_1_aider argv 与 Python 版逐参数一致" {
  let a = ca_unwrap(
    @executor.aider_argv(prompt="改 README", model="AtomGit-qwen3.8-27b"),
  )
  assert_eq(a[0], "--message")
  assert_eq(a[1], "改 README")
  assert_eq(a[2], "--model")
  assert_eq(a[3], "AtomGit-qwen3.8-27b")
  assert_eq(a[4], "--edit-format")
  assert_eq(a[5], "whole")
  assert_eq(a[6], "--map-tokens")
  assert_eq(a[7], "0")
  assert_eq(a[8], "--encoding")
  assert_eq(a[9], "gbk")
  assert_true(a.contains("--yes-always"))
  assert_true(a.contains("--no-auto-commits"))
}

///|
test "ca_2_空提示词与空模型必须 Err（不得静默走默认档）" {
  assert_true(@executor.aider_argv(prompt="", model="m") is Err(_))
  assert_true(@executor.aider_argv(prompt="x", model="") is Err(_))
  assert_true(@executor.aider_argv(prompt="x", model="   ") is Err(_))
  assert_true(@executor.atomcode_argv(prompt="x", model="") is Err(_))
  assert_true(
    @executor.aider_argv(prompt="含 NUL \u0000 的输入", model="m") is Err(_),
  )
}

///|
test "ca_3_非法 edit_format 被拒" {
  assert_true(
    @executor.aider_argv(prompt="x", model="m", edit_format="magic") is Err(_),
  )
  for ok in ["whole", "diff", "udiff"] {
    assert_true(
      @executor.aider_argv(prompt="x", model="m", edit_format=ok) is Ok(_),
    )
  }
}

///|
test "ca_4_atomcode argv：空 workdir 不下发 -C，auto_yes 可关" {
  let a = ca_unwrap(
    @executor.atomcode_argv(prompt="做 X", model="LongCat-2.0"),
  )
  assert_eq(a[0], "-p")
  assert_eq(a[1], "做 X")
  assert_true(!a.contains("-C"))
  assert_true(a.contains("-y"))
  assert_eq(a[a.length() - 1], "LongCat-2.0")
  let b = ca_unwrap(
    @executor.atomcode_argv(
      prompt="做 X",
      model="M",
      workdir=".",
      auto_yes=false,
    ),
  )
  assert_true(b.contains("-C"))
  assert_true(!b.contains("-y"))
  assert_eq(b[2], "-C")
  assert_eq(b[3], ".")
}

///|
test "ca_5_提示词里的 shell 元字符只是字面量（不经 shell）" {
  let evil = "rm -rf / ; echo $(pwned) `id` | tee"
  let a = ca_unwrap(@executor.aider_argv(prompt=evil, model="m"))
  // 关键：整串是**一个**元素，没有被拆成多个 argv，也没有 -c/--command 之类包装
  assert_eq(a[1], evil)
  assert_eq(a.length(), 12)
  assert_true(!a.contains("-c"))
  assert_true(!a.contains("--shell"))
  // 负数 map_tokens 归零而不是产出 "--map-tokens -5"
  let c = ca_unwrap(@executor.aider_argv(prompt="x", model="m", map_tokens=-5))
  assert_eq(c[7], "0")
}

///|
test "ca_6_未知执行器显式 Err 且列出可用集" {
  assert_true(@executor.is_external_executor("aider"))
  assert_true(@executor.is_external_executor("atomcode"))
  assert_true(!@executor.is_external_executor("mavis"))
  assert_true(!@executor.is_external_executor(""))
  match @executor.build_command(executor="hermes", prompt="x", model="m") {
    Err(msg) => {
      assert_true(msg.contains("aider"))
      assert_true(msg.contains("atomcode"))
    }
    Ok(_) => abort("未知执行器不该被接受")
  }
  let (bin, args) = match
    @executor.build_command(
      executor="atomcode",
      prompt="x",
      model="M",
      workdir=".",
    ) {
    Ok(v) => v
    Err(e) => abort(e)
  }
  assert_eq(bin, "atomcode")
  assert_eq(@executor.executor_binary("aider"), "aider")
  assert_true(args.length() >= 4)
}

///|
test "ca_7_缺可执行文件时的提示可诊断且不含成功暗示" {
  let h = @executor.executor_missing_hint("aider")
  assert_true(h.contains("aider"))
  assert_true(h.contains("不会静默返回成功"))
}
