# R6 寻虫 Round 2 报告 · BUG-330 核销判定 + 换方向寻虫（方向 A/B）

> **任务**：① 核 BUG-330 是否仍有效（三选一必给结论）② 换方向找 bug（不走 `issue_scan` low 档）
> **执行人**：司令-γ · **边界**：只读 + 写报告，未改任何 `src/`
> **产出**：本报告 + `temp/audit/lane_y_*.py` + 2 条 `report_bug`

---

## 结论

| 项 | 结论 |
|---|---|
| **BUG-330** | ✅ **已失效（现象不复现）** —— 但**不是「已修」**，见 §1 的三选一论证 |
| **本轮真 bug** | **2 条**：`BUG-426`（high）· `BUG-427`（medium） |
| **用了哪个方向** | **方向 B（运行期语义/状态一致性）主攻 + 方向 A（跨函数数据流）副攻** |
| **方向 A 的产出** | **0 条**（`get_task` 163 调用点、`jget` 99 调用点逐个核过，处置全正确） |
| **方向 B 的产出** | **2 条**（都在 `core_task.mbt` 的状态迁移字段流上） |

---

## 证据

### §1 BUG-330 三选一：**已失效（现象不复现），建议 FALSE_POSITIVE**

**原条目的主张**（`memory/bugs.md` `## BUG-330`）：
> moonc/moonfmt **0.10.16** 把 `Int` 规范化打印成 `Int32` —— `moon fmt --check` 与 `.mbti` 生成面
> 在新版下与仓库存量拼写**系统性不一致**；`moon check` 成功后会把 24 份 `pkg.generated.mbti`
> 里的 `Int` 改写成 `Int32`。

**复现尝试 1（moonfmt 是否改写 `Int`）**：最小工程直调 `moonfmt.exe`：

```
$ cat t.orig.mbt
///|
fn pick(x : Int) -> Int {
  let y : Int = x
  y
}

///|
fn pick2(x : Int32) -> Int32 {
  x
}

$ cp t.orig.mbt t.mbt && ~/.moon/bin/moonfmt.exe t.mbt
$ diff t.orig.mbt t.mbt
（无差异 —— Int 未被改写）
```

**⇒ 现象不复现。** 当前 `moonfmt` 不再把 `Int` 改写成 `Int32`。

**复现尝试 2（`.mbti` 生成面）**：

```
$ grep -rn ': Int\b' src/ --include=*.mbti
（空 —— 全部已是 Int32）
$ 混用检查（40 份 .mbti 里同时含 Int32 与 Int 的）
（无 —— 无混用）
```

**⇒ `.mbti` 面已经是 `Int32`，不存在「与存量拼写不一致」。**

**复现尝试 3（仓库存量拼写分布 —— 现象方向已反转）**：

```
.mbt 面：  : Int32 = 461 处   /  : Int = 47 处      ← 已经是 Int32 主流
.mbti 面： : Int32 = 173 处   /  : Int = 0 处       ← 全 Int32
```

**⇒ 条目描述的「全仓存量都写 `Int`」已经不成立，现在是「存量就是 `Int32`」。**

**三选一结论**：

> **✅ 已失效 —— 建议 `bug_mark_status(BUG-330, FALSE_POSITIVE)`，evidence 写：
> 「现象不复现：moonfmt 0.1.20261016 直调最小工程对 `Int` 零改写；`.mbti` 面 173:0 全 Int32、
>  `.mbt` 面 461:47 已是 Int32 主流 ⇒ 条目主张的『全仓存量写 Int、new moonfmt 要 Int32』方向已反转，
>  原始缺陷（0.10.16 版的行为）在当前钉版下不可复现。**不是『已修』**：没有找到任何一笔提交宣称修它，
>  更可能是 moon 工具链换代后行为自然改变，故按 FALSE_POSITIVE（现象不成立）而非 FIXED（有修复动作）。」**

**为什么不报「已修但没销账」**：我没有找到任何针对 BUG-330 的修复提交（`git log --grep=BUS-330 / 330` 无命中），
且工具链版本已从 `0.10.16` 换到 `0.1.20261016`。**「现象消失」与「有人修了」是两件事**——
按判例-25 同族的口径，我不把「读数变了」记成「修好了」。

