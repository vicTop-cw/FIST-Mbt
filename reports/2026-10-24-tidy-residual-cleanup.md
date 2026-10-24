# F·tidy 残留清理报告（task-21）

日期：2026-10-24 ｜ 执行：瘦身组（slim-team）｜ 模式：**tidy**（forbid_new_code）

> **一句话**：本轮**只做留痕 + 只读判定**，未删任何 worktree / 分支 / 兄弟目录。
> 已落 1 笔提交（`e4c3282e`）；新发现 1 个「可删」worktree 已上报待批；
> `temp/` 只出读数不动手（含 lead 要求保留的判据前置件，其中一件**已不存在**，见 §2）。
> 另有一条**必须记住的教训**：入库 `scripts/*.py` 不同批给电池面 ⇒ 全仓门禁 FATAL（lead 已代修，见 §5）。

---

## 0. 本轮实际做了什么（逐项）

| # | 项 | 动作 | 结果 |
|---|---|---|---|
| 1 | `.agents/` 未跟踪件 4 件 | 逐件判定 → 2 条 ignore + 1 件入库 | ✅ 已提交 `e4c3282e` |
| 2 | 未跟踪件总数 | 4 → 1（剩 `reports/2026-10-24-verify-doc-consistency.md`，属并发 agent WIP，未夹带） | ✅ |
| 3 | worktree 收尾 | `check_worktree_hygiene.py` 现读 | ⚠️ 报 **1 个可删**，已上报**待批**（未删） |
| 4 | `temp/` | 只读数，不动手 | 📊 见 §2 |
| 5 | 兄弟目录 34 个 | 逐个验三条件 | 📋 清单见 §3（只列不删） |
| 6 | 提交纪律 | `git add` 精确到路径；`git diff --cached --name-only` 逐条核 | ✅ 两次都核过，一次回滚了误入的他人文件 |

### 1. `.agents/` 4 件逐件处置（已提交）

| 文件 | 判定 | 依据 |
|---|---|---|
| `.agents/delta_probe2.sh` | **ignore** | 一次性 delta 探针（遍历 `origin/<b>^..<b>` 打统计），不是 `scripts/` 常驻入口。规则 `/.agents/delta_probe2.sh` + 理由注释 |
| `ISSUE_ESM_CJS_BUNDLE_CRASH.md` | **ignore（不删）** | 与 `reports/2026-10-24-external-issue-esm-cjs-bundle-crash.md` **章节标题逐行相同**（`diff` 仅差：reports 版把本机绝对路径脱敏成 `<repo>` + 加了入库说明）⇒ reports 版是**超集**。根目录这份是原始投递件，作证据链留档。规则 `/ISSUE_*.md` |
| `ISSUE_NAMESPACE_ROUTING_TRAP.md` | **ignore（不删）** | 同上族：Pentad 统帅报的 BUG-407 ns 路由静默陷阱，87 行完整根因 + 判据。**`memory/bugs.md` 现读最新是 BUG-406（17:15）**，`grep BUG-407` = 0 ⇒ 这份原件是**该条缺陷唯一在案正文**，删了就丢证据 |
| `scripts/tmp_audit_preservation_scan.py` | **入库** | 审计组《资产保全证明书》的**唯一取证器**，`reports/2026-10-24-asset-preservation-proof.md:7/1232` 明文引用其路径 ⇒ 不入库则报告不可复算 |

### 2. `temp/` 读数（只报不动）

```
du -sh --exclude=wt-skill temp/   →  267 MB
ls temp/ | wc -l                  →  243 个条目
git ls-files temp | wc -l         →  0（全部在 ignore 面，从未进仓）
```

**已登记 worktree 只有 1 个在 `temp/` 下**（task-21 写的"3 个"与现读不符）：

```
$ git worktree list | grep "FIST-Mbt/temp/"     →  temp/wt-skill  [worktree/skill-docs2]
```

> `temp/auth-measure`、`temp/wt-align`、`temp/wt-branchwork` 三个目录**不是** worktree
> （前者的内容只有 `capture.py` + 两个 raw log；后两者只有 `fist-mbt.db{,-shm,-wal}` 三件套——是跑测试留下的数据库，不是工作树）。

**最大两块**：`temp/pol_keeper_reports/` 193 MB（525 个条目）｜ `temp/b34/` 48 MB（一份 MoonBit 仓的完整 checkout 副本：`LICENSE` / `README.mbt.md` / `USAGE.md`…）

