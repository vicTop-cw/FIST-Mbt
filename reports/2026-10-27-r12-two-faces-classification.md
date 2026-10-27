# R12 · `check_two_faces.py` 精度修正 + rc 契约 + 执行面

> **任务**：① 66 处漂移逐条分类 ② 定 rc 契约 + 运行时覆盖率输出 ③ 补执行面（判例-5）
> **执行人**：司令-γ · **边界**：只改 `scripts/`（未碰 `src/` 与 25 个在途文件）
> **产出**：本报告 + `scripts/check_two_faces.py`（判据）+ `scripts/run_guards.py`（执行面）

---

## 结论

| 项 | 结论 |
|---|---|
| **66 处真/误报比例** | **真漂移 0 处 / 误报 66 处 = 100% 误报** |
| **`store_rsv.mbt` 那条真假** | **误报**。`rsv_action` 用严格 `<`，SQL 也用严格 `<` **两侧一致**；我抓到的 `>=` 来自**另一条逻辑**（`locks_upsert` 的「旧锁是否仍 live」），不是 `rsv_action` 的投影 |
| **R10 的「两后端等价」结论** | **不需要修正** —— 结论正确，是我这一版判据抓错了对象 |
| **rc 契约** | **0 干净 / 1 有漂移 / 2 判据无法自证**（`check_fmt_gate.py` 先例），已实测三档 |
| **执行面** | **已进电池**（`run_guards.py:165-166`，`--selftest` + 判据两格）；`check_battery_count_doc` **PASS** `rulers=121 battery=80 missing=0` |
| **selftest** | **20/20 格通过**（含 2 个变异对照 + 4 个覆盖率输出格） |
| **精度修正后** | 可判对象 **93 → 1**，漂移 **65 → 0** |

---

## 证据

### §1 66 处逐条分类

**原始读数**（修正前）：`F1 violations 65 + F3 violations 1 = 66`，而 `rc=0`（未定契约）。

#### 误报类型 A（主因，~60 处）：「使用关系」被当成「副本关系」

**判据只需要一个 `::fname` 引用就认为「声称自己是 f」，但代码里 `X::f` 的常见用法是「我用了它」。**

| 实例 | 注释原文 | 真相 |
|---|---|---|
| `server.mbt:142 task_ns_of -> to_json`（**重复 17 次**） | 「从任务 JSON 读它的 ns 标签（**`Task::to_json` 的 `"namespace"` 键**）」 | 在说**从 `to_json` 的输出里取值**，不是「我是 `to_json` 的副本」 |
| `engine_contract.mbt:5 contract_target_status -> to_string`（重复 6 次） | 提到 `Status::to_string` | 同上：调用来着 |
| `ops_hats.mbt:196 hat_verdict -> new`（重复 **21 次**） | 「跨包构造必需……（与 `@engine.FistEngine::new` 同约定）」 | **说的是「同约定」**（都是构造函数），不是「同实现」 |
| `multi_store.mbt:158/199/285/344 -> open` | 各处提到 `SqliteStore::open` | 调用 |
| `server.mbt:58 ns_reject_reason -> safe_ns` / `write_gate.mbt:157 -> safe_ns` / `model_router_ops.mbt:11 -> safe_ns` | 提到 `safe_ns` 判据 | 复用判据，不是副本 |

**⇒ 这一类**全部**是「同名 ≠ 同义」**：`to_json`/`new`/`open`/`safe_ns` 在注释里被**提及**，
但被检函数与它们**不是同一个东西**。

#### 误报类型 B（4 处）：「等价于」的语义近似被当成副本

