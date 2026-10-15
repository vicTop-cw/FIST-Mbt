# Goal-2 Round 44 报告：全角空白归一化（U+3000）

- **日期**：2026-10-15
- **提交**：R44 code（`src/router/router_caf_ext.mbt` `is_ws_byte` + `src/router/router_caf_ext_wbtest.mbt` `caf_norm_5`，HEAD `887ec69`）
- **状态**：§2.3 server 接线仍阻塞（`model_router_ops.mbt` 4/9）；本轮做接线前置的**中文输入边界**补锁

## 结果摘要

### docs 未实现计划穷尽（审计结论）

本轮系统扫描 `docs/*.md` 的「状态」字段 + 复核真源，结论：**除 CAF §2.3 接线（阻塞）外，docs 下无未实现计划**：

| 计划 | 结论 |
|---|---|
| `2026-10-12-...-reminder-role-plan.md` | 已实现（`supervisor_reminder_tick` 实跑 1731 reminders） |
| `2026-10-12-...-multilang-sdk-plan.md` | A 项已实现（`docs/openapi/fist.yaml` 已落盘）；B（vools）/ C（actus）在**用户独立项目** `actus\`，非本仓 |
| `2026-10-12-...-supervisor-tools-plan.md` | 7 工具全部实现（AGENTS.md 列全 8 个 `supervisor_*`） |
| `2026-10-12-...-web-dashboard-plan.md` | 并发 agent 主场（`apps/web` WIP），**不碰** |
| `2026-10-12-...-hexamind-design.md` | 六顶帽 R118 P1-b 已实现（`hat_*` 工具族） |
| `2026-10-15-...-caf-p2c-wiring-design.md` | **§2.3 接线仍阻塞**（`model_router_ops.mbt` 4/9） |

**接线前置已饱和**：R42 归一化 hash + R43 min_evidences 分界 + R36 `caf_memory_dump/load` 往返锁（`router_caf_persist_test.mbt` 4 锁）—— 三项前置契约齐备，**接线前再无前置缺口**。

### OPEN bug 与账本卫生

本轮读到 BUG-185/186/217 抬头为 OPEN，但复核 `memory/bugs.md` 发现**同 bug_id 有重复条目**（时间戳 08:44 与 08:46 不同，一 FIXED 一 OPEN）——**并发 agent 版本冲突**。R44 结束前，并发 agent 已提交 `20846a4 fix(e2e_irm): BUG-185/186`，账本卫生问题由并发方收口。**不越界改并发账本**。

### 实质产出：全角空白 U+3000 归一化（R42 明确遗留）

R42 的 `is_ws_byte` 只认 4 个 ASCII 空白字节（32/9/10/13）。**中文输入场景下全角空格 U+3000（=12288）同样起分隔作用**，未归一化会导致 `"　python　"` 与 `"python"` 产生不同 hash → 碎片化同族。

改动：
- `is_ws_byte` 追加 `b == 0x3000`（全角空格 UTF-16 code unit）
- 补锁 `caf_norm_5_全角空白归一化`：`"\u3000python\u3000"` norm 后 == `"python"`；归一化 hash 与纯 ASCII 输入 hash 一致

**实现要点**：
- MoonBit `String[i]` 返回 `UInt16` code unit → 全角空格 U+3000 是 BMP 单 code unit，`.to_int()==0x3000` 可测（不涉及代理对拆分）
- `to_lower_byte` 对 0x3000 走 else 分支（非 ASCII A-Z），`Char::from_int(12288).to_string()` 正常
- **避开的坑**：MoonBit unicode escape 语法（`\u3000` vs `\u{3000}`）不确定，锁内**直接粘贴全角空格字符**到字符串字面量，规避语法差异

### 并发观察

并发 agent 本轮连续修 BUG-221（read_dir）/ BUG-222（issue_scan）/ BUG-185/186（e2e_irm_line），`model_router_ops.mbt` 仍 4/9 WIP。**未触碰**（AGENTS.md 并发隔离）。

## 验证

- router **196/196**（R43 195 + caf_norm_5），0 failed
- 全仓 **1206/1206**（R43 1204 + 2），0 failed
- `.mbti` 无变化（`is_ws_byte` 私有，`caf_normalize_context` 签名未变，无新 pub fn）
- `moon fmt --check` 通过

## 资源消耗

`supervisor_reminder_tick` / `bug_list` / `grep is_finite` / docs 状态扫描 / `grep` 锁清单复核 /
`moon fmt` + `moon test --target js src/router` / 全仓回归 / `git commit`（path-scoped ×1）

## 任务分配记录

本轮**无任务分配**。本人在 router 域独立推进，改动只落 `src/router/` 2 文件（无并发 WIP，`.mbti` 未动证实）。

## 遗留风险

- **§2.3 server 接线仍未做**（`model_router_ops.mbt` 4/9）。接线点用归一化 hash（R42/R44）+ `>=` 分界（R43）。
- **docs 计划已穷尽**：CAF 接线完成后本仓无其他大项未实现计划；后续方向需新评估或转向 actus（用户独立项目）。
- **账本重复条目**（BUG-185/186/217）：并发 agent 已修 FIXED，但重复条目（时间戳不同）可能残留；建议并发收口后统一清理。
- **并发 WIP 持续**：`model_router_ops.mbt` 4/9 仍是 CAF 接线唯一阻塞。

## 后续建议

1. **R45 首选**：§2.3 接线（`model_router_ops.mbt` 释放后），接线点用归一化 hash + `>=` 分界 + 全角空白（三契约齐备）。
2. **R45 备选**：若接线继续阻塞，转向 **actus 动作层契约草案**（§6.2 `#!config` DSL 定义，可先在 FIST-Mbt 仓内出 `docs/openapi/` 扩展的 actus 动作 schema，供用户独立项目照抄）。
3. **R45 备选 2**：账本卫生审计（重复条目清理）—— 待并发收口后统一。
4. **持续观察**：并发 agent 修 bug 节奏快，R1 引导复核必 grep 真源再行动。

## 来源

- docs 状态扫描：`docs/*.md` 各计划「状态」字段
- 真源：`src/router/router_caf_ext.mbt` L109-111 `is_ws_byte`（R44 追加 `b == 0x3000`）
- 新增锁：`src/router/router_caf_ext_wbtest.mbt` `caf_norm_5_全角空白归一化`
- 设计文档：`docs/2026-10-15-fist-mbt-caf-p2c-wiring-design.md` §2.3
- 审计：`supervisor_reminder_tick` / `bug_list` / `memory/bugs.md` 复核
