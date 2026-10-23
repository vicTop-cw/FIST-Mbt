# R180 · README 环境要求前移 + 工具链地板钉 0.1.20261016 + 测试计数 1382→1387

**分支** `slave/docs/readme-env-bold-r127` · **主提交** `86209cca`（父 `dcefdeb8`）· **MR** <https://gitcode.com/VictorTop/Fist-Mbt/merge_requests/new?source_branch=slave/docs/readme-env-bold-r127>

## 一、结果摘要

POLISH-04 的三格验收全部落地，并把同族的两处旧地板一并钉死：

1. **位置**：环境要求节从正文中段（原 `README.md:216-227`）前移到首屏引言之后、`一源四态`之前（新 `README.md:20-32`），旧节删除，不留双真源。
2. **强调**：节标题 `## ⚠️ 环境要求（先看这一节：装错工具链会直接编不过）`，全文 `⚠` 仅此一处。
3. **地板**：`0.1.20260827` → `0.1.20261016`，写明 `is` 模式匹配表达式自 `d799f56` 起替代已移除的 `is_ok`/`is_err`；`README_EN.md` 徽章 / Requirements、`USAGE.md:35` 的同款旧地板同步改正，跟踪文档面 `grep 0.1.20260827` 归零。
4. **装环境坑**：同节补 Node ≥ 24 的 `node:sqlite` `returnArrays` 退化、Windows `node.cmd`/`.bat` 垫片吞参数引号（BUG-380）→ 指 `python scripts/moon_test_env.py --target js`。
5. **计数联动**：9 份声明文档 `1382` → `1387`（主提交 40 增 / 37 删）。`check_test_sync` 现读「136 份文档 / 23 条声明全部等于实测，must-carry 5 份齐全，豁免 22 条有效」；`check_badge` 徽章与自检注释双绿。
6. **清单面**：POLISH-04 改判 `已落地`；文首分布自述 `8/8/9/3` → `9/8/8/3`（尺实算）；POLISH-05 锚点随 README 前移重指（`:222-227` → `:27`/`:28`）。

## 二、证据

### 2.1 提交面（`86209cca`）

```
AGENTS.md 2/2, ARCHITECTURE.md 1/1, README.mbt.md 1/1, README.md 21/18,
README_EN.md 7/7, docs/2026-10-20-slave-tasks.md 4/4, docs/SOP.md 1/1,
docs/agent-map.md 1/1, docs/deliverable.md 1/1, scripts/scoring_rubric.md 1/1
```

追记提交（本报告 + 当日日志 + README_EN/USAGE 旧地板 + POLISH-04 证据措辞）单独一笔，不与主提交混面。

### 2.2 文档守卫读数

- `python scripts/check_test_sync.py <fresh log>` → `PASS 测试总数单一真源一致：实测 1387；扫描现状面 136 份文档，23 条声明全部等于实测；must-carry 5 份齐全；豁免 22 条全部有效`
- `python scripts/check_badge.py <fresh log> README.md` → `PASS 徽章一致：README tests-1387%2F1387 == 实测 1387/1387` + `PASS 自检注释一致：README 『→ Total tests: 1387, passed: 1387』 == 实测 1387`
- `python scripts/check_doc_surface.py` → rc=0（170 工具逐个可查、分组和=170、自述版本 0.3.10、J6–J15 全过）
- 电池内 `check_battery_count_doc.py` → `PASS rulers=88 ci=41 battery=50 missing=0 gate=58 exempt=27 unclassified=5`
- 电池内 `check_scripts_index.py` → PASS（所有正式脚本均已登记）

### 2.3 moon 门

- `moon check --target js`：`ran 31 tasks, now up to date (506 warnings, 0 errors)`
- `moon test --target js`（经 `scripts/moon_test_env.py`）：`Total tests: 1387, passed: 1387, failed: 0`
- `whisperer --fast`：`HEAD: dcefdeb | ✅ 三端一致`（feature 分支「篡改」误报未出现——当时 HEAD 仍等于主线 tip；其处方如出现也不执行）

### 2.4 全量电池

- 推前（工作树含本单改动）：**66 格 / 失败 0 / SKIP 5 / 缺执行面 0**
- 推后（`86209cca` 已推 + 追记工作树）：**66 格 / 失败 0 / SKIP 5 / 缺执行面 0**
- SKIP 5 全是缺前置：`temp/pt27.log` ×2（check_badge / check_test_sync 的带日志格）、`temp/chk47.json` ×3（deprecated 三格）——不构成「这格过了」的证据。

