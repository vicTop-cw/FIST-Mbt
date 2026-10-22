# 获奖提升 · R58 派单能力自动抽取（dispatch_next want 免手传）汇报

> 日期 2026-09-26 ｜ 字母轮号 R58（deliverable 功能轮第 49 行，测试 +1 → 240）｜ 主题：自治闭环零参数化 + 文档漂移修复

## 结果摘要
把 R57 看门狗自动派单的"最后一处手动"去掉：`dispatch_next` 在 `want` 为空时从顶部任务描述自动抽取所需能力标签，
并按抽取出的能力路由最佳执行者——无人值守下"只要任务描述 + 执行者能力注册，看门狗自动决定派给谁"，真正零参数。
同时修复 R57 漏掉的 AGENTS watchdog_tick 文档漂移。**测试 239 → 240（+1），三守卫 PASS，mcp_smoke 83 工具，moon check 0 错误**。

## 资源消耗
- 改动面极小：仅 `src/engine/engine_dispatch.mbt`（新增 `FistEngine::auto_want`、`dispatch_next` 空 want 自动抽取 + 返回补 `want` 字段）
  与 `src/engine/engine_dispatch_test.mbt`（+1 用例）；`AGENTS.md` watchdog_tick 行补实。
- 文档同步：README/AGENTS/deliverable/scoring_rubric 239→240；deliverable §四 补 49 行。
- 验证：`moon test --target js -j 1` 240/240；check_badge / check_test_sync / check_tools_sync 全 PASS；mcp_smoke PASS；cleanup 洁净。

## 任务分配记录
- 主会话直改 + 单文件测试（R58 1/1）+ 全量 240/240 + 三守卫 + 文档同步（属轻任务，未起子代理）。

## 验收标准 → 实测
- 功能：want 为空时自动抽取并路由 → **通过**（描述含"仪表"→ auto_want 抽到"仪表"→ 路由命中 nete）。
- 零回归：显式 want 仍优先，既有 dispatch_next/看门狗用例不变 → **通过**（engine 50/50、全量 240/240）。
- 文档即实现：四文档测试总数 240 全量一致 → **通过**；AGENTS watchdog_tick 工具说明补 autodispatch/autodispatch_want → **通过**。

## 遗留风险
- `auto_want` 依赖描述里精确出现 store 注册的能力标签子串；描述措辞与标签不一致时抽取为空，回退 agent（不崩溃、可后续泛化）。
- Windows native 竞态等既有边界不变（JS 后端为权威稳定门槛）。

## 后续建议
- 自治闭环已零参数闭环。下一轮建议转向评审节点强项：**4 AI 并行打分一轮严苛评分**、申报书、演示脚本（门禁首跑显示为短项），或三支柱其余薄弱点（项目整洁 / 复用 / 地图）。
- 可考虑给 `auto_want` 加同义词/模糊匹配（词表对齐），进一步提升免手传命中率。

## 超额内容
- 无（严格按任务包边界交付；含一次性文档漂移修复）。