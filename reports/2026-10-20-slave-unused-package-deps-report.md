# 2026-10-20 汇报 —— `slave/fix/unused-package-deps`（0029 unused_package 全族清零）

## 结果摘要
- **金标判据**：`moon check --target js --json` 由 1920 warnings / 0 errors → **1899 warnings / 0 errors**；`error_code=29`（unused_package）命中数 16 → **0**。
- **零回归**：`moon test --target js -j 1` → `Total tests: 1302, passed: 1302, failed: 0`（与本机基线逐字相同）。判定按这行的读数，不看 rc。
- **附带清掉 5 条**别的族：`src/core/core_quickcheck_wbtest.mbt` 的 0071 `core_package_not_imported` ×5 —— 这是"改 import 作用域"的自然结果，不是本单目标，如实标注。
- 改动面 13 份文件：12 份 `moon.pkg`（`omega` + src/{core,decompose,diff,engine,evolve,executor,ltl,omega,ops,router,server}）+ 账本/日志/汇报/插件投影。`.mbt` 源码一行未动。
- 入账 **BUG-342**（medium，FIXED，R18），含 `### FIXED(2026-10-20 轮次 R18 / BUG-342)` 小记与全部实测锁钉；账本抬头计数 327 条 / 11 待修。

## 资源消耗
- 本机实跑：`moon check --target js --json` ×3（基线 / 作用域试验 / 终态）、`moon check --target native` ×2（受机器级缺口阻塞）、`moon test --target js -j 1` ×1（全量）、守卫脚本 13 支各 1~2 轮。
- 回合预算：目标 20 回合，本单在既有累计 1 回合的续段内完成；时间轴 10,282s → 11,000s（累计）。
- 磁盘新增均为 gitignore 的 `temp/*`（chk5/chk6/chk7/chknat.json、pt5.log、cpi_st.log、gp5.txt 与 4 个一次性脚本 `list0029.py`/`usage0029.py`/`exp_scope.py`/`fix0029.py`），不入库。

## 任务分配记录
- 指挥官（我）亲自做：判据设计（分两族处置而非一把梭删）、作用域试验的取舍、终审与实测验证、账本/汇报落档。
- FIST 自我迭代轨（本单实际用它收的口）：`moon build cmd/cli --target js` → rc=0（13 tasks, 583 warnings / 0 errors）产出 `_build/js/debug/build/cmd/cli/cli.js`，再由 `python scripts/fist.py call …` 逐步推进 T0.1：`claim`(待领取→已领取) → `execute`(执行中，deliverable 记 1920→1899 与 1302/1302) → `submit`(待验收) → `verify --verifier commander`(已完成，completed_by=commander)。DB 走 `FIST_DB_PATH=temp/fist-selfiter.db` 显式改道，不碰仓库根台账；根任务 T0 仍停在「拆分中」，因为 T0.2/T0.3 尚未做，这条不假装收口。
- 未派子代理：本单是"一条判据 + 一次可验证删除"的窄活，派出去反而丢掉试验证据链。

## 遗留风险
1. **native 面未经本机验证**（`moon check --target native` 在本机 rc=1，原因是 `~/.moon/lib/core/_build/native/release/bundle/cmp/cmp.mi` 缺失，属机器级工具链缺口、与本单无关）。缓释：被删的 12 条 import 在整包目录（含 `*_native.mbt`）零引用；CI native job 的两步是硬门。
2. **本支是 stacked 分支**（基 = `slave/fix/moonc-0.10.16-result-api` 的 5f29de2+f72752d）。MR diff 会带上那两枚 commit。若先合 BUG-328 再 rebase，本 MR 收敛到 13 份文件。
3. **`omega/` 空包仍在**：只剩 `moon.pkg` + `pkg.generated.mbti`，无任何源文件、无任何引用。本单只清 import 块不删目录（不可逆动作留裁决）。
4. **`for "wbtest"` 这一格依赖 moonc 现行行为**：若上游把白盒单元的 `for "test"` 语义修对，`src/core/moon.pkg` 就该改回 `for "test"`，届时 0071/0029 两边都不该出现——这条判据要回读，不能当永久真理。
5. 本支 CI 面还有 6 格红（badge / test_sync / test_sync --selftest / scripts_index / doc_surface / entry_paths），逐格实测确认都由其他在册 MR 的判据面负责，非本单引入。

## 后续建议
- 按族继续下发，一族一 PR：下一发清 0071 剩 4 条（补 `moonbitlang/core/json` import 到 `cmd/cli`、`src/store`，注意 js-only 文件在 native 面反吃 0029），再 0035 reserved_keyword 13、0078 result_error_return 13、0006 unused_constructor 12、0008 unused_value 12、0004 11；`0020 deprecated`（904）与 `0025 test_unqualified_package`（803）两支大的最后单独规划，别混进小族 PR。
- 合流顺序建议：BUG-328（可编译）→ test-count-1302（文档面+守卫自检）→ 本单 → scripts_index / usage 两支；`slave/misc/plugin-state-sync` 最后（或让 CI 重投影覆盖）。
- 给守卫补一条**可复用的机器级前置**：任何删 import 的单都应"两族分开判"（整包零引用→删；仅测试引用→改作用域），并把 `pkg\.` 正则会撞上同名局部变量这条写进 SOP，避免下轮又靠肉眼救。

## 超额内容（超出本单一发范围）
- `src/core` 的 `for "wbtest"` 顺带清掉 5 条 0071（属下一族的白盒那一半）—— 因为它是同一格作用域判据的两面，拆开反而留下错配状态。
- 把 moonc 0.10.16 的 `for "test"`/`for "wbtest"`/黑盒-白盒注入差异测成了可复述判据（三条对照实验 + `_deps`/core 库的写法统计），这条经验本身比 16 条删除值钱。

## 来源
- 本机实测：`moon check --target js --json`（`temp/chk5.json` 基线 1920 / `temp/chk7.json` 终态 1899）、`moon check --target native`（`temp/chknat.json` rc=1 + 失败原文）、`moon test --target js -j 1`（`temp/pt5.log`）。
- 守卫输出：`scripts/check_pkg_imports.py`（PASS + SELFTEST OK 6 格）、`scripts/check_mbti_sync.py`（PASS 641 条）、`scripts/gen_plugins.py --check/--selftest`、`scripts/check_plugin_sync.py`、`temp/run_guards5.py` 汇总的 13 支 rc 表。
- 上游依据：`~/.moon/lib/core/*/moon.pkg` 与仓内 `_deps/*/moon.pkg` 的 `for "test"`(40+38) / `for "wbtest"`(14+5) 写法分布统计。
- 账本：`memory/bugs.md` BUG-342（detail + note + 出路 + `### FIXED(R18)`）；同日轮次 `memory/2026-10-20.md` R18 段。
