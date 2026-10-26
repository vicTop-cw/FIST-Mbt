# R11 助理并发 + 跨 ns 数据流审计

> **任务**：① `assistant_claim` 并发面（R9 缺口 #2）② 跨 namespace 数据流（R6 缺口 #3，C 案止血之后）
> **执行人**：司令-γ · **边界**：只读 + 报告（**探针因他人坏文件无法编译，见 §6**）
> **产出**：本报告 + `temp/audit/lane_ak_*.py` + 2 条 `report_bug`

---

## 结论（任务 1 与任务 2 分开写）

### 任务 1：`assistant_claim` 并发面

| 子项 | 结论 |
|---|---|
| **1a 单一真源？** | **是**（`store.mbt:238-252` 纯函数，四分支只写一处；`store_assistant.mbt:4` 注释明确「共用」）<br>⚠️ **但发现一处真·重复实现**：`constraint.mbt:69-79` 的 `rsv_conflict_verdict` **手工镜像** `rsv_action`，且**有调用方**（`constraint.mbt:127`） |
| **1b 先读后写？** | **不是**（按 R9 判据：读值只决定 action 标签）<br>但 **并发缺互斥**：两个 agent 可同时 `elected` 各自写 `is_primary=true` ⇒ **建议单独立案** |
| **1c sweep × claim 互相踩？** | **★ 真 bug** → **`BUG-431`** |
| **1d `force_takeover` 记录对得上吗？** | **★ 对不上**（同 `BUG-431`）：取决于 sweep 是否先跑 |

**四分支实测**（纯函数逐字复刻，`temp/audit/lane_ak_claim.py`）：

| 分支 | prev | 返回 `(ok, action, prev_agent)` | 预期 | 实测 |
|---|---|---|---|---|
| 分支1 无主 | `None` | `(true, "elected", "")` | elected | ✅ |
| 分支2 本人重复 | `("A","t4")` | `(true, "renewed", "")` | renewed | ✅ |
| 分支3 心跳陈旧 | `("B","t4")` | `(true, "taken_over", "B")` | taken_over | ✅ |
| 分支4 心跳新鲜 | `("B","t6")` | `(false, "conflict", "B")` | conflict | ✅ |
| **边界** hb==cutoff | `("B","t5")` | `(false, "conflict", "B")` | conflict | ✅ |
| 边界 hb 极旧 | `("B","a0")` | `(true, "taken_over", "B")` | taken_over | ✅ |

**6/6 与预期一致。** 且实测 `status` 字段**完全不参与裁决**（签名只读 `.agent` 与 `.heartbeat_at`）。

### 任务 2：跨 namespace 数据流（C 案止血**之后**）

| 子项 | 结论 |
|---|---|
| **2a C 案覆盖了什么** | 只覆盖 3 处：`store_open` 诊断、`get` 文案增强、`archive` 文案增强 |
| **2a 8 工具走不走 ns 路由** | **8/8 全走 `engine_for_ns`**（见 §2 表） |
| **2a 找到什么** | **★ 真 bug** → **`BUG-433`**：`engine_for_ns` 对**非法 ns 静默回落主库**，8 个工具全受影响 |
| **2b `get_task` 不带 ns 过滤** | **仍在**（`store_sqlite.mbt:499`）。**判定：设计选择，不是缺陷** —— 理由见 §3，**不建议改** |
| **2c BUG-374/376/378** | **全部仍有效，未被 C 案影响**（§4） |

---

## 证据

### §1 任务 1 逐项

#### 1a 裁决函数是不是单一真源？

**`store.mbt:238-252`（纯函数，零 IO，四分支单点）**：
```
None => (true,"elected","") | r.agent==agent => (true,"renewed","")
r.heartbeat_at<cutoff => (true,"taken_over",r.agent) | 其余 => (false,"conflict",r.agent)
```
**调用点唯一**：`server.mbt:5584`。`store_assistant.mbt:4` 注释明写「选举裁决共用 store.mbt 的 assistant_claim_action 单一真源」。

**⇒ 四分支没有在别处另写一遍 ✅**

**⚠️ 但发现另一处真·重复实现（判例-29 形状，不在 assistant 但同族）**：
```
src/constraint/constraint.mbt:55-79  rsv_conflict_verdict
```
注释自称「= src/store/store_rsv.mbt::rsv_action L77-88 的**忠实镜像**」，
代码是**逐字重抄**的四分支。**且它有真实调用方**（`constraint.mbt:127` `eval_no_overlap`），**不是死代码**。
⇒ **这是「两份实现声称等价、靠人守」的第二个面**，与 R10 的「两后端」同族。
**本轮但因 src/store 编译被他人坏文件阻塞，未能跑等价探针**（§6）⇒ **列为缺口**。