### 2.5 清单自证尺（R126 车道，仓外快照）

R126 的 `check_slave_task_list.py` 未合入主线；用 `git show slave/feat/check-slave-task-list-r126:scripts/check_slave_task_list.py` 的快照对 R180 工作树复跑：

- 判定面：任务行 28 / 证据锚点 57（其中内容级 21）/ 文件级在场 14
- 状态分布实算：`已落地 9 / 部分 8 / 未开工 8 / 作废 3` —— 与本单改后的文首自述一致（D3 归零）
- 剩 15 条违例：B3×9、B4×3、D1×2、D2×1，全部落在 R126 车道（它把文档锚点重指并改 header 口径）；POLISH-04 自身 B 检查不违例。

## 三、资源消耗

- 会话内全量电池 3 次（推前 / 推后 / 交付态）、`moon check` 1 次、`moon test` 1 次、`whisperer --fast` 1 次、R126 尺仓外复跑 2 次。
- 改动面：10 份文档（主提交）+ 3 份文档/报告/日志（追记）；**零 `.mbt` / `.mbti` 改动**，无需 `moon fmt`；`.mbti` 的 EOL 噪声按坑 3 还原，不进提交。

## 四、任务分配记录

文档面精修与全文档计数联动由指挥官亲做（子代理回传文本会再走一遍生成链路，而本单正是 README 与计数面）；终审为实测：五个文档守卫 + 全量电池 + `moon check`/`moon test` 逐条实跑。

## 五、遗留风险

1. **与 R126 的合并顺序**：两支都动 `docs/2026-10-20-slave-tasks.md`。R126 已把 header 改成 57/28/14、锚点重指；R180 改的是分布 9/8/8/3 与 POLISH-04/05 两行。建议先合 R126 再合 R180；冲突时 header 结构与内容两行取 R126、分布行取 R180，合完用 R126 尺复跑确认只剩本单已归零的 D3 不再红。
2. **92MB 当日日志**：`memory/2026-10-22.md` 在 HEAD 为 91,342,559 B / 528,301 行，`grep -c '^## R'` = 21,956——其中 18 个节标题各出现 1,155 次，另有 4 个 ×105、2 个 ×315、6 个 ×15。非本单引入，但会拖慢任何基于该文件的扫描/追加；建议独立立项（R128）做「按节头去重、保留每节最后一份、纯删举证」。
3. **英文 README 的位置不对齐**：`README_EN.md` 只修正了地板/徽章，Requirements 仍在正文中段；是否前移待 owner 裁决（避免双语结构各自演化）。
4. **新旧工具链的预期红**：把地板写成 0.1.20261016 后，用更旧 moon 的读者会在 `is` 表达式处红——这是正确行为（原地板 20260827 是错的），不是回归。
5. `memory/2026-10-23.md` 为本单新建；主机同日若也新建，合线按 add/add 并排处理。

## 六、后续建议

1. R128：当日日志去重（见风险 2），先做仓外快照 + 节头计数 + `git diff --numstat` 纯删证明，再动主线文件。
2. 合入顺序按风险 1 执行，合完跑 R126 尺与 `check_battery_count_doc` 复核。
3. 是否给 `README_EN` 也加同样的 ⚠️ 置顶节——等 owner 对双语结构给一句话再动。

## 七、超额内容

- `README_EN.md` 徽章 + Requirements、`USAGE.md:35` 的旧地板（原任务只点名中文 README）——不修则「换语言看 README 的 agent」仍会踩同一个坑。
- Node/Windows 两条装环境坑（原验收只要求 Node≥24 与版本号）。
- POLISH-05 锚点重指（不动则 R126 尺合入后当场 B3）。

## 八、来源

- 主提交 `86209cca`（父 `dcefdeb8`）；追记提交 `<commit2>`。
- 日志（仓外）：`C:\Users\Administrator\fist_r127_battery1.log` / `fist_r127_battery2.log` / `fist_r127_battery3.log`、`fist_r127_check.log`、`fist_r127_moontest2.log`、`fist_r127_whisperer.log`、`r127_ruler2.txt`、`r127_docsurf3.txt`。
- 尺快照：`C:\Users\Administrator\r126_ruler_snapshot.py`（源 `slave/feat/check-slave-task-list-r126:scripts/check_slave_task_list.py`）。