| 实例 | 注释原文 | 真相 |
|---|---|---|
| `server.mbt:1574 instrumented_tool == _instrument` | 「注册一个带自动 call_log 的工具（**等价于 `.tool`**，但 handler 经 `_instrument` 包装）」 | 「功能等价于另一个 API」，**不是在说自己是副本** |
| `ops_watchdog.mbt:228 watchdog_newer_task == watchdog_ts_newer` | 「b 是否比 a「更新」（**等价于 `watchdog_ts_newer`**）」 | **语义相同但实现独立**（一份比 ISO 串、一份比解析后的秒），**不该合并** |
| `router_caf_ext.mbt:74 caf_normalize_context == caf_feature_hash` | 「问题：`caf_feature_hash` 直接对……**大小写与空白敏感**」 | 在**描述要解决的问题**，不是副本 |
| `issue_scan.mbt:1661 scan_guard_prefix_literal == has_prefix` | 「该字符串（或其 `to_owned()` **等价副本**）已被 `has_prefix` 判定」 | **值相等**，不是函数副本 |

#### 误报类型 C（1 处）：F3 比较符跨逻辑域混抓

**`store_rsv.mbt SQL=['<','>='] MB=['<']`** —— 这是你特别点名要核的那条。

**逐字对比**：

```
MB 侧（rsv_action，store_rsv.mbt:104）：
    Some((_, ttl, _)) if ttl < now => (true, "taken_over")        ← 严格 <

SQL 侧（store_sqlite.mbt，两处 ON CONFLICT）：
    WHERE reservations.agent = excluded.agent
       OR reservations.ttl_until < excluded.created_at            ← 严格 <（一致 ✓）
    WHERE file_locks.agent = excluded.agent
       OR file_locks.status <> 'active'
       OR file_locks.ttl_until < excluded.ts                      ← 严格 <（一致 ✓）
```

**那个 `>=` 从哪来？** `store_rsv.mbt:303`：
```moonbit
pub fn MemoryStore::locks_upsert(...) {
  match self.file_locks.get(lock.scope) {
    Some(old) if old.status == "active" && old.agent != lock.agent &&
      old.ttl_until >= lock.ts =>            // ★ 这里是 >=
```

**但这不是 `rsv_action` 的投影** —— 它判的是「**旧锁是否仍 live**」（决定要不要记 `lock_taken_over` 违例）。
`>=` 在这里**语义正确**：`ttl_until == ts` 即锁恰好到期，仍算 live。
**这是另一条规则，我的 F3 把它和 `rsv_action` 的投影混在一个文件里抓了。**

**⇒ 判定：F3 那处是**误报**。R10 的「两后端等价」结论**不需要修正** —— 结论对，是我这一版判据抓错了对象。**

### §2 修正后的读数对比

| 指标 | 修正前 | 修正后 |
|---|---|---|
| F1 可判对象 | 93 | **1** |
| F1 漂移 | **65** | **0** |
| F3 漂移 | 1 | **0**（且对表成功：SQL=`['<']` MB=`['<']` ✓） |
| 合计漂移 | **66** | **0** |
| rc | 0（未定契约 → 与结论矛盾） | **0**（真干净） |

**修完只剩 1 条可判对象，正是 `BUG-435` 那一对** —— 且它 **✓ 等价**。
**⇒ 判据现在既不误报，也没漏掉已知的那一个真对象。**

### §3 rc 契约实测（三档全验）

```
$ python scripts/check_two_faces.py            ; echo $?
... [结论] 形态 ①②③ 无漂移 ...
0                                   ← 干净

# 注入漂移：把 constraint.mbt 的 ttl < now 改成 ttl <= now
$ python scripts/check_two_faces.py            ; echo $?
  ✗ DRIFT src/constraint/constraint.mbt:57 rsv_conflict_verdict ≠ src/store/store_rsv.mbt:91 rsv_action
  [结论] 发现 1 处漂移（形态 ①②③ 范围内）
1                                   ← 有漂移（逐条点名）

# 空扫描面 ⇒ rc=2（selftest 的 empty-scan-self-reject 格钉住）
2                                   ← 判据无法自证
```

**⇒ 与 `check_fmt_gate.py` 的 0/1/2 先例一致，未新造口径。**

### §4 运行时覆盖率输出（样例，逐字）

