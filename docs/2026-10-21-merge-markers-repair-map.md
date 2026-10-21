# 交合并 agent：跟踪面冲突标记修复地图 + 新守卫 check_merge_markers 落地须知

> 分支 `feat/guard-check-merge-markers`（随附新守卫 `scripts/blackbox/check_merge_markers.py`）。
> 本文只交证据与出路，**不代解任何一处冲突**——取哪一侧是主仓合并 agent 的设计裁决。
> 证据基线：`origin/master = c17a7b82`（本文数字均在同一基线复核过；master 正被并发推进——
> 引用前请重跑守卫取最新读数，别照抄本文计数）。

## 一、事实链（逐 commit 实测，已纠正本文早期版本的错误归因）

沿 `--first-parent` 追 `scripts/check_plan_landing.py` 的行首 `<<<<<<<` 计数：

| commit | 时间 | 标记数 |
|---|---|---|
| 8695592a | 13:34 | 0 |
| 2f7ffb69 | **16:23** | **12** |
| 7c9c6476 | **16:23** | **31** |
| 8da5221e（"清掉冲突标记，全部取 theirs"） | 16:35 | 31（未变） |
| c17a7b82（现 master） | — | 31 |

结论（三件被实测钉住的事）：

1. **标记由 16:23 那波 cherry-pick 引入并一路带进 master**（0 → 12 → 31）。
2. **`8da5221e` 那次「全部取 theirs」的清扫没有改善也没有恶化它**（31 → 31）。
3. ⚠ **本 PR 的 commit message 初稿曾写「清扫把标记重新引入本来干净的文件、实测 31→62 递增」——
   该说法是错的，特此纠正**：`62` 出自我把 `<<<<<<<`(31) 与 `>>>>>>>`(31) **两种标记各数一遍**
   当成「递增」，是自己造的读数；而「清扫 re-broke 干净文件」也没有 commit 级证据。
   留这一段不是客套：本仓库这几轮一直在抓「自述无据的绿」，写这条守卫的人自己先把错账摊平，
   否则本文就成了一条新的「红着没人核」的假证据。

**进展补记（c689f027 现 master）**：合并 agent 已把守卫本体并入 master（510b1ff0），但取的是
本文纠正**之前**的版本——故 master 上那段「清扫把标记重新引入干净文件、实测 31→62 递增」的
错误归因至今仍写着；本 PR（fix/guard-docstring-correct-measurement）只改那 3 行 docstring
（逻辑面已用 `strip_docstring` 逐字比对为**完全相同**，零行为改动），并补交本修复地图。
另外 c689f027 声称「解两支守卫的未解决冲突标记」，但其 stat 只含 `scripts/slave-branch-merge.ps1`
一个新文件——**实测现 master 仍 9 个文件带行首标记（与 c17a7b82 完全同一批）**，即那两支守卫
（check_plan_landing 31 块、run_guards 10 块等）并未被解。这正是本守卫存在的理由：
自述与跟踪面实际状态互不核对。

## 二、当前损坏面（c17a7b82，9 个跟踪文件）与候选真源

每个坏文件的 `>>>>>>>` 自己点名了它想合入的那一侧；下表核过这些 named sha 的文件版是否连贯。

| 文件 | 行首标记 | `>>>>>>>` 点名候选（行数/是否 0 标记/能否解析） | 备注 |
|---|---|---|---|
| scripts/check_plan_landing.py | 31 | 095bf312(634,干净,parseOK)｜f73788da(382,干净,parseOK) | 两种实现，需择一或合 |
| scripts/run_guards.py | 10 | f73788da(270)｜095bf312(283)｜88201f69(291)，均干净 parseOK | **三种实现分歧** |
| scripts/check_demo_isolation.py | 4 | 010ad445(257,干净,parseOK) | 单一候选，直接可取 |
| scripts/check_mbti_sync.py | 2 | df8ba1a1(369,干净,parseOK) | 单一候选，直接可取 |
| .github/workflows/ci.yml | 3 | 095bf312(397)｜f73788da(388) | 非 py，择一后须核步骤名/needs |
| docs/agent-map.md | 1 | d610e2f0(83,干净) | 单一候选 |
| src/core/pkg.generated.mbti | 1 | df8ba1a1(154,干净) | 生成面，宜 `moon info` 重生成而非手挑 |
| src/router/pkg.generated.mbti | 16 | 2a0c0ec8(308)｜df8ba1a1(318)｜6c402281(266) | 同上，重生成最稳 |
| scripts/README.md | 17 | 9 个 named sha ⇒ **9 种实现** | 文档索引面，分歧最大 |

