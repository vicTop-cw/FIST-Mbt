# Round 5 报告（12 轮六相流水线）

- **时间**：2026-10-11T00:24Z – 2026-10-11T00:31Z
- **循环**：`pipeline-12r-6phase`（注意：进程重启后 loop registry 清空，
  本轮以 `loop_create` 重建同名环，`max_rounds=5` 为重建默认值，实际继续原 12 轮计数）
- **本轮相位**：advance（性能）→ bugfind → fix_and_merge → polish

## 一、advance（推进）— commit `efb138f`

**根任务 T0r564**「dag_mc 性能优化：消除 5000×N 次 DB 读」。

- **病灶**：`mc_finish` 递归里每次调 `self.get_task(id)`——
  SqliteStore 下是 DB 查询。主循环 `for s = 0; s < n` 内每样本对每个任务调用
  `mc_finish`，最多 n×N = 5000×200 = **100 万次 DB 读**。
- **修复**：在样本循环外预计算 `deps: Map[String, Array[String]]`，
  内层递归只查内存 Map。语义等价（`mc_scope_tasks` 已载入内存，`depends_on` 不变），
  环保护（BUG-204 的 `visiting`）与 memo 化语义保持不变。
- 全量 **714/714** 通过。任务状态：已完成。

## 二、bugfind（寻虫）— BUG-217 上报

- 本轮聚焦 issue_scan 的 possible-overflow / string-index 未复核项：
  1. `ops_ts.mbt:47-48` `days * 86400 + hour * 3600 + min * 60 + sec`——
     **真实 bug**：`if year < 2024` 只有下界没有上界，year=9999 时
     days = 2,910,875，*86400 = 2.51e11，远超 Int32 → 静默绕回乱数。
     心跳超时判定、归档保留期比较等全部依赖 `iso_to_secs`。
  2. 其余 string-index（`ready_ids[0]` / `modes[0]` / `counts[0]` /
     `cands[0]` 等）均有 `length() > 0` 前置守卫，确认假阳性。
  3. `ops_ts.mbt:15` `v = v * 10 + char_int(...)` —— `parse_digits` 最大 len=4
     （年份），最大 9999，不溢出；但 `parse_digits` 是私有函数，
     **没有独立的防溢出守卫**——R2 BUG-215 同族，但本轮未触发（调用方固定 len）。
- **report_bug → BUG-217**（severity=medium，真实触发面：heartbeat/heal/archive）。

## 三、fix_and_merge（修复）— commit `ab9be6c`

- `iso_to_secs` 在 `if year < 2024` 后对称加 `if year > 2091 { return -1 }` 上界：
  - 2091-2024=67，67*365=24455，+365=24820，*86400 ≈ 2.14e9 < 2^31-1
  - 2092 起最坏 case 25185*86400 ≈ 2.18e9 已越过 Int32 上界
  - 2091 覆盖"闰年/月末最大天数"的安全余量
- 配套白盒测试：`ops_ts_wbtest.mbt` 7 条
  （正常/首日/下界/上界 2092/边界 2091/极端 9999/短字符串）。
- 全量 **721/721** 通过（+7）。
- **BUG-217 状态：OPEN → FIXED**（bug_fix 落小记，heading_changed=1）。

## 四、polish（打磨）

- 本报告落盘。CHANGELOG 更新待补（下轮）。

## 五、使用的 FIST 工具

issue_scan / report_bug / bug_fix / loop_create / loop_tick / publish /
claim / execute / submit / verify。

## 六、沉淀（本轮教训）

1. **DB 查询藏在递归里是最隐蔽的性能债**——`mc_finish` 是 memo 化 DFS，
   看起来"已经优化了"（只算一次每节点），但每节点调 `get_task` 走 DB。
   **memo 化的是计算，不是 I/O**——如果 memo 的 key 计算里还有 I/O，
   性能问题依然存在。
2. **上界与下界必须对称**——`if year < 2024` 有下界但没上界，是"半防御"。
   防御要成对写：`if x < MIN || x > MAX { bail }`。
3. **Int32 溢出的边界必须手算**——2091 看起来"很远"，但
   (2091-2024)*365*86400 = 2.14e9 已接近 2^31-1（2,147,483,647）的 99.7%。
   2092 起就爆了。**时间戳函数是 Int32 溢出的重灾区**——
   因为乘 86400（一天秒数）会迅速放大年份差。
4. **`parse_digits` 是同族潜伏点**——虽然本轮没触发（len ≤ 4），
   但 `v = v * 10 + d` 这个模式在 3 个文件里出现过（R2 修了 2 处，
   `ops_ts.mbt:15` 是第 3 处）。当前靠"调用方固定 len"保证安全，
   未来若加 `parse_digits(chars, 0, len=10)` 就会爆。
5. **测试期望值要对着实现算，不能想当然**——我最初写
   `2024-01-01 = 0`，实际实现是 `day * 86400`（day 从 1 起算），
   所以首日 = 86400 不是 0。**写边界测试时先读实现语义再断言**。
6. **进程重启会丢 loop registry**——loop_create 的状态在内存，
   重启后需重建。这解释了为什么 `loop_tick` 报 `loop not found`。
   **生产环境需要持久化 loop 状态**（可作下轮算子扩展候选）。