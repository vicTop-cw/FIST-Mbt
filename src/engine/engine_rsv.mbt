/// engine/engine_rsv.mbt —— 作用域预订 + 权限门禁（拿来主义：Interlinked 文件预订 → 多 agent 并发冲突预防）
///
/// 转发到后端 StoreBackend 的 rsv_*，供 server 工具统一走引擎，避免跨层直接摸 store。
///
/// 权限门禁（2026-10-21 BUG-多 agent 合并冲突修复）：
///   在"先到先得"的预订/锁之前，先过 engine_scope_perm 的"你有没有资格改这个目录"硬门。
///   不是防并发——是防越权。就像军队里炊事员不能进指挥中心，不是因为有人，是因为没资格。

///|
/// 权限门禁的**角色取数**单一真源（BUG-418 (a) + BUG-422 B 案）。
///
/// 三条门（`rsv_set` / `rsv_try_set` / `locks_try_acquire`）都必须走这里，不许各写一份：
/// 旧实现三处各抄一遍 `agents_get(agent_fp_of(agent)).role`，改一处漏两处就是半个越权口。
///
/// **⚠️ 关键陷阱（BUG-418 实测）**：`agents.agent_id` 是 16 位指纹
/// （`@omega.fnv1a64("agent_id:" + raw)`），而这里收到的是调用方自由填的**原始名**
/// ⇒ 必须自己算指纹再查，直接传原始名永远查不到（那会让权威面静默失效，等于没接）。
///
/// **⚠️ BUG-422：必须走 `agents_role_for_judgment` 而不是 `agents_get(...).role`**。
/// 后者的查表键是调用方自报的名字，而 `agents` 表里唯一的高角色记录恰好是
/// **server 进程给自己登记的那一条**（`agent_type="server"`、`role="Leader"`，
/// `server.mbt` 的 `make_engine()` 写的）⇒ 报 `agent="fist-mbt"` 直接继承 Leader 面
/// （实测 ALLOWED on `src/engine/` · `src/core/`）。
/// `agents_role_for_judgment` 把这类「本进程自身份」记录**整条剔除** ⇒ 不再可被冒用。
///
/// 内存后端没有 agents 表 ⇒ None（只剩名字推断；BUG-421 后推断最高只到整名
/// `human_steward`/`human`，军官单词 `leader`/`lead` 已不再提权）。
fn declared_role_for_judgment(eng : FistEngine, agent : String) -> String? {
  match eng.store.sqlite_store() {
    None => None
    Some(s) => s.agents_role_for_judgment(agent_fp_of(agent))
  }
}

