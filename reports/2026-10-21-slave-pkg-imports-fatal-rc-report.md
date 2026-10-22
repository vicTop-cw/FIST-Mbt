# 2026-10-21 R44 汇报：`slave/guard/pkg-imports-fatal-rc` —— 修掉 BUG-369 的第三把尺，棘轮 8→1（T0r25）

> 副机（slave-guard）自迭代第 R44 轮。上游立案：`memory/bugs.md` BUG-369（建议① 逐份修尺 / 建议② 立常驻判据）。
> 本轮一句话：**把「自述 2=判据无法自证」而实给 1 的第三把尺 `check_pkg_imports` 修成真给 2，
> 并把 `CONTRACT_GAP_CEILING` 从 8 降到 1 —— 降棘轮的那一步被自己冻在 selftest 里的旧数字咬了一口，
> 于是又多了一条定律。**

## 结果摘要

1. **判据改动面（承重件）**：`scripts/check_pkg_imports.py` 新增 `emit_fatal()`（写 stderr 后 `return 2`），
   6 处串式 `raise SystemExit("FATAL …")` 全改为 `raise SystemExit(emit_fatal("FATAL …"))` —— 站点是
   git 不可调用 / `git ls-files` 退出码非 0 / 清单为空 / 跟踪面一份 `moon.pkg` 都没有 / 读不到任何正文 /
   全仓一条本地 import 都没有。`emit_fatal` 的 docstring 把「带字符串的 SystemExit 只打印文本、给 1」写死。
2. **自测 6 格 → 8 格**：新增 `emit-fatal-returns-2`（函数返回值）与 `fatal-unusable-git-rc-is-really-2`
   （起子进程：`spec_from_file_location` 载入本份、`m.ROOT` 指到非仓库临时目录使 `git ls-files` 必失败，
   断的是**进程退出码**）。两格并存的理由写在注释里 —— 返回值对而 rc 错正是 BUG-369 的原始形状。
   实测 `--selftest` rc=0、不带参全量 `PASS 本地包 import 存在性一致：24 份 moon.pkg 的 30 条本地 import`。
3. **棘轮 8 → 1（现读，不是估）**：`scripts/check_exit_code_contract.py` 全量读数 = 宇宙 85 份 `scripts/**.py`
   （解析跳过 0）、32 份有 `N=` 契约块、**判定面 1 条 = 新 `CONTRACT_GAP_CEILING`**、只报不判 S 21 ｜ U 37 ｜ O 1。
   剩的 1 条是 `simulate_head_commit` 的 R3 半形。`--selftest` 27 → 28 格。
4. **搬家定律回对（R43 立的律，本轮兑现）**：判定面少 7 条，先回头对 O/S/U 三面 —— 三面数字一格未动，
   `check_pkg_imports` 从 R1/R2 列表里划掉、实现面 `impl` 现含 2 ⇒ 这 7 条是**真消失**而不是靠让位逃掉。
   为此新加一格 `fixed-ruler-gives-two-in-impl-face`：四把修过的尺（plan_landing / template_ctrl / mbti_sync /
   pkg_imports）的 ast 实现面必须真给得出 2，「判定面归零但实现面给不出 2」那种半修好会被点名（实测「缺的是 无」）。
5. **变异台 14 支全命中期望**（`temp/r44_mutation.py`，只在内存改文本）：C1 HEAD 真语料 7 条（R1+R2）｜
   C0 工作树 0 条｜M1 只回退 1 处站点 ⇒ 只剩 1 条 R2｜M2 全回退 ⇒ 7 条｜M3 只把 `return 2` 换回 `return 1`
   （承诺与文案全不动）⇒ 6 条 R2 + 恰 1 条让位留名｜M4 承诺面删 `2=` ⇒ 判定 0 条、只进 S 面｜
   M5 FATAL 关键词换中文同义词 ⇒ 不改类判定｜C2 加注释 / C3 动 stderr 写法 / C4 摘 README 条目切片 ⇒ 读数不变｜
   N1 全回退后实现面掉 2｜N2 上限 0..9 扫描 `verdict_rc` 与 `hint` 单调｜N3 用反例钉死旧硬编码格子在新上限下必然红。
   **M3 的期望是 R43 写下的预测，本轮实测与预测同向。**
