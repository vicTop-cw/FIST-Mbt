///|
/// display/soldier_test.mbt —— 士兵分类展示层测试。
/// 真源：docs/2026-10-12-fist-mbt-web-dashboard-plan.md §8.2「士兵分类表」。

///|
test "soldier_types 含 8 兵种" {
  let types = soldier_types()
  assert_eq(types.length(), soldier_type_count())
  assert_eq(soldier_type_count(), 8)
  assert_eq(types[0], "侦查兵")
  assert_eq(types[3], "特种兵")
  assert_eq(types[7], "后勤兵")
}

///|
test "soldier_type_of 关键词命中" {
  assert_eq(soldier_type_of("情报搜集"), "侦查兵")
  assert_eq(soldier_type_of("可行性调研"), "侦查兵")
  assert_eq(soldier_type_of("搜索文档"), "侦查兵")
  assert_eq(soldier_type_of("大重构"), "炮兵")
  assert_eq(soldier_type_of("算法攻坚"), "炮兵")
  assert_eq(soldier_type_of("高价值关键任务"), "特种兵")
  assert_eq(soldier_type_of("紧急修复"), "特种兵")
  assert_eq(soldier_type_of("架构决策"), "特种兵")
  assert_eq(soldier_type_of("错误修复"), "医疗兵")
  assert_eq(soldier_type_of("故障恢复"), "医疗兵")
  assert_eq(soldier_type_of("消息同步"), "通信兵")
  assert_eq(soldier_type_of("状态汇报"), "通信兵")
  assert_eq(soldier_type_of("资源分配"), "后勤兵")
  assert_eq(soldier_type_of("文件归档"), "后勤兵")
  assert_eq(soldier_type_of("环境搭建"), "工兵")
  assert_eq(soldier_type_of("脚本编写"), "工兵")
  assert_eq(soldier_type_of("高频小任务"), "骑兵")
  assert_eq(soldier_type_of("批量琐事"), "骑兵")
}

///|
test "soldier_type_of 未知回退工兵" {
  assert_eq(soldier_type_of(""), "工兵")
  assert_eq(soldier_type_of("随便来点活"), "工兵")
}

///|
test "pool_label_of 兵种→模型池标签映射（§8.3）" {
  // 特种兵/炮兵走付费池重任务
  assert_eq(pool_label_of("特种兵"), "paid-premium")
  assert_eq(pool_label_of("炮兵"), "paid-flagship")
  // 侦查兵/骑兵/通信兵走免费池轻任务
  assert_eq(pool_label_of("侦查兵"), "free-fast")
  assert_eq(pool_label_of("骑兵"), "free-mid")
  assert_eq(pool_label_of("通信兵"), "free-fast")
  // 其余走通用池
  assert_eq(pool_label_of("工兵"), "free-general")
  assert_eq(pool_label_of("医疗兵"), "free-mid")
  assert_eq(pool_label_of("后勤兵"), "free-general")
}

///|
test "soldier_mission 各兵种攻坚任务类型" {
  assert_eq(
    soldier_mission("侦查兵"),
    "情报搜集 / 可行性调研 / 搜索与文档速读",
  )
  assert_eq(
    soldier_mission("炮兵"),
    "大重构 / 算法攻坚 / 疑难排障",
  )
  assert_eq(
    soldier_mission("特种兵"),
    "高价值关键任务 / 紧急修复 / 架构决策",
  )
  assert_eq(
    soldier_mission("工兵"),
    "环境搭建 / 依赖修复 / 脚本编写",
  )
  assert_eq(
    soldier_mission("医疗兵"),
    "错误修复 / 故障恢复 / 数据抢救",
  )
  assert_eq(
    soldier_mission("通信兵"),
    "消息同步 / 状态汇报 / 提醒",
  )
  assert_eq(
    soldier_mission("后勤兵"),
    "文件整理 / 资源分配 / 归档",
  )
  assert_eq(soldier_mission("未知"), "未知兵种")
}

///|
test "soldier_model_tier 各兵种模型档位" {
  assert_eq(
    soldier_model_tier("特种兵"),
    "最强模型（白名单专属）",
  )
  assert_eq(soldier_model_tier("炮兵"), "强力模型（LongCat/旗舰）")
  assert_eq(soldier_model_tier("侦查兵"), "便宜快速模型")
  assert_eq(soldier_model_tier("骑兵"), "低延迟中端模型")
  assert_eq(soldier_model_tier("通信兵"), "快速模型")
  assert_eq(soldier_model_tier("工兵"), "通用模型")
  assert_eq(soldier_model_tier("医疗兵"), "中端模型")
  assert_eq(soldier_model_tier("后勤兵"), "通用模型")
}

///|
test "soldier_type_of 英文关键词" {
  assert_eq(soldier_type_of("search"), "侦查兵")
  assert_eq(soldier_type_of("research"), "侦查兵")
  assert_eq(soldier_type_of("refactor"), "炮兵")
  assert_eq(soldier_type_of("critical bug"), "特种兵")
  assert_eq(soldier_type_of("urgent fix"), "特种兵")
}

///|
test "soldier_type_of 大小写不敏感" {
  assert_eq(soldier_type_of("SEARCH"), "侦查兵")
  assert_eq(soldier_type_of("Refactor"), "炮兵")
  assert_eq(soldier_type_of("URGENT"), "特种兵")
}
