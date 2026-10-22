# 2026-10-21 R26 汇报：`slave/fix/implicit-impl-as-method` —— 0079 implicit_impl_as_method 全族清零（63 条）+ 耦合 0071 + 守卫 derive 盲区

- 分支：`slave/fix/implicit-impl-as-method`（stacked on `reserved-keyword-and-priv`(#12) → `unused-value-locals`(#11) → `deprecated-api-renames`(#10) → `test-qualified-imports`(#9) → `syntax-noise-sweep`(#8) → `deprecated-not-operator`(#7) → `core-package-imports`(#6) → `unused-package-deps`(#5) → `moonc-0.10.16-result-api`）
- FIST：根任务 `T0`/`T0r2`/`T0r3`/`T0r4`/`T0r5`/`T0r6` 均已完成；本单挂新根 `T0r7` 走完整生命周期（publish→claim→execute→submit→verify）
- 台账：BUG-350（low，FIXED，轮次 R26）—— 本分支链上第二份动 `.mbti` 接口面的单，方向与 #12 相反（扩张而非收缩）

## 结果摘要

| 判据 | 改前 | 改后 |
|---|---|---|
| `moon check --target js --json` warnings | 651 | **588** |
| 同判据 errors | 0 | **0** |
| `error_code` 0079 implicit_impl_as_method | 63 | **0** |
| `error_code` 0071 core_package_not_imported | 1 | **0**（中途峰值 31） |
| `error_code` 0029 unused_package | 0 | **0** |
| `moon test --target js -j 1` | 1302/1302/0 | **1302/1302/0** |
| `moon build cmd/cli --target js` | rc=0 | **rc=0** |
| moonfmt 非漂移分歧（17 份 .mbt） | — | **0**（bare LF 亦 0） |
| `check_mbti_sync` | PASS（642 条） | **PASS（654 条）** |

改动 30 份文件、+337/−2 行：17 份 `.mbt` 补 63 条 `pub extend`（Eq 26 / Debug 31 / Show 6，逐条用编译器给的确切文本）；6 份 `moon.pkg` 增加 `"moonbitlang/core/debug"` 包依赖；6 份 `pkg.generated.mbti` 手写镜像 +95 行（26×2 + 31 + 6×2）；`scripts/check_mbti_sync.py` 补 derive 承载收集（+44/−2，含 3 格新 selftest）。零行为、零 API 契约变更（新增的是接口暴露面）。

## 资源消耗

- 工具调用：约 30 次。判据实跑量：`moon check --target js --json` 全量 **6 次**（`temp/chk21`…`chk26`：试点后 650 / 批量后 619 / 补 import 后 588 / 终态复验 588×3）、`moon test --target js -j 1` **1 次**、`moon build cmd/cli --target js` **2 次**、moonfmt 逐文件 **17 次**（非漂移分歧 0）、守卫整轮 **2 次** + 变异测试 1 次（摘除 `collect_defs` 新增段）、FIST 生命周期 **5 次**调用。
- 本机墙钟：本单跨一次上下文续接，判据面（6 次全量 check + 1 次全量 test）是主要开销；无长尾空等。
- 返工 4 次：① `temp/fix79pkg.py` 首版对 `src/core` 静默零命中（用 `"\nimport {\n"` 定位，而该包没有 import 块）⇒ 改为整块前置新建；② `temp/mirror79.py` 找闭合行用 `endswith("}")`，撞上 `} derive(Eq, Debug)` 而 IndexError，且崩溃前已 `git restore` 掉镜像 ⇒ 改 `startswith("}")` 并重跑 check 重新生成后再镜像；③ FIST `publish` 被 BUG-32 产物新鲜度守卫触发重编译、撞 `\\?\` ICE ⇒ 次序改为"先 `moon build cmd/cli` → 立即驱动 → 之后才恢复 mbti"；④ 追加台账条目后 `gen_plugins --check` 报 9 份投影不一致（生成件里嵌 `BUG-1~N 共 M 条入账` 计数），跑一次 `python scripts/gen_plugins.py` 重投影后 `gen_plugins --check` / `check_plugin_sync` 复绿（+17/−17 行、9 份）。

## 任务分配记录

- 指挥官亲自做：0079 与 0071 的耦合判断（试点先行）、`moon.pkg` 与源文件两种 import 出路的取舍、mbti 扩张面镜像规则与算术校验（95 行）、`check_mbti_sync` 盲区的定位与变异验证、终审判据（check/test/build/fmt/守卫实跑）、记忆沉淀。
- 子代理：未派（63 条声明由编译器文本逐字给出，loc 驱动一次成型，派单成本高于收益）。
- FIST 自我迭代：`scripts/fist.py` 驱动 `T0r7` 全生命周期至「已完成」，连续第九轮可证。

## 遗留风险

1. **接口面扩张仍无"生成器背书"**：`pkg.generated.mbti` 的 +95 行是手写镜像（本机 `moon info` 因 BUG-330 漂移不可用于收口）。`moon check`/`moon test`/`check_mbti_sync` 三面复验通过，但建议 owner 在有匹配工具链的环境跑一次 `moon info` 确认 0 行差异。
2. **native 面本机未量测**：全部判据在 `--target js`；`moonbitlang/core/debug` 依赖在 native/wasm 目标的解析未在本机验证（CI 会跑）。
3. **stacked 合并顺序**：本支依赖 #12 → #11 → … → `moonc-0.10.16-result-api`（master 树当前不可编译，BUG-328 未合）。MR base 若为 master，diff 会含全部祖先改动。
4. **6 处预存 CI 红逐项与改前一致**（badge 1108 vs 1302、`check_test_sync` 现状面及其 selftest 基准夹具、`check_scripts_index` 的 `run_check_t0r21.py`、`check_doc_surface` 的 USAGE 0.3.8 vs moon.mod 0.3.9、`check_entry_paths` 的 `docs/SOP.md:44`），非本单引入；`cleanup_artifacts --check` 仍 DIRTY（341 件，本机取证件，刻意不销毁）。
5. **记账偏差**：`T0r7` 任务描述写"共 62 条声明"，实际交付 63 条（试点 2 + 批量 61）；`scripts/fist.py` 无描述编辑动词，不追改，如实登记。

## 后续建议

1. 下一单建议 **0078 result_error_return**(13)：把 `Result[T, E]` 改 `T raise E` 是真签名变更，可复用本单"手写镜像 + keep 备份 + restore 复验"三步工序，但要额外过调用面。
2. **0020 语义档 527** 建议先开一试点单：在 `src/server/server.mbt` 引入包内 `priv fn` 辅助收敛 `as_bool`(15)/`as_string`(7)，再评估 `Json::value` 430 与 `str[:]` 42 是否值得批量。
3. **把接口面三步工序写进 `docs/SOP.md`**：#12 与 #13 两轮独立发现同一坑（判据一跑就冲掉手工镜像），属可复用工序而非本轮经验。
4. `check_mbti_sync` 本轮暴露的"集合塌陷"读数（+95 行只计 +12）建议保留注释，下一轮看接口面 diff 时不要误判为漏计。
5. BUG-330 拼写漂移仍是所有接口面单根因；死码族 0001/0006/0007/0009 与 `warnings = "-..."` 压制仍待 owner 决策。

## 超额内容（本单边界之外做了什么、为什么）

- 加做了 `check_mbti_sync` 的 derive 承载盲区修复（+44/−2）与 3 格 selftest：不清这个盲区，本单的 63 条实现会让守卫报 12 条**假红**，而"守卫假红"在本仓的惯例等同于交付不合格；顺手用变异测试证明新格不是装饰。
- 加做了插入的算术校验（26×2+31+6×2=95）与"同型不带 derive 仍必须照红"的反面用例，避免把真缺失一并放过。
- 未做：未加 `warnings = "-..."` 压制、未删任何死码、未动 `Json::value`/`as_bool`/`as_string` 语义档、未改 `Result[T,E]`→`raise` 签名、未跑破坏性 `cleanup_artifacts.py`、未 `git add -A`；未手改任何生成件（投影只由 `gen_plugins.py` 得出）。

## 来源

- 判据：`temp/chk21.json`（试点后 650，79=61/71=1）、`temp/chk22.json`（批量后 619，79=0/71=31）、`temp/chk23.json`–`temp/chk26.json`（**588 / 0 errors**，79=71=0）、`temp/pt13.log`（`Total tests: 1302, passed: 1302, failed: 0`）、`temp/build26.log` / `temp/build27.log`（rc=0）。
- 改法脚本：`temp/fix79.py`（按 (file, anchor line) 分组插入，`files touched 16 decls inserted 61 of 61`）、`temp/fix79pkg.py`（6 份 moon.pkg 补 debug 依赖）、`temp/mirror79.py`（手写镜像 6 份 mbti / 95 行）、`temp/census79.py`（族与承载点普查）、`temp/mut_mbti.py`（守卫变异）、`temp/fmtverify2.py`、`temp/run_guards11.py`。
- 镜像备份：`temp/keep26/`（6 份终态 `pkg.generated.mbti`）。
- FIST：`temp/t7_drive.py`（根 `T0r7` 全生命周期）。
- 台账：`memory/bugs.md` BUG-350 + `### FIXED(2026-10-21 轮次 R26 / BUG-350)`；`memory/2026-10-21.md` R26 小节。
- 既有结论：BUG-349（接口面镜像与试点方法论，本单第二次复用）、BUG-346（check/test 重写 mbti，本单第五次确认）、BUG-344（复跑 `error_code` 命中才算收口）、BUG-330（拼写漂移 ⇒ `moon info` 不可背书）、BUG-32/BUG-329（fist.py 产物新鲜度守卫与 `\\?\` ICE 次序坑）、BUG-328（master 树不可编译 ⇒ stacked 链）。
- 仓库规范：`AGENTS.md` 金条四/五/八（含"代码任务终审必须实跑 `moon test`/`moon check`"与 `moon info` 后须审 `.mbti` diff）、`docs/SOP.md:33`（禁 `git add -A`，逐路径显式 staging）。
