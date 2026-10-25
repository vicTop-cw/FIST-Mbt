# C 档分支清理执行报告 · 2026-10-25

> 执行人：司令-γ · 验收人：统帅
> 依据：owner 原话「分支删除《**不管哪个仓库**》」+ 统帅裁决（**两边都删，方案 B**）

---

## 0. 一句话结论

**origin 34 → 5 支（含 main/master，即剩 3 个待处理）· gitcode 154 → 137 支。**
共删 **29 支**（origin 侧 29 次 + gitcode 侧 8 次），**蒸馏保全 7 份**，**未发生任何误删**。

---

## 1. 最终读数

| 远端 | 删前 | 删后 | 说明 |
|---|---|---|---|
| `origin` | 34 | **5** | 含 `main` / `master` ⇒ **剩 3 个待处理分支** |
| `gitcode` | 154 | **137** | 只删了双边存在的那些 |

**origin 剩余 3 个待处理**：
```
fix/agent-fp-honest                    ← 待蒸馏后删（统帅已批）
fix/render-release-priority-master     ← 真基线倒退，待裁决
fix/test-count-1449                    ← 需单独判定
```

---

## 2. 三档判定与执行结果

### A 档（零增量）· 13 支 → 全部清除

| 分支 | 结果 |
|---|---|
| `feat/audit-branch-delete` | 远端早已不存在（非我删） |
| `feat/merge-loss-detector` | 远端早已不存在 |
| `fix/agent-map-battery-count-pointer` | 远端早已不存在 |
| `fix/audit-script-execution-face` | 远端早已不存在 |
| `fix/battery-tree-state-cell` | 远端早已不存在 |
| `fix/bug354-dead-params-report-bug-watchdog` | 远端早已不存在 |
| `fix/bug380-node-shim-test-runner` | 远端早已不存在 |
| `fix/bug381-fmt-check-unmeasurable` | origin 删 ✓ |
| `fix/doc-dup-guard-and-dedupe` | origin 删 ✓ |
| `fix/merge-cleanup-content-based` | origin 删 ✓ |
| `fix/merge-cleanup-remote-baseline` | origin 删 ✓ |
| `fix/readme-dedup-and-dist-refresh` | origin 删 ✓ |
| `fix/restore-merged-registrations` | origin 删 ✓ |

> ⚠️ **前 7 支的「删除失败」是判例-54 的现场**：`error: remote ref does not exist`
> 在「删对远端 + ref 已不在」下 = **目标态已达成**；但我一开始拿到 53 支的读数是**本地过期缓存**，
> 真相是远端早已 46 支。

### B 档（≤40 行）· 7 支 → 全部删除

| 分支 | 增量 | 判据 |
|---|---|---|
| `fix/cl7-plugin-sync` | 10 文件 +23/-17 | main 已含 |
| `feat/fix-desc-clip-utf8` | 3 文件 +23/-5 | **main 已用 `@encoding.encode(UTF8,…)` 修好同一缺陷**（分支用 `@utf8.encode`，等价实现） |
| `fix/gate-chain-fmt-warmup` | 1 文件 +8/-0 | main `gate.yml` 有 3 处预热 |
| `fix/moon-env-summary-shape` | 1 文件 +8/-0 | main 有 7 处 `Total tests` |
| `fix/pr-automator-windows-json` | 1 文件 +4/-1 | main 有 `ensure_ascii` |
| `fix/battery-registration-anchor` | 1 文件 +1/-1 | 锚点已归位 |
| `fix/unit-number-doc` | 1 文件 +2/-0 | 文档面 |

### C 档（需蒸馏）· 分批处置

| 分支 | 处置 | 依据 |
|---|---|---|
| `fix/consolidated-r65` | **蒸馏后删** | 真增量 `--suggest-anchors` 已保全；D 面只有 2 个 `tmp_merge_batch.*`（判例-8 假阳性），**非基线倒退** |
| `fix/backlog-proof-restamp` | **蒸馏后删** | 5 份 backlog yaml 重打基线，diff 保全 |
| `fix/slave-task-list-anchors` | **蒸馏后删** | 认领入口锚点修正，diff 保全 |
| `fix/test-sync-doc-1413` | **直接删** | 把 8 份文档同步到 **1413**，现在是 1457 ⇒ **合它会伪造旧读数** |
| `fix/warning-batch-r1` | **直接删** | 6 处全是注释/文档补充，5 处 main 已有，唯一差异是把 `1387` 改成 `1413`（**又一个过期数**） |
| `slave/clean-dsh-recur-r3` | **蒸馏后删** | 完整 diff 保全 |
| `slave/clean-dsh-recur-r6` | **蒸馏后删** | 完整 diff 保全 |
| `slave/dsh-plugin-portable` | **蒸馏后删** | 完整 diff 保全 |
| `slave/fix-push-guard-sustainability-r1` | **蒸馏后删** | 完整 diff 保全 |

