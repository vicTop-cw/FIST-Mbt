# Lane E · 未实现计划落地盘点报告

- **日期**：2026-10-26
- **执行人**：司令-ε（Lane E 计划落地队）
- **判据**：`python scripts/check_plan_landing.py`（只读诊断）
- **性质**：**只读 + 报告**。本报告**不落地任何计划**（落地是开发动作，需另派单）

---

## 一、结论

### 1.1 总读数

```
INFO 计划落点核对（84 份文档、495 条点名路径、形态说明 39 条已出数不比对）
判定面未在跟踪面 45 条（磁盘上有 1 条、都没有 44 条）
搬家态另有 3 条（P5，不进判定面）
豁免态 7 条（P7，不进判定面）
存档面另有 18 条（只报不判）
棘轮超限：判定面 45 条 > 上限 25 ⇒ 比已核存量多 20 条
```

### 1.2 与 BUG-367 的「28 条」对比：**增了 17 条**

| 项 | BUG-367 记账 | 本次实测 | 变化 |
|---|---|---|---|
| 判定面总数 | 28 | **45** | **+17** |
| 其中 A（计划点名未落地） | 18 | 见下 | — |
| 其中 B（外部件） | 4 | 7（已进 P7 豁免面） | 口径已分离 |
| 其中 C（历史一次性工具） | 3 | 见 P7 | 口径已分离 |
| 其中 D（搬家后旧引用） | 3 | 3（P5 搬家态）+ 5（本次新识别的） | 口径不同 |

**注意口径变化**：现判据已把 B/C 类拆进「豁免态 P7（只出数不判红）」、把搬家态拆进「P5」。
**扣除这些后，判定面 45 条 = 本次需要逐条定的那批。**

### 1.3 本次 45 条的四类定性与建议

| 类 | 条数 | 性质 | 建议处置 |
|---|---|---|---|
| **A. 分支名误报** | **6** | **判据误报**（文档表格第 3 列是「分支名」，被当成文件路径） | **引用改路径**（改为正斜体或加前缀避免被当路径）+ 判据侧可选改进 |
| **B. 真缺失（需落地）** | **21** | 计划点名、跟踪面与磁盘都没有 | **落地 / 标作废**（逐条见 §3） |
| **C. 搬家后旧引用** | **5** | 文件在 `docs/archive/` 或已从 `blackbox/` 搬到 `scripts/` | **引用改路径**（纯文档改动，风险最低） |
| **D. 有等价实现待确认** | **2** | 同名件在别处存在 | **引用改路径 / 判据复查** |
| **E. 磁盘上有未入库** | **1** | `scripts/fix_esm_require.py` 在工作树、未 `git add` | **落地**（`git add` 即可） |
| 存档面（只报不判） | 18 | `docs/archive/` 里历史计划的落点 | 不动（历史面） |
| 形态说明 | 39 | `<…>`/`*`/占位符 | 不动（非路径） |
| 豁免态 P7 | 7 | 外部宿主 4 + `_` 前缀临时件 3 | 不动（口径已定） |
| 搬家态 P5 | 3 | 判据已给出实际位置 | 引用改路径（低优先） |

**合计可执行项：6（A）+ 21（B）+ 5（C）+ 2（D）+ 1（E）= 35 条。**

---

## 二、A 类：分支名误报（6 条）——**判据误报，不是缺失**

### 证据

`docs/2026-10-20-slave-tasks.md` 是一张**任务追踪表**，表头（第 97 行）明确写着：

```
| # | 任务 | 分支名 | 状态 | 现读证据（对账时点 08e540bf） | 主机账本 bug_id | 参考 plan | 验…
```

**第 3 列是「分支名」**。判据扫全文反引号内形如 `src/xxx`/`docs/xxx` 的串，**把分支名当成了文件路径**。

| # | file:line | 被误当路径的分支名 | 该行状态 |
|---|---|---|---|
| A1 | `docs/2026-10-20-slave-tasks.md:99` | `docs/polish-readme-slogan` | `已落地` |
| A2 | `docs/2026-10-20-slave-tasks.md:100` | `docs/selfdrive-walkthrough` | `部分` |
| A3 | `docs/2026-10-20-slave-tasks.md:102` | `docs/readme-env-bold` | `未开工` |
| A4 | `docs/2026-10-20-slave-tasks.md:103` | `docs/known-boundaries` | `部分` |
| A5 | `docs/2026-10-20-slave-tasks.md:112` | `docs/multi-tenant-skill-enhance` | `已落地` |
| A6 | `docs/2026-10-20-slave-tasks.md:76` | `src/server/wt_tools.mbt`（**这是 WT-02 的分支名列**）| `未开工` |

