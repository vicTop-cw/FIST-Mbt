# 2026-10-21 R41 汇报：`slave/guard/plan-landing-moved-face` —— 搬家态 + 判定面棘轮，顺手抓到「自述 rc=2 是幻影」（BUG-367 D 类 / T0r22）

- 分支：`slave/guard/plan-landing-moved-face`（链在已推的 `slave/guard/execution-face`（`f73788d`）之后单独起支；**trunk 未推**，MR 由 owner 开）
- FIST：根任务 `T0r22` 走 publish→claim→execute→submit→verify 全生命周期（`--created-by human_steward` / `--assignee slave-guard`），连续第廿二轮自我迭代可证
- 台账：BUG-367（low，**仍 OPEN**：A/B/C 三档留裁，D 类 `landed[2026-10-21 R41]`）+ 新增 BUG-369（low，**OPEN**：退出码自述面幻影家族）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `check_plan_landing.py` 判定面（默认诊断口径） | 28 条未落地 | **25 条**（搬家态 3 条单列、不进判定面） |
| 该工具的状态数 | 三态 tracked / on-disk / missing | **四态**（+ `moved`，P5） |
| 棘轮/门禁 | 无（只报不判，红绿靠人读） | `VERDICT_GAP_CEILING = 25` + `--gate` 真门禁，**已挂 CI** |
| `check_plan_landing.py --selftest` | 19 格 | **44 格**（P5 搬家 7 + 分面 2 + P6 棘轮 3 + 退出码两口径 5 + 空转三条 4 + 模式互斥 2 + 出口码 1） |
| 判据空转 FATAL 的退出码 | 文档写 2、**实测 1**（幻影） | **实测 2**（`emit_fatal()` + `SystemExit(2)`，并有一格锁它） |
| `run_guards.py --selftest` / 电池整跑 | 9 格 / 34 格 | **11 格 / 35 格 / 失败 0 / SKIP 0 / 缺执行面的尺 0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0**（零 `.mbt` 改动） |
| `moon check --target js --json` | 489 warning / 0 error | **489 / 0**，逐 `error_code` 分布与基线 `temp/chk47.json` **逐格相同** |
| 台账 | 353 条入账 / 19 待修 | **354 条 / 20 待修**（`gen_plugins.py` 重投影 9 份插件文件，`--check` + `check_plugin_sync` PASS） |

三条新定律（已写进 `docs/agent-map.md` §五）：

1. **自述的退出码必须实测**。`raise SystemExit("…")` 给的是 1 —— 本仓同形状还有 3 份纯幻影（`check_mbti_sync` 7 处串式 FATAL /
   `check_pkg_imports` 6 处 / `check_template_ctrl` 1 处，自述 `2=判据无法自证` 而代码里一条 2 都给不出）与 1 份半形
   （`simulate_head_commit`：moon 超时那条走 `return 2` 真给 2，其余 4 处 FATAL 给 1，其中「PATH 上没有 moon」那条
   **文案自己写着「（rc=2）」**）。后果不是红变绿，而是**「尺子坏了」与「有违例」在 rc 面上同色**。
2. **数站点要用 ast，不要用正则**。普查工具第一版把 docstring/注释里的 `SystemExit("…")` 字样当调用点（虚高到「9 份 33 处」），
   又把 `sys.exit(main())` 这种正常透传当「已有整式出口」（漏掉 `check_pkg_imports`、误判 `simulate_head_commit`）——
   同一轮里两处现形。连我自己的验证夹具也踩了同形错：`moon check` 比对首跑读错 JSON 键名，打出「0 vs 0 相同」的空转绿，
   补上「数组为空即 FATAL」自拒后才现出真数 489/0。
3. **模式互斥不是洁癖**。`--gate` 与 `--all-faces` 同开 ⇒ 当场拒（rc=2）。上限是按活文档面标定的；去掉这道闸实测同一份存量
   从 25 跳到 38、门禁反而给 **0**——在未标定的宇宙上比数，红是假的、绿也是假的，**「绿得莫名」比红更坏**。

## 资源消耗

- 本轮工具调用面：`Edit` ×9（`check_plan_landing.py` docstring、`run_guards.py`、`ci.yml`、`scripts/README.md` ×5、`docs/agent-map.md` ×2）
  + `Bash` 取证若干（电池 2 次整跑、guard 6 项复读、`moon test` 1 次、`moon check` 1 次、ast 普查 3 版）。
- 新增临时件（全部在 gitignore 的 `temp/`，不入提交）：`r41_before.txt` / `r41_after.txt` / `r41_a.paths` / `r41_b.paths`
  （28 → 25 的 `comm` 双向对照）、`r41_gate.txt` / `r41_af.txt` / `r41_conf.txt` / `r41_fatal.txt` / `r41_st.txt`、
  `r41_mutation.py`（8 支变异 + 6 格对照）、`r41_fatal_census.py`（正则版，**已判不合格**）、`r41_fatal_census2.py`（ast 版）、
  `r41_ledger.py`（台账 CRLF 写入）、`r41_moon_test.log` / `r41_chk.json`。
- 代价账：`cleanup_artifacts --check` 预存红 624 → **643**（构成：86 个根 `.db` + 556 个 `temp/` 文件 + 1 个 `scripts/` `_` 临时脚本），
  增量 19 全是本轮取证件；按 BUG-368 的口径把构成写进读数，不留裸数字。

## 任务分配记录

