# R113 · plan_deep 标注逐层叠乘 + 校准静默失效 修复报告

日期：2026-10-22 · 副机（slave）· 分支 `slave/fix/plan-deep-annotation-compound-r113` · 基点 `0338a6b8`（gitcode/master 当时 tip）

## 结果摘要

用产品自身（`scripts/fist.py` → MCP `task_plan_deep`，所有可选开关全开）跑自我迭代，实测出三件同源的缺陷，
全部落在 `src/engine/engine.mbt` 的 `decompose_rec` 一处递归写描述的路径上，本单一并修掉：

| 编号 | 缺陷形状（实测） | 根因（一行） | 修法 |
|---|---|---|---|
| F1 | 引擎自加的标注按层叠乘：9 字根任务 → 最深叶 3109 字节，`[难度梯度` 出现 4 次、`[父计划:` 4 次、`[边界四问` 4 次、`[omega:required]` 2 次 | `default_slices(child.split_n, parent_desc=child.description)` 把**已标注**的文本当下一层切割底稿；`更简单变体` 引文与 `父计划` 字段又各自再嵌一次 | 新增 `strip_plan_annotations()`（`src/engine/omega_strong.mbt`，与既有 `omega_clean_slice` 同族的清洗件），在切割底稿、`父计划` 引文、下钻 `parent_desc` 三处先洗再拼 |
| F2 | `calibrate` 静默失效：调用方按切片给 `[4,3,1]`，一旦同时开 `boundary_probe=true`，所有档全回落位置档，回执无任何提示 | 引擎追加的「边界审视叶」先撑大 `slices.length()`，长度门 `arr.length() == n_slices` 因此恒不成立 | 记下业务片数 `biz_slices`，校准长度对准它（并保留 `n_slices` 匹配作兼容），元叶不参与校准 |
| F3 | 同一条叶里并存两个互相矛盾的梯度档（`1/4:易` 与 `1/3:难 d=4`） | 是 F1 的现形：上一层的档被原文嵌进本层的引文 | 随 F1 消失（每条叶恰好一个档） |

改动面（只动 4 个文件）：`src/engine/engine.mbt`、`src/engine/omega_strong.mbt`、`src/engine/decompose_test.mbt`、
`src/engine/pkg.generated.mbti`（`moon info` 投影）；另把测试总数现状面 36 处 1379→1382 同步。

## 证据

### A/B 同尺实测（同一脚本、同一参数、同一 split_n=2，只有代码不同）

`split_n=2 + gradient + calibrate=[4,3,1] + reinject_context + boundary_probe + omega_strong_verify`，
根任务描述 9 字（17 字节），量具 `C:/Users/Administrator/AppData/Local/Temp/r113_measure.py`（走真产物 `_build/js/.../cli.js`，
DB 改道 temp，13 个任务全量逐条数标记）：

| 节点 | 修前 | 修后 |
|---|---|---|
| `T0.1.1` | 757 字 / **1705 B**，`[难度梯度`=4 `[父计划:`=4 `[边界四问`=4 `[omega:required]`=2 | 234 字 / **507 B**，四项全部 =1 |
| `T0.1.3`（元叶下钻） | 579 字 / 1345 B，`[难度梯度`=2 | 394 字 / 935 B，`[难度梯度`=1 |
| `T0.3.1`（最深叶） | 1297 字 / **3109 B**，`[难度梯度`=4 | 558 字 / **1350 B**，`[难度梯度`=1 |
| 全树最大叶 | **3109 B** | **1350 B**（−57%，且不再随层数倍增） |

修前读数取证于「把 4 个文件还原到基点版本 → 重新 `moon build --target js cmd/cli` → 同脚本重跑」，
读数行逐条留在本报告；修后读数是恢复改动后重跑的同一条命令。

### 回归与门禁读数

- `moon test --target js src/engine` = **193/193**（新增 3 条测试全绿）。
- `moon test --target js`（全量）= **Total tests: 1382, passed: 1382, failed: 0**，日志无 `SIGABRT`/`core dumped`/`signal:`。
- `moon build --target js cmd/cli` = **149 warnings, 0 errors**；逐行核对新增代码行号（`engine.mbt` 我的 4 处、
  `omega_strong.mbt` 新增两件、`decompose_test.mbt` 545 行之后）**零命中警告** ⇒ 本单不带新 WARNING/ERROR。
