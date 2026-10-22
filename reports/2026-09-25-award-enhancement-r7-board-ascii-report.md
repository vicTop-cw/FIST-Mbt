# 获奖提升 · 第 7 轮汇报：实时任务看板 board_ascii

> 日期：2026-09-25｜目标：获奖概率再往上提｜推进方式：fist-mbt 自驱式（新增 1 个 MCP 工具）

## 结果摘要
新增 MCP 工具 `board_ascii`——按状态分组 + 深度缩进的实时任务看板 ASCII，让 agent（或人类）一次读到「哪些任务、各自什么状态、分布在树的哪一层」。与 `fist://map`（静态代码库地图）、`dag_ascii`（依赖结构图）互补，把"地图"从静态扩展到实时管家视图，直接落地目标 pillar「让 agent 读项目一目了然、别全项目去找」，并呼应调研「偏好可见效果」（缓解评审可视化偏好）。

工具数 70→**71**，`moon test --target js` **203/203**（+2）。

## 关键改动
- `src/server/board_ascii.mbt`（新）：`render_board_ascii(tasks, ns) -> Json{counts, ascii}`——纯 MoonBit、复用 @core 模型，无新表/依赖；状态分组（待领取…已归档）+ 深度缩进 + 状态合计尾行 + ns 过滤。
- `src/server/server.mbt`：注册 `board_ascii` 工具（namespace 可选，空=全部）。
- 测试：`src/server/board_ascii_test.mbt`（分组缩进 + ns 过滤）。

## 验证
- 单测全绿；E2E `tools/list`=71 + `board_ascii` 渲染真实看板 → PASS。
- 文档即实现：工具数 70→71、测试 201→203 全量同步（README/AGENTS/ARCHITECTURE/USAGE/deliverable/agent-map/scripts-README/申报书）；`mcp_smoke.py` 断言 70→71；README 徽章 199→203；E2E 后清理看板测试任务（整洁）。

## 资源消耗
+1 工具；+2 测试；无新增依赖/表。git `76896d9 → HEAD`。

## 任务分配记录
看板模块 + 工具注册 + 单测 + E2E + 文档/脚本断言全量同步 + 沉淀记忆。

## 遗留风险
- 看板默认展示全部命名空间（空 ns 参数）；如需"仅当前 store_open 的 ns"，可按 `engine.set_namespace` 再收窄（当前已支持 namespace 参数显式过滤）。

## 后续建议
- 下一候选中期项：`declare` 强契约 / `@fs.tmpdir` 系统临时目录 / 看板接入 `store_open` 当前 ns 默认值。

## 来源
`git log c5f7718..HEAD`；`src/server/board_ascii.mbt`、`board_ascii_test.mbt`、`server.mbt`；`scripts/mcp_smoke.py`。