#### 1b 有没有先读后写？

`server.mbt:5584` 读 `assistant_active_primary()` → `:5585` 纯计算 → `:5588` 写 `assistant_upsert()`（两次 IO）。

**按 R9 判据（读值是否改变裁决）**：`taken_over` 分支的裁决**确实依赖读到的 `heartbeat_at`** ⇒ 形式上像 TOCTOU。
**但被插队时本函数仍按快照算，不会产错标签**；真正的问题是**「谁能成为主助理」完全缺互斥** ——
两个不同 agent 并发 claim 会**各自写一行 `is_primary=true` 的 active**（`assistant_upsert` 按 agent 键 upsert，不查唯一性）。
`assistant_active_primary` 用 `registered_at` 取最新一条兜住了**读侧歧义**，但**库里留下两行 active primary**。

**⇒ 不是 bug（有兜底），属并发缺口 ⇒ 建议单独立案，本单只记录。**

---

#### 1c ★ `sweep` × `claim` 互相踩（真 bug，`BUG-431`）

**三处协同**：

| 处 | 代码 | 作用 |
|---|---|---|
| `engine_assistant.mbt:44` | `if r.is_primary && r.status == "active"` | **只认 `active`** ⇒ `dead` 被过滤 |
| `store.mbt:241` | `None => (true, "elected", "")` | `prev=None` ⇒ **elected** |
| `server.mbt:5598` | `if action == "taken_over" { lock_violations_record(...) }` | **只有 taken_over 才留痕** |
| `server.mbt:5672` | `if r.status == "active" && r.heartbeat_at < cutoff` | sweep 标 dead |

**实测推演**（`temp/audit/lane_ak_sweep_claim.py`）：

```
情形A sweep未跑: B(active,心跳陈旧) → active_primary=Some(B) → claim= taken_over → ✅写 force_takeover
情形B sweep先跑: B 被标 dead      → active_primary=None     → claim= elected    → ❌不写任何违例
情形C B 主动resign:                → active_primary=None     → claim= elected    → ✅不该写(对的)
```

**⇒ 情形 B 与情形 C 回执完全相同**（`elected` + 无违例），
但 B = **失联**（该留痕）、C = **主动退位**（不该留痕）⇒ **无法区分**。

**⇒ `BUG-431` 已上报**（medium）。修法见该单（建议 A：sweep 标 dead 时自己留痕）。

#### 1d `force_takeover` 记录对得上吗？

**代码上会写**（`server.mbt:5598-5605`，字段齐：`ts/agent=prev_agent/scope="assistant"/reason="force_takeover"/lock_id=agent`）。
**但**只在 `action=="taken_over"` 时写 ⇒ **情形 B 不写** ⇒ `assistant_status` 违例统计**系统性偏低**，丢的正是「强制接管」这一档。
**⇒ 与 1c 同根因，即 `BUG-431` 的 d 面，不另开单。**

---

### §2 任务 2a：8 个工具逐个核（走不走 ns 路由）

| 工具 | 起始行 | ns 取法 | engine 取法 | 走路由？ | C 案覆盖？ |
|---|---|---|---|---|---|
| `claim` | 1821 | `get_str(args,"namespace",default="default")` | `engine_for_ns(ns)` | **是** | 否 |
| `execute` | 1869 | 同上 | `engine_for_ns(ns)` | **是** | 否 |
| `submit` | 1932 | 同上 | `engine_for_ns(get_str(...))` | **是** | 否 |
| `verify` | 2067 | 同上 | `engine_for_ns(ns)` | **是** | 否 |
| `archive` | 2206 | 同上 | `engine_for_ns(ns)` | **是** | **是** |
| `list` | 2249 | `default=""` | `if ns_str=="" {engine} else {engine_for_ns(ns_str)}` | **是** | 否 |
| `get` | 2284 | `default="default"` | `engine_for_ns(ns)` | **是** | **是** |
| `delete` | 2337 | `default="default"` | `engine_for_ns(ns)` | **是** | 否 |

**⇒ 8/8 全部走 `engine_for_ns`。C 案只覆盖 2 个（`get` / `archive`）+ `store_open`。**

#### ★ 2a 的真 bug：`engine_for_ns` 对非法 ns 静默回落（`BUG-433`）

**`server.mbt:63-72`**：`mstore.get(ns)` 的 **`None => engine`** 分支（★静默回落主库）。

