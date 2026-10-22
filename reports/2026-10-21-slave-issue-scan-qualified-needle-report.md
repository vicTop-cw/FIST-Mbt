# 副机报告 · issue_scan 外部规则命名空间被丢弃（T0r38 / BUG-347）

- 日期：2026-10-21
- 分支：`slave/fix/issue-scan-qualified-needle`（基点 `f8be50b`，强制 `slave/` 前缀）
- 任务：T0r38
- 台账：BUG-347（FIXED）
- 交付面：2 文件 +60/−7 行（`src/server/issue_scan.mbt`、`src/server/issue_scan_external_rules_wbtest.mbt`）

## 结果摘要

1. **外部 rules_file 的 `::` 命名空间不再被丢弃**：`scan_regex_to_needle` 只取最长纯字母数字段，`Json::string(` 被降级成 `string`，导致 json-injection 规则命中全库 `to_string(` / `formula_to_string(`。现 `ident::ident` 并入同一段，needle 得 `Json::string`。
2. **三探针实测与台账同形**：`pattern=Json::string(` 扫 `src/ltl` 由 **11 → 0**；`pattern=Foo::string(` **11 → 0**；正控 `src/store` 仍 **45**，与内建规则计数逐字一致。
3. **警告面零变化**：`moon check` = **504 warnings / 0 errors**，八族分布与改前逐格相同。
4. **测试全绿**：`moon test --target js` = **1342/1342/0**（基线 1340 + 新增 2 条）。
5. 台账 `bug_fix` 同一笔改抬头 + 落 FIXED 小记；工具写出的裸 LF 与块间粘连已手工归一为 CRLF。

## 证据表

| 探针 | 命令/参数 | 改前 | 改后 |
|---|---|---|---|
| A 命名空间（真规则） | `issue_scan --dir src/ltl --rules-file temp/probe_rules_json.json`（pattern `Json::string(`） | 11 命中（全为 `*_to_string(` 行） | **0** |
| B 命名空间（无关前缀） | `issue_scan --dir src/ltl --rules-file temp/probe_rules_foo.json`（pattern `Foo::string(`） | 11 命中，行号与 A 逐字相同 | **0** |
| C 正控（真命中） | `issue_scan --dir src/store --rules-file temp/probe_rules_json.json` | 45 | **45**（与内建规则计数一致） |
| D needle 级 | `scan_regex_to_needle("Json::string(")` | `string` | `Json::string` |
| E 匹配级 | `ext_rules_8`：`Json::string(x)` / `formula_to_string(f)` / `j.to_string()` 三行 | 3 行全中 | 只中第 1 行 |

| 判据 | 命令 | 读数 |
|---|---|---|
| 静态检查 | `moon check` | 504 warnings / 0 errors（八族：0020 471、0006 12、0002 11、0009 3、0078 2、0023 2、0001 2、0027 1） |
| 全量测试 | `moon test --target js` | `Total tests: 1342, passed: 1342, failed: 0` |
| 目标包 | `moon test --target js src/server` | `342/342/0`（含新增 ext_rules_7、ext_rules_8） |
| 格式 | `moonfmt.exe`（两文件临时副本） | 零差异，rc=0；bareLF 0 |
| 电池 | `python scripts/run_guards.py` | 38 格 / 5 红 / 5 SKIP / 0 缺执行面（与基线逐格相同） |

## 预存红表（未代修，按裁决如实标注）

| 判据 | rc | 成因 |
|---|---|---|
| `check_scripts_index.py` | 1 | `run_guards.py` 等 6 个脚本未登记进 `scripts/README.md` 索引 |
| `check_exit_code_contract.py --selftest` | 2 | 判据自检不通过（尺子自身红） |
| `check_plugin_sync.py` | 1 | 插件态与生成器投影不一致 |
| `gen_plugins.py --check` | 2 | 账本编号重复：BUG-183/192/328/329/330 各 ×2（历史存量） |
| `check_plan_landing.py --gate` | 1 | 判定面存量超上限（按 `--gate` 口径） |

## 分析

