# 2026-10-21 · TASK-001 冲突标记硬前置门禁报告（R88）

## 1. 结果摘要
- **交付**：`scripts/slave-branch-merge.ps1`（合并 agent 执行面）两道 TASK-001 硬门：
  1. **pick 级门**（验收②③）：每笔 `cherry-pick --no-commit` 冲突处理完之后、`git commit` 之前，
     跑 `python scripts/blackbox/check_merge_markers.py`；rc≠0（面上仍有标记）→ 本笔 pick
     `git reset --hard HEAD` 整笔回滚 + 日志点名 + 计入 `Skipped (conflict markers, TASK-001 gate)`，
     绝不带标记进 commit。根因闭环：原脚本在 src 冲突未解时无条件 commit（259b56a8 实证形状）。
  2. **push 前总闸**（验收①合入者侧）：push 之前再跑同一判据，rc≠0 拒绝 push（rc=1 面上有标记
     / rc=2 判据无法自证一律不推），转人工。
- **验收① CI 侧**：已在先——`ci.yml:38-45` 冲突标记硬门禁（R74 接线，`--selftest` + 全量两步），
  本轮核实在位，不重复接线。

## 2. 资源消耗
- 单文件 3 处小改（计数器 / pick 门 / push 总闸）；纯脚本面，无 .mbt 改动。

## 3. 任务分配记录
- 副机亲自实现（单文件单特性）。

## 4. 验证证据（rc 实读）
- `python scripts/check_ps_encoding.py` → PASS（9 个 .ps1 全部带 BOM 或纯 ASCII）——改动后 BOM 未破坏。
- PowerShell 5.1 `Parser::ParseFile` → PARSE OK rc=0（语法面自证；本机无 pwsh，DryRun 全流程
  在 pwsh 宿主上跑，行为面只能交给合并 agent 实跑验证——已如实降级标注）。
- 判据本体自证：`check_merge_markers.py --selftest` 在 CI 每次运行（ci.yml 两步）。
- 行为面推演：src 冲突未解时 `git add -A` 后暂存区含标记 → 判据 rc=1 → 回滚；memory/reports/docs
  取 theirs 后无标记 → rc=0 → 正常 commit，既有 theirs 语义不变。

## 5. 行为变化（交 owner 复核）
- **src 冲突的 pick 从「带标记 commit + 后续 [5/6] 循环清理」改为「整笔回滚跳过」**——宁可漏合、
  不可带标记进 commit（TASK-001 P0 语义）。被跳过 pick 的 src 改动不进主线，在日志有 hash 点名；
  若该改动值得合，需人工解冲突后重放。[5/6] 清理循环与第 7 步清理 commit 保留（兜底非 pick 路径的残留）。

## 6. 遗留风险（预存红点名，不代修）
- 本机无 pwsh（仅 Windows PowerShell 5.1），DryRun 全流程未实跑；语法已过 5.1 Parser。
- `git reset --hard` 只作用于合并 driver 自身工作树（脚本设计即独占工作树），非他人工作面；
  脚本开头有 HEAD 备份（README 已述）。
- ABORT 级 3 支分支（R86 报告）仍待人工清标记——本轮门禁不改变它们的状态，只保证不再新增坏 commit。

## 7. 后续建议
- 合并 agent 下次实跑后把 `Skipped (conflict markers)` 计数回填账本，观察门禁触发率。
- 若 owner 认为整笔回滚太狠，可改为「只回滚冲突文件、保留无冲突 hunks」——属人的决定。

## 8. 超额内容
- 无（acceptance ①③全覆盖 + push 总闸属①的合入者侧闭环）。

## 9. 来源
- 任务：`docs/tasks/backlog/TASK-001-conflict-markers-no-commit.yaml`（P0，discovered_by: lead；
  evidence: 259b56a8 / e1b1a9d3）；判据真源 `scripts/blackbox/check_merge_markers.py`。
