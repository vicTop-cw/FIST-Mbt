///|
/// types
// Item-level reservation mutex. Physical file locks / scope locks / file_binds protect
// *physical* concurrency, but cannot detect two agents implementing the SAME logical
// BACKLOG item in DISJOINT file scopes (the multilane blind spot from reports/…-multilane-lock-mechanism-report.md §9).
// This guard is the logical-collision analogue: one item may be held by exactly one agent.
pub struct ClaimGuardState {
  holders : Map[String, String] // item_id -> agent
  tags : Map[String, Array[String]] // item_id -> topic tags (for semantic overlap)
}

///|
/// verdict
// Verdict matrix mirrors store_rsv.mbt `rsv_action` (single source of truth):
// None -> Claimed ; owner==agent -> Renewed ; other owner -> Denied ; freed -> Released.
// The agent identity is tracked in `holders`, so the verdict is payload-free.
pub enum ClaimVerdict {
  Claimed // item was free, now held by the requesting agent
  Renewed // same agent re-claimed, no state change needed
  Denied // item held by ANOTHER agent — the collision physical locks miss
  Released // item freed
}

///|
/// policy core
// Pure single-source verdict. Kept separate so the matrix can be unit-tested without state.
pub fn decide_claim(holder : String?, req : String) -> ClaimVerdict {
  match holder {
    None => Claimed
    Some(h) => if h == req { Renewed } else { Denied }
  }
}

///|
/// guard
pub fn make_guard() -> ClaimGuardState {
  { holders: Map([]), tags: Map([]), }
}

// claim_item: None->claimed, self->renewed, other->denied. No TTL — this is a logical
// mutex for the duration of an implementation, the layer physical file locks do not provide.

///|
pub fn claim_item(
  g : ClaimGuardState,
  item : String,
  agent : String,
) -> ClaimVerdict {
  let v = decide_claim(g.holders.get(item), agent)
  match v {
    Claimed(_) | Renewed(_) => g.holders.set(item, agent)
    _ => ()
  }
  v
}

///|
pub fn release_item(
  g : ClaimGuardState,
  item : String,
  agent : String,
) -> ClaimVerdict {
  match g.holders.get(item) {
    None => Released
    Some(h) =>
      if h == agent {
        g.holders.remove(item)
        g.tags.remove(item)
        Released
      } else {
        Denied
      }
  }
}

///|
pub fn holder_of(g : ClaimGuardState, item : String) -> String? {
  g.holders.get(item)
}

// Atomic batch claim: if ANY item is held by another agent, the whole batch is denied
// (prevents two agents each grabbing a disjoint subset of the same item set).

///|
pub fn claim_all(
  g : ClaimGuardState,
  items : Array[String],
  agent : String,
) -> Result[Unit, String] {
  for it in items {
    match g.holders.get(it) {
      Some(h) if h != agent => return Err("conflict:" + it + "@" + h)
      _ => ()
    }
  }
  for it in items {
    g.holders.set(it, agent)
  }
  Ok(())
}

///|
pub fn release_all(
  g : ClaimGuardState,
  items : Array[String],
  agent : String,
) -> Unit {
  for it in items {
    match g.holders.get(it) {
      Some(h) if h == agent => {
        g.holders.remove(it)
        g.tags.remove(it)
      }
      _ => ()
    }
  }
}

///|
/// Attach topic tags to an item so semantic (not just id) overlap can be detected.
/// Tags are advisory: they never change a holder, but feed `semantic_overlap`.
pub fn set_tags(
  g : ClaimGuardState,
  item : String,
  tags : Array[String],
) -> Unit {
  g.tags.set(item, tags)
}

///|
pub fn tags_of(g : ClaimGuardState, item : String) -> Array[String] {
  match g.tags.get(item) {
    Some(ts) => ts
    None => []
  }
}

///|
pub fn snapshot(g : ClaimGuardState) -> Map[String, String] {
  let copy : Map[String, String] = Map([])
  for k, v in g.holders.iter2() {
    copy.set(k, v)
  }
  copy
}

///|
/// blind-spot detector
// Two file scopes are physically disjoint (so physical/scope locks stay silent), yet the
// item is already claimed by another agent in a different scope. This is exactly the case
// the multilane mechanism cannot see — and the case claimguard exists to catch.
pub fn scopes_disjoint(a : Array[String], b : Array[String]) -> Bool {
  for x in a {
    if b.contains(x) {
      return false
    }
  }
  true
}

