# 轮 393 巡检报告

> FIST-Mbt ExploreWatchdog 唤醒轮（Windows 计划任务，每 30 分钟无窗）。
> 生成时刻：2026-11-17。报告文件即本轮 FIST 任务的 deliverable。

## 一、WIP 收口核查（巡检分支判定）

`git status --short` 与 r392 一致：**6 M + 1 untracked**，无新收口、无新起 WIP：

| 文件 | numstat | 状态 |
|---|---|---|
| dist/fist-mbt.js | 41402/35319 | M（中止轮再生，r384 记录，未提交） |
| memory/bugs.md | 216+ | M（外来账冻结，r378 起，第 69+ 轮） |
| memory/target.md | 1/1 | M（巡检 WIP，冻结面） |
| scripts/README.md | 1/1 | M（iter-r192 车道 F 提交③在途） |
| scripts/check_plan_landing.py | 120/24 | M（iter-r192 车道 F 在途） |
| templates/pipeline_mode_loop.md | 1/1 | M（J8 修复在途） |
| reports/2026-11-17-iter-r192-report.md | untracked | iter-r192 收口报告（**在途**） |

⇒ **iter-r192 收口进行中**（车道 F 提交③未落库），禁区零碰。`src/**` 与 `scripts/run_guards.py`
维持 r385 确认的已解禁态，但 **Round C 队列（既定迭代目标）已由 r385 逐项核实全消并移交 owner 设
下一目标** ⇒ 本轮无既定目标可执行，走**巡检分支**：非阻塞换面 + FIST 闭环记账。

**本轮换面 check_mbti_sync 巡检发现真回归（非零漂移面）**：硬 CI 门 ci.yml:56-60 自 2026-11-12 起
红 ~5 天无人读，根因 `#derive` 前缀式未被 `collect_defs` 收集。已 TDD 修复并验证转绿，详见第二节。

## 二、换面巡检：check_mbti_sync（.mbti 接口声明 ↔ 源定义 守卫 · 发现真回归 + 修复）

**为何选此面**：r392 store_tables_wired + demo_isolation / r391 ofm_endpoint / r390 entry_paths /
r389 release_asset_names / r388 tool_required_sync / r387 host_installable / r386 battery_count_doc
⇒ 近 7 轮换面清单里 **check_mbti_sync 未覆盖** ⇒ 不撞面。该面是 **CI 硬门**（ci.yml:56-60「MBTI
sync guard」，无 `continue-on-error`），守的是：`pkg.generated.mbti`（`moon info` 生成的接口面，
文件头 DON'T EDIT IT）里每条 `pub fn` 声明，同包 `.mbt` 里必须能找到定义（derive 生成的方法按类型名
+ derive 标注对账）。

### 实跑（修复前）：硬门红，11 条 M1 误报

`FAIL .mbti 接口声明 ↔ 源定义 一致性守卫（扫 27 份 .mbti、810 条 pub 声明、6 种形状）`，`RC=1`。
11 条 M1 **全部**落在 `pub fn T::to_repr/equal/not_equal`（derive 宏生成的方法），涉及：

| 包 | 类型 |
|---|---|
| router | CafDryRun / CafModelStats / OfmChatMessage / OfmChatRequest / OfmChatResponse / OfmModel / StarVerdict |
| evolve | CurriculumLevel / MutationKind |
| ltl | Verdict |
| ops | AuditEntry |

### 根因调查（Phase 1 systematic-debugging · 实锤）

- **声明形态**：11 条 M1 全是 `pub fn <TypeName>::<method>(...)`（如 `pub fn CafDryRun::to_repr(Self)
  -> @debug.Repr`）——derive 宏（`@debug.Repr` / `Eq`）生成的方法，`.mbti` 侧按类型名 `T` 收
  （`\w+` 停在 `::` 前）。
- **收集逻辑**：`collect_defs` 只认 `derive` 的**两种后缀落点**——闭合行 `} derive(Eq, Debug)`
  （`DERIVE_TAIL`）与一行式 `pub type T = Int derive(Eq)`（同行 `"derive(" in l`）。两者都把 derive
  放在类型声明**之后 / 同行**。
- **变更源**：git log 实锤 `0a7682b67 工具链 0.1.20261104 匹配：derive 子句迁移为 #derive`（2026-11-12，
  HEAD 祖先）。迁移后 `derive` 变成**独立一行、紧贴在类型声明之前**的 `#derive(Eq, Debug)` 前缀式
  （如 `src/router/model_router_caf.mbt:21 #derive(Debug)` / `:22 pub struct CafDryRun {`）。
- **失效链**：`#derive` 行在 TYPE_HDR 行**之前**，而 `collect_defs` 的 `pending` 只在见到 TYPE_HDR 行
  时才设值 ⇒ 前一行 `#derive` 已被扫过、`pending` 尚为 None ⇒ 该类型名收不进 fn 集 ⇒ .mbti 里
  `pub fn T::to_repr/equal/not_equal` 找不到对账定义 ⇒ M1 误红。
- **CI 影响**：ci.yml:56-60「MBTI sync guard」是**硬门**（无 continue-on-error），实跑 rc=1 ⇒
  **该 CI 步自 11-12 起红 ~5 天**（0a7682b67 11-12 → HEAD 11-17）。近 7 轮换面未覆盖 check_mbti_sync
  ⇒ 无人读到此红（全量电池 `run_guards.py` 亦含此格 `case("check_mbti_sync.py")` 期望 rc=0，跑全量
  电池同样会红）。

### 修复（Phase 4 · TDD · 单文件收敛，无元检查涟漪）

