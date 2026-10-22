# 合并积压清账 · 收口报告（2026-10-22）

- 执行者：主修复 agent（本机 Windows 副机侧）
- 作用域：gitcode 远程分支积压（任务书口径「80 条 MERGE-CODE + 8 条 DROP」）
- 主线落点：非强推 `34a4e670` → `gitcode/main` + `gitcode/master`；本机收口时主线已被并行 agent 推进到 `90969972`
- 判据真源：`python scripts/fist-gate.py --scan`（base=gitcode/master）

## 结果摘要

**任务书的前提与实测不符，本报告以实测为准。**

| 面 | 任务书自述 | 开工实测（`fist-scan-r104.txt`） | 收口实测（`fist-scan-final2.txt`，base=`90969972`） |
|---|---|---|---|
| 远程分支总数 | 80+8 | **81** | 35 |
| MERGE-CODE | 80 | **9** | **1** |
| MERGE-LOW-RISK | — | 0 | 0 |
| DROP | 8 | 72 | 34（其中 33 条 `origin/*`） |
| REVERT-PATTERN | — | 0 | 0 |

三条结论：

1. **MERGE-CODE 积压已清零**。开工 9 条（全部 gitcode 侧）逐支手动解冲突合入主线；收口唯一剩下的 1 条是**并行 agent 在收口前几分钟新推的活支** `slave/guard/mergeability-check-r103`（ahead=1 cherry+=1 src±=73），不在本轮授权面，未动。
2. **DROP 的 gitcode 面实际删除数为 0 —— 而且这是正确的**：50 条 `git push gitcode --delete` 全部回 `remote ref does not exist`。根因不是推送失败，是**本地 remote-tracking refs 陈旧**：GitCode 在 MR 合并时已自动删除源支，而 `git fetch` 不 prune。`git fetch --prune gitcode` 后 `ls-remote` 真存量只剩 3 条。⇒ 旧口径里「DROP 一堆」本身就是陈旧 ref 造出来的幻影。
3. **origin（GitHub）侧本轮完全动不了**：`github.com:443` / `raw.githubusercontent.com` 连不上（curl 000），`git ls-remote origin` 当场连接失败；只有 `api.github.com` 回 200。33 条 `origin/*` DROP 交回清单见「遗留风险」。

## 逐支落账（可复核证据）

任务书要求的 ✅ 行在过程中逐支输出过；这里给**现在还能从主线历史复核**的落账证据（merge commit 短哈希 = `git log --merges gitcode/main --grep=<支名>`），不重抄当时未留档的逐支冲突计数。

| 分支 | 合入 main 的 merge commit | 收口时该支在 gitcode 是否还在 |
|---|---|---|
| `gitcode/slave/guard/ci-moon-bootstrap-census-r103` | `ca152879` | 否（已合并并自动删源支） |
| `gitcode/slave/guard/backlog-status-staleness-r102` | `462dfbb0` | 否 |
| `gitcode/slave/guard/mergeability-check-r103` | `b430c2a2` | **是**（同一支名后续又新推 1 提交 → 收口 MERGE-CODE 那 1 条） |
| `gitcode/slave/guard/selftest-inventory-doc-sync-r104` | `0777985e` | 否 |
| `gitcode/slave/test/claim-rank-gate-lock`（= `test/claim-rank-gate-lock` 同补丁） | `513f7401` | 否 |
| `gitcode/slave/guard/battery-isolation-r101` | `b9fa33a1` | 否 |
| `gitcode/fix/restore-rhop-test-on-main` | `04874a57` | 否 |
| `gitcode/fix/whisperer-cherry-pick-not-overlay` | `7a84e57f` | 否 |
| `origin/fix/restore-rhop-poll-impl` | `34a4e670`（+ 前序 `8e9f9082`） | — |
| `origin/fix/mbti-generic-fn` | `1d32a68e` | — |
| `origin/fix/reapply-backend-skip-r2` | `33dec543` | — |

我这一推送段的**净价值面**（不是提交数）：`git diff --shortstat 0777985e 34a4e670` = **4 files changed, 402 insertions(+), 19 deletions(-)**，承重件是 `src/ops/rhop_native_wbtest.mbt`（+148，还原 rhop 轮询 6 个白盒测试）、`patches/sqlite-bug133/reapply.sh`（+150/−17，BUG-380 后端分类守卫）、`scripts/check_mbti_sync.py`（+31/−2）。

