# marvis-combo-sweep-20261016 · 推进汇总

> 由 marvis-lead 生成 · 2026-10-16T16:00+08:00
> 作用域：`lang-zone` 全项目 · 组合模式 [打磨,寻虫,修复,验证,清整,推进]

## 组合模式各阶段产物

| 阶段 | 任务 | 状态 | 关键产物 |
|------|------|------|----------|
| 打磨 polish | T0r629 | 已完成 | REST 通道修复 BUG-120（FIST_HTTP_WAIT_SEC 可配置默认 600s）+ moon test src/engine 162/162 绿 |
| 寻虫 bugfind | T0r630 | 已完成 | BUG-252 登记 + issue_scan 全仓扫描报告 + reports/2026-10-16-marvis-combo-sweep-report.md |
| 清整 tidy | T0r631 | 已完成 | atomcode exit 0，隔离分支执行，未提交避免污染 |
| 修复 fix_and_merge | T0r633 | 已完成 | BUG-253 dag_mc 负 deadline 修复（commit ee219a0）+ BUG-252/120 标 FIXED + 全量 1260/1260 绿 |
| 验证 verify | T0r634 | 已完成 | API 枚举核对（166 工具）+ output_validate 4/4 l4-pass + 文档自洽 |
| 推进 advance | T0r635 | 进行中 | 本报告 + 项目健康度评估 |

## Bug 账本变更（本轮）

- **BUG-253** [OPEN→FIXED] dag_mc 负 deadline 缺守卫：p_on_time 恒 0 伪装成"0% 按期"。修复：commit ee219a0（src/engine/engine_dag_mc.mbt），负 deadline 钳到 0 + deadline_requested/deadline_capped/deadline_cap_note 回显。
- **BUG-252** [OPEN→FIXED] BUG-120 HTTP 桥超时：scripts/fist-mbt-http.py FIST_HTTP_WAIT_SEC 可配置（默认 600s）。
- **BUG-120** [OPEN→FIXED] HTTP 桥 30s 硬超时→600s 可配置。
- **BUG-250/251** [OPEN→FALSE_POSITIVE] 测试探针条目，非真实缺陷。
- **BUG-217 次条** 待 MCP server 重启加载新 bundle 后由 bug_fix 正常闭合（BUG-241 修复 f1e36a3 已入库但未在现网生效）。

## 项目健康度

- **fist-allmodes**：`healthy`，123 任务，46 完成，40 在流，35 就绪，0 阻塞，done_no_artifact=0。LADDER 梯度链全部完成。
- **marvis-drive**：`healthy`，13 任务，5 完成，2 在流（T0r628 组合主任务、T0r631 清整），6 就绪，0 阻塞。
- **全局**：`attention`（1105 阻塞任务全在旧轮次 namespace，非本轮范围）。

## 已知部署问题（非代码缺陷）

MCP server（PID 2728）仍运行 `_build/js/debug/build/cmd/cli/cli.js serve`（旧 debug bundle），而非部署到 `C:\Users\victo\AppData\Local\FIST-Mbt\fist-mbt.js` 的发布版。后果：
- BUG-241 修复（bug_header_lines 返回 ALL 索引）未生效，BUG-217/185/186 次条仍无法被 bug_fix 正常闭合。
- 需 DSH/MCP 重启加载新 bundle 后，上述次条可被立即修正。

## 下一步建议

1. 重启 DSH/MCP server 加载新 bundle（fist-mbt.js, 3,599,030 bytes）。
2. 重启后调用 bug_fix(["BUG-185","BUG-186","BUG-217"]) 闭合次条。
3. 继续下一轮组合开发（explore 模式：针对全局 blocked 1105 条旧任务做批量 heal/归档清扫）。