// blind_spot == true means: physical lock reports quiet (disjoint scopes) BUT the logical
// item is already taken elsewhere — the dangerous cross-scope double-implementation.

///|
pub fn blind_spot_holds(
  scopes_disjoint : Bool,
  item_claimed_by_other : Bool,
) -> Bool {
  scopes_disjoint && item_claimed_by_other
}

// Recommended gate: an agent may proceed with a disjoint-scope implementation ONLY after
// reserving the logical item. If Denied, it must NOT implement (even with non-overlapping files).

///|
pub fn may_proceed(g : ClaimGuardState, item : String, agent : String) -> Bool {
  match claim_item(g, item, agent) {
    Denied(_) => false
    _ => true
  }
}

// —— Semantic blind spot (deeper than item-id) ——
// Physical locks + item-id claims still miss the case where two agents implement DIFFERENT
// but OVERLAPPING logical items in disjoint file scopes (e.g. two "native inspection" backlog
// rows, or a parent row and a child row that both touch the same subsystem). The item ids
// differ, so claim_all is silent; the file scopes are disjoint, so reserve_scope is silent.
// Topic tags bridge that gap: if the proposed item shares any tag with an ALREADY-claimed
// item held by another agent, that is a semantic collision the multilane mechanism cannot see.

///|
/// True iff the two tag sets share at least one element.
pub fn tags_overlap(a : Array[String], b : Array[String]) -> Bool {
  for t in a {
    if b.contains(t) {
      return true
    }
  }
  false
}

///|
/// Semantic collision: an item `proposed` with tags `proposed_tags` collides when SOME
/// other item already held by a DIFFERENT agent shares at least one topic tag, even though
/// the item ids differ. (Items held by the same agent are not collisions — that is self-overlap.)
pub fn semantic_collision(
  g : ClaimGuardState,
  proposed : String,
  proposed_tags : Array[String],
  agent : String,
) -> Bool {
  for k, v in g.holders.iter2() {
    if k == proposed {
      continue
    }
    if v != agent && tags_overlap(proposed_tags, tags_of(g, k)) {
      return true
    }
  }
  false
}

// Recommended composite gate: an agent may implement `proposed` only if it neither collides
// at the item-id layer (claim_item) NOR at the semantic layer (semantic_collision). A disjoint
// file scope is NOT sufficient when topic tags overlap with another agent's claimed item.

///|
pub fn may_proceed_sematic(
  g : ClaimGuardState,
  proposed : String,
  proposed_tags : Array[String],
  agent : String,
) -> Bool {
  match claim_item(g, proposed, agent) {
    Denied(_) => false
    _ =>
      if semantic_collision(g, proposed, proposed_tags, agent) {
        false
      } else {
        true
      }
  }
}

// —— Three-dimension composite gate (Round 6 consolidation) ——
// The multilane blind spot has THREE layers that physical locks cannot see on their own:
//   1. item-id  layer: same logical item id claimed by another agent (claim_item / claim_all)
//   2. scope    layer: disjoint file scopes yet the item already held elsewhere
//                  (scopes_disjoint + blind_spot_holds)
//   3. semantic layer: different item ids, disjoint scopes, but overlapping topic tags
//                  (semantic_collision)
// may_proceed_full folds all three into ONE recommended entry gate an agent must pass before
// implementing, regardless of how physically disjoint its files are. `scopes_disjoint_flag`
// and `item_claimed_by_other_flag` are supplied by the caller (computed from scope reservation
// state + holder_of); claimguard itself does not track per-item file scopes.
// Recommended entry-gate usage in an MCP pre-claim hook:
//   let ok = may_proceed_full(g, proposed, tags, agent,
//                             scopes_disjoint_flag, item_claimed_by_other_flag)

///|
pub fn may_proceed_full(
  g : ClaimGuardState,
  proposed : String,
  proposed_tags : Array[String],
  agent : String,
  scopes_disjoint_flag : Bool,
  item_claimed_by_other_flag : Bool,
) -> Bool {
  // Layer 1: same item id already held by another agent -> blocked.
  match claim_item(g, proposed, agent) {
    Denied(_) => return false
    _ => ()
  }
  // Layer 2: physically disjoint scopes but logically taken elsewhere -> blind spot -> blocked.
  if blind_spot_holds(scopes_disjoint_flag, item_claimed_by_other_flag) {
    return false
  }
  // Layer 3: different item, disjoint scopes, but overlapping topic tags -> semantic block.
  if semantic_collision(g, proposed, proposed_tags, agent) {
    return false
  }
  true
}

