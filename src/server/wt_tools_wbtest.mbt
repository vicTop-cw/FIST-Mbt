///|
/// wt_tools_wbtest.mbt —— worktree 沙箱生命周期的白盒锁（七档状态机 / 账 / porcelain 解析）。
///
/// 锁的都是**纯判定面**（零 IO）：状态机是本功能的承重件——判错一个档的后果是「把没落盘的活
/// 当垃圾收了」或「把可回收的沙箱永远留着」。所以这里逐档、逐条陷阱来：
///   W1 `wt_task_ok` / `wt_path_ok`：账文件名与路径的安全白名单；
///   W2 七档全覆盖（abandoned / unknown×2 / blocked×2 / merged / idle / stale / fresh）；
///   W3 **顺序陷阱**：merged+dirty 必须 `blocked`（不是 merged）；
///   W4 **idle 只认锚点**：超龄且 head==created_sha ⇒ `idle`，不是 `stale`；
///   W5 可回收集合：blocked 与 unknown **不在**集合里；
///   W6 账 JSON 往返（字段名与 Python 面一致，类型不丢）；
///   W7 tally 计数；
///   W8 porcelain 解析（两块 + detached + 尾块无空行 + `refs/heads/` 剥离）。
///
/// 变异对照（判例-29/30）：把 `wt_state_of` 里的「脏先看」那格删掉（先判 merged 再判 dirty），
/// W3 必红；把 idle 判定改成按年龄，W4 必红；把 unknown 从「读不到」改成 fresh，W2 的 unknown 两格必红。

///|
test "W1a task 白名单：字母/数字/_/- 通过，分隔符与超长拒绝" {
  assert_true(wt_task_ok("r181-preflight"))
  assert_true(wt_task_ok("A_b-9"))
  assert_false(wt_task_ok(""))
  assert_false(wt_task_ok("a/b"))
  assert_false(wt_task_ok("../x"))
  assert_false(wt_task_ok("a b"))
  assert_false(wt_task_ok("a.b"))
  let long = "x".repeat(65)
  assert_false(wt_task_ok(long))
}

///|
test "W1b 路径形状：拒空/含 ../以分隔符结尾，留正常相对与绝对" {
  assert_true(wt_path_ok("temp/wt-a"))
  assert_true(wt_path_ok("F:/AI/wt-a"))
  assert_false(wt_path_ok(""))
  assert_false(wt_path_ok("temp/../escape"))
  assert_false(wt_path_ok("temp/wt-a/"))
}

///|
test "W2 七档全覆盖：abandoned / unknown×2 / blocked×2 / merged / idle / stale / fresh" {
  // abandoned：目录不在（账还在）
  let (s, _) = wt_state_of(false, None, 0, 0, 120, "", "abc")
  assert_eq(s, "abandoned")
  // unknown：脏度读不到
  let (s, _) = wt_state_of(true, Some(false), -1, 10, 120, "h", "c")
  assert_eq(s, "unknown")
  // unknown：merged 给不出结论
  let (s, _) = wt_state_of(true, None, 0, 10, 120, "h", "c")
  assert_eq(s, "unknown")
  // blocked：已并入但有未落盘改动（顺序陷阱）
  let (s, _) = wt_state_of(true, Some(true), 3, 10, 120, "h", "c")
  assert_eq(s, "blocked")
  // blocked：未并入但有未落盘改动
  let (s, _) = wt_state_of(true, Some(false), 1, 10, 120, "h", "c")
  assert_eq(s, "blocked")
  // merged：已并入且干净
  let (s, _) = wt_state_of(true, Some(true), 0, 10, 120, "h", "c")
  assert_eq(s, "merged")
  // idle：干净、未并入、head == created_sha（即使超龄）
  let (s, _) = wt_state_of(true, Some(false), 0, 999, 120, "same", "same")
  assert_eq(s, "idle")
  // stale：干净、未并入、动过、超龄
  let (s, _) = wt_state_of(true, Some(false), 0, 999, 120, "h2", "h1")
  assert_eq(s, "stale")
  // fresh：干净、未并入、动过、未超龄
  let (s, _) = wt_state_of(true, Some(false), 0, 5, 120, "h2", "h1")
  assert_eq(s, "fresh")
}

///|
test "W3 顺序陷阱：merged + dirty 必须 blocked（先判 merged 会把没落盘的活一起销毁）" {
  let (s, why) = wt_state_of(true, Some(true), 2, 1, 120, "h", "c")
  assert_eq(s, "blocked")
  assert_true(why.contains("先落盘"))
  // 反向：同一输入只把 dirty 归零 ⇒ merged（证明差异确实来自 dirty 那一格，而不是别处）
  let (s2, _) = wt_state_of(true, Some(true), 0, 1, 120, "h", "c")
  assert_eq(s2, "merged")
}

