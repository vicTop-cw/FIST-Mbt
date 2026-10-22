# 交付报告 · 副机认领入口自证尺（R126）

- 分支：`slave/feat/check-slave-task-list-r126`
- 基线：`gitcode/main dcefdeb8`（合入时现读，未落后）
- 交付 tip：`72c6606d`（本报告与当日日志为随后的 docs 追记）
- 交付面：`git diff --name-only gitcode/main..HEAD` = 5 份文件（`scripts/check_slave_task_list.py` 新增，其余 4 份为接线与文档）

## 结果摘要

把 `docs/2026-10-20-slave-tasks.md`（副机线的认领入口）从「手抄自证」升级为**常驻尺**：

1. 新增 `scripts/check_slave_task_list.py`：逐行解析清单表格，核对每条「现读证据」是否指得到**在场真源**（文件在 git 跟踪面、行号不越界、那一行确实含所声称的记号），并核对文首三组自述数字（结构级 / 内容级 / 失配）与尺实算逐键一致。记号**从文档自己的括号里取**（紧跟锚点的反引号串或「…」逐字引文），尺内不写记号表。退出码 0/1/2/4，`--selftest` 十八格（A×3 / B×5 / C×4 / D×4 / E×2）。
2. 四件接线齐（同一单内）：电池两格（`scripts/run_guards.py:148`/`:149`）、`scripts/README.md:805` 条目、README `BATTERY-REGISTRATION` 锚点读数（现读 rulers=89 ci=42 battery=51 missing=0 gate=59 exempt=27 unclassified=5）、`.github/workflows/ci.yml:87` 步骤（`--selftest` 再裸跑，住在 Migrate 之前并带 `position-why`）。
3. 现读判定面：任务行 28 / 证据锚点 57（内容级 28）/ 文件级在场 14；状态分布 已落地 8 / 部分 8 / 未开工 9 / 作废 3 / 无法取证 0。尺绿（rc=0），自检绿（18 格）。

**这单最硬的读数来自别人**：接线完成后 `check_exit_code_contract.py` 当场判我这条新尺红——R1 模块面幻影「承诺 rc=2 但 ast 出口面给不出，实现面=[0,1,4]」，成因是 `run()` 用 `return 2, 文本` 的元组返回，它的实现面只认非元组出口（BUG-369 抓过的同一形状）。`72c6606d` 把码与文本分家（读数 append 进 `sink`、裸返回 2/1/0），两尺同绿。**新尺自己先被系统抓了一次假契约，才轮到它去抓别人。**

## 证据

| 面 | 读数 | 取自 |
|---|---|---|
| 尺裸跑 | rc=0；28 行 / 57 锚点（内容级 28）/ 文件级 14；8/8/9/3/0 | `python scripts/check_slave_task_list.py` |
| 尺自检 | rc=0；`SELFTEST OK（18 格：A×3 / B×5 / C×4 / D×4 / E×2）` | 同上 `--selftest` |
| 退出码契约尺 | 判定面 **0** 条（修前 1 条，点名本尺） | `python scripts/check_exit_code_contract.py` |
| 全量电池（推后） | **68 格 / 失败 0 / SKIP 5 / 缺执行面 0**，rc=0 | `fist_r126_battery3_postpush.log`（仓外） |
| 登记联动 | `check_battery_count_doc.py` rc=0（rulers=89 …） | 电池第 62 格 |
| `moon check --target js` | Finished，**0 errors** / 506 warnings | `fist_r126_mooncheck.log` |
| `moon test --target js` | `Total tests: 1387, passed: 1387, failed: 0` | `fist_r126_moontest.log` |
| whisperer `--fast` | rc=0；文本报「本地 HEAD 与远端 main 不一致（篡改）」——**feature 分支上的已知假阳性**，未执行它给的 `git reset --hard` | `fist_r126_whisper2.log` |

本单最贵的一条证据是**锚点会自己烂**：往 `ci.yml` 前段插 8 行、往 `run_guards.py` 电池表插 5 行，清单里 11 个 `file:line` 锚点整体挪位——其中带记号的 5 条当场判红，另外 6 条只因仍落在合法行号内就**悄悄错位**（指到了别的行）。叠 `gitcode/main dcefdeb8` 后再挪 8 个锚点（7 个 B3 + 1 个 B4 空行），内容级自述 24→28。这条已经写进清单自身的纪律段：**指进易腐文件的锚点必须带记号**。

## 资源消耗