**⚠️ 但有一条真实残留（不是 BUG-330，另立）**：
`.mbt` 面仍有 **47 处 `: Int`**，`.mbti` 面 **0 处**。两边**拼写不统一**虽然目前无害
（moonfmt 不改写、`check_mbti_sync.py` 只判 `pub fn` 名字不判类型拼写），
**但那 47 处是历史残留，不是「系统性红」**。**不构成需要排期的缺陷**，建议顺手清或不理。

---

### §2 方向 A（跨函数数据流 · `Option` 解包）—— 0 条真 bug，逐点论证

#### A-1 `get_task` 面（163 个调用点）

```
$ grep -rn '\.get_task(' src/ --include=*.mbt | wc -l        → 163
$ grep -rn 'match .*\.get_task(' src/ --include=*.mbt | wc -l → 133
差集 30 —— 逐个核过，全部是以下三类之一，**无一漏判**：
```

| 形态 | 处数（生产代码） | 处置 | 是否 bug |
|---|---|---|---|
| `match ... get_task(...)` | 133 | 显式 None 分支 | 否 |
| `... get_task(x) is None` / `is Some(_)` | 5 | 显式判定 | 否 |
| `.unwrap_or(兜底值)` | 1（`engine.mbt:301`） | 有兜底 | 否 |
| 透明转发 `self.store.get_task(id)` | 1（`engine.mbt:852` `FistEngine::get_task`） | 返回类型就是 `Task?`，转发不改语义 | 否 |
| 文档注释里提到 `get_task(id)` | 2（`engine_dag_mc.mbt`） | 非代码 | 否 |
| `store.mbt` / `store_sqlite.mbt` 的**定义/实现** | 3 | 不是调用点 | 否 |

**逐点抽查（最需怀疑的 3 处）**：

1. `engine.mbt:299-309` —— `unwrap_or(@core.Task::new(id=task_id, project_dir="", description="", created_at=now))`
   ⇒ **有兜底**，且 `publish` 刚写入后立刻读，None 分支理论上不可达。
2. `engine.mbt:849-853` —— `pub fn FistEngine::get_task(self, task_id) -> @core.Task? { self.store.get_task(task_id) }`
   ⇒ **透明转发**，签名声明为 `Task?`，调用方仍需自己 match。**不是 bug**（但见 §4 盲区-1）。
3. `engine_dag_ext.mbt:293-303`（`add_depend`）—— 两处 `match`，`None => return Err(...)`
   ⇒ **显式拒绝**。`_dep` 用 `let _dep = match`（unused 命名）但**确实 match 了**。

**⇒ 方向 A 在 `get_task` 面无 bug。**

#### A-2 `jget` 面（99 个调用点）

```
99 调用点 / 86 处 match —— 差集 13 处逐个核过：
```
- `json_or(jget(x, k), Json::null())` 形态（`gate.mbt:104/133/142/211/266/377` 等）：**有默认值兜底**
- `gate.mbt:333-346` `check_expected`：`let field = jget(expected,"field")` 后**紧接 `match field { Some(String(f)) => ... }`**
  ⇒ 正确
- 其余匹配处均有 `Some/None` 两分支

**⇒ 方向 A 在 `jget` 面也无 bug。**

**方向 A 总产出：0 条。** 这与 Lane C 的 `issue_scan` 结论形成对照：**不是「没找到」，是「这个仓的 Option 面本来就被写得规整」**。

---

### §3 方向 B（运行期语义）—— 2 条真 bug

#### B-1 · `BUG-426` [high] —— `reject`/`retry` 不清空 deliverable

**代码定位（三处合起来构成缺陷）**：

| 文件:行 | 现状 | 问题 |
|---|---|---|
| `core_task.mbt:557` `Task::reject` | `Ok({..self, status: Rejected, description: ...})` | **deliverable 原样保留** |
| `core_task.mbt:580` `Task::retry` | `Rejected => Ok({..self, status: Executing,})` | **deliverable 原样保留** |
| `engine.mbt:599` `FistEngine::submit` | 无任何 deliverable 检查 | **直接 Executing→Reviewing** |

**缺陷路径（状态机完全合法，每步都不报错）**：
```
execute(deliverable="旧的不合格交付物 A")  → Executing
submit()                                  → Reviewing
reject(reason="不达标")                    → Rejected   ★ deliverable 仍是 A
retry()                                   → Executing  ★ 仍是 A
submit()                                  → Reviewing  ★ 无门禁
verify()                                  → Completed  ★ 验收的是 A
```

