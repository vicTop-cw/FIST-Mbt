# R121 · 守卫电池的逐格行不再把红格印成 OK —— 报告

- 轮次：R121（四模式流水线自我迭代 · 副机自驱单元）
- 分支：`slave/fix/guards-inline-verdict-r121`（基点 `gitcode/main` = `ccca1db6`，经 `7b1dba95` 建干后叠主线 5 个 commit）
- 交付物：`scripts/run_guards.py`（判定列 + 纯函数 + 3 格自检）、`scripts/README.md`（条目 R121 段 + `--selftest` 自述 34→37 格）、`docs/agent-map.md`（电池入口行改为「行首判定列 + 格数从汇总现读」）
- 模式：`fix_and_merge` 的只读面（本单不改 `.mbt`，不改协议/存储）

## 结果摘要

`run_guards.py` 逐格输出行的标签**只按记账口径取**：

```python
tag = {"gate": "OK", "diag": "诊断", "known-red": "预存红"}[c["kind"]]      # 主线 7b1dba95 :709
print("rc=%-2s exp=%-2s %-56s %s %s" % (rc, expect, name, tag, tail))      # 主线 7b1dba95 :710
```

`kind` 说的是「这格按哪条律记账」，`ok`（`rc == expect`）才是「这格过没过」。旧写法把前者当后者印：
一条 `rc=2 exp=0` 的**门禁**格照样印 `OK`，红只出现在末尾汇总。本单把它改成判定列在前：

```
PASS rc=0  exp=0  check_tools_sync.py            门禁 PASS 工具单一真源一致：…
FAIL rc=2  exp=0  check_battery_count_doc.py     门禁 FATAL: run_guards --list rc=1：…
```

顺带得到两个可直接用的机器入口：`grep ^FAIL` 只捞红格、`grep ^SKIP` 只捞跳过格（与已有的
`SKIP` / `TIMEOUT` 行首词形成同一列）。`--list` 面不动（见「边界」）。

## 证据

### A · 缺陷在场（真仓实测，非推演）

1. **活体读数**（`F:/AI/Fist-Mbt-wt-r115`，R120 分支，交单后电池，日志
   `C:/Users/Administrator/fist_r121_repro_on_r120.log:54`）——逐字：

   ```
   rc=2  exp=0  check_battery_count_doc.py             OK FATAL: run_guards --list rc=1：缺面清单：audit_branch_delete.py
   rc=2  exp=0  check_selftest_inventory_doc.py        OK FATAL: X4 自述失联 1 处（文档抄着数、实现给不出清单）：…
   ```

   同一轮汇总里它们是 `FAIL … got=2 expect=0`（该日志 `:67`、`:68`），**行内写着 OK、尾行写着 FATAL、
   汇总写着 FAIL**——三处对同一格给三种颜色，而人/AI 逐行读时先撞上第一处。

2. **它不是"没人会踩"的形状**：主线本体 `7b1dba95` 跑全量电池是 `59 格 / 失败 0 / SKIP 6 / 缺执行面 0`
   （`fist_r121_battery_before.log`）⇒ 平时看不出问题；只有**真出事那一轮**（预存红换因、合入把执行面拆掉、
   尺子自拒）才会出现 `rc≠exp` 的行——而那正是最需要这行说实话的时刻。本仓对这一类形状有名字：
   `run_guards.py` 自己 R106 段的「把『自动 0』印成一行看不出问题的数字，就是下一位读者以为这台机器退休了的开始」。

3. **消费者核查**（决定能不能改文法）：`grep -rn "rc=%-2s\|逐格打" scripts/*.py docs/*.md AGENTS.md`
   ⇒ 只有 `run_guards.py` 自己产生这行；读电池输出的机器只有 `check_battery_count_doc.py`，
   它抄的是 **`--list` 汇总行**文法（其 docstring 明写），逐格行无人解析。⇒ 改的是人读面，安全。

### B · 修复后的门禁读数

