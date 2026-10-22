# 2026-10-21 R45 汇报：`slave/guard/simulate-head-fatal-rc` —— 修掉 BUG-369 的最后一把尺，棘轮 1→0（T0r26）

> 副机（slave-guard）自迭代第 R45 轮。上游立案：`memory/bugs.md` BUG-369（建议① 逐份修尺 / 建议② 立常驻判据）。
> 本轮一句话：**把四份里唯一的「半形」`simulate_head_commit` 修成真给 2，`CONTRACT_GAP_CEILING` 由 1 降到 0 ——
> BUG-369 立案那批存量清零；同时变异台教了我两件事：条数不衡量坏面，而我自己的替换串少写一个空格造出了一格假绿。**

## 结果摘要

1. **判据改动面（承重件）**：`scripts/simulate_head_commit.py` 新增 `emit_fatal()`（写 stderr 后 `return 2`），
   4 处串式 `raise SystemExit("FATAL …")` 全改为 `raise SystemExit(emit_fatal("FATAL …"))` —— 站点是
   `git status` 失败 / 取不到 HEAD / PATH 上没有 moon / `git archive` 失败；moon 超时那条原本就走 `return 2`，不动。
   其中「PATH 上没有 moon」的文案自写「（rc=2）」而实给 1，就是 R42 判定面上那条 **R3 站点自述码不符**。
2. **自测 0 格 → 5 格**（这份尺此前**没有任何执行面自证**）：`emit-fatal-returns-2`／`promise-face-declares-two`
   （改码不许顺手把承诺删绿）／`no-stringy-exit-site-left`（ast 现读串式站点归零；认 Constant str、JoinedStr、`BinOp Mod`
   三种形状，并排除 `emit_fatal(…)` 的实参）／`fatal-headless-root-rc-is-really-2`（起子进程把 `ROOT` 指到空目录，
   使「取不到 HEAD」那支必失败，断的是**进程退出码**）／`list-mode-exits-0`（`--list` 不误红）。
3. **棘轮 1 → 0（现读，不是估）**：`scripts/check_exit_code_contract.py` 全量读数 = 宇宙 85 份 `scripts/**.py`（解析跳过 0）、
   32 份有 `N=` 契约块、**判定面 0 条 = 新 `CONTRACT_GAP_CEILING`**、只报不判 59 条（S 21 ｜ U 37 ｜ O 1）。
   档位历史 16 →（R43）8 →（R44）1 →（R45）0。`--selftest` 仍 28 格（一格未加：本轮修的是被测尺不是判据），
   `calib:` 五把尺的标定面**全部归零**，`fixed-ruler-gives-two-in-impl-face` 的尺清单由四把扩到**五把**。
   `hint()` 为零上限单开一条文案 —— **上限归零后这门是零容忍，不再有「存量按声明接受」的容忍带**。
4. **三面回对（R43 立的搬家律，本轮结论是「无搬家」）**：判定面少 1 条之后 S 21 ／ U 37 ／ O 1 一格未动，
   本份实现面 `impl` 现含 2 ⇒ 那条是真消失而不是让位逃掉。「回对了」这次是实测结论，不是假设。
5. **变异台 13 支（`temp/r45_mutation.py`）全命中期望，其中两支与我的事前预测不同向，照实测改写**：
   - **M2 四处全改回串式 ⇒ 判定面仍只 1 条**（不是 4 条）。结构性成因：别处那条 `return 2` 顶着 R1、
     承诺句「2=前置不满足」里没有判据失灵类关键词所以 R2 不响 ⇒ **「半形」是结构不是修辞，按条数估坏面会系统性低估**。
   - **M4 连 `return 2` 一起抽掉 ⇒ R1 与 R3 同时现形（预测 1 条、实测 2 条）**。这条正面回答「归零是不是只有一条在承重」：
     两条判据各抓各的，先前都被同一条外部 2 压住。
   - 其余 11 支：C1 HEAD 真语料复现 1 条 R3｜C0 工作树 0 条｜M1 只回退 1 处⇒1 条 R3｜M3 `emit_fatal` 改回 `return 1`
     （文案一字不动）⇒1 条 R3 且让位 0 条｜M5 承诺面删 `2=`⇒判定 0 条而 S 面出 2｜M6 自述改中文写法（不写 `rc=`）⇒0 条
     （**已知文法盲区如实留名，刻意不扩文法**——扩了就撞「形状识别认不出举例」那条律）｜C2 加注释不动｜
     M7 超时文案加「空转」关键词⇒0 条（反向夹具：加关键词不能凭空造违例）｜R1 上限 0 时零条=0、一条即红｜
     R2 判定面归零且实现面含 2｜R3 HEAD 实现面 2 的来源唯一（独立对照）。
