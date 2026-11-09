# 迭代轮 182 · BUG-580 同族 Int32 普查 + BUG-582 密封性试点 + 三单修复 · 汇报

- 日期：2026-11-09（根任务 T0 / ns `iter-1109`，七态闭环 execute→submit→verify→archive）
- 选模：explore 打分 → 车道 E=bugfind（同族普查，只读）、车道 F=advance（BUG-582 试点）、车道 G=fix（三单修复 + 一单只读调查）
- 权威门槛：JS 后端 `moon test --target js` = **2053/2053，failed: 0**（统帅当场复跑，非车道自述转抄）

## 一、结果摘要

1. **同族普查（车道 E）→ 4 实锤 + 1 排除 + 设计边界清单**
   以 BUG-580 的形状（`iso_to_epoch` Int32 绕回 + `stale_hours*3600` 单加法绕回 + 正性哨兵）为模板扫 `src/`，
   用 temp/ 独立 MoonBit 探针做四格对照（含负值/远未来臂），**17/17 PASS**：
   - **BUG-583**（high，立账 OPEN）：`src/server/mcpcf_embed.mbt:267/:360` 把裸 Unix 秒 `.to_int()` 截断喂 Int32 熔断器 ⇒ 2038-01-19 后 `src/engine/engine_circuit.mbt:136/:170` 的 `>0` 哨兵恒假 ⇒ 熔断永久卡 Open、stale 复位失效。
   - **BUG-584**（high，已修）：`ModelQuota::in_cooldown` 的 BUG-206 fail-open 意图**只落在 cool 臂**，now 臂的 -1 哨兵让 `-1 < cool_secs` 恒真 ⇒ 模型永久锁死，坏 `now` 串**今天**即可达。
   - **BUG-585**（medium，已修）：`src/server/model_router_ops.mbt:682` 的 `secs_to_iso(now_secs + secs)` 单加法绕回 ⇒ 产出 `""` ⇒ 冷却被**静默清除**（fail-open，回执零提示）。
   - **BUG-586**（low，已修）：`next_switch_at` 三处各写一遍同形加法 ⇒ 大窗口给空串或 2038 不可表示日期（纯展示面）。
   - **排除项 E5**：`src/filebind/filebind.mbt:146/:498` 的 `bound_at + ttl - now` 中间量确绕回，但 mod-2^32 同余抵消且真值恒可表示（四臂探针证实）⇒ **非缺陷**，已写进 BUG-583 detail 防后续车道重复误报。
   - **方法论实锤**：`600000` 风暴臂在 BUG-580 那一轮证伪过一次，本轮 E1 的减法臂与 E5 再次因**双回绕同余**"碰巧正确" ⇒ 真正要盯的是**单加法/截断 + 正性哨兵**这三形，减法形上不要再浪费探针。
2. **BUG-582 密封性试点（车道 F）→ 一脚本 2→0，守卫 rc 1→0**
   Triage 现读 155 处 / 52 脚本，分六档（W=8 写真树 / R=94 读现状 / G=34 subprocess 打真仓 / S=4+T=7 记账 / C=8 校准读）；红档 136 在棘轮基线内，唯 R 越线 2。
   选 `scripts/render_dsh_patch.py` 做模式②试点：T14 从读真仓模板改为**写干净模板进 temp 沙箱再读回**，主面 `main()` 仍读真模板跑 `template_problems` ⇒ 零覆盖损失。归一化集合差对表 **removed=2 / added=0**（其它脚本严格零变化），越线量恰被移除 ⇒ `check_selftest_hermetic` **rc=1→0**；变异对照在 temp 沙箱重新引入违例 ⇒ 守卫真实 `scan()` 重新冒出 2 条 R ⇒ 尺子真在看。
   边界如实：剩余 134 处红档是**基线内接受债**，不是本批新红，也不构成 BUG-582 全修。
