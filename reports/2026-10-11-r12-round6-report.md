# Round 6 报告（12 轮六相流水线）

- **时间**：2026-10-11T00:36Z – 2026-10-11T00:53Z
- **循环**：`pipeline-12r-6phase`（round=1，第 6 轮实际轮次）
- **本轮相位**：advance（性能）→ bugfind → fix_and_merge → polish

## 一、advance（推进）— commit `00626a7`

**根任务 T0r565**「board_ascii 消除重复 getter 调用」。

- **病灶**：`append_group` 内 `t.get_id()` 被调用 2-3 次
  （length 检查 + substring + 回退），`t.get_description()` 被调用 2 次
  （一次截断 desc，一次喂 `extract_difficulty`）。SqliteStore 下每次都是 DB 读。
  2079 任务 → 多出约 2079 次 DB 读。
- **修复**：各取一次复用——`let tid = t.get_id()`、`let full_desc = t.get_description()`。
  语义完全等价（同值复用，不改变展示内容）。
- 全量 **721/721** 通过。任务状态：已完成。

## 二、bugfind（寻虫）— BUG-218 + BUG-219 上报

承接 BUG-217（ops_ts 上界）继续深挖 **所有 `*86400` 乘法** 的同族问题：

1. **`model_router.mbt:252`**（BUG-218）——
   `days_from_civil(y, mo, d) * 86400` 中 `y > 9999` 允许到 9999，
   但 **Y2038 问题**：2038-12-31 → days=25201, *86400 = 2.18e9 > 2^31-1。
   实测最大安全年份 **2037**。这是经典 Y2038 bug。
2. **`ops_cleanup.mbt:18`**（BUG-219）——
   `retention_days * 86400` 无上界。retention_days=30000 时
   *86400 = 2.59e9 **溢出 Int32（绕回不是 panic）**，产生负阈值，
   所有归档任务被误清 → **数据丢失**。

## 三、fix_and_merge（修复）— commit `486e874` + `3444a70`

- **BUG-218**：`if y > 2037 { return -1 }`（model_router 用 1970 epoch，
  与 ops_ts 的 BUG-217 用 2024 参考不同口径，故安全年份边界不同）。
  配套 3 条 wbtest（2037 合法 / 2038 溢出 -1 / 9999 -1）。
- **BUG-219**：`if retention_days > 24855 { return Err }`。
  24855*86400 = 2,147,472,000 < 2^31-1（2,147,483,647），24856 起溢出。
  配套 3 条 wbtest（30000→Err / -1→Err / 30→Ok）。
- **BUG-217/218/219 状态：OPEN → FIXED**（3 笔 bug_fix 落小记）。

## 四、polish（打磨）

- 本报告落盘。CHANGELOG 更新见下一节。

## 五、使用的 FIST 工具

issue_scan / report_bug / bug_fix / publish / claim / execute / submit /
verify / loop_tick。

## 六、沉淀（本轮教训）

1. **所有 `*86400` 乘法都是 Int32 溢出的候选**——
   一天 86400 秒是个大系数，任何天数×86400 超过 24855 天（68 年）就溢出。
   **时间戳/清理函数是重灾区**。本轮一口气收了 3 个（BUG-217/218/219），
   都是同一模式：下界检查存在、上界缺失或形同虚设。
2. **"看起来很远"的年份其实很近**——2038-12-31 距今天只有 12 年，
   但 `days*86400` 已经溢出。**经典 Y2038 问题在 Int32 下是真实存在的**，
   不是段子。
3. **防御要成对写，且上界要真的算过**——`y > 9999` 形同虚设，
   因为 `days*86400` 早在 2038 就溢出了。**检查的边界必须是"最坏 case
   不溢出"的边界，而不是"看起来合理"的边界**。
4. **DB 读藏在 getter 里是隐蔽性能债**——`t.get_id()` 看起来是纯内存，
   实际 SqliteStore 下是 DB 查询。**任何循环里重复调 getter 都要怀疑**。
   本轮 `board_ascii` 一处就省了 2079 次 DB 读。
5. **溢出是绕回不是 panic**——Int32 乘法溢出在 MoonBit/JS 下不会报错，
   只是静默给出错误值。**BUG-219 尤其危险**：产生负阈值 → 误清归档 → 数据丢失，
   但进程不崩、没有日志、没有异常，只有数据不见了。
6. **算子扩展应继续沿 "性能" 主线推进**——
   R3 修了 dag_mc 难度解析，R5 修了 dag_mc deps 映射，R6 修了 board_ascii
   getter 重复。**"每个热点找一次"是可靠的方法论**。