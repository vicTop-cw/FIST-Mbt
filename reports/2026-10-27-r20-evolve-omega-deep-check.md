# R20 深挖 · `evolve_critic` 阈值 + `omega_*` 门禁（补 R19 第三波的两个「未查」）

> **任务**：① critic 阈值量纲对表 ② omega 门禁是否双路径
> **执行人**：司令-γ · **边界**：只读 + 报告（未改 `src/` `scripts/`）
> **产出**：本报告 + `temp/audit/lane_bd_critic.py`

---

## 结论（两任务分开）

### 任务 1：`evolve_critic` 阈值对表 —— **量纲正确，0 条真 bug**

| 问题 | 答案 |
|---|---|
| **0.70 是用来判什么的？** | ★ **不是判新颖度，是判「相似度」** —— `dup = sim >= critic_dup_sim()`（`critic.mbt:78`，`critic_dup_sim()=0.70`） |
| **`novelty` 返回什么？** | `1.0 - max_jaccard`（`evolve.mbt:377`）—— **新颖度** |
| **两者对表吗？** | **✅ 正确**。`sim` 与 `novelty` **严格互补**（`novelty + sim == 1.0`），扫 42 组 0 例外 |
| **`threshold=0.85` 判什么？** | `combined`（新颖度加权），**不是** sim ⇒ 也没有用错量 |
| **真 bug** | **0 条** |

**⚠️ 但发现一个 O(2N) 重复计算**（未报 bug，见 §分析）。

### 任务 2：`omega_*` 门禁 —— **是「各写一份等价逻辑」，0 条真 bug**

| 项 | 读数 |
|---|---|
| 门禁函数数 | **5 处** `omega_enabled(t)` 前置守卫 |
| 其中「`get_task` + `omega_enabled` + Err」完整序列 | **3 处**（`:426` spec_create / `:510` spec_review / `:625` result_verify） |
| **前面 8 行是否逐字相同** | **是**（只有最后的错误文案不同） |
| `omega_authorize_review(reviewer)` 重复 | **2 处**（`:501` / `:616`） |
| **抽成共用函数了吗** | **没有** |
| 判定 | **两面（各写一份等价逻辑）**，非真 bug |

---

## 证据

### §1 任务 1：量纲逐条对表

```moonbit
// evolve.mbt:362-378
pub fn Archive::novelty(self, note) -> Double {
  ...
  let mut max_sim = 0.0
  for (_, a) in self.items { let j = jaccard(n, t); if j > max_sim { max_sim = j } }
  (1.0 - max_sim).clamp(min=0.0, max=1.0)     // ← 新颖度 = 1 - 最大相似度
}

// critic.mbt:25-46
pub fn critic_most_similar(arc, note) -> (String, String, Double)? {
  let mut best : (String, String, Double) = ("", "", 0.0)
  for a in Archive::all(arc) { let j = jaccard(n, t); if j > best.2 { best = (.., .., j) } }
  // ↑ 第 3 元 = 最大相似度
}

// critic.mbt:64-79
let novelty = arc.novelty(note)                    // 新颖度 ∈ [0,1]
let sim = critic_most_similar(arc, note).2          // 相似度 ∈ [0,1]
let dup = sim >= critic_dup_sim()                   // 0.70 判 **相似度** ✓
let ok = !dup && score_accept(combined, threshold)  // 0.85 判 **combined(新颖度加权)** ✓
```

**⇒ 两个阈值各判各的量，量纲没有串。**

### §2 任务 1 的实测（42 组扫描，`lane_bd_critic.py`）

```
② 扫描：novelty 与 sim 是否恒互补
  扫了 42 组（库 7 种 × note 6 种），不互补 0 组

③ 关键边界：空库 / 空 note
  items=[]        note='alpha' → novelty=1.0  sim=0.0  sum=1.0  ✓
  items=['alpha'] note=''      → novelty=1.0  sim=0.0  sum=1.0  ✓
  items=['']      note='alpha' → novelty=1.0  sim=0.0  sum=1.0  ✓
```

**④ 变异对照（阈值是承重的）**：
```
items=["alpha beta gamma"]
  note='alpha beta'              → sim=0.667
      dup_thr=0.60 → dup=True
      dup_thr=0.70 → dup=False     ← 默认
      dup_thr=0.80 → dup=False
  note='alpha beta gamma delta'  → sim=0.750
      dup_thr=0.60 → dup=True
      dup_thr=0.70 → dup=True      ← 默认
      dup_thr=0.80 → dup=False
```
**⇒ 改 dup_thr 会改变判定 ⇒ 这个阈值真的在起作用（不是装饰）。**

