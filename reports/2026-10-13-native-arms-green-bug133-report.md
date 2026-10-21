# 2026-10-13 · native 双臂转绿 + BUG-133 关闭条件首达报告

## 结果摘要

**一句话**：native 双臂长期红（`Reapply BUG-133` 失败→后续步全 skip）的真因是**步序错**，不是
nightly moon 不兼容；改正为 `migrate → reapply → check` 后，CI 上**首次**跑完 native 全链并全绿。

**成对证据**（金条八：同一支 CI，修复前/后各一发，读数逐字）：

| 步骤 | 修复前 (`ci.yml #271`, head `95445ba`) | 修复后 (`ci.yml #278`, head `2229971`) |
|---|---|---|
| `moon update` | success | success |
| `Migrate mooncakes dep manifests` | **不存在该步** | **success**（迁 2 处清单，3 轮收敛） |
| `Reapply BUG-133 sqlite FFI fix` | **failure** `::error::找不到目标 stub.c：…/.mooncakes/mizchi/sqlite/stub.c（先跑 moon update …）` | **success** `已覆写 …/.mooncakes/mizchi/sqlite/stub.c（BUG-133 C stub 修复）` |
| `Check (native)` | skipped | success |
| `Native heap gate (BUG-133 探针当门)` | skipped | **success**：`TALLY {'ok': 12} ｜ crashes=0/12` + `VERDICT: 12 次采样未复现 ⇒ 本步放行` |
| `Test (native)` | skipped | **success：`Total tests: 807, passed: 807, failed: 0`**（`actions/checkout` 干净树） |

**真因（WSL 同版 nightly 实测，`temp/reapply_order_direct.txt`）**：
- `moon update` 之后 `.mooncakes` **根本不存在**（依赖**惰性解包**，update 只更新注册表索引）
  ⇒ 此时 `reapply.sh` 的 `TARGET_STUB` 不存在，fail-loud `exit 1`
  （脚本注释里那句"先跑 moon update 让依赖落地"本身是**误因**——update 并不解包）
- 只有能触发解包的步骤（`moon check`/`moon build`）跑过之后，`.mooncakes/mizchi/sqlite/stub.c` 才出现
  ⇒ 此后 reapply rc=0、`--verify` rc=0

**修正**：`ci.yml` / `fist-ci.yml` 的 native 臂顺序统一改为
`Refresh registry → Migrate(moon check 触发解包) → Reapply BUG-133 → Check (native)`
（`6a3bea4`）。同一提交同时推翻并纠正了我同日早些时候写进 `fist-ci.yml` 的反向注释
（"migrate 须在 Reapply 之后，否则被盖回"）——实测是反的：reapply 只覆写 `stub.c` 一个文件，
不会盖回被迁移的清单格式。

## 对 BUG-133 关闭条件的意义（两格已在同一次会话内达成）

账本 BUG-133 的关闭条件写成**两格**：①`e2e_native_heap_probe --runs 12` **连发 0 崩溃**；
②`git archive HEAD` **干净树**上 `moon test --target native` 全量通过。

**本轮在同一次 WSL 会话、同一棵 `git archive HEAD` 干净树上把两格都测了**（此前从未如此成对测过）：

| 格 | 读数（原件） |
|---|---|
| ① 连发抽检 0 崩溃 | 第 1/2/3 发均 `rc=0`、`TALLY {'ok': 12} ｜ crashes=0/12`（`temp/probe_repeat_direct.txt`） |
| ② 干净树 native 全量通过 | `moon test --target native` **rc=0**、**`Total tests: 807, passed: 807, failed: 0`**、SIGSEGV/core-dumped 命中 **0**（`temp/archive_native_direct.txt`） |

干净树的确按账本点名的 `git archive HEAD` 形状构造（第 2 行实测 `树里 .mooncakes 存在? NO`），
并按修正后的顺序走完 `moon update → migrate(moon check 触发解包) → reapply(BUG-133 stub 修复)
→ moon test --target native`，其中 `reapply --verify` 回 `OK: 目标已是 BUG-133 修复版`。

**账本现状**：`memory/bugs.md` 的 `## BUG-133 … [high] FIXED`（抬头已是 FIXED，非本轮所改——
该文件是并发会话的未提交面，本轮未碰）。**故本报告不再写"关闭条件未闭"这种已过时的判断**；
但也不宣称"本轮关闭了 BUG-133"——这两格是**首次成对实测达成**，而账本转 FIXED 的动作另有其人/其时。
两件事分开记：**证据面（本报告）**与**账本状态面（FIXED，他人所改）**各归各。

**同时修正**：本报告初稿曾写「CI 干净树通过 ≠ `git archive HEAD` 干净树通过，建议补 archive 变体」——
该建议**本轮已执行完毕**（上表第②格即 `git archive` 变体读数），故该疑虑已消。

## 资源消耗

