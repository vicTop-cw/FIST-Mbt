/// filebind_wbtest.mbt —— F094 多管家并行文件绑定协调层（T0r5）白盒锁
///
/// 本层登记的是「意图 / 持有者 / TTL」，不是物理路径锁（`lock_acquire`）或 worktree
/// 空间隔离（`wt_*`）——三者互补：本层让两个 agent 打算改同一文件时**被检出并拒绝**，
/// 而不是 last-write-wins（见 docs/features/F094-multi-butler-file-binds.md §一/§三）。
///
/// 判例纪律：
///  - **变异对照**：`fb_decide` 的冲突分支被改成「永远放行」时，本文件的
///    `fb_conflict_lock_conflicting_holder_rejected` / `fb_plan_bind_conflict_names_holder`
///    必须**变红**；还原后复绿（红/绿原文见交付报告）。
///  - **禁 `sleep`**：TTL 过期一律用**传入的 `now`** 断言（判例-31），同一毫秒内两个 now 判过期/有效。
///  - **锁只断言返回值/裁决**，不断言源码字符串（判例-30）。

///|
/// 构造一个绑定条目（默认 scope=edit / kind=file）。
fn mk(
  ns : String,
  pd : String,
  path : String,
  holder : String,
  at : Int32,
  ttl : Int32,
) -> FileBind {
  FileBind::{
    ns,
    project_dir: pd,
    path,
    holder,
    task_id: "T1",
    kind: "file",
    scope: "edit",
    intent: "intent",
    bound_at: at,
    ttl_secs: ttl,
  }
}

///|
/// 路径归一：`\\` → `/`、丢空段与 `.` 段、剥尾部 `/`。
test "fb_norm_collapses_and_normalizes" {
  assert_eq(fb_norm("src\\a\\b.mbt"), "src/a/b.mbt")
  assert_eq(fb_norm("a//b/./c/"), "a/b/c")
  assert_eq(fb_norm("./x"), "x")
  assert_eq(fb_norm(""), "")
  assert_eq(fb_norm("   "), "")
  // `..` 段**不折叠**（越界洗白会让 fb_path_ok 失守）
  assert_eq(fb_norm("a/../b"), "a/../b")
}

///|
/// 路径白名单：非空、非绝对、无 `..` 段、无盘符。
test "fb_path_ok_accepts_relative_rejects_escape" {
  assert_true(fb_path_ok("src/a.mbt"))
  assert_true(fb_path_ok("src\\a.mbt"))
  assert_true(fb_path_ok("a/./b.mbt"))
  assert_false(fb_path_ok(""))
  assert_false(fb_path_ok("   "))
  assert_false(fb_path_ok("/abs/a.mbt"))
  assert_false(fb_path_ok("../x"))
  assert_false(fb_path_ok("a/../b"))
  assert_false(fb_path_ok("a/../../b"))
  assert_false(fb_path_ok("."))
  assert_false(fb_path_ok("C:/x"))
  assert_false(fb_path_ok("C:\\x"))
}

///|
/// 绑定键三元组：ns / project_dir / path 任一不同即不同绑定位。
test "fb_key_isolates_ns_project_and_path" {
  assert_true(fb_key("ns1", "proj", "a.mbt") != fb_key("ns2", "proj", "a.mbt"))
  assert_true(
    fb_key("ns1", "projA", "a.mbt") != fb_key("ns1", "projB", "a.mbt"),
  )
  assert_true(fb_key("ns1", "proj", "a.mbt") != fb_key("ns1", "proj", "b.mbt"))
  assert_true(
    fb_key("ns1", "proj\\x", "a.mbt") == fb_key("ns1", "proj/x", "a.mbt"),
  )
}

///|
/// 过期/剩余：TTL 边界 + `ttl<=0` 永不过期。
test "fb_expired_and_remaining_boundaries" {
  let b = mk("ns", "proj", "a.mbt", "A", 100, 10)
  // now - bound_at >= ttl 才过期（边界含等号）
  assert_false(fb_expired(b, 109))
  assert_true(fb_expired(b, 110))
  assert_true(fb_expired(b, 120))
  assert_eq(fb_remaining(b, 105), 5)
  assert_eq(fb_remaining(b, 110), 0)
  assert_eq(fb_remaining(b, 120), 0)
  // 永不过期：ttl<=0
  let perm = mk("ns", "proj", "p.mbt", "A", 100, 0)
  assert_false(fb_expired(perm, 999999))
  assert_false(fb_expired(mk("ns", "proj", "q.mbt", "A", 100, -5), 999999))
  assert_eq(fb_remaining(perm, 999999), -1)
}

