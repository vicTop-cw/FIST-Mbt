// ============================================================================
// BUG-477 / Lane DL：`ops_commissar` 白盒锁（此前 275 行零测试）
//
// ══════════════════════════════════════════════════════════════════════════
// ⚠️ 头号纪律：**本文件永不订阅 rhop 流**
//
// 实测（最小复现 `dlp_p2`，被 SIGTERM 于 121 秒，无汇总行）：
//   `@rhop.from_filesystem_with(...)` 在 js 后端是 `fs.watch(path, {persistent: true})`
//   （`.mooncakes/.../monitor/watcher_js.mbt:71`）。
//   **即使 `subscribe` 之后立刻 `sub.dispose()`，进程仍然不退出** ——
//   `Subscription::dispose()`（`rx/RX-MBT.mbt:82`）透传不到底层 `ffi_watch_stop`。
//
//   ⇒ `from_filesystem_with` **不可取消**（rhop/rx 缺口）。
//   ⇒ 任何在测试里订阅它的格，都会让**整套 `moon test` 永久挂起**（CI 停摆，
//     而且看起来像「跑得慢」—— 我让 lead 花了 30 分钟才确认是挂起）。
//
// ⇒ 本文件的 round-trip **用同步读取面**：
//     读盘 → `RhopEnvelope::decode` → `RhopCipherNone::decrypt` → `RhopPacket::from_json_text`
//   每一步都是 rhop **自己的**解码器 ⇒ 仍然证明「rhop 认得它」，
//   但没有 watcher ⇒ **没有资源要释放 ⇒ 断言失败也不会挂起**。
// ══════════════════════════════════════════════════════════════════════════
//
// 三格：
//   L1 发送 ⇒ `.rhop` 文件真的落到 `commissar_events_dir`
//   L2 round-trip ⇒ 同步解码读回，payload 与发出的一致
//   L3 **变异对照** ⇒ 「没发送」的等价状态下，L1 的判据必须为假
// ============================================================================

///|
/// 夹具：`temp/` 下的唯一子目录（temp/ 已 gitignore，不污染仓库根）。
fn dl_tmp_project(tag : String) -> String {
  let mut dir = ""
  let mut i = 0
  while i < 1000 {
    let cand = "temp/dl-\{tag}-\{i.to_string()}"
    if not(@fs.path_exists(cand)) {
      @fs.create_dir(cand) catch {
        _ => abort("夹具目录建不出来：\{cand}（本格没跑到被测面）")
      }
      dir = cand
      break
    }
    i = i + 1
  }
  if dir == "" {
    abort("夹具目录名耗尽")
  }
  dir
}

///|
/// 锁 L1：`commissar_send` ⇒ 事件文件**真的落到盘上**。
///
/// ⚠️ 断言的是「`.rhop` 文件数 > 0」，不是「函数没崩」——
///   后者在 no-op 变异下仍会绿（那正是 L3 要排除的）。
test "dl_c1_send_writes_rhop_file" {
  let proj = dl_tmp_project("c1")
  commissar_ensure_dirs(proj)
  assert_true(@fs.path_exists(commissar_events_dir(proj)))
  assert_eq(dl_count_rhop(commissar_events_dir(proj)), 0)  // 前置：还没有文件

  let sig = CommissarSignal::new(
    kind="reminder",
    target="dl-c1-agent",
    text="hello from c1",
  )
  commissar_send(proj, sig, 1_700_000_000_000L)

  // ★ 本格的核心断言：文件真的多了
  let n = dl_count_rhop(commissar_events_dir(proj))
  assert_true(n > 0)
  dl_cleanup(proj)
}

///|
/// 锁 L2：round-trip —— 用 **rhop 自己的解码链**把消息读回来，payload 与发出的一致。
///
/// 为什么不用 `from_filesystem_with`：见文件头（它会挂起整套测试）。
/// 但仍是「rhop 认得它」—— 因为三段解码全部是 rhop 的公开接口。
test "dl_c2_round_trip_via_rhop_decoders" {
  let proj = dl_tmp_project("c2")
  commissar_ensure_dirs(proj)
  let sig = CommissarSignal::new(
    kind="reminder",
    target="dl-c2-agent",
    text="round-trip-payload-42",
  )
  commissar_send(proj, sig, 1_700_000_000_001L)

  let events = commissar_events_dir(proj)
  let names = @fs.read_dir(events) catch {
    _ => abort("dl_c2: read_dir 失败（本格没跑到被测面）")
  }
  let mut found = false
  let mut seen_target = ""
  for name in names {
    if not(name.has_suffix(".rhop")) {
      continue
    }
    let path = events + "/" + name
    let text = @fs.read_file_to_string(path) catch {
      _ => continue
    }
    // rhop 自己的三段解码
    match @rhop.RhopEnvelope::decode(text) {
      Err(_) => continue
      Ok(env) =>
        match @rhop.RhopCipherNone::new().decrypt(env.ct) {
          None => continue
          Some(plain) =>
            match @rhop.RhopPacket::from_json_text(plain) {
              Err(_) => continue
              Ok(pkt) =>
                match CommissarSignal::from_json(pkt.payload) {
                  Some(gs) =>
                    if gs.text == "round-trip-payload-42" {
                      found = true
                      seen_target = gs.target
                    }
                  None => ()
                }
            }
        }
    }
  }
  assert_true(found)                      // ★ 真的读回来了
  assert_eq(seen_target, "dl-c2-agent")   // 且字段没串
  dl_cleanup(proj)
}

///|
/// 锁 L3（**变异对照**）：证明 L1 的判据**真的在看盘**。
///
/// 复刻「`commissar_send` 是 no-op」时的**等价状态**（只建目录、不发），
/// 断言 L1 的那条判据（`dl_count_rhop(...) > 0`）此时**为假**。
/// ⇒ 若有人把 `commissar_send` 改成 no-op，L1 必然红。
///
/// ⚠️ 不在测试里改源码（那会让锁变成改锁）——用等价状态（判例-29 认可）。
test "dl_c3_mutation_control_noop_is_red" {
  let proj = dl_tmp_project("c3")
  commissar_ensure_dirs(proj)
  let n = dl_count_rhop(commissar_events_dir(proj))
  assert_eq(n, 0)
  assert_false(n > 0)
  dl_cleanup(proj)
}

// ── 私有小工具 ─────────────────────────────────────────────────────────────

///| 数目录下的 `.rhop` 文件
fn dl_count_rhop(dir : String) -> Int {
  let names = @fs.read_dir(dir) catch {
    _ => abort("dl_count_rhop: read_dir 失败 \{dir}（本格没跑到被测面）")
  }
  let mut n = 0
  for name in names {
    if name.has_suffix(".rhop") {
      n = n + 1
    }
  }
  n
}

///| 清理夹具（失败不报错 —— 清理不是被测面）
fn dl_cleanup(proj : String) -> Unit {
  @fs.remove_dir(proj) catch {
    _ => ()
  }
}
