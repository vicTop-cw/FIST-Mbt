# 2026-10-14 · 模板「无裸控制字符」守卫（Round 103）

## 结果摘要

**一句话**：落地上一轮报告的建议 #1 —— 给 `templates/*.md` 加「无裸控制字符」判据
`scripts/check_template_ctrl.py`，**已 --selftest 5 格全过**，并**普查出 9 份模板含 353 处裸控制字符**。
判据**只点名不自动修**（修复需判断原意，属作者/owner 的职权），故本轮把 353 处缺陷**如实暴露**，
**修留给 owner 决定**（不越权改提示词文件）。

**普查核心发现（本轮最重要的事实）**：
- `pipeline_mode_{advance,polish,verify,bugfind,fix_and_merge,tidy,explore}.md` ×7：**字母被吃**
  （`\t`→TAB 吃 `t`、`\r`→CR 吃 `r`、`\b`→BS 吃 `b`、`\e`→ESC 吃 `e`、`\v`→VT 吃 `v`）
  ⇒ `task_plan_deep`→`ask_plan_deep`、`reject`→`eject`、`run_check`→`un_check`、`execute`→`xecute`、`verify`→`erify`、`bug_list`→`ug_list`
- `pipeline_meta_prompt.md`：**CR 填充**（`\r\r\r\r\n` 当空行用，159 处），属美容性
- `tool_use_rubric.md`：CR 53 处

**为什么这是实质缺陷**：模板是**发给 agent 的提示词**。工具名错一个字母（`un_check` 而不是 `run_check`），
执行者就**调不到工具**（工具名敏感，调错名=空回）。这正是「文档即实现」面的实质缺陷，不是排版难看。

## 判据 `scripts/check_template_ctrl.py`

- **T1** `templates/**/*.md` 字节里不得含裸控制字符（白名单只放 `\n` 换行与 `\t` 制表符；
  `\r`/`\b`/`\v`/`\f`/`\e` 及其它 C0 全判红）
- **T2** 一份 .md 都枚举不到 ⇒ FATAL（判据空转≠没问题）
- **只点名不自动修**：给出上下文（前后 24 字节 + 被吃掉字母的推测），决定权留给作者/owner
- `--selftest` **5 格**：干净不误红 / CR 必红 / ESC+VT 必红 / TAB 放行 / 枚举非空 —— **全过**
- `--list` 列出各模板的控制字符构成

**L4 实测**：
```
--selftest : SELFTEST OK（5 格）rc=0
全量       : FAIL 模板含裸控制字符（9 份 / 353 处）rc=1   ← 判据在真缺陷上如实发红
--list     : pipeline_meta_prompt(CR 159) / pipeline_mode_advance(ESC 6,VT 1,CR 12,BS 3) / …
```

## 为什么不自动修（越权风险）

修复需要判断"该控制字符原本该是哪个字母"。虽然多数可查真源（`ask_plan_deep`→`task_plan_deep`），
但：
1. **`pipeline_meta_prompt.md` 的 159 个 CR 是填充不是字母被吃**，性质不同，需单独处理
2. **`\t` 在 `task_plan_deep` 里是"吃 t"、在表格里是"合法缩进"**，一刀切会误伤
3. 这些是**发给 agent 的提示词**，改错一个工具名 = 影响所有执行者

判据的价值是**把缺陷变成可查的红**（而不是"看起来正常"），修不修由作者/owner 定。

## 提交

- 新增 `scripts/check_template_ctrl.py`（判据，~200 行）
- 登记 `scripts/README.md`（守卫族条目）
- **未动**任何 `templates/*.md`（留给 owner）；**未动** `.mbt` / `ci.yml`（并发面）
- **未挂 CI**：该判据当前对现状模板必红，挂了会破坏构建。
  待 owner 修完模板后（或明确接受当前红态）再接入。

## L4

