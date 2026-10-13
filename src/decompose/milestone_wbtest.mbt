// 里程碑式渐进拆解白盒测试（L35）

///|
test "generate_milestones 3 阶段" {
  let plan = generate_milestones(parent_desc="实现登录模块", 3)
  assert_eq(plan.total, 3)
  assert_eq(plan.milestones.length(), 3)
  // 第一个里程碑无依赖，后续依赖前一个
  assert_eq(plan.milestones[0].depends_on.length(), 0)
  assert_eq(plan.milestones[1].depends_on[0], 0)
  assert_eq(plan.milestones[2].depends_on[0], 1)
}

///|
test "generate_milestones 5 阶段" {
  let plan = generate_milestones(parent_desc="实现支付系统", 5)
  assert_eq(plan.total, 5)
  assert_eq(plan.milestones.length(), 5)
  // 全链依赖
  let mut i = 1
  while i < 5 {
    assert_eq(plan.milestones[i].depends_on.length(), 1)
    assert_eq(plan.milestones[i].depends_on[0], i - 1)
    i = i + 1
  }
}

///|
test "generate_milestones 边界：split_n 小于 3 强制 3" {
  let plan = generate_milestones(parent_desc="测试", 1)
  assert_eq(plan.total, 3)
}

///|
test "generate_milestones 边界：split_n 大于 5 截断到 5" {
  let plan = generate_milestones(parent_desc="测试", 10)
  assert_eq(plan.total, 5)
}

///|
test "refine_milestone 生成子任务" {
  let plan = generate_milestones(parent_desc="实现搜索", 3)
  let subs = refine_milestone(plan.milestones[0], 3)
  assert_eq(subs.length(), 3)
  // 子任务标题应包含里程碑标题
  assert_true(subs[0].contains(plan.milestones[0].title))
}

///|
test "validate_milestone_plan 合法计划通过" {
  let plan = generate_milestones(parent_desc="测试", 4)
  let (ok, msg) = validate_milestone_plan(plan)
  assert_true(ok)
  assert_eq(msg, "")
}

///|
test "validate_milestone_plan 检测依赖越界" {
  // 构造一个非法计划：里程碑1 依赖里程碑99
  let ms = Milestone::{
    index: 0,
    title: "a",
    description: "a",
    depends_on: [],
  }
  let bad = Milestone::{
    index: 1,
    title: "b",
    description: "b",
    depends_on: [99],
  }
  let plan = MilestonePlan::{ milestones: [ms, bad], total: 2, }
  let (ok, msg) = validate_milestone_plan(plan)
  assert_false(ok)
  assert_true(msg.contains("越界"))
}

///|
test "milestone_progress 全未完成=0" {
  let plan = generate_milestones(parent_desc="测试", 3)
  let p = milestone_progress(plan, [false, false, false])
  assert_eq(p, 0.0)
}

///|
test "milestone_progress 全完成=1" {
  let plan = generate_milestones(parent_desc="测试", 4)
  let p = milestone_progress(plan, [true, true, true, true])
  assert_eq(p, 1.0)
}

///|
test "milestone_progress 部分完成" {
  let plan = generate_milestones(parent_desc="测试", 4)
  let p = milestone_progress(plan, [true, false, true, false])
  assert_eq(p, 0.5)
}

///|
test "milestone_ascii 输出非空" {
  let plan = generate_milestones(parent_desc="实现模块X", 3)
  let ascii = milestone_ascii(plan)
  assert_true(ascii.length() > 0)
  assert_true(ascii.contains("M1"))
  assert_true(ascii.contains("M3"))
}

///|
test "milestone_plan_to_json 合法 JSON" {
  let plan = generate_milestones(parent_desc="测试", 3)
  let json = milestone_plan_to_json(plan)
  assert_true(json.contains("\"total\":3"))
  assert_true(json.contains("\"milestones\""))
  assert_true(json.contains("\"index\":0"))
}
