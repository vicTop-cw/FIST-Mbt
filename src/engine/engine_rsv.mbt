/// engine/engine_rsv.mbt —— 作用域预订 + 权限门禁（拿来主义：Interlinked 文件预订 → 多 agent 并发冲突预防）
///
/// 转发到后端 StoreBackend 的 rsv_*，供 server 工具统一走引擎，避免跨层直接摸 store。
///
/// 权限门禁（2026-10-21 BUG-多 agent 合并冲突修复）：
///   在"先到先得"的预订/锁之前，先过 engine_scope_perm 的"你有没有资格改这个目录"硬门。
///   不是防并发——是防越权。就像军队里炊事员不能进指挥中心，不是因为有人，是因为没资格。

///|
pub fn FistEngine::rsv_set(
  self : FistEngine,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[String, String] {
  // 权限门禁：先过权限，再预订（BUG-413 三态分流）
  //
  // BUG-418：角色**先查权威面 `agents.role`**（显式声明），查不到才退到收窄后的推断。
  // 旧实现只用名字推断 ⇒ 自称 `commander-*` 即可拿 HumanSteward（可主动利用的越权面）。
  //
  // ⚠️ 关键陷阱：`agents.agent_id` 是 16 位指纹（`@omega.fnv1a64("agent_id:" + raw)`），
  // 而这里收到的是调用方自由填的**原始名** ⇒ 必须自己算指纹再查，
  // 直接传原始名永远查不到（那会让 (a) 静默失效，等于只做了 (b)）。
  let declared = match self.agents_get(agent_fp_of(agent)) {
    None => None
    Some(rec) => Some(rec.role)
  }
  // BUG-422：角色来源**必须带进回执**（诚实标注）。
  //
  // `role_source` 的值域：
  //   "declared"   = 从 `agents` 表读到的 —— **但查表键是调用方自报的名字**，
  //                  所以「declared」不等于「可信」，只等于「不是从名字模式推的」。
  //                  报一个已登记身份的名字（如 `fist-mbt`）即可继承它的 role（BUG-422 本尊）。
  //   "inferred"   = 从名字模式推的 —— 更不可信（BUG-421：整名 `leader`/`lead` 仍买到军官面）
  //
  // 为什么不直接返回 `Result` 让调用方区分：`rsv_set` 的签名是 `Result[String, String]`，
  // 改签名会波及工具面 3 处调用方。所以用**后缀标注** —— 零签名变更，且回执自带证据。
  let (role, role_source) = resolve_agent_role(agent, declared)
  match check_scope_permission(scope, role) {
    // RoleDenied 是**硬拒** —— HumanSteward 保护路径必须继续拒绝，绝不放行
    RoleDenied(e) => Err(e)
    // Allowed 与 Unregistered 都放行到后端登记：
    //   Allowed      = 已登记且够格（原行为）
    //   Unregistered = 未登记 ⇒ advisory 登记，不参与授权裁决
    Allowed | Unregistered(_) =>
      match self.store.rsv_set(scope~, agent~, ttl_until~, created_at~) {
        Err(e) => Err(e)
        Ok(o) => Ok(o + " [role_source=" + role_source + "]")
      }
  }
}

///|
/// 按裁决抢预订（BUG-136）：互斥由后端定，工具面只渲染结论——不许在这里先读后写。
/// 额外加了权限门禁（engine_scope_perm）：没有编辑资格的角色不许抢预订。
pub fn FistEngine::rsv_try_set(
  self : FistEngine,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
) -> Result[@store.RsvOutcome, String] {
  // 权限门禁：先过权限，再进后端裁决（BUG-413 三态分流）
  // BUG-418：角色先查权威面 `agents.role`（同上，必须自己算指纹）。
  let declared = match self.agents_get(agent_fp_of(agent)) {
    None => None
    Some(rec) => Some(rec.role)
  }
  // BUG-422：角色来源带进回执的 `action`（与 rsv_set 同口径，见那边的长注释）。
  // `action` 的合法取值因此扩展为：reserved | renewed | taken_over | conflict |
  //   unregistered | <上述之一>+role_inferred
  let (role, role_source) = resolve_agent_role(agent, declared)
  match check_scope_permission(scope, role) {
    RoleDenied(e) => Err(e)
    Allowed =>
      match self.store.rsv_try_set(scope~, agent~, ttl_until~, created_at~) {
        Err(e) => Err(e)
        Ok(o) =>
          Ok(
            if role_source == "inferred" {
              // 只在 inferred 时打标：declared 是「查到了表」但仍不可信（BUG-422 本尊），
              // 两个都标会让标签失去区分力。inferred 才是「连表都没查到」的那一档。
              o.relabel(o.action + "+role_inferred")
            } else {
              o
            },
          )
      }
    Unregistered(_) =>
      // 仍走后端裁决：同一未登记 scope 上两个 lane 抢，照样要判 conflict。
      // 区别只在 action 标签——调用方据此知道「这不是授权通过，是登记通过」。
      match self.store.rsv_try_set(scope~, agent~, ttl_until~, created_at~) {
        Err(e) => Err(e)
        // advisory 只在**真拿到**时打标；conflict 保持 conflict（那条信息更硬）
        Ok(o) =>
          Ok(
            if o.reserved {
              o.relabel(
                "unregistered" +
                (if role_source == "inferred" { "+role_inferred" } else { "" }),
              )
            } else {
              o
            },
          )
      }
  }
}

///|
pub fn FistEngine::rsv_get(
  self : FistEngine,
  scope : String,
) -> (String, String, String)? {
  self.store.rsv_get(scope)
}

///|
pub fn FistEngine::rsv_release(
  self : FistEngine,
  scope : String,
  agent : String,
) -> Bool {
  self.store.rsv_release(scope, agent)
}

///|
pub fn FistEngine::rsv_list(
  self : FistEngine,
) -> Array[(String, String, String)] {
  self.store.rsv_list()
}

// —— 分布式文件锁（引擎层转发到 StoreBackend）——

///|
pub fn FistEngine::locks_upsert(
  self : FistEngine,
  lock : @store.FileLock,
) -> Unit {
  self.store.locks_upsert(lock)
}

///|
/// 按裁决抢锁（BUG-145）：互斥由后端定，工具面只渲染结论——不许在这里先读后写。
/// 注：锁的权限门禁**暂时没接**——LockAcquireOutcome 是 read-only 类型，
/// 必须在 store 内部创建；将来会在 store_rsv 层加一个 permission_denied 构造器。
/// 目前先跳过锁的权限检查，等后端扩展。
pub fn FistEngine::locks_try_acquire(
  self : FistEngine,
  lock : @store.FileLock,
) -> @store.LockAcquireOutcome {
  self.store.locks_try_acquire(lock)
}

///|
pub fn FistEngine::locks_get(
  self : FistEngine,
  scope : String,
) -> @store.FileLock? {
  self.store.locks_get(scope)
}

///|
pub fn FistEngine::locks_list(self : FistEngine) -> Array[@store.FileLock] {
  self.store.locks_list()
}

///|
pub fn FistEngine::locks_release(
  self : FistEngine,
  scope : String,
  agent : String,
) -> Bool {
  self.store.locks_release(scope, agent)
}

///|
pub fn FistEngine::locks_sweep(self : FistEngine, now : String) -> Int32 {
  self.store.locks_sweep(now)
}

///|
pub fn FistEngine::lock_violations_list(
  self : FistEngine,
) -> Array[@store.LockViolation] {
  self.store.lock_violations_list()
}
