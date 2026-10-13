# 2026-10-13 · 新增 check_mbti_sync 判据报告（.mbti 接口声明 ↔ 源定义）

## 结果摘要

**一句话**：上轮诊断的第二次 master 坏状态（`pkg.generated.mbti` 声明了源里不存在的 4 个 `pub fn`
⇒ 干净树 `moon check` **20 errors**）**此前无判据认领**——本轮把它判据化，并用
**成对实测（坏 rev vs 补齐实现）+ 七格 selftest + 四处变异**证明它真会红且零误报。

| 项 | 读数 |
|---|---|
| 对当前 HEAD（坏） | **rc=1**，精准点名 4 个"声明了但实现未提交"的符号 |
| 对「HEAD + 补齐 13 个实现文件」 | **rc=0 PASS**（440 条声明全部有定义） |
| `--selftest` | **七格全过** |
| 变异实测 | **4/4 被抓住**（其中 2 格是变异暴露缺口后补的） |
| CI | 新步「MBTI sync guard」**刻意放 `Migrate` 之前**（第 3 步） |

提交 `309a7a7`，双远端同步。

## 为什么单立这支判据

上一轮我加的 `check_pkg_imports` 只能判"**包目录**是否在跟踪面"，**判不了符号级缺失**。
本轮 HEAD 的坏状态恰恰是后者：目录都在、`.mbti` 声明也在，但**实现 `.mbt` 未提交** ⇒
`moon check` 报 `The value identifier … is unbound`。两者互补、不可互替：

| 面 | 判什么 | 本轮坏状态 |
|---|---|---|
| `check_pkg_imports` | `moon.pkg` 的本地 import → 目录存在 | PASS（目录都在）✗ 测不到 |
| **`check_mbti_sync`（新）** | `.mbti` 的 `pub fn` 声明 → 源里有定义 | **rc=1，点名 4 符号** ✓ |

## 判据设计（窄口径）

**M1**：每个 `<pkg>/pkg.generated.mbti` 的 `pub fn <name>` 声明，同包 `.mbt` 里必须能找到
`pub fn <name>` 定义（文本级：同名顶层 `pub fn` 即算）；找不到即红并点名
"接口面声明了但实现未提交（干净树 moon check 会报 unbound）"。

**刻意不判**（避免误红）：
- 非 `pub` 的 fn（内部函数不进 `.mbti`；本判据只收集 `pub fn`，天然不误）
- 无 `.mbt` 的包（`omega/pkg.generated.mbti` 类历史遗留）
- 签名差异（同名但签名不同属 `moon info` 职责，本判据只判"名字在不在"）

**防空转**：一份 `.mbti` 都枚举不到、或全仓零条 `pub fn` 声明 ⇒ `SystemExit(2)` FATAL。

**尺子坏了自报**：`judge()` 自身抛异常（如实现被改成直接下标而缺包）⇒ `FATAL` 明示"判据自身异常，
尺子坏了"，**不冒用 1 那一档**（本仓纪律）。

## L4 实测（金条八：全部实跑）

**成对对照**（同一支脚本，两侧树各跑一发）：

| 组 | 树 | 判据读数 |
|---|---|---|
| A | 当前 HEAD（坏） | **rc=1**：4 个符号全点名（`do_evolve_asset_register_with_search` / `parse_search_lines` / `register_supervisor_tools` / `self_search_runner_default`） |
| B | HEAD + 补齐 13 个实现文件 | **rc=0 PASS**（440 条声明在同包 `.mbt` 里都有定义） |

⇒ 既证明它认的是真问题（A 点名精确），也证明修好后**零误报**（B 全绿）。

**`--selftest` 七格**：干净不误红 / 合成违例必红 / **真实 4 符号必红** / 私有函数不误 /
无 `.mbt` 包跳过 / 只收 `pub fn` / 缺额计入空转门。

**变异实测 4/4 被抓住**（且暴露并补齐了两处覆盖缺口）：

| # | 变异 | 抓它的格 | 状态 |
|---|---|---|---|
| 1 | M1 判定恒不报红 | `synthetic-violation-caught` | 首轮即抓住 |
| 2 | 去掉缺包保护（`.get` 改直接下标） | `no-mbt-package-skipped-judge-crashed`（judge 抛 KeyError ⇒ 尺子坏了） | **首轮抓不住**（判据自己崩成 traceback）⇒ 补格后抓住 |
| 3 | 正则放宽成 `(?:pub )?fn`（把内部 fn 当声明） | `only-pub-fn-collected` | **首轮抓不住**（5 格全绿）⇒ 补格后抓住 |
| 4 | 缺额不计入 n（防空转门失效） | `missing-counted-in-n` | **首轮抓不住** ⇒ 补格后抓住 |

> 这三处"首轮抓不住"是**变异测试的直接价值**：若只写 `--selftest` 而不做变异，
> 我会交付一支**看起来有 5 格自证、实际覆盖有洞**的判据。补格后 7 格、4 变异全中。

## CI 挂点：刻意放 `Migrate` 之前（第 3 步）