### §3 任务 1 的**核心发现**（未报 bug，但值得记）

```moonbit
// critic.mbt:64-68
let novelty = arc.novelty(note)               // ← 遍历 self.items 求 max_jaccard，再取 1-x
let sim = match critic_most_similar(arc, note) // ← **又**遍历 self.items 求 max_jaccard
```
**两处 loop 逐字相同**（都是 `for a in items { let j = jaccard(n, tokens(a.note)); if j > max {...} }`），
**遍历同一数据源**（`novelty` 用 `self.items`，`critic_most_similar` 用 `Archive::all` = `self.items` 的拷贝）。

**⇒ 同一个 `max_jaccard` 被算了两遍（O(2N)）**，而且**两份实现可以各自漂移**——
若将来有人只优化其中一处（比如加词权重、改 tokenize），另一处不会跟着变。

**为什么不报 bug**：
1. **现网等价**（42 组扫描 0 例外，数学上 `novelty = 1 - sim` 恒成立）
2. **它不产生错误结果**，只是冗余计算 + 漂移风险
3. **报成 bug 会让账本里出现「性能问题」条目**，与本仓 bug 账本语义（缺陷）不符

**⇒ 列建议：`sim` 已经算出来了，`novelty = 1.0 - sim` 可直接推**，
但现在 `novelty` 是 `pub` 且被别处调用（`evolve_distill.mbt:42` 的 `is_duplicate`），
**所以最小改动是在 `critic_review` 里让 `novelty` 复用 `sim` 的结果，不必动 `Archive::novelty` 本身。**

### §4 任务 2：omega 门禁的重复读数

```
$ grep -n 'omega_enabled(t)' src/engine/omega_strong.mbt
353:  if !omega_enabled(t) {      ← 在嵌套块里
383:  if !omega_enabled(t) {      ← 在嵌套块里
426:  if !omega_enabled(t) {      ← spec_create
510:  if !omega_enabled(t) {      ← spec_review
625:  if !omega_enabled(t) {      ← result_verify

$ grep -n 'omega_authorize_review(reviewer)'
501:  ← spec_review
616:  ← result_verify
```

**三个完整门禁的前置序列逐字对比**（`:420` / `:505` / `:620` 各取 13 行）：
```moonbit
let max_r = omega_norm_max_rounds(max_rounds)         ← 三处相同
let t = match self.store.get_task(task_id) {          ← 三处相同
  None => return Err("task not found: \{task_id}")    ← 三处相同
  Some(x) => x
}
if !omega_enabled(t) {                                ← 三处相同
  return Err(
    "任务 [\{task_id}] 未开启 Omega 强验证，...",       ← **只有这句文案不同**
  )
}
```
**⇒ 前 8 行**逐字相同**，第 9 行起的错误文案不同（`无需创建语料` / `无语料可审` / `无需成果复验`）。**

### §5 任务 2 的判定：两面，不是 bug

**判据**（你自己给的三分法）：
- **两者调同一函数 ⇒ 共用真源**：❌ 不完全 —— 它们调**同一个** `omega_authorize_review`
  和 `omega_enabled`，但**编排序列（`max_r` → `get_task` → 判 enabled → Err）各写一遍**
- **两者各写一份等价逻辑 ⇒ 两面**：✅ **是这一类**
- **两者各写一份不等价逻辑 ⇒ 真 bug**：❌ 不是

**⇒ 判定：两面（各写一份等价逻辑），0 条真 bug。**

**变异对照（回答「删掉语料审核的判据，成果复验是否受影响」）**：
```
两函数是**独立函数**，各含一份守卫 ⇒ 删掉 `:510` 那段的 omega_enabled 判据，
`:625` 的成果复验**完全不受影响**（它有自己的那份）。
⇒ 「各自的守卫独立」= 这正是「两份实现」的证据：
  共用真源的话，删一处会同时影响两处。
```

**为什么这算问题（而不是设计意图）**：
1. **错误文案不同是好事**（面向用户的提示更精确）—— 但**守卫逻辑相同**，可以「共用函数 + 传文案」
2. **5 处 `omega_enabled(t)` 将来任何一处漏掉**（比如新增第 6 个 omega 工具时），
   **没有机制会发现** —— 这正是 R12 `BUG-435` / R17 `BUG-438` 的同族
3. **`omega_authorize_review` 那 2 处**在**同一个函数序列的开头**，更容易被漏改

