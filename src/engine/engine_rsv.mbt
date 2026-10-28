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
pub fn verify_challenge_sig(
  pubkey_hex : String,
  msg : String,
  sig_hex : String,
) -> Bool {
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
///
/// **S3 第三段**：新增 `challenge_sig : String?` 参数 —— 由**调用方**提交签名。
/// 第一段用 `s3_last_sig_probe`（返回空串，永远验不过）做占位；第三段**删掉了它**，
/// 因为「服务端自己造签名」等于**自己给自己发通行证**。
/// 签名只能来自调用方私钥，服务端只负责**验** —— 这是 S3 的命门。
pub fn judged_role_with_challenge(
  eng : FistEngine,
  agent : String,
  challenge_nonce : String?,
  // S3 第三段：调用方提交的签名 hex（128 字符 = 64 字节）。None ⇒ 视为未提交 ⇒ 验不过。
  challenge_sig~ : String? = None,
) -> (String, String) {
  match challenge_nonce {
    // 无挑战 ⇒ 未认证。role 仍按现有逻辑算（保持可用性），但来源如实标注。
    None => {
      let (role, _) = judged_role(eng, agent)
      (role, "unauthenticated")
    }
    Some(nonce) => {
      // 有挑战 ⇒ 必须验签。公钥从 agents 表的 pubkey_fp 取。
      let pubkey = declared_pubkey_for(eng, agent)
      let msg = nonce
      let verified = match (pubkey, challenge_sig) {
        // 没登记公钥 / 调用方没交签名 ⇒ 无法认证 ⇒ 失败（fail-closed）
        (None, _) => false
        (_, None) => false
        (Some(pk), Some(sig)) => verify_challenge_sig(pk, msg, sig)
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
/// S3 第二段：**四道门专用的取数面**（保留原有 `role_source` 语义）。
///
/// 与 `judged_role_with_challenge` 的关键区别 —— **`None` 分支不做任何改变**：
///   · `challenge_nonce = None` ⇒ **原样返回 `judged_role` 的结果**（`declared` / `inferred`）。
///     理由：四道门的回执文案（如 `RANK_GATE: ... role_source=inferred`）与既有测试
///     都依赖这两个取值；把 `None` 改标成 `"unauthenticated"` 会**改掉现网语义**
///     （实测代价：3 格 rank_gate 测试立刻红）—— 那是第三段的「全量切换到认证」才该做的事。
///   · `challenge_nonce = Some(_)` ⇒ **必须验签**：通过 ⇒ `(role, "challenge_verified")`
///     （真实身份，可以拿高权）；失败或未登记公钥 ⇒ `("Executor", "challenge_failed")`（fail-closed）。
///
/// **⇒ 语义是「加严不放宽」**：不传挑战 = 完全维持现状；传了挑战 = 必须验过才给真角色。
///   真正想「没挑战就不给高权」是**第三段**（全量切换），本段刻意不做，以免半途改坏现网。
pub fn judged_role_gated(
  eng : FistEngine,
  agent : String,
  challenge_nonce : String?,
  // S3 第三段：调用方提交的签名（透传给 `judged_role_with_challenge`）
  challenge_sig~ : String? = None,
) -> (String, String) {
  match challenge_nonce {
    None => judged_role(eng, agent) // ← 零回归：原样返回
    Some(_) => {
      let (role, src) = judged_role_with_challenge(
        eng,
        agent,
        challenge_nonce,
        challenge_sig~,
      )
      (role, src)
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
// BUG-430 / S3 **第二段**：nonce 一次性消费 + 四条门接入
//
// 第一段的 nonce **不落库** ⇒ 同一个 nonce 可以被重复使用 ⇒「挑战」退化成
// 「长期通行证」。第二段补两件事：
//   ① **nonce 登记 + 一次性消费**（`claim_challenge_nonce` 原子消费）
//   ② **四条门全部走 `judged_role_with_challenge`**
//
// ⚠️ 诚实边界（必读）：
//   · `pubkey_fp` 目前是**死承诺**（`server.mbt:649` 明写「全仓无任何代码真正派生它，
//     所有写入点恒传 `pubkey_fp=""`」，BUG-403）。⇒ **线上没有任何 agent 有公钥**
//     ⇒ 传了 `challenge` 的调用**一律 challenge_failed**。
//     这是**正确且期望的** fail-closed 行为，不是 bug。
//   · 要真正生效还需要：**客户端签名回传**（`s3_last_sig_probe` 换成真实来源）
//     + **公钥登记入口**（`agents_register` 的 `pubkey_fp` 参数接线，在 `server.mbt`）。
// ══════════════════════════════════════════════════════════════════════════

///|
/// S3 第二段：nonce 登记表（**进程内**，不落库）。
///
/// key = agent 的归一化 fp，value = 「已签发但未消费」的 nonce 集合。
///
/// 为什么用进程内而不是新表：`store_sqlite.mbt` 是 HumanSteward 独占面（本轮改不了），
/// 且 nonce 的语义天然是**短命**的（一次挑战一用即弃），进程内存储足够；
/// 代价是**跨进程不共享**（多实例部署时各自的 nonce 互不可见）—— 已在 §缺口 登记。
pub let s3_pending_nonces : Map[String, Array[String]] = Map([])

///|
/// BUG-430 / S3 **第六段**：challenge 的**进程级单调计数器**（服务端自选，不给调用方）。
///
/// 为什么不能让调用方给 counter：`issue_challenge_nonce` 是纯函数 ⇒
/// 调用方给 counter 就能**离线预计算 nonce 并提前签好** ⇒ 挑战退化成固定串 ⇒ 验签失效。
///
/// ⚠️ 进程级 ⇒ 多实例部署各算各的（不同实例可能发出相同 nonce），
/// 但**每个实例只认自己发过的**（`s3_pending_nonces` 也是进程内）⇒ 跨实例不会误放行。
/// 真正的分布式唯一性需要落库（见缺口）。
///
/// 用 `Ref` 而不是顶层 `let mut`：MoonBit 顶层不允许 `let mut`（实测报 4074/3002）。
let s3_challenge_counter : Ref[Int32] = Ref(1)

///|
/// S3 第二段：**签发**一个 challenge 并登记为「待消费」。
///
/// 返回 nonce 字符串（调用方交客户端去签）。同一 agent 可同时有多个未消费 nonce
/// （并发挑战），但每个**只能用一次**。
///
/// ⚠️ **`counter` 由调用方传入 —— 只适合测试/内部路径**。
/// 生产面要「服务端自选 counter」，请用 `s3_issue_challenge_auto`：
/// 若让调用方自选 counter，调用方就能**预计算** nonce 并预先签好，
/// 那「挑战」就退化成一个固定字符串 ⇒ 验签失去意义（BUG-430 S3 第六段）。
pub fn FistEngine::s3_issue_challenge(
  self : FistEngine,
  agent : String,
  counter : Int32,
) -> String {
  ignore(self)
  let nonce = issue_challenge_nonce(agent, counter)
  let k = agent_fp_of(agent)
  let cur = match s3_pending_nonces.get(k) {
    None => []
    Some(a) => a
  }
  cur.push(nonce)
  s3_pending_nonces.set(k, cur)
  nonce
}

///|
/// BUG-430 / S3 **第六段**：**服务端自选 counter** 签发 challenge（生产面用这个）。
///
/// 为什么必须服务端自选：`issue_challenge_nonce(agent, counter)` 是**纯函数** ⇒
/// 若 counter 由调用方给，调用方可以**离线预计算** nonce、**提前签好**，
/// 然后任何时候提交都成立 ⇒ 「挑战」退化为固定字符串 ⇒ **验签形同虚设**。
///
/// 计数器是**进程级单调递增**（`s3_challenge_counter`），每个 challenge 的 nonce 都不同。
/// 与 `s3_pending_nonces` 一样是进程内的 ⇒ 多实例部署各自计数（见缺口）。
pub fn FistEngine::s3_issue_challenge_auto(
  self : FistEngine,
  agent : String,
) -> String {
  let n = s3_challenge_counter.val
  s3_challenge_counter.val = n + 1
  self.s3_issue_challenge(agent, n)
}

///|
/// S3 第二段：**一次性消费**（原子：查到即删除，第二次查必空）。
///
/// 语义：nonce 必须在**已登记且未消费**集合里，才返回 `true` 并**立即移除**。
/// 重复提交同一 nonce ⇒ 第二次 `false` ⇒ **防重放**。
///
/// 为什么是「消费」而不是「标记 consumed」：本表只存**未消费**的，
/// 消费即删除 ⇒ 表不会无限增长，且**不存在「标记了但没生效」**的中间态。
pub fn s3_consume_nonce(agent : String, nonce : String) -> Bool {
  let k = agent_fp_of(agent)
  match s3_pending_nonces.get(k) {
    None => false
    Some(arr) => {
      // 线性查找（未消费的 nonce 通常只有个位数，不值得上索引）
      let mut found = -1
      let mut i = 0
      while i < arr.length() {
        if arr[i] == nonce {
          found = i
          break
        }
        i = i + 1
      }
      if found < 0 {
        false
      } else {
        ignore(arr.remove(found))
        true
      }
    }
  }
}

///|
/// S3 第二段：**带 nonce 防重放的挑战判定**（四条门统一入口）。
///
/// 与 `judged_role_with_challenge` 的区别：本函数在验签**前后**各多一道 nonce 闸：
///   1. `challenge_nonce = None` ⇒ 直接走无挑战路径（**不消费任何 nonce**）；
///   2. `Some(nonce)` ⇒ **先验签**，验签通过**才**消费 nonce（避免「验签失败也烧掉 nonce」
///      导致合法调用方白白重试）；
///   3. nonce 已被消费过 ⇒ `challenge_replayed`（**不降级为 unauthenticated**，
///      而是明确告诉调用方「你重放了」）。
///
/// ⚠️ 返回值 `role_source` 的新增取值：`"challenge_replayed"`。
pub fn judged_role_with_nonce(
  eng : FistEngine,
  agent : String,
  challenge_nonce : String?,
  // S3 第三段：调用方提交的签名（透传）
  challenge_sig~ : String? = None,
) -> (String, String) {
  match challenge_nonce {
    None => judged_role_gated(eng, agent, None)
    Some(nonce) => {
      let (role, src) = judged_role_gated(
        eng,
        agent,
        Some(nonce),
        challenge_sig~,
      )
      if src == "challenge_verified" {
        // 验签通过 ⇒ 消费 nonce；若已被消费过 ⇒ 判重放（且**不**保留已验证身份）
        if s3_consume_nonce(agent, nonce) {
          (role, src)
        } else {
          ("Executor", "challenge_replayed")
        }
      } else {
        // 验签失败 / 未登记公钥 ⇒ 不消费 nonce（让调用方可用同一 nonce 修正重试）
        (role, src)
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
        Some(a) => if a.pubkey_fp == "" { None } else { Some(a.pubkey_fp) }
      }
  }
}

///|
/// ══════════════════════════════════════════════════════════════════════════
/// BUG-430 / S3 **第三段**：`s3_last_sig_probe` **已删除**。
///
/// 第一段的 `s3_last_sig_probe` 返回空串（永远验不过）。第三段**删掉它**，
/// 改为由调用方经 `challenge_sig` 参数**显式提交签名**。
///
/// ⚠️ **为什么不「填一个真签名」**：
/// 若本层自己生成/返回一个能验过的签名，等于**服务端自己给自己发通行证** ——
/// 任何人都能过。签名**只能来自调用方私钥**，服务端只负责**验**。
/// 这是 S3 的命门：**「验签」与「签发」必须在不同主体**。
/// ══════════════════════════════════════════════════════════════════════════

///|
pub fn FistEngine::rsv_set(
  self : FistEngine,
  scope~ : String,
  agent~ : String,
  ttl_until~ : String,
  created_at~ : String,
  // BUG-430 S3 第二段：可选挑战（不传 ⇒ None ⇒ 走原逻辑，零回归）
  challenge_nonce~ : String? = None,
  // BUG-430 S3 第三段：调用方提交的签名 hex（不传 ⇒ None ⇒ 验不过 ⇒ fail-closed）
  challenge_sig~ : String? = None,
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
  let (role, role_source) = judged_role_gated(self, agent, challenge_nonce, challenge_sig~)
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
/// ══════════════════════════════════════════════════════════════════════════
/// BUG-453：**认证态 → `action` 后缀的唯一映射源**。
///
/// 病灶（本函数存在的理由）：`judged_role_with_challenge` 承诺
/// 「`role_source` 的取值扩展是**调用方可见的变化**……让「认证状态」显式可见」
/// （见 `:124-126`），但 `rsv_try_set` / `locks_try_acquire` 的 `action` 面
/// **只映射了 `inferred` 一种**，且**无条件**追加硬编码 `+agent_self_reported`：
///   ⇒ 验签**通过**时回执仍写「自报未验证」（诚实标注写反）
///   ⇒ 验签**失败**时与「压根没传 challenge」逐字相同（日志里不可区分）
///
/// 现在四个认证态各有一个后缀，**且 `+agent_self_reported` 只在确实未经挑战时出现**。
///
/// ⚠️ 为什么抽成函数而不是两处各写一份：`rsv_try_set` 与 `locks_try_acquire`
/// 是同一取数面（`judged_role_gated`）的两个消费点，**各写一份映射就是下一个 BUG-435**。
/// ══════════════════════════════════════════════════════════════════════════
///

///|
/// BUG-453：`RoleDenied` 的硬拒回执也要带认证态（否则「验签失败后被硬拒」与
/// 「未验签被硬拒」在 `action` 面不可区分 —— 那正是本单要消除的那类混同）。
///
fn denied_tagged(role_source : String) -> @store.LockAcquireOutcome {
  let o = @store.LockAcquireOutcome::denied_by_permission()
  let t = auth_tag(role_source)
  // BUG-453：默认态零后缀 ⇒ `permission_denied` 保持既有精确断言（lock_perm_wbtest:36/51）
  if t == "" { o } else { o.relabel(o.action + t, false) }
}

///|
pub fn auth_tag(role_source : String) -> String {
  match role_source {
    // 三个**新增**认证态：必须可见
    "challenge_verified" => "+challenge_verified"
    "challenge_failed" => "+challenge_failed"
    "challenge_replayed" => "+challenge_replayed"
    // 既有态：**零后缀**。为什么不是 "+agent_self_reported"：
    //   该后缀在 `rsv_try_set` 里由调用点显式追加（修前就是这样，零回归）；
    //   而 `locks_try_acquire` 的 `permission_denied` / `unregistered` 有**精确相等**的
    //   既有断言（`lock_perm_wbtest.mbt:36/51/104`）⇒ 在这条门上必须保持逐字不变。
    _ => ""
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
  // BUG-430 S3 第二段：可选挑战（不传 ⇒ None ⇒ 走原逻辑，零回归）
  challenge_nonce~ : String? = None,
  // BUG-430 S3 第三段：调用方提交的签名 hex（不传 ⇒ None ⇒ 验不过 ⇒ fail-closed）
  challenge_sig~ : String? = None,
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
  let (role, role_source) = judged_role_gated(self, agent, challenge_nonce, challenge_sig~)
  // BUG-453：三个**新**认证态各带自己的后缀；既有态保持修前的 `+agent_self_reported`
  // （`auth_tag` 对它们返回空串，故这里补上 —— 语义与修前逐字一致，零回归）。
  let auth = auth_tag(role_source)
  let src_tag = if auth == "" { "+agent_self_reported" } else { auth }
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
  // BUG-430 S3 第二段：可选挑战（不传 ⇒ None ⇒ 走原逻辑，零回归）
  challenge_nonce~ : String? = None,
  // BUG-430 S3 第三段：调用方提交的签名 hex（不传 ⇒ None ⇒ 验不过 ⇒ fail-closed）
  challenge_sig~ : String? = None,
) -> @store.LockAcquireOutcome {
  let agent = lock.agent_of()
  let scope = lock.scope_of()
  // BUG-422：与两条预订门同一取数（剔除 server 自身份，见 `declared_role_for_judgment`）。
  // BUG-432：并入 `judged_role` —— 锁门 / 预订门 / claim 的 RANK_GATE 现在是**同一个**取数面。
  // BUG-453：**不再丢弃 `role_source`** —— 它必须进 `action` 面（认证态可见）。
  let (role, role_source) = judged_role_gated(self, agent, challenge_nonce, challenge_sig~)
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
            denied_tagged(role_source)
          }
        None => denied_tagged(role_source)
      }
    Unregistered(_) => {
      let o = self.store.locks_try_acquire(lock)
      let o2 = if o.granted {
        o.relabel("unregistered", true)
      } else {
        o
      }
      let t2 = auth_tag(role_source)
      if t2 == "" { o2 } else { o2.relabel(o2.action + t2, o2.granted) }
    }
    Allowed => {
      // BUG-453：`Allowed` 分支过去直接原样返回后端结论 ⇒ 认证态在**最常见**的路径上丢失。
      let o = self.store.locks_try_acquire(lock)
      let t3 = auth_tag(role_source)
      if t3 == "" { o } else { o.relabel(o.action + t3, o.granted) }
    }
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
