/// cli_argv_wbtest.mbt —— R152 白盒锁：CLI 通道失败归因（`classify_cli_failure` / `cli_failure_hint`）
///
/// 为什么是白盒而不是黑盒：`CliFailure` 的**构造子**在跨包面上拿不到——本包的
/// `.mbti` 只把枚举本身导出，黑盒测试里写 `@executor.CliFailure::Timeout` 会被
/// 判成 `Cannot create values of the read-only type`（2026-10-23 实测）。
/// 兄弟件 `src/router/ofm_failure_wbtest.mbt` 走的正是同一条路：归因档的值本身要在包内测。

///|
test "cf_1_跑满超时归 TIMEOUT，不许再说成可执行文件不可用" {
  // 这一格是本单的全部理由：原语对超时以 ok=false + `timeout after …` 落地，
  // 而旧调用面对**所有**非 0 一律回「可执行文件不可用」。
  let k = classify_cli_failure("timeout after 900000ms")
  assert_eq(k, CliFailure::Timeout)
  assert_eq(k.label(), "TIMEOUT")
  let h = cli_failure_hint("atomcode", k)
  assert_true(h.contains("时长预算"))
  assert_true(!h.contains("不可用"))
  assert_true(h.contains("文件系统"))
}

///|
test "cf_2_ENOENT 归 NOT_EXECUTABLE，提示沿用原缺可执行文件常" {
  let k = classify_cli_failure("spawn atomcode ENOENT")
  assert_eq(k, CliFailure::NotExecutable)
  assert_eq(k.label(), "NOT_EXECUTABLE")
  // 只有这一档配说「不可用」，且原语缺失常一字不改（既有依赖方读的就是这句）
  assert_eq(cli_failure_hint("atomcode", k), executor_missing_hint("atomcode"))
  assert_true(cli_failure_hint("atomcode", k).contains("atomcode"))
}

///|
test "cf_3_退出码非 0 归 NONZERO_EXIT，处方是读 stderr 不是装环境" {
  let k = classify_cli_failure("exit code 1")
  assert_eq(k, CliFailure::NonZeroExit)
  let h = cli_failure_hint("aider", k)
  assert_true(h.contains("退出码非 0"))
  assert_true(!h.contains("不可用"))
}

///|
test "cf_4_code 折成 -1 归 SIGNAL_KILLED，且 -11 不被前缀误吞" {
  // 判据用精确相等而不是 contains：`exit code -11` 里含 `exit code -1` 这个前缀，
  // 用 contains 会把「被信号杀」与「真退出码 -11（Linux 上常见于 SIGSEGV 的 shell 转发）」混成一档。
  assert_eq(classify_cli_failure("exit code -1"), CliFailure::SignalKilled)
  assert_eq(classify_cli_failure("exit code -11"), CliFailure::NonZeroExit)
  assert_true(
    cli_failure_hint("aider", CliFailure::SignalKilled).contains(
      "不是执行器缺失",
    ),
  )
}

///|
test "cf_5_本侧调度或解析失败归 DISPATCH_FAILED：坏的是尺不是执行器" {
  assert_eq(
    classify_cli_failure(
      "run_check: 子进程调度失败（js 运行时异常）",
    ),
    CliFailure::DispatchFailed,
  )
  let k = classify_cli_failure("run_check: 子进程结果 JSON 解析失败")
  assert_eq(k, CliFailure::DispatchFailed)
  let h = cli_failure_hint("aider", k)
  assert_true(h.contains("坏的是这一侧"))
  assert_true(!h.contains("可执行文件不可用"))
}

///|
test "cf_6_无线索留 UNKNOWN，不猜归因（空串同样不猜）" {
  assert_eq(classify_cli_failure("boom"), CliFailure::Unknown)
  assert_eq(classify_cli_failure(""), CliFailure::Unknown)
  assert_true(
    cli_failure_hint("aider", CliFailure::Unknown).contains("宁可留 Unknown"),
  )
}

///|
test "cf_7_超时优先于 spawn 线索：两类文本同串时取可处置那一档" {
  // 被看门狗杀的进程才是 TIMEOUT；ENOENT 不该混进来，但原语若把两者都带出来，
  // 结论必须是「时长预算」（处置是验产物），而不是「没装执行器」（处置是重装）。
  assert_eq(
    classify_cli_failure("timeout after 180000ms (spawn)"),
    CliFailure::Timeout,
  )
}

///|
test "cf_8_标签面逐字钉住：调用方按 failure_kind 字符串分支，改字即破坏契约" {
  assert_eq(
    [
      CliFailure::NotExecutable.label(),
      CliFailure::Timeout.label(),
      CliFailure::NonZeroExit.label(),
      CliFailure::SignalKilled.label(),
      CliFailure::DispatchFailed.label(),
      CliFailure::Unknown.label(),
    ],
    [
      "NOT_EXECUTABLE", "TIMEOUT", "NONZERO_EXIT", "SIGNAL_KILLED", "DISPATCH_FAILED",
      "UNKNOWN",
    ],
  )
}

///|
test "cf_9_与模型无关的三档不换候选：重试只会把同一条失败重跑" {
  // 这一格钉的是 R156 的立项理由：旧重试环只看「没成功且还有候选」，
  // 于是 PATH 问题/超时问题被拿去换模型重试 N 遍，还白记 N 次模型冷却账。
  let (ne_retry, ne_why) = cli_retry_policy(CliFailure::NotExecutable)
  let (to_retry, to_why) = cli_retry_policy(CliFailure::Timeout)
  let (df_retry, df_why) = cli_retry_policy(CliFailure::DispatchFailed)
  assert_false(ne_retry)
  assert_false(to_retry)
  assert_false(df_retry)
  // 理由必须点名档位本身——回执里的 `retry_skipped` 要能让调用方对上是哪一档拦的
  assert_true(ne_why.contains("NOT_EXECUTABLE"))
  assert_true(to_why.contains("TIMEOUT"))
  assert_true(df_why.contains("DISPATCH_FAILED"))
}

///|
test "cf_10_模型侧三档照旧换候选：P1.1 的既有语义零回归" {
  let (a, _) = cli_retry_policy(CliFailure::NonZeroExit)
  let (b, _) = cli_retry_policy(CliFailure::SignalKilled)
  let (c, _) = cli_retry_policy(CliFailure::Unknown)
  assert_true(a)
  assert_true(b)
  assert_true(c)
}

///|
test "cf_11_TIMEOUT 的处方是验产物+提预算，不是重装执行器" {
  let (_, why) = cli_retry_policy(CliFailure::Timeout)
  assert_true(why.contains("时长预算"))
  assert_true(why.contains("文件系统"))
  assert_true(why.contains("timeout_ms"))
  assert_true(!why.contains("不可用"))
}

///|
test "cf_12_DISPATCH_FAILED 明确不给模型记账：坏的是本侧" {
  let (_, why) = cli_retry_policy(CliFailure::DispatchFailed)
  assert_true(why.contains("不记账") || why.contains("不给模型记"))
  assert_true(why.contains("本侧"))
  // 反向对照：NOT_EXECUTABLE 的处方指向安装，而不是「立案到 src/server」
  let (_, w2) = cli_retry_policy(CliFailure::NotExecutable)
  assert_true(w2.contains("PATH"))
}
