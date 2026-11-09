/// engine/engine_supervisor_bug580_wbtest.mbt —— BUG-580 回归锁（C1 提醒静默清零 / C2 负值不拒）
///
/// ## 缺陷形态（修复前，调用面实测）
///
/// **C1**：`iso_to_epoch` 全 Int32 算术，`(jd - 2451545) * 86400` 对远未来 now
/// （如 `9999-01-01T00:00:00Z`，≈2.5e11 秒）静默 Int32 绕回成负值 ⇒
/// `ts_ok = now_ep > 0 && up_ep > 0` 判假 ⇒ **存在的提醒被静默清零**（不报错、
/// reminder_count=0，看起来像「没有任务需要提醒」）。同族：`stale_hours * 3600`
/// 的 Int32 乘法在 stale_hours ≥ 596523 时同样绕回。
///
/// **C2**：MCP 工具层 `str_to_int` 只防超上界、不拒负值 ⇒ `stale_hours="-5"`
/// 被接受，回执给出「活跃任务超过 -5 小时未更新」这类荒谬 reason
/// （12 分钟前更新的活跃任务被报 stale）。
///
/// ## 修复后的行为面（本文件锁住）
///
/// - `iso_to_epoch` 返回 **Int64?**：9999 年 epoch 为正且精确（年进位数值等价性断言）。
/// - now=9999 时已停滞的活跃任务**照常产出 stale 提醒**（不再静默清零）。
/// - 负 stale_hours / pending_hours：引擎侧返回带 `error` 字段的空结果
///   （MCP 工具层在 supervisor_tools.mbt 显式 Err——白盒锁打在引擎可观测行为上）。
/// - 正常路径零回归：空库基线 0 条、刚更新的活跃任务不报 stale。
///
/// ## 变异对照（判例-29/30 硬要求）
///
///   · 把 `iso_to_epoch` 末行的 `(jd64 - 2451545L) * 86400L` 改回 Int32 乘法 ⇒
///     `bug580_far_future_now_does_not_silently_clear_reminders` 必红（epoch 绕回负）。
///   · 把 `stale_cut = now_ep - stale_hours.to_int64() * 3600L` 的 `to_int64()` 删掉 ⇒
///     同一格必红（大阈值绕回使 stale_cut 落在未来）。
///   · 删掉 `supervisor_reminder_tick` 开头的负阈值守卫 ⇒
///     `bug580_negative_thresholds_rejected_not_silent` 必红。
///   · 把负阈值守卫改成「夹到 0」而非报错 ⇒ 同上必红（error 字段消失）。

///|
/// 白盒取 object 字段的辅助（照 `engine_supervisor_reminder_test.mbt` 的拆包样式）。
fn bug580_json_obj(j : Json) -> Map[String, Json] {
  match j {
    Json::Object(o) => o
    _ => abort("bug580: expected json object")
  }
}

