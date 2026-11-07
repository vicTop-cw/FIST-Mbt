# 唤醒轮 201 · BUG-582 越线精确分解 + 三选一定量锐化（零 WIP 改动）

- 日期：2026-11-07（FIST-Mbt-ExploreWatchdog 唤醒轮 201，承接轮 200 的 22:00 槽）
- 评估对象：aider 车道孤儿 WIP——**第二十轮同规模**（10 文件 +6144/-6025，HEAD 仍 `9b5ad890c`＝轮 200，
  孤儿态维持：WIP 全套文件 mtime 停在 11:06–11:55，悬挂自今晨起已约 **11 小时+** 零变化）
- 评估方式：**纯只读 + 非阻塞根因调查**，未对 WIP 任何文件做改动；未代 bless 基线、未代修 guard、未代提交

## 结果摘要

- **Round C 门仍锁**：`src/**`（engine_supervisor.mbt / server.mbt / supervisor_tools.mbt 等）与
  `scripts/run_guards.py` 仍 WIP ⇒ BUG-527 治本 / BUG-530 修复 / run_guards 注册**三项仍不可执行**。
- **孤儿 WIP 持平**：第二十轮同规模（diff 仍 +6144/-6025、文件集与 mtime 未变），仍是「已终审收口全绿批次」
  （BUG-580/581 在 WIP 账本内转 FIXED、BUG-582 立 OPEN、JS 2036/2036、fmt PASS、dist 对表 PASS），等 owner 三选一。
- **本轮新发现（相对轮 200 的「+2 既有累积漂移」锐化为逐文件定量分解）**：
  把「当前逻辑」同时跑在 bless 时刻树（`1fda440d0`，即 `BASELINE R=92` 那次前移）与现状树上做差，
  **R 档 +2 不是单一来源，是三个流的净和**：

  | 来源 | R 变化 | 性质 |
  |---|---|---|
  | `check_bug_ledger_scope.py` | +1 | 新增脚本，自检读真 `gen_plugins` 面（parity 标定） |
  | `check_dist_snapshot.py` | +2 | 既有脚本自检读真 `dist/` 快照面 |
  | `check_doc_surface.py` | +2 | 既有脚本自检读真 USAGE/README/BUGS/BACKLOG/CHANGELOG 面 |
  | `check_precedents_doc.py` | +3 | 新增脚本，自检读真 DOC_PATH/AGENTS_PATH 面 |
  | `check_stale_self_claim.py` | +3 | 新增脚本，自检 `os.walk` 真 ROOT 全集 |
  | `check_plan_location.py` | −1 | 移走一处自检读面（还债） |
  | `check_scripts_naming.py` | **−8** | **R→C 校准档重分类**（`88968eb37`，晚于 bless，`HERMETIC_CALIBRATION` 显式声明） |
  | **净和（棘轮读数）** | **+2**（92→94） | |

  - **关键修正一（相对轮 197）**：轮 197 把「真红面」点名到 `check_dist_snapshot.py`/`check_stale_self_claim.py`
    两文件；本轮逐文件实测证明 **新增读面实为 5 个文件、合计 +11**（另 3 个：check_bug_ledger_scope / check_doc_surface /
    check_precedents_doc）。只改轮 197 点名的 2 文件会把 R 降到 89（仍 < 基线 92 ⇒ 绿），但**漏声明另外 3 文件的 6 处校准读**。
  - **关键修正二（相对轮 200）**：轮 200 只比「现读 94 vs 基线 92」，未拆净和。本轮证实 **bless 后的
    `check_scripts_naming` R→C 重分类（−8）把基线 92「垫高」了**——即基线 92 里含 8 处当前逻辑已豁免为 C 的读 ⇒
    **棘轮 +2 低估了真实债务增长**：真实树漂移是 **+10**（+11 新增 − 1 还债），被 −8 重分类对冲后才显 +2。
  - **WIP 新脚本已排除（复确认轮 200）**：`check_foreign_ledger_entries.py` 现读 R=0 / C=0（合成夹具、不碰真账本），
    对 +2 贡献为零 ⇒ BUG-582「与本批无关」判定维持。
- **三选一定量锐化（给 owner 的处置决策）**：11 处新增读**全部是现状面标定读**（判例-32「探针须先在新鲜样本标定」），
  非可避债 ⇒ 出路 (b)「改合成夹具」对这 11 处基本不适用（它们必须读真面才能标定）。真正可选的是：
  - **(a) `--bless-baseline` R 92→94**：把净 +2 前移进基线（棘轮只许升）。代价：基线继续被重分类垫高，欠账面变「账面 94」。
  - **(b) 降债**：把可读夹具的读移出 `--selftest` 归主面 / 改 temp 夹具。对 11 处标定读大多不可行，仅 `check_plan_location`
    已示范过一次（−1）——可作范本，但空间有限。
  - **(c) 补 `HERMETIC_CALIBRATION` 声明（BUG-516 走路②，`check_scripts_naming.py` 既有惯例）★推荐**：
    给 5 个文件的标定读锚点各加一条显式校准声明 ⇒ 11 处 R→C（不进棘轮）⇒ R 现读降回 **83 < 基线 92** ⇒
    棘轮**绿（低于基线只记账不判红）**，**不抬基线、不放宽判据**，与 `check_scripts_naming` 已走的同一条正路。
    注意：(c) 也是「重分类降账」而非「真删读」，与 −8 同性质 ⇒ 它会令「基线虚高」已知状态从 8 处扩到 19 处，
    这是 BUG-516 走路②的既定取舍（账面降、行为不变），非新问题。