// —— Cross-agent reconciliation (Round 7) ——
// The multilane blind spot is most dangerous when two agents each maintain their
// OWN ClaimGuardState: each only sees its own claims, and their file scopes were
// physically disjoint so reserve_scope / lock_acquire / file_binds stayed silent.
// The ONLY way to catch the collision is to reconcile the two states. These
// functions are PURE and READ-ONLY — they never mutate either agent's state,
// preserving the single-source-of-truth discipline (store_rsv.mbt rsv_action
// remains the physical lock; claimguard stays a logical overlay).

///|
pub struct CrossCollision {
  item_a : String
  agent_a : String
  item_b : String
  agent_b : String
  tag : String // first overlapping topic tag observed
}

// First common element of two tag arrays, if any.

///|
pub fn overlapping_tag(a : Array[String], b : Array[String]) -> String? {
  for t in a {
    if b.contains(t) {
      return Some(t)
    }
  }
  None
}

// Item-id conflicts across two states: the SAME item id claimed by TWO DIFFERENT
// agents. Returns item -> (agentA, agentB). A per-agent guard would never see this
// (each agent sees only its own holder), and physical locks stay silent because
// the agents' files were disjoint.

///|
pub fn reconcile_id_conflicts(
  a : ClaimGuardState,
  b : ClaimGuardState,
) -> Map[String, (String, String)] {
  let out : Map[String, (String, String)] = Map([])
  for k, v in a.holders.iter2() {
    match b.holders.get(k) {
      Some(w) => if w != v { out.set(k, (v, w)) }
      _ => ()
    }
  }
  out
}

// Semantic blind-spot collisions across two agents' states: item_a (held by
// agent_a in a) and item_b (held by agent_b in b) have DIFFERENT ids, DIFFERENT
// agents, but share at least one topic tag. These are exactly the collisions that
// neither physical locks nor per-agent item-id / semantic checks would ever surface.

///|
pub fn reconcile_semantic_conflicts(
  a : ClaimGuardState,
  b : ClaimGuardState,
) -> Array[CrossCollision] {
  let out : Array[CrossCollision] = []
  for ka, va in a.holders.iter2() {
    for kb, vb in b.holders.iter2() {
      if va == vb {
        continue
      }
      match overlapping_tag(tags_of(a, ka), tags_of(b, kb)) {
        Some(t) =>
          out.push(CrossCollision::{
            item_a: ka,
            agent_a: va,
            item_b: kb,
            agent_b: vb,
            tag: t,
          })
        None => ()
      }
    }
  }
  out
}

// Coordinator verdict (Round 8): a SINGLE boolean a coordinator gets when it reads
// two agents' independently-maintained states and must decide whether their
// disjoint-scope work may proceed in parallel. True ONLY when BOTH reconciliation
// passes are empty — i.e. no same-id double-claim AND no cross-agent semantic
// overlap. This is the central gate that closes the multilane blind spot the
// physical locks (reserve_scope / lock_acquire / file_binds) cannot see, because
// the two agents' file scopes were disjoint and each only saw its own guard.
// Pure + read-only: never touches either agent's state.

///|
pub fn may_reconcile_ok(a : ClaimGuardState, b : ClaimGuardState) -> Bool {
  let id_ok = reconcile_id_conflicts(a, b).is_empty()
  let sem_ok = reconcile_semantic_conflicts(a, b).is_empty()
  id_ok && sem_ok
}

// Read-only convenience: how many of each collision class the two states contain.
// A coordinator can log this before failing the gate (may_reconcile_ok == false).

///|
pub fn reconcile_summary(
  a : ClaimGuardState,
  b : ClaimGuardState,
) -> (Int, Int) {
  (
    reconcile_id_conflicts(a, b).length(),
    reconcile_semantic_conflicts(a, b).length(),
  )
}

// —— Cross-agent reconciliation, N-agent (Round 9) ——
// The meta-goal drives MULTIPLE agents on the same project; real multilane runs
// have N agents, not just a pair. Round 8 only reconciled two states
// (may_reconcile_ok). This layer folds ALL pairwise reconciliations over an
// array of N independently-maintained ClaimGuardStates into one coordinator
// verdict, reusing the SAME pure read-only pairwise functions — so no second
// source of truth is introduced (store_rsv.mbt::rsv_action stays the physical
// truth; claimguard stays a logical overlay and still never mutates any state).

///|
pub struct IdConflict {
  item : String
  agent_a : String
  agent_b : String
}

