# Round 4 报告（12 轮六相流水线）

- **时间**：2026-10-11T00:11Z – 2026-10-11T00:17Z
- **循环**：`pipeline-12r-6phase`（max_rounds=12）
- **本轮相位**：advance（算子扩展）→ bugfind → fix_and_merge → polish

## 一、advance（推进）— commit `129416f`

**根任务 T0r563**「算子扩展：preset_loop 新增 2 个预设」。

- 用户显式要求"算子扩展"。现有 `preset_loop` 只有 3 个预设
  （fix-iterate / build-verify / full-iterate），缺少两类高价值组合：
  1. **perf-iterate**：性能迭代环（advance → polish → verify → advance）——
     R3 dag_mc 性能优化就是这类工作的实例，但预设里没有对应开箱环。
  2. **scan-fix-verify**：扫描到修复到验证环（bugfind → fix_and_merge → verify）——
     R2 BUG-215（同型 Int 溢出家族 3 处）就是一次 bugfind 命中 3 个点、
     一并修完并验证的模式，但预设里没有对应收口环。
- 交付：`preset_loop` 从 3 个扩到 5 个 + 2 条新 wbtest 测试。
- 全量 **709/709** 通过。任务状态：待验收 → 已完成。

## 二、bugfind（寻虫）— BUG-216 上报

- 本轮聚焦 issue_scan 的 possible-overflow 里尚未复核的一处：
  `evolve.mbt:429` `(a.score * 1000.0).to_int().to_double() / 1000.0`。
- **真实 bug**：MoonBit `Double.to_int()` 在 |值| > Int32 范围（2^31-1 = 2,147,483,647）
  时 **panic**。`Artifact.score` 文档标注 [0,1]，但 `evolve_submit` 未钳制输入，
  理论上可传 score=3000000 → *1000 = 3e9 > 2^31 → evolve_snapshot 展示面
  直接 panic。score 为 NaN 时 `.to_int()` 行为未定义。
- **report_bug → BUG-216**（severity=low，真实触发面：evolve_snapshot 展示面）。
- 其余 issue_scan findings 沿用 R3 复核结论（全部为静态扫描假阳性）。

## 三、fix_and_merge（修复）— commit `253ca24`

- `evolve_summary_line`：显示 clamp 到 [0, 2_000_000]（*1000 后 2e9 < 2^31），
  NaN 或负值回退 0，杜绝 Double→Int panic。
- 配套白盒测试：`evolve_summary_line_wbtest.mbt` 5 条
  （正常/极大 3e6/NaN/负值/恰好 2e6 阈值）。
- 全量 **714/714** 通过（+5）。
- **BUG-216 状态：OPEN → FIXED**（bug_fix 落小记，heading_changed=1）。

## 四、polish（打磨）

- CHANGELOG 新增 v0.3.8 R12-P4 段，覆盖 Round 4 commit（129416f / 253ca24）。
- 本报告落盘。

## 五、使用的 FIST 工具

loop_tick / issue_scan / bug_list / report_bug / bug_fix / publish / claim /
execute / output_validate / submit / verify。

## 六、沉淀（本轮教训）

1. **算子扩展要"从实例找缺口"**——与其凭空想新工具，不如回顾已完成的工作，
   看哪些工作模式**没有对应的开箱预设**。R3 dag_mc 性能优化对应 perf-iterate，
   R2 BUG-215 同型家族修复对应 scan-fix-verify——这两个都是真实工作实例
   但预设里找不到，就是缺口。
2. **Double→Int 转换是"静默 panic"源**——MoonBit 的 `Double.to_int()`
   在值超出 Int32 范围时 panic，NaN 时行为未定义。凡是从外部输入（如
   evolve_submit 的 score）来的 Double 转 Int，必须显式 clamp。
   这与 R12-R2/R12-R3 修的 Int 溢出是**同族病**（32 位 Int 范围问题），
   但触发面不同：Int 溢出是乘法绕回，Double→Int 是转换 panic。
3. **"文档标注 [0,1]"不等于"运行时钳制"**——`Artifact.score` 注释写 [0,1]，
   但 `evolve_submit` 直接把参数传给构造函数。只要有一个调用点没钳制，
   防御就得在消费端做（clamp），而非只靠上游契约。
4. **阈值边界测试能捕获"恰好阈值"的 off-by-one**——`art(2_000_000.0)`
   恰好是 clamp 边界：2e6 * 1000 = 2e9 < 2^31，合法；3e6 * 1000 = 3e9 > 2^31，panic。
   两条测试一起覆盖"边界两侧"。
5. **`@double.not_a_number` vs `0.0/0.0` 的取舍**：前者是 MoonBit 标准库
   推荐 API 但需要 `moon.pkg` 显式导入 `moonbitlang/core/double`，
   否则编译告警；后者不依赖导入但在部分目标平台行为不确定。
   测试里用 `0.0/0.0` 足够验证"NaN 不 panic"，生产代码的 `is_nan()` 守卫
   才是关键。
6. **测试计数**：R4 起点 709（R3 完成值），新增 5 条后 714。
   每轮 advance/bugfind 都应有可数的测试增量，否则说明"没做实事"。