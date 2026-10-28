# 无效 catch 全仓扫描 + 修复 + 判据（BUG-465）

> **执行人**：司令-γ · **日期**：2026-10-28
> **一句话**：**这是 MoonBit 的语言层边界，不是「我们写错了」** —— `catch` 只包 `raise` 效果，
> 而 FFI 抛的是 JS 运行时异常。全仓 **4 处**无效 catch，已全修，并做成判据进电池。

---

## 结论

| 项 | 结果 |
|---|---|
| **全仓扫描** | `unused_try` **4 处**（编译器算好的）；其中 **3 处生产代码 + 1 处测试** |
| **FFI 面** | **4/4 全部在 FFI 面**（`db.close()` / `db.prepare` / `stmt.step` / `instrumented_tool` 注册） |
| **修复** | **4 处全删**，逐处证明**零行为变化** |
| **判据** | `scripts/check_effective_catch.py`，selftest **8/8**（含 2 个变异对照），**已进电池** |
| **修复后** | `unused_try` **4 → 0**；全量 **1765 / passed 1765 / failed 0** |

---

## 证据

### §1 扫描读数（`unused_try` 是免费判据）

```
$ moon check --target js 2>&1 | grep -c 'unused_try'
4

$ 逐条位置：
  src/store/store_sqlite.mbt:101            db.close() catch { _ => () }
  src/store/store_sqlite.mbt:219            try { db.prepare(...)... } catch { _ => probe_ok = false }
  src/server/hat_hexa_tools.mbt:21          try { ...整段 instrumented_tool 注册... } catch { _ => s }
  src/store/store_bug463_close_wbtest.mbt:352  try { db.close() } catch { _ => () }   ← 我在 R24 写的
```

**分类**：
| 处 | 类别 | catch 体 | 删了有行为变化吗 |
|---|---|---|---|
| `:101` | **FFI 面**（`db.close()`） | `_ => ()` | **无**（从未执行） |
| `:219` | **FFI 面**（`db.prepare`/`stmt.step`/`column_text`） | `_ => probe_ok = false` | **无**：`probe_ok=false` 仍由**显式分支** `None => probe_ok = false` 设置；而「FFI 抛异常」这条路本来就是**直接崩**，不是设 false |
| `hat_hexa:21` | 非 FFI 直调（`instrumented_tool` 注册，无 raise） | `_ => s` | **无**：块内无 raise，正常路径完全一致 |
| `wbtest:352` | 测试（`db.close()`） | `_ => ()` | **无**（我上一单写的，已改直调） |

### §2 为什么这是**语言层边界**（不是我们写错）

**MoonBit 的效果系统**：`catch` / `try·catch` 只处理**声明了 `raise` 的效果**。
而 FFI 库的签名**没有 raise 标注**：

```moonbit
// .mooncakes/daqing/sqlite/sqlite_js.mbt
pub fn Database::close(self : Database) -> Unit { self.db.close() }        // ← 无 raise
pub fn Database::prepare(self, sql : String) -> Statement? { ... }         // ← 无 raise
pub fn Statement::step(self : Statement) -> Bool { ... }                   // ← 无 raise
```

**而 `node:sqlite` 的 `DatabaseSync.close()` 在已关闭时抛 JS 运行时异常。**
⇒ **异常能穿过 MoonBit 的 catch 边界** —— 因为效果系统看不见它。

**实测三格（BUG-463 报告，真跑）**：
```
P2  let _r : Unit? = Some(db.close()) catch { _ => None }   → 仍抛 database is not open
Q1  try { db.close() } catch { _ => () }                    → 仍抛
Q2  裸 db.close()                                            → 抛（对照：证明 Q1 不是"根本没抛"）
```

**⇒ 编译器早就知道**（它一直在报 `unused_try`），**只是没人把这个 warning 当判据。**

### §3 判据：`scripts/check_effective_catch.py`

**判法**：用 `moon check` 算好的 `unused_try`，**不自己写正则**。
- 为什么不自己扫 `catch {`：需要知道每个被调函数**是否 `raise`** ⇒ **要类型信息**，正则拿不到；
- 编译器已经在算，且**随版本自动正确**。

**解析要点（实测踩过）**：按 `Warning:` 分块，块内含 `unused_try` 才取该块内**第一条** `╭─[ ... ]` 定位。
**不能用「unused_try 前后各抓 N 行」** —— 会串到相邻 warning 的位置上（selftest 有专门一格钉住）。

**rc 契约**：`0` 无 / `1` 有（逐条点名）/ `2` 自拒（moon check 跑不起来，或输出里既无 `unused_try` 也无汇总行）。

**覆盖面（写在运行时输出里，不只 docstring）**：
```
[覆盖面] 本判据只判「编译器能证明无意义的 try/catch」：
  ✅ moon check 报 unused_try 的每一处
  ✅ 这类在 FFI 面上是**装饰性防线**：FFI 抛的是 JS 运行时异常，catch 拦不住
  ❌ 不判：包住「声明了 raise 但实际不 raise」的函数（编译器认为有意义）
  ❌ 不判：包住「间接调 FFI 的包装函数」（包装函数自己没 raise 标注）
  ⇒ PASS 不代表「没有无效 catch」，只代表「编译器证明不了有」
```

