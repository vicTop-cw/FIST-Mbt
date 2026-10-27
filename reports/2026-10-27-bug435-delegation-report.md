# BUG-435 消除手工镜像：`constraint.mbt` 委托 `rsv_action` · Lane AP · 2026-10-27

> **这是打磨，不是修 bug。** BUG-435 已由并发 lane 用交叉一致性锁标 FIXED（`017cf085`），
> 当时**两副本等价（10 格真跑全同）**。本单做的是**消除镜像本身** —— 别让后来人以为 BUG-435 之前没修好。

---

## 一、结论

| 项 | 结果 |
|---|---|
| 选哪个候选 | **(a) 委托**（依赖方向不成环，实测可行）|
| 改了什么 | `src/constraint/moon.pkg` 加 1 个 import；`constraint.mbt` 的 `rsv_conflict_verdict` 改为一行委托 |
| 编译 | `moon check --target js` → **0 errors** |
| 测试 | `src/constraint src/store src/consistency` = **102/102/0** |
| 新增锁 | **1 格**（`rsv_verdict_delegates_to_rsv_action`），变异实测**必红** |
| 依赖方向 | `constraint → store`，`store` **不** import `constraint` ⇒ **不成环** |

---

## 二、证据

### 2.1 三项先决条件（逐条实测）

```
$ git status --porcelain src/constraint/constraint.mbt
 M src/constraint/constraint.mbt          ← 看似在途
$ git diff HEAD --numstat src/constraint/constraint.mbt
                                          ← **空** ⇒ 无真实内容变更
$ git diff HEAD -- src/constraint/constraint.mbt | wc -l
0
```
⇒ **判例-21「stat-dirty 噪声 ≠ 真变更」**：mtime 变了但内容没变。确认可安全修改。

```
$ grep -n "fn rsv_conflict_verdict" src/constraint/constraint.mbt
69:pub fn rsv_conflict_verdict(

$ cat src/constraint/moon.pkg
supported_targets = "js+native"           ← 零 import
```

```
$ grep -n "constraint" src/store/moon.pkg
（无输出）  ⇒ store **不** import constraint ⇒ **不成环**
$ grep -rln "src/constraint" --include=moon.pkg .
./src/consistency/moon.pkg                ⇒ 只有 consistency 依赖 constraint
```

### 2.2 签名完全兼容

```moonbit
// src/store/store_rsv.mbt:96
pub fn rsv_action(prev : (String, String, String)?, agent : String, now : String) -> (Bool, String)

// src/constraint/constraint.mbt:69（改动前）
pub fn rsv_conflict_verdict(prev : (String, String, String)?, agent : String, now : String) -> (Bool, String)
```
**参数类型、个数、返回类型逐一相同** ⇒ 委托是一行的事。

### 2.3 可粘贴 patch

**`src/constraint/moon.pkg`**
```diff
--- a/src/constraint/moon.pkg
+++ b/src/constraint/moon.pkg
@@
+import {
+  "vicTop-cw/fist-mbt/src/store",
+}
+
 supported_targets = "js+native"
```

**`src/constraint/constraint.mbt`（函数体）**
```diff
--- a/src/constraint/constraint.mbt
+++ b/src/constraint/constraint.mbt
@@ pub fn rsv_conflict_verdict(
 pub fn rsv_conflict_verdict(
   prev : (String, String, String)?,
   agent : String,
   now : String,
 ) -> (Bool, String) {
-  match prev {
-    None => (true, "reserved")
-    Some((owner, _, _)) if owner == agent => (true, "renewed")
-    Some((_, ttl, _)) if ttl < now => (true, "taken_over")
-    _ => (false, "conflict")
-  }
+  @store.rsv_action(prev, agent, now)
 }
```
（docstring 同步改写：说明**曾是手工抄本**、为何改成委托、为何保留本函数名）

### 2.4 新增锁与变异实测

**为什么现有 4 条锁不够（判例-29）**：`rsv_verdict_reserved/renewed/taken_over/conflict`
只断言**行为**，它们在**手工镜像时代就已存在且全绿** ——
把实现改回抄本，这 4 条**照样全绿**。

**新锁 `rsv_verdict_delegates_to_rsv_action`**：同一批 8 组输入分别喂
`rsv_conflict_verdict` 与 `@store.rsv_action`，断言返回值**逐一相等**。
它锁的是「**行为恒等**这个事实」，而不是「源码里有没有 `@store.` 这个串」
（后者会命中注释 ⇒ 判例-30 自指假绿）。

**变异实测（真跑）**：
```
# 把委托改回手工抄本，并故意让它与 rsv_action 漂移（ttl <= now）
$ python scripts/moon_test_env.py --target js src/constraint
汇总：Total tests 15 / passed 14 / failed 1
F| rsv_verdict_delegates_to_rsv_action  failed          ← ★ 只有这一格抓到
```
**⇒ 新锁有判别力。恢复后 15/15 全绿。**

---

## 三、分析（为什么委托比保留镜像好）

**交叉一致性锁锁住的是「结果等价」，锁不住「改动的自由度」。**

- 镜像方案：两边各有一份实现，**改任何一边都不会编译失败**（`constraint` 原先零依赖，
  看不见 `store` 的代码）⇒ 靠锁**事后**发现漂移；
- 委托方案：只有一份实现，**漂移在结构上不可能发生** —— 没有第二份代码可以漂。

**这是「用锁兜」与「让错误无法表达」的区别。** 前者需要一把永远在场的锁 + 有人真的去跑它；
后者不需要任何锁。**锁应该用来防「未来有人破坏」，而不是用来补「现在就允许破坏的设计」。**

**保留函数名而不让调用方直接写 `@store.rsv_action`**：`constraint` 是对外的稳定 API 面
（`src/consistency` 等已 import 它），改名会波及调用点；且保留它能让「这里做裁决」这个语义有名字。

---

## 四、缺口与风险

1. **`constraint` 从此依赖 `store`**：包依赖图多一条边。当前不成环，但**若将来 `store`
   需要 `constraint`**（如 store 内部要用约束校验），**会成环并编译失败**。
   届时出路是把 `rsv_action` 下沉到两者共同的更底层包。**这是一个已显式登记的未来风险。**
2. **只消除了这一处镜像**。Gamma 的读数说仓内还有别的手工抄本（`check_two_faces` 的 F1 面
   就是在普查这类）；本单**不宣称**镜像已全部消除。
3. **`rsv_verdict_delegates_to_rsv_action` 在「抄本恰好与 rsv_action 一致」时仍是绿的** ——
   这是**设计如此**（它锁行为恒等，不锁实现写法）。若要锁「必须是真的委托」，
   就得断言源码里有 `@store.rsv_action`，而那会因注释命中造成自指假绿（判例-30）。
   **两害相权，选择了锁行为。**

---

## 五、建议入档位置

| 内容 | 位置 |
|---|---|
| 本单（打磨，非修 bug） | BUG-435 条目挂 `- polish:` 链接，**并注明「BUG-435 的 FIXED 状态不受影响」** |
| **「用锁兜 ≠ 让错误无法表达」** | 判例集（与判例-29 同族，方向是**从检测转向消除**）|
| `constraint → store` 的新依赖边 | 建议在 `src/constraint/moon.pkg` 旁的注释或 AGENTS 包依赖说明里登记 |
| `stat-dirty` 先决条件核查 | 判例-21 的又一实例（`git diff --numstat` 为空才算无变更）|