1. **`DERIVE_PREFIX` 正则**：`^\s*#\s*derive\s*\(`（独立一行、紧贴类型声明之前）。
2. **`collect_defs` 前缀式识别**：见 TYPE_HDR 行时，除 ① 同行 `"derive(" in l`、② 后续 `DERIVE_TAIL`
   外，补 ③ `i > 0 and DERIVE_PREFIX.match(lines[i-1])`（前一行是 `#derive`）⇒ 三种落点任一成立即收
   类型名。
3. **回归 selftest 3 格**（derive-carrier 三格 → 六格）：`#derive` 前缀类型收进 fn 集 / 前缀不误红
   （judge 端对 Baz 零违例）/ 前缀后跟非类型行不误收（防 `#derive` 误配到非紧邻类型）。
4. **自述计数同步**：`derive 承载三格` → `六格`（本仓「自述滞后于现状」BUG-514 族纪律）。

**无元检查涟漪**：`check_selftest_inventory_doc` 不追 check_mbti_sync（无「反解」锚点）；selftest 总数
用 `len(cells)` 动态反解（20→23 自动跟）；docs/ 引用全为历史/归档面（豁免）。改面收敛在
check_mbti_sync.py 单文件。

### 验证（Phase 4 · 实际运行，非自述）

- **selftest**：`SELFTEST OK（23 格：… derive 承载六格（带 derive 不误红、不带照红、#derive 前缀式三格
  不误红/不误收）…）`，`RC=0`（含 3 新回归格全绿）。
- **实跑**：`PASS .mbti 接口声明 ↔ 源定义一致：27 份 .mbti 的 810 条 pub 声明（6 种形状）在同包 .mbt
  里都有定义`，`RC=0` ⇒ **硬 CI 门转绿**。

## 三、零漂移常设面

- `check_tools_sync`：`PASS 工具单一真源一致：server.mbt 注册 183 个，AGENTS/README/deliverable/
  scoring_rubric 对齐；R3b/R7 扫现状面 169 份，历史面豁免 25 份；R8 清单分组 19 组 ΣN=183`，`RC=0`。
- `check_instruction_budget`：`AGENTS.md = 50440 字节 / 预算 65536（实际注入上限 50440）`，
  `PASS 指令文件在预算内（全部章节可见）`，`RC=0`。
- `patch_esm_main` 探针：10 bundle 全 `up to date`，`total patched: 0`，`RC=0`（防 BUG-380 垫片转发 +
  r287 型 patch 读整 bundle MemoryError；FIST 链首发前先行，非环境态）。

## 四、FIST 闭环

**T0r149 六步全链 rc=0**（wd-r393 / ns watchdog / `temp/fist_r393_chain.sh` 稳健 TID 提取后台串跑，
patch_esm_main 探针先行 10 bundle 全 up to date / total patched 0）：
publish rc=0 → TID=T0r149 → acl rc=0 → claim rc=0 → execute rc=0 → submit rc=0 → verify rc=0。
verify 字段：`status=已完成`、`completed_by=wd-r393`、`assignee=wd-r393`、
`deliverable=reports/2026-11-17-r393-wakeup-patrol.md`、`namespace=watchdog`、
`created_at=2026-11-17T14:03:57Z` / `updated_at=2026-11-17T14:04:05Z`。

## 五、禁区与立账

- **禁区零碰**：6 个 WIP 修改文件 + 1 个 untracked 报告零改零提交；本轮巡检面（check_mbti_sync /
  check_tools_sync / check_instruction_budget / patch_esm_main probe）对 WIP 文件零读零写
  （check_mbti_sync 只读 src/**/*.mbt + **/*.mbti，均在 git 跟踪面、非 WIP；patch_esm_main 探针只读
  `_build/`，gitignore 面）。
- **立账：check_mbti_sync 硬门红 ~5 天（判据实现缺陷，非被检内容缺陷）**：
  - **根因**：`0a7682b67`（11-12）工具链 0.1.20261104 迁移 derive→`#derive` 前缀式，`collect_defs`
    只认后缀式、未同步识别前缀式。
  - **影响**：CI 硬门 ci.yml:56-60 红 ~5 天 + 全量电池该格红；.mbti 面 11 个类型误红 M1。
  - **修复**：本单已 TDD 修（DERIVE_PREFIX + collect_defs 前缀识别 + 3 回归格），selftest 23 格全绿 /
    实跑 rc=0 硬门转绿（验证见第二节）。
  - **落账口径**：`memory/bugs.md` 属 WIP 冻结面（r378 起，iter-r192 在途）**不代改** ⇒ 本单在报告立账，
    待 bugs.md 解冻后补入 ledger（指挥官不代行 ledger 写入）。
  - **教训入档**：① 换面巡检覆盖不到的面（近 7 轮未碰 check_mbti_sync）会长期潜伏；② **迁移一个语法面
    要普查所有解析该语法的判据**（derive 迁移漏同步 check_mbti_sync 的 collect_defs）。

## 六、结论

本轮巡检分支：**换面 check_mbti_sync 发现真回归并修复**——`#derive` 前缀式（0a7682b67，11-12）未被
`collect_defs` 收集 ⇒ 硬 CI 门 ci.yml:56-60 红 ~5 天（11 个类型误红 M1）；TDD 补前缀式识别 + 3 回归格，
selftest 23 格全绿 / 实跑 rc=0 **硬门转绿**。零漂移常设面 check_tools_sync 183 / instruction_budget
50440/65536 / patch_esm_main 0 patch 均 rc=0。WIP 面 6M+1untracked 与 r392 一致 ⇒ iter-r192 收口
进行中、禁区零碰。立账见第五节（bugs.md 冻结 → 报告立账，待解冻补入 ledger）。FIST 闭环见第四节。
