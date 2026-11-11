# 迭代轮 183 · mcpcf 前置行为锁 + 密封性批量推广 + 自述盲区审计 + 计划落点增量归零 · 汇报

- 日期：2026-11-09（根任务 T0 / ns `iter-1109b`；提交面现读 `git log --oneline -4`）
- 选模：explore 打分 → 车道 H=fix 前置（只加测试）／车道 I=advance（BUG-582 干净子类批量）／车道 J=bugfind 只读（自述无尺盲区）／车道 K=fix（BUG-589 计划落点增量归零）
- 权威门槛：JS 后端 `moon test --target js` = **2064/2064，failed: 0**（统帅当场复跑 + 提交后徽章尺 `--fresh` 二次读数，源码面锚点 == `4b45575e1`）

## 一、结果摘要

1. **车道 H：BUG-583 的「先补锁」前置已拆**（提交 `4b45575e1`，26 件）
   - 新增 `src/engine/engine_circuit_bug583_wbtest.mbt` 7 格 + `src/server/mcpcf_embed_bug583_wbtest.mbt` 4 格，
     产品码零改动、`.mbti` 零变化（`check_mbti_sync` PASS：27 份 `.mbti` 的 808 条 pub 声明逐条对表）。
     **mcpcf 面由此获得史上第一批测试。**
   - 锁层选择有现读依据：mcpcf 的时钟**不可注入**（`mcpcf_embed.mbt:267/:360` 内部现算墙钟，`set_engine` 只注入引擎），
     2039 那一档在调用层写不出来 ⇒ 退到引擎层锁两枚正性哨兵（`engine_circuit.mbt:136/:170`，`now_secs` 是入参），
     调用层只锁可达的那一半，并把**缺口本身**钉成一条会过期的断言（`bug583_04`：传 `now_secs=-2117514496` 被静默丢弃）。
   - 统帅亲跑复核：`src/engine` 395→**402/402/failed:0**、`src/server` 591→**595/595/failed:0**；
     计数差==新增格数即「真被执行」的证明（本仓 `moon test -f bug583` 过滤器返 0 匹配，不可用作执行证明）。
     零污染实证独立复核：`%LOCALAPPDATA%\mcpconftest\data\mcpconftest-ops.db` mtime 仍 `Oct 28 22:47` 未变。
   - **M3 变异改变了 BUG-583 的代价估计**：只把 `:267` 换成 ops 基、`:360` 逐字不动 ⇒ `mcpcf.watchdog` 把
     `opened_at` 读成「远在 1972 年」当场跳半开 ⇒ 方向①「2 处改动」更正为「**2 处 + 沙箱库清表**」，
     账本里「两基同库 ⇒ half-open 随机」那句从推论升级为活体复现（由 `bug583_03` 钉住）。
     M1/M2 的**分工**（各只点亮自己那一格集合）证明锁既不恒真也不撒红。
2. **两条新账**
   - **BUG-588**（low / testability，OPEN）：mcpcf 无时钟入参 + `ops_data_dir()` 默认目录测试内不可改道 +
     `:48` 库名硬编码 ⇒ 2038 档只能在引擎层锁。关闭条件 = 有注入点 **或** BUG-583 方向④「mcpcf 库路径 ≠ 主库路径」判据落地。
   - **BUG-589**（medium，OPEN）：`check_plan_landing.py --gate` 现读 **rc=1**（判定面 30 > 棘轮上限 25）。
     该尺在 `ci.yml` 被跑**两次**（约 :67、:253）⇒ 一旦 push 触发 CI，这一格会红；现在还没红**只是因为本地领先 origin/main 91 笔未推**——
     延迟引爆不是没问题。增量主形状是 `docs/2026-10-11-multi-agent-lock-design-v3.md` 用完成时口吻点名 8 条从未存在的路径
     （`engine_lock.mbt` / `store_locks.mbt` / `locks_ops.mbt` / `assistant_ops.mbt` / `kill_argv.mbt` / `kill_exec.mbt` /
     `templates/lock_wait_loop.md` / `memory/lock-config.json`），而锁族真实落点是 `reserve_scope`/`lock_renew`/`file_bind`/`src/filebind/filebind.mbt` 那一套。
     修法约束写进账：**放宽上限是人的决定**，不许改 `VERDICT_GAP_CEILING`、不许扩白名单、不许删计划承诺。
3. **判例-47 立案**（`docs/AGENTS-precedents.md`）：时钟不可注入时退层锁 + 把缺口钉成会过期的断言；
   锁缺陷行为的格必须逐格写明「修复后应变成什么」；变异**分工**才是证据；故意保持全绿的那格用来否定「只改存储」类假修复。
   `AGENTS.md` 指针 `~46→~47` 同批——判例尺又在**落盘后当场抓到滞后**并逼改（这是它第二次在同一轮里自证有效）。