3. **三单修复（车道 G）→ 17 格回归锁 + 5 支变异对照真跑**
   - 新基元 `iso_domain_upper_secs()`：对 `iso_to_secs ∘ secs_to_iso` 往返谓词**二分反解**，不写死年份/秒常数，谓词不再单调即自拒回 0（宁可让调用方拒绝一切，不许"上界算大 ⇒ 绕回又回来了"）。
   - BUG-584：`in_cooldown` 补 now 臂同判（`<= 0` 口径含 epoch-0 并写进锁）；同形 `window_expired` **刻意反方向**维持 fail-closed，把靠算术巧合的 `elapsed >= 0` 改成显式一行。
   - BUG-585：算式抽出 `mr_cooldown_deadline`，三闸（非法时钟 / 非正 secs / `secs > bound - now_secs` 减法形域校验）一律显式 `Err` 并点名配置项与**按公式推导**的可用上限。
   - BUG-586：三处算式收敛为唯一 choke point `window_deadline_iso`，非法 `now` ⇒ `""`（修前会写出 1970 假截止时刻），超域 ⇒ **饱和到域上界那一秒**。
   - 变异对照读数：M1 撤 now 臂 ⇒ router `237/232/failed: 5`；M2 翻 `elapsed < 0` 臂 ⇒ `237/234/failed: 3`（同时抓到 R231 原锁与 `rx_rate_limit_wbtest`）；M3/M4 退回裸加法 ⇒ 各 `failed: 3`；M5 派生上界改成 Int32 max ⇒ `failed: 3`；五发均逐字还原复绿。
   - `.mbti` 仅两行纯增量（新 pub 算式），零签名破坏；调用面普查确认新算式在 `src/router`+`src/server` 之外零引用 ⇒ 两包全量即完整爆炸半径。
4. **E1 只读调查（车道 G）**：主 MCP 路径与 mcpcf 路径是**两份物理库**（主库 `.fist-mbt/data/<ns>.db` / 内嵌 `mcpconftest-ops.db`，`set_engine` 永不被注入主引擎）⇒ 今日不共享行，**不存在跨时基比较**（车道 E 的疑点已排除）；但隔离是**路径约定而非断言**（`FIST_DB_PATH` 若被指到内嵌库即同库同表，两基差≈1.7e9 秒 ⇒ 熔断随机卡死）。三档修复方向与代价已记入 BUG-583 待裁决。
5. **判例-46 立案**（`docs/AGENTS-precedents.md`）：「注释自述的 fail-open 意图只落在一臂 = 另一半静默反向」+ 派生域上界反解律；`AGENTS.md` 指针句 `判例-32~45` → `~46` **同批对表**（`check_precedents_doc` 当场抓到滞后并逼改，J 面自证有效）。

## 二、资源消耗

- **模型/额度**：全部走 Qoder 内置 agent（本会话无外部 token 支出）。车道 E、F 各一前台 `general-purpose`；车道 G 首次以后台派发**起跑即失败**（2 次工具调用、78 秒、盘面零残留），改前台重派一次成功。
- **fist-mbt 工具面（MCP 连接器）**：`store_open`、`agent_acl_grant`×2（lead-1109 / human_steward @iter-1109）、`publish`、`claim`、`execute`、`submit`、`verify`、`archive`、`mcp_get`（publish schema 现读）。
- **内置工具面**：Read/Grep/Glob、Write/Edit（账本与判例）、Bash（`moon_test_env.py`、`check_badge --fresh`、`check_selftest_hermetic`、`check_bug_ledger_shape`、`check_precedents_doc`、`check_test_sync`、`gen_plugins`、`git diff/status`）。
- **墙钟**：轮 182 全程约 82 分钟（含两次全量 JS 复跑与一次徽章尺真跑）。

## 三、任务分配记录

| 车道 | 模式 | 边界（只动哪些） | 交付 | 统帅终审 |
|---|---|---|---|---|
| E | bugfind | 只读 `src/`，temp/ 探针，禁写 src/账本 | 4 实锤 + E5 排除 + 设计边界清单，探针 17/17 | 锚点逐条 Read 复核（`mcpcf_embed:267`/`model_router:163-175`/`model_router_ops:682` 三处当场坐实） |
| F | advance | 仅 `scripts/render_dsh_patch.py`；禁改守卫/账本/README/提交 | 试点 2→0、triage 六档分组表、变异对照 | 复跑守卫 rc=0（W=8 R=92 G=34）、脚本 `--selftest` rc=0、`git diff --stat` 仅该件 |
| G | fix | `src/router/model_router.mbt`、`src/router/router_config.mbt`、`src/server/model_router_ops.mbt` + 3 份新 wbtest；禁账本/scripts/dist/plugins/提交 | 三单修复 + 17 格锁 + M1–M5 + E1 隔离结论 | 全量 `2053/2053/0`、`check_fmt_gate` PASS、`.mbti` 两行纯增量、盘面改动面逐文件核对 |
| 统帅 | — | 账本、判例库、AGENTS 指针、计数面、投影、提交、报告 | BUG-583~586 立账（584/585/586 同日销账）、判例-46、README/README_EN 2036→2053、`gen_plugins` 重投影 | 见 §一 与 §四 |

## 四、遗留风险

