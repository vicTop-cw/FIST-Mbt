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

// ══════════════════════════════════════════════════════════════════════════
// BUG-430 / S3 **第一段**：挑战-签名-验签的**纯函数骨架**
//
// 为什么从纯函数开始、而不是从握手开始：
//   「握手」涉及 MCP 传输层、客户端配合、密钥分发 —— 任何一处没通，整条链都跑不起来，
//   而且**失败原因分不清**（是密码学错了？是传输错了？是客户端没实现？）。
//   纯函数段可以在**一条编译命令 + 一个 test** 内证明「挑战确实接进了角色取数面」，
//   且**零回归**（不改 `judged_role` 签名、不碰 4 个现有调用点）。
//
// ⚠️ 诚实边界：本段**不改变安全属性**。`nonce=None` 时行为与 S1 完全一致（仍可自报）。
//   真正的安全属性要等：①握手把 nonce 真发出去 ②客户端真签名 ③服务端存得住公钥。
// ══════════════════════════════════════════════════════════════════════════

///|
/// S3：生成一次挑战的 nonce（**纯函数**，不落库、不读时钟）。
///
/// 为什么用「计数器 + agent」而不是随机数：`moonbitlang/x` **没有独立的 random 包**
/// （可行性核查已确认）。而 Ed25519 的 nonce 并**不需要密码学随机** ——
/// nonce 的作用是「**一次性、不可重放**」，由「单调计数器 + 主体标识」即可满足：
/// 同一 agent 每次挑战拿到不同 nonce，且 nonce 里绑定了 agent（换主体即失效）。
///
/// ⚠️ 本函数**不保证全局唯一**（纯函数不可能做到）。真正的唯一性由调用方传入的
/// 计数器保证（服务端单调递增）。**这是有意的**：纯函数可以在测试里完全确定。
pub fn issue_challenge_nonce(agent : String, counter : Int32) -> String {
  "fist-s3-challenge:v1:" + agent + ":" + counter.to_string()
}

///|
/// S3：**验签**（纯函数）。
///
/// `pubkey_hex` = Ed25519 公钥的 hex（64 字符 = 32 字节）；
/// `sig_hex`    = 签名的 hex（128 字符 = 64 字节）；
/// `msg`        = 被签的消息（通常 = nonce）。
///
/// hex 解码复用 `@mooncry.hex_to_bytes_or`（与 `src/router/star_gate.mbt:112` 同一个函数）。
/// 验签复用 `@mooncry.ed25519_verify`（与 `star_gate.mbt:301` **同一个函数**，
/// 本仓已在 Star 门生产使用）。
///
/// 任何一步不合法（hex 坏、公钥非 32 字节、签名非 64 字节、验签失败）⇒ `false`。
/// **fail-closed**：宁可拒绝，绝不在格式错误时放行。
pub fn verify_challenge_sig(pubkey_hex : String, msg : String, sig_hex : String) -> Bool {
  let pk = match @mooncry.hex_to_bytes_or(pubkey_hex) {
    Ok(b) => b
    Err(_) => return false
  }
  let sig = match @mooncry.hex_to_bytes_or(sig_hex) {
    Ok(b) => b
    Err(_) => return false
  }
  // 长度先于密码学校验（Ed25519 规格：公钥 32 字节、签名 64 字节）
  if pk.length() != 32 || sig.length() != 64 {
    return false
  }
  @mooncry.ed25519_verify(pk, @utf8.encode(msg), sig)
}

///|
/// S3：**带挑战的角色取数**（第一段的核心 —— 挑战真的接进了取数面）。
///
/// 语义（三态）：
///   · `challenge_nonce = None`
///       ⇒ **走现有 `judged_role` 逻辑（零回归）**，但 `role_source` 强制标注
///         `"unauthenticated"` —— 因为**没有挑战就意味着身份未认证**。
///         这是 S1 公告的延续：S1 说「自报不可验证」，S3 第一段说「未认证就别装成 declared」。
///   · `challenge_nonce = Some(nonce)` 且验签**通过**
///       ⇒ 返回 `(role, "challenge_verified")`，role 来自 `declared_role_for_judgment`
///         （即 agents 表里的 declared 角色）。
///   · `challenge_nonce = Some(_)` 但验签**失败**（含公钥未登记、hex 坏、签名不匹配）
///       ⇒ **降级为 `("Executor", "challenge_failed")`** —— fail-closed，绝不放行高权。
///
/// ⚠️ **`role_source` 的取值扩展**（调用方可见的变化）：
///   原有 `"declared"` / `"inferred"` 之外新增 `"unauthenticated"` / `"challenge_verified"`
///   / `"challenge_failed"`。**这不是改语义，是让「认证状态」显式可见。**
///
/// ⚠️ **诚实边界**：本函数**不改变 `judged_role`**（4 个现有调用点零回归）。
///   要把 S3 真正生效，还需要让四条门都改调本函数 —— 那是**第二段**。
pub fn judged_role_with_challenge(
  eng : FistEngine,
  agent : String,
  challenge_nonce : String?,
) -> (String, String) {
  match challenge_nonce {
    None =>
      // 无挑战 ⇒ 未认证。role 仍按现有逻辑算（保持可用性），但来源如实标注。
      {
        let (role, _) = judged_role(eng, agent)
        (role, "unauthenticated")
      }
    Some(nonce) => {
      // 有挑战 ⇒ 必须验签。公钥从 agents 表的 pubkey_fp 取。
      let pubkey = declared_pubkey_for(eng, agent)
      let msg = nonce
      let verified = match pubkey {
        // 没登记公钥 ⇒ 无法认证 ⇒ 失败（fail-closed）
        None => false
        Some(pk) => verify_challenge_sig(pk, msg, s3_last_sig_probe(eng, agent, nonce))
      }
      if verified {
        let (role, _src) = judged_role(eng, agent)
        (role, "challenge_verified")
      } else {
        ("Executor", "challenge_failed")
      }
    }
  }
}