**这 4 支 `slave/*` 都删了 `.dsh/fist-mbt-plugin/cordis.patch.yml`，
但 `git cat-file -e main:.dsh/.../cordis.patch.yml` 未命中 ⇒ main 本来就没有 ⇒ 非基线倒退。**

---

## 3. 蒸馏保全清单（`_archive/wt-salvage/`）

| 目录 | 内容 |
|---|---|
| `backlog-proof-restamp/` | `backlog-yaml-restamp.diff`(86 行) + `README.md` |
| `slave-task-list-anchors/` | `slave-tasks-anchors.diff`(67 行) + `README.md` |
| `slave-clean-dsh-recur-r3/` | `full.diff`(1219 行 / 14 文件) + `name-status.txt` + `README.md` |
| `slave-clean-dsh-recur-r6/` | `full.diff`(698 行 / 11 文件) + `name-status.txt` + `README.md` |
| `slave-dsh-plugin-portable/` | `full.diff`(1549 行 / 35 文件) + `name-status.txt` + `README.md` |
| `slave-fix-push-guard-sustainability-r1/` | `full.diff`(1740 行 / 39 文件) + `name-status.txt` + `README.md` |

**另（本报告前一笔提交）**：
`reports/2026-10-25-consolidated-r65-suggest-anchors-salvage.md` —— `--suggest-anchors` 增量全文保全。

---

## 4. 未执行项（诚实清单）

| 项 | 状态 | 原因 |
|---|---|---|
| `fix/agent-fp-honest` | **待蒸馏后删** | 统帅已批「先蒸馏再删」，本批未做 |
| `fix/render-release-priority-master` | **待裁决** | **真基线倒退**：它删了 `sync-from-gitcode.simulate.sh`（main 有） |
| `fix/test-count-1449` | **待判定** | 未在本批三档内单独核（名字看是另一条旧测试数同步，同 `1413` 型） |
| gitcode 剩余 137 支 | 未处理 | 本批只删「双边存在」的 8 支；gitcode 独有支不在本单范围 |

---

## 5. 本批踩的坑与判例产出

### 判例-54（删 A 档 7 支时发现）
**删除报错 ≠ 删除失败**：`remote ref does not exist` 在「删对远端 + ref 已不在」下
= 目标态已达成。⇒ 判「删没删」看不存在的那个东西，不看 rc。

### 判例-58（统帅裁决的删除命令错远端时发现）
**`remote ref does not exist` 的双面性**：
- 判例-54 说的是「删对了远端但 ref 已不在」⇒ **目标已达成**
- 但如果**删的是错远端**，同一句 error 的语义是「**根本没删到**」

⇒ 看到它必须先确认「**我删的是哪个远端 + 那个远端上本来有没有这个 ref**」。
**同一条 error，两种相反的真相。**

**本批实证**：统帅给的命令是 `git push --delete gitcode <br>`，但 32 支里 14 支**只在 origin**。
按原命令会得到 14 次 `remote ref does not exist` 并被误报成「已达成」，**而 origin 上一支没动**。

### 工作量修正（判例-41 同族）
我第一次报「origin 53 支」用的是**本地缓存** `refs/remotes/origin/*`；远端真实是 **46 支**。
⇒ **远端读数必须先 `fetch --prune` 对齐，再看内容。**

### 计数必须脚本算（判例-25 同族）
判例编号面我手算过 `43`→`45`→`46` 三次，每次都错。**改成脚本重算后一次对。**

---

## 6. 执行方式（可复核）

**逐支脚本** `temp/del_branch.sh`：删前先 `git ls-remote --exit-code --heads <remote> refs/heads/<br>` 判存在，
存在才删；不存在报「不存在」而**不报「已达成」**（判例-58 合规）。

**每批输出格式**：
```
<branch> → origin 删 ✓/不存在   gitcode 删 ✓/不存在
```

---

## 7. 来源

- 统帅裁决：A 档 13 支、B 档 7 支、C 档分批、**方案 B（两边都删）**
- δ 的 `reports/2026-10-24-asset-preservation-proof.md` §2.6（17 支 origin-only 三重判据，**本单复用未重做**）
- 判例：1（基线倒退）· 8（tmp_merge_batch 假阳性）· 10（判 rc 不判输出）· 41（远端不可达 ≠ 空）· 54 · 58 · 25（计数脚本算）
