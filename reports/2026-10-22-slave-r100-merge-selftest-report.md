# R100 副机自驱：`slave-branch-merge.ps1` 补黑名单自证面（TASK-002 追修）· 2026-10-22

分支 `slave/guard/merge-selftest-r100`，基点 `gitcode/main` = `c03d78c`（开工前 fetch 对表：main 未再前进；
上一单 R99 已推 `slave/guard/patch-caf-idempotent-r99`，R98 已推 `slave/ci/task007-battery-resident-r98`）。

## 结果摘要

- **缺陷在 main 上，是我自己 R97 那一单的后续缺口**：主机 `4822e26` 落地了 cherry-pick 黑名单
  （`$SKIP_EXACT = @('src/ops/moon.pkg','src/ops/rhop_poll.mbt')` / `$SKIP_GLOB = @('src/ops/rhop*.mbt')` /
  `Restore-Blacklisted`），但**没有自证面** —— `git show c03d78c:scripts/slave-branch-merge.ps1 | grep -c SelfTest` = **0**。
  失明的代价我在 R97 实踩过：漏摘 `src/ops/moon.pkg` 直接把 `moon build` 打成 [3002] lexing error。
  换句话说，「名单摘不动」这件事唯一的发现手段是一整次构建崩溃，而不是一行 FAIL。
- **交付**：`-SelfTest` 档。在 `%TEMP%` 里的沙箱 git 仓逐格造违例 → 调 `Restore-Blacklisted` → 断言盘面与索引；
  分叉点在 `$ErrorActionPreference = "Stop"` 之后、任何 fetch/cherry-pick/push 之前，所以 `-SelfTest` 绝不碰真仓。
- **8 格**：黑名单 C1-C5（精确名回退 HEAD / 新增毒文件删盘+删索引 / glob 命中新增件 / glob 命中且有 HEAD 版本时回退 /
  未暂存的工作树不许动手）+ 变异台 M1-M2（把名单改瞎 ⇒ 对应格必须转红，M2 还验「复原后立刻能摘」）+ 沙箱哨兵 S8
  （当前目录必须在沙箱内且没有 `moon.mod`，防止哪天有人在真仓里跑这套断言）。
- 沙箱自带 `user.name` / `user.email` / `core.autocrlf=false` / `core.safecrlf=false`，不依赖全局 git 配置；
  每格前 `reset --hard` + `clean -fdq` 回种子态 —— 后一格的绿不许是前一格的遗产。
- 规模：`scripts/slave-branch-merge.ps1` 284 行 → 512 行，BOM+CRLF 保持（CRLF 511 / bare LF 0）。

## 证据

- 干净件：`SELFTEST OK: 8 格全绿（黑名单 C1-C5 / 变异台 M1-M2 / 沙箱哨兵 S8），沙箱已删`，**rc=0**；
  加固 `New-STSandbox` 之后复跑仍 `grep -c 'OK   '` = **8**、rc=0（日志 `~/r100_selftest.log`）。
- rc=1 控制（仓库外变异件 `~/r100_mutant.ps1`，跑完即删，仓库内零变异件）：把 `Restore-Blacklisted` 里
  `git checkout HEAD -- $f` 换成空操作 ⇒ `FAIL C1 exact-path-staged-reverts-to-head  got=盘面未回到 HEAD 版本`
  ⇒ `SELFTEST FAIL: 1/8 格红 → C1 …`，**rc=1**（其余 7 格不误伤，说明格子之间隔离成立）。
- rc=2 控制两发：`TEMP=`（空）与 `TEMP=Z:\nope`（不存在的盘）都拿到 `SELFTEST BLOCKED: 沙箱种子提交建不起来`，**rc=2**。
  后者暴露了一个真形状：`Join-Path` 在 DriveNotFound 下自己会抛，所以沙箱构造整段进了 try/catch ——
  加固前那一发是裸 `New-Item` 兜住的，加固后两发同档。「尺子无法自证」绝不冒用判红那一档。

## 门禁面（本单改动集实测）

- PS5.1 语法：`Parser::ParseFile` → **TOKENS=3066 ERRORS=0**；同法测 main 基线（`c03d78c`）也是 ERRORS=0，
  所以「能解析」这件事有对表基线，不是我自证自。
- `check_ps_encoding --selftest` rc=0；全量 `PASS PowerShell 编码守卫：9 个 .ps1 全部带 BOM 或纯 ASCII` rc=0。
- `git status --porcelain` 跑完 `-SelfTest` 后只有 `M scripts/slave-branch-merge.ps1` ⇒ 沙箱不污染工作树。
- **预存红（不代修，点名）**：`check_scripts_index` rc=1 —— `check_bug_refs.py` / `fist-pr-automator.py` /
  `fist-task-pool.py` 三支未登记。本单不新增脚本文件，这一格与本单无关（`fist-task-pool.py` 属主机车道）。
