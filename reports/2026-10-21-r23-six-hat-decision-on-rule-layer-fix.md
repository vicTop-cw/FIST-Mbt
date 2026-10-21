# R23 · 六顶帽辩论：issue_scan 规则层修复批（BUG-345/346/347/348）处置口径

- 日期：2026-10-21
- 会话：`debate-20261021-001`（进程内态，重启即失）
- 终态门：**user**（本工件只给收敛读数，不代用户裁决）
- 状态：**未收敛**（rate=0.333 < 0.6），建议**不自动推进落地**

---

## 结果摘要

用 fist-mbt 新能力（R118 六顶帽，`debate_convene` / `debate_register` / `debate_verdict`）为阻塞十轮的规则层修复批产出结构化决策工件。

| 帽 | verdict | 要点 |
|---|---|---|
| 白帽（事实） | abstain | 只列已证事实，不下判断 |
| 黑帽（风险） | **reject** | 并发 WIP 冲突 / 退役=行为变更须 owner / 白盒锁与 by_severity 下游会静默变动 / 组合环可能提前停环 |
| 黄帽（价值） | **pass** | 72.7% FP 使闭环不可用 / 同根因族一批落地口径一致 / 顺序 347→345→346→348 由浅入深 / 执行者已就位 |

**收敛读数**：`{total:3, agree:1, rate:0.333, threshold:0.6, pass:false}`
**anti_drift**：`evolve_critic`、`goal_drift_check`

**指挥官综合裁决（金条四：执行权在用户/owner）**：
黄帽与黑帽并不矛盾——价值真实存在，但**落地时机与授权未到**。因此：
1. **不自动推进落地**。黑帽①③④⑤ 的风险均指向"现在动 src/server 会踩并发 WIP / 破坏白盒锁 / 静默改读数"，这些是硬约束不是偏好。
2. **组合环 `r21-rule-layer-fix` 继续停在 bugfind 步**，不 tick 到 fix_and_merge。
3. **保留 ready-to-go 工件**：执行者已定（exec-scan-rules），修复顺序与口径已定（见下），src/server 清空 + owner 授权后即可派单。
4. **行为变更项（BUG-346 退役）不擅自落地**，owner 已裁 RETIRE，但落地仍须 owner 点头。

## 资源消耗

- 3 次 `debate_register` + 1 次 `debate_convene` + 1 次 `debate_verdict` + 1 次 `hat_list`（纯计算/进程内，零文件副作用）
- 无模型调用、无网络、无子进程
- 零文件写入（除本报告与当日记忆）

## 任务分配记录

- 修复执行者（预派）：`exec-scan-rules`（executor_auction 与 executor_route 双机制收敛，coverage=1.0）
- 验证门派（预派）：`exec-verify-gate`（`moon test --target js` 全绿 + `issue_scan` FP 率下降复验）
- 本轮不派单：src/server 37 脏（R14→R23 十轮字节未变），并发未提交 WIP（BUG-335/BUG-339）

## 遗留风险

- src/server 十轮未清，issue_scan 家族 6 条 OPEN（327/333/345/346/347/348）全部压着。
- 组合环停在 bugfind 步，重启即失（诚实标注），需重建。
- 退役/改口径属行为变更，执行权在 owner。

## 后续建议

1. src/server 清空后按 **347 → 345 → 346（退役）→ 348** 顺序单批落地，每步跑 `moon test --target js` + `issue_scan` FP 率复验。
2. 落地前先 diff `issue_scan_wbtest.mbt` 白盒锁，确认精度修复不破坏 BUG-72 降噪断言；by_severity 口径改动同步校验下游统计。
3. 组合环重建为 `r21-rule-layer-fix`，落地后 tick 至 fix_and_merge → verify。
4. 落地即用 issue_scan 自验：目标 FP 率由 72.7% 显著下降。

## 超额内容

- 首次在本仓真实启用 R118 六顶帽/辩论能力并产出可复核读数（此前无实战记录）。
- 验证了该能力的**诚实边界**：三帽天然分歧时工具只给 rate 不强行收敛，终态门在用户——符合"本工具不自动判定"的设计。

## 来源

- `memory/bugs.md`：BUG-333/345/346/347/348
- 本会话 R19/R20/R21/R22 报告与审计证据
- 工具回执：`debate_convene` / `debate_register` ×3 / `debate_verdict` / `hat_list`