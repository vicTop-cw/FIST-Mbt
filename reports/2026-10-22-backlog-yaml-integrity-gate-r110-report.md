# R110 报告 · backlog 台账键唯一性门（TASK-001 的常驻化）

## 结论 / 结果摘要

R109 手工把 `docs/tasks/backlog/TASK-001-conflict-markers-no-commit.yaml` 里那份**截断抄本**删掉了
（14 个顶层键各出现 2 次，第二份停在 `open_item`、没有 `result`/`acceptance_met`/`status_note`）。
手工去重不留机器面就会长回来，本单把「再有人抄一份」变成一把常驻尺：

- 新增判据 `scripts/check_backlog_yaml_integrity.py`（R1 顶层键唯一 / R2 抬头四键齐全 / R3 只诊断不判红）。
- 接入电池两格：`case("check_backlog_yaml_integrity.py")` + `case(..., "--selftest")`。
- 在 `scripts/README.md` 索引登记（否则 `check_scripts_index` 当场红）。

为什么不能「load 成 dict 再取 status」：这批 yaml 的 acceptance 用 `- [ ]` 复选框，
`yaml.safe_load` 在抬头就 `ParserError`（R109 实测 line 23 col 9），而本仓所有消费面
（`fist-gate.py`、`check_backlog_status_staleness.py`、主机派单脚本）都是**逐行正则反解**——
所以重复块不会有任何机器读数，只会让「取最后一次出现」的读法拿到没有验收结论的旧状态。

## 证据（全部实测读数）

| 命令 | rc | 关键行 |
|---|---|---|
| `python scripts/check_backlog_yaml_integrity.py` | 0 | `扫描面=docs/tasks/backlog \| 台账 23 份 \| 违例 0 条 \| 诊断 1 条（诊断不计失败）` + `PASS backlog 顶层键唯一且抬头齐全` |
| `python scripts/check_backlog_yaml_integrity.py --selftest` | 0 | `SELFTEST OK（格子从已执行格子反解：C1…C9）` |
| `python scripts/check_py_stdout_encoding.py --all` | 0 | 该带闸 100 份 / 已带 100 份 |
| `python scripts/check_exit_code_contract.py` | 0 | 退出码契约面通过 |
| `python scripts/check_scripts_index.py` | 0 | `PASS 工具类辅助代码单一索引完整` |
| `python scripts/check_selftest_inventory_doc.py` | 0 | `INVENTORY_SYNC=clean 判定族 22 条逐一对表通过` |
| `python scripts/check_doc_surface.py` | 0 | 170 工具可查、分组和=170、版本=0.3.10 |

`--selftest` 九格：C1 干净不误红 / C2 整块重复必红 / C3 半截重复也必红 / C4 抬头缺键必红 /
C5 缩进与列表行不误判 / C6 诊断不计失败 / C7 空面必自拒 / C8 目录不存在必自拒 /
**C9 真面变异必红**（复制真实 TASK-001 台账、尾部追加前 600 字符再断言 rc=1，`finally` 还原并断言字节相同）。
C9 是这把尺「能打红」的唯一自证——离线合成件容易写成恒绿。

## 预存红点名（按交付口径：不代修，只点名 rc 与成因）

提交前全量电池 `rc=1 / 格数 56（手写 56 + 自动 0）/ 失败 4 / SKIP 5 / 缺执行面 0`，四条失败逐格归位：

1. `check_publish_payload.py got=1` — 成因：本单新脚本当时还是未跟踪文件，`moon publish` 打包面 = 工作树 − .gitignore。
   **属本单引入、随 commit 自然消失**（提交后复跑）。
2. `check_py_stdout_encoding.py --all got=1` — 成因 E1：新脚本 print 中文却没带 BUG-58/138 的 stdout UTF-8 重配。
   **属本单引入、已在本单内修掉**（补 reconfigure 闸后 rc=0）。
3. `check_py_stdout_encoding.py --selftest got=2` — 成因 M6：该格的对照就是跑 `main(['--all'])` 读 PASS 行，
   与 2 同因；修掉 2 之后一起归 0（实测 rc=0）。
4. `check_dist_snapshot.py got=0 expect=1` — **不属本单**：主线 `866e2e65` 已把 dist 快照刷到与 `moon.mod` 同版，
   电池里那份 `expected(..., 1, 依据)` 因此按本仓律自己翻红。这一发的兑现已在**并行单 R108**
   （分支 `slave/gate/dist-snapshot-expectation-cashout-r108`，tip `c15c96dc`）里做过，本分支基点 `e07f479e`
   不含 R108，所以同一条线在此仍红。**不在这里重复改**：两处都改同一行会在合并时互斥，
   归位方式是 R108 与 R110 任一先进主线，另一支 rebase 后这一格自然消失。

