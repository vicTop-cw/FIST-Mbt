# report_bug 尾随空行归一 · 白盒锁补测报告

> **任务**：给 `report_bug` 的尾随空行归一补白盒锁 + 变异对照（Lane D 遗留的「无人区」）
> **执行**：司令-ζ　**日期**：2026-10-26
> **纪律**：**只加测试，不改生产代码**（`src/server/bugreport.mbt` 变异后已逐字节还原）

---

## 一、结果摘要

| 项 | 值 |
|---|---|
| 新增文件 | `src/server/bugreport_trailing_newline_wbtest.mbt`（**1 个**，未跟踪 → 待提交） |
| 新增锁 | **3 条**（`tnl_1` / `tnl_2` / `tnl_3`） |
| 生产代码改动 | **0**（变异用，已还原；`git diff -- src/server/bugreport.mbt` 为空） |
| `moon check --target js` | **49 warnings, 0 errors** ✅ |
| `src/server` 测试（正常态） | **Total tests: 390, passed: 390, failed: 0** ✅ |
| `src/server` 测试（变异态） | **Total tests: 390, passed: 387, failed: 3** ← **3 条锁全红** ✅ |
| 变异点位置核验 | `bugreport.mbt:348` **代码行**（非注释）✅ |

**结论：3 条锁全部经过「改坏必红 / 还原必绿」双向验证，不是只增计数的空锁。**

---

## 二、被测缺陷回顾（为什么要补这个锁）

`report_bug` 落盘 `memory/bugs.md` 时会多写一个尾随空行，导致 pre-commit 的
`git diff --cached --check` 报 `new blank line at EOF` 挡住整笔提交。

**关键点：同一语义有两处实现，历史上只修了一处。**

| 路径 | 走的函数 | 首次修复 `09c0867c` |
|---|---|---|
| `bug_fix` / `bug_mark_status` | `bug_lines_to_text`（末尾空行归一） | ✅ 修了 |
| **`report_bug`** | **自己 fold 出 `entry` 再 `old + entry` 直拼** | ❌ **没修** |

叠加机制：`old` 以 `\n` 结尾 → `entry` 又以 `lines.push("\n")` 收尾 ⇒ 落盘 `…\n` + `\n` = **两个尾随换行**。

Lane D 补修 `ac4c7fa6`（MCP 真调实测 2→1 PASS），但**未补白盒锁** ⇒
**谁删掉 `bugreport.mbt:344-348` 那几行归一逻辑，全部既有测试仍然全绿。**
这与 BUG-411 完全同构：**修复已落地、测试面 0 命中。**

---

## 三、三条锁的设计

| 锁 | 断言 | 为什么需要 |
|---|---|---|
| **tnl_1** | `report_bug` **连报两条**后，落盘末尾换行数 **== 1** | 核心回归锁。**连报两条是关键**——只报一条时 `old` 为空串，叠加效应不复现，锁不住缺陷发生点 |
| **tnl_2** | 末尾换行数 **不为 0 且不为 >1**（两档错误分开报） | 锁住归一的**方向**：写成「删掉所有尾随换行」也能让部分场景过，但违反 POSIX 惯例且会让 `split("\n")` 读回多一个空元素 |
| **tnl_3** | `report_bug` 与 `bug_fix` 两条路径的尾随换行数**必须一致** | 这是 Lane D 发现的核心——**同一语义两处实现**。不要求合并（那是重构，超边界），只要求产出一致：谁再改坏一处，立刻红 |

**量化口径**：用「末尾连续换行个数」而非 `trim` 后比较——因为要锁的正是**精确形状**，`trim` 会把「1 个」与「2 个」抹平。

**隔离口径**：全部落在独立 scratch 账本 `temp/bug9_tnl*/memory/bugs.md`，
**不碰仓库真账本**（`project_dir` 越界会被拒 ⇒ bug 账只能开在临时区，见 BUG-53 双轨记账）。

---

## 四、变异对照实测（判例-29/30 硬要求）

### 4.1 变异点确认落在**代码**而非注释（判例-30）

```bash
$ grep -n "let normalized = combined" src/server/bugreport.mbt
348:  let normalized = combined[0:end].to_owned() + "\n"      ← 真实赋值行
```

### 4.2 变异内容

```moonbit
// 改前（348 行，真归一）
  let normalized = combined[0:end].to_owned() + "\n"

// 改后（把归一逻辑摘掉，等价于回到 Lane D 修之前的形状）
  let _ = end
  let normalized = combined
```

**改后确认**：
```
  let mut end = combined.length()
  while end > 0 && combined[end - 1] == '\n' {
    end = end - 1
  }
  let _ = end
  let normalized = combined          ← 归一被摘掉
```

### 4.3 变异态读数（**锁真的红了**）