///|
/// 绑定裁决单一真源：空闲→New；本人→Renewed（**即便已过期也先判本人续期**，
/// 而不是去接管自己的坟）；他主过期→Reclaimed；他主有效→Conflict。
test "fb_decide_matrix" {
  let b = mk("ns", "proj", "a.mbt", "A", 100, 10)
  match fb_decide(None, "B", 105) {
    BndNew => ()
    _ => abort("fb_decide_matrix: empty must be BndNew")
  }
  match fb_decide(Some(b), "A", 105) {
    BndRenewed => ()
    _ => abort("fb_decide_matrix: same holder must be BndRenewed")
  }
  // 本人已过期 —— 仍是 Renewed（顺序承重：本人先判）
  match fb_decide(Some(b), "A", 500) {
    BndRenewed => ()
    _ => abort("fb_decide_matrix: same holder expired must still BndRenewed")
  }
  // 他主已过期 —— Reclaimed（过期 ≠ 仍被持有，绝不永远挡路）
  match fb_decide(Some(b), "B", 500) {
    BndReclaimed => ()
    _ => abort("fb_decide_matrix: expired other holder must BndReclaimed")
  }
}

///|
/// **变异锁**：他主仍有效 ⇒ 必须 BndConflict。把 `fb_decide` 的冲突分支改成
/// 「永远放行」（BndNew）时，本格**必红**。
test "fb_conflict_lock_conflicting_holder_rejected" {
  let b = mk("ns", "proj", "a.mbt", "A", 100, 1000)
  match fb_decide(Some(b), "B", 101) {
    BndConflict => ()
    _ =>
      abort(
        "fb_conflict_lock: 他主有效必须 BndConflict（变异对照：改成永远放行则本格红）",
      )
  }
}

///|
/// 冲突点名：`fb_plan_bind` 的冲突行 holder = 现持有者（不是请求者）。
test "fb_plan_bind_conflict_names_holder" {
  let b = mk("ns", "proj", "src/a.mbt", "A", 100, 1000)
  let rows = fb_plan_bind([b], "ns", "proj", ["src/a.mbt"], "B", 101, 60)
  assert_eq(rows.length(), 1)
  match rows[0].verdict {
    BndConflict => ()
    _ => abort("fb_plan_bind_conflict: 期望 BndConflict")
  }
  assert_eq(rows[0].holder, "A") // 点名现持有者
  assert_eq(rows[0].bound_at, 100) // 现持有者的绑定时刻
  assert_eq(rows[0].ttl_secs, 1000) // 现持有者的 TTL
}

///|
/// 一次绑多个路径：逐条结果，冲突/新建/非法路径各自成行。
test "fb_plan_bind_multi_path_row_by_row" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 100, 1000)
  let rows = fb_plan_bind(
    [a],
    "ns",
    "proj",
    ["src/a.mbt", "src/b.mbt", "../bad.mbt"],
    "B",
    101,
    60,
  )
  assert_eq(rows.length(), 3)
  match rows[0].verdict {
    BndConflict => ()
    _ => abort("fb_plan_bind_multi: row0 期望 BndConflict")
  }
  match rows[1].verdict {
    BndNew => ()
    _ => abort("fb_plan_bind_multi: row1 期望 BndNew")
  }
  assert_eq(rows[1].holder, "B")
  match rows[2].verdict {
    BndInvalidPath => ()
    _ => abort("fb_plan_bind_multi: row2 期望 BndInvalidPath")
  }
}

///|
/// 同一批里重复给同一路径：首行 New、次行 Renewed（影子副本模拟"已落账"），
/// 不产生两条重复绑定。
test "fb_plan_bind_same_path_in_batch_is_idempotent" {
  let rows = fb_plan_bind(
    [],
    "ns",
    "proj",
    ["src/x.mbt", "src/x.mbt", "src/x.mbt"],
    "B",
    100,
    60,
  )
  assert_eq(rows.length(), 3)
  match rows[0].verdict {
    BndNew => ()
    _ => abort("fb_plan_bind_same: row0 期望 BndNew")
  }
  match rows[1].verdict {
    BndRenewed => ()
    _ => abort("fb_plan_bind_same: row1 期望 BndRenewed")
  }
  match rows[2].verdict {
    BndRenewed => ()
    _ => abort("fb_plan_bind_same: row2 期望 BndRenewed")
  }
  // 三次都只有一条绑定落账
  let after = fb_apply_bind(
    [],
    "ns",
    "proj",
    rows,
    "B",
    "T1",
    "file",
    "edit",
    "intent",
    100,
    60,
  )
  assert_eq(after.length(), 1)
}

