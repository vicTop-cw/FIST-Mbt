# 2026-10-21 副机 R85 报告 — TASK-006：docs 结构规范 DOCS-STRUCTURE.md

## 结果摘要

- 新增 [docs/DOCS-STRUCTURE.md](../../docs/DOCS-STRUCTURE.md)（TASK-006 验收①）：四类文档定位/命名/放置（根目录入口面 / docs/ 计划设计 / reports/ 轮次报告 / memory/ 运行记忆）+ docs/tasks/ 任务池说明 + 新人速查表。
- 分支 `slave/docs/task006-docs-structure-r85`，基点 **gitcode/main 52fc0f1**（含本轮已合入的 r83）。

## 资源消耗

- 1 个会话轮次；无代码改动、无 .mbt/.mbti 触碰（不触发 fmt 门）、无网络消耗。

## 任务分配记录

- 副机（本会话）独立完成：现状核查（守卫对根目录文件的钉住面取证）、规范撰写、守卫回归。

## 遗留风险

1. **验收②按原文执行会挂红 CI，已如实降级**：「根目录只留 README.md + ARCHITECTURE.md + CHANGELOG.md（其他迁走或删除）」与守卫网络冲突——核查实证根目录 9 份 md 全部是守卫判据输入（AGENTS=J2/J10、README=J2/J3/badge/R13/model_auth、README.mbt.md+ARCHITECTURE.md=check_test_sync R2 must-carry+枚举自锁、USAGE.md=BUG-30、CHANGELOG.md+BACKLOG.md=J4/J13、AI-DEVELOPMENT-STANDARD.md=J6/J7）。规范把②改写为「不再往根目录新增普通 md；确要迁移先改守卫再动文件」——此为对验收字面的偏离，请 owner 过目确认。
2. **验收「docs/ 内部分层（plans/ reports/ design/ skill/）」未做目录迁移**：降级为命名规则（归档评估类 `YYYY-MM-DD-` 前缀——J15 已机判；常驻参考平铺；旧档进 docs/archive/）。63 份平铺文件的迁移会一次性失配守卫与脚本内的路径常量，属低优先级（scope 原话「规范先出」）。
3. 主机远端已出现同名任务分支 `fix/task-003-ci-step-position`（TASK-003 的另一实现，设计不同：P1 静态预检族硬门 / P2 只报、无棘轮）——与我已推送的 `slave/ci/task003-step-position-r84` 待 owner 在 MR 层仲裁。

## 后续建议

- 验收②/分层两处降级若 owner 不认可，再开迁移单（先改守卫、再动文件、同批 commit）。
- `README.mbt.md`（写着 307/307 旧数）等历史入口文件的数字陈旧问题由 check_test_sync 现状面管，不在本单范围。

## 超额内容与来源

- 无。附带把 r84 提交时漏入库的 memory 追记2（src/router 外来脏改取证）随本分支入库（该追记在 r84 提交后追加，staged 版本早于追加——教训已记 memory）。

## 验证读数

- `check_doc_surface.py` PASS（170 工具逐个可查 / J1-J16 全对表，新文件未触 J15）
- `check_template_ctrl.py` PASS；`check_test_sync.py --selftest` PASS（裸跑 rc=1 为缺测试日志的用法面，预存行为，与本单无关）
