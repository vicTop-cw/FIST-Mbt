# BUG-419 修复方案 · `find_matching_rule` 注释/实现不一致（静默遮蔽）

> **任务**：让 `find_matching_rule` 对规则表顺序免疫，并补齐测试
> **执行人**：司令-γ · **边界**：只读 + 出 patch（`src/engine/` 被保护，未落地）
> **产出**：本报告（含可粘贴 patch、3 格锁设计、遮蔽实测）

---

## 结论

| 问题 | 结论 |
|---|---|
| **选 (a) 还是 (b)** | **选 (a)** —— 实现改成真「最长 pattern 优先」 |
| **现有规则表有没有已存在的遮蔽** | **0 条**（16 条规则两两之间无一遮蔽） |
| **改成最长优先后会不会变行为** | **不会变**（23 个真实 scope 实测，0 条差异） |
| **但埋的雷是真的吗** | **是真的，且比 BUG 描述的更严重** —— 见 §3 |

**关键实测**：注入一条宽规则 `src/`（`["HumanSteward","Leader"]`）到规则表**最前面**，
「第一条匹配」会让 `src/store/store_sqlite.mbt` 与 `src/server/server.mbt` **从 HumanSteward 独占
变成 Leader 也能改** —— 正是 **BUG-418 双重越权口**。**最长优先下这两条仍命中各自的 HumanSteward 独占规则。**

---

## 证据

### 1. 现有规则表逐条顺序 + 遮蔽分析

**判据来源**：`scope_matches_pattern`（`engine_scope_perm.mbt:212-219`）：
- `pattern` 带 `/` 后缀 ⇒ `scope == pattern || scope.has_prefix(pattern 去掉尾 /)`
- `pattern` 无 `/` 后缀 ⇒ `scope == pattern || scope.has_prefix(pattern + "/")`

**遮蔽判定方法**：对第 `i` 条的 `pattern` 本身当 scope，去试**前面**每一条 pattern——命中即被遮蔽。

| # | pattern | allowed_roles | 被前面遮蔽？ |
|---|---|---|---|
| 0 | `src/store/store_sqlite.mbt` | HumanSteward | — |
| 1 | `src/store/store.mbt` | HumanSteward | — |
| 2 | `src/server/server.mbt` | HumanSteward | — |
| 3 | `moon.mod` | HumanSteward | — |
| 4 | `src/core/` | HumanSteward,Leader | — |
| 5 | `src/engine/` | HumanSteward,Leader | — |
| 6 | `src/router/` | HumanSteward,Leader | — |
| 7 | `src/display/` | HumanSteward,Leader | — |
| 8 | `cmd/` | HumanSteward,Leader | — |
| 9 | `plugins/` | HumanSteward,Leader | — |
| 10 | `moon.pkg` | HumanSteward,Leader | — |
| 11 | `scripts/` | HumanSteward,Leader,Executor | — |
| 12 | `docs/` | HumanSteward,Leader,Executor | — |
| 13 | `memory/` | HumanSteward,Leader,Executor | — |
| 14 | `templates/` | HumanSteward,Leader,Executor | — |
| 15 | `patches/` | HumanSteward,Leader,Executor | — |

**⇒ 遮蔽条数：0 / 16。** 当前顺序恰好正确（全是「细节在前、泛化在后」，且无前缀关系）。

> **顺带一个已存在的失效**（不是 BUG-419，但同族）：`moon.pkg`（#10）**只对仓库根**的 `moon.pkg` 生效。
> `src/engine/moon.pkg` 命中 `src/engine/`（#5）、`cmd/cli/moon.pkg` 命中 `cmd/`（#8），
> **子包的 moon.pkg 从没走到 #10 这条规则**。两处角色集相同（都是 HumanSteward,Leader）⇒ 当前无实际后果，
> **但「moon.pkg = 编译拓扑」这条规则的作者意图没实现**。

### 2. 调用方清单（`grep -rn`）

```
src/engine/engine_perm.mbt 之外的全部引用：
  src/engine/engine_rsv.mbt:19   match check_scope_permission(scope, role) {
  src/engine/engine_rsv.mbt:42   match check_scope_permission(scope, role) {
  src/engine/engine_scope_perm_wbtest.mbt:18/32/49/56/73/75/79  （测试，6 处）
```

