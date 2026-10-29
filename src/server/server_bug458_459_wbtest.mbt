/// server_bug458_459_wbtest.mbt —— BUG-458 / BUG-459 的白盒回归锁（lane-e-server，T0r5）。
///
/// ## BUG-458：`sd_kind_path` 的 panic 面（src/ops/ops_selfdrive.mbt:33）
///
/// 病灶：kind 为空 / 含 `/` / 含 `\` / 含 `..` 时直接 `abort()`。这四条 kind 都能从 MCP 侧
/// 原样送进来（`selfdrive_get` / `selfdrive_append` / `selfdrive_export_tasks` /
/// `selfdrive_review_tick`），而 server.mbt 的 handler 把 `Err` 映成 `ToolError`、
/// 只拦不住 `abort()` ⇒ 非法 kind 是**进程级崩溃**而不是结构化错误回执（同族 BUG-374/433）。
///
/// 修法：`sd_kind_path` 返回 `Result[String, String]`，调用方透传 `Err`。
/// 本文件的三格锁（空 / `".."` / `"a/b"`）各自断言「返回 Err 而不是崩溃」——
/// 崩溃面在这里是真证据：`abort()` 会直接掀掉整个测试进程，「能走到断言」本身就是不崩的读数。
///
/// ## BUG-459：ns 写门覆盖面对表
///
/// `src/server/write_gate.mbt:158` 的文档声称 ns 写门覆盖 `publish` / `publish_parallel` /
/// `dag_publish` 三支，实际只有 `publish` 真调用（`ns_write_gate` 全仓仅一处调用点）。
/// handler 是 `run_server()` 里的匿名闭包（结构上不可注入，见 tool_cov_lane_c_test.mbt 头注），
/// 故「三个工具各自真调了门」这一格由 `scripts/check_ns_write_gate_coverage.py` 做**静态对表**锁；
/// 本文件锁的是**门本身的语义**（default/空/非法必拒、合法不误伤）与
/// **为什么门必须在 handler 层**（engine 的 `publish_with_deps` 对 default ns 照收 ⇒ 少了 handler 门就等于没有门）。

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

///|
/// 建（必要时清）一个本用例专属目录，避免上次运行残留污染。
fn b458_dir(name : String) -> String {
  let d = "temp/" + name
  @fs.create_dir("temp") catch {
    _ => ()
  }
  @fs.remove_dir(d) catch {
    _ => ()
  }
  @fs.create_dir(d) catch {
    _ => ()
  }
  @fs.create_dir(d + "/memory") catch {
    _ => ()
  }
  d
}

///|
/// 断言「是 Err 且文案点名 cause」；是 Ok 就判失败（BUG-458 三格锁共用的判据面）。
fn b458_expect_err(
  r : Result[Json, String],
  cause : String,
  what : String,
) -> Unit {
  match r {
    Err(e) => {
      if !(e.contains("kind")) {
        abort(what + "：错误文案必须点名 kind，实际：" + e)
      }
      if !(e.contains(cause)) {
        abort(
          what +
          "：错误文案必须点名原因「" +
          cause +
          "」，实际：" +
          e,
        )
      }
    }
    Ok(_) =>
      abort(
        what +
        "：必须返回 Err，实际返回 Ok（BUG-458 回归：非法 kind 又被放行了）",
      )
  }
}

///|
/// 断言「是 Err」且文案含片段（ns 写门用，文案无需点名 kind）。
fn b459_expect_err(
  r : Result[Unit, String],
  must : String,
  what : String,
) -> Unit {
  match r {
    Err(e) =>
      if !(e.contains(must)) {
        abort(
          what + "：错误文案必须含「" + must + "」，实际：" + e,
        )
      }
    Ok(_) =>
      abort(
        what + "：必须被 ns 写门拒绝，实际放行（BUG-459 回归）",
      )
  }
}

// ---------------------------------------------------------------------------
// BUG-458：三格锁（空 / ".." / "a/b"）+ 反向边界（反斜杠）+ get 面 + 正向对照
// ---------------------------------------------------------------------------

///|
test "BUG-458 锁 1/3：空 kind ⇒ 结构化 Err，不崩进程" {
  let d = b458_dir("b458_empty")
  let r = @ops.selfdrive_memory_append(
    d,
    ns="r1goal",
    kind="",
    content="x",
    now="t",
  )
  b458_expect_err(r, "空字符串", "空 kind")
  // 拒绝必须无副作用：memory/.md 不得被建出来
  if @fs.path_exists(d + "/memory/.md") {
    abort(
      "空 kind 被拒后不得落 memory/.md（拒绝必须无副作用）",
    )
  }
}

///|
test "BUG-458 锁 2/3：kind=\"..\" ⇒ Err（拒绝路径穿越），不崩进程" {
  let d = b458_dir("b458_dotdot")
  let r = @ops.selfdrive_memory_append(
    d,
    ns="r1goal",
    kind="..",
    content="x",
    now="t",
  )
  b458_expect_err(r, "\"..\"", "kind=\"..\"")
  if @fs.path_exists(d + "/memory/...md") {
    abort("kind=\"..\" 被拒后不得落 memory/...md")
  }
}

