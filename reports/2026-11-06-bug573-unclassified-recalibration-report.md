# BUG-573 收尾批 · 记账面换算法 + 登记理由旗标门 · 汇报

- 批次：2026-11-06 统帅批（本地两笔，**均未推送**）
- 落地提交：`2067bbb4f` fix(guards) 主件 · `b18ed4010` docs(guards) 收尾两面
- 台账：`memory/bugs.md` BUG-573（medium，本轮 OPEN→FIXED）

## 1. 结果摘要

**缺陷形状**：`run_guards.py --list` 长期报 `unclassified=7`，被读成「7 个脚本没人认领、门禁停摆」。
现读核证：这 7 个脚本**全部有执行面**（3 个在 REGISTRY、4 个在电池），`unclassified` 这个数字
从来没说过「缺面」——它是 `classify()` 按**名字形状**（`check_`/`probe_` 等前缀）分类时的兜底桶，
而 `missing=0` 那一格才是「有没有面」的权威。7→0 不是修了 7 个脚本，是**把一个口径错位的键换成
真判据**：`unclassified` 从此只装「跟踪面上、既不是门禁尺、也没有豁免理由、也不在任何执行面」的**真孤儿**。

**改动清单**（逐字取自 `git show --stat`）：

| 笔 | 文件 | 面 |
|---|---|---|
| `2067bbb4f` | `scripts/run_guards.py` +107/−5 | 记账面换算法 + 登记理由旗标门 + 7 格新自检 |
|  | `scripts/README.md` 3 | BATTERY-REGISTRATION 锚点 `unclassified 7→0`（含依据段落） |
|  | `memory/bugs.md` 11 | BUG-573 条目 + `### FIXED` 证据段 |
|  | `plugins/**` 10 | `gen_plugins.py` 一源四态重投影（同批，防 cl7 红） |
| `b18ed4010` | `scripts/README.md` 2 | `--selftest` 格数自述 37→51（对齐现读） |
|  | `scripts/check_battery_count_doc.py` 5 | 欠格拒因补第三成因「口径刚被改过」 |

**新门（第二件，独立于换算法）**：登记理由里声称的 `--旗标` 必须真的存在于该脚本参数面。
`install_git_hooks.py` 的理由写着 `--selftest`，而该脚本只有 `--install`/`--check` ⇒ 理由本身滞后，
`--list` 现在直接 FATAL 并 rc=1。这一门是判例-10「红着没人读等于没锁」的调用面版：
登记理由是要给人照着执行的，它错了执行面就跟着错。

## 2. 资源消耗

- 模型：本会话主代理（统帅）+ 4 个 `general-purpose` 子代理车道（并发，见 §3）。
- 工具面：`Bash`（现读取数、判据复跑）、`Read`/`Grep`/`Edit`/`Write`、`Task*`；无 MCP 写入型工具消耗（`report_bug` 在本轮因 §4 的 server-cwd 问题落到错树，未采信）。
- 判据跑动：`run_guards.py --selftest`（51 格）、`check_battery_count_doc.py`（selftest 15 格 + 现跑）、
  `check_selftest_hermetic`、`check_hardcoded_paths`、`check_new_script_hygiene`、`check_arg_face_strict`、
  `check_doc_surface`（J1–J19 PASS）、`check_doc_dup`（scripts/README.md 716 行 / 登记块 173 / 无重复登记）、
  全量电池 160 格、`gen_plugins.py` 重投影。
- 现读收口数（本批写完后当场跑的，不是抄的）：
  - 全量电池：`格数 160（手写 160 + 自动 0）/ 失败 0 / SKIP 0 / 缺执行面 0`，`BATTERY RC=0`
  - 锚点：`rulers=153 ci=48 battery=113 missing=0 gate=125 exempt=23 unclassified=0`
  - 账本投影：`ledger=BUG-1~573 共 558 条入账：5 条待修 / 512 条已修 / 13 条重复并入 / 28 条误报`
  - OPEN 逐条点名（5）：BUG-527 / 538 / 542 / 565 / 566

## 3. 任务分配记录（忌亲力亲为：4 车道并发，worktree 隔离）

| 车道 | 边界 | 状态（本汇报落盘时现读） |
|---|---|---|
| `agent-general-purpose-04625cfe` | 退役 `src/engine/auth_mode.mbt`、`engine_rsv.mbt` 两处滞后自述（散文面，不动符号） | 工作树内 2 文件已改，**待统帅终审**（`moon check` + 格式门 + 全量 src/engine 由统帅跑） |
| `agent-general-purpose-ff4ebfe9` | `scripts/run_guards.py` 前缀面同源（`GATE_PREFIXES` ↔ `AUTO_CASE_PREFIXES`，要求电池格集合零变化） | 工作树内 1 文件已改，**待统帅终审**（与本批 `2067bbb4f` 同文件，须核后合流） |
| `agent-general-purpose-14fed5fe` | 新增 `scripts/check_stale_self_claim.py`（把 AI-DEV-STD §4.1 缺陷类钉成门） | 尚无提交/改动，在途 |
| `agent-general-purpose-773233d4` | 计划治理面：`docs/plans/archived/` + `check_plan_location.py` 加宽到 `docs/proposals/` | 尚无提交/改动，在途 |

