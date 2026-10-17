///|
/// display/staff_test.mbt —— 参谋线展示层测试。
/// 真源：docs/2026-10-12-fist-mbt-web-dashboard-plan.md §8.1「参谋线」表。

///|
test "staff_titles 含 6 参谋军职" {
  let titles = staff_titles()
  assert_eq(titles.length(), staff_title_count())
  assert_eq(staff_title_count(), 6)
  assert_eq(titles[0], "侦察参谋")
  assert_eq(titles[2], "验收宪兵")
  assert_eq(titles[5], "训练教官")
}

///|
test "staff_label 关键词命中" {
  assert_eq(staff_label("searcher"), "侦察参谋")
  assert_eq(staff_label("侦察"), "侦察参谋")
  assert_eq(staff_label("情报"), "侦察参谋")
  assert_eq(staff_label("allocator"), "后勤参谋")
  assert_eq(staff_label("后勤"), "后勤参谋")
  assert_eq(staff_label("verifier"), "验收宪兵")
  assert_eq(staff_label("验收"), "验收宪兵")
  assert_eq(staff_label("observer"), "监察参谋")
  assert_eq(staff_label("监察"), "监察参谋")
  assert_eq(staff_label("specauthor"), "训练教官")
  assert_eq(staff_label("教官"), "训练教官")
  assert_eq(staff_label("recorder"), "军务文书")
  assert_eq(staff_label("文书"), "军务文书")
}

///|
test "staff_label 未知回退军务文书" {
  assert_eq(staff_label(""), "军务文书")
  assert_eq(staff_label("xyzunknown"), "军务文书")
}

///|
test "staff_label 大小写不敏感" {
  assert_eq(staff_label("Searcher"), "侦察参谋")
  assert_eq(staff_label("Verifier"), "验收宪兵")
  assert_eq(staff_label("Observer"), "监察参谋")
}

///|
test "staff_duty 各参谋军职职责" {
  assert_eq(staff_duty("侦察参谋"), "情报搜集、可行性调研")
  assert_eq(staff_duty("后勤参谋"), "资源分配、池/模型调度")
  assert_eq(staff_duty("验收宪兵"), "交付验收、门禁把关")
  assert_eq(staff_duty("军务文书"), "记录、台账、日志归档")
  assert_eq(staff_duty("监察参谋"), "状态监察、异常上报")
  assert_eq(staff_duty("训练教官"), "规范/提示词编写、训练")
  assert_eq(staff_duty("未知"), "未知参谋军职")
}

///|
test "staff_hierarchy 各参谋军职挂靠体系" {
  assert_eq(staff_hierarchy("侦察参谋"), "Leader 体系 / Searcher 职能")
  assert_eq(staff_hierarchy("后勤参谋"), "Leader 体系 / Allocator 职能")
  assert_eq(staff_hierarchy("验收宪兵"), "Leader 体系 / Verifier 职能")
  assert_eq(staff_hierarchy("军务文书"), "Leader 体系 / Recorder 职能")
  assert_eq(staff_hierarchy("监察参谋"), "Leader 体系 / Observer 职能")
  assert_eq(
    staff_hierarchy("训练教官"),
    "Leader 体系 / SpecAuthor 职能",
  )
  assert_eq(staff_hierarchy("未知"), "未知挂靠体系")
}