///|
test "BUG-458 锁 3/3：kind=\"a/b\" ⇒ Err（拒绝路径分隔符），不崩进程" {
  let d = b458_dir("b458_slash")
  let r = @ops.selfdrive_memory_append(
    d,
    ns="r1goal",
    kind="a/b",
    content="x",
    now="t",
  )
  b458_expect_err(r, "路径分隔符", "kind=\"a/b\"")
  // 关键：不得在 memory/ 之外写出 a/b.md
  if @fs.path_exists(d + "/a/b.md") {
    abort(
      "kind=\"a/b\" 被拒后不得写出 memory/ 之外的 a/b.md（路径穿越）",
    )
  }
}

///|
test "BUG-458 反向边界：Windows 反斜杠 kind=\"a\\\\b\" 同样 Err" {
  let d = b458_dir("b458_backslash")
  let r = @ops.selfdrive_memory_append(
    d,
    ns="r1goal",
    kind="a\\b",
    content="x",
    now="t",
  )
  b458_expect_err(r, "路径分隔符", "kind=\"a\\\\b\"")
}

///|
test "BUG-458 get 面：非法 kind 在读取路径上同样 Err（不是只修了 append）" {
  let d = b458_dir("b458_get")
  let empty = @ops.selfdrive_memory_get(d, ns="r1goal", kind="")
  b458_expect_err(empty, "空字符串", "get 空 kind")
  let slash = @ops.selfdrive_memory_get(d, ns="r1goal", kind="a/b")
  b458_expect_err(slash, "路径分隔符", "get kind=\"a/b\"")
}

///|
test "BUG-458 正向对照：合法 kind 仍然照常工作（修 Err 不等于把功能锁死）" {
  let d = b458_dir("b458_ok")
  match
    @ops.selfdrive_memory_append(
      d,
      ns="r1goal",
      kind="thinking",
      content="流水",
      now="t0",
    ) {
    Ok(_) => ()
    Err(e) => abort("合法 kind=thinking 必须成功，实际 Err：" + e)
  }
  if !(@fs.path_exists(d + "/memory/thinking.md")) {
    abort(
      "合法 kind=thinking 必须落 memory/thinking.md（Err 化不得吞掉正常写入）",
    )
  }
  match @ops.selfdrive_memory_get(d, ns="r1goal", kind="thinking") {
    Ok(j) =>
      // exists=true + content 含刚写入的流水；用 JSON 字符串形态做可比读数
      if !(j.stringify().contains("流水")) {
        abort(
          "get 回读必须拿到刚写入的内容，实际：" + j.stringify(),
        )
      }
    Err(e) =>
      abort("合法 kind=thinking 的 get 必须成功，实际 Err：" + e)
  }
}

// ---------------------------------------------------------------------------
// BUG-459：ns 写门语义（三支共用同一道门）+ 「门必须在 handler 层」的机理解释锁
// ---------------------------------------------------------------------------

///|
test "BUG-459 门语义：default / 空 ns 必拒（dag_publish 与 publish 同口径）" {
  b459_expect_err(ns_write_gate("default"), "ns_gate", "ns=default")
  b459_expect_err(ns_write_gate(""), "ns_gate", "ns=空串")
}

///|
test "BUG-459 门语义：非法 ns（含 / 、含 ..）必拒" {
  b459_expect_err(ns_write_gate("a/b"), "ns_gate", "ns=a/b")
  b459_expect_err(ns_write_gate("../escape"), "ns_gate", "ns=../escape")
}

///|
test "BUG-459 门语义：合法 ns 不误伤（不把门做成全拒）" {
  match ns_write_gate("lane-e-server") {
    Ok(_) => ()
    Err(e) => abort("合法 ns=lane-e-server 必须放行，实际 Err：" + e)
  }
  // 仓里既有的定时/自驱 ns 形状也必须继续放行（零回归）
  for ns in ["cron-auto", "tnr_polish"] {
    match ns_write_gate(ns) {
      Ok(_) => ()
      Err(e) =>
        abort("合法 ns=\"" + ns + "\" 必须放行，实际 Err：" + e)
    }
  }
}

///|
test "BUG-459 机理：engine 侧不拦 default ns ⇒ 门只能在 handler 层，漏一支即等于无门" {
  // 这一格不是装饰：它排掉「把门下沉到 engine」这条看似更省事的修法——
  // engine 直接收下 default ns，说明 handler 少调一次 ns_write_gate 就是一条真通路。
  let e = @engine.FistEngine::new()
  match
    e.publish_with_deps(
      project_dir="/proj/b459",
      description="default ns 直投（BUG-459 的缺口形态）",
      depends_on=[],
      created_by="human_steward",
      now="2026-10-28T10:00:00Z",
      ns="default",
    ) {
    Ok(id) =>
      if id == "" {
        abort("engine 直投 default ns 应拿到任务 id")
      }
    Err(m) =>
      abort(
        "engine.publish_with_deps 本不校验 ns（预期 Ok），实际 Err：" +
        m,
      )
  }
}
