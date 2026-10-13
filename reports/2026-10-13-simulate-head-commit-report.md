# 2026-10-13 · 新增 simulate_head_commit 提交前干净树模拟报告

## 结果摘要

**一句话**：本仓两次 master 级坏状态都是同一形状——**"实现面先提交、配套未提交"**，且**本地绿、CI 红**。
本轮把"提交前预判"做成工具：`scripts/simulate_head_commit.py` 用 `git archive HEAD` + 贴工作树差异
+ `moon check` 回答一个问题——**"把这些差异一起提交，HEAD 会不会绿？"**

| 项 | 读数 |
|---|---|
| 对当前工作树 | **SIMULATE PASS**（110 个源码差异 ⇒ `0 errors`）|
| 对抗 1（坏 HEAD + 无差异） | rc=0，明确报"没有源码差异"（不乱跑）|
| 对抗 2/3（坏 HEAD + 贴 2 个 / 4 个 `src/diff` 文件）| 均 PASS（贴到能解析该包即绿）|
| 对抗 4（只贴 `moon.pkg`）| 也 PASS（空包 moon 接受，非缺陷）|
| **对抗抓到自身缺陷** | **1 处**（未跟踪目录形态漏判）→ 已修 |

提交：`7450ce1`（工具）、`962ce47`（README 登记）。双远端同步。

## 要解决的问题（两次坏状态的共同形状）

| # | 坏状态 | 本地 | CI | 证据 |
|---|---|---|---|---|
| ① | `src/server/moon.pkg` 加了 `src/diff` import，但 `src/diff/` 四文件**从未 git add** | 🟢 绿（工作树里文件在） | 🔴 `Cannot find import 'vicTop-cw/fist-mbt/src/diff'` | CI #300 |
| ② | `pkg.generated.mbti` 声明了 4 个源里没有的 `pub fn`（实现只在工作树） | 🟢 绿（工作树里定义在） | 🔴 `… is unbound`（20 errors） | CI #303/#304 |

⇒ 两次都**发现晚（红在 `Migrate` 步且 skip 其后全部步）、定位绕**。根因不是没人检查，
而是**没有工具回答"提交这批差异后，干净树能不能过"** —— 本地 `moon check` 天生回答不了（它在工作树上跑）。

## 工具做法

1. `git archive HEAD` → 临时干净树
2. 取工作树相对 HEAD 的**源码面差异**：未跟踪 + 已修改，后缀限 `.mbt` / `.mbti`，文件名限 `moon.pkg` / `moon.mod`
   （文档/报告/脚本/CI yml 不影响 `moon check`，不贴——贴了只会慢）
3. **关键修正（对抗实测抓到的自身缺陷）**：`git status --porcelain` 对**整个未跟踪目录**只报一行
   `?? src/diff/`（尾部带斜杠）；原先按 `endswith(('.mbt','.mbti'))` 判断会**整批漏掉新包**
   ——而"新包整批未跟踪"恰是本会话最常见、也最危险的坏状态形状。现改为把目录**展开**成实际文件清单。
4. 贴进模拟树 → `moon check --target js` → 绿即 PASS（清单就是安全提交形状）/ 红即 FAIL（先补到绿）
5. 前置不满足各自明确退出：无 `moon` ⇒ rc=2；`git archive` 失败 ⇒ FATAL；`moon check` 超时 ⇒ rc=2

## L4 实测（金条八）

**主用例（对当前真实工作树）**：
```
未跟踪（源码面）8 个；已修改（源码面）102 个；合计 110 个
已贴入 110 个文件到模拟树
Finished. moon: ran 104 tasks, now up to date (1929 warnings, 0 errors)
SIMULATE PASS: 把这些差异一起提交 ⇒ 干净树 moon check 通过（110 个文件）
```
⇒ 与独立做的最小集分析一致（另一路径：`HEAD + 95 个源码差异 ⇒ rc=0`）。
**对 owner 的可执行结论**：HEAD 当前的 20 errors，把工作树这些差异**整批**提交即解。

**对抗实测（4 组，含"工具必须会红/会拒"）**：
| # | 场景 | 期望 | 实测 |
|---|---|---|---|
| 1 | 坏 HEAD（`e7a1d0e`）+ 工作树无差异 | 不乱跑，报"没有源码差异" | rc=0 ✅ |
| 2 | 坏 HEAD + 贴 2 个 `src/diff` 文件 | 贴到能解析该包即绿 | rc=0 PASS ✅ |
| 3 | 坏 HEAD + 贴全部 4 个 | rc=0 | rc=0 PASS ✅ |
| 4 | 坏 HEAD + 只贴 `moon.pkg` | 空包 moon 接受 ⇒ 亦 PASS | rc=0 PASS ✅ |

> 对抗 2 我**起初预判"应 rc=1"**——实测 PASS 后核对：`src/diff/` 只要有 `moon.pkg`（+能被解析的实现），
> `moon check` 就过；**是我的预判错，不是工具缺陷**。如实记录该次预判更正。

## 资源消耗