| 判据 | 结果 |
|---|---|
| `check_template_ctrl --selftest` | SELFTEST OK（5 格）rc=0 |
| `check_template_ctrl` 全量 | FAIL（9 份 / 353 处）rc=1 ← 如实发红 |
| `check_scripts_index` | PASS（新脚本已登记） |
| `check_doc_surface` | PASS（166 工具 / J1-J16） |
| `check_plugin_sync` | PASS（4 宿主 / 166 / v0.3.8） |
| `check_tools_sync` | PASS |

## 资源消耗

- 普查：1 次（11 份模板扫描，9 份命中）
- 上下文 dump：1 次（353 处，看清两类缺陷性质）
- 判据：实现 + selftest（5 格）+ 全量 + list 各 1 次
- 零 `.mbt`、零 `ci.yml` 改动

## 任务分配记录

- 指挥官亲自：普查 → 看清两类缺陷 → 实现判据 → selftest 5 格 → 全量如实发红 →
  **判定不自动修**（改提示词文件需作者意图知识，越权风险高）→ 登记 → 不挂 CI。
- **未派子代理**：这是"暴露缺陷 vs 越权修复"的判断，误判会导致要么掩盖缺陷要么破坏提示词。
- 边界：只新增 1 支判据 + 1 条 README 登记；**未替作者修模板**（判据价值=点名）。

## 遗留风险

1. **9 份模板仍含 353 处裸控制字符**（未修）：其中 7 份 pipeline_mode_* 的**工具名错字母**是实质缺陷
   （`un_check`→应 `run_check` 等），会让执行者调不到工具。**判据已能点名**，但**修不修待 owner 裁决**。
2. **判据未挂 CI**：当前对现状必红。若 owner 长期不修，判据永远红 → 需 owner 明确接受"红态=已知缺陷"，
   或在修完后接入 CI。
3. **同类面**：只扫了 `templates/`。`plugins/source/` 的模板源、`docs/` 里含转义的示例是否也有同类？
   **建议**后续扩面。

## 后续建议

1. **owner 裁决 353 处是否修**：若修，可按真源工具名做权威锚定（`ask_plan_deep`→`task_plan_deep`
   因 `task_plan_deep` 是注册工具、`ask_plan_deep` 不是 —— 可机械验证）；`pipeline_meta_prompt.md`
   的 159 个 CR 是填充需单独处理（`\r\r\r\r\n`→`\n`）。
2. **修完后再把本判据接入 CI**：现在接入会破坏构建，修完接上才闭环。
3. **扩面到 `plugins/source/`**：那是插件态模板的真源，可能同源被解释。
4. **写操作纪律**：本轮再次印证"用 Python 文本模式读写他人文件会静默改字节形态"——
   建议写入 `AGENTS.md`（改他人文件先取原始字节 + 二进制写回 + diff 核对行数）。

## 超额内容

- 顺带**把普查从"猜"升级到"看清两类缺陷"**：区分了"字母被吃"（致命）与"CR 填充"（美容），
  避免后续误判一刀切。
- 顺带**抵住"顺手全修"的诱惑**（第二次）：上一轮修 tidy 回退过，本轮面对 353 处仍没越权——
  提示词文件改错工具名影响所有执行者，风险远大于"看起来干净"。
- 顺带**实证 `check_scripts_index` 正常工作**：新脚本未登记时它正确报红，登记后转 PASS。

## 来源

- 判据实现：`scripts/check_template_ctrl.py`（T1/T2 + `--selftest` 5 格 + `--list`）
- 普查脚本：`temp/dump_ctrl.py`（353 处上下文，区分两类缺陷）
- 读数：`--selftest` SELFTEST OK；全量 FAIL（9 份/353 处）；`check_scripts_index` PASS；
  `check_doc_surface` PASS；`check_plugin_sync` PASS；`check_tools_sync` PASS
- 登记：`scripts/README.md`（守卫族条目，插在 `check_store_tables_wired` 前）
