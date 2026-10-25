# `origin/fix/backlog-proof-restamp` 增量保全

- **蒸馏时间**：2026-10-25 · 司令-γ
- **来源分支**：`origin/fix/backlog-proof-restamp`
- **真增量**：`docs/tasks/backlog/` 下 5 份 TASK yaml 的重打基线（`backlog-yaml-restamp.diff`，86 行）
- **为什么保全**：backlog 是任务队列，**重打基线可能是有效动作**（把 anchor/状态按现状刷新），
  不像代码增量那样能一眼判「已在 main」。**保全 diff，供将来需要时人工比对后决定是否重做。**

## 排除的基线噪音（不是增量）

`.dsh/` `packaging/` `package.json` `README.md` `.gitignore` `memory/` `reports/` `tmp_merge_batch.*`
—— 这些是「分支基线有、main 没有」的老文件，**判分支增量时必须排除**（判例-8 同族）。
