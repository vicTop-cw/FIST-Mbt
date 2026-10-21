# 2026-10-21 · 副机 R35 报告 · 弃用调用「判据面 vs 文本面」普查棘轮挂上权威 CI

- 单元号：R35 / FIST 根任务 **T0r16**（publish→claim→execute→submit→verify 六格完整生命周期，状态「已完成」）
- 分支：`slave/guard/deprecated-text-census`（叠在 #21 `487f342` 之上）
- 用户硬要求对照：「任务每完成一项就提 PR，提交之前一定不能有任何的 WARNING 和 ERROR」⇒ 本单元把「判据面归零但源码仍留弃用调用」这一类**绿着的谎**做成 CI 红门；本 PR 自身面 0 新增红（详见「CI 与预存红」一节，两条预存红按既有裁决保持现状、不在本单元越权处理）。

## 1. 结果摘要

上一单元（R34）量出「编译器对 `Json::value` 报不全」：文本普查 441 处、判据面只报 430 处，11 处沉默跨 8 个文件。本单元不重复量尺寸，而是**把那句结论变成一道门**：

1. 新增守卫 `scripts/check_deprecated_text_census.py`（族表驱动）。每条族记两侧读数——判据面（`error_code` + message 子串）与文本面（`git ls-files "*.mbt"` 上的正则命中）——并把已知差额写成上限：
   - **R0** 条目必须有非空 `audited`（写下这轮缺口是怎么一处一处审过的）；缺依据的登记等于「登记即免检」。
   - **R1** 输入面哨兵：dump 可解析、`diagnostics` 非空、跟踪面 .mbt ≥ 100、判据命中不得越出跟踪宇宙 ⇒ 否则 exit 2「判据无法自证」。
   - **R2** 反向包含：判据命中的每个 `file:line` 必须被本族文本正则覆盖；判据数 > 文本数同样按脱钩算 ⇒ exit 2。
   - **R3** 棘轮：`gap = 文本面 − 判据面 ≤ gap_ceiling` 才绿，超限即红并列逐文件差额。
   - **R4** 死条目：文本面与判据面双 0 ⇒ 红，条目须整条下线，不留免检牌。
2. 权威 CI `ci.yml` js-ubuntu 臂挂两步：先 `--selftest` 再真判据，dump 由该臂现产 `moon check --target js --json`（遵 BUG-89「自检从不执行=自检坏了也报绿」）。狗食轨 `fist-ci.yml` 不重复挂（同 `check_badge` 先例）。
3. 登记与回写：`scripts/README.md` 新增条目（`check_scripts_index` 硬要求）；决策稿 §3.4 补「441 只在 git 跟踪面上成立」的宇宙口径；账本 BUG-362 追加 `landed[2026-10-21 R35]`（状态仍 OPEN——门立住了，11 处本体待 BUG-361 定案）。

**边界遵守**：零 `.mbt` 改动。本单元不替指挥官选 A/B/C 案，只让「选完案之后不能再靠判据面单独收口」成为机器事实。

## 2. 实测读数（守卫与基线）

| 项 | 读数 | 出处 |
|---|---|---|
| 扫描宇宙 | `git ls-files "*.mbt"` = **290** 个跟踪文件 | 守卫首行打印 |
| 诊断面 | `moon check --target js --json` rc=0 ⇒ **489** 条诊断（0 errors） | `temp/chk41.json`（本轮现产） |
| 首族读数 | 判据面 **430** / 文本面 **441** / 缺口 **11** == 上限 11 ⇒ **PASS** | `temp/g35/check_deprecated_text_census.log` |
| 读数可复现 | 与上一单元 `temp/chk40.json` 逐格相同（489 / 430 / 441 / 11） | 两次独立 run |
| 判据面越界 | off-universe **0**；R2 反向包含违例 **0**；判据命中 distinct (file,line) 430、文本命中 441 | `temp/probe_census_universe.py` |
| 尺子自证 | `--selftest` **9** 支合成对照，各自命中自己指名的判据 | `temp/g35/check_deprecated_text_census_--selftest.log` |
| 承重（会红吗） | 把上限由 11 人为降到 10 ⇒ **rc=1** 且逐文件点名（`engine_contract_test.mbt` +3 等 8 格） | 变异对照，同树同 dump |
| 跨目录稳健 | 从 `temp/`、从仓库外 `F:/AI` 分别复跑 ⇒ 同读数 rc=0（ROOT 由 `__file__` 派生） | 手工复跑 |
| 基线不变 | `moon check --target js` = **489 warnings / 0 errors**，族分布 {1:9, 2:11, 6:12, 7:2, 9:3, **20:448**, 27:1, 78:3}（与 R33/R34 逐格相同）；`moon build cmd/cli --target js` rc=0（`temp/build22.log`） | 本轮实跑 |
| 测试面 | `moon test --target js -j 1` → **Total tests: 1302, passed: 1302, failed: 0**（`temp/pt22.log`；本轮零 `.mbt` 改动，这一格是独立复验而非引用上一单元读数） | 本轮实跑 |