///|
test "W4 idle 只认创建锚点：超龄但 head==created_sha 仍是 idle，不是 stale" {
  let (s, _) = wt_state_of(true, Some(false), 0, 100000, 1, "sha-1", "sha-1")
  assert_eq(s, "idle")
  // 锚点为空（老账/读不到）时不允许误判 idle
  let (s, _) = wt_state_of(true, Some(false), 0, 0, 120, "sha-1", "")
  assert_eq(s, "fresh")
}

///|
test "W5 可回收集合：merged/stale/abandoned/idle 在内，blocked/unknown/fresh 不在" {
  assert_true(wt_reclaimable("merged"))
  assert_true(wt_reclaimable("stale"))
  assert_true(wt_reclaimable("abandoned"))
  assert_true(wt_reclaimable("idle"))
  assert_false(wt_reclaimable("blocked"))
  assert_false(wt_reclaimable("unknown"))
  assert_false(wt_reclaimable("fresh"))
}

///|
test "W6 账 JSON 往返：字段与类型都不丢（与 Python 面同名字段）" {
  let j = wt_entry_json("t1", "temp/wt-t1", "wt/t1", "HEAD", "sha0", "sha1", 1234567, 90)
  assert_eq(wt_s(j, "id"), "t1")
  assert_eq(wt_s(j, "path"), "temp/wt-t1")
  assert_eq(wt_s(j, "branch"), "wt/t1")
  assert_eq(wt_s(j, "base"), "HEAD")
  assert_eq(wt_s(j, "base_sha"), "sha0")
  assert_eq(wt_s(j, "created_sha"), "sha1")
  assert_eq(wt_i(j, "created_at", 0), 1234567)
  assert_eq(wt_i(j, "ttl_min", 0), 90)
  // 缺字段给默认值，不崩
  assert_eq(wt_i(j, "nope", 7), 7)
  assert_eq(wt_s(j, "nope"), "")
  // stringify 后仍可解析回同样的值（落盘面与内存面同一形状）
  let back = @json.parse(j.stringify()) catch { _ => Json::null() }
  assert_eq(wt_s(back, "id"), "t1")
  assert_eq(wt_i(back, "ttl_min", 0), 90)
}

///|
test "W7 tally：同一档累加，空输入返回空对象（不是 null）" {
  let j = wt_tally(["merged", "merged", "blocked"])
  match j {
    Object(m) => {
      assert_eq(wt_i(j, "merged", 0), 2)
      assert_eq(wt_i(j, "blocked", 0), 1)
      assert_eq(m.get("stale") is None, true)
    }
    _ => abort("tally 必须是对象")
  }
  match wt_tally([]) {
    Object(m) => assert_eq(m.length(), 0)
    _ => abort("空 tally 也必须是空对象")
  }
}

///|
test "W8 porcelain 解析：多块 + detached + 尾块无空行 + refs/heads 剥离" {
  let raw = "worktree /a/wt-1\nHEAD 1111\nbranch refs/heads/wt/one\n\n" +
    "worktree /a/wt-2\nHEAD 2222\ndetached\n\n" +
    "worktree /a/wt-3\nHEAD 3333\nbranch refs/heads/main\n"
  let rows = wt_parse_porcelain(raw)
  assert_eq(rows.length(), 3)
  assert_eq(wt_s(rows[0], "path"), "/a/wt-1")
  assert_eq(wt_s(rows[0], "branch"), "wt/one")
  assert_eq(wt_s(rows[0], "head"), "1111")
  assert_eq(wt_s(rows[1], "detached"), "")
  match rows[1] {
    Object(m) =>
      match m.get("detached") {
        Some(True) => ()
        _ => abort("detached 行必须解析成 true")
      }
    _ => abort("行必须是对象")
  }
  // 尾块没有空行收尾也必须被 flush
  assert_eq(wt_s(rows[2], "path"), "/a/wt-3")
  assert_eq(wt_s(rows[2], "branch"), "main")
}

///|
test "W9 末段与 ref 剥离：wt_last_segment 容错尾分隔符，wt_strip_ref 只剥 refs/heads" {
  assert_eq(wt_last_segment("a/b/c"), "c")
  assert_eq(wt_last_segment("a/b/c/"), "c")
  assert_eq(wt_last_segment("solo"), "solo")
  assert_eq(wt_strip_ref("refs/heads/wt/x"), "wt/x")
  assert_eq(wt_strip_ref("tags/v1"), "tags/v1")
}

