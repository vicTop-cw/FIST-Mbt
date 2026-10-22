# R128 · iso_to_secs 字段范围校验：堵掉 Int32 真实溢出（issue_scan secs-overflow 归零）

- 日期：2026-10-22
- 分支：`slave/fix/iso-secs-field-bounds-r128`（基线 `gitcode/master` = `dcefdeb8`；R127 未并线，本单独立）
- 改动：`src/ops/ops_ts.mbt`（+32 / −3）、`src/ops/ops_ts_wbtest.mbt`（+33）；提交见本报告提交

## 一、结果摘要

R127 收尾的全量扫描里最后剩一条 medium：`src/ops/ops_ts.mbt` 的 `days * 86400 + hour * 3600 + min * 60 + sec` 被判 `secs-overflow`。复核结论是**真阳性**，不是扫描器误报：

- `parse_digits` 只做两位累加，对 `day/hour/min/sec` 不做任何范围校验；
- 上游只挡了 `year`（2024..2091）与 `mon`（越界时 `month_days` 静默取 0）；
- `2091-12-99T23:59:59` ⇒ `days = 67*365 + 334 + 99 = 24888` ⇒ `24888*86400 = 2,150,323,200` 越过 Int32 上限 `2,147,483,647`，在 Int32 下绕回成负值（≈ `-2,144,557,697`），心跳/归档比较会得到错误先后。

本单四处修：

1. `parse_digits` 逐字符验数字（`'0'..'9'` 之外返回 -1），堵掉 `char_int('a') = 49` 这类「非数字被算成合法秒数」的静默入值；
2. `iso_to_secs` 增加 `mon/day/hour/min/sec` 范围校验，非法即返回 -1；
3. 乘法改用 Int64（`to_int64()` + `86400L` 字面量，与 `src/server/server.mbt` 的 `parse_iso_ms` 同口径），最后窄化回 Int32——即使未来放宽 `year` 上界也不会静默绕回；
4. 删掉 `month_days` 的 `else 0` 兜底（`mon` 已校验，兜底反而掩盖非法月份）。

读数：`moon check --target js` = 0 errors；`src/ops` 测试 205/205；全量 `moon test --target js` = 1391/1391（基线 1387 + 本单新增 4）；`issue_scan src/ops --min-severity medium` 由 1 降为 0；电池 66 格 / 失败 0 / SKIP 5 / 缺执行面 0。

## 二、证据

### 2.1 病灶算术

| 输入 | 旧解析 | 旧 `days` | 旧运算结果（Int32） |
|---|---|---:|---:|
| `2091-12-99T23:59:59` | day=99（无校验） | 24888 | 乘积 2,150,323,200 > 2^31-1，绕回 ≈ -2,144,557,697 |
| `2091-13-31T23:59:59` | mon=13（兜底 0） | 24486 | 2,115,676,799（不溢出但把 13 月当年初，语义错） |
| `2091-12-31T24:00:00` | hour=24（无校验） | 24820 | 2,144,537,999（越界 1 小时仍被接受） |
| `2024-01-01T00:00:0a` | sec='a' → 49（无校验） | 1 | 86,449（非数字被静默算成 49 秒） |

第一行即 issue_scan 命中的形状：`days * 86400` 在 Int32 下越界。

### 2.2 修复面

- `src/ops/ops_ts.mbt:12-26`：`parse_digits` 逐字符验数字，非数字返回 -1；
- `src/ops/ops_ts.mbt:58-85`：五个字段范围校验 + Int64 乘法 + 窄化回 Int32；
- `src/ops/ops_ts_wbtest.mbt`：新增 4 条白盒锁——
  - `iso_to_secs: day=99 返回 -1（R128 Int32 溢出）`；
  - `iso_to_secs: 月日时分秒越界返回 -1`（6 个断言）；
  - `iso_to_secs: 非数字字段返回 -1`（`0a` 用 `'a'→49` 证明只靠范围检查挡不住）；
  - `iso_to_secs: 2091-12-31T23:59:59 边界值仍可解析`（精确值 `2_144_534_399`）。

### 2.3 判据自证

- **扫描前后同尺**：把 `git show dcefdeb8:src/ops/ops_ts.mbt` 落到 `temp/r128-before/`，`issue_scan --min-severity medium` = **1**（line 60，`secs-overflow`）；对现树 `src/ops` = **0**。
- **上界可证**：字段已校验且 `2024 ≤ year ≤ 2091` ⇒ `days ≤ 24820`、`total_secs ≤ 2,144,534,399 < 2^31-1`，Int64 乘积再窄化不绕回；边界单测钉死该读数。
- **非数字闸承重**：`'a'` 的 `char_int` 是 49，落在秒段合法区间内——只加范围检查会放行，必须逐字符验数字。
- **残留噪声**：`ops_ts.mbt` 仍报 1 条 low `possible-overflow`（`parse_digits` 定长 2/4 位累加，值域 ≤ 9999）与 1 条 info `long-function`（校验让函数变长），均非本单目标档位。
- **格式面**：`moon fmt` 本机 rc=127（BUG-329），等价执行 `~/.moon/bin/moonfmt.exe` 后 LF 转 CRLF；两文件 crlf 正常、bareLF=0、无制表符。

## 三、资源消耗

