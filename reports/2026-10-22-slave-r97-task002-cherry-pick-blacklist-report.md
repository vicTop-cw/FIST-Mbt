# 汇报 · 2026-10-22 · 副机 R97 —— TASK-002 cherry-pick 黑名单（`slave-branch-merge.ps1`）

**分支**：`slave/ci/task002-cherry-pick-blacklist-r97`　**基点**：`gitcode/main` = `99bacbe`（未叠 r96）
**任务真源**：`docs/tasks/backlog/TASK-002-cherry-pick-blacklist.yaml`（P1，`discovered_by: lead`，status 仍 `backlog`——
按本仓惯例由 lead 盖章，副机不自封 `done`，交付证据在本报告与当日日志）

## 结果摘要

把合入者一直在做的**手肉纪律**写进脚本：旧 slave commit 里 `src/ops/moon.pkg` 自带冲突标记（pick 进来
`moon build` 报 `[3002] lexing error @offset 134`）、`rhop_poll.mbt` 与 HEAD 的 `rhop_native.mbt` 重复定义必崩，
原先的处置是「cherry-pick 直接 abort，改 `git checkout <branch> -- src/server/xxx.mbt` 选择性拿、全程跳过 `src/ops/`」。

- `scripts/slave-branch-merge.ps1`（+229 / −1）新增 `$SkipPaths`（`^src/ops/moon\.pkg$` + `^src/ops/rhop.*\.mbt$`）
  与 `$PoisonNames`（点名 `src/ops/rhop_poll.mbt`）；命中即 `git reset -q --`（连 unmerged 三态一起清，冲突现场可用），
  HEAD 有的 `git checkout --` 还原、HEAD 没有的删文件，**每条打印 `poison:` / `黑名单:`，不静默丢**。
- 两处接线：pick 循环提交前（干净应用与真冲突两种形状都覆盖）＋ 第 5.5 步盘上兜底普查
  （poison 也可能由 checkout/copy 带进来，不只 cherry-pick 一条路）＋ 汇总行「黑名单处置: N 个文件」。
- 新增 `-SelfTest` 二十格（P1-P11 纯函数 + G0/G0b/G1-G7 `%TEMP%` 沙箱真造 cherry-pick 冲突），零副作用；
  rc 契约 0 全过 / 1 有失败 / 2 尺子自己跑不动（git 或沙箱起不来）——异常绝不冒用 1 那一档（BUG-369 家族口径）。
- 自证三档实测：**干净树 20 过 / 0 失败 rc=0**；**变异①**（族形正则 `rhop`→`NOPE`）13 过 / 7 失败 rc=1
  （P2/P3/P4/P8/G1/G2/G3 同批发红）；**变异②**（把 `rhop_native.mbt` 塞进 `$PoisonNames`）19 过 / 1 失败 rc=1（P11 单发红）。
  三档 ok+FAIL 格数恒等于 20，没有静默跳过的格。

## 资源消耗

- 本单只动 2 个文件：`scripts/slave-branch-merge.ps1`、`scripts/README.md`（条目内插入 12 行）；
  另按金条五追加 `memory/2026-10-22.md`（+14 行，尾追加前后 CRLF 计数对表 20→34、bare LF 0）与本报告。
- 未新增文件、未动 `.mbt`/`.mbti`/账本/插件态 ⇒ 无 `moon fmt`/`moon info` 面；工作树在提交前只有这两件改动。
- 命令消耗：`-SelfTest` 与两支变异台各一次（沙箱建删在 `%TEMP%`，本仓零写入）；快门禁 5 把各一次。
- 全量电池（`run_guards.py` 88 把尺）**本轮未取到读数**：第一次以后台方式启动，任务输出与日志文件都是 0 字节
  （外层 `echo` 让包装层退出码恒 0，属假绿形状，已拒绝当作绿灯引用）；第二次前台跑到超时转后台，仍在跑。
  本单的门禁面以下面逐把尺实测为准，不借用任何未取到的读数。

## 任务分配记录

- 副机（本机）亲自做：读 `TASK-002` 三格验收、设计与落盘黑名单/兜底/自检三件套、跑门禁与变异台、终审。
- 按金条四**不做**的：不改 `docs/tasks/backlog/TASK-002` 的 `status`（盖章权在 lead）；不碰他人 lane；
  不代修别人车道上的预存红（见「遗留风险」）。
- 主机并行面（本轮 fetch 时新见，与本单零文件重叠）：`slave/fix/dist-snapshot-guard`（`9718fee`）、
  `fix/v0310-projection-closeout2`（`e7b1ca9`，v0.3.10 下游投影收口，自称「6 把红尺转绿」）——
  后者若先合，main 的红尺面会变，本报告的两条 rc=1 需按合序复核。

## 遗留风险

1. **`check_scripts_index` rc=1（预存红，非本单引入）**：`check_bug_refs.py`、`fist-pr-automator.py` 未登记。
   这两条的登记正文在我另一条在飞 MR `slave/docs/scripts-index-closeout-r96` 上；main（`99bacbe`）还没有那份正文
   （R95 的 `scripts/NAMING.md` + `check_scripts_naming.py` 同样未合，所以本单基点上那条命名尺连文件都不存在，
   跑它只能得到 rc=2 file-not-found）。**合序 r96 → r97 即转绿**；在 r97 里重复登记会与自家 MR 撞同一面，故不做。
