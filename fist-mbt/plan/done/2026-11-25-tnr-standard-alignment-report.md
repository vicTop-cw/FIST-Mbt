---
status: 已完成
completed_by: codearts
completed_at: 2026-11-25T13:40:00+08:00
task_id: T0r47
namespace: autoplan
---

# T0r47 · 规范收编·tnr：按 AI-DEVELOPMENT-STANDARD.md 全面对表

> 执行者：AtomCode（fist-mbt 任务池，ns=autoplan，执行身份 codearts）
> 约束：只读盘点 + 最小改动；产出物写明路径。
> 真源：[`AI-DEVELOPMENT-STANDARD.md`](../../../AI-DEVELOPMENT-STANDARD.md) §2「计划文件规范」（第 43–45 行）＋ `:47` 历史豁免边界。
> 本报告即本轮交付物，落位 `fist-mbt/plan/done/`（规范规定的归档位，同时满足任务「入 done 区」要求）。

## 1. 结果摘要

按四条对表面逐条实扫，结论：**命名面与三区结构基本合规，真正未收口的是「计划目录收编」的三处残留**——
两份**规范性表面**仍指向已废弃的旧计划目录 `docs/plans/`（本轮已改），一份**运行态账本**仍把计划登记在旧路径上，
外加一处**引用悬空**（`docs/plans/README.md` 全仓被引用但文件不存在）。`_` 前缀面与 docs 命名面均干净。

| 对表面 | 判定 | 关键读数 |
|---|---|---|
| 文件命名 | ✅ 合规 | `draft/active/done/decisions` 四区 .md 全部命中 `^\d{4}-\d{2}-\d{2}-.+\.md$`；仅 1 份非 .md 数据件（见 §4） |
| 计划目录收编 `fist-mbt/plan/{draft,active,done}` | ⚠️ **3 处残留已修 + 1 处运行态漂移** | `docs/README.md` / `docs/DOCS-STRUCTURE.md` 旧路径指向已改；`autoplan-plans.json` P3 `file` 仍指旧路径（账本，见 §4） |
| `_` 前缀不入库 | ✅ 干净 | 判据 `check_underscore_ignore.py` 实跑 rc=0；游离件 0 |
| 冗余文件清理 | ⚠️ 1 项零风险可清（未动） | 根 `_mcp_tools.txt` 已 `git rm`（工作树 D）；`.fist-mbt/tmp/_mcp_tools.txt` 为忽略态残留 |
| docs 归档命名（J15） | ✅ 合规 | `docs/*.md` 73 份，含日期数字却无 `YYYY-MM-DD-` 前缀的仅 `improvement-plan-20261010.md`（J15 明列豁免族） |

## 2. 证据

### 2.1 判据实跑（L3/L4）

```
python scripts/check_plan_location.py
  [扫描] fist-mbt/plan/draft 下 20 份计划文档，其中 8 份解析到 `status:`
  [扫描] docs/proposals 下 3 份提案文档（另按名跳过说明/模板 1 份：TEMPLATE.md），其中 2 份解析到 `status:`
  [违例] 1 条：
    ✗ [P9] docs/proposals/2026-11-22-longrun-upgrade-proposal.md — 缺强制字段 `status`
  [结论] 有违例                                          rc=1

python scripts/check_plan_location.py --selftest     → [selftest] 58/58 格通过
python scripts/check_underscore_ignore.py           → PASS 工作树无游离的 `_` 前缀件   rc=0
```

散落对表读数（同一实跑输出）：**扫描面 1339 份日期前缀文档，制裁位外基线 28 条，新散落 0**。
⇒ `docs/plans/` 下现有件都在基线/制裁面内，不是新散落违例；但**规范性表面的旧路径指向**是另一回事（§3.1）。

### 2.2 四区文件清单与命名实扫

| 区 | 份数 | 命名合规 | 备注 |
|---|---|---|---|
| `draft/` | 20 | ✅（19 .md + 1 非 md） | 8 份解析到 `status:`；5 份为早期 `-proposal.md`/`-owner-decision.md`/`-verdict.md`（`status: 已定案`，仍在 draft） |
| `active/` | 2 | ✅ | `2026-11-25-butler-patrol-trigger.md`、`2026-11-25-fist-agent-worker-issue1.md`（**均未跟踪**） |
| `done/` | 2 | ✅ | `2026-10-24-wt03-sparse-scripts-proposal.md`、`2026-10-26-4pools-rhop-roadmap-proposal.md` |
| `decisions/` | 5 | ✅ | 记录面，命名 `YYYY-MM-DD-<slug>.md` |