---

## 分析

### 量纲问题的正确答案：这次**没有**用错量，但「看起来像用错」

**你的怀疑是对的**（`0.70` 与 Jaccard/覆盖率混淆是经典错误），
**但本仓这处是对的**：`0.70` 判 `sim`（相似度），`0.85` 判 `combined`（新颖度加权），两个量各自匹配。

**为什么会看起来可疑**：`critic_review` 里同时出现 `novelty`、`sim`、`combined` **三个 [0,1] 标量**，
它们**互补但不相同**（`novelty = 1 - sim`，`combined = f(novelty, score)`）。
**读者若不追到 `Archive::novelty` 的实现，很容易以为 `0.70` 在判新颖度。**

**⇒ 这本身是一个可改进点**：变量名 `sim` / `novelty` / `combined` 都太短，
建议改成 `max_jaccard_sim` / `novelty_1_minus_sim` / `weighted_score`。

### 「各写一份等价逻辑」为什么比「各写一份不等价」更值得修

| 形态 | 危害 | 修法紧迫性 |
|---|---|---|
| 共用真源 | 无 | — |
| **各写一份等价**（omega 3 处 / evolve 前缀 2 处 / critic 2 处 Jaccard） | **现在无害，未来漂移** | **低但如果新增第 N 处就会漏** |
| 各写一份不等价 | **现在就错** | **高**（`BUG-438`） |

**⇒ 本仓已积累 3 处「等价的两面」（omega 门禁 / evolve 前缀 / critic 的 novelty-vs-sim）。**
**它们的共同成因**：**「多写 8 行能精确控制错误文案」的短期便利 > 「抽函数」的长期收益。**

### 与 R19 第三波的关系

R19 第三波我说这 7 面「零 bug」，并明确列了这两个「未查」。
**本波查完：仍然零 bug，但把两个「未查」变成了「已查 + 有具体读数 + 有具体建议」。**

**⇒ 这正说明「未查」必须写进报告 —— 不然下一波的人（包括我自己）会以为扫过了。**

---

## 缺口与风险

### 1. `evolve_distill` 的 `is_duplicate` 与 `evolve_critic` 的 `dup` 是**两个独立的重复判据**

`evolve_distill.mbt:42`：`Archive::is_duplicate(arc, goal_p, threshold=0.88)`
`critic.mbt:78`：`sim >= critic_dup_sim()`（0.70）

**两者阈值不同（0.88 vs 0.70）、函数不同**，判的是**同一件事（是否与档案库重复）**。
**⇒ 这是第 4 处「等价的两面」？还是有意分层（distill 更严、critic 更松）？**
**本轮未深究 —— 列为缺口。**

### 2. `omega_enabled` 的 5 处守卫没有机械判据

若新增第 6 个 omega 工具时漏写该守卫，**没有判据会发现**。
建议做成判据（扫 `omega_strong.mbt` 里所有 `pub fn FistEngine::omega_*`，要求每个都含 `omega_enabled`）。

### 3. 未跑真实执行

任务 1 的 42 组扫描是 **Python 复刻**（`tokens` 用近似正则），不是真跑 MoonBit。
**若 `@evolve.tokens` 的分词规则与我的复刻不同，结论可能变**（虽然互补关系是数学恒等式，不依赖分词细节）。

### 4. `critic_most_similar` 的 `Archive::all` 会**拷贝整个 items**

```moonbit
pub fn Archive::all(self) -> Array[Artifact] {
  let out : Array[Artifact] = []
  for (_, a) in self.items { out.push(a) }   // O(N) 拷贝
  out
}
```
`critic_review` 每次调用都做一次 **O(N) 拷贝 + O(N) 遍历**，而 `novelty` 又做一次 O(N) 遍历。
⇒ **总共 O(3N)**。**档案库变大后这是可测量的开销**（但当前规模未测）。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r20-evolve-omega-deep-check.md` |
| 扫描脚本 | `temp/audit/lane_bd_critic.py`（42 组量纲扫描 + 变异对照） |
| **建议后续** | ① `critic_review` 里 `novelty` 复用 `sim`（省 O(N)）② omega 3 处守卫抽「共用函数 + 传文案」③ **把「omega 工具必须含 enabled 守卫」做成判据** ④ 核 `is_duplicate(0.88)` vs `critic_dup_sim(0.70)` 是否该统一 |
| **未做** | **未调 `bug_fix`**（0 条真 bug）· **未改 `src/`** · **未跑 MoonBit 执行**（Python 复刻） |
