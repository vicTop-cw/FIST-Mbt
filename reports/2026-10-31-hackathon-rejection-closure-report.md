# 九月黑客松拒收六项整改 · 收口报告

- 日期：2026-10-31（本地 09:10–10:20，UTC 01:10–02:20）
- 触发材料：组委会回执原文（用户转述）——「申报明确承诺物理多租户隔离、自动修复三轮和可替换 Executor，均属核心而非质量目标：实际 alpha/beta 库零任务，任务写同一主库；错误指纹修复返回零修复；外部实现 Executor 报 readonly；Native 的 serve/demo 正常参数仅输出帮助。此外，DAG 接受成环依赖，Omega 验收门可由 archive 绕过。」
- 执行者：Qoder 主会话（统帅本人动手，未派子车道；只派了 3 路只读侦察）
- 工作区前提：**同一棵树上有其它 lane 在写**（src/ 在 09:52 有一批非本人改动、README/AGENTS/CHANGELOG/USAGE/scripts/README 均被占）⇒ 本次全程只用明确路径提交，**不碰被占的文档面**

## 一、结果摘要

六项逐条打到调用面复验，**五修一立案**，六格一键复验探针全绿；
收口时读 CI 原始回执又**实测抓出一项不在拒收单里的跨平台缺陷**（BUG-507，见第七行）：

| # | 拒收项 | 结论 | 落点 |
|---|---|---|---|
| ① | 物理多租户隔离（alpha/beta 零任务） | **修**：八条无人值守/自愈写路径由「传全局 `engine`」改为过 `engine_for_ns` | BUG-501 |
| ② | 自动修复三轮（零修复） | **修**：handler 改接持有原文的三轮引擎；`live` 内容表使下一轮在上轮产物上收敛；`max_rounds` 真消费；摘掉「未知根因→重算指纹盖章」的洗白分支 | BUG-502 |
| ③ | 可替换 Executor（报 readonly） | **修**：`pub(open) trait Executor` + 一组 pub 访问器/构造器；新增**独立包** `tests/external_executor/` 实现两个执行器跑通同一调用点 | BUG-505 |
| ④ | native serve/demo 仅输出帮助 | **参数分派面已修**（BUG-159，本轮在 WSL 真跑三臂复核：version/serve/demo 均不回帮助）；本轮补：发布资产「内部文件魔数↔资产名声明平台」进判据、`user_arg` 补缺失 cfg 臂；**native 轨 `cli_exit` 退出码不生效立案 BUG-506（OPEN）** | BUG-506 |
| ⑤ | DAG 接受成环依赖 | **修**：环闸抽成唯一真源 `depend_edge_ok`，三条写边入口全部接线；upsert 改为「任一边被拒 ⇒ 整条不写」；新建通道的悬空依赖同样拒 | BUG-503 |
| ⑥ | Omega 验收门可由 archive 绕过 | **修**：抽出 `omega_archive_gate`，`archive` / `archive_force` / **自动续轮 `publish_next_round`**（原先完全没有门）三条路径同源；门判在建新轮任务之前，不留半套状态 | BUG-504 |
| ＋ | **本轮实测新发现（不在拒收单里）**：CI 的 JS/ubuntu 臂 `Test (js)` 两格真红 | **修**：`.mbt` 放行规则的临时目录只认 `TEMP`/`TMPDIR`/`TMP`，而 ubuntu runner 三个都不给（本机 WSL 实测 `TMPDIR=[] TEMP=[] TMP=[]`）⇒ 落盘失败 ⇒ `mbt_include` 恒 false。抽成纯函数 `ocr_temp_candidates(env)` 并加 POSIX `/tmp`、`/var/tmp` 兜底；拒绝原因改为点名试过哪些候选 | BUG-507 |