///|
pub struct ReconcileAllReport {
  id_conflicts : Array[IdConflict]
  semantic_conflicts : Array[CrossCollision]
}

// All unordered pairs (i<j) of the given states. Pure + read-only: every
// comparison is delegated to reconcile_id_conflicts / reconcile_semantic_conflicts,
// so the comparison logic exists in exactly one place.

///|
pub fn reconcile_all(states : Array[ClaimGuardState]) -> ReconcileAllReport {
  let id_out : Array[IdConflict] = []
  let sem_out : Array[CrossCollision] = []
  let n = states.length()
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      let a = states[i]
      let b = states[j]
      for k, pair in reconcile_id_conflicts(a, b).iter2() {
        id_out.push(IdConflict::{ item: k, agent_a: pair.0, agent_b: pair.1, })
      }
      for c in reconcile_semantic_conflicts(a, b) {
        sem_out.push(c)
      }
    }
  }
  { id_conflicts: id_out, semantic_conflicts: sem_out, }
}

// Coordinator verdict over N agents: true ONLY when NO pairwise id conflict AND
// NO pairwise semantic conflict exists across any pair. Pure + read-only.

///|
pub fn may_reconcile_all_ok(states : Array[ClaimGuardState]) -> Bool {
  let r = reconcile_all(states)
  r.id_conflicts.is_empty() && r.semantic_conflicts.is_empty()
}

// Read-only convenience: total id + semantic collision counts across all pairs.

///|
pub fn reconcile_all_summary(states : Array[ClaimGuardState]) -> (Int, Int) {
  let r = reconcile_all(states)
  (r.id_conflicts.length(), r.semantic_conflicts.length())
}

// —— Coordinator admission gate + triage scoreboard (Round 10) ——
// The multilane scenario: a NEW agent wants to START work and must check against
// ALL in-flight agents BEFORE claiming. This is distinct from reconciling a *fixed*
// pool (R9 may_reconcile_all_ok): here the proposed agent is the one seeking
// admission, and the verdict names WHICH existing agents it would collide with, so
// a coordinator can negotiate (ask those peers to yield) rather than just fail.
// Pure + read-only: delegates entirely to reconcile_all (same single source of truth),
// modifies NO state.

///|
pub struct AdmitReport {
  ok : Bool // true iff `proposed` introduces NO new collision vs any peer
  colliding_agents : Array[String] // distinct peer agents `proposed` would collide with
  id_conflicts : Array[IdConflict]
  semantic_conflicts : Array[CrossCollision]
  // NOTE: id_conflicts/semantic_conflicts may also contain PRE-EXISTING peer-vs-peer
  // conflicts (two in-flight agents already fighting, neither involving `proposed`).
  // Such conflicts do NOT block admission (ok stays true) but are surfaced here so
  // the coordinator sees the whole scene's hazard, not just `proposed`'s own risk.
}

///|
pub fn admit(
  proposed : ClaimGuardState,
  others : Array[ClaimGuardState],
) -> AdmitReport {
  let states : Array[ClaimGuardState] = [proposed]
  for s in others {
    states.push(s)
  }
  let r = reconcile_all(states)
  // Agents that already hold something in `proposed` — conflicts on their own
  // side are not "peer" collisions; a peer is whoever is on the OTHER side.
  let proposed_agents : Map[String, Unit] = Map([])
  for _k, v in proposed.holders.iter2() {
    proposed_agents.set(v, ())
  }
  let seen : Map[String, Unit] = Map([])
  for c in r.id_conflicts {
    match proposed_agents.get(c.agent_a) {
      Some(_) =>
        match proposed_agents.get(c.agent_b) {
          Some(_) => ()
          None => seen.set(c.agent_b, ())
        }
      None =>
        match proposed_agents.get(c.agent_b) {
          Some(_) => seen.set(c.agent_a, ())
          None => ()
        }
    }
  }
  for c in r.semantic_conflicts {
    match proposed_agents.get(c.agent_a) {
      Some(_) =>
        match proposed_agents.get(c.agent_b) {
          Some(_) => ()
          None => seen.set(c.agent_b, ())
        }
      None =>
        match proposed_agents.get(c.agent_b) {
          Some(_) => seen.set(c.agent_a, ())
          None => ()
        }
    }
  }
  let agents : Array[String] = []
  for a, _ in seen.iter2() {
    agents.push(a)
  }
  {
    ok: agents.is_empty(),
    colliding_agents: agents,
    id_conflicts: r.id_conflicts,
    semantic_conflicts: r.semantic_conflicts,
  }
}

