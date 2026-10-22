# 获奖提升 · R43 汇报：triage 难度抽取单一化（复用 extract_difficulty 去重）

> 日期 2026-09-25 ｜ 字母轮号 R43（deliverable 功能轮第 40 行）｜ 主题：复用 / 拿来主义 · 去重

## 结果摘要
把 `task_triage` 自己的难度标签解析（`:易]` 后缀粗匹配 `triage_label_of`）与 R40 的 `extract_difficulty` 统一为单一抽取来源：`triage_label_of` 复用 `extract_difficulty` 再归一化易/中/难，消除两处重复解析，并顺带修正 calibrate 真实难度（`难 d=5`）在旧粗匹配下不被识别的问题。空/无标签仍按"叶/分支"兜底，对既有行为零回归。未加工具、测试计数不变（233/83）。

## 资源消耗
- 改动：`src/engine/engine_triage.mbt`（`triage_label_of` 复用 `extract_difficulty` 归一），文档 `docs/deliverable.md`（+40 行）。未加工具/测试。
- 时间：单轮闭环（重构→调试收敛→文档）。

## 任务分配记录
- 主会话直改。调试教训：triage 只列"待领取"任务，顶层非叶孩子递归时已置"拆分中"不入 triage，端到端断言 calibrate 难度显示的前提不成立——改为既有用例回归 + 纯函数语义收敛，避免误造无法成立的测试。

## 遗留风险
- `extract_difficulty` 仍为 package 私有（engine.mbt），若后续跨包复用需提升 pub；当前同包已够。
- 顶层非叶任务的难度标签在 triage 中本就不可见（拆分中不列），属既有语义非缺陷。

## 后续建议
- 大项单一真源化仍是最强剩余项：AGENTS/deliverable/fist://map 的分组与轮表做成单一数据源 + CI 校验，根除人工维护漂移。
- 可让 `board_ascii`/`status_summary` 也复用难度抽取，彻底消除全库多份解析器。

## 超额内容
- 顺带修正 calibrate 真实难度标签在 triage 里的归一识别（旧粗匹配漏掉 `难 d=5`）。

## 来源
- `moon test --target js` 233/233；`moon check --target js` 0 错误。

*（内容由AI生成，仅供参考）*