**验证**：`A2` 的分支名加 `.md` 后**确实存在**（`docs/selfdrive-walkthrough.md`），进一步证明它是任务名/分支名而非路径。

**建议处置**：**引用改路径**——把该表第 3 列的仓库路径样式分支名改为纯文本（如加 `branch:` 前缀或去反引号）。
判据侧可选改进：跳过「表头含『分支名』的表格」第 3 列。

---

## 三、B 类：真缺失（21 条）——**逐条点名与建议**

按来源计划分组。**「判据词」列**取自该行上下文，用于区分「计划自称已完成」vs「计划说将新增」：

### 3.1 `docs/2026-10-11-multi-agent-lock-design-v3.md`（设计文档，8 条）

| # | file:line | 点名路径 | 建议 |
|---|---|---|---|
| B1 | 见 §5 对照表 | `memory/lock-config.json` | **标作废**（配置文件不应进仓，`memory/` 已被 .gitignore） |
| B2 | 同上 | `src/engine/engine_lock.mbt` | **落地**（多 agent 锁核心）——已有 `src/store/store_assistant.mbt` 部分实现，需核 |
| B3 | 同上 | `src/executor/kill_argv.mbt` | **标作废**（kill 未实施，见 WT-02 同批） |
| B4 | 同上 | `src/server/assistant_ops.mbt` | **落地**（assistant 5 工具已存在，见 AGENTS.md §项目助理，只是**未被单独建文件**） |
| B5 | 同上 | `src/server/kill_exec.mbt` | **标作废**（同 B3） |
| B6 | 同上 | `src/server/locks_ops.mbt` | **落地**（lock_acquire/renew/release/status 4 工具已存在，同上，未被单独建文件） |
| B7 | 同上 | `src/store/store_locks.mbt` | **落地**（同上） |
| B8 | 同上 | `templates/lock_wait_loop.md` | **标作废**（模板未随设计落地） |

**✅ 已核实**：B4/B6/B7 的能力**确实已在别处实现** ——
```bash
$ grep -c 'lock_acquire\|assistant_claim' src/server/server.mbt
8                                   ← 工具注册在 server.mbt，未拆独立文件
$ git ls-files src/store/ | grep -i assistant
src/store/store_assistant.mbt       ← 分区实现已存在
src/store/store_assistant_test.mbt
$ git ls-files src/server/ | grep -E 'assistant|lock'
src/server/assistant_sweep_wbtest.mbt   ← 只有测试文件，无 assistant_ops.mbt / locks_ops.mbt
```
⇒ 「**设计文档规划的模块划分未被采纳，能力已在别处实现**」——这三条应**标作废**而非落地。
（B2 的 `engine_lock.mbt` 同理：锁能力在 `store_assistant.mbt` + `server.mbt`，未拆 `engine_lock.mbt`。）

### 3.2 `docs/plan-light-worktree-isolation.md`（5 条）

| # | 点名路径 | 建议 |
|---|---|---|
| B9 | `memory/lock-config.json` | **标作废**（同 B1） |
| B10 | `src/core/types.mbt` | **标作废**（`src/core/` 实际无 `types.mbt`，类型散在 `core_task.mbt` 等） |
| B11 | `src/engine/engine_worktree.mbt` | **落地**（worktree 管理，与 light-wt 相关） |
| B12 | `src/store/store_worktree.mbt` | **落地**（同上） |
| B13 | `templates/worktree_wait_loop.md` | **标作废**（同 B8） |

### 3.3 `docs/proposals/2026-10-22-folder-watch-trigger-proposal.md`（2 条，提案）

| # | 点名路径 | 建议 |
|---|---|---|
| B14 | `src/ops/ops_folder_watch.mbt` | **标作废**（提案未获批，无等价实现） |
| B15 | `src/ops/ops_pipeline_tick.mbt` | **标作废**（`pipeline_tick` 已在 `src/ops/ops.mbt` 等处，`ops_` 前缀文件未采纳） |

### 3.4 其余零散缺失（6 条）