**什么时候 `mstore.get` 返回 None？** 当 `safe_ns` 拒绝时（`multi_store.mbt:28-45`，
**只允许 `[0-9A-Za-z_-]`**）。

**实测**（`temp/audit/lane_ak_ns_fallback.py`）：

| ns 值 | `safe_ns` | `engine_for_ns` |
|---|---|---|
| `bugs` / `fist-mbt` / `r4-fix` / `a_b_c` | OK | 对应 ns 库 ✅ |
| `my-ns.2`（**含点**） | **None** | **主库** ★ |
| `ns with space` | **None** | **主库** ★ |
| `中文ns` | **None** | **主库** ★ |
| `ns/../escape` | **None** | **主库** ★ |
| `ns:1` | **None** | **主库** ★ |

**后果（写路径最重）**：`delete` 误删主库任务（**不可逆**）、`archive` 误归档、
`execute` 覆盖错任务、`submit`/`verify` 作用在主库、`claim` 认领落主库；
读路径 `get` 串库读数、`list` 列出主库全部。

**为什么 C 案没覆盖**：C 案处理的是「**路由到了空库**」（主库有 ns 标签 + ns 库为空），
**不处理「ns 非法 ⇒ 路由被静默取消」**。**两个不同病灶。**

**⇒ `BUG-433` 已上报**（high）。**这是 C 案止血之后仍存的缝。**

---

### §3 任务 2b：`get_task` 不带 ns 过滤 —— **是设计选择，不是缺陷**

**代码仍在**（`store_sqlite.mbt:499`）：`SELECT {task_columns} FROM tasks WHERE id = ?` —— **无 ns**。

**C 案止血没有改它**（C 案只改 server 层文案与 store_open 回执）。

**数据实测（决定「加不加 ns 过滤」）**：
```
主库 fist-mbt.db：总 2432 条 · 单库 ns 种类 63 · default/空 161 · **非 default 2271**
ns 分布：award-demo 661 / zn 497 / default 161 / bugs 148 / gradient-verify 140 / ...
```

#### 判定：**保持现状（不加 ns 过滤）是对的**

**理由（三条）**：
1. **语义单元是 `id` 不是 `(ns,id)`**：`id` 全库唯一，`ns` 只是标签。加过滤 = 主键查询退化成复合键 ⇒ **2271 条非 default 历史在「不知 ns」时读不到**。
2. **隔离边界是「库」不是「ns 标签」**：`engine_for_ns` 选库 = 隔离；库里有哪些 ns 是**内容**。⇒ 库内无过滤是正确分层。
3. **加过滤会制造「静默读不到」**：调用方拿 id 不传 ns（默认 default）⇒ 查不到 ⇒ **又一个 BUG-420 式缺口**。

**⇒ 这不是 bug，是设计选择。不建议改。**
**真正该改的是 BUG-433（非法 ns 静默回落）** —— 那才是隔离失效。

> **诚实边界**：`get_task` 无 ns 过滤确实意味着
> **「选对了库 = 拿到该库全部 id」**。若将来要做「库内 ns 硬隔离」，
> 应该在 `engine_for_ns` 之后再加一层 ns 断言，**而不是**改这条主键查询。

---

### §4 任务 2c：BUG-374/376/378 现在还有效吗

`grep -rn 'BUG-374\|BUG-376\|BUG-378' src/` 命中：

| 编号 | 位置 | 内容 | 被 C 案影响？ |
|---|---|---|---|
| **BUG-374/378** | `server.mbt:1978/2036` | `run_check` 走 **task 同一 ns→store 映射**，落库与任务同库 | **否**（C 案不动 run_check） |
| **BUG-376** | `server.mbt:1998/2057`、`omega_gate_wbtest.mbt:163-174` | 任务不存在 ⇒ **拒绝并落审计，不执行命令**（半途态禁令） | **否** |
| 三条共同 | `server.mbt:1953` 工具描述 | 明写「任务在指定 ns 不存在时直接拒绝、绝不执行命令」 | **否** |

**⇒ 三条修复全部仍有效，C 案未触及。**
**但** `run_check` 也走 `engine_for_ns`（`:1982`）⇒ **受 BUG-433 影响**：
传非法 ns ⇒ 回落主库 ⇒ 「任务在主库存在」时**命令执行到主库任务上**，与 BUG-376 的「不执行」承诺冲突。**已在 BUG-433 关联段点到。**

---

## 分析

### 三条分析（合并）