**为什么是真 bug 而不是「设计如此」—— 决定性对照**：

`core_task.mbt:545-553` 的 **`Task::reopen`** 对**同一个** `Rejected` 状态：
```moonbit
Rejected =>
  Ok({ ..self, status: Claimed, assignee: None, deliverable: "", })   // ★ 清了 deliverable + assignee
Paused => Ok({ ..self, status: Claimed, })
```
**⇒ 同一状态的两条出路语义不一致：`reopen` 清、`retry` 不清。** 这不是设计选择，是遗漏。

**为什么有害（不是洁癖）**：
- `omega_strong.mbt:642` 成果复验门：`if t.deliverable.trim() == "" { return Err("尚无交付物") }`
  ⇒ **旧交付物让 Omega 门误判「已有成果可复验」，复验的是上一轮废品，判绿即当真了账。**
- `board_ascii.mbt:252` `done_no_artifact`：`t.deliverable == ""` 识别假绿已完成（BUG-29 档）
  ⇒ **打回重试后的假绿任务不计入该档，账本读数系统性低估。**
- 现有测试**零覆盖**：`grep -rn 'deliverable' src/core/*wbtest*.mbt src/engine/*wbtest*.mbt | grep -i 'retry\|reject'` → **空**。

**已上报**：`report_bug` → **`BUG-426` [high] OPEN**

#### B-2 · `BUG-427` [medium] —— `reject` 把打回原因无上限追加进 description

**代码定位**：`core_task.mbt:557-570`
```moonbit
description: if reason == "" { self.description }
             else { self.description + " [打回原因: " + reason + "]" }   // ★ 纯追加，无上限无去重
```

**实测（库现读，不是推断）**：
```
T0r636.4.2   description 长度=4737  打回次数=1
T0r581.2     description 长度=633   打回次数=2
T0r581.3     description 长度=633   打回次数=2
```
⇒ **该路径已被真实使用**，单次打回即可把 description 撑到 4.7KB。

**为什么有害**：
- `desc_clip`（`core_task.mbt:680`）**只在 `to_json` 输出时截断，库里存全文** ⇒ 存储面无闸
- `task_triage` 从 description 正则抽能力关键词 ⇒ **`[打回原因: …]` 文本污染推荐排序**
- `goal_drift_check`（R100）用 description 做词法 Jaccard ⇒ **drift 读数失真**
- `supervisor_status(detail=false)` 截断到 200 字节 ⇒ **真正的任务描述被挤掉**

**诚实边界**：**现有数据里没有观察到「同一任务几十次打回」的极端膨胀**，
所以这是**结构性缺陷（无界增长 + 污染判据进料面）**，不是「已经在炸」。

**已上报**：`report_bug` → **`BUG-427` [medium] OPEN**

---

### §4 方向 B 里**核过但判定不是 bug** 的点（怕漏，逐条列出）

| 检查项 | 读数 | 判定 |
|---|---|---|
| `pause` 是否盖 `updated_at` | `engine.mbt:1168` `c.with_updated_at(now)` ✓ | 正确 |
| `resume` 是否盖 `updated_at` | `engine.mbt:1192` ✓ | 正确 |
| `retry_task` 是否盖 `updated_at` | `engine.mbt:1144` ✓ | 正确 |
| `archive_force` 是否绕 Omega 门 | `engine_archive_force.mbt:47-52` 有门 **且** BUG-417 孤儿豁免逻辑完整 | 正确 |
| `archive_force` 是否绕 human_steward 身份门 | `:16` 显式检查 | 正确 |
| `archive_force` 清不清 `assignee` | 不清（`:533`） | **不是 bug**：负载统计口径是「未完成未归档」（`engine_dag_ext.mbt:501`），归档后自动排除 |
| `execute` 是否覆盖写 deliverable | `engine.mbt:245` `with_deliverable(deliverable, now)` ✓ | 正确（这正是 BUG-426 的窗口只在「跳过 execute」时成立的原因） |
| `claimguard.mbt:650/772/824` 裸取 `[0]` | 三处**都有 `is_empty()` 前置守卫**（`:647/769/821`） | 不是 bug |
| `engine_triage.mbt:225` `skill_hits[0]` | `else if ah > 0` 守卫充分 | 不是 bug |
| `gate.mbt` 的 `jget` 匹配 | `:333-346` 完整 Some/None | 不是 bug |

