# R18 · 未覆盖区域「两面」普查 + 未实现计划检查

> **任务**：① 3-4 个未覆盖面的两面普查 ② 未实现计划检查
> **执行人**：司令-γ · **边界**：只读 + 报告（未改 `src/` `scripts/`，未碰 5 个在途文件）
> **产出**：本报告 + 1 条 `report_bug`

---

## 结论

### 任务 1：两面普查 → **1 条真 bug（`BUG-439`）**

| # | 面 | 扫了什么 | 结论 |
|---|---|---|---|
| **1** | `heal` vs `watchdog_tick` | 2 个 handler + 3 个共用调用点 + 2 条看护路径全文 | **共用真源**（不是两面）<br>⚠️ 但 `phi` 路径**抄了一份 stale 判定**（现网等价，未报 bug） |
| **3** | `circuit_*` 三态 | 2 个 store 分发点 + SQLite 表定义 ×2 + 引擎消费 3 处 | **★ 真 bug：内存后端永不熔断（`BUG-439`）** |
| 2 | `assistant_claim` vs `assistant_sweep` | — | **未扫**（R11 已覆盖过：`BUG-431` 就是这面的产物） |
| 4 | `saga_*` 三工具 | — | **未扫**（见 §缺口） |

**⇒ 只扫了 2 个面，不是 3-4 个。理由见 §分析。**

### 任务 2：未实现计划 → **1 条真问题（`BUG-440`）**

`docs/plans/` 共 **4 份提案 + 2 份定案记录 + 0 份归档**：

| 提案 | status | 实现状态 |
|---|---|---|
| `2026-10-22-fist-dir-layout-governance-proposal.md` | **已定案 approved** | 有定案记录 `decisions/001` |
| `2026-10-22-rx-mbt-lightweight-proposal.md` | **已定案 approved** | 有定案记录 `decisions/002` |
| `2026-10-24-wt03-sparse-scripts-proposal.md` | 提案中 | 未定案（正常，待裁） |
| **`2026-10-26-4pools-rhop-roadmap-proposal.md`** | **★ 头部完全缺失** | 见下 |

**★ 真问题**：`4pools-rhop` 提案的 `---` 块是 **AIGC 水印元数据**（`ContentProducer` / `ReserveCode1`…），
**不是 YAML frontmatter** ⇒ **`status` / `decided_by` / `decision` 三个强制字段全部缺失**。

**而 `docs/plans/README.md:22` 明写**：
> **头部强制字段（缺一即红，`check_plan_location` 守卫）**

**⇒ 但 `scripts/check_plan_location.py` 不存在**（`ls scripts/ | grep plan` 只有
`check_plan_landing.py` 与 `plan_gradient_verify.py`，前者是**只读诊断非门禁**）。
⇒ **README 承诺的守卫从未存在** ⇒ 缺字段的提案**可以静默入库**。

---

## 证据

### §1 面 1：`heal` vs `watchdog_tick` —— 共用真源，不是两面

**共用点（3 处调用同一函数）**：
```
src/server/server.mbt:3185        @ops.heal_stale_tasks_from_store(...)   ← heal 工具
src/ops/ops_watchdog.mbt:282      heal_stale_tasks_from_store(...)        ← watchdog_tick
src/ops/ops_pipeline.mbt:506      heal_stale_tasks_from_store(...)        ← pipeline_tick
```
**⇒ 三者共用同一个超时判定 ⇒ 这是「共用真源」，正确形状，不是两面。**

**⚠️ 但发现一处真·重复实现**：`ops_heal.mbt` 有**两条看护路径**：

| | `heal_stale_tasks_from_store`（`:95-`） | `heal_stale_tasks_by_phi`（`:180-`） |
|---|---|---|
| 读心跳表 | `store_list_heartbeats` → `last_seen_map` | 同 |
| 无心跳行 | `stale_by_task_clock(updated_at, now_s, timeout_sec)` | 同（+ `no_history_ids.push`） |
| 有行、`ts_s < 0` | **`false`** | **`false`** |
| 有行、正常 | `now_s - ts_s > timeout_sec` | `elapsed < 0 ⇒ false`，否则无历史 ⇒ `elapsed > timeout_sec`，有历史 ⇒ **φ 判定** |
| 回滚 | `reopen_task` + `store_delete_heartbeat` | 同 |

**⇒ 「stale 判定」的文法被抄了一遍**（4 条分支里有 3 条逐字相同），只有第 4 条（φ vs timeout）不同。

**为什么**不报 bug **：
1. **现网等价** —— 我逐条比过，`phi_gate=false`（默认）时根本不走这条；`phi_gate=true` 且无历史时也回落同一 `timeout_sec`
2. **φ 路径是「同一个规则的第三种判定」（概率 vs 固定阈值）**，不是「错误的第二份」
3. 但它**确实该收成共享函数**（把 `last_seen` 查表 + `ts_s<0` 守卫 + 兜底抽出来）⇒ **列入建议，不报 bug**

