# T0r2 交付报告：claimguard 接入 claim 路径（逻辑项互斥闭环）

> 任务：`T0r2`（ns `fist-plan-20261029`，P1）｜认领：`lead`｜执行：子代理 `24f28c5e`｜终审：lead
> 提交：`d41542af`（engine.mbt + moon.pkg）｜锁文件由 `d6a0bc2f3` 先行入库

## 一、结果摘要

`src/claimguard/` 从**零接线**（engine/server 引用数 = 0）变为**真正生效**：`claim` 前做逻辑项互斥，冲突 `Err` 点名现持有者；`verify`/`reject`/`pause`/`archive` 四个释放点已接；claim 自身两条失败路径回滚持有。

| 项 | 读数 |
|---|---|
| engine 全包 | `Total tests: 361, passed: 361, failed: 0` |
| 新锁 8 格 | `Total tests: 8, passed: 8, failed: 0` |
| claimguard 包 | `Total tests: 57, passed: 57, failed: 0` |
| server 回归面 | `Total tests: 553, passed: 553, failed: 0`（子代理侧） |

## 二、设计与接线（关键判断）

1. **状态挂模块级，不挂 `FistEngine` 字段**：`server.mbt:137` 的 `engine_for_ns` 对**非 default ns 每次调用新建引擎**，只有 default 复用单例 ⇒ 字段级 guard 在非 default ns **恒为空表**，恰好就是"接了等于没接"的形状。T0r2 自己就落在非 default ns。
2. **键 = `(ns, task_id)`**：任务 id 空间每库各自（`T0`/`T0r2` 在多棵树里都有），只按 id 会跨 ns 误拦。
3. **接线点在既有门之后**：军衔/能力/依赖门拒掉的请求不进 guard（不留幽灵条目）。
4. **陈旧对账**：guard 进程内、账本库内。`holder≠assignee` 但账本仍「待领取」⇒ 该持有对**这一行**不成立 ⇒ 接管（否则一条陈旧条目把任务永久锁死）；行已不在待领取 ⇒ 持有为真 ⇒ 拒绝并点名。全程无 `sleep`（判例-31）。

## 三、变异对照（两发，均实测）

| 变异 | 改哪里 | 读数 | 还原 |
|---|---|---|---|
| 子代理：`claim_item` 改成永远放行 | 生产实现 | 8 格里 **5 红**（G1 / G1-b / G2×2 / G4），3 绿 | 复绿 8/8；`grep MUTANT-MT0R2` = 0 |
| **终审独立复验**：G1 持有者断言改成 `lane-ZZZ` | 只改测试 | **恰好 1 红**（G1 @L73/87），7 绿 | 逐字还原后 8/8 |

> 两发互相印证：实现侧变异红 5 格（互斥 + 释放 + 对账），测试侧变异只红 1 格（证明断言精确、不是一刀切）。

**探针标定（判例-32 实践）**：`moon test -f` **需要通配** —— `-f "claim_guard"` 回 `Total tests: 0`（看着像"没这测试"），`-f "*claim_guard*"` 才回 8。我先把探针标定成功，再用它的读数。

## 四、缺口与风险

1. **错误文案变化（非成功语义）**：再 claim 一条已领取任务时，文案由 `非法迁移: claim 要求状态 [待领取]…` 变为 `CLAIM_GUARD: …已被 A 持有…`（信息是超集）。全仓无测试断言旧串。
2. **跨库同 `(ns,id)` 不互斥**：store 未暴露库身份 ⇒ 采用「账本仍待领取即允许接管」。要跨进程/跨库，正确层是 store 侧 `rsv_*`。
3. **`archive_force` 未加释放行**（边界外）：实测无实质缺口 —— 它只放行 已暂停/已打回，这两态已分别被 pause/reject 释放过。
4. **内存条目不做 TTL**：只在释放/对账时清，规模受进程生命周期 claim 次数约束。
5. **并发 WIP**：改动期工作树有 20+ 他人改动；本次只碰 2 改（+1 锁已被 d6a0bc2f3 先行入库），未触 `server.mbt`。

## 五、后续建议

1. 逻辑项互斥下沉到 store 侧 `rsv_*`，覆盖跨进程/跨库（这才是"同一 BACKLOG 项只一人"的完整解）。
2. `archive_force` 补释放行。
3. 若要以「BACKLOG 项」而非「任务 id」为互斥粒度，需先建「任务 → BACKLOG 项」映射（当前 claim 取不到）。
4. 测试总数锚点又前进了（本轮复跑见 AGENTS 已写 1914）⇒ 提交时按实测刷新，勿沿用 1904。

## 六、超额内容

探针标定（`-f` 需通配）原本不在任务范围内，但它是本次"8 格是否真在跑"的唯一证据路径，顺手记录成可复用经验。

## 七、来源

- 设计依据：`reports/2026-10-13-multilane-lock-mechanism-report.md` §9（多 lane 盲点）
- 锁：`src/engine/engine_claimguard_wbtest.mbt`（8 格，`d6a0bc2f3`）
- 报告：`reports/2026-10-29-plan-reconciliation-report.md`（T0 对表指出"claimguard 零接线"）
