/// run_check_js_ffi_wbtest.mbt —— FFI FixedArray[String] 边界运行时验证（已知问题收口）。
///
/// 已知问题：js_run_command 的 args 由 Array[String] 改为 FixedArray[String]
///（新工具链 [0020] 废弃 Array 跨 JS FFI）。若 FixedArray 在 JS 运行时不被 spawn
/// 当作真正的数组消费，spawn 会抛 TypeError，被 JS 兜底成 ok:false。
/// 本测试以 node 真实子进程证明边界可用——ok 必须为 true 才算过。

///|
/// 关键断言：args: FixedArray[String] 跨 JS 边界后，node 子进程的 -e 脚本正常执行
/// 且 stdout 命中 FFI_OK；这同时验证了 Array→FixedArray 转换与 spawn 数组消费两条链路。
async test "FFI: FixedArray[String] 跨 JS 边界可被 spawn 当数组消费" {
  let res = run_check_external(
    "node",
    ["-e", "process.stdout.write('FFI_OK')"],
    ".",
    8000,
  )
  match res {
    Err(e) => fail("run_check_external 调度失败: " + e)
    Ok(payload) => {
      let ok = match payload {
        Object(m) =>
          match m.get("ok") {
            Some(True) => true
            _ => false
          }
        _ => false
      }
      assert_true(ok)
      let stdout = match payload {
        Object(m) =>
          match m.get("stdout") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      assert_true(stdout.contains("FFI_OK"))
    }
  }
}

///|
/// 多参数（>1 个元素）同样按数组顺序传给 spawn：node 收到 argv[1..] 拼接后 stdout 命中。
/// 专门锁 FixedArray 不止单元素、且元素顺序保持不变。
async test "FFI: FixedArray[String] 多参数顺序跨边界保持" {
  let res = run_check_external(
    "node",
    [
      "-e", "process.stdout.write(process.argv.slice(1).join(','))", "alpha", "beta",
    ],
    ".",
    8000,
  )
  match res {
    Err(e) => fail("run_check_external 调度失败: " + e)
    Ok(payload) => {
      let ok = match payload {
        Object(m) =>
          match m.get("ok") {
            Some(True) => true
            _ => false
          }
        _ => false
      }
      assert_true(ok)
      let stdout = match payload {
        Object(m) =>
          match m.get("stdout") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
      assert_true(stdout.contains("alpha,beta"))
    }
  }
}
