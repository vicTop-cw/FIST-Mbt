///|
/// ops_modes_wbtest.mbt —— 自驱编程 7 种开发模式注册表白盒测试（≥ 20 条）

// ---------------------------------------------------------------------------
// default_mode
// ---------------------------------------------------------------------------

test "modes: default_mode 是 Advance" {
  match default_mode() {
    Advance => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// parse_mode：7 种合法值
// ---------------------------------------------------------------------------

///|
test "modes: parse_mode advance" {
  match parse_mode("advance") {
    Ok(Advance) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode polish" {
  match parse_mode("polish") {
    Ok(Polish) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode verify" {
  match parse_mode("verify") {
    Ok(Verify) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode bugfind" {
  match parse_mode("bugfind") {
    Ok(BugFind) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode fix_and_merge" {
  match parse_mode("fix_and_merge") {
    Ok(FixAndMerge) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode tidy" {
  match parse_mode("tidy") {
    Ok(Tidy) => assert_true(true)
    _ => assert_true(false)
  }
}

///|
test "modes: parse_mode explore（第 7 种）" {
  match parse_mode("explore") {
    Ok(Explore) => assert_true(true)
    _ => assert_true(false)
  }
  // trim 后同样可解析（与其余 6 种一致）
  match parse_mode("  explore ") {
    Ok(Explore) => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// parse_mode：非法值
// ---------------------------------------------------------------------------

///|
test "modes: parse_mode 非法值返回 Err" {
  match parse_mode("ADVANCE") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
  match parse_mode("bogus") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
  match parse_mode("") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
  // 近似名不收（防"exploring/exploratory"这类拼写悄悄落到某个模式上）
  match parse_mode("exploring") {
    Err(_) => assert_true(true)
    Ok(_) => assert_true(false)
  }
}

///|
test "modes: parse_mode 自动 trim 空白" {
  match parse_mode("  polish  ") {
    Ok(Polish) => assert_true(true)
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// mode_short
// ---------------------------------------------------------------------------

///|
test "modes: mode_short Advance" {
  assert_eq(mode_short(Advance), "advance")
}

///|
test "modes: mode_short Polish" {
  assert_eq(mode_short(Polish), "polish")
}

///|
test "modes: mode_short 覆盖 7 种" {
  assert_eq(mode_short(Advance), "advance")
  assert_eq(mode_short(Polish), "polish")
  assert_eq(mode_short(Verify), "verify")
  assert_eq(mode_short(BugFind), "bugfind")
  assert_eq(mode_short(FixAndMerge), "fix_and_merge")
  assert_eq(mode_short(Tidy), "tidy")
  assert_eq(mode_short(Explore), "explore")
}

// ---------------------------------------------------------------------------
// mode_template_path
// ---------------------------------------------------------------------------

///|
test "modes: mode_template_path advance" {
  assert_eq(mode_template_path("advance"), "templates/pipeline_mode_advance.md")
}

///|
test "modes: mode_template_path polish" {
  assert_eq(mode_template_path("polish"), "templates/pipeline_mode_polish.md")
}

///|
test "modes: mode_template_path 非法值也返回拼接字符串" {
  assert_eq(mode_template_path("bogus"), "templates/pipeline_mode_bogus.md")
}

///|
test "modes: mode_template_path explore" {
  assert_eq(mode_template_path("explore"), "templates/pipeline_mode_explore.md")
}

// ---------------------------------------------------------------------------
// mode_constraints（用 Json::boolean 构造函数 + assert_eq 比对）
// ---------------------------------------------------------------------------

///|
test "modes: mode_constraints polish forbid_new_features=true" {
  let j = mode_constraints("polish")
  match j {
    Object(m) =>
      assert_eq(m.get("forbid_new_features"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints tidy forbid_new_code=true" {
  let j = mode_constraints("tidy")
  match j {
    Object(m) => assert_eq(m.get("forbid_new_code"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints bugfind require_issue_scan=true" {
  let j = mode_constraints("bugfind")
  match j {
    Object(m) =>
      assert_eq(m.get("require_issue_scan"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints fix_and_merge require_github_token=true" {
  let j = mode_constraints("fix_and_merge")
  match j {
    Object(m) =>
      assert_eq(m.get("require_github_token"), Some(Json::boolean(true)))
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints verify API 枚举与文档检查" {
  let j = mode_constraints("verify")
  match j {
    Object(m) => {
      assert_eq(m.get("require_api_enum"), Some(Json::boolean(true)))
      assert_eq(m.get("require_doc_check"), Some(Json::boolean(true)))
    }
    _ => assert_true(false)
  }
}

///|
test "modes: mode_constraints advance 无特殊约束" {
  let j = mode_constraints("advance")
  match j {
    Object(m) => {
      assert_eq(m.get("forbid_new_features"), Some(Json::boolean(false)))
      assert_eq(m.get("require_issue_scan"), Some(Json::boolean(false)))
    }
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// all_modes
// ---------------------------------------------------------------------------

///|
test "modes: all_modes 长度 7" {
  assert_eq(all_modes().length(), 7)
}

///|
/// 向上最多 12 级定位仓库根：以**既有**的 advance 模板作为地标文件。
/// 返回 "…" 前缀（可直接与 "templates/xxx.md" 拼接；地标就在 cwd 时返回 Some("")）；
/// 定位不到返回 None ⇒ 调用方判红，绝不"看不见就当通过"。
/// 注意别把 Some("") 和 None 混成一个哨兵：实测地标文件就在 cwd，
/// 早期版本用空串同时表达"找到在根"和"没找到"，锁恒红（已改判 Some/None）。
fn xm_repo_root() -> String? {
  let marker = "templates/pipeline_mode_advance.md"
  let mut prefix = ""
  for i = 0; i < 12; i = i + 1 {
    if @fs.path_exists(prefix + marker) {
      return Some(prefix)
    }
    prefix = prefix + "../"
  }
  None
}

///|
test "modes: all_modes 每一项的模板文件真实存在（模板态不许悬空）" {
  // moon test 的 cwd 随 target/宿主而变，先定位仓库根再逐条查 7 份模板。
  // 定位不到根 ⇒ 判红（不是静默跳过）；某份模板缺失 ⇒ 也判红。
  let all = all_modes()
  assert_eq(all.length(), 7)
  match xm_repo_root() {
    Some(root) =>
      for item in all {
        match item {
          Object(m) =>
            match m.get("template_path") {
              Some(Json::String(p)) => assert_true(@fs.path_exists(root + p))
              _ => assert_true(false)
            }
          _ => assert_true(false)
        }
      }
    None => assert_true(false)
  }
}

///|
test "modes: all_modes 每个元素字段完备" {
  let all = all_modes()
  for item in all {
    match item {
      Object(m) => {
        // mode 字段
        match m.get("mode") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // name 字段
        match m.get("name") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // description 字段
        match m.get("description") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // constraints 字段（必须是 Json 对象）
        match m.get("constraints") {
          Some(Json::Object(_)) => assert_true(true)
          _ => assert_true(false)
        }
        // template_path 字段
        match m.get("template_path") {
          Some(Json::String(s)) => assert_true(s != "")
          _ => assert_true(false)
        }
        // forbidden_tools 字段（必须是数组）
        match m.get("forbidden_tools") {
          Some(Json::Array(_)) => assert_true(true)
          _ => assert_true(false)
        }
      }
      _ => assert_true(false)
    }
  }
}

///|
test "modes: all_modes mode 值互逆" {
  let all = all_modes()
  let expected = [
    "advance", "polish", "verify", "bugfind", "fix_and_merge", "tidy", "explore",
  ]
  for i = 0; i < all.length(); i = i + 1 {
    match all[i] {
      Object(m) =>
        match m.get("mode") {
          Some(Json::String(s)) => assert_eq(s, expected[i])
          _ => assert_true(false)
        }
      _ => assert_true(false)
    }
  }
}

// ---------------------------------------------------------------------------
// 额外：非法 parse_mode 错误消息包含提示
// ---------------------------------------------------------------------------

///|
test "modes: parse_mode 错误消息含可选值" {
  match parse_mode("bogus") {
    Err(msg) => assert_true(msg.contains("advance"))
    Ok(_) => assert_true(false)
  }
}

///|
test "modes: parse_mode 错误消息含第 7 种 explore（漏一个名字=调用面文档说谎）" {
  match parse_mode("bogus") {
    Err(msg) => {
      assert_true(msg.contains("explore"))
      assert_true(msg.contains("tidy"))
    }
    Ok(_) => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// 探索模式（explore）：抬头/约束/禁单/模板
// ---------------------------------------------------------------------------

///|
test "modes: mode_display_name explore" {
  assert_eq(mode_display_name("explore"), "探索：按复杂度自选模式")
  // 其余 6 种不得被顺手改坏（未知值仍落兜底串）
  assert_eq(mode_display_name("tidy"), "项目打扫清整")
  assert_eq(mode_display_name("nope"), "未知模式")
}

///|
test "modes: mode_constraints explore 挂三把专用门且布尔化" {
  let j = mode_constraints("explore")
  match j {
    Object(m) => {
      // 本模式自己不写代码，新功能允许与否由它选中的模式决定 → false
      assert_eq(m.get("forbid_new_features"), Some(Json::boolean(false)))
      assert_eq(m.get("require_issue_scan"), Some(Json::boolean(false)))
      // 真门槛：必须先打分、允许并行、并行必须作用域不相交
      assert_eq(m.get("require_complexity_scoring"), Some(Json::boolean(true)))
      assert_eq(m.get("allow_parallel_modes"), Some(Json::boolean(true)))
      assert_eq(m.get("require_disjoint_files"), Some(Json::boolean(true)))
    }
    _ => assert_true(false)
  }
}

///|
test "modes: mode_forbidden_tools explore 为空（它是派单口，禁 publish 会掐死自己）" {
  assert_eq(mode_forbidden_tools("explore").length(), 0)
  // 反向对照：polish/tidy 的禁单没被我这次改动碰掉
  assert_eq(mode_forbidden_tools("polish").length(), 3)
  assert_eq(mode_forbidden_tools("tidy").length(), 3)
}

///|
test "modes: all_modes explore 条目结构完整（forbidden_tools 是空数组）" {
  let explore_item = all_modes()[6]
  match explore_item {
    Object(m) => {
      assert_eq(m.get("mode"), Some(Json::string("explore")))
      assert_eq(
        m.get("template_path"),
        Some(Json::string("templates/pipeline_mode_explore.md")),
      )
      match m.get("description") {
        Some(Json::String(s)) => assert_true(s.contains("复杂度"))
        _ => assert_true(false)
      }
      match m.get("forbidden_tools") {
        Some(Json::Array(a)) => assert_eq(a.length(), 0)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// select_mode_by_complexity：档表 + 夹紧
// ---------------------------------------------------------------------------

///|
test "explore: select_mode_by_complexity 0..5 六档一一对应六个不同单模式" {
  let got = [
    mode_short(select_mode_by_complexity(0)),
    mode_short(select_mode_by_complexity(1)),
    mode_short(select_mode_by_complexity(2)),
    mode_short(select_mode_by_complexity(3)),
    mode_short(select_mode_by_complexity(4)),
    mode_short(select_mode_by_complexity(5)),
  ]
  assert_eq(got, [
    "tidy", "verify", "bugfind", "polish", "fix_and_merge", "advance",
  ])
  // 双射：六个档两两不同 ⇒ 没有任何单模式在选择器里永远选不到
  for i = 0; i < 6; i = i + 1 {
    for j = i + 1; j < 6; j = j + 1 {
      assert_true(got[i] != got[j])
    }
  }
}

///|
test "explore: select_mode_by_complexity 越界夹紧而非报错" {
  // 下越界：全部落到最低档 tidy
  assert_eq(mode_short(select_mode_by_complexity(-7)), "tidy")
  assert_eq(mode_short(select_mode_by_complexity(0)), "tidy")
  // 上越界：全部落到最高档 advance
  assert_eq(mode_short(select_mode_by_complexity(5)), "advance")
  assert_eq(mode_short(select_mode_by_complexity(6)), "advance")
  assert_eq(mode_short(select_mode_by_complexity(9999)), "advance")
}

///|
test "explore: select_mode_by_complexity 永不返回 explore 自身（探索模式不是工作单元）" {
  for c = -3; c <= 9; c = c + 1 {
    assert_eq(mode_short(select_mode_by_complexity(c)) != "explore", true)
  }
}

// ---------------------------------------------------------------------------
// 复杂度口径配对锁：ops_modes 的档表 ↔ decompose 的 difficulty_label_from
// ---------------------------------------------------------------------------

///|
/// 测试侧对照物：逐字复刻 src/decompose/decompose.mbt `difficulty_label_from`
/// 的两个阈值（易: d<=2.0 / 中: 2.0<d<=3.5 / 难: d>3.5）。
/// 它不是第二处产品真源（只在 wbtest 里），作用是：src/ops 无法 import
/// src/decompose（moon.pkg 未依赖，加依赖越界），所以拿它当尺子量
/// complexity_band_of_tier 有没有跟既有难度口径脱钩——改任一侧即红。
fn xm_oracle_tier(d : Double) -> String {
  if d <= 2.0 {
    "易"
  } else if d <= 3.5 {
    "中"
  } else {
    "难"
  }
}

///|
test "explore: complexity_band_of_tier 与既有 difficulty_label_from 阈值同口径" {
  // 正向：0..5 每个整数都落在"它自己那一档"的区间里
  for s = 0; s <= 5; s = s + 1 {
    let tier = xm_oracle_tier(s.to_double())
    let (lo, hi) = complexity_band_of_tier(tier)
    assert_true(lo <= s && s <= hi)
  }
  // 反向：档区间里的每个整数回灌 difficulty_label_from 口径仍是同一档
  for tier in ["易", "中", "难"] {
    let (lo, hi) = complexity_band_of_tier(tier)
    for s = lo; s <= hi; s = s + 1 {
      assert_eq(xm_oracle_tier(s.to_double()), tier)
    }
  }
  // 三档区间必须无缝且不重叠地铺满 0..5（否则有整数复杂度无人认领）
  assert_eq(complexity_band_of_tier("易"), (0, 2))
  assert_eq(complexity_band_of_tier("中"), (3, 3))
  assert_eq(complexity_band_of_tier("难"), (4, 5))
}

///|
test "explore: complexity_band_of_tier 未知档不夹（空串=无 LADDER 标记，放行信号分）" {
  assert_eq(complexity_band_of_tier(""), (0, 5))
  assert_eq(complexity_band_of_tier("极难"), (4, 5))
  assert_eq(complexity_band_of_tier("bogus"), (0, 5))
}

// ---------------------------------------------------------------------------
// estimate_complexity：信号 + LADDER 夹紧
// ---------------------------------------------------------------------------

///|
test "explore: estimate_complexity 恒在 0..5 内（越界夹紧，不报错）" {
  let cases = [
    ("", 0),
    ("补测试", 0),
    ("重构跨模块的 api 接口，修 bug 与失败回归并补测试", 12),
    ("改 README 说明", -5),
  ]
  for (desc, subs) in cases {
    let c = estimate_complexity(desc, subs)
    assert_true(c >= 0 && c <= 5)
  }
}

///|
test "explore: estimate_complexity 空目标 = 0 档（没信息 ⇒ 最低授权，不误开 advance）" {
  assert_eq(estimate_complexity("", 0), 0)
  assert_eq(
    mode_short(select_mode_by_complexity(estimate_complexity("", 0))),
    "tidy",
  )
}

///|
test "explore: estimate_complexity 满信号目标 = 5 档" {
  let unit = "bug 失败 测试 覆盖 api 接口 新功能 跨模块 重构 合并 "
  let big = xm_repeat(unit, 60)
  assert_eq(estimate_complexity(big, 40), 5)
}

///|
test "explore: estimate_complexity 单调—— richer 目标不低于 poorer 目标" {
  let poor = estimate_complexity("补测试", 0)
  let rich = estimate_complexity("补测试", 9)
  assert_true(rich >= poor)
  // 逐项对账：poor = 测试词 +1；rich = 测试词 +1 + 子任务 9 个 +2
  assert_eq(poor, 1)
  assert_eq(rich, 3)
}

///|
test "explore: estimate_complexity 以 LADDER 声明档为权威（夹进该档区间）" {
  // 信号分只有 1，但任务带"难"档 ⇒ 落到难档下界 4（不另立第二套难度口径）
  assert_eq(estimate_complexity("修 bug [难度梯度 3/3:难]", 0), 4)
  // 同一句话带"易"档 ⇒ 信号分被夹回 0..2 内的 1（1 已在区间内，不动）
  assert_eq(estimate_complexity("修 bug [难度梯度 1/3:易]", 0), 1)
  // "中"档是单点档 3 ⇒ 无论信号分多少都钉在 3
  assert_eq(estimate_complexity("重构 [难度梯度 2/3:中]", 0), 3)
  assert_eq(estimate_complexity("重构 [难度梯度 2/3:中]", 40), 3)
  // 无档标记 ⇒ 信号分原样生效（上面那支 "修 bug" = 1）
  assert_eq(estimate_complexity("修 bug", 0), 1)
}

///|
test "explore: estimate_complexity 文档词不加分（防把『补文档』估成高复杂度）" {
  assert_eq(estimate_complexity("补充文档与说明注释", 0), 0)
  assert_eq(estimate_complexity("补充文档与说明注释 readme", 0), 0)
}

///|
fn xm_repeat(unit : String, times : Int) -> String {
  let mut s = ""
  for i = 0; i < times; i = i + 1 {
    s = s + unit
  }
  s
}

// ---------------------------------------------------------------------------
// file_scope_conflicts / file_scopes_disjoint
// ---------------------------------------------------------------------------

///|
test "explore: file_scopes_disjoint 两两不相交/重叠/自重叠三种形状" {
  assert_eq(file_scopes_disjoint([["a.mbt"], ["b.mbt"]]), true)
  assert_eq(file_scopes_disjoint([["a.mbt"], ["a.mbt"]]), false)
  assert_eq(
    file_scopes_disjoint([["a.mbt", "b.mbt"], ["b.mbt", "c.mbt"]]),
    false,
  )
  assert_eq(file_scopes_disjoint([["a.mbt"]]), true)
  assert_eq(file_scopes_disjoint([]), true)
  // trim 后比对（申报串带空格不该被当成两个不同文件）
  assert_eq(file_scopes_disjoint([[" a.mbt "], ["a.mbt"]]), false)
  // 空串忽略：两格都只申报空串 ⇒ 无从相交，交由"未申报"那道门去拦
  assert_eq(file_scopes_disjoint([[""], [""]]), true)
  assert_eq(file_scope_conflicts([["x.mbt", "y.mbt"], ["y.mbt", "z.mbt"]]), [
    "y.mbt",
  ])
}

///|
test "explore: file_scope_conflicts 不做路径归一化（./a 与 a 视作两个作用域）" {
  // 这条锁钉住"归一是调用方责任"的声明：若哪天改成归一比对，这里必须同步改。
  assert_eq(file_scopes_disjoint([["./a.mbt"], ["a.mbt"]]), true)
}

// ---------------------------------------------------------------------------
// explore_plan：四把门
// ---------------------------------------------------------------------------

///|
fn xm_json(j : Json, key : String) -> Json? {
  match j {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
fn xm_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Json::String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn xm_str_array(j : Json, key : String) -> Array[String] {
  let out : Array[String] = []
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Json::Array(arr)) =>
          for e in arr {
            match e {
              Json::String(s) => out.push(s)
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  out
}

///|
/// "中"档描述 ⇒ 复杂度恒为 3 ⇒ chosen_mode 恒为 polish，与信号分无关。
/// 用它的目的是让并行用例的 chosen_mode 可预测（不必在测试里重算信号）。
const XM_MID_DESC : String = "把这块逻辑梳理一遍 [难度梯度 2/3:中]"

///|
test "explore: explore_plan 无候选 ⇒ 单模式，parallel_allowed=false" {
  let p = explore_plan(XM_MID_DESC, 0, [], [], true)
  assert_eq(xm_str(p, "chosen_mode"), "polish")
  assert_eq(xm_json(p, "complexity"), Some(Json::number(3.0)))
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish"])
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
  assert_eq(xm_str(p, "declared_tier"), "中")
  assert_true(xm_str(p, "basis").contains("polish"))
}

///|
test "explore: explore_plan 作用域重叠 ⇒ 拒并行（承重锁）" {
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["polish", "verify"],
    [["src/a.mbt", "src/shared.mbt"], ["src/shared.mbt"]],
    true,
  )
  assert_eq(xm_json(p, "scopes_declared"), Some(Json::boolean(true)))
  assert_eq(xm_json(p, "scopes_disjoint"), Some(Json::boolean(false)))
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
  // 拒并行时扇出面积必须回收到 1（不是"照旧并行、只在 note 里抱怨"）
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish"])
  assert_true(xm_str(p, "note").contains("src/shared.mbt"))
}

///|
test "explore: explore_plan 作用域不相交 + 已放行 ⇒ 允许并行" {
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["polish", "verify"],
    [["src/a.mbt"], ["docs/b.md"]],
    true,
  )
  assert_eq(xm_json(p, "scopes_declared"), Some(Json::boolean(true)))
  assert_eq(xm_json(p, "scopes_disjoint"), Some(Json::boolean(true)))
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(true)))
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish", "verify"])
}

///|
test "explore: explore_plan 光靠『不相交』不放行——必须回传 conflicts_check 结论" {
  // 两两不相交只证明"本轮候选之间不打架"，挡不住别的 agent 早已预订其中文件。
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["polish", "verify"],
    [["src/a.mbt"], ["docs/b.md"]],
    false,
  )
  assert_eq(xm_json(p, "scopes_disjoint"), Some(Json::boolean(true)))
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish"])
  assert_true(xm_str(p, "note").contains("scopes_cleared"))
}

///|
test "explore: explore_plan 有候选没申报作用域 ⇒ 拒并行（fail-closed）" {
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["polish", "verify"],
    [["src/a.mbt"], []],
    true,
  )
  assert_eq(xm_json(p, "scopes_declared"), Some(Json::boolean(false)))
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
  assert_true(xm_str(p, "note").contains("未申报"))
  // files 比候选短同样按"未申报"处理（下标对不齐 ⇒ 不许猜）
  let q = explore_plan(XM_MID_DESC, 0, ["polish", "verify"], [["a"]], true)
  assert_eq(xm_json(q, "parallel_allowed"), Some(Json::boolean(false)))
  assert_eq(xm_json(q, "scopes_declared"), Some(Json::boolean(false)))
}

///|
test "explore: explore_plan 候选没含选中模式 ⇒ 补到头部并判未申报（不许绕过门）" {
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["verify", "bugfind"],
    [["src/a.mbt"], ["src/b.mbt"]],
    true,
  )
  assert_eq(xm_str(p, "chosen_mode"), "polish")
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish"])
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
  assert_eq(xm_json(p, "scopes_declared"), Some(Json::boolean(false)))
}

///|
test "explore: explore_plan 拒收 explore 自身为并行工作单元（防无限递归）" {
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["polish", "explore"],
    [["src/a.mbt"], ["src/b.mbt"]],
    true,
  )
  assert_eq(xm_str_array(p, "rejected_candidates").length(), 1)
  assert_true(xm_str_array(p, "rejected_candidates")[0].contains("explore"))
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish"])
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
}

///|
test "explore: explore_plan 剔除非法模式名并进 rejected_candidates" {
  let p = explore_plan(
    XM_MID_DESC,
    0,
    ["polish", "bogus", "polish"],
    [["src/a.mbt"], ["src/b.mbt"], ["src/c.mbt"]],
    true,
  )
  let rej = xm_str_array(p, "rejected_candidates")
  assert_eq(rej.length(), 1)
  assert_true(rej[0].contains("bogus"))
  // 重名去重：只剩 1 个可用候选 ⇒ 并行门不触发
  assert_eq(xm_str_array(p, "parallel_modes"), ["polish"])
  assert_eq(xm_json(p, "parallel_allowed"), Some(Json::boolean(false)))
}

///|
test "explore: explore_plan 返回契约键齐全 + conflict_gate 字面量" {
  let p = explore_plan(XM_MID_DESC, 0, [], [], false)
  for
    k in [
      "chosen_mode", "complexity", "basis", "parallel_modes", "parallel_allowed",
      "conflict_gate", "note",
    ] {
    assert_true(xm_json(p, k) != None)
  }
  assert_eq(xm_str(p, "conflict_gate"), "reserve_scope/conflicts_check")
}

///|
test "explore: explore_plan 的 complexity 与 estimate_complexity 同值（两出口不漂移）" {
  for desc in [XM_MID_DESC, "修 bug [难度梯度 3/3:难]", "", "补测试"] {
    let p = explore_plan(desc, 5, [], [], false)
    let want = estimate_complexity(desc, 5)
    assert_eq(xm_json(p, "complexity"), Some(Json::number(want.to_double())))
    assert_eq(
      xm_str(p, "chosen_mode"),
      mode_short(select_mode_by_complexity(want)),
    )
  }
}

///|
test "explore: explore_plan 纯计算——同输入两次调用逐字节相同（无时钟/无随机/不读库）" {
  let a = explore_plan(
    XM_MID_DESC,
    3,
    ["polish", "verify"],
    [["src/a.mbt"], ["docs/b.md"]],
    true,
  )
  let b = explore_plan(
    XM_MID_DESC,
    3,
    ["polish", "verify"],
    [["src/a.mbt"], ["docs/b.md"]],
    true,
  )
  assert_eq(a.stringify(), b.stringify())
  assert_eq(xm_json(a, "parallel_allowed"), Some(Json::boolean(true)))
}

// ---------------------------------------------------------------------------
// validate_loop_steps 接受第 7 种（本文件可达：同包白盒）
// ---------------------------------------------------------------------------

///|
test "loop: validate_loop_steps 接受 explore（组合环可用第 7 种）" {
  assert_eq(validate_loop_steps(["explore"]), None)
  assert_eq(validate_loop_steps(["explore", "polish"]), None)
  // to_lower 归一：大写传入同样合法（与其余 6 种一致）
  assert_eq(validate_loop_steps(["EXPLORE"]), None)
}

///|
test "loop: validate_loop_steps 仍拒非法 step，且错误消息点名 explore" {
  match validate_loop_steps(["nope"]) {
    Some(msg) => {
      assert_true(msg.contains("nope"))
      assert_true(msg.contains("explore"))
      assert_true(msg.contains("tidy"))
    }
    None => assert_true(false)
  }
  assert_eq(validate_loop_steps([]), Some("steps is empty"))
}