```
$ python scripts/moon_test_env.py --target js src/server
  F| test ...bugreport_trailing_newline_wbtest.mbt:56 ("tnl_1 report_bug 落盘末尾换行恰好 1") failed
  F| test ...bugreport_trailing_newline_wbtest.mbt:112 ("tnl_2 归一是恰好一个终止换行而非零个") failed
  F| test ...bugreport_trailing_newline_wbtest.mbt:150 ("tnl_3 report_bug 与 bug_fix 尾随换行一致") failed
  汇总：Total tests 390 / passed 387 / failed 3
Total tests: 390, passed: 387, failed: 3.
```

**3 条锁全部变红，全部精确点到自己那一条。**

### 4.4 还原后读数（**回到全绿**）

```
$ cp temp/_bugreport_backup.mbt src/server/bugreport.mbt
$ sed -n '348p' src/server/bugreport.mbt
  let normalized = combined[0:end].to_owned() + "\n"          ← 已还原

$ python scripts/moon_test_env.py --target js src/server
  汇总：Total tests 390 / passed 390 / failed 0
Total tests: 390, passed: 390, failed: 0.
```

### 4.5 生产文件零残留

```
$ git diff --stat -- src/server/bugreport.mbt
（空 = 与 HEAD 逐字节一致）
```

---

## 五、过程中的一个真实事故（必须记）

**我第一次写这个测试文件时是「按猜测的签名」写的，`moon check` 报 22 errors，直接卡住了全仓 pre-commit。**

Lane M 实测确认：把该未跟踪文件移出仓库后 `moon check` 立即 0 errors。
⇒ **一个未跟踪的坏文件能以坏状态留在工作树，挡住全仓任何人的提交。**

**根因（两条）**：
1. `report_bug` 真实签名比我猜的长得多（含 `detail~` / `severity~` / `ref_call_id~` / `reported_by~` /
   `publish_task~` / `eng : @engine.FistEngine` / `now~` 七个具名参数）——我没先 `grep` 就动笔；
2. `bug_fix` 返回 `Result[Json, String]`（不是 raise 型），我用了 `catch` 接。

**修法**：`grep -n "pub fn report_bug" src/server/bugreport.mbt` 核真实签名 →
把 `catch` 改成 `match { Ok(_) => () , Err(m) => fail(...) }` → 0 errors。

**教训（给后续 lane）**：
> **写测试前先核真实签名**（`grep "pub fn <name>"`），不要按 API 直觉写。
> 一个未跟踪的坏测试文件就能卡住全仓 pre-commit——**分多次写时，每次落盘都应是可编译形态**。

---

## 六、缺口与风险

1. **两处归一实现仍未合并**（`report_bug` 自己归一 + `bug_lines_to_text` 归一）。
   本单按边界**只加锁不重构**。`tnl_3` 已把「两条路径必须一致」钉住，
   但**根因（同一语义两份实现）仍在**——将来仍可能有人只改一处。
   **建议**：单开一单把两处归一收口成一个私有函数（如 `bug_normalize_eof`）。
2. **本单未覆盖 `bug_mark_status` 路径**。`tnl_3` 只比了 `report_bug` vs `bug_fix`；
   `bug_mark_status` 也走 `bug_lines_to_text`，与 `bug_fix` 同路，风险较低但**未直接锁**。
3. **`temp/bug9_tnl*` 目录会留在 temp/ 下**（与既有 `bug9_status` 同惯例，`.gitignore` 覆盖）。
4. **报错细节**：变异态下三条锁都红，但我未逐一验证「哪条锁抓的是哪一档错误」的**精确对应**
   （例如把归一改成 `rstrip` 时应只有 `tnl_2` 红）。若将来需要更细的变异矩阵，可补。

---

## 七、建议入档位置

| 内容 | 位置 |
|---|---|
| 3 条锁 + 变异实测（387/3 → 390/390） | 本报告；测试名 `tnl_1/2/3` 可在 `scripts/README.md` 的 bug 账相关条目旁登记 |
| **「未跟踪的坏测试文件能卡全仓 pre-commit」** | **判例集候选**（与 Lane M 的「打印 ≠ 生效」同批；建议命名「坏未跟踪文件 = 全仓提交阻塞器」） |
| **「写测试前先 `grep "pub fn <name>"` 核签名」** | `docs/probe-authoring.md` 或 AGENTS 的测试编写纪律 |
| 「同一语义两处实现，只修一处」仍需重构收口 | `memory/bugs.md` BUG-409 家族追记 + 单开重构单 |

---

## 八、来源

- 被测生产代码：`src/server/bugreport.mbt:335-351`（`report_bug` 归一）、`:494-512`（`bug_lines_to_text`）
- Lane D 补修：`ac4c7fa6`
- 首次（不完整）修复：`09c0867c`
- 新增测试：`src/server/bugreport_trailing_newline_wbtest.mbt`
- 门禁：`moon check --target js`（0 errors）/ `moon_test_env.py --target js src/server`（390/390，变异态 387/3）
