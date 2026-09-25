# 获奖提升 · R48 汇报：fist://map 补全工具家族 + map_verify 锁定

> 日期 2026-09-25 ｜ 字母轮号 R48（deliverable 功能轮第 44 行）｜ 主题：结构化项目 · 地图对 agent 完整（支柱①）

## 结果摘要
环视发现 `fist://map` 的 tool_groups 漏掉 R46 已列的新增工具：publish_parallel/reopen_task、omega_verify/verify_fix、运维杂项 9 个、atgc_old 3 个等——agent 首读地图却不完整，违反支柱①"让 agent 读取项目时一目了然"。

## 资源消耗
- 改动：`src/server/server.mbt`（`map_json` tool_groups 补关键工具家族 + 新增 2 分组）、`scripts/map_verify.py`（+R48 断言锁定补漏）。工具/测试计数不变（83/233）。

## 任务分配记录
- 主会话直改 + 实跑 `map_verify.py` 验证；曾试做过严断言（要求地图精确覆盖全部 83 个工具 id）发现不成立——地图是"人类友好短名"定位工具而非工具 id 清单，回退为"关键补漏命中"断言。

## 遗留风险
- 地图分组沿用短名（如 `audit_permission/log` 内含 audit_log），未逐 id 穷举；精确全覆盖由 `check_tools_sync.py`（AGENTS vs server 真源）把关，两个守卫职责互补。
- 地图与 AGENTS 的分组名称体系不同（"自驱" vs "自驱闭环"等），属各自组织风格，非漂移。

## 后续建议
- 若想让地图对 agent 更可导航，可加 `fist://map` 的每个分组工具用精确 id 全文（会明显加长资源文本），权衡后暂不必要。
- 大项：`watchdog_tick` 无人值守接 `selfdrive_dispatch`（中改、跨包耦合）仍为可选的下一叙事增强。

## 超额内容
- 本轮顺带证明"先做守卫/验证再改立场"的纪律：map_verify 首版过严断言暴露地图短名语义，及时回退而非硬凑，避免误锁。

## 来源
- `moon test --target js` 233/233；`python scripts/map_verify.py` PASS；`python scripts/check_tools_sync.py` PASS。

*（内容由AI生成，仅供参考）*