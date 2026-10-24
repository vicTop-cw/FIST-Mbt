# bugfind：`src/` 核心引擎的合并后副作用排查（task-17 · A 路）

> **模式**：bugfind（`require_issue_scan + require_test_corpus + require_ocr`）
> **板块**：`src/` 核心引擎 —— 本会话 20+ 笔 cherry-pick 的副作用
> **结论先行**：**3 条 finding，1 条在线（F3）、1 条潜伏（F1）、1 条设计缺口（F2）**。
> **0 errors / 1455 全绿并不构成「没有 bug」的证据 —— 下面 F3 就在全绿之下活着。**
> 日期：2026-10-24 · 主仓作业 · **未改任何代码**（`git status --short -- src/` 为空）

---

## 一、issue_scan 原始读数（bugfind 强制第一步）

入口：`python scripts/issue_scan.py src`（薄封装，拉起 `_build/js/.../cli.js` 走 MCP `issue_scan`）

```
scanned_files: 133     total_findings: 682     truncated: false (max=5000)
by_severity: { high: 0, medium: 0, low: 682, info: 0 }
```

### by_rule（全量 682 条，`--min-severity low`）

| rule | severity | count |
|---|---|---|
| `moonbit-result-discard` | low | 306 |
| `moonbit-array-index-bounds` | low | 164 |
| `moonbit-long-function` | info | 165 |
| `moonbit-overly-broad-catch` | low | 101 |
| `string-index` | low | 28 |
| `possible-overflow` | low | 26 |
| `moonbit-json-injection` | low | 26 |
| `moonbit-race-condition` | low | 12 |
| `moonbit-resource-leak` | low | 7 |
| `moonbit-dead-code` | low | 6 |
| `moonbit-floating-point-equality` | low | 3 |
| `moonbit-private-field-leak` | low | 2 |
| `moonbit-shared-mutable` | low | 1 |
| `moonbit-unused-variable` | info | 182 |

### 本会话改过的 5 个文件的命中分布

| 文件 | 命中 | 其中需复核 |
|---|---|---|
| `src/store/store_sqlite.mbt` | 243 | 全是 `result-discard`（`ignore(stmt.bind(…))` 惯例）+ 2 条 resource-leak + 4 条 broad-catch |
| `src/server/server.mbt` | 55 | `cached_pid_token[0]` 被报 `string-index`（**误报**：那是数组下标）|
| `src/engine/engine_supervisor.mbt` | 17 | 全是 result-discard + 1 条 json-injection（模板串，误报）|
| `src/engine/engine.mbt` | 6 | 2 条 array-index（`slices[i]`/`cs[i]`，循环内有界，误报）|
| `src/engine/omega_strong.mbt` | **0** | —— |
| `src/core/core_task.mbt` | 1 | `decode_to(...) catch` broad-catch（**有意吞错**，见 `desc_clip` 注释）|

> **`omega_required` 整条管线在 issue_scan 面零命中。**
> 规则扫描对「字段默认值掩盖逻辑错」「继承语义丢失」这类**语义缺陷天然无感** ——
> 这正是下面三条 finding 全部要靠**边界语料 + 真引擎**才抓得到的原因。

### ocr_scan（bugfind 强制第三步）：**未能出数，诚实标注**

```
$ python scripts/fist.py call ocr_scan --project_dir . --path src --subcmd scan
{"ok":false,"ocr_available":false,"subcmd":"scan",
 "error":"ocr_scan: OCR 二进制不可用",
 "hint":"OCR 二进制（opencodereview.exe，@alibaba-group/ocr-win32-x64）不可用。…
        本工具不会替你安装依赖，也不会静默返回成功。"}
```

**OCR 二进制本机未安装**（`../ocr-local` 不存在、`FIST_OCR_BIN` 未设）。
工具诚实地 fail-closed 而非静默报绿 —— 这是设计正确行为，但意味着
**bugfind 的 `require_ocr` 一格本机无法完成**。本报告其余结论不依赖 OCR 面。
另注：`ocr_scan` 的参数名是 `project_dir`+`path`+`subcmd`（白名单 `scan|files|delegate|rules`），
**不是** `dir`/`max_findings` —— task 把参数名写错了，我第一次调用被 inputSchema 拒。

---

## 二、五处重点逐处人工复核

### ① `src/core/core_task.mbt` — `omega_required` 字段 / `from_db` 第 19 参 → **对齐，无缺陷**

