# R130 · router `iso_to_secs` 日历日校验 + 往返锁 报告

## 一、结果摘要

- 病灶：`src/router/model_router.mbt` 的 `iso_to_secs` 只挡 `d > 31`，`2024-02-30` /
  `2024-04-31` / `2023-02-29` 被 `days_from_civil` 静默归一成下月 1 日
  （与 `2024-03-01` / `2024-05-01` / `2024-03-01` 同值）——配置里的非法 cooldown
  时间戳会被当成合法时刻参与比较。
- 修复：新增 `is_leap_year` / `days_in_month`，校验改为 `d > days_in_month(y, mo)` 即 -1。
- 新增两条锁：非法日历日必须 -1；合法日期 `iso→秒→iso` 必须逐字往返。

## 二、证据

- 修前（HEAD 实现 + 新锁）：`caf_ts_7_不存在的日历日返回-1` 落红，`Total tests: 211,
  passed: 210, failed: 1.`
- 修后：`src/router` 211/211；全量 1389/1389。
- `issue_scan src/router --min-severity medium` = 0。

## 三、分析

- 为什么此前没人发现：`d > 31` 看起来像完整校验；Hinnant `days_from_civil` 对越界日
  不报错而是自然进位，`2024-02-30` 算出的 day index 与 `2024-03-01` 相同，于是
  「非法输入」与「合法输入」撞值——单看返回值为正，调用方无从区分。
- 影响面：router 的 `iso_to_secs` 用于 cooldown 判定与滚动窗口起点
  （`model_router.mbt:167-169`、`:791`、`:839`），错值不崩溃，但会把不存在的日期
  当成真实时刻；与 R129 在 ops 侧修的是同族问题，这次换到 router 的实现。
- 为什么 `sec <= 60` 未动：闰秒 `:60` 是 ISO8601 的合法形状，收紧会扩大本单范围；
  `days_from_civil` 会把它归一为下一分钟，属已知余差，记入遗留风险。

## 四、判据自证

- 修前红点名（`moon test --target js src/router`）：
  `test src/router/model_router_ts_len_test.mbt:67 ("caf_ts_7_不存在的日历日返回-1") failed`。
- 修后同命令 211/211。
- 往返锁覆盖：1970 epoch 下界、2024 闰日、跨月/跨年、2037 上界。

## 五、资源消耗

- 编译检查 1 次（0 errors / 506 warnings，与基线一致）。
- `src/router` 测试 3 次（修前 2 次、修后 1 次）；全量 1 次；issue_scan 1 次；电池 2 次。

## 六、任务分配记录

- 全部由副机直接执行：定位 → 修复 → 加锁 → 验证 → 交付。

## 七、遗留风险

1. `sec == 60` 仍被接受并归一为下一分钟（闰秒形状），未在本单收紧。
2. router 上界 2037（Y2038）与 ops 2091 双口径仍在，未合并。
3. 两份 `iso_to_secs` 未合并（跨包依赖成本高）；R129 的顺序锁只在两边都判合法时生效。
4. native 未跑（本机限制），判据以 JS 后端为准。

## 八、后续建议

1. 若彻底消双口径，可评估让 router 依赖 ops；当前两包依赖方向不支持，属单独决策。
2. `sec == 60` 可考虑仅在 `23:59:60` 接受，其余 -1（需先确认外部调用面）。
3. `days_in_month` 现于 ops/router 各一份，可提为 core 共享工具；改动面大，暂不做。

## 九、超额内容

- 顺手加 `iso→秒→iso` 往返锁，覆盖闰日与上界，可持续抓「归一化撞值」类回归。

## 十、来源

- 触发：复核 router `iso_to_secs` 的 `d > 31` 校验（R129 同族问题）。
- 真源：`src/router/model_router.mbt:509-566`；测试 `src/router/model_router_ts_len_test.mbt`。
- 规范：AGENTS「Commit gate」；memory 追加规则。

## 十一、终读

- 守卫回归电池（暂存全部改动后）：**66 格 / 失败 0 / SKIP 5 / 缺执行面 0**（rc=0）。