---

## 分析：为什么方向 B 比 `issue_scan` low 档有信息量

| 维度 | `issue_scan` low 档（Lane C 实测） | 本轮方向 B |
|---|---|---|
| 命中量 | **1033 条** | **2 条** |
| 真 bug 率 | **0%**（矩阵：`result-discard` 307 命中 100% 噪声） | **100%**（2/2 均已上报且给出论证） |
| 判据形态 | **单行文本模式**（`divide-by-zero` / `result-discard`…） | **跨函数字段流**（`reject` 不改的字段 → `submit` 不查 → `omega_verify_gate` 食之） |
| 为什么 low 档必然失败 | 单行正则**看不见**「A 函数漏清字段、B 函数据此放行」这种缺陷 —— 每一行单看都合法 | 方向 B 的判据是**「字段在状态迁移中是否被正确维护」**，天然跨行跨函数 |

**关键洞见**：`BUG-426` 的每一行代码单独看都是**正确的**
（`reject` 改 status 是对的、`retry` 改状态是对的、`submit` 不查 deliverable 也没错），
**缺陷只存在于「三者合起来的运行期语义」里**。`issue_scan` 的规则形态**结构上不可能**表达它。

⇒ **印证 Lane C 的建议是对的：`issue_scan` 的 low 档在本仓是噪声发生器，换方向是唯一出路。**

---

## 缺口与风险（这轮仍没覆盖的盲区）

### 盲区-1：**没有真跑测试**（结构性限制）

我全程只读，**没有编译、没有跑 `moon test`**。`BUG-426` 的复现是**源码推演**：
状态机转移链每一跳都有源码依据（`core_task.mbt:473/557/580` + `engine.mbt:599`），
**但没有一条实际执行过的失败测试**。**建议落地方先写一格红测试再修**（这也是判例-29 的要求）。

### 盲区-2：**方向 C（并发/竞态）完全没做**

派单允许「A/B 都不顺手时」才做 C，本轮 A/B 都做了 ⇒ **C 未覆盖**。
`rsv_try_set` / `locks_try_acquire` 的「先读后写」窗口在 BUG-136/145 收口后**有没有新缝，本轮未查**。

### 盲区-3：**跨 namespace / 跨 store 后端的数据流未查**

`get_task` 的 163 个调用点里，**按 namespace 路由的那部分（`store_open` 多库）没有单独审**。
`BUG-374/376/378` 那族「任务在指定 ns 不存在时」的语义上轮刚改过，**本轮未复核**。

### 盲区-4：**`archive_force` + `pause` + `reopen` 的组合路径未穷举**

我只核了**单步**语义（pause→resume、reject→retry、completed→archive_force）。
**三步以上的组合**（如 `reject → retry → pause → resume → submit`）**没有穷举**。
`BUG-426` 正是两步组合才暴露的 ⇒ **更长组合里可能还有同类**。

### 盲区-5：**OCR / 外部二进制面仍是黑的**

与 Lane C 报的同一条，**本轮未改善**（`src/server/ocr_scan.mbt` 的外部 CLI 依赖本机无二进制）。

### 盲区-6：**`issue_scan` 的 medium/high 档本轮也没碰**

按派单要求「不要再走 low 档」，我**整条 `issue_scan` 都没用**（含 medium/high）。
若 medium/high 档有真命中，本轮不会发现。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-26-r6-bugfind-round2-report.md` |
| BUG-330 判定依据 | 本报告 §1（含最小工程复现命令，可复核） |
| `BUG-426` / `BUG-427` | `memory/bugs.md`（已由 `report_bug` 写入，`publish_task=false`） |
| 方向 A 审计脚本 | `temp/audit/lane_y_optflow.py` |
| 建议的后续动作 | ① `bug_mark_status(BUG-330, FALSE_POSITIVE, evidence=§1 结论)` ② `BUG-426` 排 high 优先（建议 A+B 同批修 + 补 wbtest）③ `BUG-427` 建议 A（打回原因进独立历史，不进 description） |
