# 获奖提升 · 第 8 轮汇报：项目脉冲 status_summary + 修复 overview

> 日期：2026-09-25｜目标：获奖概率再往上提｜推进方式：fist-mbt 自驱式（新增 1 个 MCP 工具）

## 结果摘要
新增 MCP 工具 **`status_summary`**——让 agent（AI 客户端）一次 `tools/call` 就读到项目脉搏：`{ version, total_tasks, by_status:{状态:数量}, active_namespaces }`，不必 list+逐条筛选，强化"fist-mbt 是更好的 AI 项目管理工具"。纯 MoonBit、复用引擎任务集、无新表/依赖，工具数 71→**72**。
顺带修复 `fist://overview` 两处过时点（评审可直接读取的 Resource）：version `0.1.0`→`0.2.4`、状态数 7→**9 态**（补"已打回/已暂停"）；看板状态 order 一并补"拆分中"，9 态齐全。

`moon test --target js` **204/204**（+1 status_summary 单测）。

## 关键改动
- `src/server/board_ascii.mbt`：新增 `render_status_summary(tasks, active_ns, version)`；看板 order 补"拆分中"。
- `src/server/server.mbt`：注册 `status_summary` 工具；`overview_json()` version 0.2.4 + 9 态。
- `src/server/board_ascii_test.mbt`：status_summary 单测。

## 验证
- 单测全绿；E2E `tools/list`=72 + `status_summary` 返回 version 0.2.4/total/by_status/active_namespaces → PASS（只读，无 db 残留）。
- 文档即实现：工具数 71→72、测试 203→204 全量同步（README/AGENTS/ARCHITECTURE/USAGE/deliverable/agent-map/scripts-README/mcp_smoke/申报书），README 徽章 203→204。

## 资源消耗
+1 工具、+1 测试、+1 pub 函数（render_status_summary）；无新增依赖/表。git `e316985 → HEAD`。

## 任务分配记录
脉冲工具 + overview 修复 + 单测 + E2E + 文档/脚本断言全量同步 + 沉淀记忆。

## 遗留风险
- `active_namespaces` 反映已 `store_open` 的命名空间；未打开任何 ns 时为空数组（工具名/数据仍可从 by_status 判断）。为"当前 ns"聚合可再接入引擎 set_namespace。

## 后续建议
- 下一候选中期项：`declare` 强契约 / `@fs.tmpdir` 系统临时目录 / `status_summary` 接入"当前 ns"聚合。

## 来源
`git log e316985..HEAD`；`src/server/board_ascii.mbt`、`board_ascii_test.mbt`、`server.mbt`。