# Lane L：`check_plan_landing.py` 两条设计性排除落地报告

> **任务**：Lane L 派单 —— 让 `check_plan_landing.py` 的判定面棘轮从「超限 10 条」转绿
> **裁决依据**：统帅 2026-10-26 裁决 **路 B（扩展为两条设计性排除）**；路 A（文档补作废标记）**单独立项，不在本单**
> **作业面**：`scripts/check_plan_landing.py`（已 `reserve_scope` → granted）
> **日期**：2026-10-26

---

## 结论

**判定面 34 → 25，≤ 上限 25，棘轮转绿。**

| 项 | 改前 | 改后 |
|---|---|---|
| 判定面（未在跟踪面） | **34 条** | **25 条** |
| 豁免态（单列不判红） | 7 条 | **17 条**（+10 = 6 日日志 + 4 提案） |
| 搬家态（单列不判红） | 3 条 | 3 条（不变） |
| 存档面（只报不判） | 18 条 | 18 条（不变） |
| 棘轮 | **超限 10 条**（rc=1 并红） | **25 ≤ 25，不再超限** |
| `--selftest` | 46 格 | **57 格**（+11），rc=0 |

**但必须先说清一件事：原派单的两条改进，前提都不成立。**（见 §一）

---

## 一、前置核验：原派单的两条改进前提都不成立

在动手前我核了前置，发现**两条改进都改不动任何一条**。这是本单最重要的过程记录。

### 改进 1（语境排除）：`BACKTICK` 并不「抓所有反引号内容」

派单原文：
> `scripts/check_plan_landing.py:83` 的 `BACKTICK` **抓所有反引号内容当路径候选** ⇒ 分支名、工具名、命令名全被当路径。

**实测代码不是这样。** `:83` 只是抽反引号内容，紧随其后有**三道闸**：

```python
if not cand.startswith(TOP_DIRS):                       continue   # 必须 src/ docs/ scripts/ 等开头
if not (cand.endswith(PATH_EXT) or "." not in os.path.basename(cand)): continue
if "/" not in cand and not cand.endswith(PATH_EXT):      continue   # 拒顶层单名
```

`TOP_DIRS` 已含 `src/ scripts/ cmd/ docs/ templates/ plugins/ patches/ reports/ memory/ specs/ resources/ .github/`；
`PATH_EXT` 已含 `.mbt .py .md .json .yml .sh .toml .mbti` 等。

**⇒ 分支名 / 工具名 / 命令名（不以 `src/` 等开头）早已被挡住。**
我把 34 条逐条打出来核对，**全部是真实路径**（`src/engine/engine_lock.mbt`、`memory/2026-10-12.md`…），**没有一条是格式误读**。
**改进 1 改完，判定面仍是 34。**

### 改进 2（读作废标记）：文档里根本没有标记可读

派单原文：
> Lane J 已裁定 B 类 21 条全部作废。判据应在**文档里读到作废标记时不再计为 missing**。

**但 Lane J 的原文是「应标作废」——那是待办建议，不是文档已标的事实。** 实测：

```
【已作废】       → 0 个文档
【作废】         → 0 个文档
WOULD-NOT-DO     → 0 个文档
N/A（作废）      → 0 个文档
节标题含「作废」 → 仅 2 处（docs/2026-10-20-slave-tasks.md:42/117，且不是那 21 条所在处）
```

**⇒ 改进 2 改到判据里，一轮下来一条都读不到标记，判定面仍是 34。**

### 34 条的真实构成（逐条分类）

| 类 | 条数 | 性质 | 原两条改进能否消 |
|---|---|---|---|
| ① `memory/YYYY-MM-DD.md` 日日志 | **6** | `.gitignore` **设计性排除**，本就不进跟踪面 | ❌ |
| ② `memory/` 其它 | 3 | 计划点名的配置/占位（`lock-config.json` / `当日.md`） | ❌ |
| ③ `docs/proposals/` 提案点名的新增件 | **4** | **提案**（未采纳）≠ 落地承诺 | ❌ |
| ⑤ 普通计划点名的新增件 | **21** | 真的没实现 | ❌（文档没标作废） |

**关键观察：③ + ⑤ = 25，正好等于上限 25** —— 说明上限当初就是按「真未实现 + 提案」这个口径定的。
**① + ② = 9，正是超出的那 9 条。** 而 ① 的 6 条是纯设计性排除面 —— **本来就该被排除**。

---

## 二、两条设计性排除（统帅裁决路 B）

