# BUG-413 · `reserve_scope` 第三态 `unregistered` · Lane Q 交付 · 2026-10-26

> **交付形态**：核心代码改动落在**受保护文件**（`src/engine/` = HumanSteward/Leader），
> 本 lane 为 Executor ⇒ 实测被拒 ⇒ 按派单要求**出精确 patch 方案，由统帅应用**。
> 本 lane **已完成可做的那部分**：`templates/pipeline_mode_explore.md` 语义同步（已 granted）。

---

## 一、结论

### 1.1 改在哪一层

核心逻辑落在 **`src/engine/`**，共两个文件：

| 文件 | 位置 | 权限 | 状态 |
|---|---|---|---|
| `src/engine/engine_scope_perm.mbt` | `check_scope_permission`（原 L138-172） | **受保护**（HumanSteward, Leader） | **只出 patch** |
| `src/engine/engine_rsv.mbt` | `rsv_set`（L13-24）/ `rsv_try_set`（L31-45） | **受保护** | **只出 patch** |
| `src/engine/engine_scope_perm_wbtest.mbt` | 新增测试文件 | 同目录 ⇒ 受保护 | **只出 patch** |
| `templates/pipeline_mode_explore.md` | 步骤 4 第 4 道门 + 冲突处置 | **可改（已 granted）** | ✅ **已同步** |

**为什么不能绕过**：`scope_permissions` 里 `pattern: "src/engine/"` 的规则
`allowed_roles: ["HumanSteward", "Leader"]`，实测：
```
reserve_scope("src/engine/engine_scope_perm.mbt", agent="lane-q-scope")
→ 拒绝：角色 'Executor' 无权编辑 'src/engine/engine_scope_perm.mbt'。
   允许的角色：HumanSteward, Leader；规则原因：引擎层 = 工具调用的骨架
```

### 1.2 三种拒绝面**现在还不能区分**，patch 后能

| 调用 | 现在返回 | patch 后应返回 |
|---|---|---|
| `reports/…`（未登记） | `拒绝：scope '…' 无权限规则（fail-closed）。指挥官需要在 engine_scope_perm.mbt 里加规则才能开放` | ✅ `action="unregistered"`（advisory 登记） |
| `scripts/…`（已登记·够格） | `{"action":"reserved", …}` | ✅ **零回归**，仍 `reserved` |
| `src/server/server.mbt`（HumanSteward 保护） | `拒绝：角色 'Executor' 无权编辑…允许 HumanSteward` | ✅ **仍拒**（不能因 `unregistered` 放行） |

**根因定位（代码级）**：`engine_scope_perm.mbt:146-152` 把「无匹配规则」与
「有规则但角色不够」**混成同一种 `Err(String)`**：

```moonbit
match find_matching_rule(scope) {
  None => Err("拒绝：scope '…' 无权限规则（fail-closed）。…")   // ← 未登记
  Some(rule) => if allowed { Ok(rule) } else { Err("拒绝：角色 '…' 无权编辑 …") }  // ← 角色无权
}
```
调用方（`engine_rsv.mbt`）只会把 `Err` 直通上抛 ⇒ **下游无法分辨**这两种语义完全不同的拒绝。

### 1.3 HumanSteward 保护**完好**（patch 中显式设了三道防绕过）

1. `check_scope_permission` 的 `Some(rule)` 分支**不碰**——角色检查逻辑一字不改
2. `rsv_set` / `rsv_try_set` 的 `RoleDenied(e) => Err(e)` **是第一分支**，硬拒
3. 新增锁 3 专门断言四条保护路径（`store_sqlite.mbt` / `store.mbt` / `server.mbt` / `moon.mod`）
   对 **Executor 和 Leader 都仍然 `RoleDenied`**

---

## 二、证据

### 2.1 grep 实现位置

```
$ grep -rn "reserve_scope\|engine_scope_perm\|scope_perm" src/ --include=*.mbt -l
src/claimguard/claimguard.mbt
src/claimguard/claimguard_wbtest.mbt
src/constraint/constraint.mbt
src/engine/engine_rsv.mbt            ← reserve 转发 + 权限门禁
src/engine/engine_scope_perm.mbt     ← 权限规则表 + 判定函数
src/ops/ops_modes.mbt
src/ops/ops_modes_wbtest.mbt
src/server/server.mbt                ← 工具面渲染
src/store/store_sqlite.mbt
```

`check_scope_permission` 的**全部调用点**（决定改动波及面）：
```
$ grep -rn "check_scope_permission" --include=*.mbt src/
src/engine/engine_rsv.mbt:19
src/engine/engine_rsv.mbt:37
src/engine/engine_scope_perm.mbt:13   (docstring)
src/engine/engine_scope_perm.mbt:140  (定义)
```
⇒ **仅 2 处真实调用**，同单内一并改，**无外部波及**。