- 本单约 50 分钟（含编译等待与 2 发全量测试）。
- `moon check --target js` 4 发（末发 0 errors / 506 warnings 为存量）；`src/ops` 测试 3 发（205/205）；全量 2 发（1391/1391）；`issue_scan` 4 发；moonfmt 3 发；电池 1 发。
- 无子代理派单：单文件 + 单测的轻任务，按分流决策树直接做；证据面全部主代理亲跑。

## 四、任务分配记录

- 触发任务：R127 收尾扫描遗留的 1 条 medium（真阳性复核）。
- 执行：主代理（直接编辑 + 运行验证）。
- 终审：主代理（check / 包测 / 全量 / 扫描 / 电池五面读数）。

## 五、遗留风险

1. **并线冲突（需注意）**：R127 与本单都在 `memory/2026-10-22.md` 尾部追加，两单先后并线时后合并方需解一次尾部冲突（建议先 R127 后 R128，由后手重解）。代码面两单无重叠文件。
2. `parse_digits` 以 -1 作错误哨兵；当前四个调用点都紧跟范围检查，-1 必被拒。若未来把该函数复用到「允许负数」的字段，需改哨兵形态。
3. 分隔符（`-`、`T`、`:`）仍未校验：`2024:01-01T00:00:00` 的字段数字合法即会通过。属于格式严格性，非本单范围。
4. native 目标未跑（本机权威面为 JS；native 环境与 BUG-133 历史见 AGENTS）。
5. 扫描器仍有 1 条 low `possible-overflow`（`parse_digits` 定长累加）与 1 条 info `long-function`，均非本单目标档位。

## 六、后续建议

1. `secs-overflow` 规则可考虑识别「相邻字段范围校验 + Int64 口径」作为 suppress 形状——本单用 Int64 只能让这一处静音，规则仍假设「乘法必 Int32」。
2. 若追求格式严格性，可把 `iso_to_secs` 与 `src/server/server.mbt` 的 `parse_iso_ms` 统一到一处，避免两个时间解析器继续分叉。
3. 若嫌 info 噪声，可把五段范围校验合成一个 `if`（server.mbt 风格）或抽 `iso_fields_valid` 小函数。

## 七、超额内容

- 原计划只加范围校验，实际补上非数字字符闸（`0a` 秒静默入值的真 bug）。
- `parse_digits` 的 -1 让 `year` 里的非数字也不再依赖「碰巧越界」被拒。
- 乘法升 Int64 后，未来放宽 `year` 上界（如 2200）不会静默绕回，属于顺手的纵深防御。

## 八、来源

- 触发：R127 `issue_scan` 全量扫描遗留 medium；`git show dcefdeb8:src/ops/ops_ts.mbt` 复扫 1 条 medium。
- 真源：`src/ops/ops_ts.mbt`；同口径参照 `src/server/server.mbt:344`。
- 测试：`src/ops/ops_ts_wbtest.mbt` 新增 4 条。
- 规范：AGENTS「Commit gate」；memory 追加规则。

## 九、R129 追记（同日叠单：跨解析器顺序锁 + 闰年口径）

### 结果摘要

- 在 R128 基础上补齐 `iso_to_secs` 分隔符校验（第 5/8/11/14/17 位固定为 `-` `-` `T/t/空格` `:` `:`），
  并在 `src/server` 新增跨解析器白盒锁：ops 版与 router 版对同一对合法时间戳必须给出相同先后关系。
- 该锁**当场抓到真 bug**：ops 版用「365 天年 + 非闰月表」，`2024-02-29` 与 `2024-03-01`
  都算成 day=60（同值），且 `2024-02-30` / `2024-04-31` 等不存在日期被静默接受。
  改为真闰年口径 + 当月天数校验，两个日期的值分别为 5,184,000 / 5,270,400。
- 数值变化只影响同体系时间差（调用点为 heal/cleanup/heartbeat/watchdog/board 排序，
  无持久化契约）；2091 上界仍安全：`24,837 * 86,400 + 86,399 = 2,146,003,199 < 2^31-1`。

### 证据

- 修前 `src/server` 跨锁红：`diff: -0 +-1`（ops 判 2024-02-29 == 2024-03-01，router 判前者早一天）。
- 修后 `src/ops` 208/208、`src/server` 367/367、全量 1395/1395。
- `issue_scan src/ops --min-severity medium` = 0；`src/server` = 0。

### 判据自证

- `src/ops/ops_ts_wbtest.mbt` 新增闰日/非法日期用例（5 断言），上界读数更新为 2,146,003,199。
- `src/server/iso_secs_cross_wbtest.mbt`：9 枚时间戳两两 36 对，双解析器 sign 比较逐一相等。

### 遗留风险

- 两份 `iso_to_secs` 参考系仍不同（ops 自 2024、router 自 1970 真闰年），本单只钉
  「先后关系一致」，不合并实现——合并需跨包依赖调整，收益不抵风险。
- ops 版仍接受尾部多余字符（`...:00` 之后的 `Z` 或其它后缀不校验），与 router 的
  长度策略不同；两版都容忍 `Z`，但更长的垃圾串同样入值，未在本单收紧。

### 终读

- 守卫回归电池（暂存全部改动后）：**66 格 / 失败 0 / SKIP 5 / 缺执行面 0**（rc=0）。