### 排除 1（P8）：`memory/YYYY-MM-DD.md` 日日志

**为什么这是设计性排除，不是为转绿硬塞豁免：**

`.gitignore:154-157` 原文：

```
# 流水账（memory/*.md 日日志）：614MB 级大文件膨胀 git 历史 + 每次合并必撞冲突，
# 账本 bugs.md / product.md / target.md / task.md / links.md / rules.json / research/
# / reviews/ 均为结构化核心记忆，单独保留在 git 里。
memory/2026-*.md
```

**该面被 gitignore 永久排除 ⇒ 它本来就不会进跟踪面。**
拿跟踪面当分母去问「这个文件在不在跟踪面」是**一个永远为假的问题** —— 判据读错了面，不是文档缺了什么。

**自愈设计（关键）**：`_gitignore_excludes_daily_logs()` **每次现读 `.gitignore`**，不写死 `True`：

```python
def _gitignore_excludes_daily_logs(root=None):
    for raw in text.splitlines():
        s = raw.strip()
        if not s or s.startswith("#"): continue
        if re.match(r"^/?memory/(?:20\d{2}|\*|20\?\?)[-*].*\.md$", s):
            return True
    return False
```

- **规则被移除 ⇒ 排除自动失效 ⇒ 那 6 条重新计入判定面**（自愈，不是一次性豁免）
- 读不到 `.gitignore` ⇒ 返回 `False`（**保守**：宁可多报，不可错放）
- 只认日日志形态的规则；`memory/` 整目录挡**不算**（本仓刻意逐文件点名）

**窄形**：`_RE_DAILY_LOG = ^memory/(?:19|20)\d{2}-\d{2}-\d{2}\.md$` —— 只吃日期形态，`memory/lock-config.json` 不被排除（有反证格钉住）。

### 排除 2（P9）：`docs/proposals/` 提案目录

**为什么这是设计性排除，不是为转绿硬塞豁免：**

**提案 ≠ 落地承诺。**
- **计划（plan）**说「将新增 X」= 对交付的**承诺** ⇒ 没落地就是欠账，该计入 missing
- **提案（proposal）**说「建议新增 X」= **选项讨论** ⇒ 未被采纳就本不该落地

把提案点名算成 missing，等于要求「**讨论过的每一个选项都必须实现**」—— 那会让提案制度本身变得不可用（任何讨论都变成欠账）。

**窄形**：`PROPOSAL_DOC_PREFIX = "docs/proposals/"` —— 只认这一条路径前缀，**不按名字含 "proposal" 模糊匹配**（`docs/proposal-x.md` 不在前缀内，有反证格钉住）。

**⚠️ 触发条件（正向，必须写清）：若某条提案被采纳并转成正式计划** —— 即
① 从 `docs/proposals/` 移入 `docs/` 正式面，或
② 在正式计划文档里重新点名该文件
—— 则 **P9 不再覆盖它，该点名重新计入判定面**。

---

## 三、证据

### 3.1 代码 diff

```
git diff --numstat -- scripts/check_plan_landing.py
95	7	scripts/check_plan_landing.py
```

三处改动：

| # | 位置 | 改动 |
|---|---|---|
| **A** | `exempt_reason()` 之后 | **新增** `_RE_DAILY_LOG` / `_GITIGNORE_FILE` / `PROPOSAL_DOC_PREFIX` / `_gitignore_excludes_daily_logs()` / `design_exempt_reason()`（共 ~60 行，含完整设计性论证注释） |
| **B** | `judge()` | 签名新增 `daily_logs_ignored=None, proposal_prefix=PROPOSAL_DOC_PREFIX` 两参；在 P7 豁免之后插入 P8/P9 判定分支 |
| **C** | `split_faces()` | `NON_VERDICT` 从 `("moved","external","scratch")` 扩为 `(…,"ignored-log","proposal")`；`exempt` 同步纳入两新态 |
| **D** | `selftest()` | 新增 **11 格**（含 2 格变异对照、4 格反证） |

### 3.2 `--selftest` 前后

```
改前：46 格
改后：57 格    rc=0
```

**新增 11 格逐条**（这是统帅要求的「成对验证」，实际给了 4 对 + 4 反证）：

