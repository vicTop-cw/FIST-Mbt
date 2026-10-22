---
decision_id: DEC-2026-10-22-002
proposal: fist-mbt/plans/2026-10-22-rx-mbt-lightweight-proposal.md
decided_by: human_steward
decided_at: 2026-10-22T16:07:00+08:00
decision: approved
---
# 定案记录 DEC-2026-10-22-002

**提案**：fist-mbt 轻量化——深度复用 RX-MBT 依赖

**决策**：✅ 批准（approved，按 lead 建议）

**定案人**：human_steward（指挥官）

**定案依据**：fist-mbt 依赖 `vicTop-cw/RX-MBT` 却全仓仅 1 处使用（`ops_commissar.mbt` 的 `@rx.Observer::new`）；熔断器/限速/轮询/递归拆解均手搓，估 3000+ 行与 RX-MBT 高度重叠。深度复用可轻量化且公共 API 零回归。

**三点裁决**：
1. **顺序**：A1 限速换库 → A2 轮询改事件 → A3 递归用 Itor → B1 熔断时钟复用。
2. **熔断器保留半开态**：closed/open/half-open + `probe_limit` 探测配额（BUG-34 修过不得丢）全保留；只把底层虚拟时钟/连续失败计数换 RX-MBT `Clock`；**禁止整体替换 `engine_circuit.mbt`**。
3. **归属**：纳入 `rx-mbt-governance` 任务树作为**功能 F**，依赖功能 C（写入门禁）。轻量化必须写在写入门禁之后。

**后续动作**：
1. 以功能 F 发布到 `rx-mbt-governance` 命名空间，前置依赖 = 功能 C（T0r3 写入门禁）。
2. 内部按 A1→A2→A3→B1 四个独立 scope 拆分，每 scope 独立 commit、可单独回退。
3. 验收硬门：`moon test --target js` = 1358/1358、公共工具签名/回执字段零变化、写入门禁生效、`check_tools_sync`/`check_test_sync`/双守卫全过。
4. C 档明确不换：Saga 补偿、Phi Accrual、SQLite 持久化、门禁守卫。

**关联**：`DEC-2026-10-22-001`（双层目录治理）；`PROP-2026-10-22-001`（写入门禁为功能 C 的前置）。