# R134 · 立 `check_unit_number_unique.py` 轮次号唯一性守卫（副机自立项）

## 结果摘要

- **缺陷**：`reports/` 是轮次号的落地交付面，但编号没有认领面——各支只读开工时刻的远端快照，谁先推谁占号。叠主线后的基点 `92d0edba` 现读 **47 份规范命名报告 / 42 个编号**，其中 **R110 / R113 / R118 / R121 / R126 五组编号各被两个不同单元复用**（读标题确认互不相干），全部静默进仓；同日副机自己实测四次撞号（R122→R123→R125→R128→R133）。第五组 R126（`mcp-server-moon-env` / `slave-task-list-selfproof-ruler`）是叠主线后本尺当场抓到的真源新撞号，已同批收紧进基线。
- **判据**（新尺 `scripts/check_unit_number_unique.py`，265 行）：
  - **U1 撞号**：同一编号被两个不同 slug 复用 ⇒ 红；同 slug 多份报告=同一单元追记，不算撞号。
  - **U2 基线对表**：历史撞号登记在 `docs/tasks/unit-number-baseline.txt`，实际 slug 集合必须与基线**逐字相等**——新增 slug ⇒ 红（新单元撞老号），少 slug ⇒ 红（基线过期，棘轮只许收紧）。
  - **U3 悬空认领**：基线点名而 `reports/` 对不上的编号 ⇒ 红。
  - 退出码 0/1/2/4：空宇宙、零解析、基线缺失/语法坏/重复认领一律走 2 号档自拒；未捕获异常走 4，不冒用 1。
- **现读**：叠线后基点 `92d0edba` 读 `编号 42 个 / 报告 47 份`；本单报告落盘后交单态 `UNITNUM=clean 编号 43 个 / 报告 48 份；撞号基线 5 组逐组对表一致`，rc=0。`--selftest` **11 格全过**（S1–S11，清单从已执行格子反解）。
- **登记**：`scripts/run_guards.py` 两格（裸跑 + `--selftest`）；README 锚点 `rulers=90 ci=42 battery=52 missing=0 gate=60 exempt=27 unclassified=5`（由 `check_battery_count_doc.py` 漂移输出反解，不手算）；`scripts/README.md` 追加条目。
- **范围与诚实边界**：只认 `<日期>-<slug>-r<编号>-report.md` 规范形；`…-r94-<说明>-…` 与 `…-award-enhancement-r110-gate-reconfirm-report.md` 两族历史命名不入面（判错单元身份的代价比漏判大，扩面前先做命名迁移）。远端分支名与在飞状态离网判不了，在飞两支同取一号的残余缺口如实留在「遗留风险」。
- **自踩并已修**：S6 首稿用了不匹配规范形的第二份样本 ⇒ 它根本没进宇宙，是「同单元追记不误红」的幻影格；已改成两份规范命名的同 slug 报告，重跑 11 格全过。

## 资源消耗

- 1 个副机 agent（无子代理派发）；工具调用以文件读写 + 守卫复跑为主。
- 全量电池（推后首读，日志仓外 `~/r134_battery_post.log`）：格数 70（手写 70 + 自动 0）/ 失败 1 / SKIP 5 / 缺执行面 0，rc=1。
  - `check_slave_task_list.py` got=1：**本单插入 6 行把清单里 WT-04 的 `run_guards.py:469` 锚点挤到 475**，主线新并入的认领入口尺当场抓到 B3/B4/D1 三条（正是它自己文档里写过的「锚点位移」形状）。已按该尺纪律把锚点改回真行号 `:475`（内容未变），复跑 `PASS 认领入口自证通过` rc=0。
  - SKIP 5 格全是缺前置临时件（`temp/pt27.log` ×2、`temp/chk47.json` ×3），不计失败也不构成通过证据。
  - 本单早前一发（叠线前）`whisperer.py --selftest` 曾卡满 600s：其 G1 调 `fist-gate.py --scan`，后者的 `git fetch --all --prune` **无超时上限**；本发网络未卡故通过。根因留给后续建议第 4 条。
- 无 `.mbt` 改动 ⇒ 未跑 `moon build/test`；未产生 `.mbti` 刷脏。
- 未新增依赖、未触网写操作（仅 `git fetch`/`ls-remote` 只读）。

## 任务分配记录

- 本单为副机自立项：FIST 任务库 `F:/AI/Fist-Mbt/fist-mbt.db` 只读打开后，内容为另一项目的 p5c 任务（1 已完成 / 51 已归档），**无待领取的主机任务**；主仓 `gitcode/master` 亦无为本缺陷预置的任务。
- 分支：`slave/feat/unit-number-unique-r134`，基点 `gitcode/master` = `92d0edba`（开工时 `dcefdeb8`，交单窗口内主线前进后已叠线重验）；开工与交付前各验一次 R134 号三面（远端分支 / `reports/` / 文本面）。
- 撞号让号过程（R122→R123→R125→R128→R133）见 `memory/2026-10-22.md` 的 R133 段；本单据此把「选号」做成常驻判据而不是再靠人工对表。