- `moon info --target js` rc=0；`check_mbti_sync.py` rc=0（24 份 .mbti / 677 条 pub 声明对表通过）。
- `check_test_sync.py <全量日志>` rc=0：实测 1382，扫 136 份现状面文档、19 条声明全等实测、must-carry 5 份齐全。
- `check_badge.py <全量日志> README.md` rc=0：徽章 `tests-1382%2F1382` 与 README 注释行一致。
- `scripts/run_guards.py` 电池（`FIST_DB_PATH` 改道 temp）：**rc=0 / 57 格 / 失败 0 / SKIP 6 / 缺执行面 0**；
  SKIP 六格都是「缺前置进料文件」的既有形状（`temp/pt27.log`×2、`temp/chk47.json`×3、`fist-mbt.db`×1），
  本单已用 temp 全量日志把其中 `check_test_sync` / `check_badge` 两格单独跑绿（读数见上）。

### 新增白盒锁（`src/engine/decompose_test.mbt`）

1. 开关全开：每条叶 `[难度梯度 `/`更简单变体：先把「`/`[父计划:`/`[omega:required]`/spec 指纹 **各恰好 1 次**，
   `[边界四问` ≤1 次（叠乘在文本面上的形状就是同一标记出现多次——这条断言在修前的代码上直接红：实测 4/4/4/2）。
2. `boundary_probe=true` 时 `calibrate=[4,3,1]` 仍按业务片生效：`[难度梯度 1/4:难 d=4]`/`2/4:中 d=3`/`3/4:易 d=1`，
   第 4 片是引擎追加的 `[边界审视` 元叶（修前这三条全回落位置档）。
3. 默认关闭开关时下钻底稿不重复挂 spec 指纹（F1 的默认路径同形面：修前 2 层叶带两枚 `[spec:`）。

## 任务分配记录（金条四/八）

- 本单是「副机用自身能力自驱」的产物：缺陷由产品调用面（`task_plan_deep` 开关全开）发现，修由我在独立
  worktree `F:/AI/Fist-Mbt-wt-r113` 完成（主 worktree 当时在同机并行 agent 的 `…r112` 分支上，TASK-017 处于 `in_review`，
  不与之抢面），终审按金条八实跑 `moon test` + 电池，不据自述。
- 主机任务池（`docs/tasks/backlog/`）本单未认领任何一项：P0 TASK-001 内容面已在 R110 收口（抬头盖章归 owner），
  P1/P2/P3 十余项仍在池内；`TASK-017` 属同机另一 agent，我不碰。
- 未做（不在本单面内，留待后续单）：D1 参数类型报错文案不点名允许类型（`-32602 … none of the permitted types`），
  D2 读类工具默认 ns 造成的 `task not found: T0` 不回显搜索面。

## 资源消耗

- 工具链：`moon test`（包级 1 次 + 全量 1 次）、`moon build cmd/cli` 3 次（修前/修后 A/B 各一次 + 恢复一次）、
  `moon info` 1 次、电池全量 1 次（57 格）。
- 会话轮次：本单约 20 次工具往返；墙钟约 11 分钟。
- 未起常驻服务、未发网络请求；所有 DB 落 `C:/Users/Administrator/AppData/Local/Temp/`，仓库根 `fist-mbt.db` 零污染
  （`check_battery_isolation.py` rc=0：跟踪面/未跟踪面快照前后 13/0 项不变）。

## 遗留风险

1. **`moon fmt` 本机 rc=127（工具链 ICE，非本单引入）**：全仓/单文件/`--check` 三种跑法同红，报错形如
   `Could not access '\\?\..._build\wasm-gc\release\format\...'`。本单按 AGENTS「以本地 moon fmt 落盘为准」无法满足，
   改为逐文件对照既有风格手写格式化（新代码全部 `///|` 分块、80 列内、match/`=>` 换行照旧），落盘后 `moon check` 干净。
   CI 的 fmt 门目前带 `continue-on-error`，与本单无关。
2. **测试总数 1382 的并发撞面**：同机另一 agent 若也新增测试并同步现状面，合并时 19 条声明行会撞（append-only 文档可
   union，声明行取实测更大值后重跑 `check_test_sync` 即可自解）。
3. **账本未挂号**：本单三条缺陷（F1/F2/F3）尚未写进 `memory/bugs.md` 编号条目——挂号会牵动 `gen_plugins` 四宿主投影与
   `check_plugin_sync`，我按「一单一面」留作下一单，不在这里做半截投影。
4. **F2 的「静默」只修了失效、没修回执**：现在长度对得上就生效，对不上仍回退位置档且不在返回 JSON 里点名。
   彻底做法是加 `calibrate_note` 返回字段，但那会改 `task_plan_deep` 的返回形状（`J9` 描述契约门要同批改 server.mbt 描述），
   本单没顺手做。

## 叠主线后权威读数（交单前，现读远端 tip）

叠 `gitcode/master`（本单基点之后先进 14 commit，含 `803293c2` 一系）后重测，交单的读数以这一节为准：