///|
/// W9 **三工具共用同一本账**（契约面，不是空转断言）：
/// `wt_create` 落这条账、`wt_status` 按这条账判七档、`wt_destroy` 只认这条账上的路径——
/// 三者只要有一方把路径约定改掉（例如改成 `wt_<task>.json` 或落别的目录），
/// 「创建了但 status 看不见」「status 说能收但 destroy 拒动」就会同时出现，
/// 而这正是本功能要防的那类**账对不上**的事故。
/// ⇒ 此处锁死：账路径 = `<project>/.fist-mbt/data/wt-<task>.json`，且 task 先过白名单。
test "W9 三工具共用同一本账：路径约定与 task 白名单" {
  let p = wt_manifest_path("/proj", "r181-preflight")
  assert_eq(p, "/proj/.fist-mbt/data/wt-r181-preflight.json")
  // 同一 task 两次调用必须得到**同一个**路径（否则 status 与 destroy 会看不同的账）
  assert_eq(wt_manifest_path("/proj", "t1"), wt_manifest_path("/proj", "t1"))
  // 不同 task 落不同文件（否则多沙箱会互相覆盖账）
  assert_true(wt_manifest_path("/proj", "a") != wt_manifest_path("/proj", "b"))
}

///|
/// W10 **防御纵深**：`wt_manifest_path` 自己就该挡住不合规 task，而不是把这件事
/// 托付给每个调用方。原实现只在注释里写「task 先过白名单」——调用方漏一处，
/// 就能用 `../` 把账读出/写出目录。合规 task 仍得到正常路径（零回归）。
test "W10 账路径自带白名单：不合规 task 不产生可越界路径" {
  // 合规：正常路径
  assert_eq(wt_manifest_path("/p", "r1"), "/p/.fist-mbt/data/wt-r1.json")
  // 不合规：不得把 `..` / 分隔符拼进路径（哨兵路径不含 task 内容）
  let bad = wt_manifest_path("/p", "../../etc/passwd")
  assert_false(bad.contains("./") || bad.contains("passwd"))
  let bad2 = wt_manifest_path("/p", "a/b")
  assert_false(bad2.contains("a/b"))
}

////|
/// W11 **TTL 非正值不许把活沙箱判成垃圾**：`wt_state_of` 原直接 `age_min > ttl_min`,
/// 于是 `ttl_min = 0` 或负值对任何沙箱恒真 ⇒ 刚创建、没动过、没并入的沙箱会立刻被判
/// `stale`（**可回收档**）⇒ 无人值守车道会把它当垃圾收掉。修法：非正值按默认 120 分钟算。
test "W11 ttl_min 非正值不得让新沙箱立刻 stale" {
  // 对照：未动过（head == created_sha）⇒ idle
  assert_eq(wt_state_of(true, Some(false), 0, 10, 120, "abc", "abc").0, "idle")
  // ttl=0 / 负值、年龄 5 分钟 ⇒ **不许** stale
  assert_eq(wt_state_of(true, Some(false), 0, 5, 0, "new", "old").0, "fresh")
  assert_eq(wt_state_of(true, Some(false), 0, 5, -30, "new", "old").0, "fresh")
  // 零回归：正 TTL 仍按原语义（301 > 300 ⇒ stale）
  assert_eq(wt_state_of(true, Some(false), 0, 301, 300, "new", "old").0, "stale")
}

///|
/// W12 **主工作树不是沙箱**：`git worktree list --porcelain` 的**第 0 条恒为主工作树**（仓库根）。
/// 原实现把它也算进 `unregistered` ⇒ **每次 `wt_status` 都报「有个没人管的沙箱」**——
/// 那是假信号，会诱导人去「清理」仓库根。修法：跳过第 0 条（并回执 `main_worktree` 说明是谁）。
test "W12 unregistered 跳过主工作树" {
  let main = wt_porcelain_row("/repo", "aaa", "main", false)
  let sb = wt_porcelain_row("/repo-sb", "bbb", "wt/t1", false)
  let parsed : Array[Json] = [main, sb]
  // 账上只有 sandbox ⇒ 无 unregistered（主工作树被跳过）
  assert_eq(wt_unregistered(parsed, ["/repo-sb"]).length(), 0)
  // 账上为空 ⇒ 只报 sandbox 一条（不是 2 条）
  assert_eq(wt_unregistered(parsed, []).length(), 1)
  // 尾部斜杠归一后仍能匹配
  assert_eq(wt_unregistered(parsed, ["/repo-sb/"]).length(), 0)
  // 只有主工作树一条 ⇒ 永远没有 unregistered
  assert_eq(wt_unregistered([wt_porcelain_row("/x", "", "", false)], []).length(), 0)
}
