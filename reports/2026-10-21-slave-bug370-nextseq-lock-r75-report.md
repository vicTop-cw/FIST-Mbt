# R75 报告 · BUG-370 出路③ 收尾：bug_next_seq 白盒锁（slave/test/bug370-nextseq-lock-r75）

## 结果摘要

BUG-370 ③（写侧 `report_bug` ID 分配）收尾。取证发现：**实现侧已是「现有条目最大 BUG-n + 1」**（`src/server/bugreport.mbt` 的 `bug_next_seq`，BUG-217 时代落地；账本 R47 小记「③写侧没做」是滞后信息——它当时没做的是指「动 `.mbti` 接口面」的裁决，而现实现根本不动签名）。真正缺的是账本 ③ 点名的那格白盒锁，本单补齐：

- **新增 `src/server/bugreport_nextseq_wbtest.mbt` 七格**（该函数此前零测试覆盖）：
  1. `bn_01` 空账从 1 起；2. `bn_02` 单抬头 max+1；3. `bn_03` 乱序账本取最大（首次空闲会提前复用小号）；4. `bn_04` 串号账本（BUG-183 两条例子）仍 max+1——BUG-370 事故形状的直接回归；5. `bn_05` 正文提及 `BUG-999` 不计数、缩进抬头计数；6. **`bn_06` 同一棵账本连报两条 ⇒ 编号必不同且严格递增（③ 点名格）**；7. `bn_07` 超长编号串走溢出哨兵（2e8 break）不产出绕回乱数。
- **文档面测试计数同步**：9 份 36 处 1351→1358。

## 资源消耗

1 小时内；2 轮 src/server 包测试 + 1 轮全量 + 4 把守卫。

## 任务分配记录

副机单兵完成。分支 `slave/test/bug370-nextseq-lock-r75` **基于 r71**（`slave/fix/issue-scan-min-severity-r71` @ 320b1c5）叠栈——r71 树可编译，master 259b56a 树构建崩（见 r73 报告取证）。

## 金条八实测

- 全量 `moon test --target js`：`Total tests: 1358, passed: 1358, failed: 0`（`temp/r75_moontest.log`）
- src/server 包：361/361（`temp/r75_server_test2.log`）
- `check_test_sync temp/r75_moontest.log` PASS（实测 1358；131 份文档 19 条声明全等；must-carry 5 份齐）
- `check_badge temp/r75_moontest.log README.md` PASS（README 徽章 1358 == 实测）
- `check_bug_reference_integrity` rc=1：判定面 10 条 == r71 基线，**新文件零新增悬空**（BUG-370/183/192/217 均在账）
- `moon fmt` 本机 ICE（既知 rc=127 形状）→ `moonfmt.exe` 逐文件对照，采纳其数组换行口径落盘后复跑仍 361/361

## 遗留风险（预存红，点名不代修）

- r71 基点预存项全部原样继承（master 冲突标记由 r71 修、电池 2 失败由 r72 修、BOM/登记由 r73 修、CI 接线由 r74 修）——本单不重复。
- 账本 BUG-370 的 R47 小记与代码现状不符（说「③没做」）：按 FIXED 终态互锁纪律**未手改账本**，以本报告 + `memory/2026-10-21.md` R75 节留痕；若主机要用 `bug_fix` 补小记，证据即本单。

## 后续建议

1. 合序沿用：r71 → r72 → r73 → r74 → 本单（本单与 r72/r73/r74 零文件交叠）。
2. `bug_next_seq` 的 max+1 语义今后若改「按时间序分配」等策略，`bn_04`/`bn_06` 两格会当场红——这是有意设计的守门位。

## 超额内容

无（账本滞后信息的取证属本单必要部分，未越界改账）。

## 来源

- 基点：r71 @ 320b1c5；分支：`slave/test/bug370-nextseq-lock-r75`
- 证据：`temp/r75_moontest.log` / `temp/r75_server_test2.log` / `temp/r75_testsync.log` / `temp/r75_badge.log` / `temp/r75_bugref.log` / `temp/r75_fmt_out.mbt`
- 账本锚：`memory/bugs.md` BUG-370 条（L5959 起）及其 R47 小记
- 记忆：`memory/2026-10-21.md` R75 节