- 本单不动 `.mbt`，故未跑 `moon fmt` / `moon test`（无 MoonBit 改动面）；`.mbti` 零接触，不会触发 info 刷脏。

## 任务分配记录

副机本机自驱，单文件、不拆子代理（委派只会丢掉「同一会话里加一行参数即炸」这类现场证据）。
观测全部是本地判据 + 仓库外沙箱，未触碰网络、未推任何人的分支。

## 资源消耗

一次 `-SelfTest` 全档实测在秒级（8 格 × 沙箱 git 操作），可在 CI 里跑；沙箱目录跑完即删。
本轮主要开销在编码/换行纪律：`scripts/README.md`（CRLF 180→188，bare LF 0）与
`memory/2026-10-22.md`（CRLF 20→44）都用 rb→拼 bytes→wb 追加，`git diff --stat` 对表为 +260/−1
（那 1 删是 `param()` 里 `[switch]$DryRun` 补逗号那一行）。

## 遗留风险

1. `Restore-Blacklisted` 只认**索引面**（`git diff --cached`）。工作树里未暂存的同名毒路径不会被摘 —— C5 是
   现状刻画格、不是「已修复」。生产路径成立的前提是 `cherry-pick --no-commit` 的产物为暂存态；若哪天改成
   不带 `--no-commit` 的合并流程，这条边界要重估。
2. `$SKIP_EXACT` / `$SKIP_GLOB` 仍是硬编码名单。`src/ops/rhop*.mbt` 这一支防的是「旧 commit 再带一份同名函数
   ⇒ 重复定义」，但名单本身失明（比如有人改名成 `src/ops/rhopX_*.mbt`）时，M1/M2 抓的是**函数失明**、不是**名单不够全**。
3. `-SelfTest` 目前不在任何电池里：`.ps1` 不在 `run_guards.py` 的 `scripts/*.py` 宇宙内，且 r98/r99 两支都在改
   `run_guards.py`，这里再接一支只会加撞点。接线交回主机在合并序上统一裁。
4. 本单没有动 38 处裸 `git` 调用与 `$ErrorActionPreference = "Stop"` 的组合（BUG-109 那一族形状）。
   harness 内部全部经 `Invoke-STGit`（函数作用域降 EAP），**生产路径仍是原样**。

## 后续建议

- 若要接进电池，正确形状是 `case` 一条 `powershell -NoProfile -File scripts/slave-branch-merge.ps1 -SelfTest`
  （expect=0）而不是裸跑主流程；同时需要一个「PS 可用」的门（本机只有 PS5.1，无 pwsh）。
- 建议把「`param()` 中前一个带行内注释的参数必须补逗号」写进 `scripts/NAMING.md` 同级的 .ps1 工艺条目 ——
  报错位置指向既有行，下一个改这个文件的人会当成基线坏了。
- `slave-branch-merge.ps1` 的 `-SelfTest` 与 r97 分支的 `Invoke-Git`/`Select-SkipPaths` 版**词汇不同**：
  合并时以 main 现名（`$SKIP_EXACT` / `Restore-Blacklisted`）为准，r97 只搬「stderr 改造 + 盘上普查」那几格，
  别整支 pick（已在 R97 报告追记里点名）。

## 超额内容

- 除自证格外顺带把沙箱做成**每格独立**（`Reset-STSandbox`）并加固了 `New-STSandbox` 的异常面 ——
  后者是在跑 rc=2 控制时被 `Join-Path` 的 `DriveNotFound` 逼出来的，属于判据自证过程中长出来的健壮性，任务验收没要求。
- M2 多验了「名单复原后同一违例立刻被摘」，把「名单是承重的、不是装饰」钉成一格而不是靠注释声明。

## 来源

- `scripts/slave-branch-merge.ps1`（本单改动面；`param()` 在第 6-9 行，`Restore-Blacklisted` 在第 20-51 行，
  `-SelfTest` 分叉紧随 `$ErrorActionPreference = "Stop"`（第 276 行 → 分叉在第 279 行））
- `scripts/README.md` 第 167-173 行既有条目（本单在其后追加 R100 段）
- `reports/2026-10-22-slave-r97-task002-cherry-pick-blacklist-report.md`（追记：本单已被主机 `4822e26` 部分取代，
  以及「只搬自证面」的接法）
- `~/r100_selftest.log`（8 格读数）、`~/r100_mutant.log`（rc=1 控制）、`~/r100_baseline.ps1`（基线 Parser 对表件）
- 记忆条目 `project-slave-unit-close-out-traps`（第 5 条锚点编辑、第 12 条 rb/wb 字节追加纪律本轮继续生效）