4. **顺手关掉一处口径滞后**：`src/engine/engine_circuit_test.mbt:3` 的「需 SQLite 后端（Mem 后端 cb 为 no-op）」
   已落后于 BUG-439（车道 H 有 6 格走内存后端通过即反证）⇒ 改为「本文件按 SQLite 组织用例 + 旧理由已失效 + 换后端需另跑对照不在本轮」。
5. **两把尺的自证实录**：`check_foreign_ledger_entries` 把我写的 BUG-587 正文里 `.fist-mbt/data/` 判成「基线外外来条目」，
   按该尺自己给的出路登记进 `WHITELIST` 的 `meta` 段（带理由），复跑 rc=0 + `--selftest` 15/15；
   `scripts/README.md` 的 `meta` 清单自述同批补 587（不补就是下一个 J10 型滞后）。

## 二、资源消耗

- **模型/额度**：Qoder 内置 agent，全部本地；本会话无外部 token 支出。
- **车道**：H（前台，成功，11 格 + M1–M3）／I（后台，BUG-582 批量推广）／J（后台，只读盲区审计）／K（后台，BUG-589 分档修）。
- **fist-mbt 工具面**：`store_open(iter-1109b)`、`agent_acl_grant`×2（`lead-1109b` 行 `bee0446681e9675a` / `human_steward` 行 `6527cca83946fae6`，均 `pid_bound=false`）、`publish`、`claim`；后续 execute/submit/verify/archive 见 §八。
- **判据面**：`moon_test_env`（全量 + 两包）、`check_badge --fresh`、`check_fmt_gate`、`check_warning_ledger`、`check_bug_ledger_shape`、`check_bug_reference_integrity`、`check_foreign_ledger_entries`、`check_bug_ledger_scope`、`check_precedents_doc`、`check_mbti_sync`、`check_plugin_sync`(cl7)、`check_dist_snapshot`、`check_doc_surface`、`check_instruction_budget`、`check_battery_count_doc`、`check_store_tables_wired`、`check_selftest_hermetic`、`check_plan_landing`（含 `--gate`）、`gen_plugins`、`gh run list`。
- **墙钟**：轮 182 + 轮 183 连续作业，本段约 75 分钟。

## 三、任务分配记录

| 车道 | 模式 | 边界 | 状态 | 交付 |
|---|---|---|---|---|
| H | fix（只加测试） | `src/engine`/`src/server` 新建 wbtest，禁改产品码/账本/README | **已收口**（统帅亲跑复核） | 11 格前置锁 + M1–M3 变异 + 可测性缺口另立 BUG-588 |
| I | advance | 仅所选 `scripts/*.py`，禁改守卫/账本/锚点面，禁跑 moon | **已收口**（车道完成，统帅逐把复跑；车道因账户额度耗尽未及写汇总） | 4 把判据自检密封化，R 档 92→87；`310f5f50a` + `ee289b8f2` |
| J | bugfind（只读） | 不改盘，只跑只读判据 | **无交付**（账户额度耗尽中断，77 次工具调用后零盘面留存） | 盲区审计未完成，转下轮重派 |
| K | fix | 仅 `docs/**`（禁改尺、禁 git mv 执行） | **半成品收口**（车道完成文档改动，写完汇总前额度耗尽） | `--gate` 30→11、rc=0；六份文档落地对表；`cb4a77c64`；C 档 11 条只登记 |
| 统帅 | — | 账本、判例、指针、计数面、投影、提交、报告、FIST 台账 | 进行中 | BUG-583 追记 / 588 / 589 立账、判例-47、2053→2064 共 41 处、`gen_plugins`×2 |

## 四、遗留风险

1. **BUG-589 的门禁面在 push 后才会显形**：本地领先 91 笔，CI 从未跑过这些笔 ⇒ 「CI 绿」不能为本地状态背书（`gh run list` 现读只有 `Star gate attestation` / `Sync from GitCode` 两条自动线在绿）。车道 K 若只能把增量降到 C 档（真未落地），剩余项**必须转 owner**，不许用改上限或删承诺消红。
2. **BUG-583 仍 OPEN**：2038 后 mcpcf 熔断永久卡 Open；三档修复方向待裁决。本轮只交付了前置锁。另注意**定时发信器**：`mcpcf_embed_bug583_wbtest.mbt` 的 `bug583_02` Unix 正域带断言在 2038-01-19 之后会自己红——届时若仍未修，那是预期信号而不是判据坏了。
3. **BUG-584 残余**：墙钟越过声明域（>2037）⇒ `window_expired` 仍 fail-closed ⇒ 用量只增不减 ⇒ 最终 `available=false`；关闭条件 = 时钟 Int64 化（BUG-583 方向③）。
4. **BUG-587（台账库在构建产物目录）**：本轮靠 `moon build` 的 up-to-date 缓存侥幸未清档，不得据此判无风险；三档修法 + 「`data_dir` 不得位于 `_build/` 之下」判据待裁决。
5. **BUG-582 整体方向仍待 owner**：车道 I 只做干净子类；校准读类（`HERMETIC_CALIBRATION`）与结构冲突/G 档（call-face ⟂ 读锚点）不在其内。守卫自身设计终态不是零红。
6. **owner 既有裁决项不代翻**：BUG-527 / 542 / 565A（三案 + 计数面 + 双层守卫并存）/ 566（宿主审批门误判族）。
7. **非本批留账**：`scripts/explore_watchdog_wrapper.ps1` / `_prompt.md` / `_hidden.vbs` 仍未跟踪未 ignore（`check_publish_payload` 红面 3 条），属唤醒轮基础设施。
8. **推送面**：`origin/main` 仍在 `cdb241acf`；是否推、推前是否需要先让 CI 跑一轮，由 owner 决定（不可逆动作执行权不在本席）。