6. **本轮新雷（已按实测改写并升成定律）**：降棘轮把两条硬编码旧存量的老格子当场判 FAIL（合成量 4 vs 新上限 1；
   `hint(3, 1)` 读到「FAIL」而格子要求「收紧」）。断言改为全部从 `CONTRACT_GAP_CEILING` 推导（合成量取 `at`/`at+1`），
   并给 `at == 0` 留独立分支 —— R45 清零时不必再改格子。定律入 `docs/agent-map.md` §五：
   **自测格子里的每个数字要么来自常量、要么来自实测**。同一条律也收回了判据自己印的 `SELFTEST OK（…）` 行：
   原先按分类写死「6｜4｜3｜2｜5｜1｜4」，加一格就与 `len(cells)` 不自洽 ⇒ 现在只印可导出的两个数
   （总数 `len(cells)`、`calib:` 前缀格数现数），分类名保留、分类数删除。
7. **金条八实跑**：`moon test --target js -j 1` = **Total tests: 1302, passed: 1302, failed: 0**；
   `moon check --target js --json` = **489 warning / 0 error**、stderr 空，逐 (level, title, path) 与基线
   `temp/chk47.json` **求差集为空**（本单零 `.mbt` 改动）。BUG-330 如期复现（23 份 `.mbti` 判脏、18 份
   `Int`→`Int32` 纯拼写差 237/237），按 BUG-342 note③ 约定 `git restore -- '*.mbti'` 收回、未入提交；
   还原后 `check_mbti_sync` PASS（24 份 / 654 条 pub 声明 / 6 形状）。
8. **执行面与文档面**：`run_guards.py` 电池 **37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0**（`temp/g30.txt`）；
   `check_doc_surface` / `check_scripts_index` / `check_badge` / `check_test_sync`（带日志）全绿；
   `scripts/README.md` 的 pkg_imports 条目就地改标「R44 已修真」并记变异台 14 支，contract 条目同步真源读数与 28 格；
   `memory/bugs.md` BUG-369 追加 `landed[2026-10-21 R44]`（本单仍 OPEN，只剩一把尺）。

## 资源消耗

| 项 | 值 |
|---|---|
| 模型 | qoder-agent（副机 slave-guard） |
| tokens in / out | 约 108,000 / 12,400 |
| 估算成本 | ≈ 0.33（本地推理计费口径，与 R42/R43 同尺度） |
| 时长 | ≈ 540,000 ms（含 `moon test` 与 `moon check` 各一次全量、变异台 14 支、电池 37 格复跑） |
| 命令次数 | 守卫/自测/变异台 12 次、`moon test` 1 次、`moon check` 1 次、git 读 6 次 / 写 3 次（add + commit + push） |

## 任务分配记录

| 任务 | 承接 | 状态 |
|---|---|---|
| R44 全部改动（`check_pkg_imports` 修码 + 两格自测 + 棘轮 8→1 + 承重新格 + 变异台 + 文档面同步 + 金条八复跑） | 副机 slave-guard | 已完成，本轮提交 |
| BUG-369 最后一把尺 `simulate_head_commit`（R3 半形，上限 1→0） | 下一单 `T0r26` | 待发布 |
| README 条目行内 `N=` 承诺面（开启后判定面 16→39，新增 10 份面真伪未核） | 未排 | 待指挥官定优先级 |
| MR 开启动作（R41/R42/R43/R44 四条分支） | owner（人类指挥官） | 副机只推分支 + 给入口链接 |

## 遗留风险

1. **`CONTRACT_GAP_CEILING` = 1 只锁住「最后一把尺」**：本轮把棘轮降到 1，意味着 R45 之后任何新脚本只要写一句
   `2=判据无法自证` 而给不出 2，就会顶穿上限变红 —— 这是想要的行为，但**降上限的人必须先确认那 1 条已归零**，
   否则 R45 会同时背着旧账和新账。
2. **`emit_fatal()` 的形状在各尺间还没统一**：三份尺（template_ctrl / mbti_sync / pkg_imports）各写一份同名函数，
   行为一致但没有共用件。共用件会引入「尺依赖尺」的新耦合（谁改了公共件，另两份的自测就可能一并按住不动），
   本轮刻意保持三份独立副本 + 各自锁一格；这是权衡，不是遗漏。
3. **O 面那条不透明件（`scripts/fist.py` L287 `exit_code`）仍是「只报不判」**：它靠 `has_external` 让位机制逃出判定面，
   读数是诚实的，但「让位」与「修好」在实现面上无法区分 —— 本轮用 `fixed-ruler-gives-two-in-impl-face` 补了
   「修过的尺」那半边，未修过的尺仍只能靠留名。