// Convenience boolean for the admission gate.

///|
pub fn admit_ok(
  proposed : ClaimGuardState,
  others : Array[ClaimGuardState],
) -> Bool {
  admit(proposed, others).ok
}

// Coordinator triage: for each agent that appears in ANY conflict (id or semantic),
// count how many conflicts it is party to. A coordinator uses this to decide whom to
// ask to yield first (highest degree => most contested). Pure + read-only.

///|
pub fn conflict_scoreboard(report : ReconcileAllReport) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for c in report.id_conflicts {
    m.set(
      c.agent_a,
      match m.get(c.agent_a) {
        Some(v) => v + 1
        None => 1
      },
    )
    m.set(
      c.agent_b,
      match m.get(c.agent_b) {
        Some(v) => v + 1
        None => 1
      },
    )
  }
  for c in report.semantic_conflicts {
    m.set(
      c.agent_a,
      match m.get(c.agent_a) {
        Some(v) => v + 1
        None => 1
      },
    )
    m.set(
      c.agent_b,
      match m.get(c.agent_b) {
        Some(v) => v + 1
        None => 1
      },
    )
  }
  m
}

// —— Coordinator negotiation (Round 11) ——
// R10 gave a NEWCOMER the admission verdict + named the peers it would collide with,
// plus a scoreboard of who is most contested. The multilane scenario then needs a
// COORDINATOR move: ASK one of those peers to yield, and SIMULATE whether the newcomer
// would then be admitted — WITHOUT mutating any real state (the coordinator decides;
// claimguard only computes). Every fn below is pure + read-only; none calls claim_item /
// release_item / mutates a Map in place. A real yield is a coordinator action (e.g. via
// reserve_release on the lane-owned store) that lies OUTSIDE this package's isolated scope.

// Pure projection: drop every item currently held by `agent` (a simulated "yield").
// Tags of those items are dropped too, so a later admit does not compare stale topics.
// Returns a NEW state; the input is never mutated.

///|
pub fn peer_yield(s : ClaimGuardState, agent : String) -> ClaimGuardState {
  let h2 : Map[String, String] = Map([])
  let t2 : Map[String, Array[String]] = Map([])
  for k, v in s.holders.iter2() {
    if v != agent {
      h2.set(k, v)
    }
  }
  for k, v in s.tags.iter2() {
    match h2.get(k) {
      Some(_) => t2.set(k, v)
      None => ()
    }
  }
  { holders: h2, tags: t2, }
}

// Pick the single peer a coordinator should ask to yield first: the HIGHEST conflict
// degree on the scoreboard (most contested); ties broken by smallest agent name for
// deterministic output. None when the scene has zero conflicts. Pure + read-only.

///|
pub fn advise_yield(report : ReconcileAllReport) -> String? {
  let board = conflict_scoreboard(report)
  let entries : Array[(String, Int)] = []
  for a, d in board.iter2() {
    entries.push((a, d))
  }
  if entries.is_empty() {
    None
  } else {
    Some(pick_top(entries, 1, entries[0]).0)
  }
}

// Pure max-by-(degree desc, name asc) over the entries array; no mutable accumulator.

///|
fn pick_top(
  es : Array[(String, Int)],
  i : Int,
  cur : (String, Int),
) -> (String, Int) {
  if i >= es.length() {
    cur
  } else {
    let e = es[i]
    let next = if e.1 > cur.1 {
      e
    } else if e.1 == cur.1 && e.0 < cur.0 {
      e
    } else {
      cur
    }
    pick_top(es, i + 1, next)
  }
}

// Priority-aware tie-break (Round 13): among equal collision-degree candidates,
// yield the LOWER-priority peer first (priority asc), then smallest name. The
// payload is (name, degree, priority). Pure + read-only, no mutable accumulator.

///|
fn pick_top_priority(
  es : Array[(String, Int, Int)],
  i : Int,
  cur : (String, Int, Int),
) -> (String, Int, Int) {
  if i >= es.length() {
    cur
  } else {
    let e = es[i]
    let next = if e.1 > cur.1 {
      e
    } else if e.1 == cur.1 && e.2 < cur.2 {
      e
    } else if e.1 == cur.1 && e.2 == cur.2 && e.0 < cur.0 {
      e
    } else {
      cur
    }
    pick_top_priority(es, i + 1, next)
  }
}