## 五、后续建议

1. 先修 BUG-589 的 C 档（真未落地）再谈降上限：把 `supervisor_tools_test.mbt` 这类**计划承诺**要么兑现要么改写成提案口吻；`VERDICT_GAP_CEILING` 的**下调**应在增量归零之后由机器提示、人批准。
2. 「自述无尺」盲区清单（车道 J）落地时优先补**行为级**判据而非文档扫描（判例：按语义取数，不靠排版；文档尺对不合形的自述天然免疫）。
3. mcpcf 若要长期活着，`FIST_RUN_CHECK_ALLOW` / `data_dir` / 库名硬编码这三条运维侧口径应统一成一份启动参数真源（现散在 `.mcp.dev.json`、启动器与 `mcpcf_embed.mbt:48`）。
4. 时钟 Int64 化专项建议单独立项：它能一并干掉 BUG-583、BUG-584 残余、ops_ts 的 2091 顶与 BUG-218 的 2037 顶。

## 六、超额内容

- 车道 H 除派单目标外，交付了 mcpcf 调用层可达性锁（`bug583_01/03/04`）与「只改存储无效」反证格（`bug583_07`），
  并把 M3 的意外发现转化为对 BUG-583 代价估计的**更正**（写进账本追记，不是只留在回传里）。
- `check_foreign_ledger_entries` 的 `meta` 登记与 `scripts/README.md` 自述同批补，避免制造下一个 J10 型滞后。

## 七、来源

- 车道 H 回传原文（本会话）+ 统帅亲跑：`temp/pt_round183.log`（2064/2064/0，RC=0）、`temp/pkg_engine_183.log`、`temp/pkg_server_183.log`、`temp/badge183.out`（锚点 == `4b45575e1`）、`temp/cl7_183.txt`、`temp/fle_after.txt`、`temp/plan_gate_183.txt`、`temp/hermetic_before_183.txt`。
- 台账面：`memory/bugs.md` BUG-583 追记 / BUG-587 / BUG-588 / BUG-589；`docs/AGENTS-precedents.md` 判例-47；`memory/2026-11-09.md` 轮 182/183 段。
- 车道 I / J / K 的回传与终审读数在它们收口后追加到本节，不预先抄未验证的结论。

## 八、轮 183 收口读数（统帅现跑，2026-11-09）

| 面 | 读数 | 说明 |
|---|---|---|
| 全量测试 | 2064/2064 / failed 0 / rc=0 | 车道 H 当轮实跑（`temp/pt_round183.log`），本轮四把脚本改动不触 moon 面 |
| `check_selftest_hermetic` | rc=0，**W=8 R=87 G=34** | 轮初 92 ⇒ 车道 I 还债 5 处；基线常量**未动**（棘轮只许升，见 BUG-582 追记） |
| `check_plan_landing --gate` | **rc=0，判定面 11 条**（上限 25） | 轮初 rc=1 / 30 条；`VERDICT_GAP_CEILING` 未动、白名单未扩、承诺未删 |
| `check_plugin_sync`（cl7） | rc=0，4 宿主 / 64 文件 / 182 工具 / v0.3.11 | `gen_plugins` 现跑后复核 |
| `check_battery_count_doc` | rc=0（rulers=155 ci=49 battery=115 gate=127） | 计数面未变（本轮无新增格） |
| `check_arg_face_strict` | rc=0（99 把全拒未知旗标） | 四把改动脚本在内 |
| `check_precedents_doc` | rc=0（判例-32..47 连续 16 条，指针对表一致） | 含本批引用形修正 |
| `check_publish_payload` | 三件唤醒巡检 scratch 进 `.gitignore` 后只剩**报告自身**未跟踪 | 报告随本批入库即清零 |

**车道收口状态（如实）**：I 已收口（`310f5f50a` + `ee289b8f2`）；K 半成品收口（`cb4a77c64`，C 档 11 条未处置）；
J 零交付（额度耗尽中断，无盘面留存）。三个后台车道**均因账户额度上限中断在汇总之前**，
所以本报告所有读数都是统帅现跑所得，没有一条转抄车道自述。

**未决项（转下轮 / owner）**：BUG-589 剩下的 11 条 C 档与「上限是否收紧至 11」；
BUG-587 的 `_build` 落点三选一；BUG-583 三档修法；时钟 Int64 化（BACKLOG P1）。