- 字段：`omega_required : Bool` ✅
- getter：`Task::get_omega_required()` ✅
- `Task::new(omega_required~ : Bool = false)` ✅
- `from_db` 第 19 参 `omega_required : Bool` ✅
- `to_json` 输出 `"omega_required"` ✅

**`from_db` 全部 4 个调用点逐一核对参数个数**：

```
src/engine/engine_execute_r2_test.mbt:136   → 19 参（末参 false）✅
src/server/board_ascii_test.mbt:116         → 19 参（末参 false）✅
src/server/board_ascii_test.mbt:197         → 19 参（末参 false）✅
src/store/store_sqlite.mbt:430              → 19 参（末参 omega_raw != 0）✅
```

> **「19 参会编译错」这个担心不成立** —— MoonBit 位置参数个数不符是**编译错**，
> 不会静默取默认值。真正会静默出错的是**顺序错**（例如把 bool 和 array 位置互换），
> 这里末参类型 `Bool` 唯一，错序也会编译错。**本项无缺陷。**

### ② `src/store/store_sqlite.mbt` — DDL / ALTER / 19 列 SELECT / bind → **对齐，无缺陷**

`task_columns()` 19 列顺序与 `row_to_task` 读取下标逐位核对：

| idx | 列 | 读取点 |
|---|---|---|
| 0 | id | `column_text(0)` |
| 1 | parent_id | `column_text(1)` |
| 2–9 | project_dir…level | `column_text(2..5)` / `column_int(6..8)` |
| 10 | assignee | `column_text(10)` |
| 11–14 | description…updated_at | `column_text(11..14)` |
| 15 | completed_by | `column_text(15)` |
| 16 | cleanup_mode | `column_text(16)` |
| 17 | depends_on | `column_text(17)` |
| **18** | **omega_required** | **`column_int(18)` → `omega_raw != 0`** ✅ |

**bind 面（重点：placeholder ↔ bind 数量）**：

```
INSERT INTO tasks (...) VALUES (?,?,?,…,?)   19 个 ?   ↔ bind_task_values 1..19 连续无缺  ✅
UPDATE tasks SET …(17 列)… WHERE id = ?      18 个 ?   ↔ 17 SET + bind(18)=id              ✅
UPDATE … WHERE id = ? AND status = ?         19 个 ?   ↔ 17 SET + bind(18)=id + bind(19)   ✅
```

`bind_task_values` 索引 `[1..19]` 连续、`bind_task_update_values` 索引 `[1..17]` 连续，均无跳号。

> ⚠️ **一个真实的脆弱点（非缺陷，记为 F2 的邻居）**：UPDATE 的 `WHERE id = ?` 绑定在
> `update_task` 里是**硬编码的 `18`**、`update_task_if_status` 里是 `18`/`19`。
> 这三处数字与 `bind_task_update_values` 的**最大绑定号 17** 靠人肉维持一致。
> 加列时若漏改 WHERE 的号，SQLite 不会报错（多余的 bind 被忽略 / 缺 bind 视为 NULL），
> **会静默更新错行或更新 0 行**。无判据锁这一格。

### ③ `src/engine/omega_strong.mbt` — `get_omega_required() || description.contains()` → **多源 OR，优先级见 F2**

`omega_enabled` 真值表（唯一权威判据点，6 处门禁全走它）：

| col | desc_mark | enabled | 场景 |
|---|---|---|---|
| T | T | **T** | 两者一致（开）|
| T | F | **T** | 方向②要保的场景（元数据开/文本无）|
| F | T | **T** | 旧库迁移后 / upsert 拼回标记 |
| F | F | **F** | 两者一致（关）|

**`||` 语义 = 只有两者皆假才关**，所以「任一为真」都保留门禁 —— 这是**保守方向**，
不会误关。方向正确。

### ④ `src/engine/engine.mbt` — 传 `omega_required=` → **调用点唯一，但继承语义丢失（= F3）**

全仓 `omega_required=` 的**赋值点只有 1 处**：`engine.mbt:1373`，在 `decompose_rec` 里
`omega_required=omega_strong_verify`。递归下钻（`decompose_rec` 自调用，line 1392）
原样传同一个 `omega_strong_verify`，**同一调用内一致**。

**但它取的是「本次 `plan_deep` 的入参」，不是「父任务是否开着 Omega」。** → 见 **F3**。

### ⑤ `src/server/server.mbt` — `cached_pid_token` 固化 → **`None` 判法正确，pid=0 不撞车（H3 不成立）**