```
$ python scripts/check_two_faces.py
[覆盖面] 本判据只覆盖 3/5 种「两面」形态：
  ✅ ①真源 vs 另一套执行点（同语言多实现）
  ✅ ②真源 vs SQL 编码（ON CONFLICT / WHERE 谓词）
  ✅ ③真源 vs 手工抄本（注释声称「镜像/等价」的重复定义）
  ❌ ④真源 vs 消费面的前提 —— 需要枚举「该面的前置条件」，那通常不写在代码里（BUG-433）
  ❌ ⑤真源 vs 胶水的语义 —— 需要状态机时序建模，每步单看都合法（BUG-431 / BUG-429）
[结论] 本脚本 PASS 不代表「无两面」，只代表「形态 ①②③ 无两面」。
```

**selftest 里 4 格专门钉住它**（`coverage-3of5-in-output` / `coverage-names-form4` /
`coverage-names-form5` / `coverage-pass-not-full`）⇒ **输出里不写覆盖率，判据自己红。**

### §5 执行面（判例-5）

```python
# scripts/run_guards.py:165-166
    # —— R12：「两面」漂移普查判据（形态 ①②③）——
    # 本仓 6 天内因同一根因踩了 5 次（BUG-420/425、R10 内存vs SQLite、R10 SQL 谓词、BUG-435 抄本）。
    # **覆盖面 3/5**：④消费面的前提、⑤胶水的语义 不在覆盖面内（需人工判据）——
    # 判据自己是运行时输出覆盖率声明的，PASS **不代表无两面**。
    case("check_two_faces.py", "--selftest"),
    case("check_two_faces.py"),
```

```
$ python scripts/check_battery_count_doc.py
PASS 电池读数与 README 登记逐键一致：rulers=121 ci=46 battery=80 missing=0 gate=88 exempt=28 unclassified=7
```

**⇒ `missing=0`，不缺面。**

### §6 selftest 20 格

```
[OK] copy-identical-no-drift / copy-identical-f1-count / copy-identical-no-violation
[OK] MUTATION-copy-drift-detected      ← ★变异对照1：抄本改坏 1 字符 ⇒ 必红
[OK] MUTATION-drift-count
[OK] MUTATION-lt-vs-le-detected        ← ★变异对照2：< 改 <= ⇒ 必红
[OK] comment-literal-no-false-red      ← 判例-30：注释字面量不自命中
[OK] empty-scan-self-reject / empty-scan-has-note   ← 空扫描自拒 rc=2
[OK] multi-def-detected / multi-def-count / multi-def-does-not-fail
[OK] coverage-3of5-in-output / coverage-names-form4 / coverage-names-form5 / coverage-pass-not-full
[selftest] 20/20 格通过
```

---

## 分析：「同名 ≠ 同义」——按判定形状搜带来的新问题

**你说得对：这是本轮最有价值的发现，而且方向和我上一轮说的「术语别名会遮蔽普查」正好相反。**

| 上一轮（遮蔽） | 本轮（误报） |
|---|---|
| 同一件事有**多个名字** ⇒ 按名字搜**漏掉** | 同一个名字有**多种事** ⇒ 按名字搜**误报** |
| 形态：别名 / 缩写 / 中英混用 | 形态：`to_json`/`new`/`open`/`safe_ns`/`has_prefix` 这些**高频通用名** |
| 后果：以为干净，其实有漂移 | 后果：66 处噪声，**真漂移被淹没**，且 rc 无法定 |

### 具体形态（三种，各有对策）

**A. 「提及」≠「声称副本」**（~60 处）
`/// 从 `Task::to_json` 的 `"namespace"` 键读` —— `::to_json` 是**路径的一部分**，不是断言。
**对策（已实施）**：要求**等价声称词**（`忠实镜像`/`的镜像`/`抄自`/`duplicate of`）**同时出现**，
且参照名可解析。光有 `::name` 一律不算。

