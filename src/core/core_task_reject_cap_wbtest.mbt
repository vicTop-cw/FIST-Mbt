/// core_task_reject_cap_wbtest.mbt —— BUG-427 的成对锁：打回原因不许无上限增长。
///
/// 缺陷原形：`Task::reject` 每次都在 `description` 尾巴拼一段 ` [打回原因: …]`，
/// **存储面无任何长度闸**（`desc_clip` 只在 `to_json` 输出时截断）。
///
/// 实测：`T0r636.4.2` **单次打回即 4737 字节**。
///
/// 污染面（description 是三处功能的共同进料面）：
///   · `task_triage` 的能力抽取 —— `cap_match` 用 `desc.contains(want)`
///   · `goal_drift_check` 的 Jaccard —— `@evolve.tokens(get_description())`
///   · `supervisor_status` 的 200 字节截断 —— 真正有用的前 200 字节之外全废
///
/// 本文件钉三件事：
///   ① 单条原因被截断到 `REJECT_REASON_CAP`（不因一条巨长原因炸开）
///   ② 打回 N 次后 description 长度**不线性增长**（滚动窗口只留最近 1 次）
///   ③ 原始 description 内容**不被破坏**（剥尾巴只剥自己拼的那段）

///|
/// 造一个「待验收」的任务（reject 的前置状态）。
fn rc_reviewing(desc : String) -> Task {
  let t = Task::new(
    id="RC-1",
    project_dir=".",
    description=desc,
    assignee="exec-1",
  )
  let c = match t.claim(assignee="exec-1") {
    Ok(x) => x
    Err(e) => abort("claim 失败：" + e)
  }
  let ex = match c.execute() {
    Ok(x) => x
    Err(e) => abort("execute 失败：" + e)
  }
  match ex.submit() {
    Ok(x) => x
    Err(e) => abort("submit 失败：" + e)
  }
}

///|
/// 锁 1：单条超长原因 ⇒ 被截断到 `REJECT_REASON_CAP` 附近
///
/// 若把 `clip_utf8(reason, REJECT_REASON_CAP)` 退回裸 `reason`，本格必红。
test "bug427_long_reason_is_clipped" {
  let base = "原始任务描述"
  let t = rc_reviewing(base)
  // 一条远超上限的原因（约 2000 字节）
  let long_reason = "很长的打回原因".repeat(200)
  let r = match t.reject(reason=long_reason) {
    Ok(x) => x
    Err(e) => abort("reject 失败：" + e)
  }
  let added = r.get_description().length() - base.length()
  // 固定开销 = " [打回原因: " (10 字节) + "]" (1 字节) = 11
  let overhead = " [打回原因: ".length() + 1
  let limit = REJECT_REASON_CAP + overhead
  if added > limit {
    fail(
      "BUG-427 未修：单条打回增量 " +
      added.to_string() +
      " 字节 > 上限 " +
      limit.to_string(),
    )
  }
  // 原始描述必须完整保留
  if !(r.get_description().has_prefix(base)) {
    fail("原始描述被破坏：应以 '" + base + "' 开头")
  }
}

///|
/// 锁 2（**核心**）：打回 5 次后 description 长度**不线性增长**
///
/// 这是滚动窗口的判据：若把 `strip_reject_tail(...)` 去掉（退回无窗口版），
/// 每次打回都会再拼一段 ⇒ 长度随次数线性增长 ⇒ 本格必红。
test "bug427_repeated_reject_does_not_grow_linearly" {
  let base = "原始任务描述"
  let mut t = rc_reviewing(base)
  let reason = "第 N 次打回的原因说明" // 约 30 字节
  let mut len1 = 0
  let mut len5 = 0
  for i in 1..<=5 {
    let r = match t.reject(reason=reason + i.to_string()) {
      Ok(x) => x
      Err(e) => abort("第 " + i.to_string() + " 次 reject 失败：" + e)
    }
    // reject 之后必须能 retry 回执行中，才能再 submit/reject
    let back = match r.retry() {
      Ok(x) => x
      Err(e) => abort("retry 失败：" + e)
    }
    let sub = match back.submit() {
      Ok(x) => x
      Err(e) => abort("重新 submit 失败：" + e)
    }
    t = sub
    if i == 1 {
      len1 = r.get_description().length()
    }
    if i == 5 {
      len5 = r.get_description().length()
    }
  }
  // 滚动窗口下，第 5 次与第 1 次长度差应极小（只差序号字符）
  // 无窗口版会差 ~4 × 30 = 120 字节
  let diff = if len5 > len1 { len5 - len1 } else { len1 - len5 }
  if diff > 20 {
    fail(
      "BUG-427 未修：打回 5 次后长度增长 " +
      diff.to_string() +
      " 字节（第1次 " +
      len1.to_string() +
      "，第5次 " +
      len5.to_string() +
      "）⇒ 滚动窗口没生效",
    )
  }
}