```moonbit
let cached_pid_token : Array[Int32?] = Array::make(1, None)
fn current_pid_token() -> Int32 {
  match cached_pid_token[0] {
    Some(v) => v              // ← 判「已缓存」用的是 Some/None，不是 pid != 0
    None => { … compute …; cached_pid_token[0] = Some(pid); pid }
  }
}
```

**统领担心的 `pid != 0` 哨兵没有被用**，用的是 `Some/None` —— **正确**。
`pid=0` 时缓存为 `Some(0)`，与 `None` 是**不同构造子**，不会走到「未缓存」分支。

> 附：`cached_pid_token[0]` 被 issue_scan 报成 `string-index`（line 465/470）是**误报** ——
> 那是数组下标不是字符串下标，规则按语法近似判定。

---

## 三、边界语料清单（每条带 `confirmed`）

### F3 — 子任务丢失父任务的 Omega 门禁 ✅ `confirmed: true`（**在线缺陷**）

| 项 | 内容 |
|---|---|
| **位置** | `src/engine/engine.mbt:1373` `omega_required=omega_strong_verify` |
| **判据** | 该值取「本次 `plan_deep` 入参」，而非「父任务 `omega_enabled(parent)`」 |
| **触发** | 父任务开着 Omega（元数据列=1 或描述含 `[omega:required]`），但调用 `plan_deep` **不传** `omega_strong_verify`（默认 false） |
| **后果** | 所有子任务 `omega_required=false` 且描述无标记 ⇒ `omega_enabled(child)=false` ⇒ `omega_spec_create` / `omega_spec_review` / `omega_result_verify` **全部直接放行**，强验证门禁对整棵子树失效 |

**真引擎证据**（临时 wbtest，跑完即删，`src/` 现无改动）：

```
publish("父任务 [omega:required]")  → 父 omega_enabled = true
claim → plan_deep(split_n=2, 不传 omega_strong_verify)
读数（编码 k=子任务数 L=丢失门禁数 P=父是否开）:  PHk2L2P1
                                              ↑  ↑  ↑
                                    2 个子任务 2 个丢失 父开着
```

**已排除的替代解释**：不是 `||` 优先级问题（父判定为真）；不是递归传递问题（同一入参一致）；
不是事务/落库问题（子任务确实 `create_task` 成功，`children_of` 取得到）。

**现有测试为何全绿**：`omega_required_column_wbtest.mbt` 的 4 条锁里，唯一涉及 `plan_deep` 的
那条（line 113）**只测 `omega_strong_verify=true`** 这一侧 ——
「传 true 时子任务为 true」它钉住了，**「父开着但不传」这一侧零覆盖**。
`grep -rn "omega" src/engine/*_test.mbt src/engine/*_wbtest.mbt | grep -i "继承|inherit|parent"` = **0 命中**。

**是否设计意图？** 注释只写「把 Omega 门禁判据写进不可覆盖的元数据列…不依赖 description 文本」，
**没有一句说明子任务是否继承父门禁**。这是契约空白 —— 若「继承」是本意则为缺陷，
若「每层各自决定」是本意则需在注释里写明并与 `[omega:required]` 文本注入的旧行为对齐
（旧行为下 decomposer 会把标记**写进子任务描述**，才让门禁"看起来"继承了）。

**建议修法（不在本单执行）**：`omega_required=omega_strong_verify || omega_enabled(parent)`。

---

### F1 — `agent_acl.pid_bound` 的 `0` 哨兵与真实 pid 撞车 ⚠️ `confirmed: true`（**潜伏缺陷**）

| 项 | 内容 |
|---|---|
| **位置** | 检查侧 `src/store/store_sqlite.mbt:2969` `if pid_bound != 0 && bound_pid != current_pid`<br>写入侧 `src/store/store_sqlite.mbt:3110` `bound_pid = SELECT pid FROM agents`（查不到回落 `0`）|
| **机理** | 同一列 `agent_acl.pid_bound` 承载两种 `0`：①「未绑定」哨兵 ②「绑定的 pid 恰好是 0」/「查不到 pid 时的回落值」。检查侧把 ② 读成 ① ⇒ **绑定静默失效** |

**边界语料（5 格，临时 sqlite 库，复刻真实判据）**：

| 格 | 场景 | got | want | 判定 |
|---|---|---|---|---|
| A | 绑定 pid=12345，同进程访问 | OK | OK | ✅ |
| B | 绑定 12345，换进程 999 | Err(换实例) | Err(换实例) | ✅ |
| **C** | **agent pid=0 且绑定，换进程 999** | **OK** | **Err(换实例)** | **❌ 绑定静默失效** |
| **D** | **grant 时查不到 agents 行（bound_pid 回落 0），换进程 999** | **OK** | **Err(换实例)** | **❌ 绑到不存在的 pid** |
| E | 未绑定（pid_bound=0），任意进程 | OK | OK | ✅（哨兵本义正确）|