- 会话轮次：本单 3 个提交（`cbc7b558` 尺+接线 / `519df414` 叠线 / `72c6606d` 退出码修真）+ 本追记；约 12 次电池/守卫全量运行、2 次 `moon check`、2 次 `moon test`、2 次 whisperer、1 次 `git archive` 快照对照。
- 仓外日志 7 份（`fist_r126_*.log` / `r126_*`），未进跟踪面。
- 无新增依赖；尺纯标准库（`ast` 都不用，只 `re`/`subprocess`/`io`）。

## 任务分配记录（金条四）

- 本单由主线 agent 直接执行（单文件新尺 + 四件接线，属「中任务」但边界完全自持：只动 5 份文件），未拆分。
- 边界：只动 `scripts/check_slave_task_list.py`、`scripts/run_guards.py`、`scripts/README.md`、`.github/workflows/ci.yml`、`docs/2026-10-20-slave-tasks.md`；未改任何 `.mbt`、未动 `memory/bugs.md`、未碰别人分支。
- 子代理使用：0（无并行读取需求，证据全部来自现读命令）。

## 遗留风险

1. **SKIP 5 格藏红**（继承 R122）：`check_badge` / `check_test_sync` / `check_deprecated_text_census` ×2 / `check_deprecated_site_list` 因缺 `temp/pt27.log`、`temp/chk47.json` 前置而不计失败——「没跑」不等于「过了」。
2. **退出码契约尺的元组盲区仍在**：`return 2, 文本` 形状在它的实现面上是隐形的。本单只修了自己这一处；其他尺若用同形返回，承诺 rc=2 会被读成幻影（或反过来漏判）。属该尺判据面的已知边界，非本单范围。
3. **预存红 2 处（不代修，按登记口径）**：`check_ci_step_position.py` rc=1（判定面 35 > 棘轮 34，升档属 owner 裁决；本尺住在 Migrate 之前故不新增违例）；`check_scripts_naming.py` rc=1（判定面 2 > 棘轮上限，主线刻意降级的 `_` 临时件所致）。
4. **whisperer 假阳性**：feature 分支上 `--fast` 恒报「篡改」，处方 `git reset --hard` 会毁掉本单工作。只当读数、不当裁决（已在当日日志二次点名）。
5. **README 登记数字仍在手抄边缘**：新尺入库必须同批改 `BATTERY-REGISTRATION` 的七个键，`check_battery_count_doc.py` 会红——这单已对表，但下一单加尺仍要重复一次。
6. **仓库外分支**：远端尚有 `slave/fix/router-iso-calendar-r130`、`slave/fix/server-ts-shape-r131` 未进 main；本单基线 `dcefdeb8` 现读仍为 main tip，交付后若主线前进需再叠。

## 建议入档位置

- 报告：本文件（`reports/2026-10-22-slave-task-list-selfproof-ruler-r126-report.md`）。
- 当日日志：`memory/2026-10-22.md` 的 R126 小节（含「锚点会自己烂」「新尺先被抓假契约」两条教训）。
- 清单自身的纪律段：`docs/2026-10-20-slave-tasks.md` §1（已写）。
- 不新增账本条目：本单是既有缺口的收口（J10 声明滞后的副机形状），不构成新 BUG。

## 超额内容（本单边界外，未动）

- 未修 `check_exit_code_contract.py` 对元组返回的识别（属它的判据面扩张，影响面跨全仓尺子，应单独立项）。
- 未清 SKIP 前置文件；未动 `check_ci_step_position` 棘轮上限；未修 `check_scripts_naming` 存量。
- 未替 R130/R131 分支做任何合并或判读。

## 来源

- 真源：`scripts/check_slave_task_list.py`、`scripts/run_guards.py`、`scripts/README.md`、`.github/workflows/ci.yml`、`docs/2026-10-20-slave-tasks.md`（均在 `72c6606d` 的树里）。
- 读数日志（仓外）：`C:\Users\Administrator\fist_r126_battery3_postpush.log`、`fist_r126_ecc2.txt`、`fist_r126_self.txt`、`fist_r126_self_st.txt`、`fist_r126_mooncheck.log`、`fist_r126_moontest.log`、`fist_r126_whisper2.log`。
- 对照实验：`git archive dcefdeb8` 快照内同一条退出码契约尺 rc=0，证明修前的红来自本单新尺而非主线。
- MR（只交链接，不代开）：`https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/feat/check-slave-task-list-r126`