- WSL 隔离副本 4 次（fmt 粒度、步序、镜像、check-vs-fmt），全程不碰共享工作树；
- GitHub API 只读约 12 次 + 3 次 job 日志（最大 2.1MB）；
- 本轮零 `.mbt` 改动（改的是 CI workflow 与报告），未跑本地 `moon test`。

## 任务分配记录

- 指挥官亲自：WSL 复现 → 步序定因 → 两处 workflow 修正 → CI 成对取证 → 报告。
- 未派子代理：判据是「同一支 CI 前后对照」，拆出去反而要重新解释上下文。
- 边界：全程只动 `.github/workflows/*`（干净跟踪面）；`src/**`(92 脏)、`cmd/**`(10 脏)、
  `README/AGENTS/ARCHITECTURE`、`memory/2026-10-13.md`（工作树 375 行 vs HEAD 83 行）均未碰。

## 遗留风险

1. **`Format check` 仍在 ci.yml js,ubuntu 第 7 位红，skip 其后 22 步**（含全部守卫族）。定因与落法见
   `reports/2026-10-13-ci-format-int32-diagnosis-report.md`；落哪条属 owner（改共享 CI 定义）。
2. **BUG-133 关闭条件按账本口径仍未闭**（见上）；本发只是 CI 侧首达，需连发稳定性 + `git archive` 变体。
3. **`fist-ci.yml` 的 js 臂同样卡在 Format check**（其 native 臂已绿）。
4. **js,windows 臂整 job success**，但它的步序里**没有** `Reapply BUG-133`（windows 臂本就不跑 native 链），
   故本报告的步序修正只涉 native 双臂。
5. `js,ubuntu` 的 `HTTP contract self-proof` 已移到 Format 之前并实证 success（`64101be`），
   但它**之后**的守卫族仍被 Format 挡着——「自证能跑」与「守卫族能跑」是两件事，别混读。

## 后续建议

1. **Format 门落法**（owner）：①降为信息步（最低风险，立即解锁 22 步守卫族）；②全面重排并全量测试守
   `Int32` 溢出（最彻底）。B/B′/diff-scoped 三条已实测证伪。
2. ~~补 `git archive` 变体抽检~~ **本轮已执行完毕**（两格均在 `git archive HEAD` 干净树上达成，
   见「对 BUG-133 关闭条件的意义」表）。若账本已转 FIXED，则 J11 那一格（"账上仍 OPEN 时门不许删/挪位"）
   自然失效——本轮 `check_doc_surface` 实测 **PASS、无 J11 命中**，与该口径一致。
3. **给 `Reapply BUG-133` 加一条自证**（已做一半）：本轮已把"目标不存在（依赖未解包）"与"不是修复版"
   两种失败的**提示文案**分清（`5b7fac0`，含"update 并不解包"的正解与 CI 正确顺序指引）；
   仍未加的是**程序化**区分（如按退出码分流 1=未解包 / 2=非修复版），那属可选增强。
4. `e2e_native_heap_probe` 的 `VERDICT` 文案已自带"0/N 不等于已修"的诚实标注，这条纪律保持。

## 超额内容

- 顺带把 `ci.yml` 里那条误导性注释（"先跑 moon update 让依赖落地"）就地改正并写明**惰性解包**的真实机制。
- 顺带发现并纠正我同日写进 `fist-ci.yml` 的反向注释（migrate/reapply 顺序），避免它成为下一颗误导雷。

## 来源

- CI 成对读数：`ci.yml #271`（修复前，head `95445ba`）vs `#278`（修复后，head `2229971`）；
  日志落盘 `temp/ci_old_native.log`、`temp/ci_native278.log`。
- WSL 步序实测：`temp/reapply_order_direct.txt`（update 后 .mooncakes 不存在 ⇒ reapply rc=1；
  migrate 后 stub.c 出现 ⇒ reapply rc=0、verify rc=0）。
- 代码改动：`.github/workflows/ci.yml`、`.github/workflows/fist-ci.yml`（提交 `6a3bea4`）；
  `patches/sqlite-bug133/reapply.sh` 失败提示纠正（提交 `5b7fac0`）。
- 账本口径：`memory/bugs.md` BUG-133（两格关闭条件、`0/N` 是抽样性质、J11 三向对表）。
- BUG-133 两格成对实测原件（WSL 同版 nightly 0.1.20261012，`git archive HEAD` 干净树）：
  `temp/archive_native_direct.txt`（第二格：rc=0 / 807/807 / 信号命中 0）、
  `temp/probe_repeat_direct.txt`（第一格：连发 3 发均 crashes=0/12）。
- 本轮 `check_doc_surface` 实测 **PASS**（J11 无命中，与账本已 FIXED 的口径一致）；
  该守卫此前多轮 FAIL 于 J14/J15，现已由并发会话收口——本报告只如实记录该时点读数。