**注意 BUG-413 上一轮新加的 `pub fn matching_rule`（:194）目前没有任何调用方**——
它是给「`Allowed` 不带规则载荷、但调用方想要详情」预留的口子，`matching_rule` 直接转调 `find_matching_rule`。
⇒ **改 `find_matching_rule` 会自动同时改到 `matching_rule` 和 `check_scope_permission`，无遗漏面。**

### 3. 行为差异实测（第一条匹配 vs 最长优先）

**现网规则表，23 个真实 scope 逐一比对**：

| scope | 第一条匹配 | 最长优先 | 变？ |
|---|---|---|---|
| `src/store/store_sqlite.mbt` | `src/store/store_sqlite.mbt` | 同 | — |
| `src/store/store.mbt` | `src/store/store.mbt` | 同 | — |
| `src/store/other.mbt` | (无) | (无) | — |
| `src/server/server.mbt` | `src/server/server.mbt` | 同 | — |
| `src/server/other.mbt` | (无) | (无) | — |
| `moon.mod` | `moon.mod` | 同 | — |
| `moon.pkg` | `moon.pkg` | 同 | — |
| `src/engine/moon.pkg` | `src/engine/` | `src/engine/` | — |
| `src/core/moon.pkg` | `src/core/` | `src/core/` | — |
| `src/core/core_task.mbt` | `src/core/` | `src/core/` | — |
| `src/engine/engine.mbt` | `src/engine/` | `src/engine/` | — |
| `src/router/model_router.mbt` | `src/router/` | `src/router/` | — |
| `src/display/rank.mbt` | `src/display/` | `src/display/` | — |
| `cmd/cli/main.mbt` | `cmd/` | `cmd/` | — |
| `plugins/claude/skill.md` | `plugins/` | `plugins/` | — |
| `scripts/check_badge.py` | `scripts/` | `scripts/` | — |
| `docs/SOP.md` | `docs/` | `docs/` | — |
| `memory/2026-10-26.md` | `memory/` | `memory/` | — |
| `templates/x.md` | `templates/` | `templates/` | — |
| `patches/sqlite/stub.c` | `patches/` | `patches/` | — |
| `reports/x.md` | (无) | (无) | — |
| `temp/x.py` | (无) | (无) | — |
| `src/unknown/y.mbt` | (无) | (无) | — |

**⇒ 行为变更 0 条。合入后现网零回归。**

### 4. 雷是真的：注入宽规则后的遮蔽现场

**模拟「未来有人加 `src/` 保护整棵源码树」并插到最前**：

```moonbit
PermissionRule::{
  pattern: "src/",
  allowed_roles: ["HumanSteward", "Leader"],
  reason: "（注入测试）",
},
```

| scope | 第一条匹配（旧实现） | 最长优先（新实现） | 后果 |
|---|---|---|---|
| `src/engine/engine.mbt` | `src/` (HS,Leader) | `src/engine/` (HS,Leader) | 角色相同，无后果 |
| `src/core/core_task.mbt` | `src/` (HS,Leader) | `src/core/` (HS,Leader) | 角色相同，无后果 |
| `src/router/x.mbt` | `src/` (HS,Leader) | `src/router/` (HS,Leader) | 角色相同，无后果 |
| `src/display/rank.mbt` | `src/` (HS,Leader) | `src/display/` (HS,Leader) | 角色相同，无后果 |
| **`src/store/store_sqlite.mbt`** | **`src/` (HS,Leader)** | **`src/store/store_sqlite.mbt` (HS)** | **★ Leader 获得改数据库层的权限** |
| **`src/server/server.mbt`** | **`src/` (HS,Leader)** | **`src/server/server.mbt` (HS)** | **★ Leader 获得改 MCP 接口的权限** |
| `src/unknown/y.mbt` | `src/` | `src/` | — |

**⇒ 6 个 scope 判定规则变了，其中 2 个是「HumanSteward 独占被降级为 Leader 可改」——
这就是 BUG 描述里说的「与 BUG-418 叠加 = 双重越权口」。实测确认。**

---

## 可粘贴 patch

### patch 1：`src/engine/engine_scope_perm.mbt`（实现改成真最长优先 + 抽出可注入规则表的内部函数）