> 第七条是我读 **CI 原始回执**（`gh api actions/jobs/<id>/logs`）而不是读文档发现的：
> `origin/main` 的 CI 在本轮之前已连续两次红（run `41063304724` / `41145839030`），红的是 `Test (js)`
> （`Total tests: 1983, passed: 1981, failed: 2`），而**本机 Windows 全量永远 100% 绿**——
> 有 `TEMP` 就测不出这一形（判例-33「服务本体 ≠ 服务接入」、判例-37「文本命中 ≠ 行为覆盖」同族：
> **本机绿 ≠ 双环境绿**）。申报书里那句「JS 后端 Windows 与 Linux 双环境均可复现」在此之前是假的。

复验面分两栏，**第一栏克隆即有**（评委不必依赖本轮工作树的私物）：

**A. 仓内复跑（已随本笔提交进 git）**

```bash
python scripts/moon_test_env.py --target js        # 全量，含本笔新增 19 格锁
```

新增锁逐一点名：`src/engine/engine_acc_reject_wbtest.mbt`（7 格：环闸三拒 + upsert 关环且盘上 `depends_on` 未变 + 续轮被拦且不建 `T0r2` + 归档同门对照）、
`src/omega/omega_acc_fix_test.mbt`（4 格：坏指纹被真修 + `fixed_specs` 可复用再验 + 未知根因不重盖章 + `max_rounds` 夹紧）、
`src/evidence/evidence_acc_fix_test.mbt`（预算与两轮收敛）、`tests/external_executor/external_executor_test.mbt`（**独立包**实现两个 Executor，3 格）、
`src/server/ocr_scan_wbtest.mbt` 的 `BUG-507` 三格（空环境也必须给出 POSIX 兜底候选／候选不得含空串／环境变量优先且顺序不变）——
第三栏那格钉的是「Linux runner 上三个 env 都不给」这一形，**在 Windows 本机也能跑红**（它断言的是候选表本身，不是本机目录）。

**B. 活体探针（本轮工作树内可跑，入库动作被并发车道挡住，见 §四.7）**

```bash
moon build --target js --release && python scripts/patch_esm_main.py _build/js/release/build/cmd/cli/cli.js
python scripts/blackbox/e2e_acceptance_recheck.py --selftest --json
```

2026-10-31 本机读数：`A1 PASS / A2 PASS / A3 PASS / A4 SKIP / A5 PASS / A6 PASS / ST1 PASS`，rc=0。
A4 回 SKIP 的理由写在回执里：本机是 Windows 而公网只发 `fist-mbt-native-linux-x64` 一个 native 资产——
**探针拒绝拿 WSL 读数冒充 Windows 交付物**（判例-33：服务本体能跑 ≠ 服务被正确接入）。

## 二、资源消耗

- 时间：约 70 分钟墙钟（含 3 次全量/局部测试等待）。
- 测试：全量 JS 轨 `Total tests: 2002, passed: 2002, failed: 0`（HEAD 基线 1983 + 本笔新增 19 格；
  收口后又用最终树复跑一次，同数）；
  分包复跑 `src/engine 389/389`、`src/server 563/563`（BUG-507 三格另以 `-f "*BUG-507*"` 单跑 3/3）、`src/omega 56/56`、`tests/external_executor 3/3`。
- 构建：`moon build --target js --release` 3 次；`moon fmt` + `moon info` 各 2 次（第二次 0 改动）。
- 判据：`check_bug_ledger_shape` / `check_doc_surface` / `check_plugin_sync` / `check_scripts_index` /
  `check_demo_isolation` / `check_arg_face_strict` / `check_warning_ledger` / `check_fmt_gate` 全 PASS；
  `check_test_sync`/`check_badge` 见 §四.2（脏树下降为 ADVISORY，本笔不烧数）。
