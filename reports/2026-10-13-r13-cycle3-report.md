# R13 第 3 环报告 · 修 BUG-153（issue_scan 除法守卫同一行识别）

- 日期：2026-10-13
- 命名空间：`r13-pipeline`（根任务 `T0`，`task_plan_deep` 开关全开）
- 模式：bugfind + fix（第 2 环发现 → 第 3 环修复）
- 状态：**第 3 环闭环，BUG-153 FIXED，BUG-152 仍 OPEN**

---

## 结果摘要

第 3 环把第 2 环翻案后的真根因落成**可运行修复**：给 `src/server/issue_scan.mbt` 的 `scan_finding_guarded` 的 `unprotected-division` 分支补上**同一行 code 守卫识别**，使规则 hint（L129）承诺的 `if total > 0 { … } else { 兜底 }` 形态真正被实现。

**核心实证（我独立复跑，非子代理自述）**：

| 判据 | 结果 | 说明 |
|---|---|---|
| `moon check` | 0 errors | 38 tasks，1859 warnings 为仓库既有 |
| `moon test --target js src/server` | **210/210/0** | 首次报一次 `Error [4021]` 是 moon 增量编译缓存瞬时误报，重跑 0 Error |
| 全量 `moon test --target js` | **814/814/0** | 基线 811，+3 新增测试，RC=0 |
| `issue_scan --dir src` | 55 → **52** findings | `unprotected-division` count **3 → 0**（清零） |
| 基线对账 | 55−52=**3** | 精确等于 3 条目标假阳性，**无误滤真缺陷** |

**判绿达成**（BUG-142 口径：以汇总行为准，exit 0 只是必要条件）。

---

## 根因（第 3 环精确定位，比第 2 环翻案再收窄一层）

第 2 环我写「issue_scan 不认守卫」——**第 3 环翻案**：`issue_scan.mbt` **有**守卫识别器 `scan_finding_guarded`（主扫描 L652/L836 真调用），且对 `unprotected-division` **已有**两个守卫函数：

- `scan_guard_zero`（L462）：在 prev 行找 `<= 0` / `== 0` / `< 1` / `is_empty()` / `<= 0.0` / `== 0.0`
- `scan_guard_is_empty`（L430）：找 `vn.is_empty()` / `vn.length()==0` / `vn.length()<=0`

**但它们都只扫 `prev_lines`，不扫 `code` 自身同一行**。`substring-overrun` 分支**有**同一行 code 检查（L516-534），`unprotected-division` **没有**。

3 条假阳性的守卫**全在同一行**（`let acc = if total > 0 { passed / total * 100 } else { 0.0 }`），所以前向扫 `prev_lines` 根本看不到。**缺的不是"除法守卫"，是"除法守卫的同一行那一格"**——hint 承诺了这一形态，实现漏了。

---

## 修复内容（只改 `src/server/issue_scan.mbt` 单文件）

新增 `scan_guard_div_direct(line, vn)`，只认 `vn` 字面量**紧跟**比较运算符（`>0` / `>0.0` / `>=1` / `>=1.0` / `<=0` / `<=0.0` / `<1` / `!=0` / `==0` / `==0.0`），刻意**不含 `>= 0`**（0 会通过、不是有效守卫）；`vn` 为空直接 false。

**两处接线**：
1. `code` 自身（守卫常与除法**同行**）——`if rule=="unprotected-division" && not(vn.is_empty()) && scan_guard_div_direct(code, vn) { return true }`
2. `prev_lines` 循环分支——前一行 `if total > 0 {` 直接守卫

**与已有功能互补不重复**：`safe_clamps`（L501）、`scan_guard_zero`、`scan_guard_is_empty` 都已存在且仍保留；新增函数**只**补同一行那一格。

**新增 3 条 DEBUG TESTS**：prev 行守卫→true / 同行守卫→true / **无守卫→false（反向）**。

未触碰 R125 格式化残留行（该文件 ` M` 的 diff 全为格式化，功能改动干净可审）。

---

## 资源消耗