6. **本轮抓到自家一类假绿并机械修掉**：M5 的替换串写成 `" / 2=…"`，真文本是 `）/ 2=…`（前无空格）⇒ 变异根本没发生，
   而基线本来就是 0 条，那格于是打印「ok」。`check()` 现装自动闸：**M 支变异文本与工作树逐字相同即判 FAIL**。
   「空转的自测和通过的自测长得一模一样」这条老律这轮出现在变异台上而不是尺子上——它不是少考一支，是**我以为我考过了**。
7. **文档与账本同步**：`scripts/README.md` 两份条目（`simulate_head_commit` 补 `--selftest` 五格与变异台读数；
   `check_exit_code_contract` 真源读数改 0、档位历史补 R45 一档、写明零上限语义与五把尺）；
   `docs/agent-map.md` §五 棘轮句更新为「R45 降到 0」并新增两条定律（判定面条数不衡量坏面；变异台得先证明变异发生）；
   `memory/bugs.md` BUG-369 追加 `landed[2026-10-21 R45]` 七段。

## 资源消耗

- 命令实测（同一批采样，2026-10-21T00:00–00:03Z）：`moon test --target js -j 1` → `Total tests: 1302, passed: 1302, failed: 0`；
  `moon check --target js --json` → 489 warning / 0 error，与基线 `temp/chk47.json` **双向差集为空**（新增 0 / 消失 0）；
  `check_exit_code_contract.py --selftest` 28 格 rc=0、全量 rc=0；`simulate_head_commit.py --selftest` 5 格 rc=0、
  `--list` rc=0、全量模拟 rc=0（HEAD=95a1006，源码面差异 0 个）；`temp/r45_mutation.py` 13/13 rc=0；
  `check_mbti_sync` 全量 + `--selftest` 17 格 rc=0；`check_test_sync` PASS；`check_doc_surface` PASS；
  `check_scripts_index` PASS；`run_guards.py` **37 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0**。
- 预存红一格按声明期望命中：`cleanup_artifacts.py --check` 现读 **672**（86 根 `.db` + 585 `temp/` + 1 `scripts/`）——
  比 R44 的 669 多 3，多的是本轮三份实测进料（`temp/pt48.log`、`temp/chk48.json`、`temp/chk48.err`）。
  计时口径照旧：读数是电池那一次采样，不与本报告其它数字混批。
- `.mbti` 拼写抖动（`Int`↔`Int32`，本轮 `.mbt` 零改动）按 BUG-330 既有出路 `git restore -- '*.mbti'` 处置，未提交噪音。
- 会话开销：本轮为续接轮（上一段耗尽上下文后从摘要恢复），未新增子代理；主链命令约 12 次。

## 任务分配记录

- FIST 根任务 `T0r26`（`--created-by human_steward`，指挥官=主机侧裁决，认领人 `slave-guard`）：
  「BUG-369 最后一把尺 + 棘轮 1→0」，验收线 ①–⑤ 由本轮逐条对表（见「结果摘要」1–5 与「遗留风险」）。
- 分流按金条四：可分配的机械改动（改站点、写自测格、跑变异台）由本机主链直接完成并逐条实测；
  架构裁决（`emit_fatal` 共用件化落哪个包）与不可逆动作（合并 MR、账本状态 token 变更）**未自行动手**，只出方案与本报告。