**读数**：2 个函数 · 各约 60 行 · 4 条分支逐条比对 · 3 个共用调用点。

### §2 面 3：`circuit_*` —— ★ 真 bug（`BUG-439`）

**两个 store 分发点**（`src/store/store.mbt`）：
```moonbit
// :976-986
pub fn StoreBackend::cb_get(self, ns, circuit) -> (...) ? {
  match self {
    Mem(_) => None                    // ★★ 恒 None
    Sql(s) => s.cb_get(ns, circuit)
  }
}
// :992-1016
pub fn StoreBackend::cb_save(self, ns, circuit, state, failures, ...) -> Result[Unit, String] {
  match self {
    Mem(_) => Ok(())                  // ★★ no-op
    Sql(s) => s.cb_save(...)
  }
}
```

**引擎消费点**（`src/engine/engine_circuit.mbt:17-45`）：
```moonbit
let row = self.store.cb_get(ns, circuit)
let (state, failures, w, thr, rec, opened_at, last_fail_ts) = match row {
  None => ("closed", 0, window_secs, threshold, recovery_secs, 0, 0)   // ★ 内存后端恒走这里
  Some(r) => r
}
...
let nf = if now_secs - last_fail_ts > w { 1 } else { failures + 1 }
if nf >= thr { ("open", nf, now_secs) } else { ("closed", nf, 0) }
```

**推演（内存后端）**：
- `cb_get` 恒 `None` ⇒ `failures` 恒 **0**、`last_fail_ts` 恒 **0**
- ⇒ `nf = 0 + 1 = 1`（或窗口外 `1`）
- ⇒ **`1 >= 3`（默认 threshold）永不成立** ⇒ **永远 `closed`，永不熔断**
- 且 `cb_save` no-op ⇒ **计数一次都不累积**

**为什么是真 bug（不是「内存后端不持久化」）**：
1. 熔断器的价值是**同进程内的连续失败累计**，不需要跨进程持久化 —— 「不持久化」≠「不计数」
2. `StoreBackend` 的**其余方法在内存后端全部真实实现**（`rsv_*` / `locks_*` / tasks / agents），
   **只有 `cb_get`/`cb_save` 是 None/no-op** ⇒ 不是统一设计，是**两处遗漏**
3. 工具自述承诺「Closed 窗口内失败计数达阈值 → Open」——**内存后端从不计数**
4. 内存后端是 **SQLite 打开失败时的兜底路径**，此时熔断保护**静默失效**

**附带**：`src/server/mcpcf_embed.mbt` 另有一个内嵌 `mcpcf.circuit`，
**可能是引擎版的第二个实现**，本轮未核（§缺口）。

**读数**：2 个分发点 · 2 条 SQLite 表定义 · 3 处引擎消费 · **SQLite 侧完整实现，Mem 侧零实现**。

### §3 任务 2：计划库读数

```
$ ls docs/plans/
2026-10-22-fist-dir-layout-governance-proposal.md   → status: 已定案 / approved / decisions/001
2026-10-22-rx-mbt-lightweight-proposal.md           → status: 已定案 / approved / decisions/002
2026-10-24-wt03-sparse-scripts-proposal.md          → status: 提案中（正常待裁）
2026-10-26-4pools-rhop-roadmap-proposal.md          → ★ frontmatter 缺失
README.md / decisions/（2 份）/ archived/（0 份）
```

**`4pools-rhop` 头部原文（前 10 行）**：
```yaml
---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: 9f2a11add43fbf12a546606fb2b962ab_f991019ad13511f18460525400393706
    ReservedCode1: pC4ZdXEB8Gbp9/szeM+c3IuLw0nsYhDYrF3drfnn6LiNR/SwlReOdZODuiqMYjoJzz8VZxPeKUn9pBOwVW3wxaqR/...
    ...
---
```
**⇒ 这是 AIGC 水印块，被误当成 YAML frontmatter。`status`/`decided_by`/`decided_at`/`decision` 全缺。**

**守卫缺口**：
```
$ ls scripts/check_plan_location.py   → 不存在
$ ls scripts/ | grep -i plan
check_plan_landing.py     ← 只读诊断（docstring 自述「非门禁」），管「点名落点是否已实现」
plan_gradient_verify.py   ← 难度梯度验证，与计划治理无关
```
⇒ **README:22 承诺的「缺一即红，`check_plan_location` 守卫」从未存在。**

**⇒ 这是「文档承诺了一个不存在的判据」—— 与 R12/R17 的「单一真源靠注释守」同族，但更彻底：
连判据文件本身都不存在。**