SKIP 5 格都是 `temp/` 前置件缺失（`chk47.json` / `pt27.log`），按本仓律 SKIP 不构成「这格过了」的证据。
`check_scripts_naming.py` 的 2 条红（N1 无角色名 20 份 > 上限 16、N2 连字符名 5 份 > 上限 4）是已登记的预存红，
`--show` 名单里**没有** `check_backlog_yaml_integrity.py` ⇒ 本单未加一条。

## 缺口与风险

- 本尺只看顶层键唯一与抬头齐全，**不看 yaml 内容是否自相矛盾**（如 `priority: P0` 与 `status: backlog` 并存却已 `acceptance_met`）；
  那一面归 `check_backlog_status_staleness.py`（现登记预存红，上限 4 条，等 owner 盖章下降）。
- R3 只诊断不判红是有意的：状态章归 owner。若将来「未盖章却写了 acceptance_met」变成事故面，
  把 R3 升为违例即可，但那是裁决不是修尺。
- `fist-gate.py scan` 会自动生成 backlog yaml（R83），生成的新文件不会与既有块重叠，
  但**人工往同一文件追加整块**这条路径本尺现在是唯一挡得住的机器面。

## 后续建议

1. `expected(...)` 只按 rc 比对，不看成因 ⇒ 建议给期望格加一条「成因指纹」（读数首行关键字），
   否则「同码换因」（红数不变、红的内容变了）读起来是绿的。本仓已两次撞上这一形。
2. 主线合并顺序建议：R107（文案修尺）→ R108（兑现期望，电池全绿）→ R109（台账去重）→ R110（本单，常驻化）。
   R110 叠在 R109 tip 上，R109 进主线后本单就是「先修内容、再立门」的顺序。

## 来源

- 现场：`scripts/check_backlog_yaml_integrity.py`（新增）、`scripts/run_guards.py:208` 前接线、`scripts/README.md` 索引条目
- 上一单：`reports/2026-10-22-task001-yaml-duplicate-block-r109-report.md`
- 规范：`AI-DEVELOPMENT-STANDARD.md` §7 已知边界；`AGENTS.md` 金条四/五/八
- 读数：本文件「证据」表 + `temp/` 外重定向的电池日志（`FIST_DB_PATH` 指到仓外，不落仓库）

## 追记 · 叠主线后的权威读数（同一轮，交单前复核）

- 交单前复查主仓：`gitcode/master` 已从本分支基点 `e07f479e` 前进 13 个 commit，其中
  `c6eb84e6` 并了 **R108**、`4914a81f` + `15bb3b24` 两次并了 **R109** ⇒ 本分支叠主线（merge commit `21886d0e`）。
  唯一冲突是 `memory/2026-10-22.md` 的日志尾部追加（三方各加各的段），按本仓律**并集解决**：
  保留主线 R108 段 + 本线 R109/R110 段，断言无冲突标记、无裸 LF、三个小节标题各出现 1 次。
  `scripts/README.md` 与 `scripts/run_guards.py` 由 ort 自动合并（主线这一轮做了文档去重，`README` 索引条目未被吃掉：
  `grep -c check_backlog_yaml_integrity.py` = README 1 / run_guards 2）。
- **第 4 条预存红的归位**：叠主线后 `expected("check_dist_snapshot` 在本分支为 **0 处**——R108 的兑现随主线进来，
  本单不再需要在两处改同一行。上面「不属本单」那一格因此自然消失，这正是报告里写的归位方式，不是推测。
- 提交时读数（merge 前，`check_publish_payload` 与 stdout 两条已随本单修掉）：`rc=1 / 57 格 / 失败 1` =
  `check_delivery_gap.py got=1`——**交付态红**（HEAD 尚未推），律是「不给它登记期望」，推完自己翻绿。
- **推后权威读数**（tip `21886d0e` 已在 `gitcode/slave/gate/backlog-yaml-integrity-r110`）：
  `python scripts/run_guards.py` ⇒ **rc=0 / 格数 57（手写 57 + 自动 0）/ 失败 0 / SKIP 5 / 缺执行面 0**。
  SKIP 5 格全是 `temp/` 前置件缺失（`chk47.json` / `pt27.log`），按本仓律 SKIP 不构成「这格过了」的证据。
  本单两格 `check_backlog_yaml_integrity.py`（裸跑 + `--selftest`）在 57 格里各占一格，读数 rc=0。
- MR 只交链接不代开：https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/gate/backlog-yaml-integrity-r110