**B. 「语义近似」≠「实现副本」**（4 处）
`等价于 .tool`（功能等价）、`等价于 watchdog_ts_newer`（语义相同但实现必须独立）、
`等价副本`（值相等）。
**对策（已实施）**：把 `等价`/`等价于` **从声称词里剔除** —— 它在中文本仓里**绝大多数场合表示
「功能/语义相同」而非「代码是副本」**。只留强副本词。

**C. 「跨规则混抓」**（1 处 F3）
同一个文件里有**多条规则**（`rsv_action` 的判定、`locks_upsert` 的 live 判定），
我按文件抓比较符 ⇒ 把 B 规则的 `>=` 算到 A 规则的账上。
**对策（已实施）**：F3 改成**只取 `rsv_action` 函数体** + **只取 `ON CONFLICT...WHERE` 子句**，
两侧各自限定在「同一条规则」的作用域内。

### 一条可推广的判据观

> **按「形状」搜（同名、同签名、同注释词）只能给出**候选**，不能给出**结论**。
> 候选到结论之间必须有一层「**它们是不是同一个东西**」的判定 ——
> 而那层判定恰恰是最难机械化的。**
>
> **⇒ 所以这类判据的正确形态是：高精度 + 低召回，宁可只报 1 条真候选，也不要报 66 条噪声。**
> **因为「66 条噪声 + rc=0」等于什么也没说；而「1 条候选 + 明确说只看这个」至少是可信的。**

**这与「3/5 覆盖率必须写在输出里」是同一件事的两面**：
**判据必须把自己的「有效范围」和「判别力」同时说清**，否则它只是一个报告生成器。

---

## 缺口与风险

### 1. F2（同签名多定义）**只告警**，且量很大（78 组、其中一组 4 处）

示例：`archive` 在 `core_task.mbt:509`（状态机）与 `engine.mbt:802`（引擎转发）——
**不同层，不是漂移**。`assistant_get` 4 处（engine/store/memory/sqlite）——
**其中 memory vs sqlite 是真该对表的一对**（R10 那条）。

**⇒ F2 现在的作用是「列候选清单」，不是判据。这是对的（多后端是合法设计），但也意味着
「形态 ①」实际上只是**列出了可能的面**，没有**判定**它们是否一致。**
**⇒ 缺口：形态 ① 的「判定」仍需 R10 那种专门的探针（真跑两后端）。**

### 2. F3 只覆盖「已存在于注释里的声称」

若有人写了 `ON CONFLICT ... WHERE` 但**没在注释里说「同一条规则」** ⇒ F3 不查。
**⇒ 这是「依赖注释」的判据，注释缺失就失效。** 应在后续把「有 `ON CONFLICT` 就查」升级为无条件。

### 3. 形态 ④/⑤ 仍不可判据化（本轮无进展）

这不意外 —— 它们需要「枚举前置条件」与「状态机时序建模」，都不是静态文本匹配能做的。
**本脚本的输出已明说这一点。**

### 4. 本轮未能验证「判据在真仓上的稳定性」

修正后 `rc=0` 只跑了一次。**若别的 lane 正在改 `constraint.mbt`（我观察到 `src/engine/`+
`src/core/` 有 25 个在途文件），下一次跑可能就红。** ⇒ 那是**判据正常工作**，不是误报。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r12-two-faces-classification.md` |
| 判据 | `scripts/check_two_faces.py`（含 20 格 selftest，2 个变异对照） |
| 执行面 | `scripts/run_guards.py:165-166`（判例-5 已满足） |
| `BUG-435` | **保持 low**（孤立包、现网等价、无生产路径）；本报告 §1 为其「等价」判定补了实测依据 |
| **R10 结论** | **不需要修正** —— §1「误报类型 C」已证明是判据抓错对象，不是后端不等价 |
| **建议后续单** | ① 形态 ① 的「判定」（非列表）仍需 R10 式探针 ② F3 去掉「依赖注释」这一前提 |
| **未做** | **未调 `bug_fix`**（无 bug）· **未改 `src/`** |