```diff
--- a/src/engine/engine_scope_perm.mbt
+++ b/src/engine/engine_scope_perm.mbt
@@
 ///|
 /// 取 scope 命中的规则（`Allowed` 之外的调用方若需要规则详情，走这里）。
 pub fn matching_rule(scope : String) -> PermissionRule? {
   find_matching_rule(scope)
 }

 ///|
-/// 匹配规则——最长 pattern 优先（最具体的覆盖最宽泛的）。
-fn find_matching_rule(scope : String) -> PermissionRule? {
-  for rule in scope_permissions {
-    if scope_matches_pattern(scope, rule.pattern) {
-      return Some(rule)
-    }
-  }
-  None
-}
+/// 匹配规则——**最长 pattern 优先**（最具体的覆盖最宽泛的，BUG-419）。
+///
+/// 旧实现是「遍历 `scope_permissions`，第一条匹配即返回」，**结果依赖规则表顺序**：
+/// 任何人把一条更宽的前缀规则（如 `src/` 保护整棵源码树）插到前面，
+/// `src/store/store_sqlite.mbt`、`src/server/server.mbt` 这类 HumanSteward 独占规则
+/// 就会被**静默遮蔽**成「Leader 也能改」——两个方向都无报错、无日志、无测试红。
+///
+/// 实测（BUG-419）：注入 `src/` 到表首后，旧实现让上述两个文件从 HumanSteward 独占
+/// 降级为 Leader 可改（与 BUG-418 叠加 = 双重越权口）。
+///
+/// 现实现按 `pattern.length()` **降序遍历**，只取第一条（= 最长）匹配 ⇒ **对规则表顺序免疫**。
+/// 用「只认最长那一条」而不是「收集全部再选」，是为了让语义与注释一致：
+/// 最具体的规则**独占**裁决，不做多规则合并（合并会让权限面变成并集，更宽）。
+fn find_matching_rule(scope : String) -> PermissionRule? {
+  find_matching_rule_in(scope, scope_permissions)
+}
+
+///|
+/// 同 `find_matching_rule`，但**接受显式规则表** —— 只供白盒锁构造「宽规则排在窄规则前面」
+/// 的现场（判例-29：判据必须能测到实现，而不是只测现网那一份恰好正确的表）。
+///
+/// 生产调用一律只传 `scope_permissions`（见上一函数）⇒ 对现网零回归。
+fn find_matching_rule_in(
+  scope : String,
+  rules : Array[PermissionRule],
+) -> PermissionRule? {
+  // 按 pattern 长度降序：最长 = 最具体。稳定排序保证同长度时保持原相对顺序
+  // （同长度且都匹配的情形在 glob 前缀语义下不可能同时把一条作为另一条的子集，
+  //  故此处不需要额外的决胜规则；真要更严可在注释里追加断言）。
+  let ordered = rules.copy()
+  ordered.sort_by(fn(a, b) {
+    let la = a.pattern.length()
+    let lb = b.pattern.length()
+    if la > lb {
+      -1
+    } else if la < lb {
+      1
+    } else {
+      0
+    }
+  })
+  for rule in ordered {
+    if scope_matches_pattern(scope, rule.pattern) {
+      return Some(rule)
+    }
+  }
+  None
+}
```

> ⚠️ **`sort_by` 的签名已核**：本仓 `engine_triage.mbt:207` / `engine_dag_ext.mbt:208,567` 三处
> 都是 `sort_by(fn(a, b) { ... })` 返回 `-1/0/1` 三路 `Int32`，与上面写法一致；
> `engine_dag_ext.mbt:207` 也用了 `let sorted = tasks.copy()` 的同款前置复制。

### patch 2：新增 `src/engine/engine_scope_perm_order_wbtest.mbt`（3 格锁）