`confirmed: true`（2/5 格缺陷）。**但可达性必须诚实降级为"潜伏"**：

```
生产面 pid_bound 的写入点 = agents_acl_grant
  ├─ MCP 工具面：server.mbt 里 agents_acl_grant 出现 **0 次**（未暴露）
  ├─ 唯一调用链 engine.agents_acl_grant → store.agents_acl_grant
  └─ engine.agents_acl_grant 在全仓**无生产调用者**（仅 store_sqlite_agents_wbtest 直调）

默认 ACL 由 agents_acl_ensure 落，SQL 里 pid_bound 写死 0
⇒ 生产环境 pid_bound 恒为 0 ⇒ `pid_bound != 0` 分支从不进入
```

**⇒ F1 是「判据写好、触发器未接线」的潜伏缺陷。一旦有人把 `agents_acl_grant` 暴露成 MCP 工具
（或任何代码调用 `pid_bound=true`），它立刻变成真实缺陷。**
这与本会话判例-3「改名不是接线」同族：**没接线的判据等于没有判据；没接线的触发器掩盖了判据的缺陷。**

---

### F2 — `omega_required` 无「关闭」入口，且描述覆盖后标记永久留在列里 ✅ `confirmed: true`（**设计缺口，需 owner 定性**）

**这是统领问的第 ② 条，答案是：`||` 任一为真 ⇒ 判定仍为真（功能上"对"），但存在两个不对称。**

| 不对称 | 事实 | 影响 |
|---|---|---|
| ① **无关闭入口** | 全仓 `omega_required=` 赋值点仅 `engine.mbt:1373`（取值 `omega_strong_verify`）；`Task::new` 默认 `false`；**没有任何 API 能把已置 true 的任务改回 false** | Omega 一旦开出，**只能靠手工改库**才能关。`update_task` 能写 false，但没有任何业务路径产生"false 的 Task" |
| ② **描述清空后标记残留在列里** | 方向①在 upsert 时把 `[omega:required]` **拼回描述**；方向②的列不受描述影响 ⇒ 两者都"粘住" | 用户想"先关掉 Omega 改描述再开"，做不到 —— 描述里那个标记**删不掉**（下次 upsert 又拼回来）|

**边界语料（全绿，即"当前行为符合 OR 语义"，但暴露上述不对称）**：

| 格 | 场景 | 读数 | 性质 |
|---|---|---|---|
| 1 | 父开 omega + `plan_deep` 不传参 | 子任务门禁**关** | ← F3 本体 |
| 2 | 父未开 + 传参 true | 子任务门禁开 | ✅ 符合预期 |
| 3 | 反复切换 col: 1→0→1 | 可往返 | ✅ 列本身无粘滞 |
| 4 | upsert 覆盖描述（新描述无标记）| 门禁仍开 | ✅ OR 语义正确，但标记被拼回 ⇒ 删不掉 |
| 5 | 旧库迁移（旧行只有文本标记，列=0）| 门禁开 | ✅ **文本兜底生效** ← 统领问的第 ① 条 |

**⇒ 统领问的第 ① 条（旧库迁移后文本兜底还在吗）：在。** `ALTER TABLE … DEFAULT 0` 后旧行列为 0，
但 `description.contains("[omega:required]")` 仍命中 ⇒ `omega_enabled=true`。**兜底完好。**

**⇒ `||` 的优先级结论**：不存在「谁压谁」，是**单调 OR（只增不减）**。
方向②的意图（元数据不可被描述覆盖）达成了；代价是**开关变成只读单向（只能开不能关）**。
这是**设计意图还是副作用**，注释未交代 —— 需 owner 定性。若需要"可关"，得补
① 显式 `omega_disable` 路径 ② upsert 时同步清理列的判据（否则 `||` 永远为真）。

---

## 四、风险排序（哪条最可能已经在线）

