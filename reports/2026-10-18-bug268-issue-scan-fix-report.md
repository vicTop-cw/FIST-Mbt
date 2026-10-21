# BUG-268 修复 · issue_scan substring-overrun 假阳性清除

- 日期：2026-10-18
- 轮次：工具链死锁恢复后「解决已知问题 + 查看项目状态」续作
- HEAD 基线：`c7136d3` → 终态 `c768561`

## 结果摘要

| 项 | 结果 |
|---|---|
| BUG-268（issue_scan substring-overrun 3/3 假阳性） | ✅ 已修，`bug_fix` 标 FIXED |
| 项目健康度 | `attention` → **`healthy`**（blocked 1→0） |
| 僵尸阻塞 `T0r583.1.3` | ✅ 归档（`archive(force)`，可 `reopen_task` 逆回） |
| 同步门禁 | tools / doc_surface / plugin / mbti / desc_enum **全部 PASS** |
| 提交门禁 | `moon test --target js src/server` = **326/326**；`moon fmt --check` rc=0 |

## 修复内容

在 `src/server/issue_scan.mbt` 新增三类守卫检测（`scan_substring_guard` 链路）：

1. **`scan_guard_multi_line_length`**（多行 if-else 长度守卫）——治 `memory.mbt:165-166`（memory_gc_logic 的 `if n <= max_chars { return } else { substring(n-cut, n) }`）
2. **`scan_guard_mod_invariant`**（模运算区间不变量）——治 `mcp_config_scaffold.mbt:138`（`d = rem % 16` → 0≤d<16，恒为合法下标）
3. **`scan_guard_find_endvar`**（`find()` 结果变量上限）——治 `ops_ops_selfdrive.mbt:587`（`end = find("]")` + `if end > 3` 间接长度约束）

配套辅助：`scan_nospace`（绕开钉版 moon `String::replace` 的 4014/4080/4086 编译错）、`scan_substring_arg_expr`、`scan_parse_int_opt`、`scan_cut_bounded`。所有新守卫为**保守拒绝**（任一步不满足即返回 false，判定留给下游），不吞真越界。

## 资源消耗

- 子代理 1 个（`bcea620e-09a0-4a73-b169-7026e9e3a2af`）
- diff：`src/server/issue_scan.mbt` +449 行（含 `///|` 块注释）、`src/server/issue_scan_test.mbt` +168 行，**纯增量 0 删除**
- 提交 2 个：`15fe403`（代码修复）、`c768561`（bugs.md FIXED + 插件态重投影）

## 任务分配记录

| 分配 | 内容 | 状态 |
|---|---|---|
| 子代理 bcea620e | BUG-268 issue_scan 守卫扩展 + 白盒测试 | ✅ 完成，我终审通过 |
| 僵尸叶 T0r583.1.3 | `archive(force=true)` 归档 | ✅ 完成 |

## 遗留风险

1. **MCP 工具 `issue_scan` 外部读数仍为 medium=6**：运行中的 MCP server 二进制是修复前编译的。已用进程内 `lint_15` 在**新编译代码**上确认 FP 消除（src/server / src/ops 均无 medium substring-overrun）。外部读数需重启/重编译 server 才反映修复，**不要拿 MCP 的 medium=6 当「没修好」的证据**。
2. **Windows LF/CRLF 幻影**：全仓 `moon fmt` / `moon test` 会在 Windows autocrlf 下批量生成幻影 `M`（`git diff --name-only` 为空）。本次子代理全仓 fmt 触发 84 个、我跑 test 触发 27 个，均已 `git checkout` 清理。真改动判据是 `git diff --name-only`，不是 `git status --porcelain`。
3. **并发修复 agent WIP**：`scripts/blackbox/e2e_irm_line.py` 全程未触碰、未 stage，仍留脏。
4. **测试文件自伤已复检**：子代理曾误删列首 `}`，按「`///|` 块分隔 + EOF」重建 22 个顶层项收尾；`moon test` 326/326 通过证明结构无误（错位 `}` 会直接 parse error）。
5. **外部 OPEN 未修**：11 条外部项目（Pentad/Tnr/codegen，源码不在本仓）+ 3 条重编号元数据（BUG-261/262/263），非本仓可修。

## 后续建议

1. 合并 agent 收口后重跑一次**全仓** `moon test --target js`，确认 1058/1058 基线无回归，然后恢复 `check_test_sync` 的真总数校验。
2. MCP server 重启后复验外部 `issue_scan` 读数（预期 medium 从 6 降到 0 或更少）。
3. Slice B（CAF 写回 + `caf_dr_6`）待全仓 `moon test` 绿后再派。
4. 11 条外部 OPEN 如需修，另起对应项目（Pentad / Tnr / codegen）的 FIST 命名空间认领。
5. 守卫形态可沉淀为 `docs/` issue_scan 守卫语义笔记，或 `evolve_lesson` 归档为 `[lesson]issue_scan-guard`。

## 超额内容

- 顺手清理了我此前遗留的临时文件 `memory/_openbugs.json`、`memory/_bug268.json`（未跟踪，已删）。
- 清掉 27+84 个 LF/CRLF 幻影 dirty，恢复干净工作树。

## 来源

- BUG-268 账本：`memory/bugs.md`
- 守卫真源：`src/server/issue_scan.mbt`
- 白盒测试：`src/server/issue_scan_test.mbt`（lint_11~15）
- 验证：`moon test --target js src/server`（326/326）、`moon fmt --check`、5 项同步门禁脚本
- 提交：`15fe403`、`c768561`