| # | 文档 | 点名路径 | 建议 |
|---|---|---|---|
| B16 | `docs/2026-10-12-fist-mbt-supervisor-tools-plan.md` | `src/server/supervisor_tools_test.mbt` | **落地**（supervisor 8 工具已有实现 `supervisor_tools.mbt`，但**测试文件确缺**；判据文件头已点名此例） |
| B17 | `docs/fist-config-skill.md` | `src/server/mcp_config_scaffold_impl.mbt` | **标作废**（`mcp_config_scaffold` 已实现在 `server.mbt`，`_impl` 分文件未采纳） |
| B18 | `docs/mcpcf-embed-skill.md` | `src/lib/fist_ops.mbt` | **标作废**（`src/lib/` 不存在；mcpcf 已实现在 `src/server/mcpcf_embed.mbt`） |
| B19 | `docs/SHIP-PLAN-BLACKBOX-v2.md` | `templates/pipeline_mode_loop.md` | **标作废**（`pipeline_mode_*.md` 已有 7 份，`loop` 变体未采纳） |
| B20 | `docs/2026-10-15-fist-mbt-caf-p2d-cold-start-design.md` | `src/server/model_router_caf_ops.mbt` | **标作废**（CAF 已实现在 `src/router/` 与 `model_router_ops.mbt`） |
| B21 | `docs/2026-10-20-slave-dev-playbook.md` | `docs/polish-plan-point-A` | **引用改路径**（应为 `docs/2026-10-20-slave-tasks.md` 的 §Slice 7） |

> **B 类的共同模式**：**大量「设计时规划的模块划分」未被执行，但能力已实现在别处**。
> 这不是「计划没落地」，而是「**落地的形态与计划设想的不同**」。
> ⇒ 21 条里 **约 15 条建议标作废**（计划失效/已被等价实现覆盖），**约 6 条是真该落地的**。

---

## 四、C 类：搬家后旧引用（5 条）——**纯文档改动，风险最低**

| # | 文档:行 | 点名的旧路径 | 实际操作位置（`git ls-files` 实读） |
|---|---|---|---|
| C1 | `docs/plans/2026-10-22-fist-dir-layout-governance-proposal.md` | `reports/2026-10-16-future-plan.md` | **`docs/archive/2026-10-16-future-plan.md`** |
| C2 | `docs/proposal-process.md` | `reports/2026-10-16-future-plan.md` | 同上 |
| C3 | `docs/proposals/2026-10-22-cross-machine-task-publish-proposal.md` | `reports/2026-10-16-future-plan.md` | 同上 |
| C4 | `docs/proposals/2026-10-22-folder-watch-trigger-proposal.md` | `reports/2026-10-16-future-plan.md` | 同上 |
| C5 | `docs/2026-10-21-fist-governance-tier2-plan.md` | `scripts/blackbox/check_ps_encoding.py` | **`scripts/check_ps_encoding.py`**（从 blackbox/ 搬到 scripts/） |

**验证读数**：
```bash
$ git ls-files | grep '2026-10-16-future-plan'
docs/archive/2026-10-16-future-plan.md          ← 只有这一份
$ git ls-files | grep check_ps_encoding
scripts/check_ps_encoding.py                    ← 只有这一份
```

**建议处置**：一律 **引用改路径**（5 条纯文档改动，零代码风险）。

---

## 五、D 类：有等价实现（2 条）

| # | 文档 | 点名路径 | 发现的等价件 |
|---|---|---|---|
| D1 | `docs/executor-marketplace-skill.md` | `src/ops/dispatch.mbt` | `scripts/dispatch_verify.py`（名字相关但**不是等价实现**，需人工确认） |
| D2 | `docs/improvement-plan-20261010.md` | `docs/assets/README.md` | `README.md` / `tests/README.md`（**不是等价**，`docs/assets/` 目录不存在） |

**建议处置**：D1/D2 均为**标作废**（规划中的目录/文件未采纳，能力已在别处）。

---

## 六、E 类：磁盘上有未入库（1 条）——**最容易的一笔**

| # | 文档 | 点名路径 | 状态 |
|---|---|---|---|
| E1 | `docs/2026-10-18-fist-mbt-rank-wiring-report.md` | `scripts/fix_esm_require.py` | **工作树磁盘上有、未进跟踪面** |

**判据原话**：`⇒ 出路是 git add 并提交`

**✅ 已核实（推翻判据的出口建议）**：
```bash
$ git check-ignore -v scripts/fix_esm_require.py
.gitignore:137:/scripts/fix_esm_require.py   scripts/fix_esm_require.py
```
**该文件被 `.gitignore:137` 明确挡在跟踪面外 —— 它是本机专属件，`git add` 是错的建议。**