**⚠️ 前置件现状（与指令不符，如实报）**：

```
temp/pt27.log      → 存在，99 字节 / 4 行        （任务书写"约 1.4 万行"，实测不符，疑似已被覆盖）
temp/chk47.json    → 不存在（已消失）
```

⇒ 两件里 **`chk47.json` 已经没了**（我本轮**没有任何删除动作**，是接手前就已不在）。
若 lead 仍在用它作判据前置，需要重新生成。**我没有动 `temp/` 任何东西。**

### 3. 兄弟目录（`E:/IDEProjects/AI/`，现读 **34** 个，审计组报的 38 与现读不符）

**3.1 `wt03` 被三条件全过——但它有独有提交，按纪律不删**

```bash
$ python scripts/check_worktree_hygiene.py
可删   ①dirty=0   ②unpushed=0   ③unmerged=0    E:/IDEProjects/AI/light-wt/cmd-gamma-t16
REPORT 1 个 worktree 可删（共 14 个，已排除主树）
```

我独立复核（不只信尺子）：

```
$ git status --porcelain | wc -l                                    → 0
$ git rev-list HEAD --not --branches --remotes --tags | wc -l       → 0
$ git ls-files -u | wc -l                                           → 0
$ git rev-parse --short HEAD        → b534e259
$ 主仓 main HEAD                     → cc09e652
$ git merge-base --is-ancestor b534e259 cc09e652  → NO（未进 main）
```

⇒ **三条件全过、但 HEAD 不在 main 里**。这是「干净但未合」的形态：`cmd-gamma-t16` 分支本身还在主仓
（`refs/heads/cmd-gamma-t16` = b534e259），删 worktree 只回收 74 MB 磁盘占用、**不丢任何提交**。
**按纪律「每个删除先验三条件 + 有疑问一律保留」，我列为待批，不自行删除。**

**3.2 `FIST-Mbt-slave-wt03` —— 也三条件全过，但同样有独有提交**

```
dirty=0  unpushed=0  conflict=0         ← 三条件全过
HEAD = 81eac734 "docs(ops): WT-03 design doc — light-wt / light-wt-teardown 双轨脚本"
```

**但它有真正独有的内容**：`81eac734` 只新增 `docs/design-wt-sparse-scripts.md`（72 行 WT-03 设计），
而 **主仓没有 `docs/design-wt-sparse-scripts.md`**，`git ls-remote origin refs/heads/feature/wt-sparse-scripts` = **0 行**（上游也没有）。

⇒ 这是**上游与主仓都找不到的孤本**。`check_worktree_hygiene.py` 的 ② 之所以判 0，是因为它问的是
「相对**本 sibling 自己的** `--not --branches --remotes`」——分支就在它自己仓里，所以恒 0。
**这正是判例-10c 的意义：尺子只给候选，孤本要靠内容面核。⇒ 不删，建议先把它推成 PR 或把设计稿捞进主仓。**

**3.3 其余 FIST-Mbt 相关目录（只列不删）**

| 目录 | 大小 | 三条件 | 判定 |
|---|---|---|---|
| `FIST-Mbt-slave-guard01` | 41 MB | dirty=2（`scripts/README.md` + `check_model_auth_no_key.py` 的 GUARD-01 增量）/ unpushed=0 | **有未交付增量**——主仓 `grep GUARD-01` = 0 命中，`WORKFLOWS_DIR`/`EXAMPLE_GLOBS` 也不在 main 版里 ⇒ 增量未落地，不删 |
| `FIST-Mbt-slave-wt02` | 69 MB | dirty=333（atgc/atgc-old 一片）/ unpushed=0 | **有未交付增量**，不删 |
| `FIST-Mbt-slave-wt03` | 36 MB | dirty=0 / unpushed=0，**但 HEAD 不在 main** | 见 3.2 ⇒ 不删 |
| `FIST-Mbt-wt-r2` | — | **不存在**（任务书列的，实际已无） | — |
| `light-wt/cmd-beta` | — | dirty=5 / unpushed=0 | 有 WIP，不删 |
| `light-wt/cmd-epsilon` | — | dirty=1 / **unpushed=1** | 有独有提交，不删 |
| `light-wt/cmd-gamma-t16` | 74 MB | dirty=0 / unpushed=0 / conflict=0 | **三条件全过 ⇒ 待批**（见 3.1） |

