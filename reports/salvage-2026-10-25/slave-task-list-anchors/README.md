# `origin/fix/slave-task-list-anchors` 增量保全

- **蒸馏时间**：2026-10-25 · 司令-γ
- **来源分支**：`origin/fix/slave-task-list-anchors`
- **真增量**：`docs/2026-10-20-slave-tasks.md` 的锚点行号修正（`slave-tasks-anchors.diff`，67 行）
- **为什么保全**：这是**文件面**改动（认领入口的 `文件:行` 锚点），
  行号会随 main 演进持续漂移 ⇒ 同类修正将来还会需要。**保全 diff 作为「锚点漂移的修法样本」。**

## 相关判据

`scripts/check_slave_task_list.py` 的 A/B/C/D/E 五族判定 + `--suggest-anchors` 只读建议器
（后者的增量已另存 `reports/2026-10-25-consolidated-r65-suggest-anchors-salvage.md`）。
