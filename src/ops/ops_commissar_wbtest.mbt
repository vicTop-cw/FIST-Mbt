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
    if !@fs.path_exists(cand) {
      @fs.create_dir(cand) catch {
        _ =>
          abort(
            "夹具目录建不出来：\{cand}（本格没跑到被测面）",
          )
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
  assert_eq(dl_count_rhop(commissar_events_dir(proj)), 0) // 前置：还没有文件

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
    if !name.has_suffix(".rhop") {
      continue
    }
    let path = events + "/" + name
    let text = @fs.read_file_to_string(path) catch { _ => continue }
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
  assert_true(found) // ★ 真的读回来了
  assert_eq(seen_target, "dl-c2-agent") // 且字段没串
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

///|
/// 数目录下的 `.rhop` 文件
fn dl_count_rhop(dir : String) -> Int32 {
  let names = @fs.read_dir(dir) catch {
    _ =>
      abort(
        "dl_count_rhop: read_dir 失败 \{dir}（本格没跑到被测面）",
      )
  }
  let mut n = 0
  for name in names {
    if name.has_suffix(".rhop") {
      n = n + 1
    }
  }
  n
}

///|
/// 清理夹具（失败不报错 —— 清理不是被测面）
fn dl_cleanup(proj : String) -> Unit {
  @fs.remove_dir(proj) catch {
    _ => ()
  }
}

// ============================================================================
// T0r3 · 接收侧「同步读取」白盒锁（`commissar_read`）
//
// 被测面：`commissar_read` 的解码链 + 过滤 + 坏文件计数 + 空目录语义。
// **全部断言返回值/结构体字段，不断言源码字符串**（判例-30）；
// 全程不订阅 rhop、不 sleep（判例-31）。
// ============================================================================

///|
/// 夹具：往 events/ 里直接落一个原始文件（**不是**通过 `commissar_send`）
/// —— 这样能造出 send 造不出来的坏文件。
fn dl_write_raw(proj : String, name : String, body : String) -> Unit {
  let path = commissar_events_dir(proj) + "/" + name
  @fs.write_string_to_file(path, body) catch {
    _ =>
      abort(
        "dl_write_raw: 写文件失败 \{path}（本格没跑到被测面）",
      )
  }
}

///|
/// 坏文件计数之和（tests 里要反复用，别每处重写一遍）
fn dl_bad_total(rep : CommissarReadReport) -> Int32 {
  rep.bad_read +
  rep.bad_envelope +
  rep.bad_decrypt +
  rep.bad_packet +
  rep.bad_payload
}

///|
/// 锁 R1：**round-trip** —— `commissar_send` 发一条，`commissar_read` 同步读出同一条。
/// 顺带锁住「四个子目录都被 `ensure_dirs` 建出来」（T0r3 的目录正式化）。
test "dl_c4_read_round_trip_single" {
  let proj = dl_tmp_project("c4")
  commissar_ensure_dirs(proj)
  // 目录约定：events / inbox / outbox / archive 四者都在
  assert_true(@fs.path_exists(commissar_events_dir(proj)))
  assert_true(@fs.path_exists(commissar_inbox_dir(proj)))
  assert_true(@fs.path_exists(commissar_outbox_dir(proj)))
  assert_true(@fs.path_exists(commissar_archive_dir(proj)))

  let sig = CommissarSignal::new(
    kind="reminder",
    target="dl-c4-agent",
    text="round-trip-42",
    ns="ns-c4",
  )
  commissar_send(proj, sig, 1_700_000_000_100L)

  let rep = commissar_read(proj)
  assert_eq(rep.error, "") // 目录级故障必须为空
  assert_true(rep.dir_exists)
  assert_eq(rep.scanned, 1)
  assert_eq(rep.returned, 1)
  assert_eq(dl_bad_total(rep), 0)
  assert_eq(rep.dropped_by_limit, 0)
  // ★ 读回来的就是发出去的那一条（不是"读到了点东西"）
  let e = rep.entries[0]
  assert_eq(e.text, "round-trip-42")
  assert_eq(e.kind, "reminder")
  assert_eq(e.target, "dl-c4-agent")
  assert_eq(e.ns, "ns-c4")
  assert_eq(e.at, 1_700_000_000_100L)
  assert_eq(e.source, "commissar-send")
  assert_true(e.id != "") // 信封 id 没丢
  dl_cleanup(proj)
}

///|
/// 锁 R2：过滤（kind / target）与 limit / since_seq 游标真的生效。
test "dl_c5_read_filters_limit_and_cursor" {
  let proj = dl_tmp_project("c5")
  commissar_ensure_dirs(proj)
  commissar_send(
    proj,
    CommissarSignal::new(kind="reminder", target="a", text="t1"),
    1_700_000_000_201L,
  )
  commissar_send(
    proj,
    CommissarSignal::new(kind="guidance", target="a", text="t2"),
    1_700_000_000_202L,
  )
  commissar_send(
    proj,
    CommissarSignal::new(kind="reminder", target="b", text="t3"),
    1_700_000_000_203L,
  )

  // kind 过滤：reminder 两条，guidance 一条被计为 filtered_kind
  let rk = commissar_read(proj, kind="reminder")
  assert_eq(rk.returned, 2)
  assert_eq(rk.filtered_kind, 1)
  assert_eq(rk.matched, 2)
  // target 过滤
  let rt = commissar_read(proj, target="a")
  assert_eq(rt.returned, 2)
  assert_eq(rt.filtered_target, 1)
  // 组合过滤
  let rb = commissar_read(proj, kind="reminder", target="b")
  assert_eq(rb.returned, 1)
  assert_eq(rb.entries[0].text, "t3")
  // limit：取**最新** limit 条，按时间升序返回
  let rl = commissar_read(proj, limit=2)
  assert_eq(rl.returned, 2)
  assert_eq(rl.dropped_by_limit, 1)
  assert_eq(rl.entries[0].text, "t2")
  assert_eq(rl.entries[1].text, "t3")
  // since_seq：闭区间下界（seq >= since_seq），只留最新那条
  let rs = commissar_read(proj, since_seq=1_700_000_000_203L)
  assert_eq(rs.returned, 1)
  assert_eq(rs.entries[0].text, "t3")
  assert_eq(rs.before_cursor, 2)
  dl_cleanup(proj)
}

///|
/// 锁 R3：坏文件**被计数并点名**，且**不中断**其余文件的读取。
///
/// 三种坏法各走一个解码阶段（信封 / 解密 / packet），外加一个 `.rhop.tmp` 残留
/// （它不是信号，不该被算成坏文件）。
test "dl_c6_read_bad_files_counted_not_fatal" {
  let proj = dl_tmp_project("c6")
  commissar_ensure_dirs(proj)
  commissar_send(
    proj,
    CommissarSignal::new(kind="reminder", target="ok", text="good"),
    1_700_000_000_301L,
  )
  dl_write_raw(proj, "bad1-envelope.rhop", "not-json-at-all")
  dl_write_raw(
    proj, "bad2-ciphertext.rhop", "{\"v\":1,\"alg\":\"none\",\"ct\":\"%%%not-base64%%%\"}",
  )
  // ct = base64("{}") ⇒ 信封与解密都过，packet 字段缺失
  dl_write_raw(
    proj, "bad3-packet.rhop", "{\"v\":1,\"alg\":\"none\",\"ct\":\"e30=\"}",
  )
  // 原子写的中间态残留：不是 .rhop、不算坏文件
  dl_write_raw(proj, "leftover.rhop.tmp", "x")

  let rep = commissar_read(proj)
  assert_eq(rep.error, "")
  assert_eq(rep.scanned, 4) // 4 个 .rhop（.rhop.tmp 不算）
  assert_eq(rep.ignored, 1)
  // ★ 一个坏文件不能带走好文件
  assert_eq(rep.returned, 1)
  assert_eq(rep.entries[0].text, "good")
  // ★ 坏文件逐个计数（不是"有东西被丢了"）
  assert_eq(dl_bad_total(rep), 3)
  assert_true(rep.bad_envelope >= 1) // bad1 必然停在信封层
  assert_eq(rep.bad_files.length(), 3) // 三个坏文件都有名有姓
  let names = rep.bad_files.join("|")
  assert_true(names.contains("bad1-envelope.rhop"))
  assert_true(names.contains("bad2-ciphertext.rhop"))
  assert_true(names.contains("bad3-packet.rhop"))
  dl_cleanup(proj)
}

///|
/// 锁 R4：空目录 / 根本不存在的目录 ⇒ **返回空，不报错**；
/// 且读取是**纯读**（不顺手建目录 —— 读操作有副作用的话，`dir_exists` 就永远为真了）。
test "dl_c7_read_empty_or_missing_dir_is_empty_not_error" {
  let proj = dl_tmp_project("c7")
  // ① 连 .commissar 都没有
  let rep = commissar_read(proj)
  assert_false(rep.dir_exists)
  assert_eq(rep.error, "")
  assert_eq(rep.returned, 0)
  assert_eq(rep.scanned, 0)
  assert_eq(rep.bad_files.length(), 0)
  // ★ 纯读：读一遍不该把 .commissar 建出来
  assert_false(@fs.path_exists(commissar_root(proj)))
  // ② 目录建好了但没有任何信号
  commissar_ensure_dirs(proj)
  let rep2 = commissar_read(proj)
  assert_true(rep2.dir_exists)
  assert_eq(rep2.error, "")
  assert_eq(rep2.scanned, 0)
  assert_eq(rep2.returned, 0)
  assert_eq(dl_bad_total(rep2), 0)
  dl_cleanup(proj)
}

///|
/// 锁 R5（**变异对照的等价态**）：目录里**只有**坏文件。
///
/// 复刻两种变异下的等价状态，让"改坏了必然红"能在这里被独立看见：
///   · 把坏文件**静默跳过**（不计数）⇒ `dl_bad_total == 1` 变 0、`bad_files` 变空 ⇒ 红；
///   · 把 ct **当明文直读**（跳过 decrypt）⇒ 明文是信封 JSON、不是 packet JSON
///     ⇒ 计数落到别的桶（bad_packet），而 `bad_decrypt==1` 的读数为 0 ⇒ 红。
/// ⇒ 本格与 `dl_c4`（正常路径）构成一对：正常路径绿、坏路径红。
test "dl_c8_read_mutation_control_bad_only_dir" {
  let proj = dl_tmp_project("c8")
  commissar_ensure_dirs(proj)
  dl_write_raw(
    proj, "only-bad.rhop", "{\"v\":1,\"alg\":\"none\",\"ct\":\"%%%broken%%%\"}",
  )
  let rep = commissar_read(proj)
  assert_eq(rep.scanned, 1)
  assert_eq(rep.returned, 0) // 坏文件不能被当成信号返回
  // ★ 核心：坏文件必须"被看见"（计数 + 点名），而不是静默变成"目录是空的"
  assert_eq(dl_bad_total(rep), 1)
  assert_eq(rep.bad_files.length(), 1)
  assert_true(rep.bad_files[0].contains("only-bad.rhop"))
  dl_cleanup(proj)
}

///|
/// `commissar_gc`：**保留最近 N 条**（不是按 mtime 删 —— `@fs` 拿不到 mtime）。
///
/// 三格合一，每格断言一个**不同**的不变量：
///  ① `dry_run` 只报不删（`deleted` 空、文件仍在）
///  ② 真删只删早的（保留末尾最新 N 条）
///  ③ `keep >= total` 时零删除（边界：不该多删）
///
/// 排序依据是**文件名**（`sig-<at_ms>-<counter>.rhop`，`at_ms` 13 位 ⇒ 字典序 == 时间序）。
/// 禁 `sleep`（判例-31）：`at_ms` 由 `commissar_send` 的参数给，不靠时序。
test "dl_c9_gc_keep_recent_dry_run_then_delete" {
  let proj = dl_tmp_project("c9")
  commissar_ensure_dirs(proj)
  let events = commissar_events_dir(proj)
  // 造 5 条，at_ms 递增 ⇒ 文件名升序 = 12345..9
  let mut i = 0
  while i < 5 {
    let at = 1_700_000_000_000L + i.to_int64() * 1000L
    commissar_send(
      proj,
      { kind: "R1", target: "t9", ns: "default", text: "m\{i}", },
      at,
    )
    i = i + 1
  }
  let before = commissar_list_names(events, @ref.Ref(""))
  let rhop_before : Array[String] = []
  for nm in before {
    if nm.has_suffix(".rhop") {
      rhop_before.push(nm)
    }
  }
  assert_eq(rhop_before.length(), 5)

  // ① dry_run：只报不删
  let dry = commissar_gc(proj, keep=2, dry_run=true)
  assert_eq(dry.total, 5)
  assert_eq(dry.kept, 2) // R230：笔误修正——keep=2 ⇒ kept=2、doomed=3（2+3=total=5；原断言 3+3>5 自相矛盾，且与本格后半 real.deleted==3 / rhop_after==2 冲突）
  assert_eq(dry.doomed.length(), 3)
  assert_eq(dry.deleted.length(), 0) // ★ 关键：dry_run 不许真删
  for nm in before {
    if nm.has_suffix(".rhop") {
      assert_true(@fs.path_exists(events + "/" + nm))
    }
  }

  // ② 真删：只删早的 3 条，末尾 2 条仍在
  let real = commissar_gc(proj, keep=2, dry_run=false)
  assert_eq(real.deleted.length(), 3)
  assert_eq(real.failed.length(), 0)
  let after = commissar_list_names(events, @ref.Ref(""))
  let rhop_after : Array[String] = []
  for nm in after {
    if nm.has_suffix(".rhop") {
      rhop_after.push(nm)
    }
  }
  assert_eq(rhop_after.length(), 2)
  // ★ 删掉的那 3 个必须不在，留下的 2 个必须在
  for nm in real.deleted {
    assert_false(@fs.path_exists(events + "/" + nm))
  }

  // ③ keep >= total ⇒ 零删除（边界：不许把「保留」读成「至少删一条」）
  let noop = commissar_gc(proj, keep=99, dry_run=false)
  assert_eq(noop.total, 2)
  assert_eq(noop.kept, 2)
  assert_eq(noop.doomed.length(), 0)
  assert_eq(noop.deleted.length(), 0)

  // ④ 目录不存在 ⇒ 不是错误（还没发过消息的仓）
  let empty = commissar_gc(dl_tmp_project("c9b"), keep=10)
  assert_eq(empty.total, 0)
  assert_eq(empty.kept, 0)
  assert_eq(empty.err, "")
}

///|
/// `commissar_gc` 变异对照：**把「保留末尾」改成「保留开头」⇒ 本格必须变红**。
///
/// 为什么单独立一格：`dl_c9` 只证明「删了 3 条留了 2 条」——
/// **如果实现删的是最新的 3 条，它也满足「删3留2」**。
/// ⇒ 必须断言**留下的是最新的**，不是「数量对就行」（判例-30：数量对 ≠ 对象对）。
test "dl_c10_gc_keeps_newest_not_oldest" {
  let proj = dl_tmp_project("c10")
  commissar_ensure_dirs(proj)
  let events = commissar_events_dir(proj)
  let mut i = 0
  while i < 4 {
    let at = 1_700_000_000_000L + i.to_int64() * 1000L
    commissar_send(
      proj,
      { kind: "R1", target: "t10", ns: "default", text: "m\{i}", },
      at,
    )
    i = i + 1
  }
  let rep = commissar_gc(proj, keep=1, dry_run=false)
  assert_eq(rep.deleted.length(), 3)
  let after = commissar_list_names(events, @ref.Ref(""))
  let rhop_after : Array[String] = []
  for nm in after {
    if nm.has_suffix(".rhop") {
      rhop_after.push(nm)
    }
  }
  assert_eq(rhop_after.length(), 1)
  // ★ 留下的必须是最晚那条（at_ms 最大）——只断言长度会让「保留最旧」也过
  let kept_name = rhop_after[0]
  assert_true(kept_name.contains("1700000003000"))
}