### §4 selftest 8 格

```
[OK] clean-no-hits
[OK] dirty-two-hits
[OK] dirty-keeps-first-path
[OK] dirty-does-not-borrow-neighbor            ← 不串到相邻 warning（实测踩过）
[OK] ★MUTATION-keyword-removed-no-hits         ← 词被改名 ⇒ 判 0，不凭空报红
[OK] ★MUTATION-unrecognizable-output-self-rejects  ← 无汇总行 ⇒ 自拒 rc=2
[OK] coverage-note-in-output
[OK] ffi-runtime-exception-explained
[selftest] 8/8 格通过
```

### §5 变异对照（真跑）

```
注入：把 store_sqlite.mbt 的 `db.close()` 改回 `db.close() catch { _ => () }`
  $ python scripts/check_effective_catch.py
  [违例] 发现 1 处 unused_try：
    ✗ src/store/store_sqlite.mbt:48
  rc=1                                          ← 判据抓住了

恢复：cp /tmp/ss3.bak → 判据 [违例]（无），unused_try 计数 = 0
```

### §6 修复后行为验证（零变化的证据）

```
$ python scripts/moon_test_env.py src/store
  汇总：Total tests 111 / passed 111 / failed 0     ← 与修前一致

$ python scripts/moon_test_env.py        # 全量
  汇总：Total tests 1765 / passed 1765 / failed 0
```

**⇒ 删掉 4 处无效 catch 后，全仓 1765 格**全过**，零行为变化。**

---

## 分析：为什么「catch 对 FFI 无效」是语言设计边界

### 两条异常通道，只有一条被 `catch` 管

| 通道 | 谁产生 | MoonBit `catch` 管得到吗 |
|---|---|---|
| **`raise` 效果** | MoonBit 函数声明 `raise` | ✅ 管得到（这是它设计的靶子） |
| **宿主运行时异常** | JS：`throw`；FFI 边界直接冒出来 | **❌ 管不到** |

**⇒ FFI 函数即便内部会 `throw`，只要签名没写 `raise`，效果系统就看不见它。**
**这不是 daqing/sqlite 的 bug** —— FFI 的 `raise` 标注需要手写，而 JS 的 `throw` 不可静态枚举。

### 这件事的代价：**假的防线比没有防线更坏**

`db.close() catch { _ => () }` 的三重误导：
1. **读代码的人**以为「关闭期异常被吞掉了」⇒ 不会去查「二次 close 会不会崩」；
2. **写测试的人**以为覆盖到了 ⇒ `k463_8` 那格就是照着这个假设写的（结果测了一个不可实现的契约，R24 已修）；
3. **`catch` 本身占了一行**，让 review 时看着「处理过了」。

**⇒ `unused_try` 这个 warning 一直在报，就是这个假防线唯一的警报 —— 而它没被当判据。**

---

## 缺口与风险

### 1. 判据只覆盖「编译器能证明」的部分 —— 已知边界

`unused_try` = 0 **不等于**没有无效 catch。**两类不报**：
- 包住「**声明了 raise 但实际从不 raise**」的函数 ⇒ 编译器认为有意义，**运行时仍拦不住 JS 异常**；
- 包住「**间接调 FFI 的包装函数**」（包装函数自己没 raise 标注，内部调 FFI）⇒ 同上。

**⇒ 这两类要靠人工 review，本判据明说了不覆盖。**

### 2. `store_sqlite.mbt:101` 现在**真的会抛**了

删掉假 catch 后，「外部直关 → `s.close()`」**会抛 `database is not open`**（此前也抛，只是被 `catch` 的**存在**掩盖了）。
**这是我上一单（R24）已经处理过的**：所有夹具改用 `s.close()`，不再制造这个状态；
`k463_8b` 那格把「二次 close 会抛」钉成可执行事实。

### 3. 我没有改 `daqing/sqlite` 的 `raise` 标注

给它补 `raise` 能让 `catch` 真的生效，但那是**依赖库**（`.mooncakes/` 被 gitignore，`moon update` 会重生成），
且要给 6 个函数补标注 + 处理所有调用面的效果传播 —— **改动面远超本单**。
**⇒ 本单采取「删掉假防线 + 让真实行为显式」，而不是「修补依赖库」。**

### 4. 进电池的两格都是 `gate`（不是 known-red）

因为修完后 `unused_try` = 0 ⇒ 期望 `rc=0` 是**真绿**，不是免检牌。

---

## 建议入档位置

| 内容 | 位置 |
|---|---|
| 本报告 | `reports/2026-10-28-effective-catch-report.md` |
| 判据 | `scripts/check_effective_catch.py`（8 格 selftest） |
| 执行面 | `scripts/run_guards.py`（两格 gate）+ 锚点 `rulers=126 battery=85 gate=93` |
| 修复 | `src/store/store_sqlite.mbt`（:101 / :219）· `src/server/hat_hexa_tools.mbt`（:21）· `src/store/store_bug463_close_wbtest.mbt`（:352） |
| **建议后续** | ① 给 `daqing/sqlite` 补 `raise` 标注（独立立项，改动面大）② 人工 review 上述两类「编译器不报」的无效 catch ③ 把「FFI 调用后的 catch」列入 code review 清单 |