**上轮实测教训**：我上一轮把 `Package-import guard` 挂在 `Migrate` **之后**，CI #304 实证
`Migrate` 一红它就 **skip** —— 而"依赖/编译坏状态"恰是最需要它出声的场景。
本判据因此**刻意挂在 `Migrate` 之前**（YAML 校验：MBTI sync guard 位置 3 < Migrate 位置 4），
先 `--selftest` 再全量。**这是本会话第三次同族教训**
（Format 门 skip 契约自证 → Migrate skip Package-import guard → 本次主动前置）。

## 资源消耗

- 判据脚本 222 行；`--selftest` 跑 6 次（初跑 + 两轮变异 + 还原）；
- 成对实测 2 棵 `git archive` 树（含 tarfile 解包，因 Windows 下 `git archive | tar -x` 对中文文件名失败）；
- 变异实测 2 轮（首轮 3 处 + 补格后 4 处）；
- 守卫链复跑 2 轮；本链零 `.mbt` 源码改动、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：判据面可行性探测（含"正常态会不会误红"预判）→ 实现 → 七格 selftest →
  成对实测 → 两轮变异 → CI 挂点位置论证 → README 登记 → 报告。
- **未派子代理**：本链要害是"判据口径取舍"与"变异暴露的覆盖缺口判断"（哪一格该补），外包会引入误判。
- 边界：只新增一支判据 + CI 一步 + README 一行；未改任何 `.mbt`、未代提交他人 WIP。

## 遗留风险

1. **判据只判 `pub fn`**：`pub let` / `pub const` / `pub type` / `pub enum` 等声明形状**本轮不判**。
   若某坏状态是"类型声明了但定义未提交"，本判据看不到（`moon check` 会看到）。
   扩面需先确认 `.mbti` 里这些形状的稳定性（可选，下一轮）。
2. **文本级比对 ≠ 语义级**：本判据只判"同名 `pub fn` 存在"，**不判签名一致**。
   签名漂移（同名不同参）会漏 —— 那属 `moon info` 职责（`moon info` 会重写 `.mbti`）。
3. **当前 HEAD 仍坏（20 errors）**：本判据会红（正确信号），修复仍需并发会话补齐 13 个未跟踪
   `.mbt` + `store.mbt`/`store_sqlite.mbt` 配套改动（上轮三组实验已定位）。
4. **CI 会在 `Migrate` 之前先红在本判据**：这是**期望行为**（它比 `Migrate` 的错误信息更精确），
   但会改变 CI 红面的"第一处失败步"读数——若有人按旧日志找 `Migrate`，需知情。

## 后续建议

1. **把 `check_mbti_sync` 的判据面扩到 `pub let/const/type/enum`**（可选）：本轮只做实 `pub fn`
   （先窄口径避免误红）。扩面前需在健康树上预跑确认零误报——本轮已确立"先预判误报再落地"的做法。
2. **给 `Migrate` 步的失败分支加"根因分流"**（上轮已提）：本轮判据前移后，`Migrate` 前的红面
   已能点名两类坏状态（缺包目录 / 缺符号定义）；仍建议在 `Migrate` 失败时按错误文本分流指路。
3. **提交纪律：实现面与其配套文件同批提交**——本轮两次坏状态（`src/diff` 悬空 import、
   `.mbti` 声明缺实现）都是"接口面先提交、实现未提交"。现已有两支判据（`check_pkg_imports` +
   `check_mbti_sync`）兜这两类，但**同批提交才是根修**。
4. **判据挂点体检**（第三次同族教训后）：建议盘点所有判据步相对"前置硬门"（`Migrate` / `Format`）
   的位置，把静态判据统一提到硬门之前。本会话已累计三次"判据挂了但没跑到"。

## 超额内容

- 顺带**用变异测试暴露并补齐了两处 selftest 覆盖缺口**（若只写自传说"5 格"就交付，
  那支判据实际抓不住 3 类退化）——这条方法学价值高于判据本身。
- 顺带**确立了"新判据先预判误报再落地"的做法**：本轮在写脚本前先用一次性脚本对 HEAD 与工作树
  各跑一遍，确认"坏态报 4 个、健康态报 0 个"，才动手实现。
- 顺带**把上轮的挂点教训应用为主动前置**（本判据放 `Migrate` 之前），而非等 CI 再证一遍。
- 顺带处理了 Windows 下 `git archive | tar -x` 对中文文件名失败的 harness 缺陷（改用 `--output` + tarfile）。

## 来源

- 判据：`scripts/check_mbti_sync.py`（含七格 `--selftest` + 异常自报）；CI 步名「MBTI sync guard」；
  登记 `scripts/README.md`。
- 成对实测原件：`temp/verify_mbti_guard.py`（A: HEAD rc=1 点名 4 符号；B: 补齐实现后 rc=0），
  输出 `E:\temp\vmbti2.txt`。
- 可行性预判：`temp/feasibility_mbti.py`（HEAD 声明 440 / 缺 4；工作树 470 / 缺 0），输出 `E:\temp\feas.txt`。
- 变异实测：`temp/mutate_mbti.py`（两轮），输出 `E:\temp\mutmbti4.txt` / `E:\temp\mutmbti5.txt`。
- 上轮坏状态诊断：`reports/2026-10-13-second-breakage-20-errors-report.md`（20 errors 定性 + 三组修复实验）。
- 提交：`309a7a7`（判据 + CI 步 + README 登记）。