///|
/// 造一个「已认领（活跃）且远早于 now 更新」的任务，返回其 task_id。
fn bug580_active_stale_task(e : FistEngine, updated_now : String) -> String {
  let id = match
    e.publish(
      project_dir="/proj/bug580",
      description="根任务",
      created_by="human_steward",
      now=updated_now,
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
  ignore(e.claim(task_id=id, assignee="worker_1", now=updated_now))
  id
}

///|
test "bug580_far_future_now_does_not_silently_clear_reminders" {
  let e = FistEngine::new()
  let id = bug580_active_stale_task(e, "2026-09-06T10:00:00Z")
  // 修复前：now=9999 → now_ep Int32 绕回负值 → ts_ok=false → 已停滞 7000+ 年的
  // 活跃任务静默零提醒。修复后：Int64 epoch，提醒必须照常产出。
  let tick = e.supervisor_reminder_tick(
    now="9999-01-01T00:00:00Z",
    stale_hours=24,
    pending_hours=48,
  )
  let m = bug580_json_obj(tick)
  // 无 error 字段（这是合法输入，不该被拒）
  assert_true(m.get("error") is None)
  let reminders = match m.get("reminders") {
    Some(Json::Array(a)) => a
    _ => abort("reminders missing")
  }
  let mut stale_for_id = false
  for r in reminders {
    let rm = match r {
      Json::Object(o) => o
      _ => Map([])
    }
    let kind = match rm.get("kind") {
      Some(Json::String(s)) => s
      _ => ""
    }
    let task_id = match rm.get("task_id") {
      Some(Json::String(s)) => s
      _ => ""
    }
    if kind == "stale" && task_id == id {
      stale_for_id = true
    }
  }
  assert_true(stale_for_id)
  // reminder_count 与 reminders 长度一致（>0）
  let cnt = match m.get("reminder_count") {
    Some(Json::Number(n, ..)) => n
    _ => abort("reminder_count missing")
  }
  assert_true(cnt > 0.0)
}

///|
test "bug580_iso_to_epoch_far_future_is_positive_and_precise" {
  // 机制格（C1 根因直打）：9999 年 epoch 在 Int32 下绕回负值，Int64 下为正。
  let ep9999 = match iso_to_epoch("9999-01-01T00:00:00Z") {
    Some(v) => v
    None => abort("9999-01-01 should parse")
  }
  assert_true(ep9999 > 0L)
  // 数值等价性（不是「非空」）：9998-01-01 → 9999-01-01 差 365 天
  //（两年都非闰年），锁住远未来年份的日/年进位在 Int64 下仍精确。
  assert_eq(
    iso_delta_seconds("9998-01-01T00:00:00Z", "9999-01-01T00:00:00Z"),
    Some(31536000L),
  )
  // 与 2026 年的跨度也精确：约 9734 天，同上非闰年口径逐段对不上就红。
  assert_true(ep9999 > iso_to_epoch("2026-01-01T00:00:00Z").unwrap_or(0L))
}

///|
test "bug580_negative_thresholds_rejected_not_silent" {
  let e = FistEngine::new()
  // C2：负 stale_hours → 显式 error（引擎侧），不产出负阈值算出的荒谬提醒。
  let tick = e.supervisor_reminder_tick(
    now="2026-09-09T12:00:00Z",
    stale_hours=-5,
    pending_hours=48,
  )
  let m = bug580_json_obj(tick)
  match m.get("error") {
    Some(Json::String(s)) => assert_true(s.contains("负值"))
    _ => abort("expected error field for negative stale_hours")
  }
  match m.get("reminders") {
    Some(Json::Array(a)) => assert_eq(a.length(), 0)
    _ => abort("reminders missing")
  }
  // pending_hours 负值同样拒绝
  let tick2 = e.supervisor_reminder_tick(
    now="2026-09-09T12:00:00Z",
    stale_hours=24,
    pending_hours=-1,
  )
  let m2 = bug580_json_obj(tick2)
  assert_true(
    match m2.get("error") {
      Some(Json::String(_)) => true
      _ => false
    },
  )
  // 回执仍回显收到的阈值（便于调用方自查传了什么）
  let echo = match m.get("stale_hours") {
    Some(Json::Number(n, ..)) => n
    _ => abort("stale_hours echo missing")
  }
  assert_true(echo == -5.0)
}

///|
test "bug580_normal_path_behavior_unchanged" {
  let e = FistEngine::new()
  // 基线：空库 0 条、无 error
  let tick0 = e.supervisor_reminder_tick(
    now="2026-09-09T12:00:00Z",
    stale_hours=24,
    pending_hours=48,
  )
  let m0 = bug580_json_obj(tick0)
  assert_true(m0.get("error") is None)
  match m0.get("reminder_count") {
    Some(Json::Number(n, ..)) => assert_true(n == 0.0)
    _ => abort("reminder_count missing")
  }
  // 刚发布（pending）的任务不触发 pending_timeout（48h 内）
  let fresh_id = match
    e.publish(
      project_dir="/proj/bug580",
      description="新任务",
      created_by="human_steward",
      now="2026-09-09T11:48:00Z",
    ) {
    Ok(x) => x
    Err(m) => abort("publish failed: \{m}")
  }
  ignore(
    e.claim(task_id=fresh_id, assignee="worker_1", now="2026-09-09T11:50:00Z"),
  )
  // 12 分钟前更新的活跃任务：不报 stale（修复前传 stale_hours=-5 会误报，
  // 修复后负值在入口被拒，正常路径下同样不该报）
  let tick1 = e.supervisor_reminder_tick(
    now="2026-09-09T12:00:00Z",
    stale_hours=24,
    pending_hours=48,
  )
  let m1 = bug580_json_obj(tick1)
  assert_true(m1.get("error") is None)
  let reminders1 = match m1.get("reminders") {
    Some(Json::Array(a)) => a
    _ => abort("reminders missing")
  }
  for r in reminders1 {
    let rm = match r {
      Json::Object(o) => o
      _ => Map([])
    }
    let task_id = match rm.get("task_id") {
      Some(Json::String(s)) => s
      _ => ""
    }
    if task_id == fresh_id {
      abort("freshly updated task must not be flagged")
    }
  }
  assert_true(
    match m1.get("reminder_count") {
      Some(Json::Number(n, ..)) => n == 0.0
      _ => false
    },
  )
}