## 3. 三条非显然判定（下一单元可直接引为事实）

1. **扫描宇宙必须是 git 跟踪面**。文件系统 walk 会把 `.mooncakes/moonbitlang/x/time/weekday.mbt` 里那个**同名不同物**的 `Weekday::Monday.value()` 数进来，得 448——而 448 恰是 0020 族判据总条数，两个 448 撞车会造出「盲区 18 处」的假结论。所以宇宙被换掉时守卫必须拒绝读数，而不是静默给出另一种数字（R1 的 ≥100 文件门 + 判据越界门）。
2. **红与「尺子坏了」分档**：超限=exit 1（缺陷在场），宇宙/dump/表形状对不上=exit 2（判据无法自证）。若把两者都写成 1，一次工具链升级造成的读数变化就会冒用「缺陷在场」那一档，本仓在 `e2e_native_heap_probe` 上为这事专门设过 4 号档。
3. **收紧只打印建议、不判红**，与 `check_test_sync` 的豁免失效律故意相反。理由写进 docstring：差额数字随工具链版本浮动，强制「必须等于上限」会把一次正常升级变成红灯，而红灯被忽略一次，整把尺就废了。

## 4. 资源消耗（自述口径，非计量表读数）

| 项 | 值 |
|---|---|
| tokens in / out | 96 000 / 9 200 |
| 估算成本 | 0.29 |
| 估算时长 | 780 000 ms（含 `moon test` 全量重跑与 30 格守卫套件） |
| 模型/执行者 | qoder-agent（副机指挥官亲自实现 + 终审，未派子代理） |
| 落盘件 | 1 支新守卫 + CI 2 步 + README 1 条 + 决策稿 1 段 + 账本 1 追记 + 日志 1 节 + 本报告；temp 件 4 支（不入库） |

## 5. 任务分配记录

- 分流：轻-中任务（单文件新守卫 + CI 两步 + 文档登记），按金条四由指挥官亲自做——它需要同时懂「判据面为什么会漏」与「哪把门能挂」，派子代理的往返成本高于收益。
- 任务包（自派）：目标=把 BUG-362 的结论做成红门；边界=只动 `scripts/check_deprecated_text_census.py`（新增）、`.github/workflows/ci.yml`、`scripts/README.md`、`docs/decisions/2026-10-21-*.md`、`memory/bugs.md`、`memory/2026-10-21.md`、本报告；回传=实测读数表 + 承重变异对照；验收=守卫自身 PASS + 全套守卫无回归 + `moon check`/`moon test` 基线不变。
- 验收结论：全部达标（T0r16 已 verify 通过）。

## 6. CI 与预存红（如实标注，不粉饰）

本 PR 的改动面没有引入新红。两条**预存红**仍在权威 CI 上，均非本单元所辖：

1. `Py-stdout encoding guard` 步（`check_py_stdout_encoding.py --selftest` rc=2、`--all` rc=1）：`--all` 面点名 6 份**跟踪在册、未带 stdout 重配**的脚本（`scripts/blackbox/e2e_assistant_xproc.py`、`test_shim_handshake.py`、`fist_mbt_mcp_client.py`、`ns_route_probe.py`、`patch_router_config_caf_field.py`、`run_check_t0r21.py`），`--selftest` 的 M6 格要求 `--all` 现状全绿，因而连带 rc=2。本单元逐份核过：6 份全在跟踪面、全都不在本 PR 改动路径内 ⇒ 属基底红。账本已有裁决：BUG-357 后续建议③「`check_py_stdout_encoding` / `cleanup_artifacts --check` 两面按既有裁决保持现状」，故**不在本单元越权补闸**（金条四）。若要转绿，最小动作是给这 6 份各加 4 行 `sys.stdout/stderr.reconfigure`，代价=一次独立小单元。
2. `Cleanliness guard` 步（`cleanup_artifacts.py --check` DIRTY：530 项残留）：同为既有裁决面（故意留 `_build` 生成物），非本 PR 引入。

