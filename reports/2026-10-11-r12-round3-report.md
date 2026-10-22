# Round 3 报告（12 轮六相流水线）

- **时间**：2026-10-11T00:06Z – 2026-10-11T00:08Z
- **循环**：`pipeline-12r-6phase`（max_rounds=12）
- **本轮相位**：advance → bugfind（fix_and_merge/polish/verify 推进中）

## 一、advance（推进）— commit `69ca1dc`

**根任务 T0r562**「dag_mc 预计算 tier_cache 消除重复难度解析」。

- 病灶：`engine_dag_mc.mbt` 主循环 `for s = 0; s < n` 内，每个样本对每个任务
  重复调用 `extract_difficulty`（含正则/字符串扫描）+ `mc_durations`。
  默认 samples=1000、上限 5000，任务数 N 常见 50-200，最坏
  **5000×200 = 100 万次重复难度解析**。
- 修复：把两个纯函数调用提到 `for s` 之前，用 `tier_cache` 数组
  （`(id, a, m, b)` 三元组）缓存；内层循环只做一次三角形采样。
  - 数组替代 Map：避免 String 哈希（旧代码每样本建 Map）
  - 每样本减少 N 次字符串扫描
  - 语义等价：`mc_durations` 是纯函数，`mc_tri_sample(state,...)` 与
    `state` 更新顺序一致（遍历顺序相同）
- 交付：`engine_dag_mc.mbt` 性能优化 + 现有 `dag_mc_test.mbt` 5 条测试全过
  （确定性可复现 / 关键度 / 空作用域 / samples 钳制 / BUG-182 字段形状）。
- 全量 **707/707** 通过。任务状态：待验收 → 已完成。

## 二、bugfind（寻虫）

- issue_scan 复扫 `src`：71 findings（medium 23 / low 48）。
- 逐条复核（本轮聚焦 substring-overrun 与 unprotected-division，因这两类
  一旦守卫写错是**运行时 panic** 而非静默错误值）：
  - **7 处 unprotected-division**：全部有守卫（`n_safe`/`win_safe`/`need_safe`/
    `total > 0`/`n > 0`），issue_scan 文本模式匹配看不到。
  - **15 处 substring-overrun**：全部先 `length() > N` 校验再 `substring`。
  - **1 处 unwrapped-unwrap**：`ops_watchdog.mbt:416` 有 `is_some()` 守卫。
  - **22 处 possible-overflow**：3 处 R12-R2 已修（parse_simple_double /
    sd_parse_int / bug_parse_int），其余为 Double 运算或已钳制。
- 结论：**未新增 BUG**。账本维持 0 OPEN。

## 三、fix_and_merge（修复）

- 本轮无新 BUG 需要修（上一轮 advance 已修并提交）。
- 复扫确认 R1/R2 加的守卫全部到位，无遗漏。

## 四、polish（打磨）

- CHANGELOG 新增 v0.3.8 R12-P3 段，覆盖 Round 3 commit（69ca1dc）。
- 本报告落盘。

## 五、使用的 FIST 工具

loop_tick / issue_scan / bug_list / publish / claim / execute / submit / verify /
output_validate。

## 六、沉淀（本轮教训）

1. **循环不变式外提是最稳的性能优化**——`extract_difficulty` 在 5000 样本
   × 200 任务下被调 100 万次，而任务难度在整个模拟期间**不变**。这是
   "编译器不会帮你做的循环不变式提升"（编译器无法证明纯函数无副作用），
   必须手工外提。
2. **语义等价证明**：`mc_durations` 是纯函数，`mc_tri_sample` 的 `state`
   更新顺序与遍历顺序耦合。只要 `tier_cache` 按 `tasks` 顺序 push、
   内层循环按 `tier_cache` 顺序遍历，随机序列完全一致，结果可复现。
3. **数组 vs Map 的取舍**：`dur`/`memo`/`critical_hits` 仍需 Map（按 id 查询），
   但 `tier_cache` 只需顺序遍历，数组更省哈希开销。
4. **substring-overrun 是"静态扫描最不可信"的一类**：`if s.length() > N` 的
   守卫写在 `substring` 之前的同一行，issue_scan 的 `scan_guard_length_above`
   必须精确匹配子串；一旦换行/加空格就判假阳性。判据应聚焦"能否写出
   使 `substring` 越界的输入"，而非文本模式。
5. **unprotected-division 已全部加哨兵**——这是 R1 的主要产出，
   issue_scan 的 7 条命中在逐条复核后全部确认有守卫。
   "有守卫"本身是运行时事实，静态文本匹配看不到。
6. **算子扩展角度**：本轮聚焦性能优化（用户显式要求），
   未新增 MCP 工具/算子；若后续轮次发现新算子机会（如 DGM 演化算子、
   组合环预设），另行立项。