// Simulate: if `yield_agent` yields (every item it holds is released), would `proposed`
// be admitted? Pure + read-only: each peer state is replaced by its peer_yield projection
// before re-running R10's admit. The verdict says "yes" iff the collision set shrinks to
// none after that single yield — otherwise the coordinator must negotiate more peers.

///|
pub fn admit_after_yield(
  proposed : ClaimGuardState,
  others : Array[ClaimGuardState],
  yield_agent : String,
) -> AdmitReport {
  let relaxed : Array[ClaimGuardState] = []
  for s in others {
    relaxed.push(peer_yield(s, yield_agent))
  }
  admit(proposed, relaxed)
}

// —— Coordinator cascade negotiation (Round 12) ——
// R11 simulated a SINGLE yield. The multilane reality is a NEGOTIATION CHAIN: the
// newcomer may collide with several peers holding different items, so the coordinator
// must ask them to yield ONE AT A TIME, re-checking admission after each ask, until
// either the newcomer is admitted or a step budget is exhausted. This is the full
// cascade: pure + read-only, mutating NO real state. Each "ask" is a peer_yield
// projection (a simulated release); the real yield is a coordinator action outside
// this package. Returns the agents asked (in order) and the final admission verdict.

///|
pub struct NegotiateReport {
  ok : Bool // true iff `proposed` is admitted after the cascade (or was already ok)
  yielded : Array[String] // agents asked to yield, in negotiation order
  admit : AdmitReport // final admission verdict after the last simulated yield
}

///|
pub fn negotiate_admit(
  proposed : ClaimGuardState,
  others : Array[ClaimGuardState],
  max_steps : Int,
) -> NegotiateReport {
  let mut cur : Array[ClaimGuardState] = []
  for s in others {
    cur.push(s)
  }
  let yielded : Array[String] = []
  for _step = 0; _step < max_steps; _step = _step + 1 {
    let r = admit(proposed, cur)
    if r.ok {
      return { ok: true, yielded, admit: r, }
    }
    // Among the peers `proposed` actually collides with, ask the most-contested
    // one to yield (highest degree, tie -> smallest name). The proposed agent
    // itself is NEVER a candidate: we restrict to `r.colliding_agents`, so the
    // coordinator never asks the newcomer to give up its own claim.
    let states : Array[ClaimGuardState] = [proposed]
    for s in cur {
      states.push(s)
    }
    let board = conflict_scoreboard(reconcile_all(states))
    let cands : Array[(String, Int)] = []
    for a, d in board.iter2() {
      if r.colliding_agents.contains(a) {
        cands.push((a, d))
      }
    }
    if cands.is_empty() {
      return { ok: false, yielded, admit: r, }
    }
    let target = pick_top(cands, 1, cands[0]).0
    let cur2 : Array[ClaimGuardState] = []
    for s in cur {
      cur2.push(peer_yield(s, target))
    }
    cur = cur2
    yielded.push(target)
  }
  // Budget exhausted (or never entered the loop): report the final admission verdict.
  let r = admit(proposed, cur)
  { ok: r.ok, yielded, admit: r, }
}

// Priority-aware cascade (Round 13): identical cascade shape to `negotiate_admit`,
// but when the colliding peers TIE on collision-degree, the coordinator asks the
// LOWER-priority peer to yield first (priority asc, then smallest name). Real
// priority comes from the orchestrator / executor_route trust+load axis; this
// package stays pure+read-only and takes it as a payload. `priorities` maps agent
// name -> priority (default 0 for absent). Pure + read-only, mutating NO state.

///|
pub fn negotiate_admit_priority(
  proposed : ClaimGuardState,
  others : Array[ClaimGuardState],
  max_steps : Int,
  priorities : Map[String, Int],
) -> NegotiateReport {
  let mut cur : Array[ClaimGuardState] = []
  for s in others {
    cur.push(s)
  }
  let yielded : Array[String] = []
  for _step = 0; _step < max_steps; _step = _step + 1 {
    let r = admit(proposed, cur)
    if r.ok {
      return { ok: true, yielded, admit: r, }
    }
    let states : Array[ClaimGuardState] = [proposed]
    for s in cur {
      states.push(s)
    }
    let board = conflict_scoreboard(reconcile_all(states))
    let cands : Array[(String, Int, Int)] = []
    for a, d in board.iter2() {
      if r.colliding_agents.contains(a) {
        let p = priorities.get_or_default(a, 0)
        cands.push((a, d, p))
      }
    }
    if cands.is_empty() {
      return { ok: false, yielded, admit: r, }
    }
    let target = pick_top_priority(cands, 1, cands[0]).0
    let cur2 : Array[ClaimGuardState] = []
    for s in cur {
      cur2.push(peer_yield(s, target))
    }
    cur = cur2
    yielded.push(target)
  }
  let r = admit(proposed, cur)
  { ok: r.ok, yielded, admit: r, }
}