- **根因与台账描述的差异**：台账写「按 `::` 切分只取尾段」，实现实为「收集连续字母数字片段后取最长者」。两者对外表现一致（命名空间被丢），但修法必须落在片段收集规则上，而不是删一个 `split("::")`。`Json`(4) 短于 `string`(6)，所以尾段胜出；若命名空间更长（如 `VeryLongNamespace::x`），旧实现会保留命名空间段、反而丢弃方法名——同一缺陷的另一种假阴性形态。
- **为什么只改片段收集、不改内建规则**：内建 `moonbit-json-injection` 用字面量 `Json::string(` 直接 `contains`，不经过 `scan_regex_to_needle`，本次修复对它零影响；正控 `src/store=45` 与内建计数一致证明了这一点。
- **内建规则的语义问题仍独立存在**：BUG-346（把安全构造器 `Json::string(` 当注入）需要 owner 裁决规则意图（检测拼接 vs 检测构造器），不属于本次「外部 pattern 解析」的修复范围，保持 OPEN。
- **边界处理**：`Json::(string)`（右侧是分组而非标识符）不并入，回落到 `string`——这是子串近似器在 regex 交替式上的固有取舍，已用断言固化，避免后续把 `::` 无条件当名字一部分。

## 资源消耗

- 轮次：R56（副机自我迭代第 38 单，T0r38）
- 工具调用：publish/claim 各 1、bug_fix 1（含 2 次入参被拒后的第 3 次成功）、issue_scan 3 次探针、moon check 2 次、moon test 2 次（目标包 + 全量）、电池 1 次、moonfmt 1 次
- 工作树：2 代码文件 + 台账 + 当日记忆 + 本报告；`.mbti` 全部 restore，未入提交

## 任务分配记录

- 本单由副机自行发布并执行（主机本轮无待领取任务）：`publish`（human_steward / level 3 / default ns）→ `claim`（slave-agent）→ 执行 → `execute` → `submit` → `verify`（commander）。
- 无子代理派发：改动集中在一个私有辅助函数与其白盒测试，不满足拆分条件。

## 遗留风险

1. **BUG-346 仍在**：内建 json-injection 规则对 `Json::string(` 的语义判断未动，`src/store` 仍会报 45 条（本次反而用这 45 条做正控）。
2. **子串近似器的其他损失**：`@fs\.(open|write|read)\s*\(` 仍只取最长段 `write`，`open(`/`read(` 命中不到；属 BUG-348（low/info 精度）同族，未在本单扩大范围。
3. **`bug_fix` 工具的行尾/空行缺陷**：Windows 下落盘用裸 LF 且不留块间空行，需要调用方事后归一；已记入 R56 记忆，建议后续给工具补 CRLF 落盘与块间空行。
4. **预存 5 红未代修**：按裁决只标注 rc 与成因，不在本单处理。

## 后续建议

1. 修 `bug_fix` 的落盘行尾（Windows CRLF）与小记后补空行，把「写后自查 bareLF」从纪律变成工具保证。
2. BUG-346 由 owner 裁决：改规则意图（检测字符串拼接注入）或降级/删除该规则；裁决前不建议继续以 `Json::string(` 字面量判注入。
3. `scan_regex_to_needle` 可进一步支持 `(open|write|read)` 交替式展开为多条 needle，但会改变外部规则命中面，应先出方案。

## 超额内容

- 台账描述的根因不精确（「按 `::` 切分取尾段」→ 实为「最长片段胜出」），已在 R56 记忆与台账 evidence 中更正，并补充了「命名空间更长时反而丢方法名」的假阴性形态。
- 发现并归一了 `bug_fix` 的 5 处裸 LF 与块间粘连带（台账 CRLF 一致性）。
- 正控使用内建规则的同目录计数（45）作为「真命中未误杀」的对照，避免只报负向探针造成假绿。

## 来源

- 台账：`memory/bugs.md` BUG-347 条目 + `### FIXED(2026-10-21T07:04:56Z / BUG-347)`
- 当日记忆：`memory/2026-10-21.md` R56 段
- 证据日志：`temp/t38b_check_full.log`、`temp/t38b_test_full.log`、`temp/t38b_battery.log`、`temp/t39_check_full.log`（改前基线）
- 探针规则：`temp/probe_rules_json.json`、`temp/probe_rules_foo.json`（未被跟踪）
- 代码：`src/server/issue_scan.mbt`（`scan_regex_to_needle` / `scan_is_alnum_char`）、`src/server/issue_scan_external_rules_wbtest.mbt`（ext_rules_7/8）