```moonbit
/// engine_scope_perm_order_wbtest.mbt —— BUG-419 的成对锁：
/// `find_matching_rule` 必须对规则表顺序免疫。
///
/// 缺陷原形：注释写「最长 pattern 优先」，实现是「第一条匹配即返回」。
/// 当前规则表顺序恰好正确 ⇒ 静默生效；一旦有人插入更宽的前缀规则，
/// HumanSteward 独占会被静默遮蔽（实测见 reports/2026-10-26-bug419-find-matching-rule-fix-plan.md §4）。

///|
/// 锁 1（零回归）：**现网规则表下，最长优先与旧「第一条匹配」结果一致**。
/// 这条锁证明「改实现不改行为」——若它红了，说明现网某条 scope 的判定会变，必须单列评审。
test "scope_order_wb1_no_regression_on_live_table" {
  let scopes = [
    "src/store/store_sqlite.mbt", "src/store/store.mbt", "src/server/server.mbt",
    "moon.mod", "moon.pkg", "src/core/core_task.mbt", "src/engine/engine.mbt",
    "src/router/model_router.mbt", "src/display/rank.mbt", "cmd/cli/main.mbt",
    "plugins/claude/x.md", "scripts/x.py", "docs/SOP.md", "memory/x.md",
    "templates/x.md", "patches/x.c", "reports/x.md", "temp/x.py", "src/unknown/y.mbt",
  ]
  for scope in scopes {
    // 「旧实现」= 按原顺序第一条匹配；「新实现」= find_matching_rule（最长优先）
    let mut first : PermissionRule? = None
    for rule in scope_permissions {
      if first is None && matches_for_test(scope, rule.pattern) {
        first = Some(rule)
      }
    }
    let newest = find_matching_rule(scope)
    assert_eq(pattern_of(newest), pattern_of(first))
  }
}

///|
/// 锁 2（**关键**）：宽规则排在窄规则**前面**时，最长优先仍返回**窄**规则。
/// 旧「第一条匹配」实现在这一格**必红**。
///
/// 判例-30 防护：临时规则表用**真 struct 字面量**构造（不是注释里的示例），
/// 且 `find_matching_rule_in` 走的是真实现路径（不是复制一份逻辑）。
test "scope_order_wb2_wide_before_narrow_still_picks_narrow" {
  let wide_first = [
    // ★宽规则排在最前（正是未来最容易犯的错）
    PermissionRule::{
      pattern: "src/",
      allowed_roles: ["HumanSteward", "Leader"],
      reason: "注入：保护整棵源码树（最宽）",
    },
    PermissionRule::{
      pattern: "src/store/store_sqlite.mbt",
      allowed_roles: ["HumanSteward"],
      reason: "数据库层唯一真源",
    },
    PermissionRule::{
      pattern: "src/server/server.mbt",
      allowed_roles: ["HumanSteward"],
      reason: "MCP 工具注册 + 核心路由",
    },
    PermissionRule::{
      pattern: "src/core/",
      allowed_roles: ["HumanSteward", "Leader"],
      reason: "核心数据结构",
    },
  ]
  // 必须命中窄规则（HumanSteward 独占），不能命中宽的 src/
  match find_matching_rule_in("src/store/store_sqlite.mbt", wide_first) {
    Some(r) =>
      assert_eq(r.pattern, "src/store/store_sqlite.mbt")
      assert_eq(r.allowed_roles.length(), 1)
    None => abort("★ 注入了 src/ 却完全没命中——匹配语义坏了")
  }
  match find_matching_rule_in("src/server/server.mbt", wide_first) {
    Some(r) => assert_eq(r.pattern, "src/server/server.mbt")
    None => abort("★ server.mbt 未命中")
  }
  // 窄规则覆盖不到的，才落到宽的 src/
  match find_matching_rule_in("src/unknown/z.mbt", wide_first) {
    Some(r) => assert_eq(r.pattern, "src/")
    None => abort("★ src/unknown/z.mbt 应落到 src/")
  }
  // 中等宽度：src/core/ 比 src/ 长 ⇒ 取 src/core/
  match find_matching_rule_in("src/core/core_task.mbt", wide_first) {
    Some(r) => assert_eq(r.pattern, "src/core/")
    None => abort("★ core_task.mbt 未命中")
  }
}

///|
/// 锁 3（**变异对照**，判例-29/30）：**把「按长度降序」那一步删掉**
/// （= 退化成按原数组顺序取第一条）⇒ 锁 2 的行为必须变成「命中 src/」。
///
/// 为什么这一格必须存在：锁 2 只能证明「现在的实现返回窄规则」，
/// 证明不了「是因为排序才返回窄规则」。这一格**手工复刻变异后的行为**并断言它确实不同 ⇒
/// 若排序被删，锁 2 必红。
///
/// 注意：这里**不真的改源码**（改不了），而是把「无排序版」写成显式循环，
/// 断言它与 `find_matching_rule_in` 的结果**不同** —— 两者不同才说明排序在起作用。
test "scope_order_wb3_mutation_control_sort_matters" {
  let wide_first = [
    PermissionRule::{
      pattern: "src/",
      allowed_roles: ["HumanSteward", "Leader"],
      reason: "宽",
    },
    PermissionRule::{
      pattern: "src/store/store_sqlite.mbt",
      allowed_roles: ["HumanSteward"],
      reason: "窄",
    },
  ]
  let scope = "src/store/store_sqlite.mbt"
  // 变异版：不排序，按原顺序第一条匹配（= 旧实现）
  let mut mutated : PermissionRule? = None
  for rule in wide_first {
    if mutated is None && matches_for_test(scope, rule.pattern) {
      mutated = Some(rule)
    }
  }
  // 真实现（带排序）
  let real = find_matching_rule_in(scope, wide_first)
  assert_eq(pattern_of(mutated), "src/")                       // 变异版命中宽
  assert_eq(pattern_of(real), "src/store/store_sqlite.mbt")     // 真实现命中窄
  // ★核心断言：两者必须不同。若有人删掉排序，real 会塌回 "src/"，本格红。
  assert_true(pattern_of(mutated) != pattern_of(real))
}

///|
/// 测试辅助：复刻 `scope_matches_pattern` 的前缀语义（白盒测试同包可见，可直接调用真函数；
/// 此处用包装只是为了名字在测试里读得清楚）。
fn matches_for_test(scope : String, pattern : String) -> Bool {
  scope_matches_pattern(scope, pattern)
}

///|
/// 测试辅助：取 pattern（`None` → 空串）。
fn pattern_of(r : PermissionRule?) -> String {
  match r {
    Some(x) => x.pattern
    None => ""
  }
}
```

