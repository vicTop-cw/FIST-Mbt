# Round 2 报告（12 轮六相流水线）

- **时间**：2026-10-10T23:42Z – 2026-10-11T00:00Z
- **循环**：`pipeline-12r-6phase`（max_rounds=12）
- **本轮相位**：advance → bugfind → fix_and_merge → polish（verify/advance 留到下一轮）

## 一、advance（推进）— commit `da11717`

**根任务 T0r561**「修复 parse_simple_double Int 溢出 + 小数精度」。

- 病灶：`store_sqlite_executions.mbt` 的 `parse_simple_double` 用 Int 累加解析
  SQLite cost 文本字段。MoonBit Int 为 32 位（-2^31 ~ 2^31-1），异常大字符串
  （如 "999999999999999999999"）在 `integer_part * 10 + d` 处溢出并**静默**
  绕回成乱数。
- **关键工程判断**：守卫必须**在乘法之前**判定——若 `integer_part=214748364`，
  `*10` 即越界。阈值取 `int_safe = 200_000_000`（*10 后 = 2e9 < 2^31，留 10 倍余量）。
- 超过阈值 → 切到 `int_double` Double 累积；小数部分限 15 位（再多被 1e15 除数归一）。
- 交付：`parse_simple_double` 修复 + `store_sqlite_executions_wbtest.mbt` 6 条
  白盒测试（sse_01~sse_06：正常/负数/前导空格/3e9 大数不绕回/24 位超大数/空串与纯符号）。
- 全量 **696/696** 通过。任务状态：待验收 → 已完成。

## 二、bugfind（寻虫）— BUG-215 上报

- 用 issue_scan 复扫 `src`：71 findings（medium 23 / low 48）。
- 逐条复核后命中 **2 处新真实溢出点**（与 R12-R2 刚修的 parse_simple_double 同型）：
  1. `ops_selfdrive.mbt:161` `sd_parse_int` `v = v * 10 + digit`
  2. `server/bugreport.mbt:205` `bug_parse_int` `acc = acc * 10 + ci - 48`
- **report_bug → BUG-215**（severity=low，真实触发面：`sd_parse_int` 读
  memory 计数文件，异常写入即溢出）。
- 其余 medium（23-1=22）经逐条复核判为**静态扫描假阳性**——R1 加的守卫
  （`n_safe`/`win_safe`/`max > 0`/`is_some()` 等）issue_scan 的文本模式匹配看不到。

## 三、fix_and_merge（修复）— commit `4b29152`

- `sd_parse_int`：`v >= 200_000_000` 时 `return None`（调用方视为解析失败，不产出乱数）。
- `bug_parse_int`：`acc >= 200_000_000` 时 `break`（返回已累积部分）。
- 配套白盒测试：`ops_selfdrive_overflow_wbtest.mbt` 6 条（sdp_01~sdp_06）+
  `bugreport_overflow_wbtest.mbt` 5 条（bp_01~bp_05）。
- 全量 **707/707** 通过（+11）。
- **BUG-215 状态：OPEN → FIXED**（bug_fix 落小记，heading_changed=1）。

## 四、polish（打磨）

- CHANGELOG 新增 v0.3.8 R12-P2 段，覆盖 Round 2 全部 commit（da11717 / 4b29152）。
- 本报告落盘。

## 五、使用的 FIST 工具

loop_tick / issue_scan / bug_list / report_bug / bug_fix / publish / claim / execute /
output_validate / submit / verify。

## 六、沉淀（本轮教训）

1. **Int 溢出是"同型家族病"**——同一段代码（`v = v * 10 + d`）在 3 个文件里
   重复出现（store_sqlite_executions / ops_selfdrive / bugreport）。fix_and_merge
   阶段应主动**横向排查同型**，而非只修当下命中的一处。
2. **溢出守卫必须在乘法之前**——若守卫 `v < 2e9` 放在乘法后，`v=214748364` 时
   `*10` 已经溢出。阈值取 2e8（*10 后 2e9 < 2^31）是安全下界。
3. **issue_scan 的 possible-overflow 是纯文本模式匹配**，无法区分 Int32/Int64/
   Double，也无法看到已有守卫。判据应聚焦"能否写出可复现的溢出测试"，
   而非 medium/low 计数。
4. **wbtest vs test 的取舍**：`fn`（私有）只能被 `_wbtest.mbt` 访问；
   `pub fn` 才可被 `_test.mbt` 访问。测试私有函数须用 `_wbtest.mbt` 后缀。
5. **阈值边界测试**（sdp_05/sdp_06）能捕获"刚好在阈值处"的 off-by-one：
   `sd_parse_int("2000000001")` 第 10 位触发哨兵 → None；`"199999999"` 仍成功。