- **冲突面**：唯一冲突 `memory/2026-10-22.md` 尾部追加。并集解（主线 3642 行在前、本单 R113 节 23 行在后），
  落盘实测 `CR=0`、冲突标记 0 处、`## R113` 标题恰 1 次。其余 14 个文件三方无重叠。
- **MR 面 diff**（`gitcode/master` → 分支 tip）：15 files / +306 / −25，其中当日日志只 +24 行。
- **全量测试**：`moon test --target js` → `Total tests: 1382, passed: 1382, failed: 0`。主线这 14 commit
  未增测试，本单的 1379→1382 文档面同步在合并树上仍然成立（不用二次改）。电池里这两格因缺前置 `temp/pt27.log`
  而 SKIP，故用合并树日志单独重跑：`check_test_sync` rc=0（实测 1382，136 份现状面 19 条声明全等、must-carry 5 份齐全、
  豁免 22 条有效）、`check_badge` rc=0（`tests-1382%2F1382` 与自检注释一致）。
- **电池**：`run_guards.py` 58 格 / 失败 2 / SKIP 5 / 缺执行面 0。两格失败都不属本单，逐条给因：
  1. `check_delivery_gap.py` `got=1 expect=0` —— HEAD 未推的交付态红，推后自翻（本仓既有口径：推前不登记期望，
     交单读数只认推后那一发）。
  2. `check_backlog_status_staleness.py` `got=0 expect=1` —— **预存红**：`gitcode/master` 的 `run_guards.py:228`
     与本分支同一行一字不差，即红在主线就在主线。成因是「被检面被别人修好 ⇒ 登记的必红期望反现形」：
     主线把任务池那 9 条状态落差关掉后，实测现读 `扫描面=gitcode/main | backlog 23 份 | 落差 0 条 / 上限 0 条`、
     `rc=0`。本单不代修（把期望改绿要连「期望依据」一起改，归任务池 owner 那一单）。
- **警告面**：合并树构建日志 722 处 `Warning` 里，点名 `src/engine/engine.mbt` / `omega_strong.mbt` /
  `decompose_test.mbt` 的 **0 处**（grep 三个文件名零命中）——本单新增行不引入新警告。

### 交单前自检抓到自己两格（如实记账）

1. **整文件行尾翻脏**：首发提交把 `memory/2026-10-22.md` 写成 CRLF，而仓库 blob 与主线都是纯 LF
   （`.gitattributes` 只给 `*.sh` / `*.mjs` / `templates/*.md` / `.githooks/*` 钉 `eol=lf`，`*.md` 不在清单里）。
   后果不是难看而是**冲突面**：合并时 5022 行每一行都是冲突。已还原 LF，MR 面回到「只追加一节」。
2. **转义吃掉字母**：正文那条 moon fmt 的 ICE 路径 `` `\\?\..._build\wasm-gc\release\format` `` 在写入时
   `\r` 吞掉 `r`、`\f` 吞掉 `f`，落成裸 CR(0x0D) + 裸 FF(0x0C) 两个控制字符。这正是 `.gitattributes` 注释里
   记录过的 templates/*.md 353 处裸 CR 同形坑，只是这次发生在日志面、`eol=lf` 钉不住它。
   报告文件实测本就 `CR=0 / FF=0`，未受影响；日志按字面还原后全文件控制字符归零。

## 建议入档位置

- `memory/2026-10-22.md`：本单条目（已写）。
- `memory/bugs.md`：下一单给 F1/F2/F3 挂编号 + `### FIXED` 同批跑 `gen_plugins.py` 与 cl7。
- 原则类沉淀（`evolve_distill`）：**「引擎自己加到产物上的标注，必须在被再次当作输入前洗掉」**——
  `omega_clean_slice` 早就为强验证标记立了这条，但另外四件标注漏了同一条纪律；一条纪律只在一个标记上兑现，等于没立。

## 来源

- 真源：`src/engine/engine.mbt`（`plan_deep` 入口 + `decompose_rec`）、`src/engine/omega_strong.mbt`
  （`strip_plan_annotations` / `cut_before`）、`src/decompose/decompose.mbt`（`default_slices` 底稿形状，未改）。
- 量具与日志：`C:/Users/Administrator/AppData/Local/Temp/r113_measure.py`、`r113_full.log`、`r113_engine.log`、
  `r113_guards.log`、`r113_build_before.log`、`r113_build_after.log`、`r113_fmt.log`。
- 上游发现面：本会话前段的开关矩阵复测（`[all] 1996B` 那次是另一组 split_n=2 参数，本报告以同尺 A/B 重测数为准）。
- 规范依据：`AI-DEVELOPMENT-STANDARD.md` 通用 5 条（增量零回归、证据梯 ≥L4）+ FIST 专项「用自身能力迭代」。
