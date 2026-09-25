# 获奖提升 · R46 汇报：工具清单单一真源守卫 + AGENTS 补齐 29 工具

> 日期 2026-09-25 ｜ 字母轮号 R46（deliverable 功能轮第 42 行）｜ 主题：项目整洁 / 文档即实现 · 单一真源

## 结果摘要
把"工具清单文档即实现"做成立即可验的 CI 硬约束。新增 `scripts/check_tools_sync.py`，唯一真源 = `server.mbt` 实际注册的工具名（正则 `instrumented_tool(\n s1,\n "<name>",)` 精确提取 83 个、实测无重复）；校验 AGENTS 表格行首反引号名 ⊆ 真源、真源全部工具必须出现在 AGENTS、README/AGENTS/deliverable/scoring_rubric 工具总数 == 83。接入 ci.yml JS 两轨。守卫立即暴露真实缺口：AGENTS.md 只列 54/83（漏 29 个真源工具），本轮逐组补齐后 PASS。测试/工具计数不变（83/233）。

## 资源消耗
- 新文件：`scripts/check_tools_sync.py`；改动：`AGENTS.md`（补 29 工具 + 新增 3 分组 + 组计数更新）、`.github/workflows/ci.yml`（两轨加守卫）、`docs/deliverable.md`（42 行）。
- 时间：单轮闭环（建守卫 → 发现缺口 → 补齐文档 → 接 CI → 验证）。

## 任务分配记录
- 主会话直改 + 实测脚本验证（`_probe_tools.py` 临时探测 regex 提取 83 个后删除，保持项目整洁）。

## 遗留风险
- 守卫依赖 server.mbt 注册模式 `instrumented_tool(` 稳定；若未来改成别的注册 helper 需同步更新正则（脚本顶部有注释说明）。
- AGENTS 分组计数注释（如"生命周期（14）"）是人工维护的近似标签，守卫不校验"分组和==83"（只校验"全真源在文档出现 + 无幽灵工具"），避免过度约束。

## 后续建议
- 把较簿：可进一步加"测试数单一真源"（extract real test count from moon.log 跨 README/AGENTS/deliverable/scoring_rubric），与 check_badge 互补。
- 大项剩余：把 deliverable 轮表也纳入单一真源校验，或让 fist://map 与 AGENTS 分组同一源生成。

## 超额内容
- 守卫同时覆盖"文档有幽灵工具"与"新工具有漏写"两个方向，形成双向闭环。

## 来源
- `python scripts/check_tools_sync.py` → PASS；`moon test --target js` 233/233；`moon check` 0 错误。

*（内容由AI生成，仅供参考）*