- 1 个 `subagent`（修 BUG-152，约 6 分钟）
- 我（指挥官）：根因定位、终审逐条核查 diff、独立实跑验证（`moon check` / `src/server` / 全量 / `issue_scan` 各 1 次 + 对账）
- 实跑命令 5 次左右

---

## 任务分配记录

| 角色 | 承担 | 结果 |
|---|---|---|
| 子代理（bugfind-fix） | 实现 `scan_guard_div_direct` + 两处接线 + 3 条测试 + 实跑 | 通过终审 |
| 指挥官（我） | 根因翻案、终审、记账、沉淀 | 独立复跑验证一致 |

**过程纠错**：我起初派子代理时根因说错了（「只认 `safe_clamps`、不认直接守卫」），修正消息 `send_message` 报「active teammate not found」未达，但**子代理自己推理出了正确方案**（同一行守卫 + 反向测试）。终审时我据此**逐条核查 diff**，确认方案与已有功能互补、未重复实现。

---

## 遗留风险

1. **BUG-152（`secs-overflow` 的 Int32 假设）仍未修**——本轮修的是 `unprotected-division`，是两个不同问题；`engine_supervisor.mbt:558` 秒数算式的守卫校验仍漏 `yy`。
2. **守卫检测仍是词法启发式**，不解析作用域/控制流：`else` 分支 + 无关 `if total > 0` 可能被保守滤（本仓未触发）。
3. **`unprotected-division` 命中 3→0 是预期改进**，若 CI/文档对该规则命中数有硬断言需同步。
4. 只跑 JS 目标（按项目边界 JS 为权威门槛，BUG-133 native 崩因在依赖侧）。
5. `src/server/issue_scan.mbt` 仍为 ` M`（R125 格式化残留 + 本次功能改动叠加，功能 diff 干净）。

---

## 后续建议

- **第 4 环**：修 BUG-152（`secs-overflow` 的 Int32 假设）——给 `scan_finding_guarded` 补 `secs-overflow` 的守卫分支（对照 `possible-overflow` 的 `.to_double()`/`Double`/`f64` 守卫模板），或改规则 `why` 为「仅显式 `Int32` 溢出」。`issue_scan.mbt` mtime 昨日、可安全改。
- **第 4 环可顺带**：`engine_supervisor.mbt:551` 校验 mo/dd/hh/mi/ss 但**漏 yy**——补上界守卫可让 `secs-overflow` 在该处真阳性被识别。
- **契约/描述面**（R12 后续建议 3，BUG-214 形态）：`check_doc_surface.py` 已有 `RE_TOOL_DESC`/`tool_desc_registry()`（J9 返回契约），但**"描述引用已删除枚举值"未见实现**——第 4 环可评估补这条判据。
- **BUG-151**（file_locks/lock_violations 双后端 clear 不一致）：`store_sqlite.mbt` mtime = **2026-10-13 15:20:31（今天，活跃编辑中）** + diff +219 行，**确为他方活跃 WIP**，继续留 owner 收口。
- **`self_search` 入库接线**（R12 翻账点名 P3 未实现）：等 `src/evolve/` 占用释放（当前 ` M` 需先确认 mtime）。
- **SHIP-PLAN G7 GitCode 发布**：外部 API 卡点（token/凭证），需用户侧配置才能闭环。

---

## 超额内容（本次无超额；均为计划内）

无。本轮只改了 `src/server/issue_scan.mbt` 单文件 + 记账 + 沉淀，未新增工具、未改历史文件。

---

## 来源

- 真源代码：`src/server/issue_scan.mbt`（`scan_finding_guarded` / `scan_guard_zero` / `scan_guard_is_empty` / `scan_guard_div_direct`）
- 守卫目标代码：`src/omega/gate.mbt` L346-347、`src/omega/omega_tool.mbt` L248-249、`src/engine/engine_dag_ext.mbt` L862
- 账本：`memory/bugs.md`（BUG-153 FIXED @2026-10-13T07:59:24Z，BUG-152 OPEN）
- 日志：`memory/2026-10-13.md` 第 3 环段
- 前序报告：`reports/2026-10-13-r13-cycle1-report.md`、`reports/2026-10-13-r13-cycle2-report.md`