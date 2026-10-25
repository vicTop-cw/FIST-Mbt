# `origin/slave/clean/dsh/recur/r3` 增量保全

- **蒸馏时间**：2026-10-25 · 司令-γ
- **来源分支**：见文件夹名（`slave-xxx` ⇔ `origin/slave/xxx`）
- **保全内容**：
  - `full.diff` —— 该分支相对 main 的**完整 diff**（含全部文件）
  - `name-status.txt` —— 逐文件 A/M/D 状态面

## 为什么保全

这 4 支都有**自己的交付物**（`docs/design-*.md` + `reports/*-report.md` + 若干 `scripts/` 改动），
δ 的 `asset-preservation-proof.md` §2.6 **未覆盖**它们。

## 判定：含「真删除面」

这 4 支都删了 `.dsh/fist-mbt-plugin/cordis.patch.yml`，
但 **main 上本来就没有这个文件**（`git cat-file -e main:.dsh/.../cordis.patch.yml` 未命中）
⇒ **不是基线倒退**，是分支基线里带着老文件、这次清理掉。

## 若将来要重做

先按 `name-status.txt` 逐文件核「这些改动在 main 上有没有等价物」，
再按判例-1 的口径检查 `D` 面是否有 main 已有文件被删（**当前：无**）。
