# R71 `slave/fix/issue-scan-min-severity-r71` — issue_scan 严重度下限（min_severity）+ 同步基点编译红修复

- 分支：`slave/fix/issue-scan-min-severity-r71`（基点 gitcode master `259b56a`，一单一分支）。
- 单据来源：主机（副机objective）自驱单——给 `issue_scan` 加 `min_severity` 噪音闸；顺带修复同步基点上的编译红。

## 结果摘要

**基点修复（master 259b56a 的 issue_scan.mbt 是结构性坏合并）**
- master `259b56a` 的 `src/server/issue_scan.mbt` 缺 12 个辅助函数定义、缺 info 档聚合、缺 suppressed 谓词链、残留旧版 `substring()` 写法 ⇒ `moon check` 35 errors。逐点证实：`259b56a` 与独立血统提交 `606dd33` 的去标记 diff 里，master 侧**零功能新增** ⇒ 整体采用 `606dd33` 版四个 issue_scan 文件（`issue_scan.mbt` / `issue_scan_test.mbt` / `issue_scan_wbtest.mbt` / `issue_scan_external_rules_wbtest.mbt`）。
- 同族掉行损伤两处外科复原：`src/ops/ops_test.mbt`（`healed` 未绑定——heal 块 + conflicts-claim 3 行）、`src/server/output_validate_test.mbt`（`r1/r2/r3` 未绑定——3 个 output_validate 调用）；`src/ops/rhop_poll.mbt` 从 606dd33 还原 + `src/ops/moon.pkg` 补 `"moonbitlang/core/ref"`。

**min_severity 特性（真源 `src/server/issue_scan.mbt`）**
- `issue_scan(dir, rules_file, max_findings, include_tests~ , min_severity~ : String = "")`：空串=不过滤（-1，零回归）；`high|medium|low|info`→档位（rank 3/2/1/0，未知档按 0）；**非法值显式 Err，不静默回落**。
- 过滤位置：结构降噪（guarded_filtered）**之后**、max_findings 截断**之前**；JSON 返回新增 `min_severity`（归一化回显）与 `filtered_out` 计数。
- MCP 面：`server.mbt` 的描述/schema/参数表三处同步；`scripts/issue_scan.py` 加 `--min-severity`（缺值 rc=2）；`docs/issue-scan-skill.md` MCP/CLI 双示例同步。
- 注释面账本对齐：剥离 15 处 `BUG-333/384/385` 引用（账本止于 BUG-373，J1 规则——引用必须有对应 `## BUG-n` 抬头）。

**验证（金条八，实跑读数）**
- `moon test --target js` = **Total tests: 1351, passed: 1351, failed: 0**（基线 1348 + 新增 3：end-to-end 1 + wbtest 2）。
- `moon check` = 0 errors / 497 warnings，逐条核对**零条**归因于本单新增代码（新增测试含 `Int`→`Int32` 已知世代漂移按 HEAD 形态保留）。
- `moonfmt` 非漂移分歧 0；`check_mbti_sync` PASS（650 条 pub 声明）；`check_test_sync` PASS（1351）；`check_tools_sync` / `check_doc_surface`（含 --selftest）/ `check_badge` / `check_merge_markers` / `check_plugin_sync`（4 宿主 / 170 工具）全 PASS。

**CLI A/B（重建 `moon build --target js cmd/cli`，产物 `_build/js/debug/build/cmd/cli/cli.js`，真跑 `scripts/issue_scan.py src`，132 文件基线 total=961）**
| 变体 | rc | total | filtered_out | 结论 |
|---|---|---|---|---|
| 默认 | 0 | 961 | 0 | 零回归；`min_severity:""` 回显 |
| `--min-severity high` | 0 | 0 | 961 | 只剩高危（本仓 0 条 high），四桶全归零 |
| `--min-severity medium` | 0 | 1 | 960 | 唯一 medium（secs-overflow）保留 |
| `--min-severity info` | 0 | 961 | 0 | == 基线全等 |
| `--min-severity severe` | 1 | — | — | 显式报错：`非法 min_severity（只接受 high\|medium\|low\|info，空串=不过滤）: severe` |
| `--min-severity`（缺值） | 2 | — | — | `FAIL --min-severity 缺值（只接受 high\|medium\|low\|info）` |
| `--bogus-flag` | 2 | — | — | `未知参数`（帮助文已含 `--min-severity`） |

## 资源消耗

- 本机（副机）单会话：moon check/test/build 若干轮 + 8 支守卫 + 7 支 CLI A/B；无外部 LLM/API 消耗；全部证据落 `temp/r71_*.{log,json,txt}` 与 `temp/r71_606_vs_master.diff`。

## 任务分配记录

- 指挥官（本会话）亲自：基点取证（donor diff）、方案裁定（整采 606dd33 + 5 处插入）、终审全部读数、注释面账本对齐逐处过目。
- 无子代理/外部执行器分配（单文件族任务，轻任务直办）。

## 遗留风险（预存红，按裁决如实点名、不代修）

1. **`check_bug_reference_integrity.py` rc≠0（9 条 J1 悬空）**：基点（master 259b56a）预存，例：`src/server/server.mbt` 注释引用 BUG-327 而账本无该抬头。本单剥离自己的 15 处后维持基线 9 条不增不减。成因：账本止于 BUG-373 而代码面有更早散落引用。
2. **`check_exit_code_contract.py --selftest` rc=2**：基点预存。成因：其 `--selftest` 期望的"2"实现面在 `check_plan_landing.py` 与 `check_mbti_sync.py` 里缺失（该两尺的 FATAL 路径未按判据面报 2）。本单未触碰这两个脚本（`git status scripts/` 仅 `issue_scan.py` + `scoring_rubric.md`）。
3. **`moon fmt` 本机 rc=127（`\?\` ICE，BUG-329 同族）**：以 moonfmt.exe 逐文件对照替代，非漂移分歧 0；并发 WIP 收口后需 nightly 全仓重排。
4. **`.mbti` 世代漂移反复**：`moon check/test` 会把 26 份 `.mbti` 刷成 Int32 形态，已 `git restore` 并仅手改 `src/server/pkg.generated.mbti:102` 一行（HEAD 形态 `Int`）；收尾时确认该行在位（曾被 restore 误还原，已复补并通过 mbti_sync）。

## 后续建议

1. 主机侧考虑把 `606dd33` 血统与 master 合并缺口正式收口（本单在分支内整采，master 侧坏合并仍在）。
2. `min_severity` 后续可接入 `run_check`/bugfind 流水线的默认降噪档（如 bugfind 模式默认 `--min-severity low`）。
3. 两处基点预存红（bugref 9 条 / exit_code_contract selftest）建议立独立单据修复，勿与本类特性单混车。

## 超额内容

- 超出 min_severity 本体的部分均为**编译红修复**（同步基点不可编译 ⇒ 特性无法验证，属前置必需）：4 个 issue_scan 文件整采、ops_test/output_validate_test 掉行复原、rhop_poll 还原。未顺带修任何预存红、未动插件态、未重构守卫。

## 来源

- objective：用户常设指令（副机自驱 + 每单提 PR + 零 WARNING/ERROR 门）。
- 证据：`temp/r71_check*.log`（check 0 errors）、`temp/r71_test1.log`（1351/1351）、`temp/r71_cli_*.json|txt`（A/B 七格）、`temp/r71_606_vs_master.diff`（donor 取证）。
