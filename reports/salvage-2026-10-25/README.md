# 分支增量保全 · 2026-10-25（C 档清理同批）

> **为什么放在 `reports/` 而不是 `_archive/`**：
> `_archive/` 在 `.gitignore`（`/_archive/`），**不进跟踪面**。
> 保全的价值在于「将来有人能查到」——放进 gitignore 等于**没人能看见的保全**。
> ⇒ **落 `reports/`（跟踪面 = 证据链面）**。

## 内容

| 目录 | 来源分支 | 保全什么 |
|---|---|---|
| `backlog-proof-restamp/` | `origin/fix/backlog-proof-restamp` | 5 份 backlog yaml 重打基线的 diff（86 行）+ 为何保全 |
| `slave-task-list-anchors/` | `origin/fix/slave-task-list-anchors` | 认领入口锚点修正 diff（67 行）+ 为何保全 |
| `slave-clean-dsh-recur-r3/` | `origin/slave/clean-dsh-recur-r3` | 完整 diff（1219 行 / 14 文件）+ name-status |
| `slave-clean-dsh-recur-r6/` | `origin/slave/clean-dsh-recur-r6` | 完整 diff（698 行 / 11 文件）+ name-status |
| `slave-dsh-plugin-portable/` | `origin/slave/dsh-plugin-portable` | 完整 diff（1549 行 / 35 文件）+ name-status |
| `slave-fix-push-guard-sustainability-r1/` | `origin/slave/fix-push-guard-sustainability-r1` | 完整 diff（1740 行 / 39 文件）+ name-status |

**另**：`reports/2026-10-25-consolidated-r65-suggest-anchors-salvage.md`（`--suggest-anchors` 增量全文）。

## 这些分支已从远端删除

保全的意义：**分支没了，增量还在**。要重做时按 `name-status.txt` 逐文件核
「main 上有没有等价物」，再按判例-1 检查 `D` 面。

## 判定依据

- `git diff --name-status main...origin/<branch>`（判例-1 基线倒退检查）
- `git cat-file -e main:<file>`（判例-54：判 rest 存在不判输出）
- 排除 `tmp_merge_batch.*`（判例-8 假阳性）与 `.dsh/` `packaging/` 等基线噪音