- `moon check` 共 6 次（1 次主用例 + 4 次对抗 + 1 次对照），每次约 1.5–3 分钟；
- `git archive` 建树 6 棵（含 3 棵对抗树，另有 2 棵 Windows 目录占用而复用新名）；
- 对抗脚本 3 版（前两版因"未跟踪目录/commit 时序"设计错误而重做）；
- 本链零 `.mbt` 源码改动、零网络请求（除 push）。

## 任务分配记录

- 指挥官亲自：动机梳理（两次坏状态共性）→ 工具实现 → 主用例实测 → 4 组对抗 → 自带缺陷修复 →
  README 登记 → 报告。
- **未派子代理**：本链要害是"对抗场景设计"（前两版设计错、需按实测反馈重做）与"缺陷归属判断"
  （是工具缺陷还是我预判错），外包会引入误判。
- 边界：只新增一支工具脚本 + README 一行；未改 `.mbt`、未代提交他人 WIP。

## 遗留风险

1. **工具只覆盖"能不能编译"这一格**：它不跑测试、不跑守卫族。若差异能让 `moon check` 过但测试红，
   工具仍报 PASS。**建议**：可加 `--with-test` 开关跑 `moon test`（本链未做，因耗时且本轮目标是"编译面预判"）。
2. **贴入的是"文件内容"，不判"该不该提交"**：工具回答的是"技术上能不能过"，不回答"这批改动语义上是否可提交"
   （例如别人的半成品 WIP 贴进去也可能 PASS）。**这是刻意的**——用途是防"半批提交造坏状态"，
   不是替人审提交内容。
3. **依赖 moon 与 git 的可用性**：两者缺一即 rc=2/FATAL（不假装通过）。
4. **当前 HEAD 仍坏（20 errors）**：工具已给出闭合清单（110 个差异整批提交即绿），
   但执行提交属该面 owner（并发会话 WIP 收尾中）。
5. **未跟踪目录展开的口径**：只展开 `.mbt` / `.mbti` / `moon.pkg` / `moon.mod`；
   若新包只有其它扩展名（如 `.c` 供 FFI），本工具不会贴——那种情况需 `--all`。

## 后续建议

1. **把它接进提交前流程**：可在 `AGENTS.md` 的 Commit gate 节里加一句
   "提交前若工作树有多个文件改动，先跑 `python scripts/simulate_head_commit.py` 确认整批提交能过"——
   这正是两次坏状态的根治点（**整批提交**而非分批）。
2. **`--with-test` 开关**（可选）：让工具在 check 之后再跑 `moon test --target js`，
   把"能编译但测试红"也纳入预判（代价是耗时翻倍以上）。
3. **接进 CI 的 `Migrate` 前**（可选）：CI 上工作树 == 检出（无差异），该工具在 CI 里无意义；
   但可在 CI 加一步"HEAD 干净树 `moon check`"作为**等价断言**——本轮实测：HEAD 干净树 check = 20 errors，
   与我的 `check_mbti_sync` 点名一致。⇒ 若不想新增工具链步骤，**现有 `check_mbti_sync` 已能替代**。
4. **推广"提交前预判"这一思路**：本会话多次踩"本地绿、CI 红"（还有 `Format check` 的 moon 版本差、
   `.mbti` 与实现不同步）。凡"判据的判读面与 CI 面不同"，都值得一支预演工具。

## 超额内容

- 顺带**对抗实测抓到本工具一处真缺陷并修复**：未跟踪目录形态（`?? src/diff/`）因尾斜杠匹配不上后缀
  而被整批漏判——那正是本会话两次坏状态的原形。**若不做对抗，这工具会带着"看不见新包"的盲区交付**
  （与本会话在判据上反复强调的"变异测试价值"同源）。
- 顺带**如实记录一次预判更正**：对抗 2 我预判 rc=1，实测 PASS；核对后确认是我的预判错
  （空包/已解析包 check 都能过），工具行为正确。
- 顺带**用另一条独立路径复核结论**：最小集分析（贴 95 个差异 ⇒ rc=0）与工具（贴 110 个 ⇒ PASS）
  结论一致，互为对照。

## 来源

- 工具：`scripts/simulate_head_commit.py`（`collect_diffs` / `_expand_untracked` / `main`）。
- 登记：`scripts/README.md` 的 `simulate_head_commit.py` 条目。
- 主用例读数：`SIMULATE PASS … 110 个文件 … 0 errors`（本机实跑）。
- 对抗原件：`temp/adv_simulate4.py`、`temp/adv_simulate5.py`（输出 `E:\temp\adv6.txt` / `adv7.txt`）。
- 最小集对照：`temp/minset_analysis.py`（输出 `E:\temp\minset.txt`：未跟踪 8 + 已修改 87 ⇒ rc=0）。
- 前序坏状态报告：`reports/2026-10-13-master-broken-src-diff-diagnosis-report.md`（①）、
  `reports/2026-10-13-second-breakage-20-errors-report.md`（②）。
- 提交：`7450ce1`、`962ce47`。