**恢复基准（重要限定）**：`16465969`（这波的共同祖先）上，上述 8 个文件 0 标记且 `.py` 皆 parseOK
（`scripts/README.md` 当时 3 处，非 0）。但请注意：它是**合并前**的状态，
**不含这波 cherry-pick 想带进来的特性**。所以：

- 想要「立刻恢复可跑」⇒ 取 `16465969` 版（代价：这一波意图丢失，需重做）。
- 想要「保留这一波的特性」⇒ 取该文件 `>>>>>>>` 点名的 named sha 版（候选都是 0 标记 + parseOK），
  但多候选=多实现的文件（run_guards 3 种 / README 9 种 / check_plan_landing 2 种 / ci.yml 2 种）
  是真的集成决策，**不是 `git checkout` 一条命令能代替的**。
- 取完后**务必跑该守卫自己的 `--selftest` 复验**（别只看 `解析OK`——这几轮的教训是
  「语法过 ≠ 判据对」）。

## 三、新守卫的自证（可在任意基线复跑）

- `--selftest` 5 格全绿：C1 干净不误红 / C2 未解决冲突必红且不牵连干净文件 /
  C3 半截标记必红 / C4 行内提及不误红 / C5 空扫描必自拒；计数从已执行格子反解，不手写。
- 真跑 c17a7b82 的 worktree ⇒ **exit 1**，逐条点名上述文件与各自计数。
- 退出码契约三档都有路径（实测）：绿=0 / 违例=1 / 不在 git 仓库=**2 自拒**。
- 变异敏感性：删半截分支⇒C3 红；空扫描改成报绿⇒C5 红；去行首锚定需**同破 regex `^` 与
  `.match` 两道冗余**才让 C1/C4 红（单改任一条不失效——锚定是冗余锁，不是死码）。
  另记一次失败尝试：`match→search` 单独改是 **no-op**（模式里已有 `^`），所以它「不被抓到」
  不是锁弱，而是那条变异根本没改变行为。

## 四、落地须知（否则新守卫上线即空转）

1. **它必须被真正跑起来**：`scripts/run_guards.py`（CI 守卫跑批器）自己现在带 10 处标记 ⇒
   **整套守卫当前在 CI 跑不起来**。先按上表恢复 run_guards.py，再把本守卫加进它的清单
   （或直接给 `.github/workflows/ci.yml` JS 轨加一步 `python scripts/blackbox/check_merge_markers.py`）。
2. **先清现场、再挂门禁**：本守卫对上表 9 个文件必然报红（它没错，是把既有欠账显式化）。
   合并顺序上宜先解冲突、再挂门禁，免得把红灯归因错成「新守卫捣乱」。
3. 本文件与守卫都放在**不与主仓既有文件重叠**的路径（`scripts/blackbox/` 新文件 +
   `docs/` 新文件），`check_scripts_index` 的文件级登记面不覆盖 `blackbox/` 子目录 ⇒ 零碰撞。

## 五、我明确没做的事（边界声明）

- **未解任何一处冲突**（取侧=设计裁决，归合并 agent）。
- **未改 `memory/bugs.md` 抬头**：并发合并 agent 正高频写它，我另开编号会撞车；
  且 `report_bug` 通道此刻因 `src/server/*.mbt` 带标记导致 cli.js 无法重建而被 BUG-32 新鲜度门
  如实拒绝——我**没有绕过这道门去手编账本充数**。
- **未碰 `master`**：全部产物在独立 topic 分支 `feat/guard-check-merge-markers`（origin+gitcode 两镜像），
  等 PR/合并。为纠正第一节的错误归因，本分支被我自己 `--amend` 重写过一次（只动我自己的未合并分支，
  不涉及主仓）。
