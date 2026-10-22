# R131 · server `_iso_to_unix_ms` 形状与日历日校验 报告

## 一、结果摘要

- 病灶：`src/server/server.mbt` 的 `_iso_to_unix_ms` 只按固定下标取数字——分隔符位置
  从未校验（`2024x01x01T00x00x00` 也入值），日历日只挡 `d > 31`
  （`2024-02-30` 被 `_days_from_civil` 归一成 `2024-03-01`，两者同毫秒值）。
- 影响面：该函数是 `iso_minus_secs` 的唯一基准解析器，而 `iso_minus_secs` 直接决定
  `assistant_claim` / `assistant_sweep` 的心跳新鲜线与陈旧线——MCP 入参 `now` 的
  非法形状会被静默算成有效 cutoff，返回值看不出偏移。
- 修复：分隔符位严格为 `- - T/t/空格 : :`（保留空格不回归）；新增
  `_is_leap_year` / `_days_in_month`，按真实日历判日。

## 二、证据

- 修前（HEAD 实现 + 新锁）：`Total tests: 368, passed: 366, failed: 2.`
  失败读数点名：`Some(1704067200000) != None`（垃圾分隔符被接受）、
  `Some(1709251200000) != None`（`2024-02-30` 与 `2024-03-01` 同为该毫秒值）。
- 修后：`src/server` 368/368；全量 1389/1389。
- `issue_scan src/server --min-severity medium` = 0。

## 三、分析

- 为什么危险：`iso_minus_secs` 解析失败会回退墙钟；但「形状垃圾」并未解析失败，
  而是算出错误基准，cutoff 偏移无法从返回值看出来。
- 空格分隔：ops 侧文档明确 T/空格并列；本单保留空格接受，只把「任意字符」
  收成三种合法形状，避免收紧过头引入回归。
- 为什么不只是删掉 `d > 31`：Hinnant 算法对非法日自然进位、不报错，
  必须显式按真实日历判。

## 四、判据自证

- 修前红点名 2 条（`tz_minus_secs_wbtest.mbt:83` / `:95`），修后同命令 368/368。
- 空格接受断言与新形状拒绝断言成对出现，防「收紧过头」。

## 五、资源消耗

- 编译检查 2 次；`src/server` 测试 2 次；全量 1 次；issue_scan 1 次；电池 2 次。
- 说明：本机 pin 的 moonfmt 会把 `server.mbt` 无关语法重排（137 行噪声），
  已回退并按既有风格手写本单片段，最终 diff 收敛为 37 行；格式化门交 CI。

## 六、任务分配记录

- 全部由副机直接执行：定位 → 加锁证明红 → 修复 → 验证 → 交付。

## 七、遗留风险

1. 三份时间解析器（ops / router / server）各自维护日历校验，未统一到 core；
   本单只修 server 这份。
2. `_iso_to_unix_ms` 仍接受尾部多余字符（只读前 19 位）。
3. native 未跑（本机限制），判据以 JS 后端为准。

## 八、后续建议

1. 把 `is_leap_year` / `days_in_month` 提到 `src/core` 共享，消除三处分叉
   （需单独评估改动面与 `.mbti` 影响）。
2. 若要彻底严格，可拒绝 19 位之后的非 `Z` 内容。

## 九、超额内容

- 无（本单刻意保持最小 diff，未顺手改其它解析器）。

## 十、来源

- 触发：R129 / R130 同族排查第三处（server 侧）。
- 真源：`src/server/server.mbt:283-380`；测试 `src/server/tz_minus_secs_wbtest.mbt`。
- 关联：BUG-196（`iso_minus_secs` 的 `iso` 参数曾是死代码，现为真实基准）。

## 十一、终读

- 守卫回归电池（暂存全部改动后）：**66 格 / 失败 0 / SKIP 5 / 缺执行面 0**（rc=0）。