| 项 | 命令 | 读数 |
|---|---|---|
| 编译 | `python -m py_compile scripts/run_guards.py` | rc=0 |
| 自检 | `python scripts/run_guards.py --selftest` | rc=**0**，`SELFTEST OK（37 格…）`（原 34 + 判定列 3 格） |
| 新格 1 | `inline-verdict-red-never-printed-as-ok` | `case_line("gate", False, 1, 0, …)` 行首 `FAIL` 且整行不含 `OK` |
| 新格 2 | `inline-verdict-green-printed-as-pass` | `case_line("gate", True, 0, 0, …)` 行首 `PASS` |
| 新格 3 | `inline-known-red-still-labeled-by-kind` | `case_line("known-red", True, 1, 1, …)` 行首 `PASS` 且仍带 `预存红` |
| 变异核验 | `python ~/fist_r121_mutation.py`（四支装回坏形状） | M1 判定列恒印 `OK`（旧缺陷本体）⇒ rc=1 命中 1/1；M2 判定列挪出行首 ⇒ rc=1 命中 3/3；M3 口径列抹掉 ⇒ rc=1 命中 1/1；M4 判定列反了 ⇒ rc=1 命中 3/3；**还原后 sha256 与原始逐字相同 = True** |
| 台账对表 | `python scripts/check_battery_count_doc.py` | rc=0 `PASS 电池读数与 README 登记逐键一致：rulers=84 ci=40 battery=46 missing=0 …` |
| 自述清单 | `python scripts/check_selftest_inventory_doc.py` | rc=0 `INVENTORY_SYNC=clean 判定族 25 条逐一对表通过`（run_guards 不在其判定面：实现行没有「反解」锚点，口径③） |
| 文档面 | `python scripts/check_doc_surface.py --selftest` / 全量 | rc=0 / rc=0（170 工具、自述版本=0.3.10） |
| README 重复条目 | `python scripts/check_doc_dup.py` | rc=0（1138 行，无重复长条目） |
| 脚本索引 | `python scripts/check_scripts_index.py` | rc=0 |
| 编码面 | `python scripts/check_py_stdout_encoding.py --all` | rc=0（该带闸 40/40） |
| 退出码契约 | `python scripts/check_exit_code_contract.py` | rc=0 |
| 主干门 | `moon check --target js` | **0 errors**（`ran 146 tasks, 508 warnings, 0 errors`） |
| 主干测试 | `moon test --target js` | `Total tests: 1387, passed: 1387, failed: 0.`（本分支不改任何 `.mbt`，`git diff --name-only` 只有 3 份文档/脚本） |
| 主线叠加 | `git merge-tree` 预判 → `git merge gitcode/main`（5 commits） | 预判冲突标记 0 ⇒ 实际 merge rc=0；主线那 3 行改动在 `SPECIAL_CASES` 里（`:239`），与本单改动区（`:667-681`、`:709`、`:826+`）不相交 |
| 合入门 | `python scripts/whisperer.py --fast` | **rc=1 预存红（主线现状码）**：本分支基点未含 R120 的 whisperer 修法，主线 Step 0 把「本地 HEAD ≠ gitcode/main」判成篡改并处方 `git reset --hard ccca1db`——本单是 feature 分支，领先/落后是常态形状。逐字：`⚠️ 本地 HEAD 与远端 main 不一致（篡改） / → 跑 --scan-only 恢复，或手动 git reset --hard ccca1db`。不采纳（金条四），见 R120 报告与 MR |
| **全量电池（叠主线后、交单前）** | `python scripts/run_guards.py` | rc=1：**60 格 / 失败 1 / SKIP 5 / 缺执行面 0**。新格式自己抓到那一格红并逐字点名：`FAIL rc=1  exp=0  check_delivery_gap.py  门禁 … 会删掉尚未交付的通道分支`；同一条在旧格式下会印成 `rc=1 exp=0 check_delivery_gap.py OK`。**这一格是本分支自己的未推送状态**（单跑 `check_delivery_gap.py` 现读：`HEAD 30dde2d0 ahead=2 files=3 pushed=False ✗ 未交付`，base=`origin/master`），不是回归 |
| 徽章对表 | `python scripts/check_badge.py ~/fist_r121_test.log README.md` | rc=1 **预存红（主线本体）**：`README 徽章 1382/1382 ≠ 实际测试数 1387/1387` |
| 测试数声明 | `python scripts/check_test_sync.py ~/fist_r121_test.log` | rc=1 **预存红**：R2 缺 1387 声明三面（`docs/deliverable.md`、`docs/agent-map.md`、`scripts/scoring_rubric.md`）+ R3 防空转 |
| 预存红归属自证 | 在 `F:/AI/Fist-Mbt-wt-r115`（`docs/agent-map.md` 未被本单改动，`git diff --name-only HEAD` 为空）跑同一条尺 | 同样报 `R2 docs/agent-map.md 未出现实测总数 1387 的声明` ⇒ **agent-map 那条红不是本单改出来的**，是主线联动漏账 |

## 资源消耗

- 单轮副机会话：约 12 分钟工具时间；电池 3 次全量（前/后/终，每次约 90-120s）、`--selftest` 2 次、
  `moon check` + `moon test --target js` 各 1 次、变异 4 支（每支重跑自检）。
- 无新增依赖、无网络写动作（`git fetch` 只读 + 一次 `git push` 交单）。

## 任务分配记录