1. **任务 1 的坑在「胶水」不在「裁决」**：`assistant_claim_action` 纯函数单点、6/6 实测正确；问题全在它前后 ——
   读侧过滤（`assistant_active_primary` 只认 active）、写侧留痕（只有 taken_over 记）、第三方（`sweep`）改读侧输入。
   **与 R9 的 `legacy_grant`（裁决对、标签错）同族：纯函数正确，前后胶水丢语义。**
2. **任务 2 的坑在「路由取消」不在「路由选错」**：C 案所有诊断都建立在「路由发生了」这个前提上，
   而 `None => engine` 是**路由根本没发生**的出口。**共同形状（与 R10 四者同族）：
   健康检查只覆盖该面「能表达」的情形，缺陷落在它表达不了的分支。**
3. **`get_task` 不该改**：隔离（选库）与过滤（库内谓词）是两件事。把「隔离失效」误诊为「过滤缺失」，
   会去修一个不该动的地方、留下真缝（`None => engine`）。

---

## 缺口与风险

### 1. **探针未能真跑**（工具失败，原样上报）

我在 `src/store/` 建了 `r11_ak_probe_test.mbt`（`assistant_claim_action` 四分支真跑 +
`rsv_conflict_verdict` vs `rsv_action` 镜像等价实测），编译报：

```
src/store/store_rsv_test.mbt:1182:10
  _ => mut_w = false
  The variable mut_w is not mutable.
```

**⇒ 这是别人把 R10 探针合进 `store_rsv_test.mbt` 时引入的编译错误**（`M` 状态，非我改动）。
`moon check --target js` 同样报 `[4021] declared_role_for_judgment is unbound`
（`src/engine/engine_rsv.mbt` / `engine_scope_perm.mbt`，别人的在途）。

**⇒ 我没有改任何 `src/`，也没绕（不能 `--no-verify` 式地跳过）。**
**任务 1 的四分支读数改用「逐字复刻 + 源码原文自证」**（`lane_ak_claim.py` 把真函数源码贴出，
Python 复刻与逐分支对照）——**这是降级，不是等价**，已在此标注。
探针源码保留在 `temp/audit/r11/r11_ak_probe_test.mbt`，**等 `src/store` 可编译时可直接粘回跑**。

### 2. `constraint.mbt::rsv_conflict_verdict` 的镜像等价**未实测**

**这是本轮新发现的第七个「两个面」**（R10 说的是内存/SQLite 两后端，
这里是 policy 层镜像），**未跑等价探针**（同 §6-1 的编译阻塞）。
**⇒ 建议单独立案核这一对。**

### 3. `assistant_claim` 缺互斥 —— **并发双主助理未实测**

§1b 推理得出「两个 agent 可同时 elected」，**但没有真跑并发**（`MemoryStore` 单线程可跑，
但编译阻塞）。**建议单独立案。**

### 4. `sweep` 的 `stale_secs=600` vs `claim` 的 `heartbeat_ttl_sec=300`

两者判据同源但默认值不同 ⇒ **300~600 秒之间存在一个窗口**：
claim 认为「B 陈旧可接管」，但 sweep 还没标 dead ⇒ 此时走 `taken_over`（有留痕）。
超过 600 秒则逐渐被 sweep 抢走。**这个窗口差异本身是设计（不同用途），不是 bug**，
但**它就是 `BUG-431` 的触发器**。

### 5. 任务 2 未核 `run_check` / `ocr_scan` / `executor_run` 的 ns 路由

派单只列了 8 个生命周期工具。**`run_check`（`:1982`）实测也走 `engine_for_ns`** ⇒ 受 BUG-433 影响，
已在 `BUG-433` 的关联段点到，但**未逐个实测其余工具**。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-27-r11-assistant-ns-audit.md` |
| `BUG-431`（助理留痕） | `memory/bugs.md`（已写入，medium） |
| `BUG-433`（ns 静默回落） | `memory/bugs.md`（已写入，**high**） |
| 脚本 | `temp/audit/lane_ak_claim.py`（四分支+边界）· `lane_ak_sweep_claim.py`（1c 时序）· `lane_ak_ns_tools.py`（8 工具表）· `lane_ak_ns_fallback.py`（2a 回落） |
| 待跑探针（编译恢复后可用） | `temp/audit/r11/r11_ak_probe_test.mbt` |
| **建议后续单** | ① `constraint.mbt` 镜像等价实测 ② `assistant_claim` 并发互斥 ③ `get_task` **不改**（设计选择，记录结论即可） |
| **未做** | **未调 `bug_fix`**（代码未落地）· **未改 `src/`**（探针已移除） |