| 环节 | 承担 | 说明 |
|---|---|---|
| 判 `moved` 的判定条件该多窄 | 副机（机械事实） | 「同名 + 父目录前缀 + 候选在跟踪面」三条，加三条保守（不吃 on-disk、不碰顶层点名） |
| 判 A/B/C 三档「删文还是补做」 | **留指挥官** | 内容裁决，金条四；本单一条文档未改 |
| 判 `VERDICT_GAP_CEILING` 放宽 | **留指挥官** | 脚本只提示收紧，放宽需人改常量（改判据宇宙 = 内容裁决） |
| 判 BUG-369 那 4 份是否同轮改 | 副机出方案、**执行留裁** | 每改一份都改其 rc 面，CI/电池期望要逐条复核 ⇒ 按边界一轮一把尺 |
| MR / merge | **owner** | 副机只推 `slave/` 分支并给入口链接，不开 MR、不动 trunk |

## 遗留风险

1. **BUG-369 四份未改**：`check_mbti_sync` / `check_pkg_imports` / `check_template_ctrl` 的 FATAL 与「有违例」仍在 rc=1 同色，
   `simulate_head_commit` 自相矛盾（同一条「前置不满足」分走 1 与 2）。CI 目前没按 rc==2 分档 ⇒ 尚无实际误判，
   但任何新门据此写都会踩空。
2. **判定面 25 条是「声明的存量」，不是「已裁决的存量」**：`--gate` 现在默认绿（25 ≤ 25）。若指挥官裁 A 类为「设计作废」，
   上限应收紧；若裁为「待补做」，则补做进度由棘轮钉住——**上限不会自己跟着现实走**。
3. **`moved` 只证同名与前缀关系，不证同一份内容**：若归档时被改过名或改过内容，本态读数仍是「搬家」。
   已在小记与 docstring 双向声明这条边界。
4. **B 类 4 条（外部件 `src/*.js`）常驻判定面**：分母是本仓跟踪面，必然报 missing。出路三案（白名单 / 改文 / 存量声明 + 增量归零）
   未裁，本轮刻意不加白名单——BUG-365 已把「免检牌」钉成反夹具，豁免面必须与反夹具同轮落地。
5. 未复核面：native 臂（本机工具链不可用，24 把尺的 native 行为零读数）；`gated()` 两格依赖本机 `temp/` 基线件，跨环境读成 SKIP；
   workflows 其余臂是否按 rc 分档（本轮只读 js-ubuntu 臂）。

## 后续建议

1. 按 BUG-369 建议① 逐份修那 4 把尺（一份一轮），每份配「FATAL 的码真是 2」一格，并复核 CI/电池里按 rc 写死的期望值。
2. 采纳 BUG-369 建议② 立 `scripts/check_exit_code_contract.py`：承诺面 = **脚本正文 ∪ `scripts/README.md` 条目**（`check_pkg_imports`
   的承诺活在 README，只扫脚本正文就会漏），实现面 = ast 可达整数出口集合；这条普查现在是零执行面临时件，本单是它的第一个样本。
3. BUG-367 A/B/C 三档请指挥官裁决；裁后把 `VERDICT_GAP_CEILING` 一并收紧（棘轮已就位，裁决慢不会让盲区重新长回来）。
4. 若要把整把电池（35 格）搬进 CI，需先给 3 格 `known-red` 开 `continue-on-error`——那等于把「期望红要带依据」降级成「红都放行」，
   建议与 `check_py_stdout_encoding` 那 9 份历史脚本一起裁。

## 超额内容

- BUG-367 D 类之外的三件（本单边界原为「加 moved 态」）：`--gate` 真门禁、CI 新增 ratchet gate 步、`run_guards.py` 门禁格 + 2 格 selftest。
- 幻影 rc=2 是**顺路抓的**：起因只是给空转 FATAL 写期望格。已固化为 BUG-369 + `docs/agent-map.md` §五两条定律。
- 普查工具重写两版（正则 → ast），第一版判不合格并保留当反例；`docs/agent-map.md` 新增「数站点用 ast」一条属额外沉淀。
- 我自己的验证夹具（`moon check` JSON 键名读错）被抓并补了空宇宙自拒 —— 这条属本轮踩坑，未额外入账（已由 BUG-369 的②覆盖同一形状）。

## 来源

- 真源：`git ls-files` 跟踪面 / 工作树磁盘面 / `docs/*.md` 文本抽取（`scripts/check_plan_landing.py`）；`moon test` / `moon check --json` 现产；
  `scripts/run_guards.py` 电池整跑；`memory/bugs.md` 台账 354 条；`.github/workflows/ci.yml` 现读。
- 证据件：`temp/r41_before.txt`（改前 28 条）、`temp/r41_after.txt`（改后 25 + 3 moved）、`temp/r41_{a,b}.paths`（`comm` 双向对照）、
  `temp/r41_mutation.py`（8 变异 + 6 对照全绿）、`temp/r41_fatal_census2.py`（ast 普查输出）、`temp/r41_chk.json`（489/0）、
  `temp/r41_moon_test.log`（1302/1302/0）。
- 上游：BUG-367（T0r21 出数）、BUG-365/366（免检牌与零执行面两条定律）、BUG-368（预存红要带构成）、
  BUG-330（`.mbti` 由 moon 重写 ⇒ `git restore` 不提交）、AGENTS.md 金条四/五/八、docs/SOP.md §禁止 `git add -A`。