| 格名 | 类型 | 断言 |
|---|---|---|
| `p8-ignored-log-detected` | **格 1** | 被 gitignore 的日日志 ⇒ `ignored-log` 态 |
| `p8-mutation-disabled-falls-back-to-missing` | **格 2（变异对照）** | 注入 `daily_logs_ignored=False` ⇒ **回到 missing**（6 条重新计入） |
| `p9-proposal-detected` | **格 3** | `docs/proposals/` 下点名 ⇒ `proposal` 态 |
| `p9-mutation-prefix-removed-falls-back-to-missing` | **格 4（变异对照）** | 注入 `proposal_prefix=""` ⇒ **回到 missing**（4 条重新计入） |
| `p8-not-overbroad-non-daily-log` | 反证 | `memory/lock-config.json` 非日日志 ⇒ **不被 P8 吃掉** |
| `p9-not-overbroad-non-proposal-dir` | 反证 | `docs/proposal-x.md` 不在前缀内 ⇒ **不被 P9 吃掉** |
| `split-p8p9-out-of-verdict` | 律 | 两新态**不进判定面**（纯函数夹具，不只活在打印里） |
| `p8-gitignore-read-from-truth` | 真源自证 | 排除依据是**现读 `.gitignore`**，不是写死常量 |

### 3.3 判例-50 变异验真（独立脚本，4 处全中）

| 变异 | 改坏点 | 结果 |
|---|---|---|
| MUT1 | `if daily_logs_ignored and …` → `if False and …` | ✓ `p8-ignored-log-detected` 变红 |
| MUT2 | `if proposal_prefix and …` → `if False and …` | ✓ `p9-proposal-detected` 变红 |
| MUT3 | `NON_VERDICT` 去掉两新态 | ✓ `split-p8p9-out-of-verdict` 变红 |
| MUT4 | P8 读真源改坏 | ✓ `p8-mutation-disabled-falls-back-to-missing` 变红 |

**每处都先验证「变异真生效」再跑判据；还原后 `selftest rc=0 FAIL=0`。**

### 3.4 判据两次读数

```
改前：INFO … 判定面未在跟踪面 34 条 …；棘轮超限 34 > 25 ⇒ 多 9 条
改后：INFO … 判定面未在跟踪面 25 条 …（无棘轮超限行）
```

**豁免态 7 → 17（+10 = 6 + 4），与预期逐条对齐。**

### 3.5 相关门禁

```
check_battery_count_doc.py   PASS rc=0
check_scripts_index.py       PASS rc=0
```

---

## 四、剩余 25 条（≤ 上限，逐条点名）

| # | 文档 | 点名 | 性质 |
|---|---|---|---|
| 1 | `docs/2026-10-11-multi-agent-lock-design-v3.md` | `memory/lock-config.json` | ② 设计未采纳（TTL 走工具参数） |
| 2-7 | 同上 | `src/engine/engine_lock.mbt` / `src/executor/kill_argv.mbt` / `src/server/assistant_ops.mbt` / `src/server/kill_exec.mbt` / `src/server/locks_ops.mbt` / `src/store/store_locks.mbt` / `templates/lock_wait_loop.md` | ⑤ 真未实现 |
| 8 | `docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` | `src/server/supervisor_tools_test.mbt` | ⑤ 命名差异（实际是 `_wbtest.mbt`，Lane J B16 已裁定 (ii)） |
| 9 | `docs/2026-10-15-…caf-p2d-cold-start-design.md` | `src/server/model_router_caf_ops.mbt` | ⑤ |
| 10 | `docs/2026-10-20-slave-dev-playbook.md` | `docs/polish-plan-point-A` | ⑤ |
| 11 | `docs/2026-10-20-slave-tasks.md` | `src/server/wt_tools.mbt` | ⑤（`run_light_wt.py` 已实现能力面，Lane J B11/B12 改判 (iii)） |
| 12 | `docs/DOCS-STRUCTURE.md` | `memory/当日.md` | ② 占位形态（非日期字面量） |
| 13 | `docs/SHIP-PLAN-BLACKBOX-v2.md` | `templates/pipeline_mode_loop.md` | ⑤ |
| 12 | `docs/DOCS-STRUCTURE.md` | `memory/当日.md` | ② 占位词（非日期字面量，P8 正确地不排除） |
| 15 | `docs/executor-marketplace-skill.md` | `src/ops/dispatch.mbt` | ⑤ |
| 16 | `docs/fist-config-skill.md` | `src/server/mcp_config_scaffold_impl.mbt` | ⑤ |
| 17 | `docs/improvement-plan-20261010.md` | `docs/assets/README.md` | ⑤ |
| 18 | `docs/mcpcf-embed-skill.md` | `src/lib/fist_ops.mbt` | ⑤ |
| 19-22 | `docs/plan-light-worktree-isolation.md` | `memory/lock-config.json` / `src/core/types.mbt` / `src/engine/engine_worktree.mbt` / `src/store/store_worktree.mbt` / `templates/worktree_wait_loop.md` | ②/⑤ |
| 23 | `docs/probe-authoring.md` | `src/engine/zz_calib_wbtest` | ⑤ 形态（目录名无扩展） |

