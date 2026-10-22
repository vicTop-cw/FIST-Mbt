# 交付报告 · backlog 控制字符清理 + 完整性尺 R4（R120）

- 日期：2026-10-22
- 分支：`slave/fix/backlog-control-char-r120`
- 提交：`HEAD`（TASK-023 字节修复 + 完整性尺 R4/C10/C11 + README 条目）+ 本报告所在提交
- 基点说明：本支基于 R119 顶点 `9c03782e`。交付时 `gitcode/master` 已前进到 `7b1dba95`（R118 `3049905f`、R119 `7b1dba95` 均已并线）⇒ 本支相对主线只有 1 笔主体提交（`af021d63`）+ 1 笔报告基线修订。本单与 R119 的文件重叠只有 `memory/2026-10-22.md`（追加）与 R119 报告（修回一个 0x08，见「超额内容」）。
- 性质：副机自立项（R119 报告「后续建议」第一条）

## 结果摘要

1. **TASK-023 两处控制字符修回**：`docs/tasks/backlog/TASK-023-…yaml` 里 0x08（退格）共 2 个，都在 `^## BUG-(327|333|336|384|385)\b` 正则内；原意是字面 `\b`，被写成退格后 grep/正则照跑但永远命不中。改为字面 `\b`（总字节 2773→2775，CRLF 19 不变）。
2. **完整性尺加 R4**：`check_backlog_yaml_integrity.py` 新增「正文不得含 C0 控制字符（`\x00`-`\x08` / `\x0b` / `\x0c` / `\x0e`-`\x1f`）」；制表符与 CR/LF 是合法排版空白，不进判据面。违例逐文件点名「N 个控制字符 + 首个 0xNN 在第 L 行」，rc=1。
3. **自检扩到 11 格**：C10 控制字符必红 / C11 制表与换行不误红；清单仍从已执行格子反解。
4. **README 条目同批更新**：三条判据→四条判据、九格→十一格（含 C10/C11 说明）。
5. **顺手修回同类事故**：R119 报告与 `memory/2026-10-22.md` 各 1 个 0x08（写 `\b` 时被转义吃成退格），本单取证时现形并修回。
6. **现状面**：backlog 23 份，R4 读数 0 违例；R1/R2/R3 读数不变。

## 证据

| 项 | 读数 |
|---|---|
| TASK-023 | 0x08 2→0；字面 `\b` 2 处；CRLF 19→19；`git diff --numstat` 2+/2- |
| 尺 `--selftest` | rc=0；11 格：C1 干净不误红 / C2 整块重复必红 / C3 半截重复也必红 / C4 抬头缺键必红 / C5 缩进与列表行不误判 / C6 诊断不计失败 / C7 空面必自拒 / C8 目录不存在必自拒 / C9 真面变异必红 / C10 控制字符必红 / C11 制表与换行不误红 |
| 尺裸跑 | `扫描面=docs/tasks/backlog`，台账 23 份 / 违例 0 条 / 诊断 0 条，rc=0 |
| 对表尺 | `check_selftest_inventory_doc.py` → `INVENTORY_SYNC=clean 判定族 25 条逐一对表通过` rc=0（本尺条目无族清单，不入判定面） |
| 电池规模 | `check_battery_count_doc.py` → `rulers=84 ci=40 battery=46 missing=0` rc=0 |
| 全量电池（提交前基线） | **59 格 / 失败 0 / SKIP 5 / 缺执行面 0** rc=0（提交后推送前 `check_delivery_gap` 会按设计红一格，推送后复跑归零） |
| 交付态电池（`af021d63` 推送后） | **59 格 / 失败 0 / SKIP 5 / 缺执行面 0** rc=0 |
| 主线基线 | `gitcode/master` = `7b1dba95`；`git rev-list --count gitcode/master..HEAD` = 1（主体提交时） |
| 控制字符普查 | memory/reports/docs/scripts/.github 的文本面修前 11 份带 C0；本单修 2 份后余 9 份（历史件，见遗留风险） |

## 资源消耗

- 分支 1 条（基于 R119 顶点），提交 2 笔：`af021d63`（代码/台账/文档 + 报告/日志）+ 报告基线修订。
- 无 `.mbt` 改动，未跑 `moon`。
- 全量电池 2 发（提交前基线 + 推送后收尾）。

## 任务分配记录

- 线索：R119 报告「后续建议」——TASK-023 控制字符清理 + 完整性尺加控制字符判据。
- 单 agent：字节级取证 → 修字节（CRLF 保持）→ 尺加判据与两格自检 → README 同批 → 电池。
- 中途发现 R119 自身制品也带 0x08，判断为同一事故类别，纳入本单修回并记账。

## 遗留风险

1. **仓内仍有 9 份历史文本带 C0 控制字符**（3 份 `memory/`、5 份 `reports/`、1 份 `scripts/check_release_asset_names.py` 的 0x0c）。它们不属本单范围：历史报告/日志是证据面，改字节要 owner 裁定；`check_release_asset_names.py` 那处是脚本内字符串，改它要连带跑其 38 格自检。建议单独立「文本面控制字符普查/修复」单元。
2. **R4 只覆盖 backlog YAML**：本单把判据放在台账尺上，因为那是同类损坏实际发生的消费面；memory/reports/docs 面目前无守卫。
3. **基线已并线**：R118/R119 已进主线（`7b1dba95`），本支相对主线只剩自己的提交；本支修改了 R119 报告一个字节，该修订随本支入线（R119 已合并，无 MR 重叠问题）。
4. **R4 的边界**：允许制表符与 CR/LF，其余 C0 一律红；若未来台账正文需要 `\f` 等字符，需要显式裁决（当前 23 份无此需求）。

## 后续建议

- 立「文本面控制字符普查」单：先只读普查（memory/reports/docs + 脚本），再按文件归属分批修；配套一把能扫全仓文本面的守卫（例如 `check_text_control_chars.py`），避免同类事故只能靠人眼。
- 本单修复 R119 制品的事实说明：**写含反斜杠转义的文本后必须回扫控制字符**，建议以后报告/日志落盘后跑一次字节扫描（或纳入落盘流程）。
- TASK-023 已 `done`，本单不改其状态；若 owner 要求把修复记入台账，可在其 `status_note` 追加一句。

## 超额内容

- 修回 R119 报告与当日日志各 1 个 0x08（原不在本单范围，属同类事故取证现形）。
- 控制字符普查（11 份命中）只登记、未扩大改动。

## 来源

- `docs/tasks/backlog/TASK-023-cef1e9c-j1-17-1-327-333-336-384-385-bug-.yaml`
- `scripts/check_backlog_yaml_integrity.py`（R110 尺，本单加 R4）
- `scripts/README.md`（条目 + `--selftest` 十一格）
- `reports/2026-10-22-backlog-reconcile-r119-report.md`（后续建议与同类损坏取证）
- `memory/2026-10-22.md`（R119 记录）
- 实测命令：`python scripts/check_backlog_yaml_integrity.py --selftest` / `python scripts/check_backlog_yaml_integrity.py` / `python scripts/check_selftest_inventory_doc.py` / `python scripts/run_guards.py`
- 仓外日志：`C:/Users/Administrator/AppData/Local/Temp/r120_battery_pre.log`