统帅亲笔只做：判据口径裁决、锚点数字、提交与重投影同批、终审跑全量。

## 4. 遗留风险

1. **两笔未推送**：本地领先 `origin/main` 约 38 笔。推送 = owner 红线（`git push origin main` + `git push gitcode main`，之后按 40 位全 SHA 逐条核双臂 CI）。staleness 类判据只扫 `gitcode/main`，推送前本地红是预期态。
2. **`report_bug` 落错树（BUG-565 A 半未修）**：插件连接器 server cwd 落在 `_build/js/release/build/cmd/cli`，
   本轮 `report_bug` 写出的是那棵树的 `BUG-1`。本批因此**放弃 RPC 落账**，改为直接追加 md 真源并按现读最大号 +1 取号。
   风险仍在：任何走 RPC 的落账动作都可能落到错树，且调用方无出路（绝对路径被设计拒绝）。
3. **口径换算法的传染性**：`unclassified` 语义变了，历史报告/日志里那句「7 个未归类」不再可比。
   已在 `check_battery_count_doc` 的拒因里补「或这一键的算法口径刚被改过（BUG-573 的 7→0 就是这一档，不是格子被删）」，
   让下一轮读到欠格时不会误判成「有人删了登记」。
4. **`check_selftest_inventory_doc` 没钉住 run_guards 自己的 selftest 格数**：它跑 59 面全清，
   但对 `run_guards.py --selftest` 的格数自述不做对表 ⇒ 本轮 44→51 的滞后靠人眼发现（已用第二笔对齐）。
   这是覆盖缺口，不是已修面。
5. **并发车道同文件风险**：`ff4ebfe9` 与本批都改了 `scripts/run_guards.py`。合流时必须重跑全量电池，
   不能拿本批的 160/0 读数代替合流后读数。

## 5. 后续建议

- 优先收 §3 两条「已改待终审」车道：`moon check` + `python scripts/check_fmt_gate.py` + `python scripts/moon_test_env.py --target js test src/engine`，通过后再谈合流。
- 下一把尺（无人认领，建议立单）：把「判据自身的 `--selftest` 格数自述 ↔ 现读」做进 `check_selftest_inventory_doc`，
  覆盖 `run_guards.py` 这类超大判据；照 §4.1 的路子走 `check_stale_self_claim` 车道，避免两把尺重叠。
- 旗标门可以再放宽一层：现在只查「理由里声称的旗标在不在脚本里」，还能查「声称的 rc 契约在不在」（同族滞后，尚未做）。
- owner 侧待裁决清单不变：BUG-527 出路②上游 issue、BUG-538 连接器重连、BUG-542 A/B、BUG-565 A 三案 + B 启动器部署、BUG-566 harness 侧。

## 6. 超额内容

- **两条变异对照真跑**（判例-29/30 要求「改坏代码不是注释」）：
  ① 把 `classify()` 里 `elif unlabeled_orphan(rel, owned):` 那行摘掉 ⇒ 对应格当场红，证明这行接线承重；
  ② 把 `stale_reason_flags()` 的「否定句跳过」分支摘掉 ⇒ 「`refresh_dist.py` 的理由写『无 --selftest 旗标』是**真话**」那格红，
  证明门只对肯定式声称发红。第二支原本差点做成误红：第一版 crude 扫描把这条真话报成了滞后声称。
- **两支负对照 + 一次自曝**：合成 `reg unclassified=7` vs 现读 0，跑出的是**新加的第三成因文案**（不是只写在源码里），
  证明拒因到了运行时消息面；另两支失败夹具（`orphan_demo.py` 撞「演示/示例脚本」豁免、`zqk_unlabeled_probe.py` 撞 `probe_` 一次性探针豁免）
  暴露出「对照格根本没走到目标分支却打印跑过了」的形状，已改为先断言夹具名既不命中 `is_gate` 也不命中 `exempt_reason` 再跑。
- **长耗时读数期间冻结被检件**：全量电池 160 格跑的期间不改任何被扫文件，收尾两面（README 自述 + 欠格拒因）排在电池收 rc=0 之后，
  避免「回执证明的是建树那一刻的字节」。

## 7. 来源

- 本仓：`memory/bugs.md` BUG-573 条目与其 `### FIXED` 证据段（现读最大号 572 ⇒ 取 573）
- 本仓：`scripts/run_guards.py`（`owned_script_names` / `unlabeled_orphan` / `flag_claims_in_reason` / `stale_reason_flags` / `classify(extra_owned=)` 与新 7 格自检）
- 本仓：`scripts/README.md` BATTERY-REGISTRATION 锚点段落（依据原文随批落盘）
- 本仓：`scripts/check_battery_count_doc.py`（欠格拒因第三成因，legend 与 runtime 两处）
- 本仓：`AI-DEVELOPMENT-STANDARD.md` §4.1（滞后自述缺陷类，车道 #40/#41 的规范依据）
- 本仓：`memory/2026-11-06.md` 续24 段（过程日志与收口读数）
- 本机判据读数：全量电池 / `--list` 锚点 / `check_doc_surface` / `check_doc_dup` / `gen_plugins` 投影行，均为 §2 所列现跑结果