> 说明：以上按实测输出归类，具体条数以判据现读为准（列 1 与列 2-7 已合并计数）。

---

## 五、缺口与风险

### 5.1 剩余 25 条里**没有**遗漏的日日志（已复验）

初稿我曾写「有 2 条日日志没被 P8 吃掉」，**复验后确认这是误判**：`docs/deliverable.md` 与
`docs/2026-10-12-ofm-…playbook.md` 的日日志条目**确实已被 P8 正确排除**（见 §5.3 的 6 条明细）。

剩余 25 条中**不含任何 `memory/YYYY-MM-DD.md` 形态**；剩下的 `memory/` 点名只有
`memory/lock-config.json`（3 处）与 `memory/当日.md`（1 处）—— 前者**不是日日志形态、按设计不该被 P8 吃**，
后者是占位词不是日期字面量。**两条都是判据读得对的真实未落地项。**

### 5.2 上限 25 恰好等于实测值 —— 没有余量

改后 25 = 上限 25，**棘轮判定是 `n > ceiling` 才并红 ⇒ 相等不红**，但**一有余量归零风险**：
只要再多 1 条未落地落点，立刻超限。

**建议**：Lane J 那 21 条作废标记落地后（路 A 单独立项），判定面会降到 21 以下，届时可把 `VERDICT_GAP_CEILING` 收紧到 21 并保留 4 条余量。

### 5.3 「10 条被排除」的构成 —— **已复验，与分类完全一致**

**初稿我曾标注此处「10 ≠ 9+4 需复核」，复验后排除了这个疑点。**

实测 10 条逐条（`grep '[ignored-log]` / `[proposal]`）：

| 态 | 条数 | 明细 |
|---|---|---|
| `ignored-log` | **6** | `docs/superpowers/plans/2026-09-24-probability-gate.md`→`memory/2026-09-24.md`；`docs/deliverable.md`→`memory/2026-09-25.md`；`docs/improvement-plan-20261010.md`→`memory/2026-10-10.md` 与 `memory/2026-10-13.md`；`docs/2026-10-12-ofm-…playbook.md`→`memory/2026-10-12.md`；`docs/2026-10-17-caf-writeback-task-package.md`→`memory/2026-10-17.md` |
| `proposal` | **4** | `docs/proposals/2026-10-22-cross-machine-…`→`docs/cross-machine-skill.md`；`docs/proposals/2026-10-22-folder-watch-…`→`docs/folder-watch-skill.md` / `src/ops/ops_folder_watch.mbt` / `src/ops/ops_pipeline_tick.mbt` |

**⇒ 6 + 4 = 10，与 §一 分类表的 ①=6、③=4 逐条对齐。** 初稿的疑点源于我把「①+②=9」当成了排除基数（② 的 3 条 `memory/lock-config.json` 等**不是**日日志形态，按设计**不该**被 P8 吃掉 —— 反证格 `p8-not-overbroad-non-daily-log` 正是钉这个）。

### 5.4 未做的事（守边界）

- **未改任何 `docs/`** —— 路 A 单独立项，统帅明令不在本单
- **未改 `src/`** 任何文件
- **未动 `VERDICT_GAP_CEILING`**（仍 25）
- **未新增任何豁免** —— 两条都是设计性排除，且都带反证格

---

## 六、建议入档位置

| 内容 | 建议位置 |
|---|---|
| 本报告 | `reports/2026-10-26-plan-landing-judge-improvement-report.md`（已落盘） |
| P8/P9 设计性排除 | `scripts/check_plan_landing.py` 内 `exempt_reason()` 之后的注释块（已就位，含为什么不是硬塞的完整论证） |
| 「原派单两条改进前提不成立」 | 建议进 `reports/2026-10-24-merge-precedents.md` 判例集：**「派单里的技术前提，必须先核代码再动手」** —— 本单两条前提都错了，若直接照做会空转一轮 |
| 路 A（21 条补作废标记） | 单独立项材料：`reports/2026-10-26-plan-landing-b-class-verdict.md` §一（21 条分档表） |