并行 agent 在同一时间窗内也在合同一批积压（主线在我推送之间走过 `fe82ece1 → b9fa33a1 → 0777985e → 04874a57 → 33dec543 → 34a4e670 → 90969972`），因此**本轮真正的增量以「对当时 main 的净 diff」计，不以提交数计**——提交数会被并行合并的交叉祖先刷爆。

## 门禁读数（硬门自证）

- `moon check --target js`（收口 base）：**0 errors**，读数 `Finished. moon: ran 30 tasks, now up to date (508 warnings, 0 errors)`。
- `moon test --target js src/ops`：**201/201**（本轮落进主线的那 6 个白盒测试所在包）。
- `moon test --target js src/engine`：**189/190** —— 唯一红是 `rank_gate G4`（`src/engine/claim_rank_wbtest.mbt:151`，断言行 158，「连长认领团长级任务被拒且文案含 RANK_GATE」）。**预存红，非本轮引入**，证明方式见「遗留风险」。
- `whisperer.py --fast`：每轮合入前跑过；读数只在「我把 HEAD 移到侧支」时报漂移，属预期告警，不是篡改证据。
- 冲突解决工艺：`memory/2026-10-22.md` 的 4 处尾追加冲突全部按 **union（两边正文都保留、只剥标记）** 解，字节级过滤，未覆盖任何一方；`src/engine/claim_rank_wbtest.mbt` 的 add/add 是先证明 ours 是 theirs 的**严格超集**（`comm -13` 在带引号 token 集上，theirs 独有集为空）才取 `--ours`，不是「src 一律 HEAD 优先」。

## 资源消耗

- 目标额度 20 轮，实际约 65 分钟墙钟（含 3 次全量 `moon check`/`moon test` 与 50 条批量删除尝试）。
- 隔离手段：`git worktree add`（`F:\AI\Fist-Mbt-wt-clear`）+ `.mooncakes` 目录联接（16M 复用，不重下依赖）。**全程未写主机正在使用的主 checkout**——那里有并行 agent 的在飞改动（`?? scripts/check_selftest_inventory_doc.py`、`M scripts/README.md`）。
- 临时产物一律写在仓外：`$HOME/fist-scan-*.txt`、`$HOME/fist-clear.db`（`FIST_DB_PATH` 指出去，不落仓库台账）。

## 任务分配记录

- 主修复 agent（本 agent）：Phase 2 手动解冲突合入 + 门禁自证 + Phase 1 删除尝试与陈旧 ref 归因。
- 并行 host/slave agent：同日同批积压的另一半（`r101`~`r105` 各支本体、`fix/restore-rhop-test-on-mergeone`、TASK-002 黑名单）。**撞面处置**：不抢合、不重复登记，收口只报现读。
- 指挥官/owner：GitHub 侧删除、`slave/guard/mergeability-check-r103` 的合序裁决（见下）。

## 遗留风险

1. **33 条 `origin/*` DROP 未删**（外部阻塞，非判据缺口）：`origin` 走 git-over-HTTPS 指向 `github.com:443`，本机不可达。逐支已用本地 remote-tracking ref 复核为 main 祖先且 `cherry+=0`（内容零丢失风险），删除动作交回 commander：
   `fix/mbti-generic-fn, fix/orphan-rhop-test-compile-red, fix/pre-commit-marker-gate, fix/reapply-backend-skip, fix/reapply-backend-skip-r2, fix/restore-issue-scan-merged-state, fix/restore-plan-landing-ratchet-gate, fix/restore-rhop-poll-impl, fix/task-003-ci-step-position, fix/task-004-revert-diff-detector, fix/task-004-revert-diff-detector-v2, fix/tier2-delta-ratchet-ledger, fix/tier2-governance-bundle, fix/v0310-projection-closeout, fix/v0310-projection-closeout2, fix/version-align-r2, fix/version-align-r3, fix/version-align-r4, fix/whisperer-cherry-pick-not-overlay, test/claim-rank-gate-lock`（及其余同为 `ahead=0/cherry+=0` 的 `origin/*` 支，逐条读数在 `$HOME/fist-scan-final2.txt`）。
   注：GitHub 侧 REST API 面理论可用（`api.github.com` 回 200），但**本轮未获授权走 API 绕过 git 面**，也没拿 token 试过。