- warning 回基线：新文件自带 **11 条** warning ⇒ `test_unqualified_package`×10 与 `missing_pattern_arguments`×1
  **改代码**消掉（加 `@omega.` 限定、`Json::Number(n, ..)`），`unused_package`×2 与 `consistency/moon.pkg` 同形
  （整包只有一份 `_test.mbt`）⇒ 登记进 `docs/warning-ledger.md` L4、§2 计数 4→6、合计 46→48。
  现读 `moon check --target js` = **48 warnings / 0 errors**，台账 L1 27/27、L2 7/7、覆盖率 100%。
- 插件投影：`check_plugin_sync` 先红（9 文件漂移）⇒ 先核漂移**只由我的账本驱动**（BUG-1~506 / 1 条待修），
  再 `gen_plugins.py` 重生成 ⇒ PASS（4 宿主 / 64 生成文件 / 182 工具 / v0.3.10）。
- 变异对照：**5 次真跑**（M1' 摘 upsert 环闸 → 2 格红；M2 门判错对象 → 1 格红；M3 恢复洗白分支 → 1 格红；
  M4 把 POSIX 兜底 `["/tmp","/var/tmp"]` 改成 `[]` → BUG-507 三格 **3/3 红**；
  外加 A2/A5/A6 三格的「修前 FAIL」活体对照）。
  **M4 之后按字节还原**（`还原字节相同 = True`，29180↔29180）并复跑 3/3 绿 ⇒ 判例-30 的还原纪律这次做到了，
  与上午 M3 那笔「忘了还原」形成对照（同族债还得当场还）。

## 三、任务分配记录

| 角色 | 干什么 | 回传 |
|---|---|---|
| 统帅（本人） | 意图判定、六项定位、代码修复、锁与变异对照、账本/报告/申报书/PDF、探针脚本 | 本文件 |
| Explore 子代理 ×3（只读） | 并行侦察「多租户隔离 / 自动修复 / Executor+native+DAG」三条面的 file:line 证据 | 已并入 BUG-501/502/503/505 的 detail |
| 其它 lane（并发） | 同一时间窗内在改 src/ 与文档面 | **未并入本笔**，见 §四红线 |

## 四、遗留风险（如实，含本笔自己造成的过程债）

1. **native 轨 `cli_exit` 不生效**（BUG-506，OPEN）：未知子命令 js 轨 rc=2、native 轨 rc=0。
   纯函数侧有锁（`cmd/cli/subcmd_wbtest.mbt:19-21`），坏在 extern→libc `exit` 那一跳。
   本轮**没修**的结转理由与三条出路都写进账本了：判绿需要真 native 产物复跑，而 Windows 本机
   native 构建要 MSVC+sqlite3.lib，且在共享树起 native 全量构建会与其它 lane 抢 `_build`。
2. **测试计数现状面未扫（CI 现在红在第 22 步的 `check_badge` 自证拒判上，把第 24 步 `check_test_sync`
   该报的那格一起挡掉了——见 §四.9 与 BUG-508；数字那一格本身是已知且故意留的）**：
   实测 `python scripts/check_test_sync.py --total 2002 --strict` ⇒ **26 条违例，分布在 10 份现状面**
   （README_EN.md ×5、AGENTS.md ×5、README.md ×4、scripts/scoring_rubric.md ×2、docs/deliverable.md ×2、
   docs/SOP.md、README.mbt.md、ARCHITECTURE.md、docs/agent-map.md、docs/known-boundaries.md）。
   **为什么本笔不扫**（两条都是实测，不是推诿）：
   ① `README.md` / `AGENTS.md` 此刻是 lane-R115 的未提交 WIP（4 行改名指针对齐），按判例-11 带 `-- <明确路径>`
      提交＝把他们那 4 行也写进我的提交；`scripts/run_guards.py`（128 行改名批量）同理被占；
   ② 当时写这条的理由是「1999 只在脏树成立」——**这条已被 CI 削弱，如实更正**：推送后 ubuntu runner
      在**干净树**（只有我的三笔、不含 lane-R115 的在途测试）上实测出**逐字相同的 2002**
      （`temp/ci_after_push.log:1877`）⇒ 2002 是「当前 HEAD 的合法读数」，不是本机私物。
      但**它仍然不是最终数**：lane-R115 那批在途文件里还有测试，他们落地后 N 会变；
      而 ①（`README.md`/`AGENTS.md`/`USAGE.md`/`BACKLOG.md`/`CHANGELOG.md` 是他们的未提交 WIP）
      依旧成立 ⇒ **同步这一笔现在做不了**，只能等他们落地。
   ⇒ 正确处置：**由最后落地的那一笔**做 `docs: 测试总数 1983 → N 同步`（本仓惯例），
      且 N 必须是在**干净树**上重测的数。这一格连同执行法一起结转，不伪装成已完成。
