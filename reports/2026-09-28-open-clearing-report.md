# 2026-09-28 · 缺陷账本 OPEN 清零轮（BUG-106/111/112/114 → 版本 0.3.4）

> 任务名：`open-clearing` · 盖章 2026-09-28T16:50:00Z · 分支 `master` · 目标版本 `v0.3.4`

## 结果摘要

用户指令「是不是还有 bug? bugs.md 看下，有就启动修复模式 全部清掉」⇒ 盘面 4 条 OPEN 全部落地，
台账从「113 条 = 96 已修 / 9 重复并入 / 4 误报 / **4 待修**」变成「113 条 = **100 已修** / 9 重复并入 / 4 误报 / **0 待修**」。

| 条目 | 修法 | 锁 | 调用面实测 |
|---|---|---|---|
| BUG-111 | 上一轮已修（release 作业 `needs: [meta, build-js]` + native 容错） | R8（三支） | `v0.3.3` run：meta/build-js/release 全绿，匿名 HEAD 资产 302 → `fist-mbt-js-v0.3.3.zip`、前两字节 `PK` |
| BUG-112 | 上一轮已修（`install/unix.sh` + `GITHUB_PATH` + `moon update`） | R9（两支，只看去注释后的代码面） | 同上那一次 run 的 `Build JS target` 不再红 |
| BUG-114 | `server.mbt` 的 `project_version`、`cmd/cli/help_topics.mbt` 的 `FIST_VERSION` 与 `moon.mod`/`USAGE.md` 一起到 0.3.4 | 新增 **R11**（源码常量 == moon.mod，五格对照，基线读不到即自拒、可选面缺席不误红）+ 常驻 `fist-mbt_wbtest.mbt` 由红转绿 | `node cli.js version` 首行 `FIST-Mbt v0.3.4` |
| BUG-106 | 新增 `cmd/cli/subcmd.mbt`（`parse_subcmd` 单源展开 `--version/-V/--help/-h`、`USAGE_ERROR_EXIT_CODE=2`、`exit_code_of`、`cli_exit` 三形态），`main.mbt` 只读它 | 白盒 `cmd/cli/subcmd_wbtest.mbt` 两格 + 新增调用面判据 `scripts/cli_flag_probe.py`（七格自证，CI 新步） | 三格版本旗 rc=0 首行回显版本；`--help`/`-h` rc=0 且不落未知臂；未知参数 **rc=2** |

| BUG-115（本轮新开并即修） | 测试文件 `r2e_engine` 补 `@fs.create_dir("temp")`（SQLite 不造父目录，原先依赖同包另一文件先建目录） | CI 的 JS 轨在干净 checkout 上跑全量即常驻判据 | 同一无 `temp/` 条件下：修前 535/532/3 failed，修后 535/535（`temp/fixed_no_temp.log`） |

配套：`moon.mod`/`USAGE.md` → **0.3.4**，四宿主投影重生成（129 工具 / v0.3.4 / 0 条待修），
文档面测试总数 533 → **535** 由 `check_test_sync` 反解同步（README/README_EN/AGENTS/docs 五面）。

## 资源消耗

- 测试：`moon test --target js` 全量 **535/535**（1 次全量 + 2 次分包聚焦：`src/server` 145/145、`cmd/cli` 2/2）；
  native 本轮**未复跑**，不据旧数宣称双端同版全绿。
- 构建：`moon build --target js cmd/cli` 2 次（第二次是帮助面常量变更后增量，`ran 2 tasks, 0 errors`）+ `patch_esm_main.py` 幂等 patch。
- 判据：守卫族 10 支（`--selftest` + 全量各一遍）全 rc=0，除两条已知豁免见「遗留风险」。
- 新代码量：MoonBit 3 个文件（1 新实现 + 1 新测试 + 1 处分发改动）、Python 1 新判据 + 3 处既有守卫扩面、
  文档/账本 6 面同步。

## 任务分配记录

按本项目「四模式流水线」的口径，本轮是**修复 + 验证**两段的合轮，全部由指挥官 lane 亲自做完，未派子代理：
四条都是跨文件一致性/入口面缺陷，派工的核对成本高于直接修（且 `cmd/cli`、`src/server` 有并发写者，
分派会放大撞车面）。并发面的未提交改动**未被代为发布**（见下）。

## 遗留风险