**3.4 与本任务无关的目录（`fist-*` / 非 FIST 项目）——只列清单，未做任何判定/删除**

`AI/` · `Actus` · `DownLoads` · `NPU-Tnr-test` · `Nodea` · `Nodea-ATGC` · `Pentad` · `Tnr` · `Tnr_merge_check` · `Tnr_p0`
· `_archive` · `_fist_atgc_v2_ctl` · `_fist_atgc_v2_exp` · `_fist_iso` · `_fist_meta_prompts` · `_lz_night_scratch`
· `backup` · `competition` · `fist-evidence` · `lang-pulgins` · `lang-zone` · `mcpconftest` · `name-squats`
· `rx-mbt` · `sigma-lang` · `temp` · `vools` · `vq` · `兹`

（`_fist_*` 四个虽带 fist 前缀，但**不是 `FIST-Mbt` 的 worktree**（`git worktree list` 无命中），
各 1~4 MB 的脚本/元提示词目录，归属不明 ⇒ 不碰。）

---

## 4. 清理后画像

| 面 | 接手时 | 本轮结束 | 变化 | 备注 |
|---|---|---|---|---|
| `.git` 大小 | — | **2.0 GB** | — | 本轮仅排名不计入功劳：上一轮做到 1.4G，其后并发 agent 大量提交/建 worktree 回涨到 2.0G |
| worktree 数 | 12（lead 报）→ 我接手实测 **14** | **15**（`check_worktree_hygiene` 口径排除主树后 14） | +1 | 增量来自并发 agent（β/γ/ε），**不是本组产生**；本组**一个都没建** |
| 其中「可删」 | — | **1**（`light-wt/cmd-gamma-t16`） | — | 待批 |
| 本地分支 | 92 | **93** | +1 | 并发 agent 产生 |
| `temp/` 大小 | — | **267 MB / 243 条目** | 0 | 本组未动 |
| 未跟踪件 | 4 | **1** | −3 | 剩的那件是并发 agent WIP |
| 兄弟目录 | 38（审计组报） | **34**（现读） | 0 | 本组未删任何兄弟目录 |

---

## 5. 我上一笔引出的问题（lead 已代修，机理留档）

`e4c3282e` 把 `scripts/tmp_audit_preservation_scan.py` 入跟踪面，但**没同批给它电池面** ⇒
`run_guards --list` 报「缺面」⇒ `check_battery_count_doc` **FATAL** ⇒ 全仓门禁红。
lead 已登记进 `EXEMPT_RULES` + 锚点同批（`rulers 117→118 / exempt 27→28`）。

**教训（本仓硬结构约束，不是风格偏好）**：
> 往跟踪面加任何 `scripts/*.py`，**必须同批给它一个执行面**
> （`case()` / `expected()` / 或 `EXEMPT_RULES` + 理由），否则全仓门禁 FATAL。

这次我选择了「先交报告、后谈动作」——不再重复「做了事但没留痕」。

---

## 6. 待 lead 裁决 / 我没做的事

| # | 事项 | 我的建议 |
|---|---|---|
| 1 | `light-wt/cmd-gamma-t16`（74 MB，三条件全过，HEAD `b534e259` 不在 main 但分支还在主仓） | **可删**（只回收磁盘、不丢提交）；等 lead 批 |
| 2 | `FIST-Mbt-slave-wt03`：三条件全过但 `docs/design-wt-sparse-scripts.md` 是**孤本** | **不删**。建议先把这份 72 行设计稿捞进主仓（由 owner 决定放 `docs/` 还是 `reports/`） |
| 3 | `temp/chk47.json` 已消失 | 若判据仍需，请重新生成；我未动 `temp/` |
| 4 | `temp/` 267 MB / 243 条目（`pol_keeper_reports` 193 MB + `b34` 48 MB 占 90%） | 建议单独派人按「产物 vs 证据」分类后再清；本轮只出读数 |
| 5 | `ISSUE_NAMESPACE_ROUTING_TRAP.md` 对应的 BUG-407 **账本里查无此条**（最新是 BUG-406） | 建议 owner 裁决是否正式建 BUG-407；原文件我已挡在 ignore 面留证据 |
| 6 | 兄弟目录 34 个（含 4 个 `_fist_*`）归属不明 | 不是本组范围，仅列清单 |