- **未派子代理**，理由（金条四）：本单是「读 500 行 Python 找一处输出语义缺陷 + 改 3 处 + 自证」，
  关键产物是我自己那一行读数的解释（为什么 `kind` 不能当 `ok` 用），拆开反而丢掉判据现场；
  变异与台账对表由我亲自跑，符合「代码任务终审必须实际运行验证」。
- FIST 面：本单挂在本机自驱流水线的 R121 单元，未发布 MCP 根任务（一次性轻-中任务，直接子代理粒度以下）。

## 遗留风险

1. **逐格行文法变了**：仓内无机器消费者（证据 A.3 实测），但**仓外**若有谁的手脚本按旧格式 `rc=… exp=…`
   取第一列，需要同步。缓解：新行把判定列放行首、`rc=` 仍在原位可 grep，且 `SKIP`/`TIMEOUT` 一直是行首词，
   列形状从此统一。
2. **`--selftest` 的覆盖面清单仍是手写散文**：`SELFTEST OK（37 格：…）` 里的清单不是从格子反解的。
   `check_selftest_inventory_doc.py` 的口径③只锁「实现自带反解锚点」的尺，run_guards 不在判定面 ⇒
   我这次同批改了文档，但**没有机器替下一位加格的人兜**。这是 R104 那条律在本仓的一处未覆盖面。
3. **`check_badge` / `check_test_sync` 在电池里恒 SKIP**（缺前置 `temp/pt27.log`）⇒ 主线这两把尺的红
   在电池读数里表现为「没跑」，只有人工点名才现形（本次就是人工点名）。R120 报告已提同一条，仍挂着。
4. **预存红四条不代修**（交付口径），已逐条给 rc：`check_badge` rc=1、`check_test_sync` rc=1、
   `whisperer --fast` rc=1（R120 MR 修）、`check_scripts_naming` rc=1（电池里期望就是 1，不进汇总）。
5. **`memory/whisperer-head.txt` 是被跟踪的运行时状态文件**：跑一次 `whisperer --fast` 就 dirty 一个跟踪件，
   与「本分支交付面只含本单改动」互相干扰（本单靠 `git checkout -f --` 还原）。根治要么把状态挪出跟踪面，
   要么在门后自动还原——属 R120 那条线的后续，不在本单动。
6. **R120 撞号再现**：主线已合入另一条 `slave/fix/backlog-control-char-r120`（`af021d63`），而我的
   `slave/fix/whisperer-head-state-r120` 仍在飞 ⇒ 现在仓库里 `R120` 指两件事。分支名可区分、报告可区分，
   但**轮次标签已不再唯一**；建议 owner 在合并顺序上定序（或在 `docs/` 建一份轮次台账）。

## 后续建议

1. 把 `SELFTEST OK（N 格：…）` 那句清单改成**从已执行格子名反解**（R104 现成写法），然后就能进
   `check_selftest_inventory_doc.py` 的判定面被机器钉住——这一格是 R104 律在本尺的自然延伸。
2. 电池给 `check_badge`/`check_test_sync` 自带前置：电池内跑一条 `moon test --target js -j 1` 落
   `temp/pt27.log`（或改成读现成产物），把这 2 个长期 SKIP 变成真覆盖。
3. 把 `whisperer-head.txt` 挪出跟踪面（或加 `--dry-state`），别让"跑门"污染交付面。
4. 轮次台账：`docs/rounds.md` 记 `R编号 ↔ 分支 ↔ 主线 commit`，撞号在起稿时就能查，不用靠事后改名。
5. 本仓所有「行内标签」类输出可复用这条律：**判定列必须来自判定本身，口径/分类只能做次级标签**。
   `run_guards` 之外，`fist-gate.py`、`gen_plugins --check` 的逐件回执值得同样扫一遍。

## 超额内容

- 顺带清掉 `docs/agent-map.md` 里写死的「35 格」陈旧自述（改为"格数从汇总现读"）——不在原计划，但同一行
  正是被我改动语义的那行，留着旧数就是留着下一个漂移点。
- 四支变异（不是两支）是为把「判定列必须放行首」这条也钉住而加的，超出「修一处标签」的最小面。

## 来源

- 缺陷发现：R120 交单后电池读数（`fist_r121_repro_on_r120.log`）——为了写 R120 报告而跑电池，
  顺带看见 `rc=2 exp=0 … OK` 这一行自相矛盾。
- 同族律：`scripts/run_guards.py` R106 段（「一行看不出问题」）、R104/R105 X5（空产物反证）、
  `AGENTS.md` 守卫族段的「红着没人读等于没锁」。
- 主线现状：`gitcode/main` = `ccca1db6`（含 R118/R119/R120 三条并线）；测试总数 1387 来自
  `C:/Users/Administrator/fist_r121_test.log`。