- 终审按金条八：以上全部读数来自实跑命令，不以 rc=0 或自述代替。

## 遗留风险

1. **文法盲区如实留名**：R3 只认 `rc=N` 形状。把「（rc=2）」改写成「（返回值为 2）」，M6 实测 0 条——
   该站点仍真给 2，所以这不是当前缺陷，但**文案换写法就能躲过 R3**。不为它扩文法的代价写在账上。
2. **README 条目行内 `N=` 仍未纳入承诺面**（R42 起的已声明盲区）：实测开启后判定面 16→39、10 份新面真伪未核。
   上限归零之后，这一面一旦开启可能立刻把 `CONTRACT_GAP_CEILING` 顶上去了——**开启它必须与逐条核面对同一批**。
3. **`emit_fatal` 三份尺各写各的**（mbti_sync / pkg_imports / simulate_head_commit，plan_landing 另有一支）：
   形状一致但不同源，未来若有人把其中一份改回 `return 1`，只有那把尺的自测与判定面会红，不会一次性暴露。
4. **守卫本地提交面仍是空的**：`.githooks/pre-commit` 只跑 `moon check` 且 `core.hooksPath` 未设置 ⇒ 本轮的红仍只在 CI 面上生效。
5. **账本状态 token 未动**：BUG-369 抬头仍 `OPEN`。`gen_plugins.py` 按 `## BUG-N … OPEN` 与 `### FIXED(...)` 反解插件账本面，
   改状态要与插件同步同批做，否则账本改了、插件投影还是旧态（本轮只在 `landed` 行写明「存量清零 ⇒ 建议转 FIXED」）。

## 后续建议

1. 逐条核 README 内联承诺面（10 份新面），核完再开 `--readme-inline` 并把上限重标定，同一批采样写账。
2. 把 `emit_fatal` 收成共用件（先定落点与是否进 `.mbti`，属架构裁决 → 需指挥官/owner 定），再把四把尺的调用点收敛。
3. 电池整面进 CI（现 3 条预存红按期望值命中，需要给红门定「按声明期望」的口径），并给 `core.hooksPath` 接线决定权留 owner。
4. BUG-369 转 FIXED：与插件账本同批做，同时把「零容忍」语义写进 SOP 的退出码条目。

## 超额内容（本轮多做/主动做的）

- 变异台自动闸（`check()` 里「变异文本与工作树逐字相同即 FAIL」）不在任务包内，是本轮被自己那格假绿逼出来的；
  已同步写进 `docs/agent-map.md` §五成为定律，而不是只留在 `temp/` 的一次性脚本里。
- 给 `hint()` 补零上限专用文案（R44 预留的分支本轮生效），并把 `fixed` 尺清单扩到五把——两处都属判据自身演进，非题目要求。
- 本报告与 `--selftest` 五格同为「这份尺第一次有执行面」的记录：它原先一份自测都没有。

## 来源

- 上游立案：`memory/bugs.md` BUG-369（R42 立判据、R43/R44 两轮修尺、R45 收尾）；定律面 `docs/agent-map.md` §五。
- 判据真源：`scripts/check_exit_code_contract.py`（宇宙现读 `git ls-files scripts`）；被测面：`scripts/simulate_head_commit.py`。
- 证据：`temp/r45_mutation.py`（13 支）、`temp/pt48.log`（1302/1302/0）、`temp/chk48.json`（489 warning，与 `temp/chk47.json` 差集空）。
- 提交面（回填段）：见下。

## 回填：提交面与 MR 入口

- 主件：`57f2426` `fix: simulate_head_commit 的 4 处 FATAL 出口真给 rc=2，退出码棘轮 1→0（BUG-369 / T0r26）`
  （2 个显式路径 / +139 −22，逐路径 `git add`、无 `-A`、无 `--no-verify`）。
- 分支：`slave/guard/simulate-head-fatal-rc`（强制 `slave/` 前缀，未推主干）。