## 遗留风险

1. **在飞撞号判不了**：本尺只看 `reports/` 落地面，两支同时在飞、各自先取同一号时，只有先推的那支落仓后才会被判红。它是「事后棘轮」不是「取号锁」。要前置只能接远端分支面（需网络与在飞状态），本轮不做离线假绿。
2. **两族历史命名不在面**：`…-r94-<说明>-report.md` / `…-award-enhancement-r110-gate-reconfirm-report.md` 这类「编号后还有说明段」的文件若参与判号会把同一单元拆成不同身份，故排除；它们之间的撞号目前无人认领。
3. **基线是人工棘轮**：新历史撞号必须在同一笔里收紧基线，否则 U1 会红；基线被放宽不会被本尺阻止（棘轮只验「与 baseline 逐字相等」，放不放宽是人的决定）——这一层的护栏是 code review 与本报告的登记纪律。
4. **预存红（非本单引入，按口径点名不代修）**：
   - `check_scripts_naming.py` rc=1：N1 无角色名 22 份 > 上限 16、N2 连字符名 5 份 > 上限 4（词法棘轮，见 `scripts/NAMING.md`），电池按 `expected=1` 登记。
   - `check_ci_step_position.py` rc=1：位置违规 35 > 棘轮上限 34；其 `--selftest` rc=2。
   - `fist-gate.py` rc=2：fmt 段依赖 `git diff` 管道，本机工具链退化 ⇒ 按设计 DEGRADED。
5. **R133 在分支面双占**：远端同时存在 `slave/fix/memory-log-dup-r133`（副机）与 `slave/fix/memory-log-dedupe-r133`（另一支），正是「编号无认领面」的活样本；本单不处理，如实点名。

## 后续建议

1. **命名迁移**：把两族带说明段的历史报告改成规范形（或在文件名里保留说明但把编号紧贴 `-report.md`），迁移完成后把 `NAME_RE` 收紧为全量面。
2. **取号前置**：下一单开工时把「三面查号」写进任务包模板（远端分支 / `reports/` / 文本面 grep），推送前再查一次；可与 `fist-gate.py --scan` 的远端读数合并成一格。
3. **基线纪律**：发现历史撞号时先改号而非加基线；只有确实要保留的历史双占才进基线，并在报告里写清两个 slug 各自的单元。
4. **下一单候选（本轮实测）**：给 `fist-gate.py --scan` 的 `git fetch --all --prune` 加超时并降级为 DEGRADED（保留既有远端引用继续），治「电池格被一次慢 fetch 拖满 600s 判红」——本轮两台电池同格同超时已复现两次。
5. **R135+**：可考虑把本尺的 U1 判据扩展到 `docs/tasks/backlog/*.yaml` 的 `unit:`/`round:` 字段（若将来引入），让「号」在任务池面也有唯一性。

## 超额内容

- 同批修掉自家 S6 幻影格（不匹配规范形的样本本就不在宇宙里），并留证：修前 `PASS S6` 与修后 `PASS S6` 的差别是「第二份样本是否真的进面」。
- **尺子第一发命中真源**：叠主线后 `check_selftest_inventory_doc.py` 当场报本尺 S9 红（`UNITNUM=violate 违例 1 条`），内容是主线新并入的 R126 双占——不是沙箱合成违例，是真源里刚发生的新撞号；按棘轮纪律同批收紧进基线后转绿。这把尺因此不只是「在夹具上绿」。
- 交单前用 `check_exit_code_contract.py` 自检新尺：判定面 0 条（新尺未产生假契约），`check_py_stdout_encoding.py --all` = 108/108 已带 stdout 闸（新尺在列）。
- 副机项目记忆新增「轮次号撞号」一条（取号/推送前查三面、R133 双占现状）。

## 来源

- 新尺：`scripts/check_unit_number_unique.py`（11 格自检，S9 为真源活格）。
- 基线：`docs/tasks/unit-number-baseline.txt`（5 组，17 行含头注释）。
- 登记：`scripts/run_guards.py`（两格）、`scripts/README.md`（锚点 + 2026-10-23 条目）。
- 锚点修复：`docs/2026-10-20-slave-tasks.md` 的 WT-04 证据行 `scripts/run_guards.py:469` → `:475`（本单插入 6 行所致，内容逐字未改）。
- 当日日志：`memory/2026-10-23.md`（R134 段）。
- 电池日志：`~/r134_battery.log`（仓外；含逐格判定列与末行 `rc=`）。
- 交单基点：`gitcode/master` = `92d0edba`；分支 `slave/feat/unit-number-unique-r134`。
- 口径依据：BUG-369 退出码契约；BUG-58/138 stdout 编码闸；BUG-104 自述面反解；R106 电池只读与预存红登记律。