///|
/// `fb_apply_bind` 只落成功三态：冲突行**一个字节都不写**（不覆盖现持有者）。
test "fb_apply_bind_skips_conflict_and_invalid" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 100, 1000)
  let rows = fb_plan_bind(
    [a],
    "ns",
    "proj",
    ["src/a.mbt", "src/b.mbt", "../bad.mbt"],
    "B",
    101,
    60,
  )
  let out = fb_apply_bind(
    [a],
    "ns",
    "proj",
    rows,
    "B",
    "T1",
    "file",
    "edit",
    "intent",
    101,
    60,
  )
  assert_eq(out.length(), 2) // a 保留 + b 新增
  assert_eq(out[0].holder, "A") // 冲突行没被覆盖
  assert_eq(out[1].holder, "B")
  assert_eq(out[1].path, "src/b.mbt")
  // 入参不被 mutation
  assert_eq(a.holder, "A")
}

///|
/// 释放裁决：NotFound / 持有者 Released / 非持有者未 force RelNotHolder / force RelForced。
test "fb_decide_release_matrix" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 100, 10)
  match fb_decide_release(None, "B", false) {
    RelNotFound => ()
    _ => abort("fb_decide_release: empty must RelNotFound")
  }
  match fb_decide_release(Some(a), "A", false) {
    RelReleased => ()
    _ => abort("fb_decide_release: holder must RelReleased")
  }
  match fb_decide_release(Some(a), "B", false) {
    RelNotHolder => ()
    _ => abort("fb_decide_release: other no force must RelNotHolder")
  }
  match fb_decide_release(Some(a), "B", true) {
    RelForced => ()
    _ => abort("fb_decide_release: other force must RelForced")
  }
}

///|
/// 释放计划：只命中筛选项出行；未命中的不出行（不是"拒了"，是"不归这次管"）。
test "fb_plan_release_filters_and_only_matching" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 100, 10)
  let b = mk("ns", "proj", "src/b.mbt", "B", 100, 10)
  let all = fb_plan_release([a, b], "ns", "proj", [], "", "edit", "A", false)
  assert_eq(all.length(), 2)
  let only_a = fb_plan_release(
    [a, b],
    "ns",
    "proj",
    ["src/a.mbt"],
    "",
    "edit",
    "A",
    false,
  )
  assert_eq(only_a.length(), 1)
  assert_eq(only_a[0].path, "src/a.mbt")
  // 非持有者只释放自己那部分
  let rel_b = fb_plan_release(
    [a, b],
    "ns",
    "proj",
    ["src/b.mbt"],
    "",
    "edit",
    "B",
    false,
  )
  assert_eq(rel_b.length(), 1)
  match rel_b[0].verdict {
    RelReleased => ()
    _ => abort("fb_plan_release: B 释放自己的必须 RelReleased")
  }
}

///|
/// `fb_apply_release` 只移除 Released/Forced；RelNotHolder 原样保留（拒绝释放 ≠ 悄悄删）。
test "fb_apply_release_keeps_not_holder" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 100, 10)
  let b = mk("ns", "proj", "src/b.mbt", "B", 100, 10)
  let rows = [
    ReleaseRow::{ path: "src/a.mbt", verdict: RelReleased, holder: "A", },
    ReleaseRow::{ path: "src/b.mbt", verdict: RelNotHolder, holder: "B", },
  ]
  let out = fb_apply_release([a, b], "ns", "proj", rows, "T1", "edit")
  assert_eq(out.length(), 1)
  assert_eq(out[0].path, "src/b.mbt")
  assert_eq(out[0].holder, "B")
}

///|
/// force 生效：非持有者 + force ⇒ 移除。
test "fb_apply_release_force_removes" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 100, 10)
  let rows = [
    ReleaseRow::{ path: "src/a.mbt", verdict: RelForced, holder: "A", },
  ]
  let out = fb_apply_release([a], "ns", "proj", rows, "", "edit")
  assert_eq(out.length(), 0)
}

///|
/// **过期与仍有效分开计数**（BUG-74 同族：两栏不许混读）。
test "fb_counts_valid_vs_expired_separated" {
  let v1 = mk("ns", "proj", "v1.mbt", "A", 100, 1000)
  let v2 = mk("ns", "proj", "v2.mbt", "B", 100, 1000)
  let e1 = mk("ns", "proj", "e1.mbt", "C", 100, 1)
  let (valid, expired) = fb_counts([v1, v2, e1], 500)
  assert_eq(valid, 2)
  assert_eq(expired, 1)
  // 空账本
  let (v0, e0) = fb_counts([], 500)
  assert_eq(v0, 0)
  assert_eq(e0, 0)
}