3. **执行器抽象层与 MCP 通道仍是两条**：`mcp_delegate.mbt` 的 `delegate_execute` 无生产调用点；
   注册表存名字+能力标签、不持有 trait 实例 ⇒ 「远程沙箱/第三方 Agent」需本地包装可执行文件。
   已写进申报书 §3「如实边界」与账本 BUG-505 的「未锁的缺口」。
4. **`heal` 不传 ns 时只扫主库**：文案已从骗人的 `all-namespaces` 改成 `main-db/all-ns-rows` + `scope_note`，
   但**真跨库扇出没做**（要复用 `supervisor_ns_candidates` 那套聚合，属独立决策）。
5. **本笔的过程债（不粉饰）**：M3 变异注入后我**忘了还原**就去写下一项，靠全量测试那 1 格红兜住
   （`src/omega` 55/56）。判例-30 与本仓 BUG-432 都记过同一形状的坑，这次又差点重演 ⇒
   已在 BUG-502 的 evidence 里当场自曝。
6. **公网交付物仍落后于 HEAD**：GitHub Release 最新是 v0.3.10（2026-10-30 04:41Z），
   本笔改动**尚未发版**。若评委按公网资产复验，必须先把这批改动发出去（见 §五）。
7. **探针脚本还没进 git（与第 2 条同一个成因）**：`scripts/blackbox/e2e_acceptance_recheck.py` 本轮实测可用，
   但一 `git add` 它，`check_battery_count_doc` 立即 FATAL「缺面清单：blackbox/e2e_acceptance_recheck.py」
   —— AGENTS 那条「往 `scripts/` 加 `.py` 必须同批给执行面」。执行面在 `scripts/run_guards.py` 的 `REGISTRY`，
   而该文件正被 lane-R115 的改名批量占着（未提交 128 行）。
   **没走的两条捷径**：改文件名命中 `UNIVERSE_EXCLUDE_RE`（`verify_` / `_` 前缀）躲普查＝判例-39「改名不是接线」；
   **先加 `REGISTRY` 行、脚本暂不跟踪**更危险——台账点名的脚本不存在 ⇒ G2 在他机/CI 上 FATAL、整台电池卡死
   （`5be75f1e` 现场已写在 `run_guards.py` 注释里）。⇒ **面与脚本必须同一笔提交**，故随 lane-R115 落地后一起补：
   `REGISTRY` 一行 + `git add` 探针，两步同批，缺一必红。
   本报告与申报书因此把「克隆即有」的复验口径写在 §一 A 栏（19 格具名锁），不用一条仓里还不存在的路径充证据。
8. **BUG-507 的 Linux 正身已复验到（本笔唯一由外部事实关闭的一格）**：推送 `a7080f728` 后
   CI run `41171466812` / job `124450135277` 的 **步骤 21 `Test (js)` = success**，
   原文 `Total tests: 2002, passed: 2002, failed: 0`（本机与 CI 读数逐字相同）。
   ⇒ 这条跨平台主张不是拿本机绿抵的；关闭证据是 ubuntu runner 上同一条命令的汇总行。
