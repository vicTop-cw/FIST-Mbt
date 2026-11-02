///|
/// BUG-538 白盒锁 · IO 薄壳行为格（**js target 限定**，见 moon.pkg targets 配置）：
///   I1 正常写行：追加落盘可读回（时间戳前缀 + 事件 + 内容，多次写追加不覆盖）；
///   I2 off 开关：path="" ⇒ 零 IO no-op（不把 "" 当路径去撞 IO）；
///   I3 IO 失败静默：父目录位置被一个**文件**占位 ⇒ append 必失败但**不抛不崩**。
///
/// I3 为什么用「父目录被文件占住」：mkdirSync 对既有同名文件是确定性错误
/// （ENOTDIR/EEXIST，Windows / POSIX 同形），跨平台可复现 ——
/// 不用 sleep 抢时序（判例-31：不可复现的锁 = 不可信）。

///|
const BUG538_IO_TEST_DIR : String = "target/_bug538_log_wbtest"

///|
async test "bug538_i1_正常写行_追加落盘可读回" {
  let path = BUG538_IO_TEST_DIR + "/server.log"
  // 清场：上一轮残留会让追加语义断言失真
  @fs.remove_file(path) catch {
    _ => ()
  }
  assert_true(server_log_write_to(path, "server.start", "version=test"))
  assert_true(server_log_write_to(path, "spawn.end", "ok=true code=0"))
  let raw = @fs.read_file_to_string(path) catch {
    _ => abort("bug538_i1: 写入成功但读回失败")
  }
  // 两次写入都落了盘（追加，不互相覆盖）
  assert_true(raw.contains("[fist-mbt] server.start version=test"))
  assert_true(raw.contains("[fist-mbt] spawn.end ok=true code=0"))
  // 行形状：ISO 时间戳打头、换行结尾（一行一事件，可 grep）
  assert_true(raw.contains("T") && raw.contains("Z [fist-mbt] server.start"))
  assert_eq(raw[raw.length() - 1:raw.length()].to_owned(), "\n")
}

///|
async test "bug538_i2_off开关_path空串_零IO" {
  // off 的语义在**路径解析层**归零为 ""；write_to 对空串必须 no-op 返 false。
  // 绝不能把 "" 当路径去 IO、靠 appendFileSync 抛异常的 catch 兜住 —— 那是
  // 在错误的层兜底（"" 路径的 mkdir/append 是无意义调用）。
  assert_false(server_log_write_to("", "server.start", "should-not-persist"))
}

///|
async test "bug538_i3_io失败静默_父目录被文件占位_不抛不崩" {
  // 前置：先把目录建出来（@fs.write_string_to_file 不补建父目录；测试间无顺序保证，
  // 不能依赖 i1 的 mkdir）—— 用日志薄壳自己的 mkdir 语义落一颗种子文件。
  assert_true(
    server_log_write_to(BUG538_IO_TEST_DIR + "/seed.log", "seed", "dir"),
  )
  let blocker = BUG538_IO_TEST_DIR + "/notadir"
  @fs.write_string_to_file(blocker, "placeholder-not-a-dir") catch {
    _ => abort("bug538_i3: 前置夹具写入失败")
  }
  // blocker 是**文件** ⇒ 在它下面建目录/写文件是确定性 IO 错误
  let r = server_log_write_to(
    blocker + "/x.log",
    "spawn.start",
    "should-fail-silently",
  )
  assert_false(r)
  // 占位文件本身不被破坏（失败路径无副作用）
  let raw = @fs.read_file_to_string(blocker) catch {
    _ => abort("bug538_i3: 占位文件被失败路径破坏")
  }
  assert_true(raw.contains("placeholder"))
}

///|
async test "bug538_i4_心跳_短间隔真写_到点自停_off零io" {
  // 心跳短间隔真写：30ms 间隔 —— 「间隔到了会写」是被测语义。
  // 固定窗口版两红实证：BUG-543（400ms 窗口只到 2 tick）放宽到 1200ms 后，
  // 本轮 run 41433285731 windows 臂又红（2 != 4）——30ms 名义间隔下事件循环饥饿
  // 把有效 tick 周期拖到 ~600ms，「窗口 = 间隔 × 拍数 × N 倍裕量」的线性假设
  // 在慢 runner 上不可救（裕量倍数只是把红点往后挪）。
  // ⇒ 改「轮询到数 + 截止」：每 100ms 读一次日志数行，凑齐即 break；30s 截止内
  // 没凑齐才 fail（此时才是真缺陷：漏拍）。时序无关的理由：max_ticks 的上限停
  // 语义保证拍数到 3 后**不再增** ——「等满截止才凑齐」与「秒凑齐」在最终计数与
  // 内容上完全等价，判断成立与否只看最终计数与内容，不依赖任何窗口假设（判例-31）。
  // max_ticks=3 ⇒ 落盘行数**恰好 3**（少 = 没在写，多 = 到点没自停）—— 两向变异对照都在这一格。
  let path = BUG538_IO_TEST_DIR + "/heartbeat.log"
  @fs.remove_file(path) catch {
    _ => ()
  }
  server_log_heartbeat_start_with(path, 30, 3)
  // 恰好 3 行（每行以 \n 结尾 ⇒ split 尾部多一个空段）⇒ split 计数凑到 4 即到数
  let expected_splits = 4
  let deadline_ms = 30000
  let mut waited_ms = 0
  let mut raw = ""
  let mut reached = false
  while waited_ms < deadline_ms {
    @async.sleep(100)
    waited_ms = waited_ms + 100
    let chunk = @fs.read_file_to_string(path) catch {
      _ => "" // 文件尚未落盘，继续等
    }
    if chunk.split("\n").count() >= expected_splits {
      raw = chunk
      reached = true
      break
    }
  }
  if !reached {
    abort(
      "bug538_i4: 30s 截止内心跳未凑齐 3 行（漏拍 = 真缺陷，不是调度噪声）",
    )
  }
  // 行形状与其它事件同一收口：ISO 时间戳 + [fist-mbt] heartbeat alive pid=
  assert_true(raw.contains("Z [fist-mbt] heartbeat alive pid="))
  // 恰好 3 行：轮询在凑齐瞬间 break，若到点没自停（行数 >3）在这里被两向锁抓住
  assert_eq(raw.split("\n").count(), 4)
  // off 门：空路径不装定时器（零 IO）—— 30ms 间隔走的是注入参数，
  // off 门拦的是 path==""，两个开关维度都过一遍
  server_log_heartbeat_start_with("", 30, 3)
  @async.sleep(150)
  let off_path = BUG538_IO_TEST_DIR + "/heartbeat-off.log"
  assert_false(@fs.path_exists(off_path))
  // interval<=0 / max_ticks<=0 同样不装（零开销门的另外两半）
  server_log_heartbeat_start_with(path, 0, 3)
  server_log_heartbeat_start_with(path, 30, 0)
  @async.sleep(150)
  // 两发都不装 ⇒ 文件行数不变（仍停在上面的 3 行）
  let raw2 = @fs.read_file_to_string(path) catch {
    _ => abort("bug538_i4: 日志文件消失")
  }
  assert_eq(raw2, raw)
}