///|
/// `ttl<=0` 永不过期 ⇒ 计入 valid，不进 expired。
test "fb_counts_permanent_bind_is_valid" {
  let perm = mk("ns", "proj", "perm.mbt", "A", 0, 0)
  let (valid, expired) = fb_counts([perm], 999999)
  assert_eq(valid, 1)
  assert_eq(expired, 0)
}

///|
/// `fb_match` 各维过滤（空串 = 不过滤；多维交集）。
test "fb_match_dimension_filters" {
  let b = mk("ns1", "projA", "src/a.mbt", "A", 100, 10)
  assert_true(fb_match(b, "", "", [], "", ""))
  assert_true(fb_match(b, "ns1", "projA", [], "T1", "edit"))
  assert_false(fb_match(b, "ns2", "projA", [], "T1", "edit"))
  assert_false(fb_match(b, "ns1", "projB", [], "T1", "edit"))
  assert_false(fb_match(b, "ns1", "projA", [], "T2", "edit"))
  assert_false(fb_match(b, "ns1", "projA", [], "T1", "build"))
  assert_true(fb_match(b, "ns1", "projA", ["src/a.mbt"], "T1", "edit"))
  assert_false(fb_match(b, "ns1", "projA", ["src/z.mbt"], "T1", "edit"))
  assert_false(fb_match(b, "ns1", "projA", ["src/a.mbt"], "T2", "edit"))
}

///|
/// 裁决 → 稳定字符串名。
test "fb_verdict_and_release_names" {
  assert_eq(fb_verdict_name(BndNew), "bound")
  assert_eq(fb_verdict_name(BndRenewed), "renewed")
  assert_eq(fb_verdict_name(BndReclaimed), "reclaimed")
  assert_eq(fb_verdict_name(BndConflict), "conflict")
  assert_eq(fb_verdict_name(BndInvalidPath), "invalid_path")
  assert_eq(fb_release_name(RelReleased), "released")
  assert_eq(fb_release_name(RelForced), "forced")
  assert_eq(fb_release_name(RelNotHolder), "not_holder")
  assert_eq(fb_release_name(RelNotFound), "not_found")
}

///|
/// 绑定行 JSON：`ok` 只对成功三态为 true，含剩余秒数。
test "fb_row_json_ok_and_remaining" {
  let new_row = BindPlanRow::{
    path: "src/a.mbt",
    verdict: BndNew,
    holder: "B",
    bound_at: 100,
    ttl_secs: 60,
  }
  match fb_row_json(new_row, 105) {
    Object(m) => {
      assert_eq(m.get("path"), Some(Json::string("src/a.mbt")))
      assert_eq(m.get("verdict"), Some(Json::string("bound")))
      assert_eq(m.get("ok"), Some(Json::boolean(true)))
      assert_eq(m.get("holder"), Some(Json::string("B")))
      assert_eq(m.get("remaining_secs"), Some(Json::number(55.0)))
    }
    _ => abort("fb_row_json_new: 期望 JSON object")
  }
  let conflict_row = BindPlanRow::{
    path: "src/a.mbt",
    verdict: BndConflict,
    holder: "A",
    bound_at: 100,
    ttl_secs: 1000,
  }
  match fb_row_json(conflict_row, 105) {
    Object(m) => {
      assert_eq(m.get("verdict"), Some(Json::string("conflict")))
      assert_eq(m.get("ok"), Some(Json::boolean(false)))
      assert_eq(m.get("holder"), Some(Json::string("A")))
    }
    _ => abort("fb_row_json_conflict: 期望 JSON object")
  }
}

///|
/// 状态行 JSON：`expired` 与 `remaining_secs` 由 `now` 决定。
test "fb_status_json_expired_flag" {
  let b = mk("ns", "proj", "src/a.mbt", "A", 100, 10)
  match fb_status_json(b, 105) {
    Object(m) => {
      assert_eq(m.get("expired"), Some(Json::boolean(false)))
      assert_eq(m.get("remaining_secs"), Some(Json::number(5.0)))
      assert_eq(m.get("holder"), Some(Json::string("A")))
    }
    _ => abort("fb_status_json_valid: 期望 JSON object")
  }
  match fb_status_json(b, 120) {
    Object(m) => assert_eq(m.get("expired"), Some(Json::boolean(true)))
    _ => abort("fb_status_json_expired: 期望 JSON object")
  }
}

