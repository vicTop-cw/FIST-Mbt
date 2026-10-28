// ============================================================================
// BUG-430 / S1 公告边界的锁（Lane AT）
//
// S1 做的是「让不安全变得可见」——**不是**「让它变得安全」。
// 判别标准：回执里必须能读出「这个 agent 是调用方自报的、服务端没验证过」。
//
// 为什么必须有锁（判例-29）：公告是**文案**，文案最容易被后来的「清理」删掉，
// 而删掉之后**没有任何测试会红**（回执仍然是一个字符串，仍然正确）。
// ⇒ 必须有格钉住这几个字。
//
// ⚠️ 判例-30 防护：本文件的断言用 `contains` 匹配**回执字符串**（运行时产物），
// 不是匹配源码文本 —— 所以不存在「模式串自己就在文件里」的自指假绿。
// ============================================================================

///|
/// 【锁 1（BUG-430 S1）】`rsv_set` 回执必须自证 `agent_source=self-reported`。
///
/// 这条钉的是：调用方从回执里能读到「agent 是自报的」。
/// 变异（把 `agent_source` 那段拼串删掉）⇒ 本格红。
test "bug430_s1_rsv_set_receipt_declares_agent_source" {
  let eng = FistEngine::new(store=@store.StoreBackend::memory())
  let r = eng.rsv_set(
    scope="scripts/x.py",
    agent="lane-at-probe",
    ttl_until="2099-01-01T00:00:00Z",
    created_at="2026-10-27T00:00:00Z",
  )
  match r {
    Err(e) => abort("rsv_set 应成功：" + e)
    Ok(o) => {
      assert_true(o.contains("agent_source=self-reported"))
      // ★ 措辞必须写「不安全」，不是「有说明」：
      //   回执里必须出现「无法验证」/「冒充」这类**否定性**表述，
      //   否则读者会读成「已知且已处理」。
      assert_true(o.contains("unverifiable") || o.contains("冒充"))
      // 且必须点名关闭条件（S3 之前不消除）
      assert_true(o.contains("S3"))
    }
  }
}

///|
/// 【锁 2（BUG-430 S1）】`rsv_try_set` 回执的 `action` 必须带 `+agent_self_reported`。
///
/// `RsvOutcome` 是 store 侧结构体、本层不能加字段 ⇒ 走 action 标签。
/// 变异（把 `+agent_self_reported` 后缀删掉）⇒ 本格红。
test "bug430_s1_rsv_try_set_action_declares_agent_source" {
  let eng = FistEngine::new(store=@store.StoreBackend::memory())
  let r = eng.rsv_try_set(
    scope="scripts/y.py",
    agent="lane-at-probe",
    ttl_until="2099-01-01T00:00:00Z",
    created_at="2026-10-27T00:00:00Z",
  )
  match r {
    Err(e) => abort("rsv_try_set 应成功：" + e)
    Ok(o) => {
      // 拿到锁（reserved）时必须带标签
      assert_true(o.reserved)
      assert_true(o.action.contains("+agent_self_reported"))
    }
  }
}

///|
/// 【锁 3（BUG-430 S1，**措辞锁定**）】回执不得只说「有说明」而不说「不安全」。
///
/// 这条是 S1 的**核心风险**所在（Alpha 的警告）：
/// 「写了说明」≠「安全了」，而写了说明**可能让人更放心**。
/// ⇒ 钉住「回执里必须同时出现『否定词』」——只写 `agent_source=self-reported`
/// 却不写「不能防冒充」是**不合格**的公告。
///
/// 变异：把「不能防有意的冒充」那半句删掉、只留字段名 ⇒ 本格红。
test "bug430_s1_receipt_must_say_insecure_not_merely_documented" {
  let eng = FistEngine::new(store=@store.StoreBackend::memory())
  let r = eng.rsv_set(
    scope="scripts/z.py",
    agent="lane-at-probe",
    ttl_until="2099-01-01T00:00:00Z",
    created_at="2026-10-27T00:00:00Z",
  )
  let o = match r {
    Err(e) => abort("rsv_set 应成功：" + e)
    Ok(o) => o
  }
  // ① 字段在（锁 1 已覆盖，这里再钉一次以防锁 1 被改弱）
  assert_true(o.contains("agent_source"))
  // ② **否定性措辞**必须在场：不能只说「有字段」，要说「挡不住」
  let has_negative = o.contains("unverifiable") ||
    o.contains("不能防") ||
    o.contains("冒充")
  if !has_negative {
    abort(
      "S1 公告不合格：回执只有字段名、没有说明「挡不住冒充」。" +
      "写了说明 ≠ 安全了 —— 只写文档反而让人更放心。实得：" +
      o,
    )
  }
  // ③ 关闭条件必须点名（否则读者以为这就是全部）
  assert_true(o.contains("S3"))
}