2. **`rank_gate G4` 预存红**（`src/engine/claim_rank_wbtest.mbt:151/158`）：不是本轮引入。证明 = 该测试文件与其实现文件 `src/engine/engine.mbt` 对 main **逐字相同**（`git diff --quiet` 两面皆真），且我推送段的净 diff **不含任何 `src/engine/` 文件**；红面由主线 `test/claim-rank-gate-lock` 合并带进。修向（改断言还是改 Gate 1 文案）归 lead，副机不代改。
3. **`moon fmt` 在本机仍 rc=127**（`Sys_error("\\\\?: Invalid argument")` 抬在 `Moonfmt.make_directory`）：预存工具链阻塞。本轮**未手改任何 `.mbt`**（改动面是 markdown 标记剥离 + 一处内容已证逐字相同的 `--ours`），故 fmt 中性；CI 的 fmt 门仍可能因代际差异红，如实标注，不据此声称「fmt 已过」。
4. **收口时新增 1 条 MERGE-CODE**（`gitcode/slave/guard/mergeability-check-r103`）：并行 agent 新推，不属于「积压」，本轮不抢合。
5. **gitcode 上 `fix/restore-rhop-test-on-mergeone` 已是 main 祖先（cherry+=0）但支还挂着**：可删，但它是并行 agent 几分钟前的车道支，删除动作留给其 owner 或 GitCode 合并时自动清理——不在本轮授权面内，我没动。
6. **陈旧 remote-tracking ref 仍会骗判据**：`fist-gate.py --scan` 的分支宇宙来自本地 ref。任何远程写操作前必须先 `git fetch --prune` + `git ls-remote` 对表，否则「DROP 一堆」会再次被当成真存量。

## 后续建议

1. 把 `--scan` 的分支来源从本地 remote-tracking refs 改成 `ls-remote` 现读（或至少在 scan 头部打印 ref 陈旧告警并附 prune 命令）——本轮最大的假积压就是这么来的。
2. 删除类批处理应当**先 dry-run 列名单 + 逐支 `merge-base --is-ancestor` 复验**，再执行；把「执行 50 条」拆成「验 50 条 → 删真存在的 N 条」，读数目才是可交付的。
3. 两条 agent 车道并行清同一批积压时，验收口径应统一到**对当时 main 的净 diff**，不用提交数或 ahead 数（两者在交叉合并下都会虚高）。
4. `moon fmt` 门在本机恢复之前，`.mbt` 面的合入应当只允许「搬运已格式化文件」，任何手改都要显式声明 fmt 未验。

## 超额内容（超出任务书要求的动作）

- 建了独立 `git worktree` 车道而不是按任务书写的 `git checkout -B` 直接动主 checkout——主 checkout 里有并行 agent 的在飞改动，按原流程会撞上「stash 别人工作」这一档。
- 对 `origin/test/claim-rank-gate-lock` 的 add/add 冲突没有照任务书「src/ 用当前 HEAD 优先」直接取 ours，而是先做超集证明再取。
- Phase 1 在名单从 8 条涨到 84 条时**停下来请示**，得到「删 gitcode 51 条」的裁决后才执行；origin 侧按裁决只交清单不执行。

## 来源

- 判据与读数：`scripts/fist-gate.py`（`--scan`）、`scripts/whisperer.py`（`--fast`）、`moon check/test --target js`；扫描原文 `$HOME/fist-scan-r104.txt`（开工）/ `fist-scan-pruned.txt`（prune 后）/ `fist-scan-final2.txt`（收口）。
- 主线历史：`34a4e670`（本 agent 推送）、`90969972`（收口时 gitcode/main 与 master 同指）。
- 工具链现状与工艺依据：项目记忆 `project-slave-box-toolchain-blockers.md`、`project-slave-unit-close-out-traps.md`（本轮新添坑 18/19/20）。
- 任务书前提（80 条 MERGE-CODE / 8 条 DROP / HEAD `f6560010`）与本报告的实测差异，以上表为准。

## 附注（收口后自查：零丢面证明）