> ⚠️ **落地方需核的两处语法**（我无法编译，`src/engine/` 被保护）：
> 1. ~~`Array::sort_by` 在本仓钉版 moon 的签名~~ —— **已核**：本仓 `src/engine/engine_triage.mbt:207`
>    与 `engine_dag_ext.mbt:208/567` 三处都是 `sort_by(fn(a, b) { ... })` 返回 `-1/0/1` 三路，
>    与 patch 写法**一致**。`engine_dag_ext.mbt:207` 还用了同样的 `let sorted = tasks.copy()` 前置复制。
> 2. `if first is None && ...` —— 本仓 `is None` 有先例（`dag_ext_test.mbt:1439` `if jget(j, key) is None {`、
>    `:1445` `if o.get("linear") is None || ...`），**`||` 右侧直接用，无需加括号**。
> 3. `assert_true` / `assert_eq` 的参数顺序（本仓既有测试是 `assert_eq(实际, 期望)`，已按此写）。

---

## 3 格锁设计说明（对应硬要求）

| 要求 | 对应锁 | 失败含义 |
|---|---|---|
| 锁 1：当前规则表下两者一致（零回归证明） | `scope_order_wb1_no_regression_on_live_table` | 现网判定会变 ⇒ **必须单列评审** |
| 锁 2（关键）：宽排窄前 ⇒ 仍返回窄 | `scope_order_wb2_wide_before_narrow_still_picks_narrow` | 实现仍是「第一条匹配」⇒ **BUG-419 未修** |
| 锁 3（变异对照）：删排序 ⇒ 锁 2 必红 | `scope_order_wb3_mutation_control_sort_matters` | 排序没生效 / 被删 ⇒ **锁 2 变成恒绿假锁** |

---

## 分析

### 为什么选 (a) 而不是 (b)

派单倾向 (a)，我实测后**同意并加强**：

1. **「顺序正确」是隐式契约，隐患是静默的**。选 (b) 等于把责任压给每个改规则表的人，
   而这类错误**无报错、无日志、无测试红**（§4 实测：两个 HumanSteward 独占静默降级）。
2. **实测证明雷是真的**，不是理论担忧：注入 `src/` 后 6 个 scope 判定变化，其中 2 个是**授权面扩大**。
3. **现网 0 遮蔽、0 行为变更** ⇒ (a) 的迁移成本是 **0 行规则表改动**，只有实现改。

### 为什么写成 `find_matching_rule_in(scope, rules)` 而不是就地排序 `scope_permissions`