注：守卫 `check_plan_location.py` **只判 `draft/` 本层 + `docs/proposals/`**（`enumerate_docs` 明写「`decisions/`、`archived/` 不进判定面」），
故 `active/` 与 `done/` 两区的命名合规是本轮**自行补扫**得出，不是守卫读数——这是一处判定面缺口（§5 建议）。

### 2.3 `_` 前缀面

| 形态 | 件 | 判定 |
|---|---|---|
| 有意跟踪的 `_` 共享模块 | `scripts/_badge_anchor.py`、`_deployment_symbols.py`、`_mutation_probe.py`、`_tool_registry.py` | ✅ 电池豁免惯例（AGENTS 明载） |
| 运行态忽略件 | `.fist-mbt/tmp/_mcp_tools.txt`（`.gitignore:234` `/.fist-mbt/` 整目录挡） | ✅ 合法本地工件 |
| 研究快照 | `memory/research/_snapshot.md`（102 行，27KB） | ⚠️ 历史面，`memory/` 属历史豁免（§4） |
| 根级残留 | `_mcp_tools.txt` | **已 `git rm`**（工作树 `D _mcp_tools.txt`）⇒ 已不入库 |

### 2.4 docs 归档命名（J15）

`docs/*.md` 共 73 份；含日期数字却不带 `YYYY-MM-DD-` 前缀的仅 1 份 `improvement-plan-20261010.md`，
命中 J15 明文豁免族（`improvement-plan-YYYYMMDD.md` / `improvement-proposals-YYYYMMDD.md`）。⇒ **无违例**。

## 3. 差异判定

### 3.1 规范性表面残留旧路径（本轮已改，最小改动）

两份文档集的「新增文件分流规则」表仍把在流计划指向**已废弃**的 `docs/plans/`，
而该路径正是 T0r28（2026-11-24）收编后声明「不再新增」的旧位：

| 文件 | 改前 | 改后 |
|---|---|---|
| `docs/README.md:111` | 「新计划 / 提案（在流） \| `docs/plans/`（`YYYY-MM-DD-<topic>-proposal.md`）」 | 「… \| `fist-mbt/plan/draft/`（`YYYY-MM-DD-<slug>.md`；定案执行中→`active/`，终态→`done/`；旧路径 `docs/plans/` 不再新增）」 |
| `docs/DOCS-STRUCTURE.md:67` | 「… \| `docs/plans/`（`YYYY-MM-DD-<topic>-proposal.md`，头部字段见 `docs/plans/README.md`）」 | 同上口径，并把头部字段指引改指**真实存在**的 `fist-mbt/plan/README.md` |

> 为什么必须改：`AI-DEVELOPMENT-STANDARD.md:47` 的历史豁免只覆盖「按日期记录当时事实」的历史面
> （`CHANGELOG.md` / `memory/` / `reports/`）；**分流规则是"当前承诺"型表面**，留着旧路径等于教后人往废弃位放文件。
> 另一层：`docs/plans/README.md` 被多处引用但**文件不存在**（收编后未跟移），头部字段指引属**悬空引用**。

### 3.2 `fist-mbt/plan/README.md` 自述口径落后于规范（本轮已改）

原文写「文件名：`YYYY-MM-DD-<topic>-proposal.md`」＋「头部强制字段（缺一即红）」——
把**提案卡**的 `-proposal.md` 后缀当成全体计划文件的命名规范，与规范 `:45`（一律 `YYYY-MM-DD-<slug>.md`）冲突，
也与守卫实现 `cards_only=True`（P3/P5 只对 `*-proposal.md` 生效）冲突。已改为对齐表述并显式标注适用范围。

### 3.3 守卫未覆盖 `active/` 与 `done/`（判定面缺口，非文件违例）

守卫的 `FACES["plans"]["prefix"]` 只指向 `draft/`。规范要求三区统一命名，但**尺子只量了一区**。
现状两区实测全合规（§2.2），所以不产生现行违例；但这意味着**将来 `active/`/`done/` 出现命名漂移不会有人读**。
属于「红着没人读」的同族缺口（`check_tools_sync` 第 3 条不扫 `src/` 的形状），**不在本轮最小改动范围**内，列入 §5。

### 3.4 状态字段治理面：1 条真违例（非本轮引入）

`[P9] docs/proposals/2026-11-22-longrun-upgrade-proposal.md — 缺强制字段 status`。
该件为**未跟踪**（`??`），且 proposals 面的 `status` 闭集是英文词表（`draft/under-review/approved/…`），
与 plans 面的中文闭集不同——需按其自身提案流程补 `status`。**归属他方 WIP，本轮不动**（约束：只读盘点 + 最小改动）。