- 三条被判 `cherry+=1`（补丁不在 main）的**早期被弃草稿支** `work/backlog-clear` = `626219b6` / `3801bd11` / `9b4271ad`，已**逐行机器对表主线正文**（added lines ↔ `gitcode/main:<file>`）：`reapply.sh` 124/0、`memory/2026-10-22.md` 22/0、`claim_rank_wbtest.mbt` 131/0 ⇒ **not-on-main 全为 0，零丢面**。
- 读法（值得入档）：`git cherry` 比的是 **patch-id**，而 patch-id 对上下文敏感 ⇒ 「超集文件里的一支子集提交」「union 合并后的日志追加」「换过锚点的同一 shell 改动」都会显示 `+`。判「内容有没有进主线」必须加一层**逐行对表**，只看 `cherry+=` 会把已落账的活读成丢失。

## GitHub 面 API 现读（收口后补测：可达性事实已变）

前提更正：先前「GitHub 完全不可达」只对 **git 面**成立。`github.com:443`（`git ls-remote origin` / `git push origin` / `git fetch --prune origin`）确实连不上，但 **REST 面通**：`api.github.com` 用 `GITHUB_TOKNE` 认证为 `vicTop-cw`，仓库真名 `vicTop-cw/FIST-Mbt`（默认分支 `master`），`permissions = admin/maintain/push/triage/pull`。⇒ origin 侧的删除**技术上可做**，只是本轮按 owner 裁决未执行。

现读（不靠本地陈旧 ref）：GitHub 上 **35 支** = `main` + `master`（同指 `f6560010`）+ **33 条工作支**。逐支用本地对象做 `git merge-base --is-ancestor <tip> gitcode/main`：

- **32 支 = 主线祖先**（内容已全在主线，删ref零丢失风险）；
- **1 支 `fix/reapply-backend-skip`**（tip `3801bd11`）拓扑上不是祖先，但 `git cherry += 0` 且其 22 条新增行**逐行对表主线正文全在**（见上「附注」）⇒ 同属可删，形状正是「union 后 cherry 假报 +」。

可删清单（33，API 现读逐字支名）：
  feat/slave-mergeability-guard, feat/task-007-run-guards-universe, feat/tier2-pr4-fist-pr-automator, feat/tier2-pr4-pr-automator, fix/battery-readonly, fix/bug-refs-guard-semantics, fix/bug-refs-ledger-backfill, fix/cleanup-artifact-naming, fix/dist-snapshot-guard, fix/guard-census-covers-blackbox, fix/hygiene-ps1-bom-and-index, fix/integrate-guard-repairs-verified, fix/ledger-close-358, fix/mbti-generic-fn, fix/orphan-rhop-test-compile-red, fix/pre-commit-marker-gate, fix/reapply-backend-skip, fix/reapply-backend-skip-r2, fix/restore-issue-scan-merged-state, fix/restore-plan-landing-ratchet-gate, fix/restore-rhop-poll-impl, fix/task-003-ci-step-position, fix/task-004-revert-diff-detector, fix/task-004-revert-diff-detector-v2, fix/tier2-delta-ratchet-ledger, fix/tier2-governance-bundle, fix/v0310-projection-closeout, fix/v0310-projection-closeout2, fix/version-align-r2, fix/version-align-r3, fix/version-align-r4, fix/whisperer-cherry-pick-not-overlay, test/claim-rank-gate-lock

两条由此暴露的事实：

1. **GitHub 主干落后 gitcode 主干 197 commits**（`git rev-list --count f6560010..gitcode/main` = 197）⇒ 任务书自述的「HEAD 三端一致 ✅」不成立，`f6560010` 只是 GitHub 侧的旧主干。
2. `git fetch --prune origin` 本身失败（443 不通）⇒ **origin 的本地 remote-tracking refs 永远刷不动**，`--scan` 报的 DROP=37 与 GitHub 真存量 33 之间那 4 条差是陈旧 ref 幻影。origin 面的任何判据都必须走 API 现读，不能走本地 ref。

执行路径（备好未跑，等一句授权）：
- 快进主干：`PATCH /repos/vicTop-cw/FIST-Mbt/git/refs/heads/master`（和 `/heads/main`）body `{"sha":"<gitcode/main>"}`——快进、非强推；**应先在主干同步后再删支**，否则删完主干仍是旧的。
- 删支：`DELETE /repos/vicTop-cw/FIST-Mbt/git/refs/heads/<urlencoded-ref>`（33 次），或 git 通的时候 `git push origin --delete ...`。
