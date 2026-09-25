# R107 汇报：quickcheck 属性测试（BACKLOG P2 落地 · 复用 moonbitlang/core/quickcheck · 287→295/295）

> 日期 2026-09-26 · FIST 指挥官终审通过 · 结果摘要 / 资源消耗 / 分配记录 / 遗留 / 建议 / 超额 / 来源 全齐

## 一、结果摘要
- **目标**：兑现 BACKLOG P2「集成 moonbitlang/core/quickcheck 属性测试替代部分硬编码断言」——拿来主义支柱实证：复用既有属性测试库（随机输入验证不变量），并补测 core/decompose 两个此前**无直接测试**的基础包。
- **交付**：
  1. `src/decompose/decompose_quickcheck_test.mbt`（新，黑盒 +3）：default_slices 数量与前缀不变量 / difficulty_label 三档合法+整段单调（前易后难，含越界 idx 钳制）/ difficulty_label_from 随数值单调不减；
  2. `src/core/core_quickcheck_wbtest.mbt`（新，白盒 +5）：Task 迁移纪律 claim（空 assignee 拒绝）/ execute（仅两态）/ reopen（仅归档拒绝）/ split（叶子拒绝）/ submit-reject 对称；
  3. core/decompose 的 moon.pkg 各加 `moonbitlang/core/quickcheck` **`for "test"`**（test-only 导入不污染产物体积）。
- **验收**：`moon check` 0 错误；`moon test --target js -j 1` **287→295/295 全绿**；mcp_smoke PASS（101 工具）；award_demo **MCP-AWARD-DEMO PASS**；守卫族 check_tools_sync(101)/check_test_sync(295)/check_scripts_index/map_verify 全 PASS；cleanup 清 83 残留 → CLEAN。

## 二、资源消耗
- 调研：本地工具链 `~/.moon/lib/core/quickcheck`（README.mbt.md + facade/driver 签名核对——check 单参 `(A) -> Bool raise?`、count/max_size/seed 可配、固定 seed 可复现）。
- 实现：core_quickcheck_wbtest.mbt（+5）/ decompose_quickcheck_test.mbt（+3）/ 两 moon.pkg（test-only 导入）。
- 验证：`moon check` + `moon test --target js -j 1`（295/295）+ mcp_smoke + award_demo + 守卫族 + cleanup（83 残留清理）；12 处文档计数与覆盖说明同步（README/README_EN/AGENTS/ARCHITECTURE/deliverable/scoring_rubric/BACKLOG/agent-map/申报书/快照/日志/报告）。

## 三、任务分配记录
- R107 属指挥官亲自实现的硬创新轮（与 R92-R104 同模式，无子代理）；无子任务发布。

## 四、遗留风险
- 属性测试聚焦纯函数/状态机迁移层（core/decompose），engine 集成层仍以固定断言覆盖（既有 287 测试不变）——后续可按需扩面。
- quickcheck 在 JS 目标下通过；native 目标需按既有边界（Windows native 偶发竞态）串行验证，权威门槛仍为 JS 后端 295/295。
- `for "test"` 导入在 `moon check` 输出 core_package_not_imported 警告（本项目既有 991+ 警告同类，非错误）——不阻塞、不污染产物。

## 五、后续建议
- **R108 候选（硬创新轮）**：BACKLOG P2 剩余（Transactional transition / Evaluator-Optimizer schema）或 P1（Agent Contract 7 字段注入 ops_selfdrive）；硬创新后按门禁纪律后台跑 score_gate 复评（第 27 次评估，快照 `_snapshot.md` 已更新为 295 + R105-R107 行）。
- 门禁复评 PASS 后收口（score-20260924.md 追加评估段 + 日志/报告 + commit/push 指定文件）。

## 六、超额内容
- 顺手修正 README 快速开始/测试段历史遗留的「148 项」陈旧计数（现 295），"文档=实现实时校准"纪律内。

## 七、来源
- 调研：`~/.moon/lib/core/quickcheck/README.mbt.md` + `driver.mbt`（check 签名与参数语义）
- 实现：`src/core/core_quickcheck_wbtest.mbt` / `src/decompose/decompose_quickcheck_test.mbt` / `src/core/moon.pkg` / `src/decompose/moon.pkg`
- 文档：README/README_EN/AGENTS/ARCHITECTURE/deliverable/scoring_rubric/BACKLOG/agent-map/申报书/`memory/research/_snapshot.md`
- 留痕：`memory/2026-09-25.md` R107 段