## 资源消耗

1 次唤醒轮；bash ×6 + 只读工具若干 + 1 份一次性分析脚本（`temp/tmp_e/decompose_r.py`，落 gitignored temp/、不入电池面）；
无子代理派发——BUG-582 是低危 judgment call 的**根因锐化**，纯只读调查属统帅终审职责内，无可派发面。

## 任务分配记录

无（唯一 OPEN bug BUG-582 仍判为低危 judgment call，本轮只**锐化**不代修；处置三选一 (a)/(b)/(c) 留给 owner，
其中 (c) 已带 5 文件 11 锚点的可执行清单——owner 若选 (c)，解禁后 1 个子代理可照单落地）。

## 遗留风险

1. **孤儿 WIP 仍阻塞 Round C 队列全部三项**（BUG-527 治本 / BUG-530 修复 / run_guards 注册），悬挂约 11h+，等 owner 三选一。
2. **BUG-582 仍 OPEN**（R 94/92 越线）：本轮已把「二选一」锐化为「三选一定量清单」，**与 WIP 无纠缠**（已二次证伪 WIP 致债）
   ⇒ 可在 WIP 收口前后任一时机独立处置；**若 owner 选 WIP 选项①收口，应把本报告的 5 文件 11 锚点分解回写进 WIP 账本的
   BUG-582 条目**（当前该条目只写「155 处、二选一降债/bless」，未含逐文件定量与 −8 基线垫高）。
3. **C: 盘 90%（22G 余量）+ OFM relay 本机未起**（均环境态，同轮 199）——跑判据统一 TEMP 改道 `temp/tmp_e` 规避 Errno 28。

## 后续建议

1. **owner 优先定夺孤儿 WIP 三选一**（决策输入同轮 199/200）：① 本车道续写收口＝替全绿批次收尾最后 3 步机械动作
   （`gen_plugins` 重投影核 cl7 rc=0 → `commit_scoped.sh` 12 文件：需解禁 src/** + run_guards.py + 2 新文件，
   **并建议同批回写 BUG-582 的 5 文件分解**）；② 新起车道接手；③ owner 自处置。
2. **BUG-582 处置三选一**（与 WIP 互不阻塞）：推荐 **(c) 补 `HERMETIC_CALIBRATION`**（5 文件 11 锚点清单见结果摘要，
   R 降回 83、不抬基线、走 `check_scripts_naming` 既有的正路）；(a) bless 92→94 为「图省事」档；(b) 降债空间有限。
   三选一均**需 owner 知情**（bless/校准声明都属「判定何为合法校准读」的策略变更，不悄悄改）。

## 超额内容

无（只读根因调查 + 状态复确认 + BUG-582 逐文件定量锐化，均在记账义务内；未越权碰 WIP、未代提交、未代 bless 基线、
未代修 guard、未代补校准声明）。

## 来源

- 唤醒协议（用户 prompt 标准动作 1~5，第 3 步「若仍被占用 → 非阻塞巡检/根因调查」）
- 本轮实跑读数：`check_selftest_hermetic.py` 主面（`>/dev/null` 取真 **rc=1**，`[棘轮] W=8/8 R=94/92 G=34/34`）；
  一次性分解脚本 `temp/tmp_e/decompose_r.py`（当前逻辑跑双树：bless 时刻树 R=92/C=0，现状树 R=94/C=8，
  逐文件差：+1/+2/+2/+3/+3/−1/−8）；`git archive 1fda440d0 scripts` 抽 bless 时刻树（171 份 .py）；
  `git merge-base --is-ancestor 1fda440d0 88968eb37`（证 bless 早于校准档 C）；
  `git diff memory/bugs.md`（WIP 内 BUG-580/581 转 FIXED + BUG-582 立 OPEN，23+/2-）
- 轮 200 报告 `reports/2026-11-07-wakeup-200-bug582-root-cause-report.md`（rc=1 坐实 + 二选一锐化）
- 轮 197 日志（`check_dist_snapshot`/`check_stale_self_claim` 真红面点名 + 二出路由轮 140 首列——本轮把 2 文件修正为 5 文件）
- `memory/bugs.md`（WIP）BUG-582 条目（OPEN，「155 处、与本批无关」——本轮逐文件量化并补 −8 基线垫高）
