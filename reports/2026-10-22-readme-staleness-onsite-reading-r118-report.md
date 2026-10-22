# R118 · `check_backlog_status_staleness` 的 README 盘上读数结清 — 报告

日期：2026-10-22 · 单元号：R118 · 分支：`slave/docs/readme-staleness-onsite-reading-r118`
基点：`gitcode/master` = `b5136899`（现读 `git rev-list --left-right --count` = `0 / 0`，即本支尚未有提交、基点就是主线 tip）
立项来源：副机自立项（原为 R114「期望兑现」单，被主线吃掉一半后缩成这一面）

## 结果摘要

`scripts/README.md` 里 `check_backlog_status_staleness.py` 条目写着**盘上三档各有实测读数**，其中两档已经是假账：

- `within 落差 4 / 上限 4 / 超限 0` rc=0 —— 现读是 **`落差 0 / 上限 0 / 超限 0`**（`STALE_CEILING` 已由 R111 降到 0，
  存量 9 条落差已逐条核对盖章）；
- 「把上限改成 3 的变异件 rc=1（超 1 条）」—— 存量清零后盘上不可能再出现超限，这一档**不可复现**。

改法：把这句换成盘上实测**两档** + 一句「红档改由 `--selftest` 里点名超限的合成违例格钉住」。
**只改文字，不动判据**：`STALE_CEILING = 0` 一个字没碰（那是防「为了让电池变绿而放宽」的闸）。

为什么这一面还值得单独一单：R111 的报告第 27 行**预告**过这条 README 同步（`4/4/0 → 0/0/0`），但那一单没落地；
R117 兑现电池期望时也没带上它（现读主线仍是 `4/4/0`）⇒ 一句假账连续活了三轮。
教训写进日志：**清完内容债的那一单要同批把盘上读数改掉，跨单交接必落后**。

## 本单的来龙去脉（如实记账，不装作一开始就这么设计）

- 我最初按 R113 遗留风险第 5 条开了 `slave/fix/battery-expectation-staleness-r114`，做完 `run_guards.py` 的期望兑现 + 这条 README 同步。
- 交单前 `git fetch` 对表：`gitcode/master` 已前进 **22 个提交**，而我的 R113 三个提交已全部是主线祖先；
  `git rev-list --left-right --count gitcode/master...HEAD` = **22 / 0**。
- 主线里 `scripts/run_guards.py:226` 已是 `case("check_backlog_status_staleness.py")`，出自 `47555d8a`
  （副机并行 agent 的 **R117**「兑现 backlog 状态落差的过期预存红期望」）。⇒ 我那半**已被吃掉**，
  再推只会造出同一格的第三份注释抄本与无意义冲突。
- 正确动作（本仓第 19 条坑）：**从最新主线重开 lean 支**，只带 `git cherry` 意义上真正未落的那一面（README 读数），
  并丢掉已在主线的那一面。故单元号从 R114 改为 R118，`run_guards.py` 的草稿不搬。

## 证据（全部本基点现读）

| 量具 | 命令 | 读数 |
|---|---|---|
| 主尺现状 | `python scripts/check_backlog_status_staleness.py` | `扫描面=gitcode/main \| backlog 23 份 \| 主线点名到的 TASK id 16 个 \| 落差 0 条 / 上限 0 条 / 超限 0 条`，`BACKLOG_STALENESS=within`，**rc=0** |
| 主尺自检 | `python scripts/check_backlog_status_staleness.py --selftest` | `SELFTEST OK: 11 格（反解：M×2 / P×2 / R×4 / V×3）`，rc=0 ⇒ README 那句「11 格」自述照旧成立，未动 |
| 格数自述对表 | `python scripts/check_selftest_inventory_doc.py` | 对该尺「判定族 4 / 实现反解族 4 / 对表合计 11 格」通过；本单未改格数面（其 rc=2 见下节，与本行无关） |
| 文档面 | `python scripts/check_doc_surface.py` / `python scripts/check_scripts_index.py` | **rc=0 / rc=0** |
| 全量电池（改前，基点现状） | `python scripts/run_guards.py --case-timeout 180` | **58 格 / 失败 2 / SKIP 5 / 缺执行面 1**，rc=1 —— 两格失败均为**预存红**，见下节 |

改后权威读数（推分支之后重跑）见下方「推后权威读数」段。

## 预存红（本单不代修，按口径点名 rc 与成因）

基点 `gitcode/master` 上电池就红两格，两条同因，**与本单 1 行文档改动无因果**：

1. `FAIL check_battery_count_doc.py  got=2 expect=0` :: `FATAL: run_guards --list rc=1：缺面清单：audit_branch_delete.py`
   —— 主线已收录 `scripts/audit_branch_delete.py`（README 第 119 行有条目），但它**既不在电池格、也不在 CI 面、也没有常驻豁免锚点**
   ⇒ `run_guards.py --list` 现读 rc=1（缺执行面 1）⇒ 普查尺拿不到读数，按「判据无法自证不许报绿」走 2 号档。
2. `FAIL check_selftest_inventory_doc.py  got=2 expect=0` :: `X4 ... check_battery_count_doc.py 文档有 3 条族计数自述，实现清单拿不到：--selftest 实回 rc=1`
   —— 纯级联：那把尺的 `--selftest` 里有一格「真 README + 真 `--list` 现状面必须绿」，被第 1 条打红，于是清单无从对表。