2. **`check_doc_surface` rc=1（预存红）**：`USAGE.md` 自述 0.3.9 ≠ `moon.mod` 0.3.10（真源 170 工具）。
   修法现有两条线：`slave/integrate/r93-on-cef1e9c-r94` 与主机今日在飞单线 `fix/bug-refs-ledger-backfill`（`c27d6e7` 的 J1 补账里同时把 `USAGE.md` 0.3.9 → 0.3.10）。两支与我 r96/r97 **零文件重叠**（merge-tree/diff 实测），任取一份即转绿。副机首稿只点了一条线，是没先 fetch 就写现状。
3. **黑名单是「撤出索引」而不是「拒绝合并」**：命中文件被还原成 HEAD 版本或删除，逐条点名但仍继续跑。
   若某个旧 slave commit 的*唯一*内容就是 poison 面，本单会把它的实质内容清空后照发提交——
   需要「清空即跳过该 commit」时，是策略裁决项（TASK-002 验收没写，副机不自作主张加严）。
4. `-SelfTest` 只在**本机 PS5.1** 验过（本机无 pwsh）。`Invoke-Git` 用临时降 `$ErrorActionPreference` 收原生 stderr
   （BUG-109 那一族），pwsh 7 下语义应一致但未实测，跨 shell 读数需在有 pwsh 的机器补一格。

## 后续建议

1. 合序建议：`r96`（README 三件登记 + NAMING）→ `r97`（本单）→ r94（USAGE.md 版本面）。
   实测 merge 面只有一处：`git merge-tree --write-tree r96 HEAD` 只对 `memory/2026-10-22.md`（同日尾追加）发红，
   `scripts/README.md` **auto-merge 干净**（两支插同一文件的不同 hunk）。冲突两边都留，不许 `--theirs` 覆盖任何一方正文。
2. 若要把「poison 出现在任何 lane」升成硬门，最省的接法是复用本单的 `$PoisonNames`：
   `check_merge_markers` 那条普查族里加一把「跟踪面不得存在 `src/ops/rhop_poll.mbt`」，比在合并脚本里兜底更早一步。
3. `run_guards.py` 里加一把 `.ps1 -SelfTest` 的面（现在 PowerShell 侧的判据不进电池，全靠人跑）。
   本单的 20 格 + 两支变异台正是这种「可被电池调用」的形状：约定 rc=0 绿 / 非 0 红即可接线。
4. **对表主机在飞三支（2026-10-22 实测，`git merge-tree --write-tree`）**：主机今天推了
   `fix/bug-refs-ledger-backfill`（`c27d6e7`）、`fix/v0310-projection-closeout2`（`e7b1ca9`）、
   `fix/dist-snapshot-guard`（`9718fee`），main 仍 `99bacbe` 未前进。与副机三支的冲突面只有**一个文件**：
   - `fix/dist-snapshot-guard` ↔ `r96` ⇒ 红在 `scripts/README.md`；↔ `r97` ⇒ 同处红；↔ `r95` **CLEAN**；
   - `fix/v0310-projection-closeout2` ↔ `r97` **CLEAN**（它也动 `scripts/README.md`，但与本单不同 hunk）。
   即撞点全部集中在 README **文件尾追加**这一族（同「同日尾追加」的老形状）。给 owner 的可执行结论：
   谁先合都可能，但**后合的一侧只需解 `scripts/README.md` 一处尾追加冲突**，两段登记并排保留即可，
   不存在代码面冲突；`r95`（NAMING 第一批）对全部在飞支干净，可最先合。

## 超额内容

- 验收只要求「脚本里有黑名单」，本单额外交付：`-SelfTest` 二十格 + 两支变异台 + 盘上兜底普查 + 汇总计数行。
- 额外抓到并当场改掉自己写的一格：5.5 普查原先用 `$SkipPaths` 扫 `src/ops/*.mbt`，宽族形把 HEAD 的干净实现
  `rhop_native.mbt` 也收进 poison ⇒ 每次跑都打「盘上还留着 … build 必崩」的**假警报**，把合入者引去删对的函数。
  改成兜底面只认 `$PoisonNames`，并补 P10/P11 两格钉住这个区分（变异② 就是专门为这一格做的）。
- 第一版沙箱从 trunk **之后**分叉 poison ⇒ cherry-pick 干净应用 ⇒ G1-G7 全空跑却报绿；补 G0/G0b 两格
  先证明「真造出冲突、且冲突确实落在 moon.pkg 上」。这是本仓「尺子必须先证明自己会红」的同一口径。

## 来源

- 任务真源：`docs/tasks/backlog/TASK-002-cherry-pick-blacklist.yaml`（problem / scope / acceptance / evidence 四段）
- 实现：`scripts/slave-branch-merge.ps1`（`Invoke-Git` / `Test-SkipPath` / `Select-SkipPaths` / `Select-PoisonNames` /
  `Clear-SkipPaths` / `Run-SelfTest` / pick 循环接线 / 5.5 普查）
- 文档登记：`scripts/README.md` 的 `slave-branch-merge.ps1` 条目（含三档读数与 rc 契约）
- 当日日志：`memory/2026-10-22.md` 的 R97 段
- 本机工具链边界：`project-slave-box-toolchain-blockers`（无 pwsh ⇒ PS5.1 `Parser::ParseFile` + `-File` 实跑）
- 门禁读数（本轮逐把实测）：`check_ps_encoding` rc=0（9 个 .ps1 全带 BOM）／
  `blackbox/check_merge_markers` rc=0（1236 跟踪文件）／`check_py_stdout_encoding --all` rc=0（该带闸 88 份 / 已带 88 份）／
  `run_guards --selftest` rc=0（13 格；现状 88 把尺 / CI 面 28 / 电池面 88 / 缺面 0）／
  `check_scripts_index` rc=1（预存红，见遗留风险 1）／`check_doc_surface` rc=1（预存红，见遗留风险 2）