///|
/// 锁 3（对照）：**不含**打回原因的描述不被 `strip_reject_tail` 误伤
///
/// 防「为了剥尾巴把正常描述也截了」。
test "bug427_plain_description_untouched" {
  let base = "一个正常任务描述，没有任何打回历史"
  let t = rc_reviewing(base)
  let r = match t.reject(reason="第一次打回") {
    Ok(x) => x
    Err(e) => abort("reject 失败：" + e)
  }
  if !(r.get_description().has_prefix(base)) {
    fail("原始描述被误伤")
  }
  // 尾巴必须是新拼的那段
  if !(r.get_description().contains("[打回原因: 第一次打回]")) {
    fail("打回原因没进 description")
  }
}

///|
/// 锁 4（变异对照，判例-29）：直接断言 `strip_reject_tail` 真被 `reject` 调用
///
/// 只断言「长度没长出」不足以防「有人把窗口逻辑删了但恰好测试次数不够」——
/// 这格钉住实现里那次调用真在。
test "bug427_strip_tail_wired" {
  let src = @fs.read_file_to_string("src/core/core_task.mbt", encoding="utf8") catch {
    _ =>
      abort("读 src/core/core_task.mbt 失败：接线格没跑到被测面")
  }
  assert_true(src.contains("strip_reject_tail(self.description)"))
  assert_true(src.contains("clip_utf8(reason, REJECT_REASON_CAP)"))
}

///|
/// 锁 5（R137）：**`clip_utf8` 的 CJK 边界行为** —— 本仓打回原因全是中文。
///
/// 为什么补这格：本文件前 4 格**全是 ASCII**（`"x"` 重复串），而 `clip_utf8` 按**字节**截断；
/// 同族的 `desc_clip` 有「中文业主证」（`core_task_desc_clip_wbtest.mbt` 的 `dc_*`），`clip_utf8` 此前**没有**。
///
/// ⚠️ **实测：本格锁的是"行为"，不能当 continuation 回退的变异对照**（老实记下来）：
/// 把 `clip_utf8` 里的回退 `while` 整段删掉，本格**仍然绿** —— 因为
/// `@encoding.decode_to` 对不完整尾字节会**静默丢弃**（`catch` 都不触发），
/// 于是 `bytes[0:7]` 与被回退后的 `bytes[0:6]` 解出来的字符串**相同**。
/// ⇒ 那段回退是**防御性冗余**（显式表达意图），不是可观测的行为差异。
/// 能作为它变异对照的断言必须直接看**字节下标**（`cut` 落在字符起始），而 `cut` 是局部变量。
test "clip_utf8_cjk_boundary_is_safe" {
  // 「一二三四五六七八九十」= 10 个 3 字节字符（共 30 字节）
  let s = "一二三四五六七八九十"
  // 上限 7 落在第 3 个字符中间 ⇒ 必须回退到 6（2 个完整字符）
  assert_eq(clip_utf8(s, 7), "一二")
  // 上限正好落在字符边界 ⇒ 不回退
  assert_eq(clip_utf8(s, 6), "一二")
  // 上限不小于全串 ⇒ 原样返回
  assert_eq(clip_utf8(s, 30), s)
  assert_eq(clip_utf8(s, 99), s)
  // 混合中英：`a`(1) + `一`(3) + `二`(3)；上限 3 落在「一」中间 ⇒ 回退到 1 ⇒ 只剩 "a"
  assert_eq(clip_utf8("a一二", 3), "a")
  // 上限 4 正好是 `a` + 完整「一」的边界 ⇒ "a一"
  assert_eq(clip_utf8("a一二", 4), "a一")
}