1. **`cmd/cli/help_topics.mbt`（`fist help <topic>` 本体）与 `main.mbt` 的其余部分是并行改动面的未提交新增** ⇒
   本次提交只带「HEAD 正文 + 我自己的分发 hunk」（摘段双向验：暂存里不含对方行、工作区仍含）。
   对方随后整档写回时若丢掉 `parse_subcmd`，白盒会随文件一起消失，但**调用面判据会红**（CI 新步 `cli_flag_probe`）。
2. **`check_scripts_index` 本地红**：对方未登记的 `scripts/gen_help_docs.py`。HEAD 面上不存在该文件 ⇒ 不随本次进 CI。
   本轮不替对方收尾，只在此点名。
3. **干净树上的三连红已定位并修掉**（BUG-115，本轮第 3 笔）：暂存树首轮 535/532/3 failed，
   在 HEAD 的干净 worktree 里 `rm -rf temp` 复跑必红 ⇒ 三条全出自
   `src/engine/engine_execute_r2_test.mbt`（它开 `temp/*.db` 却不建 `temp/`，靠同包另一文件先建目录）。
   修后同条件 535/535。**这条同时给 BUG-111 里那句「Actions run 178→186 全 failed 但读不到日志」提供了一个可复跑解释**，
   但不据此宣称 CI 已全量绿（native 轨与别的红因还没归因）。
   方法论上的收获：**开发工作树里的"全绿"不覆盖新 clone**——凡是碰测试面/存储面的收口，
   第一次全量复跑要在 `git archive` 或 worktree 的干净树里做。
   另记一条**并发面事实**（不算我的账、也不并入本轮计数）：工作树里 `run_serve` 的横幅 `println` 被
   并行改动面重新启用（HEAD 按 BUG-101 是注释掉的）⇒ 本地 `python scripts/fist.py call cost_stats` 现在报
   `malformed JSON-RPC response: 'stdin/stdout 接管...'`，而 `list-tools` 走另一条路仍返回 129 工具。
   发布树里那三行是注释 ⇒ 不随本次发布，交对方收口时自查。
4. **`v0.3.4` 的公网复验在发布之后**：推送 + 标签触发 release 流水线有外部时延。本轮已把
   `e2e_irm_line.py` 的版本针改成从 `moon.mod` 反解（不再写死 0.3.3），所以 run 完成后重跑它就是复验，不必再改判据。
5. **native 轨仍非权威**：`build-native-windows` 在 CI 上红在 `Install MoonBit`（用 `install/windows` + Expand-Archive，
   与 ci.yml 的 `install/powershell.ps1` 不同形），带 `continue-on-error` 不顶掉发布；AGENTS 已写明门槛是 JS。

## 后续建议

- 把「全量测试红名单必须先读一遍」写进收口清单：本轮最贵的发现不是新 bug，而是
  **一条常驻锁在 master 上红了三个版本没人读**（BUG-114 的成因）。
- `fist version` 一类的自述面建议后续并入 `mcp_tool_tour.py --surface-selftest` 的同族判据（现在由 `cli_flag_probe` 承担）。
- 并行改动面收口后重跑 `moon info && moon fmt`，并复跑 `cli_flag_probe`（它的文案针从 `main.mbt` 反解，改写文案不会假绿但值得再看一眼）。

## 超额内容（用户没要求、本轮顺手做的）

- 拆掉判据自己的一处假账：`check_release_asset_names --selftest` 的 `R5×2` 里有一格因"变异只改注释"被循环跳过
  ⇒ **从没执行过**。格子清单与 PASS 行范围改为从实现反解，那格换成真变异。
- 把 `e2e_irm_line.py` 的 5 处写死 `0.3.3` 针改成从 `moon.mod` 反解（否则下次升版它必假红）。

## 来源

- 需求原句：「是不是还有bug? bugs.md 看下，有就启动修复模式 全部清掉」（本轮会话内，接在安装面收口之后）。
- 真源与判据：`memory/bugs.md`（抬头状态 + `### FIXED` 小记）、`scripts/check_release_asset_names.py`（R1-R11）、
  `scripts/cli_flag_probe.py`、`cmd/cli/subcmd.mbt`、`cmd/cli/subcmd_wbtest.mbt`、
  `src/server/fist-mbt_wbtest.mbt`（BUG-16 常驻锁）、`.github/workflows/ci.yml`（新步）、`.github/workflows/release.yml`。
- 过程记录：`CHANGELOG.md` 本轮段、`memory/2026-09-28.md` 收口段；一次性脚本与证据留在 `temp/`（不入库）。
