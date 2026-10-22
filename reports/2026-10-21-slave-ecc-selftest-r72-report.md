# R72 `slave/fix/ecc-selftest-r72` — 修复同步基点 scripts 面坏合并：ecc 自检 rc=2 归零

- 分支：`slave/fix/ecc-selftest-r72`（基点 gitcode master `259b56a`，一单一分支，与 R71 互不叠加）。
- 单据来源：R71 报告后续建议③——两处基点预存红中先收口 `check_exit_code_contract --selftest` rc=2。

## 结果摘要

**取证（根因 = 又一处 master 坏合并，且是"静默"级）**
- `scripts/check_plan_landing.py:253` SyntaxError：`if on_disk:` 的分支体在合并中被吞（donor `606dd33` 侧有完整 `findings.append(... "on-disk" ...)` + `find_moved`/moved 块）⇒ 整个脚本无法解析，ecc 自检宇宙把它 SKIP → `calib:check_plan_landing.py` 报"不在宇宙里"。
- `scripts/check_mbti_sync.py`：调用 `emit_fatal` 8 处但**定义被合并丢失**（py_compile 过、运行必 NameError）⇒ ecc 自检 `fixed-ruler-gives-two-in-impl-face` 点名"实现面给不出 2"。
- 两份的 donor 侧均为严格超集（plan_landing 含 P5 搬家态/P6 棘轮/--gate 口径/emit_fatal/fatal_reason 纯函数与 44 格自检；mbti_sync 仅多 emit_fatal 定义 + 自检摘要行，master 侧零独有内容）；`scripts/` 其余 10 份与 donor 有差异的文件逐一核对方向，master 侧更新、不动。
- 普查闭环：全 `scripts/*.py` py_compile 扫描仅 plan_landing 语法坏；`emit_fatal` 调用无定义扫描仅 mbti_sync。

**修复**
- 整采 `606dd33` 的 `scripts/check_plan_landing.py` 与 `scripts/check_mbti_sync.py`（`git checkout 606dd33 --`，无手改）。
- `scripts/run_guards.py` 一行同步：plan_landing 诊断格的 why 文案 25→36 条（该尺复活后真读数变了，按"数字变了就现形"定律同步文字；`expected()` 只对 rc，rc=1 期望本就命中）。

**验证（金条八，实跑读数）**
- `check_exit_code_contract --selftest` = **SELFTEST OK 28 格，rc 2→0**（本单目标达成）。
- `check_plan_landing --selftest` = 44 格 rc=0；`check_mbti_sync --selftest` = 17 格 rc=0（含"判据空转的退出码真是 2"两格）。
- 三尺正常模式：ecc rc=0（判定面归零）；mbti_sync rc=0 PASS（650 条 pub 声明）；plan_landing 诊断 rc=1（合法——诊断口径判定面非空即 1）。
- `run_guards.py` 电池：34 格 / 失败 5 / SKIP 3——**较修前净改善 2 格**（plan_landing 两格由 SyntaxError 崩改为有读数）；剩余 5 失败全为基点预存（见遗留风险）。
- 本单零 `.mbt/.mbti` 改动 ⇒ moon test/check 面不受影响（基点 1348/1348）。

## 资源消耗

- 本机单会话：取证 diff 数轮 + 电池 1 发 + 自检 3 尺；无外部消耗；证据落 `temp/r72_*.{log,py}`。

## 任务分配记录

- 指挥官（本会话）亲自：根因取证（donor 超集判定 + 全 scripts 普查）、整采裁定、电池逐格归因、终审。
- 无子代理分配（scripts 单文件族，轻任务直办）。

## 遗留风险（基点预存，如实点名、不代修）

1. **电池 5 红全为基点预存**：① `check_scripts_index` 点名 `scripts/slave-branch-merge.ps1`（master 独有件未入索引/未声明）；② `check_ps_encoding` rc=1（某 .ps1 非 ASCII 无 BOM，BUG-88 族）；③④ `check_py_stdout_encoding --selftest/--all` **期望滞后**——基点实际全绿（37/37、85/85 带闸）而电池仍钉旧红期望 2/1（其自述"修好后期望值要改回 0"未执行）；⑤ `check_test_sync` 点名 `docs/agent-map.md` 停在 1302 而实测 1348（与 R71 报告同一条 staleness）。
2. **plan_landing 门禁口径棘轮超限**：判定面 36 > 上限 25（`VERDICT_GAP_CEILING=25` 是 donor 血统标定）。修前该尺 SyntaxError 连读数都出不来；现在是诚实红。按"放宽上限是人的决定"不代调——需指挥官裁决：清存量落点或重标上限。
3. **`check_bug_reference_integrity` 判定面 11 条 > 上限 1**（raw master 基线，本单零触碰；R71 分支上剥新码引用后为 9）。
4. 本机 `moon fmt` rc=127（BUG-329 族）不变；本单无 `.mbt` 改动，不涉及。

## 后续建议

1. py_stdout_encoding 两格期望按其自述改回 0（独立小单，与 ps_encoding/scripts_index 红可并成"电池期望面同步"一单）。
2. plan_landing 棘轮 36>25 需指挥官裁决后处理（清存量优先于调上限）。
3. agent-map 1302→1348 与 R71 的 1351 同族，master 合并时以实测数为准。

## 超额内容

- `run_guards.py` why 文案一行同步（25→36）：修复的直接后果（尺复活→真读数现形），属收尾必需。
- 未动其余任何基点红、未调任何上限常量。

## 来源

- 单据：R71 报告后续建议③；goal objective（副机自驱、每单提 PR）。
- 证据：`temp/r72_ecc.log`（判定面归零）、`temp/r72_pl*.log`、`temp/r72_ms.log`、`temp/r72_battery.log`（34/5/3 逐格）、`temp/r72_bugref.log`（11 条基线）、`temp/donor_plan_landing.py` / `temp/master_plan_landing.py`（取证对照）。
