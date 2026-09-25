# 调研记档：可扩展路线清单（future-roadmap）

> 蒸馏日期：2026-09-24
> 目标锚点：贯彻竞赛报告结论——生态唯一性 + 技术深度 + 自驱证据（加分支柱）；风险 = 演示体验 / 申报书 / MCP 概念门槛。
> 用法：与 recent-market.md 对照，区分「近期(验收前)」的必做硬实力与「中期/远期」的差异化可扩展项。
> M1 标准：全文不出现盘符/用户主目录，项目内引用相对路径。

## 近期（验收前，2026-09-30）
- **补「30 秒体验」一键演示（README 段落 + scripts/demo 脚本）** — 直接对冲「MCP 需客户端接线」的演示门槛，让评委最快看到效果。为何增分：验收通过是必要条件，演示体验是获奖关键差异因素。
- **clean README AIGC 标记 + 一页项目申报书 PDF** — 消除「被误判纯 AI 生成」的减分项，补齐赛事要求的第一印象材料。为何增分：申报书质量=评委第一印象，直接权重于排名。
- **跑通并留痕 scoring.mbt（P0 scoring，≥7 测试）** — 让自进化方案真正闭环（coverage/fingerprint/schema/accuracy 可量化）。为何增分：把「技术深度」从描述变成可运行证据。
- **（视余力）mooncakes 发布 + 英文 README** — 坐实生态贡献并可覆盖 Lambda World 2026 国际受众。为何增分：生态发布=贡献实锤，英文 README 扩大受众覆盖。

## 中期（季度评选前）
- **集成 quickcheck 属性测试 + moonbitlang/core/diff 展示** — 用 MoonBit 标准库新特性替代部分硬编码断言。为何增分：展示对官方新能力的运用，强化「技术深度」评审维度。
- **mizchi/llm 纯 MoonBit 客户端替换 Python sidecar** — 进一步「纯 MoonBit 化」。为何增分：强化"以 MoonBit 为主要语言"这一硬指标，且减少运行时依赖。
- **补 ARCHITECTURE.md 模块关系图/数据流/MCP 协议层** — 让评委快速理解全貌。为何增分：降低 MCP 概念理解门槛（评审风险中的一个）。
- **Dashboard/ASCII 可视化输出**（状态流转、DAG 依赖图 JSON→图） — ✅ 已落地（R7，2026-09-25）：`board_ascii` 实时任务看板（按状态分组 + 深度缩进 ASCII）+ 既有 `dag_ascii`（依赖结构）；点对点缓解「偏好可见效果」。为何增分：给 MCP 增加可直览呈现，对冲可视化偏好。

## 远期（季度/半年评选、生态深耕）
- **P5 self_search.mbt（自我搜索外部生态并蒸馏入档）** — 参考五方向调研实现外部检索入库。为何增分：独特"自进化"能力，可作为季度评选"持续迭代"证据。
- **Scoring 驱动的自动进化闭环（mutation/skill_lib/curriculum）** — 让 fist-mbt 自动产出并沉淀技能。为何增分：把自驱动推向"无人值守自进化"，生态中独一无二。
- **失败回流学习（learn-from-reject）** — ✅ 已落地 `evolve_lesson` 独立工具（2026-09-25）：把被打回/失败原因归档成 `[lesson]<类目>` 资产入 DGM（note=reason、code=纠偏提示），衔接 `inject` 通路、`dead_ends` 直接反映教训（`moon test` 201/201 + `lesson_verify.py` E2E PASS）。**后续增强项（已自动串联+进程内可见）**：omega 打回（`omega_spec_review`/`omega_result_verify`/`omega_escalate`）已与 `evolve_lesson` 自动串联——打回时引擎自动落 [lesson]，无需人工调工具（R6 `evolve/lesson.mbt` 单一真源 + `StoreBackend::sqlite_store`）；并补 `sync_db_lessons` 把 DB 教训回灌进内存 arc，使 `inject`/`dead_ends` 同进程可见（E2E `omega_lesson_verify.py` PASS）。为何增分：把"会犯错"从黑盒变成可演绎的护城河，独一无二。
- **与 moonclaw/posoco/官方 MCP SDK 的差异化共处**（定位"完整 MCP Server+编排+自进化"而非平台） — 在竞品升温下守住并放大稀缺位。为何增分：避免被误判重复造轮子，保持"生态唯一一体化"卖点。

## 一句总结
近期三件事（体验脚本 + 申报书/AIGC + scoring 实证）决定能否稳住"二等奖/一等奖"基础盘；中期差异化（纯 MoonBit 化 + 可视化 + 架构文档）扩大分数；远期自进化能力是"前 10"与"不可替代"的护城河。