## 4. 冗余与清理判定

| 候选 | 判定 | 处置 |
|---|---|---|
| 根 `_mcp_tools.txt` | 已被删除（工作树 `D`） | **已完成**，本轮仅需确认无引用悬空——`git grep -n "_mcp_tools"` 全仓零命中 ✅ |
| `.fist-mbt/tmp/_mcp_tools.txt` | `.fist-mbt/` 整体被 ignore | 本地临时件，无需动 |
| `scripts/README.md.tmp` | 0 字节、12:29 落盘 | **他方进行中 WIP 的痕迹**（同批未跟踪新脚本多份），不删 |
| `docs/plans/archived/`、`docs/plans/decisions/` | 空目录、无跟踪件 | git 不跟踪空目录 ⇒ 无入库风险，留作旧路径残影（可选清，本轮不动） |
| `docs/plans/2026-11-25-longrun-baton-handover-contract.md` | 未跟踪，标题 `# T0r54 …` | **他方 T0r54 的产出**，落在 `SCATTER_SANCTIONED` 的 `docs/plans/` 内 ⇒ 散落判据不点名；但按规范 `:45`「区目录外不放计划文件」，它应进 `fist-mbt/plan/draft/`。**归属他方，本轮只登记不移动** |
| `memory/research/_snapshot.md` | 历史快照，`memory/` 历史豁免面 | 按 `:47` 不追改 |

> 说明：`cleanup_artifacts.py --help` 在本机直接执行了清理动作（无 `--dry-run` 面，属工具自身设计），
> 其影响面限于 `temp/` 与被 ignore 的运行态库；**未触碰任何跟踪件**。后续调用它应显式带 `--check`。

## 5. 遗留风险与后续建议

1. **`active/`/`done/` 无守卫**（§3.3）：建议给 `check_plan_location.py` 加一面对（三区的命名 + 终态位置），
   或至少把 `NAME_RX` 复用到另两区做只读扫描。属独立小任务。
2. **运行态账本漂移**：`.Fist-Mbt/data/autoplan-plans.json` 的 P3 条目 `file` 仍为 `docs/plans/2026-11-22-chatgroup-gui.md`
   （该路径在工作树不存在，真件已在 `fist-mbt/plan/draft/`）。账本由 `autoplan.py drop/finalize` 维护，
   重跑 `drop`/`finalize` 可自然纠正；本轮未改（运行态数据，非仓库资产）。
3. **`docs/plans/README.md` 悬空引用**：收编后 ≥5 处文档仍引它（`fist-mbt/plan/draft/*` 内多份、`scripts/check_publish_payload.py`）。
   最短修法是**在旧位补一份指回新位的薄 README**（保留历史链接可达），或逐条改指 `fist-mbt/plan/README.md`。
   属独立收口项。
4. **命名族混用**：`draft/` 里 5 份早期件用 `-proposal.md`/`-owner-decision.md`/`-verdict.md` 后缀。
   按守卫口径它们**作为提案卡**受 P3/P5 管（`cards_only` 只看后缀），现状均合规；
   但规范 `:45` 的 slug 口径并不要求去后缀，**不改**。
5. **他方 WIP 密集**：`autoplan.db-wal` 4.1MB（13:25 活跃）、`active/` 两份未跟踪、`docs/plans/` 一份 T0r54 契约。
   本轮所有改动均逐文件确认归属，未动他方件。

## 6. 来源

- 判据实跑：`python scripts/check_plan_location.py`（rc=1，P9 一条）、`--selftest`（58/58）、
  `python scripts/check_underscore_ignore.py`（rc=0）
- 真源：`AI-DEVELOPMENT-STANDARD.md:43-45`（计划文件规范）、`:47`（历史豁免边界）
- 台账：`.Fist-Mbt/data/autoplan.db` 表 `tasks`（T0r47，ns=autoplan，created_by=human_steward）、
  `.Fist-Mbt/data/autoplan-plans.json`（P3 漂移读数）
- 命令：`git ls-files` / `git status --short --untracked-files=all` / `git grep -n "docs/plans/"`

## 7. 交付物路径（本轮改动清单）

| 类型 | 路径 |
|---|---|
| 新增（本报告） | `fist-mbt/plan/done/2026-11-25-tnr-standard-alignment-report.md` |
| 修改 | `docs/README.md`（计划落位行） |
| 修改 | `docs/DOCS-STRUCTURE.md`（计划落位行） |
| 修改 | `fist-mbt/plan/README.md`（文件规范段口径对齐） |