| 序 | ID | 缺陷 | 在线? | 影响面 | 为何排这个位次 |
|---|---|---|---|---|---|
| **1** | **F3** | 子任务丢失父 Omega 门禁 | ✅ **在线** | 强验证门禁对整棵子树失效 | 唯一**当前可达且破坏核心承诺**的一条。Omega 强验证是本仓一等能力，门禁静默失效 = 语料审核流程形同虚设 |
| 2 | F2 | Omega 只能开不能关 | ✅ 在线 | 运维侧无法回退 | 不破坏判据正确性（OR 语义当前方向正确），但把"误开 Omega"变成**不可逆**，只能改库 |
| 3 | F1 | `pid_bound` 0 哨兵撞车 | ⚠️ **潜伏** | 一旦接线即静默放行换实例 | 机理确证、可达性为零（grant 未暴露）。**风险不是"现在有洞"而是"以为已经堵上了"** |

### 附带观察（非缺陷，供 tidy/守卫组参考）

- **`agent ACL` 整族未接 MCP 面**：`agents_acl_grant` 无工具注册、`agents_acl_check` 只被
  `agent_write_gate` 内部调用。这套 ACL 体系的"授权"半边**没有用户入口** ——
  与 F1 的可达性为零直接相关，也是一个功能完备性缺口（建议交 verify 路）。
- **UPDATE 的 WHERE bind 号硬编码（18/19）** 与 `bind_task_update_values` 的最大号（17）
  靠人肉一致，无判据锁。加列是本会话的高频动作 ⇒ 建议加一把结构判据。
- **`ignore(stmt.bind(...))` 占 issue_scan 命中的 306 条（44.9%）**：这是本仓既有惯例
  （bind 失败极少且无补救路径），**不建议按规则批量改** —— 会制造 306 处噪声改动。

---

## 五、方法学记录（本次新踩的坑，供后人）

### 坑 1：`println` 在 `moon test` 里是**假绿源**（我自己踩了一次）

第一版探针用 `assert_true(true)` + `println("PROBE_RESULT …")`，结果
**206/206 全绿、`PROBE_RESULT` 一行都没出现** —— 测试 runner **不透传 stdout**。
我在抓「假绿」的 task 里自己先交了一份假绿。

**正确做法**：把读数**编码进失败串**。
但 `fail()` 的正文会被 runner 截断（实测截到 `"PROBE_RES…"`），所以要把读数放在**测试名**里：

```moonbit
let tag = "k" + kids.length().to_string() + "L" + lost.to_string() + "P" + …
fail("PH" + tag)     // runner 打印测试名 → grep -oE "PHk[0-9]+L[0-9]+P[01]"
                     // 读数: PHk2L2P1
```

**教训**：`assert_true(true)` 是能写出来的最危险的断言；探针的断言必须**失败**才能证明它真在看。

### 坑 2：issue_scan 对语义缺陷天然无感

`omega_required` 整条管线在 682 条命中里**零命中**。规则扫描只看语法形状（除零/空下标/unwrap），
**看不见「字段默认值掩盖逻辑错」「继承语义丢失」「多源 OR 的单向性」**。
⇒ bugfind 的 `require_issue_scan` 是**底线不是全部**，三条 finding 全靠边界语料 + 真引擎。

### 坑 3：`ocr_scan` 参数名与 task 描述不符

task 写 `dir`/`max_findings`，实际 schema 是 `project_dir` + `path` + `subcmd`（白名单四值）。
第一次调用被 inputSchema 直接拒（这是好事，fail-fast）。

---

## 六、交付物自检

| 判据 | 读数 |
|---|---|
| **是否改了代码** | **否** —— `git status --short -- src/` = 空 |
| 临时探针 | 已删（`src/engine/zz_probe_f3_wbtest.mbt` 不存在） |
| 探针期间测试读数 | 206/206 → 探针失败期 205/206（**故意红**）→ 删除后恢复 |
| 全量基线 | `Total tests: 1455 / passed 1455 / failed 0` |
| issue_scan | 133 文件 / 682 命中 / high 0 / medium 0 |
| ocr_scan | **不可用**（二进制未安装，工具 fail-closed 诚实报错） |

---

## 七、建议入档位置

1. **F3** → `memory/bugs.md` 立新条（**high**，在线）。这是本会话 cherry-pick 引入的语义退化，
   且 issue_scan/全绿测试双面都看不见，属"判例级"发现。
2. **F1** → 记账为**潜伏**（medium），绑定在"agent ACL 接 MCP 面"那张单上一起做。
   它本身不值得单独立单修，但**开放 grant 工具前必须先修**。
3. **F2** → 交 owner 定性「Omega 是否应可关闭」，再决定是补 `omega_disable` 路径还是写进设计意图说明。
4. **坑 1（println 假绿 / fail-串截断）** → 建议进 `docs/` 判例集，与判例-3「改名不是接线」并列。
   两者同族：**判据形状冒充判据实质**。