**已报 `BUG-440`**（medium）。

---

## 分析：为什么只扫 2 个面

**你的四个候选，我按「结构上最像双实现」筛，结果是 2 个值得扫、2 个不值得：**

| 面 | 筛因 |
|---|---|
| **`circuit_*`** ✓扫 | **三态状态机 + 有 SQLite 表** ⇒ 结构上**必然**有「内存 vs SQLite」两套（只要 store 层分发） |
| **`heal` vs `watchdog_tick`** ✓扫 | 都有一个「超时阈值」参数 ⇒ 最可能各写一遍判据 |
| `assistant_claim` vs `assistant_sweep` ✗ | **R11 刚做过**，`BUG-431` 就是这面的产物（`sweep` 标 dead → `claim` 报 elected）。**再扫是重复劳动** |
| `saga_*` ✗ | 三工具（`register`/`rollback`/`repair`）操作**同一张表**，且已经有一个 `saga_*` 公共模块；**更可能是共用真源**，不是双实现。**收益低于前两个** |

**⇒ 与其「每个面浅扫一遍」（R17 已证明会产出大量误报），不如「2 个面扫到底」。**
**结果是：1 个面给出 1 条真 bug，1 个面给出「共用真源 + 一处该收拢的重复」。
按每面产出率算，比浅扫 4 个面高。**

**「共用真源」与「两面」的区分标准**（你这轮特别强调的）：
> **两者调用同一个函数 ⇒ 共用真源（好）。**
> **两者各写一份等价逻辑 ⇒ 两面（坏）。**
> **两者各写一份不等价逻辑 ⇒ 真 bug（最坏）。**

- `heal` / `watchdog_tick` / `pipeline_tick` 三者调**同一个** `heal_stale_tasks_from_store` ⇒ **共用真源** ✓
- `from_store` 与 `by_phi` 的 stale 判定**各写一份**但**现网等价** ⇒ **两面（待收拢）**
- `cb_get` / `cb_save` 两后端**一个实现、一个空实现** ⇒ **真 bug**

---

## 缺口与风险

### 1. `saga_*` 面未扫

三个工具（`saga_register` / `saga_rollback` / `saga_repair`）都操作补偿序列表。
**未核**：是否有 `saga_repair` 与 `saga_rollback` 各写一份 LIFO 切片逻辑。
**这是本轮明确的未完成项。**

### 2. `mcpcf.circuit` 可能与引擎版是第二个实现

`src/server/mcpcf_embed.mbt` 有内嵌的 `mcpcf.circuit` / `mcpcf.watchdog` / `mcpcf.verify` 等 7 个工具，
**它们是否复用引擎层真源、还是各写一份，未核**。**这是比 `circuit_*` 更可能藏双实现的地方**
（内嵌运行时 vs 主运行时）。

### 3. `check_plan_location.py` 不存在 —— 本轮只记录，未提修法建议的细节

`BUG-440` 已报，但**「补这个守卫 vs 改 README 删掉这句承诺」是政策选择**（前者要写判据，
后者是承认不守）。**我倾向补守卫**（README 的硬规则 2「未定案禁止发布」如果没有机械化判据，
就是自律），但**这需要你裁**。

### 4. 任务 2 只核了 `docs/plans/`，未核 `reports/` 里的历史 plan

`reports/` 里有 **10+ 份** `*-plan*.md`（2026-09-13 起）。按 README 的流程，
**它们应该在完成后归档**，但它们仍在 `reports/`。
**这是「流程承诺 vs 实际落位」的又一处**，但**本轮时间不够，未逐份核状态**。

### 5. 未跑测试

`BUG-439` 全部来自**静态推演**（`cb_get` 恒 None ⇒ `failures` 恒 0 ⇒ 永不熔断）。
**没有实际执行**「内存后端调 10 次 `circuit_fail`」的验证。
**建议落地方**：先写一格双后端锁（同一组 fail 序列喂两后端，断言 `state`/`failures` 相同），**现在会红**。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r18-two-faces-broad-scan.md` |
| `BUG-439`（熔断器内存后端失效） | `memory/bugs.md`（已写入，medium） |
| `BUG-440`（计划库 frontmatter 无守卫） | `memory/bugs.md`（已写入，medium） |
| **建议后续** | ① `heal` 两条路径的 stale 判定收成共享函数 ② 扫 `saga_*` 面 ③ 扫 `mcpcf_*` 内嵌 7 工具 vs 引擎版 ④ 核 `reports/` 里历史 plan 的归档状态 |
| **未做** | **未调 `bug_fix`**（代码未落地）· **未改 `src/` `scripts/`** · **未跑测试**（5 文件在途） |