///|
/// S3 第一段：取某 agent 登记的**公钥 hex**（agents 表 `pubkey_fp` 列）。
///
/// 取数走**与 `declared_role_for_judgment` 完全相同的路径**
/// （`eng.store.sqlite_store()` → `SqliteStore::agents_get`），不新造第二条取数面 ——
/// BUG-432 的教训：同一语义长第二个实现必翻车。
///
/// 返回 `None` 表示「未登记公钥」⇒ 该 agent **无法通过挑战认证**（fail-closed）。
/// `pubkey_fp` 为空串视为未登记。
fn declared_pubkey_for(eng : FistEngine, agent : String) -> String? {
  match eng.store.sqlite_store() {
    None => None
    Some(s) =>
      match s.agents_get(agent_fp_of(agent)) {
        None => None
        Some(a) =>
          if a.pubkey_fp == "" {
            None
          } else {
            Some(a.pubkey_fp)
          }
      }
  }
}

///|
/// S3 第一段：**签名来源占位**。
///
/// 纯函数段**拿不到**调用方提交的签名（那要走握手/参数），故此处返回空串 ⇒
/// 任何 `Some(nonce)` 调用在**第一段**都会走到 `challenge_failed`。
///
/// **这是有意为之，且必须写清**：
/// 第一段证明的是「挑战接进了取数面 + 验签函数可用 + fail-closed 正确」，
/// **不证明**「真客户端能通过认证」—— 后者需要第二段把
/// 「调用方提交的 (nonce, sig)」真正传进来（替换本占位）。
///
/// ⚠️ 若有人把本函数改成返回一个恒能验过的签名，等于**绕过 S3** ——
/// 第二段实现时必须**删掉本函数**，而不是让它返回真签名。
fn s3_last_sig_probe(eng : FistEngine, agent : String, nonce : String) -> String {
  ignore(eng)
  ignore(agent)
  ignore(nonce)
  ""
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
        // BUG-430 / S1：**公告边界，不提供安全保障**。
        // `agent` 是调用方自报的字符串，服务端没有任何手段验证它真属于谁 ⇒ 可冒充任何已登记名字。
        // 本字段让这件事**可见**，不解决它。
        // ⚠️ 写了说明 ≠ 安全了 —— 恰相反，写了说明可能让人更放心。
        // 关闭条件是 S3（身份锚点：签名挑战/验签）；S1/S2 都不消除冒充风险。
        Ok(o) =>
          Ok(
            o +
            " [role_source=" +
            role_source +
            "; agent_source=self-reported - agent is caller-asserted, unverifiable by the server; " +
            "this does NOT prevent impersonation and will not be closed before BUG-430 S3]",
          )
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
  // BUG-430 / S1：`agent` 是**调用方自报**的，服务端无法验证 ⇒ 回执必须让它可见。
  //   `RsvOutcome` 是 store 侧结构体、本层不能加字段 ⇒ 走既有的 `action` 标签机制
  //   （与 `role_inferred` 同一手法），后缀 `+agent_self_reported`。
  //   ⚠️ 这是**公告**不是**保障**：它不阻止冒充，只让冒充在回执里看得见；
  //   在 S3（身份锚点）落地前，冒充风险不会消除。
  // `action` 的合法取值因此扩展为：reserved | renewed | taken_over | conflict |
  //   unregistered | <上述之一>[+role_inferred][+agent_self_reported]
  let (role, role_source) = judged_role(self, agent)
  let src_tag = "+agent_self_reported"
  match check_scope_permission(scope, role) {
    RoleDenied(e) => Err(e)
    Allowed =>
      match self.store.rsv_try_set(scope~, agent~, ttl_until~, created_at~) {
        Err(e) => Err(e)
        Ok(o) =>
          Ok(
            o.relabel(
              o.action +
              (if role_source == "inferred" { "+role_inferred" } else { "" }) +
              src_tag,
            ),
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
                (if role_source == "inferred" { "+role_inferred" } else { "" }) +
                src_tag,
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