归属证据：`for r in refs/remotes/gitcode/*; do git show "$r:scripts/run_guards.py" | grep -c audit_branch_delete; done` 全部为 0
⇒ **没有任何在途分支处理这一面**，所以它不是"别人正在修"，是"没人接"。已另开 R119 立项（见「后续建议」），
按一单一面纪律**不混进本单**——本单只动 `scripts/README.md` 一行。

SKIP 5 格照本仓律**不构成通过证据**（`temp/pt27.log` 两格、`temp/chk47.json` 三格缺进料前置）。

## 推后权威读数（交付态，本单以此为准）

提交 `f285459a` 推送后（远端钩子 `Git Hooks Checking [PASSED]`）重跑同一条命令：
`python scripts/run_guards.py --case-timeout 180`（`FIST_DB_PATH` 指仓外 Temp，日志写 `~/r118_battery_postpush.log`）
⇒ **58 格 / 失败 2 / SKIP 5 / 缺执行面 1**，rc=1（与基点逐格同形，本单未增未减）。

- `rc=0 exp=0 check_delivery_gap.py OK 汇总：3 个分支，其中 0 个存在未推送提交` —— 交付态自翻为绿，
  印证「这种格不登记期望、不豁免、不降棘轮，只把门禁顺序改成 commit→push→复跑」这条纪律。
- `rc=0 exp=0 check_backlog_status_staleness.py OK BACKLOG_STALENESS=within 落差 0 条 <= 上限 0`
  —— 本单结清的正是这句话在 README 里的旧抄本（`4/4/0`）。
- 失败两格 = 上一条点名的两条预存红（`audit_branch_delete.py` 缺执行面 + 其级联），成因与本单无关，已立项 R119。
- `blackbox/check_merge_markers.py` 跟踪面 1335 个文件 **0 未解决标记**（本单文字里不含标记形状，故不触它）。

## 任务分配记录

- 轻任务（单文件 1 行文档 + 报告 + 日志）→ 副机指挥官直接做，未派子代理、未进 FIST 任务库。
- 判据归属查过：`git log --oneline -S'现读 9 条状态落差 > 上限 4' -- scripts/run_guards.py` ⇒ `19830ccb`（R106，我自己那一单），
  所以 R114 那半属"结自己的账"；被 R117 抢先落地后，本单只剩文档面，仍属同一笔账的尾款。

## 资源消耗

- 只碰 Python 判据面与文档面，未触发 `moon` 构建/测试 ⇒ `_build` 未变、无 `.mbti` 刷脏。
- 命令数：约 12 发（含 fetch、两次电池）。最长一发 = 全量电池 ~90 s（基点那次 rc=1）。
- 数据库：`FIST_DB_PATH` 指到仓外 Temp（`~/fist_r118.db`），仓库根未产生 `fist-mbt.db` 演示行；日志也写仓外（`~/r118_battery_pre.log`）。

## 遗留风险

1. **本单只结清"一句假账"，而"假账"这一形没有常驻判据**：`check_selftest_inventory_doc.py` 对表的是**格数自述**，
   `check_battery_count_doc.py` 对表的是**电池规模**，都没有"README 里那句盘上 rc 读数 ↔ 现读 rc"这一格。
   ⇒ 建议给电池加一条**盘上读数对表**判据（从 README 条目反解 `xxx rc=N` 断言并与实际跑一遍对表），
   否则下一次"内容债清完、文档读数没人改"照样复发。
2. 主线电池现红 2 格（上一条的预存红），CI 面若也跑这两把尺会是同红——不属本单。
3. `docs/tasks/backlog/` 的任务池 `status` 盖章权在 owner：现读「落差 0」只说明**已点名的**那些不再有落差，
   R3 OPEN 档（从未点名且仍 `backlog`）只报不判，本单没有改变它的判定强度。

## 后续建议

- **R119（已立项，未开工）**：把 `audit_branch_delete.py` 归入电池分类——它是**会删远端分支**的通道工具，
  裸跑格会真删东西，正确处置是「常驻豁免 + 锚点」或「只进 `--selftest` 格」，二选一都要写清理由；
  落地后 `check_battery_count_doc` / `check_selftest_inventory_doc` 两格自然归 0。
- 把上一条建议的「盘上读数对表」做成判据（本仓已有 `check_selftest_inventory_doc` 的先例：从文档反解、不手写清单）。

## 超额内容

无。改动面 = `scripts/README.md` 1 行（1 增 1 删）+ 本报告 + 当日日志一段。
`scripts/run_guards.py` 未改（那一半已在主线的 R117 里）。

## 来源

- 触发：本单元原形 R114（R113 报告遗留风险第 5 条）与 `git fetch` 后的 22/0 对表读数；
  主线吃掉证据 = `47555d8a`（R117）、`scripts/run_guards.py:226`（现读 `case(...)`）。
- 真源：`scripts/check_backlog_status_staleness.py:45`（`STALE_CEILING = 0`，本单未改）、
  `scripts/README.md` 该尺条目（原 `盘上三档` 句）。
- 历史同形：`reports/2026-10-22-backlog-status-reconcile-r111-report.md:27`（预告未落地的 README 同步）、
  `reports/2026-10-22-staleness-expectation-cashout-report.md`（R117 兑现电池期望，未带文档面）、
  R108 `check_dist_snapshot` 兑现、R76 `check_bug_reference_integrity` 兑现。
- 规范依据：`AI-DEVELOPMENT-STANDARD.md` 通用「一源四态 / 增量零回归」+ 本仓「上限不许为变绿而上调」「判据无法自证不许报绿」。