///|
/// 账本序列化/反序列化往返：字段不丢、可跨进程复现。
test "fb_ledger_serialize_parse_roundtrip" {
  let bs = [
    mk("ns1", "proj", "src/a.mbt", "A", 100, 10),
    mk("ns1", "proj", "src/b.mbt", "B", 200, 0),
  ]
  let raw = fb_ledger_serialize(bs)
  let back = fb_ledger_parse(raw)
  assert_eq(back.length(), 2)
  assert_eq(back[0].ns, "ns1")
  assert_eq(back[0].project_dir, "proj")
  assert_eq(back[0].path, "src/a.mbt")
  assert_eq(back[0].holder, "A")
  assert_eq(back[0].bound_at, 100)
  assert_eq(back[0].ttl_secs, 10)
  assert_eq(back[1].holder, "B")
  assert_eq(back[1].ttl_secs, 0)
  // 序列化是稳定字符串
  assert_true(fb_ledger_serialize(bs) == raw)
}

///|
/// 坏账不"顺手清账"：坏 JSON / 形状不对 / 缺 path 或 holder 的条目一律丢弃但保留合法条目。
test "fb_ledger_parse_bad_inputs" {
  assert_eq(fb_ledger_parse("").length(), 0)
  assert_eq(fb_ledger_parse("   ").length(), 0)
  assert_eq(fb_ledger_parse("not json").length(), 0)
  assert_eq(fb_ledger_parse("{}").length(), 0)
  assert_eq(fb_ledger_parse("123").length(), 0)
  // 裸数组 + 坏条目 + 好条目
  let raw = "[{\"path\":\"\",\"holder\":\"X\"},{\"path\":\"a.mbt\",\"holder\":\"A\",\"bound_at\":1,\"ttl_secs\":2}]"
  let back = fb_ledger_parse(raw)
  assert_eq(back.length(), 1)
  assert_eq(back[0].path, "a.mbt")
  assert_eq(back[0].holder, "A")
}

///|
/// 端到端「意图」闭环：A 绑 → B 冲突被拒并点名 → B 等 A 过期后接管 → B 释放 → A 再绑。
test "fb_end_to_end_intent_lifecycle" {
  // 阶段 1：A 绑住 a.mbt（ttl=1000）
  let a = mk("ns", "proj", "src/a.mbt", "A", 1000, 1000)
  // 阶段 2：B 来抢同一路径，仍有效 ⇒ 拒绝并点名 A
  let plan_b = fb_plan_bind([a], "ns", "proj", ["src/a.mbt"], "B", 1001, 60)
  match plan_b[0].verdict {
    BndConflict => ()
    _ => abort("fb_e2e: B 抢有效绑定必须 BndConflict")
  }
  assert_eq(plan_b[0].holder, "A")
  // 阶段 3：now 前进到过期后，B 接管（过期 ≠ 仍被持有）
  let plan_b2 = fb_plan_bind([a], "ns", "proj", ["src/a.mbt"], "B", 2500, 60)
  match plan_b2[0].verdict {
    BndReclaimed => ()
    _ => abort("fb_e2e: B 在 A 过期后必须 BndReclaimed")
  }
  let ledger = fb_apply_bind(
    [a],
    "ns",
    "proj",
    plan_b2,
    "B",
    "T2",
    "file",
    "edit",
    "intent",
    2500,
    60,
  )
  assert_eq(ledger.length(), 1)
  assert_eq(ledger[0].holder, "B")
  // 阶段 4：B 释放
  let rel = fb_plan_release(ledger, "ns", "proj", [], "T2", "edit", "B", false)
  assert_eq(rel.length(), 1)
  match rel[0].verdict {
    RelReleased => ()
    _ => abort("fb_e2e: B 释放自己必须 RelReleased")
  }
  let empty = fb_apply_release(ledger, "ns", "proj", rel, "T2", "edit")
  assert_eq(empty.length(), 0)
}

///|
/// **变异对照的入口级锁**：`fb_plan_bind` 在"同键他人有效持有"时，冲突行的
/// `holder` 必须是**现持有者**（而非请求者），且 `verdict` 必须是 BndConflict。
/// 任何「永远放行」式变异都会让下面这两条断言变红。
test "fb_mutation_lock_conflict_never_allowed" {
  let a = mk("ns", "proj", "src/a.mbt", "A", 1000, 1000)
  let rows = fb_plan_bind([a], "ns", "proj", ["src/a.mbt"], "B", 1001, 60)
  assert_eq(rows.length(), 1)
  match rows[0].verdict {
    BndConflict => ()
    _ =>
      abort(
        "fb_mutation_lock: 冲突被放行（应 BndConflict）——变异对照失败",
      )
  }
  assert_eq(rows[0].holder, "A")
}
