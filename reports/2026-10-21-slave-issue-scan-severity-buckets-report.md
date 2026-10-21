# 副机任务报告 · T0r39 / BUG-345 —— issue_scan by_severity 四桶（info 独立成桶）

- 日期：2026-10-21
- 分支：`slave/fix/issue-scan-severity-buckets`（基点 1104bb0，T0r38 之上）
- 任务：FIST T0r39（publish → claim → execute → submit → verify 全程走 fist-mbt 自身）
- 账本：BUG-345 → FIXED（`### FIXED(2026-10-21T07:18:52Z / BUG-345)`）

## 1. 结果摘要

`issue_scan` 的 `by_severity` 聚合从三桶改为四桶：新增 `info` 键，`info` 不再被 `else → low` 兜底并入 `low`；未知档位归 `info` 而非 `low`。旧调用方读 `high/medium/low` 不受影响，`total_findings` 与 `by_rule` 口径不变——纯增量、零破坏。

BUG-333 降噪预案（把子串近似噪音规则经 rules_file 降为 `info`）从此可真正净化 `by_severity`：修前 A/B 两跑 `low` 一字不变，修后实测 `low 1→0`、`info 1→3`。

## 2. 证据表（真产物 MCP `issue_scan`，同目录同文件 A/B）

| 读数 | A：默认 rules | B：rules_file 降级 | 断言 |
|---|---|---|---|
| `by_severity` | `{high:0, medium:0, low:1, info:1}` | `{high:0, medium:0, low:0, info:3}` | low 严格下降、info 增加 |
| `by_rule` | race-condition=low、long-function=info | race-condition=info、long-function=info、probe-info-rule=info | 覆盖生效 |
| 四桶之和 | 2 | 3 | == `total_findings` |

代码面：

| 文件 | 改动 |
|---|---|
| `src/server/issue_scan.mbt` | 新增私有 `scan_severity_bucket`（四桶纯函数）；聚合改四桶计数；`by_severity` 增 `info` 键 |
| `src/server/issue_scan_wbtest.mbt` | 四桶穷举锁（high/medium/low/info/critical/空串） |
| `src/server/issue_scan_test.mbt` | A/B 集成锁（同名覆盖降级：low 1→0、info 1→3、四桶和==total） |

## 3. 判据与门禁

| 门 | 读数 | 结论 |
|---|---|---|
| `moon check --target js` | 504 warnings / 0 errors，八族分布与基线逐格相同 | 通过（未新增 warning；首版 helper 的 `j.value` 多出 1 条 0020，改 match 取值后归零） |
| `moon test --target js` | `Total tests: 1344, passed: 1344, failed: 0` | 通过（基线 1342 + 新增 2） |
| `moonfmt.exe` 三文件临时副本 diff | 零差异 | 通过 |
| 行尾 | 三文件 bareLF = 0 | 通过 |
| 守卫电池 `scripts/run_guards.py` | 38 格 / 失败 5 / SKIP 5 / 缺执行面的尺 0 | 与基线逐格一致 |

### 预存红（不代修，按裁决如实标注）

| 格 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | 索引未收录 `run_guards.py`（预存） |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检不通过（预存，尺子自身） |
| `check_plugin_sync.py` | 1 | 需先 `gen_plugins.py` 重生成（预存） |
| `gen_plugins.py --check` | 2 | 账本编号重复 BUG-183/192/328/329/330 各 ×2（预存） |
| `check_plan_landing.py --gate` | 1 | 判定面超上限（预存，BUG-367 ④ 口径） |

## 4. 分析

- 根因：聚合块用 `if high / else if medium / else low`，`info`（及任何未知档）落入 `else`。`by_rule` 读规则表 severity 显示 `info`，`by_severity` 读命中 severity 却无 `info` 桶 ⇒ 同参撕裂，降噪只改标签不改桶。
- 修法：抽出可白盒测的纯函数 `scan_severity_bucket`，未知档显式归 `info`；输出层新增 `info` 键。四桶互斥且和恒等于 `total_findings`，测试直接钉住守恒。
- 零破坏：`by_severity` 只增键不改旧键语义；扫描规则集、匹配器、`by_rule`、`findings` 未动。

## 5. 资源消耗

- 模型调用：本单会话约 20 次工具往返（读码 4、编辑 3、测试 4、格式 1、电池 1、账本 1、记忆/报告 2）。
- 机器时间：全量测试约 30s，`moon check` 约 40s，电池约 90s。
- 代码量：3 文件 +90/−13（含测试）。

## 6. 任务分配记录

| 时刻（UTC） | 动作 | 结果 |
|---|---|---|
| 07:07:40 | `publish` T0r39 | 根任务创建 |
| 07:07:45 | `claim` T0r39 → slave-agent | 已领取 |
| 07:08–07:10 | 修复 + 单包测试 + check + A/B 探针 + 全量测试 | 全绿 |
| 07:18:52 | `bug_fix` BUG-345 | heading_changed=1, note_written=true |
| 待回填 | `execute` / `submit` / `verify` | 见 T0r39 终态 |

## 7. 遗留风险

1. 未知 severity（如外部规则写 `error`）现在归 `info`。若下游把 `info` 当“可忽略”，语义上比旧行为（落 `low`）更靠后；本仓规则表实际取值只有 high/medium/low/info，暂无实例。
2. BUG-333 的默认降级与常驻 A/B 守卫脚本（①③）未做——涉及默认行为变更与 scripts 面，待 owner 裁决。
3. BUG-346（`moonbit-json-injection` 把安全构造器当注入）与 BUG-348（low/info 规则精度）仍是规则语义问题，本单未动。

## 8. 后续建议

1. 修 BUG-346：按 owner 裁决把内建 json-injection 规则改成真正的拼接注入形状，或纳入默认降噪集并同步白盒锁。
2. BUG-333 ③：加常驻 A/B 判据脚本（固定目录 + `memory/bug333_denoise_rules.json`，断言 `info` 键存在且 `low` 严格下降）。
3. 文档面：`docs/issue-scan-skill.md` 可在下次文档批次补一句 `by_severity` 四桶说明（本单未改文档，避免与并发文档 WIP 冲突）。

## 9. 超额内容

- 无新增范围。测试覆盖取“纯函数穷举 + 端到端 A/B”两层，未额外改扫描规则或输出结构。

## 10. 来源

- 台账：`memory/bugs.md` BUG-345（含 R12 实测与 R14 蓝本）。
- 蓝本：`reports/2026-10-20-r14-bug345-fix-blueprint.md`。
- 日志：`temp/t39_check_full.log`、`temp/t39_test_full.log`、`temp/t39_battery.log`（本机未入库）。
- 代码：`src/server/issue_scan.mbt`、`src/server/issue_scan_wbtest.mbt`、`src/server/issue_scan_test.mbt`。