9. **CI 上还挂着一格与本笔无关的红，且它挡住了后面 8 步（另立 BUG-508，OPEN）**：
   `check_badge.py` 被 CI 以**裸跑**方式调用（`ci.yml:189`），而它要求快照同目录有源码面锚点
   `<log>.src`——CI 从来没人写这个锚点（唯一写入口是带 `--fresh`/`--fresh-if-stale` 的那条路）。
   实测正文：`REJECT SNAPSHOT-STALE … rc=2，不冒用违例红`。
   ⇒ 这是**判据主动诚实沉默**被 CI 当红，与产品无关；更糟的是它一红，fail-fast 把
   第 24 步 `check_test_sync`（真正该报「文档 1983 ≠ 实测 2002」那一步）一起 skipped 掉了。
   修法是一行（改 `--fresh-if-stale`；ubuntu 全量实测只花 41 秒），但它**必须与 §四.2 的数字同步同批**：
   改完照旧红（徽章仍是 1983），拆成两笔只会各红一次。成因、实测与为什么没单改都写进账本了。

## 五、后续建议（按性价比排序）

1. **发版（0.3.10 → 0.3.11）——owner 已点头，但此刻做不到，缺的是版本号现状面**：
   **已做**：`git push origin main` 落了 3 笔（`b2a7bf14` / `32bd6325` / `a7080f72`），CI 的 `Test (js)` 已由红转绿。
   **未做**：版本号声明分布在 `moon.mod` + `src/server/server.mbt` + `cmd/cli/help_topics.mbt`(`FIST_VERSION`) +
   **`README.md` / `USAGE.md` / `README_EN.md` / `BACKLOG.md` / `CHANGELOG.md`**，后五份此刻全是
   lane-R115 的未提交 WIP（每份 1~3 行**改名指针对齐**，如 `output_validate.py`→`check_output_validate.py`）。
   ⇒ 一并提交会同时犯两个错：① 判例-11（别人 WIP 进我的提交）；② HEAD 的文档指向「HEAD 里还不存在的脚本名」
   ⇒ CI 第 12 步 Doc-path references guard (R135) 当场红。更糟的是他们随后提交会用自己的副本**覆掉我的版本行**
   ⇒ 已发的 tag 与仓库自述脱钩。⇒ 顺序只能是：**R115 落地 → 数字同步 → 版本号前进 → 打 tag → 出资产**。
   同批还要把 Windows native 臂的 `continue-on-error: true` 摘掉或补 `sqlite3.lib` 就绪步骤
   （它长期静默失败 ⇒ 公网至今只有 linux-x64 一个 native 资产，这正是「native 只会打印帮助」这类误读的土壤）。
2. **一笔结转（等 lane-R115 落地后一起做，两半同批、缺一必红）**：
   ① `docs: 测试总数 1983 → N 同步`——N 必须在**干净树**上重测（现在脏树读的是 2002，含别人在途的测试），
      违例面实测 26 条 / 10 份文件（清单见 §四.2）；
   ② `scripts/run_guards.py` 的 `REGISTRY` 加一行 `"blackbox/e2e_acceptance_recheck.py": "端到端探针：起真 server + node 产物 + 沙箱库，需运行前提，跑法见 scripts/README.md"`，
      **与 `git add scripts/blackbox/e2e_acceptance_recheck.py` 同一笔提交**（理由与禁走的捷径见 §四.7）；
   ③ `ci.yml:189` 的 `check_badge.py` 补 `--fresh-if-stale`（BUG-508：现在那一步结构上永远 rc=2，
      并把第 24 步 `check_test_sync` 挡成 skipped；改完才看得到「徽章 1983 ≠ 实测 N」那一格的真红）。
   ⇒ 三半同批做完，CI 才有机会一次转绿；拆开做只会各红一次。
3. **把 `e2e_acceptance_recheck.py` 挂进 CI**：六格逐条打到调用面，比任何「已修复」叙述都硬；
   挂目前会因 A4 的 native 臂在 Linux runner 上真跑而多测出 BUG-506 那一格（**这是好事**，红在真缺陷上）。