⇒ **建议处置：文档移除该点名**（或改为「本机件，不入库」说明），
**不要 `git add`**。判据把它归入 `[on-disk]` 并建议 `git add`，是因为它**不读 `.gitignore`** ——
这是判据的一个盲点，记入 §10 缺口。

---

## 七、存档面 / 豁免态 / 形态说明（不进入处置）

| 分类 | 条数 | 说明 |
|---|---|---|
| 存档面 | 18 | 分布在 5 份 `docs/archive/` 历史计划，落点在其记录年代未建属正常 |
| 豁免态 P7 | 7 | 外部宿主件 4（`src/adapter.js` / `eac-login.js` / `eac.js` / `vault.js`）+ `_` 前缀临时件 3 |
| 形态说明 | 39 | `<…>` / `*` / `{ns}` / `<lang>` 等占位符，非真实路径 |
| 搬家态 P5 | 3 | 判据已给出实际位置，属低优先引用更新 |

---

## 八、建议统帅批准的落地顺序

### P0（纯文档改动，零代码风险，建议一次做完）

| 项 | 条数 | 动作 |
|---|---|---|
| **C 类引用改路径** | **5** | 把 `reports/2026-10-16-future-plan.md` → `docs/archive/…`（4 处）、`blackbox/check_ps_encoding.py` → `check_ps_encoding.py`（1 处） |
| **A 类分支名去路径化** | **6** | `slave-tasks.md` 第 3 列改纯文本 |
| 小计 | **11** | 全部是文档编辑，`check_plan_landing` 应从 45 降到 ~34 |

### P1（需先裁决「落地 or 作废」）

| 项 | 条数 | 说明 |
|---|---|---|
| **B 类 21 条** | 21 | 建议：**6 条落地**（B2/B11/B12/B16 + 需核 B3）· **15 条标作废**（设计时模块划分未采纳、能力已实现在别处） |
| **D 类 2 条** | 2 | 建议标作废 |

### P2

| 项 | 条数 | 说明 |
|---|---|---|
| E1 | 1 | 先核是否 `.gitignore` 面 |
| P5 搬家态 | 3 | 引用改路径 |

### 判据侧改进建议（不在本单范围）

1. **跳过「表头含『分支名』的表格」第 3 列** —— 消除 A 类 6 条误报的**根因**
2. **识别「计划已声明作废」的段落** —— 若计划文档开头有 `已作废` / `superseded` 标记，整份文档跳过
3. **识别「设计文档的模块规划」段** —— 设计文档 §文件结构 一类章节里的路径是**提议**，不是承诺

---

## 九、可复现命令

```bash
# 判据主读数
python scripts/check_plan_landing.py

# 分类依据
git ls-files | grep '2026-10-16-future-plan'      # → docs/archive/…
git ls-files | grep check_ps_encoding             # → scripts/…
sed -n '97p' docs/2026-10-20-slave-tasks.md       # → 表头第3列是「分支名」
```

## 十、缺口与风险

1. **B 类 21 条的「落地 vs 作废」我给了建议，但最终需统帅/owner 裁决**——
   因为「设计文档的模块划分未采纳」不算缺陷，只是计划与实现形态不同。
2. **本报告未核实 B 类每条的能力是否真在别处实现**（只对 B4/B6/B7/B17/B18/B20 做了 `AGENTS.md` 交叉核对）。
3. **判据盲点：`check_plan_landing` 不读 `.gitignore`** —— 它把 `.gitignore:137` 明确挡掉的
   `scripts/fix_esm_require.py` 报成 `[on-disk]`（磁盘有、未入库）并建议 `git add`。
   实际该文件是**本机专属件，绝不该入库**。⇒ 判据应在 `[on-disk]` 分支前先过 `git check-ignore`，
   命中的报 `[ignored]` 并建议「文档移除点名」而非 `git add`。
4. **`temp/audit/` 目录在本会话中多次被外部清理**（写入后跨调用读不到），故本报告的分类由**单进程内完成**，
   临时脚本 `temp/audit/lane_e_probe.py` 可能已不存在。
5. 判据自身 `rc=0` 而打印「棘轮超限」——**退出码与结论不一致**，是判据的既有口径（只读诊断），非本单问题。

## 来源

