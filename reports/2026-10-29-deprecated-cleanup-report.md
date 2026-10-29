# deprecated 清理（BUG-478 · Lane DQ）

> 司令-γ · 2026-10-29 · **做了 9 个（不是 10 个）** —— `substring` 那条按判据判定运行时构造 ⇒ 不改

---

## ① `multi_store_test.mbt:9` 的 `d` —— `sed` 原文 + 判定

```moonbit
fn base_dir() -> String {
  // BUG-462：每次调用取唯一目录（bug462_unique_db 同源 token）
  let d = @store.bug462_unique_db("ms_base")
  d.substring(start=0, end=d.length() - 3)   // ← 去掉 .db 后缀当目录名
}
```

**`d` 是运行时构造，不是字面量。** `bug462_unique_db` 返回
`"temp/b462_<tag>_<token>.db"`，`<token>` 来自 `@env.rand(8)`（`bug462_fixtures.mbt:33/40`）
⇒ **长度不受测试控制**。

**⇒ 按判据「运行时构造 ⇒ 不改」，本单做 **9 个**。**

---

## ② 9 个改动逐条

| # | 位置 | 前 | 后 |
|---|---|---|---|
| 1-2 | `ops_commissar_wbtest.mbt:36/100` | `not(x)` → `!x` |
| 3 | `server_bug467_verify_identity_wbtest.mbt:85` | `not(x is Ok(_))` → `!(x is Ok(_))` |
| 4 | `omega_strong_test.mbt:529` | `parts.length()` → `parts.count()` |
| 5 | `ops_bug480_watch_probe_wbtest.mbt:29` | `Ref::new(0)` → `Ref(0)` |
| 6-7 | `store_sqlite.mbt:59/62` | `"".to_bytes()`→`@utf8.encode("")` · `is_some()`→`is Some(_)` |
| 8 | `mcp_delegate.mbt:71` | `ex.run(...)` → `Executor::run(ex, ...)` |
| 9 | `registry_test.mbt:176` | `match j.as_bool()` → `if j is True/False/else` |

---

## ③ 两个坑（都已修）

### 坑 1：`@encoding` 别名冲突

`@encoding/utf8.encode("")` 直接写报 `[4020] Package "encoding/utf8" not found`。
**根因**：`store/moon.pkg:4` 已用 `@encoding` 指 `moonbitlang/x/encoding`，
core 的 `encoding/utf8` 默认别名**也是** `@encoding` ⇒ 冲突。
**修法**：显式别名 `"moonbitlang/core/encoding/utf8" @utf8` + 调用点 `@utf8.encode`。

**⇒ 判例：`@pkg` 别名不是「包路径的最后一段」，是「无冲突时才是」。冲突时必须显式 `@别名`。**

### 坑 2：`as_bool` 替换我改错了**两次方向**

原代码 `Some(b) => if !b { abort(...) }` —— 语义是 **`b` 必须为 `true` 才通过**
（`:169` 注释明写「应标记 overconfident=true」）。

- **第一次** `if j is True { abort }` —— **完全反了**
- **第二次** `if j is False { () } else if j is True { abort }` —— **仍反**
- **第三次** `if j is True { () } else if j is False { abort }` —— 才对

**测试抓到我**（`registry_test.mbt:146` 胜者诅咒防护红）。

**⇒ 判例：`if !b { abort }` ⇔ `b == false` 时中止 ⇔ `b == true` 才通过。
改写 `is True/False` 前先写出「什么条件通过」，再翻译。**

---

## ④ 更新的「已知 warning 台账」

### 新增两条

| 类型 | 数 | 位置 | 为什么保留 | 复审条件 |
|---|---|---|---|---|
| **`deprecated`（Show→Debug）** | **11** | `cmd/cli/main.mbt:501`(2) · `router/*_wbtest.mbt` 与 `router/*_test.mbt`(9) | `star_gate.mbt:42` 是**手写 `Show` 实现**（非 derive）；3 处 `inspect(...,content=)` **快照断言**改后会变。**更深风险：快照绿灯可能只是「新快照被接受了」，不是「行为没变」。** | 单独一轮 + `--update` + **逐条核 diff** |
| **`deprecated`（JS FFI Array）** | **3** | `server/github_js.mbt:63` · `server/laya_js.mbt:18` · `server/run_check_js.mbt:32` | FFI 边界类型，改 `FixedArray` 要**同步改 JS 侧**，波及三个文件全部调用点；`run_check_js` 是**执行面**（R126） | 单独一轮 + 同步改 JS 侧 |

### 本单新增一条「不改」

| 类型 | 数 | 位置 | 为什么不改 |
|---|---|---|---|
| **`deprecated`（substring）** | **1** | `multi_store_test.mbt:9` | `d` 是**运行时构造**（`@env.rand(8)`），长度不受测试控制 ⇒ 今天 ≥3 不代表明天 ≥3 |

### 台账全貌（41 个已知有意保留）

`result_error_return` 4 · `unused_constructor` 9 · `struct_never_constructed` 3 ·
`unused_package` 4 · `deprecated_syntax` 1 · `unused_value`②预留 6 ·
**Show→Debug 11** · **FFI 3** = **41**（`substring` 1 + `unused_async` 1 属待处理，不计入）

---

## ⑤ 自报：那 3 个 `core_package_not_imported` 是我 R38 引入的

**R38 我用显式 `extend ... with @moonbitlang/core/debug.Debug::{to_repr}` 消掉了 5 个
`implicit_impl_as_method`，但这三处引用该包时 `engine/moon.pkg` 没 import 它** ⇒
报 3 个 `core_package_not_imported`（`auth_mode.mbt:53` / `engine.mbt:1597/1615`）。

**⇒ 消 5 个、引入 3 个，净消只有 2 个。**

**⇒ 它证明了一件事：消 warning 的动作本身会引入 warning。**

---

## ⑥ 读数

| 项 | 修前 | 修后 |
|---|---|---|
| `moon check` | 61 warnings / 0 errors | **49 warnings / 0 errors** |
| **`deprecated`** | **26** | **17** |
| **`core_package_not_imported`** | **3** | **0** |

**测试**：`src/store` 130/130/0 · `src/executor` 30/30/0 · **全量 1896/1896/0**

**提交**：
- 笔 1 `2908ff58c` `fix(build):` —— `src/engine/moon.pkg` 加 `debug`（修 R38 遗留）
- 笔 2 `a9c2d6075` `refactor(deprecated):` —— 7 个文件，9 个替换

**探针残留**：`git status --short src/ | grep -E 'dbg_|probe_'` ⇒ 仅他人已跟踪的
`ops_bug480_watch_probe_wbtest.mbt`（我只改了一行），**无我的残留**。

---

## ⑦ 缺口与风险

- **R1** `deprecated` 17 个中：11 Show→Debug + 3 FFI 已进台账**不做**，其余待查 + `deprecated_syntax` 1。
- **R2** `substring` 那条**没做**，进台账。若将来该函数返回短串才暴露 —— **那时该改的是 `bug462_fixtures`，不是这里**。
- **R3** `commit_scoped.sh` 暂存残留**已由他人按 BUG-482 修好**（实测输出「已清理暂存残留」✅）。

---

## ⑧ 建议入档（判例）

① `@pkg` 别名冲突时必须显式 `@别名`（默认别名只在无冲突时成立）
② 双重否定 `if !b { abort }` 改写 `is True/False` **极易读反** —— 先写「什么条件通过」再翻译
③ 消 `implicit_impl_as_method` 要**连 import 一起加**，否则「一换一」甚至「一换多」