### 2.2 现有测试覆盖 = **零**

```
$ ls src/engine/*scope_perm*
src/engine/engine_scope_perm.mbt        ← 只有实现，没有 wbtest

$ grep -rn "check_scope_permission\|scope_permissions" src/engine/*wbtest*.mbt src/engine/*test*.mbt
（无输出）
```
⇒ **`check_scope_permission` 从落地至今没有任何测试**。这本身就是
「机制存在但没人锁」的形状（同判例-5 家族），patch 中补齐 5 条锁。

### 2.3 权限矩阵现状（`scope_permissions`，L33-119）

| 层 | pattern | allowed_roles |
|---|---|---|
| 统帅独占 | `src/store/store_sqlite.mbt`、`src/store/store.mbt`、`src/server/server.mbt`、`moon.mod` | `HumanSteward` |
| 军官+ | `src/core/`、`src/engine/`、`src/router/`、`src/display/`、`cmd/`、`plugins/`、`moon.pkg` | `HumanSteward, Leader` |
| 全员 | `scripts/`、`docs/`、`memory/`、`templates/`、`patches/` | `HumanSteward, Leader, Executor` |
| **无规则** | 其余全部（`reports/`、`tests/`、`src/claimguard/`、`src/constraint/`…） | **无 ⇒ 一律 fail-closed** |

### 2.4 测试与编译（本 lane 已完成部分）

```
$ moon check --target js
Finished. moon: ran 24 tasks, now up to date (49 warnings, 0 errors)      ← 0 errors

$ python scripts/check_doc_surface.py
PASS 文档面一致：171 工具在 AGENTS/README 逐个可查、分组和=171、当前自述版本=0.3.10、J6 … J17 …
$ python scripts/check_doc_surface.py --selftest
rc=0

$ git diff --stat templates/pipeline_mode_explore.md
 templates/pipeline_mode_explore.md | 17 +++++++++++++++--
 1 file changed, 15 insertions(+), 2 deletions(-)
```

**注**：核心逻辑改动未应用，故未跑 `src/engine src/store src/server` 的全绿验证——
**该验证必须由应用 patch 之后执行**（见 §四 验证清单）。

---

## 三、分析

### 3.1 为什么「三态」是正确的最小改法

现状的 `Result[PermissionRule, String]` 是**二值**：成功 / 失败。
但真实语义有**三值**：

| 语义 | 谁能决定 | 对并行的意义 |
|---|---|---|
| 够格 | 角色矩阵 | 机制担保独占 |
| 不够格 | 角色矩阵 | 硬拒，不许并行 |
| 没人管 | 规则表里没这个路径 | **不是拒绝**——责任转移给调用方 |

第三态被压进 `Err` 后，调用方唯一能做的就是把整条路摘掉 ⇒ explore 并行门恒不可过。
**这不是「保守」，是把「未登记」误当成「禁止」。**

### 3.2 为什么不加规则、而要加状态

给 `reports/` 等路径加 `PermissionRule`（全员可改）也能「让它过」，但那是**扩大授权面**：
一旦 `reports/` 进入规则表，它就受**角色检查**约束，而角色来自 `infer_role_from_agent`
（名字推断，宽松）⇒ 等于给一个弱边界穿上正式授权的外衣。

`unregistered` 反其道：**不授权，只登记**。写权限仍完全由角色矩阵决定，
未登记路径的并发责任显式交回调用方。**这是正确方向。**

### 3.3 为什么 `Allowed` 不带 `PermissionRule` 载荷

`PermissionRule` 是包内**私有** struct（L22 `struct PermissionRule`）。
把它作为 `pub enum` variant 的载荷会触发可见性错误。
本仓现有 `pub enum`（`TaskStatus` / `DiffOp`…）的 variant **全是零元或内置类型载荷**，无私有 struct 先例。

⇒ 设计取舍：`Allowed` 零元 + 新增 `matching_rule(scope)` 供需要详情者查询。
**代价**：调用方多一次调用；**收益**：零可见性风险、零 `moon.pkg` 改动。

### 3.4 `RsvOutcome` 不加字段的依据

`src/store/store_rsv.mbt:62-70` 的 `RsvOutcome` 有 5 字段，`action` 已是 `String`。
全仓消费方检查：
```
server.mbt:5101  "action": Json::string(o.action)      ← 直出字符串，无枚举 match
```
⇒ **只多一个合法取值，零破坏**。若未来有人对 `action` 做穷尽枚举才需同步。

---