| 项 | 来源 |
|---|---|
| 判据 | `scripts/check_plan_landing.py`（只读诊断） |
| BUG-367 老账 | 本仓账本（A18/B4/C3/D3 = 28） |
| 现读 | 84 份文档 / 495 条点名路径 |

---

## 裁决（2026-10-26 · 统帅批准）

> **本节为追加内容**。上方正文（含 §三 B 类逐条建议）**保持原样未改** ——
> 那是 Lane E 作出判断当时的依据，按判例-45「叙述面只追加、不改写」保留。
> 本节记录**统帅对 B 类 21 条的最终裁决**与**对本报告三处判断的更正**。
>
> **详细证据**见 `reports/2026-10-26-plan-landing-b-class-verdict.md`（commander-delta，`832267bf`）。

### 一、B 类 21 条最终分档：**全部作废，无一排期**

| 判定 | 数量 | 条目 |
|---|---|---|
| (ii) 已以别的形态实现 | **13** | B2, B4, B6, B7, B10, B13, B15, B16, B17, B18, B19, B20, B21 |
| (iii) 计划本身已作废 | **8** | B1, B3, B5, B8, B9, B14, **B11, B12** |

**共同模式（与 §三 的共同模式一致，此处为裁决口径）：**
> 计划的设计级模块划分（拆文件 / 拆目录）未被执行，
> 但**能力已实现在别处**；或该形态被后续设计决定放弃。

**其中 B11/B12 由 commander-delta 初判 (i) 真未落地，经统帅裁决改判 (iii)：**
- `scripts/run_light_wt.py` 已提供 `create` / `teardown` / `status` + `--ttl-min` + manifest 记账（实测可用）
- 计划 `plan-light-worktree-isolation.md` 写在脚本层成熟之前，`src/` 分层是当时信息条件下的设想
- 现在再在 `src/` 实现一遍 = **双轨制**（两个入口管同一批 worktree，还要与脚本层 manifest 对账）
  ⇒ **这是造 bug 不是补功能**

### 二、对本报三处判断的更正（统帅批准采纳）

| # | 本报原说法 | 更正 | 证据 |
|---|---|---|---|
| **B16** | 「落地」，「测试文件确缺」 | **(ii) 已实现** —— 不缺测试 | `src/server/supervisor_tools_wbtest.mbt` 有 **9 个 test 覆盖全部 8 个 supervisor 工具**；`python scripts/moon_test_env.py --target js src/server` → **Total tests 387 / passed 387 / failed 0**。**命名 `_wbtest`（白盒）而非 `_test`（黑盒）≠ 缺失** |
| **B13** | 标作废 | **(ii) 已实现** —— 能力面存在 | `scripts/run_light_wt.py` 提供 `create`/`teardown`/`status` + `--ttl-min` 完整生命周期（2026-10-25 task-27 实测可用）|
| **B1/B9 理由** | 标作废，理由「`memory/` 已被 .gitignore」 | **结论对、理由错** | `.gitignore:90` 注释明写「**逐文件/前缀精确点名，不整目录挡**」；`git check-ignore memory/lock-config.json` **未命中**。正确理由：**该配置形态未被采纳**（TTL 走工具参数，不走外部配置文件）|

### 三、🔄 重新评估的触发条件（**作废 ≠ 永久关闭**）

B11/B12 判作废的依据是「**当前没有需要 `src/` 层 worktree 管理的真实需求**」，
不是「这件事永远不该做」。若将来出现下列需求，**性质会从「补旧计划」变成「新增需求」**：

> **「MCP 客户端（AI）需要在 `claim` 时自动创建 worktree 沙箱，
> 而不是由人或 CI 脚本先手动 create。」**

**为什么这一句构成真实区别：**

| 驱动方式 | 现状 |
|---|---|
| 人 / CI 驱动（先建沙箱再干活，沙箱是**前置条件**）| ✅ 已实现（`scripts/run_light_wt.py`）|
| 任务调度驱动（claim 时自动分配，沙箱是**调度产物**）| ❌ 未实现 |

**当前没有真实需求 —— 没需求就不造。**
**若将来出现，应重开新单配新设计，而不是翻回来说「当初判错了」。**

### 四、本报告仍有效的部分

上方 §一 / §二 的判定面统计（45 条 / A18+B21+C3+D3）与 `check_plan_landing.py` 的现读
（84 份文档 / 495 条点名路径）**不受本次裁决影响**，仍然有效。