// Coordinator-consumable negotiation plan (Round 14): wraps the priority-aware
// cascade (R13) and derives planner metrics the orchestrator needs to DECIDE
// whether to execute the plan, without mutating any state. Two derived fields:
//   - priority_cost: sum of priorities of the peers asked to yield (a cost of
//     disruption; lower is cheaper to the lane). Real priority comes from
//     executor_route trust+load; this package only consumes the payload.
//   - freed_for_proposed: the concrete item_ids that would become free for the
//     newcomer if every yielded peer actually releases (the contested items
//     `proposed` wants AND a yielded peer currently holds). This is the
//     operational payoff — the coordinator can check "will this plan actually
//     unblock my item?" before committing to the disruption.
// Pure + read-only; delegates the cascade entirely to `negotiate_admit_priority`.

///|
pub struct NegotiatePlan {
  report : NegotiateReport // underlying cascade verdict (ok / yielded / admit)
  priority_cost : Int // sum of priorities of yielded peers (disruption cost)
  freed_for_proposed : Array[String] // contested items that would unblock `proposed`
}

///|
pub fn negotiate_plan(
  proposed : ClaimGuardState,
  others : Array[ClaimGuardState],
  max_steps : Int,
  priorities : Map[String, Int],
) -> NegotiatePlan {
  let neg = negotiate_admit_priority(proposed, others, max_steps, priorities)
  // agent name -> items it currently holds (from the original in-flight states)
  let agent_items : Map[String, Array[String]] = Map([])
  for s in others {
    for item, agent in s.holders.iter2() {
      match agent_items.get(agent) {
        Some(arr) => arr.push(item)
        None => {
          let a : Array[String] = [item]
          agent_items.set(agent, a)
        }
      }
    }
  }
  // Items freed for `proposed` = its own desired items that a yielded peer holds.
  let freed : Array[String] = []
  for y in neg.yielded {
    match agent_items.get(y) {
      Some(items) =>
        for it in items {
          if proposed.holders.get(it) is Some(_) && !freed.contains(it) {
            freed.push(it)
          }
        }
      None => ()
    }
  }
  // Disruption cost = sum of priorities of the peers asked to yield.
  let mut cost = 0
  for y in neg.yielded {
    cost = cost + priorities.get_or_default(y, 0)
  }
  { report: neg, priority_cost: cost, freed_for_proposed: freed, }
}

// —— Coordinator admission scheduler (Round 15) ——
// R14 produces ONE negotiation plan (cost + freed) for ONE proposed newcomer. A
// real coordinator faces SEVERAL newcomers and must decide an admission order that
// minimizes total disruption to the lane. This scheduler is the missing layer:
// it greedily admits the cheapest-disruption candidate first. Each admission's
// negotiated yields are folded into a COPIED live scene (plus the newcomer's own
// claims), so later candidates see the freed items and need fewer / zero further
// yields. Pure + read-only over the inputs: it works on an internal scene copy and
// never mutates the caller's `peers`/`candidates`. Single cost oracle = R14's
// `negotiate_plan` (which itself reuses R13's cascade) — no parallel cascade impl.

///|
pub struct ScheduledAdmit {
  agent : String // the admitted candidate's agent name (from its proposed holders)
  plan : NegotiatePlan // the plan that admitted it (report.ok is guaranteed true)
}

///|
pub struct ScheduleReport {
  admitted : Array[ScheduledAdmit] // in admission order, cheapest-disruption-first
  rejected : Array[String] // candidate agent names that could not be admitted
  total_priority_cost : Int // sum of priority_cost over admitted (lane disruption)
  scene : Array[ClaimGuardState] // resulting live scene after all admits+yields
}

// Deep-copy a guard state so the scheduler's scene mutations never touch the
// caller's input states. Maps are mutable, so a shallow copy would alias them.

///|
fn cg_copy_state(s : ClaimGuardState) -> ClaimGuardState {
  let h : Map[String, String] = Map([])
  for k, v in s.holders.iter2() {
    h.set(k, v)
  }
  let t : Map[String, Array[String]] = Map([])
  for k, v in s.tags.iter2() {
    t.set(k, v)
  }
  { holders: h, tags: t, }
}