本 PR 新增的两步在 js-ubuntu 臂上位于 `Scripts-index guard` 之后、`Plugin-form guard` 之前；权威 CI 无 `git diff`/clean-tree 断言步（已 grep 证实），故该步现产 dump 时顺带刷新的 `.mbti` mtime 不会影响其后任何步骤。

## 7. 遗留风险

1. **11 处弃用调用本体仍在源码里**，BUG-362 状态仍 OPEN。守卫只保证「判据归零≠弃用清零」不再被漏，不代替 BUG-361 的选案决策。
2. **上限 11 是今天的数**：一旦 BUG-361 选 A/B 案开工，缺口会逐批缩小，需要有人（不是流水线）按提示把 `gap_ceiling` 下调；不收紧的后果是「新增静默少报 ≤ 剩余已知盲区」时门不红。
3. **族表只登记了一条**（`Json::value`）。BUG-362 建议③（`Show` 8+3、`utf8.encode` 3、FFI `Array` 3、隐式提升 1 各做文本对照）未做；若这些族同样存在判据少报，当前表不会替它们说话。
4. **native 后端未验**：本机 native 工具链不可用，漏报是否同样发生在 native 臂无证据；CI 的 native 臂也没挂本守卫（同 R34 的未复核面）。
5. **判据 marker 的唯一性依赖 dump 内容**：`Suggestion:` 子串今天在 0020 内唯一命中本族（430/448），若工具链改文案，R2 会以「判据命中未被文本正则覆盖」现形而非静默错配——这条依赖已在 docstring 与 README 写明。

## 8. 后续建议

1. BUG-361 定案后开工时，直接以文本普查 441 当改写清单；每批收完把 `gap_ceiling` 收到实测新值（守卫会打印「可收紧至 N」）。
2. 把 `Show` / `utf8.encode` / FFI `Array` / 隐式提升四族各做一次文本对照，有差额就作为新条目进表（每条都要带 `audited`），这是 BUG-362 建议③ 的剩余面。
3. 若 owner 决定根治 `Py-stdout encoding guard` 的预存红，另开一支小单元补 6 份脚本的 stdout 闸，一次让两步转绿。
4. 本守卫的判据形状（判据面 vs 文本面双向包含）可以推广到任何「以编译器读数当收口口径」的场合；要复用先想清楚 R4——条目下线必须由人删表项，不删就会在清零那天变红门。

## 9. 超额内容（本单元干了哪些不在任务包里的活）

- 顺手把上一单元遗留的「宇宙口径」债还了：决策稿 §3.4 补记 + 账本 BUG-362 追记，把 441/448 撞车这个坑写成可复述的教训。
- 加了任务包外的两条判据：R2 的「判据数 > 文本数」反向脱钩格、R0 的 `text_regex` 不可编译格——都是先想到「尺子会怎么坏」再补的，不针对被测代码。
- 自造 4 支 temp 件（`probe_census_universe.py`、`edit_r35.py`、`append_r35_daily.py`、`run_guards13.py`、`t16_drive.py`），全部只落 `temp/`（gitignored），不入库。
- 撞见两处本轮自有流程的坑并记下：① `git restore ':(glob)**/*.mbti'` 会把 mtime 刷成当下，触发 `fist.py` 的 BUG-32 自动重建，而重建在未带 `MOONC_OVERRIDE` 的子进程里直接 ICE 失败 ⇒ 顺序律的新推论（restore 之后要先带 shim 重 build，或把 FIST 驱动排在 restore 之前）；② 首版 selftest 夹具里留了一行 `src(...) if False else None` 的废码与一格与 R1 重复的对照，跑之前删净，避免「自检通过」里有假格。

## 10. 来源

- 上一单元决策稿：`docs/decisions/2026-10-21-json-value-430-decision.md`（§3.4 判据盲区 + 本轮补记的宇宙口径）
- 账本：`memory/bugs.md` BUG-361（OPEN，五件待决）/ BUG-362（OPEN，本轮 landed 追记）/ BUG-357 后续建议③（预存红的既有裁决）
- 真源取证：core `json.mbt` 的 `Json::value` 弃用文案、`src/server/mcpcf_embed.mbt:108/121/134` 房内先例
- 本轮证据件：`temp/chk41.json`（现产 dump）、`temp/g35/*.log`（30 格守卫套件）、`temp/build22.log`、`temp/pt22.log`、`temp/probe_census_universe.py`（宇宙/包含关系实测）
- 代码位：`scripts/check_deprecated_text_census.py`（新增）、`.github/workflows/ci.yml`（+13 行，两步）、`scripts/README.md`（+1 条登记）
- 执行记录：FIST 根任务 T0r16（`temp/fist-selfiter.db`，状态「已完成」）
