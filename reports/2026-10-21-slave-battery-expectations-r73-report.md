# R73 报告 · 电池滞后期望清账（slave/fix/battery-expectations-r73）

## 结果摘要

`run_guards.py` 电池四格滞后期望/预存红清账，4 文件、+8/−7 行、零 `.mbt/.mbti`：

1. **`scripts/run_guards.py`**：`check_py_stdout_encoding.py` 两格 `expected(rc=2/--selftest)`、`expected(rc=1/--all)` 翻回 `case()`——BUG-355 一族 9 份历史脚本的 stdout 闸早已补齐，电池自己的注释写着「修好后期望值要改回 0」，本单履约。
2. **`scripts/slave-branch-merge.ps1`**：补 UTF-8 BOM（原文件 887 个非 ASCII 字节且无 BOM，PS5.1 按 ANSI 读会解析期即炸——BUG-88 同族），`check_ps_encoding.py` rc=1→0。
3. **`scripts/README.md`**：补 3 条登记（`check_scripts_index.py` rc=1→0）——`check_doc_surface.py` 用 donor 606dd330 的正典条目**原文**（`git diff 606dd33 HEAD -- scripts/check_doc_surface.py` 为空，脚本逐字节相同，条目不会说谎）；`commit_bug335_lock.ps1` / `slave-branch-merge.ps1` 依头注释写简条。
4. **`docs/agent-map.md`**：测试计数 1302→1348（T0r45 的文档面同步漏了这张图；本单提交前 `check_test_sync temp/pt27.log` PASS：扫描现状面 131 份文档、20 条声明全部等于实测 1348，含本条新值）。

**电池读数**：34 格 / 失败 2 / SKIP 3（基点同尺 7 失败→2）。剩余 2 失败与 3 SKIP 全部为基点预存、他单在办，见「遗留风险」。

## 资源消耗

1 人日以内；2 轮 moon test 尝试（1 次全量 rc=1 构建崩——预存红取证用）、1 轮电池、4 把单尺。

## 任务分配记录

副机单兵完成（发现→取证→修复→验证→收尾），无子任务外派。分支 `slave/fix/battery-expectations-r73` 自 master 259b56a 切出。

## 遗留风险（预存红，点名 rc 与成因，不代修）

- **基点 259b56a 全量 `moon test --target js` rc=1，构建即崩**（`temp/r73_moontest.log`）：
  - `src/server/issue_scan.mbt:688/696/726`、`src/server/issue_scan_wbtest.mbt:68` 有**已提交的 git 冲突标记**（`<<<<<<< HEAD` / `=======` / `>>>>>>> 606dd330`）→ Error 3002 Parse error；本仓自家 `check_merge_markers.py` 的守卫面显然没盖住这两个文件，建议主机立案。
  - `src/ops/ops_test.mbt:66/67`、`src/ops/rhop_native_wbtest.mbt` 多处 Error 4021。
  - 这一整面由 **r71 分支（`slave/fix/issue-scan-min-severity-r71`）的基点修复**承担（donor 版本 + ops_test healed block + rhop 依赖补齐），本单不重复修，避免两 MR 冲突。
- **电池剩余 2 失败**（均为 r72 分支已修未合）：`check_mbti_sync.py --selftest` got=1（`emit_fatal` 未定义）、`check_plan_landing.py --selftest` got=1（SyntaxError U+3002，断行 docstring 吞 `if on_disk:` 体）。
- **3 SKIP**：`check_deprecated_text_census` / `check_deprecated_site_list` 各格缺 `temp/chk47.json` 前置件。
- `check_bug_reference_integrity` rc=1：判定面 11 条悬空 == 基线（新增 README 条目经核对零新增悬空，BUG-339/355 等号均在账）。
- `moon fmt --check` rc=127：本机 moon ICE（既知，moonfmt.exe 逐文件对照替代）；本单零 `.mbt` 改动，格式面不受影响。

## 后续建议

1. 主机优先合入 r71 / r72 两个 MR——本单的电池读数在两单合入后应到「失败 0 / SKIP 按前置件」。
2. `check_merge_markers.py` 扫描面核查：已提交冲突标记漏检两文件是 BUG-385 家族的又一形状，建议立案扩面。
3. `run_guards.py` 的 `expected(kind="known-red"/"diag")` 棘轮在本单又兑现一格（py_stdout_encoding 2 格），同类滞后期望尚有 `cleanup_artifacts` 预存红一格待裁决。

## 超额内容

无。发现 master 基点构建崩属取证副产物，按「预存红点名不代修」裁决只记录不修。

## 来源

- 基点：master 259b56a；分支：`slave/fix/battery-expectations-r73`
- 证据文件：`temp/r73_battery.log`（34/2/3）、`temp/r73_moontest.log`（rc=1 构建崩取证）、`temp/r73_bugref.log`（11==基线）、`temp/r73_scripts_index.log`
- 关联分支：`slave/fix/issue-scan-min-severity-r71`（承担基点构建红修复）、`slave/fix/ecc-selftest-r72`（承担电池剩余 2 失败修复）
- 记忆：`memory/2026-10-21.md` R73 节