// Derive a candidate's agent name from its proposed holder map. A candidate state
// represents one agent's desired claims, so its holders share a single agent name.

///|
fn cg_state_agent(s : ClaimGuardState) -> String {
  for _k, v in s.holders.iter2() {
    return v
  }
  ""
}

///|
pub fn schedule_admit(
  peers : Array[ClaimGuardState],
  candidates : Array[ClaimGuardState],
  max_steps : Int,
  priorities : Map[String, Int],
) -> ScheduleReport {
  // Mutable in-flight peers (deep copy). Yields from negotiation fold into THIS
  // copy only — already-admitted newcomers are never bounced.
  let mut peers_live : Array[ClaimGuardState] = []
  for s in peers {
    peers_live.push(cg_copy_state(s))
  }
  // Admitted newcomers are committed: they join the scene but are never yielded
  // to make room for a later candidate. A later candidate that hard-conflicts
  // with a committed newcomer is simply rejected.
  let committed : Array[ClaimGuardState] = []
  // Remaining candidates not yet scheduled.
  let mut remaining : Array[ClaimGuardState] = []
  for c in candidates {
    remaining.push(c)
  }
  let admitted : Array[ScheduledAdmit] = []
  let rejected : Array[String] = []
  let mut total_cost = 0
  // Greedy: while candidates remain, pick the one with the lowest disruption cost
  // that can be admitted against the CURRENT scene (costs shift as the scene
  // changes, so we re-evaluate every round). The scene is peers_live ++ committed,
  // but yields only ever touch peers_live. Ties broken by smaller agent name for
  // deterministic output. If no remaining candidate can be admitted, the rest are
  // rejected and we stop (budget / structural exhaustion).
  while !remaining.is_empty() {
    // Rebuild the scene each round: live peers + committed newcomers.
    let scene : Array[ClaimGuardState] = []
    for s in peers_live {
      scene.push(s)
    }
    for s in committed {
      scene.push(s)
    }
    // Names of already-admitted newcomers. A candidate whose negotiation plan
    // would yield one of them can NOT be admitted (that would evict a committed
    // peer) — it is rejected instead.
    let committed_names : Map[String, Unit] = Map([])
    for s in committed {
      committed_names.set(cg_state_agent(s), ())
    }
    let mut best = -1
    let mut best_cost = 1000000000
    let mut best_ok = false
    for i = 0; i < remaining.length(); i = i + 1 {
      let cplan = negotiate_plan(remaining[i], scene, max_steps, priorities)
      // Admissible only if ok AND it does not ask a committed newcomer to yield.
      let mut touches_committed = false
      for y in cplan.report.yielded {
        if committed_names.contains(y) {
          touches_committed = true
        }
      }
      if cplan.report.ok && !touches_committed {
        let cheaper = if best == -1 {
          true
        } else if cplan.priority_cost < best_cost {
          true
        } else if cplan.priority_cost == best_cost {
          cg_state_agent(remaining[i]) < cg_state_agent(remaining[best])
        } else {
          false
        }
        if cheaper {
          best_cost = cplan.priority_cost
          best = i
          best_ok = true
        }
      }
    }
    if !best_ok {
      for c in remaining {
        rejected.push(cg_state_agent(c))
      }
      break
    }
    let cand = remaining[best]
    let plan = negotiate_plan(cand, scene, max_steps, priorities)
    admitted.push({ agent: cg_state_agent(cand), plan, })
    total_cost = total_cost + plan.priority_cost
    // Fold the negotiated yields into the live peers copy ONLY. Already-admitted
    // newcomers in `committed` are never yielded.
    let yielded = plan.report.yielded
    let peers2 : Array[ClaimGuardState] = []
    for s in peers_live {
      let mut cur = s
      for y in yielded {
        cur = peer_yield(cur, y)
      }
      peers2.push(cur)
    }
    peers_live = peers2
    // The admitted newcomer joins the committed set with its own claims; it is
    // from now on an immovable part of the scene.
    committed.push(cg_copy_state(cand))
    // Drop `best` from the remaining pool.
    let rem2 : Array[ClaimGuardState] = []
    for i = 0; i < remaining.length(); i = i + 1 {
      if i != best {
        rem2.push(remaining[i])
      }
    }
    remaining = rem2
  }
  // Final scene = settled live peers + committed newcomers.
  let scene : Array[ClaimGuardState] = []
  for s in peers_live {
    scene.push(s)
  }
  for s in committed {
    scene.push(s)
  }
  { admitted, rejected, total_priority_cost: total_cost, scene, }
}