4. **BUG-330 `.mbti` 拼写抖动仍在**：本轮又收回一次。全仓 `moon fmt`/`moon info` 的一次性对齐是更大的决定，
   按金条四留给指挥官。
5. **cleanup 预存红随取证增长**（663 → 664 → 665 → 669）：它按声明期望值命中、不判失败，但绝对数在涨，
   真要做清理需要单独一轮（temp/ 里本轮又落了 `r44_mutation.py` / `r44_full.txt` / `t24_drive.py` / `g30.txt` / `chk44.*` / `test44.log`）。
6. **`.githooks/pre-commit` 的 `core.hooksPath` 仍未设置**：本地提交面依旧是空的，本轮所有绿都靠显式复跑 + CI 门。

## 后续建议

1. **R45 题目**：`simulate_head_commit` 的 R3 半形 —— 4 处 FATAL 改真给 2（其中一条文案自写「（rc=2）」，
   改完那条文案就不再是谎），`CONTRACT_GAP_CEILING` 1→0，并把「上限为 0」这条分支的自测格子从建议变主力。
2. **给「让位」与「修好」分个类**：在 `check_exit_code_contract` 的 O 面读数里加一列「这份脚本的 `impl` 是否含 2」，
   让「外部件透传但别处真给 2」与「外部件透传且全份给不出 2」在账上就长得不一样。
3. **README 条目行内 `N=` 开不开，要有决策而不是默认**：实测开启把判定面从 16 推到 39（R43 时点数据），
   新增 10 份面没核真伪 —— 建议单列一轮「先核 10 份、再决定开」，别在修尺的轮次里顺手开。
4. **把电池整块挂 CI 需要处理 3 条已知红格**（`cleanup_artifacts` / `check_plan_landing --gate` / 其它声明红），
   要么给它们 `continue-on-error` + 显式标注，要么在 CI 侧复制「期望值命中不算失败」这套语义。
5. **`git restore -- '*.mbti'` 该有个守卫**：现在是约定俗成，一旦有人忘了，`.mbti` 的 237 处纯拼写差会伪装成
   「接口变了」进 diff —— 值得一个小判据（判「只有 `Int`→`Int32` 对偶差 ⇒ 提示收回」）。

## 超额内容

- 新增一格 `fixed-ruler-gives-two-in-impl-face`（任务只要求修尺 + 降棘轮，这格是把 R43 的搬家定律固化成机器核）。
- 变异台做到 14 支（R43 是 11 支），其中 N1/N2/N3 三支是为「降棘轮」这个动作本身新增的对照面。
- 一条新定律 + `docs/agent-map.md` §五 的两处更正（把普查记录标注为「当时形状」，避免下轮误读成仍在违例）。
- `--selftest` 的 28 格计数、`hint`/`verdict_rc` 的 0..9 扫描，都是任务未要求但为了「R45 不再咬自己」补的。
- 未做（也刻意不做）：`emit_fatal` 共用件化、README 行内承诺面开启、`.mbti` 拼写守卫 —— 都记进了上面的建议，不在本轮偷跑。

## 来源

- 任务包：FIST `T0r25`（根任务链 `T0r22` → `T0r23` → `T0r24` → `T0r25`），立案条 `memory/bugs.md` BUG-369。
- 判据与读数：`scripts/check_pkg_imports.py`（8 格自测）、`scripts/check_exit_code_contract.py`（28 格自测 + 全量读数）、
  `temp/r44_mutation.py`（14 支变异台）、`temp/g30.txt`（电池 37 格）、`temp/test44.log`（`moon test` 1302/1302/0）、
  `temp/chk44.json`（`moon check` 489/0，与 `temp/chk47.json` 差集为空）。
- 定律面：`docs/agent-map.md` §五（R44 新增「自测格子里的每个数字要么来自常量、要么来自实测」；
  同节 R42/R43 那几条本轮做了现状更正）。
- 规范面：`AGENTS.md`（金条四/五/八）、`docs/SOP.md:33`（禁止 `git add -A`，逐路径 staging）。
- 上游轮次：`reports/2026-10-21-slave-mbti-sync-fatal-rc-report.md`（R43）、`memory/2026-10-21.md` R42/R43 两段。