///|
/// **裁决角色 + 来源的唯一取数面**（BUG-432 收口）。
///
/// 四条门（`rsv_set` / `rsv_try_set` / `locks_try_acquire` / **`claim` 的 RANK_GATE**）
/// 一律只准走这里，**不许各写一份 `resolve_agent_role(...)`**：
/// BUG-432 正是「同一语义（名字 → 身份）在 claim 侧长出了第二个实现（`estimate_rank`）」，
/// 而 BUG-418/421/422 三轮收口全漏 —— 把取数面收成**一个函数**，是让下一道门
/// **没有地方**再分叉。要加新门，请复用本函数，不要新造判据。
///
/// 返回 `(role, role_source)`，语义见 `resolve_agent_role`：
///   · `role` ∈ {`HumanSteward`, `Leader`, `Executor`}
///   · `role_source` = `"declared"` | `"inferred"`（`"declared"` 只表示「有一条通过过滤的
///     登记记录」，**不表示已核验** —— 见 `agents_role_for_judgment` 的诚实边界）
fn judged_role(eng : FistEngine, agent : String) -> (String, String) {
  resolve_agent_role(agent, declared_role_for_judgment(eng, agent))
}

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
  // BUG-422：查表改走 `declared_role_for_judgment`（剔除 server 自身份），见其长注释。
  // BUG-432：连「查表 + 推断」这一步也收进 `judged_role`（四条门共用，见该函数注释）。
  // BUG-422：角色来源**必须带进回执**（诚实标注）。
  //
  // `role_source` 的值域：
  //   "declared"   = 来自一条**通过裁决过滤的**登记记录（非 server 自身份、角色可继承、
  //                  且不低于名字推断）。它仍是**未核验**的自报身份 —— 「declared」只说明
  //                  「不是从名字模式推的」，不说明「已核验」。
  //                  现存残余：报一个**非 server 类型**且被显式授予 Leader 的登记名仍可继承
  //                  （现网该类记录 0 条；详见 `agents_role_for_judgment` 的诚实边界）。
  //   "inferred"   = 从名字模式推的（或声明被过滤/不可继承）—— 更不可信；
  //                  BUG-421 后推断最高只到整名 `human_steward`/`human`。
  //
  // 为什么不直接返回 `Result` 让调用方区分：`rsv_set` 的签名是 `Result[String, String]`，
  // 改签名会波及工具面 3 处调用方。所以用**后缀标注** —— 零签名变更，且回执自带证据。
  let (role, role_source) = judged_role(self, agent)
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
  // BUG-422：查表走 `declared_role_for_judgment`（剔除 server 自身份，见其长注释）。
  // BUG-432：该步已并入 `judged_role`（四条门共用取数面）。
  // BUG-422：角色来源带进回执的 `action`（与 rsv_set 同口径，见那边的长注释）。
  // `action` 的合法取值因此扩展为：reserved | renewed | taken_over | conflict |
  //   unregistered | <上述之一>+role_inferred
  let (role, role_source) = judged_role(self, agent)
  match check_scope_permission(scope, role) {
    RoleDenied(e) => Err(e)
    Allowed =>
      match self.store.rsv_try_set(scope~, agent~, ttl_until~, created_at~) {
        Err(e) => Err(e)
        Ok(o) =>
          Ok(
            if role_source == "inferred" {
              // 只在 inferred 时打标：declared 说明「有一条通过过滤的登记记录」，
              // 两个都标会让标签失去区分力。inferred 才是「没有可用声明」的那一档
              // （未登记 / 被 BUG-422 过滤 / 角色不可继承 / 低于推断）。
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
///
/// **BUG-424：权限门已接**（原注释称「暂时没接」，写于 2026-10-22、挂了 4 天）。
/// 拆解那个「技术障碍」，两条都要纠正：
///   · 「`LockAcquireOutcome` 是 read-only 类型」—— **说法不成立**：字段只是**包内私有**
///     （跨包写 literal 被编译器拒，BUG-413 已实测 4036/4033），与 read-only 无关；
///     而 BUG-413 早就用 `RsvOutcome::relabel` 解决过同一个障碍，只是没人回头看这条注释。
///   · 「必须在 store 内部创建」—— 对，但 store 侧已补
///     `LockAcquireOutcome::denied_by_permission()`（拒绝态，不碰库 ⇒ agent/ttl 为空）
///     与 `FileLock::agent_of()` / `scope_of()` 两个**读访问器**（本笔同批）⇒ **无需后端扩展**。
///
/// 三态语义与 `check_scope_permission` 一致（BUG-413）：
///   · `RoleDenied`   ⇒ **硬拒**：`granted=false` + `action="permission_denied"`，**不写库**
///   · `Unregistered` ⇒ advisory：正常抢锁，拿到时把 action 标 `unregistered`（不参与授权裁决）
///   · `Allowed`      ⇒ 原样
///
/// 角色来源走 `resolve_agent_role`（权威面 `agents.role` 优先、名字推断兜底）——
/// **不是**裸 `infer_role_from_agent`，否则 BUG-418 刚收窄的那层会被这里绕开
/// （与 `rsv_set` / `rsv_try_set` 同口径）。
///
/// **本门覆盖不到的面（诚实标注）**：
///   · `locks_upsert`（底层原语）仍是裸通道 —— 它被 `locks_sweep` 等内部路径依赖，
///     加门会破坏那些路径；工具面 `lock_acquire` 走的是本函数，故攻击面已关闭
///   · `lock.agent` 是调用方自报字符串 ⇒ 「身份未经核验」这一根因仍在（BUG-422 的诚实边界）：
///     BUG-421 已删掉整名 `leader`/`lead` 提权，BUG-422 已把 server 自身份记录剔出裁决，
///     但「报一个非 server 类型的高角色登记名」仍可继承 —— 彻底收口需认证身份（A/C 案）。
pub fn FistEngine::locks_try_acquire(
  self : FistEngine,
  lock : @store.FileLock,
) -> @store.LockAcquireOutcome {
  let agent = lock.agent_of()
  let scope = lock.scope_of()
  // BUG-422：与两条预订门同一取数（剔除 server 自身份，见 `declared_role_for_judgment`）。
  // BUG-432：并入 `judged_role` —— 锁门 / 预订门 / claim 的 RANK_GATE 现在是**同一个**取数面。
  let (role, _role_source) = judged_role(self, agent)
  match check_scope_permission(scope, role) {
    RoleDenied(_) =>
      // **legacy_grant 特判（BUG-424 裁决 (a)(b)(c)）**
      //
      // 一个 Executor 在权限门接上**之前**可能已持有高权 scope 的锁，现在它要续期：
      //   · 一律硬拒 ⇒ **制造僵尸锁**：它持有锁却续不了，到期后谁也拿不回，
      //     原持有者也被门挡在门外。**僵尸比遗留更糟：遗留有主可追，僵尸无主。**
      //   · 放行 + 留痕 + 禁止扩大 ⇒ 采纳这条。
      //
      // 判决：**只放行「续自己那条还活着的锁」**
      //   `RoleDenied` AND 现有锁(agent==自己 AND status=="active") ⇒ 放行，标 `renewed_legacy_grant`
      //   `RoleDenied` AND (别人的锁 OR 非 active)                  ⇒ 硬拒
      //
      // **留痕落在 `action` 而不是 `violation_logged`**：后者的语义是「抢别人的锁」
      // （有受害者），legacy 是「续自己的锁」（无受害者）。混进去会污染 `lock_denied` 统计口径。
      // legacy 量可由 `action == "renewed_legacy_grant"` 单独计数。
      //
      // **「禁止扩大」不需要新约束**：`lock_renew` 工具面已强制同 scope + 同 agent
      // （`server.mbt:5271` `Some(l) if l.agent != agent => Err`），天然不能借续期换 scope；
      // 而 `lock_acquire` 走到这里时，若库里没有「自己那条 active 锁」，仍是硬拒 ⇒ 不开新口。
      // **不加「ttl 不延长」**——那等于软拒绝，又回到僵尸问题。
      match self.store.locks_get(scope) {
        Some(existing) =>
          if existing.agent_of() == agent && existing.status_of() == "active" {
            let o = self.store.locks_try_acquire(lock)
            // **BUG-429：必须判 `o.granted` 再打标。**
            //
            // `locks_get`（:202）与 `locks_try_acquire`（:205）是两次独立 IO ——
            // 中间别的 agent 可以抢到同一把锁且 ttl 新鲜 ⇒ 本次写被后端拒
            // ⇒ `granted=false`。此时若无条件标 `renewed_legacy_grant`，
            // 回执就会是 **`granted=false` + `action="renewed_legacy_grant"` + `agent=别人`**
            // —— **三个字段互相矛盾**（同文件 Unregistered 分支写对了 `if o.granted`，这里漏抄）。
            //
            // 补上后语义：只有**真拿到**才标 legacy_grant；被后端拒时保留后端原标签
            // （那是更硬的信息：conflict / taken_over 说明锁被别人拿走了）。
            if o.granted {
              o.relabel("renewed_legacy_grant", true)
            } else {
              o
            }
          } else {
            @store.LockAcquireOutcome::denied_by_permission()
          }
        None => @store.LockAcquireOutcome::denied_by_permission()
      }
    Unregistered(_) => {
      let o = self.store.locks_try_acquire(lock)
      if o.granted {
        o.relabel("unregistered", true)
      } else {
        o
      }
    }
    Allowed => self.store.locks_try_acquire(lock)
  }
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