## 四、精确 patch（供统帅应用）

完整可粘贴的代码见 **`temp/bug413_patch_plan.md`**（本 lane 工作副本）。
摘要：

### 4.1 `src/engine/engine_scope_perm.mbt`

**新增**（插在 `PermissionRule` 之后）：

```moonbit
pub enum ScopeVerdict {
  Allowed
  RoleDenied(String)
  Unregistered(String)
}
```

**替换** `check_scope_permission`（L138-172）为返回 `ScopeVerdict` 的三分支实现：
`None => Unregistered(...)` / `Some(rule) => if allowed { Allowed } else { RoleDenied(...) }`。

**新增** `pub fn matching_rule(scope) -> PermissionRule?`（转发 `find_matching_rule`）。

### 4.2 `src/engine/engine_rsv.mbt`

`rsv_set`：`RoleDenied(e) => Err(e)`；`Allowed | Unregistered(_) => self.store.rsv_set(...)`

`rsv_try_set`：`RoleDenied(e) => Err(e)`；`Allowed => 原样`；
`Unregistered(_) =>` 仍走后端裁决，但 `action: if o.reserved { "unregistered" } else { o.action }`
（**conflict 保持 conflict**——那条信息更硬）。

### 4.3 新增 `src/engine/engine_scope_perm_wbtest.mbt`

| 锁 | 断言 |
|---|---|
| 锁 1 | `reports/x.md` + Executor ⇒ `Unregistered`（新行为） |
| 锁 2 | `scripts/x.py` + Executor ⇒ `Allowed`（零回归） |
| 锁 3 | 四条 HumanSteward 路径 × {Executor, Leader} ⇒ **全部 `RoleDenied`**（防绕过） |
| 锁 4 | 三种面互异（分类器判别力） |
| 锁 5（接线格，判例-29） | `rsv_try_set` 实现里三态真被分流，非只测纯函数 |

### 4.4 应用后验证清单

```bash
moon check --target js                                   # 0 errors
python scripts/moon_test_env.py --target js src/engine src/store src/server
                                                          # 判绿看 Total tests / passed / failed
# 变异对照：把 4.2 的 Unregistered(_) 分支改回硬拒 ⇒ 锁 1 / 锁 5 必红
# 实跑三例（见 §2.4 表格）：
#   未登记 → unregistered ／ 已登记 → reserved ／ HumanSteward 路径 → 仍拒
```

---

## 五、缺口与风险

1. **本次未完成核心修复**：`src/engine/` 受 `HumanSteward/Leader` 保护，本 lane 无权改。
   **BUG-413 在 patch 应用前仍是 OPEN**——本报告不构成「已修复」。
2. **`find_matching_rule` 的「最长 pattern 优先」是假的**（注释 vs 实现不一致）：
   L175 注释写「最长 pattern 优先（最具体的覆盖最宽泛的）」，实现却是
   L177-181「**第一条匹配即返回**」。
   本 patch **刻意不动它**（动了会改既有权重裁决面 = 破坏零回归），
   但这是**既存缺陷**：若将来加 `src/store/` 这类宽前缀规则且排在 `store_sqlite.mbt` 之前，
   窄规则会被**静默遮蔽**。**建议单开。**
3. **`unregistered` 放宽方向**：两个 lane 可同时登记同一未登记路径而不被机制拦住。
   缓解：`action` 标签显式归责 + explore 模板已写死「必须字面不相交」为并行前置条件。
4. **`infer_role_from_agent` 仍是宽松名字推断**（含 `lead`/`polish` 即 Leader）——
   本 patch 不动，但意味着「角色无权」面**本身不是强安全边界**。
   若被 agent 用 `leader-xxx` 命名即可越过所有 Leader 级保护。**这是独立的安全面缺口。**
5. **`server.mbt` 的 reason 文案未改**（受保护）：`unregistered` 时 `reason` 留空，
   调用方靠 `action` 字段分辨。**可选优化**，不必须。

---

## 六、建议入档位置

| 内容 | 位置 |
|---|---|
| BUG-413 patch 方案 | `memory/bugs.md` 的 BUG-413 条目挂 `- patch: reports/2026-10-26-bug413-reserve-scope-third-state.md` |
| 「未登记 ≠ 被拒」的分类器教训 | 判例集（与「conflict vs fail_closed 混同」同族） |
| `find_matching_rule` 注释与实现不一致 | **新 BUG 或 BUG-413 追记**（建议单开，属裁决面静默遮蔽） |
| 「`check_scope_permission` 零测试覆盖」 | 判例-5 家族实例（机制存在但没人锁） |
| `infer_role_from_agent` 宽松推断可越权 | 安全面独立单 |