- `scope_permissions` 是 `pub let`（**不可变全局**），就地 `sort` 需要可变副本，且**每次调用都排序**浪费；
- 抽成接受规则表的内部函数后，**测试能注入任意规则表**（锁 2/3 的前提）；
- 生产路径只多一层 `find_matching_rule` → `find_matching_rule_in(scope, scope_permissions)`，
  语义完全等价，**零回归**。

### 为什么不「收集全部匹配再合并角色集」

**合并会让权限面变成并集**：`src/` 给 Leader，`src/store/store_sqlite.mbt` 只给 HumanSteward，
合并后 Leader 反而能改数据库层 —— **比现在的「第一条匹配」更糟**。
「最长独占裁决」才是注释想要的语义。

---

## 缺口与风险

### 风险 1：改成最长优先，有没有规则因此从「命中 A」变成「命中 B」？

**现网零条**（§3 实测 23 个 scope，0 差异）。**但有三类潜在变化需知会**：

| 场景 | 会不会变 | 说明 |
|---|---|---|
| 现网 16 条规则的任何 scope | **不会** | 16 条两两无前缀关系（§1 遮蔽 0/16） |
| 未来加**更宽**的规则到表首 | **会变，且变对了** | 这正是本 BUG 要修的方向（§4 实测） |
| 未来加**更长但不是前缀**的规则 | 只在它真匹配时变 | 语义正确 |

### 风险 2：已存在的失效面（同族，不在本单范围，但建议顺手记一笔）

`moon.pkg`（#10）**对子包永不生效**：`src/engine/moon.pkg` 命中 `src/engine/`、`cmd/cli/moon.pkg` 命中 `cmd/`。
当前两处角色集相同 ⇒ 无实际后果，**但规则作者意图（「moon.pkg = 编译拓扑」独立成条）没实现**。
**最长优先也修不了这个**（`src/engine/` 比 `moon.pkg` 长 ⇒ 仍命中目录规则）。
**要不要把 `moon.pkg` 改成 `*/moon.pkg` 或 `**/moon.pkg` 是另一个决定**，需配 `scope_matches_pattern` 的 glob 扩展。
**建议单独立单，不要混进 BUG-419。**

### 风险 3：我无法编译验证

`src/engine/` 被 HumanSteward 保护（`store_sqlite.mbt` / `server.mbt` 那两条规则的同类保护），
**patch 1 的 `sort_by` 签名、patch 2 的 `is None` 写法都必须由落地方先核**（见 patch 尾注）。
**本报告给的是「语义正确 + 3 格锁设计完整」的方案，不是「已验证可编译」的代码。**

### 风险 4：`matching_rule` 目前零调用方

BUG-413 上轮新加的 `pub fn matching_rule`（:194）**没有任何生产调用方**。
改 `find_matching_rule` 会同时改到它 ⇒ 无遗漏，**但也意味着这条路径至今没被真实使用过**。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本方案报告 | `reports/2026-10-26-bug419-find-matching-rule-fix-plan.md` |
| 遮蔽/行为差异实测脚本 | `temp/audit/lane_u_shadow.py`（§1/§3）、`temp/audit/lane_u_inject.py`（§4 注入现场） |
| patch 1 | `src/engine/engine_scope_perm.mbt`（落地方应用，**我不改**） |
| patch 2 | 新文件 `src/engine/engine_scope_perm_order_wbtest.mbt`（落地方创建，**我不改**） |
| 落地后 | 按判例-11 `git commit -F msg -- src/engine/engine_scope_perm.mbt src/engine/engine_scope_perm_order_wbtest.mbt`；跑 `python scripts/moon_test_env.py src/engine` 判绿（**以汇总行为准**：`Total tests: N, passed: N, failed: 0`，BUG-142） |
| BUG-419 结案 | **我不调 `bug_fix`**（代码未落地，符合派单要求） |

### 落地后的验收清单（给落地方）

1. `moon fmt` 后 `python scripts/check_fmt_gate.py` 判格式（**本机 `moon fmt --check` 不可用，BUG-388**）
2. `python scripts/moon_test_env.py src/engine` ⇒ 汇总行 `failed: 0`，且新增 3 格全绿
3. **变异验证**：临时把 `ordered.sort_by(...)` 注释掉 ⇒ 锁 3 **必须红**（不红说明锁 3 是假锁）
4. 恢复后复跑 ⇒ 全绿
5. 才可 `bug_fix(["BUG-419"])` 并附 evidence（含上一步的变异观测）
