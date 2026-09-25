# 获奖提升 · R25 汇报：README 一键完整自检门禁 + Tools 计数修正（评审可复现闭环）

> 日期：2026-09-25｜目标 pillar：任意机器结果可完全复现 / 文档即实现（评审体验）
> 方式：fist-mbt 自驱式获奖概率提升链路；本轮为文档可复现闭环（不新增工具/测试）。

## 结果摘要
- **README「一键自检」旁补「一键完整自检（评审用）」**：把 `moon test --target js -j 1`（→**219/219**）、`python scripts/mcp_smoke.py`（→**78 个工具**）、`python scripts/award_demo.py`（→**MCP-AWARD-DEMO PASS** + 结尾 cleanup **CLEAN**）连成一条评审可一键复现的闭环，并附"临时 .db 属正常、结尾自动清理仅剩交付库"的说明。**所有期望均逐条实跑核对后才写入**（不臆造，避免评审跑不通）。
- **修正 README 一处超陈旧计数**：`## MCP 暴露面 → Tools（61 个）` → `Tools（78 个 · 精选概览；完整清单见 AGENTS.md 与 fist://map）`。
- 全仓 README 工具计数 grep 复核：仅剩两处正确 78。
- 纯文档；`moon test --target js` **219/219**、`mcp_smoke` 78、`award_demo` PASS+CLEAN 不变。

## 资源消耗
- 修改：`README.md`（一键完整自检块 + Tools 计数）、`memory/2026-09-25.md`（R25）。
- 验证：实跑 `moon test`/`mcp_smoke`/`award_demo` 逐条对期望。

## 任务分配记录
- 直接实现（指挥官终审制）：先取证（跑三条命令得真实输出），再写文档；纯文档，无回归。

## 遗留风险
- README `## MCP 暴露面` 仍是"精选概览"而非 78 个穷举（标题已注明完整清单见 AGENTS.md / fist://map），避免冗长失准。
- 静态测试徽章 `tests-219/219` 手工维护；若再新增测试需同步（已在 KNOWN 说明）。

## 后续建议
- 下一可借力点（按调研强度）：
  1. **把 `task_triage`（含 want）接进自驱/看门狗"按推荐取单"**（无人值守按能力而非固定顺序）；
  2. **executor 注册 + 路由**（远期 Marketplookup 完整形态）；
  3. **CI 徽章实时化**（把 `tests-219/219` 静态徽章改为 workflow 生成，减少手工同步）。

## 超额内容
- 评审从头（README 快速开始）到尾（deliverable/申报书）逐处可复现、计数与实测一致；一键完整自检替代了"到处找命令拼验证"。

## 来源
- 现状：`README.md` 快速开始；实机输出 `moon test`(219)/`mcp_smoke`(78)/`award_demo`(PASS+CLEAN)。
- 前置：R15 award_demo + cleanup、R21-R23 triage/want、R24 轮表对账。