4. **BUG-506 关闭路径**：优先做账本里的出路①（CI native 臂加行为面判据 + 换可靠退出方式），
   拿不到就把 `cli_exit` 在 native 臂改 `abort()`（rc=134，至少非 0 且可诊断），别留 rc=0 的静默。
5. **执行器两条并一条**：把 `executor_run` 的派发点接上 trait 注册槽（需 store 侧新增命令模板落库面），
   否则「可替换」在包外成立、在生产链路上仍要靠 CLI 通道。

## 六、超额内容（本笔顺手做的、不在派单里）

- 给 `heal` 回执补 `scope_note`，并把 `backend` 从「主库自述」改成「实际在扫的那台库」——BUG-119 那套
  「后端身份必须写在回执里」的要求，在 ns 路由之后本来会说谎。
- `check_bug_ledger_shape.py` 复跑（收口终读：**494 抬头 / OPEN 2**——BUG-506 与 BUG-508）确认新账目形态干净。
- `publish_with_deps` 的悬空依赖以前静默写进库、要等 `dag_check` 才红，本笔改为落库前拒。
- `supervisor_task_upsert` 的「任一边被拒 ⇒ 整条不写」按本仓「事务性迁移」口径统一，不留半套改动。

## 七、来源

- 拒收回执：用户消息（2026-10-31 转述组委会通知原文）。
- **CI 原始回执（BUG-507 的唯一成因来源）**：`gh api repos/vicTop-cw/FIST-Mbt/actions/runs` 的
  run `41145839030` / `41063304724`（`origin/main` 连红两次）→ `actions/jobs/124370614726` 步骤表
  （20 Format check=success·带 continue-on-error，21 Test (js)=failure）→
  `actions/jobs/124370614726/logs` 原文（留盘 `temp/js_job.log`，两条失败断言逐字在 1839/1840 行附近）。
- 实测原件：`temp/acc_recheck_probe.py`（第一轮探针）、`temp/acc3_probe.py`（I5/I6 专项）、
  `temp/full_js_suite_b507.txt`（全量 **2002/2002** 汇总行；`temp/full_js_suite_final.txt` 是收口前那跑的 1999）、
  `temp/b507*.log`（BUG-507 三格：修前红/修后绿/变异 3 红/还原复绿）、`temp/b507_pre_mutation.bytes`（变异前字节底）、
  `temp/acceptance-recheck/*`（六格沙箱与 JSON 证据）、
  `temp/native_wsl_probe.txt`（native 三臂真跑）、`_release/native/fist-mbt.exe`（ELF 魔数 + WSL 读数）。
- 代码面：`src/server/server.mbt`、`src/engine/{engine,engine_dag_ext,engine_supervisor,engine_archive_force,omega_strong}.mbt`、
  `src/omega/omega_tool.mbt`、`src/evidence/{auto_repair,evidence_acc_fix_test}.mbt`、`src/executor/base.mbt`、
  `cmd/cli/main.mbt`、`tests/external_executor/*`、`src/engine/engine_acc_reject_wbtest.mbt`、
  `src/omega/omega_acc_fix_test.mbt`、`scripts/blackbox/e2e_acceptance_recheck.py`（未入库，见 §四.7）、
  **BUG-507 面**：`src/server/ocr_scan.mbt`（`ocr_temp_candidates` 纯函数 + POSIX 兜底 + 拒绝原因点名候选）、
  `src/server/ocr_scan_wbtest.mbt`（`BUG-507` 三格）。
- 账本：`memory/bugs.md` BUG-501～BUG-507（含每条的 FIXED 小记与回归锁点名；BUG-506 仍 OPEN）。
- 判据与纪律依据：`AGENTS.md` 判例-29 / -30 / -32 / -33 / -36 / -37、R207（未知旗标必须拒）、判例-11（提交带明确路径）。