1. **BUG-583 仍 OPEN**：2038 后 mcpcf 熔断永久卡 Open；且 mcpcf 面**零测试覆盖**（`engine_circuit_test.mbt` 用 100..2000 合成秒够不到绕回档）⇒ 任何修复都要先补行为锁。三档方向（换时基 / 域拒绝 / 引擎 Int64 化）按代价升序记在账本，待 owner 或后续批次裁决；另附一条「mcpcf 库路径 ≠ 主库路径」判据建议（把约定变成断言）。
2. **BUG-584 残余（如实记账，未在本门里偷偷绕过）**：墙钟越过声明域（>2037）⇒ `window_expired` 仍 fail-closed ⇒ 用量只增不减 ⇒ 最终 `available=false`。关闭条件是时钟 Int64 化迁移（与 BUG-583 方向③同源），不是把坏时间戳当成一次重置。
3. `in_cooldown` 现在对**非法时钟 fail-open**：坏时钟下冷却保护消失（与 BUG-206 同方向的取舍）；若要求「坏时钟不许静默放行」，需要的是显式报错版路由入口，非本轮范围。
4. `FIST_MODEL_COOLDOWN_SECS` 给非数字（如 `abc`）仍走 `bug_parse_int`→0→静默回落 300；本轮只修「大到绕回」与「非正」两档。
5. **BUG-582 整体处置方向待 owner**：试点只证一个脚本。推广三类分流——干净 temp 夹具/主面冗余类（约 15–20 脚本可照本模式批量）、校准读类（`HERMETIC_CALIBRATION` 声明机制走不走须裁决）、结构冲突/G 档（call-face ⟂ 读锚点，temp 夹具解不了，挂 BUG-492 选项 C）。守卫自身设计终态不是零红，「标定格清零＝更假不是更严」。
6. **owner 既有裁决项不代翻**：BUG-527（native 上游 issue 出路②）、BUG-542、BUG-565 A 半三案 + 计数面裁决 + 双层守卫并存与否、BUG-566（宿主审批门误判族）。
7. **非本批留账**：`scripts/explore_watchdog_wrapper.ps1` / `_prompt.md` / `_hidden.vbs` 三件仍未跟踪未 ignore（`check_publish_payload` 红面），属唤醒轮基础设施，由该车道/owner 处置，本批未动。
8. **车道基础设施留档**：后台 `Agent` 派单起跑即失败（无任何工具产出、`git status` 零残留）时，先核盘面再前台重派，不当作任务本身不可完成。

## 五、后续建议

1. 立「**时钟 Int64 化迁移**」专项：一并干掉 ops_ts 的 2091 顶、BUG-218 的 2037 顶与 BUG-583/584 残余——本轮三单修的正是「域校验前移到加法之前」这一层，根子在 Int32 承载 epoch 秒。
2. mcpcf 面补第一批行为锁（`engine_circuit` 域外秒数臂），否则 BUG-583 的任何修复都无法自证。
3. BUG-582 干净子类批量推广可开一车道（15–20 脚本 × 每脚本单格改造，模式已验证）；校准类与结构冲突类先出决策单再动手。
4. 同族排查直接瞄准**单加法/截断 + 正性哨兵**三形，减法形已有两轮同余实证，不再投探针。

## 六、超额内容

- 判例-46（两条定律）+ `AGENTS.md` 指针句同批对表，滞后由 `check_precedents_doc` 当场逼改。
- E5 排除项与设计边界清单（ops_ts 2024..2091、router 1970..2037、`ops_cleanup` 24855 上限、`star_gate` Int64+Double、`engine_phi` Double 域校验等）全部写入 BUG-583 detail，防后续车道重复误报。
- `window_expired` 那一臂的处置做了「行为不变、形状显式化 + 可区分变异格」，为 R231 的既有语义留了可复核证据。

## 七、来源

- 车道 E / F / G 回传原文（本会话，含修前红修后绿读数与 triage 表）。
- 取证件：`temp/pt_round182.log`（全量 2053/2053/0 + RC=0）、`temp/badge182.out`（徽章尺真跑）、`temp/findings_before.txt`（密封性 155 处逐脚本表）、`temp/mutation_control.py`（车道 F 变异对照）、`temp/sync_test_count_182.py`（计数面换尺）。
- 台账面：`memory/bugs.md` BUG-580（同族原型）/ BUG-582（试点追记）/ BUG-583、584、585、586（本轮新立，584~586 同日销账）；`docs/AGENTS-precedents.md` 判例-46；`memory/2026-11-09.md` 轮 182 段。
- 当前状态自述用配方不用快照：提交面现读 `git log --oneline -3`，全量读数现读 `python scripts/check_badge.py --fresh-if-stale temp/pt_badge182.log README.md`。
